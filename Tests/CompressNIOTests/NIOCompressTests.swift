
import NIO
import XCTest
@testable import CompressNIO

class CompressNIOTests: XCTestCase {
    /// Create random buffer
    /// - Parameters:
    ///   - size: size of buffer
    ///   - randomness: how random you want the buffer to be (percentage)
    func createRandomBuffer(size: Int, randomness: Int = 100) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: size)
        let randomness = (randomness * randomness) / 100
        for i in 0..<size {
            let random = Int.random(in: 0..<25600)
            if random < randomness*256 {
                buffer.writeInteger(UInt8(random & 0xff))
            } else {
                buffer.writeInteger(UInt8(i & 0xff))
            }
        }
        return buffer
    }

    func testCompressDecompress(_ algorithm: CompressionAlgorithm, bufferSize: Int = 16000) throws {
        let buffer = createRandomBuffer(size: bufferSize, randomness: 50)
        var bufferToCompress = buffer
        var compressedBuffer = try bufferToCompress.compress(with: algorithm, allocator: ByteBufferAllocator())
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: bufferSize)
        try compressedBuffer.decompress(to: &uncompressedBuffer, with: algorithm)
        XCTAssertEqual(buffer, uncompressedBuffer)
    }

    func streamCompress(_ algorithm: CompressionAlgorithm, buffer: inout ByteBuffer, blockSize: Int = 1024) throws -> ByteBuffer {
        // compress
        let compressor = algorithm.compressor
        try compressor.startStream()
        var compressedBuffer = ByteBufferAllocator().buffer(capacity: 0)

        while buffer.readableBytes > 0 {
            let size = min(blockSize, buffer.readableBytes)
            var slice = buffer.readSlice(length: size)!
            var compressedSlice = try slice.compressStream(with: compressor, finalise: false)
            compressedBuffer.writeBuffer(&compressedSlice)
            compressedSlice.discardReadBytes()
            buffer.discardReadBytes()
        }
        var emptyBuffer = ByteBufferAllocator().buffer(capacity: 0)
        var compressedEmptyBuffer = try emptyBuffer.compressStream(with: compressor, finalise: true)
        compressedBuffer.writeBuffer(&compressedEmptyBuffer)
        try compressor.finishStream()
        return compressedBuffer
    }

    func streamBlockCompress(_ algorithm: CompressionAlgorithm, buffer: inout ByteBuffer, blockSize: Int = 1024) throws -> [ByteBuffer] {
        let compressor = algorithm.compressor
        try compressor.startStream()
        var compressedBuffers: [ByteBuffer] = []

        while buffer.readableBytes > 0 {
            let size = min(blockSize, buffer.readableBytes)
            var slice = buffer.readSlice(length: size)!
            var compressedSlice = try slice.compressStream(with: compressor, finalise: false)
            compressedBuffers.append(compressedSlice)
            compressedSlice.discardReadBytes()
            buffer.discardReadBytes()
        }
        var emptyBuffer = ByteBufferAllocator().buffer(capacity: 0)
        let compressedEmptyBlock = try emptyBuffer.compressStream(with: compressor, finalise: true)
        compressedBuffers.append(compressedEmptyBlock)
        try compressor.finishStream()

        return compressedBuffers
    }

    func streamDecompress(_ algorithm: CompressionAlgorithm, from: inout ByteBuffer, to: inout ByteBuffer, blockSize: Int = 1024) throws {
        // decompress
        let decompressor = algorithm.decompressor
        try decompressor.startStream()
        while from.readableBytes > 0 {
            let size = min(blockSize, from.readableBytes)
            var slice = from.readSlice(length: size)!
            try slice.decompressStream(to: &to, with: decompressor)
            from.discardReadBytes()
        }
        try decompressor.finishStream()
    }

    func streamBlockDecompress(_ algorithm: CompressionAlgorithm, from: [ByteBuffer], to: inout ByteBuffer) throws {
        let decompressor = algorithm.decompressor
        try decompressor.startStream()
        for var buffer in from {
            try buffer.decompressStream(to: &to, with: decompressor)
            buffer.discardReadBytes()
        }
        try decompressor.finishStream()
    }

    func testStreamCompressDecompress(_ algorithm: CompressionAlgorithm, bufferSize: Int = 16396, blockSize: Int = 1024) throws {
        let byteBufferAllocator = ByteBufferAllocator()
        let buffer = createRandomBuffer(size: bufferSize, randomness: 50)

        var bufferToCompress = buffer
        var compressedBuffer = try streamCompress(algorithm, buffer: &bufferToCompress, blockSize: blockSize)

        var uncompressedBuffer = byteBufferAllocator.buffer(capacity: bufferSize+1)
        try streamDecompress(algorithm, from: &compressedBuffer, to: &uncompressedBuffer, blockSize: 1024)

        XCTAssertEqual(buffer, uncompressedBuffer)
    }

    /// testBlockStreamCompressDecompress is different from testStreamCompressDecompress as it decompresses the
    /// slice that were compressed while testStreamCompressDecompress decompresses on a arbitrary block size
    func testBlockStreamCompressDecompress(_ algorithm: CompressionAlgorithm, bufferSize: Int = 16396, blockSize: Int = 1024) throws {
        let byteBufferAllocator = ByteBufferAllocator()
        let buffer = createRandomBuffer(size: bufferSize, randomness: 50)

        // compress
        var bufferToCompress = buffer
        let compressedBuffers = try streamBlockCompress(algorithm, buffer: &bufferToCompress, blockSize: blockSize)

        // decompress
        var uncompressedBuffer = byteBufferAllocator.buffer(capacity: bufferSize+1)
        try streamBlockDecompress(algorithm, from: compressedBuffers, to: &uncompressedBuffer)

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

    func testGZipBlockStreamCompressDecompress() throws {
        try testBlockStreamCompressDecompress(.gzip)
    }

    func testDeflateBlockStreamCompressDecompress() throws {
        try testBlockStreamCompressDecompress(.deflate)
    }

    func testTwoStreamsInParallel() throws {
        let buffer = createRandomBuffer(size: 1024)
        var bufferToCompress = buffer
        let compressor = CompressionAlgorithm.gzip.compressor
        var outputBuffer = ByteBufferAllocator().buffer(capacity: compressor.maxSize(from: bufferToCompress))
        let buffer2 = createRandomBuffer(size: 1024)
        var bufferToCompress2 = buffer2
        let compressor2 = CompressionAlgorithm.gzip.compressor
        var outputBuffer2 = ByteBufferAllocator().buffer(capacity: compressor2.maxSize(from: bufferToCompress2))
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
            var compressedBuffer = try buffer.compress(with: .gzip)
            var outputBuffer = ByteBufferAllocator().buffer(capacity: 1024)
            try compressedBuffer.decompress(to: &outputBuffer, with: .deflate)
            XCTFail("Shouldn't get here")
        } catch let error as CompressNIOError where error == CompressNIOError.corruptData {
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
        } catch let error as CompressNIOError where error == CompressNIOError.bufferOverflow {
        } catch {
            XCTFail()
        }
    }

    func testStreamCompressWithOverflowError() {
        var buffer = createRandomBuffer(size: 1024)
        var outputBuffer = ByteBufferAllocator().buffer(capacity: 16)
        do {
            let compressor = CompressionAlgorithm.gzip.compressor
            try compressor.startStream()
            try buffer.compressStream(to: &outputBuffer, with: compressor, finalise: false)
            XCTFail("Shouldn't get here")
        } catch let error as CompressNIOError where error == CompressNIOError.bufferOverflow {
        } catch {
            XCTFail()
        }
    }

    func testRetryCompressAfterOverflowError() throws {
        let buffer = createRandomBuffer(size: 1024)
        var bufferToCompress = buffer
        let compressor = CompressionAlgorithm.deflate.compressor
        try compressor.startStream()
        var compressedBuffer = ByteBufferAllocator().buffer(capacity: 16)
        do {
            try bufferToCompress.compressStream(to: &compressedBuffer, with: compressor, finalise: true)
            XCTFail("Shouldn't get here")
        } catch let error as CompressNIOError where error == CompressNIOError.bufferOverflow {
            var compressedBuffer2 = try bufferToCompress.compressStream(with: compressor, finalise: true)
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
            var compressedBuffer = try buffer.compress(with: .gzip)
            var outputBuffer = ByteBufferAllocator().buffer(capacity: 512)
            try compressedBuffer.decompress(to: &outputBuffer, with: .gzip)
            XCTFail("Shouldn't get here")
        } catch let error as CompressNIOError where error == CompressNIOError.bufferOverflow {
        } catch {
            XCTFail()
        }
    }

    func testRetryDecompressAfterOverflowError() throws {
        let buffer = createRandomBuffer(size: 1024)
        var bufferToCompress = buffer
        var compressedBuffer = try bufferToCompress.compress(with: .gzip)
        let decompressor = CompressionAlgorithm.gzip.decompressor
        try decompressor.startStream()
        var outputBuffer = ByteBufferAllocator().buffer(capacity: 512)
        do {
            try compressedBuffer.decompressStream(to: &outputBuffer, with: decompressor)
            XCTFail("Shouldn't get here")
        } catch let error as CompressNIOError where error == CompressNIOError.bufferOverflow {
            var outputBuffer2 = ByteBufferAllocator().buffer(capacity: 1024)
            try compressedBuffer.decompressStream(to: &outputBuffer2, with: decompressor)
            outputBuffer.writeBuffer(&outputBuffer2)
            XCTAssertEqual(outputBuffer, buffer)
        }
        try decompressor.finishStream()
    }

    func testAllocatingDecompress() throws {
        let bufferSize = 16000
        // create a buffer that will compress well
        let buffer = createRandomBuffer(size: bufferSize, randomness: 10)
        var bufferToCompress = buffer
        var compressedBuffer = try bufferToCompress.compress(with: .gzip)
        let uncompressedBuffer = try compressedBuffer.decompress(with: .gzip)
        XCTAssertEqual(buffer, uncompressedBuffer)
    }

    func testRandomAllocatingDecompress() throws {
        let bufferSize = 16000
        // create a buffer that will compress well
        let buffer = createRandomBuffer(size: bufferSize, randomness: 100)
        var bufferToCompress = buffer
        var compressedBuffer = try bufferToCompress.compress(with: .gzip)
        let uncompressedBuffer = try compressedBuffer.decompress(with: .gzip)
        XCTAssertEqual(buffer, uncompressedBuffer)
    }

    func testAllocatingStreamCompressDecompress() throws {
        let algorithm: CompressionAlgorithm = .gzip
        let bufferSize = 16000
        let blockSize = 1024
        let buffer = createRandomBuffer(size: bufferSize, randomness: 25)

        // compress
        var bufferToCompress = buffer
        let compressor = algorithm.compressor
        try compressor.startStream()
        var compressedBuffer = ByteBufferAllocator().buffer(capacity: 0)

        while bufferToCompress.readableBytes > 0 {
            if blockSize < bufferToCompress.readableBytes {
                var slice = bufferToCompress.readSlice(length: blockSize)!
                var compressedSlice = try slice.compressStream(with: compressor, finalise: false)
                compressedBuffer.writeBuffer(&compressedSlice)
                compressedSlice.discardReadBytes()
            } else {
                var slice = bufferToCompress.readSlice(length: bufferToCompress.readableBytes)!
                var compressedSlice = try slice.compressStream(with: compressor, finalise: true)
                compressedBuffer.writeBuffer(&compressedSlice)
                compressedSlice.discardReadBytes()
            }
            bufferToCompress.discardReadBytes()
        }
        try compressor.finishStream()

        // decompress
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: bufferSize)
        let decompressor = algorithm.decompressor
        try decompressor.startStream()
        while compressedBuffer.readableBytes > 0 {
            let size = min(512, compressedBuffer.readableBytes)
            var slice = compressedBuffer.readSlice(length: size)!
            var uncompressedBuffer2 = try slice.decompressStream(with: decompressor)
            uncompressedBuffer.writeBuffer(&uncompressedBuffer2)
            compressedBuffer.discardReadBytes()
        }
        try decompressor.finishStream()

        XCTAssertEqual(buffer, uncompressedBuffer)
    }

    func testLZ4Compress() throws {
        try testCompressDecompress(.lz4)
    }

    func testLZ4StreamCompress() throws {
        try testBlockStreamCompressDecompress(.lz4, bufferSize: 256*1024, blockSize: 16*1024)
    }

    func testLZ4AllocatingDecompress() throws {
        let bufferSize = 16000
        // create a buffer that will compress well
        let buffer = createRandomBuffer(size: bufferSize, randomness: 10)
        var bufferToCompress = buffer
        var compressedBuffer = try bufferToCompress.compress(with: .lz4)
        let uncompressedBuffer = try compressedBuffer.decompress(with: .lz4)
        XCTAssertEqual(buffer, uncompressedBuffer)
    }

    func testPerformance(_ algorithm: CompressionAlgorithm, buffer: inout ByteBuffer) throws {
        var compressedBuffer = ByteBufferAllocator().buffer(capacity: algorithm.compressor.maxSize(from: buffer))
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: buffer.readableBytes)

        let now = Date()
        try buffer.compress(to: &compressedBuffer, with: algorithm)
        let compressedSize = compressedBuffer.readableBytes
        try compressedBuffer.decompress(to: &uncompressedBuffer, with: algorithm)
        print("\(algorithm.description): \(-now.timeIntervalSinceNow) \((100*compressedSize)/uncompressedBuffer.readableBytes)")
    }

    func testPerformance() throws {
        let algorithms: [CompressionAlgorithm] = [.gzip, .deflate, .lz4]
        print("Testing performance 20% random")
        let buffer = createRandomBuffer(size: 1*1024*1024, randomness: 20)
        for algo in algorithms {
            var bufferCopy = buffer
            try testPerformance(algo, buffer: &bufferCopy)
        }
        print("Testing performance 40% random")
        let buffer2 = createRandomBuffer(size: 1*1024*1024, randomness: 40)
        for algo in algorithms {
            var bufferCopy = buffer2
            try testPerformance(algo, buffer: &bufferCopy)
        }
        print("Testing performance 70% random")
        let buffer3 = createRandomBuffer(size: 1*1024*1024, randomness: 70)
        for algo in algorithms {
            var bufferCopy = buffer3
            try testPerformance(algo, buffer: &bufferCopy)
        }
    }

    // this block of data doesn't produce a Z_STREAM_END return value
    func testBlockWithoutStreamEnd() throws {
        let data: [UInt8] = [0x1f,0x8b,0x8,0x0,0x0,0x0,0x0,0x0,0x0,0x13,0x62,0x60,0x64,0x62,0x66,0x61,0xe5,0x60,0xe7,0xe0,0xac,0xe7,0xe6,0xe1,0xe5,0xe3,0x17,0x10,0x14,0x12,0x16,0x11,0x15,0x13,0x97,0x90,0x94,0x92,0x96,0x91,0x95,0x93,0x57,0x50,0x54,0x52,0x56,0x51,0x55,0x53,0xd7,0xf0,0xd6,0xd2,0xd6,0xd1,0xe5,0xd1,0x37,0x30,0x34,0x32,0x36,0x31,0x35,0x33,0xb7,0xb0,0xb4,0xb2,0xb6,0xb1,0xb5,0xb3,0x77,0x70,0x74,0x3a,0xfb,0xdd,0xd5,0xcd,0xfd,0xa1,0xa7,0x97,0xb7,0x8f,0x6f,0xa0,0x7f,0x40,0x60,0x50,0x70,0x48,0x68,0x58,0x78,0x44,0x64,0x54,0x74,0x4c,0x6c,0x5c,0x48,0x42,0x22,0x73,0x72,0x4a,0x6a,0x5a,0x7a,0x68,0x66,0x56,0x76,0x4e,0x6e,0x5e,0x7e,0x41,0x61,0x40,0x71,0x49,0x69,0x59,0x79,0x45,0x65,0x60,0x75,0x4d,0x6d,0x5d,0x7d,0x43,0x63,0x53,0x73,0x4b,0x6b,0x5b,0x7b,0x7,0x43,0x57,0x77,0x4f,0x6f,0x5f,0xff,0x84,0x89,0x93,0x26,0x4f,0x99,0x3a,0x6d,0xfa,0x8c,0x99,0xb3,0x7e,0xce,0x99,0x3b,0x6f,0xfe,0x82,0x85,0x8b,0x16,0x2f,0x59,0xba,0x6c,0xf9,0x8a,0x95,0xab,0x14,0xd7,0xac,0x5d,0xb7,0x7e,0xc3,0xc6,0x4d,0x9b,0xb7,0x6c,0xdd,0xb6,0x7d,0xc7,0xce,0x5d,0xbb,0xf7,0xec,0xdd,0xb7,0xff,0xc0,0xc1,0x43,0x87,0x8f,0x1c,0x3d,0x76,0xfc,0xc4,0xc9,0x53,0xa7,0xcf,0x9c,0x3d,0x77,0xfe,0xc2,0xc5,0x4b,0x97,0xaf,0x5c,0xbd,0x76,0xfd,0xc6,0xcd,0x5b,0xb7,0xef,0xdc,0xbd,0x77,0xff,0xc1,0xc3,0x47,0x8f,0x9f,0x3c,0xd5,0x7a,0xfe,0xe2,0xe5,0xab,0xd7,0x6f,0xde,0xbe,0x7b,0xff,0xe1,0xe3,0xa7,0xcf,0x5f,0xbe,0x7e,0xfb,0x3e,0xe5,0xe7,0xaf,0xdf,0x7f,0x16,0xfd,0xfb,0x7f,0x10,0xec,0x7f,0x36,0xa0,0xff,0xb9,0x90,0xfd,0xaf,0x83,0xe1,0x7f,0x4d,0x90,0xff,0xf5,0x90,0xfc,0xcf,0xa,0xf3,0xbf,0xb3,0x8b,0xab,0xdb,0x17,0xf,0xb0,0xff,0xfd,0xe0,0xfe,0x57,0x86,0xf8,0x3f,0x3e,0x21,0x31,0x9,0xec,0xff,0xc,0xb8,0xff,0x8b,0xa0,0xfe,0xaf,0x82,0xf9,0xff,0x30,0xd8,0xff,0x9d,0x20,0xff,0x9f,0x47,0xf2,0xff,0xd9,0xd9,0x60,0xff,0x77,0xc1,0xfd,0xbf,0x1a,0xe4,0x7f,0x6b,0x22,0xfd,0x2f,0x1,0xf4,0xff,0x16,0xb8,0xff,0x9f,0x1,0xfd,0x1f,0x8d,0xe2,0xff,0x1f,0x20,0xff,0xff,0xfd,0xf7,0x9f,0x1,0xbb,0xff,0x31,0xe3,0x5f,0x53,0x4b,0x13,0xd5,0xff,0x56,0xc8,0xfe,0x77,0x7,0xfa,0xbf,0x17,0xe4,0xff,0xfd,0xa8,0xf1,0x8f,0xd5,0xff,0xd6,0x48,0xfe,0x5f,0x0,0x8b,0xff,0x4e,0x58,0xfc,0x73,0xc0,0xe2,0x7f,0x36,0x5a,0xfc,0xaf,0xc6,0x1e,0xff,0xb2,0x40,0xff,0xab,0x43,0xfd,0x3f,0x1,0x11,0xff,0x72,0x90,0xf8,0x17,0x29,0x80,0xf9,0x1f,0x35,0xfe,0x8b,0xa0,0xfe,0x57,0x25,0xde,0xff,0xf0,0xf8,0x5f,0x8c,0xe1,0xff,0x65,0xee,0x48,0xf1,0xbf,0xf,0xe8,0xff,0xd4,0x88,0x1f,0x10,0xff,0xff,0x24,0x1c,0xff,0x70,0xff,0x27,0xa2,0xa6,0xff,0xd9,0x73,0x76,0xe1,0xf3,0xff,0x44,0x12,0xd2,0x3f,0xc8,0xff,0xd,0x10,0xff,0x6f,0xfa,0x64,0x80,0x88,0x7f,0xb9,0xff,0x0,0x0,0x0,0x0,0xff]
        var byteBuffer = ByteBufferAllocator().buffer(capacity: 512)
        byteBuffer.writeBytes(data)
        _ = try byteBuffer.decompress(with: .gzip)
    }
    
    static var allTests : [(String, (CompressNIOTests) -> () throws -> Void)] {
        return [
            ("testGZipCompressDecompress", testGZipCompressDecompress),
            ("testDeflateCompressDecompress", testDeflateCompressDecompress),
            ("testGZipStreamCompressDecompress", testGZipStreamCompressDecompress),
            ("testDeflateStreamCompressDecompress", testDeflateStreamCompressDecompress),
            ("testGZipBlockStreamCompressDecompress", testGZipStreamCompressDecompress),
            ("testDeflateBlockStreamCompressDecompress", testDeflateStreamCompressDecompress),
            ("testTwoStreamsInParallel", testTwoStreamsInParallel),
            ("testDecompressWithWrongAlgorithm", testDecompressWithWrongAlgorithm),
            ("testCompressWithOverflowError", testCompressWithOverflowError),
            ("testStreamCompressWithOverflowError", testStreamCompressWithOverflowError),
            ("testRetryCompressAfterOverflowError", testRetryCompressAfterOverflowError),
            ("testDecompressWithOverflowError", testDecompressWithOverflowError),
            ("testRetryDecompressAfterOverflowError", testRetryDecompressAfterOverflowError),
            ("testAllocatingDecompress", testAllocatingDecompress),
            ("testRandomAllocatingDecompress", testRandomAllocatingDecompress),
            ("testAllocatingStreamCompressDecompress", testAllocatingStreamCompressDecompress),
            ("testLZ4Compress", testLZ4Compress),
            ("testLZ4StreamCompress", testLZ4StreamCompress),
            ("testLZ4AllocatingDecompress", testLZ4AllocatingDecompress),
            ("testPerformance", testPerformance)
        ]
    }
}
