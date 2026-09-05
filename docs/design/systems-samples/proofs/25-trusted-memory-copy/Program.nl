namespace SystemsProofs.TrustedMemoryCopy

import System

enum CopyError {
    Ok,
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
func CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int): CopyError {
    if len < 0 || len > dst.Length || len > src.Length {
        return CopyError.OutOfRange
    }

    unsafe {
        Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len)
    }

    return CopyError.Ok
}

func Main() {
    src := alloc new byte[4]
    src[0] = (byte)1
    src[1] = (byte)2
    src[2] = (byte)3
    src[3] = (byte)4
    dst := alloc new byte[4]
    _ = CopyExact(dst, src, 4)
}
