namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection

public class ColumnarCodePlanVoidProbe {
    public static func Nothing() {}
}

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

    otherNodes := SingleNodeTable(ColumnarExpressionNodeKind.IntLiteralExpression(), 1)
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

func CodePlanRequiredParameterlessVoidMethod(): MethodInfo {
    method := typeof(ColumnarCodePlanVoidProbe).GetMethod("Nothing")
    if method == null {
        throw new InvalidOperationException(
            "Required parameterless void method was not found.")
    }
    return method
}

func CodePlanVoidType(): Type {
    return CodePlanRequiredParameterlessVoidMethod().get_ReturnType()
}

func ValidV3VoidCodePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 103, 0)
    method := plan.AddMethod(CodePlanRequiredParameterlessVoidMethod())
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), method)
    plan.CompleteFragment(root, CodePlanVoidType())
    plan.CompleteV3(CodePlanVoidType())
    return plan
}

test "recursive schemas pin only callable Reflection Emit opcode wire values" {
    assert ColumnarCodePlanContract.LdcI4_M1() == 21
    assert ColumnarCodePlanContract.LdcI4_0() == 22
    assert ColumnarCodePlanContract.LdcI4_8() == 30
    assert ColumnarCodePlanContract.LdcI4() == 32
    assert ColumnarCodePlanContract.Dup() == 37
    assert ColumnarCodePlanContract.Ldarg() == -503
    assert ColumnarCodePlanContract.Ldarga() == -502
    assert ColumnarCodePlanContract.Ldloc() == -500
    assert ColumnarCodePlanContract.Ldloca() == -499
    assert ColumnarCodePlanContract.Stloc() == -498
    assert ColumnarCodePlanContract.Call() == 40
    assert ColumnarCodePlanContract.Br() == 56
    assert ColumnarCodePlanContract.Brfalse() == 57
    assert ColumnarCodePlanContract.Brtrue() == 58
    assert ColumnarCodePlanContract.ConvI4() == 105
    assert ColumnarCodePlanContract.Callvirt() == 111
    assert ColumnarCodePlanContract.Newobj() == 115
    assert ColumnarCodePlanContract.Ldfld() == 123
    assert ColumnarCodePlanContract.Stfld() == 125
    assert ColumnarCodePlanContract.Ldsfld() == 126
    assert ColumnarCodePlanContract.Newarr() == 141
    assert ColumnarCodePlanContract.Ldlen() == 142
    assert ColumnarCodePlanContract.LdelemU1() == 145
    assert ColumnarCodePlanContract.LdelemU2() == 147
    assert ColumnarCodePlanContract.LdelemI4() == 148
    assert ColumnarCodePlanContract.LdelemU4() == 149
    assert ColumnarCodePlanContract.LdelemI8() == 150
    assert ColumnarCodePlanContract.LdelemR4() == 152
    assert ColumnarCodePlanContract.LdelemR8() == 153
    assert ColumnarCodePlanContract.LdelemRef() == 154
    assert ColumnarCodePlanContract.StelemI1() == 156
    assert ColumnarCodePlanContract.StelemI2() == 157
    assert ColumnarCodePlanContract.StelemI4() == 158
    assert ColumnarCodePlanContract.StelemI8() == 159
    assert ColumnarCodePlanContract.StelemR4() == 160
    assert ColumnarCodePlanContract.StelemR8() == 161
    assert ColumnarCodePlanContract.StelemRef() == 162
    assert ColumnarCodePlanContract.Ldelem() == 163
    assert ColumnarCodePlanContract.Stelem() == 164
    assert ColumnarCodePlanContract.Ldtoken() == 208
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
    assert plan.ArgumentIsAddress.Length >= plan.ArgumentCount
    assert !plan.ArgumentIsAddress[11]
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
    assert plan.MethodUsesDeclaredSignature.Length >= 8
    assert plan.MethodDeclaringTypes.Length >= 8
    assert plan.MethodReturnTypes.Length >= 8
    assert plan.MethodParameterTypes.Length >= 8
    assert plan.MethodIsStatic.Length >= 8
    assert plan.MethodIsAbstract.Length >= 8
    assert plan.Constructors.Length >= 8
    assert plan.Fields.Length >= 8
    assert plan.FieldUsesDeclaredSignature.Length >= 8
    assert plan.FieldDeclaringTypes.Length >= 8
    assert plan.FieldValueTypes.Length >= 8
    assert plan.FieldIsStatic.Length >= 8
    assert !plan.FieldUsesDeclaredSignature[7]
    assert plan.OperationKinds[20] == ColumnarCodePlanContract.MarkLabelOperation()
}

test "schema v2 append APIs reject mismatched or unavailable operands" {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 500, 0)
    typeIndex := plan.AddType(typeof(int))
    intIndex := plan.AddInt32(200)
    argumentIndex := plan.AddArgument(0, typeIndex)
    addressArgumentIndex := plan.AddArgument(1, typeIndex, true)
    labelIndex := plan.DefineLabel()

    assert throws InvalidOperationException {
        plan.AppendInt32Instruction(ColumnarCodePlanContract.Call(), intIndex)
    }
    assert throws InvalidOperationException {
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldloc(), argumentIndex)
    }
    assert throws InvalidOperationException {
        plan.AppendArgumentInstruction(
            ColumnarCodePlanContract.Ldarga(), addressArgumentIndex)
    }
    assert throws InvalidOperationException {
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldelem(), typeIndex + 1)
    }
    operationCountBeforeLdtoken := plan.OperationCount
    assert throws InvalidOperationException {
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldtoken(), typeIndex)
    }
    assert plan.OperationCount == operationCountBeforeLdtoken
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

test "schema v3 admits exact ldtoken type operands only" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 501, 0)
    typeIndex := plan.AddType(typeof(string))
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldtoken(), typeIndex)
    plan.CompleteFragment(root, typeof(RuntimeTypeHandle))
    plan.CompleteV3(typeof(RuntimeTypeHandle))
    plan.ValidateSealedStructure()

    assert plan.OperandKinds[0] == ColumnarCodePlanContract.TypeOperand()
    assert plan.OperandIndices[0] == typeIndex

    invalid := new ColumnarCodePlan()
    invalid.PrepareV3()
    invalid.BeginFragment(-1, 502, 0)
    invalidType := invalid.AddType(typeof(string))
    operationCountBeforeWrongOpcode := invalid.OperationCount
    assert throws InvalidOperationException {
        invalid.AppendTypeInstruction(ColumnarCodePlanContract.Call(), invalidType)
    }
    assert invalid.OperationCount == operationCountBeforeWrongOpcode
    operationCountBeforeWrongIndex := invalid.OperationCount
    assert throws InvalidOperationException {
        invalid.AppendTypeInstruction(ColumnarCodePlanContract.Ldtoken(), invalidType + 1)
    }
    assert invalid.OperationCount == operationCountBeforeWrongIndex
}

