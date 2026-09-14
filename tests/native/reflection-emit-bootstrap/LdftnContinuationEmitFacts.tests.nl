namespace NSharpLang.ReflectionEmitBootstrap.Tests

test "ldftn builds an executable instance continuation and names its exact core token" {
    result := LdftnContinuationEmitFacts.EmitAndInvoke()
    assert result.Calls == 1
    assert result.TargetName == "MoveNextCore"
    assert result.TargetOwnerName == "LdftnContinuationOwner"
    assert result.TargetToken == result.CoreToken
    assert result.LdftnCount == 1
    assert result.DelegateTargetsMachine
}
