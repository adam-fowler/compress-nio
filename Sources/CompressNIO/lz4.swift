import CLZ4
import NIO

/// Compressor using LZ4
class LZ4Compressor: NIOCompressor {
    var stream: UnsafeMutablePointer<LZ4_stream_t>?
    var dictionary: ByteBuffer! = nil
    
    init() {
        stream = nil
    }
    
    deinit {
        if stream != nil {
            try? finishStream()
        }
    }

    func startStream() throws {
        assert(stream == nil)
        stream = LZ4_createStream()
        self.dictionary = ByteBufferAllocator().buffer(capacity: 64*1024)
    }
    
    func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, flush: CompressNIOFlush) throws {
        assert(stream != nil)
        var bytesRead = 0
        var bytesWritten = 0
        
        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let rt = LZ4_compress_fast_continue(
                stream,
                LZ4_voidPtr_to_CharPtr(fromBuffer.baseAddress!),
                LZ4_voidPtr_to_CharPtr(toBuffer.baseAddress!),
                Int32(fromBuffer.count),
                Int32(toBuffer.count),
                1
            )
            switch rt {
            case -1:
                throw CompressNIOError.corruptData
            case ..<(-1):
                throw CompressNIOError.bufferOverflow
            default:
                break
            }

            _ = dictionary.withUnsafeMutableReadableBytes { buffer in
                LZ4_saveDict(stream, LZ4_voidPtr_to_CharPtr(buffer.baseAddress!), 64*1024)
            }
            
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)
    }
    
    func finishStream() throws {
        assert(stream != nil)
        LZ4_freeStream(stream)
        stream = nil
        self.dictionary = nil
    }
    
    func resetStream() throws {
        assert(stream != nil)
        // LZ4_resetStream_fast is a more optimal than calling finish and then start
        LZ4_resetStream_fast(stream)
    }

    func maxSize(from: ByteBuffer) -> Int {
        let bufferSize = LZ4_compressBound(Int32(from.readableBytes))
        return Int(bufferSize)
    }

    func deflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        var bytesRead = 0
        var bytesWritten = 0

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let rt = LZ4_compress_default(
                LZ4_voidPtr_to_CharPtr(fromBuffer.baseAddress!),
                LZ4_voidPtr_to_CharPtr(toBuffer.baseAddress!),
                Int32(fromBuffer.count),
                Int32(toBuffer.count)
            )
            switch rt {
            case -1:
                throw CompressNIOError.corruptData
            case ..<(-1):
                throw CompressNIOError.bufferOverflow
            default:
                break
            }
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)
    }

}

class LZ4Decompressor: NIODecompressor {
    var stream: UnsafeMutablePointer<LZ4_streamDecode_t>?
    var lastByteBuffer: ByteBuffer?
    
    deinit {
        if stream != nil {
            try? finishStream()
        }
    }

    func startStream() throws {
        assert(stream == nil)
        stream = LZ4_createStreamDecode()
    }
    
    func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        assert(stream != nil)
        var bytesRead = 0
        var bytesWritten = 0
        
        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let rt = LZ4_decompress_safe_continue(
                stream,
                LZ4_voidPtr_to_CharPtr(fromBuffer.baseAddress!),
                LZ4_voidPtr_to_CharPtr(toBuffer.baseAddress!),
                Int32(fromBuffer.count),
                Int32(toBuffer.count)
            )
            switch rt {
            case -1:
                throw CompressNIOError.corruptData
            case ..<(-1):
                throw CompressNIOError.bufferOverflow
            default:
                break
            }
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)

        // store reference to last ByteBuffer uncompressed as it is used in the next decompress
        lastByteBuffer = to
    }
    
    func finishStream() throws {
        assert(stream != nil)
        LZ4_freeStreamDecode(stream)
        stream = nil
        self.lastByteBuffer = nil

    }
    
    func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        var bytesRead = 0
        var bytesWritten = 0

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let rt = LZ4_decompress_safe(
                LZ4_voidPtr_to_CharPtr(fromBuffer.baseAddress!),
                LZ4_voidPtr_to_CharPtr(toBuffer.baseAddress!),
                Int32(fromBuffer.count),
                Int32(toBuffer.count)
            )
            switch rt {
            case -1:
                throw CompressNIOError.corruptData
            case ..<(-1):
                throw CompressNIOError.bufferOverflow
            default:
                break
            }
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)
    }
}
