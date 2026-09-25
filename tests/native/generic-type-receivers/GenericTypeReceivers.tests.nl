namespace NSharpLang.GenericTypeReceivers.Tests

import System.Buffers
import System.Collections.Generic
import System.Numerics

// THE EXECUTABLE HALF OF THE CONSTRUCTED-GENERIC-TYPE RECEIVER.
//
// `Vector<int>.Count` used to parse as the comparison chain `Vector < int > .Count` and report an
// NL202 about comparing a `Vector` with an `Int32` followed by an NL102 about a `.` with no receiver
// in front of it. The estate contracts state the parse tree and the diagnostics; this project states
// what the feature is FOR, by running it — every entry point below reaches real IL through the
// columnar backend and reads a real value back.
//
// THE VALUES ARE CHECKED AGAINST EACH OTHER, NOT AGAINST A CONSTANT. Lane counts are
// machine-dependent (`Vector<int>.Count` is 4 on a 128-bit vector unit and 8 on a 256-bit one), so a
// literal expectation would pin the test to one machine. The relations are not machine-dependent:
// a lane count is positive, it is the same number read twice through two different functions, and a
// `byte` vector holds exactly four times as many lanes as an `int` vector because a `byte` is a
// quarter the width. Those hold everywhere the runtime runs.
//
// THE COMPARISON CONTROL IS PINNED WITH ITS LITERAL BODY. `Between` is written
// `lower < value && value > upper` — which is NOT a range test, and is deliberately not "corrected"
// here: it is the shape whose two angle brackets look most like a type-argument list, so it is the
// shape a regression in the disambiguation would break first. Its documented answer is the answer
// that expression actually has.
func LaneCount(): int {
    return Vector<int>.Count
}

func LaneCountAgain(): int {
    return Vector<int>.Count
}

func ByteLaneCount(): int {
    return Vector<byte>.Count
}

func ZeroVector(): Vector<int> {
    return Vector<int>.Zero
}

func OneVector(): Vector<int> {
    return Vector<int>.One
}

func QualifiedLaneCount(): int {
    return System.Numerics.Vector<int>.Count
}

func IntEquals(a: int, b: int): bool {
    return EqualityComparer<int>.Default.Equals(a, b)
}

func StringEquals(a: string, b: string): bool {
    return EqualityComparer<string>.Default.Equals(a, b)
}

func CompareStrings(a: string, b: string): int {
    return Comparer<string>.Default.Compare(a, b)
}

func NestedReceiverEquals(left: Dictionary<string, List<int>>, right: Dictionary<string, List<int>>): bool {
    return EqualityComparer<Dictionary<string, List<int>>>.Default.Equals(left, right)
}

func RentedLength(size: int): int {
    buffer := ArrayPool<byte>.Shared.Rent(size)
    length := buffer.Length
    ArrayPool<byte>.Shared.Return(buffer, false)
    return length
}

func Between(value: int, lower: int, upper: int): bool {
    return lower < value && value > upper
}

func LessThanLength(value: int, values: int[]): bool {
    return value < values.Length
}

func InRangeOfBoth(i: int, left: int[], j: int, right: int[]): bool {
    return i < left.Length && j > right.Length
}

test "a static property on a constructed external generic type reads the same value through two functions" {
    lanes := LaneCount()
    assert lanes > 0
    assert lanes == LaneCountAgain()
    assert lanes == Vector<int>.Count
}

test "the lane count scales with the element width — a byte vector holds four times an int vector" {
    assert ByteLaneCount() == LaneCount() * 4
}

test "a static property whose type is the constructed type itself comes back as that type" {
    // The read-back is the point: `Vector<int>.Zero` is typed `Vector<int>`, so the value that
    // crosses the function boundary must compare equal to a second, independent read of the same
    // static property — and must NOT compare equal to the type's other constant.
    zero := ZeroVector()
    assert zero.Equals(Vector<int>.Zero)
    assert zero.Equals(Vector<int>.One) == false
    assert OneVector().Equals(Vector<int>.One)
}

test "a fully qualified receiver resolves without relying on the file's import" {
    assert QualifiedLaneCount() == LaneCount()
}

test "a static property read chains into an instance call on the constructed type it returns" {
    assert IntEquals(1, 1)
    assert IntEquals(1, 2) == false
    assert StringEquals("a", "a")
    assert StringEquals("a", "b") == false
}

test "a second constructed generic comparer over the same chain answers its own contract" {
    assert CompareStrings("a", "a") == 0
    assert CompareStrings("a", "b") < 0
    assert CompareStrings("b", "a") > 0
}

test "a NESTED type argument closes on a split `>>` and still names one constructed receiver" {
    left := new Dictionary<string, List<int>>()
    right := new Dictionary<string, List<int>>()
    assert NestedReceiverEquals(left, left)
    assert NestedReceiverEquals(left, right) == false
}

test "a static property on a constructed generic type is a receiver for an instance call in its own right" {
    // `ArrayPool<byte>.Shared` was recorded as a language wall — a generic static member access did
    // not parse. It is a rented buffer here rather than a name in a list: the pool hands back an
    // array at least as long as the request, and the buffer is returned to the same pool instance.
    assert RentedLength(16) >= 16
    assert RentedLength(1000) >= 1000
}

test "the comparison controls keep the meaning their written text has" {
    // `lower < value && value > upper` — NOT a range test, and pinned as written.
    assert Between(5, 1, 10) == false
    assert Between(20, 1, 10)
    assert Between(0, 1, 10) == false
}

test "a comparison against a member access is still a comparison" {
    values: int[] = [1, 2, 3]
    assert LessThanLength(2, values)
    assert LessThanLength(3, values) == false
    assert InRangeOfBoth(1, values, 4, values)
    assert InRangeOfBoth(1, values, 2, values) == false
}
