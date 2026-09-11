namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit


// These controls build LIVE source TypeBuilders. They therefore exercise the exact shape seen while
// Compiler Core compiles its own List<ValueTuple<...>> job queues; baked stand-ins cannot prove
// that TypeBuilder.GetConstructor/GetField rebinding retained the closed tuple signature.
func BuilderTupleTypes2(first: Type, second: Type): Type[] {
    result := new Type[](2)
    result[0] = first
    result[1] = second
    return result
}

func BuilderTupleTypes3(first: Type, second: Type, third: Type): Type[] {
    result := new Type[](3)
    result[0] = first
    result[1] = second
    result[2] = third
    return result
}

func BuilderTupleTypes6(first: Type, second: Type): Type[] {
    result := new Type[](6)
    result[0] = first
    result[1] = second
    result[2] = typeof(MethodBuilder)
    result[3] = typeof(Type)
    result[4] = typeof(Dictionary<string, int>)
    result[5] = typeof(Dictionary<string, Type>)
    return result
}

func BuilderTupleTypes8(first: Type, second: Type, rest: Type): Type[] {
    result := new Type[](8)
    result[0] = first
    result[1] = second
    result[2] = typeof(MethodBuilder)
    result[3] = typeof(Type)
    result[4] = typeof(Type)
    result[5] = typeof(Type)
    result[6] = typeof(Dictionary<string, int>)
    result[7] = rest
    return result
}

func BuilderTupleClosed(arity: int, arguments: Type[]): Type {
    definition := ColumnarTypeOfPlanner.OpenValueTupleType(arity)
    if definition == null {
        throw new InvalidOperationException("Required CLR ValueTuple definition was not found.")
    }
    return definition.MakeGenericType(arguments)
}

func BuilderTupleNamesake(arity: int, arguments: Type[]): Type {
    name := "System.ValueTuple`2"
    assemblyName := "BuilderTupleNamesake2"
    if arity == 8 {
        name = "System.ValueTuple`8"
        assemblyName = "BuilderTupleNamesake8"
    }
    definition := TypeOfCreateBuilder(name, assemblyName, arity)
    definitionType: Type = definition
    return definitionType.MakeGenericType(arguments)
}

func BuilderTupleConstructionPlan(tree: ColumnarRangePlannerTestTree, bindings: ColumnarFragmentBindings, failure: string): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := false
    resultType := typeof(int)
    status := ColumnarConstructionPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
    if status != ColumnarFragmentPlanStatus.Planned || ownership != ColumnarDirectCallOwnership.Planned || legacyWholeSubtreePlanning {
        if ownership == ColumnarDirectCallOwnership.NotOwned {
            throw new InvalidOperationException(failure + " Ownership remained NotOwned.")
        }
        if ownership == ColumnarDirectCallOwnership.OwnedRejected {
            throw new InvalidOperationException(failure + " Ownership was OwnedRejected.")
        }
        throw new InvalidOperationException(failure)
    }
    assert plan.ResultType == resultType
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

