
import NIO

public enum NIOCompression {
    
    /// Compression Algorithm type
    public struct Algorithm: CustomStringConvertible, Equatable {
        fileprivate enum AlgorithmEnum: String {
            case gzip
            case deflate
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
            }
        }
        
        /// get decompressor
        public var decompressor: NIODecompressor {
            switch algorithm {
            case .gzip:
                return ZlibDecompressor(windowBits: 16 + 15)
            case .deflate:
                return ZlibDecompressor(windowBits: 15)
            }
        }
        
        public static let gzip = Algorithm(algorithm: .gzip)
        public static let deflate = Algorithm(algorithm: .deflate)
    }
    
    /// Errors returned from compression/decompression routines
    public struct Error: Swift.Error, CustomStringConvertible, Equatable {
        fileprivate enum ErrorEnum: String {
            case bufferOverflow
            case corruptData
            case noMoreMemory
            case unfinished
            case internalError
        }
        fileprivate let error: ErrorEnum
        
        /// return as String
        public var description: String { return error.rawValue }
        
        /// output buffer is too small
        public static let bufferOverflow = Error(error: .bufferOverflow)
        /// input data is corrupt
        public static let corruptData = Error(error: .corruptData)
        /// ran out of memory
        public static let noMoreMemory = Error(error: .noMoreMemory)
        /// called `streamFinish`while there is still data to process
        public static let unfinished = Error(error: .unfinished)
        /// error internal to system
        public static let internalError = Error(error: .internalError)
    }
}


