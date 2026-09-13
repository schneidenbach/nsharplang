namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic

func TupleDiagnostics(): List<Diag> {
    diagnostics := new List<Diag>()
    diagnostics.Add(new Diag { Code: "NL103", Line: 4 })
    diagnostics.Add(new Diag { Code: "NL202", Line: 9 })
    diagnostics.Add(new Diag { Code: "NL103", Line: 4 })
    return diagnostics
}

func TupleItems(): List<Item> {
    items := new List<Item>()
    items.Add(new Item { Name: "alpha" })
    items.Add(new Item { Name: "beta" })
    items.Add(new Item { Name: "alpha" })
    return items
}

test "a tuple literal assigned into a tuple-typed local over a source type emits" {
    assert GroupSizes(TupleItems()) == 3
}

test "the same tuple is a typed local's initializer" {
    assert PairedName(new Item { Name: "alpha" }) == "alpha:1"
}

test "a lambda whose body is a tuple literal infers the extension's result type" {
    pairs := Pairs(TupleDiagnostics())
    assert pairs.Count == 3
    assert FirstCode(TupleDiagnostics()) == "NL103"
    assert TotalLines(TupleDiagnostics()) == 17
}

test "the positional spelling produces the same tuple" {
    positional := PositionalPairs(TupleDiagnostics())
    assert positional.Count == 3
    assert positional[0].Item1 == "NL103"
    assert positional[1].Item2 == 9
}

test "a tuple literal is a grouping key" {
    assert GroupCount(TupleDiagnostics()) == 2
    assert FirstGroupKeyCode(TupleDiagnostics()) == "NL103"
}