test "schema v3 admits exact array allocation duplication and store rows" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 520, 0)
    typeIndex := plan.AddType(typeof(int))

    plan.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), typeIndex)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI1())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI2())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI4())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI8())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemR4())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemR8())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemRef())
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Stelem(), typeIndex)
    plan.CompleteFragment(root, typeof(int[]))
    plan.CompleteV3(typeof(int[]))
    plan.ValidateSealedStructure()

    assert plan.OperationCount == 10
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Newarr()
    assert plan.OperandKinds[0] == ColumnarCodePlanContract.TypeOperand()
    assert plan.OperandIndices[0] == typeIndex
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Dup()
    assert plan.OperandKinds[1] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[1] == -1
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.StelemI1()
    assert plan.OperandKinds[2] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[2] == -1
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.StelemI2()
    assert plan.OperandKinds[3] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[3] == -1
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.StelemI4()
    assert plan.OperandKinds[4] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[4] == -1
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.StelemI8()
    assert plan.OperandKinds[5] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[5] == -1
    assert plan.OpCodeValues[6] == ColumnarCodePlanContract.StelemR4()
    assert plan.OperandKinds[6] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[6] == -1
    assert plan.OpCodeValues[7] == ColumnarCodePlanContract.StelemR8()
    assert plan.OperandKinds[7] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[7] == -1
    assert plan.OpCodeValues[8] == ColumnarCodePlanContract.StelemRef()
    assert plan.OperandKinds[8] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[8] == -1
    assert plan.OpCodeValues[9] == ColumnarCodePlanContract.Stelem()
    assert plan.OperandKinds[9] == ColumnarCodePlanContract.TypeOperand()
    assert plan.OperandIndices[9] == typeIndex

    invalid := new ColumnarCodePlan()
    invalid.PrepareV3()
    invalid.BeginFragment(-1, 521, 0)
    invalidType := invalid.AddType(typeof(int))
    operationCount := invalid.OperationCount
    assert throws InvalidOperationException {
        invalid.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Newarr())
    }
    assert throws InvalidOperationException {
        invalid.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Stelem())
    }
    assert throws InvalidOperationException {
        invalid.AppendTypeInstruction(ColumnarCodePlanContract.Dup(), invalidType)
    }
    assert throws InvalidOperationException {
        invalid.AppendTypeInstruction(ColumnarCodePlanContract.StelemI4(), invalidType)
    }
    assert throws InvalidOperationException {
        invalid.AppendTypeInstruction(
            ColumnarCodePlanContract.Newarr(), invalidType + 1)
    }
    assert throws InvalidOperationException {
        invalid.AppendTypeInstruction(
            ColumnarCodePlanContract.Stelem(), invalidType + 1)
    }
    assert invalid.OperationCount == operationCount
}

test "schema v1 and v2 fence schema v3 array rows from append and tamper paths" {
    schemaV1 := new ColumnarCodePlan()
    schemaV1.Prepare()
    assert throws InvalidOperationException {
        schemaV1.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
    }
    assert throws InvalidOperationException {
        schemaV1.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), 0)
    }
    assert schemaV1.OperationCount == 0
    schemaV1.AppendInstruction(ColumnarCodePlanContract.LdcI4_1())
    schemaV1.CompleteBoolean()

    tamperedV1 := ValidBooleanCodePlan()
    tamperedV1.OpCodeValues[0] = ColumnarCodePlanContract.Dup()
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(tamperedV1)
    }
    tamperedV1.OpCodeValues[0] = ColumnarCodePlanContract.LdcI4_1()
    ColumnarCodePlanExecutor.Validate(tamperedV1)
    tamperedV1.OpCodeValues[0] = ColumnarCodePlanContract.Newarr()
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(tamperedV1)
    }
    tamperedV1.OpCodeValues[0] = ColumnarCodePlanContract.LdcI4_1()
    ColumnarCodePlanExecutor.Validate(tamperedV1)

    schemaV2 := new ColumnarCodePlan()
    schemaV2.PrepareV2()
    v2Root := schemaV2.BeginFragment(-1, 522, 0)
    v2Type := schemaV2.AddType(typeof(int))
    operationCount := schemaV2.OperationCount
    assert throws InvalidOperationException {
        schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
    }
    assert throws InvalidOperationException {
        schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI1())
    }
    assert throws InvalidOperationException {
        schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI2())
    }
    assert throws InvalidOperationException {
        schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI4())
    }
    assert throws InvalidOperationException {
        schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI8())
    }
    assert throws InvalidOperationException {
        schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemR4())
    }
    assert throws InvalidOperationException {
        schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemR8())
    }
    assert throws InvalidOperationException {
        schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemRef())
    }
    assert throws InvalidOperationException {
        schemaV2.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), v2Type)
    }
    assert throws InvalidOperationException {
        schemaV2.AppendTypeInstruction(ColumnarCodePlanContract.Stelem(), v2Type)
    }
    assert schemaV2.OperationCount == operationCount
    schemaV2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    schemaV2.CompleteFragment(v2Root, typeof(int))
    schemaV2.CompleteV2(typeof(int))
    schemaV2.ValidateSealedStructure()

    tamperedNoOperandV2 := ValidV2CodePlan()
    tamperedNoOperandV2.OpCodeValues[0] = ColumnarCodePlanContract.Dup()
    assert throws InvalidOperationException {
        tamperedNoOperandV2.ValidateSealedStructure()
    }
    tamperedNoOperandV2.OpCodeValues[0] = ColumnarCodePlanContract.LdcI4_0()
    tamperedNoOperandV2.ValidateSealedStructure()
    tamperedNoOperandV2.OpCodeValues[0] = ColumnarCodePlanContract.StelemRef()
    assert throws InvalidOperationException {
        tamperedNoOperandV2.ValidateSealedStructure()
    }
    tamperedNoOperandV2.OpCodeValues[0] = ColumnarCodePlanContract.LdcI4_0()
    tamperedNoOperandV2.ValidateSealedStructure()

    tamperedTypeV2 := new ColumnarCodePlan()
    tamperedTypeV2.PrepareV2()
    tamperedRoot := tamperedTypeV2.BeginFragment(-1, 523, 0)
    tamperedType := tamperedTypeV2.AddType(typeof(int))
    tamperedTypeV2.AppendTypeInstruction(
        ColumnarCodePlanContract.Ldelem(), tamperedType)
    tamperedTypeV2.CompleteFragment(tamperedRoot, typeof(int))
    tamperedTypeV2.CompleteV2(typeof(int))
    tamperedTypeV2.OpCodeValues[0] = ColumnarCodePlanContract.Newarr()
    assert throws InvalidOperationException {
        tamperedTypeV2.ValidateSealedStructure()
    }
    tamperedTypeV2.OpCodeValues[0] = ColumnarCodePlanContract.Ldelem()
    tamperedTypeV2.ValidateSealedStructure()
    tamperedTypeV2.OpCodeValues[0] = ColumnarCodePlanContract.Stelem()
    assert throws InvalidOperationException {
        tamperedTypeV2.ValidateSealedStructure()
    }
    tamperedTypeV2.OpCodeValues[0] = ColumnarCodePlanContract.Ldelem()
    tamperedTypeV2.ValidateSealedStructure()
}

