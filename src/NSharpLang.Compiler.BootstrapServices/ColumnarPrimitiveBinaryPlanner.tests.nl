namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


func PrimitiveBinaryPlan(
    source: string,
    bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    tree := DirectCallParsedTree(source)
    plan := new ColumnarCodePlan()
    assert ColumnarPrimitiveBinaryPlanner.Plan(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        plan) == ColumnarFragmentPlanStatus.Planned
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func PrimitiveBinaryDeclines(
    source: string,
    bindings: ColumnarFragmentBindings) {
    tree := DirectCallParsedTree(source)
    plan := new ColumnarCodePlan()
    assert ColumnarPrimitiveBinaryPlanner.Plan(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        plan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

func PrimitiveBinaryOpcodeCount(
    plan: ColumnarCodePlan,
    opCodeValue: short): int {
    count := 0
    index := 0
    while index < plan.OperationCount {
        if plan.OpCodeValues[index] == opCodeValue {
            count += 1
        }
        index += 1
    }
    return count
}

func PrimitiveBinaryParameterBindings(valueType: Type): ColumnarFragmentBindings {
    return PrimitiveBinaryPairBindings(valueType, valueType)
}

func PrimitiveBinaryPairBindings(
    leftType: Type,
    rightType: Type): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "left", 0, leftType)
    ColumnarRangePlannerAddParameter(bindings, "right", 1, rightType)
    return bindings
}

func PrimitiveBinaryExecuteParameters(
    plan: ColumnarCodePlan,
    resultType: Type,
    leftType: Type,
    rightType: Type,
    leftValue: object,
    rightValue: object): string {
    parameterTypes := new Type[](2)
    parameterTypes[0] = leftType
    parameterTypes[1] = rightType
    arguments := new object[](2)
    ExecutorSetObject(arguments, 0, leftValue)
    ExecutorSetObject(arguments, 1, rightValue)
    return ExecutorRunRecursivePlan(
        plan, resultType, parameterTypes, arguments)
}

test "primitive binary planner owns and executes every retained primitive addition family" {
    intPlan := PrimitiveBinaryPlan(
        "20 + 22", ColumnarRangePlannerEmptyBindings())
    assert intPlan.ResultType == typeof(int)
    assert intPlan.FragmentCount == 3
    assert PrimitiveBinaryOpcodeCount(
        intPlan, ColumnarCodePlanContract.Add()) == 1
    assert ExecutorRunV3ScalarPlan(intPlan, typeof(int)) == "42"

    longPlan := PrimitiveBinaryPlan(
        "20L + 22L", ColumnarRangePlannerEmptyBindings())
    assert longPlan.ResultType == typeof(long)
    assert PrimitiveBinaryOpcodeCount(
        longPlan, ColumnarCodePlanContract.Add()) == 1
    assert ExecutorRunV3ScalarPlan(longPlan, typeof(long)) == "42"

    stringPlan := PrimitiveBinaryPlan(
        "\"left\" + \"right\"", ColumnarRangePlannerEmptyBindings())
    assert stringPlan.ResultType == typeof(string)
    assert PrimitiveBinaryOpcodeCount(
        stringPlan, ColumnarCodePlanContract.Add()) == 0
    assert stringPlan.MethodCount == 1
    concat := stringPlan.Methods[0]
    assert concat.get_DeclaringType() == typeof(string)
    assert concat.get_Name() == "Concat"
    assert concat.get_IsStatic()
    assert concat.get_ReturnType() == typeof(string)
    concatParameters := concat.GetParameters()
    assert concatParameters.Length == 2
    assert concatParameters[0].get_ParameterType() == typeof(string)
    assert concatParameters[1].get_ParameterType() == typeof(string)
    assert ExecutorRunV3ScalarPlan(stringPlan, typeof(string)) == "leftright"

    uintPlan := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryParameterBindings(typeof(uint)))
    assert uintPlan.ResultType == typeof(uint)
    assert PrimitiveBinaryOpcodeCount(
        uintPlan, ColumnarCodePlanContract.Add()) == 1
    assert PrimitiveBinaryExecuteParameters(
        uintPlan, typeof(uint), typeof(uint), typeof(uint),
        (uint)20, (uint)22) == "42"

    ulongPlan := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryParameterBindings(typeof(ulong)))
    assert ulongPlan.ResultType == typeof(ulong)
    assert PrimitiveBinaryExecuteParameters(
        ulongPlan, typeof(ulong), typeof(ulong), typeof(ulong),
        (ulong)20, (ulong)22) == "42"

    floatPlan := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryParameterBindings(typeof(float)))
    assert floatPlan.ResultType == typeof(float)
    assert PrimitiveBinaryExecuteParameters(
        floatPlan, typeof(float), typeof(float), typeof(float),
        1.25f, 2.75f) == (1.25f + 2.75f).ToString()

    doublePlan := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryParameterBindings(typeof(double)))
    assert doublePlan.ResultType == typeof(double)
    assert PrimitiveBinaryExecuteParameters(
        doublePlan, typeof(double), typeof(double), typeof(double),
        19.5, 22.5) == (19.5 + 22.5).ToString()

    decimalPlan := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert decimalPlan.ResultType == typeof(decimal)
    assert PrimitiveBinaryOpcodeCount(
        decimalPlan, ColumnarCodePlanContract.Add()) == 0
    assert PrimitiveBinaryOpcodeCount(
        decimalPlan, ColumnarCodePlanContract.Call()) == 1
    assert decimalPlan.MethodCount == 1
    assert decimalPlan.MethodUsesDeclaredSignature[0]
    decimalMethod := decimalPlan.Methods[0]
    assert decimalMethod.get_DeclaringType() == typeof(decimal)
    assert decimalMethod.get_Name() == "op_Addition"
    assert decimalPlan.MethodDeclaringTypes[0] == typeof(decimal)
    assert decimalPlan.MethodParameterTypes[0].Length == 2
    assert decimalPlan.MethodParameterTypes[0][0] == typeof(decimal)
    assert decimalPlan.MethodParameterTypes[0][1] == typeof(decimal)
    assert decimalPlan.MethodReturnTypes[0] == typeof(decimal)
    assert PrimitiveBinaryExecuteParameters(
        decimalPlan, typeof(decimal), typeof(decimal), typeof(decimal),
        1.5m, 2.5m) == (1.5m + 2.5m).ToString()

    promotedPlan := PrimitiveBinaryPlan(
        "left + right",
        PrimitiveBinaryPairBindings(typeof(byte), typeof(short)))
    assert promotedPlan.ResultType == typeof(int)
    assert PrimitiveBinaryExecuteParameters(
        promotedPlan, typeof(int), typeof(byte), typeof(short),
        (byte)20, (short)22) == "42"
}

