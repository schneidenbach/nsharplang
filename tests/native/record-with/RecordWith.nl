namespace NSharpLang.RecordWith.Tests

import System.Collections.Generic

// A reference record. A `with` expression clones through the synthesized `<Clone>$` virtual (a
// MemberwiseClone downcast) and writes each replacement on the cloned object reference. The original
// instance is a distinct object, unaffected by the replacements.
record Point {
    X: int
    Y: int
    Label: string
}

// A value record. A `with` expression copies the receiver value into a fresh local and writes each
// replacement through that copy's ADDRESS. Like a C# record struct it carries NO `<Clone>$` method — a
// value clone virtual would be reached by `callvirt` on a value, which is unverifiable — and the source
// value is never mutated by the copy's replacements.
record struct Rgb {
    R: int
    G: int
    B: int
}

// A positional value record: the same value-copy `with` path over primary-constructor members.
record struct Meters(value: int) {
}

// Records the order in which `with` replacement values are evaluated. Each Tag call appends its ordinal
// and returns the supplied value, so a test can prove left-to-right source-order evaluation.
class EvaluationOrder {
    Ordinals: List<int>

    constructor() {
        Ordinals = new List<int>()
    }

    func Tag(ordinal: int, value: int): int {
        Ordinals.Add(ordinal)
        return value
    }
}

// Value-record `with` in a named method: exercises the value-copy lowering and gives the test assembly an
// emitted method whose result proves the copy is independent of its source.
func WithGreen(source: Rgb, green: int): Rgb {
    return source with { G: green }
}

// Reference-record `with` in a named method: exercises the clone lowering.
func WithX(source: Point, x: int): Point {
    return source with { X: x }
}

// Multiple replacements in one value-record `with`, evaluated through the order probe so the test can
// assert source order.
func RecolorOrdered(source: Rgb, order: EvaluationOrder): Rgb {
    return source with { R: order.Tag(1, 10), G: order.Tag(2, 20), B: order.Tag(3, 30) }
}
