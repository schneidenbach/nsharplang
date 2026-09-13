namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// A LAMBDA INSIDE A GENERATOR BODY.
//
// A generator has already hoisted every parameter and every local of its body into a field of its own
// state machine, so the machine IS the closure's display: a lambda becomes a private instance method
// ON the machine, and the delegate is built from the machine the body is already running on. Nothing
// is copied, and an instance generator's enclosing members reach the same way they reach from the
// body itself — through the receiver it captured.

// Captures a hoisted local and a captured parameter.
func* ScaledByCapture(n: int): IEnumerable<int> {
    factor := 3
    scale: Func<int, int> = x => x * factor + n
    yield scale(2)
    yield scale(5)
}

// The delegate leaves the machine entirely: a BCL call takes it and invokes it many times.
func* MatchesAtLeast(items: List<string>, minimum: int): IEnumerable<int> {
    longEnough: Predicate<string> = s => s.Length >= minimum
    matches := items.FindAll(longEnough)
    yield matches.Count
}

// An INSTANCE generator's lambda, reading the enclosing type through the captured receiver.
class CensusTally {
    Base: int

    constructor(baseValue: int) {
        Base = baseValue
    }

    func* Scaled(values: List<int>): IEnumerable<int> {
        shift: Func<int, int> = v => v + Base
        for v in values {
            yield shift(v)
        }
    }
}
