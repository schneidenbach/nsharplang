namespace NSharpLang.Compiler.Columnar

import System

func ConversionDirectCallOneType(value: Type): Type[] {
    result := new Type[](1)
    result[0] = value
    return result
}

func ConversionDirectCallLiteralFacts(isLiteral: bool, isNegative: bool, value: long): ColumnarDirectCallArgumentFacts {
    literalKinds := new bool[](1)
    negativeKinds := new bool[](1)
    values := new long[](1)
    literalKinds[0] = isLiteral
    negativeKinds[0] = isNegative
    values[0] = value
    return new ColumnarDirectCallArgumentFacts(literalKinds, negativeKinds, values)
}

func ConversionDirectCallLiteralTree(ownerName: string, methodName: string, literalText: string, literalKind: int, isNegative: bool, outerParentheses: int): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), ownerName)

    memberStart := builder.AddToken(methodName)
    member := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, methodName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(owner))

    minusStart := -1
    if isNegative {
        minusStart = builder.AddToken("-")
    }

    argument := builder.AddLeaf(literalKind, literalText)
    if isNegative {
        argument = builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression(), minusStart, 1, minusStart, builder.Source.Length - minusStart, ColumnarRangePlannerChildren1(argument))
    }

    index := 0
    while index < outerParentheses {
        argument = builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(argument))

        index += 1
    }

    root := DirectCallAppendCall(builder, member, DirectCallOneArgument(argument))

    return builder.Build(root)
}

