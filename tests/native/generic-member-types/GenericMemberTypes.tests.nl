namespace NSharpLang.GenericMemberTypes.Tests

import System
import System.Collections.Generic
import System.Reflection


// Every member named below is one this project declares itself, so `null` here means the emitter
// did not write it at all — a failure that deserves its own sentence rather than a null dereference
// on the next line.
func DeclaredMemberType(owner: Type, name: string): Type {
    property := owner.GetProperty(name)
    if property == null {
        throw new InvalidOperationException("'" + owner.Name + "' declares no property named '" + name + "'.")
    }
    return property.get_PropertyType()
}

// The free functions of a source file are emitted as static methods of one holder type. Nothing
// this project declares gives a handle to it, so it is reached the way any other consumer would:
// through the assembly the tests themselves live in.
func DeclaredStaticMethod(name: string): MethodInfo {
    assembly := typeof(Holder<int>).get_Assembly()
    types := assembly.GetTypes()
    index := 0
    while index < types.Length {
        candidate := types[index].GetMethod(name, BindingFlags.Public | BindingFlags.Static)
        if candidate != null {
            return candidate
        }
        index = index + 1
    }
    throw new InvalidOperationException("No static method named '" + name + "' was emitted.")
}

func GmtNumbers(): List<int> {
    values := new List<int>()
    values.Add(1)
    values.Add(2)
    values.Add(3)
    values.Add(4)
    return values
}

// `return <lambda>` does not parse today, so every lambda below is bound to a typed local first.
func GmtEvenPick(): Func<int, bool> {
    pick: Func<int, bool> = value => value % 2 == 0
    return pick
}

func GmtAppender(sink: List<int>): Action<int> {
    appender: Action<int> = value => sink.Add(value)
    return appender
}

func GmtEmptyLookup(): Dictionary<string, int> {
    return new Dictionary<string, int>()
}

func GmtHolder(): Holder<int> {
    return new Holder<int>(GmtNumbers(), GmtEmptyLookup(), GmtEvenPick())
}

test "a List and a Dictionary closed over the declaring type's own parameter store and load" {
    holder := GmtHolder()
    assert holder.Items.Count == 4
    holder.Add(5)
    assert holder.Items.Count == 5

    holder.Lookup["five"] = 5
    assert holder.Lookup["five"] == 5
    assert holder.Lookup.Count == 1
}

test "a nullable annotation on such a type is the same CLR type, not a different one" {
    holder := GmtHolder()
    assert holder.OptionalItems == null

    more := new List<int>()
    more.Add(9)
    holder.Adopt(more)
    optional := holder.OptionalItems ?? new List<int>()
    assert optional.Count == 1

    holder.Adopt(null)
    assert holder.OptionalItems == null
}

test "a delegate closed over the declaring type's own parameter is a field that stores and loads" {
    holder := GmtHolder()
    assert holder.OnEach == null

    seen := new List<int>()
    holder.Listen(GmtAppender(seen))
    assert holder.OnEach != null

    // CALLING it is the part that needs the `Invoke` handle rebound onto the instantiation: the
    // reflection query that answers for `Action<int>` throws on `Action<T>`.
    assert holder.Announce(4)
    assert !holder.Announce(7)
    assert seen.Count == 2
    assert seen[0] == 4
    assert seen[1] == 7
}

test "a Func closed over the declaring type's own parameter decides a loop" {
    holder := GmtHolder()
    chosen := holder.Selected()
    assert chosen.Count == 2
    assert chosen[0] == 2
    assert chosen[1] == 4
}

test "the same shapes are emittable as parameters and returns of a generic free function" {
    // `FirstMatch` and `Sink` take `List<T>` and `Func<T, bool>` / `Action<T>` over their OWN
    // method-level type parameter and copy the delegate into a local of the same shape. Their
    // SIGNATURES are what this asserts: calling them from N# still trips a separate analyzer gap
    // (a function type is not unified against a substituted method type parameter — NL202 naming
    // the same type on both sides), which is not what this project is about.
    firstMatch := DeclaredStaticMethod("FirstMatch")
    parameters := firstMatch.GetParameters()
    assert parameters.Length == 3

    methodParameter := firstMatch.GetGenericArguments()[0]
    listType := parameters[0].get_ParameterType()
    assert listType.GetGenericTypeDefinition() == typeof(List<int>).GetGenericTypeDefinition()
    assert listType.GetGenericArguments()[0] == methodParameter

    pickType := parameters[1].get_ParameterType()
    assert pickType.GetGenericTypeDefinition() == typeof(Func<int, bool>).GetGenericTypeDefinition()
    assert pickType.GetGenericArguments()[0] == methodParameter
    assert pickType.GetGenericArguments()[1] == typeof(bool)

    assert firstMatch.get_ReturnType() == methodParameter

    sink := DeclaredStaticMethod("Sink")
    sinkParameter := sink.GetGenericArguments()[0]
    listenerType := sink.GetParameters()[1].get_ParameterType()
    assert listenerType.GetGenericTypeDefinition() == typeof(Action<int>).GetGenericTypeDefinition()
    assert listenerType.GetGenericArguments()[0] == sinkParameter
}

// ---- CLR metadata ----------------------------------------------------------------------------

test "each member's emitted type is the constructed external generic, not something substituted" {
    holder := typeof(Holder<int>)

    itemsType := DeclaredMemberType(holder, "Items")
    assert itemsType == typeof(List<int>)

    lookupType := DeclaredMemberType(holder, "Lookup")
    assert lookupType == typeof(Dictionary<string, int>)

    // The `?` is the analyzer's flow fact. `List<T>?` and `List<T>` are ONE CLR type, and a field
    // that emitted `Nullable<List<int>>` for the annotated one would not even load.
    optionalType := DeclaredMemberType(holder, "OptionalItems")
    assert optionalType == typeof(List<int>)

    onEachType := DeclaredMemberType(holder, "OnEach")
    assert onEachType == typeof(Action<int>)

    pickType := DeclaredMemberType(holder, "Pick")
    assert pickType == typeof(Func<int, bool>)
}

test "a second instantiation gets its own substituted member types" {
    holder := typeof(Holder<string>)

    onEachType := DeclaredMemberType(holder, "OnEach")
    assert onEachType == typeof(Action<string>)

    pickType := DeclaredMemberType(holder, "Pick")
    assert pickType == typeof(Func<string, bool>)
}

test "the open definition's members are typed by the type parameter itself" {
    definition := typeof(Holder<int>).GetGenericTypeDefinition()
    parameter := definition.GetGenericArguments()[0]

    onEachType := DeclaredMemberType(definition, "OnEach")
    assert onEachType.get_IsGenericType()
    assert onEachType.GetGenericTypeDefinition() == typeof(Action<int>).GetGenericTypeDefinition()
    assert onEachType.GetGenericArguments()[0] == parameter
}
