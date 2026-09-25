namespace NSharpLang.CensusCapturedReceiverArgument.Tests

import System.Collections.Generic

func Sample(): List<string> {
    values := new List<string>()
    values.Add("a")
    values.Add("bb")
    values.Add("ccc")
    return values
}

test "a captured-receiver call reaches the argument of an external static" {
    kept := new Widths(1).ClampedAboveOne(Sample(), 8)
    assert kept.Count == 2
    assert kept[0] == "bb"
    assert kept[1] == "ccc"
}

test "the same argument over a captured field rather than a captured parameter" {
    kept := new Widths(2).ClampedAboveFloor(Sample(), 8)
    assert kept.Count == 1
    assert kept[0] == "ccc"
}

test "a captured-receiver call reaches a generic argument whose type is inferred from it" {
    hashes := new Widths(0).WidthHash(Sample())
    assert hashes.Count == 3
    assert hashes[0] == HashOf(1)
    assert hashes[1] == HashOf(2)
    assert hashes[2] == HashOf(3)
}

test "the controls that bound the subject still emit and still answer" {
    plain := new Widths(0).ClampedPlain(Sample(), 8)
    assert plain.Count == 2
    bare := new Widths(0).WidthAboveOne(Sample())
    assert bare.Count == 2
}

test "the captured-receiver argument runs once per element, left to right" {
    ordered := new OrderedWidths()
    kept := ordered.Run(Sample())
    assert kept.Count == 2
    assert ordered.Steps.Count == 6
    assert ordered.Steps[0] == "width:a"
    assert ordered.Steps[1] == "ceiling"
    assert ordered.Steps[2] == "width:bb"
    assert ordered.Steps[3] == "ceiling"
    assert ordered.Steps[4] == "width:ccc"
    assert ordered.Steps[5] == "ceiling"
}
