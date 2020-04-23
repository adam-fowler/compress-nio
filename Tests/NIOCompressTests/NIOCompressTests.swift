
import NIO
import XCTest
@testable import NIOCompress

class NIOCompressTests: XCTestCase {
    func createOrderedBuffer(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        for _ in 0..<size {
            buffer.writeInteger(UInt8(size&0xff))
        }
        return buffer
    }
    
    func createRandomBuffer(size: Int) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        for _ in 0..<size {
            buffer.writeInteger(UInt8.random(in: UInt8.min...UInt8.max))
        }
        return buffer
    }
    
    func testCompressDecompress(_ algorithm: NIOCompression.Algorithm) throws {
        let bufferSize = 16000
        let buffer = createRandomBuffer(size: bufferSize)
        var bufferToCompress = buffer
        var compressedBuffer = try bufferToCompress.compress(with: algorithm, allocator: ByteBufferAllocator())
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: bufferSize)
        try compressedBuffer.decompress(to: &uncompressedBuffer, with: algorithm)
        XCTAssertEqual(buffer, uncompressedBuffer)
    }
    
    func testStreamCompressDecompress(_ algorithm: NIOCompression.Algorithm) throws {
        let byteBufferAllocator = ByteBufferAllocator()
        let bufferSize = 16000
        let blockSize = 1024
        let buffer = createRandomBuffer(size: bufferSize)
        
        // compress
        var compressedBuffers: [ByteBuffer] = []
        var bufferToCompress = buffer
        let compressor = algorithm.compressor
        try compressor.startStream()
        while bufferToCompress.readableBytes > 0 {
            if blockSize < bufferToCompress.readableBytes {
                var slice = bufferToCompress.readSlice(length: blockSize)!
                compressedBuffers.append(try slice.compressStream(with: compressor, finalise: false, allocator: byteBufferAllocator))
            } else {
                var slice = bufferToCompress.readSlice(length: bufferToCompress.readableBytes)!
                compressedBuffers.append(try slice.compressStream(with: compressor, finalise: true, allocator: byteBufferAllocator))
            }
        }
        try compressor.finishStream()

        // decompress
        var uncompressedBuffer = byteBufferAllocator.buffer(capacity: bufferSize)
        let decompressor = algorithm.decompressor
        try decompressor.startStream()
        for i in 0..<compressedBuffers.count {
            try compressedBuffers[i].decompressStream(to: &uncompressedBuffer, with: decompressor)
        }
        try decompressor.finishStream()

        XCTAssertEqual(buffer, uncompressedBuffer)
    }
    
    func testGZipCompressDecompress() throws {
        try testCompressDecompress(.gzip)
    }
    
    func testDeflateCompressDecompress() throws {
        try testCompressDecompress(.deflate)
    }
    
    func testGZipStreamCompressDecompress() throws {
        try testStreamCompressDecompress(.gzip)
    }
    
    func testDeflateStreamCompressDecompress() throws {
        try testStreamCompressDecompress(.deflate)
    }
    
    func testTwoStreamsInParallel() throws {
        let buffer = createRandomBuffer(size: 1024)
        var bufferToCompress = buffer
        let compressor = NIOCompression.Algorithm.gzip.compressor
        var outputBuffer = ByteBufferAllocator().buffer(capacity: compressor.deflateBound(from: bufferToCompress))
        let buffer2 = createRandomBuffer(size: 1024)
        var bufferToCompress2 = buffer2
        let compressor2 = NIOCompression.Algorithm.gzip.compressor
        var outputBuffer2 = ByteBufferAllocator().buffer(capacity: compressor2.deflateBound(from: bufferToCompress2))
        try compressor.startStream()
        try compressor2.startStream()
        try bufferToCompress.compressStream(to: &outputBuffer, with: compressor, finalise: true)
        try bufferToCompress2.compressStream(to: &outputBuffer2, with: compressor2, finalise: true)
        try compressor.finishStream()
        try compressor2.finishStream()
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: 1024)
        try outputBuffer.decompress(to: &uncompressedBuffer, with: .gzip)
        XCTAssertEqual(buffer, uncompressedBuffer)
        var uncompressedBuffer2 = ByteBufferAllocator().buffer(capacity: 1024)
        try outputBuffer2.decompress(to: &uncompressedBuffer2, with: .gzip)
        XCTAssertEqual(buffer2, uncompressedBuffer2)
    }
    
    func testDecompressWithWrongAlgorithm() {
        var buffer = createRandomBuffer(size: 1024)
        do {
            var compressedBuffer = try buffer.compress(with: .gzip, allocator: ByteBufferAllocator())
            var outputBuffer = ByteBufferAllocator().buffer(capacity: 1024)
            try compressedBuffer.decompress(to: &outputBuffer, with: .deflate)
            XCTFail("Shouldn't get here")
        } catch let error as NIOCompression.Error where error == NIOCompression.Error.corruptData {
        } catch {
            XCTFail()
        }
    }
    
    func testCompressWithOverflowError() {
        var buffer = createRandomBuffer(size: 1024)
        var outputBuffer = ByteBufferAllocator().buffer(capacity: 16)
        do {
            try buffer.compress(to: &outputBuffer, with: .gzip)
            XCTFail("Shouldn't get here")
        } catch let error as NIOCompression.Error where error == NIOCompression.Error.bufferOverflow {
        } catch {
            XCTFail()
        }
    }
    
    func testStreamCompressWithOverflowError() {
        var buffer = createRandomBuffer(size: 1024)
        var outputBuffer = ByteBufferAllocator().buffer(capacity: 16)
        do {
            let compressor = NIOCompression.Algorithm.gzip.compressor
            try compressor.startStream()
            try buffer.compressStream(to: &outputBuffer, with: compressor, finalise: false)
            XCTFail("Shouldn't get here")
        } catch let error as NIOCompression.Error where error == NIOCompression.Error.bufferOverflow {
        } catch {
            XCTFail()
        }
    }
    
    func testRetryCompressAfterOverflowError() throws {
        let buffer = createRandomBuffer(size: 1024)
        var bufferToCompress = buffer
        let compressor = NIOCompression.Algorithm.deflate.compressor
        try compressor.startStream()
        var compressedBuffer = ByteBufferAllocator().buffer(capacity: 16)
        do {
            try bufferToCompress.compressStream(to: &compressedBuffer, with: compressor, finalise: true)
            XCTFail("Shouldn't get here")
        } catch let error as NIOCompression.Error where error == NIOCompression.Error.bufferOverflow {
            var compressedBuffer2 = try bufferToCompress.compressStream(with: compressor, finalise: true, allocator: ByteBufferAllocator())
            try compressor.finishStream()
            compressedBuffer.writeBuffer(&compressedBuffer2)
            var outputBuffer = ByteBufferAllocator().buffer(capacity: 1024)
            try compressedBuffer.decompress(to: &outputBuffer, with: .deflate)
            XCTAssertEqual(outputBuffer, buffer)
        }
    }

    func testDecompressWithOverflowError() {
        var buffer = createRandomBuffer(size: 1024)
        do {
            var compressedBuffer = try buffer.compress(with: .gzip, allocator: ByteBufferAllocator())
            var outputBuffer = ByteBufferAllocator().buffer(capacity: 512)
            try compressedBuffer.decompress(to: &outputBuffer, with: .gzip)
            XCTFail("Shouldn't get here")
        } catch let error as NIOCompression.Error where error == NIOCompression.Error.bufferOverflow {
        } catch {
            XCTFail()
        }
    }
    
    func testRetryDecompressAfterOverflowError() throws {
        let buffer = createRandomBuffer(size: 1024)
        var bufferToCompress = buffer
        var compressedBuffer = try bufferToCompress.compress(with: .gzip, allocator: ByteBufferAllocator())
        let decompressor = NIOCompression.Algorithm.gzip.decompressor
        try decompressor.startStream()
        var outputBuffer = ByteBufferAllocator().buffer(capacity: 512)
        do {
            try compressedBuffer.decompressStream(to: &outputBuffer, with: decompressor)
            XCTFail("Shouldn't get here")
        } catch let error as NIOCompression.Error where error == NIOCompression.Error.bufferOverflow {
            var outputBuffer2 = ByteBufferAllocator().buffer(capacity: 1024)
            try compressedBuffer.decompressStream(to: &outputBuffer2, with: decompressor)
            outputBuffer.writeBuffer(&outputBuffer2)
            XCTAssertEqual(outputBuffer, buffer)
        }
        try decompressor.finishStream()
    }
    
    static var allTests : [(String, (NIOCompressTests) -> () throws -> Void)] {
        return [
            ("testGZipCompressDecompress", testGZipCompressDecompress),
            ("testDeflateCompressDecompress", testDeflateCompressDecompress),
            ("testGZipStreamCompressDecompress", testGZipStreamCompressDecompress),
            ("testDeflateStreamCompressDecompress", testDeflateStreamCompressDecompress),
            ("testTwoStreamsInParallel", testTwoStreamsInParallel),
            ("testDecompressWithWrongAlgorithm", testDecompressWithWrongAlgorithm),
            ("testCompressWithOverflowError", testCompressWithOverflowError),
            ("testStreamCompressWithOverflowError", testStreamCompressWithOverflowError),
            ("testRetryCompressAfterOverflowError", testRetryCompressAfterOverflowError),
            ("testDecompressWithOverflowError", testDecompressWithOverflowError),
            ("testRetryDecompressAfterOverflowError", testRetryDecompressAfterOverflowError),
        ]
    }
}
