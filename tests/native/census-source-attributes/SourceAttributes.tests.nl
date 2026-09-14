namespace NSharpLang.CensusSourceAttributes

import System
import System.Reflection
import System.Runtime.CompilerServices
import System.Text.Json.Serialization

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

// Assert that member assignments preserve both the attribute row and its payload.
// A successful compilation alone cannot detect an attribute silently omitted from metadata.
test "an attribute member assignment sets an exported field" {
    named := MarkOn("MemberAssignedField")
    assert named != null, "the attribute row must be emitted for an attribute member assignment"
    assert named.Tag == "member named"
    assert named.Count == 43
}

test "an attribute member assignment sets a property through its setter" {
    found := RequiredMethod("MemberAssignedProperty").GetCustomAttribute(typeof(NotedAttribute), false) as NotedAttribute
    assert found != null, "the attribute row must be emitted for an attribute member assignment"
    assert found.Note == "through a setter, member assignment"
}

test "an attribute member assignment binds an inherited member" {
    found := RequiredMethod("MemberAssignedInherited").GetCustomAttribute(typeof(DerivedMarkAttribute), false) as DerivedMarkAttribute
    assert found != null, "the attribute row must be emitted for an attribute member assignment"
    assert found.Tag == "member derived"
    assert found.Count == 4
    assert found.Extra == "member own"
}

test "an attribute member assignment binds on an external attribute" {
    found := RequiredMethod("MemberAssignedExternal").GetCustomAttribute(typeof(ObsoleteAttribute), false) as ObsoleteAttribute
    assert found != null, "the attribute row must be emitted for an attribute member assignment"
    assert found.DiagnosticId == "NL9998"
}

// THE READER MUST NOT TURN AN ORDINARY ARGUMENT INTO A NAMED ONE. A positional enum member is a
// dotted name, and a `|` of two of them is a binary expression; neither is `Identifier` followed by
// a separator, so both stay positional and land in the constructor's own parameters.
test "positional enum arguments preserve their constructor payload" {
    found := RequiredMethod("EnumPositionalArguments").GetCustomAttribute(typeof(LevelledAttribute), false) as LevelledAttribute
    assert found != null, "the attribute row must be emitted"
    assert found.Level == Level.High
    expectedTargets := AttributeTargets.Method | AttributeTargets.Class
    assert found.Targets == expectedTargets
    payload := must found.Payload
    assert payload.ToString() == "19"
}

func DefaultedOn(name: string): DefaultedAttribute {
    declared: MethodInfo? = typeof(DefaultCarrier).GetMethod(name)
    method := must declared
    return method.GetCustomAttribute(typeof(DefaultedAttribute), false) as DefaultedAttribute
}

// AN OMITTED OPTIONAL ARGUMENT IS WRITTEN AS THE DECLARED DEFAULT. Exact arity used to be required,
// so every one of these reported NL402 "No constructor of attribute 'DefaultedAttribute' accepts N
// positional argument(s)".
test "an attribute that writes no arguments takes every declared default" {
    found := DefaultedOn("AllOmitted")
    assert found.Level == 7
    assert found.Note == "unsaid"
    assert found.Flag
    assert found.Ranking == Level.High
}

test "the written arguments win and only the rest default" {
    first := DefaultedOn("FirstWritten")
    assert first.Level == 3
    assert first.Note == "unsaid"
    assert first.Flag
    assert first.Ranking == Level.High

    two := DefaultedOn("TwoWritten")
    assert two.Level == 3
    assert two.Note == "said"
    assert two.Flag
    assert two.Ranking == Level.High

    all := DefaultedOn("AllWritten")
    assert all.Level == 3
    assert all.Note == "said"
    assert !all.Flag
    assert all.Ranking == Level.Low
}

test "a named argument beside defaulted positional ones binds the member it names" {
    found := DefaultedOn("NamedOnly")
    assert found.Level == 7
    assert found.Note == "named only"
}

