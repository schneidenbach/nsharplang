namespace NSharpLang.CensusEmitShapes.Tests

import System
import System.Security.Cryptography

test "an empty collection expression is applicable at a reflected array parameter" {
    hash := SHA256.Create()
    tail := EmptyCollectionArguments.FinalizeEmpty(hash)
    assert tail.Length == 0
    computed := hash.Hash
    if computed == null {
        throw new InvalidOperationException("The finished transform produced no hash.")
    }
    assert computed.Length == 32
}

test "the empty literal is the real zero-length array the call transforms" {
    first := SHA256.Create()
    block := new byte[](2)
    block[0] = 1
    block[1] = 2
    EmptyCollectionArguments.BlockThenFinal(first, block)
    streamed := first.Hash
    if streamed == null {
        throw new InvalidOperationException("The streamed transform produced no hash.")
    }

    second := SHA256.Create()
    direct := second.ComputeHash(block)
    index := 0
    while index < direct.Length {
        assert streamed[index] == direct[index]
        index = index + 1
    }
}
