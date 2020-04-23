
import NIO

/// Protocol for decompressor
public protocol NIODecompressor: class {
    /// Decompress byte buffer to another byte buffer
    /// - Parameters:
    ///   - from: source byte buffer
    ///   - to: destination byte buffer
    func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    
    /// Setup decompressor for stream decompression
    func startStream() throws
    
    /// Decompress block as part of a stream to another ByteBuffer
    /// - Parameters:
    ///   - from: source byte buffer
    ///   - to: destination byte buffer
    func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    
    /// Finished using thie decompressor for stream decompression
    func finishStream() throws
}

extension NIODecompressor {
    /// Default implementation of `inflate`: start stream, inflate one buffer, end stream
    public func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        try startStream()
        try streamInflate(from: &from, to: &to)
        try finishStream()
    }
}

/// Protocol for compressor
public protocol NIOCompressor: class {
    /// Compress byte buffer to another byte buffer
    /// - Parameters:
    ///   - from: source byte buffer
    ///   - to: destination byte buffer
    func deflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    
    /// Setup compressor for stream compression
    func startStream() throws
    
    /// Compress block as part of a stream compression
    /// - Parameters:
    ///   - from: source byte buffer
    ///   - to: destination byte buffer
    ///   - finalise: Is this the final block to compress
    func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, finalise: Bool) throws
    
    /// Finish using this compressor for stream compression
    func finishStream() throws
    
    /// Return the maximum possible number of bytes required for the compressed version of a `ByteBuffer`
    /// - Parameter from: `ByteBuffer` to get maximum size for
    func deflateBound(from: ByteBuffer) -> Int
}

extension NIOCompressor {
    /// default version of `deflate`:  start stream, compress one bufferm, finish stream
    public func deflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        try startStream()
        try streamDeflate(from: &from, to: &to, finalise: true)
        try finishStream()
    }
}

