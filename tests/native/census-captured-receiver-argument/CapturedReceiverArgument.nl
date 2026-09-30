namespace NSharpLang.CensusCapturedReceiverArgument.Tests

import System
import System.Collections.Generic
import System.Linq

// A CALL ON THE CAPTURED ENCLOSING INSTANCE, WRITTEN AS AN ARGUMENT INSIDE A LAMBDA.
//
// The emitter has an arm for a bare-name call that resolves on the captured enclosing instance, and
// the preflight — which is what types a call's arguments before an overload is chosen from them —
// had no twin for it. So `Width(p)` written in a lambda body EMITTED on its own and could not be
// TYPED, and every call that types its arguments refused an argument written that way. The subjects
// are the combination and the controls that bound it: the same static with a plain argument, the
// same instance call outside an argument, and the same argument over a captured field.
class Widths {
    Floor: int

    constructor(floor: int) {
        Floor = floor
    }

    func Width(value: string): int {
        return value.Length
    }

    // The subject: an external STATIC whose argument is a call on the captured receiver.
    func ClampedAboveOne(values: List<string>, ceiling: int): List<string> {
        return values.Where(v => Math.Clamp(Width(v), 0, ceiling) > 1).ToList()
    }

    // The same, with the second argument a captured FIELD rather than a captured parameter.
    func ClampedAboveFloor(values: List<string>, ceiling: int): List<string> {
        return values.Where(v => Math.Clamp(Width(v), 0, ceiling) > Floor).ToList()
    }

    // A GENERIC external instance method, whose type argument is inferred from that argument alone.
    func WidthHash(values: List<string>): List<int> {
        return values.Select(v => HashOf(Width(v))).ToList()
    }

    // Controls that already emitted and must keep emitting.
    func ClampedPlain(values: List<string>, ceiling: int): List<string> {
        return values.Where(v => Math.Clamp(v.Length, 0, ceiling) > 1).ToList()
    }

    func WidthAboveOne(values: List<string>): List<string> {
        return values.Where(v => Width(v) > 1).ToList()
    }
}

func HashOf(value: int): int {
    hash := new HashCode()
    hash.Add(value)
    return hash.ToHashCode()
}

// EVALUATION ORDER, RECORDED. The captured receiver's method and the lambda parameter's own read
// each note themselves, so the order and the count are stated rather than inspected.
class OrderedWidths {
    Steps: List<string> = new List<string>()

    func Width(value: string): int {
        Steps.Add("width:" + value)
        return value.Length
    }

    func Ceiling(): int {
        Steps.Add("ceiling")
        return 8
    }

    func Run(values: List<string>): List<string> {
        return values.Where(v => Math.Clamp(Width(v), 0, Ceiling()) > 1).ToList()
    }
}
