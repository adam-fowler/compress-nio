
import NIO

/// Errors returned from compression/decompression routines
public struct NIOCompressError: Swift.Error, CustomStringConvertible, Equatable {
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
    public static let bufferOverflow = NIOCompressError(error: .bufferOverflow)
    /// input data is corrupt
    public static let corruptData = NIOCompressError(error: .corruptData)
    /// ran out of memory
    public static let noMoreMemory = NIOCompressError(error: .noMoreMemory)
    /// called `streamFinish`while there is still data to process
    public static let unfinished = NIOCompressError(error: .unfinished)
    /// error internal to system
    public static let internalError = NIOCompressError(error: .internalError)
}


