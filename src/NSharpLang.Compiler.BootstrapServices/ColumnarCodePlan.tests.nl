namespace NSharpLang.Compiler.Columnar

import System

func ValidBooleanCodePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.Prepare()
    plan.AppendInstruction(ColumnarCodePlanContract.LdcI4_1())
    plan.CompleteBoolean()
    return plan
}

func SingleNodeTable(kind: int, textLength: int): ColumnarNodeTable {
    kinds := new int[](1)
    kinds[0] = kind
    valueStarts := new int[](1)
    valueLengths := new int[](1)
    valueLengths[0] = textLength
    childStarts := new int[](1)
    childCounts := new int[](1)
    return new ColumnarNodeTable(
        kinds,
        valueStarts,
        valueLengths,
        childStarts,
        childCounts,
        new int[](0))
}

test "boolean code-plan schema pins CLR opcode values" {
    // System.Reflection.Emit.OpCodes.Ldc_I4_0.Value == 0x16 and Ldc_I4_1.Value == 0x17.
    assert ColumnarCodePlanContract.LdcI4_0() == 22
    assert ColumnarCodePlanContract.LdcI4_1() == 23
}

test "boolean code-plan accepts its one sealed payload shape" {
    plan := ValidBooleanCodePlan()
    ColumnarCodePlanExecutor.Validate(plan)

    assert plan.SchemaVersion == 1
    assert plan.OperationCount == 1
    assert plan.OperationKinds[0] == ColumnarCodePlanContract.EmitInstructionOperation()
    assert plan.OperandKinds[0] == ColumnarCodePlanContract.NoOperand()
    assert plan.OpCodeValues[0] == 23
    assert plan.ResultType == typeof(bool)
}

test "boolean code-plan rejects schema and lifecycle corruption" {
    wrongSchema := ValidBooleanCodePlan()
    wrongSchema.SchemaVersion = 2
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(wrongSchema)
    }

    unsealed := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(unsealed)
    }

    wrongResult := ValidBooleanCodePlan()
    wrongResult.ResultType = typeof(int)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(wrongResult)
    }

    closedPlan := ValidBooleanCodePlan()
    assert throws InvalidOperationException {
        closedPlan.AppendInstruction(ColumnarCodePlanContract.LdcI4_0())
    }

    corruptBeforeSeal := new ColumnarCodePlan()
    corruptBeforeSeal.Prepare()
    corruptBeforeSeal.AppendInstruction(ColumnarCodePlanContract.LdcI4_1())
    corruptBeforeSeal.OperationKinds[0] = 99
    assert throws InvalidOperationException {
        corruptBeforeSeal.CompleteBoolean()
    }
}

test "boolean code-plan rejects row-count and column corruption" {
    zeroRows := ValidBooleanCodePlan()
    zeroRows.OperationCount = 0
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(zeroRows)
    }

    twoRows := ValidBooleanCodePlan()
    twoRows.OperationCount = 2
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(twoRows)
    }

    shortOperationColumn := ValidBooleanCodePlan()
    shortOperationColumn.OperationKinds = new int[](0)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(shortOperationColumn)
    }

    shortOpcodeColumn := ValidBooleanCodePlan()
    shortOpcodeColumn.OpCodeValues = new short[](0)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(shortOpcodeColumn)
    }

    shortOperandColumn := ValidBooleanCodePlan()
    shortOperandColumn.OperandKinds = new int[](0)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(shortOperandColumn)
    }
}

test "boolean code-plan rejects unknown operation operand and opcode values" {
    unknownOperation := ValidBooleanCodePlan()
    unknownOperation.OperationKinds[0] = 99
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(unknownOperation)
    }

    unknownOperand := ValidBooleanCodePlan()
    unknownOperand.OperandKinds[0] = 99
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(unknownOperand)
    }

    unknownOpcode := ValidBooleanCodePlan()
    unknownOpcode.OpCodeValues[0] = (short)24
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(unknownOpcode)
    }
}

