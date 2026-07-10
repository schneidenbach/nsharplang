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
