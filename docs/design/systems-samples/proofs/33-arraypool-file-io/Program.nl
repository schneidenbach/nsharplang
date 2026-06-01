namespace SystemsProofs.ArrayPoolFileIo

import System
import System.Buffers
import System.IO

enum ParseError {
    Empty
}

[boundary]
func WarmPool() {
    buf := ArrayPool<byte>.Shared.Rent(65536)
    ArrayPool<byte>.Shared.Return(buf)
}

[hot]
func ParseFirstByte(bytes: ReadOnlySpan<byte>): Result<byte, ParseError> {
    if bytes.Length == 0 {
        return Err(ParseError.Empty)
    }
    return Ok(bytes[0])
}

[boundary]
func ReadAndParse(path: string): Result<byte, ParseError> {
    buf := ArrayPool<byte>.Shared.Rent(65536)
    try {
        n := File.OpenRead(path).Read(buf)
        return ParseFirstByte(buf.AsSpan(0, n))
    } finally {
        ArrayPool<byte>.Shared.Return(buf)
    }
}

func Main() {
    WarmPool()
    print ReadAndParse("input.bin")
}
