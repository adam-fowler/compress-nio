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

## Compressing 

There are three methods for doing stream compressing: window, allocating and raw. All of them start with calling `compressor.startStream` and end with calling `compressor.finishStream`. 

#### Window method
For the window method you provide a working buffer for the compressor to use. When you call `compressStream` it compresses into this buffer and when the buffer is full it will call a `process` closure you have provided.
```swift
let compressor = CompressionAlgorithm.gzip.compressor
compressor.window = ByteBufferAllocator().buffer(capacity: 64*1024)
try compressor.startStream()
try compressor.compressStream(with: compressor, flush: .finish) { buffer in
    // process your compressed data
}
try compressor.finishStream()
```
#### Allocation method
With the allocating method you leave the compressor to allocate the ByteBuffers for output data. It will calculate the maximum possible size the compressed data could be and allocates that amount of space for each compressed data block. The last compressed block needs to have the `flush` parameter set to `.finish`
```swift
let compressor = CompressionAlgorithm.gzip.compressor
try compressor.startStream()
while var buffer = getData() {
    let flush: CompressNIOFlush = isThisTheFinalBlock ? .finish : .sync
    let compressedBuffer = try buffer.compressStream(with: compressor, flush: flush, allocator: ByteBufferAllocator())
}
try compressor.finishStream()
```
If you don't know when you are receiving your last data block you can always compress an empty `ByteBuffer` with the `flush` set to `.finish` to get your final block. Also note that the flush parameter is set to `.sync` in the loop. This is required otherwise the next `compressStream` cannot successfully estimate its buffer size as there might be buffered data still waiting to be output.
#### Raw method
With this mehod you call the lowest level function and deal with `.bufferOverflow` errors thrown whenever you run out of space in your output buffer. You will need a loop for receiving data and then you will need an inner loop for compressing that data. You call the `compress` until you have no more data to compress. Everytime you receive a `.bufferOverflow` error you have to provide a new output data. Once you have read all the input data you do the same again but with the `flush` parameter set to `.finish`.

## Decompressing

The same three methods window, allocation, raw are available for decompressing streamed data but you don't need to set a `flush` parameter to `.finish` while decompressing which makes everything a little easier. 

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


