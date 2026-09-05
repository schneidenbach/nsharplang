namespace SystemsProofs.AsyncFileHotParser

import System
import System.Buffers
import System.IO
import System.Threading.Tasks

type ByteArrayPool = ArrayPool<byte>

enum ParseError {
    Empty
}

[hot]
func CountNonZero(bytes: ReadOnlySpan<byte>): Result<int, ParseError> {
    if bytes.Length == 0 {
        return Err(ParseError.Empty)
    }

    count := 0
    for i := 0; i < bytes.Length; i++ {
        if bytes[i] != 0 {
            count = count + 1
        }
    }
    return Ok(count)
}

[boundary]
async func ReadAndCount(path: string): Task<int> {
    buf := ByteArrayPool.Shared.Rent(4096)
    stream := File.OpenRead(path)
    n := await stream.ReadAsync(buf, 0, buf.Length)
    result := CountNonZero(buf.AsSpan(0, n))
    stream.Dispose()
    ByteArrayPool.Shared.Return(buf)
    if result.IsErr {
        return -1
    }
    return result.OkValueUnchecked
}

[boundary]
async func Main(): Task<int> {
    count := await ReadAndCount("NSharpLang.Runtime.dll")
    if count <= 0 {
        return 1
    }
    return 0
}
