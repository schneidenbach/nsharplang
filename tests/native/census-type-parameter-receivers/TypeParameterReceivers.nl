namespace NSharpLang.CensusTypeParameterReceivers.Tests

// Fixture types for calls whose RECEIVER is typed by a generic type parameter. `stored.ToString()`
// on a `T` field passed analysis and then declined at emit as "instance call 'T.ToString' is not
// modeled"; the CLR shape for it is `constrained. !T; callvirt` over the receiver's ADDRESS
// (ECMA-335 III.2.1), which is right for a value-type and a reference-type argument alike.
interface ICounter {
    func Bump(): int
}

// A value-type counter whose `Bump` writes itself: the witness that a constrained call ran on the
// receiver's own storage rather than on a copy of it.
struct Counter: ICounter {
    count: int

    func Bump(): int {
        count = count + 1
        return count
    }
}

// The reference-type twin: every copy of the reference shares one counter.
class CounterBox: ICounter {
    count: int

    func Bump(): int {
        count = count + 1
        return count
    }
}

// A value type that implements `ToString` itself — the constrained call is direct, with no box.
struct Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        X = x
        Y = y
    }

    override func ToString(): string => "(" + X.ToString() + ", " + Y.ToString() + ")"
}

// A value type that inherits `object`'s `ToString` — the constrained call boxes it, then dispatches.
struct Plain {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

class Named {
    name: string

    constructor(name: string) {
        this.name = name
    }

    override func ToString(): string => name
}

// `System.Object`'s members, called on a FIELD typed `T`.
class Holder<T> {
    stored: T

    constructor(value: T) {
        stored = value
    }

    func Show(): string => stored.ToString()
    func Hash(): int => stored.GetHashCode()
    func Same(other: T): bool => stored.Equals(other)
    func TypeName(): string => stored.GetType().Name
}

// An interface constraint's member, called on a mutable field and on a `readonly` one. The mutable
// field is bumped in place; the readonly one is copied first, as C# copies it, so a struct `T` never
// sees its own storage change.
class Bumper<T> where T: ICounter {
    counter: T
    readonly frozen: T

    constructor(first: T, second: T) {
        counter = first
        frozen = second
    }

    func BumpField(): int {
        counter.Bump()
        return counter.Bump()
    }

    func BumpReadonly(): int {
        frozen.Bump()
        return frozen.Bump()
    }
}

// The same calls on a PARAMETER, a LOCAL and a CALL RESULT typed by a method's own type parameter.
func ShowParam<T>(value: T): string => value.ToString()

func ShowLocal<T>(value: T): string {
    copy := value
    return copy.ToString()
}

func FirstOf<T>(values: T[]): T => values[0]

func ShowFirst<T>(values: T[]): string => FirstOf<T>(values).ToString()

func BumpParam<T>(value: T): int where T: ICounter {
    value.Bump()
    return value.Bump()
}

func BumpLocal<T>(value: T): int where T: ICounter {
    local := value
    local.Bump()
    return local.Bump()
}

// A call result has no storage of its own, so each `Bump` acts on a fresh copy of a struct element.
func BumpFirst<T>(values: T[]): int where T: ICounter {
    FirstOf<T>(values).Bump()
    return FirstOf<T>(values).Bump()
}
