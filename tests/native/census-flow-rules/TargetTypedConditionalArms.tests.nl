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

test "a typeless arm reaches a method the emitter binds by its arguments, in both arm orders" {
    assert StaticNullFirst(true, "a") == "none:1"
    assert StaticNullFirst(false, "a") == "a:1"
    assert StaticNullSecond(true, "b") == "b:2"
    assert StaticNullSecond(false, "b") == "none:2"
    assert FrameworkStatic(true, "x")
    assert !FrameworkStatic(false, "x")
    assert !FrameworkStaticNullSecond(true, "x")
    assert FrameworkStaticNullSecond(false, "x")
}

test "a derived arm reaches a base parameter, a value arm a lifted one, and an instance method takes it too" {
    assert DerivedArm(true, new Circle("c")) == "<none>"
    assert DerivedArm(false, new Circle("c")) == "c"
    assert LiftedArm(true, 3) == -1
    assert LiftedArm(false, 3) == 3
    describer := new Describer("p")
    assert InstanceArgument(true, describer, "!") == "p"
    assert InstanceArgument(false, describer, "!") == "p!"
}

test "a typeless arm takes the type of the overload its other arm chooses" {
    assert MeasureDefaultFirst(true, 3) == -1
    assert MeasureDefaultFirst(false, 3) == 3
    assert MeasureDefaultSecond(true, "four") == 4
    assert MeasureDefaultSecond(false, "four") == -2
    assert MeasureNullFirst(true, 3) == -1
    assert MeasureNullFirst(false, 3) == 3
    assert MeasureNullSecond(true, "four") == 4
    assert MeasureNullSecond(false, "four") == -2
}

test "a default arm is null or zero as the chosen parameter says, static and instance alike" {
    assert PlainDefault(true, 5) == 100
    assert PlainDefault(false, 5) == 105
    meter := new Meter(10)
    assert ShiftDefault(true, meter, 5) == 9
    assert ShiftDefault(false, meter, 5) == 15
    assert ShiftNull(true, meter, "ab") == -5
    assert ShiftNull(false, meter, "ab") == 12
}

test "a default arm reaches a framework method, as a reference and as a value" {
    assert FrameworkStaticDefault(true, "x")
    assert !FrameworkStaticDefault(false, "x")
    assert FrameworkValueDefault(true, 8) == 0
    assert FrameworkValueDefault(false, 8) == 8
}
