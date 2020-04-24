
/// Compression Algorithm type
public struct CompressionAlgorithm: CustomStringConvertible {
    fileprivate enum AlgorithmEnum: String {
        case gzip
        case deflate
        case lz4
    }
    fileprivate let algorithm: AlgorithmEnum
    
    /// return as String
    public var description: String { return algorithm.rawValue }
    
    /// get compressor
    public var compressor: NIOCompressor {
        switch algorithm {
        case .gzip:
            return ZlibCompressor(windowBits: 16 + 15)
        case .deflate:
            return ZlibCompressor(windowBits: 15)
        case .lz4:
            return LZ4Compressor()
        }
    }
    
    /// get decompressor
    public var decompressor: NIODecompressor {
        switch algorithm {
        case .gzip:
            return ZlibDecompressor(windowBits: 16 + 15)
        case .deflate:
            return ZlibDecompressor(windowBits: 15)
        case .lz4:
            return LZ4Decompressor()
        }
    }
    
    public static let gzip = CompressionAlgorithm(algorithm: .gzip)
    public static let deflate = CompressionAlgorithm(algorithm: .deflate)
    public static let lz4 = CompressionAlgorithm(algorithm: .lz4)
}

