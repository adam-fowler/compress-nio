
/// Compression Algorithm type
public struct CompressionAlgorithm: CustomStringConvertible {
    fileprivate enum AlgorithmEnum {
        case gzip(windowSize: Int)
        case zlib(windowSize: Int)
        case deflate(windowSize: Int)
    }
    fileprivate let algorithm: AlgorithmEnum
    
    /// return as String
    public var description: String {
        switch algorithm {
        case .gzip: return "gzip"
        case .zlib: return "zlib"
        case .deflate: return "deflate"
        }
    }
    
    /// get compressor
    /// 
    /// - Parameter windowSize: Window size to use in compressor. Window size is 2^windowSize
    public var compressor: NIOCompressor {
        switch algorithm {
        case .gzip(let windowSize):
            return ZlibCompressor(windowSize: 16 + windowSize)
        case .zlib(let windowSize):
            return ZlibCompressor(windowSize: windowSize)
        case .deflate(let windowSize):
            return ZlibCompressor(windowSize: -windowSize)
        }
    }
    
    /// get decompressor
    /// 
    /// - Parameter windowSize: Window size to use in decompressor. Window size is 2^windowSize
    public var decompressor: NIODecompressor {
        //assert((9...15).contains(windowSize), "Window size must be between the values 9 and 15")
        switch algorithm {
        case .gzip(let windowSize):
            return ZlibDecompressor(windowSize: 16 + windowSize)
        case .zlib(let windowSize):
            return ZlibDecompressor(windowSize: windowSize)
        case .deflate(let windowSize):
            return ZlibDecompressor(windowSize: -windowSize)
        }
    }
    
    /// Deflate with gzip header
    public static func gzip(windowSize: Int = 15) -> CompressionAlgorithm {
        assert((9...15).contains(windowSize), "Window size must be between the values 9 and 15")
        return CompressionAlgorithm(algorithm: .gzip(windowSize: windowSize))
    }
    /// Deflate with zlib header
    public static func zlib(windowSize: Int = 15) -> CompressionAlgorithm {
        assert((9...15).contains(windowSize), "Window size must be between the values 9 and 15")
        return CompressionAlgorithm(algorithm: .zlib(windowSize: windowSize))
    }
    /// Raw deflate without a header
    public static func deflate(windowSize: Int = 15) -> CompressionAlgorithm {
        assert((9...15).contains(windowSize), "Window size must be between the values 9 and 15")
        return CompressionAlgorithm(algorithm: .deflate(windowSize: windowSize))
    }
}

