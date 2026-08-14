namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// CONTRACTS FOR THE READ-ONLY DICTIONARY CATALOG ROW (task 019 slice 15, stage 1).
//
// `IReadOnlyDictionary<K, V>` is the ONE collection head the columnar catalog did not carry, and its
// absence is what walled `CodeIntelligenceService.GetSourceText` at slice 13 — a static N# parameter
// of that type declines at `emit.declaration.method-param`, while the same parameter spelled
// `Dictionary<K, V>` resolves. These contracts publish the head and prove every row BY EXECUTION.
//
// THE HEAD IS FETCHED BY NAME AND NOT BY `typeof`, AND THAT IS THE POINT OF THE TWO STAGES. This
// file is compiled by the PINNED toolset — the one that does not yet know the head — so writing
// `typeof(IReadOnlyDictionary<string, string>)` here would decline the whole file. Reflection by
// name is the only spelling available until the toolset carries the row it is publishing.
//
// EVERY ROW IS ASKED TWICE. Each assertion about the new head is paired with a CONTROL over
// `Dictionary` or `SortedDictionary` whose answer must not have moved, and with a NEGATIVE that must
// stay refused — because a catalog row that accidentally admits its neighbours is worse than a
// missing one.
//
// THE MUTATORS STAY OUT, BY CONSTRUCTION. The interface declares `ContainsKey`, `TryGetValue`,
// `get_Item`, `Keys`, `Values` and inherits `Count`; it declares NO `Add`, `Remove`, `Clear` or
// `set_Item`, so the read-only head is admitted to the READ predicates only and a write through it
// keeps declining exactly as it did before the row existed.
func RodCatalogDefinition(): Type {
    definition := Type.GetType("System.Collections.Generic.IReadOnlyDictionary`2")
    if definition == null {
        throw new InvalidOperationException("System.Collections.Generic.IReadOnlyDictionary`2 runtime type was not found.")
    }
    return definition
}

func RodCatalogClosed(key: Type, value: Type): Type {
    arguments := new Type[](2)
    arguments[0] = key
    arguments[1] = value
    return RodCatalogDefinition().MakeGenericType(arguments)
}

func RodCatalogCanonicals(first: string, second: string): List<string> {
    values := new List<string>()
    values.Add(first)
    values.Add(second)
    return values
}

test "the read-only dictionary head resolves through the planner, and its two neighbours still do" {
    bindings := ColumnarRangePlannerEmptyBindings()

    resolved := typeof(object)
    assert ColumnarTypeOfPlanner.TryResolveCollection("IReadOnlyDictionary", RodCatalogCanonicals("string", "string"), bindings, out resolved)
    assert resolved == RodCatalogClosed(typeof(string), typeof(string))

    // CONTROL — the two heads that already resolved must resolve to exactly what they always did.
    dictionary := typeof(object)
    assert ColumnarTypeOfPlanner.TryResolveCollection("Dictionary", RodCatalogCanonicals("string", "string"), bindings, out dictionary)
    assert dictionary == typeof(Dictionary<string, string>)

    sorted := typeof(object)
    assert ColumnarTypeOfPlanner.TryResolveCollection("SortedDictionary", RodCatalogCanonicals("string", "int"), bindings, out sorted)
    assert sorted == typeof(SortedDictionary<string, int>)
}

test "the read-only dictionary head carries Dictionary's arity and element rules, not looser ones" {
    bindings := ColumnarRangePlannerEmptyBindings()

    // ONE argument is not two: the arity gate is the same one the two concrete heads use.
    oneArgument := new List<string>()
    oneArgument.Add("string")
    single := typeof(object)
    assert ColumnarTypeOfPlanner.TryResolveCollection("IReadOnlyDictionary", oneArgument, bindings, out single) == false

    // An unresolvable argument refuses the whole head rather than closing over `object`.
    unknown := typeof(object)
    assert ColumnarTypeOfPlanner.TryResolveCollection("IReadOnlyDictionary", RodCatalogCanonicals("string", "MissingType"), bindings, out unknown) == false

    // A nested collection VALUE is admissible, exactly as it is for `Dictionary`.
    nested := typeof(object)
    assert ColumnarTypeOfPlanner.TryResolveCollection("IReadOnlyDictionary", RodCatalogCanonicals("string", "List<int>"), bindings, out nested)
    assert nested == RodCatalogClosed(typeof(string), typeof(List<int>))
}

test "the read-only dictionary is a supported collection type in both catalogs at once" {
    closed := RodCatalogClosed(typeof(string), typeof(string))

    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(closed)
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedCollectionType(closed)

    // CONTROL — the concrete dictionary and the open definition answer as they always have.
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(Dictionary<string, string>))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedCollectionType(typeof(Dictionary<string, string>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(RodCatalogDefinition()) == false
}

test "the read-only dictionary is a MODELLED runtime generic head with its own name" {
    assert ColumnarExactTypeResolver.RuntimeGenericValidationHead(RodCatalogDefinition()) == "IReadOnlyDictionary"
    assert ColumnarExactTypeResolver.IsModeledRuntimeGenericHeadName("IReadOnlyDictionary")

    // CONTROL — the head name of every neighbour is unchanged, and an unmodelled head stays empty.
    assert ColumnarExactTypeResolver.RuntimeGenericValidationHead(typeof(Dictionary<int, int>).GetGenericTypeDefinition()) == "Dictionary"
    assert ColumnarExactTypeResolver.RuntimeGenericValidationHead(typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()) == "SortedDictionary"
    assert ColumnarExactTypeResolver.RuntimeGenericValidationHead(typeof(IReadOnlyList<int>).GetGenericTypeDefinition()) == "IReadOnlyList"
    assert ColumnarExactTypeResolver.IsModeledRuntimeGenericHeadName("IDictionary") == false
}

test "a concrete dictionary upcasts to the read-only head and nothing upcasts back" {
    readOnly := RodCatalogClosed(typeof(string), typeof(string))

    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(typeof(Dictionary<string, string>), readOnly)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(typeof(SortedDictionary<string, string>), readOnly)

    // NEGATIVES — the upcast is one-directional and BOTH arguments must match exactly.
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(readOnly, typeof(Dictionary<string, string>)) == false
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(typeof(Dictionary<string, int>), readOnly) == false
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(typeof(Dictionary<int, string>), readOnly) == false
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(typeof(List<string>), readOnly) == false

    // CONTROL — the one-argument upcasts the row sits beside are untouched.
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(typeof(List<string>), typeof(IReadOnlyList<string>))
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(typeof(HashSet<string>), typeof(IReadOnlySet<string>))
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(typeof(List<string>), typeof(IReadOnlyList<int>)) == false
}
