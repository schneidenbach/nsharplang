namespace NSharpLang.CensusGenericSignatures

import System
import System.Collections.Generic
import System.Reflection

// A SOURCE VALUE DECLARATION IS AN ORDINARY GENERIC ARGUMENT AND AN ORDINARY KEY.
//
// The signatures in `SourceValueArguments.nl` used to decline at `emit.declaration.method-param` and
// `emit.declaration.field-type`: the key surface admitted a source REFERENCE declaration directly
// and a source record struct only when the live source registry proved the record fact, so a plain
// `struct` could not be a `HashSet` element or a `Dictionary` key at all. Equality is what a key
// surface is about, and every source declaration has it — the assertions below run both kinds.
func ValueDeclaredFlags(): BindingFlags {
    return BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
}

func ValueFieldType(name: string): Type {
    found: FieldInfo? = typeof(LocationIndex).GetField(name, ValueDeclaredFlags())
    return (must found).FieldType
}

test "a plain source struct is the element of an emitted HashSet" {
    stored := ValueFieldType("seen")
    assert stored.GetGenericTypeDefinition() == typeof(HashSet<int>).GetGenericTypeDefinition()
    arguments := stored.GetGenericArguments()
    assert arguments.Length == 1
    assert Object.ReferenceEquals(arguments[0], typeof(Loc))
    assert typeof(Loc).get_IsValueType()
}

test "a readonly record struct is the element of an emitted HashSet" {
    stored := ValueFieldType("spans")
    arguments := stored.GetGenericArguments()
    assert arguments.Length == 1
    assert Object.ReferenceEquals(arguments[0], typeof(Span))
    assert typeof(Span).get_IsValueType()
}

test "a plain source struct is the key of an emitted Dictionary" {
    stored := ValueFieldType("labels")
    assert stored.GetGenericTypeDefinition() == typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    arguments := stored.GetGenericArguments()
    assert arguments.Length == 2
    assert Object.ReferenceEquals(arguments[0], typeof(Loc))
    assert arguments[1] == typeof(string)
}

test "a nullable source struct is an ordinary collection element" {
    stored := ValueFieldType("optional")
    assert stored.GetGenericTypeDefinition() == typeof(List<int>).GetGenericTypeDefinition()
    element := stored.GetGenericArguments()[0]
    assert element.get_IsGenericType()
    assert element.GetGenericTypeDefinition() == typeof(Nullable<int>).GetGenericTypeDefinition()
    assert Object.ReferenceEquals(element.GetGenericArguments()[0], typeof(Loc))
}

test "an unmodelled read-only set head closes over a source struct in a parameter and a return" {
    method: MethodInfo? = typeof(LocationIndex).GetMethod("CountAll")
    parameters := (must method).GetParameters()
    assert parameters.Length == 1
    assert parameters[0].ParameterType.GetGenericTypeDefinition() == typeof(IReadOnlySet<int>).GetGenericTypeDefinition()
    assert Object.ReferenceEquals(parameters[0].ParameterType.GetGenericArguments()[0], typeof(Loc))

    returning: MethodInfo? = typeof(LocationIndex).GetMethod("SeenSet")
    returned := must returning
    assert Object.ReferenceEquals(returned.ReturnType.GetGenericArguments()[0], typeof(Loc))
}

// `System.ValueType`'s field-wise equality is what makes a plain struct a key, so two values that
// agree on every field must collapse to one entry and two that differ must not.
test "a plain source struct hashes and compares field-wise inside the emitted set" {
    index := new LocationIndex()
    assert index.Observe(new Loc(1, 2))
    assert !index.Observe(new Loc(1, 2))
    assert index.Observe(new Loc(1, 3))
    assert index.Distinct() == 2
    assert index.CountAll(index.SeenSet()) == 2
}

test "a record struct hashes and compares by its synthesized equality inside the emitted set" {
    index := new LocationIndex()
    assert index.ObserveSpan(new Span(0, 4))
    assert !index.ObserveSpan(new Span(0, 4))
    assert index.ObserveSpan(new Span(1, 4))
    assert index.DistinctSpans() == 2
}

test "a plain source struct keys the emitted dictionary" {
    index := new LocationIndex()
    index.Label(new Loc(7, 1), "seven")
    index.Label(new Loc(8, 1), "eight")

    assert index.LabelOf(new Loc(7, 1)) == "seven"
    assert index.LabelOf(new Loc(8, 1)) == "eight"
    assert index.LabelOf(new Loc(9, 1)) == "<none>"
}

test "a lifted source struct stores and reads back through the list" {
    index := new LocationIndex()
    index.Remember(new Loc(5, 5))
    index.Remember(null)

    assert index.RememberedLine(0) == 5
    assert index.RememberedLine(1) == -1
}

test "a delegate field typed by two source declarations emits and runs" {
    field: FieldInfo? = typeof(Projector).GetField("project", ValueDeclaredFlags())
    delegateType := (must field).FieldType
    delegateArguments := delegateType.GetGenericArguments()
    assert delegateArguments.Length == 2
    assert Object.ReferenceEquals(delegateArguments[0], typeof(Loc))
    assert Object.ReferenceEquals(delegateArguments[1], typeof(Marker))

    projector := new Projector(value => new Marker(value.Line.ToString()))
    assert projector.Apply(new Loc(11, 0)).Text == "11"
}

test "an untargeted typed lambda keeps its written parameter and runs" {
    index := new LocationIndex()
    assert index.NextLine(new Loc(8, 3)) == 9
    assert index.SumSix() == 21

    methods := typeof(LocationIndex).GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    found := false
    for method in methods {
        parameters := method.GetParameters()
        if method.Name.StartsWith("<Lambda>", StringComparison.Ordinal) && parameters.Length == 1 && Object.ReferenceEquals(parameters[0].ParameterType, typeof(int)) {
            found = true
        }
    }
    assert found
}

test "a compatible written lambda parameter controls overload selection" {
    index := new LocationIndex()
    assert index.CompatibleWrittenParameter() == 1
}

test "an inferred typed lambda keeps its generic lexical owner" {
    owner := new LambdaOwner<string>()
    assert owner.Echo("generic") == "generic"
}
