namespace NSharpLang.Conditional.Tests

import System

// Boolean short-circuit truth tables — operands are Boolean parameters, owned end-to-end.
func And(a: bool, b: bool): bool {
    return a && b
}

func Or(a: bool, b: bool): bool {
    return a || b
}

// The short-circuit result persisted through a local before the return.
func AndPersisted(a: bool, b: bool): bool {
    result := a && b
    return result
}

func OrPersisted(a: bool, b: bool): bool {
    result := a || b
    return result
}

// Nested short-circuit: precedence groups this as `(a && b) || c`.
func AndThenOr(a: bool, b: bool, c: bool): bool {
    return a && b || c
}

// A short-circuit condition feeding a ternary; the arms are ints.
func SelectByBoth(a: bool, b: bool, whenTrue: int, whenFalse: int): int {
    return a && b ? whenTrue : whenFalse
}

// A ternary whose condition is a comparison (a primitive binary); the arms are ints.
func MaxOfTwo(left: int, right: int): int {
    return left >= right ? left : right
}

// A ternary with reference-typed (string) arms.
func Label(flag: bool): string {
    return flag ? "yes" : "no"
}

// A nested ternary inside a short-circuit operand: `(cond ? x : y) && z`.
func NestedTernaryInAnd(cond: bool, x: bool, y: bool, z: bool): bool {
    return (cond ? x : y) && z
}

// Recursive range/index use: a ternary selecting the index of an array read.
func SelectElement(chooseFirst: bool): int {
    values := [10, 20, 30]
    return values[chooseFirst ? 0 : 1]
}

// A probe that counts how many times its right-operand method is evaluated.
class SideEffectProbe {
    RightEvaluations: int

    constructor() {
        this.RightEvaluations = 0
    }

    func Note(value: bool): bool {
        this.RightEvaluations = this.RightEvaluations + 1
        return value
    }
}

// `&&` must NOT evaluate the right operand when the left is false. Returns the evaluation count,
// plus 100 when the combined result was true (so both the short-circuit and the result are proven).
func AndRightEvaluations(left: bool): int {
    probe := new SideEffectProbe()
    outcome := left && probe.Note(true)
    if outcome {
        return probe.RightEvaluations + 100
    }
    return probe.RightEvaluations
}

// `||` must NOT evaluate the right operand when the left is true.
func OrRightEvaluations(left: bool): int {
    probe := new SideEffectProbe()
    outcome := left || probe.Note(false)
    if outcome {
        return probe.RightEvaluations + 100
    }
    return probe.RightEvaluations
}

// A REFERENCE `??` IN AN ARGUMENT POSITION, WHICH IS THE ONE SHAPE THAT HAD NO SCHEMA-V3 SPELLING.
//
// An argument's type is decided through an expression plan, and the reference `??` arm was written
// with `dup`/`pop` — opcodes only a method-body plan admits. So an argument containing one could not
// be TYPED, and a call whose arguments have no types cannot have an overload chosen from them. Every
// API the residual emitter models by name hid it; a GENERIC method, whose type arguments are
// inferred from the argument types, had nothing to fall back on and answered "not modeled".
func HashOfCoalesced(value: string?): int {
    hash := new HashCode()
    hash.Add(value ?? "fallback")
    return hash.ToHashCode()
}

func HashOfPlain(value: string): int {
    hash := new HashCode()
    hash.Add(value)
    return hash.ToHashCode()
}

func CombineCoalesced(value: string?, count: int): int {
    return HashCode.Combine(value ?? "fallback", count)
}

// The LEFT is evaluated exactly once whichever way the test goes — the parked form reloads it rather
// than recomputing it, which a counting probe is the only way to observe.
class CoalesceProbe {
    Reads: int
    Answer: string?

    constructor(answer: string?) {
        Reads = 0
        Answer = answer
    }

    func Read(): string? {
        Reads = Reads + 1
        return Answer
    }
}

func CoalesceLeftEvaluations(answer: string?): int {
    probe := new CoalesceProbe(answer)
    hash := new HashCode()
    hash.Add(probe.Read() ?? "fallback")
    return probe.Reads
}