test "builder-bound ValueTuple admission is exact and retains the established exclusions" {
    first := TypeOfCreateBuilder("BuilderTupleFirst", "BuilderTupleAdmissionFirst", 0)
    second := TypeOfCreateBuilder("BuilderTupleSecond", "BuilderTupleAdmissionSecond", 0)
    pair := BuilderTupleClosed(2, BuilderTupleTypes2(first, typeof(Type[])))
    six := BuilderTupleClosed(6, BuilderTupleTypes6(first, second))
    rest := BuilderTupleClosed(2, BuilderTupleTypes2(typeof(Dictionary<string, Type>), typeof(bool)))
    nineStorage := BuilderTupleClosed(8, BuilderTupleTypes8(first, second, rest))

    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(pair)
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(six)
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(nineStorage)
    assert ColumnarTypeOfPlanner.IsSupportedType(pair)
    assert ColumnarTypeOfPlanner.IsSupportedType(six)
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(pair)
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(six)
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedValueTupleReceiver(pair)
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedValueTupleReceiver(six)
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedValueTupleReceiver(nineStorage)

    // The old baked two-through-seven construction surface is unchanged, including an enum element
    // that TypeOf/receiver admission deliberately excludes at their separate boundaries.
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(typeof(ValueTuple<DayOfWeek, int>))

    sourceValue := SourceCallDefinition("BuilderTupleValue", false).Builder
    sourceInterface := SourceCallInterfaceDefinition("BuilderTupleInterface").Builder
    sourceEnum := AdmissibilityEnumBuilder()
    sourceGeneric := TypeOfCreateBuilder("BuilderTupleGeneric`1", "BuilderTupleGeneric", 1)

    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(BuilderTupleClosed(2, BuilderTupleTypes2(sourceValue, typeof(int))))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(BuilderTupleClosed(2, BuilderTupleTypes2(sourceInterface, typeof(int))))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(BuilderTupleClosed(2, BuilderTupleTypes2(sourceEnum, typeof(int))))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(BuilderTupleClosed(2, BuilderTupleTypes2(sourceGeneric, typeof(int))))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(BuilderTupleClosed(2, BuilderTupleTypes2(first.MakeArrayType(), typeof(int))))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(BuilderTupleNamesake(2, BuilderTupleTypes2(first, typeof(int))))

    wrongRest := BuilderTupleClosed(3, BuilderTupleTypes3(typeof(int), typeof(int), typeof(int)))
    malformedLong := BuilderTupleClosed(8, BuilderTupleTypes8(first, second, wrongRest))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(malformedLong)
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedValueTupleReceiver(malformedLong)
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(BuilderTupleNamesake(8, BuilderTupleTypes8(first, second, rest)))
}

test "construction planner emits exact builder-bound ValueTuple constructor signatures" {
    firstDefinition := SourceCallDefinition("BuilderTupleCtorFirst", true)
    secondDefinition := SourceCallDefinition("BuilderTupleCtorSecond", true)
    first: Type = firstDefinition.Builder
    second: Type = secondDefinition.Builder
    definitions := new ColumnarStructDef[](2)
    definitions[0] = firstDefinition
    definitions[1] = secondDefinition

    pairTexts := new string[](2)
    pairKinds := new int[](2)
    pairTexts[0] = "first"
    pairTexts[1] = "types"
    pairKinds[0] = ColumnarExpressionNodeKind.IdentifierExpression()
    pairKinds[1] = ColumnarExpressionNodeKind.IdentifierExpression()
    pairTree := ConstructionNewTree("ValueTuple<BuilderTupleCtorFirst,Type[]>", pairTexts, pairKinds)
    ConstructionStampScope(pairTree, "import System\nclass BuilderTupleCtorFirst {}\nclass BuilderTupleCtorSecond {}\n")
    pairBindings := ConstructionBindings(definitions)
    ColumnarRangePlannerAddParameter(pairBindings, "first", 0, first)
    ColumnarRangePlannerAddParameter(pairBindings, "types", 1, typeof(Type[]))
    pairPlan := BuilderTupleConstructionPlan(pairTree, pairBindings, "The tuple2 construction planner path declined.")
    pairArguments := BuilderTupleTypes2(first, typeof(Type[]))
    pair := BuilderTupleClosed(2, pairArguments)

    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(pairPlan.ResultType, pair)
    assert pairPlan.ConstructorCount == 1
    assert pairPlan.ConstructorUsesDeclaredSignature[0]
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(pairPlan.ConstructorDeclaringTypes[0], pair)
    pairParameters := pairPlan.ConstructorParameterTypes[0]
    assert pairParameters.Length == 2
    assert pairParameters[0] == first
    assert pairParameters[1] == typeof(Type[])
    assert pairPlan.OpCodeValues[pairPlan.OperationCount - 1] == ColumnarCodePlanContract.Newobj()

    sixTexts := new string[](6)
    sixKinds := new int[](6)
    sixTexts[0] = "first"
    sixTexts[1] = "second"
    sixTexts[2] = "builder"
    sixTexts[3] = "returnType"
    sixTexts[4] = "ordinals"
    sixTexts[5] = "parameterTypes"
    index := 0
    while index < sixKinds.Length {
        sixKinds[index] = ColumnarExpressionNodeKind.IdentifierExpression()
        index += 1
    }
    sixTree := ConstructionNewTree("ValueTuple<BuilderTupleCtorFirst,BuilderTupleCtorSecond,MethodBuilder,Type,Dictionary<string,int>,Dictionary<string,Type>>", sixTexts, sixKinds)
    ConstructionStampScope(sixTree, "import System\nimport System.Collections.Generic\nimport System.Reflection.Emit\nclass BuilderTupleCtorFirst {}\nclass BuilderTupleCtorSecond {}\n")
    sixBindings := ConstructionBindings(definitions)
    ColumnarRangePlannerAddParameter(sixBindings, "first", 0, first)
    ColumnarRangePlannerAddParameter(sixBindings, "second", 1, second)
    ColumnarRangePlannerAddParameter(sixBindings, "builder", 2, typeof(MethodBuilder))
    ColumnarRangePlannerAddParameter(sixBindings, "returnType", 3, typeof(Type))
    ColumnarRangePlannerAddParameter(sixBindings, "ordinals", 4, typeof(Dictionary<string, int>))
    ColumnarRangePlannerAddParameter(sixBindings, "parameterTypes", 5, typeof(Dictionary<string, Type>))
    sixPlan := BuilderTupleConstructionPlan(sixTree, sixBindings, "The tuple6 construction planner path declined.")
    sixArguments := BuilderTupleTypes6(first, second)
    six := BuilderTupleClosed(6, sixArguments)

    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(sixPlan.ResultType, six)
    assert sixPlan.ConstructorCount == 1
    assert sixPlan.ConstructorUsesDeclaredSignature[0]
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(sixPlan.ConstructorDeclaringTypes[0], six)
    sixParameters := sixPlan.ConstructorParameterTypes[0]
    assert sixParameters.Length == 6
    index = 0
    while index < sixArguments.Length {
        assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(sixParameters[index], sixArguments[index])
        index += 1
    }
    assert sixPlan.OpCodeValues[sixPlan.OperationCount - 1] == ColumnarCodePlanContract.Newobj()
}

