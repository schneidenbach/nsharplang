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

// THE OPEN-CONSTRUCTOR FINDERS LIVE WITH THE TESTS THAT WANT THEM. They used to be production members
// of the construction planner, backing a hand list of six BCL collection names. The planner selects
// every closed generic constructor by ordinary overload resolution now, so the finders are scaffolding
// for the rows below -- which assert what the BCL's signatures ARE, so the selections beside them are
// read against a known shape rather than against themselves.
func ClosureCollectionOpenComparerConstructor(definition: Type, comparerDefinitionName: string): ConstructorInfo? {
    constructors := definition.GetConstructors()
    index := 0
    while index < constructors.Length {
        parameters := constructors[index].GetParameters()
        if parameters.Length == 1 {
            parameterType := parameters[0].get_ParameterType()
            if parameterType.get_IsGenericType() && !parameterType.get_IsGenericTypeDefinition() {
                parameterDefinition := parameterType.GetGenericTypeDefinition()
                if parameterDefinition.FullName == comparerDefinitionName {
                    return constructors[index]
                }
            }
        }
        index += 1
    }
    return null
}

func ClosureCollectionOpenCopyComparerConstructor(definition: Type, comparerDefinitionName: string): ConstructorInfo? {
    constructors := definition.GetConstructors()
    index := 0
    while index < constructors.Length {
        parameters := constructors[index].GetParameters()
        if parameters.Length == 2 {
            firstType := parameters[0].get_ParameterType()
            secondType := parameters[1].get_ParameterType()
            if firstType.get_IsGenericType() && !firstType.get_IsGenericTypeDefinition() && secondType.get_IsGenericType() && !secondType.get_IsGenericTypeDefinition() {
                firstDefinition := firstType.GetGenericTypeDefinition()
                secondDefinition := secondType.GetGenericTypeDefinition()
                if firstDefinition.FullName == "System.Collections.Generic.IEnumerable`1" && secondDefinition.FullName == comparerDefinitionName {
                    return constructors[index]
                }
            }
        }
        index += 1
    }
    return null
}

func ClosureCollectionOpenSequenceConstructor(definition: Type): ConstructorInfo? {
    definitionArguments := definition.GetGenericArguments()
    if definitionArguments.Length != 1 {
        return null
    }

    // A namesake built with Reflection.Emit answers nothing before it is created, and asking is a
    // NotSupportedException rather than an empty list.
    constructors := new ConstructorInfo[](0)
    try {
        constructors = definition.GetConstructors()
    } catch ex: NotSupportedException {
        return null
    }
    selected: ConstructorInfo? = null
    index := 0
    while index < constructors.Length {
        parameters := constructors[index].GetParameters()
        if parameters.Length == 1 {
            parameterType := parameters[0].get_ParameterType()
            if parameterType.get_IsGenericType() && !parameterType.get_IsGenericTypeDefinition() && parameterType.GetGenericTypeDefinition() == typeof(IEnumerable<int>).GetGenericTypeDefinition() {
                parameterArguments := parameterType.GetGenericArguments()
                if parameterArguments.Length == 1 && parameterArguments[0] == definitionArguments[0] {
                    if selected != null {
                        throw new InvalidOperationException("The definition has more than one exact IEnumerable<T> constructor.")
                    }
                    selected = constructors[index]
                }
            }
        }
        index += 1
    }
    return selected
}

// The closed type's SELECTED constructor rendered as its parameter list, or "<none>". This is the
// product path: exactly what a `new` expression resolves.
func ClosureCollectionTypes1(first: Type): Type[] {
    result := new Type[](1)
    result[0] = first
    return result
}

func ClosureCollectionTypes2(first: Type, second: Type): Type[] {
    result := new Type[](2)
    result[0] = first
    result[1] = second
    return result
}

func ClosureCollectionSelects(targetType: Type, argumentTypes: Type[]): string {
    constructor: ConstructorInfo? = null
    parameters := new Type[](0)
    if !ColumnarConstructionPlanner.TrySelectClosedRuntimeConstructor(targetType, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length), out constructor, out parameters) || constructor == null {
        return "<none>"
    }

    rendered := ""
    index := 0
    while index < parameters.Length {
        if index > 0 {
            rendered = rendered + "|"
        }
        parameterType := parameters[index]
        rendered = rendered + (parameterType.FullName ?? "<null>")
        index += 1
    }

    return rendered
}

