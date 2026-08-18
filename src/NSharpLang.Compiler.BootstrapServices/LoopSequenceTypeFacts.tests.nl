namespace NSharpLang.Compiler

import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `LoopSequenceTypeFacts`, IN N#.
//
// These absorb `tests/LoopSequenceTypeFactsTests.cs`, the last canonical C# assertion layer over
// `LoopSequenceTypeFacts.nl`, into the file that already carried this subject's one native
// contract. The subject answers what a `for x in xs` loop BINDS: given the sequence's resolved
// generic type, what is `x`?
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. The entry point takes a constructed
// `GenericTypeInfo`, which declines at `emit.local.initializer` from a `tests/native` project
// because the model lives in a dependency assembly. Here it is the same assembly's own.
//
// WHY THE ANSWER IS READ THROUGH HELPERS. The kernel answers `TypeInfo?`, and `.ToString()` on a
// user N# class needs an `object` receiver — `(value as object).ToString()` — so the text of an
// answer is read through `LoopFactsElementText` rather than spelled at every assertion.
//
// THE COVERAGE ADDS THE THREE NAME TABLES, WHICH THE C# ONLY EVER REACHED THROUGH A CONSTRUCTED
// TYPE. The deleted file drove 25 rows through the single public door; the three predicates behind
// it — 5 dictionary names, 2 span names, 15 collection names — are asserted directly here, because
// a table with a missing row is exactly what a sampled door cannot see.
//
// THE FIVE THINGS IT IS EASY TO GET WRONG:
//
// (1) A DICTIONARY DOES NOT ENUMERATE ITS VALUES. Five dictionary-shaped names with TWO arguments
// answer a SYNTHESISED `KeyValuePair<K, V>`, not `V` — and that synthesised type carries a real
// runtime generic definition, seeded through `Type.GetType`, so downstream member lookup works.
//
// (2) SYNC AND ASYNC ARE SEPARATE DOORS, NOT A FILTER. `requireAsync: true` answers ONLY
// `IAsyncEnumerable<T>` — no dictionary, no span, no collection — and `requireAsync: false` never
// answers for `IAsyncEnumerable`.
//
// (3) ARITY IS PART OF THE ANSWER, AND IT DIFFERS BY FAMILY. Dictionaries need exactly two;
// everything else needs exactly one. `IEnumerable<>` with none and `IAsyncEnumerable<K, V>` are
// both refused.
//
// (4) THE NAME IS NORMALISED NAMESPACE-FIRST, THEN CLR ARITY SUFFIX, so
// `System.Collections.Generic.IEnumerable`1` and `IEnumerable` are one name.
//
// (5) A SOURCE GENERIC CANNOT IMPERSONATE A RUNTIME ONE BY NAME. When `GenericDefinition` is set
// to anything that is not a `ReflectionTypeInfo`, the answer is `null` regardless of the name —
// which is what stops a user type called `List` from being walked as the BCL's.

func LoopFactsNoInfos(): List<TypeInfo> {
    return new List<TypeInfo>()
}

func LoopFactsInfos1(first: TypeInfo): List<TypeInfo> {
    items := new List<TypeInfo>()
    items.Add(first)
    return items
}

func LoopFactsInfos2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    items := new List<TypeInfo>()
    items.Add(first)
    items.Add(second)
    return items
}

// The C# wrote `…?.ToString()`; an N# user class needs an `object` receiver for that.
func LoopFactsElementText(value: TypeInfo?): string {
    if value != null {
        valueObject := value as object
        return valueObject.ToString()
    }

    return "<null>"
}

// The C# wrote `Assert.IsType<GenericTypeInfo>(…)`, which asserts the RUNTIME type and returns the
// cast value; this answers the same question as a name.
func LoopFactsRuntimeKind(value: TypeInfo?): string {
    if value != null {
        if value as GenericTypeInfo != null {
            return "GenericTypeInfo"
        }

        valueObject := value as object
        return valueObject.GetType().Name
    }

    return "<null>"
}