test "schema v3 checkpoint rollback removes array rows and type operands transactionally" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 524, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    checkpoint := plan.CreateCheckpoint()

    typeIndex := plan.AddType(typeof(int))
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), typeIndex)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI4())
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Stelem(), typeIndex)
    assert plan.OperationCount == 5
    assert plan.TypeCount == 1

    plan.Rollback(checkpoint)
    assert plan.OperationCount == 1
    assert plan.TypeCount == 0
    assert !plan.FragmentCompleted[root]

    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))
    plan.ValidateSealedStructure()
}

test "schema v3 rejects corrupt array opcode and operand pairings purely" {
    typed := new ColumnarCodePlan()
    typed.PrepareV3()
    typedRoot := typed.BeginFragment(-1, 525, 0)
    typedIndex := typed.AddType(typeof(int))
    typed.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), typedIndex)
    typed.CompleteFragment(typedRoot, typeof(int[]))
    typed.CompleteV3(typeof(int[]))

    typed.OperandKinds[0] = ColumnarCodePlanContract.NoOperand()
    typed.OperandIndices[0] = -1
    assert throws InvalidOperationException { typed.ValidateSealedStructure() }
    typed.OperandKinds[0] = ColumnarCodePlanContract.TypeOperand()
    typed.OperandIndices[0] = typedIndex
    typed.ValidateSealedStructure()
    typed.OperandIndices[0] = typedIndex + 1
    assert throws InvalidOperationException { typed.ValidateSealedStructure() }
    typed.OperandIndices[0] = typedIndex
    typed.ValidateSealedStructure()
    typed.OpCodeValues[0] = ColumnarCodePlanContract.Dup()
    assert throws InvalidOperationException { typed.ValidateSealedStructure() }
    typed.OpCodeValues[0] = ColumnarCodePlanContract.Newarr()
    typed.ValidateSealedStructure()

    fixed := new ColumnarCodePlan()
    fixed.PrepareV3()
    fixedRoot := fixed.BeginFragment(-1, 526, 0)
    fixedType := fixed.AddType(typeof(int))
    fixed.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI4())
    fixed.CompleteFragment(fixedRoot, typeof(int))
    fixed.CompleteV3(typeof(int))

    fixed.OperandKinds[0] = ColumnarCodePlanContract.TypeOperand()
    fixed.OperandIndices[0] = fixedType
    assert throws InvalidOperationException { fixed.ValidateSealedStructure() }
    fixed.OperandKinds[0] = ColumnarCodePlanContract.NoOperand()
    fixed.OperandIndices[0] = -1
    fixed.ValidateSealedStructure()
    fixed.OpCodeValues[0] = ColumnarCodePlanContract.Stelem()
    assert throws InvalidOperationException { fixed.ValidateSealedStructure() }
    fixed.OpCodeValues[0] = ColumnarCodePlanContract.StelemI4()
    fixed.ValidateSealedStructure()
}

test "schema v3 structure admits void only as the root fragment result" {
    valid := ValidV3VoidCodePlan()
    valid.ValidateSealedStructure()
    assert valid.ResultType == CodePlanVoidType()
    assert valid.FragmentResultTypes[0] == CodePlanVoidType()

    schemaV2 := new ColumnarCodePlan()
    schemaV2.PrepareV2()
    v2Root := schemaV2.BeginFragment(-1, 505, 0)
    v2Method := schemaV2.AddMethod(CodePlanRequiredParameterlessVoidMethod())
    schemaV2.AppendMethodInstruction(ColumnarCodePlanContract.Call(), v2Method)
    assert throws InvalidOperationException {
        schemaV2.CompleteFragment(v2Root, CodePlanVoidType())
    }
    assert !schemaV2.FragmentCompleted[v2Root]

    nested := new ColumnarCodePlan()
    nested.PrepareV3()
    nestedRoot := nested.BeginFragment(-1, 506, 0)
    nestedChild := nested.BeginFragment(nestedRoot, 507, 1)
    nestedMethod := nested.AddMethod(CodePlanRequiredParameterlessVoidMethod())
    nested.AppendMethodInstruction(ColumnarCodePlanContract.Call(), nestedMethod)
    assert throws InvalidOperationException {
        nested.CompleteFragment(nestedChild, CodePlanVoidType())
    }
    assert !nested.FragmentCompleted[nestedChild]
}

test "sealed schema v3 rejects corrupt void fragment and root result relationships" {
    voidRootWithNonvoidResult := ValidV3VoidCodePlan()
    voidRootWithNonvoidResult.ResultType = typeof(int)
    assert throws InvalidOperationException {
        voidRootWithNonvoidResult.ValidateSealedStructure()
    }

    nonvoidRootWithVoidResult := new ColumnarCodePlan()
    nonvoidRootWithVoidResult.PrepareV3()
    nonvoidRoot := nonvoidRootWithVoidResult.BeginFragment(-1, 508, 0)
    nonvoidRootWithVoidResult.AppendInstructionWithoutOperand(
        ColumnarCodePlanContract.LdcI4_1())
    nonvoidRootWithVoidResult.CompleteFragment(nonvoidRoot, typeof(int))
    nonvoidRootWithVoidResult.CompleteV3(typeof(int))
    nonvoidRootWithVoidResult.ResultType = CodePlanVoidType()
    assert throws InvalidOperationException {
        nonvoidRootWithVoidResult.ValidateSealedStructure()
    }

    nestedVoid := new ColumnarCodePlan()
    nestedVoid.PrepareV3()
    root := nestedVoid.BeginFragment(-1, 509, 0)
    nestedVoid.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    child := nestedVoid.BeginFragment(root, 510, 1)
    nestedVoid.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    nestedVoid.CompleteFragment(child, typeof(int))
    nestedVoid.CompleteFragment(root, typeof(int))
    nestedVoid.CompleteV3(typeof(int))
    nestedVoid.FragmentResultTypes[child] = CodePlanVoidType()
    assert throws InvalidOperationException { nestedVoid.ValidateSealedStructure() }
}

