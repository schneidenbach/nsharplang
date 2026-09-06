namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func ClosureCollectionClosedType(
    definition: Type,
    argument: Type
): Type {
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

func ClosureCollectionClosedType2(
    definition: Type,
    first: Type,
    second: Type
): Type {
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return definition.MakeGenericType(arguments)
}

func ClosureCollectionRequiredConstructor(value: ConstructorInfo?): ConstructorInfo {
    if value == null {
        throw new InvalidOperationException("The required collection constructor was not found.")
    }
    return value
}

func ClosureCollectionSortedWords(values: SortedSet<string>): string {
    enumerator := values.GetEnumerator()
    result := ""
    try {
        while enumerator.MoveNext() {
            if result.Length > 0 {
                result = result + "|"
            }
            result = result + enumerator.get_Current()
        }
    } finally {
        enumerator.Dispose()
    }
    return result
}

func ClosureCollectionAdvanceAfterMutation(values: SortedSet<string>): bool {
    enumerator := values.GetEnumerator()
    advanced := false
    try {
        if !enumerator.MoveNext() {
            throw new InvalidOperationException("The mutation control requires an initial value.")
        }
        if !values.Add("late") {
            throw new InvalidOperationException("The mutation control requires a new value.")
        }
        advanced = enumerator.MoveNext()
    } finally {
        enumerator.Dispose()
    }
    return advanced
}

func ClosureCollectionExerciseProductionKeyViews(): bool {
    localBuilders := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    ordinals := new Dictionary<string, int>(StringComparer.Ordinal)
    lifted := new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal)
    boxed := new Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>(StringComparer.Ordinal)

    localCopy := new HashSet<string>(localBuilders.Keys, StringComparer.Ordinal)
    ordinalCopy := new HashSet<string>(ordinals.Keys, StringComparer.Ordinal)
    liftedCopy := new HashSet<string>(lifted.Keys, StringComparer.Ordinal)
    boxedCopy := new HashSet<string>(boxed.Keys, StringComparer.Ordinal)

    names := new HashSet<string>(StringComparer.Ordinal)
    names.UnionWith(localBuilders.Keys)
    names.UnionWith(ordinals.Keys)
    names.UnionWith(lifted.Keys)
    names.UnionWith(boxed.Keys)

    return localCopy.get_Count() == 0 && ordinalCopy.get_Count() == 0 && liftedCopy.get_Count() == 0 && boxedCopy.get_Count() == 0 && names.get_Count() == 0
}

test "collection constructors retain their exact enumerable and comparer signatures" {
    hashSetDefinition := typeof(HashSet<int>).GetGenericTypeDefinition()
    sortedSetDefinition := typeof(SortedSet<int>).GetGenericTypeDefinition()

    hashComparer := ClosureCollectionRequiredConstructor(
        ColumnarConstructionPlanner.FindOpenComparerConstructor(
            hashSetDefinition,
            "System.Collections.Generic.IEqualityComparer`1"
        )
    )
    hashCopyComparer := ClosureCollectionRequiredConstructor(
        ColumnarConstructionPlanner.FindOpenCopyComparerConstructor(
            hashSetDefinition,
            "System.Collections.Generic.IEqualityComparer`1"
        )
    )
    sortedComparer := ClosureCollectionRequiredConstructor(
        ColumnarConstructionPlanner.FindOpenComparerConstructor(
            sortedSetDefinition,
            "System.Collections.Generic.IComparer`1"
        )
    )
    sortedCopyComparer := ClosureCollectionRequiredConstructor(
        ColumnarConstructionPlanner.FindOpenCopyComparerConstructor(
            sortedSetDefinition,
            "System.Collections.Generic.IComparer`1"
        )
    )

    assert hashComparer.GetParameters().Length == 1
    assert hashCopyComparer.GetParameters().Length == 2
    assert sortedComparer.GetParameters().Length == 1
    assert sortedCopyComparer.GetParameters().Length == 2
    assert hashComparer.GetParameters()[0].get_ParameterType().GetGenericTypeDefinition() == typeof(IEqualityComparer<int>).GetGenericTypeDefinition()
    assert hashCopyComparer.GetParameters()[0].get_ParameterType().GetGenericTypeDefinition() == typeof(IEnumerable<int>).GetGenericTypeDefinition()
    assert hashCopyComparer.GetParameters()[1].get_ParameterType().GetGenericTypeDefinition() == typeof(IEqualityComparer<int>).GetGenericTypeDefinition()
    assert sortedComparer.GetParameters()[0].get_ParameterType().GetGenericTypeDefinition() == typeof(IComparer<int>).GetGenericTypeDefinition()
    assert sortedCopyComparer.GetParameters()[0].get_ParameterType().GetGenericTypeDefinition() == typeof(IEnumerable<int>).GetGenericTypeDefinition()
    assert sortedCopyComparer.GetParameters()[1].get_ParameterType().GetGenericTypeDefinition() == typeof(IComparer<int>).GetGenericTypeDefinition()

    assert ColumnarConstructionPlanner.IsComparerCollectionDefinition(hashSetDefinition)
    assert ColumnarConstructionPlanner.IsComparerCollectionDefinition(sortedSetDefinition)
    assert ColumnarConstructionPlanner.IsCopyComparerCollectionDefinition(hashSetDefinition)
    assert ColumnarConstructionPlanner.IsCopyComparerCollectionDefinition(sortedSetDefinition)
    assert !ColumnarConstructionPlanner.IsCopyComparerCollectionDefinition(typeof(Dictionary<int, int>).GetGenericTypeDefinition())
    assert !ColumnarConstructionPlanner.IsComparerCollectionDefinition(typeof(List<int>).GetGenericTypeDefinition())
    assert ColumnarConstructionPlanner.FindOpenComparerConstructor(sortedSetDefinition, "System.Collections.Generic.IEqualityComparer`1") == null
    assert ColumnarConstructionPlanner.FindOpenCopyComparerConstructor(hashSetDefinition, "System.Collections.Generic.IComparer`1") == null
}

