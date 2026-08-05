namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit


// Direct schema-v3 owner for the two Boolean control-flow expression forms:
//   * the ternary conditional `cond ? whenTrue : whenFalse` (kind 13) — a Brfalse/Br branch-merge
//     with exact-type arm unification, and
//   * the short-circuit logical operators `a && b` / `a || b` (kind-12 binaries whose operator text
//     is `&&`/`||`) — conditional evaluation of the right operand, branching on the left through
//     Brfalse (`&&`) / Brtrue (`||`) to a merge constant.
// Both mirror the legacy ColumnarIlEmitter case-13 / case-12 short-circuit lowerings byte-for-byte.
// Operands recurse through the shared value-position surface, so a comparison condition, a call arm,
// or a nested conditional plans as its own owner; any operand the surface declines rolls the whole
// candidate back to a NotOwned, whole-subtree boundary served by the legacy arm. The condition and
// both short-circuit operands must be exactly Boolean, and the ternary arms must be the exact same
// type — no implicit unification.
class ColumnarConditionalPlanner {

    // Root front-door gate: a three-child ternary, or a two-child binary whose operator text is a
    // short-circuit `&&`/`||`. Every other binary routes to its own owner.
    static func MayPlanRoot(nodes: ColumnarNodeTable, source: string, node: int): bool {
        if nodes == null || source == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }
        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.TernaryExpression() {
            return nodes.ChildCount(candidate) == 3
        }
        return IsShortCircuitBinary(nodes, source, candidate)
    }

    // Value-position gate consumed by the recursive plannable-value dispatcher: a `&&`/`||` binary.
    static func IsShortCircuitBinary(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.BinaryExpression() && nodes.ChildCount(node) == 2 && IsShortCircuitOperator(nodes, source, node)
    }

    // Root ownership seam consumed by the emitter front door. A planned root claims the whole node;
    // any decline is a NotOwned whole-subtree exit (never terminal) so the legacy arm serves the
    // mixed-type ternary and coalesce forms outside this slice.
    static func TryEmitRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, il: ILGenerator, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        nsharpOwned = false
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if Plan(nodes, source, node, bindings, handles, plan) != ColumnarFragmentPlanStatus.Planned {
            legacyWholeSubtreePlanning = true
            return false
        }

        nsharpOwned = true
        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetTypeRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        nsharpOwned = false
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if Plan(nodes, source, node, bindings, handles, plan) != ColumnarFragmentPlanStatus.Planned {
            legacyWholeSubtreePlanning = true
            return false
        }

        nsharpOwned = true
        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateRootInputs(nodes, source, node, bindings, handles, plan)
        plan.PrepareV3()
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return plan.Status
        }

        kind := nodes.Kind(candidate)
        isTernary := kind == ColumnarExpressionNodeKind.TernaryExpression() && nodes.ChildCount(candidate) == 3
        isShortCircuit := IsShortCircuitBinary(nodes, source, candidate)
        if !isTernary && !isShortCircuit {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, kind, candidate)
            resultType := typeof(int)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            planned := false
            if isTernary {
                planned = TryPlanTernary(nodes, source, candidate, bindings, handles, plan, fragment, 0, out resultType, out nestedOwnership)
            } else {
                planned = TryPlanShortCircuit(nodes, source, candidate, bindings, handles, plan, fragment, 0, out resultType, out nestedOwnership)
            }
            if !planned {
                plan.Rollback(checkpoint)
                return plan.Status
            }

            plan.CompleteFragment(fragment, resultType)
            plan.CompleteV3(resultType)
            return plan.Status
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    // Ternary `cond ? whenTrue : whenFalse` (kind 13). Appends into the already-open fragment,
    // mirroring the legacy case-13 lowering exactly: emit the Boolean condition, `brfalse` to the
    // else label, emit the then arm, `br` to the end label, mark the else label, emit the else arm,
    // require both arms are the SAME type, mark the end label. A non-Boolean condition or a
    // mixed-type arm decline is atomic (the caller rolls the plan back).
    static func TryPlanTernary(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if nodes.ChildCount(node) != 3 {
            return false
        }

        conditionType := typeof(bool)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, out conditionType, out nestedOwnership) || conditionType != typeof(bool) {
            return false
        }

        falseLabel := plan.DefineLabel()
        endLabel := plan.DefineLabel()
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), falseLabel)

        whenTrueType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 1), bindings, handles, plan, fragment, depth + 1, out whenTrueType, out nestedOwnership) {
            return false
        }

        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
        plan.AppendMarkLabel(falseLabel)

        whenFalseType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 2), bindings, handles, plan, fragment, depth + 1, out whenFalseType, out nestedOwnership) || whenTrueType != whenFalseType {
            return false
        }

        plan.AppendMarkLabel(endLabel)
        resultType = whenTrueType
        return true
    }

    // Short-circuit `a && b` / `a || b` (kind-12 binary). Appends into the already-open fragment,
    // mirroring the legacy case-12 short-circuit arm exactly: evaluate the Boolean left operand,
    // branch on it BEFORE the right is evaluated (`brfalse` short-circuits `&&` to false on a false
    // left; `brtrue` short-circuits `||` to true on a true left), evaluate the Boolean right operand
    // only on the non-short path, `br` to the end, then on the short path push the constant merge
    // value (`&&` -> false via ldc.i4.0; `||` -> true via ldc.i4.1). Both operands and the result
    // are Boolean; a non-Boolean operand declines atomically.
    static func TryPlanShortCircuit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(bool)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if !IsShortCircuitBinary(nodes, source, node) {
            return false
        }

        isAnd := HasExactOperatorText(nodes, source, node, "&&")

        leftType := typeof(bool)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, out leftType, out nestedOwnership) || leftType != typeof(bool) {
            return false
        }

        shortLabel := plan.DefineLabel()
        endLabel := plan.DefineLabel()
        branchOpCode := ColumnarCodePlanContract.Brtrue()
        if isAnd {
            branchOpCode = ColumnarCodePlanContract.Brfalse()
        }
        plan.AppendLabelInstruction(branchOpCode, shortLabel)

        rightType := typeof(bool)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 1), bindings, handles, plan, fragment, depth + 1, out rightType, out nestedOwnership) || rightType != typeof(bool) {
            return false
        }

        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
        plan.AppendMarkLabel(shortLabel)
        mergeConstant := ColumnarCodePlanContract.LdcI4_1()
        if isAnd {
            mergeConstant = ColumnarCodePlanContract.LdcI4_0()
        }
        plan.AppendInstructionWithoutOperand(mergeConstant)
        plan.AppendMarkLabel(endLabel)
        resultType = typeof(bool)
        return true
    }

    static func IsShortCircuitOperator(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return HasExactOperatorText(nodes, source, node, "&&") || HasExactOperatorText(nodes, source, node, "||")
    }

    static func HasExactOperatorText(nodes: ColumnarNodeTable, source: string, node: int, expected: string): bool {
        start := nodes.ValueStart(node)
        length := nodes.ValueLengths[node]
        return start >= 0 && length == expected.Length && length <= source.Length && start <= source.Length - length && source.Substring(start, length) == expected
    }

    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        current := node
        while current >= 0 && current < nodes.Kinds.Length && nodes.Kind(current) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if nodes.ChildCount(current) != 1 || depth > 200 {
                return -1
            }
            current = nodes.Child(current, 0)
            depth += 1
        }
        if current < 0 || current >= nodes.Kinds.Length {
            return -1
        }
        return current
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned conditional expression has no result type.")
        }
        return resultType
    }

    static func ValidateRootInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || handles == null || plan == null {
            throw new InvalidOperationException("Conditional planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Conditional planning received an invalid node index.")
        }
    }
}
