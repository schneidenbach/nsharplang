namespace NSharpLang.Conditional.Tests

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
