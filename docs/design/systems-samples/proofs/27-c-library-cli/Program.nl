namespace SystemsProofs.CLibraryCli

import System
import System.Runtime.InteropServices

enum HashError {
    NativeFailure
}

static class NativeHash {
    [LibraryImport("fast_hash")]
    static func Hash64(data: ReadOnlySpan<byte>, len: int, out value: ulong): int
}

[boundary]
func HashFileBytes(bytes: ReadOnlySpan<byte>): Result<ulong, HashError> {
    value: ulong = (ulong)0
    rc := NativeHash.Hash64(bytes, bytes.Length, out value)
    if rc != 0 {
        return Err(HashError.NativeFailure)
    }

    return Ok(value)
}

func Main() {
    bytes := alloc new byte[4]
    bytes[0] = (byte)1
    bytes[1] = (byte)2
    bytes[2] = (byte)3
    bytes[3] = (byte)4
    print HashFileBytes(bytes)
}
