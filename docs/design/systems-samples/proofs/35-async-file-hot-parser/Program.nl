namespace SystemsProofs.AsyncFileHotParser

import System
import System.Buffers
import System.IO
import System.Threading.Tasks

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
async func ReadAndCount(path: string): ValueTask<Result<int, ParseError>> {
    buf := ArrayPool<byte>.Shared.Rent(4096)
    try {
        using stream := File.OpenRead(path)
        n := await stream.ReadAsync(buf)
        return CountNonZero(buf.AsSpan(0, n))
    } finally {
        ArrayPool<byte>.Shared.Return(buf)
    }
}

async func Main() {
    print await ReadAndCount("input.bin")
}
