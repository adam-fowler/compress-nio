
/// Compression Algorithm type
public struct CompressionAlgorithm: CustomStringConvertible {
    fileprivate enum AlgorithmEnum: String {
        case gzip
        case deflate
        case rawDeflate
    }
    fileprivate let algorithm: AlgorithmEnum
    
    /// return as String
    public var description: String { return algorithm.rawValue }
    
    /// get compressor
    public func compressor(windowBits: Int = 15) -> NIOCompressor {
        assert((8...15).contains(windowBits), "Window bits must be between the values 8 and 15")
        switch algorithm {
        case .gzip:
            return ZlibCompressor(windowBits: 16 + windowBits)
        case .deflate:
            return ZlibCompressor(windowBits: windowBits)
        case .rawDeflate:
            return ZlibCompressor(windowBits: -windowBits)
        }
    }
    
    /// get decompressor
    public func decompressor(windowBits: Int = 15) -> NIODecompressor {
        assert((8...15).contains(windowBits), "Window bits must be between the values 8 and 15")
        switch algorithm {
        case .gzip:
            return ZlibDecompressor(windowBits: 16 + windowBits)
        case .deflate:
            return ZlibDecompressor(windowBits: windowBits)
        case .rawDeflate:
            return ZlibDecompressor(windowBits: -windowBits)
        }
    }
    
    /// Deflate with gzip header
    public static let gzip = CompressionAlgorithm(algorithm: .gzip)
    /// Deflate with zlib header
    public static let deflate = CompressionAlgorithm(algorithm: .deflate)
    /// Raw deflate without a header
    public static let rawDeflate = CompressionAlgorithm(algorithm: .rawDeflate)
}