test "primitive binary planner recursively owns a left associative addition chain" {
    plan := PrimitiveBinaryPlan(
        "1 + 2 + 39", ColumnarRangePlannerEmptyBindings())
    assert plan.ResultType == typeof(int)
    assert plan.FragmentCount == 5
    assert PrimitiveBinaryOpcodeCount(
        plan, ColumnarCodePlanContract.Add()) == 2
    assert ExecutorRunV3ScalarPlan(plan, typeof(int)) == "42"
}

test "primitive binary planner emits one exact source addition Method Call row" {
    owner := SourceCallDefinition("PrimitiveBinarySourceAddition", true)
    operandType: Type = owner.Builder
    definition := SourceOperatorDefine(
        owner,
        "op_Addition",
        SourceOperatorTwoTypes(operandType, operandType),
        operandType)
    bindings := PrimitiveBinaryParameterBindings(operandType)
    bindings.SourceTypeDefinitions = SourceOperatorDefinitions(owner, null)

    plan := PrimitiveBinaryPlan("left + right", bindings)
    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType, operandType)
    assert PrimitiveBinaryOpcodeCount(
        plan, ColumnarCodePlanContract.Add()) == 0
    assert PrimitiveBinaryOpcodeCount(
        plan, ColumnarCodePlanContract.Call()) == 1
    assert plan.MethodCount == 1
    assert plan.MethodUsesDeclaredSignature[0]
    assert ColumnarConstructionPlanner.SameObject(
        plan.Methods[0], definition.Builder)
    assert ColumnarConstructionPlanner.SameObject(
        plan.MethodDeclaringTypes[0], operandType)
    assert plan.MethodParameterTypes[0].Length == 2
    assert ColumnarConstructionPlanner.SameObject(
        plan.MethodParameterTypes[0][0], operandType)
    assert ColumnarConstructionPlanner.SameObject(
        plan.MethodParameterTypes[0][1], operandType)
    assert ColumnarConstructionPlanner.SameObject(
        plan.MethodReturnTypes[0], operandType)
    assert plan.MethodIsStatic[0]
    assert !plan.MethodIsAbstract[0]
}

