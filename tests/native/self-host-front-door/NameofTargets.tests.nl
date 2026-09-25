namespace NSharpLang.SelfHostFrontDoor

test "nameof answers the last segment of a method group, qualified or not" {
    assert NameofTargets.StaticMethodName() == "Helper"
    assert NameofTargets.QualifiedMethodName() == "Helper"
    assert NameofTargets.OverloadedMethodName() == "Overloaded"
    assert NameofTargets.ExternalMethodName() == "Join"
}

test "nameof answers a value member, an event and a local the same way" {
    assert NameofTargets.ValueMemberName() == "Instance"
    assert NameofTargets.EventName() == "Changed"
    assert NameofTargets.LocalName() == "total"
}
