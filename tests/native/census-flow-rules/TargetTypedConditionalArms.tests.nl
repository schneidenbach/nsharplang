namespace NSharpLang.CensusFlowRules.Tests

import System

test "a reference arm and a bare null arm answer in both orders" {
    assert PickReference(true, "a") == "a"
    assert PickReference(false, "a") == null
    assert PickReferenceNullFirst(false, "a") == "a"
    assert PickReferenceNullFirst(true, "a") == null
}

test "a VALUE arm lifts to the target's nullable, which is what the join could not do" {
    assert PickValue(true, 3) == 3
    assert PickValue(false, 3) == null
    assert PickValueNullFirst(false, 3) == 3
    assert PickValueNullFirst(true, 3) == null
    assert PickDefaultArm(true, 3) == 3
    assert PickDefaultArm(false, 3) == null
}

test "a throwing arm against a bare null takes the target's type and still raises" {
    failure := new InvalidOperationException("not ready")
    assert NullOrThrowReference(true, failure) == null
    assert NullOrThrowValue(true, failure) == null
    assert ValueOrThrow(false, 7, failure) == 7

    raised := false
    try {
        ignored := NullOrThrowValue(false, failure)
        assert ignored == null
    } catch caught: InvalidOperationException {
        raised = caught.Message == "not ready"
    }

    assert raised
}

test "the other three target positions decide the same way" {
    assert DeclaredLocal(true, 4) == 4
    assert DeclaredLocal(false, 4) == -1
    assert AssignedLocal(true, 5) == 5
    assert AssignedLocal(false, 5) == -1
    assert ArgumentPosition(true, 9) == 9
    assert ArgumentPosition(false, 9) == -1
}

test "a wider element and an enum element take the same lifted route" {
    twelve: long? = 12
    assert PickLong(true, 12) == twelve
    assert PickLong(false, 12) == null
    assert ShadeOrDefault(PickShade(true, Shade.Dark)) == Shade.Dark
    assert PickShade(false, Shade.Dark) == null
    assert ShadeOrDefault(PickShade(false, Shade.Dark)) == Shade.Light
}