test "sealed recursive schemas reject ldtoken version and operand corruption" {
    schemaV2 := new ColumnarCodePlan()
    schemaV2.PrepareV2()
    v2Root := schemaV2.BeginFragment(-1, 503, 0)
    v2Type := schemaV2.AddType(typeof(int))
    schemaV2.AppendTypeInstruction(ColumnarCodePlanContract.Ldelem(), v2Type)
    schemaV2.CompleteFragment(v2Root, typeof(int))
    schemaV2.CompleteV2(typeof(int))
    schemaV2.OpCodeValues[0] = ColumnarCodePlanContract.Ldtoken()
    assert throws InvalidOperationException { schemaV2.ValidateSealedStructure() }

    wrongOperand := new ColumnarCodePlan()
    wrongOperand.PrepareV3()
    v3Root := wrongOperand.BeginFragment(-1, 504, 0)
    v3Type := wrongOperand.AddType(typeof(string))
    wrongOperand.AppendTypeInstruction(ColumnarCodePlanContract.Ldtoken(), v3Type)
    wrongOperand.CompleteFragment(v3Root, typeof(RuntimeTypeHandle))
    wrongOperand.CompleteV3(typeof(RuntimeTypeHandle))
    wrongOperand.OperandKinds[0] = ColumnarCodePlanContract.Int32Operand()
    assert throws InvalidOperationException { wrongOperand.ValidateSealedStructure() }
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

func OpenV3CodePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1200, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    plan.CompleteFragment(root, typeof(int))
    return plan
}

func ValidV3CodePlan(): ColumnarCodePlan {
    plan := OpenV3CodePlan()
    plan.CompleteV3(typeof(int))
    return plan
}

func ValidInt64V3CodePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1209, 0)
    valueIndex := plan.AddInt64((long)1)
    plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
    plan.CompleteFragment(root, typeof(long))
    plan.CompleteV3(typeof(long))
    return plan
}

test "schema v3 pins its envelope and has a sealed one-shot lifecycle" {
    assert ColumnarCodePlanContract.ScalarSchemaVersion() == 3
    assert ColumnarCodePlanContract.LdcI8() == 33
    assert ColumnarCodePlanContract.LdcR4() == 34
    assert ColumnarCodePlanContract.LdcR8() == 35
    assert ColumnarCodePlanContract.Ldstr() == 114
    assert ColumnarCodePlanContract.Add() == 88
    assert ColumnarCodePlanContract.Neg() == 101
    assert ColumnarCodePlanContract.Not() == 102
    assert ColumnarCodePlanContract.Ceq() == -511
    // The typed byref-dereference family carries its exact single-byte ECMA-335 III.3.42 encodings:
    // ldind.i1=0x46 (70) through ldind.r8=0x4F (79), with ldind.i (0x4D, 77) omitted, then
    // ldind.ref=0x50 (80).
    assert ColumnarCodePlanContract.LdindI1() == 70
    assert ColumnarCodePlanContract.LdindU1() == 71
    assert ColumnarCodePlanContract.LdindI2() == 72
    assert ColumnarCodePlanContract.LdindU2() == 73
    assert ColumnarCodePlanContract.LdindI4() == 74
    assert ColumnarCodePlanContract.LdindU4() == 75
    assert ColumnarCodePlanContract.LdindI8() == 76
    assert ColumnarCodePlanContract.LdindR4() == 78
    assert ColumnarCodePlanContract.LdindR8() == 79
    assert ColumnarCodePlanContract.LdindRef() == 80
    assert ColumnarCodePlanContract.IsScalarNoOperandOpcode(
        ColumnarCodePlanContract.LdindI1())
    assert ColumnarCodePlanContract.IsScalarNoOperandOpcode(
        ColumnarCodePlanContract.LdindR8())
    assert ColumnarCodePlanContract.Int64Operand() == 10
    assert ColumnarCodePlanContract.SingleOperand() == 11
    assert ColumnarCodePlanContract.DoubleOperand() == 12
    assert ColumnarCodePlanContract.StringOperand() == 13

    plan := ValidV3CodePlan()
    assert plan.SchemaVersion == 3
    assert plan.Status == ColumnarFragmentPlanStatus.Planned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
    plan.ValidateSealedStructure()

    plan.ConsumeV3()
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
    assert throws InvalidOperationException { plan.ConsumeV3() }
    assert throws InvalidOperationException { plan.ConsumeV2() }
    assert throws InvalidOperationException { plan.AddInt64((long)1) }

    plan.Reset()
    assert plan.SchemaVersion == ColumnarCodePlanContract.CurrentSchemaVersion()
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Empty
    assert plan.Int64Count == 0
    assert plan.SingleCount == 0
    assert plan.DoubleCount == 0
    assert plan.StringCount == 0
    assert plan.Int64Values != null
    assert plan.SingleValues != null
    assert plan.DoubleValues != null
    assert plan.StringValues != null
}

test "schema v3 admits the exact Add row and keeps it isolated from schema v2" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1216, 0)
    left := plan.BeginFragment(root, 0, 1)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.CompleteFragment(left, typeof(int))
    right := plan.BeginFragment(root, 0, 2)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.CompleteFragment(right, typeof(int))
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Add())
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Add()
    assert plan.OperandKinds[2] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[2] == -1
    plan.ValidateSealedStructure()
    ColumnarCodePlanExecutor.Validate(plan)

    v2Builder := new ColumnarCodePlan()
    v2Builder.PrepareV2()
    _v2Root := v2Builder.BeginFragment(-1, 1217, 0)
    assert throws InvalidOperationException {
        v2Builder.AppendInstructionWithoutOperand(
            ColumnarCodePlanContract.Add())
    }
    assert v2Builder.OperationCount == 0

    smuggled := ValidV2CodePlan()
    smuggled.OpCodeValues[0] = ColumnarCodePlanContract.Add()
    assert throws InvalidOperationException {
        smuggled.ValidateSealedStructure()
    }
}