// THE FILLED-IN DEFAULTS ARE REAL FIXED ARGUMENTS IN THE ROW, not an absence a reader has to
// reconstruct — which is what a C#-compiled assembly's row carries for the same declaration.
test "the emitted row carries one fixed argument per parameter" {
    declared: MethodInfo? = typeof(DefaultCarrier).GetMethod("FirstWritten")
    method := must declared
    data := method.GetCustomAttributesData()
    rows := 0
    for index := 0; index < data.Count; index++ {
        row := data[index]
        if row.AttributeType != typeof(DefaultedAttribute) {
            continue
        }
        rows = rows + 1
        assert row.ConstructorArguments.Count == 4
        assert row.NamedArguments.Count == 0
    }
    assert rows == 1
}

// AN ARRAY ARGUMENT CONVERTS ELEMENT BY ELEMENT. `[1, 2, 250]` is an `int[]` as written; each element
// is an integer constant a `byte` holds, and the blob writes each at the ELEMENT width.
test "an int array literal fills a byte array parameter element by element" {
    declared: MethodInfo? = typeof(DefaultCarrier).GetMethod("NarrowedElements")
    method := must declared
    found := method.GetCustomAttribute(typeof(BytesAttribute), false) as BytesAttribute
    assert found.Values.Length == 3
    assert found.Values[0] == 1
    assert found.Values[1] == 2
    assert found.Values[2] == 250
    assert found.Widths.Length == 0
}

test "two array arguments each convert against their own element type" {
    declared: MethodInfo? = typeof(DefaultCarrier).GetMethod("TwoArrays")
    method := must declared
    found := method.GetCustomAttribute(typeof(BytesAttribute), false) as BytesAttribute
    assert found.Values.Length == 1
    assert found.Values[0] == 1
    assert found.Widths.Length == 2
    assert found.Widths[0] == 2L
    assert found.Widths[1] == 3L
}

// AN EXTERNAL BASE CONSTRUCTOR WITH ARGUMENTS. This declined at
// `emit.ctor.base-chain-without-base`: the chain could only be resolved among the base's SOURCE
// constructor rows, and an external base has none.
test "an attribute chaining to an external base constructor passes its argument up" {
    declared: MethodInfo? = typeof(DefaultCarrier).GetMethod("Relaxed")
    method := must declared
    found := method.GetCustomAttribute(typeof(RelaxedAttribute), false) as CompilationRelaxationsAttribute
    assert found.CompilationRelaxations == 8
}

// A FIELD'S ATTRIBUTES REACH THE FIELD ROW. Every one of these was validated by the analyzer and
// then dropped from the assembly, because the struct member scan yielded a field's name and type as
// TEXT with no declaration position for the attribute reader to scan back from.
test "an instance field's attribute is emitted on the field row" {
    field := must typeof(FieldCarrier).GetField("Value")
    found := field.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the instance field"
}

test "a static field's attribute is emitted on the field row" {
    field := must typeof(FieldCarrier).GetField("Shared", BindingFlags.Public | BindingFlags.Static)
    found := field.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the static field"
}

test "a const field carries both its literal value and its attribute" {
    field := must typeof(FieldCarrier).GetField("Limit", BindingFlags.Public | BindingFlags.Static)
    assert field.IsLiteral
    assert (must field.GetRawConstantValue()).ToString() == "10"
    found := field.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the const"
}

test "an external attribute on a field is emitted" {
    field := must typeof(FieldCarrier).GetField("Legacy")
    found := field.GetCustomAttribute(typeof(ObsoleteAttribute), false) as ObsoleteAttribute
    assert found.Message == "field went away"
}

test "a field's attribute carries enum, flags and boxed arguments like any other position" {
    field := must typeof(FieldCarrier).GetField("Described")
    found := field.GetCustomAttribute(typeof(LevelledAttribute), false) as LevelledAttribute
    assert found.Level == Level.High
    assert found.Targets == AttributeTargets.Field
    payload := must found.Payload
    assert payload.ToString() == "field payload"
}

