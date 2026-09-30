namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic

func chainSnapshot(): Snapshot {
    units := new List<int>()
    units.Add(4)
    units.Add(9)
    return new Snapshot(units, "  hey  ")
}

test "a value result after a conditional link is lifted and short-circuits" {
    assert UnitCountOrZero(chainSnapshot()) == 2
    assert UnitCountOrZero(null) == 0
}

test "a lifted chain stored in a local compares against null" {
    assert UnitCountOrMinusOne(chainSnapshot()) == 2
    assert UnitCountOrMinusOne(null) == -1
    assert must UnitCountLocal(chainSnapshot()) == 2
    assert UnitCountLocal(null) == null
}

test "a reference result after a conditional link is maybe-null" {
    assert TrimmedNameOrDefault(chainSnapshot()) == "hey"
    assert TrimmedNameOrDefault(null) == "none"
}

test "an invocation the guard short-circuits is itself lifted" {
    assert TrimmedOrDefault("  ok  ") == "ok"
    assert TrimmedOrDefault(null) == "none"
}

test "two conditional links in one chain make one lifted result" {
    assert InnerUnitCountOrZero(new Holder(chainSnapshot())) == 2
    assert InnerUnitCountOrZero(new Holder(null)) == 0
    assert InnerUnitCountOrZero(null) == 0
}

test "an index in the continuation is guarded by the chain" {
    assert FirstUnitOrZero(chainSnapshot()) == 4
    assert FirstUnitOrZero(null) == 0
}

test "a continuation reached through a call in the chain is still guarded" {
    assert TrimmedNameLengthOrZero(chainSnapshot()) == 3
    assert TrimmedNameLengthOrZero(null) == 0
}

test "a parenthesis ends the chain and the code after it guards itself" {
    assert ParenthesisedChainLength(chainSnapshot()) == 7
    assert ParenthesisedChainLength(null) == 0
}