test "builder-bound ValueTuple Item and Rest fields retain exact substituted result types" {
    first := TypeOfCreateBuilder("BuilderTupleFieldFirst", "BuilderTupleFieldFirst", 0)
    second := TypeOfCreateBuilder("BuilderTupleFieldSecond", "BuilderTupleFieldSecond", 0)
    six := BuilderTupleClosed(6, BuilderTupleTypes6(first, second))
    rest := BuilderTupleClosed(2, BuilderTupleTypes2(typeof(Dictionary<string, Type>), typeof(bool)))
    nineStorage := BuilderTupleClosed(8, BuilderTupleTypes8(first, second, rest))

    firstSelection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert ColumnarRuntimeInstanceMemberResolver.TrySelect(six, "Item1", out firstSelection)
    assert firstSelection.IsField
    assert firstSelection.Field != null
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(firstSelection.ResultType, first)
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(firstSelection.DeclaringType, six)

    sixthSelection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert ColumnarRuntimeInstanceMemberResolver.TrySelect(six, "Item6", out sixthSelection)
    assert sixthSelection.IsField
    assert sixthSelection.Field != null
    assert sixthSelection.ResultType == typeof(Dictionary<string, Type>)

    restSelection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert ColumnarRuntimeInstanceMemberResolver.TrySelect(nineStorage, "Rest", out restSelection)
    assert restSelection.IsField
    assert restSelection.Field != null
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(restSelection.ResultType, rest)

    restFirstSelection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert ColumnarRuntimeInstanceMemberResolver.TrySelect(restSelection.ResultType, "Item1", out restFirstSelection)
    assert restFirstSelection.ResultType == typeof(Dictionary<string, Type>)

    bakedRest := typeof(ValueTuple<string, bool>)
    bakedLong := BuilderTupleClosed(8, BuilderTupleTypes8(typeof(string), typeof(Version), bakedRest))
    bakedSelection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert ColumnarRuntimeInstanceMemberResolver.TrySelect(bakedLong, "Rest", out bakedSelection)
    assert bakedSelection.ResultType == bakedRest

    missingSelection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(six, "Rest", out missingSelection)
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(six, "Item7", out missingSelection)
}
