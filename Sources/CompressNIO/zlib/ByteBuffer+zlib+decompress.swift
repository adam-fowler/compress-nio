
import NIOCore

// Decompress extensions to ByteBuffer
extension ByteBuffer {
    /// Decompress the readable contents of this byte buffer into another using the compression
    /// algorithm specified.
    ///
    /// - Parameters:
    ///   - buffer: Byte buffer to write decompressed data to
    ///   - algorithm: Algorithm to use when decompressing
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space
    ///         to write the decompressed data into
    ///     - `NIOCompression.Error.corruptData` if the input byte buffer is corrupted
    public mutating func decompress(
        to buffer: inout ByteBuffer,
        with algorithm: ZlibAlgorithm,
        configuration: ZlibConfiguration = .init()
    ) throws {
        let decompressor = try ZlibDecompressor(algorithm: algorithm, windowSize: configuration.windowSize)
        try decompressor.inflate(from: &self, to: &buffer)
    }

    /// Allocate a `ByteBuffer` to decompress this buffer into. Decompress  the readable contents of
    /// this byte buffer into the allocated buffer. If the allocated buffer is too small allocate more
    /// space and continue the decompression.
    ///
    /// Seeing as this method cannot tell the size of the buffer required to allocate for decompression
    /// it may allocate many `ByteBuffers` during the decompress process. It is always preferable to
    /// know in advance the size of the decompressed buffer and to use `decompress(to:with:)`.
    ///
    /// - Parameters:
    ///   - buffer: Byte buffer to write decompressed data to
    ///   - maxSize: Maximum size of buffer to allocate to decompress into
    ///   - allocator: Byte buffer allocator used to create new byte buffers
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space to write the decompressed data into
    ///     - `NIOCompression.Error.corruptData` if the input byte buffer is corrupted
    public mutating func decompress(
        with algorithm: ZlibAlgorithm,
        configuration: ZlibConfiguration = .init(),
        maxSize: Int = .max,
        allocator: ByteBufferAllocator = ByteBufferAllocator()
    ) throws -> ByteBuffer {
        let decompressor = try ZlibDecompressor(algorithm: algorithm, windowSize: configuration.windowSize)
        let buffer = try decompressStream(with: decompressor, maxSize: maxSize, allocator: allocator)
        return buffer
    }

    /// A version of decompressStream which you provide a fixed sized window buffer to and a process closure.
    ///
    /// When the window buffer is full the process closure is called. If there is any unprocessed data left
    /// at the end of the compress the process closure is called with this.
    ///
    /// Before calling this you need to provide a working window `ByteBuffer` to the decompressor by
    /// setting `NIODecompressor.window`.
    ///
    /// - Parameters:
    ///   - compressor: Algorithm to use when decompressing
    ///   - process: Closure to be called when window buffer fills up or decompress has finished
    /// - Returns: `ByteBuffer` containing compressed data
    public mutating func decompressStream(
        with decompressor: ZlibDecompressor,
        window: inout ByteBuffer,
        process: (ByteBuffer) throws -> Void
    ) throws {
        while self.readableBytes > 0 {
            do {
                try self.decompressStream(to: &window, with: decompressor)
            } catch let error as CompressNIOError where error == .bufferOverflow {
                try process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            } catch let error as CompressNIOError where error == .inputBufferOverflow {
                // can ignore CompressNIOError.inputBufferOverflow errors here
            }
        }

        if window.readableBytes > 0 {
            try process(window)
        }
    }

