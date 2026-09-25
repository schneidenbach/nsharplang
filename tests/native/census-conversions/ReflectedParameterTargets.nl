namespace NSharpLang.CensusConversions.Tests

import System
import System.Collections.Concurrent
import System.Collections.Generic
import System.IO
import System.Security.Cryptography
import System.Text
import System.Text.Json

// CENSUS §CONV/3 — A REFLECTED PARAMETER IS A TARGET LIKE ANY OTHER.
//
// Three conversions the language performs at every OTHER position stopped at a reflected overload set,
// and each one reported NL402 "No overload of 'X' accepts N arguments with these types" for a call C#
// compiles without hesitating:
//
//   * AN INTEGER CONSTANT at a narrower parameter (ECMA-334 §10.2.11). `roots.TryAdd(root, 0)` on a
//     `ConcurrentDictionary<string, byte>` said "passes `string`, `int`" — for the only overload
//     `TryAdd` has.
//   * AN ARRAY LITERAL at an array parameter. `sha.TransformBlock([0], 0, 1, null, 0)` said
//     "passes `int[]`" while the identical literal written at a local (`one: byte[] = [0]`) was
//     accepted, so the element type the parameter names was the one position that did not target-type.
//   * AN EXPLICIT TYPE ARGUMENT that is the ENCLOSING method's type parameter.
//     `JsonSerializer.Deserialize<T>(json, options)` inside `func Read<T>(…)` could not bind, because
//     `T` converts to no CLR type and a written type argument that would not convert failed the
//     candidate outright.
//
// Every function below is written the way the converted corpus writes it. The tests read the VALUES
// back — the byte that was stored, the bytes the literal really wrote, the value the deserialization
// produced — because a call that bound the wrong overload or converted an element wrongly would still
// have the right arity and the right length.

// §10.2.11 through a CONSTRUCTED generic receiver: the parameter is the type's own `TValue`, bound to
// `byte` by the receiver, and the constant has to be measured against the BOUND type rather than the
// open one.
func AddRoot(roots: ConcurrentDictionary<string, byte>, root: string): bool {
    return roots.TryAdd(root, 0)
}

func AddLevel(levels: Dictionary<string, byte>, name: string) {
    levels.Add(name, 200)
}

// §10.2.11 at a plainly declared `byte` parameter, with no generic anywhere.
func WriteZeroByte(stream: Stream) {
    stream.WriteByte(0)
}

// A NEGATIVE constant is the same rule with the sign carried through, and `short` accepts one where
// `byte` must not.
func AddDelta(deltas: List<short>) {
    deltas.Add(-1)
}

// The array literal at a reflected array parameter, read back through the bytes it actually wrote.
func DecodeLiteral(): string {
    return Encoding.UTF8.GetString([72, 105], 0, 2)
}

// The same literal at a CONSTRUCTOR's array parameter, which is the other position a written argument
// list reaches.
func StreamOverLiteral(): int {
    stream := new MemoryStream([72, 105, 33])
    return (int)stream.Length
}

// Two elements at the extremes of `byte`, so the range check is exercised in both directions rather
// than only at zero.
func EdgeBytes(): string {
    return Convert.ToBase64String([0, 255])
}

// The census's own call, with the `null` output buffer beside the literal.
func HashSingleByteBlock(): byte[] {
    sha := SHA256.Create()
    try {
        sha.TransformBlock([0], 0, 1, null, 0)
        sha.TransformFinalBlock(new byte[](0), 0, 0)
        return must sha.Hash
    } finally {
        sha.Dispose()
    }
}

func HashSingleByteDirectly(): byte[] {
    return SHA256.HashData([0])
}

// The enclosing method's type parameter, written as the reflected generic method's type argument. The
// method is left OPEN by the analyzer — there is no CLR type to close it over — and the emitter
// instantiates it over this method's own type parameter.
func ReadJson<T>(json: string, options: JsonSerializerOptions): T? {
    return JsonSerializer.Deserialize<T>(json, options)
}

// The same call with the options position left to its own default, so the type argument is the only
// thing the call site supplies.
func ReadJsonDefaults<T>(json: string): T? {
    return JsonSerializer.Deserialize<T>(json)
}

// The same shape one level up: a caller that is itself generic hands its own parameter on, so the
// binding travels rather than being read off the call site.
func ReadFirst<T>(json: string, options: JsonSerializerOptions): T? {
    return ReadJson<T>(json, options)
}

// THE CONSTANT MUST NOT HIJACK THE OVERLOAD. `Math.Max`, `Math.Abs`, `Math.Clamp` and
// `Convert.ToInt32` each declare a `byte`, a `short`, a `long` and an `int` form, and C# picks the
// `int` one for an `int` constant because identity is the best conversion of all. The boxed result's
// runtime type is what the choice actually was.
func MaxedTypeName(): string {
    maxed: object = Math.Max(0, 1)
    return maxed.GetType().Name
}

func AbsoluteTypeName(): string {
    absolute: object = Math.Abs(0)
    return absolute.GetType().Name
}

func ClampedTypeName(): string {
    clamped: object = Math.Clamp(5, 0, 10)
    return clamped.GetType().Name
}

func ConvertedTypeName(): string {
    converted: object = Convert.ToInt32(0)
    return converted.GetType().Name
}