test "boolean planner consumes the live parser node-kind ledger" {
    assert ColumnarExpressionNodeKind.BoolLiteralExpression() == 4

    plan := new ColumnarCodePlan()
    trueNodes := SingleNodeTable(ColumnarExpressionNodeKind.BoolLiteralExpression(), 4)
    assert ColumnarBooleanLiteralPlanner.Plan(trueNodes, "true", 0, plan)
        == ColumnarFragmentPlanStatus.Planned
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4_1()

    falseNodes := SingleNodeTable(ColumnarExpressionNodeKind.BoolLiteralExpression(), 5)
    assert ColumnarBooleanLiteralPlanner.Plan(falseNodes, "false", 0, plan)
        == ColumnarFragmentPlanStatus.Planned
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4_0()

    otherNodes := SingleNodeTable(0, 1)
    assert ColumnarBooleanLiteralPlanner.Plan(otherNodes, "1", 0, plan)
        == ColumnarFragmentPlanStatus.NotOwned
}

test "boolean planner rejects corrupt parser payloads" {
    plan := new ColumnarCodePlan()
    boolNodes := SingleNodeTable(ColumnarExpressionNodeKind.BoolLiteralExpression(), 5)

    assert throws InvalidOperationException {
        ColumnarBooleanLiteralPlanner.Plan(boolNodes, "truth", 0, plan)
    }
    assert throws InvalidOperationException {
        ColumnarBooleanLiteralPlanner.Plan(boolNodes, "truth", 1, plan)
    }
}

func OpenBooleanCodePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.Prepare()
    plan.AppendInstruction(ColumnarCodePlanContract.LdcI4_1())
    return plan
}

func ValidV2CodePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 100, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    return plan
}

func ValidNestedV2CodePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 100, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())

    firstChild := plan.BeginFragment(root, 101, 1)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.CompleteFragment(firstChild, typeof(int))

    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
    secondChild := plan.BeginFragment(root, 102, 2)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    plan.CompleteFragment(secondChild, typeof(int))
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())

    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    return plan
}

test "schema v2 pins only the callable Reflection Emit opcode wire values" {
    assert ColumnarCodePlanContract.LdcI4_M1() == 21
    assert ColumnarCodePlanContract.LdcI4_0() == 22
    assert ColumnarCodePlanContract.LdcI4_8() == 30
    assert ColumnarCodePlanContract.LdcI4() == 32
    assert ColumnarCodePlanContract.Ldarg() == -503
    assert ColumnarCodePlanContract.Ldloc() == -500
    assert ColumnarCodePlanContract.Ldloca() == -499
    assert ColumnarCodePlanContract.Stloc() == -498
    assert ColumnarCodePlanContract.Call() == 40
    assert ColumnarCodePlanContract.Br() == 56
    assert ColumnarCodePlanContract.Brfalse() == 57
    assert ColumnarCodePlanContract.ConvI4() == 105
    assert ColumnarCodePlanContract.Callvirt() == 111
    assert ColumnarCodePlanContract.Newobj() == 115
    assert ColumnarCodePlanContract.Ldfld() == 123
    assert ColumnarCodePlanContract.Ldlen() == 142
    assert ColumnarCodePlanContract.LdelemU1() == 145
    assert ColumnarCodePlanContract.LdelemU2() == 147
    assert ColumnarCodePlanContract.LdelemI4() == 148
    assert ColumnarCodePlanContract.LdelemU4() == 149
    assert ColumnarCodePlanContract.LdelemI8() == 150
    assert ColumnarCodePlanContract.LdelemR4() == 152
    assert ColumnarCodePlanContract.LdelemR8() == 153
    assert ColumnarCodePlanContract.LdelemRef() == 154
    assert ColumnarCodePlanContract.Ldelem() == 163
}