    /// A version of decompressStream which allocates the ByteBuffer to write into.
    ///
    /// As with `decompress(with:allocator)` this method cannot tell the size of the buffer required to
    /// allocate for the decompression. It may allocate many `ByteBuffers` during the decompress process.
    /// It is always preferable to know in advance the size of the decompressed buffer and to use
    /// `decompressStream(to:with:)`.
    ///
    /// - Parameters:
    ///   - decompressor: Algorithm to use when decompressing
    ///   - maxSize: Maximum size of buffer to allocate to decompress into
    ///   - allocator: Byte buffer allocator used to allocate the new `ByteBuffer`
    /// - Returns: `ByteBuffer` containing compressed data
    public mutating func decompressStream(
        with decompressor: ZlibDecompressor,
        maxSize: Int = .max,
        allocator: ByteBufferAllocator = ByteBufferAllocator()
    ) throws -> ByteBuffer {
        var buffers: [ByteBuffer] = []
        let originalSize = self.readableBytes
        func _decompress(iteration: Int, bufferSize: Int) throws {
            var bufferSize = bufferSize
            if bufferSize >= maxSize {
                throw CompressNIOError.bufferOverflow
            }
            var nextBufferSize = iteration * 3 * originalSize / 2
            if bufferSize + nextBufferSize > maxSize {
                nextBufferSize = maxSize - bufferSize
            }
            bufferSize += nextBufferSize
            // grow buffer to write into with each iteration
            var buffer = allocator.buffer(capacity: nextBufferSize)
            do {
                defer {
                    if buffer.readableBytes > 0 {
                        buffers.append(buffer)
                    }
                }
                try self.decompressStream(to: &buffer, with: decompressor)
            } catch let error as CompressNIOError where error == CompressNIOError.bufferOverflow {
                try _decompress(iteration: iteration + 1, bufferSize: bufferSize)
            } catch let error as CompressNIOError where error == .inputBufferOverflow {
                // can ignore CompressNIOError.inputBufferOverflow errors here
            }
        }

        try _decompress(iteration: 1, bufferSize: 0)

        if buffers.count == 0 {
            return allocator.buffer(capacity: 0)
        } else if buffers.count == 1 {
            return buffers[0]
        } else {
            // concatenate all the buffers together
            let size = buffers.reduce(0) { return $0 + $1.readableBytes }
            var finalBuffer = allocator.buffer(capacity: size)
            for var buffer in buffers {
                finalBuffer.writeBuffer(&buffer)
            }
            return finalBuffer
        }
    }

    /// Decompress one byte buffer from a stream of blocks out of a compressed bytebuffer
    ///
    /// The decompress stream functions work with a stream of data. You create a `NIODecompressor`,
    /// call `startStream` on it and then for each chunk of data in the stream you call `decompressStream`.
    /// Once you are complete call `endStream`.
    ///  eg
    ///  ```
    ///  let decompressor = NIOCompression.Algorithm.gzip.decompressor
    ///  try decompressor.startStream()
    ///  try inputBuffer1.decompressStream(to: &outputBuffer, with: decompressor)
    ///  try inputBuffer2.decompressStream(to: &outputBuffer, with: decompressor)
    ///  ...
    ///  try decompressor.finishStream()
    ///  ````
    ///
    ///  If a `bufferOverflow` error is thrown you can supply a larger buffer and call the `decompressStream`
    /// again. Remember though the `ByteBuffer` you were writing into from the original call could have some
    /// decompressed data in it still so don't throw it away.
    ///
    /// - Parameters:
    ///   - byteBuffer: byte buffer block from a compressed buffer
    ///   - decompressor: Algorithm to use when decompressing
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space to write
    ///            the decompressed data into
    ///     - `NIOCompression.Error.corruptData` if the input byte buffer is corrupted
    public mutating func decompressStream(
        to byteBuffer: inout ByteBuffer,
        with decompressor: ZlibDecompressor
    ) throws {
        do {
            try decompressor.inflate(from: &self, to: &byteBuffer)
        } catch let error as CompressNIOError where error == .inputBufferOverflow {
            // can ignore CompressNIOError.inputBufferOverflow errors here
        }
    }

    /// A version of decompressStream which you provide a fixed sized window buffer to and a process closure.
    ///
    /// When the window buffer is full the process closure is called. If there is any unprocessed data left
    /// at the end of the compress the process closure is called with this.
    ///
    /// Before calling this you need to provide a working window `ByteBuffer` to the decompressor by
    /// setting `NIODecompressor.window`.
    ///
    /// - Parameters:
    ///   - compressor: Algorithm to use when decompressing
    ///   - process: Closure to be called when window buffer fills up or decompress has finished
    /// - Returns: `ByteBuffer` containing compressed data
    public mutating func decompressStream(
        with decompressor: ZlibDecompressor,
        window: inout ByteBuffer,
        process: (ByteBuffer) async throws -> Void
    ) async throws {
        while self.readableBytes > 0 {
            do {
                try self.decompressStream(to: &window, with: decompressor)
            } catch let error as CompressNIOError where error == .bufferOverflow {
                try await process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            } catch let error as CompressNIOError where error == .inputBufferOverflow {
                // can ignore CompressNIOError.inputBufferOverflow errors here
            }
        }

        if window.readableBytes > 0 {
            try await process(window)
        }
    }
}