func LoopFactsGenericName(value: TypeInfo?): string {
    generic := value as GenericTypeInfo
    if generic != null {
        return generic.Name
    }

    return "<not generic>"
}

func LoopFactsGenericArgumentText(value: TypeInfo?, index: int): string {
    generic := value as GenericTypeInfo
    if generic != null {
        if index >= 0 && index < generic.TypeArguments.Count {
            return LoopFactsElementText(generic.TypeArguments[index])
        }
    }

    return "<none>"
}

// A synchronous sequence of `int`, by name — the shape all eighteen accepted sync names share.
func LoopFactsSyncElementText(name: string): string {
    return LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(
        new GenericTypeInfo(name, LoopFactsInfos1(BuiltInTypes.Int)),
        false))
}

test "source generics cannot impersonate runtime loop sequence shapes by name" {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    sourceList := new GenericTypeInfo(
        "List",
        arguments,
        new SimpleTypeInfo("source List"))

    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(
        sourceList,
        false) == null
}

// ---- the synchronous door -------------------------------------------------------------------------

// Successor to LoopSequenceTypeFacts_ReturnsElementTypeForSyncSequences — all eighteen of its rows,
// expanded out of the `[Theory]`, in order.
test "loop sequence type facts answer the element type for every sync sequence" {
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IEnumerable", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("System.Collections.Generic.IEnumerable`1", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("List", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("HashSet", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IList", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("ICollection", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IQueryable", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("ISet", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Queue", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Stack", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("LinkedList", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Collection", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("ObservableCollection", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("SortedSet", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IReadOnlyList", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IReadOnlyCollection", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Span", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("System.ReadOnlySpan`1", LoopFactsInfos1(BuiltInTypes.Int)), false)) == "int"
}

// Successor to LoopSequenceTypeFacts_ReturnsElementTypeForAsyncSequences — both of its rows.
test "loop sequence type facts answer the element type for every async sequence" {
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IAsyncEnumerable", LoopFactsInfos1(BuiltInTypes.String)), true)) == "string"
    assert LoopFactsElementText(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("System.Collections.Generic.IAsyncEnumerable`1", LoopFactsInfos1(BuiltInTypes.String)), true)) == "string"
}

// ---- the dictionary door --------------------------------------------------------------------------

// Successor to LoopSequenceTypeFacts_DictionariesEnumerateKeyValuePairs — all five of its rows,
// with each row's three assertions kept: the runtime type, the name, and both type arguments.
test "loop sequence type facts enumerate dictionaries as key value pairs" {
    dictionary := LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Dictionary", LoopFactsInfos2(BuiltInTypes.String, BuiltInTypes.Int)), false)
    assert LoopFactsRuntimeKind(dictionary) == "GenericTypeInfo"
    assert LoopFactsGenericName(dictionary) == "KeyValuePair"
    assert LoopFactsGenericArgumentText(dictionary, 0) == "string"
    assert LoopFactsGenericArgumentText(dictionary, 1) == "int"

    interfaceDictionary := LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IDictionary", LoopFactsInfos2(BuiltInTypes.String, BuiltInTypes.Int)), false)
    assert LoopFactsRuntimeKind(interfaceDictionary) == "GenericTypeInfo"
    assert LoopFactsGenericName(interfaceDictionary) == "KeyValuePair"
    assert LoopFactsGenericArgumentText(interfaceDictionary, 0) == "string"
    assert LoopFactsGenericArgumentText(interfaceDictionary, 1) == "int"

    readOnlyDictionary := LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IReadOnlyDictionary", LoopFactsInfos2(BuiltInTypes.String, BuiltInTypes.Int)), false)
    assert LoopFactsRuntimeKind(readOnlyDictionary) == "GenericTypeInfo"
    assert LoopFactsGenericName(readOnlyDictionary) == "KeyValuePair"
    assert LoopFactsGenericArgumentText(readOnlyDictionary, 0) == "string"
    assert LoopFactsGenericArgumentText(readOnlyDictionary, 1) == "int"

    sortedDictionary := LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("SortedDictionary", LoopFactsInfos2(BuiltInTypes.String, BuiltInTypes.Int)), false)
    assert LoopFactsRuntimeKind(sortedDictionary) == "GenericTypeInfo"
    assert LoopFactsGenericName(sortedDictionary) == "KeyValuePair"
    assert LoopFactsGenericArgumentText(sortedDictionary, 0) == "string"
    assert LoopFactsGenericArgumentText(sortedDictionary, 1) == "int"

    sortedList := LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("SortedList", LoopFactsInfos2(BuiltInTypes.String, BuiltInTypes.Int)), false)
    assert LoopFactsRuntimeKind(sortedList) == "GenericTypeInfo"
    assert LoopFactsGenericName(sortedList) == "KeyValuePair"
    assert LoopFactsGenericArgumentText(sortedList, 0) == "string"
    assert LoopFactsGenericArgumentText(sortedList, 1) == "int"
}

