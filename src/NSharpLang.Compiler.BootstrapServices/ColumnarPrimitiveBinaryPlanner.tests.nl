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
        "new PrimitiveBinaryExcludedOwner(left && left)")
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

func PrimitiveBinaryCheckedBindings(valueType: Type): ColumnarFragmentBindings {
    bindings := PrimitiveBinaryParameterBindings(valueType)
    bindings.OverflowCheckingEnabled = true
    return bindings
}

test "primitive binary planner owns subtraction multiplication division and remainder" {
    subPlan := PrimitiveBinaryPlan(
        "50 - 8", ColumnarRangePlannerEmptyBindings())
    assert subPlan.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        subPlan, ColumnarCodePlanContract.Sub()) == 1
    assert ExecutorRunV3ScalarPlan(subPlan, typeof(int)) == "42"

    mulPlan := PrimitiveBinaryPlan(
        "6 * 7", ColumnarRangePlannerEmptyBindings())
    assert PrimitiveBinaryOpcodeCount(
        mulPlan, ColumnarCodePlanContract.Mul()) == 1
    assert ExecutorRunV3ScalarPlan(mulPlan, typeof(int)) == "42"

    divPlan := PrimitiveBinaryPlan(
        "84 / 2", ColumnarRangePlannerEmptyBindings())
    assert PrimitiveBinaryOpcodeCount(
        divPlan, ColumnarCodePlanContract.Div()) == 1
    assert ExecutorRunV3ScalarPlan(divPlan, typeof(int)) == "42"

    remPlan := PrimitiveBinaryPlan(
        "142 % 100", ColumnarRangePlannerEmptyBindings())
    assert PrimitiveBinaryOpcodeCount(
        remPlan, ColumnarCodePlanContract.Rem()) == 1
    assert ExecutorRunV3ScalarPlan(remPlan, typeof(int)) == "42"

    longSub := PrimitiveBinaryPlan(
        "left - right", PrimitiveBinaryParameterBindings(typeof(long)))
    assert longSub.ResultType == typeof(long)
    assert PrimitiveBinaryOpcodeCount(
        longSub, ColumnarCodePlanContract.Sub()) == 1
    assert PrimitiveBinaryExecuteParameters(
        longSub, typeof(long), typeof(long), typeof(long),
        50L, 8L) == "42"

    uintDiv := PrimitiveBinaryPlan(
        "left / right", PrimitiveBinaryParameterBindings(typeof(uint)))
    assert uintDiv.ResultType == typeof(uint)
    assert PrimitiveBinaryOpcodeCount(
        uintDiv, ColumnarCodePlanContract.DivUn()) == 1
    assert PrimitiveBinaryOpcodeCount(
        uintDiv, ColumnarCodePlanContract.Div()) == 0
    assert PrimitiveBinaryExecuteParameters(
        uintDiv, typeof(uint), typeof(uint), typeof(uint),
        (uint)84, (uint)2) == "42"

    ulongRem := PrimitiveBinaryPlan(
        "left % right", PrimitiveBinaryParameterBindings(typeof(ulong)))
    assert PrimitiveBinaryOpcodeCount(
        ulongRem, ColumnarCodePlanContract.RemUn()) == 1
    assert PrimitiveBinaryExecuteParameters(
        ulongRem, typeof(ulong), typeof(ulong), typeof(ulong),
        (ulong)142, (ulong)100) == "42"

    doubleDiv := PrimitiveBinaryPlan(
        "left / right", PrimitiveBinaryParameterBindings(typeof(double)))
    assert doubleDiv.ResultType == typeof(double)
    assert PrimitiveBinaryOpcodeCount(
        doubleDiv, ColumnarCodePlanContract.Div()) == 1
    assert PrimitiveBinaryExecuteParameters(
        doubleDiv, typeof(double), typeof(double), typeof(double),
        105.0, 2.5) == (105.0 / 2.5).ToString()

    charSub := PrimitiveBinaryPlan(
        "left - right", PrimitiveBinaryParameterBindings(typeof(char)))
    assert charSub.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        charSub, ColumnarCodePlanContract.Sub()) == 1
    assert PrimitiveBinaryExecuteParameters(
        charSub, typeof(int), typeof(char), typeof(char),
        'd', 'a') == "3"
}

test "primitive binary planner owns bitwise and or xor over integral op types" {
    andPlan := PrimitiveBinaryPlan(
        "left & right", PrimitiveBinaryParameterBindings(typeof(int)))
    assert andPlan.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        andPlan, ColumnarCodePlanContract.And()) == 1
    assert PrimitiveBinaryExecuteParameters(
        andPlan, typeof(int), typeof(int), typeof(int),
        46, 58) == "42"

    orPlan := PrimitiveBinaryPlan(
        "left | right", PrimitiveBinaryParameterBindings(typeof(long)))
    assert orPlan.ResultType == typeof(long)
    assert PrimitiveBinaryOpcodeCount(
        orPlan, ColumnarCodePlanContract.Or()) == 1
    assert PrimitiveBinaryExecuteParameters(
        orPlan, typeof(long), typeof(long), typeof(long),
        32L, 10L) == "42"

    xorPlan := PrimitiveBinaryPlan(
        "left ^ right", PrimitiveBinaryParameterBindings(typeof(uint)))
    assert xorPlan.ResultType == typeof(uint)
    assert PrimitiveBinaryOpcodeCount(
        xorPlan, ColumnarCodePlanContract.Xor()) == 1
    assert PrimitiveBinaryExecuteParameters(
        xorPlan, typeof(uint), typeof(uint), typeof(uint),
        (uint)60, (uint)22) == "42"

    promotedAnd := PrimitiveBinaryPlan(
        "left & right",
        PrimitiveBinaryPairBindings(typeof(byte), typeof(short)))
    assert promotedAnd.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        promotedAnd, ColumnarCodePlanContract.And()) == 1

    PrimitiveBinaryDeclines(
        "left & right", PrimitiveBinaryParameterBindings(typeof(bool)))
}

