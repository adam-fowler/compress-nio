
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
    /// 
    /// - Parameter windowSize: Window size to use in compressor. Window size if 2^windowSize
    public func compressor(windowSize: Int = 15) -> NIOCompressor {
        assert((9...15).contains(windowSize), "Window bits must be between the values 9 and 15")
        switch algorithm {
        case .gzip:
            return ZlibCompressor(windowBits: 16 + windowSize)
        case .deflate:
            return ZlibCompressor(windowBits: windowSize)
        case .rawDeflate:
            return ZlibCompressor(windowBits: -windowSize)
        }
    }
    
    /// get decompressor
    /// 
    /// - Parameter windowSize: Window size to use in decompressor. Window size if 2^windowSize
    public func decompressor(windowSize: Int = 15) -> NIODecompressor {
        assert((9...15).contains(windowSize), "Window bits must be between the values 9 and 15")
        switch algorithm {
        case .gzip:
            return ZlibDecompressor(windowBits: 16 + windowSize)
        case .deflate:
            return ZlibDecompressor(windowBits: windowSize)
        case .rawDeflate:
            return ZlibDecompressor(windowBits: -windowSize)
        }
    }
    
    /// Deflate with gzip header
    public static let gzip = CompressionAlgorithm(algorithm: .gzip)
    /// Deflate with zlib header
    public static let deflate = CompressionAlgorithm(algorithm: .deflate)
    /// Raw deflate without a header
    public static let rawDeflate = CompressionAlgorithm(algorithm: .rawDeflate)
}