test "schema v3 carries exact managed-address arguments into ldind.ref" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1215, 0)
    stringType := plan.AddType(typeof(string))
    addressArgument := plan.AddArgument(0, stringType, true)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), addressArgument)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdindRef())
    plan.CompleteFragment(root, typeof(string))
    plan.CompleteV3(typeof(string))
    plan.ValidateSealedStructure()

    assert plan.ArgumentIsAddress[0]
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OperandKinds[0] == ColumnarCodePlanContract.ArgumentOperand()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdindRef()
    assert plan.OperandKinds[1] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[1] == -1
}

test "ldind.ref remains scalar-only and rejected appends are atomic" {
    recursive := new ColumnarCodePlan()
    recursive.PrepareV2()
    recursive.BeginFragment(-1, 1216, 0)
    stringType := recursive.AddType(typeof(string))
    addressArgument := recursive.AddArgument(0, stringType, true)
    recursive.AppendArgumentInstruction(
        ColumnarCodePlanContract.Ldarg(), addressArgument)
    operationCount := recursive.OperationCount

    assert throws InvalidOperationException {
        recursive.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdindRef())
    }
    assert recursive.OperationCount == operationCount

    smuggled := new ColumnarCodePlan()
    smuggled.PrepareV3()
    root := smuggled.BeginFragment(-1, 1217, 0)
    smuggledStringType := smuggled.AddType(typeof(string))
    smuggledArgument := smuggled.AddArgument(0, smuggledStringType, true)
    smuggled.AppendArgumentInstruction(
        ColumnarCodePlanContract.Ldarg(), smuggledArgument)
    smuggled.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdindRef())
    smuggled.CompleteFragment(root, typeof(string))
    smuggled.CompleteV3(typeof(string))
    smuggled.SchemaVersion = ColumnarCodePlanContract.RecursiveSchemaVersion()
    assert throws InvalidOperationException { smuggled.ValidateSealedStructure() }
}

test "schema v3 grows every scalar pool without losing values" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()

    i := 0
    while i < 12 {
        assert plan.AddInt64((long)i) == i
        assert plan.AddSingle((float)i + (float)0.25) == i
        assert plan.AddDouble((double)i + 0.5) == i
        assert plan.AddString("scalar") == i
        i += 1
    }

    assert plan.Int64Count == 12
    assert plan.SingleCount == 12
    assert plan.DoubleCount == 12
    assert plan.StringCount == 12
    assert plan.Int64Values.Length >= 12
    assert plan.SingleValues.Length >= 12
    assert plan.DoubleValues.Length >= 12
    assert plan.StringValues.Length >= 12
    assert plan.Int64Values[11] == (long)11
    assert plan.SingleValues[11] == (float)11 + (float)0.25
    assert plan.DoubleValues[11] == (double)11 + 0.5
    assert plan.StringValues[11] == "scalar"
    assert throws ArgumentNullException { plan.AddString(null) }
}

test "schema v3 checkpoint rollback restores every scalar pool transactionally" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1201, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    checkpoint := plan.CreateCheckpoint()

    plan.AddInt64((long)7)
    plan.AddSingle((float)1.25)
    plan.AddDouble(2.5)
    plan.AddString("discarded")
    child := plan.BeginFragment(root, 1202, 1)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.CompleteFragment(child, typeof(int))
    plan.CompleteFragment(root, typeof(int))

    plan.Rollback(checkpoint)
    assert plan.Int64Count == 0
    assert plan.SingleCount == 0
    assert plan.DoubleCount == 0
    assert plan.StringCount == 0
    assert plan.Int64Values.Length >= 4
    assert plan.SingleValues.Length >= 4
    assert plan.DoubleValues.Length >= 4
    assert plan.StringValues.Length >= 4
    assert plan.OperationCount == 1
    assert plan.FragmentCount == 1
    assert !plan.FragmentCompleted[0]

    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))
    plan.ValidateSealedStructure()
}

test "schema v3 rejects stale foreign and cross-version checkpoints" {
    first := new ColumnarCodePlan()
    first.PrepareV3()
    first.BeginFragment(-1, 1203, 0)
    checkpoint := first.CreateCheckpoint()

    second := new ColumnarCodePlan()
    second.PrepareV3()
    second.BeginFragment(-1, 1204, 0)
    assert throws InvalidOperationException { second.Rollback(checkpoint) }

    first.Reset()
    first.PrepareV3()
    first.BeginFragment(-1, 1205, 0)
    assert throws InvalidOperationException { first.Rollback(checkpoint) }

    crossVersion := new ColumnarCodePlan()
    crossVersion.PrepareV3()
    crossVersion.BeginFragment(-1, 1206, 0)
    v3Checkpoint := crossVersion.CreateCheckpoint()
    crossVersion.SchemaVersion = ColumnarCodePlanContract.RecursiveSchemaVersion()
    assert throws InvalidOperationException { crossVersion.Rollback(v3Checkpoint) }

    reverse := new ColumnarCodePlan()
    reverse.PrepareV2()
    reverse.BeginFragment(-1, 1207, 0)
    v2Checkpoint := reverse.CreateCheckpoint()
    reverse.SchemaVersion = ColumnarCodePlanContract.ScalarSchemaVersion()
    assert throws InvalidOperationException { reverse.Rollback(v2Checkpoint) }
}

