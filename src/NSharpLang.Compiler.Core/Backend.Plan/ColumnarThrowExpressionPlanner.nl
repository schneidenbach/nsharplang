namespace NSharpLang.Compiler.Columnar

import System


// THE `throw <exception>` EXPRESSION (node kind 83) ON THE PLAN SIDE.
//
// A throw expression produces NO value: its type is the bottom type and the position it sits in
// decides what the surrounding expression is worth. The grammar admits it in exactly three places —
// the right operand of `??`, either arm of a conditional, and an expression body — and the analyzer
// reports NL340 everywhere else, so this owner is never asked for a root value.
//
// Its rows are the operand's rows followed by `throw`, and `throw` is a METHOD-BODY (schema v4)
// opcode: `ColumnarCodePlanContract.IsMethodBodyNoOperandOpcode` admits it and
// `ColumnarCodePlan.AppendInstructionWithoutOperand` gates it on `IsMethodBodySchema()`. A
// schema-v3 expression fragment therefore declines a throw arm and the legacy emitter arm serves
// that shape, exactly as it did before this owner existed.
//
// The stack story is what makes a throw arm safe inside a branch-merge. `ValidateMethodBodyStack`
// does NOT merge a height into the row after a `throw`, so the merge label a conditional marks
// after a throwing arm is reached only from the OTHER arm's edge — which is precisely C#'s reading
// of `x ?? throw e` (worth `x`, with its nullability removed) and of `cond ? v : throw e` (worth
// `v`).
class ColumnarThrowExpressionPlanner {

    // Is this node a `throw <exception>` written in a value position? One child, no value span.
    static func IsThrowExpression(nodes: ColumnarNodeTable, node: int): bool {
        return nodes != null && node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.ThrowExpression && nodes.ChildCount(node) == 1
    }

    // Append the operand's rows and raise. The operand is planned by the ONE nested-value owner, so a
    // `new InvalidOperationException(msg)`, a factory call, a field read or a local all answer there;
    // the result must be a reference the runtime can raise, which is any type assignable to
    // `System.Exception` (a `T` constrained to an exception type reaches here as that constraint).
    static func TryAppendThrow(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int): bool {
        if nodes == null || source == null || bindings == null || handles == null || plan == null {
            return false
        }
        if !IsThrowExpression(nodes, node) || !plan.IsMethodBodySchema() {
            return false
        }

        exceptionType := typeof(int)
        nestedOwnership := ColumnarDirectCallOwnership.NotOwned
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, out exceptionType, out nestedOwnership) {
            return false
        }
        if exceptionType == null || exceptionType.IsValueType || !typeof(Exception).IsAssignableFrom(exceptionType) {
            return false
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Throw())
        return true
    }
}