test "primitive binary planner owns shifts with signed and unsigned right selection" {
    leftShift := PrimitiveBinaryPlan(
        "left << right",
        PrimitiveBinaryPairBindings(typeof(int), typeof(int)))
    assert leftShift.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        leftShift, ColumnarCodePlanContract.Shl()) == 1
    assert PrimitiveBinaryExecuteParameters(
        leftShift, typeof(int), typeof(int), typeof(int),
        21, 1) == "42"

    signedRight := PrimitiveBinaryPlan(
        "left >> right",
        PrimitiveBinaryPairBindings(typeof(long), typeof(int)))
    assert signedRight.ResultType == typeof(long)
    assert PrimitiveBinaryOpcodeCount(
        signedRight, ColumnarCodePlanContract.Shr()) == 1
    assert PrimitiveBinaryOpcodeCount(
        signedRight, ColumnarCodePlanContract.ShrUn()) == 0
    assert PrimitiveBinaryExecuteParameters(
        signedRight, typeof(long), typeof(long), typeof(int),
        168L, 2) == "42"

    unsignedRight := PrimitiveBinaryPlan(
        "left >> right",
        PrimitiveBinaryPairBindings(typeof(ulong), typeof(int)))
    assert unsignedRight.ResultType == typeof(ulong)
    assert PrimitiveBinaryOpcodeCount(
        unsignedRight, ColumnarCodePlanContract.ShrUn()) == 1
    assert PrimitiveBinaryOpcodeCount(
        unsignedRight, ColumnarCodePlanContract.Shr()) == 0
    assert PrimitiveBinaryExecuteParameters(
        unsignedRight, typeof(ulong), typeof(ulong), typeof(int),
        (ulong)168, 2) == "42"

    PrimitiveBinaryDeclines(
        "left >> right",
        PrimitiveBinaryPairBindings(typeof(int), typeof(long)))
    PrimitiveBinaryDeclines(
        "left << right",
        PrimitiveBinaryPairBindings(typeof(uint), typeof(int)))
}

func PrimitiveBinaryOrderingResult(
    source: string,
    valueType: Type,
    leftValue: object,
    rightValue: object): string {
    plan := PrimitiveBinaryPlan(
        source, PrimitiveBinaryParameterBindings(valueType))
    return PrimitiveBinaryExecuteParameters(
        plan, typeof(bool), valueType, valueType, leftValue, rightValue)
}

test "primitive binary planner owns ordering with signed unsigned and float lowering" {
    intLess := PrimitiveBinaryPlan(
        "left < right", PrimitiveBinaryParameterBindings(typeof(int)))
    assert intLess.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        intLess, ColumnarCodePlanContract.Clt()) == 1
    assert PrimitiveBinaryOrderingResult(
        "left < right", typeof(int), 1, 2) == "True"
    assert PrimitiveBinaryOrderingResult(
        "left < right", typeof(int), 5, 2) == "False"

    intLessEqual := PrimitiveBinaryPlan(
        "left <= right", PrimitiveBinaryParameterBindings(typeof(int)))
    assert PrimitiveBinaryOpcodeCount(
        intLessEqual, ColumnarCodePlanContract.Cgt()) == 1
    assert PrimitiveBinaryOpcodeCount(
        intLessEqual, ColumnarCodePlanContract.Ceq()) == 1
    assert PrimitiveBinaryOrderingResult(
        "left <= right", typeof(int), 2, 2) == "True"

    uintGreater := PrimitiveBinaryPlan(
        "left > right", PrimitiveBinaryParameterBindings(typeof(uint)))
    assert PrimitiveBinaryOpcodeCount(
        uintGreater, ColumnarCodePlanContract.CgtUn()) == 1
    assert PrimitiveBinaryOrderingResult(
        "left > right", typeof(uint), (uint)50, (uint)8) == "True"

    floatLessEqual := PrimitiveBinaryPlan(
        "left <= right", PrimitiveBinaryParameterBindings(typeof(double)))
    assert PrimitiveBinaryOpcodeCount(
        floatLessEqual, ColumnarCodePlanContract.CgtUn()) == 1
    assert PrimitiveBinaryOpcodeCount(
        floatLessEqual, ColumnarCodePlanContract.Ceq()) == 1
    assert PrimitiveBinaryOrderingResult(
        "left <= right", typeof(double), 2.0, 2.5) == "True"
    zero := 0.0
    nanValue := zero / zero
    assert PrimitiveBinaryOrderingResult(
        "left <= right", typeof(double), nanValue, 2.5) == "False"

    doubleGreaterEqual := PrimitiveBinaryPlan(
        "left >= right", PrimitiveBinaryParameterBindings(typeof(double)))
    assert PrimitiveBinaryOpcodeCount(
        doubleGreaterEqual, ColumnarCodePlanContract.CltUn()) == 1
    assert PrimitiveBinaryOpcodeCount(
        doubleGreaterEqual, ColumnarCodePlanContract.Ceq()) == 1
}

test "primitive binary planner owns numeric and Boolean equality" {
    intEq := PrimitiveBinaryPlan(
        "left == right", PrimitiveBinaryParameterBindings(typeof(int)))
    assert intEq.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        intEq, ColumnarCodePlanContract.Ceq()) == 1
    assert PrimitiveBinaryOrderingResult(
        "left == right", typeof(int), 42, 42) == "True"
    assert PrimitiveBinaryOrderingResult(
        "left == right", typeof(int), 42, 7) == "False"

    intNotEq := PrimitiveBinaryPlan(
        "left != right", PrimitiveBinaryParameterBindings(typeof(int)))
    assert PrimitiveBinaryOpcodeCount(
        intNotEq, ColumnarCodePlanContract.Ceq()) == 2
    assert PrimitiveBinaryOrderingResult(
        "left != right", typeof(int), 42, 7) == "True"

    boolEq := PrimitiveBinaryPlan(
        "left == right", PrimitiveBinaryParameterBindings(typeof(bool)))
    assert boolEq.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        boolEq, ColumnarCodePlanContract.Ceq()) == 1
    assert PrimitiveBinaryOrderingResult(
        "left == right", typeof(bool), true, true) == "True"
    assert PrimitiveBinaryOrderingResult(
        "left == right", typeof(bool), true, false) == "False"

    boolNotEq := PrimitiveBinaryPlan(
        "left != right", PrimitiveBinaryParameterBindings(typeof(bool)))
    assert PrimitiveBinaryOpcodeCount(
        boolNotEq, ColumnarCodePlanContract.Ceq()) == 2
    assert PrimitiveBinaryOrderingResult(
        "left != right", typeof(bool), true, false) == "True"

    doubleEq := PrimitiveBinaryPlan(
        "left == right", PrimitiveBinaryParameterBindings(typeof(double)))
    assert PrimitiveBinaryOpcodeCount(
        doubleEq, ColumnarCodePlanContract.Ceq()) == 1
    assert PrimitiveBinaryOrderingResult(
        "left == right", typeof(double), 42.0, 42.0) == "True"
}

