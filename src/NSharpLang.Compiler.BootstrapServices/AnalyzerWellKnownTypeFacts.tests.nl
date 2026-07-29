namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the analyzer's well-known-type owner: the MetadataLoadContext-backed fact bag
// and the three tables that read it. All four were `private`/nested in Analyzer.cs, so no test named
// them directly — their behaviour was pinned only indirectly, through end-to-end diagnostics. This
// is their first DIRECT pinning.

// The fact bag over a real MetadataLoadContext, opened the same way the rest of the compiler opens
// one, so these contracts exercise the true resolution paths rather than a stub.
func WellKnownProbeFacts(context: MetadataLoadContext): AnalyzerWellKnownTypes {
    core := context.LoadFromAssemblyName("System.Runtime")
    return new AnalyzerWellKnownTypes(context, core)
}

func WellKnownTypeName(candidate: Type?): string {
    if candidate == null {
        return "<null>"
    }

    return candidate.get_FullName()
}

test "the fact bag resolves every required core type into the load context, not the runtime" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := WellKnownProbeFacts(context)

        assert WellKnownTypeName(facts.Int32) == "System.Int32"
        assert WellKnownTypeName(facts.Int64) == "System.Int64"
        assert WellKnownTypeName(facts.Single) == "System.Single"
        assert WellKnownTypeName(facts.Double) == "System.Double"
        assert WellKnownTypeName(facts.Decimal) == "System.Decimal"
        assert WellKnownTypeName(facts.Byte) == "System.Byte"
        assert WellKnownTypeName(facts.SByte) == "System.SByte"
        assert WellKnownTypeName(facts.Int16) == "System.Int16"
        assert WellKnownTypeName(facts.UInt16) == "System.UInt16"
        assert WellKnownTypeName(facts.UInt32) == "System.UInt32"
        assert WellKnownTypeName(facts.UInt64) == "System.UInt64"
        assert WellKnownTypeName(facts.Char) == "System.Char"
        assert WellKnownTypeName(facts.Boolean) == "System.Boolean"
        assert WellKnownTypeName(facts.String) == "System.String"
        assert WellKnownTypeName(facts.Void) == "System.Void"
        assert WellKnownTypeName(facts.Object) == "System.Object"
        assert WellKnownTypeName(facts.Delegate) == "System.Delegate"
        assert WellKnownTypeName(facts.SystemType) == "System.Type"

        // These are METADATA types. Confusing them with the compiler's own runtime types is the exact
        // bug the fact bag exists to prevent, so the distinction is pinned rather than assumed.
        assert facts.Int32 != typeof(int)
        assert facts.String != typeof(string)
        assert facts.Object != typeof(object)
    } finally {
        scan.Dispose()
    }
}

test "the fact bag resolves the optional open generics it is asked for" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := WellKnownProbeFacts(context)

        assert WellKnownTypeName(facts.NullableOpen) == "System.Nullable`1"
        assert WellKnownTypeName(facts.ListOpen) == "System.Collections.Generic.List`1"
        assert WellKnownTypeName(facts.IEnumerableOpen) == "System.Collections.Generic.IEnumerable`1"
        assert WellKnownTypeName(facts.ICollectionOpen) == "System.Collections.Generic.ICollection`1"
        assert WellKnownTypeName(facts.IListOpen) == "System.Collections.Generic.IList`1"
        assert WellKnownTypeName(facts.DictionaryOpen) == "System.Collections.Generic.Dictionary`2"
        assert WellKnownTypeName(facts.IDictionaryOpen) == "System.Collections.Generic.IDictionary`2"
        assert WellKnownTypeName(facts.IQueryableOpen) == "System.Linq.IQueryable`1"
        assert WellKnownTypeName(facts.TaskOpen) == "System.Threading.Tasks.Task`1"
        assert WellKnownTypeName(facts.ValueTaskOpen) == "System.Threading.Tasks.ValueTask`1"
        assert WellKnownTypeName(facts.Action) == "System.Action"
        assert WellKnownTypeName(facts.Action1) == "System.Action`1"
        assert WellKnownTypeName(facts.Action2) == "System.Action`2"
        assert WellKnownTypeName(facts.Action3) == "System.Action`3"
        assert WellKnownTypeName(facts.Action4) == "System.Action`4"
        assert WellKnownTypeName(facts.Func1) == "System.Func`1"
        assert WellKnownTypeName(facts.Func2) == "System.Func`2"
        assert WellKnownTypeName(facts.Func3) == "System.Func`3"
        assert WellKnownTypeName(facts.Func4) == "System.Func`4"
        assert WellKnownTypeName(facts.Func5) == "System.Func`5"

        // Every open generic really is an open definition — a closed instantiation here would silently
        // break every MakeGenericType the analyzer performs.
        assert facts.ListOpen.get_IsGenericTypeDefinition()
        assert facts.DictionaryOpen.get_IsGenericTypeDefinition()
        assert facts.Func5.get_IsGenericTypeDefinition()
        assert facts.DictionaryOpen.GetGenericArguments().Length == 2
        assert facts.Func5.GetGenericArguments().Length == 5
    } finally {
        scan.Dispose()
    }
}

