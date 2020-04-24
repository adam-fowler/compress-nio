# Swift NIO Compress

A compression library for Swift NIO ByteBuffers.

# Compress and Decompress
Swift NIO Compress contains a number of methods for compressing and decompressing `ByteBuffers`. A simple usage would be 
```swift
var compressedBuffer = buffer.compress(with: .gzip)
var uncompressedBuffer = buffer.decompress(with: .gzip)
```
These methods allocate a new `ByteBuffer` for you. The `decompress` method can allocate multiple `ByteBuffers` while it is uncompressing depending on how well compressed the original `ByteBuffer` is. It is preferable to know in advance the size of buffer you need and allocate it yourself just the once and use the following functions.
```swift
let uncompressedSize = buffer.readableBytes
let maxCompressedSize = CompressionAlgorithm.deflate.compressor.maxSize(from:buffer)
var compressedBuffer = ByteBufferAllocator().buffer(capacity: maxCompressedSize)
try buffer.compress(to: &compressedBuffer, with: .deflate)
var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: uncompressedSize)
try compressedBuffer.decompress(to: &uncompressedBuffer, with: .deflate)
```
In the above example there is a call to a function `CompressionAlgorithm.deflate.compressor.maxSize(from:buffer)`. This returns the maximum size of buffer required to write out compressed data for the `deflate` compression algorithm.

If you provide a buffer that is too small a `NIOCompress.bufferOverflow` error is thrown. You will need to provide a larger `ByteBuffer` to complete your operation.

# Streaming
There are situations where you might want to or are required to compress/decompress a block of data in smaller slices. If you have a large file you want to compress it is probably best to load it in smaller slices instead of loading it all into memory in one go. If you are receiving a block of compressed data via HTTP you cannot guarantee it will be delivered in one slice. Swift NIO Compress provides a streaming api to support these situations. 

If you are compressing first you create a `NIOCompressor` and call `startStream` then for each segment of the larger block of data you receive you call `streamCompress`. Once you are done you call `finishStream`. Decompression has a similar pattern. In a similar way to the one shot methods above the stream methods provide both versions that create a new `ByteBuffer` and versions you supply an already allocated buffer. 
```swift
let compressedBuffer = ByteBufferAllocator().buffer(capacity: sizeOfCompressedData)
let compressor = CompressionAlgorithm.gzip.compressor
try compressor.startStream()
while buffer = getSlice() {
    try buffer.compressStream(to: &compressedBuffer, with: compressor, finalise: isLastBuffer)
}
try compressor.finishStream()
```
This will compress data you are receiving via `getSlice` and output all of it into `compressedBuffer`. The last slice you compress you need to call with the `finalise` parameter set to true. If you don't know at that point that you have just received your last slice you can call at the end `compressStream` on an empty `ByteBuffer` like this
```swift
var emptyBuffer = ByteBufferAllocator().buffer(capacity: 0)
try emptyBuffer.compressStream(to: &compressedBuffer, with: compressor, finalise: true)
```

While streaming if the buffer you are compressing into is too small a `NIOCompress.bufferOverflow` error will be thrown. In this situation you can provide another `ByteBuffer` to receive the remains of the data. Data may have already been decompressed into your original buffer so don't throw away the original.
