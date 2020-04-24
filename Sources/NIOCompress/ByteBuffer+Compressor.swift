
import NIO

// compress/decompress extensions to ByteBuffer
extension ByteBuffer {
    /// Decompress the readable contents of this byte buffer into another using the compression algorithm specified
    /// - Parameters:
    ///   - buffer: Byte buffer to write decompressed data to
    ///   - algorithm: Algorithm to use when decompressing
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space to write the decompressed data into
    ///     - `NIOCompression.Error.corruptData` if the input byte buffer is corrupted
    public mutating func decompress(to buffer: inout ByteBuffer, with algorithm: CompressionAlgorithm) throws {
        let decompressor = algorithm.decompressor
        try decompressor.inflate(from: &self, to: &buffer)
    }

    /// Allocate a `ByteBuffer` to decompress this buffer into. Decompress  the readable contents of this byte buffer into the allocated buffer. If the allocated buffer is too small allocate more space
    /// and continue the decompression.
    ///
    /// Seeing as this method cannot tell the size of the buffer required to allocate to decompress into it may allocate many `ByteBuffers` during the decompress
    /// process. It is always preferable to know in advance the size of the decompressed buffer and to use `decompress(to:with:)`.
    ///
    /// - Parameters:
    ///   - buffer: Byte buffer to write decompressed data to
    ///   - allocator: Byte buffer allocator used to create new byte buffers
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space to write the decompressed data into
    ///     - `NIOCompression.Error.corruptData` if the input byte buffer is corrupted
    public mutating func decompress(with algorithm: CompressionAlgorithm, allocator: ByteBufferAllocator = ByteBufferAllocator()) throws -> ByteBuffer {
        var buffers: [ByteBuffer] = []
        let originalSize = self.readableBytes
        let decompressor = algorithm.decompressor
        func _decompress(iteration: Int) throws {
            // grow buffer to write into with each iteration
            var buffer = allocator.buffer(capacity: iteration * 3 * originalSize / 2)
            do {
                defer {
                    buffers.append(buffer)
                }
                try decompressStream(to: &buffer, with: decompressor)
            } catch let error as NIOCompressError where error == NIOCompressError.bufferOverflow {
                try _decompress(iteration: iteration+1)
            }
        }
        try decompressor.startStream()
        try _decompress(iteration: 1)
        try decompressor.finishStream()
        
        // concatenate all the buffers together
        if buffers.count == 1 {
            return buffers[0]
        } else {
            let size = buffers.reduce(0) { return $0 + $1.readableBytes }
            var finalBuffer = allocator.buffer(capacity: size)
            for var buffer in buffers {
                finalBuffer.writeBuffer(&buffer)
            }
            return finalBuffer
        }
    }

    /// Compress the readable contents of this byte buffer into another using the compression algorithm specified
    /// - Parameters:
    ///   - buffer: Byte buffer to write compressed data to
    ///   - algorithm: Algorithm to use when compressing
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesnt have enough space to write the compressed data into
    public mutating func compress(to buffer: inout ByteBuffer, with algorithm: CompressionAlgorithm) throws {
        let compressor = algorithm.compressor
        try compressor.deflate(from: &self, to: &buffer)
    }
    
    /// Allocate a new byte buffer and compress this byte buffer into it using the compression algorithm specified
    /// - Parameters:
    ///   - algorithm: Algorithm to use when compressing
    ///   - allocator: Byte buffer allocator used to create new byte buffer
    /// - Returns: the new byte buffer with the compressed data
    public mutating func compress(with algorithm: CompressionAlgorithm, allocator: ByteBufferAllocator = ByteBufferAllocator()) throws -> ByteBuffer {
        let compressor = algorithm.compressor
        var buffer = allocator.buffer(capacity: compressor.maxSize(from: self))
        try compressor.deflate(from: &self, to: &buffer)
        return buffer
    }
    