test "schema v2 lifecycle is explicit sealed and one shot" {
    empty := new ColumnarCodePlan()
    assert empty.Lifecycle == ColumnarCodePlanLifecycle.Empty

    plan := ValidV2CodePlan()
    assert plan.SchemaVersion == 2
    assert plan.Status == ColumnarFragmentPlanStatus.Planned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
    assert plan.FragmentKinds[0] == 100
    assert plan.FragmentSourceNodeIndices[0] == 0
    assert plan.OperationOwnerFragmentIndices[0] == 0
    plan.ValidateSealedStructure()

    plan.ConsumeV2()
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
    assert throws InvalidOperationException { plan.ConsumeV2() }
    assert throws InvalidOperationException {
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    }

    plan.Reset()
    assert plan.SchemaVersion == 1
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Empty
    assert plan.Status == ColumnarFragmentPlanStatus.NotOwned
    assert plan.OperationCount == 0
    assert plan.FragmentCount == 0
}

test "schema v2 grows every value column without losing flat ownership facts" {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 200, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())

    i := 0
    while i < 12 {
        typeIndex := plan.AddType(typeof(int))
        intIndex := plan.AddInt32(i)
        argumentIndex := plan.AddArgument(i, typeIndex)
        localIndex := plan.DeclarePlanLocal(typeIndex)
        labelIndex := plan.DefineLabel()
        assert typeIndex == i
        assert intIndex == i
        assert argumentIndex == i
        assert localIndex == i
        assert labelIndex == i

        child := plan.BeginFragment(root, 300 + i, i + 1)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
        plan.CompleteFragment(child, typeof(int))
        i += 1
    }

    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    plan.ValidateSealedStructure()

    assert plan.OperationCount == 14
    assert plan.FragmentCount == 13
    assert plan.TypeCount == 12
    assert plan.Int32Count == 12
    assert plan.ArgumentCount == 12
    assert plan.PlanLocalCount == 12
    assert plan.LabelCount == 12
    assert plan.OperationKinds.Length >= plan.OperationCount
    assert plan.OperationOwnerFragmentIndices.Length >= plan.OperationCount
    assert plan.FragmentKinds.Length >= plan.FragmentCount
    assert plan.ArgumentOrdinals[11] == 11
    assert plan.FragmentKinds[12] == 311
    assert plan.FragmentSourceNodeIndices[12] == 12
    assert plan.OperationOwnerFragmentIndices[12] == 12
}

test "schema v2 carries selected argument type method constructor and field pools" {
    noTypes := new Type[](0)
    method := typeof(string).GetMethod("get_Length", noTypes)
    ctorTypes := new Type[](2)
    ctorTypes[0] = typeof(int)
    ctorTypes[1] = typeof(bool)
    constructor := typeof(Index).GetConstructor(ctorTypes)
    field := typeof(ValueTuple<int, int>).GetField("Item1")
    if method == null || constructor == null || field == null {
        throw new InvalidOperationException("Required schema-v2 reflection handles were not found.")
    }

    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 400, 0)
    typeIndex := plan.AddType(typeof(int))
    intIndex := plan.AddInt32(42)
    argumentIndex := plan.AddArgument(0, typeIndex)
    localIndex := plan.DeclarePlanLocal(typeIndex)
    methodIndex := plan.AddMethod(method)
    constructorIndex := plan.AddConstructor(constructor)
    fieldIndex := plan.AddField(field)
    labelIndex := plan.DefineLabel()

    poolIndex := 1
    while poolIndex < 8 {
        assert plan.AddMethod(method) == poolIndex
        assert plan.AddConstructor(constructor) == poolIndex
        assert plan.AddField(field) == poolIndex
        poolIndex += 1
    }

    plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), intIndex)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), localIndex)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), localIndex)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), localIndex)
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodIndex)
    plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
    plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldIndex)
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), labelIndex)
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), labelIndex)
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldelem(), typeIndex)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemU1())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemU2())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemI4())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemU4())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemI8())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemR4())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemR8())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemRef())
    plan.AppendMarkLabel(labelIndex)
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    plan.ValidateSealedStructure()

    assert plan.ArgumentOrdinals[0] == 0
    assert plan.ArgumentTypeIndices[0] == typeIndex
    assert plan.MethodCount == 8
    assert plan.ConstructorCount == 8
    assert plan.FieldCount == 8
    assert plan.Methods.Length >= 8
    assert plan.Constructors.Length >= 8
    assert plan.Fields.Length >= 8
    assert plan.OperationKinds[20] == ColumnarCodePlanContract.MarkLabelOperation()
}

