namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

// Validation finishes before the first ILGenerator call. Schema-v1 accepts exactly one
// operand-free boolean constant instruction and rejects every unknown value atomically.
public class ColumnarCodePlanExecutor {
    public static func Execute(plan: ColumnarCodePlan, il: ILGenerator) {
        Validate(plan)
        if il == null {
            throw new InvalidOperationException("Columnar code-plan IL generator cannot be null.")
        }

        opCodeValue := plan.OpCodeValues[0]
        if opCodeValue == ColumnarCodePlanContract.LdcI4_0() {
            il.Emit(OpCodes.Ldc_I4_0)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_1() {
            il.Emit(OpCodes.Ldc_I4_1)
        }
    }

    public static func Validate(plan: ColumnarCodePlan) {
        if plan == null {
            throw new InvalidOperationException("Columnar code plan cannot be null.")
        }
        if plan.SchemaVersion != ColumnarCodePlanContract.CurrentSchemaVersion() {
            throw new InvalidOperationException(
                "Unsupported columnar code-plan schema version " + plan.SchemaVersion.ToString() + ".")
        }
        if plan.Status != ColumnarFragmentPlanStatus.Planned
            || plan.ResultType == null
            || plan.ResultType != typeof(bool) {
            throw new InvalidOperationException("Columnar code plan is not a sealed boolean payload.")
        }
        if plan.OperationCount != 1 {
            throw new InvalidOperationException(
                "Columnar boolean code-plan schema v1 requires exactly one operation.")
        }
        if plan.OperationKinds == null
            || plan.OpCodeValues == null
            || plan.OperandKinds == null
            || plan.OperationKinds.Length < 1
            || plan.OpCodeValues.Length < 1
            || plan.OperandKinds.Length < 1 {
            throw new InvalidOperationException("Columnar code-plan operation columns are inconsistent.")
        }
        if !ColumnarCodePlanContract.IsBooleanInstructionRow(
            plan.OperationKinds[0],
            plan.OpCodeValues[0],
            plan.OperandKinds[0]) {
            throw new InvalidOperationException(
                "Columnar boolean code-plan schema v1 contains an unknown instruction row.")
        }
    }
}