func ConversionDirectCallAssertLiteralRejected(tree: ColumnarRangePlannerTestTree, bindings: ColumnarFragmentBindings) {
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

func ConversionDirectCallAssertLiteralValue(plan: ColumnarCodePlan, targetType: Type, expectedValue: long) {
    assert plan.OperationCount >= 2
    assert !ConversionDirectCallHasOpcode(plan, ColumnarCodePlanContract.Neg())

    literalIndex := plan.OperandIndices[0]
    if targetType == typeof(long) || targetType == typeof(ulong) {
        assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI8()
        assert literalIndex >= 0 && literalIndex < plan.Int64Count
        assert plan.Int64Values[literalIndex] == expectedValue
    } else {
        assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
        assert literalIndex >= 0 && literalIndex < plan.Int32Count
        assert (long)plan.Int32Values[literalIndex] == expectedValue
    }
}

func ConversionDirectCallHasOpcode(plan: ColumnarCodePlan, opcode: short): bool {
    index := 0
    while index < plan.OperationCount {
        if plan.OpCodeValues[index] == opcode {
            return true
        }

        index += 1
    }

    return false
}

func ConversionDirectCallMethodIndex(plan: ColumnarCodePlan, name: string): int {
    index := 0
    while index < plan.MethodCount {
        method := plan.Methods[index]
        if method != null && method.get_Name() == name {
            return index
        }

        index += 1
    }

    throw new InvalidOperationException("Required direct-call conversion method was not recorded: " + name)
}

func ConversionDirectCallTargetMethodIndex(plan: ColumnarCodePlan): int {
    if plan.OperationCount == 0 || plan.OpCodeValues[plan.OperationCount - 1] != ColumnarCodePlanContract.Call() {
        throw new InvalidOperationException("A direct-call conversion plan must end in the selected static call.")
    }

    methodIndex := plan.OperandIndices[plan.OperationCount - 1]
    if methodIndex < 0 || methodIndex >= plan.MethodCount {
        throw new InvalidOperationException("The selected direct-call conversion method index is invalid.")
    }

    return methodIndex
}

func ConversionDirectCallVariablePlan(ownerName: string, actualType: Type, parameterType: Type): ColumnarCodePlan {
    owner := SourceCallDefinition(ownerName, true)
    parameterTypes := ConversionDirectCallOneType(parameterType)
    SourceCallPublicStatic(owner, "Take", parameterTypes, typeof(int))
    ownerType: Type = owner.Builder

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "value", 0, actualType)
    tree := DirectCallQualifiedTree(ownerName, "Take", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    plan := DirectCallPlan(tree, bindings)
    targetIndex := ConversionDirectCallTargetMethodIndex(plan)
    assert plan.Methods[targetIndex].get_Name() == "Take"
    assert plan.MethodUsesDeclaredSignature[targetIndex]
    assert plan.MethodDeclaringTypes[targetIndex] == ownerType
    assert plan.MethodParameterTypes[targetIndex].Length == 1
    assert plan.MethodParameterTypes[targetIndex][0] == parameterType
    assert plan.MethodReturnTypes[targetIndex] == typeof(int)
    assert plan.MethodIsStatic[targetIndex]
    return plan
}

func ConversionDirectCallAssertUnaryWidening(ownerName: string, actualType: Type, parameterType: Type, expectedOpcode: short) {
    plan := ConversionDirectCallVariablePlan(ownerName, actualType, parameterType)

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == expectedOpcode
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
}

func ConversionDirectCallAssertDecimalWidening(ownerName: string, actualType: Type, expectedOperatorParameterType: Type, expectsI4Normalization: bool) {
    plan := ConversionDirectCallVariablePlan(ownerName, actualType, typeof(decimal))

    conversionIndex := ConversionDirectCallMethodIndex(plan, "op_Implicit")

    assert plan.MethodUsesDeclaredSignature[conversionIndex]
    assert plan.MethodDeclaringTypes[conversionIndex] == typeof(decimal)
    assert plan.MethodParameterTypes[conversionIndex].Length == 1
    assert plan.MethodParameterTypes[conversionIndex][0] == expectedOperatorParameterType

    assert plan.MethodReturnTypes[conversionIndex] == typeof(decimal)
    assert plan.MethodIsStatic[conversionIndex]
    assert !plan.MethodIsAbstract[conversionIndex]

    if expectsI4Normalization {
        assert ConversionDirectCallHasOpcode(plan, ColumnarCodePlanContract.ConvI4())
    } else {
        assert !ConversionDirectCallHasOpcode(plan, ColumnarCodePlanContract.ConvI4())
    }

    assert plan.OpCodeValues[plan.OperationCount - 2] == ColumnarCodePlanContract.Call()

    assert plan.OperandIndices[plan.OperationCount - 2] == conversionIndex
}

test "direct-call planner preserves every legacy small and character numeric widening" {
    smallTypes := new Type[](5)
    smallTypes[0] = typeof(byte)
    smallTypes[1] = typeof(sbyte)
    smallTypes[2] = typeof(short)
    smallTypes[3] = typeof(ushort)
    smallTypes[4] = typeof(char)

    index := 0
    while index < smallTypes.Length {
        actualType := smallTypes[index]
        prefix := "DirectCallSmallConversion" + index.ToString()

        ConversionDirectCallAssertUnaryWidening(prefix + "ToInt", actualType, typeof(int), ColumnarCodePlanContract.ConvI4())

        ConversionDirectCallAssertUnaryWidening(prefix + "ToLong", actualType, typeof(long), ColumnarCodePlanContract.ConvI8())

        ConversionDirectCallAssertUnaryWidening(prefix + "ToFloat", actualType, typeof(float), ColumnarCodePlanContract.ConvR4())

        ConversionDirectCallAssertUnaryWidening(prefix + "ToDouble", actualType, typeof(double), ColumnarCodePlanContract.ConvR8())

        ConversionDirectCallAssertDecimalWidening(prefix + "ToDecimal", actualType, actualType == typeof(char) ? typeof(char) : typeof(int), actualType != typeof(char))

        index += 1
    }
}

test "direct-call planner preserves int long and float widening opcode identities" {
    ConversionDirectCallAssertUnaryWidening("DirectCallIntToLong", typeof(int), typeof(long), ColumnarCodePlanContract.ConvI8())

    ConversionDirectCallAssertUnaryWidening("DirectCallIntToFloat", typeof(int), typeof(float), ColumnarCodePlanContract.ConvR4())

    ConversionDirectCallAssertUnaryWidening("DirectCallIntToDouble", typeof(int), typeof(double), ColumnarCodePlanContract.ConvR8())

    ConversionDirectCallAssertDecimalWidening("DirectCallIntToDecimal", typeof(int), typeof(int), false)

    ConversionDirectCallAssertUnaryWidening("DirectCallLongToFloat", typeof(long), typeof(float), ColumnarCodePlanContract.ConvR4())

    ConversionDirectCallAssertUnaryWidening("DirectCallLongToDouble", typeof(long), typeof(double), ColumnarCodePlanContract.ConvR8())

    ConversionDirectCallAssertDecimalWidening("DirectCallLongToDecimal", typeof(long), typeof(long), false)

    ConversionDirectCallAssertUnaryWidening("DirectCallFloatToDouble", typeof(float), typeof(double), ColumnarCodePlanContract.ConvR8())
}

test "direct-call planner emits exact value boxing and leaves reference upcasts opcode free" {
    objectPlan := ConversionDirectCallVariablePlan("DirectCallBoxObject", typeof(int), typeof(object))

    comparablePlan := ConversionDirectCallVariablePlan("DirectCallBoxInterface", typeof(int), typeof(IComparable))

    assert objectPlan.OperationCount == 3
    assert objectPlan.OpCodeValues[1] == ColumnarCodePlanContract.Box()
    objectBoxTypeIndex := objectPlan.OperandIndices[1]
    assert objectPlan.Types[objectBoxTypeIndex] == typeof(int)

    assert comparablePlan.OperationCount == 3
    assert comparablePlan.OpCodeValues[1] == ColumnarCodePlanContract.Box()
    comparableBoxTypeIndex := comparablePlan.OperandIndices[1]
    assert comparablePlan.Types[comparableBoxTypeIndex] == typeof(int)

    referencePlan := ConversionDirectCallVariablePlan("DirectCallReferenceUpcast", typeof(string), typeof(object))

    assert referencePlan.OperationCount == 2
    assert referencePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert referencePlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert !ConversionDirectCallHasOpcode(referencePlan, ColumnarCodePlanContract.Box())

    referenceInterfacePlan := ConversionDirectCallVariablePlan("DirectCallReferenceInterfaceUpcast", typeof(string), typeof(IComparable))

    assert referenceInterfacePlan.OperationCount == 2
    assert referenceInterfacePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert referenceInterfacePlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert !ConversionDirectCallHasOpcode(referenceInterfacePlan, ColumnarCodePlanContract.Box())
}

test "source direct-call overload ranking is exact then numeric then boxing" {
    owner := SourceCallDefinition("DirectCallConversionRanking", true)
    objectParameters := ConversionDirectCallOneType(typeof(object))
    longParameters := ConversionDirectCallOneType(typeof(long))
    intParameters := ConversionDirectCallOneType(typeof(int))
    comparableParameters := ConversionDirectCallOneType(typeof(IComparable))

    SourceCallPublicStatic(owner, "ExactFirst", objectParameters, typeof(int))
    SourceCallPublicStatic(owner, "ExactFirst", longParameters, typeof(int))
    SourceCallPublicStatic(owner, "ExactFirst", intParameters, typeof(int))
    SourceCallPublicStatic(owner, "NumericFirst", objectParameters, typeof(int))
    SourceCallPublicStatic(owner, "NumericFirst", longParameters, typeof(int))
    SourceCallPublicStatic(owner, "BoxingTie", objectParameters, typeof(int))
    SourceCallPublicStatic(owner, "BoxingTie", comparableParameters, typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "value", 0, typeof(int))

    exactTree := DirectCallQualifiedTree("DirectCallConversionRanking", "ExactFirst", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    exactPlan := DirectCallPlan(exactTree, bindings)
    exactTarget := ConversionDirectCallTargetMethodIndex(exactPlan)
    assert exactPlan.MethodParameterTypes[exactTarget][0] == typeof(int)
    assert exactPlan.OperationCount == 2

    numericTree := DirectCallQualifiedTree("DirectCallConversionRanking", "NumericFirst", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    numericPlan := DirectCallPlan(numericTree, bindings)
    numericTarget := ConversionDirectCallTargetMethodIndex(numericPlan)
    assert numericPlan.MethodParameterTypes[numericTarget][0] == typeof(long)
    assert numericPlan.OpCodeValues[1] == ColumnarCodePlanContract.ConvI8()

    ambiguousTree := DirectCallQualifiedTree("DirectCallConversionRanking", "BoxingTie", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(ambiguousTree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

test "direct-call integer constants adopt fixed targets that int variables cannot" {
    owner := SourceCallDefinition("DirectCallLiteralAdoption", true)
    targetTypes := new Type[](7)
    targetTypes[0] = typeof(byte)
    targetTypes[1] = typeof(sbyte)
    targetTypes[2] = typeof(short)
    targetTypes[3] = typeof(ushort)
    targetTypes[4] = typeof(uint)
    targetTypes[5] = typeof(long)
    targetTypes[6] = typeof(ulong)

    index := 0
    while index < targetTypes.Length {
        methodName := "Take" + index.ToString()
        SourceCallPublicStatic(owner, methodName, ConversionDirectCallOneType(targetTypes[index]), typeof(int))

        index += 1
    }

    literalBindings := DirectCallSingleDefinitionBindings(owner)
    index = 0
    while index < targetTypes.Length {
        methodName := "Take" + index.ToString()
        literalTree := DirectCallQualifiedTree("DirectCallLiteralAdoption", methodName, DirectCallOneText("7"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

        literalPlan := DirectCallPlan(literalTree, literalBindings)
        targetIndex := ConversionDirectCallTargetMethodIndex(literalPlan)

        assert literalPlan.MethodParameterTypes[targetIndex][0] == targetTypes[index]
        ConversionDirectCallAssertLiteralValue(literalPlan, targetTypes[index], 7)

        index += 1
    }

    variableBindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(variableBindings, "value", 0, typeof(int))

    index = 0
    while index < targetTypes.Length {

        // Int32 variables widen to Int64, but constant-only adoption is required for
        // every small/unsigned target in this matrix.
        if targetTypes[index] != typeof(long) {
            methodName := "Take" + index.ToString()
            variableTree := DirectCallQualifiedTree("DirectCallLiteralAdoption", methodName, DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

            ownership := ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning := true
            DirectCallRejected(variableTree, variableBindings, out ownership, out legacyWholeSubtreePlanning)

            assert ownership == ColumnarDirectCallOwnership.OwnedRejected
            assert !legacyWholeSubtreePlanning
        }

        index += 1
    }

    overflowTree := DirectCallQualifiedTree("DirectCallLiteralAdoption", "Take0", DirectCallOneText("256"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    overflowOwnership := ColumnarDirectCallOwnership.NotOwned
    overflowLegacyChildPlanning := true
    DirectCallRejected(overflowTree, literalBindings, out overflowOwnership, out overflowLegacyChildPlanning)

    assert overflowOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !overflowLegacyChildPlanning
}

test "direct-call integer constants adopt supported nullable element targets" {
    nullableByte := NullableArgumentType(typeof(byte))
    owner := SourceCallDefinition("DirectCallNullableLiteralAdoption", true)
    SourceCallPublicStatic(owner, "Take", ConversionDirectCallOneType(nullableByte), typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)
    literalTree := DirectCallQualifiedTree("DirectCallNullableLiteralAdoption", "Take", DirectCallOneText("255"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    literalPlan := DirectCallPlan(literalTree, bindings)
    targetIndex := ConversionDirectCallTargetMethodIndex(literalPlan)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteralArgument(nullableByte, 255, false)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteralArgument(nullableByte, 256, false)

    assert literalPlan.MethodParameterTypes[targetIndex][0] == nullableByte
    assert literalPlan.OperationCount == 3
    assert literalPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert literalPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
    assert literalPlan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
    assert literalPlan.ConstructorCount == 1
    assert literalPlan.ConstructorUsesDeclaredSignature[0]
    assert literalPlan.ConstructorDeclaringTypes[0] == nullableByte
    assert literalPlan.ConstructorParameterTypes[0].Length == 1
    assert literalPlan.ConstructorParameterTypes[0][0] == typeof(byte)

    variableBindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(variableBindings, "value", 0, typeof(int))
    variableTree := DirectCallQualifiedTree("DirectCallNullableLiteralAdoption", "Take", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    variableOwnership := ColumnarDirectCallOwnership.NotOwned
    variableLegacyChildPlanning := true
    DirectCallRejected(variableTree, variableBindings, out variableOwnership, out variableLegacyChildPlanning)

    assert variableOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !variableLegacyChildPlanning

    overflowTree := DirectCallQualifiedTree("DirectCallNullableLiteralAdoption", "Take", DirectCallOneText("256"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    overflowOwnership := ColumnarDirectCallOwnership.NotOwned
    overflowLegacyChildPlanning := true
    DirectCallRejected(overflowTree, bindings, out overflowOwnership, out overflowLegacyChildPlanning)

    assert overflowOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !overflowLegacyChildPlanning
}

test "direct-call integer syntax facts validate sign value and source type together" {
    owner := SourceCallDefinition("DirectCallLiteralFactValidation", true)
    SourceCallPublicStatic(owner, "TakeSigned", ConversionDirectCallOneType(typeof(sbyte)), typeof(int))

    SourceCallPublicStatic(owner, "TakeUnsigned", ConversionDirectCallOneType(typeof(byte)), typeof(int))

    actualTypes := ConversionDirectCallOneType(typeof(int))
    definitions := SourceCallDefinitions(owner)
    negativeZeroFacts := ConversionDirectCallLiteralFacts(true, true, 0)
    signedZero := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "TakeSigned", actualTypes, definitions, negativeZeroFacts)

    unsignedZero := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "TakeUnsigned", actualTypes, definitions, negativeZeroFacts)

    assert signedZero.Status == ColumnarSourceDirectCallStatus.Selected
    assert signedZero.ParameterTypes[0] == typeof(sbyte)
    assert unsignedZero.Status == ColumnarSourceDirectCallStatus.Rejected

    negativeFlagWithPositiveValue := ConversionDirectCallLiteralFacts(true, true, 1)

    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "TakeSigned", actualTypes, definitions, negativeFlagWithPositiveValue)
    }

    positiveFlagWithNegativeValue := ConversionDirectCallLiteralFacts(true, false, -1)

    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "TakeSigned", actualTypes, definitions, positiveFlagWithNegativeValue)
    }

    detachedNegativeFlag := ConversionDirectCallLiteralFacts(false, true, 0)

    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "TakeSigned", actualTypes, definitions, detachedNegativeFlag)
    }

    outOfRangeFacts := ConversionDirectCallLiteralFacts(true, false, 2147483648L)

    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "TakeSigned", actualTypes, definitions, outOfRangeFacts)
    }

    wrongSourceType := ConversionDirectCallOneType(typeof(string))
    positiveFacts := ConversionDirectCallLiteralFacts(true, false, 1)
    assert throws InvalidOperationException {
        ColumnarSourceDirectCallResolver.ResolveExplicitStatic(owner.Builder, "TakeSigned", wrongSourceType, definitions, positiveFacts)
    }
}

test "target-typed integer magnitude extraction excludes non-decimal literal spellings" {
    magnitude := -1
    assert ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("0", out magnitude)

    assert magnitude == 0
    assert ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("255", out magnitude)

    assert magnitude == 255
    assert ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("2147483647", out magnitude)

    assert magnitude == 2147483647

    assert !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("2147483648", out magnitude)

    assert !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("7L", out magnitude)

    assert !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("7UL", out magnitude)

    assert !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("0x7", out magnitude)

    assert !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("1_0", out magnitude)

    assert !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude("'A'", out magnitude)
}

test "direct-call constant adoption pins every legacy signed and unsigned boundary" {
    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(byte), 255)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(byte), 256)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(sbyte), 127)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(sbyte), 128)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(short), 32767)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(short), 32768)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(ushort), 65535)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(ushort), 65536)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(uint), 2147483647)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(uint), 2147483648L)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(long), 2147483647)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(long), 2147483648L)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(ulong), 2147483647)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(ulong), 2147483648L)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(sbyte), -127, true)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(sbyte), -128, true)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(short), -32767, true)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(short), -32768, true)

    assert ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(long), -2147483647, true)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(long), -2147483648L, true)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(byte), 0, true)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(ushort), 0, true)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(uint), 0, true)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(ulong), 0, true)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(int), 1)

    assert !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(typeof(char), 65)
}

