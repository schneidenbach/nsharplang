namespace SystemsProofs.ArrayPoolFileIo

import System
import System.Buffers
import System.IO

type ByteArrayPool = ArrayPool<byte>

enum ParseError {
    Empty
}

[boundary]
func WarmPool() {
    buf := ByteArrayPool.Shared.Rent(65536)
    ByteArrayPool.Shared.Return(buf)
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
    buf := ByteArrayPool.Shared.Rent(65536)
    stream := File.OpenRead(path)
    n := stream.Read(buf, 0, buf.Length)
    result := ParseFirstByte(buf.AsSpan(0, n))
    stream.Dispose()
    ByteArrayPool.Shared.Return(buf)
    return result
}

func Main(): int {
    WarmPool()
    result := ReadAndParse("NSharpLang.Runtime.dll")
    if result.IsOk == false {
        return 1
    }
    if result.OkValueUnchecked != (byte)77 {
        return 2
    }
    return 0
}
