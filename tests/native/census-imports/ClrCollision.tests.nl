namespace Census.Imports.Clr.Tests

import System
import System.Reflection
import Census.Imports.Clr


// A SOURCE TYPE AND A CLR TYPE THAT SHARE A SIMPLE NAME.
//
// `Range` is declared by `System` and by `Census.Imports.Clr`, and this file imports both, so a BARE
// `Range` here is NL209 — the diagnostic contract lives beside the analyzer. What runs here is the
// binding that a qualified spelling produces: each names exactly one of the two, the emitted IL uses
// that one, and the two are different CLR types.
test "a qualified source spelling and a qualified CLR spelling name different types" {
    sourceRange := new Census.Imports.Clr.Range()
    clrRange: System.Range = 1..3

    assert sourceRange.Side() == "source"
    assert clrRange.Start.Value == 1
    assert clrRange.End.Value == 3
}

test "the two Range spellings carry different declaring namespaces in metadata" {
    sourceType: Type = typeof(Census.Imports.Clr.Range)
    clrType: Type = typeof(System.Range)

    assert sourceType.Name == clrType.Name
    assert (sourceType.get_Namespace() ?? "") == "Census.Imports.Clr"
    assert (clrType.get_Namespace() ?? "") == "System"
    assert sourceType.FullName != clrType.FullName
}

test "a qualified CLR spelling still indexes an array the way System.Range does" {
    values: int[] = [10, 20, 30, 40]
    window: System.Range = 1..3
    slice := values[window]

    assert slice.Length == 2
    assert slice[0] == 20
    assert slice[1] == 30
}
