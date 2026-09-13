namespace NSharpLang.CensusLocalFunctions.Tests

import System
import System.Collections.Generic

// THE SOURCE SHAPES A LOCAL FUNCTION'S CAPTURE MAKES LEGAL, compiled and RUN by the tip compiler.
//
// A local function and a lambda are one closure model. A capture-free local function is still a
// plain method; one that reads or writes an enclosing local or parameter becomes an instance method
// of a display class created for the declaring scope, and the captured binding lives in a shared box
// that display holds — so a write on either side is seen by the other. One that captures only the
// enclosing instance is an instance method of the declaring type, which is where `this` comes from.
//
// Before this, every one of these declined at `emit.return.expression` or
// `emit.statement.block-child`: the local function was a private static with nowhere to read from.

// THE CENSUS PROBE. `visit` reads and writes two enclosing locals and recurses.
func Walk(items: List<string>): int {
    total := 0
    seen := new List<string>()

    func visit(value: string) {
        if seen.Contains(value) {
            return
        }

        seen.Add(value)
        total = total + value.Length
        if value.Length > 1 {
            visit(value.Substring(1))
        }
    }

    for item in items {
        visit(item)
    }

    return total
}

// MUTUAL RECURSION THROUGH CAPTURED STATE. Both halves write the same counter, so the answer proves
// the two display methods share one box rather than each holding a copy.
func CountSteps(n: int): int {
    steps := 0

    func even(value: int): bool {
        steps = steps + 1
        if value == 0 {
            return true
        }

        return odd(value - 1)
    }

    func odd(value: int): bool {
        steps = steps + 1
        if value == 0 {
            return false
        }

        return even(value - 1)
    }

    if even(n) {
        return steps
    }

    return 0 - steps
}

// A WRITE MADE BETWEEN THE DECLARATION AND THE CALL is seen by the local function, and a write the
// local function makes is seen afterwards. A by-value snapshot would fail both halves.
func SharedStorage(seed: int): int {
    value := seed

    func doubleIt() {
        value = value * 2
    }

    value = value + 1
    doubleIt()
    return value
}

// A CAPTURED PARAMETER. The parameter is boxed at the body's start, so the local function's write
// lands in the same slot the body reads afterwards.
func BumpParameter(start: int): int {
    func bump() {
        start = start + 10
    }

    bump()
    bump()
    return start
}

// NESTED SCOPES. `outer` captures a body local; `inner` captures another and calls `outer`.
func TwoScopes(seed: int): int {
    scale := seed
    offset := 100

    func scaled(value: int): int {
        return value * scale
    }

    func shifted(value: int): int {
        return scaled(value) + offset
    }

    return shifted(3)
}

// A CAPTURE-FREE LOCAL FUNCTION keeps the plain lowering — no display class is created for it.
func Doubled(n: int): int {
    func twice(x: int): int {
        return x * 2
    }

    return twice(n)
}

// A CAPTURING LOCAL FUNCTION CONVERTED TO A DELEGATE binds the delegate to the display the body
// created, so the delegate and the body keep sharing one box after the body returns.
func MakeAdder(seed: int): Func<int, int> {
    offset := seed

    func add(value: int): int {
        return value + offset
    }

    return add
}

// The same conversion in the two other positions a delegate is written in.
func AddThroughLocalVariable(seed: int, value: int): int {
    offset := seed

    func add(x: int): int {
        return x + offset
    }

    let adder: Func<int, int> = add
    return adder(value)
}

func MapThroughArgument(values: List<int>, seed: int): List<int> {
    offset := seed

    func add(x: int): int {
        return x + offset
    }

    return values.ConvertAll(add)
}

// PER-ITERATION CAPTURE. A local declared inside the loop is a new binding each time round, so each
// delegate collected here closes over its own — C#'s rule, observed through the collected delegates.
func PerIterationAdders(count: int): List<Func<int>> {
    adders := new List<Func<int>>()
    for i := 0; i < count; i++ {
        step := i * 10
        adders.Add(() => step)
    }

    return adders
}

// A LOCAL FUNCTION'S PARAMETER MAY REUSE A NAME A NESTED BLOCK BINDS. The loop's `item` and the
// local function's `item` never share a scope, so neither shadows the other.
func TotalLengths(items: List<string>): int {
    total := 0

    func add(item: string) {
        total = total + item.Length
    }

    for item in items {
        add(item)
    }

    return total
}

// `this` CAPTURE IN A CLASS. `bump` reads and writes an instance field and captures nothing else, so
// it is an instance method of Walker and its `this` is the receiver the call site passes.
class Walker {
    Count: int

    func Run(items: List<string>) {
        func bump(value: string) {
            Count = Count + value.Length
        }

        for item in items {
            bump(item)
        }
    }

    func Reset() {
        func clear() {
            Count = 0
        }

        clear()
    }
}

// `this` AND A LOCAL together: the display carries `<>4__this`, and the instance METHOD call inside
// the local function goes through it.
class Scaler {
    Factor: int

    func Scale(values: List<int>, bonus: int): int {
        total := 0

        func accumulate(value: int) {
            total = total + Multiply(value) + bonus
        }

        for value in values {
            accumulate(value)
        }

        return total
    }

    func Multiply(value: int): int {
        return value * Factor
    }
}

// A STRUCT's local function that reads `this` is an instance method of the struct, so it receives the
// receiver by reference — C#'s rule for a capturing local function in a value type.
struct Reading {
    Value: int

    func PlusOffset(offset: int): int {
        func read(extra: int): int {
            return Value + extra
        }

        return read(offset)
    }
}
