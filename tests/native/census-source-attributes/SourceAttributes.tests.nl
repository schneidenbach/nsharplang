namespace NSharpLang.CensusSourceAttributes

import System.Reflection

// EVERY ASSERTION HERE READS THE EMITTED ASSEMBLY. The attribute types and the declarations they are
// written on live in `SourceAttributes.nl`, in this same project, so a passing test means the
// compiler resolved a type it was still building, chose one of its `ConstructorBuilder`s, wrote a
// custom-attribute blob for it, and the CLR decoded that blob back into a live instance.
func RequiredMethod(name: string): MethodInfo {
    method: MethodInfo? = typeof(Target).GetMethod(name)
    return must method
}

func MarkOn(name: string): MarkAttribute {
    found := RequiredMethod(name).GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    return found
}

test "a source-declared attribute on a class carries its positional arguments" {
    found := typeof(Target).GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the class"
    assert found.Count == 7
}

test "the no-argument constructor is chosen for a bare attribute" {
    bare := MarkOn("Bare")
    assert bare.Tag == ""
    assert bare.Count == 0
}

test "both the short and the Attribute-suffixed spelling bind the same type" {
    full := MarkOn("FullSpelling")
    assert full.Tag == "full spelling"
    assert full.Count == 0
}

test "a named argument sets an exported field" {
    named := MarkOn("NamedField")
    assert named.Tag == "named"
    assert named.Count == 42
}

test "a named argument sets a property through its setter" {
    found := RequiredMethod("NamedProperty").GetCustomAttribute(typeof(NotedAttribute), false) as NotedAttribute
    assert found.Note == "through a setter"
}

// THE WIDTHS ARE THE POINT OF THIS TEST. A blob writes each value at the width its PARAMETER declares,
// so a wrong width reads back as a different number rather than as an error.
test "every primitive width round-trips at its declared width" {
    found := RequiredMethod("Widths").GetCustomAttribute(typeof(WidthsAttribute), false) as WidthsAttribute
    assert found.Flag
    assert found.Letter == 'x'
    assert found.Small == -8
    assert found.Unsigned == 250
    assert found.Short == -3000
    assert found.UnsignedShort == 60000
    assert found.Whole == -123456
    assert found.UnsignedWhole == 4000000000U
    assert found.Wide == -9000000000000L
    assert found.UnsignedWide == 18000000000000000000UL
    assert found.Single == 1.5f
    assert found.Wide64 == 2.25
}

test "typeof, a string array and a null reference round-trip" {
    found := RequiredMethod("TypedArguments").GetCustomAttribute(typeof(TypedAttribute), false) as TypedAttribute
    assert found.Subject == typeof(Target)
    assert found.Names.Length == 2
    assert found.Names[0] == "a"
    assert found.Names[1] == "b"
    assert found.Note == null
}

test "typeof of a built-in type names the runtime type" {
    found := RequiredMethod("BuiltInTypeArgument").GetCustomAttribute(typeof(TypedAttribute), false) as TypedAttribute
    assert found.Subject == typeof(int)
    assert found.Names.Length == 1
    assert found.Note == "kept"
}

test "a source enum, an external flags enum and a boxed int round-trip" {
    found := RequiredMethod("Levelled").GetCustomAttribute(typeof(LevelledAttribute), false) as LevelledAttribute
    assert found.Level == Level.High
    expectedTargets := AttributeTargets.Method | AttributeTargets.Class
    assert found.Targets == expectedTargets
    payload := must found.Payload
    assert payload.ToString() == "17"
}

test "a boxed string argument keeps its own type" {
    found := RequiredMethod("BoxedString").GetCustomAttribute(typeof(LevelledAttribute), false) as LevelledAttribute
    assert found.Level == Level.Low
    assert found.Targets == AttributeTargets.All
    payload := must found.Payload
    assert payload.ToString() == "boxed string"
}

// A NAMED ARGUMENT DECLARED BY THE BASE is bound by walking the declaration's base chain, which is the
// only way to reach `Count` from `DerivedMarkAttribute`.
test "an attribute deriving from a source attribute binds inherited and own named arguments" {
    found := RequiredMethod("Derived").GetCustomAttribute(typeof(DerivedMarkAttribute), false) as DerivedMarkAttribute
    assert found.Tag == "derived"
    assert found.Count == 3
    assert found.Extra == "own"
}

test "an attribute deriving from an external attribute base is emitted" {
    found := RequiredMethod("ExternallyBased").GetCustomAttribute(typeof(ExternallyBasedAttribute), false) as ExternallyBasedAttribute
    assert found.Reason == "because"
}

test "an attribute on a parameter is emitted on the parameter" {
    parameters := RequiredMethod("WithParameter").GetParameters()
    assert parameters.Length == 1
    found := parameters[0].GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the parameter"
}

// THE EXTERNAL RATCHET. Both of these were silently DROPPED from the assembly before source attributes
// were implemented, because the old writer only knew all-string constructors.
test "an external attribute with a non-string argument is emitted" {
    found := RequiredMethod("ExternalTwoArguments").GetCustomAttribute(typeof(ObsoleteAttribute), false) as ObsoleteAttribute
    assert found.Message == "gone"
    assert found.IsError
}

test "an external attribute with only a named argument is emitted" {
    found := RequiredMethod("ExternalNamedOnly").GetCustomAttribute(typeof(ObsoleteAttribute), false) as ObsoleteAttribute
    assert found.DiagnosticId == "NL9999"
}

test "inherit true finds an attribute written on the overridden method" {
    declared: MethodInfo? = typeof(DerivedCarrier).GetMethod("Describe")
    overriding := must declared
    own := overriding.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute?
    assert own == null
    inherited := overriding.GetCustomAttribute(typeof(MarkAttribute), true) as MarkAttribute
    assert inherited.Tag == "inherited"
}

// ALLOWMULTIPLE IS NOT ONLY AN ANALYZER RULE. Two rows have to reach the assembly, and the emitted
// attribute type has to carry the `[AttributeUsage]` that makes them legal.
test "an attribute declaring AllowMultiple is emitted twice" {
    found := RequiredMethod("Tagged").GetCustomAttributes(typeof(TagAttribute), false)
    assert found.Length == 2
    first := found[0] as TagAttribute
    second := found[1] as TagAttribute
    assert first.Name != second.Name
    assert first.Name == "first" || first.Name == "second"
    assert second.Name == "first" || second.Name == "second"
}

test "the emitted attribute type carries its own AttributeUsage" {
    usage := typeof(TagAttribute).GetCustomAttribute(typeof(AttributeUsageAttribute), false) as AttributeUsageAttribute
    assert usage.AllowMultiple
    assert usage.ValidOn == AttributeTargets.Method
}

test "the emitted custom attribute rows name the constructors the source chose" {
    data := RequiredMethod("NamedField").GetCustomAttributesData()
    marks := 0
    for index := 0; index < data.Count; index++ {
        row := data[index]
        if row.AttributeType != typeof(MarkAttribute) {
            continue
        }
        marks = marks + 1
        assert row.ConstructorArguments.Count == 1
        assert row.NamedArguments.Count == 1
        named := row.NamedArguments[0]
        assert named.MemberName == "Count"
        assert named.IsField
    }
    assert marks == 1
}
