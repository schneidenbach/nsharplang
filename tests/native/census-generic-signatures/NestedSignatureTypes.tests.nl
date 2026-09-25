namespace NSharpLang.CensusGenericSignatures

import System
import System.Collections.Concurrent
import System.Collections.Generic
import System.Reflection

// EVERY ASSERTION BELOW READS THE EMITTED ASSEMBLY OR RUNS THE EMITTED CODE. `NestedSignatureTypes.nl`
// compiling at all is half the contract — before this rule a nested source type used as a generic
// ARGUMENT in a declaration signature could not be resolved, because the walk that assembles the CLR
// shape saw only file and import scope while the name it had to answer was lexical.
func NestedDeclaredFlags(): BindingFlags {
    return BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
}

func NestedCachedType(): Type {
    found: Type? = typeof(Snapshots).GetNestedType("Cached", BindingFlags.Public | BindingFlags.NonPublic)
    return must found
}

func NestedField(name: string): FieldInfo {
    found: FieldInfo? = typeof(Snapshots).GetField(name, NestedDeclaredFlags())
    return must found
}

func NestedFieldType(name: string): Type {
    return NestedField(name).FieldType
}

test "a nested source type is the generic argument of an unmodelled external head" {
    stored := NestedFieldType("byStamp")
    assert stored.get_IsGenericType()
    assert stored.GetGenericTypeDefinition() == typeof(ConcurrentDictionary<int, int>).GetGenericTypeDefinition()
    arguments := stored.GetGenericArguments()
    assert arguments.Length == 2
    assert arguments[0] == typeof(string)
    assert Object.ReferenceEquals(arguments[1], NestedCachedType())
}

test "the same nested type closes a modelled collection head and a nested generic" {
    ordered := NestedFieldType("ordered")
    assert ordered == typeof(List<int>).GetGenericTypeDefinition().MakeGenericType([NestedCachedType()])

    grouped := NestedFieldType("grouped")
    groupedArguments := grouped.GetGenericArguments()
    assert groupedArguments.Length == 2
    assert groupedArguments[0] == typeof(string)
    assert groupedArguments[1] == typeof(List<int>).GetGenericTypeDefinition().MakeGenericType([NestedCachedType()])
}

test "an ARRAY of a nested source type is an ordinary generic argument" {
    batches := NestedFieldType("batches")
    batchArguments := batches.GetGenericArguments()
    assert batchArguments.Length == 2
    assert batchArguments[1].get_IsArray()
    assert Object.ReferenceEquals(batchArguments[1].GetElementType(), NestedCachedType())
}

test "the nested declaration really is private and nested" {
    cached := NestedCachedType()
    assert cached.get_IsNested()
    assert cached.get_IsNestedPrivate()
    assert Object.ReferenceEquals(cached.get_DeclaringType(), typeof(Snapshots))
}

test "the members of the constructed type are reachable after it resolves" {
    snapshots := new Snapshots()
    snapshots.Add("first", "alpha")
    snapshots.Add("second", "beta")

    assert snapshots.Count == 2
    assert snapshots.NoteFor("first") == "alpha"
    assert snapshots.NoteFor("second") == "beta"
    assert snapshots.NoteFor("missing") == ""
    assert snapshots.NewestNote() == "beta"
    assert snapshots.RecentCount() == 2
    assert snapshots.FormattedNewest() == "beta"
    assert snapshots.PrivateLambdaResult() == "private"
    assert snapshots.SlotCount() == 2
}

test "property event and annotated lambda positions keep the nested source argument" {
    property: PropertyInfo? = typeof(Snapshots).GetProperty("Recent", NestedDeclaredFlags())
    propertyType := (must property).PropertyType
    assert propertyType.GetGenericTypeDefinition() == typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
    assert Object.ReferenceEquals(propertyType.GetGenericArguments()[0], NestedCachedType())

    changed: EventInfo? = typeof(Snapshots).GetEvent("Changed", NestedDeclaredFlags())
    handlerType := (must changed).EventHandlerType
    assert handlerType != null
    assert handlerType.GetGenericTypeDefinition() == typeof(Action<int>).GetGenericTypeDefinition()
    assert Object.ReferenceEquals(handlerType.GetGenericArguments()[0], NestedCachedType())

    formatter := NestedField("formatter").GetValue(new Snapshots()) as Delegate
    assert formatter != null
    delegateMethod := formatter.Method
    parameters := delegateMethod.GetParameters()
    assert delegateMethod.Name.StartsWith("<Lambda>", StringComparison.Ordinal)
    assert parameters.Length == 1
    assert Object.ReferenceEquals(parameters[0].ParameterType, NestedCachedType())
    assert Object.ReferenceEquals(delegateMethod.get_DeclaringType(), typeof(Snapshots))
}

