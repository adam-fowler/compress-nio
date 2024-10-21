
import CCompressZlib
import NIOCore

/// Zlib algorithm
public enum ZlibAlgorithm: Sendable {
    case gzip
    case zlib
    case deflate
}

/// Zlib library configuration
public struct ZlibConfiguration: Sendable {
    /// Compression Strategy
    public enum Strategy: Sendable {
        /// default compression strategy
        case `default`
        /// Force Huffman encoding only (no string match)
        case huffmanOnly
        /// Limit match distances to one (run-length encoding). Designed to be
        /// almost as fast as huffmanOnly, but give better compression for PNG
        /// image data
        case rle
        ///  For data produced by a filter. Filtered data consists mostly of small
        /// values with a somewhat random distribution. Force more Huffman coding and
        /// less string matching; it is somewhat intermediate between huffmanOnly
        /// and default
        case filtered
        /// Prevents the use of dynamic Huffman codes, allowing for a simpler
        /// decoder for special applications.
        case fixed

        var zlibValue: Int32 {
            switch self {
            case .default: return Z_DEFAULT_STRATEGY
            case .huffmanOnly: return Z_HUFFMAN_ONLY
            case .rle: return Z_RLE
            case .filtered: return Z_FILTERED
            case .fixed: return Z_FIXED
            }
        }
    }

    /// Base two logarithm of the window size. eg 9 is 512, 10 is 1024
    public var windowSize: Int32
    /// Level of compression. Value between 0 and 9 where 1 is fastest, 9 is best compression and
    /// 0 is no compression
    public var compressionLevel: Int32
    /// Amount of memory to use when compressing. Less memory will mean the compression will take longer
    /// and compression level will be reduced. Value between 1 - 9 where 1 is least amount of memory.
    public var memoryLevel: Int32
    /// Strategy when compressing
    public var strategy: Strategy

    ///  Initialise ZlibConfiguration
    /// - Parameters:
    ///   - windowSize: Base two logarithm of the window size. eg 9 is 512, 10 is 1024
    ///   - compressionLevel: Level of compression. Value between 0 and 9 where 1 is fastest, 9 is best compression and
    ///         0 is no compression
    ///   - memoryLevel: Amount of memory to use when compressing. Less memory will mean the compression will take longer
    ///         and compression level will be reduced. Value between 1 - 9 where 1 is least amount of memory.
    ///   - strategy: Strategy when compressing
    public init(windowSize: Int32 = 15, compressionLevel: Int32 = Z_DEFAULT_COMPRESSION, memoryLevel: Int32 = 8, strategy: Strategy = .default) {
        assert((9...15).contains(windowSize), "Window size must be between the values 9 and 15")
        assert((-1...9).contains(compressionLevel), "Compression level must be between the values 0 and 9, or -1 indicating the default value")
        assert((1...9).contains(memoryLevel), "Compression memory level must be between the values 1 and 9")
        self.windowSize = windowSize
        self.compressionLevel = compressionLevel
        self.memoryLevel = memoryLevel
        self.strategy = strategy
    }
}

/// Compressor using Zlib
public final class ZlibCompressor {
    var stream: z_stream

    /// Initialize Zlib deflate stream for compression
    /// - Parameters:
    ///   - algorithm: Zlib algorithm
    ///   - configuration: Zlib configuration
    ///
    /// - Throws: ``CompressNIOError`` if deflate stream fails to initialize
    public init(algorithm: ZlibAlgorithm, configuration: ZlibConfiguration = .init()) throws {
        var configuration = configuration
        switch algorithm {
        case .gzip:
            configuration.windowSize = 16 + configuration.windowSize
        case .zlib:
            break
        case .deflate:
            configuration.windowSize = -configuration.windowSize
        }

        self.stream = z_stream()
        self.stream.zalloc = nil
        self.stream.zfree = nil
        self.stream.opaque = nil

        let rt = CCompressZlib_deflateInit2(
            &self.stream,
            configuration.compressionLevel,
            Z_DEFLATED,
            configuration.windowSize,
            configuration.memoryLevel,
            configuration.strategy.zlibValue
        )
        switch rt {
        case Z_MEM_ERROR:
            throw CompressNIOError.noMoreMemory
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }

    deinit {
        var stream = self.stream
        deflateEnd(&stream)
    }

    ///  Deflate Zlib stream
    /// - Parameters:
    ///   - from: source bytebuffer
    ///   - to: output bytebuffer
    ///   - flush: whether deflate should flush the output
    /// - Throws: ``CompressNIOError`` if deflate fails
    public func deflate(from: inout ByteBuffer, to: inout ByteBuffer, flush: CompressNIOFlush) throws {
        var bytesRead = 0
        var bytesWritten = 0

        defer {
            to.moveWriterIndex(forwardBy: bytesWritten)
            from.moveReaderIndex(forwardBy: bytesRead)
        }

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            let flag: Int32
            switch flush {
            case .no:
                flag = Z_NO_FLUSH
            case .sync:
                flag = Z_SYNC_FLUSH
            case .finish:
                flag = Z_FINISH
            }

            self.stream.avail_in = UInt32(fromBuffer.count)
            self.stream.next_in = CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            self.stream.avail_out = UInt32(toBuffer.count)
            self.stream.next_out = CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            let rt = CCompressZlib.deflate(&self.stream, flag)
            bytesRead = self.stream.next_in - CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            bytesWritten = self.stream.next_out - CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            switch rt {
            case Z_OK:
                if flush == .finish {
                    throw CompressNIOError.bufferOverflow
                }
            case Z_DATA_ERROR:
                throw CompressNIOError.corruptData
            case Z_BUF_ERROR:
                throw CompressNIOError.bufferOverflow
            case Z_MEM_ERROR:
                throw CompressNIOError.noMoreMemory
            case Z_STREAM_END:
                break
            default:
                throw CompressNIOError.internalError
            }
        }
    }