test "parenthesized negative zero retains its sign and emits no runtime negation" {
    owner := SourceCallDefinition("DirectCallNegativeLiteralShape", true)
    SourceCallPublicStatic(owner, "TakeSigned", ConversionDirectCallOneType(typeof(sbyte)), typeof(int))

    SourceCallPublicStatic(owner, "TakeUnsigned", ConversionDirectCallOneType(typeof(byte)), typeof(int))

    SourceCallPublicStatic(owner, "TakeSignedBoundary", ConversionDirectCallOneType(typeof(sbyte)), typeof(int))

    SourceCallPublicStatic(owner, "TakeLongBoundary", ConversionDirectCallOneType(typeof(long)), typeof(int))

    SourceCallPublicStatic(owner, "TakeUIntBoundary", ConversionDirectCallOneType(typeof(uint)), typeof(int))

    SourceCallPublicStatic(owner, "TakeULongBoundary", ConversionDirectCallOneType(typeof(ulong)), typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)
    signedZeroTree := ConversionDirectCallLiteralTree("DirectCallNegativeLiteralShape", "TakeSigned", "0", ColumnarExpressionNodeKind.IntLiteralExpression(), true, 2)

    signedZeroPlan := DirectCallPlan(signedZeroTree, bindings)
    ConversionDirectCallAssertLiteralValue(signedZeroPlan, typeof(sbyte), 0)

    signedZeroTarget := ConversionDirectCallTargetMethodIndex(signedZeroPlan)
    assert signedZeroPlan.MethodParameterTypes[signedZeroTarget][0] == typeof(sbyte)

    unsignedZeroTree := ConversionDirectCallLiteralTree("DirectCallNegativeLiteralShape", "TakeUnsigned", "0", ColumnarExpressionNodeKind.IntLiteralExpression(), true, 2)

    ConversionDirectCallAssertLiteralRejected(unsignedZeroTree, bindings)

    signedBoundaryTree := ConversionDirectCallLiteralTree("DirectCallNegativeLiteralShape", "TakeSignedBoundary", "127", ColumnarExpressionNodeKind.IntLiteralExpression(), true, 1)

    signedBoundaryPlan := DirectCallPlan(signedBoundaryTree, bindings)
    ConversionDirectCallAssertLiteralValue(signedBoundaryPlan, typeof(sbyte), -127)

    longBoundaryTree := ConversionDirectCallLiteralTree("DirectCallNegativeLiteralShape", "TakeLongBoundary", "2147483647", ColumnarExpressionNodeKind.IntLiteralExpression(), true, 1)

    longBoundaryPlan := DirectCallPlan(longBoundaryTree, bindings)
    ConversionDirectCallAssertLiteralValue(longBoundaryPlan, typeof(long), -2147483647)

    uintBoundaryTree := ConversionDirectCallLiteralTree("DirectCallNegativeLiteralShape", "TakeUIntBoundary", "2147483647", ColumnarExpressionNodeKind.IntLiteralExpression(), false, 0)

    uintBoundaryPlan := DirectCallPlan(uintBoundaryTree, bindings)
    ConversionDirectCallAssertLiteralValue(uintBoundaryPlan, typeof(uint), 2147483647)

    ulongBoundaryTree := ConversionDirectCallLiteralTree("DirectCallNegativeLiteralShape", "TakeULongBoundary", "2147483647", ColumnarExpressionNodeKind.IntLiteralExpression(), false, 0)

    ulongBoundaryPlan := DirectCallPlan(ulongBoundaryTree, bindings)
    ConversionDirectCallAssertLiteralValue(ulongBoundaryPlan, typeof(ulong), 2147483647)

    rejectedSignedBoundary := ConversionDirectCallLiteralTree("DirectCallNegativeLiteralShape", "TakeSignedBoundary", "128", ColumnarExpressionNodeKind.IntLiteralExpression(), true, 0)

    ConversionDirectCallAssertLiteralRejected(rejectedSignedBoundary, bindings)
}

