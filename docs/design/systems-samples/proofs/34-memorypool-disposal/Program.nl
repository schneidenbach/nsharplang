namespace SystemsProofs.MemoryPoolDisposal

import System
import System.Buffers

type ByteMemoryPool = MemoryPool<byte>

enum FillError {
    NoSpace
}

[hot]
func FillHeader(dst: Span<byte>): Result<int, FillError> {
    if dst.Length < 4 {
        return Err(FillError.NoSpace)
    }

    dst[0] = 78
    dst[1] = 35
    dst[2] = 1
    dst[3] = 0
    return Ok(4)
}

[boundary]
func BuildMessage(): Result<int, FillError> {
    owner := ByteMemoryPool.Shared.Rent(1024)
    result := FillHeader(owner.Memory.Span)
    owner.Dispose()
    return result
}

func Main(): int {
    result := BuildMessage()
    if result.IsOk == false {
        return 1
    }
    if result.OkValueUnchecked != 4 {
        return 2
    }
    return 0
}