test "primitive binary planner owns the decimal operator statics" {
    subPlan := PrimitiveBinaryPlan(
        "left - right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert subPlan.ResultType == typeof(decimal)
    assert PrimitiveBinaryOpcodeCount(
        subPlan, ColumnarCodePlanContract.Call()) == 1
    assert subPlan.Methods[0].get_Name() == "op_Subtraction"
    assert PrimitiveBinaryExecuteParameters(
        subPlan, typeof(decimal), typeof(decimal), typeof(decimal),
        50m, 8m) == "42"

    mulPlan := PrimitiveBinaryPlan(
        "left * right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert mulPlan.ResultType == typeof(decimal)
    assert mulPlan.Methods[0].get_Name() == "op_Multiply"
    assert PrimitiveBinaryExecuteParameters(
        mulPlan, typeof(decimal), typeof(decimal), typeof(decimal),
        6m, 7m) == "42"

    divPlan := PrimitiveBinaryPlan(
        "left / right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert divPlan.Methods[0].get_Name() == "op_Division"
    assert PrimitiveBinaryExecuteParameters(
        divPlan, typeof(decimal), typeof(decimal), typeof(decimal),
        84m, 2m) == "42"

    remPlan := PrimitiveBinaryPlan(
        "left % right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert remPlan.Methods[0].get_Name() == "op_Modulus"
    assert PrimitiveBinaryExecuteParameters(
        remPlan, typeof(decimal), typeof(decimal), typeof(decimal),
        142m, 100m) == "42"

    lessPlan := PrimitiveBinaryPlan(
        "left < right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert lessPlan.ResultType == typeof(bool)
    assert lessPlan.Methods[0].get_Name() == "op_LessThan"
    assert PrimitiveBinaryExecuteParameters(
        lessPlan, typeof(bool), typeof(decimal), typeof(decimal),
        1m, 2m) == "True"

    greaterEqualPlan := PrimitiveBinaryPlan(
        "left >= right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert greaterEqualPlan.ResultType == typeof(bool)
    assert greaterEqualPlan.Methods[0].get_Name() == "op_GreaterThanOrEqual"
    assert PrimitiveBinaryExecuteParameters(
        greaterEqualPlan, typeof(bool), typeof(decimal), typeof(decimal),
        2m, 2m) == "True"

    equalPlan := PrimitiveBinaryPlan(
        "left == right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert equalPlan.ResultType == typeof(bool)
    assert equalPlan.Methods[0].get_Name() == "op_Equality"
    assert PrimitiveBinaryExecuteParameters(
        equalPlan, typeof(bool), typeof(decimal), typeof(decimal),
        5m, 5m) == "True"

    notEqualPlan := PrimitiveBinaryPlan(
        "left != right", PrimitiveBinaryParameterBindings(typeof(decimal)))
    assert notEqualPlan.Methods[0].get_Name() == "op_Inequality"
    assert PrimitiveBinaryExecuteParameters(
        notEqualPlan, typeof(bool), typeof(decimal), typeof(decimal),
        5m, 8m) == "True"

    PrimitiveBinaryDeclines(
        "left & right", PrimitiveBinaryParameterBindings(typeof(decimal)))
}

test "primitive binary planner selects checked overflow opcodes only under a checked context" {
    uncheckedAdd := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryParameterBindings(typeof(int)))
    assert PrimitiveBinaryOpcodeCount(
        uncheckedAdd, ColumnarCodePlanContract.Add()) == 1
    assert PrimitiveBinaryOpcodeCount(
        uncheckedAdd, ColumnarCodePlanContract.AddOvf()) == 0

    checkedAdd := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryCheckedBindings(typeof(int)))
    assert PrimitiveBinaryOpcodeCount(
        checkedAdd, ColumnarCodePlanContract.AddOvf()) == 1
    assert PrimitiveBinaryOpcodeCount(
        checkedAdd, ColumnarCodePlanContract.Add()) == 0
    assert PrimitiveBinaryExecuteParameters(
        checkedAdd, typeof(int), typeof(int), typeof(int),
        20, 22) == "42"

    checkedSub := PrimitiveBinaryPlan(
        "left - right", PrimitiveBinaryCheckedBindings(typeof(int)))
    assert PrimitiveBinaryOpcodeCount(
        checkedSub, ColumnarCodePlanContract.SubOvf()) == 1
    assert PrimitiveBinaryOpcodeCount(
        checkedSub, ColumnarCodePlanContract.Sub()) == 0

    checkedMul := PrimitiveBinaryPlan(
        "left * right", PrimitiveBinaryCheckedBindings(typeof(int)))
    assert PrimitiveBinaryOpcodeCount(
        checkedMul, ColumnarCodePlanContract.MulOvf()) == 1

    checkedUintAdd := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryCheckedBindings(typeof(uint)))
    assert PrimitiveBinaryOpcodeCount(
        checkedUintAdd, ColumnarCodePlanContract.AddOvfUn()) == 1
    assert PrimitiveBinaryExecuteParameters(
        checkedUintAdd, typeof(uint), typeof(uint), typeof(uint),
        (uint)20, (uint)22) == "42"

    checkedUintMul := PrimitiveBinaryPlan(
        "left * right", PrimitiveBinaryCheckedBindings(typeof(uint)))
    assert PrimitiveBinaryOpcodeCount(
        checkedUintMul, ColumnarCodePlanContract.MulOvfUn()) == 1

    checkedDiv := PrimitiveBinaryPlan(
        "left / right", PrimitiveBinaryCheckedBindings(typeof(int)))
    assert PrimitiveBinaryOpcodeCount(
        checkedDiv, ColumnarCodePlanContract.Div()) == 1

    checkedDouble := PrimitiveBinaryPlan(
        "left + right", PrimitiveBinaryCheckedBindings(typeof(double)))
    assert PrimitiveBinaryOpcodeCount(
        checkedDouble, ColumnarCodePlanContract.Add()) == 1
    assert PrimitiveBinaryOpcodeCount(
        checkedDouble, ColumnarCodePlanContract.AddOvf()) == 0
}

test "primitive binary planner declines mixed pairs boolean and non numeric relations atomically" {
    PrimitiveBinaryDeclines(
        "left - right",
        PrimitiveBinaryPairBindings(typeof(int), typeof(double)))
    PrimitiveBinaryDeclines(
        "left * right",
        PrimitiveBinaryPairBindings(typeof(int), typeof(long)))
    PrimitiveBinaryDeclines(
        "left < right",
        PrimitiveBinaryParameterBindings(typeof(string)))
    PrimitiveBinaryDeclines(
        "left == right",
        PrimitiveBinaryParameterBindings(typeof(string)))

    partialBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(partialBindings, "left", 0, typeof(int))
    PrimitiveBinaryDeclines("left * missing", partialBindings)
    PrimitiveBinaryDeclines("left < missing", partialBindings)
}

func PrimitiveBinaryExecuteOneParameter(
    plan: ColumnarCodePlan,
    resultType: Type,
    parameterType: Type,
    parameterValue: object): string {
    parameterTypes := new Type[](1)
    parameterTypes[0] = parameterType
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, parameterValue)
    return ExecutorRunRecursivePlan(
        plan, resultType, parameterTypes, arguments)
}

test "primitive binary planner owns numeric cast operands per admitted target" {
    // The flagship no-op shape: an int literal reinterpreted as uint emits NO conversion opcode,
    // exactly like the legacy case-16 i4-slot branch. The known literal survives to the cast
    // fragment boundary, which refines it to the declared uint.
    literalBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(literalBindings, "left", 0, typeof(uint))
    uintLiteralPlan := PrimitiveBinaryPlan("left == (uint)42", literalBindings)
    assert uintLiteralPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        uintLiteralPlan, ColumnarCodePlanContract.ConvU4()) == 0
    assert PrimitiveBinaryOpcodeCount(
        uintLiteralPlan, ColumnarCodePlanContract.ConvI4()) == 0
    assert PrimitiveBinaryOpcodeCount(
        uintLiteralPlan, ColumnarCodePlanContract.Ceq()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        uintLiteralPlan, typeof(bool), typeof(uint), (uint)42) == "True"

    // A char literal reinterpreted as int is the same no-op branch.
    intCharBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(intCharBindings, "left", 0, typeof(int))
    intCharPlan := PrimitiveBinaryPlan("(int)'a' == left", intCharBindings)
    assert intCharPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        intCharPlan, ColumnarCodePlanContract.ConvI4()) == 0
    assert PrimitiveBinaryExecuteOneParameter(
        intCharPlan, typeof(bool), typeof(int), 97) == "True"

    // Widening to long always emits conv.i8.
    longBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(longBindings, "left", 0, typeof(int))
    longPlan := PrimitiveBinaryPlan("(long)left + 1L", longBindings)
    assert longPlan.ResultType == typeof(long)
    assert PrimitiveBinaryOpcodeCount(
        longPlan, ColumnarCodePlanContract.ConvI8()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        longPlan, typeof(long), typeof(int), 41) == "42"

    // The ulong target keeps the legacy source-driven selection: uint zero-extends via conv.u8,
    // int sign-extends via conv.i8.
    ulongFromUintBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(ulongFromUintBindings, "left", 0, typeof(uint))
    ulongFromUintPlan := PrimitiveBinaryPlan("(ulong)left + 2UL", ulongFromUintBindings)
    assert ulongFromUintPlan.ResultType == typeof(ulong)
    assert PrimitiveBinaryOpcodeCount(
        ulongFromUintPlan, ColumnarCodePlanContract.ConvU8()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        ulongFromUintPlan, typeof(ulong), typeof(uint), (uint)40) == "42"

    ulongFromIntBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(ulongFromIntBindings, "left", 0, typeof(int))
    ulongFromIntPlan := PrimitiveBinaryPlan("(ulong)left + 2UL", ulongFromIntBindings)
    assert PrimitiveBinaryOpcodeCount(
        ulongFromIntPlan, ColumnarCodePlanContract.ConvU8()) == 0
    assert PrimitiveBinaryOpcodeCount(
        ulongFromIntPlan, ColumnarCodePlanContract.ConvI8()) == 1

    // char casts truncate via conv.u2 and participate in the promoted equality family.
    charBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(charBindings, "left", 0, typeof(int))
    charPlan := PrimitiveBinaryPlan("(char)left == 'a'", charBindings)
    assert charPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        charPlan, ColumnarCodePlanContract.ConvU2()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        charPlan, typeof(bool), typeof(int), 97) == "True"

    // Small-int truncations select conv.u1/conv.i1/conv.i2 and promote back to int arithmetic.
    byteBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(byteBindings, "left", 0, typeof(int))
    bytePlan := PrimitiveBinaryPlan("(byte)left + 1", byteBindings)
    assert bytePlan.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        bytePlan, ColumnarCodePlanContract.ConvU1()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        bytePlan, typeof(int), typeof(int), 300) == "45"

    sbytePlan := PrimitiveBinaryPlan("(sbyte)left + 1", byteBindings)
    assert PrimitiveBinaryOpcodeCount(
        sbytePlan, ColumnarCodePlanContract.ConvI1()) == 1

    shortPlan := PrimitiveBinaryPlan("(short)left * 2", byteBindings)
    assert shortPlan.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        shortPlan, ColumnarCodePlanContract.ConvI2()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        shortPlan, typeof(int), typeof(int), 10) == "20"

    // Floating targets widen via conv.r8/conv.r4; i8/r8 sources narrow to int via conv.i4.
    doubleBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(doubleBindings, "left", 0, typeof(int))
    doublePlan := PrimitiveBinaryPlan("(double)left < 4.5", doubleBindings)
    assert doublePlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        doublePlan, ColumnarCodePlanContract.ConvR8()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        doublePlan, typeof(bool), typeof(int), 4) == "True"

    floatPlan := PrimitiveBinaryPlan("(float)left + 1.5f", doubleBindings)
    assert floatPlan.ResultType == typeof(float)
    assert PrimitiveBinaryOpcodeCount(
        floatPlan, ColumnarCodePlanContract.ConvR4()) == 1

    truncateBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(truncateBindings, "left", 0, typeof(double))
    truncatePlan := PrimitiveBinaryPlan("(int)left + 1", truncateBindings)
    assert truncatePlan.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        truncatePlan, ColumnarCodePlanContract.ConvI4()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        truncatePlan, typeof(int), typeof(double), 41.9) == "42"

    uintNarrowBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(uintNarrowBindings, "left", 0, typeof(long))
    ColumnarRangePlannerAddParameter(uintNarrowBindings, "right", 1, typeof(uint))
    uintNarrowPlan := PrimitiveBinaryPlan("(uint)left == right", uintNarrowBindings)
    assert uintNarrowPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        uintNarrowPlan, ColumnarCodePlanContract.ConvU4()) == 1
    assert PrimitiveBinaryExecuteParameters(
        uintNarrowPlan, typeof(bool), typeof(long), typeof(uint),
        5L, (uint)5) == "True"

    // A literal identity cast rides the direct-literal path and emits no conversion opcode.
    identityBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(identityBindings, "left", 0, typeof(int))
    identityPlan := PrimitiveBinaryPlan("(int)41 + left", identityBindings)
    assert identityPlan.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        identityPlan, ColumnarCodePlanContract.ConvI4()) == 0
    assert PrimitiveBinaryExecuteOneParameter(
        identityPlan, typeof(int), typeof(int), 1) == "42"

    // A ushort target over a KNOWN in-range literal rides the same no-op path: the fragment
    // boundary refines the known Int32 value to ushort with no conv.u2 row.
    ushortLiteralBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(
        ushortLiteralBindings, "left", 0, typeof(ushort))
    ushortLiteralPlan := PrimitiveBinaryPlan(
        "left == (ushort)16", ushortLiteralBindings)
    assert ushortLiteralPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        ushortLiteralPlan, ColumnarCodePlanContract.ConvU2()) == 0
    assert PrimitiveBinaryOpcodeCount(
        ushortLiteralPlan, ColumnarCodePlanContract.Ceq()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        ushortLiteralPlan, typeof(bool), typeof(ushort), (ushort)16) == "True"
    ushortMismatchPlan := PrimitiveBinaryPlan(
        "left == (ushort)16", ushortLiteralBindings)
    assert PrimitiveBinaryExecuteOneParameter(
        ushortMismatchPlan, typeof(bool), typeof(ushort), (ushort)17) == "False"
}

