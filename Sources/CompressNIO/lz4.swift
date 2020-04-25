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
                throw CompressNIOError.bufferOverflow
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
                throw CompressNIOError.bufferOverflow
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
    var bufferCache = ByteBufferCache(size: 64*1024)
    
    public func startStream() throws {
        assert(self.stream == nil)
        self.stream = LZ4_createStreamDecode()
    }
    
    public func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        assert(self.stream != nil)
        var bytesRead = 0
        var bytesWritten = 0
        
        bufferCache.add(from)
        
        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let rt = LZ4_decompress_safe_continue(
                stream,
                LZ4_voidPtr_to_CharPtr(fromBuffer.baseAddress!),
                LZ4_voidPtr_to_CharPtr(toBuffer.baseAddress!),
                Int32(fromBuffer.count),
                Int32(toBuffer.count)
            )
            if rt < 0 {
                throw CompressNIOError.bufferOverflow
            }
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)
        
        bufferCache.reduce()
    }
    
    public func finishStream() throws {
        assert(self.stream != nil)
        LZ4_freeStreamDecode(self.stream)
        self.stream = nil
        self.bufferCache.empty()
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
                throw CompressNIOError.bufferOverflow
            }
            bytesRead = fromBuffer.count
            bytesWritten = Int(rt)
        }
        to.moveWriterIndex(forwardBy: bytesWritten)
        from.moveReaderIndex(forwardBy: bytesRead)
    }
}

/// Keep a reference to a number ByteBuffers so they aren't deleted
struct ByteBufferCache {
    let size: Int
    var buffers: [ByteBuffer]

    init(size: Int) {
        self.size = size
        self.buffers = []
    }
    
    mutating func add(_ buffer: ByteBuffer) {
        // assert cache has grown too big ie the total size of all the blocks minus the first block is less than the cache size
        assert(buffers.reduce(0){ $0 + $1.readableBytes } - (buffers.first?.readableBytes ?? 0) < size)
        buffers.append(buffer)
    }
    
    mutating func reduce() {
        var count: Int = 0
        var dropIndex: Int? = nil
        for i in (0..<buffers.count).reversed() {
            count += buffers[i].readableBytes
            if count >= size {
                dropIndex = i
                break
            }
        }
        if let dropIndex = dropIndex {
            buffers = Array(buffers[dropIndex..<buffers.count])
        }
    }
    
    mutating func empty() {
        buffers = []
    }
}