    /// Decompress one byte buffer from a stream of blocks out of a compressed bytebuffer
    ///
    /// The decompress stream functions work with a stream of data. You create a `NIODecompressor`, call `startStream` on it and then for each
    /// chunk of data in the stream you call `decompressStream`. Once you are complete call `endStream`.
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
    ///  If a `bufferOverflow` error is thrown you can supply a larger buffer and call the `decompressStream` again. Remember though the `ByteBuffer`
    ///  you were writing into from the original call could have some decompressed data in it still so don't throw it away.
    ///
    /// - Parameters:
    ///   - byteBuffer: byte buffer block from a compressed buffer
    ///   - decompressor: Algorithm to use when decompressing
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space to write the decompressed data into
    ///     - `NIOCompression.Error.corruptData` if the input byte buffer is corrupted
    public mutating func decompressStream(to byteBuffer: inout ByteBuffer, with decompressor: NIODecompressor) throws {
        try decompressor.streamInflate(from: &self, to: &byteBuffer)
    }
    
    /// Compress one byte buffer from a stream of blocks into another bytebuffer
    ///
    /// The compress stream functions work with a stream of data. You create a `NIOCompressor`, call `startStream` on it and then for each
    /// chunk of data in the stream you call `compressStream`. Your last block should be called with the `finalised` parameter set to true. Once
    /// you are complete call `endStream`.
    ///  eg
    ///  ```
    ///  let compressor = NIOCompression.Algorithm.gzip.compressor
    ///  try compressor.startStream()
    ///  try inputBuffer1.compressStream(to: &outputBuffer, with: compressor, finalise: false)
    ///  try inputBuffer2.compressStream(to: &outputBuffer, with: compressor, finalise: false)
    ///  ...
    ///  try inputBufferN.compressStream(to: &outputBuffer, with: compressor, finalise: true)
    ///  try decompressor.finishStream()
    ///  ````
    ///
    ///  If a `bufferOverflow` error is thrown you can supply a larger buffer and call the `compressStream` again. Remember though the `ByteBuffer`
    ///  you were writing into from the original call could have some decompressed data in it still so don't throw it away.
    ///
    /// - Parameters:
    ///   - byteBuffer: byte buffer block from a large byte buffer
    ///   - compressor: Algorithm to use when compressing
    ///   - finalise: Is this the last block
    /// - Throws:
    ///     - `NIOCompression.Error.bufferOverflow` if output byte buffer doesn't have enough space to write the compressed data into
    public mutating func compressStream(to byteBuffer: inout ByteBuffer, with compressor: NIOCompressor, finalise: Bool) throws {
        try compressor.streamDeflate(from: &self, to: &byteBuffer, finalise: finalise)
    }
    
    /// A version of compressStream which allocates the ByteBuffer to write into.
    /// - Parameters:
    ///   - compressor: Algorithm to use when compressing
    ///   - finalise: Is this the last block
    ///   - allocator: Byte buffer allocator used to allocate the new `ByteBuffer`
    /// - Returns: `ByteBuffer` containing compressed data
    public mutating func compressStream(with compressor: NIOCompressor, finalise: Bool, allocator: ByteBufferAllocator = ByteBufferAllocator()) throws -> ByteBuffer {
        var byteBuffer = allocator.buffer(capacity: compressor.maxSize(from: self))
        try compressStream(to: &byteBuffer, with: compressor, finalise: finalise)
        return byteBuffer
        
    }
}

extension ByteBuffer {
    /// Process unsafe version of readable data and write out to unsafe writable data of another ByteBuffer
    /// - Parameters:
    ///   - to: Target `ByteBuffer`
    ///   - closure: Process closure
    mutating func withUnsafeProcess(to: inout ByteBuffer, closure: (UnsafeMutableRawBufferPointer, UnsafeMutableRawBufferPointer) throws -> ()) throws {
        try self.withUnsafeMutableReadableBytes { fromBuffer in
            try to.withUnsafeMutableWritableBytes { toBuffer in
                try closure(fromBuffer, toBuffer)
            }
        }
    }
}
