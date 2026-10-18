namespace NSharpLang.CensusClosures.Tests

import System
import System.Collections.Generic
import System.Text

// A LAMBDA THAT CAPTURES A LOOP VARIABLE, and a lambda whose body is an object initializer reading a
// capture.
//
// `for x in xs` declares a FRESH `x` per iteration, so each closure sees its own value. A classic
// `for i := 0; ...; i++` declares ONE `i` for the whole loop, so every closure sees the one variable
// (C# semantics, checked against Roslyn's `ForStatement` / `ForEachStatement` lowering).
class Opts {
    N: int
}

func ExistsInLoop(xs: List<int>, ys: List<int>): int {
    hits := 0
    for x in xs {
        if ys.Exists(y => y == x) {
            hits++
        }
    }
    return hits
}

func TypedLocalInLoop(xs: List<int>): int {
    total := 0
    for x in xs {
        f: Func<int, bool> = y => y == x
        if f(2) {
            total++
        }
    }
    return total
}

func ClassicForExists(ys: List<int>): int {
    hits := 0
    for i := 0; i < 3; i++ {
        if ys.Exists(y => y == i) {
            hits++
        }
    }
    return hits
}

// Each `for ... in` iteration captures its own `x`: invoking after the loop sees 1, 2, 3.
func ForeachClosuresAfterLoop(): List<int> {
    fs := new List<Func<int>>()
    for x in [1, 2, 3] {
        fs.Add(() => x)
    }
    result := new List<int>()
    for f in fs {
        result.Add(f())
    }
    return result
}

// The classic `for` variable is shared: after the loop every closure sees the final value 3.
func ClassicForClosuresAfterLoop(): List<int> {
    fs := new List<Func<int>>()
    for i := 0; i < 3; i++ {
        fs.Add(() => i)
    }
    result := new List<int>()
    for f in fs {
        result.Add(f())
    }
    return result
}

// A `while` counter that closures capture is the same single shared variable.
func WhileCounterClosuresAfterLoop(): List<int> {
    fs := new List<Func<int>>()
    n := 0
    while n < 3 {
        fs.Add(() => n)
        n++
    }
    result := new List<int>()
    for f in fs {
        result.Add(f())
    }
    return result
}

func CollectAfter(fs: List<Func<int>>): List<int> {
    result := new List<int>()
    for f in fs {
        result.Add(f())
    }
    return result
}

// The step forms: each classic-for variable is still one variable, observed at its final value.
func DecrementClosures(): List<int> {
    fs := new List<Func<int>>()
    for i := 3; i > 0; i-- {
        fs.Add(() => i)
    }
    return CollectAfter(fs)
}

func CompoundAddClosures(): List<int> {
    fs := new List<Func<int>>()
    for i := 0; i < 5; i += 2 {
        fs.Add(() => i)
    }
    return CollectAfter(fs)
}

func CompoundSubtractClosures(): List<int> {
    fs := new List<Func<int>>()
    for i := 4; i > 0; i -= 1 {
        fs.Add(() => i)
    }
    return CollectAfter(fs)
}

func PrefixIncrementClosures(): List<int> {
    fs := new List<Func<int>>()
    for i := 0; i < 3; ++i {
        fs.Add(() => i)
    }
    return CollectAfter(fs)
}

// A closure that writes the shared counter is seen by the loop that owns it.
func ClosureMutatesCounter(): int {
    steps := 0
    for i := 0; i < 10; i++ {
        bump: Action = () => { i = i + 4 }
        if i == 0 {
            bump()
        }
        steps++
    }
    return steps
}

// Closures written before and after a closure mutates the counter all observe its final storage.
func SharedCounterAfterMutation(): List<int> {
    fs := new List<Func<int>>()
    for i := 0; i < 10; i++ {
        fs.Add(() => i)
        if i == 0 {
            bump: Action = () => { i += 4 }
            bump()
        }
    }
    return CollectAfter(fs)
}

// Two loops may reuse a name; each has its own variable.
func SequentialLoopsSameName(): List<int> {
    fs := new List<Func<int>>()
    for i := 0; i < 2; i++ {
        fs.Add(() => i)
    }
    for i := 10; i < 12; i++ {
        fs.Add(() => i)
    }
    return CollectAfter(fs)
}

// A closure inside a closure reaches the same shared variable.
func ClosureInsideClosure(): List<int> {
    fs := new List<Func<int>>()
    for i := 0; i < 3; i++ {
        fs.Add(() => {
            inner: Func<int> = () => i + 100
            return inner()
        })
    }
    return CollectAfter(fs)
}

func ForeachInsideClassicFor(): List<int> {
    fs := new List<Func<int>>()
    for i := 0; i < 2; i++ {
        for x in [10, 20] {
            fs.Add(() => x + i)
        }
    }
    return CollectAfter(fs)
}

func ForeachAssignsLoopVariable(): List<int> {
    fs := new List<Func<int>>()
    for x in [1, 2, 3] {
        x = x + 10
        fs.Add(() => x)
    }
    return CollectAfter(fs)
}

func NestedLoopClosures(): List<int> {
    fs := new List<Func<int>>()
    for i := 1; i <= 2; i++ {
        for j := 10; j <= 20; j += 10 {
            fs.Add(() => i + j)
        }
    }
    return CollectAfter(fs)
}

func CapturedOutResult(): int {
    x := 1
    f: Func<int> = () => {
        SetCaptured(out x, x + 1)
        return x
    }
    first := f()
    x = 5
    return first * 100 + f()
}

func SetCaptured(out value: int, next: int) {
    value = next
}

class Sized {
    Size: int
    Label: string

    constructor(size: int) {
        Size = size
        Label = "s"
    }
}

// The constructor arguments of an initializer's `new` capture; its member names do not.
func InitializerConstructorCapture(limit: int): int {
    f: Func<string, Sized> = key => new Sized(limit) { Label: key }
    return f("a").Size
}

func AnonymousObjectCapture(limit: int): int {
    f: Func<string, int> = key => (new { N: limit }).N
    return f("a")
}

func InitializerCapture(limit: int): int {
    f: Func<string, Opts> = key => new Opts { N: limit }
    return f("a").N
}

func InitializerCaptureLocal(): int {
    limit := 5
    f: Func<string, Opts> = key => new Opts { N: limit }
    return f("a").N
}

func InitializerCaptureInline(limit: int): int {
    return Apply(key => new Opts { N: limit + key.Length })
}

func Apply(make: Func<string, Opts>): int {
    return make("ab").N
}

func InitializerCaptureExternal(limit: int): int {
    f: Func<string, StringBuilder> = key => new StringBuilder { Capacity: limit }
    return f("a").Capacity
}
