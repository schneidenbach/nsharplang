namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic

func GroupingKeyRows(): List<(Code: string, Amount: int)> {
    rows := new List<(Code: string, Amount: int)>()
    rows.Add((Code: "a", Amount: 1))
    rows.Add((Code: "b", Amount: 2))
    return rows
}

test "a tuple element NAME reads through an IGrouping key" {
    rows := GroupingKeyRows()
    assert GroupingKeyNames.KeyCodes(rows) == "ab"
    assert GroupingKeyNames.KeyAmounts(rows) == 3
}

test "the positional spelling of the same key element still agrees" {
    rows := GroupingKeyRows()
    assert GroupingKeyNames.KeyCodesPositional(rows) == GroupingKeyNames.KeyCodes(rows)
}