test "schema v2 append APIs reject mismatched or unavailable operands" {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 500, 0)
    typeIndex := plan.AddType(typeof(int))
    intIndex := plan.AddInt32(200)
    argumentIndex := plan.AddArgument(0, typeIndex)
    labelIndex := plan.DefineLabel()

    assert throws InvalidOperationException {
        plan.AppendInt32Instruction(ColumnarCodePlanContract.Call(), intIndex)
    }
    assert throws InvalidOperationException {
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldloc(), argumentIndex)
    }
    assert throws InvalidOperationException {
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldelem(), typeIndex + 1)
    }
    assert throws InvalidOperationException {
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), labelIndex + 1)
    }
    assert throws ArgumentNullException { plan.AddAmbientLocal(null) }
    assert throws ArgumentNullException { plan.AddMethod(null) }
    assert throws ArgumentNullException { plan.AddConstructor(null) }
    assert throws ArgumentNullException { plan.AddField(null) }

    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
}

test "schema v2 checkpoint rollback removes recursive partial state transactionally" {
    noTypes := new Type[](0)
    method := typeof(string).GetMethod("get_Length", noTypes)
    ctorTypes := new Type[](2)
    ctorTypes[0] = typeof(int)
    ctorTypes[1] = typeof(bool)
    constructor := typeof(Index).GetConstructor(ctorTypes)
    field := typeof(ValueTuple<int, int>).GetField("Item1")
    if method == null || constructor == null || field == null {
        throw new InvalidOperationException("Required schema-v2 reflection handles were not found.")
    }

    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 600, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    checkpoint := plan.CreateCheckpoint()

    typeIndex := plan.AddType(typeof(int))
    plan.AddInt32(7)
    plan.AddArgument(0, typeIndex)
    plan.DeclarePlanLocal(typeIndex)
    plan.DefineLabel()
    plan.AddMethod(method)
    plan.AddConstructor(constructor)
    plan.AddField(field)
    child := plan.BeginFragment(root, 601, 1)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.CompleteFragment(child, typeof(int))
    plan.CompleteFragment(root, typeof(int))
    assert plan.FragmentResultTypes[0] == typeof(int)

    plan.Rollback(checkpoint)
    assert plan.OperationCount == 1
    assert plan.TypeCount == 0
    assert plan.Int32Count == 0
    assert plan.ArgumentCount == 0
    assert plan.MethodCount == 0
    assert plan.ConstructorCount == 0
    assert plan.FieldCount == 0
    assert plan.PlanLocalCount == 0
    assert plan.LabelCount == 0
    assert plan.FragmentCount == 1
    assert !plan.FragmentCompleted[0]
    assert plan.FragmentResultTypes[0]
        == ColumnarCodePlanContract.UnsealedFragmentResultType()

    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    plan.ValidateSealedStructure()
}

test "schema v2 rejects foreign and stale checkpoints" {
    first := new ColumnarCodePlan()
    first.PrepareV2()
    first.BeginFragment(-1, 700, 0)
    checkpoint := first.CreateCheckpoint()

    second := new ColumnarCodePlan()
    second.PrepareV2()
    second.BeginFragment(-1, 701, 0)
    assert throws InvalidOperationException { second.Rollback(checkpoint) }

    first.Reset()
    first.PrepareV2()
    first.BeginFragment(-1, 702, 0)
    assert throws InvalidOperationException { first.Rollback(checkpoint) }

    branched := new ColumnarCodePlan()
    branched.PrepareV2()
    branchRoot := branched.BeginFragment(-1, 703, 0)
    branched.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    outer := branched.CreateCheckpoint()
    branched.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    discarded := branched.CreateCheckpoint()
    branched.Rollback(outer)
    branched.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    assert throws InvalidOperationException { branched.Rollback(discarded) }
    branched.Rollback(outer)
    branched.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
    branched.CompleteFragment(branchRoot, typeof(int))
    branched.CompleteV2(typeof(int))
}

