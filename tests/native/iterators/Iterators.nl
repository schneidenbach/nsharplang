namespace NSharpLang.Iterators.Tests

import System.Collections.Generic


// Covered-shape synchronous iterators (`func*`) lowered by the N# iterator planner through the
// columnar backend. Every definition here stays inside the covered surface: captured value
// parameters, hoisted typed/inferred locals, while loops, if/else branches, arithmetic and
// comparison operators, `yield`, `yield break`, for..in over array parameters, and guard throws.

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

// Array-driven iterators (sub-slice 4): for..in over a captured array parameter lowers to an index
// loop over hoisted array/index fields.
func* Values(xs: int[]): IEnumerable<int> {
    for x in xs {
        yield x
    }
}

// Mid-array early exit: a guard `yield break` inside the loop.
func* UntilNegative(xs: int[]): IEnumerable<int> {
    for x in xs {
        if x < 0 {
            yield break
        }

        yield x
    }
}

// Filter and transform inside the loop.
func* EvenSquares(xs: int[]): IEnumerable<int> {
    for x in xs {
        if x % 2 == 0 {
            yield x * x
        }
    }
}

// The guard-throw range shape: a lazily-raised ArgumentException plus direction-dependent loops
// whose branches both declare `value` (same-typed disjoint redeclarations share one hoisted slot).
func* RangeBy(start: int, end: int, step: int): IEnumerable<int> {
    if step == 0 {
        throw new ArgumentException("Step cannot be zero")
    }

    if step > 0 {
        value := start
        while value < end {
            yield value
            value = value + step
        }
    } else {
        value := start
        while value > end {
            yield value
            value = value + step
        }
    }
}

// The Fibonacci shape: guard yield breaks, multiple standalone yields, and local rotation.
func* Fib(count: int): IEnumerable<int> {
    if count <= 0 {
        yield break
    }

    a: int = 0
    b: int = 1
    yield a
    if count == 1 {
        yield break
    }

    yield b
    i: int = 2
    while i < count {
        next := a + b
        yield next
        a = b
        b = next
        i = i + 1
    }
}
