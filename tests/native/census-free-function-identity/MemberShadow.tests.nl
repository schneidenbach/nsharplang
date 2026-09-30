namespace Census.FreeFunctionIdentity.MemberShadow

import System.Collections.Generic

test "an explicit member receiver preserves behavior beside a same-file free function" {
    shadowing := new Shadowing()
    assert shadowing.Direct() == "member"
    assert shadowing.SameNamespaceFreeFunction() == 1
    assert shadowing.FromConstructor() == "member"
}

test "an explicit member receiver preserves behavior beside a cross-file free function" {
    shadowing := new Shadowing()
    assert shadowing.CrossFile() == "cross-file member"
    assert shadowing.DelegateField() == "delegate member"
}

test "a type-qualified static member preserves behavior beside a free function" {
    assert Shadowing.FromStaticBody() == "static member"
    assert new Shadowing().FromInstanceBodyToStatic() == "static member"
}

test "an explicit inherited member receiver preserves behavior beside free functions" {
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

test "a struct's explicit member receiver preserves behavior beside a free function" {
    value := new ShadowingValue()
    assert value.Direct() == "struct member"
}

test "a member generator's explicit receivers preserve behavior beside free functions" {
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

// A `test` block is outside any type, so it can use these free functions by their bare names.
test "outside every type the free function is what the bare name means" {
    assert Label() == 1
    assert Title() == 4
    assert Tag() == 5
    assert Pick() == 6
    assert LabelFromFreeLambda() == 1
    assert Contains("first") == 5
}
