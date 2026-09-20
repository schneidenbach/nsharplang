namespace NSharpLang.CensusEmitShapes.Tests

import System
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

    // AN ARGUMENT THAT CONTAINS A COALESCE IS STILL AN ARGUMENT THAT CHOOSES. `a ?? b` produces what
    // the present value is — the emit arm has always known that — but the preflight typed both
    // operands and then said nothing, so a concat containing one had no type and the overload could
    // not be chosen from it. The second argument here is a StringComparison, which only two of
    // `IndexOf`'s arity-2 declarations accept, and the first must be typed to separate those two.
    static func OrdinalIndexOf(haystack: string, suffix: string?): int {
        return haystack.IndexOf("na" + (suffix ?? ""), StringComparison.Ordinal)
    }
}

// THE SAME RECEIVER, ONE LEVEL IN: A CALL THROUGH A STATIC-MEMBER RECEIVER AS AN ARGUMENT.
//
// The planner read a dotted callee as `owner.member`, asked the scope to name `Encoding.UTF8` as a
// TYPE, and — when it could not — handed the whole subtree to the emitter's own runtime-call tier.
// That is a fine answer for a statement, and no answer at all for an ARGUMENT: a nested value is
// typed by PLANNING it, and there is no emitter tier inside a plan. So
// `Convert.ToHexString(Encoding.UTF8.GetBytes(root))` declined at
// `emit.call.static-member-unmodeled` — naming the OUTER call, because the inner one could not be
// typed — while the identical call bound to a local emitted. A dotted head the scope cannot name as
// a type is a static property READ, which is an ordinary receiver value, so the planner now asks
// its own value-receiver owner before the hand-off.
class NestedStaticReceiverCalls {
    static func HexOfBytes(text: string): string {
        return Convert.ToHexString(Encoding.UTF8.GetBytes(text))
    }

    // Two levels of the same shape, and the inner one is itself an argument.
    static func RoundTrip(text: string): string {
        return Encoding.UTF8.GetString(Encoding.UTF8.GetBytes(text))
    }

    // The nested call feeds an argument that is not the first, so the receiver and the earlier
    // argument must still be emitted in written order ahead of it.
    static func TaggedLength(tag: string, text: string): string {
        return string.Concat(tag, Encoding.UTF8.GetByteCount(text).ToString())
    }

    // A SOURCE static-member receiver, one level in — the same relation over a type this
    // compilation declares rather than a referenced one.
    static func LengthOfOwnText(): int {
        return Convert.ToInt32(StaticReceiverOverloads.Text.IndexOf("na"))
    }

    // The nested call as the receiver of a further call, rather than as an argument.
    static func UpperRoundTrip(text: string): string {
        return Encoding.UTF8.GetString(Encoding.UTF8.GetBytes(text)).ToUpperInvariant()
    }
}