test "the lazy runtime accessors answer the same value on every read" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := WellKnownProbeFacts(context)

        // Whether the runtime assembly is reachable from this context or not, the contract is the
        // same: the first read decides, the answer never changes for the rest of the analysis, and a
        // miss is absorbed rather than thrown. A re-probing accessor would let one analysis see two
        // different `Union<,>` definitions.
        firstUnion := facts.GetRuntimeUnionOpen()
        firstResult := facts.GetRuntimeResultOpen()
        assert firstUnion == facts.GetRuntimeUnionOpen()
        assert firstResult == facts.GetRuntimeResultOpen()
        assert firstUnion == facts.GetRuntimeUnionOpen()
    } finally {
        scan.Dispose()
    }
}

test "required types are found through the split core library, not only the core assembly" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null

        // Two probes are not redundant: a reference set can split the framework across facade
        // assemblies and `System.Private.CoreLib` implementations. Handing the bag an assembly that
        // declares NONE of the core types proves the second probe carries the whole required set on
        // its own — if it did not, construction would throw.
        jsonAssembly := context.LoadFromAssemblyName("System.Text.Json")
        assert jsonAssembly.GetType("System.Int32") == null

        splitFacts := new AnalyzerWellKnownTypes(context, jsonAssembly)
        assert WellKnownTypeName(splitFacts.Int32) == "System.Int32"
        assert WellKnownTypeName(splitFacts.String) == "System.String"
        assert WellKnownTypeName(splitFacts.Void) == "System.Void"
        assert WellKnownTypeName(splitFacts.Delegate) == "System.Delegate"

        // The optional generics that are probed in their OWN assemblies are unaffected by the core
        // split, because those probes never consult the core assembly first.
        assert WellKnownTypeName(splitFacts.IQueryableOpen) == "System.Linq.IQueryable`1"
        assert WellKnownTypeName(splitFacts.JsonTypeInfoOpen)
            == "System.Text.Json.Serialization.Metadata.JsonTypeInfo`1"
    } finally {
        scan.Dispose()
    }
}

test "the compiler-known open-generic table maps exactly the names resolvable without an import" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := WellKnownProbeFacts(context)

        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "List", 1) == facts.ListOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "IEnumerable", 1) == facts.IEnumerableOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "IQueryable", 1) == facts.IQueryableOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "ICollection", 1) == facts.ICollectionOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "IList", 1) == facts.IListOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Task", 1) == facts.TaskOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "ValueTask", 1) == facts.ValueTaskOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Dictionary", 2) == facts.DictionaryOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "IDictionary", 2) == facts.IDictionaryOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Func", 1) == facts.Func1
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Func", 2) == facts.Func2
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Func", 3) == facts.Func3
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Func", 4) == facts.Func4
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Func", 5) == facts.Func5
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Action", 1) == facts.Action1
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Action", 2) == facts.Action2
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Action", 3) == facts.Action3
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Action", 4) == facts.Action4

        // Both JsonTypeInfo spellings reach the same definition.
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "JsonTypeInfo", 1) == facts.JsonTypeInfoOpen
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(
            facts,
            "System.Text.Json.Serialization.Metadata.JsonTypeInfo",
            1) == facts.JsonTypeInfoOpen

        // Both Result spellings reach the lazy runtime definition.
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Result", 2)
            == facts.GetRuntimeResultOpen()
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "NSharpLang.Runtime.Result", 2)
            == facts.GetRuntimeResultOpen()
    } finally {
        scan.Dispose()
    }
}

test "the compiler-known table is arity-exact, case-sensitive and unqualified" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := WellKnownProbeFacts(context)

        // Right name, wrong arity.
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "List", 2) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Dictionary", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Func", 6) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Action", 5) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Result", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "JsonTypeInfo", 2) == null

        // Degenerate arities are answers, not crashes — the unresolved-type reporter passes whatever
        // arity it read off the source.
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "List", 0) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "List", -1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Func", 17) == null

        // Case and qualification are both significant: this table is consulted BEFORE the import-based
        // resolver, so a loose match here would silently suppress a `Type not found` diagnostic.
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "list", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "LIST", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "func", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "System.Collections.Generic.List", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, " ", 1) == null

        // Names that are resolvable only through an import are NOT compiler-known.
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "HashSet", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Queue", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "IReadOnlyList", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Span", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(facts, "Nullable", 1) == null

        // With no facts built there is nothing to answer with.
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(null, "List", 1) == null
        assert AnalyzerWellKnownTypeFacts.KnownOpenGenericType(null, "Func", 2) == null
    } finally {
        scan.Dispose()
    }
}

