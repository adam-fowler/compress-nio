
import NIOCore

// compress extensions to ByteBuffer
extension ByteBuffer {
    /// Compress the readable contents of this byte buffer into another using the compression algorithm specified
    /// - Parameters:
    ///   - buffer: Byte buffer to write compressed data to
    ///   - algorithm: Algorithm to use when compressing
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesnt have enough space to
    ///         write the compressed data into
    public mutating func compress(to buffer: inout ByteBuffer, with algorithm: ZlibAlgorithm, configuration: ZlibConfiguration = .init()) throws {
        var compressor = ZlibCompressor(algorithm: algorithm, configuration: configuration)
        try compressor.deflate(from: &self, to: &buffer)
    }

    /// Allocate a new byte buffer and compress this byte buffer into it using the compression algorithm specified
    /// - Parameters:
    ///   - algorithm: Algorithm to use when compressing
    ///   - allocator: Byte buffer allocator used to create new byte buffer
    /// - Returns: the new byte buffer with the compressed data
    public mutating func compress(
        with algorithm: ZlibAlgorithm,
        configuration: ZlibConfiguration = .init(),
        allocator: ByteBufferAllocator = ByteBufferAllocator()
    ) throws -> ByteBuffer {
        var compressor = ZlibCompressor(algorithm: algorithm, configuration: configuration)
        var buffer = allocator.buffer(capacity: compressor.maxSize(from: self))
        try compressor.deflate(from: &self, to: &buffer)
        return buffer
    }

    /// A version of compressStream which you provide a fixed sized window buffer to and a process closure.
    ///
    /// When the window buffer is full the process closure is called. If there is any unprocessed data left
    /// at the end of the compress the process closure is called with this.
    ///
    /// Before calling this you need to provide a working window `ByteBuffer` to the compressor by setting
    /// `NIOCompressor.window`.
    ///
    /// - Parameters:
    ///   - compressor: Algorithm to use when compressing
    ///   - flush: how compressor should flush output data.
    ///   - process: Closure to be called when window buffer fills up or compress has finished
    /// - Returns: `ByteBuffer` containing compressed data
    public mutating func compressStream(
        with compressor: inout ZlibCompressor,
        window: inout ByteBuffer,
        flush: CompressNIOFlush,
        process: (ByteBuffer) throws -> Void
    ) throws {
        while self.readableBytes > 0 {
            do {
                try self.compressStream(to: &window, with: &compressor, flush: .no)
            } catch let error as CompressNIOError where error == .bufferOverflow {
                try process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            }
        }

        if flush == .sync {
            while true {
                do {
                    try self.compressStream(to: &window, with: &compressor, flush: .sync)
                    break
                } catch let error as CompressNIOError where error == .bufferOverflow {
                    try process(window)
                    window.moveReaderIndex(to: 0)
                    window.moveWriterIndex(to: 0)
                }
            }
        } else if flush == .finish {
            while true {
                do {
                    try self.compressStream(to: &window, with: &compressor, flush: .finish)
                    break
                } catch let error as CompressNIOError where error == .bufferOverflow {
                    try process(window)
                    window.moveReaderIndex(to: 0)
                    window.moveWriterIndex(to: 0)
                }
            }
        }

        if flush == .finish {
            if window.readableBytes > 0 {
                try process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            }
        }
    }

    /// A version of compressStream which allocates the ByteBuffer to write into.
    ///
    /// If you call this after a call to another `compressStream` this cannot accurately calculate the size
    /// of the buffer required to compress into unless the previous call to `compressStream` was called with
    /// `flush` set to `.sync`. If the buffer calculation is inaccurate a `.bufferOverflow` error is thrown.
    ///
    /// - Parameters:
    ///   - compressor: Algorithm to use when compressing
    ///   - flush: how compressor should flush output data.
    ///   - allocator: Byte buffer allocator used to allocate the new `ByteBuffer`
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if the allocated byte buffer doesn't have enough space to write the decompressed data into
    /// - Returns: `ByteBuffer` containing compressed data
    public mutating func compressStream(
        with compressor: inout ZlibCompressor,
        flush: CompressNIOFlush,
        allocator: ByteBufferAllocator = ByteBufferAllocator()
    ) throws -> ByteBuffer {
        var byteBuffer = allocator.buffer(capacity: compressor.maxSize(from: self))
        try self.compressStream(to: &byteBuffer, with: &compressor, flush: flush)
        return byteBuffer
    }

