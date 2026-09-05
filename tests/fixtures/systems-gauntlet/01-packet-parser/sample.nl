import System
import System.Buffers.Binary

struct Header {
    Version: ushort
    Length: uint
}

enum HeaderError {
    Short
}

[hot]
func ParseHeader(buf: ReadOnlySpan<byte>): Result<Header, HeaderError> {
    if buf.Length < 6 {
        return Err(HeaderError.Short)
    }

    return Ok(new Header {
        Version: BinaryPrimitives.ReadUInt16LittleEndian(buf.Slice(0, 2)),
        Length: BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(2, 4))
    })
}
