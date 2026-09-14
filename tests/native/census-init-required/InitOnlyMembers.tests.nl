namespace NSharpLang.CensusInitRequired.Tests

import System.Reflection


// RUNTIME: what an `init` member is worth after the creation that set it.
test "an object initializer sets every init-only member it names" {
    config := new Configuration {
        AppName: "MyApp",
        Version: "1.0"
    }

    assert config.AppName == "MyApp"
    assert config.Version == "1.0"
    assert config.Notes == ""
}

test "an init-only member keeps the value its declaration gives when the creation says nothing" {
    defaulted := new Defaulted()
    assert defaulted.Label == "default"
    assert defaulted.Count == 7

    overridden := new Defaulted {
        Label: "written"
    }
    assert overridden.Label == "written"
    assert overridden.Count == 7
}

test "a constructor of the declaring type writes an init-only member" {
    seeded := new Seeded("from-ctor")
    assert seeded.Name == "from-ctor"
    assert seeded.Read() == "from-ctor"
}

test "a derived constructor writes the base's init-only member" {
    derived := new SeededDerived("tagged")
    assert derived.Tag == "tagged"
    assert derived.ReadTag() == "tagged"
}

test "an init-only member on a value type carries the value the creation gave it" {
    measurement := new Measurement {
        Amount: 42,
        Unit: 3
    }

    assert measurement.Amount == 42
    assert measurement.Unit == 3

    copied := measurement
    assert copied.Amount == 42
}

test "an init-only member typed by the declaration's own type parameter round-trips" {
    holder := new Holder<string>("generic")
    assert holder.Value == "generic"

    numbers := new Holder<int>(11)
    assert numbers.Value == 11
    assert numbers.Slot == 0
}

test "closed generic init setters retain their constructed owner and modifier" {
    first := new GenericInitializable<string> {
        Value: "closed"
    }
    second := new GenericInitializable<string> {
        Value: "repeated"
    }

    assert first.Value == "closed"
    assert second.Value == "repeated"

    measurement := new GenericMeasurement<int> {
        Value: 42
    }
    assert measurement.Value == 42

    nested := new GenericInitOwner.Nested<string> {
        Value: "nested"
    }
    assert nested.Value == "nested"
}

test "a record's synthesized equality compares its init-only members" {
    first := new Pair {
        Left: 1,
        Right: 2
    }
    same := new Pair {
        Left: 1,
        Right: 2
    }
    different := new Pair {
        Left: 9,
        Right: 2
    }

    assert first.Equals(same)
    assert !first.Equals(different)
}

test "a declared init accessor writes through the body the source gave it" {
    declared := new Declared {
        Managed: "through-setter"
    }

    assert declared.Managed == "through-setter"
}

// CLR METADATA: the modreq is the marker, and it is what every other language reads.
test "an init-only member emits a property whose setter return type carries IsExternalInit" {
    property := typeof(Configuration).GetProperty("AppName")
    assert property != null
    assert property.PropertyType == typeof(string)

    setter := property.SetMethod
    assert setter != null

    modifiers := setter.ReturnParameter.GetRequiredCustomModifiers()
    assert modifiers.Length == 1
    assert modifiers[0].FullName == "System.Runtime.CompilerServices.IsExternalInit"
}

test "a declared init accessor carries the same modreq an auto member does" {
    property := typeof(Declared).GetProperty("Managed")
    assert property != null

    setter := property.SetMethod
    assert setter != null
    assert setter.ReturnParameter.GetRequiredCustomModifiers()[0].FullName == "System.Runtime.CompilerServices.IsExternalInit"
}

test "an ordinary settable member carries no init marker" {
    getter := typeof(Declared).GetMethod("get_Managed")
    assert getter != null
    assert getter.ReturnParameter.GetRequiredCustomModifiers().Length == 0

    notes := typeof(Configuration).GetField("Notes")
    assert notes != null
    assert !notes.IsInitOnly
}

test "an init-only member's storage is a private compiler-generated backing field" {
    backing := typeof(Configuration).GetField("<AppName>k__BackingField", BindingFlags.NonPublic | BindingFlags.Instance)
    assert backing != null
    assert backing.IsPrivate
    assert backing.FieldType == typeof(string)

    generated := false
    for attribute in backing.GetCustomAttributesData() {
        if attribute.AttributeType.FullName == "System.Runtime.CompilerServices.CompilerGeneratedAttribute" {
            generated = true
        }
    }

    assert generated

    // The name the source wrote names the PROPERTY and nothing else: no public field of that name
    // exists, so every reader outside the type goes through the accessors.
    assert typeof(Configuration).GetField("AppName") == null
}

test "an init-only member on a generic type keeps the declaration's own type parameter" {
    definition := typeof(Holder<string>).GetGenericTypeDefinition()
    property := definition.GetProperty("Value")
    assert property != null
    assert property.PropertyType.IsGenericParameter

    setter := property.SetMethod
    assert setter != null
    assert setter.ReturnParameter.GetRequiredCustomModifiers()[0].FullName == "System.Runtime.CompilerServices.IsExternalInit"
}

test "generic init metadata is shared through a lambda emitter" {
    assert GenericInitThroughLambda() == 42
}

test "generic init metadata is shared through a local function emitter" {
    assert GenericInitThroughLocalFunction() == 42
}
