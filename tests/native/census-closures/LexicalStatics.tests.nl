namespace NSharpLang.CensusClosures.Tests

test "a bare static call inside a lambda in a static member reaches the lexical owner" {
    assert LexicalStaticOwner.BumpThroughLambda(3) == 10
    assert LexicalStaticOwner.BumpThroughLambda(0) == 7
}

test "a lambda body reads the lexical owner's bare static field beside the call" {
    assert LexicalStaticOwner.BumpAndSeedThroughLambda(1) == 15
    assert LexicalStaticOwner.SeedThroughInferredLambda() == 7
}

test "a non-capturing lambda in an instance member reaches the owner's statics" {
    owner := new LexicalStaticOwner(2)
    assert owner.LabelThroughNonCapturingLambda(4) == "4!"
}

test "a capturing lambda still reaches both the captured receiver and the owner's statics" {
    owner := new LexicalStaticOwner(2)
    assert owner.ScaleThroughCapturingLambda(3) == 20
    assert owner.NestedThroughCapturingLambda(3) == 12
}