test "schema v3 rejects every corrupt scalar pool column purely" {
    int64Column := ValidV3CodePlan()
    int64Column.Int64Values = null
    assert throws InvalidOperationException { int64Column.ValidateSealedStructure() }

    singleColumn := ValidV3CodePlan()
    singleColumn.SingleValues = null
    assert throws InvalidOperationException { singleColumn.ValidateSealedStructure() }

    doubleColumn := ValidV3CodePlan()
    doubleColumn.DoubleValues = null
    assert throws InvalidOperationException { doubleColumn.ValidateSealedStructure() }

    stringColumn := ValidV3CodePlan()
    stringColumn.StringValues = null
    assert throws InvalidOperationException { stringColumn.ValidateSealedStructure() }

    negativeCount := ValidV3CodePlan()
    negativeCount.Int64Count = -1
    assert throws InvalidOperationException { negativeCount.ValidateSealedStructure() }

    negativeSingleCount := ValidV3CodePlan()
    negativeSingleCount.SingleCount = -1
    assert throws InvalidOperationException { negativeSingleCount.ValidateSealedStructure() }

    negativeDoubleCount := ValidV3CodePlan()
    negativeDoubleCount.DoubleCount = -1
    assert throws InvalidOperationException { negativeDoubleCount.ValidateSealedStructure() }

    negativeStringCount := ValidV3CodePlan()
    negativeStringCount.StringCount = -1
    assert throws InvalidOperationException { negativeStringCount.ValidateSealedStructure() }

    shortInt64Column := ValidV3CodePlan()
    shortInt64Column.Int64Count = 1
    shortInt64Column.Int64Values = new long[](0)
    assert throws InvalidOperationException { shortInt64Column.ValidateSealedStructure() }

    shortSingleColumn := ValidV3CodePlan()
    shortSingleColumn.SingleCount = 1
    shortSingleColumn.SingleValues = new float[](0)
    assert throws InvalidOperationException { shortSingleColumn.ValidateSealedStructure() }

    shortDoubleColumn := ValidV3CodePlan()
    shortDoubleColumn.DoubleCount = 1
    shortDoubleColumn.DoubleValues = new double[](0)
    assert throws InvalidOperationException { shortDoubleColumn.ValidateSealedStructure() }

    shortStringColumn := ValidV3CodePlan()
    shortStringColumn.StringCount = 1
    shortStringColumn.StringValues = new string[](0)
    assert throws InvalidOperationException { shortStringColumn.ValidateSealedStructure() }

    nullStringEntry := ValidV3CodePlan()
    nullStringEntry.StringCount = 1
    nullStringEntry.StringValues = new string[](1)
    assert throws InvalidOperationException { nullStringEntry.ValidateSealedStructure() }
}

test "schema v3 appends only exact scalar opcode and pool pairings" {
    int64Plan := new ColumnarCodePlan()
    int64Plan.PrepareV3()
    int64Root := int64Plan.BeginFragment(-1, 1210, 0)
    int64Index := int64Plan.AddInt64((long)1)
    assert throws InvalidOperationException {
        int64Plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcR8(), int64Index)
    }
    int64Plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), int64Index)
    int64Plan.CompleteFragment(int64Root, typeof(long))
    int64Plan.CompleteV3(typeof(long))
    int64Plan.ValidateSealedStructure()
    assert int64Plan.OperandKinds[0] == ColumnarCodePlanContract.Int64Operand()

    singlePlan := new ColumnarCodePlan()
    singlePlan.PrepareV3()
    singleRoot := singlePlan.BeginFragment(-1, 1211, 0)
    singleIndex := singlePlan.AddSingle((float)1.5)
    assert throws InvalidOperationException {
        singlePlan.AppendSingleInstruction(ColumnarCodePlanContract.LdcR8(), singleIndex)
    }
    singlePlan.AppendSingleInstruction(ColumnarCodePlanContract.LdcR4(), singleIndex)
    singlePlan.CompleteFragment(singleRoot, typeof(float))
    singlePlan.CompleteV3(typeof(float))
    singlePlan.ValidateSealedStructure()
    assert singlePlan.OperandKinds[0] == ColumnarCodePlanContract.SingleOperand()

    doublePlan := new ColumnarCodePlan()
    doublePlan.PrepareV3()
    doubleRoot := doublePlan.BeginFragment(-1, 1212, 0)
    doubleIndex := doublePlan.AddDouble(2.5)
    assert throws InvalidOperationException {
        doublePlan.AppendDoubleInstruction(ColumnarCodePlanContract.LdcR4(), doubleIndex)
    }
    doublePlan.AppendDoubleInstruction(ColumnarCodePlanContract.LdcR8(), doubleIndex)
    doublePlan.CompleteFragment(doubleRoot, typeof(double))
    doublePlan.CompleteV3(typeof(double))
    doublePlan.ValidateSealedStructure()
    assert doublePlan.OperandKinds[0] == ColumnarCodePlanContract.DoubleOperand()

    stringPlan := new ColumnarCodePlan()
    stringPlan.PrepareV3()
    stringRoot := stringPlan.BeginFragment(-1, 1213, 0)
    stringIndex := stringPlan.AddString("used")
    assert throws InvalidOperationException {
        stringPlan.AppendStringInstruction(ColumnarCodePlanContract.LdcI8(), stringIndex)
    }
    stringPlan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), stringIndex)
    stringPlan.CompleteFragment(stringRoot, typeof(string))
    stringPlan.CompleteV3(typeof(string))
    stringPlan.ValidateSealedStructure()
    assert stringPlan.OperandKinds[0] == ColumnarCodePlanContract.StringOperand()
}

test "schema v3 rejects tampered scalar opcode and operand rows structurally" {
    unknownOpcode := ValidInt64V3CodePlan()
    unknownOpcode.OpCodeValues[0] = (short)31
    assert throws InvalidOperationException { unknownOpcode.ValidateSealedStructure() }

    unknownOperand := ValidInt64V3CodePlan()
    unknownOperand.OperandKinds[0] = 99
    assert throws InvalidOperationException { unknownOperand.ValidateSealedStructure() }

    wrongScalarPair := ValidInt64V3CodePlan()
    wrongScalarPair.OpCodeValues[0] = ColumnarCodePlanContract.LdcR8()
    assert throws InvalidOperationException { wrongScalarPair.ValidateSealedStructure() }
}

test "schema v1 and v2 reject schema v3 scalar-pool smuggling" {
    int64V1 := OpenBooleanCodePlan()
    int64V1.Int64Count = 1
    assert throws InvalidOperationException { int64V1.CompleteBoolean() }

    singleV1 := OpenBooleanCodePlan()
    singleV1.SingleCount = 1
    assert throws InvalidOperationException { singleV1.CompleteBoolean() }

    doubleV1 := OpenBooleanCodePlan()
    doubleV1.DoubleCount = 1
    assert throws InvalidOperationException { doubleV1.CompleteBoolean() }

    stringV1 := OpenBooleanCodePlan()
    stringV1.StringCount = 1
    assert throws InvalidOperationException { stringV1.CompleteBoolean() }

    int64V2 := ValidV2CodePlan()
    int64V2.Int64Count = 1
    assert throws InvalidOperationException { int64V2.ValidateSealedStructure() }

    singleV2 := ValidV2CodePlan()
    singleV2.SingleCount = 1
    assert throws InvalidOperationException { singleV2.ValidateSealedStructure() }

    doubleV2 := ValidV2CodePlan()
    doubleV2.DoubleCount = 1
    assert throws InvalidOperationException { doubleV2.ValidateSealedStructure() }

    stringV2 := ValidV2CodePlan()
    stringV2.StringCount = 1
    assert throws InvalidOperationException { stringV2.ValidateSealedStructure() }
}

