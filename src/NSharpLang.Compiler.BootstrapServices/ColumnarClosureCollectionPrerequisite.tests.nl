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
