
import CNIOCompressZlib
import NIO

struct ZlibCompressor: NIOCompressor {
    let windowBits: Int
    var isActive: Bool
    var stream = z_stream()
    var nextInBufferOffset: Int
    var lastError: Error?

    init(windowBits: Int) {
        self.windowBits = windowBits
        self.isActive = false
        self.nextInBufferOffset = 0
        self.lastError = nil
    }

    mutating func startStream() {
        assert(!isActive)
        isActive = true
        
        // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let rc = CNIOCompressZlib_deflateInit2(&self.stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, Int32(windowBits), 8, Z_DEFAULT_STRATEGY)
        precondition(rc == Z_OK, "Unexpected return from zlib init: \(rc)")
    }
    
    mutating func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, finalise: Bool) throws {
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
                self.stream.next_in = CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            } else {
                self.stream.next_in = CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!) + nextInBufferOffset
            }
            self.stream.next_in = CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            self.stream.avail_out = UInt32(toBuffer.count)
            self.stream.next_out = CNIOCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            
            let rt = CNIOCompressZlib.deflate(&self.stream, flag)
            bytesRead = fromBuffer.count - Int(self.stream.avail_in)
            bytesWritten = toBuffer.count - Int(self.stream.avail_out)
            do {
                switch rt {
                case Z_OK:
                    if finalise == true {
                        throw NIOCompression.Error.bufferOverflow
                    } else if self.stream.avail_out == 0 {
                        throw NIOCompression.Error.bufferOverflow
                    }
                case Z_DATA_ERROR:
                    throw NIOCompression.Error.corruptData
                case Z_BUF_ERROR:
                    throw NIOCompression.Error.bufferOverflow
                case Z_MEM_ERROR:
                    throw NIOCompression.Error.noMoreMemory
                case Z_STREAM_END:
                    break
                default:
                    throw NIOCompression.Error.internalError
                }
            } catch {
                lastError = error
                nextInBufferOffset = self.stream.next_in - CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
                throw error
            }
        }
        from.moveReaderIndex(forwardBy: bytesRead)
    }
    
    mutating func finishStream() {
        assert(isActive)
        isActive = false
        deflateEnd(&self.stream)
    }
    
    mutating func deflateBound(from: ByteBuffer) -> Int {
        // deflateBound() provides an upper limit on the number of bytes the input can
        // compress to. We add 5 bytes to handle the fact that Z_SYNC_FLUSH will append
        // an empty stored block that is 5 bytes long.
        // From zlib docs (https://www.zlib.net/manual.html)
        // If the parameter flush is set to Z_SYNC_FLUSH, all pending output is flushed to the output buffer and the output is
        // aligned on a byte boundary, so that the decompressor can get all input data available so far. (In particular avail_in
        // is zero after the call if enough output space has been provided before the call.) Flushing may degrade compression for
        // some compression algorithms and so it should be used only when necessary. This completes the current deflate block and
        // follows it with an empty stored block that is three bits plus filler bits to the next byte, followed by four bytes
        // (00 00 ff ff).
        // As we use avail_out == 0 as an indicator of whether the deflate was complete. I also add an extra byte to ensure we
        // always have at least one byte left in the compressed buffer after the deflate has completed.
        let bufferSize = Int(CNIOCompressZlib.deflateBound(&stream, UInt(from.readableBytes)))
        return bufferSize + 6
    }
}

struct ZlibDecompressor: NIODecompressor {
    let windowBits: Int
    var isActive: Bool
    var stream = z_stream()
    var nextInBufferOffset: Int
    var lastError: Error?

    init(windowBits: Int) {
        self.windowBits = windowBits
        self.isActive = false
        self.nextInBufferOffset = 0
        self.lastError = nil
    }

    mutating func startStream() {
        assert(!isActive)
        isActive = true

        self.stream.zalloc = nil
        self.stream.zfree = nil
        self.stream.opaque = nil

        let rc = CNIOCompressZlib_inflateInit2(&self.stream, Int32(windowBits))
        precondition(rc == Z_OK, "Unexpected return from zlib init: \(rc)")
    }
    
    mutating func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        assert(isActive)
        var bytesRead = 0
        var bytesWritten = 0

        defer {
            to.moveWriterIndex(forwardBy: bytesWritten)
        }

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            if lastError == nil {
                self.stream.avail_in = UInt32(fromBuffer.count)
                self.stream.next_in = CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            } else {
                self.stream.next_in = CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!) + nextInBufferOffset
            }
            self.stream.avail_out = UInt32(toBuffer.count)
            self.stream.next_out = CNIOCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            lastError = nil

            let rt = CNIOCompressZlib.inflate(&self.stream, Z_NO_FLUSH)

            bytesRead = fromBuffer.count - Int(self.stream.avail_in)
            bytesWritten = toBuffer.count - Int(self.stream.avail_out)
            do {
                switch rt {
                case Z_OK:
                    if self.stream.avail_out == 0 {
                        throw NIOCompression.Error.bufferOverflow
                    }
                case Z_BUF_ERROR:
                    throw NIOCompression.Error.bufferOverflow
                case Z_DATA_ERROR:
                    throw NIOCompression.Error.corruptData
                case Z_MEM_ERROR:
                    throw NIOCompression.Error.noMoreMemory
                case Z_STREAM_END:
                    break
                default:
                    throw NIOCompression.Error.internalError
                }
            } catch {
                lastError = error
                nextInBufferOffset = self.stream.next_in - CNIOCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
                throw error
            }
        }
        from.moveReaderIndex(forwardBy: bytesRead)
    }
    
    mutating func finishStream() {
        assert(isActive)
        isActive = false
        inflateEnd(&self.stream)
    }
}
