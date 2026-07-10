namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

public class ColumnarBooleanLiteralPlanner {
    public static func TryEmit(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan,
        il: ILGenerator,
        out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(bool)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    public static func TryGetType(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(bool)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    public static func Plan(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        if nodes == null || source == null || plan == null {
            throw new InvalidOperationException("Boolean-literal planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException(
                "Boolean-literal planning received an invalid node index.")
        }
        plan.Prepare()
        if nodes.Kind(node) != ColumnarExpressionNodeKind.BoolLiteralExpression() {
            return plan.Status
        }

        text := nodes.Text(source, node)
        if text == "true" {
            plan.AppendInstruction(ColumnarCodePlanContract.LdcI4_1())
        } else if text == "false" {
            plan.AppendInstruction(ColumnarCodePlanContract.LdcI4_0())
        } else {
            throw new InvalidOperationException(
                "Boolean literal node text must be exactly 'true' or 'false'.")
        }

        plan.CompleteBoolean()
        return plan.Status
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned boolean literal has no result type.")
        }
        return resultType
    }
}
