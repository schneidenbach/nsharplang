namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `ForeachPatternFacts` — the C# `foreach` pattern lookup, asked of real
// CLR types.
//
// WHAT THESE ROWS ARE FOR. The pattern lookup is the ONE place that decides whether `for x in e`
// compiles, and it is shared by the analyser (which types `x`) and the emitter (which lowers the
// loop). Every row here is a shape the old name table could not see, a member-lookup hazard that
// throws if asked the obvious way, or a disposal rule that differs between a struct, a ref struct
// and a class — the three things that make this lookup harder than `GetMethod("GetEnumerator")`.
func PatternFactsNested(owner: Type, name: string): Type {
    nested := owner.GetNestedType(name)
    if nested == null {
        throw new InvalidOperationException("The foreach pattern contracts require a nested type named " + name + " on " + owner.Name + ".")
    }

    if nested.get_IsGenericTypeDefinition() {
        return nested.MakeGenericType(owner.GetGenericArguments())
    }

    return nested
}

// `typeof(void)` has no N# spelling; the void identity is read off a method that returns nothing.
func PatternFactsVoidType(): Type {
    clear := typeof(List<int>).GetMethod("Clear")
    if clear == null {
        throw new InvalidOperationException("The foreach pattern contracts require List<T>.Clear.")
    }

    return clear.get_ReturnType()
}

func PatternFactsEnumeratorName(collection: Type): string {
    pattern := ForeachPatternFacts.FindPattern(collection)
    if pattern == null {
        return "<none>"
    }

    return pattern.EnumeratorType.Name
}

func PatternFactsElementName(collection: Type): string {
    pattern := ForeachPatternFacts.FindPattern(collection)
    if pattern == null {
        return "<none>"
    }

    return pattern.ElementType.Name
}

// ---- the pattern ------------------------------------------------------------------------------------

// A `List<T>` implements `IEnumerable<T>` AND carries a struct `GetEnumerator`. C# binds the STRUCT,
// which is the whole reason a `foreach` over a list allocates nothing; this row is what pins that the
// pattern is asked BEFORE the interface.
test "the foreach pattern binds a struct enumerator ahead of the interface" {
    assert PatternFactsEnumeratorName(typeof(List<int>)) == "Enumerator"
    assert PatternFactsElementName(typeof(List<int>)) == "Int32"

    listPattern := ForeachPatternFacts.FindPattern(typeof(List<int>))
    assert listPattern != null
    assert listPattern.EnumeratorType.get_IsValueType()
    assert listPattern.MoveNextMethod.Name == "MoveNext"
    assert listPattern.CurrentGetter.Name == "get_Current"
}

test "the foreach pattern reads a dictionary as its pair" {
    assert PatternFactsElementName(typeof(Dictionary<string, int>)) == "KeyValuePair`2"
    assert PatternFactsElementName(PatternFactsNested(typeof(Dictionary<string, int>), "KeyCollection")) == "String"
    assert PatternFactsElementName(PatternFactsNested(typeof(Dictionary<string, int>), "ValueCollection")) == "Int32"
}

// An INTERFACE has no `BaseType`, so a lookup that only walks the base chain misses every member an
// interface inherits. `IReadOnlyList<T>` declares none of the three itself.
test "the foreach pattern walks base interfaces for an interface collection" {
    assert PatternFactsEnumeratorName(typeof(IReadOnlyList<int>)) == "IEnumerator`1"
    assert PatternFactsElementName(typeof(IReadOnlyList<int>)) == "Int32"
    assert PatternFactsElementName(typeof(IEnumerable<string>)) == "String"
}

// `Span<T>.Enumerator.Current` is a `ref T`. The element is `T`: the by-ref spelling is the
// enumerator's way of avoiding a second copy, and the loop variable is a copy of the element.
test "the foreach pattern strips a by-ref Current down to the element" {
    spanPattern := ForeachPatternFacts.FindPattern(typeof(Span<int>))
    assert spanPattern != null
    assert spanPattern.CurrentReturnsByRef
    assert spanPattern.ElementType.Name == "Int32"
    assert !spanPattern.ElementType.get_IsByRef()

    readOnlyPattern := ForeachPatternFacts.FindPattern(typeof(ReadOnlySpan<char>))
    assert readOnlyPattern != null
    assert readOnlyPattern.CurrentReturnsByRef
    assert readOnlyPattern.ElementType.Name == "Char"
}

test "the foreach pattern finds shapes no name table listed" {
    assert PatternFactsElementName(PatternFactsNested(typeof(System.Text.Json.JsonElement), "ArrayEnumerator")) == "JsonElement"
    assert PatternFactsElementName(typeof(System.Collections.BitArray)) == "Object"
}

// An `IEnumerator<T>` is NOT a sequence: it has no `GetEnumerator`, which is the whole reason C#
// refuses `foreach (var x in enumerator)`. An ARRAY, by contrast, does answer the pattern — through
// `System.Array`'s non-generic enumerator — and the walk that types a `foreach` answers arrays in
// its own arm before reaching this one, because `object` is the wrong element type for `int[]`.
test "the foreach pattern refuses what is not an enumerator source" {
    assert ForeachPatternFacts.FindPattern(typeof(int)) == null
    assert ForeachPatternFacts.FindPattern(typeof(IEnumerator<int>)) == null
    assert ForeachPatternFacts.FindPattern(typeof(Version)) == null
    assert PatternFactsElementName(typeof(string[])) == "Object"
}

