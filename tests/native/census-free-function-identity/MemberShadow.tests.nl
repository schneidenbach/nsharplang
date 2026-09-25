namespace Census.FreeFunctionIdentity.MemberShadow


test "a member of the enclosing type hides a same-file free function of the same name" {
    shadowing := new Shadowing()
    assert shadowing.Direct() == "member"
    assert shadowing.FromConstructor() == "member"
}

test "a member hides a free function another file of the namespace declares" {
    shadowing := new Shadowing()
    assert shadowing.CrossFile() == "cross-file member"
    assert shadowing.DelegateField() == "delegate member"
}

test "a static member hides a free function from a static body and from an instance body" {
    assert Shadowing.FromStaticBody() == "static member"
    assert new Shadowing().FromInstanceBodyToStatic() == "static member"
}

test "an inherited member hides a free function, from a source base and from an external one" {
    assert new Shadowing().Inherited() == "base member"
    names := new ShadowingNames()
    names.Add("first")
    assert names.HasFirst()
}

test "a lambda, a nested lambda, a local function and a method group in a member body read the member" {
    shadowing := new Shadowing()
    assert shadowing.InLambda() == "member"
    assert shadowing.InNestedLambda() == "member"
    assert shadowing.InLocalFunction() == "member"
    assert shadowing.AsMethodGroup() == "member"
}

test "a struct's member hides a free function of the same name" {
    value := new ShadowingValue()
    assert value.Direct() == "struct member"
}

// A `test` block is a free function of this namespace, so nothing hides the free functions here.
test "outside every type the free function is what the bare name means" {
    assert Label() == 1
    assert Title() == 4
    assert Tag() == 5
    assert Pick() == 6
    assert LabelFromFreeLambda() == 1
    assert Contains("first") == 5
}