// NOT IN THE DELETED FILE. The synthesised pair carries a REFLECTION generic definition, which is
// what lets the loop variable's `.Key` and `.Value` resolve downstream — a synthesised type with a
// null definition would be walkable and useless.
test "loop sequence type facts seed the synthesised pair with a runtime definition" {
    pairInfo := LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Dictionary", LoopFactsInfos2(BuiltInTypes.String, BuiltInTypes.Int)), false) as GenericTypeInfo
    assert pairInfo != null
    assert pairInfo.GenericDefinition != null
    assert pairInfo.GenericDefinition as ReflectionTypeInfo != null
    assert pairInfo.TypeArguments.Count == 2
}

// NOT IN THE DELETED FILE. A dictionary is a dictionary only with exactly two arguments, and never
// in the async door.
test "loop sequence type facts refuse dictionaries at the wrong arity or door" {
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Dictionary", LoopFactsInfos1(BuiltInTypes.String)), false) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Dictionary", LoopFactsNoInfos()), false) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Dictionary", LoopFactsInfos2(BuiltInTypes.String, BuiltInTypes.Int)), true) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("SortedList", LoopFactsInfos2(BuiltInTypes.String, BuiltInTypes.Int)), true) == null
}

// ---- the refusals ----------------------------------------------------------------------------------

// Successor to LoopSequenceTypeFacts_RejectsWrongModeAndArity — all five of its assertions.
test "loop sequence type facts refuse the wrong mode and the wrong arity" {
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IAsyncEnumerable", LoopFactsInfos1(BuiltInTypes.Int)), false) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IEnumerable", LoopFactsInfos1(BuiltInTypes.Int)), true) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IEnumerable", LoopFactsNoInfos()), false) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IAsyncEnumerable", LoopFactsInfos2(BuiltInTypes.Int, BuiltInTypes.String)), true) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Task", LoopFactsInfos1(BuiltInTypes.Int)), false) == null

    // Not in the deleted file: the async door refuses spans and collections too, and an unrelated
    // generic is refused in either door.
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Span", LoopFactsInfos1(BuiltInTypes.Int)), true) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("List", LoopFactsInfos1(BuiltInTypes.Int)), true) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("Task", LoopFactsInfos1(BuiltInTypes.Int)), true) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("IEnumerator", LoopFactsInfos1(BuiltInTypes.Int)), false) == null
    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(new GenericTypeInfo("List", LoopFactsInfos2(BuiltInTypes.Int, BuiltInTypes.String)), false) == null
}

// ---- the three name tables ---------------------------------------------------------------------------