// ---- the interface arms ------------------------------------------------------------------------------

test "the sequence interface lookup answers the one construction a type names" {
    listSequence := ForeachPatternFacts.FindSequenceInterface(typeof(List<int>))
    assert listSequence != null
    assert listSequence.GetGenericArguments()[0].Name == "Int32"

    assert ForeachPatternFacts.FindSequenceInterface(typeof(int)) == null
    assert ForeachPatternFacts.FindAsyncSequenceInterface(typeof(IAsyncEnumerable<string>)) != null
    assert ForeachPatternFacts.FindAsyncSequenceInterface(typeof(List<int>)) == null
}

// `List<int>` names `IEnumerable<int>` through the class AND through `IList<int>`. That is ONE
// construction reached twice, not an ambiguity, and the lookup has to tell them apart.
test "one sequence construction reached twice is not an ambiguity" {
    assert ForeachPatternFacts.SameConstruction(typeof(IEnumerable<int>), typeof(IEnumerable<int>))
    assert !ForeachPatternFacts.SameConstruction(typeof(IEnumerable<int>), typeof(IEnumerable<string>))
    assert !ForeachPatternFacts.SameConstruction(typeof(Dictionary<string, int>), typeof(IEnumerable<int>))
}

test "the non-generic sequence and the disposable interface are recognised by name" {
    assert ForeachPatternFacts.ImplementsNonGenericSequence(typeof(List<int>))
    assert ForeachPatternFacts.ImplementsNonGenericSequence(typeof(System.Collections.BitArray))
    assert !ForeachPatternFacts.ImplementsNonGenericSequence(typeof(int))

    assert ForeachPatternFacts.ImplementsDisposable(PatternFactsNested(typeof(List<int>), "Enumerator"))
    assert ForeachPatternFacts.ImplementsDisposable(typeof(IEnumerator<int>))
    assert !ForeachPatternFacts.ImplementsDisposable(typeof(int))
}

// ---- disposal ----------------------------------------------------------------------------------------

// A REF STRUCT CAN NAME `IDisposable` AND STILL NOT BE DISPOSABLE THROUGH IT. `Span<T>.Enumerator`
// implements `IEnumerator<T>` — which is legal for a by-ref-like type on this runtime — so the
// interface test answers YES, but no by-ref-like value can be converted to an interface, so the only
// disposal C# will emit is a PATTERN `void Dispose()`. It implements `Dispose` EXPLICITLY and
// therefore has no public one, which is why a loop over a span disposes nothing and carries no
// protected region at all. Asking the interface question here instead would emit a `constrained.`
// call on a value that cannot be constrained.
test "a ref struct enumerator disposes only through the pattern" {
    spanPattern := ForeachPatternFacts.FindPattern(typeof(Span<int>))
    assert spanPattern != null
    assert spanPattern.EnumeratorType.get_IsByRefLike()
    assert ForeachPatternFacts.ImplementsDisposable(spanPattern.EnumeratorType)
    assert ForeachPatternFacts.FindPatternDispose(spanPattern.EnumeratorType) == null
}

test "a pattern Dispose must be parameterless and return void" {
    assert ForeachPatternFacts.FindPatternDispose(PatternFactsNested(typeof(List<int>), "Enumerator")) != null
    assert ForeachPatternFacts.FindPatternDispose(typeof(int)) == null
}

// ---- the identity tests ------------------------------------------------------------------------------

// Every identity in this lookup is by `FullName`, because the analyser reads referenced assemblies
// through a MetadataLoadContext where the projected `System.Boolean` is not `typeof(bool)`.
test "the pattern identity tests read full names" {
    assert ForeachPatternFacts.IsBoolean(typeof(bool))
    assert !ForeachPatternFacts.IsBoolean(typeof(int))
    assert !ForeachPatternFacts.IsBoolean(null)
    assert ForeachPatternFacts.IsString(typeof(string))
    assert !ForeachPatternFacts.IsString(typeof(char))
    assert ForeachPatternFacts.IsVoid(PatternFactsVoidType())
    assert !ForeachPatternFacts.IsVoid(typeof(int))
}

// A member lookup that asks the binder throws `AmbiguousMatchException` when a derived declaration
// shadows the one being asked for. This walk answers the most derived declaration instead.
test "the member walk answers without the binder's ambiguity" {
    assert ForeachPatternFacts.FindParameterlessInstanceMethod(typeof(List<int>), "GetEnumerator") != null
    assert ForeachPatternFacts.FindParameterlessInstanceMethod(typeof(List<int>), "Clear") != null
    assert ForeachPatternFacts.FindParameterlessInstanceMethod(typeof(List<int>), "Add") == null
    assert ForeachPatternFacts.FindParameterlessInstanceMethod(typeof(List<int>), "NoSuchMember") == null
    assert ForeachPatternFacts.FindParameterlessInstanceMethod(null, "GetEnumerator") == null

    assert ForeachPatternFacts.FindCurrentGetter(typeof(IEnumerator<int>)) != null
    assert ForeachPatternFacts.FindCurrentGetter(typeof(List<int>)) == null
    assert ForeachPatternFacts.FindCurrentGetter(null) == null
}
