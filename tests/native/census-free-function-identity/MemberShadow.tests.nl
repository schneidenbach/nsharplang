namespace Census.FreeFunctionIdentity.MemberShadow

import System.Collections.Generic

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

test "a member generator reads the member, not the free function it hides" {
    collected := new List<string>()
    for text in new Shadowing().InIterator() {
        collected.Add(text)
    }
    assert collected.Count == 4
    assert collected[0] == "member"
    assert collected[1] == "cross-file member"
    assert collected[2] == "static member"
    assert collected[3] == "base member"

    values := new List<string>()
    for text in new ShadowingValue().InIterator() {
        values.Add(text)
    }
    assert values.Count == 1
    assert values[0] == "struct member"

    names := new ShadowingNames()
    names.Add("first")
    presence := new List<bool>()
    for present in names.Presence() {
        presence.Add(present)
    }
    assert presence.Count == 1
    assert presence[0]
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
