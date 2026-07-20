namespace NSharpLang.Iterators.Tests

import System.Collections.Generic


// Covered-shape synchronous iterators (`func*`) lowered by the N# iterator planner through the
// columnar backend. Every definition here stays inside the sub-slice 3b surface: captured value
// parameters, hoisted typed/inferred locals, while loops, if/else branches, arithmetic and
// comparison operators, `yield`, and `yield break`.

// The canonical counting shape: one captured parameter and one hoisted local.
func* CountTo(n: int): IEnumerable<int> {
    i: int = 0
    while i < n {
        yield i
        i = i + 1
    }
}

// An infinite arithmetic sequence: two captured parameters plus an inferred hoisted local. Only
// consumer-side early termination can end an enumeration.
func* ArithmeticFrom(start: int, step: int): IEnumerable<int> {
    value := start
    while true {
        yield value
        value = value + step
    }
}

// A guard clause ending in `yield break` before the first yield.
func* UpToTwo(n: int): IEnumerable<int> {
    if n <= 0 {
        yield break
    }

    yield 1
    yield 2
}

// A zero-yield iterator: the state machine goes straight to done.
func* Nothing(): IEnumerable<int> {
}

// if/else branches inside the loop select which value each step yields.
func* EvenScaled(n: int): IEnumerable<int> {
    i: int = 0
    while i < n {
        if i % 2 == 0 {
            yield i * 10
        } else {
            yield i
        }

        i = i + 1
    }
}
