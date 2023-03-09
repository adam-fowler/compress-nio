
import CCompressZlib
import NIOCore

/// Compressor using Zlib
final class ZlibCompressor: NIOCompressor {
    let windowBits: Int
    var stream: z_stream
    var isActive: Bool

    init(windowBits: Int) {
        self.windowBits = windowBits
        self.isActive = false
        self.window = nil
        
        self.stream = z_stream()
        self.stream.zalloc = nil
        self.stream.zfree = nil
        self.stream.opaque = nil

    }

    deinit {
        if isActive {
            try? finishStream()
        }
    }

    var window: ByteBuffer?

    func startStream() throws {
        assert(!isActive)

        // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let rt = CCompressZlib_deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, Int32(windowBits), 8, Z_DEFAULT_STRATEGY)
        switch rt {
        case Z_MEM_ERROR:
            throw CompressNIOError.noMoreMemory
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
        isActive = true
    }

    func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, flush: CompressNIOFlush) throws {
        assert(isActive)
        var bytesRead = 0
        var bytesWritten = 0

        defer {
            to.moveWriterIndex(forwardBy: bytesWritten)
            from.moveReaderIndex(forwardBy: bytesRead)
        }

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let flag: Int32
            switch flush {
            case .no:
                flag = Z_NO_FLUSH
            case .sync:
                flag = Z_SYNC_FLUSH
            case .finish:
                flag = Z_FINISH
            }

            stream.avail_in = UInt32(fromBuffer.count)
            stream.next_in = CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            stream.avail_out = UInt32(toBuffer.count)
            stream.next_out = CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            let rt = CCompressZlib.deflate(&stream, flag)
            bytesRead = stream.next_in - CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            bytesWritten = stream.next_out - CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            switch rt {
            case Z_OK:
                if flush == .finish {
                    throw CompressNIOError.bufferOverflow
                }
            case Z_DATA_ERROR:
                throw CompressNIOError.corruptData
            case Z_BUF_ERROR:
                throw CompressNIOError.bufferOverflow
            case Z_MEM_ERROR:
                throw CompressNIOError.noMoreMemory
            case Z_STREAM_END:
                break
            default:
                throw CompressNIOError.internalError
            }
        }
    }

    func finishDeflate(to: inout ByteBuffer) throws {
        assert(isActive)
        var bytesWritten = 0

        defer {
            to.moveWriterIndex(forwardBy: bytesWritten)
        }

        try to.withUnsafeMutableWritableBytes { toBuffer in
            stream.avail_in = 0
            stream.next_in = nil
            stream.avail_out = UInt32(toBuffer.count)
            stream.next_out = CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            let rt = CCompressZlib.deflate(&stream, Z_FINISH)
            bytesWritten = stream.next_out - CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            switch rt {
            case Z_OK:
                throw CompressNIOError.bufferOverflow
            case Z_DATA_ERROR:
                throw CompressNIOError.corruptData
            case Z_BUF_ERROR:
                throw CompressNIOError.bufferOverflow
            case Z_MEM_ERROR:
                throw CompressNIOError.noMoreMemory
            case Z_STREAM_END:
                break
            default:
                throw CompressNIOError.internalError
            }
        }
    }

    func finishStream() throws {
        assert(isActive)
        self.isActive = false
        self.window?.moveReaderIndex(to: 0)
        self.window?.moveWriterIndex(to: 0)

        let rt = deflateEnd(&stream)
        switch rt {
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }

    func maxSize(from: ByteBuffer) -> Int {
        // deflateBound() provides an upper limit on the number of bytes the input can
        // compress to. We add 5 bytes to handle the fact that Z_SYNC_FLUSH will append
        // an empty stored block that is 5 bytes long.
        // From zlib docs (https://www.zlib.net/manual.html)
        // "If the parameter flush is set to Z_SYNC_FLUSH, all pending output is flushed to the output buffer and the output is
        // aligned on a byte boundary, so that the decompressor can get all input data available so far. (In particular avail_in
        // is zero after the call if enough output space has been provided before the call.) Flushing may degrade compression for
        // some compression algorithms and so it should be used only when necessary. This completes the current deflate block and
        // follows it with an empty stored block that is three bits plus filler bits to the next byte, followed by four bytes
        // (00 00 ff ff)."
        let bufferSize = Int(CCompressZlib.deflateBound(&stream, UInt(from.readableBytes)))
        return bufferSize + 6
    }
    
    func resetStream() throws {
        assert(isActive)
        // deflateReset is a more optimal than calling finish and then start
        let rt = deflateReset(&stream)
        switch rt {
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }
}

/// Decompressor using Zlib
class ZlibDecompressor: NIODecompressor {
    let windowBits: Int
    var isActive: Bool
    var stream = z_stream()

    init(windowBits: Int) {
        self.windowBits = windowBits
        self.isActive = false
        self.window = nil
    }

    deinit {
        if isActive {
            try? finishStream()
        }
    }

    var window: ByteBuffer?

    func startStream() throws {
        assert(!isActive)

        // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil
        stream.avail_in = 0;
        stream.next_in = nil;

        let rt = CCompressZlib_inflateInit2(&stream, Int32(windowBits))
        switch rt {
        case Z_MEM_ERROR:
            throw CompressNIOError.noMoreMemory
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
        isActive = true
    }

    func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        assert(isActive)
        var bytesRead = 0
        var bytesWritten = 0

        defer {
            from.moveReaderIndex(forwardBy: bytesRead)
            to.moveWriterIndex(forwardBy: bytesWritten)
        }

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            stream.avail_in = UInt32(fromBuffer.count)
            stream.next_in = CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            stream.avail_out = UInt32(toBuffer.count)
            stream.next_out = CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            let rt = CCompressZlib.inflate(&stream, Z_NO_FLUSH)

            bytesRead = stream.next_in - CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            bytesWritten = stream.next_out - CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            switch rt {
            case Z_OK:
                if stream.avail_out == 0 {
                    throw CompressNIOError.bufferOverflow
                }
            case Z_BUF_ERROR:
                throw CompressNIOError.bufferOverflow
            case Z_DATA_ERROR:
                throw CompressNIOError.corruptData
            case Z_MEM_ERROR:
                throw CompressNIOError.noMoreMemory
            case Z_STREAM_END:
                break
            default:
                throw CompressNIOError.internalError
            }
        }
    }

    func finishStream() throws {
        assert(isActive)
        isActive = false
        let rt = inflateEnd(&stream)
        switch rt {
        case Z_DATA_ERROR:
            throw CompressNIOError.unfinished
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }
    
    func resetStream() throws {
        assert(isActive)
        // inflateReset is a more optimal than calling finish and then start
        let rt = inflateReset(&stream)
        switch rt {
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }
}
