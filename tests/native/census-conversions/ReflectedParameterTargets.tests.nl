namespace NSharpLang.CensusConversions.Tests

import System.Collections.Concurrent
import System.Collections.Generic
import System.IO
import System.Text.Json

test "an integer constant reaches a reflected byte parameter, and the byte it stores is the one written" {
    roots := new ConcurrentDictionary<string, byte>()
    assert AddRoot(roots, "/src")

    // The VALUE is the contract, not the fact that the call bound: an overload chosen by widening the
    // constant to something else would have stored something else.
    stored: byte = 1
    assert roots.TryGetValue("/src", out stored)
    assert stored == 0

    // The same key twice is still the dictionary's own answer, so nothing here is a one-shot.
    assert !AddRoot(roots, "/src")

    levels := new Dictionary<string, byte>()
    AddLevel(levels, "warning")
    assert levels["warning"] == 200
}

test "a constant reaches a plainly declared byte parameter, and a negative one reaches a short" {
    stream := new MemoryStream()
    WriteZeroByte(stream)
    WriteZeroByte(stream)

    written := stream.ToArray()
    assert written.Length == 2
    assert written[0] == 0
    assert written[1] == 0

    deltas := new List<short>()
    AddDelta(deltas)
    assert deltas.Count == 1
    assert deltas[0] == -1
}

test "an array literal at a reflected parameter writes the parameter's element type" {
    // `[72, 105]` is provisionally `int[]`; what `GetString` receives has to be a `byte[]` holding 72
    // and 105, which is exactly what decoding it proves.
    assert DecodeLiteral() == "Hi"

    // Both ends of `byte` in one literal, so the range is checked in both directions. 0x00 0xFF is
    // "AP8=" in base64.
    assert EdgeBytes() == "AP8="

    // A constructor's array parameter is the same position written another way.
    assert StreamOverLiteral() == 3
}

test "the hashed block is the byte the literal wrote, not the int it was inferred as" {
    blockHash := HashSingleByteBlock()
    directHash := HashSingleByteDirectly()

    assert blockHash.Length == 32
    assert directHash.Length == 32

    index := 0
    while index < blockHash.Length {
        assert blockHash[index] == directHash[index]
        index = index + 1
    }
}

test "an explicit type argument may be the enclosing method's own type parameter" {
    options := new JsonSerializerOptions()

    assert ReadJson<string>("\"hi\"", options) == "hi"
    assert ReadJson<int>("42", options) == 42

    // A DIFFERENT instantiation of the same generic function has to answer differently, which is what
    // proves the reflected method was instantiated over this method's type parameter rather than
    // closed over a surrogate when the function was compiled.
    assert ReadJsonDefaults<bool>("true")
    assert ReadJsonDefaults<string>("\"again\"") == "again"

    // And the binding travels: `ReadFirst<T>` hands its own parameter on rather than naming a type.
    assert ReadFirst<string>("\"passed\"", options) == "passed"
    assert ReadFirst<int>("7", options) == 7
}

test "a deserialized reference type comes back as the type that was asked for" {
    options := new JsonSerializerOptions()

    values := ReadJson<int[]>("[1,2,3]", options)
    assert values != null
    assert values.Length == 3
    assert values[0] == 1
    assert values[2] == 3

    // `null` is a JSON value, and the open return is nullable precisely so it can be answered.
    assert ReadJson<string>("null", options) == null
}