test "primitive binary planner owns decimal literal operands" {
    decimalBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(decimalBindings, "left", 0, typeof(decimal))
    comparePlan := PrimitiveBinaryPlan("left == 24.5m", decimalBindings)
    assert comparePlan.ResultType == typeof(bool)
    assert comparePlan.ConstructorCount == 1
    decimalConstructor := comparePlan.Constructors[0]
    assert decimalConstructor.get_DeclaringType() == typeof(decimal)
    constructorParameters := decimalConstructor.GetParameters()
    assert constructorParameters.Length == 5
    assert constructorParameters[0].get_ParameterType() == typeof(int)
    assert constructorParameters[3].get_ParameterType() == typeof(bool)
    assert constructorParameters[4].get_ParameterType() == typeof(byte)
    assert PrimitiveBinaryExecuteOneParameter(
        comparePlan, typeof(bool), typeof(decimal), 24.5m) == "True"

    additionPlan := PrimitiveBinaryPlan(
        "1.5m + 2.5m", ColumnarRangePlannerEmptyBindings())
    assert additionPlan.ResultType == typeof(decimal)
    assert additionPlan.ConstructorCount == 2
    assert ExecutorRunV3ScalarPlan(additionPlan, typeof(decimal))
        == (1.5m + 2.5m).ToString()

    integerFormPlan := PrimitiveBinaryPlan(
        "5m + 2m", ColumnarRangePlannerEmptyBindings())
    assert integerFormPlan.ResultType == typeof(decimal)
    assert ExecutorRunV3ScalarPlan(integerFormPlan, typeof(decimal))
        == (5m + 2m).ToString()

    negativeScalePlan := PrimitiveBinaryPlan(
        "left < 0.5m", decimalBindings)
    assert negativeScalePlan.ResultType == typeof(bool)
    assert PrimitiveBinaryExecuteOneParameter(
        negativeScalePlan, typeof(bool), typeof(decimal), 0.25m) == "True"

    // A NEGATIVE decimal literal operand closes through the unary-literal planner's
    // System.Decimal.op_UnaryNegation lowering inside the binary plan.
    negativeLiteralPlan := PrimitiveBinaryPlan(
        "left == -1.25m", decimalBindings)
    assert negativeLiteralPlan.ResultType == typeof(bool)
    negationFound := false
    methodIndex := 0
    while methodIndex < negativeLiteralPlan.MethodCount {
        if negativeLiteralPlan.Methods[methodIndex].get_Name()
            == "op_UnaryNegation" {
            negationFound = true
        }
        methodIndex += 1
    }
    assert negationFound
    negativeProbe := -1.25m
    assert PrimitiveBinaryExecuteOneParameter(
        negativeLiteralPlan, typeof(bool), typeof(decimal),
        negativeProbe) == "True"
}

