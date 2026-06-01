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
    value := 0UL
    rc := NativeHash.Hash64(bytes, bytes.Length, out value)
    if rc != 0 {
        return Err(HashError.NativeFailure)
    }

    return Ok(value)
}

func Main() {
    bytes := new byte[] { 1, 2, 3, 4 }
    print HashFileBytes(bytes)
}
