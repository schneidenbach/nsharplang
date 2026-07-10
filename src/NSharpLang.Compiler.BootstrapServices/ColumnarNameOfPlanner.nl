namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

// N# owns the syntactic nameof lowering admitted by the columnar parser: after transparent
// parentheses, an identifier or member-access target contributes its final source name as ldstr.
// Recursive expression owners append through the same schema-v3 transaction as root planning.
public class ColumnarNameOfPlanner {
    public static func TryEmit(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan,
        il: ILGenerator,
        out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
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
            resultType = typeof(int)
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
        ValidateRootInputs(nodes, source, node, plan)
        plan.PrepareV3()
        if nodes.Kind(node) != ColumnarExpressionNodeKind.NameOfExpression() {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        fragment := plan.BeginFragment(-1, nodes.Kind(node), node)
        resultType := typeof(string)
        if !TryAppendNameOf(nodes, source, node, plan, out resultType) {
            plan.Rollback(checkpoint)
            return plan.Status
        }

        plan.CompleteFragment(fragment, resultType)
        plan.CompleteV3(resultType)
        return plan.Status
    }

    public static func TryAppendNameOf(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        ValidateAppendInputs(nodes, source, node, plan)
        resultType = typeof(string)
        if nodes.Kind(node) != ColumnarExpressionNodeKind.NameOfExpression()
            || nodes.ChildCount(node) != 1 {
            return false
        }

        target := UnwrapParentheses(nodes, nodes.Child(node, 0))
        if target < 0 {
            return false
        }
        targetKind := nodes.Kind(target)
        if targetKind != ColumnarExpressionNodeKind.IdentifierExpression()
            && targetKind != ColumnarExpressionNodeKind.MemberAccessExpression() {
            return false
        }

        name := nodes.Text(source, target)
        if name.Length == 0 {
            return false
        }
        valueIndex := plan.AddString(name)
        plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), valueIndex)
        return true
    }

    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length
            && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }
            node = nodes.Child(node, 0)
            depth = depth + 1
        }
        if node < 0 || node >= nodes.Kinds.Length {
            return -1
        }
        return node
    }

    static func ValidateRootInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan) {
        if nodes == null || source == null || plan == null {
            throw new InvalidOperationException("Nameof planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Nameof planning received an invalid node index.")
        }
    }

    static func ValidateAppendInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan) {
        ValidateRootInputs(nodes, source, node, plan)
        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
            || plan.Status != ColumnarFragmentPlanStatus.NotOwned
            || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException(
                "Nameof expressions can only append to an open schema-v3 plan.")
        }
        if plan.FragmentCount <= 0 || plan.FragmentCompleted == null
            || plan.FragmentCompleted.Length < plan.FragmentCount {
            throw new InvalidOperationException("Nameof expressions require an open fragment.")
        }
        hasOpenFragment := false
        i := 0
        while i < plan.FragmentCount {
            if !plan.FragmentCompleted[i] {
                hasOpenFragment = true
            }
            i = i + 1
        }
        if !hasOpenFragment {
            throw new InvalidOperationException("Nameof expressions require an open fragment.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned nameof expression has no result type.")
        }
        return resultType
    }
}
