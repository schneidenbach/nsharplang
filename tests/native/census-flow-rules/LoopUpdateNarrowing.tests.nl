namespace NSharpLang.CensusFlowRules.Tests


test "a for update walks a base chain under the condition that proved it" {
    chain := new ChainDef("ab", new ChainDef("c", null))
    assert ChainNameLength(chain) == 3
    assert ChainNameLength(null) == 0
}

test "a for update reads a proved Nullable<T> as its T" {
    assert CountDownSteps(3) == 4
    assert CountDownSteps(null) == 0
    assert BoundedSteps(3, 10) == 4
    assert BoundedSteps(null, 10) == 0
}