test "collection constructors retain their exact enumerable and comparer signatures" {
    hashSetDefinition := typeof(HashSet<int>).GetGenericTypeDefinition()
    sortedSetDefinition := typeof(SortedSet<int>).GetGenericTypeDefinition()
    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()

    hashComparer := ClosureCollectionRequiredConstructor(
        ClosureCollectionOpenComparerConstructor(
            hashSetDefinition,
            "System.Collections.Generic.IEqualityComparer`1"
        )
    )
    hashCopyComparer := ClosureCollectionRequiredConstructor(
        ClosureCollectionOpenCopyComparerConstructor(
            hashSetDefinition,
            "System.Collections.Generic.IEqualityComparer`1"
        )
    )
    sortedComparer := ClosureCollectionRequiredConstructor(
        ClosureCollectionOpenComparerConstructor(
            sortedSetDefinition,
            "System.Collections.Generic.IComparer`1"
        )
    )
    sortedCopyComparer := ClosureCollectionRequiredConstructor(
        ClosureCollectionOpenCopyComparerConstructor(
            sortedSetDefinition,
            "System.Collections.Generic.IComparer`1"
        )
    )
    dictionaryCopyComparer := ClosureCollectionRequiredConstructor(
        ClosureCollectionOpenCopyComparerConstructor(
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

    assert ClosureCollectionOpenComparerConstructor(sortedSetDefinition, "System.Collections.Generic.IEqualityComparer`1") == null
    assert ClosureCollectionOpenCopyComparerConstructor(hashSetDefinition, "System.Collections.Generic.IComparer`1") == null
    assert ClosureCollectionOpenCopyComparerConstructor(dictionaryDefinition, "System.Collections.Generic.IComparer`1") == null

    // And the planner reaches exactly those signatures WITHOUT naming a single collection: each
    // selection below is ordinary overload resolution over the closed type's own constructors.
    assert ClosureCollectionSelects(typeof(HashSet<string>), ClosureCollectionTypes1(typeof(IEqualityComparer<string>))) == "System.Collections.Generic.IEqualityComparer`1[[System.String, System.Private.CoreLib, Version=10.0.0.0, Culture=neutral, PublicKeyToken=7cec85d7bea7798e]]"
    assert ClosureCollectionSelects(typeof(SortedSet<string>), ClosureCollectionTypes1(typeof(IComparer<string>))) == "System.Collections.Generic.IComparer`1[[System.String, System.Private.CoreLib, Version=10.0.0.0, Culture=neutral, PublicKeyToken=7cec85d7bea7798e]]"
    assert ClosureCollectionSelects(typeof(List<string>), ClosureCollectionTypes1(typeof(IEnumerable<string>))) != "<none>"
    assert ClosureCollectionSelects(typeof(Dictionary<string, int>), ClosureCollectionTypes2(typeof(IEnumerable<KeyValuePair<string, int>>), typeof(IEqualityComparer<string>))) != "<none>"
    assert ClosureCollectionSelects(typeof(HashSet<string>), ClosureCollectionTypes1(typeof(IComparer<string>))) == "<none>"
}

test "List key snapshots select the exact enumerable copy constructor" {
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    enumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    constructor := ClosureCollectionRequiredConstructor(
        ClosureCollectionOpenSequenceConstructor(listDefinition)
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

    // A namesake with no constructors of its own selects nothing, and neither does a CLOSED list asked
    // for a sequence of the wrong element.
    foreignList := TypeOfCreateBuilder(
        "System.Collections.Generic.List",
        "ClosureCollection.ForeignList",
        1
    )
    assert ClosureCollectionOpenSequenceConstructor(foreignList) == null
    assert ClosureCollectionSelects(typeof(List<string>), ClosureCollectionTypes1(typeof(IEnumerable<int>))) == "<none>"
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
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(
        typeof(SortedDictionary<string, int>),
        "Keys",
        out selection
    )
}
