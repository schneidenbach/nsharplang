namespace NSharpLang.CensusEmitShapes.Tests

test "a this-capturing lambda stored by the CONSTRUCTOR reads the instance, not a copy of it" {
    assert GreetingOf("ada") == "ada!"
    assert ShoutOf("ada", "?") == "ada?"

    // And the field really is a field: rebinding it in a method replaces what the constructor stored.
    assert Rebound("ada") == "re:ada"
}

test "a constructor's closure captures its own parameters alongside the instance" {
    assert NextOf(10, 5) == 15
    assert NextOf(0, 1) == 1
}

test "a lambda literal written at a source constructor's argument builds the delegate there" {
    assert RunnerSaying("hi") == "said:hi"
    assert ConstantRunner() == "constant"
}

test "a call whose callee is a VALUE invokes the delegate that value is" {
    assert InvokedDirectly() == "a-y"
    assert InvokedFromAList() == "second-y"
}
