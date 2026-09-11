namespace SystemsTemplate

import System
import System.Buffers.Binary

enum ParseError {
    Short
}

[hot]
func ParseLength(buf: ReadOnlySpan<byte>): Result<uint, ParseError> {
    if buf.Length < 4 {
        return Err(ParseError.Short)
    }

    return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))
}

[boundary]
func AdaptPacket(bytes: byte[]): Result<uint, ParseError> {
    return ParseLength(bytes.AsSpan())
}

func Warmup(): void {
}
