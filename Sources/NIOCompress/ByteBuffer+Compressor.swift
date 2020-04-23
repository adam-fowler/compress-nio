
import NIO

extension ByteBuffer {
    public mutating func compress(with algorithm: NIOCompression.Algorithm, allocator: ByteBufferAllocator) throws -> ByteBuffer {
        var compressor = algorithm.compressor
        var buffer = allocator.buffer(capacity: compressor.deflateBound(from: self))
        try compressor.deflate(from: &self, to: &buffer)
        return buffer
    }
    
    public mutating func compress(to buffer: inout ByteBuffer, with algorithm: NIOCompression.Algorithm) throws {
        var compressor = algorithm.compressor
        try compressor.deflate(from: &self, to: &buffer)
    }

    public mutating func decompress(to buffer: inout ByteBuffer, with algorithm: NIOCompression.Algorithm) throws {
        var decompressor = algorithm.decompressor
        try decompressor.inflate(from: &self, to: &buffer)
    }

    public mutating func compressStream(with compressor: inout NIOCompressor, finalise: Bool, allocator: ByteBufferAllocator) throws -> ByteBuffer {
        var byteBuffer = allocator.buffer(capacity: compressor.deflateBound(from: self))
        try compressStream(to: &byteBuffer, with: &compressor, finalise: finalise)
        return byteBuffer
        
    }
    
    public mutating func compressStream(to byteBuffer: inout ByteBuffer, with compressor: inout NIOCompressor, finalise: Bool) throws {
        try compressor.streamDeflate(from: &self, to: &byteBuffer, finalise: finalise)
    }

    public mutating func decompressStream(to byteBuffer: inout ByteBuffer, with decompressor: inout NIODecompressor) throws {
        try decompressor.streamInflate(from: &self, to: &byteBuffer)
    }
}

extension ByteBuffer {
    mutating func withUnsafeProcess(to: inout ByteBuffer, closure: (UnsafeMutableRawBufferPointer, UnsafeMutableRawBufferPointer) throws -> ()) throws {
        try self.withUnsafeMutableReadableBytes { fromBuffer in
            try to.withUnsafeMutableWritableBytes { toBuffer in
                try closure(fromBuffer, toBuffer)
            }
        }
    }
}
