namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// A LAMBDA INSIDE A GENERATOR BODY.
//
// A generator has already hoisted every parameter and every local of its body into a field of its own
// state machine. A lambda over those ordinary bindings becomes a private instance method on the
// machine. A loop-declared capture uses a fresh StrongBox per declaration execution and a display
// that snapshots the current box reference, while retaining the machine for outside shared captures.

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

func* PerIterationCallbacks(values: int[]): IEnumerable<Func<int>> {
    for value in values {
        yield () => value
    }
}

func* SharedIterationCallbacks(): IEnumerable<Func<int>> {
    offset := 10
    for value in [1, 2] {
        current := value
        yield () => current + offset
        current = current + 100
        offset = offset + 1
    }
}

func* SameIterationCallbacks(): IEnumerable<Func<int>> {
    for value in [1] {
        yield () => {
            value = value + 1
            return value
        }
        yield () => value
    }
}

func* CountedIterationCallbacks(): IEnumerable<Func<int>> {
    for i := 0; i < 2; i++ {
        current := i
        yield () => current
    }
}

func* CountedInitializerCallbacks(): IEnumerable<Func<int>> {
    for i := 0; i < 2; i++ {
        yield () => i
    }
}

func* WhileIterationCallbacks(): IEnumerable<Func<int>> {
    i := 0
    while i < 2 {
        current := i
        yield () => current
        i++
    }
}

func* EnumerableIterationCallbacks(values: List<int>): IEnumerable<Func<int>> {
    for value in values {
        yield () => value
    }
}

func* MemberSuffixCallbacks(values: int[], items: int[]): IEnumerable<Func<int>> {
    for Length in values {
        yield () => items.Length
    }
}

interface ILoopMarker {
}

class LoopBase {
}

class LoopValue: LoopBase, ILoopMarker {
}

func* ConstrainedIterationCallbacks<T, U>(item: U): IEnumerable<object> where T: class where U: T, ILoopMarker, new() {
    for ignored in [0] {
        value := item
        callback: Func<object> = () => value
        yield callback
    }
}
