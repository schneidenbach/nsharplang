namespace NSharpLang.Compiler.Columnar

import System

public enum ColumnarFragmentPlanStatus {
    NotOwned = 0,
    Planned = 1
}

// Schema v1 is deliberately the exact first production surface: one operand-free boolean
// instruction. Opcode values are the signed values exposed by System.Reflection.Emit.OpCode.Value,
// never positional reflection indices or a second semantic numbering system.
public class ColumnarCodePlanContract {
    public static func CurrentSchemaVersion(): int {
        return 1
    }

    public static func EmitInstructionOperation(): int {
        return 1
    }

    public static func NoOperand(): int {
        return 0
    }

    public static func LdcI4_0(): short {
        return 22
    }

    public static func LdcI4_1(): short {
        return 23
    }

    public static func IsBooleanInstructionRow(
        operationKind: int,
        opCodeValue: short,
        operandKind: int): bool {
        return operationKind == EmitInstructionOperation()
            && operandKind == NoOperand()
            && (opCodeValue == LdcI4_0() || opCodeValue == LdcI4_1())
    }
}

// N# owns both construction and validation. Public columns make the versioned payload explicit;
// CompleteBoolean seals only the one shape that the schema-v1 executor can replay.
public class ColumnarCodePlan {
    public SchemaVersion: int
    public Status: ColumnarFragmentPlanStatus
    public OperationCount: int
    public OperationKinds: int[]
    public OpCodeValues: short[]
    public OperandKinds: int[]
    public ResultType: Type?

    constructor() {
        SchemaVersion = ColumnarCodePlanContract.CurrentSchemaVersion()
        Status = ColumnarFragmentPlanStatus.NotOwned
        OperationCount = 0
        OperationKinds = new int[](1)
        OpCodeValues = new short[](1)
        OperandKinds = new int[](1)
        ResultType = null
    }

    public func Prepare() {
        Reset()
        EnsureStorage()
    }

    public func AppendInstruction(opCodeValue: short) {
        EnsureBuilding()
        EnsureStorage()
        if OperationCount != 0 {
            throw new InvalidOperationException(
                "Columnar boolean code-plan schema v1 requires exactly one instruction.")
        }
        if opCodeValue != ColumnarCodePlanContract.LdcI4_0()
            && opCodeValue != ColumnarCodePlanContract.LdcI4_1() {
            throw new InvalidOperationException(
                "Columnar boolean code-plan schema v1 received an unknown opcode value.")
        }

        OperationKinds[0] = ColumnarCodePlanContract.EmitInstructionOperation()
        OpCodeValues[0] = opCodeValue
        OperandKinds[0] = ColumnarCodePlanContract.NoOperand()
        OperationCount = 1
    }

    public func CompleteBoolean() {
        EnsureBuilding()
        if SchemaVersion != ColumnarCodePlanContract.CurrentSchemaVersion()
            || OperationCount != 1
            || OperationKinds == null
            || OpCodeValues == null
            || OperandKinds == null
            || OperationKinds.Length < 1
            || OpCodeValues.Length < 1
            || OperandKinds.Length < 1
            || !ColumnarCodePlanContract.IsBooleanInstructionRow(
                OperationKinds[0],
                OpCodeValues[0],
                OperandKinds[0]) {
            throw new InvalidOperationException(
                "Columnar boolean code-plan schema v1 cannot seal an invalid instruction row.")
        }
        ResultType = typeof(bool)
        Status = ColumnarFragmentPlanStatus.Planned
    }

    public func Reset() {
        SchemaVersion = ColumnarCodePlanContract.CurrentSchemaVersion()
        Status = ColumnarFragmentPlanStatus.NotOwned
        OperationCount = 0
        ResultType = null
    }

    func EnsureStorage() {
        if OperationKinds == null || OperationKinds.Length < 1 {
            OperationKinds = new int[](1)
        }
        if OpCodeValues == null || OpCodeValues.Length < 1 {
            OpCodeValues = new short[](1)
        }
        if OperandKinds == null || OperandKinds.Length < 1 {
            OperandKinds = new int[](1)
        }
    }

    func EnsureBuilding() {
        if Status != ColumnarFragmentPlanStatus.NotOwned {
            throw new InvalidOperationException("Columnar code plan is no longer open for mutation.")
        }
    }
}
