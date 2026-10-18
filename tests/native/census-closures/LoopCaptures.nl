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
