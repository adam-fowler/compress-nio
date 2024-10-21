
import CCompressZlib
import NIOCore

/// Compressor using Zlib
final class ZlibCompressorWrapper: NIOCompressor {
    let algorithm: ZlibAlgorithm
    let configuration: ZlibConfiguration
    var zlibCompressor: ZlibCompressor?
    var window: ByteBuffer?

    init(configuration: ZlibConfiguration, algorithm: ZlibAlgorithm) {
        self.algorithm = algorithm
        self.configuration = configuration
        self.zlibCompressor = nil
        self.window = nil
    }


    func startStream() throws {
        try self.zlibCompressor = .init(algorithm: self.algorithm, configuration: self.configuration)
    }

    func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, flush: CompressNIOFlush) throws {
        guard let compressor = self.zlibCompressor else { throw CompressNIOError.uninitializedStream }
        try compressor.deflate(from: &from, to: &to, flush: flush)
    }

    func finishDeflate(to: inout ByteBuffer) throws {
        guard let compressor = self.zlibCompressor else { throw CompressNIOError.uninitializedStream }
        var emptyByteBuffer = ByteBuffer()
        try compressor.deflate(from: &emptyByteBuffer, to: &to, flush: .finish)
    }

    func finishStream() throws {
        self.zlibCompressor = nil
        self.window?.moveReaderIndex(to: 0)
        self.window?.moveWriterIndex(to: 0)
    }

    func maxSize(from: ByteBuffer) -> Int {
        guard let compressor = self.zlibCompressor else { preconditionFailure("Cannot get maxSize from uninitialized stream") }
        return compressor.maxSize(from: from)
    }

    func resetStream() throws {
        guard let compressor = self.zlibCompressor else { throw CompressNIOError.uninitializedStream }
        try compressor.reset()
    }
}

/// Decompressor using Zlib
final class ZlibDecompressorWrapper: NIODecompressor {
    let algorithm: ZlibAlgorithm
    let windowSize: Int32
    var zlibDecompressor: ZlibDecompressor?
    var window: ByteBuffer?

    init(windowSize: Int32, algorithm: ZlibAlgorithm) {
        self.algorithm = algorithm
        self.windowSize = windowSize
        self.zlibDecompressor = nil
        self.window = nil
    }

    func startStream() throws {
        try self.zlibDecompressor = .init(algorithm: self.algorithm, windowSize: self.windowSize)
    }

    func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        guard let decompressor = self.zlibDecompressor else { throw CompressNIOError.uninitializedStream }
        try decompressor.inflate(from: &from, to: &to)
    }

    func finishStream() throws {
        self.zlibDecompressor = nil
        self.window?.moveReaderIndex(to: 0)
        self.window?.moveWriterIndex(to: 0)
    }

    func resetStream() throws {
        guard let decompressor = self.zlibDecompressor else { throw CompressNIOError.uninitializedStream }
        try decompressor.reset()
    }
}
