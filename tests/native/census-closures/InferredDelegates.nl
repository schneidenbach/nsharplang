namespace NSharpLang.CensusClosures.Tests

import System
import System.Collections.Generic

// A ZERO-PARAMETER LAMBDA AT AN INFERRING POSITION THAT CAPTURES, AND A LAMBDA ASSIGNED TO STORAGE
// THAT ALREADY EXISTS.
//
// `zero := () => seed` has no delegate target to take a signature from — a zero-parameter lambda
// needs none, because its return type is whatever the body answers. That arm existed and was
// CAPTURE-LESS: the body emitted into a sub-emitter with empty local and parameter maps, so any read
// of an enclosing binding reached the untyped expression door and declined at `emit.body`. The
// display class, the capture copies and the body are now the targeted arm's; only the ORDER differs,
// because the synthesized method's signature is set after the body has said what it returns.
//
// `step = x => x * 10` is the mirror question at the other end: an already-declared local IS storage
// with a written type, and the assignment arm read its right-hand side with no delegate context to
// offer, so a lambda there declined as an unsupported expression (node kind 39) while the
// DECLARATION of the same local emitted.
func CaptureParameter(seed: int): int {
    zero := () => seed
    return zero() + zero()
}

func CaptureLocal(): string {
    prefix := "n="
    label := () => prefix + "1"
    return label()
}

// A MUTATED capture is lifted into a shared box, and the delegate reads the box rather than a copy:
// the write after the lambda was built is the value it answers.
func CaptureMutatedLocal(): int {
    total := 1
    read := () => total * 10
    total = 4
    return read()
}

// A VOID body infers `Action`, not `Func<T>`.
func CaptureIntoAction(): int {
    sink := new List<int>()
    add := () => sink.Add(7)
    add()
    add()
    return sink.Count
}

// A NESTED inferred lambda: the outer one captures a parameter, and the value it answers is itself a
// zero-parameter lambda that captures the outer one's capture through the display above it.
func CaptureThroughTwoDisplays(seed: int): int {
    outer := () => seed + 1
    inner := () => outer() * 2
    return inner()
}

class Ledger {
    Factor: int

    constructor(factor: int) {
        Factor = factor
    }

    // The enclosing INSTANCE and a parameter at once, with no delegate target in sight.
    func Weigh(bonus: int): int {
        weigh := () => Factor * 10 + bonus
        return weigh()
    }
}

// ── a lambda assigned to storage that already exists ───────────────

func ReassignTypedLocal(): int {
    let step: Func<int, int> = x => x * 2
    first := step(4)
    step = x => x * 10
    return first + step(4)
}

// The right-hand side may capture, exactly as a declaration's may.
func ReassignWithCapture(bump: int): int {
    let step: Func<int, int> = x => x
    step = x => x + bump
    return step(1)
}

// A METHOD GROUP is the other contextual delegate value, and it reads the same way at an assignment.
func DoubleValue(value: int): int {
    return value * 2
}

func ReassignFromMethodGroup(): int {
    let step: Func<int, int> = x => x
    step = DoubleValue
    return step(21)
}

// A PARAMETER of delegate type is storage too.
func ReassignParameter(step: Func<int, int>): int {
    step = x => x + 100
    return step(1)
}

// A MUTATED delegate local is lifted into a box the inner lambda shares, so the reassignment made
// through the box is what the reader answers.
func ReassignLiftedDelegate(): int {
    let step: Func<int, int> = x => x * 2
    read := () => step(5)
    step = x => x * 3
    return read()
}
