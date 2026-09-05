namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit


// N# owns the syntactic nameof lowering admitted by the columnar parser: after transparent
// parentheses, an identifier or member-access target contributes its final source name as ldstr.
// Recursive expression owners append through the same schema-v3 transaction as root planning.
class ColumnarNameOfPlanner {
    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateRootInputs(nodes, source, node, plan)
        plan.PrepareV3()
        resultType := typeof(string)
        if !TryAppendRoot(nodes, source, node, plan, out resultType) {
            return plan.Status
        }

        plan.CompleteV3(resultType)
        return plan.Status
    }

    // THE ROOT-APPEND SEQUENCE, OWNED ONCE (015-B6). `Plan` wraps it between `PrepareV3` and
    // `CompleteV3`; `ColumnarMethodBodyPlanner`'s expression door calls the same function on an open
    // schema-v4 method body. The root fragment is not ceremony here — `ValidateAppendInputs` below
    // demands an open fragment, and this is what supplies one on either schema. A decline rolls the
    // plan back to the caller's exact state.
    static func TryAppendRoot(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(string)
        if nodes == null || source == null || plan == null || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.NameOfExpression() {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        fragment := plan.BeginFragment(-1, nodes.Kind(node), node)
        if !TryAppendNameOf(nodes, source, node, plan, out resultType) {
            plan.Rollback(checkpoint)
            return false
        }

        plan.CompleteFragment(fragment, resultType)
        return true
    }

    static func TryAppendNameOf(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        ValidateAppendInputs(nodes, source, node, plan)
        resultType = typeof(string)
        if nodes.Kind(node) != ColumnarExpressionNodeKind.NameOfExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        target := UnwrapParentheses(nodes, nodes.Child(node, 0))
        if target < 0 {
            return false
        }
        targetKind := nodes.Kind(target)
        if targetKind != ColumnarExpressionNodeKind.IdentifierExpression() && targetKind != ColumnarExpressionNodeKind.MemberAccessExpression() {
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
        while node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
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

    static func ValidateRootInputs(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan) {
        if nodes == null || source == null || plan == null {
            throw new InvalidOperationException("Nameof planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Nameof planning received an invalid node index.")
        }
    }

    static func ValidateAppendInputs(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan) {
        ValidateRootInputs(nodes, source, node, plan)
        // 015-B6: a schema-v4 METHOD BODY is admitted alongside v3. This gate threw — a hard crash out
        // of the compiler, not a decline — on every method-body plan, and ALL NINE owners that carried
        // it were widened in ONE move because the value surface routes by operand kind: admitting a
        // subset would mean pre-scanning operands to predict which owner they reach, which is a second
        // copy of the dispatcher's own decision.
        // It appends one ldstr; the open-fragment invariant below is unchanged and v4 satisfies
        // it with a root fragment.
        if (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && plan.SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Nameof expressions can only append to an open schema-v3 or method-body plan.")
        }
        if plan.FragmentCount <= 0 || plan.FragmentCompleted == null || plan.FragmentCompleted.Length < plan.FragmentCount {
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
