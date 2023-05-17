
import NIOCore

// compress/decompress extensions to ByteBuffer
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
    public mutating func decompress(to buffer: inout ByteBuffer, with algorithm: CompressionAlgorithm) throws {
        let decompressor = algorithm.decompressor(windowBits: 15)
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
    ///   - allocator: Byte buffer allocator used to create new byte buffers
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space to write the decompressed data into
    ///     - `NIOCompression.Error.corruptData` if the input byte buffer is corrupted
    public mutating func decompress(with algorithm: CompressionAlgorithm, allocator: ByteBufferAllocator = ByteBufferAllocator()) throws -> ByteBuffer {
        let decompressor = algorithm.decompressor(windowBits: 15)
        try decompressor.startStream()
        let buffer = try decompressStream(with: decompressor, allocator: allocator)
        try decompressor.finishStream()
        return buffer
    }

    /// Compress the readable contents of this byte buffer into another using the compression algorithm specified
    /// - Parameters:
    ///   - buffer: Byte buffer to write compressed data to
    ///   - algorithm: Algorithm to use when compressing
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesnt have enough space to 
    ///         write the compressed data into
    public mutating func compress(to buffer: inout ByteBuffer, with algorithm: CompressionAlgorithm) throws {
        let compressor = algorithm.compressor(windowBits: 15)
        try compressor.deflate(from: &self, to: &buffer)
    }
    
    /// Allocate a new byte buffer and compress this byte buffer into it using the compression algorithm specified
    /// - Parameters:
    ///   - algorithm: Algorithm to use when compressing
    ///   - allocator: Byte buffer allocator used to create new byte buffer
    /// - Returns: the new byte buffer with the compressed data
    public mutating func compress(
        with algorithm: CompressionAlgorithm, 
        allocator: ByteBufferAllocator = ByteBufferAllocator()
    ) throws -> ByteBuffer {
        let compressor = algorithm.compressor(windowBits: 15)
        var buffer = allocator.buffer(capacity: compressor.maxSize(from: self))
        try compressor.deflate(from: &self, to: &buffer)
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
        with decompressor: NIODecompressor, 
        process: (ByteBuffer)->()
    ) throws {
        guard var window = decompressor.window else { 
            preconditionFailure("decompressString(with:flush:process requires your compressor has a window buffer")
        }
        while self.readableBytes > 0 {
            do {
                try decompressStream(to: &window, with: decompressor)
            } catch let error as CompressNIOError where error == .bufferOverflow {
                process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            }
        }

        if window.readableBytes > 0 {
            process(window)
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
    ///   - allocator: Byte buffer allocator used to allocate the new `ByteBuffer`
    /// - Returns: `ByteBuffer` containing compressed data
    public mutating func decompressStream(
        with decompressor: NIODecompressor, 
        allocator: ByteBufferAllocator = ByteBufferAllocator()
    ) throws -> ByteBuffer {
        var buffers: [ByteBuffer] = []
        let originalSize = self.readableBytes
        func _decompress(iteration: Int) throws {
            // grow buffer to write into with each iteration
            var buffer = allocator.buffer(capacity: iteration * 3 * originalSize / 2)
            do {
                defer {
                    if buffer.readableBytes > 0 {
                        buffers.append(buffer)
                    }
                }
                try decompressStream(to: &buffer, with: decompressor)
            } catch let error as CompressNIOError where error == CompressNIOError.bufferOverflow {
                try _decompress(iteration: iteration+1)
            }
        }
        
        try _decompress(iteration: 1)
        
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
        with decompressor: NIODecompressor
    ) throws {
        try decompressor.streamInflate(from: &self, to: &byteBuffer)
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
        with compressor: NIOCompressor, 
        flush: CompressNIOFlush, 
        process: (ByteBuffer)->()
    ) throws {
        guard var window = compressor.window else { preconditionFailure("compressString(with:flush:process requires your compressor has a window buffer") }
        while self.readableBytes > 0 {
            do {
                try compressStream(to: &window, with: compressor, flush: .no)
            } catch let error as CompressNIOError where error == .bufferOverflow {
                process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            }
        }
        
        if flush == .sync {
            while true {
                do {
                    try compressStream(to: &window, with: compressor, flush: .sync)
                    break
                } catch let error as CompressNIOError where error == .bufferOverflow {
                    process(window)
                    window.moveReaderIndex(to: 0)
                    window.moveWriterIndex(to: 0)
                }
            }
        } else if flush == .finish {
            while true {
                do {
                    try compressStream(to: &window, with: compressor, flush: .finish)
                    break
                } catch let error as CompressNIOError where error == .bufferOverflow {
                    process(window)
                    window.moveReaderIndex(to: 0)
                    window.moveWriterIndex(to: 0)
                }
            }
        }

        if flush == .finish {
            if window.readableBytes > 0 {
                process(window)
                window.moveReaderIndex(to: 0)
                window.moveWriterIndex(to: 0)
            }
        }
        compressor.window = window
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
        with compressor: NIOCompressor, 
        flush: CompressNIOFlush, 
        allocator: ByteBufferAllocator = ByteBufferAllocator()
    ) throws -> ByteBuffer {
        var byteBuffer = allocator.buffer(capacity: compressor.maxSize(from: self))
        try compressStream(to: &byteBuffer, with: compressor, flush: flush)
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
        with compressor: NIOCompressor, 
        flush: CompressNIOFlush
    ) throws {
        try compressor.streamDeflate(from: &self, to: &byteBuffer, flush: flush)
    }
}

extension ByteBuffer {
    /// Process unsafe version of readable data and write out to unsafe writable data of another ByteBuffer
    /// - Parameters:
    ///   - to: Target `ByteBuffer`
    ///   - closure: Process closure
    public mutating func withUnsafeProcess(to: inout ByteBuffer, closure: (UnsafeMutableRawBufferPointer, UnsafeMutableRawBufferPointer) throws -> ()) throws {
        try self.withUnsafeMutableReadableBytes { fromBuffer in
            try to.withUnsafeMutableWritableBytes { toBuffer in
                try closure(fromBuffer, toBuffer)
            }
        }
    }
}
