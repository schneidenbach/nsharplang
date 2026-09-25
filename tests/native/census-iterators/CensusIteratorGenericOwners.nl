namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// A STATIC GENERATOR DECLARED BY A GENERIC TYPE.
//
// `Repeat` below has no type parameters of its own, yet its signature and its body both name `T`, the
// parameter of the type that declares it. The state machine is a separate type, so it cannot see
// `T` through its owner: it declares its OWN copy of every parameter the body can name — the owner's
// first, then the method's — and the factory instantiates it over the exact parameters the factory
// itself sees. The owner's `where` rows travel with those copies, because a machine that names
// `CensusGuarded<T>` only loads when its `T` satisfies what `CensusGuarded` demands.
//
// Every generator here is enumerated beside this file over at least two instantiations, so a
// machine that closed over the wrong parameter, or over none, fails at run time instead of passing.
class CensusRepeater<T> {
    Seed: T

    constructor(seed: T) {
        Seed = seed
    }

    // The reported shape: a non-generic static member whose element is the owner's parameter.
    static func* Repeat(value: T, count: int): IEnumerable<T> {
        for i := 0; i < count; i += 1 {
            yield value
        }
    }

    // A generic static member of the same generic type: the machine carries `T` and `U` both.
    static func* EchoPerTag<U>(value: T, tags: List<U>): IEnumerable<T> {
        for _ in tags {
            yield value
        }
    }

    // The owner's own constructed type, named inside the machine and built through its factory.
    static func* Seeds(values: List<T>): IEnumerable<CensusRepeater<T>> {
        for v in values {
            yield new CensusRepeater<T>(v)
        }
    }

    // An unqualified call to the generator from a sibling static member of the same type.
    static func CountRepeats(value: T, count: int): int {
        n := 0
        for _ in Repeat(value, count) {
            n += 1
        }
        return n
    }

    // An instance member calling the static generator through its own instantiation.
    func Copies(count: int): List<T> {
        copies := new List<T>()
        for v in CensusRepeater<T>.Repeat(Seed, count) {
            copies.Add(v)
        }
        return copies
    }
}

// A generic static generator on a NON-generic type: the machine carries only the method's parameter,
// and the factory instantiates it over the method's own.
class CensusPlainOwner {
    static func* Twice<U>(value: U): IEnumerable<U> {
        yield value
        yield value
    }
}

// Two owner parameters, only one of which is the element.
class CensusKeyed<K, V> {
    static func* KeysOf(map: Dictionary<K, V>): IEnumerable<K> {
        for key in map.Keys {
            yield key
        }
    }
}

// A value-type owner.
struct CensusSlot<T> {
    Held: T

    static func* Pair(first: T, second: T): IEnumerable<T> {
        yield first
        yield second
    }
}

// CONSTRAINED OWNERS. The machine restates each owner parameter, so it must restate that parameter's
// `where` row too: a machine whose `T` dropped `IDisposable` or `struct` would describe a type the
// owner's own rules could never instantiate. The metadata rows beside this file read the machine's
// declared constraints back.
class CensusDisposingOwner<T> where T: IDisposable {
    static func* Each(resources: List<T>): IEnumerable<T> {
        for resource in resources {
            yield resource
        }
    }
}

class CensusValueOwner<T> where T: struct {
    static func* Each(values: List<T>): IEnumerable<T> {
        for value in values {
            yield value
        }
    }
}

class CensusLease: IDisposable {
    Name: string

    constructor(name: string) {
        Name = name
    }

    func Dispose() {
    }
}

// A generic free function reaching the generator through its OWN parameter.
func CensusRepeatAny<X>(value: X, count: int): int {
    n := 0
    for _ in CensusRepeater<X>.Repeat(value, count) {
        n += 1
    }
    return n
}