test "a nested source generic and a base signature close over the private nested type" {
    slots := NestedFieldType("slots")
    slotType := slots.GetGenericArguments()[0]
    assert slotType.get_IsGenericType()
    assert Object.ReferenceEquals(slotType.GetGenericArguments()[0], NestedCachedType())

    cachedList: Type? = typeof(Snapshots).GetNestedType("CachedList", BindingFlags.Public | BindingFlags.NonPublic)
    baseType := (must cachedList).BaseType
    assert baseType != null
    assert baseType.GetGenericTypeDefinition() == typeof(List<int>).GetGenericTypeDefinition()
    assert Object.ReferenceEquals(baseType.GetGenericArguments()[0], NestedCachedType())
}

test "a method constraint carries the private nested type inside its generic argument" {
    constrained: MethodInfo? = typeof(Snapshots).GetMethod("Constrained", NestedDeclaredFlags())
    genericParameters := (must constrained).GetGenericArguments()
    assert genericParameters.Length == 1
    constraints := genericParameters[0].GetGenericParameterConstraints()
    assert constraints.Length == 1
    assert constraints[0].GetGenericTypeDefinition() == typeof(IComparer<int>).GetGenericTypeDefinition()
    assert Object.ReferenceEquals(constraints[0].GetGenericArguments()[0], NestedCachedType())
}

test "an array and a nested-generic value round-trip through the constructed dictionaries" {
    snapshots := new Snapshots()
    snapshots.Add("k", "one")
    snapshots.Add("j", "two")

    snapshots.Batch("batch")
    assert snapshots.BatchSize("batch") == 2
    assert snapshots.BatchNote("batch", 1) == "two"
    assert snapshots.BatchSize("absent") == 0

    snapshots.Group("group")
    assert snapshots.GroupedNote("group", 0) == "one"
    assert snapshots.GroupedNote("absent", 0) == ""
}

test "a tuple element typed by the nested declaration keeps its element type" {
    labelled: MethodInfo? = typeof(Snapshots).GetMethod("Labelled", NestedDeclaredFlags())
    selected := must labelled
    returned := selected.ReturnType
    assert returned.get_IsGenericType()
    tupleArguments := returned.GetGenericArguments()
    assert tupleArguments.Length == 2
    assert Object.ReferenceEquals(tupleArguments[0], NestedCachedType())
    assert tupleArguments[1] == typeof(int)
}

// A NESTED TYPE AT TWO DEPTHS. `Leaf` is written bare inside `Mid` and as `Mid.Leaf` from `Deep`;
// both spellings must select the identical CLR type, and both must reach it as a generic argument.
test "a doubly nested type is the same CLR type under either spelling" {
    mid: Type? = typeof(Deep).GetNestedType("Mid", BindingFlags.Public | BindingFlags.NonPublic)
    midType := must mid
    leaf: Type? = midType.GetNestedType("Leaf", BindingFlags.Public | BindingFlags.NonPublic)
    leafType := must leaf

    outerField: FieldInfo? = typeof(Deep).GetField("outer", NestedDeclaredFlags())
    outerType := (must outerField).FieldType
    assert outerType == typeof(List<int>).GetGenericTypeDefinition().MakeGenericType([leafType])

    innerField: FieldInfo? = midType.GetField("inner", NestedDeclaredFlags())
    innerArguments := (must innerField).FieldType.GetGenericArguments()
    assert innerArguments.Length == 2
    assert Object.ReferenceEquals(innerArguments[1], leafType)

    lazyField: FieldInfo? = midType.GetField("lazily", NestedDeclaredFlags())
    lazyArguments := (must lazyField).FieldType.GetGenericArguments()
    assert lazyArguments.Length == 1
    assert Object.ReferenceEquals(lazyArguments[0], leafType)
}

test "the doubly nested shapes run" {
    deep := new Deep()
    deep.Add(4)
    deep.Add(5)
    assert deep.Sum() == 9

    mid := new Deep.Mid()
    mid.Put("a", 7)
    assert mid.Get("a") == 7
    assert mid.Get("b") == -1
    assert mid.LazyValue() == 0
}
