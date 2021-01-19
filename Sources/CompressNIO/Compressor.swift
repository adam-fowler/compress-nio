
import NIO

/// Protocol for decompressor
public protocol NIODecompressor: class {
    /// Decompress byte buffer to another byte buffer
    /// - Parameters:
    ///   - from: source byte buffer
    ///   - to: destination byte buffer
    func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    
    /// Working buffer for window based compression
    var window: ByteBuffer? { get set }
    
    /// Setup decompressor for stream decompression
    func startStream() throws
    
    /// Decompress block as part of a stream to another ByteBuffer
    /// - Parameters:
    ///   - from: source byte buffer
    ///   - to: destination byte buffer
    func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    
    /// Finished using thie decompressor for stream decompression
    func finishStream() throws
    
    /// equivalent of calling `finishStream` followed by `startStream`.
    func resetStream() throws
}

extension NIODecompressor {
    /// Default implementation of `inflate`: start stream, inflate one buffer, end stream
    public func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        try startStream()
        try streamInflate(from: &from, to: &to)
        try finishStream()
    }

    /// Default implementation of `reset`.
    public func resetStream() throws {
        try finishStream()
        try startStream()
    }
}

/// how should compressor flush output data
public enum CompressNIOFlush {
    /// let compressor decide how much data should be flushed to the output buffer
    case no
    /// ensure all data that has been read has been flushed
    case sync
    /// finish compressing and do a full flush
    case finish
}

/// Protocol for compressor
public protocol NIOCompressor: class {
    /// Compress byte buffer to another byte buffer
    /// - Parameters:
    ///   - from: source byte buffer
    ///   - to: destination byte buffer
    func deflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    
    /// Working buffer for window based compression
    var window: ByteBuffer? { get set }
    
    /// Setup compressor for stream compression
    func startStream() throws
    
    /// Compress block as part of a stream compression
    /// - Parameters:
    ///   - from: source byte buffer
    ///   - to: destination byte buffer
    ///   - flush: how compressor should flush output data.
    func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, flush: CompressNIOFlush) throws

    /// Finish stream deflate, where you have no more input data but still have data to output
    /// - Parameter to: destination byte buffer
    func finishDeflate(to: inout ByteBuffer) throws

    /// Finish using this compressor for stream compression
    func finishStream() throws

    /// Finish using this compressor for stream compression
    func finishWindowedStream(process: (ByteBuffer)->()) throws

    /// equivalent of calling `finishStream` followed by `startStream`. There maybe implementation of this that are more optimal
    func resetStream() throws

    /// Return the maximum possible number of bytes required for the compressed version of a `ByteBuffer`
    /// - Parameter from: `ByteBuffer` to get maximum size for
    func maxSize(from: ByteBuffer) -> Int
}

extension NIOCompressor {
    /// default version of `deflate`:  start stream, compress one bufferm, finish stream
    public func deflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        try startStream()
        try streamDeflate(from: &from, to: &to, flush: .finish)
        try finishStream()
    }
    
    /// Default implementation of `reset`.
    public func resetStream() throws {
        try finishStream()
        try startStream()
    }

    public func finishWindowedStream(process: (ByteBuffer)->()) throws {
        guard var window = self.window else { preconditionFailure("finishWindowedStream requires your compressor has a window buffer") }
        while true {
            do {
                try finishDeflate(to: &window)
                break
            } catch let error as CompressNIOError where error == .bufferOverflow {
                process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            }
        }

        if window.readableBytes > 0 {
            process(window)
        }
        window.moveReaderIndex(to: 0)
        window.moveWriterIndex(to: 0)
    }
}

