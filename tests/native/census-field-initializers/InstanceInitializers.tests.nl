namespace NSharpLang.CensusFieldInitializers.Tests

import System.Reflection

test "every census instance initializer shape produces its value at runtime" {
    value := new InstanceCensus()
    assert value.Scale == 7
    assert value.Label == "ab"
    assert value.Limit == 2147483647
    assert value.Negative == -1
    assert value.Names != null
    assert value.Names.Count == 0
    assert value.Mutable == 10
}

test "a field initializer over primary-constructor parameters is an ordinary expression" {
    box := new Boxed(3, 4)
    assert box.Width == 3
    assert box.Area == 12
}

test "a readonly instance field with an initializer is initonly in metadata" {
    scaleField := typeof(InstanceCensus).GetField("Scale", BindingFlags.Public | BindingFlags.Instance)
    mutableField := typeof(InstanceCensus).GetField("Mutable", BindingFlags.Public | BindingFlags.Instance)
    assert scaleField != null, "the readonly field Scale must be present"
    assert mutableField != null, "the mutable field Mutable must be present"
    if scaleField != null {
        assert scaleField.get_IsInitOnly(), "a readonly instance field must be emitted initonly"
    }
    if mutableField != null {
        assert !mutableField.get_IsInitOnly(), "a mutable instance field must not be emitted initonly"
    }
}

test "instance field initializers run before the base constructor call and before the derived body" {
    derived := new OrderDerived()
    // C# order: the derived type's field initializers, then the base constructor, then the derived body.
    assert derived.Marker == 13
    assert OrderTrace.Log == "derived-init;base-ctor;derived-body;"
    // The base constructor already saw the derived initializer's effect when it ran.
    assert derived.Trace == "derived-init;base-ctor;"
}

test "a nullable field with no initializer defaults to null beside an initialized field" {
    value := new NullableDefaults()
    assert value.Tokens == null
    assert value.Names == null
    assert value.Count == 4
    assert value.Label == "set"
}