test "suffix hexadecimal underscore and character literals never gain adoption facts" {
    owner := SourceCallDefinition("DirectCallLiteralSpellingExclusions", true)
    SourceCallPublicStatic(owner, "Take", ConversionDirectCallOneType(typeof(byte)), typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)

    longSuffix := ConversionDirectCallLiteralTree("DirectCallLiteralSpellingExclusions", "Take", "7L", ColumnarExpressionNodeKind.IntLiteralExpression(), false, 0)

    ConversionDirectCallAssertLiteralRejected(longSuffix, bindings)

    unsignedLongSuffix := ConversionDirectCallLiteralTree("DirectCallLiteralSpellingExclusions", "Take", "7UL", ColumnarExpressionNodeKind.IntLiteralExpression(), false, 0)

    ConversionDirectCallAssertLiteralRejected(unsignedLongSuffix, bindings)

    hexadecimal := ConversionDirectCallLiteralTree("DirectCallLiteralSpellingExclusions", "Take", "0x7", ColumnarExpressionNodeKind.IntLiteralExpression(), false, 0)

    ConversionDirectCallAssertLiteralRejected(hexadecimal, bindings)

    underscored := ConversionDirectCallLiteralTree("DirectCallLiteralSpellingExclusions", "Take", "1_0", ColumnarExpressionNodeKind.IntLiteralExpression(), false, 0)

    ConversionDirectCallAssertLiteralRejected(underscored, bindings)

    character := ConversionDirectCallLiteralTree("DirectCallLiteralSpellingExclusions", "Take", "'A'", ColumnarExpressionNodeKind.CharLiteralExpression(), false, 0)

    ConversionDirectCallAssertLiteralRejected(character, bindings)
}