test "primitive binary source addition rejects unsupported and corrupt facts atomically" {
    unsupportedOwner := SourceCallDefinition(
        "PrimitiveBinaryUnsupportedSourceAddition", true)
    unsupportedType: Type = unsupportedOwner.Builder
    unsupportedBindings := PrimitiveBinaryParameterBindings(unsupportedType)
    unsupportedBindings.SourceTypeDefinitions =
        SourceOperatorDefinitions(unsupportedOwner, null)
    PrimitiveBinaryDeclines("left + right", unsupportedBindings)

    mappedOwner := SourceCallDefinition(
        "PrimitiveBinaryCorruptSourceAddition", true)
    foreignOwner := SourceCallDefinition(
        "PrimitiveBinaryForeignSourceAddition", true)
    mappedType: Type = mappedOwner.Builder
    foreignDefinition := SourceOperatorDefine(
        foreignOwner,
        "op_Addition",
        SourceOperatorTwoTypes(mappedType, mappedType),
        mappedType)
    SourceCallAddStaticFact(
        mappedOwner, "op_Addition", foreignDefinition)
    corruptBindings := PrimitiveBinaryParameterBindings(mappedType)
    corruptBindings.SourceTypeDefinitions =
        SourceOperatorDefinitions(mappedOwner, null)
    corruptTree := DirectCallParsedTree("left + right")
    corruptPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarPrimitiveBinaryPlanner.Plan(
            corruptTree.Nodes,
            corruptTree.Source,
            corruptTree.Root,
            corruptBindings,
            ColumnarRangeIndexHandles.Resolve(),
            corruptPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(corruptPlan)
}

test "primitive binary planner declines other operators types and malformed arity atomically" {
    PrimitiveBinaryDeclines(
        "20 - 22", ColumnarRangePlannerEmptyBindings())
    PrimitiveBinaryDeclines(
        "20 + 22L", ColumnarRangePlannerEmptyBindings())
    PrimitiveBinaryDeclines(
        "left + right", PrimitiveBinaryParameterBindings(typeof(bool)))
    PrimitiveBinaryDeclines(
        "left + right",
        PrimitiveBinaryPairBindings(typeof(uint), typeof(ulong)))
    PrimitiveBinaryDeclines(
        "\"left\" + 1", ColumnarRangePlannerEmptyBindings())

    partialBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(partialBindings, "left", 0, typeof(int))
    PrimitiveBinaryDeclines("left + missing", partialBindings)

    malformedBuilder := new ColumnarRangePlannerNodeBuilder()
    plusStart := malformedBuilder.AddToken("+")
    one := malformedBuilder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    malformedRoot := malformedBuilder.AddNode(
        ColumnarExpressionNodeKind.BinaryExpression(),
        plusStart,
        1,
        0,
        malformedBuilder.Source.Length,
        ColumnarRangePlannerChildren1(one))
    malformed := malformedBuilder.Build(malformedRoot)
    malformedPlan := new ColumnarCodePlan()
    assert ColumnarPrimitiveBinaryPlanner.Plan(
        malformed.Nodes,
        malformed.Source,
        malformed.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        malformedPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(malformedPlan)

    corruptBuilder := new ColumnarRangePlannerNodeBuilder()
    left := corruptBuilder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    right := corruptBuilder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    corruptRoot := corruptBuilder.AddNode(
        ColumnarExpressionNodeKind.BinaryExpression(),
        200,
        1,
        0,
        corruptBuilder.Source.Length,
        ColumnarRangePlannerChildren2(left, right))
    corrupt := corruptBuilder.Build(corruptRoot)
    corruptPlan := new ColumnarCodePlan()
    assert ColumnarPrimitiveBinaryPlanner.Plan(
        corrupt.Nodes,
        corrupt.Source,
        corrupt.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        corruptPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(corruptPlan)

    childBuilder := new ColumnarRangePlannerNodeBuilder()
    childPlus := childBuilder.AddToken("+")
    childLeft := childBuilder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    invalidChildren := ColumnarRangePlannerChildren2(childLeft, 200)
    invalidChildRoot := childBuilder.AddNode(
        ColumnarExpressionNodeKind.BinaryExpression(),
        childPlus,
        1,
        0,
        childBuilder.Source.Length,
        invalidChildren)
    invalidChild := childBuilder.Build(invalidChildRoot)
    invalidChildPlan := new ColumnarCodePlan()
    assert ColumnarPrimitiveBinaryPlanner.Plan(
        invalidChild.Nodes,
        invalidChild.Source,
        invalidChild.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        invalidChildPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(invalidChildPlan)
}

test "primitive binary admission does not broaden ordinary direct calls" {
    tree := DirectCallParsedTree("Accept(20 + 22)")
    assert !ColumnarDirectCallPlanner.IsAdmittedValueSyntax(
        tree.Nodes, tree.Root, 0)

    receiver := DirectCallParsedTree("(20 + 22).ToString()")
    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacy := false
    _receiverPlan := DirectCallRejected(
        receiver,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy
}

test "primitive binary admission does not broaden range or from-end values" {
    endpoint := DirectCallParsedTree("(20 + 22)..")
    endpointPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        endpoint.Nodes,
        endpoint.Source,
        endpoint.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        endpointPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(endpointPlan)

    fromEnd := DirectCallParsedTree("^(20 + 22)")
    fromEndPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        fromEnd.Nodes,
        fromEnd.Source,
        fromEnd.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        fromEndPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(fromEndPlan)
}

test "construction planner consumes primitive and source addition in constructors and arrays" {
    owner := ConstructionSourceDefinition(
        "PrimitiveBinaryConstructionOwner", true)
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    owner.DefineUserConstructor(
        parameterTypes,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))

    constructorTree := DirectCallParsedTree(
        "new PrimitiveBinaryConstructionOwner(left + right)")
    ConstructionStampScope(
        constructorTree, "class PrimitiveBinaryConstructionOwner {}")
    constructorBindings := ConstructionBindings(
        SourceCallDefinitions(owner))
    ColumnarRangePlannerAddParameter(
        constructorBindings, "left", 0, typeof(int))
    ColumnarRangePlannerAddParameter(
        constructorBindings, "right", 1, typeof(int))
    constructorPlan := ConstructionPlan(
        constructorTree, constructorBindings)
    assert PrimitiveBinaryOpcodeCount(
        constructorPlan, ColumnarCodePlanContract.Add()) == 1
    assert constructorPlan.OpCodeValues[constructorPlan.OperationCount - 1]
        == ColumnarCodePlanContract.Newobj()

    sizedTree := DirectCallParsedTree("new int[left + right]")
    ConstructionStampScope(sizedTree, "")
    sizedBindings := PrimitiveBinaryParameterBindings(typeof(int))
    sizedPlan := ConstructionPlan(sizedTree, sizedBindings)
    assert sizedPlan.ResultType == typeof(int[])
    assert PrimitiveBinaryOpcodeCount(
        sizedPlan, ColumnarCodePlanContract.Add()) == 1
    assert PrimitiveBinaryOpcodeCount(
        sizedPlan, ColumnarCodePlanContract.Newarr()) == 1

    inferredTree := DirectCallParsedTree("[left + 1, right + 1]")
    ConstructionStampScope(inferredTree, "")
    inferredBindings := PrimitiveBinaryParameterBindings(typeof(int))
    inferredPlan := ConstructionPlan(inferredTree, inferredBindings)
    assert inferredPlan.ResultType == typeof(int[])
    assert PrimitiveBinaryOpcodeCount(
        inferredPlan, ColumnarCodePlanContract.Add()) == 2
    assert PrimitiveBinaryOpcodeCount(
        inferredPlan, ColumnarCodePlanContract.StelemI4()) == 2

    objectOwner := ConstructionSourceDefinition(
        "PrimitiveBinaryObjectInitializer", true)
    valueField := ConstructionDefinePublicField(
        objectOwner.Builder, "Value", typeof(int))
    objectOwner.Fields["Value"] = valueField
    objectOwner.SetFieldOrder(ConstructionOneText("Value"))
    objectOwner.DefaultCtor = objectOwner.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0))
    objectTree := DirectCallParsedTree(
        "new PrimitiveBinaryObjectInitializer { Value: left + right }")
    ConstructionStampScope(
        objectTree, "class PrimitiveBinaryObjectInitializer {}")
    objectBindings := PrimitiveBinaryParameterBindings(typeof(int))
    objectBindings.SourceTypeDefinitions = SourceCallDefinitions(objectOwner)
    objectPlan := ConstructionPlan(objectTree, objectBindings)
    assert ColumnarConstructionPlanner.SameObject(
        objectPlan.ResultType, objectOwner.Builder)
    assert PrimitiveBinaryOpcodeCount(
        objectPlan, ColumnarCodePlanContract.Add()) == 1
    assert PrimitiveBinaryOpcodeCount(
        objectPlan, ColumnarCodePlanContract.Stfld()) == 1

    decimalOwner := ConstructionSourceDefinition(
        "PrimitiveBinaryDecimalConstruction", true)
    decimalParameters := new Type[](1)
    decimalParameters[0] = typeof(decimal)
    decimalOwner.DefineUserConstructor(
        decimalParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    decimalTree := DirectCallParsedTree(
        "new PrimitiveBinaryDecimalConstruction(left + right)")
    ConstructionStampScope(
        decimalTree, "class PrimitiveBinaryDecimalConstruction {}")
    decimalBindings := PrimitiveBinaryParameterBindings(typeof(decimal))
    decimalBindings.SourceTypeDefinitions =
        SourceCallDefinitions(decimalOwner)
    decimalPlan := ConstructionPlan(decimalTree, decimalBindings)
    assert ColumnarConstructionPlanner.SameObject(
        decimalPlan.ResultType, decimalOwner.Builder)
    assert PrimitiveBinaryOpcodeCount(
        decimalPlan, ColumnarCodePlanContract.Call()) == 1
    assert decimalPlan.MethodCount == 1
    assert decimalPlan.Methods[0].get_DeclaringType() == typeof(decimal)
    assert decimalPlan.Methods[0].get_Name() == "op_Addition"

    sourceOperand := ConstructionSourceDefinition(
        "PrimitiveBinaryConstructionOperand", true)
    sourceOperandType: Type = sourceOperand.Builder
    sourceOperator := SourceOperatorDefine(
        sourceOperand,
        "op_Addition",
        SourceOperatorTwoTypes(sourceOperandType, sourceOperandType),
        sourceOperandType)
    sourceOwner := ConstructionSourceDefinition(
        "PrimitiveBinarySourceConstruction", true)
    sourceParameters := new Type[](1)
    sourceParameters[0] = sourceOperandType
    sourceOwner.DefineUserConstructor(
        sourceParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    sourceDefinitions := new ColumnarStructDef[](2)
    sourceDefinitions[0] = sourceOwner
    sourceDefinitions[1] = sourceOperand
    sourceTree := DirectCallParsedTree(
        "new PrimitiveBinarySourceConstruction(left + right)")
    ConstructionStampScope(
        sourceTree,
        "class PrimitiveBinarySourceConstruction {}\n"
            + "class PrimitiveBinaryConstructionOperand {}")
    sourceBindings := PrimitiveBinaryParameterBindings(sourceOperandType)
    sourceBindings.SourceTypeDefinitions = sourceDefinitions
    sourcePlan := ConstructionPlan(sourceTree, sourceBindings)
    assert ColumnarConstructionPlanner.SameObject(
        sourcePlan.ResultType, sourceOwner.Builder)
    assert PrimitiveBinaryOpcodeCount(
        sourcePlan, ColumnarCodePlanContract.Call()) == 1
    assert sourcePlan.MethodCount == 1
    assert ColumnarConstructionPlanner.SameObject(
        sourcePlan.Methods[0], sourceOperator.Builder)
    assert sourcePlan.OpCodeValues[sourcePlan.OperationCount - 1]
        == ColumnarCodePlanContract.Newobj()
}

test "construction planner composes string Length addition inside five nested sized arrays" {
    owner := ConstructionSourceDefinition(
        "PrimitiveBinaryNestedArrayOwner", true)
    parameterTypes := new Type[](5)
    parameterTypes[0] = typeof(int[])
    parameterTypes[1] = typeof(int[])
    parameterTypes[2] = typeof(int[])
    parameterTypes[3] = typeof(int[])
    parameterTypes[4] = typeof(int[])
    owner.DefineUserConstructor(
        parameterTypes,
        ConstructionDefaults(5),
        ConstructionDefaultTexts(5))

    tree := DirectCallParsedTree(
        "new PrimitiveBinaryNestedArrayOwner(new int[](source.Length + 1), new int[](source.Length + 1), new int[](source.Length + 1), new int[](source.Length + 1), new int[](source.Length + 1))")
    ConstructionStampScope(
        tree, "class PrimitiveBinaryNestedArrayOwner {}")
    bindings := ConstructionBindings(SourceCallDefinitions(owner))
    ColumnarRangePlannerAddParameter(
        bindings, "source", 0, typeof(string))

    plan := ConstructionPlan(tree, bindings)
    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType, owner.Builder)
    assert PrimitiveBinaryOpcodeCount(
        plan, ColumnarCodePlanContract.Add()) == 5
    assert PrimitiveBinaryOpcodeCount(
        plan, ColumnarCodePlanContract.Newarr()) == 5
    assert PrimitiveBinaryOpcodeCount(
        plan, ColumnarCodePlanContract.Newobj()) == 1
}

test "unsupported addition shapes remain contextual construction exits" {
    owner := ConstructionSourceDefinition(
        "PrimitiveBinaryExcludedOwner", true)
    definitions := SourceCallDefinitions(owner)
    factSource := "class PrimitiveBinaryExcludedOwner {}"
    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacy := false

    mixedTree := DirectCallParsedTree(
        "new PrimitiveBinaryExcludedOwner(left + 1L)")
    ConstructionStampScope(mixedTree, factSource)
    mixedBindings := ConstructionBindings(definitions)
    ColumnarRangePlannerAddParameter(
        mixedBindings, "left", 0, typeof(int))
    _mixedPlan := ConstructionRejected(
        mixedTree, mixedBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    missingTree := DirectCallParsedTree(
        "new PrimitiveBinaryExcludedOwner(left + missing)")
    ConstructionStampScope(missingTree, factSource)
    missingBindings := ConstructionBindings(definitions)
    ColumnarRangePlannerAddParameter(
        missingBindings, "left", 0, typeof(int))
    _missingPlan := ConstructionRejected(
        missingTree, missingBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    operatorNearMiss := DirectCallParsedTree(
        "new PrimitiveBinaryExcludedOwner(left - left)")
    ConstructionStampScope(operatorNearMiss, factSource)
    nearMissBindings := ConstructionBindings(definitions)
    ColumnarRangePlannerAddParameter(
        nearMissBindings, "left", 0, typeof(int))
    _nearMissPlan := ConstructionRejected(
        operatorNearMiss, nearMissBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    helperTree := DirectCallParsedTree(
        "new PrimitiveBinaryExcludedOwner(Helper())")
    ConstructionStampScope(helperTree, factSource)
    visibleHelpers := new HashSet<string>(StringComparer.Ordinal)
    visibleHelpers.Add("Helper")
    helperBindings := new ColumnarFragmentBindings(
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        new Dictionary<string, LocalBuilder>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        visibleHelpers)
    helperBindings.SourceTypeDefinitions = definitions
    _helperPlan := ConstructionRejected(
        helperTree, helperBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy
}

test "admitted primitive additions reject terminally after construction commitment" {
    owner := ConstructionSourceDefinition(
        "PrimitiveBinaryTerminalOwner", true)
    stringParameter := new Type[](1)
    stringParameter[0] = typeof(string)
    owner.DefineUserConstructor(
        stringParameter,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    definitions := SourceCallDefinitions(owner)
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := true

    constructorTree := DirectCallParsedTree(
        "new PrimitiveBinaryTerminalOwner(left + right)")
    ConstructionStampScope(
        constructorTree, "class PrimitiveBinaryTerminalOwner {}")
    constructorBindings := ConstructionBindings(definitions)
    ColumnarRangePlannerAddParameter(
        constructorBindings, "left", 0, typeof(int))
    ColumnarRangePlannerAddParameter(
        constructorBindings, "right", 1, typeof(int))
    _constructorPlan := ConstructionRejected(
        constructorTree, constructorBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    sizedTree := DirectCallParsedTree("new int[left + right]")
    ConstructionStampScope(sizedTree, "")
    sizedBindings := PrimitiveBinaryParameterBindings(typeof(string))
    _sizedPlan := ConstructionRejected(
        sizedTree, sizedBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    inferredTree := DirectCallParsedTree(
        "[left + right, \"incompatible\"]")
    ConstructionStampScope(inferredTree, "")
    inferredBindings := PrimitiveBinaryParameterBindings(typeof(int))
    _inferredPlan := ConstructionRejected(
        inferredTree, inferredBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    objectOwner := ConstructionSourceDefinition(
        "PrimitiveBinaryTerminalObject", true)
    labelField := ConstructionDefinePublicField(
        objectOwner.Builder, "Label", typeof(string))
    objectOwner.Fields["Label"] = labelField
    objectOwner.SetFieldOrder(ConstructionOneText("Label"))
    objectOwner.DefaultCtor = objectOwner.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0))
    initializerTree := DirectCallParsedTree(
        "new PrimitiveBinaryTerminalObject { Label: left + right }")
    ConstructionStampScope(
        initializerTree, "class PrimitiveBinaryTerminalObject {}")
    objectBindings := ConstructionBindings(
        SourceCallDefinitions(objectOwner))
    ColumnarRangePlannerAddParameter(
        objectBindings, "left", 0, typeof(int))
    ColumnarRangePlannerAddParameter(
        objectBindings, "right", 1, typeof(int))
    _objectPlan := ConstructionRejected(
        initializerTree, objectBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "semantic construction admission preserves target-typed null values" {
    constructorOwner := ConstructionSourceDefinition(
        "PrimitiveBinaryNullConstructor", true)
    stringParameter := new Type[](1)
    stringParameter[0] = typeof(string)
    constructorOwner.DefineUserConstructor(
        stringParameter,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    constructorTree := DirectCallParsedTree(
        "new PrimitiveBinaryNullConstructor(null)")
    ConstructionStampScope(
        constructorTree, "class PrimitiveBinaryNullConstructor {}")
    constructorPlan := ConstructionPlan(
        constructorTree,
        ConstructionBindings(SourceCallDefinitions(constructorOwner)))
    assert PrimitiveBinaryOpcodeCount(
        constructorPlan, ColumnarCodePlanContract.Ldnull()) == 1

    objectOwner := ConstructionSourceDefinition(
        "PrimitiveBinaryNullObject", true)
    labelField := ConstructionDefinePublicField(
        objectOwner.Builder, "Label", typeof(string))
    objectOwner.Fields["Label"] = labelField
    objectOwner.SetFieldOrder(ConstructionOneText("Label"))
    objectOwner.DefaultCtor = objectOwner.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0))
    objectTree := DirectCallParsedTree(
        "new PrimitiveBinaryNullObject { Label: null }")
    ConstructionStampScope(
        objectTree, "class PrimitiveBinaryNullObject {}")
    objectPlan := ConstructionPlan(
        objectTree,
        ConstructionBindings(SourceCallDefinitions(objectOwner)))
    assert PrimitiveBinaryOpcodeCount(
        objectPlan, ColumnarCodePlanContract.Ldnull()) == 1
    assert PrimitiveBinaryOpcodeCount(
        objectPlan, ColumnarCodePlanContract.Stfld()) == 1
}
