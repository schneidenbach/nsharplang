namespace NSharpLang.CensusEmitShapes.Tests

import System.Text


// A CALL WHOSE RECEIVER IS A STATIC MEMBER READ IS AN ORDINARY CALL, AND ITS OVERLOAD IS CHOSEN BY
// ORDINARY RESOLUTION.
//
// The direct-call planner owns every external call whose receiver AND arguments it can type; a
// receiver like `Encoding.UTF8` or `Holder.Text` is one it yields, so those calls land in the
// emitter's own runtime-call tier. That tier could only bind a name that left EXACTLY ONE
// declaration at the call's arity, so every ordinary tie — `GetString(byte[])` beside
// `GetString(ReadOnlySpan<byte>)`, `IndexOf(char)` beside `IndexOf(string)` — declined, and the
// declines were papered over by hand-written per-API arms that bound the WRONG overload:
// `IndexOf("a", 0)` used to emit `IndexOf(string, StringComparison)` and read the `0` as a
// comparison mode.
//
// The tier now asks the same resolver the planner asks, with the argument types it can preflight,
// and — for an argument that is target-typed rather than typed, such as a collection expression —
// filters the admitted candidates by whether the argument can actually be emitted at each one.
class StaticReceiverOverloads {
    static Text: string = "banana"

    // Two arity-1 declarations, separated by the argument's own type.
    static func CharIndex(): int {
        return StaticReceiverOverloads.Text.IndexOf('n')
    }

    static func StringIndex(): int {
        return StaticReceiverOverloads.Text.IndexOf("na")
    }

    // The overload the per-API arm got WRONG: the second argument is a start index, not a
    // StringComparison.
    static func StringIndexFrom(): int {
        return StaticReceiverOverloads.Text.IndexOf("na", 3)
    }

    // A static PROPERTY of a referenced type as the receiver, with a byte[] argument.
    static func DecodedFromArray(bytes: byte[]): string {
        return Encoding.UTF8.GetString(bytes)
    }

    // The same call whose argument is a COLLECTION EXPRESSION: it has no type of its own, so the
    // candidate that can accept it is the one the call selects.
    static func DecodedFromLiteral(): string {
        return Encoding.UTF8.GetString([72, 105])
    }

    static func Encoded(): byte[] {
        return Encoding.UTF8.GetBytes("Hi")
    }
}