test "schema v2 validates deeply nested fragment ownership linearly" {
    depth := 512
    fragmentIndices := new int[](depth)
    plan := new ColumnarCodePlan()
    plan.PrepareV2()

    currentParent := -1
    i := 0
    while i < depth {
        fragment := plan.BeginFragment(currentParent, 900 + i, i)
        fragmentIndices[i] = fragment
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
        currentParent = fragment
        i += 1
    }

    i = depth - 1
    while i >= 0 {
        if i < depth - 1 {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
        }
        plan.CompleteFragment(fragmentIndices[i], typeof(int))
        i -= 1
    }
    plan.CompleteV2(typeof(int))
    plan.ValidateSealedStructure()
    assert plan.FragmentCount == depth
    assert plan.OperationCount == depth * 2 - 1
}

test "schema v2 rejects corrupt columns pools and opcode operand pairings purely" {
    nullOwnerColumn := ValidV2CodePlan()
    nullOwnerColumn.OperationOwnerFragmentIndices = null
    assert throws InvalidOperationException { nullOwnerColumn.ValidateSealedStructure() }

    shortOwnerColumn := ValidV2CodePlan()
    shortOwnerColumn.OperationOwnerFragmentIndices = new int[](0)
    assert throws InvalidOperationException { shortOwnerColumn.ValidateSealedStructure() }

    unknownOperation := ValidV2CodePlan()
    unknownOperation.OperationKinds[0] = 99
    assert throws InvalidOperationException { unknownOperation.ValidateSealedStructure() }

    wrongOperand := ValidV2CodePlan()
    wrongOperand.OperandKinds[0] = ColumnarCodePlanContract.Int32Operand()
    wrongOperand.OperandIndices[0] = 0
    assert throws InvalidOperationException { wrongOperand.ValidateSealedStructure() }

    unknownOpcode := ValidV2CodePlan()
    unknownOpcode.OpCodeValues[0] = (short)31
    assert throws InvalidOperationException { unknownOpcode.ValidateSealedStructure() }

    corruptPool := ValidV2CodePlan()
    corruptPool.TypeCount = 1
    assert throws InvalidOperationException { corruptPool.ValidateSealedStructure() }

    building := new ColumnarCodePlan()
    building.PrepareV2()
    root := building.BeginFragment(-1, 800, 0)
    building.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    building.CompleteFragment(root, typeof(int))
    building.OperationKinds[0] = 99
    assert throws InvalidOperationException { building.CompleteV2(typeof(int)) }
    assert building.Lifecycle == ColumnarCodePlanLifecycle.Building
    assert building.Status == ColumnarFragmentPlanStatus.NotOwned
    assert building.ResultType == null
    assert building.OperationKinds[0] == 99
}