test "a field the source wrote no attribute on carries none" {
    field := must typeof(FieldCarrier).GetField("Plain")
    assert field.GetCustomAttributes(false).Length == 0
}

test "a value type's field carries its attribute too" {
    marked := must typeof(FieldPoint).GetField("X")
    found := marked.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the struct field"

    plain := must typeof(FieldPoint).GetField("Y")
    assert plain.GetCustomAttributes(false).Length == 0
}

test "a property's attribute is emitted on the property row" {
    declared: PropertyInfo? = typeof(Carrier).GetProperty("Described")
    property := must declared
    found := property.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the property"
}

test "a constructor's attribute is emitted on the constructor" {
    constructors := typeof(Carrier).GetConstructors()
    assert constructors.Length == 1
    found := constructors[0].GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the constructor"
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

// ─── one declaration, two metadata rows ───────────────────────────────────────────────────────
//
// Everything below reads the EMITTED assembly for `record Positional(...)`. Before this, an
// attribute written on a positional parameter made the whole type decline at `parse.struct` — the
// member scan refused the `[` outright — so none of these rows existed at all.
func PositionalField(name: string): FieldInfo {
    return must typeof(Positional).GetField(name)
}

func PositionalParameter(name: string): ParameterInfo {
    constructors := typeof(Positional).GetConstructors()
    assert constructors.Length == 1
    for parameter in constructors[0].GetParameters() {
        if parameter.Name == name {
            return parameter
        }
    }

    throw new InvalidOperationException("Positional constructor has no parameter named '" + name + "'.")
}

test "an attribute declared for fields lands on the field a positional parameter declares" {
    found := PositionalField("Summary").GetCustomAttribute(typeof(MemberOnlyAttribute), false) as MemberOnlyAttribute
    assert found.Note == "on the member"
    assert PositionalParameter("Summary").GetCustomAttribute(typeof(MemberOnlyAttribute), false) == null
}

test "an attribute declared for parameters lands on the parameter" {
    assert PositionalParameter("Name").GetCustomAttribute(typeof(ArgumentOnlyAttribute), false) != null
    assert PositionalField("Name").GetCustomAttribute(typeof(ArgumentOnlyAttribute), false) == null
}

// THE PARAMETER WINS THE TIE. The source wrote a parameter, and the fallback only moves an attribute
// that could not have been written there at all.
test "an attribute declared for both rows lands on the parameter" {
    assert PositionalParameter("Rank").GetCustomAttribute(typeof(EitherAttribute), false) != null
    assert PositionalField("Rank").GetCustomAttribute(typeof(EitherAttribute), false) == null
}

test "an attribute declared for every target lands on the parameter" {
    found := PositionalParameter("Wide").GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "wide open"
    assert PositionalField("Wide").GetCustomAttribute(typeof(MarkAttribute), false) == null
}

// AN EXTERNAL ATTRIBUTE IS ROUTED BY THE USAGE IT DECLARES, read from metadata rather than from a
// declaration — and it is the same decision. `[Obsolete]` is declared for every DECLARATION and for
// no parameter, so it lands on the field; `[CompilerGenerated]` is declared for `All` and stays on
// the parameter the source wrote it on.
test "an external attribute whose usage excludes parameters lands on the field" {
    found := PositionalField("Legacy").GetCustomAttribute(typeof(ObsoleteAttribute), false) as ObsoleteAttribute
    assert found.Message == "the field went away"
    assert PositionalParameter("Legacy").GetCustomAttribute(typeof(ObsoleteAttribute), false) == null
}

test "an external attribute whose usage admits parameters stays on the parameter" {
    assert PositionalParameter("Generated").GetCustomAttribute(typeof(CompilerGeneratedAttribute), false) != null
    assert PositionalField("Generated").GetCustomAttribute(typeof(CompilerGeneratedAttribute), false) == null
}

// THE CENSUS SHAPE, VERBATIM. C# writes `[property: JsonIgnore(Condition = ...)] bool Summary =
// false` on a record parameter to put the attribute where the serializer reads it. N# writes no
// prefix and reaches the same row, because `JsonIgnore` is declared for properties and fields and
// for no parameter.
test "the shape the census found reaches the member the serializer reads" {
    found := PositionalField("Ignored").GetCustomAttribute(typeof(JsonIgnoreAttribute), false) as JsonIgnoreAttribute
    assert found.Condition == JsonIgnoreCondition.WhenWritingDefault
    assert PositionalParameter("Ignored").GetCustomAttribute(typeof(JsonIgnoreAttribute), false) == null
}

test "a positional parameter the source wrote no attribute on carries none on either row" {
    assert PositionalField("Plain").GetCustomAttributes(false).Length == 0
    assert PositionalParameter("Plain").GetCustomAttribute(typeof(MarkAttribute), false) == null
    assert PositionalParameter("Plain").GetCustomAttribute(typeof(MemberOnlyAttribute), false) == null
}

// THE DEFAULT VALUE AND THE ATTRIBUTE ARE WRITTEN ON THE SAME DECLARATION and neither displaces the
// other: this is the exact shape the census found (`[JsonIgnore] Summary: bool = false`).
test "a positional parameter keeps its default beside its attribute" {
    parameter := PositionalParameter("Summary")
    assert parameter.get_HasDefaultValue()
    assert (must parameter.get_DefaultValue()).ToString() == "False"
}

test "a class's primary constructor parameter routes the same way" {
    field := must typeof(PositionalCarrier).GetField("seed", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    found := field.GetCustomAttribute(typeof(MemberOnlyAttribute), false) as MemberOnlyAttribute
    assert found.Note == "on the class member"

    constructors := typeof(PositionalCarrier).GetConstructors()
    assert constructors.Length == 1
    parameters := constructors[0].GetParameters()
    assert parameters.Length == 2
    assert parameters[0].GetCustomAttribute(typeof(MemberOnlyAttribute), false) == null
    assert parameters[1].GetCustomAttribute(typeof(ArgumentOnlyAttribute), false) != null
}

test "a value type's primary constructor parameter routes the same way" {
    field := must typeof(PositionalPoint).GetField("X", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    found := field.GetCustomAttribute(typeof(MemberOnlyAttribute), false) as MemberOnlyAttribute
    assert found.Note == "on the struct member"

    constructors := typeof(PositionalPoint).GetConstructors()
    assert constructors.Length == 1
    parameters := constructors[0].GetParameters()
    assert parameters.Length == 2
    assert parameters[1].GetCustomAttribute(typeof(ArgumentOnlyAttribute), false) != null
}

// AN EXPLICIT CONSTRUCTOR'S PARAMETER IS ONLY A PARAMETER, and its attribute was dropped from the
// assembly before this: a constructor's parameter metadata was written without ever asking what the
// source declared on it.
test "an explicit constructor's parameter carries its attribute" {
    constructors := typeof(ExplicitParameterCarrier).GetConstructors()
    assert constructors.Length == 1
    parameters := constructors[0].GetParameters()
    assert parameters.Length == 2
    found := parameters[0].GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the constructor parameter"
    assert parameters[1].GetCustomAttribute(typeof(MarkAttribute), false) == null
}

// A CONSTRUCTOR'S PARAMETER IS NOT A MEMBER, so a field of the same name never takes its attribute.
test "an explicit constructor's parameter never routes to a field of the same name" {
    field := must typeof(ExplicitParameterCarrier).GetField("Value")
    assert field.GetCustomAttribute(typeof(MarkAttribute), false) == null
}

// AN ENUM MEMBER'S ATTRIBUTES REACH THE LITERAL FIELD THE MEMBER BECAME. Every one of these was a
// parse error (`NL935`) until the emitter stopped creating enum types before the attribute queue
// flushed.
test "an enum member's attribute is emitted on the literal field" {
    field := must typeof(Marked).GetField("None", BindingFlags.Public | BindingFlags.Static)
    assert field.IsLiteral
    assert (must field.GetRawConstantValue()).ToString() == "0"
    found := field.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the first member"
}

test "an enum member carries every attribute written on it" {
    field := must typeof(Marked).GetField("Low", BindingFlags.Public | BindingFlags.Static)
    data := field.GetCustomAttributesData()
    assert data.Count == 2

    marked := field.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert marked.Tag == "on the second member"
    obsolete := field.GetCustomAttribute(typeof(ObsoleteAttribute), false) as ObsoleteAttribute
    assert obsolete.Message == "member went away"
}

test "an enum member's attribute carries enum, flags and boxed arguments like any other field" {
    field := must typeof(Marked).GetField("High", BindingFlags.Public | BindingFlags.Static)
    found := field.GetCustomAttribute(typeof(LevelledAttribute), false) as LevelledAttribute
    assert found.Level == Level.High
    assert found.Targets == AttributeTargets.Field
    payload := must found.Payload
    assert payload.ToString() == "member payload"
}

test "an enum member the source wrote no attribute on carries none" {
    field := must typeof(Marked).GetField("Plain", BindingFlags.Public | BindingFlags.Static)
    assert field.GetCustomAttributes(false).Length == 0
}

// THE ENUM'S OWN ATTRIBUTES STAY ON THE TYPE, and `[Flags]` still reaches it.
test "the enum declaration keeps its own attributes beside its members'" {
    found := typeof(Marked).GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the enum"
    assert typeof(Marked).GetCustomAttribute(typeof(FlagsAttribute), false) != null
    combined: Marked = Marked.Low | Marked.High
    assert combined.ToString() == "Low, High"
}

// THE ENUM IS STILL AN ENUM. Leaving its type open until the attribute flush changed when it is
// created, not what it is.
test "an attributed enum is still a CLR enum with its declared members" {
    assert typeof(Marked).IsEnum
    assert Enum.GetUnderlyingType(typeof(Marked)) == typeof(int)
    assert Enum.GetNames(typeof(Marked)).Length == 4
    assert (int)Marked.High == 2
    assert Enum.IsDefined(typeof(Marked), Marked.Plain)
}

test "a string-backed enum member's attribute is emitted on its literal field" {
    // A STRING-BACKED ENUM IS NOT A CLR ENUM: its values ARE strings, so `typeof(MarkedText)` is
    // `typeof(string)` and the emitted class of literal fields is reached by name.
    textType := must typeof(Marked).Assembly.GetType("NSharpLang.CensusSourceAttributes.MarkedText")
    field := must textType.GetField("Warm", BindingFlags.Public | BindingFlags.Static)
    assert field.IsLiteral
    assert (must field.GetRawConstantValue()).ToString() == "warm"
    found := field.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the text member"

    plain := must textType.GetField("Cool", BindingFlags.Public | BindingFlags.Static)
    assert plain.GetCustomAttributes(false).Length == 0
}

// A NESTED ENUM'S TYPE STILL LOADS, which is the assertion the whole materialization order exists
// for: the class that names it has a field, a constructor and an interpolation over it.
test "a nested enum's member carries its attribute and the host still loads" {
    // The nested enum is reached through the FIELD THAT NAMES IT, which is the signature the
    // materialization order exists to keep loadable.
    nestedType := (must typeof(EnumHost).GetField("Current")).FieldType
    assert nestedType.IsEnum
    field := must nestedType.GetField("First", BindingFlags.Public | BindingFlags.Static)
    found := field.GetCustomAttribute(typeof(MarkAttribute), false) as MarkAttribute
    assert found.Tag == "on the nested member"
    assert new EnumHost().Label() == "First"
}
