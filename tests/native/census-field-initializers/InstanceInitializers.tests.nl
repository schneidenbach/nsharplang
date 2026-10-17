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

// A `readonly` member stays a FIELD, and an exported mutable one is an AUTO-PROPERTY whose storage is
// an ordinary writable backing field — the initializer runs into that storage either way.
test "a readonly instance field with an initializer is initonly in metadata" {
    scaleField := typeof(InstanceCensus).GetField("Scale", BindingFlags.Public | BindingFlags.Instance)
    mutableProperty := typeof(InstanceCensus).GetProperty("Mutable", BindingFlags.Public | BindingFlags.Instance)
    mutableStorage := typeof(InstanceCensus).GetField("<Mutable>k__BackingField", BindingFlags.NonPublic | BindingFlags.Instance)
    assert scaleField != null, "the readonly field Scale must be present"
    assert typeof(InstanceCensus).GetField("Mutable", BindingFlags.Public | BindingFlags.Instance) == null, "the mutable member Mutable is a property, not a public field"
    assert mutableProperty != null && mutableProperty.CanWrite, "the mutable member Mutable must be a settable property"
    assert mutableStorage != null, "the auto-property Mutable must have its backing field"
    if scaleField != null {
        assert scaleField.get_IsInitOnly(), "a readonly instance field must be emitted initonly"
    }
    if mutableStorage != null {
        assert !mutableStorage.get_IsInitOnly(), "an auto-property's backing field must not be emitted initonly"
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

test "an implicitly-defaulted nullable field beside a written initializer compiles and defaults to null" {
    value := new NullableBesideWritten()
    assert value.Absent == null
    assert value.AbsentNumber == null
    assert value.Present == 2
    assert value.PresentText == "set"
}

test "an implicitly-defaulted nullable field reads the same as an explicit null initializer" {
    value := new NullableAfterWritten()
    assert value.Present == 3
    assert value.Absent == null
    assert value.Explicit == null
    assert value.Absent == value.Explicit
}

test "an implicitly-defaulted nullable member is an ordinary auto-property in metadata" {
    absentProperty := typeof(NullableBesideWritten).GetProperty("Absent", BindingFlags.Public | BindingFlags.Instance)
    presentProperty := typeof(NullableBesideWritten).GetProperty("Present", BindingFlags.Public | BindingFlags.Instance)
    absentStorage := typeof(NullableBesideWritten).GetField("<Absent>k__BackingField", BindingFlags.NonPublic | BindingFlags.Instance)
    assert absentProperty != null, "the nullable member Absent must be a property"
    assert presentProperty != null, "the written-initializer member Present must be a property"
    assert absentStorage != null, "the auto-property Absent must have its backing field"
    if absentStorage != null {
        assert !absentStorage.get_IsInitOnly(), "a mutable nullable member's storage must not be emitted initonly"
    }
    if absentProperty != null {
        assert absentProperty.get_PropertyType() == typeof(string), "Absent must keep its declared reference type"
    }
}
