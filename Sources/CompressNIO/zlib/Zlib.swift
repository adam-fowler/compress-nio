
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
    /// Compression Level. Lower the value is the faster the compression, higher the value is
    /// better the compression
    public enum CompressionLevel: Int32 {
        case noCompression = 0
        case fastestCompression = 1
        case compressionLevel2 = 2
        case compressionLevel3 = 3
        case compressionLevel4 = 4
        case compressionLevel5 = 5
        case compressionLevel6 = 6
        case compressionLevel7 = 7
        case compressionLevel8 = 8
        case bestCompression = 9
        case defaultCompressionLevel = -1
    }

    /// How much memory is allocated for internal compression state, the smaller the amount
    /// of memory the slower compression is. Memory allocated is (1 << (memLevel+9))
    public enum MemoryLevel: Int32 {
        case memory1k = 1
        case memory2K = 2
        case memory4K = 3
        case memory8K = 4
        case memory16K = 5
        case memory32K = 6
        case memory64K = 7
        case memory128K = 8
        case memory256K = 9

        public static var defaultMemoryLevel: Self { .memory128K }
    }

    /// How much memory is allocated for the compression/history window. Larger sizes produce
    /// better compression. Buffer size is (1 << (windowBits+2))
    public enum WindowSize: Int32 {
        case window2k = 9
        case window4k = 10
        case window8k = 11
        case window16k = 12
        case window32k = 13
        case window64k = 14
        case window128k = 15

        public static var defaultWindowSize: Self { .window128k }
    }

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
    ///   - windowSize: Base two logarithm of the window size. eg 9 is 2048, 10 is 4096
    ///   - compressionLevel: Level of compression. Value between 0 and 9 where 1 is fastest, 9 is best compression and
    ///         0 is no compression
    ///   - memoryLevel: Amount of memory to use when compressing. Less memory will mean the compression will take longer
    ///         and compression level will be reduced. Value between 1 - 9 where 1 is least amount of memory.
    ///   - strategy: Strategy when compressing
    @_disfavoredOverload
    public init(windowSize: Int32 = 15, compressionLevel: Int32 = Z_DEFAULT_COMPRESSION, memoryLevel: Int32 = 8, strategy: Strategy = .default) {
        assert((9...15).contains(windowSize), "Window size must be between the values 9 and 15")
        assert((-1...9).contains(compressionLevel), "Compression level must be between the values 0 and 9, or -1 indicating the default value")
        assert((1...9).contains(memoryLevel), "Compression memory level must be between the values 1 and 9")
        self.windowSize = windowSize
        self.compressionLevel = compressionLevel
        self.memoryLevel = memoryLevel
        self.strategy = strategy
    }

    ///  Initialise ZlibConfiguration
    /// - Parameters:
    ///   - windowSize: Size of compression/history window
    ///   - compressionLevel: Level of compression
    ///   - memoryLevel: Amount of memory used for compression state
    ///   - strategy: Strategy when compressing
    public init(
        windowSize: WindowSize = .defaultWindowSize,
        compressionLevel: CompressionLevel = .defaultCompressionLevel,
        memoryLevel: MemoryLevel = .defaultMemoryLevel,
        strategy: Strategy = .default
    ) {
        self.windowSize = windowSize.rawValue
        self.compressionLevel = compressionLevel.rawValue
        self.memoryLevel = memoryLevel.rawValue
        self.strategy = strategy
    }
}

/// Compressor using Zlib
public final class ZlibCompressor {
    var stream: UnsafeMutablePointer<z_stream>

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

        self.stream = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        self.stream.initialize(to: z_stream())
        self.stream.pointee.zalloc = nil
        self.stream.pointee.zfree = nil
        self.stream.pointee.opaque = nil

        let rt = CCompressZlib_deflateInit2(
            self.stream,
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
        let rt = deflateEnd(self.stream)
        assert(rt == Z_OK, "deflateEnd returned error: \(rt)")
        self.stream.deinitialize(count: 1)
        self.stream.deallocate()
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

            self.stream.pointee.avail_in = UInt32(fromBuffer.count)
            self.stream.pointee.next_in = CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            self.stream.pointee.avail_out = UInt32(toBuffer.count)
            self.stream.pointee.next_out = CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            let rt = CCompressZlib.deflate(self.stream, flag)
            bytesRead = self.stream.pointee.next_in - CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            bytesWritten = self.stream.pointee.next_out - CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
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
        let bufferSize = Int(CCompressZlib.deflateBound(self.stream, UInt(from.readableBytes)))
        return bufferSize + 6
    }

    /// Reset deflate stream
    /// - Throws: ``CompressNIOError`` if reset fails
    public func reset() throws {
        let rt = deflateReset(self.stream)
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
    var stream: UnsafeMutablePointer<z_stream>

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

        self.stream = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        self.stream.initialize(to: z_stream())
        // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
        self.stream.pointee.zalloc = nil
        self.stream.pointee.zfree = nil
        self.stream.pointee.opaque = nil
        self.stream.pointee.avail_in = 0
        self.stream.pointee.next_in = nil

        let rt = CCompressZlib_inflateInit2(self.stream, windowSize)
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
        let rt = inflateEnd(self.stream)
        assert(rt == Z_OK, "inflateEnd returned error: \(rt)")
        self.stream.deinitialize(count: 1)
        self.stream.deallocate()
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
            self.stream.pointee.avail_in = UInt32(fromBuffer.count)
            self.stream.pointee.next_in = CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            self.stream.pointee.avail_out = UInt32(toBuffer.count)
            self.stream.pointee.next_out = CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)

            let rt = CCompressZlib.inflate(self.stream, Z_NO_FLUSH)

            bytesRead = self.stream.pointee.next_in - CCompressZlib_voidPtr_to_BytefPtr(fromBuffer.baseAddress!)
            bytesWritten = self.stream.pointee.next_out - CCompressZlib_voidPtr_to_BytefPtr(toBuffer.baseAddress!)
            switch rt {
            case Z_OK:
                if self.stream.pointee.avail_out == 0 {
                    throw CompressNIOError.bufferOverflow
                }
            case Z_BUF_ERROR:
                if self.stream.pointee.avail_in == 0 {
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
        let rt = inflateReset(self.stream)
        switch rt {
        case Z_OK:
            break
        default:
            throw CompressNIOError.internalError
        }
    }
}