test "schema v1 and v2 reject corrupt hidden schema v3 pool columns" {
    int64V1 := OpenBooleanCodePlan()
    int64V1.Int64Values = null
    assert throws InvalidOperationException { int64V1.CompleteBoolean() }

    singleV1 := OpenBooleanCodePlan()
    singleV1.SingleValues = null
    assert throws InvalidOperationException { singleV1.CompleteBoolean() }

    doubleV1 := OpenBooleanCodePlan()
    doubleV1.DoubleValues = null
    assert throws InvalidOperationException { doubleV1.CompleteBoolean() }

    stringV1 := OpenBooleanCodePlan()
    stringV1.StringValues = null
    assert throws InvalidOperationException { stringV1.CompleteBoolean() }

    int64V2 := ValidV2CodePlan()
    int64V2.Int64Values = null
    assert throws InvalidOperationException { int64V2.ValidateSealedStructure() }

    singleV2 := ValidV2CodePlan()
    singleV2.SingleValues = null
    assert throws InvalidOperationException { singleV2.ValidateSealedStructure() }

    doubleV2 := ValidV2CodePlan()
    doubleV2.DoubleValues = null
    assert throws InvalidOperationException { doubleV2.ValidateSealedStructure() }

    stringV2 := ValidV2CodePlan()
    stringV2.StringValues = null
    assert throws InvalidOperationException { stringV2.ValidateSealedStructure() }
}

test "schema completion entrypoints cannot cross-seal versions" {
    v2 := new ColumnarCodePlan()
    v2.PrepareV2()
    v2Root := v2.BeginFragment(-1, 1208, 0)
    v2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    v2.CompleteFragment(v2Root, typeof(int))
    assert throws InvalidOperationException { v2.CompleteV3(typeof(int)) }

    v3 := OpenV3CodePlan()
    assert throws InvalidOperationException { v3.CompleteV2(typeof(int)) }
}

test "schema v2 carries argument address and exact declared method columns" {
    noTypes := new Type[](0)
    getter := typeof(string).GetMethod("get_Length", noTypes)
    if getter == null {
        throw new InvalidOperationException("Required String.Length getter was not found.")
    }

    suppliedParameters := new Type[](0)
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1210, 0)
    stringType := plan.AddType(typeof(string))
    argument := plan.AddArgument(0, stringType, false)
    methodIndex := plan.AddMethodWithSignature(
        getter,
        typeof(string),
        suppliedParameters,
        typeof(int),
        false,
        false)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodIndex)
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    plan.ValidateSealedStructure()

    assert !plan.ArgumentIsAddress[0]
    assert plan.MethodUsesDeclaredSignature[0]
    assert plan.MethodDeclaringTypes[0] == typeof(string)
    assert plan.MethodReturnTypes[0] == typeof(int)
    assert plan.MethodParameterTypes[0].Length == 0
    assert !plan.MethodIsStatic[0]
    assert !plan.MethodIsAbstract[0]
}

test "schema v2 carries ldarga and exact declared field columns" {
    tupleType := typeof(ValueTuple<int, int>)
    field := tupleType.GetField("Item1")
    if field == null {
        throw new InvalidOperationException("Required ValueTuple.Item1 field was not found.")
    }

    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1213, 0)
    receiverType := plan.AddType(tupleType)
    receiver := plan.AddArgument(0, receiverType, false)
    fieldIndex := plan.AddFieldWithSignature(
        field, tupleType, typeof(int), false)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarga(), receiver)
    plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldIndex)
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    plan.ValidateSealedStructure()

    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarga()
    assert !plan.ArgumentIsAddress[0]
    assert plan.FieldUsesDeclaredSignature[0]
    assert plan.FieldDeclaringTypes[0] == tupleType
    assert plan.FieldValueTypes[0] == typeof(int)
    assert !plan.FieldIsStatic[0]
}

test "schema v3 seals stfld rows while earlier recursive schemas reject them" {
    tupleType := typeof(ValueTuple<int, int>)
    field := tupleType.GetField("Item1")
    if field == null {
        throw new InvalidOperationException(
            "Required ValueTuple.Item1 field was not found.")
    }

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1215, 0)
    tupleTypeIndex := plan.AddType(tupleType)
    tupleArgument := plan.AddArgument(0, tupleTypeIndex, false)
    fieldIndex := plan.AddFieldWithSignature(
        field, tupleType, typeof(int), false)
    plan.AppendArgumentInstruction(
        ColumnarCodePlanContract.Ldarga(), tupleArgument)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldIndex)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))
    plan.ValidateSealedStructure()

    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Stfld()
    assert plan.OperandKinds[2] == ColumnarCodePlanContract.FieldOperand()

    schemaV2 := new ColumnarCodePlan()
    schemaV2.PrepareV2()
    _schemaV2Root := schemaV2.BeginFragment(-1, 1216, 0)
    schemaV2Field := schemaV2.AddField(field)
    assert throws InvalidOperationException {
        schemaV2.AppendFieldInstruction(
            ColumnarCodePlanContract.Stfld(), schemaV2Field)
    }
}