// NOT IN THE DELETED FILE. All five dictionary names, exhaustively, plus the near misses.
test "loop sequence type facts name exactly five dictionary shapes" {
    assert LoopSequenceTypeFacts.IsDictionaryTypeName("Dictionary")
    assert LoopSequenceTypeFacts.IsDictionaryTypeName("IDictionary")
    assert LoopSequenceTypeFacts.IsDictionaryTypeName("IReadOnlyDictionary")
    assert LoopSequenceTypeFacts.IsDictionaryTypeName("SortedDictionary")
    assert LoopSequenceTypeFacts.IsDictionaryTypeName("SortedList")

    assert !LoopSequenceTypeFacts.IsDictionaryTypeName("ConcurrentDictionary")
    assert !LoopSequenceTypeFacts.IsDictionaryTypeName("ImmutableDictionary")
    assert !LoopSequenceTypeFacts.IsDictionaryTypeName("List")
    assert !LoopSequenceTypeFacts.IsDictionaryTypeName("dictionary")
    assert !LoopSequenceTypeFacts.IsDictionaryTypeName("")
}

// NOT IN THE DELETED FILE. Both span names, exhaustively — the family that must NOT be widened,
// because a span is not a collection and cannot be boxed into one.
test "loop sequence type facts name exactly two span shapes" {
    assert LoopSequenceTypeFacts.IsSpanTypeName("Span")
    assert LoopSequenceTypeFacts.IsSpanTypeName("ReadOnlySpan")

    assert !LoopSequenceTypeFacts.IsSpanTypeName("Memory")
    assert !LoopSequenceTypeFacts.IsSpanTypeName("ReadOnlyMemory")
    assert !LoopSequenceTypeFacts.IsSpanTypeName("span")
    assert !LoopSequenceTypeFacts.IsSpanTypeName("")
}

// NOT IN THE DELETED FILE. All fifteen collection names, exhaustively.
test "loop sequence type facts name exactly fifteen collection shapes" {
    assert LoopSequenceTypeFacts.IsCollectionTypeName("List")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("HashSet")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("IList")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("ICollection")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("IEnumerable")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("IQueryable")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("ISet")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("Queue")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("Stack")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("LinkedList")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("Collection")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("ObservableCollection")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("SortedSet")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("IReadOnlyList")
    assert LoopSequenceTypeFacts.IsCollectionTypeName("IReadOnlyCollection")

    assert !LoopSequenceTypeFacts.IsCollectionTypeName("IEnumerator")
    assert !LoopSequenceTypeFacts.IsCollectionTypeName("IAsyncEnumerable")
    assert !LoopSequenceTypeFacts.IsCollectionTypeName("Span")
    assert !LoopSequenceTypeFacts.IsCollectionTypeName("Dictionary")
    assert !LoopSequenceTypeFacts.IsCollectionTypeName("ImmutableArray")
    assert !LoopSequenceTypeFacts.IsCollectionTypeName("")
}

// NOT IN THE DELETED FILE. The two normalisations, in the kernel's order.
test "loop sequence type facts normalise the namespace and the arity suffix" {
    assert LoopSequenceTypeFacts.UnqualifiedTypeName("System.Collections.Generic.IEnumerable") == "IEnumerable"
    assert LoopSequenceTypeFacts.UnqualifiedTypeName("IEnumerable") == "IEnumerable"
    assert LoopSequenceTypeFacts.UnqualifiedTypeName("Trailing.") == "Trailing."
    assert LoopSequenceTypeFacts.StripGenericArity("IEnumerable`1") == "IEnumerable"
    assert LoopSequenceTypeFacts.StripGenericArity("IEnumerable") == "IEnumerable"
    assert LoopSequenceTypeFacts.StripGenericArity(LoopSequenceTypeFacts.UnqualifiedTypeName("System.ReadOnlySpan`1")) == "ReadOnlySpan"

    // The composed effect at the door: the qualified spelling and the bare one answer alike.
    assert LoopFactsSyncElementText("System.Collections.Generic.IReadOnlyCollection`1") == "int"
    assert LoopFactsSyncElementText("IReadOnlyCollection") == "int"
}
