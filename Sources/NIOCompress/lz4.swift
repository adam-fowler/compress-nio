import CLZ4
import NIO

/// Compressor using LZ4
class LZ4Compressor: NIOCompressor {
    var stream: UnsafeMutablePointer<LZ4_stream_t>?
    var dictionary: ByteBuffer! = nil
    
    init() {
        stream = nil
    }
    
    func startStream() throws {
        assert(self.stream == nil)
        self.stream = LZ4_createStream()
        self.dictionary = ByteBufferAllocator().buffer(capacity: 64*1024)
    }
    
    func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, finalise: Bool) throws {
        assert(self.stream != nil) 
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
            if rt < 0 {
                throw NIOCompressError.bufferOverflow
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
        assert(self.stream != nil)
        LZ4_freeStream(stream)
        self.stream = nil
        self.dictionary = nil
    }
    
    func maxSize(from: ByteBuffer) -> Int {
        let bufferSize = LZ4_compressBound(Int32(from.readableBytes))
        return Int(bufferSize)
    }

    public func deflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        var bytesRead = 0
        var bytesWritten = 0

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let rt = LZ4_compress_default(
                LZ4_voidPtr_to_CharPtr(fromBuffer.baseAddress!),
                LZ4_voidPtr_to_CharPtr(toBuffer.baseAddress!),
                Int32(fromBuffer.count),
                Int32(toBuffer.count)
            )
            if rt < 0 {
                throw NIOCompressError.bufferOverflow
            }
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)
    }

}

public class LZ4Decompressor: NIODecompressor {
    var stream: UnsafeMutablePointer<LZ4_streamDecode_t>?
    
    public func startStream() throws {
        assert(self.stream == nil)
        self.stream = LZ4_createStreamDecode()
    }
    
    public func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        assert(self.stream != nil)
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
            if rt < 0 {
                throw NIOCompressError.bufferOverflow
            }
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)
    }
    
    public func finishStream() throws {
        assert(self.stream != nil)
        LZ4_freeStreamDecode(self.stream)
        self.stream = nil
    }
    
    public func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        var bytesRead = 0
        var bytesWritten = 0

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let rt = LZ4_decompress_safe(
                LZ4_voidPtr_to_CharPtr(fromBuffer.baseAddress!),
                LZ4_voidPtr_to_CharPtr(toBuffer.baseAddress!),
                Int32(fromBuffer.count),
                Int32(toBuffer.count)
            )
            if rt < 0 {
                throw NIOCompressError.bufferOverflow
            }
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)
    }
}
