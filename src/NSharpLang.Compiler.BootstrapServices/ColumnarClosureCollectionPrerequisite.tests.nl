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

func ClosureCollectionListCopyTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    listType := builder.AddLeaf(0, "List<string>")
    source := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "source"
    )
    keys := DirectCallAppendMember(builder, source, "Keys")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(listType, keys)
    )
    return builder.Build(root)
}

func ClosureCollectionListCopyPlan(sourceType: Type): ColumnarCodePlan {
    tree := ClosureCollectionListCopyTree()
    ConstructionStampScope(tree, "")
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "source", 0, sourceType)
    return ConstructionPlan(tree, bindings)
}

test "collection constructors retain their exact enumerable and comparer signatures" {
    hashSetDefinition := typeof(HashSet<int>).GetGenericTypeDefinition()
    sortedSetDefinition := typeof(SortedSet<int>).GetGenericTypeDefinition()
    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()

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
    dictionaryCopyComparer := ClosureCollectionRequiredConstructor(
        ColumnarConstructionPlanner.FindOpenCopyComparerConstructor(
            dictionaryDefinition,
            "System.Collections.Generic.IEqualityComparer`1"
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
    dictionaryParameters := dictionaryDefinition.GetGenericArguments()
    dictionaryCopyParameters := dictionaryCopyComparer.GetParameters()
    dictionarySequenceType := dictionaryCopyParameters[0].get_ParameterType()
    dictionaryPairType := dictionarySequenceType.GetGenericArguments()[0]
    dictionaryComparerType := dictionaryCopyParameters[1].get_ParameterType()
    assert dictionaryCopyParameters.Length == 2
    assert dictionarySequenceType.GetGenericTypeDefinition() == typeof(IEnumerable<int>).GetGenericTypeDefinition()
    assert dictionaryPairType.GetGenericTypeDefinition() == typeof(KeyValuePair<int, int>).GetGenericTypeDefinition()
    assert dictionaryPairType.GetGenericArguments()[0] == dictionaryParameters[0]
    assert dictionaryPairType.GetGenericArguments()[1] == dictionaryParameters[1]
    assert dictionaryComparerType.GetGenericTypeDefinition() == typeof(IEqualityComparer<int>).GetGenericTypeDefinition()
    assert dictionaryComparerType.GetGenericArguments()[0] == dictionaryParameters[0]

    assert ColumnarConstructionPlanner.IsComparerCollectionDefinition(hashSetDefinition)
    assert ColumnarConstructionPlanner.IsComparerCollectionDefinition(sortedSetDefinition)
    assert ColumnarConstructionPlanner.IsCopyComparerCollectionDefinition(hashSetDefinition)
    assert ColumnarConstructionPlanner.IsCopyComparerCollectionDefinition(sortedSetDefinition)
    assert ColumnarConstructionPlanner.IsCopyComparerCollectionDefinition(dictionaryDefinition)
    assert !ColumnarConstructionPlanner.IsComparerCollectionDefinition(typeof(List<int>).GetGenericTypeDefinition())
    assert !ColumnarConstructionPlanner.IsCopyComparerCollectionDefinition(typeof(List<int>).GetGenericTypeDefinition())
    assert ColumnarConstructionPlanner.FindOpenComparerConstructor(sortedSetDefinition, "System.Collections.Generic.IEqualityComparer`1") == null
    assert ColumnarConstructionPlanner.FindOpenCopyComparerConstructor(hashSetDefinition, "System.Collections.Generic.IComparer`1") == null
    assert ColumnarConstructionPlanner.FindOpenCopyComparerConstructor(dictionaryDefinition, "System.Collections.Generic.IComparer`1") == null
}

test "List key snapshots select the exact enumerable copy constructor" {
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    enumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    constructor := ClosureCollectionRequiredConstructor(
        ColumnarConstructionPlanner.FindOpenListCopyConstructor(listDefinition)
    )
    parameters := constructor.GetParameters()
    assert parameters.Length == 1
    parameterType := parameters[0].get_ParameterType()
    assert parameterType.GetGenericTypeDefinition() == enumerableDefinition
    listArguments := listDefinition.GetGenericArguments()
    parameterArguments := parameterType.GetGenericArguments()
    assert listArguments.Length == 1
    assert parameterArguments.Length == 1
    assert parameterArguments[0] == listArguments[0]

    assert ColumnarConstructionPlanner.IsListCopyCollectionDefinition(listDefinition)
    assert !ColumnarConstructionPlanner.IsListCopyCollectionDefinition(typeof(HashSet<int>).GetGenericTypeDefinition())
    assert ColumnarConstructionPlanner.FindOpenListCopyConstructor(typeof(List<string>)) == null
    foreignList := TypeOfCreateBuilder(
        "System.Collections.Generic.List",
        "ClosureCollection.ForeignList",
        1
    )
    assert !ColumnarConstructionPlanner.IsListCopyCollectionDefinition(foreignList)
    assert ColumnarConstructionPlanner.FindOpenListCopyConstructor(foreignList) == null
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
        assert ColumnarConstructionPlanner.IsListKeyCollectionCopy(
            typeof(List<int>).GetGenericTypeDefinition(),
            typeof(List<string>),
            selection.ResultType
        )

        plan := ClosureCollectionListCopyPlan(dictionary)
        assert plan.ResultType == typeof(List<string>)
        assert plan.MethodCount == 1
        assert plan.Methods[0].get_Name() == "get_Keys"
        assert ColumnarTypeEquivalenceFacts.TypesEquivalent(
            plan.MethodDeclaringTypes[0],
            dictionary
        )
        assert ColumnarTypeEquivalenceFacts.TypesEquivalent(
            plan.MethodReturnTypes[0],
            expectedKeys
        )
        assert plan.ConstructorCount == 1
        assert plan.ConstructorDeclaringTypes[0] == typeof(List<string>)
        assert plan.ConstructorParameterTypes[0].Length == 1
        expectedEnumerable := ClosureCollectionClosedType(
            typeof(IEnumerable<int>).GetGenericTypeDefinition(),
            typeof(string)
        )
        assert plan.ConstructorParameterTypes[0][0] == expectedEnumerable
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
    foreignList := TypeOfCreateBuilder(
        "System.Collections.Generic.List",
        "ClosureCollection.ForeignListForMatch",
        1
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
    assert !ColumnarConstructionPlanner.IsListKeyCollectionCopy(
        typeof(List<int>).GetGenericTypeDefinition(),
        typeof(List<int>),
        exactKeys
    )
    assert !ColumnarConstructionPlanner.IsListKeyCollectionCopy(
        typeof(List<int>).GetGenericTypeDefinition(),
        typeof(List<string>),
        enumerableString
    )
    assert !ColumnarConstructionPlanner.IsListKeyCollectionCopy(
        foreignList,
        typeof(List<string>),
        exactKeys
    )
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(
        typeof(SortedDictionary<string, int>),
        "Keys",
        out selection
    )
}
