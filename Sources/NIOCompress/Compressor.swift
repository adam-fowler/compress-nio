
import NIO

public protocol NIODecompressor {
    mutating func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    mutating func startStream()
    mutating func streamInflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    mutating func finishStream()
}

extension NIODecompressor {
    public mutating func inflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        startStream()
        try streamInflate(from: &from, to: &to)
        finishStream()
    }
}

public protocol NIOCompressor {
    mutating func deflate(from: inout ByteBuffer, to: inout ByteBuffer) throws
    mutating func startStream()
    mutating func streamDeflate(from: inout ByteBuffer, to: inout ByteBuffer, finalise: Bool) throws
    mutating func finishStream()

    mutating func deflateBound(from: ByteBuffer) -> Int
}

extension NIOCompressor {
    public mutating func deflate(from: inout ByteBuffer, to: inout ByteBuffer) throws {
        startStream()
        try streamDeflate(from: &from, to: &to, finalise: true)
        finishStream()
    }
}