test "primitive binary planner adopts an unsuffixed int literal into an exact uint long ulong left" {
    // `u / 2` runs uint/uint: the literal 2 adopts uint via ldc.i4, and the division is unsigned.
    uintBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(uintBindings, "left", 0, typeof(uint))
    uintDivPlan := PrimitiveBinaryPlan("left / 2", uintBindings)
    assert uintDivPlan.ResultType == typeof(uint)
    assert PrimitiveBinaryOpcodeCount(
        uintDivPlan, ColumnarCodePlanContract.LdcI4()) == 1
    assert PrimitiveBinaryOpcodeCount(
        uintDivPlan, ColumnarCodePlanContract.DivUn()) == 1
    eightyFour := (uint)84
    assert PrimitiveBinaryExecuteOneParameter(
        uintDivPlan, typeof(uint), typeof(uint), eightyFour) == "42"

    // `l != 0` runs long/long: the literal 0 adopts long via ldc.i8, negated ceq for `!=`.
    longBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(longBindings, "left", 0, typeof(long))
    longNePlan := PrimitiveBinaryPlan("left != 0", longBindings)
    assert longNePlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        longNePlan, ColumnarCodePlanContract.LdcI8()) == 1
    fiveBillion := 5000000000L
    assert PrimitiveBinaryExecuteOneParameter(
        longNePlan, typeof(bool), typeof(long), fiveBillion) == "True"

    // ulong adopts through the same ldc.i8 shape.
    ulongBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(ulongBindings, "left", 0, typeof(ulong))
    ulongPlan := PrimitiveBinaryPlan("left + 10", ulongBindings)
    assert ulongPlan.ResultType == typeof(ulong)
    assert PrimitiveBinaryOpcodeCount(
        ulongPlan, ColumnarCodePlanContract.LdcI8()) == 1
    assert PrimitiveBinaryOpcodeCount(
        ulongPlan, ColumnarCodePlanContract.Add()) == 1
    thirtyTwo := (ulong)32
    assert PrimitiveBinaryExecuteOneParameter(
        ulongPlan, typeof(ulong), typeof(ulong), thirtyTwo) == "42"

    // A NEGATIVE literal adopts long only — the value seals pre-negated via ldc.i8, no neg opcode.
    longNegPlan := PrimitiveBinaryPlan("left > -5", longBindings)
    assert longNegPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        longNegPlan, ColumnarCodePlanContract.LdcI8()) == 1
    zeroLong := 0L
    assert PrimitiveBinaryExecuteOneParameter(
        longNegPlan, typeof(bool), typeof(long), zeroLong) == "True"

    // A SHIFT count literal never adopts: `l << 2` keeps its Int32 count (ldc.i4, not ldc.i8) and
    // shifts the long value, exactly as before adoption existed.
    longShiftPlan := PrimitiveBinaryPlan("left << 2", longBindings)
    assert longShiftPlan.ResultType == typeof(long)
    assert PrimitiveBinaryOpcodeCount(
        longShiftPlan, ColumnarCodePlanContract.Shl()) == 1
    assert PrimitiveBinaryOpcodeCount(
        longShiftPlan, ColumnarCodePlanContract.LdcI4()) == 1
    assert PrimitiveBinaryOpcodeCount(
        longShiftPlan, ColumnarCodePlanContract.LdcI8()) == 0
    tenLong := 10L
    assert PrimitiveBinaryExecuteOneParameter(
        longShiftPlan, typeof(long), typeof(long), tenLong) == "40"
}

