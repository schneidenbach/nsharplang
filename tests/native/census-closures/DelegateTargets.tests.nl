namespace NSharpLang.CensusClosures.Tests

test "a static method group converts to a Delegate parameter" {
    assert StaticGroupName() == "Twice"
    assert StaticGroupResult() == 42
}

test "a free function group converts to a Delegate parameter" {
    assert SiblingGroupResult() == 15
}

test "an instance method group converts to a Delegate parameter bound to its receiver" {
    assert InstanceGroupResult() == 20
}

test "a void method group takes the natural Action type" {
    assert VoidGroupParameterCount() == 0
}

test "a delegate value converts with as Delegate" {
    assert AsDelegateResult() == 10
}

test "a typed delegate local still converts to a Delegate parameter" {
    assert TypedLocalResult() == 16
}
