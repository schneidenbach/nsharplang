namespace NSharpLang.ReadonlyStructs.Tests

// THE SHAPES THE `readonly struct` RULES ARE PROVED OVER, compiled by the tip CLI and executed as real
// IL by the sibling `.tests.nl`. Every declaration here is the SOURCE of a metadata or runtime claim
// made there; nothing is written for coverage's sake.

// The brief's baseline probe, verbatim: the shape that failed to PARSE before this arc.
readonly struct Point {
    readonly X: int

    constructor(x: int) {
        X = x
    }
}

// A GENERIC readonly struct whose sole field is the type parameter itself.
readonly struct ReadonlyBox<T> {
    readonly Value: T

    constructor(value: T) {
        Value = value
    }
}

// A PLAIN struct with a readonly field. This is NOT a readonly struct and must not be treated as one:
// conflating the two would silently promise immutability for half the existing corpus.
struct Mutable {
    readonly X: int
    Y: int

    constructor(x: int, y: int) {
        X = x
        Y = y
    }
}

interface HasMagnitude {
    func Magnitude(): int
}

// A readonly struct with an instance method that COMPUTES a value, and one that IMPLEMENTS an
// interface — the two shapes a value type is reached through when the receiver may be a readonly
// location or a boxed interface reference.
readonly struct Vector: HasMagnitude {
    readonly Dx: int
    readonly Dy: int

    constructor(dx: int, dy: int) {
        Dx = dx
        Dy = dy
    }

    func Magnitude(): int {
        return Dx * Dx + Dy * Dy
    }

    func Scaled(factor: int): Vector {
        return new Vector(Dx * factor, Dy * factor)
    }

    func Equals(other: Vector): bool {
        return Dx == other.Dx && Dy == other.Dy
    }

    override func GetHashCode(): int {
        return Dx * 31 + Dy
    }

    override func ToString(): string {
        return "(" + Dx.ToString() + "," + Dy.ToString() + ")"
    }
}

// A readonly struct with a PRIMARY CONSTRUCTOR. Its captured parameters are fields the compiler
// synthesized rather than fields the source declared, and they carry the same promise: C# emits them
// `initonly` for a readonly struct, and so must N#.
readonly struct Captured(first: int, second: int) {
    func Total(): int {
        return first + second
    }
}

// STATIC STATE IS NOT INSTANCE STATE. A readonly struct may hold a mutable static field; only the
// instance fields are constrained.
readonly struct WithStatic {
    static Counter: int = 0
    readonly Tag: int

    constructor(tag: int) {
        Tag = tag
    }
}

// A `readonly ref struct` and a `readonly record struct`: the other two spellings the word is legal on.
readonly ref struct Window {
    readonly Start: int
    readonly Length: int

    constructor(start: int, length: int) {
        Start = start
        Length = length
    }

    func End(): int {
        return Start + Length
    }
}

readonly record struct Pair {
    readonly Left: int
    readonly Right: int

    constructor(left: int, right: int) {
        Left = left
        Right = right
    }
}

// A NESTED readonly struct, to prove the member dispatch carries the modifier as well as the
// top-level one.
class Container {
    readonly struct Inner {
        readonly Value: int

        constructor(value: int) {
            Value = value
        }
    }

    static func MakeInner(value: int): int {
        inner := new Inner(value)
        return inner.Value
    }
}

// THE ACCEPTANCE SHAPE. `src/NSharpLang.Runtime/Result.cs` is a readonly generic struct holding two
// payload slots and a byte discriminator, with a private constructor, instance state predicates and
// `Try`-shaped `out` accessors. This is that shape in N#, minus the static factory members (static
// members on a generic type are a separate stream's arc). A field of type `T` is the FAITHFUL
// translation of C#'s unconstrained `T?` field — N#'s `T?` would mean something else.
readonly struct ResultShape<T, E> {
    readonly value: T
    readonly error: E
    readonly state: byte

    constructor(value: T, error: E, state: byte) {
        this.value = value
        this.error = error
        this.state = state
    }

    IsOk: bool => state == 1

    IsError: bool => state == 2

    func TryGetValue(out result: T): bool {
        result = value
        return state == 1
    }

    func TryGetError(out result: E): bool {
        result = error
        return state == 2
    }

    func Equals(other: ResultShape<T, E>): bool {
        return state == other.state
    }

    override func GetHashCode(): int {
        return state.ToString().Length + state
    }
}
