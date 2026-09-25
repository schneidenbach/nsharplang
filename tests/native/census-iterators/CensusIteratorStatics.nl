namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic


// A STATIC MEMBER OF A TYPE THIS PROGRAM DECLARES, READ AND WRITTEN INSIDE A GENERATOR.
//
// A static read has no receiver to evaluate and a static write has no receiver to store through, so
// both are one row over a handle the definition names — `ldsfld`/`stsfld` for a field, `call` for a
// static property's accessor. The emitter has answered these since the beginning; the PLAN side had
// no owner for them, which is why an iterator body (whose every value is planned) declined a name as
// ordinary as `Counter.Total`.
class CensusStaticCounter {
    static Total: int
    static Label: string

    static func Reset() {
        Total = 0
        Label = ""
    }
}

// A static PROPERTY, whose read is its getter call and whose write is its setter call.
class CensusRegistry {
    static Backing: int

    static Current: int {
        get {
            return Backing
        }
        set {
            Backing = value
        }
    }
}

// A static declared on a BASE: naming the derived type binds the base's declaration, because a
// static member belongs to the type that declares it.
class CensusBase {
    static Seen: int
}

class CensusDerived: CensusBase {
}

// A static READ inside a generator, in a condition, in an arithmetic operand and as the yielded
// value itself.
func* StaticReads(count: int): IEnumerable<int> {
    for i := 0; i < count; i += 1 {
        if CensusStaticCounter.Total > 0 {
            yield CensusStaticCounter.Total + i
        } else {
            yield i
        }
    }
}

// A static WRITE inside a generator, observed across suspensions by the consumer.
func* StaticWrites(count: int): IEnumerable<int> {
    for i := 0; i < count; i += 1 {
        CensusStaticCounter.Total = CensusStaticCounter.Total + 1
        CensusStaticCounter.Label = "step" + i.ToString()
        yield CensusStaticCounter.Total
    }
}

// A static PROPERTY read and written inside a generator.
func* StaticProperty(count: int): IEnumerable<int> {
    for i := 0; i < count; i += 1 {
        CensusRegistry.Current = CensusRegistry.Current + 2
        yield CensusRegistry.Current
    }
}

// A static reached through the DERIVED name, which binds the base's one declaration.
func* InheritedStatic(): IEnumerable<int> {
    CensusDerived.Seen = CensusDerived.Seen + 1
    yield CensusBase.Seen
}

// The same reads and writes in a PLAIN body, so the tests can assert one lowering serves both.
func PlainStaticBump(): int {
    CensusStaticCounter.Total = CensusStaticCounter.Total + 1
    return CensusStaticCounter.Total
}
