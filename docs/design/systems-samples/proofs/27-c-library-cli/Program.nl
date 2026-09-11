namespace SystemsProofs.CLibraryCli

import System.Runtime.InteropServices

enum HashError {
    NativeFailure
}

// A native import is a P/Invoke stub, so its parameters are the CLR interop marshaller's input and
// not the language's. The buffer is `byte[]` rather than `ReadOnlySpan<byte>` for that reason: an
// array marshals as a pinned pointer, while a span — like every generic type — is refused by the
// marshaller. N# emits the P/Invoke directly and there is no source generator to write a pinning
// wrapper, so the compiler reports a generic parameter here rather than letting the call abort.
static class NativeHash {
    [LibraryImport("fast_hash")]
    static func Hash64(data: byte[], len: int, out value: ulong): int
}

[boundary]
func HashFileBytes(bytes: byte[]): Result<ulong, HashError> {
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
