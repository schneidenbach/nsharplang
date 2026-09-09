namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

class ColumnarBooleanLiteralPlanner {
    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(bool)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(bool)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, plan)
        plan.Prepare()
        if !TryAppendLiteral(nodes, source, node, plan) {
            return plan.Status
        }

        plan.CompleteBoolean()
        return plan.Status
    }

    // Append exactly one boolean-literal row into an ALREADY-OPEN plan.
    //
    // THE WALL HERE IS STRUCTURAL, NOT A PREDICATE, WHICH IS WHY THIS IS AN ADDITIONAL ENTRY POINT
    // RATHER THAN A LOOSENED GATE. The scalar owner's method-body admission was one condition in
    // `ValidateAppendInputs`; this owner is a schema-v1 producer, and v1 admits EXACTLY ONE
    // instruction and no `ret` at all (`AppendInstruction` throws on a second row). So a method body
    // cannot be reached by relaxing anything — it needs an appender that dispatches on the plan's
    // schema. `Plan` is expressed through this function so exactly ONE decision about what a boolean
    // literal's row is survives in the file.
    //
    // A schema-v4 METHOD BODY takes the flat operand-free appender, which admits ldc.i4.0/ldc.i4.1
    // through `IsNoOperandOpcode` (the whole ldc.i4.m1..ldc.i4.8 short-form range) exactly as it
    // admits every other constant row; schema v1 keeps the single-instruction appender byte for byte.
    static func TryAppendLiteral(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan): bool {
        ValidateInputs(nodes, source, node, plan)
        if nodes.Kind(node) != ColumnarExpressionNodeKind.BoolLiteralExpression() {
            return false
        }

        text := nodes.Text(source, node)
        opCodeValue := ColumnarCodePlanContract.LdcI4_1()
        if text == "false" {
            opCodeValue = ColumnarCodePlanContract.LdcI4_0()
        } else if text != "true" {
            throw new InvalidOperationException("Boolean literal node text must be exactly 'true' or 'false'.")
        }

        if plan.IsMethodBodySchema() {
            plan.AppendInstructionWithoutOperand(opCodeValue)
        } else {
            plan.AppendInstruction(opCodeValue)
        }
        return true
    }

    static func ValidateInputs(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan) {
        if nodes == null || source == null || plan == null {
            throw new InvalidOperationException("Boolean-literal planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Boolean-literal planning received an invalid node index.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned boolean literal has no result type.")
        }
        return resultType
    }
}