test "exact Dictionary Keys result types cover every closure value shape and no namesake" {
    valueTypes := new Type[](4)
    valueTypes[0] = typeof(LocalBuilder)
    valueTypes[1] = typeof(int)
    valueTypes[2] = typeof(ValueTuple<LocalBuilder, Type>)
    valueTypes[3] = typeof(ValueTuple<FieldInfo, Type>)

    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    keyCollectionDefinition := ColumnarTypeOfPlanner.RequiredDictionaryKeyCollectionDefinition()
    index := 0
    while index < valueTypes.Length {
        dictionary := ClosureCollectionClosedType2(
            dictionaryDefinition,
            typeof(string),
            valueTypes[index]
        )
        expectedKeys := ClosureCollectionClosedType2(
            keyCollectionDefinition,
            typeof(string),
            valueTypes[index]
        )
        selection := ColumnarRuntimeInstanceMemberSelection.Empty()
        assert ColumnarRuntimeInstanceMemberResolver.TrySelect(
            dictionary,
            "Keys",
            out selection
        )
        assert ColumnarTypeEquivalenceFacts.TypesEquivalent(selection.ResultType, expectedKeys)
        assert ColumnarTypeOfPlanner.IsSupportedDictionaryKeyCollectionType(selection.ResultType)
        assert ColumnarTypeOfPlanner.IsSupportedType(selection.ResultType)
        index += 1
    }

    exactKeys := ClosureCollectionClosedType2(
        keyCollectionDefinition,
        typeof(string),
        typeof(int)
    )
    enumerableString := ClosureCollectionClosedType(
        typeof(IEnumerable<int>).GetGenericTypeDefinition(),
        typeof(string)
    )
    enumerableInt := ClosureCollectionClosedType(
        typeof(IEnumerable<int>).GetGenericTypeDefinition(),
        typeof(int)
    )
    sortedStrings := ClosureCollectionClosedType(
        typeof(SortedSet<int>).GetGenericTypeDefinition(),
        typeof(string)
    )
    foreignKeys := DictionaryNestedControlForeignSameName(
        "KeyCollection",
        typeof(string),
        typeof(int)
    )
    selection := ColumnarRuntimeInstanceMemberSelection.Empty()

    assert ColumnarReferenceConversionFacts.TryEmitReferenceConversion(exactKeys, enumerableString)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(exactKeys, enumerableString)
    assert !ColumnarReferenceConversionFacts.TryEmitReferenceConversion(exactKeys, enumerableInt)
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(exactKeys, enumerableInt)
    assert ColumnarReferenceConversionFacts.TryEmitReferenceConversion(sortedStrings, enumerableString)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(sortedStrings, enumerableString)
    assert !ColumnarReferenceConversionFacts.TryEmitReferenceConversion(sortedStrings, enumerableInt)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryKeyCollectionType(keyCollectionDefinition)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryKeyCollectionType(foreignKeys)
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(
        typeof(SortedDictionary<string, int>),
        "Keys",
        out selection
    )
}

test "every production Dictionary Keys shape flows unchanged into HashSet operations" {
    assert ClosureCollectionExerciseProductionKeyViews()

    values := new Dictionary<string, int>(StringComparer.Ordinal)
    liveKeys := values.Keys
    values["first"] = 1
    copied := new HashSet<string>(liveKeys, StringComparer.Ordinal)
    assert copied.get_Count() == 1
    assert copied.Contains("first")

    values["second"] = 2
    copied.UnionWith(liveKeys)
    assert copied.get_Count() == 2
    assert copied.Contains("second")
}

test "HashSet copy construction uses the supplied comparer before duplicate insertion" {
    source := new HashSet<string>(StringComparer.Ordinal)
    assert source.Add("A")
    assert source.Add("a")

    ordinal := new HashSet<string>(source, StringComparer.Ordinal)
    ignoreCase := new HashSet<string>(source, StringComparer.OrdinalIgnoreCase)
    assert ordinal.get_Count() == 2
    assert ignoreCase.get_Count() == 1
    assert !ignoreCase.Add("a")
}

test "SortedSet constructors retain comparer ordering duplicates mutation and disposal" {
    source := new HashSet<string>(StringComparer.Ordinal)
    assert source.Add("b")
    assert source.Add("A")
    assert source.Add("a")

    copied := new SortedSet<string>(source, StringComparer.Ordinal)
    assert copied.get_Count() == 3
    assert !copied.Add("a")
    assert ClosureCollectionSortedWords(copied) == "A|a|b"

    direct := new SortedSet<string>(StringComparer.OrdinalIgnoreCase)
    assert direct.Add("b")
    assert direct.Add("A")
    assert !direct.Add("a")
    assert ClosureCollectionSortedWords(direct) == "A|b"

    assert throws InvalidOperationException {
        ClosureCollectionAdvanceAfterMutation(copied)
    }
    assert copied.Contains("late")
}
