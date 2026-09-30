namespace NSharpLang.CensusEmitShapes

import System

// A MEMBER READ OFF A CALL RESULT IS CHOSEN BY THE RESULT'S TYPE, NOT BY THE MEMBER'S SPELLING.
//
// `.ItemN` and `.Length` have instructions of their own on the receivers that own them — a
// `ValueTuple`'s public element FIELD, `ldlen` on an array — and a read off a NAMED receiver was
// always resolved by type. A read off a CALL RESULT is not claimed by the instance-member planner,
// and the emitter's own arm routed those two spellings to the tuple and length instructions alone:
// `Pair(1, e).Item2` on a `System.Tuple`, whose element is a PROPERTY, declined, and so did a source
// class's own `Item1` or `Length` property read the same way. Through a local every one of them
// emitted.

// A REFERENCE tuple: `Tuple<T1, T2>` exposes its elements as read-only properties.
func Pair(count: int, inner: Exception?): Tuple<int, Exception?> => new Tuple<int, Exception?>(count, inner)

// The VALUE tuple twin, whose elements are fields — the shape the tuple instruction owns.
func ValuePair(count: int, inner: Exception?): (int, Exception?) => (count, inner)

func HasNoInner(inner: Exception?): bool {
    return Pair(1, inner).Item2 == null
}

func HasInner(inner: Exception?): bool {
    return Pair(1, inner).Item2 != null
}

func InnerOf(inner: Exception?): Exception? {
    return Pair(1, inner).Item2
}

// The element as the receiver of the next hop in the chain, over a tuple whose element is non-null.
func Wrapped(count: int, inner: Exception): Tuple<int, Exception> => new Tuple<int, Exception>(count, inner)

func InnerMessage(inner: Exception): string {
    return Wrapped(1, inner).Item2.Message
}

func DescribeInner(inner: Exception?): string {
    if Pair(1, inner).Item2 == null {
        return "none"
    }
    return "some"
}

func ValueHasNoInner(inner: Exception?): bool {
    return ValuePair(1, inner).Item2 == null
}

// A SOURCE class whose own properties happen to carry those spellings.
class ItemAndLength {
    Item1: string?
    Length: string?

    constructor(item: string?, length: string?) {
        Item1 = item
        Length = length
    }
}

func MakeItemAndLength(item: string?, length: string?): ItemAndLength => new ItemAndLength(item, length)

func ItemMissing(item: string?): bool {
    return MakeItemAndLength(item, "x").Item1 == null
}

func LengthMissing(length: string?): bool {
    return MakeItemAndLength("x", length).Length == null
}

// And the receivers the dedicated instructions still own, read off a call.
func Words(): string[] => ["alpha", "beta", "gamma"]

func WordCount(): int {
    return Words().Length
}

func Greeting(): string => "hello"

func GreetingLength(): int {
    return Greeting().Length
}
