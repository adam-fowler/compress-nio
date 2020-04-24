
import CNIOCompressZlib
import NIO

/// Compressor using Zlib
class ZlibCompressor: NIOCompressor {
    let windowBits: Int
    var isActive: Bool
    var stream = z_stream()
    var lastError: Error?

    init(windowBits: Int) {
        self.windowBits = windowBits
        self.isActive = false
        self.lastError = nil
    }

    deinit {
        if isActive {
            try? finishStream()
        }
    }

    func startStream() throws {
        assert(!isActive)
        
        // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let rt = CNIOCompressZlib_deflateInit2(&self.stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, Int32(windowBits), 8, Z_DEFAULT_STRATEGY)
        switch rt {
        case Z_MEM_ERROR:
            throw NIOCompressError.noMoreMemory
        case Z_OK:
            break
        default:
            throw NIOCompressError.internalError
        }
        isActive = true
    }
    
    func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, finalise: Bool) throws {
        assert(isActive)
        var bytesRead = 0
        var bytesWritten = 0
        
        defer {
            to.moveWriterIndex(forwardBy: bytesWritten)
        }

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let flag = finalise ? Z_FINISH : Z_SYNC_FLUSH
            
            if lastError == nil {
                self.stream.avail_in = UInt32(fromBuffer.count)
            }
            self.stream.next_in = CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            self.stream.avail_out = UInt32(toBuffer.count)
            self.stream.next_out = CNIOCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            
            let rt = CNIOCompressZlib.deflate(&self.stream, flag)
            bytesRead = self.stream.next_in - CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            bytesWritten = self.stream.next_out - CNIOCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            do {
                switch rt {
                case Z_OK:
                    if finalise == true {
                        throw NIOCompressError.bufferOverflow
                    } else if self.stream.avail_out == 0 {
                        throw NIOCompressError.bufferOverflow
                    }
                case Z_DATA_ERROR:
                    throw NIOCompressError.corruptData
                case Z_BUF_ERROR:
                    throw NIOCompressError.bufferOverflow
                case Z_MEM_ERROR:
                    throw NIOCompressError.noMoreMemory
                case Z_STREAM_END:
                    break
                default:
                    throw NIOCompressError.internalError
                }
            } catch {
                lastError = error
                throw error
            }
        }
        from.moveReaderIndex(forwardBy: bytesRead)
    }
    
    func finishStream() throws {
        assert(isActive)
        isActive = false
        let rt = deflateEnd(&self.stream)
        switch rt {
        case Z_OK:
            break
        default:
            throw NIOCompressError.internalError
        }
    }
    
    func deflateBound(from: ByteBuffer) -> Int {
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
        // As we use avail_out == 0 as an indicator of whether the deflate was complete. I also add an extra byte to ensure we
        // always have at least one byte left in the compressed buffer after the deflate has completed.
        let bufferSize = Int(CNIOCompressZlib.deflateBound(&stream, UInt(from.readableBytes)))
        return bufferSize + 6
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
    }

    deinit {
        if isActive {
            try? finishStream()
        }
    }

    func startStream() throws {
        assert(!isActive)

        // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
        self.stream.zalloc = nil
        self.stream.zfree = nil
        self.stream.opaque = nil

        let rt = CNIOCompressZlib_inflateInit2(&self.stream, Int32(windowBits))
        switch rt {
        case Z_MEM_ERROR:
            throw NIOCompressError.noMoreMemory
        case Z_OK:
            break
        default:
            throw NIOCompressError.internalError
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
            self.stream.avail_in = UInt32(fromBuffer.count)
            self.stream.next_in = CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            self.stream.avail_out = UInt32(toBuffer.count)
            self.stream.next_out = CNIOCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            let rt = CNIOCompressZlib.inflate(&self.stream, Z_NO_FLUSH)

            bytesRead = self.stream.next_in - CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            bytesWritten = self.stream.next_out - CNIOCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            switch rt {
            case Z_OK:
                if self.stream.avail_out == 0 {
                    throw NIOCompressError.bufferOverflow
                }
            case Z_BUF_ERROR:
                throw NIOCompressError.bufferOverflow
            case Z_DATA_ERROR:
                throw NIOCompressError.corruptData
            case Z_MEM_ERROR:
                throw NIOCompressError.noMoreMemory
            case Z_STREAM_END:
                break
            default:
                throw NIOCompressError.internalError
            }
        }
    }
    
    func finishStream() throws {
        assert(isActive)
        isActive = false
        let rt = inflateEnd(&self.stream)
        switch rt {
        case Z_DATA_ERROR:
            throw NIOCompressError.unfinished
        case Z_OK:
            break
        default:
            throw NIOCompressError.internalError
        }
    }
}
