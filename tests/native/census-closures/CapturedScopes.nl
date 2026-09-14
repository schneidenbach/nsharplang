namespace NSharpLang.CensusClosures.Tests

import System
import System.Collections.Generic

// THE SCOPES A LAMBDA CAN REACH OUT TO, compiled and RUN by the tip compiler.
//
// A lambda that captures anything runs as an instance method on a display class the capturing scope
// creates. The scope's own captures live in that display's fields; the enclosing RECEIVER, when the
// body needs one, lives in `<>4__this` beside them. A lambda written INSIDE another capturing lambda
// gets its own display, and that display's `<>4__this` holds the PARENT DISPLAY — so one link per
// nesting level, walked until the level that declares the name is reached. Nothing counts levels.
//
// Before this, a lambda capturing BOTH `this` and a local declined at `emit.body`, an expression-
// bodied lambda whose body was another lambda declined at `emit.expression.unhandled-kind` (node
// kind 39), and a lambda nested inside a capturing lambda declined at `emit.body` for want of a
// body root to scan.

// MIXED CAPTURE: the instance and a parameter. `Factor` comes through `<>4__this`, `bonus` from a
// snapshot field beside it.
class Scaler {
    Factor: int
    Label: string

    constructor(factor: int, label: string) {
        Factor = factor
        Label = label
        Scaled = x => x
    }

    func Make(bonus: int): Func<int, int> {
        return x => x * Factor + bonus
    }

    // A member of the instance reached through a LOCAL rather than a parameter is the same read.
    func MakeThroughLocal(seed: int): Func<int, int> {
        offset := seed * 2
        return x => x * Factor + offset
    }

    // The captured receiver serves a bare CALL and a bare FIELD read alike — before this, the call
    // emitted and the read did not.
    func Narrate(suffix: string): Func<int, string> {
        return x => Describe(x) + suffix
    }

    func Describe(value: int): string {
        return Label + value.ToString()
    }

    // A PROPERTY of the enclosing instance, read through the same hop as a field.
    Doubled: int {
        get {
            return Factor * 2
        }
    }

    func MakeFromProperty(bonus: int): Func<int, int> {
        return x => x * Doubled + bonus
    }

    // WRITTEN `this.Member` names the same member the bare name does, and takes the same two hops.
    func MakeExplicit(bonus: int): Func<int, int> {
        return x => x * this.Factor + bonus
    }

    // A CONSTRUCTOR may capture `this` too: `ldarg.0` there is the object under construction, the
    // same reference every later method sees.
    Scaled: Func<int, int>

    constructor(factor: int, label: string, bonus: int) {
        Factor = factor
        Label = label
        Scaled = x => x * Factor + bonus
    }
}

// NESTED LAMBDAS. Each level captures the level above it; the inner display holds the outer display.
func Curried(threshold: int): Func<int, Func<int, bool>> {
    return x => y => y > x + threshold
}

func ThreeDeep(seed: int): Func<int, Func<int, Func<int, int>>> {
    return a => b => c => a + b + c + seed
}

// The same chain written with BLOCK bodies, which lower through the same displays.
func CurriedBlocks(seed: int): Func<int, Func<int, int>> {
    outer: Func<int, Func<int, int>> = a => {
        return b => a + b + seed
    }

    return outer
}

// A nested lambda that captures ONLY the outer lambda's parameter still needs its own display, and
// the outer scope's own capture is reached through the parent display it points at.
func InnerCapturesOuterOnly(): Func<int, Func<int, int>> {
    return a => b => a + b
}

// NESTING INSIDE AN INSTANCE METHOD: the innermost body reaches a parameter, the outer lambda's
// parameter and the instance, which is three different storage tiers in one expression.
class Composer {
    Scale: int

    constructor(scale: int) {
        Scale = scale
    }

    func Curry(bonus: int): Func<int, Func<int, int>> {
        return a => b => (a + b + bonus) * Scale
    }
}

// A MUTATED capture stays one storage location across the display chain: the box the outer scope
// lifted is the box the inner lambda reads.
func SharedCounter(): Func<int, Func<int, int>> {
    total := 0
    return a => b => {
        total = total + a + b
        return total
    }
}

// PER-ITERATION CAPTURE WITH A WRITE, through a display: each pass round the loop binds a new
// `acc`, the write lands in that binding, and the delegate collected there reads its own.
func WrittenPerIterationAdders(count: int): List<Func<int>> {
    adders := new List<Func<int>>()
    for i := 0; i < count; i++ {
        acc := i
        acc = acc + 1
        adders.Add(() => acc * 10)
    }

    return adders
}