test "primitive binary planner derefs byref parameters inside binaries" {
    // The exact case-12 blocker shape from the interface-parameter-modifiers product surface:
    // `value + 10` with `ref value: int` plans ldarg(address) + ldind.i4 for the read, then the
    // literal and add — executed through a real byref slot.
    byRefIntBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(
        byRefIntBindings, "value", 0, typeof(int).MakeByRefType())
    byRefIntPlan := PrimitiveBinaryPlan("value + 10", byRefIntBindings)
    assert byRefIntPlan.ResultType == typeof(int)
    assert PrimitiveBinaryOpcodeCount(
        byRefIntPlan, ColumnarCodePlanContract.LdindI4()) == 1
    assert PrimitiveBinaryOpcodeCount(
        byRefIntPlan, ColumnarCodePlanContract.Add()) == 1
    assert byRefIntPlan.ArgumentCount == 1
    assert byRefIntPlan.ArgumentIsAddress[0]
    assert PrimitiveBinaryExecuteOneParameter(
        byRefIntPlan, typeof(int), typeof(int).MakeByRefType(), 32) == "42"

    // A byref long left operand derefs via ldind.i8 and the right literal adopts long.
    byRefLongBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(
        byRefLongBindings, "value", 0, typeof(long).MakeByRefType())
    byRefLongPlan := PrimitiveBinaryPlan("value * 3", byRefLongBindings)
    assert byRefLongPlan.ResultType == typeof(long)
    assert PrimitiveBinaryOpcodeCount(
        byRefLongPlan, ColumnarCodePlanContract.LdindI8()) == 1
    assert PrimitiveBinaryOpcodeCount(
        byRefLongPlan, ColumnarCodePlanContract.LdcI8()) == 1
    fourteenLong := 14L
    assert PrimitiveBinaryExecuteOneParameter(
        byRefLongPlan, typeof(long), typeof(long).MakeByRefType(),
        fourteenLong) == "42"

    // A byref double ordering operand derefs via ldind.r8.
    byRefDoubleBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(
        byRefDoubleBindings, "value", 0, typeof(double).MakeByRefType())
    byRefDoublePlan := PrimitiveBinaryPlan("value < 4.5", byRefDoubleBindings)
    assert byRefDoublePlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        byRefDoublePlan, ColumnarCodePlanContract.LdindR8()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        byRefDoublePlan, typeof(bool), typeof(double).MakeByRefType(), 4.0)
        == "True"

    // A byref element outside the ldind table (decimal) keeps the binary a whole-subtree exit.
    byRefDecimalBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(
        byRefDecimalBindings, "value", 0, typeof(decimal).MakeByRefType())
    PrimitiveBinaryDeclines("value + 1m", byRefDecimalBindings)
}

