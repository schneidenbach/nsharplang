namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR `GeneratorSequenceTypeFacts`, IN N#.
//
// These replace `tests/GeneratorSequenceTypeFactsTests.cs`, the last canonical C# assertion layer
// over `GeneratorSequenceTypeFacts.nl`. The subject answers the ONE question a `func*` declaration
// asks: "is this return type a sequence the generator can actually yield into?" — and it also owns
// the two sentences the diagnostic prints when the answer is no.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. The entry point takes a CONSTRUCTED
// `GenericTypeInfo`, and a dependency-assembly constructed object declines at
// `emit.local.initializer` from a `tests/native` project. Here the model and the subject are the
// same assembly's own.
//
// THE COVERAGE IS TABLE-COMPLETE, WHICH THE C# WAS NOT. The deleted file sampled the accepted
// names through the outer `IsSequenceReturnType` door only, and pinned the two suggestion strings
// with a SUBSTRING check. Here the inner predicate is asserted directly for every accepted name in
// both modes, and the two suggestion sentences are pinned WHOLE — a substring check cannot see a
// sentence that has lost its second half.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) THE SYNC AND ASYNC TABLES ARE DISJOINT, NOT NESTED. `IEnumerable` is accepted for `func*` and
// REFUSED for `async func*`; `IAsyncEnumerable` is the exact mirror. There is no name accepted by
// both, so a single shared table would be wrong in both directions.
//
// (2) ARITY IS PART OF THE ANSWER AND IT IS CHECKED FIRST. Exactly one type argument, in both
// modes — `IEnumerable` with none and `IAsyncEnumerable` with two are both refused before the name
// is even considered.
//
// (3) THE NAME IS NORMALISED TWICE, IN ORDER: NAMESPACE FIRST, THEN CLR ARITY SUFFIX. The kernel
// strips to the last dot and then to the backtick, so `System.Collections.Generic.IEnumerable`1`
// and `IEnumerable` are the same name. Doing it in the other order would leave a backtick inside
// the namespace-stripped tail of a name like `A.B`1.C`, which is why the order is contractable.
//
// (4) A NON-GENERIC TYPE IS REFUSED WITHOUT REACHING THE TABLE. `IsSequenceReturnType` casts to
// `GenericTypeInfo` first and answers false when the cast fails, so a bare `IEnumerable` written
// without type arguments never gets an arity or a name check at all.
func GenSeqNoInfos(): List<TypeInfo> {
    return new List<TypeInfo>()
}

func GenSeqInfos1(first: TypeInfo): List<TypeInfo> {
    items := new List<TypeInfo>()
    items.Add(first)
    return items
}

func GenSeqInfos2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    items := new List<TypeInfo>()
    items.Add(first)
    items.Add(second)
    return items
}

// ---- the outer door ------------------------------------------------------------------------------

// Successor to GeneratorSequenceTypeFacts_AcceptsSequenceReturnTypes — all eight of its rows, in
// order, expanded out of the `[Theory]` the C# used.
test "generator sequence type facts accept every sequence return type" {
    assert GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IEnumerable", GenSeqInfos1(BuiltInTypes.Int)), false)
    assert GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("System.Collections.Generic.ICollection", GenSeqInfos1(BuiltInTypes.Int)), false)
    assert GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("List", GenSeqInfos1(BuiltInTypes.Int)), false)
    assert GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IList`1", GenSeqInfos1(BuiltInTypes.Int)), false)
    assert GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("System.Collections.Generic.IReadOnlyCollection`1", GenSeqInfos1(BuiltInTypes.Int)), false)
    assert GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IReadOnlyList", GenSeqInfos1(BuiltInTypes.Int)), false)
    assert GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IAsyncEnumerable", GenSeqInfos1(BuiltInTypes.Int)), true)
    assert GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("System.Collections.Generic.IAsyncEnumerable`1", GenSeqInfos1(BuiltInTypes.Int)), true)
}

// Successor to GeneratorSequenceTypeFacts_RejectsNonSequenceReturnTypes — all five of its rows.
test "generator sequence type facts refuse every non sequence return type" {
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IEnumerator", GenSeqInfos1(BuiltInTypes.Int)), false)
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IAsyncEnumerable", GenSeqInfos1(BuiltInTypes.Int)), false)
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IEnumerable", GenSeqInfos1(BuiltInTypes.Int)), true)
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("Task", GenSeqInfos1(BuiltInTypes.Int)), true)
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("Task", GenSeqInfos1(BuiltInTypes.Int)), false)

    // Not in the deleted file: the outer door casts before it counts or names, so a type that is
    // not generic at all is refused without reaching the table.
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new SimpleTypeInfo("IEnumerable"), false)
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(BuiltInTypes.Int, false)
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new ExternalTypeInfo("System.Collections.Generic.IEnumerable`1"), false)
}

