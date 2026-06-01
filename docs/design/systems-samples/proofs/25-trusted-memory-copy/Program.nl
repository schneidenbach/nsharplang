namespace SystemsProofs.TrustedMemoryCopy

import System

enum CopyError {
    OutOfRange
}

[memory(safe)]
[trusted(
    reason: "len is checked against both span lengths before the unsafe copy",
    owner: "runtime-core",
    review: "2026-12-01",
    expires: "2027-06-01"
)]
[hot]
func CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int): Result<int, CopyError> {
    if len < 0 || len > dst.Length || len > src.Length {
        return Err(CopyError.OutOfRange)
    }

    unsafe {
        Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len)
    }

    return Ok(len)
}

func Main() {
    src := new byte[] { 1, 2, 3, 4 }
    dst := new byte[4]
    _ = CopyExact(dst, src, 4)
}
