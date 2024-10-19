
import CCompressZlib
import NIOCore

/// Compressor using Zlib
final class ZlibCompressorWrapper: NIOCompressor {
    var zlibCompressor: ZlibCompressor

    init(configuration: ZlibConfiguration, algorithm: ZlibAlgorithm) {
        self.zlibCompressor = .init(algorithm: algorithm, configuration: configuration)
        self.window = nil
    }

    var window: ByteBuffer?

    func startStream() throws {
        try self.zlibCompressor.startStream()
    }

    func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, flush: CompressNIOFlush) throws {
        try self.zlibCompressor.streamDeflate(from: &from, to: &to, flush: flush)
    }

    func finishDeflate(to: inout ByteBuffer) throws {
        try self.zlibCompressor.finishDeflate(to: &to)
    }

    func finishStream() throws {
        try self.zlibCompressor.finishStream()
        self.window?.moveReaderIndex(to: 0)
        self.window?.moveWriterIndex(to: 0)
    }

    func maxSize(from: ByteBuffer) -> Int {
        self.zlibCompressor.maxSize(from: from)
    }

    func resetStream() throws {
        try self.zlibCompressor.resetStream()
    }
}

/// Decompressor using Zlib
final class ZlibDecompressorWrapper: NIODecompressor {
    var zlibDecompressor: ZlibDecompressor

    init(windowSize: Int32, algorithm: ZlibAlgorithm) {
        self.zlibDecompressor = .init(algorithm: algorithm, windowSize: windowSize)
        self.window = nil
    }

    var window: ByteBuffer?

    func startStream() throws {
        try self.zlibDecompressor.startStream()
    }

    func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        try self.zlibDecompressor.streamInflate(from: &from, to: &to)
    }

    func finishStream() throws {
        try self.zlibDecompressor.finishStream()
    }

    func resetStream() throws {
        try self.zlibDecompressor.resetStream()
    }
}