test "the binding-surrogate table is a strict subset of the compiler-known table" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := WellKnownProbeFacts(context)

        // Everything the surrogate table carries, it carries identically.
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "List", 1) == facts.ListOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "IEnumerable", 1) == facts.IEnumerableOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "IQueryable", 1) == facts.IQueryableOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "ICollection", 1) == facts.ICollectionOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "IList", 1) == facts.IListOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Task", 1) == facts.TaskOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "ValueTask", 1) == facts.ValueTaskOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Dictionary", 2) == facts.DictionaryOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "IDictionary", 2) == facts.IDictionaryOpen
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Func", 1) == facts.Func1
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Func", 5) == facts.Func5
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Action", 1) == facts.Action1
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Action", 4) == facts.Action4

        // And the four entries it deliberately OMITS stay omitted. Surrogate binding replaces N#-defined
        // type arguments with `object`; a Result or a JsonTypeInfo reconstructed that way would name a
        // type the program never wrote, so those names are only ever resolved with real arguments.
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Result", 2) == null
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "NSharpLang.Runtime.Result", 2) == null
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "JsonTypeInfo", 1) == null
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(
            facts,
            "System.Text.Json.Serialization.Metadata.JsonTypeInfo",
            1) == null

        // The same arity, case and qualification discipline applies.
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "List", 2) == null
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Func", 6) == null
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "Action", 5) == null
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "list", 1) == null
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, "HashSet", 1) == null
        assert AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(null, "List", 1) == null
    } finally {
        scan.Dispose()
    }
}

test "the no-metadata fallback answers with the compiler's own runtime types" {
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Int) == typeof(int)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Long) == typeof(long)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Float) == typeof(float)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Double) == typeof(double)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Decimal) == typeof(decimal)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Byte) == typeof(byte)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.SByte) == typeof(sbyte)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Short) == typeof(short)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.UShort) == typeof(ushort)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.UInt) == typeof(uint)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.ULong) == typeof(ulong)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Char) == typeof(char)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Bool) == typeof(bool)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.String) == typeof(string)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Object) == typeof(object)

    // `void` has no `typeof` on the columnar surface, so it is read out of the core library — and it
    // must land on the SAME instance the rest of the compiler would produce.
    assert WellKnownTypeName(AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Void))
        == "System.Void"
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Void)
        == typeof(object).get_Assembly().GetType("System.Void")

    // The three non-value built-in names are not CLR types.
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Null) == null
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Never) == null
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new SimpleTypeInfo("Int32")) == null
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new SimpleTypeInfo("System.Int32")) == null
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new SimpleTypeInfo("Widget")) == null
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new SimpleTypeInfo("")) == null
}

test "the no-metadata fallback descends arrays, nullables and oblivious wrappers" {
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new ArrayTypeInfo(BuiltInTypes.Int))
        == typeof(int[])
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
        new ArrayTypeInfo(new ArrayTypeInfo(BuiltInTypes.String))) == typeof(string[][])

    // A nullable is only a nullable when its inner type is a VALUE type; over a reference type the
    // whole conversion fails rather than answering the bare reference type.
    nullableInt := AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new NullableTypeInfo(BuiltInTypes.Int))
    assert nullableInt != null
    assert nullableInt.get_IsGenericType()
    assert nullableInt.GetGenericTypeDefinition()
        == typeof(object).get_Assembly().GetType("System.Nullable`1")
    assert nullableInt.GetGenericArguments()[0] == typeof(int)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new NullableTypeInfo(BuiltInTypes.String))
        == null
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new NullableTypeInfo(BuiltInTypes.Object))
        == null

    // The oblivious wrapper is transparent.
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new ObliviousTypeInfo(BuiltInTypes.Bool))
        == typeof(bool)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
        new ObliviousTypeInfo(new ObliviousTypeInfo(BuiltInTypes.Char))) == typeof(char)
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
        new ObliviousTypeInfo(new ArrayTypeInfo(BuiltInTypes.String))) == typeof(string[])

    // An unmappable element or inner type fails the whole descent.
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
        new ArrayTypeInfo(new SimpleTypeInfo("Widget"))) == null
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
        new NullableTypeInfo(new SimpleTypeInfo("Widget"))) == null
    assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
        new ObliviousTypeInfo(new SimpleTypeInfo("Widget"))) == null
}

test "the no-metadata fallback answers null for every other type family and resolves no alias" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.Unknown) == null
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(BuiltInTypes.InferenceHole) == null
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new ByRefTypeInfo(BuiltInTypes.Int)) == null
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new FunctionTypeInfo()) == null
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new TypeInfo()) == null

        genericArguments := new List<TypeInfo>()
        genericArguments.Add(BuiltInTypes.Int)
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
            new GenericTypeInfo("List", genericArguments)) == null

        unionArms := new List<TypeInfo>()
        unionArms.Add(BuiltInTypes.Int)
        unionArms.Add(BuiltInTypes.String)
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
            new AnonymousUnionTypeInfo(unionArms)) == null

        // A reflection type is NOT read through — this fallback exists precisely because no metadata
        // facts were built, so it never hands back a load-context type.
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(new ReflectionTypeInfo(typeof(int))) == null
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
            new ArrayTypeInfo(new ReflectionTypeInfo(typeof(int)))) == null

        // And an alias is NOT resolved here. The metadata-backed path normalizes aliases before it
        // descends; this one deliberately does not, and that difference is behaviour.
        assert AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(
            new AliasTypeInfo(new SimpleTypeReference("int"))) == null
    } finally {
        scan.Dispose()
    }
}