test "primitive binary planner declines non-adopting literal mixes atomically" {
    uintBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(uintBindings, "left", 0, typeof(uint))

    // Both operand orders: only the RIGHT literal adopts (the legacy arm's exact rule). A literal
    // LEFT against a typed uint right stays a mixed int/uint pair and declines.
    literalLeft := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(literalLeft, "value", 0, typeof(uint))
    PrimitiveBinaryDeclines("2 / value", literalLeft)

    // An out-of-range magnitude declines for every target: the cap is Int32.MaxValue, so a literal
    // above it neither adopts nor plans as its own Int32.
    PrimitiveBinaryDeclines("left / 3000000000", uintBindings)

    // A suffixed literal keeps its own fixed type and never adopts: `2UL` against a uint left is a
    // uint/ulong mismatch that declines.
    PrimitiveBinaryDeclines("left / 2UL", uintBindings)

    // A negative literal never adopts an unsigned left (uint/ulong reject it), so the mix declines.
    PrimitiveBinaryDeclines("left + -5", uintBindings)
    ulongBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(ulongBindings, "left", 0, typeof(ulong))
    PrimitiveBinaryDeclines("left + -5", ulongBindings)
}

test "primitive binary planner reinterprets exact i4 slot and int enum casts to int and uint" {
    // `(uint)intValue` reinterprets via an explicit conv.u4 — the legacy i4-slot no-op planned as a
    // non-empty fragment. Executes to the identical unsigned bit pattern.
    uintFromInt := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(uintFromInt, "left", 0, typeof(uint))
    ColumnarRangePlannerAddParameter(uintFromInt, "right", 1, typeof(int))
    uintFromIntPlan := PrimitiveBinaryPlan("left == (uint)right", uintFromInt)
    assert uintFromIntPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        uintFromIntPlan, ColumnarCodePlanContract.ConvU4()) == 1
    assert PrimitiveBinaryOpcodeCount(
        uintFromIntPlan, ColumnarCodePlanContract.Ceq()) == 1
    assert PrimitiveBinaryExecuteParameters(
        uintFromIntPlan, typeof(bool), typeof(uint), typeof(int), (uint)7, 7) == "True"
    uintFromIntMismatch := PrimitiveBinaryPlan("left == (uint)right", uintFromInt)
    assert PrimitiveBinaryExecuteParameters(
        uintFromIntMismatch, typeof(bool), typeof(uint), typeof(int), (uint)9, 3) == "False"

    // `(int)uintValue` reinterprets via an explicit conv.i4.
    intFromUint := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(intFromUint, "left", 0, typeof(int))
    ColumnarRangePlannerAddParameter(intFromUint, "right", 1, typeof(uint))
    intFromUintPlan := PrimitiveBinaryPlan("left == (int)right", intFromUint)
    assert intFromUintPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        intFromUintPlan, ColumnarCodePlanContract.ConvI4()) == 1
    assert PrimitiveBinaryExecuteParameters(
        intFromUintPlan, typeof(bool), typeof(int), typeof(uint), 7, (uint)7) == "True"

    // A known int-backed enum reinterprets to int inside a binary: `((int)e & flag) == value`.
    enumBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(
        enumBindings, "e", 0, typeof(ColumnarRangePlannerProbeEnum))
    enumFalsePlan := PrimitiveBinaryPlan("((int)e & 4) == 0", enumBindings)
    assert enumFalsePlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        enumFalsePlan, ColumnarCodePlanContract.ConvI4()) == 1
    assert PrimitiveBinaryOpcodeCount(
        enumFalsePlan, ColumnarCodePlanContract.And()) == 1
    assert PrimitiveBinaryExecuteOneParameter(
        enumFalsePlan, typeof(bool), typeof(ColumnarRangePlannerProbeEnum),
        ColumnarRangePlannerProbeEnum.Four) == "False"
    enumTruePlan := PrimitiveBinaryPlan("((int)e & 4) == 0", enumBindings)
    assert PrimitiveBinaryExecuteOneParameter(
        enumTruePlan, typeof(bool), typeof(ColumnarRangePlannerProbeEnum),
        ColumnarRangePlannerProbeEnum.One) == "True"

    // `(uint)e` reinterprets an int-backed enum to uint via conv.u4.
    enumUint := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(enumUint, "left", 0, typeof(uint))
    ColumnarRangePlannerAddParameter(
        enumUint, "e", 1, typeof(ColumnarRangePlannerProbeEnum))
    enumUintPlan := PrimitiveBinaryPlan("left == (uint)e", enumUint)
    assert enumUintPlan.ResultType == typeof(bool)
    assert PrimitiveBinaryOpcodeCount(
        enumUintPlan, ColumnarCodePlanContract.ConvU4()) == 1
    assert PrimitiveBinaryExecuteParameters(
        enumUintPlan, typeof(bool), typeof(uint),
        typeof(ColumnarRangePlannerProbeEnum),
        (uint)4, ColumnarRangePlannerProbeEnum.Four) == "True"

    // An identity int cast still declines: it needs no reinterpretation and its empty fragment
    // stays with the legacy owner.
    identityBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(identityBindings, "left", 0, typeof(int))
    ColumnarRangePlannerAddParameter(identityBindings, "right", 1, typeof(int))
    PrimitiveBinaryDeclines("left == (int)right", identityBindings)

    // A source that is neither an exact int/uint nor an int-backed enum (a string-backed enum's
    // runtime type is not a CLR enum) never reinterprets and stays legacy-owned.
    stringSource := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(stringSource, "left", 0, typeof(int))
    ColumnarRangePlannerAddParameter(stringSource, "e", 1, typeof(string))
    PrimitiveBinaryDeclines("left == (int)e", stringSource)
}

test "primitive binary planner declines legacy-owned cast forms atomically" {
    intPair := PrimitiveBinaryPairBindings(typeof(int), typeof(int))

    // Non-numeric targets, decimal targets, and NON-LITERAL ushort targets stay legacy-owned
    // (only a known in-range ushort literal rides the refinement no-op path); an out-of-range
    // ushort literal keeps the legacy conv.u2 truncation owner.
    boolPair := PrimitiveBinaryParameterBindings(typeof(bool))
    PrimitiveBinaryDeclines("left == (bool)right", boolPair)
    PrimitiveBinaryDeclines("(decimal)left + 1m", intPair)
    PrimitiveBinaryDeclines("(ushort)left + right", intPair)
    ushortRange := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(ushortRange, "left", 0, typeof(ushort))
    PrimitiveBinaryDeclines("left == (ushort)70000", ushortRange)
    PrimitiveBinaryDeclines("(string)left == right", intPair)

    // A decimal source never reaches a conv opcode.
    decimalSource := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(decimalSource, "left", 0, typeof(decimal))
    ColumnarRangePlannerAddParameter(decimalSource, "right", 1, typeof(int))
    PrimitiveBinaryDeclines("(int)left + right", decimalSource)

    // An identity cast over a non-literal operand emits nothing, which the plan schema cannot
    // represent as its own fragment; the legacy owner keeps serving it.
    PrimitiveBinaryDeclines("(int)left + right", intPair)
}

