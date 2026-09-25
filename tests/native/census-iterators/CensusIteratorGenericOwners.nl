namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// A STATIC GENERATOR DECLARED INSIDE A GENERIC TYPE.
//
// The machine is nested in the declaring type and re-declares that type's parameters first, then the
// method's own — the shape C# emits. Its body therefore names `CensusGenericBox<!0>::Name()` in its
// OWN `!0`, and the factory instantiates it on the declaring method's view of the same parameters:
// `<Names>d__N<!0>` inside `Names`, `<Echo>d__N<!0, !!0>` inside `Echo<U>`. A machine that was not
// generic over the declaring type's parameters would name a `!0` it does not have, which the runtime
// refuses to load.
class CensusGenericBox<T> {
    static func Name(): string => "box"

    static func* Names(count: int): IEnumerable<string> {
        for i := 0; i < count; i += 1 {
            yield Name() + i.ToString()
        }
    }

    // A generic generator in a generic type: the machine is generic over both `T` and `U`.
    static func* Echo<U>(value: U): IEnumerable<U> {
        yield value
        yield value
    }

    // Both parameters in the body: a hoisted `T` field, a call back into the declaring type, and a
    // yielded `T`.
    static func* Tagged<U>(item: T, _label: U): IEnumerable<T> {
        yield Pick(item)
        yield item
    }

    static func Pick(item: T): T => item
}

// The declaring type's CONSTRAINTS travel with its parameters. Naming `CensusRankedBox<!0>` from the
// machine is only legal when the machine's own `!0` satisfies `IComparable<!0>` too.
class CensusRankedBox<T> where T: IComparable<T> {
    static func Latest(_previous: T, next: T): T => next

    static func* Running<U>(items: List<T>, _tag: U): IEnumerable<T> {
        best := items[0]
        for item in items {
            best = Latest(best, item)
            yield best
        }
    }
}

// A reference-type constraint, read by a generator that never names `T` in its own signature.
class CensusReferenceBox<T> where T: class {
    static func Describe(_value: T): string => "ref"

    static func* Describes<U>(value: T, _extra: U): IEnumerable<string> {
        yield Describe(value)
        yield Describe(value) + "!"
    }
}

// A per-iteration lambda in a generic type's static generator: its display is generic over the
// machine's parameters and restates their constraints as well.
class CensusIndexedBox<T> where T: IComparable<T> {
    static func* Positions<U>(items: List<T>, _tag: U): IEnumerable<int> {
        for item in items {
            index := items.IndexOf(item)
            scaled: Func<int> = () => index * 10
            yield scaled()
        }
    }
}
