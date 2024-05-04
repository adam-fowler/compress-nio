
/// Compression Algorithm type
public struct CompressionAlgorithm: CustomStringConvertible, Sendable {
    fileprivate enum AlgorithmEnum: Sendable {
        case gzip(configuration: ZlibConfiguration)
        case zlib(configuration: ZlibConfiguration)
        case deflate(configuration: ZlibConfiguration)
    }

    fileprivate let algorithm: AlgorithmEnum

    /// return as String
    public var description: String {
        switch self.algorithm {
        case .gzip: return "gzip"
        case .zlib: return "zlib"
        case .deflate: return "deflate"
        }
    }

    /// get compressor
    ///
    /// - Parameter windowSize: Window size to use in compressor. Window size is 2^windowSize
    public var compressor: NIOCompressor {
        switch self.algorithm {
        case .gzip(var configuration):
            configuration.windowSize = 16 + configuration.windowSize
            return ZlibCompressor(configuration: configuration)
        case .zlib(let configuration):
            return ZlibCompressor(configuration: configuration)
        case .deflate(var configuration):
            configuration.windowSize = -configuration.windowSize
            return ZlibCompressor(configuration: configuration)
        }
    }

    /// get decompressor
    ///
    /// - Parameter windowSize: Window size to use in decompressor. Window size is 2^windowSize
    public var decompressor: NIODecompressor {
        switch self.algorithm {
        case .gzip(let configuration):
            return ZlibDecompressor(windowSize: 16 + configuration.windowSize)
        case .zlib(let configuration):
            return ZlibDecompressor(windowSize: configuration.windowSize)
        case .deflate(let configuration):
            return ZlibDecompressor(windowSize: -configuration.windowSize)
        }
    }

    /// Deflate with gzip header
    public static func gzip(configuration: ZlibConfiguration = .init()) -> CompressionAlgorithm {
        return CompressionAlgorithm(algorithm: .gzip(configuration: configuration))
    }

    /// Deflate with zlib header
    public static func zlib(configuration: ZlibConfiguration = .init()) -> CompressionAlgorithm {
        return CompressionAlgorithm(algorithm: .zlib(configuration: configuration))
    }

    /// Raw deflate without a header
    public static func deflate(configuration: ZlibConfiguration = .init()) -> CompressionAlgorithm {
        return CompressionAlgorithm(algorithm: .deflate(configuration: configuration))
    }
}
