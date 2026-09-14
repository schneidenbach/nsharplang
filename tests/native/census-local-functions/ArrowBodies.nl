namespace NSharpLang.CensusLocalFunctions.Tests

import System
import System.Collections.Generic


// A LOCAL FUNCTION'S ARROW BODY — the same body every other function is allowed to have.
//
// `func inner(v: string?): string => v ?? "d"` used to decline its WHOLE enclosing function at
// `parse.function`: the statement kernel that skips a local function's declaration scanned for `{`
// and refused when there was none, so a local function could only ever be written with braces. The
// signature and body kernels behind it already read an expression body — only the SKIP did not.
//
// A `void` arrow is part of that same body. An expression body used to be lowered as `return <expr>`
// whatever the declared return was, so a `void` one emitted a value return from a void method and
// declined at `emit.body`. What the arrow means is the declared return's decision: a value function
// RETURNS the expression, a `void` one PERFORMS it.

// THE PLAIN EXPRESSION BODY.
func PickOrDefault(name: string?): string {
    func inner(v: string?): string => v ?? "d"
    return inner(name)
}

// A BODY WHOSE END ONLY THE EXPRESSION PARSER KNOWS — the arrow body ends where its EXPRESSION ends,
// not at a brace or a line break. (The multi-line spelling is pinned in the parser estate, beside
// `ColumnarFunctionBodyShapeProbe`; the formatter's canonical form for this one is a single line.)
func SumAcross(a: int, b: int): int {
    func add(x: int, y: int): int => x + y

    return add(a, b)
}

// A `void` ARROW. `sink.Add(x)` produces nothing, so the body is performed, not returned.
func PushTwice(sink: List<int>, v: int): int {
    func push(x: int): void => sink.Add(x)
    push(v)
    push(v + 1)
    return sink.Count
}

// A `static` LOCAL FUNCTION with an arrow body: the modifier prefix sits before the `func` keyword
// and the span the kernel records has to cover it.
func TripleIt(a: int): int {
    static func triple(x: int): int => x * 3
    return triple(a)
}

// MUTUAL RECURSION between two arrow bodies — the block rule and the arrow body at once.
func IsEvenByArrow(n: int): bool {
    func even(x: int): bool => x == 0 ? true : odd(x - 1)
    func odd(x: int): bool => x == 0 ? false : even(x - 1)
    return even(n)
}

// ARROW AND BLOCK BODIES IN ONE SCOPE, calling each other.
func MixedBodies(a: int): int {
    func doubled(x: int): int => x * 2
    func plusOne(x: int): int {
        return x + 1
    }

    return plusOne(doubled(a))
}

// A CAPTURING arrow body: the captured local is lifted into the same display a block-bodied local
// function's capture would use.
func DecorateWith(prefix: string, name: string): string {
    func decorate(v: string): string => prefix + v
    return decorate(name)
}

// A PARAMETER DEFAULT THAT IS ITSELF A LAMBDA. Its `=>` belongs to the SIGNATURE, so the scan for
// the body's arrow has to be depth-aware: reading the first `=>` anywhere would cut the declaration
// in half at the default.
func ApplyOrIdentity(a: int, f: Func<int, int>?): int {
    func apply(x: int, g: Func<int, int>? = null): int => g == null ? x : g(x)
    return apply(a, f)
}

// AN ARROW BODY AHEAD OF THE STATEMENTS THAT USE IT, which is the block-scoping rule meeting the
// arrow body: the call is written above the declaration.
func CallAboveArrowDeclaration(n: int): int {
    computed := scaled(n)
    func scaled(x: int): int => x * 10

    return computed
}

// A FREE FUNCTION'S OWN `void` ARROW, so the lowering is pinned for both owners: the body kernel is
// shared, and a regression that only fixed local functions would leave this one declining.
func AppendTo(sink: List<int>, v: int): void => sink.Add(v)

// `continue` INSIDE A `for`, IN A LOCAL FUNCTION'S BODY. Reported as a suspected decline from an
// emitter-class body; it is neither a tip gap nor a stage-0 one — the compiler's own source carries
// 262 such sites — so this pins it rather than lifting anything.
func CountNonZero(values: int[]): int {
    func count(vs: int[]): int {
        total := 0
        for i := 0; i < vs.Length; i++ {
            if vs[i] == 0 {
                continue
            }

            total = total + 1
        }

        return total
    }

    return count(values)
}