test "integer literal overload ranking is identity numeric boxing then adoption" {
    owner := SourceCallDefinition("DirectCallLiteralRanking", true)
    intParameters := ConversionDirectCallOneType(typeof(int))
    longParameters := ConversionDirectCallOneType(typeof(long))
    objectParameters := ConversionDirectCallOneType(typeof(object))
    byteParameters := ConversionDirectCallOneType(typeof(byte))
    sbyteParameters := ConversionDirectCallOneType(typeof(sbyte))

    SourceCallPublicStatic(owner, "PreferInt", byteParameters, typeof(int))
    SourceCallPublicStatic(owner, "PreferInt", objectParameters, typeof(int))
    SourceCallPublicStatic(owner, "PreferInt", longParameters, typeof(int))
    SourceCallPublicStatic(owner, "PreferInt", intParameters, typeof(int))

    SourceCallPublicStatic(owner, "PreferLong", byteParameters, typeof(int))
    SourceCallPublicStatic(owner, "PreferLong", objectParameters, typeof(int))
    SourceCallPublicStatic(owner, "PreferLong", longParameters, typeof(int))

    SourceCallPublicStatic(owner, "PreferBox", byteParameters, typeof(int))
    SourceCallPublicStatic(owner, "PreferBox", objectParameters, typeof(int))

    SourceCallPublicStatic(owner, "Adopt", byteParameters, typeof(int))
    SourceCallPublicStatic(owner, "AdoptionTie", byteParameters, typeof(int))
    SourceCallPublicStatic(owner, "AdoptionTie", sbyteParameters, typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)
    intTree := DirectCallQualifiedTree("DirectCallLiteralRanking", "PreferInt", DirectCallOneText("7"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    intPlan := DirectCallPlan(intTree, bindings)
    intTarget := ConversionDirectCallTargetMethodIndex(intPlan)
    assert intPlan.MethodParameterTypes[intTarget][0] == typeof(int)
    ConversionDirectCallAssertLiteralValue(intPlan, typeof(int), 7)
    assert intPlan.OperationCount == 2
    assert !ConversionDirectCallHasOpcode(intPlan, ColumnarCodePlanContract.Box())

    longTree := DirectCallQualifiedTree("DirectCallLiteralRanking", "PreferLong", DirectCallOneText("7"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    longPlan := DirectCallPlan(longTree, bindings)
    longTarget := ConversionDirectCallTargetMethodIndex(longPlan)
    assert longPlan.MethodParameterTypes[longTarget][0] == typeof(long)
    ConversionDirectCallAssertLiteralValue(longPlan, typeof(long), 7)
    assert longPlan.OperationCount == 2

    boxTree := DirectCallQualifiedTree("DirectCallLiteralRanking", "PreferBox", DirectCallOneText("7"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    boxPlan := DirectCallPlan(boxTree, bindings)
    boxTarget := ConversionDirectCallTargetMethodIndex(boxPlan)
    assert boxPlan.MethodParameterTypes[boxTarget][0] == typeof(object)
    ConversionDirectCallAssertLiteralValue(boxPlan, typeof(object), 7)
    assert boxPlan.OperationCount == 3
    assert boxPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert boxPlan.OpCodeValues[1] == ColumnarCodePlanContract.Box()
    assert boxPlan.Types[boxPlan.OperandIndices[1]] == typeof(int)

    adoptionTree := DirectCallQualifiedTree("DirectCallLiteralRanking", "Adopt", DirectCallOneText("7"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    adoptionPlan := DirectCallPlan(adoptionTree, bindings)
    adoptionTarget := ConversionDirectCallTargetMethodIndex(adoptionPlan)
    assert adoptionPlan.MethodParameterTypes[adoptionTarget][0] == typeof(byte)
    ConversionDirectCallAssertLiteralValue(adoptionPlan, typeof(byte), 7)
    assert adoptionPlan.OperationCount == 2

    tieTree := DirectCallQualifiedTree("DirectCallLiteralRanking", "AdoptionTie", DirectCallOneText("7"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    ConversionDirectCallAssertLiteralRejected(tieTree, bindings)
}

test "direct-call conversion candidates roll back malformed declaration handles atomically" {
    owner := SourceCallDefinition("DirectCallMalformedConversion", true)
    target := SourceCallPublicStatic(owner, "Take", ConversionDirectCallOneType(typeof(long)), typeof(int))

    // This makes the source declaration metadata disagree with its exact MethodBuilder.
    // The int argument would otherwise append conv.i8, so this also protects the
    // conversion owner's outer transaction from malformed declaration facts.
    target.ReturnType = typeof(string)

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "value", 0, typeof(int))
    tree := DirectCallQualifiedTree("DirectCallMalformedConversion", "Take", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    plan := new ColumnarCodePlan()
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := false
    resultType := typeof(int)
    assert throws InvalidOperationException {
        ColumnarDirectCallPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
    }

    ColumnarRangePlannerAssertEmptyRollback(plan)
}
