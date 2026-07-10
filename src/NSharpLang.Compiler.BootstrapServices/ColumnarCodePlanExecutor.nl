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
        plan.ValidateSealedStructure()
    }
}
