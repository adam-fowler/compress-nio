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
var compressedBuffer = ByteBufferAllocator().buffer(capacity: knownCompressedSize)
try buffer.compress(to: &compressedBuffer, with: .deflate)
var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: uncompressedSize)
try compressedBuffer.decompress(to: &uncompressedBuffer, with: .deflate)
```
This returns the maximum size of buffer required to write out compressed data for the `deflate` compression algorithm.

If you provide a buffer that is too small a `CompressNIO.bufferOverflow` error is thrown. You will need to provide a larger `ByteBuffer` to complete your operation.

# Streaming
There are situations where you might want to or are required to compress/decompress a block of data in smaller slices. If you have a large file you want to compress it is probably best to load it in smaller slices instead of loading it all into memory in one go. If you are receiving a block of compressed data via HTTP you cannot guarantee it will be delivered in one slice. Swift NIO Compress provides a streaming api to support these situations. 

## Compressing 

There are three methods for doing stream compressing: window, allocating and raw. All of them start with calling `compressor.startStream` and end with calling `compressor.finishStream`. 

#### Window method
For the window method you provide a working buffer for the compressor to use. When you call `compressStream` it compresses into this buffer and when the buffer is full it will call a `process` closure you have provided.
```swift
let compressor = ZlibCompressor(algorithm: .gzip)
var window = ByteBufferAllocator().buffer(capacity: 64*1024)
while var buffer = getData() {
    try buffer.compressStream(with: compressor, window: window, flush: .finish) { buffer in
        // process your compressed data
    }
}
try compressor.reset()
```
#### Allocation method
With the allocating method you leave the compressor to allocate the ByteBuffers for output data. It will calculate the maximum possible size the compressed data could be and allocates that amount of space for each compressed data block. The last compressed block needs to have the `flush` parameter set to `.finish`
```swift
let compressor = ZlibCompressor(algorithm: .gzip)
while var buffer = getData() {
    let flush: CompressNIOFlush = isThisTheFinalBlock ? .finish : .sync
    let compressedBuffer = try buffer.compressStream(with: compressor, flush: flush, allocator: ByteBufferAllocator())
}
try compressor.reset()
```
If you don't know what is your final data block you can always compress an empty `ByteBuffer` with the `flush` set to `.finish` to get your final block. Also note that the flush parameter is set to `.sync` in the loop. This is required otherwise the next `compressStream` cannot successfully estimate its buffer size as there might be buffered data still waiting to be output.

#### Raw method

With this mehod you call the lowest level function and deal with `.bufferOverflow` errors thrown whenever you run out of space in your output buffer. You will need a loop for receiving data and then you will need an inner loop for compressing that data. You call the `compress` until you have no more data to compress. Everytime you receive a `.bufferOverflow` error you have to provide a new output data. Once you have read all the input data you do the same again but with the `flush` parameter set to `.finish`.

## Decompressing

The same three methods window, allocation, raw are available for decompressing streamed data but you don't need to set a `flush` parameter to `.finish` while decompressing which makes everything a little easier. 