    /// Compress one byte buffer from a stream of blocks into another bytebuffer
    ///
    /// The compress stream functions work with a stream of data. You create a `NIOCompressor`, call
    /// `startStream` on it and then for each chunk of data in the stream you call `compressStream`.
    /// Your last block should be called with the `flush` parameter set to `.finish`. Once you are complete
    /// call `endStream`.
    ///  eg
    ///  ```
    ///  let compressor = NIOCompression.Algorithm.gzip.compressor
    ///  try compressor.startStream()
    ///  try inputBuffer1.compressStream(to: &outputBuffer, with: compressor, flush: .no)
    ///  try inputBuffer2.compressStream(to: &outputBuffer, with: compressor, flush: .no)
    ///  ...
    ///  try inputBufferN.compressStream(to: &outputBuffer, with: compressor, flush: .finish)
    ///  try decompressor.finishStream()
    ///  ````
    ///
    ///  If you call this function without `flush` set to `.finish` it will return if some data has been
    /// processed. Unless you are certain you have provided a output buffer large enough you should to see
    /// if your input buffer has any `readableBytes` left and call the function again if there are any.
    /// If a `bufferOverflow` error is thrown you need to supply a larger buffer and call the `compressStream`
    /// again. Remember though the `ByteBuffer` you were writing into from the original call could have some
    /// decompressed data in it still so don't throw it away.
    ///
    /// - Parameters:
    ///   - byteBuffer: byte buffer block from a large byte buffer
    ///   - compressor: Algorithm to use when compressing
    ///   - flush: how compressor should flush output data.
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space to write the compressed data into
    public mutating func compressStream(
        to byteBuffer: inout ByteBuffer,
        with compressor: inout ZlibCompressor,
        flush: CompressNIOFlush
    ) throws {
        try compressor.streamDeflate(from: &self, to: &byteBuffer, flush: flush)
    }

    /// A version of compressStream which you provide a fixed sized window buffer to and a process closure.
    ///
    /// When the window buffer is full the process closure is called. If there is any unprocessed data left
    /// at the end of the compress the process closure is called with this.
    ///
    /// Before calling this you need to provide a working window `ByteBuffer` to the compressor by setting
    /// `NIOCompressor.window`.
    ///
    /// - Parameters:
    ///   - compressor: Algorithm to use when compressing
    ///   - flush: how compressor should flush output data.
    ///   - process: Closure to be called when window buffer fills up or compress has finished
    /// - Returns: `ByteBuffer` containing compressed data
    public mutating func compressStream(
        with compressor: inout ZlibCompressor,
        window: inout ByteBuffer,
        flush: CompressNIOFlush,
        process: (ByteBuffer) async throws -> Void
    ) async throws {
        while self.readableBytes > 0 {
            do {
                try self.compressStream(to: &window, with: &compressor, flush: .no)
            } catch let error as CompressNIOError where error == .bufferOverflow {
                try await process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            }
        }

        if flush == .sync {
            while true {
                do {
                    try self.compressStream(to: &window, with: &compressor, flush: .sync)
                    break
                } catch let error as CompressNIOError where error == .bufferOverflow {
                    try await process(window)
                    window.moveReaderIndex(to: 0)
                    window.moveWriterIndex(to: 0)
                }
            }
        } else if flush == .finish {
            while true {
                do {
                    try self.compressStream(to: &window, with: &compressor, flush: .finish)
                    break
                } catch let error as CompressNIOError where error == .bufferOverflow {
                    try await process(window)
                    window.moveReaderIndex(to: 0)
                    window.moveWriterIndex(to: 0)
                }
            }
        }

        if flush == .finish {
            if window.readableBytes > 0 {
                try await process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            }
        }
    }
}
