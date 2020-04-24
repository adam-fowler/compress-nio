# Swift NIO Compress

A compression library for Swift NIO Bytebuffers.

# Usage
Swift NIO Compress contains a number of methods for compressing and decompressing `ByteBuffers`. A simple usage would be 
```
var compressedBuffer = buffer.compress(with: .gzip)
var uncompressedBuffer = buffer.uncompress(with: .gzip)
```
These methods allocate a new `ByteBuffer` for you and the uncompress can allocate a number of `ByteBuffers` while it is uncompressing. It if preferable to know in advance the size of buffer you need and allocate it yourself and use the following functions.
```
let uncompressedSize = buffer.readableBytes
var compressedBuffer = ByteBufferAllocator().buffer(capacity: CompressionAlgorithm.deflate.compressor.maxSize(from:buffer))
try buffer.compress(to: &compressedBuffer, with: .deflate)
var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: uncompressedSize)
try compressedBuffer.decompress(to: &uncompressedBuffer, with: .deflate)
```
In the above example there is a call to a function `CompressionAlgorithm.gzip.compressor.maxSize(from:buffer)`. This returns the maximum size of buffer required to write out compressed data for the deflate algorithm.

If you provide a buffer that is too small a `NIOCompress.bufferOverflow` error is thrown. You will need to provide a larger `ByteBuffer` to complete your operation.
