namespace SystemsProofs.MemoryPoolDisposal

import System
import System.Buffers

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
    using owner := MemoryPool<byte>.Shared.Rent(1024)
    return FillHeader(owner.Memory.Span)
}

func Main() {
    print BuildMessage()
}