// A SECOND int-backed probe enum, so a MIXED enum pair has a shape to be refused in. Two distinct
// enums over the same underlying type are the case a rule keyed only on "is integral on the stack"
// would wrongly admit.
enum ColumnarPrimitiveBinaryOtherProbeEnum {
    Zero = 0,
    One = 1,
    Four = 4
}

// Non-int-backed enums are resolved by CANONICAL IDENTITY: N# source enums are int- or
// string-backed, so the wider underlying set only exists on external types.
func PrimitiveBinaryRuntimeType(canonicalName: string): Type {
    resolved := Type.GetType(canonicalName)
    if resolved == null {
        throw new InvalidOperationException(
            "The runtime does not define '" + canonicalName + "'.")
    }

    return resolved
}

test "primitive binary planner owns bitwise and or xor over ONE enum and KEEPS the enum type" {
    probe := typeof(ColumnarRangePlannerProbeEnum)

    // The result type is the ENUM, not int. This is the whole difference between the enum arm and
    // another row in the promotable table: `One | Four` is a ColumnarRangePlannerProbeEnum(5), and
    // a non-Flags enum with no member at 5 renders as its number.
    orPlan := PrimitiveBinaryPlan(
        "left | right", PrimitiveBinaryParameterBindings(probe))
    assert orPlan.ResultType == probe
    assert PrimitiveBinaryOpcodeCount(
        orPlan, ColumnarCodePlanContract.Or()) == 1
    assert PrimitiveBinaryExecuteParameters(
        orPlan, probe, probe, probe,
        ColumnarRangePlannerProbeEnum.One,
        ColumnarRangePlannerProbeEnum.Four) == "5"

    andPlan := PrimitiveBinaryPlan(
        "left & right", PrimitiveBinaryParameterBindings(probe))
    assert andPlan.ResultType == probe
    assert PrimitiveBinaryOpcodeCount(
        andPlan, ColumnarCodePlanContract.And()) == 1
    assert PrimitiveBinaryExecuteParameters(
        andPlan, probe, probe, probe,
        ColumnarRangePlannerProbeEnum.Four,
        ColumnarRangePlannerProbeEnum.Four) == "Four"

    xorPlan := PrimitiveBinaryPlan(
        "left ^ right", PrimitiveBinaryParameterBindings(probe))
    assert xorPlan.ResultType == probe
    assert PrimitiveBinaryOpcodeCount(
        xorPlan, ColumnarCodePlanContract.Xor()) == 1
    assert PrimitiveBinaryExecuteParameters(
        xorPlan, probe, probe, probe,
        ColumnarRangePlannerProbeEnum.Four,
        ColumnarRangePlannerProbeEnum.Four) == "Zero"

    // An EXTERNAL long-backed enum runs the same way and keeps its own 64-bit form: the operands
    // never promote, so the answer is exact above 2^32.
    keywords := PrimitiveBinaryRuntimeType("System.Diagnostics.Tracing.EventKeywords")
    longPlan := PrimitiveBinaryPlan(
        "left | right", PrimitiveBinaryParameterBindings(keywords))
    assert longPlan.ResultType == keywords
    assert PrimitiveBinaryOpcodeCount(
        longPlan, ColumnarCodePlanContract.Or()) == 1
    assert PrimitiveBinaryExecuteParameters(
        longPlan, keywords, keywords, keywords,
        Enum.ToObject(keywords, 4294967296L),
        Enum.ToObject(keywords, 1L)) == "4294967297"

    // TWO DIFFERENT enums are not one op type, so the pair never unifies and the family declines.
    mixed := PrimitiveBinaryPairBindings(
        probe, typeof(ColumnarPrimitiveBinaryOtherProbeEnum))
    PrimitiveBinaryDeclines("left | right", mixed)

    // An enum mixed with its own underlying type is likewise not one op type.
    PrimitiveBinaryDeclines(
        "left | right", PrimitiveBinaryPairBindings(probe, typeof(int)))

    // The ordering, arithmetic and shift families are UNCHANGED: only and/or/xor grew an enum arm.
    PrimitiveBinaryDeclines(
        "left + right", PrimitiveBinaryParameterBindings(probe))
    PrimitiveBinaryDeclines(
        "left < right", PrimitiveBinaryParameterBindings(probe))
    PrimitiveBinaryDeclines(
        "left << right", PrimitiveBinaryPairBindings(probe, typeof(int)))
}

test "the bitwise enum rule admits exactly the underlying set the family already runs" {
    // Every CLR enum underlying type is one the family runs over plain operands, so an enum never
    // reaches an opcode a value of its underlying type could not.
    assert ColumnarNumericFacts.IsBitwiseEnum(typeof(ColumnarRangePlannerProbeEnum))
    assert ColumnarNumericFacts.IsBitwiseEnum(
        PrimitiveBinaryRuntimeType("System.Diagnostics.Tracing.EventKeywords"))
    assert ColumnarNumericFacts.IsBitwiseEnum(
        PrimitiveBinaryRuntimeType("System.Security.SecurityRuleSet"))
    assert ColumnarNumericFacts.IsBitwiseEnum(
        PrimitiveBinaryRuntimeType("System.Runtime.InteropServices.ComTypes.TYPEFLAGS"))

    // A non-enum is refused however integral it is, which is what keeps the plain-operand table the
    // only route for int/long/uint/ulong.
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(int))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(long))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(bool))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(string))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(decimal))

    // The rule is stated once and the two owners that must agree on it both read it: the planner
    // that selects the opcode and the executor that validates the resulting stack shape.
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(ColumnarRangePlannerProbeEnum))
}