test "schema v2 rejects malformed argument address and declared method columns" {
    noTypes := new Type[](0)
    getter := typeof(string).GetMethod("get_Length", noTypes)
    if getter == null {
        throw new InvalidOperationException("Required String.Length getter was not found.")
    }

    missingAddress := new ColumnarCodePlan()
    missingAddress.PrepareV2()
    addressRoot := missingAddress.BeginFragment(-1, 1211, 0)
    stringType := missingAddress.AddType(typeof(string))
    argument := missingAddress.AddArgument(0, stringType)
    missingAddress.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    missingAddress.CompleteFragment(addressRoot, typeof(string))
    missingAddress.CompleteV2(typeof(string))
    missingAddress.ArgumentIsAddress = null
    assert throws InvalidOperationException { missingAddress.ValidateSealedStructure() }

    missingSignature := new ColumnarCodePlan()
    missingSignature.PrepareV2()
    signatureRoot := missingSignature.BeginFragment(-1, 1212, 0)
    signatureStringType := missingSignature.AddType(typeof(string))
    signatureArgument := missingSignature.AddArgument(0, signatureStringType)
    signatureMethod := missingSignature.AddMethodWithSignature(
        getter,
        typeof(string),
        noTypes,
        typeof(int),
        false,
        false)
    missingSignature.AppendArgumentInstruction(
        ColumnarCodePlanContract.Ldarg(), signatureArgument)
    missingSignature.AppendMethodInstruction(
        ColumnarCodePlanContract.Callvirt(), signatureMethod)
    missingSignature.CompleteFragment(signatureRoot, typeof(int))
    missingSignature.CompleteV2(typeof(int))
    missingSignature.MethodParameterTypes = null
    assert throws InvalidOperationException { missingSignature.ValidateSealedStructure() }

    tupleType := typeof(ValueTuple<int, int>)
    field := tupleType.GetField("Item1")
    if field == null {
        throw new InvalidOperationException("Required ValueTuple.Item1 field was not found.")
    }
    missingFieldSignature := new ColumnarCodePlan()
    missingFieldSignature.PrepareV2()
    fieldRoot := missingFieldSignature.BeginFragment(-1, 1214, 0)
    tupleTypeIndex := missingFieldSignature.AddType(tupleType)
    tupleArgument := missingFieldSignature.AddArgument(0, tupleTypeIndex, false)
    fieldIndex := missingFieldSignature.AddFieldWithSignature(
        field, tupleType, typeof(int), false)
    missingFieldSignature.AppendArgumentInstruction(
        ColumnarCodePlanContract.Ldarga(), tupleArgument)
    missingFieldSignature.AppendFieldInstruction(
        ColumnarCodePlanContract.Ldfld(), fieldIndex)
    missingFieldSignature.CompleteFragment(fieldRoot, typeof(int))
    missingFieldSignature.CompleteV2(typeof(int))
    missingFieldSignature.FieldValueTypes = null
    assert throws InvalidOperationException {
        missingFieldSignature.ValidateSealedStructure()
    }
}

test "schema v2 exact declared method API rejects null signature facts" {
    noTypes := new Type[](0)
    getter := typeof(string).GetMethod("get_Length", noTypes)
    if getter == null {
        throw new InvalidOperationException("Required String.Length getter was not found.")
    }
    field := typeof(ValueTuple<int, int>).GetField("Item1")
    if field == null {
        throw new InvalidOperationException("Required ValueTuple.Item1 field was not found.")
    }

    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    assert throws ArgumentNullException {
        plan.AddMethodWithSignature(null, typeof(string), noTypes, typeof(int), false, false)
    }
    assert throws ArgumentNullException {
        plan.AddMethodWithSignature(getter, null, noTypes, typeof(int), false, false)
    }
    assert throws ArgumentNullException {
        plan.AddMethodWithSignature(getter, typeof(string), null, typeof(int), false, false)
    }
    assert throws ArgumentNullException {
        plan.AddMethodWithSignature(getter, typeof(string), noTypes, null, false, false)
    }
    assert throws ArgumentNullException {
        plan.AddFieldWithSignature(null, typeof(ValueTuple<int, int>), typeof(int), false)
    }
    assert throws ArgumentNullException {
        plan.AddFieldWithSignature(field, null, typeof(int), false)
    }
    assert throws ArgumentNullException {
        plan.AddFieldWithSignature(field, typeof(ValueTuple<int, int>), null, false)
    }
}


// ---- 015-B8 — THE PLAN-LOCAL MIRROR: ARMING, MATERIALISATION, AND WHAT IT IS NOT ----
//
// A mirror is the enclosing body's local VOCABULARY carried into a type-discovery scratch: the slot
// indices and their types, so the scratch's rows can name a local the way the outer plan names it,
// while the scratch types the expression that reads it. It is armed on a FRESH plan rather than after a
// prepare, and that is forced rather than chosen — two of the four scratch sites hand their plan to a
// callee whose own `Plan()` prepares it, so an "arm after my prepare" API could not reach them.
test "a plan-local mirror is armed on a fresh plan and materialised by every prepare" {
    vocabulary := new Type[](2)
    vocabulary[0] = typeof(int)
    vocabulary[1] = typeof(string)

    // The arming is inert until a prepare: a fresh plan still reports an empty pool.
    scalar := new ColumnarCodePlan()
    scalar.EnablePlanLocalMirror(vocabulary)
    assert scalar.PlanLocalCount == 0
    assert scalar.HasPlanLocalMirror()

    scalar.PrepareV3()
    assert scalar.PlanLocalCount == 2
    assert scalar.PlanLocalIsMirror[0]
    assert scalar.PlanLocalIsMirror[1]
    assert scalar.Types[scalar.PlanLocalTypeIndices[0]] == typeof(int)
    assert scalar.Types[scalar.PlanLocalTypeIndices[1]] == typeof(string)

    // A slot the plan declares for ITSELF after the mirror is storage, at the next index up — which is
    // what keeps the mirror's indices identical to the enclosing body's.
    own := scalar.DeclarePlanLocal(scalar.AddType(typeof(long)))
    assert own == 2
    assert !scalar.PlanLocalIsMirror[2]

    // The vocabulary is CONFIGURATION rather than state, so whichever prepare opens the plan
    // materialises it — the recursive schema and the method-body schema alike.
    recursive := new ColumnarCodePlan()
    recursive.EnablePlanLocalMirror(vocabulary)
    recursive.PrepareV2()
    assert recursive.PlanLocalCount == 2
    assert recursive.PlanLocalIsMirror[1]

    body := new ColumnarCodePlan()
    body.EnablePlanLocalMirror(vocabulary)
    body.PrepareMethodBody()
    assert body.PlanLocalCount == 2
    assert body.PlanLocalIsMirror[0]

    // An EMPTY vocabulary is the off-the-door case, and it declares nothing at all — which is why every
    // schema-v3 expression path can arm the mirror without a byte moving.
    empty := new ColumnarCodePlan()
    empty.EnablePlanLocalMirror(new Type[](0))
    assert !empty.HasPlanLocalMirror()
    empty.PrepareV3()
    assert empty.PlanLocalCount == 0
}

test "a plan-local mirror refuses a used plan a null vocabulary and a null slot" {
    used := new ColumnarCodePlan()
    used.PrepareV3()
    assert throws InvalidOperationException { used.EnablePlanLocalMirror(new Type[](0)) }

    fresh := new ColumnarCodePlan()
    assert throws ArgumentNullException { fresh.EnablePlanLocalMirror(null) }

    holed := new Type[](2)
    holed[0] = typeof(int)
    assert throws InvalidOperationException { fresh.EnablePlanLocalMirror(holed) }
    assert !fresh.HasPlanLocalMirror()
}
