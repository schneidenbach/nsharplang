namespace NSharpLang.CensusFlowRules.Tests

test "a while body reads its condition's narrowed nullable before writing it" {
    assert WhileBodyNarrowing(3) == 6
    assert WhileBodyNarrowing(2) == 3
    assert WhileBodyNarrowing(null) == 0
}

test "a for body reads its condition's narrowed nullable before writing it" {
    assert ForBodyNarrowing(3) == 6
    assert ForBodyNarrowing(2) == 3
    assert ForBodyNarrowing(null) == 0
}

test "a while continue write leaves the other path narrowed and exits on null" {
    assert WhileContinueBeforeWrite(5) == 9
    assert WhileContinueBeforeWrite(null) == 0
}

test "a for continue write leaves the other path narrowed and exits on null" {
    assert ForContinueBeforeWrite(5) == 9
    assert ForContinueBeforeWrite(null) == 0
}
