# Compress NIO

A compression library for Swift NIO ByteBuffers.

# Compress and Decompress
Compress NIO contains a number of methods for compressing and decompressing `ByteBuffers`. A simple usage would be 
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

If you provide a buffer that is too small a `CompressNIO.bufferOverflow` error is thrown. You will need to provide a larger `ByteBuffer` to complete your operation.

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

While streaming if the buffer you are compressing into is too small a `CompressNIO.bufferOverflow` error will be thrown. In this situation you can provide another `ByteBuffer` to receive the remains of the data. Data may have already been decompressed into your original buffer so don't throw away the original.

It doesn't appear to be documented but zlib doesn't always cope with slices smaller than 1K so try to keep your slices to greater than 1K when decompressing a stream.

# LZ4

As well as the zlib gzip and deflate algorithms CompressNIO provides LZ4 support. LZ4 has been included because of its different characteristics to the zlib algorithms. LZ4 is considerably faster, up to 10 to 20 times faster. With that speed increase though comes a cost in compression quality and flexibility. LZ4 does not compress anywhere near as well and its streaming support is limited. Below is a table comparing the performance characteristics of gzip and LZ4 compressing and decompressing 10MB buffers of varying complexity.

gzip compression ratio | gzip speed | LZ4 compression ratio | LZ4 speed
-----------------------|------------|-----------------------|----------
12%                    |290ms       |24%                    |19ms
26%                    |517ms       |43%                    |23ms
42%                    |637ms       |62%                    |24ms
68%                    |595ms       |87%                    |24ms
90%                    |402ms       |99%                    |12ms

The reduction in flexibility comes from LZ4's inability to decompress arbitrary sized slices from a compressed buffer. Decompression has to run on the block boundaries generated at compression time. If you compressed a buffer in multiple streamed blocks you need to decompress each of those compressed blocks separately to decompress successfully. Similarly a buffer compressed in one go will not decompress as a series of streamed slices.

Finally if LZ4 runs out of space while compressing or decompressing unlike the zlib algorithms all the work it has done so far is thrown away and you need to restart the process again with a bigger buffer.