// Successor to GeneratorSequenceTypeFacts_RejectsWrongArity — both of its assertions.
test "generator sequence type facts refuse the wrong arity in both modes" {
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IEnumerable", GenSeqNoInfos()), false)
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IAsyncEnumerable", GenSeqInfos2(BuiltInTypes.Int, BuiltInTypes.String)), true)

    // Not in the deleted file: the gate is symmetric — the async name with none, and the sync name
    // with two, are refused the same way.
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("IAsyncEnumerable", GenSeqNoInfos()), true)
    assert !GeneratorSequenceTypeFacts.IsSequenceReturnType(new GenericTypeInfo("List", GenSeqInfos2(BuiltInTypes.Int, BuiltInTypes.String)), false)
}

// ---- the inner table ----------------------------------------------------------------------------

// NOT IN THE DELETED FILE. `IsGeneratorSequenceTypeName` is the table itself, and the C# only ever
// reached it through a constructed type. All six accepted sync names, exhaustively.
test "generator sequence type facts admit exactly six synchronous sequence names" {
    assert GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("List", 1, false)
    assert GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IEnumerable", 1, false)
    assert GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("ICollection", 1, false)
    assert GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IList", 1, false)
    assert GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IReadOnlyCollection", 1, false)
    assert GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IReadOnlyList", 1, false)

    // The near misses, one per accepted name, and the async name in the sync mode.
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("LinkedList", 1, false)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IEnumerator", 1, false)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("Collection", 1, false)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("ISet", 1, false)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IReadOnlyDictionary", 1, false)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IAsyncEnumerable", 1, false)
}

// NOT IN THE DELETED FILE. The async table has exactly one member, and the sync names are all
// refused in that mode.
test "generator sequence type facts admit exactly one asynchronous sequence name" {
    assert GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IAsyncEnumerable", 1, true)
    assert GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("System.Collections.Generic.IAsyncEnumerable`1", 1, true)

    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("List", 1, true)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IEnumerable", 1, true)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("ICollection", 1, true)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IList", 1, true)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IReadOnlyCollection", 1, true)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IReadOnlyList", 1, true)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IAsyncEnumerator", 1, true)
}

// NOT IN THE DELETED FILE. Arity is checked BEFORE the name, in both modes.
test "generator sequence type facts check arity before the name" {
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IEnumerable", 0, false)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IEnumerable", 2, false)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IAsyncEnumerable", 0, true)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("IAsyncEnumerable", 2, true)
    assert !GeneratorSequenceTypeFacts.IsGeneratorSequenceTypeName("NotASequenceAtAll", 0, false)
}

// ---- the two normalisations ---------------------------------------------------------------------

// NOT IN THE DELETED FILE. Namespace stripping and CLR arity stripping are separate steps, and
// this pins each one on its own before the table composes them.
test "generator sequence type facts normalise the namespace and the arity suffix" {
    assert GeneratorSequenceTypeFacts.UnqualifiedTypeName("System.Collections.Generic.IEnumerable") == "IEnumerable"
    assert GeneratorSequenceTypeFacts.UnqualifiedTypeName("IEnumerable") == "IEnumerable"
    assert GeneratorSequenceTypeFacts.UnqualifiedTypeName("A.B") == "B"
    assert GeneratorSequenceTypeFacts.UnqualifiedTypeName("") == ""

    // A trailing dot has nothing after it, so the whole value survives rather than becoming empty.
    assert GeneratorSequenceTypeFacts.UnqualifiedTypeName("Trailing.") == "Trailing."

    assert GeneratorSequenceTypeFacts.StripGenericArity("IEnumerable`1") == "IEnumerable"
    assert GeneratorSequenceTypeFacts.StripGenericArity("IEnumerable") == "IEnumerable"
    assert GeneratorSequenceTypeFacts.StripGenericArity("`1") == ""
    assert GeneratorSequenceTypeFacts.StripGenericArity("") == ""

    // Composed in the kernel's order — namespace first, then arity.
    assert GeneratorSequenceTypeFacts.StripGenericArity(GeneratorSequenceTypeFacts.UnqualifiedTypeName("System.Collections.Generic.IReadOnlyCollection`1")) == "IReadOnlyCollection"
}

// ---- the diagnostic sentences -------------------------------------------------------------------

// Successor to GeneratorSequenceTypeFacts_OwnsDiagnosticText — all four of its assertions, with
// the two `Assert.Contains` substring checks tightened to the WHOLE sentence.
test "generator sequence type facts own both diagnostic sentences whole" {
    assert GeneratorSequenceTypeFacts.ExpectedSequenceKind(false) == "a synchronous enumerable sequence type"
    assert GeneratorSequenceTypeFacts.ExpectedSequenceKind(true) == "an async enumerable sequence type"
    assert GeneratorSequenceTypeFacts.ReturnTypeSuggestion(false).Contains("IEnumerable<T>")
    assert GeneratorSequenceTypeFacts.ReturnTypeSuggestion(true).Contains("IAsyncEnumerable<T>")

    assert GeneratorSequenceTypeFacts.ReturnTypeSuggestion(false) == "Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`."
    assert GeneratorSequenceTypeFacts.ReturnTypeSuggestion(true) == "Use `IAsyncEnumerable<T>` for `async func*`."
}