    public func maxSize(from: ByteBuffer) -> Int {
        // deflateBound() provides an upper limit on the number of bytes the input can
        // compress to. We add 5 bytes to handle the fact that Z_SYNC_FLUSH will append
        // an empty stored block that is 5 bytes long.
        // From zlib docs (https://www.zlib.net/manual.html)
        // "If the parameter flush is set to Z_SYNC_FLUSH, all pending output is flushed to the output buffer and the output is
        // aligned on a byte boundary, so that the decompressor can get all input data available so far. (In particular avail_in
        // is zero after the call if enough output space has been provided before the call.) Flushing may degrade compression for
        // some compression algorithms and so it should be used only when necessary. This completes the current deflate block and
        // follows it with an empty stored block that is three bits plus filler bits to the next byte, followed by four bytes
        // (00 00 ff ff)."
        let bufferSize = Int(CCompressZlib.deflateBound(&self.stream, UInt(from.readableBytes)))
        return bufferSize + 6
    }

    /// Reset deflate stream
    /// - Throws: ``CompressNIOError`` if reset fails
    public func reset() throws {
        let rt = deflateReset(&self.stream)
        switch rt {
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }
}

/// Decompressor using Zlib
public final class ZlibDecompressor {
    var stream: z_stream

    /// Initialize Zlib inflate stream for decompression
    /// - Parameters:
    ///   - algorithm: Zlib algorithm
    ///   - windowSize: Window size used to inflate stream 8...15
    ///
    /// - Throws: ``CompressNIOError`` if inflate stream fails to initialize
    public init(algorithm: ZlibAlgorithm, windowSize: Int32 = 15) throws {
        var windowSize = windowSize
        switch algorithm {
        case .gzip:
            windowSize = 16 + windowSize
        case .zlib:
            break
        case .deflate:
            windowSize = -windowSize
        }

        self.stream = z_stream()
        // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
        self.stream.zalloc = nil
        self.stream.zfree = nil
        self.stream.opaque = nil
        self.stream.avail_in = 0
        self.stream.next_in = nil

        let rt = CCompressZlib_inflateInit2(&self.stream, windowSize)
        switch rt {
        case Z_MEM_ERROR:
            throw CompressNIOError.noMoreMemory
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }

    deinit {
        var stream = self.stream
        inflateEnd(&stream)
    }

    /// Inflate Zlib stream
    /// - Parameters:
    ///   - from: source bytebuffer
    ///   - to: output bytebuffer
    ///
    /// - Throws: ``CompressNIOError`` if inflate fails
    public func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        var bytesRead = 0
        var bytesWritten = 0

        defer {
            from.moveReaderIndex(forwardBy: bytesRead)
            to.moveWriterIndex(forwardBy: bytesWritten)
        }

        try from.withUnsafeProcess(to: &to) { fromBuffer, toBuffer in
            self.stream.avail_in = UInt32(fromBuffer.count)
            self.stream.next_in = CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            self.stream.avail_out = UInt32(toBuffer.count)
            self.stream.next_out = CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            let rt = CCompressZlib.inflate(&self.stream, Z_NO_FLUSH)

            bytesRead = self.stream.next_in - CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            bytesWritten = self.stream.next_out - CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            switch rt {
            case Z_OK:
                if self.stream.avail_out == 0 {
                    throw CompressNIOError.bufferOverflow
                }
            case Z_BUF_ERROR:
                if self.stream.avail_in == 0 {
                    throw CompressNIOError.inputBufferOverflow
                } else {
                    throw CompressNIOError.bufferOverflow
                }
            case Z_DATA_ERROR:
                throw CompressNIOError.corruptData
            case Z_MEM_ERROR:
                throw CompressNIOError.noMoreMemory
            case Z_STREAM_END:
                break
            default:
                throw CompressNIOError.internalError
            }
        }
    }

    /// Reset Zlib inflate stream 
    /// - Throws: ``CompressNIOError`` if reset fails
    public func reset() throws {
        // inflateReset is a more optimal than calling finish and then start
        let rt = inflateReset(&self.stream)
        switch rt {
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }
}
