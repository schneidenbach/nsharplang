import System
import System.Buffers.Binary

enum WriteError {
    NoSpace
}

[hot]
func WriteFrame(dst: Span<byte>, tag: byte, length: uint): Result<int, WriteError> {
    if dst.Length < 5 {
        return Err(WriteError.NoSpace)
    }

    dst[0] = tag
    BinaryPrimitives.WriteUInt32LittleEndian(dst.Slice(1, 4), length)
    return Ok(5)
}