test "schema v2 rejects corrupt nested sibling and operation owner intervals" {
    equalParentInterval := ValidNestedV2CodePlan()
    equalParentInterval.FragmentOperationStarts[1] = 0
    equalParentInterval.FragmentOperationCounts[1] = equalParentInterval.OperationCount
    assert throws InvalidOperationException { equalParentInterval.ValidateSealedStructure() }

    outsideParent := ValidNestedV2CodePlan()
    outsideParent.FragmentOperationStarts[1] = outsideParent.OperationCount
    assert throws InvalidOperationException { outsideParent.ValidateSealedStructure() }

    overlappingSiblings := ValidNestedV2CodePlan()
    overlappingSiblings.FragmentOperationStarts[2] =
        overlappingSiblings.FragmentOperationStarts[1]
    assert throws InvalidOperationException { overlappingSiblings.ValidateSealedStructure() }

    corruptParent := ValidNestedV2CodePlan()
    corruptParent.FragmentParentIndices[1] = 1
    assert throws InvalidOperationException { corruptParent.ValidateSealedStructure() }

    corruptKind := ValidNestedV2CodePlan()
    corruptKind.FragmentKinds[1] = -1
    assert throws InvalidOperationException { corruptKind.ValidateSealedStructure() }

    corruptSource := ValidNestedV2CodePlan()
    corruptSource.FragmentSourceNodeIndices[1] = -1
    assert throws InvalidOperationException { corruptSource.ValidateSealedStructure() }

    unsealedResult := ValidNestedV2CodePlan()
    unsealedResult.FragmentResultTypes[1] =
        ColumnarCodePlanContract.UnsealedFragmentResultType()
    assert throws InvalidOperationException { unsealedResult.ValidateSealedStructure() }

    ancestorOwnsChildRow := ValidNestedV2CodePlan()
    ancestorOwnsChildRow.OperationOwnerFragmentIndices[1] = 0
    assert throws InvalidOperationException { ancestorOwnsChildRow.ValidateSealedStructure() }

    childOwnsParentRow := ValidNestedV2CodePlan()
    childOwnsParentRow.OperationOwnerFragmentIndices[0] = 1
    assert throws InvalidOperationException { childOwnsParentRow.ValidateSealedStructure() }

    unknownOwner := ValidNestedV2CodePlan()
    unknownOwner.OperationOwnerFragmentIndices[0] = 99
    assert throws InvalidOperationException { unknownOwner.ValidateSealedStructure() }
}

test "schema v1 rejects schema v2 row value and argument smuggling" {
    operandIndex := OpenBooleanCodePlan()
    operandIndex.OperandIndices[0] = 0
    assert throws InvalidOperationException { operandIndex.CompleteBoolean() }

    operationOwner := OpenBooleanCodePlan()
    operationOwner.OperationOwnerFragmentIndices[0] = 0
    assert throws InvalidOperationException { operationOwner.CompleteBoolean() }

    types := OpenBooleanCodePlan()
    types.TypeCount = 1
    assert throws InvalidOperationException { types.CompleteBoolean() }

    integers := OpenBooleanCodePlan()
    integers.Int32Count = 1
    assert throws InvalidOperationException { integers.CompleteBoolean() }

    arguments := OpenBooleanCodePlan()
    arguments.ArgumentCount = 1
    assert throws InvalidOperationException { arguments.CompleteBoolean() }

    ambientLocals := OpenBooleanCodePlan()
    ambientLocals.AmbientLocalCount = 1
    assert throws InvalidOperationException { ambientLocals.CompleteBoolean() }
}

test "schema v1 rejects schema v2 handle local label and fragment smuggling" {
    methods := OpenBooleanCodePlan()
    methods.MethodCount = 1
    assert throws InvalidOperationException { methods.CompleteBoolean() }

    constructors := OpenBooleanCodePlan()
    constructors.ConstructorCount = 1
    assert throws InvalidOperationException { constructors.CompleteBoolean() }

    fields := OpenBooleanCodePlan()
    fields.FieldCount = 1
    assert throws InvalidOperationException { fields.CompleteBoolean() }
}

test "schema v1 rejects schema v2 local label fragment and sealed smuggling" {
    planLocals := OpenBooleanCodePlan()
    planLocals.PlanLocalCount = 1
    assert throws InvalidOperationException { planLocals.CompleteBoolean() }

    labels := OpenBooleanCodePlan()
    labels.LabelCount = 1
    assert throws InvalidOperationException { labels.CompleteBoolean() }

    fragments := OpenBooleanCodePlan()
    fragments.FragmentCount = 1
    assert throws InvalidOperationException { fragments.CompleteBoolean() }

    sealedPlan := ValidBooleanCodePlan()
    sealedPlan.ArgumentCount = 1
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(sealedPlan) }
}
