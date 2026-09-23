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
        candidate := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, node)
        if candidate < 0 {
            return false
        }
        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.TernaryExpression {
            return nodes.ChildCount(candidate) == 3
        }
        return IsShortCircuitBinary(nodes, source, candidate)
    }

    // Value-position gate consumed by the recursive plannable-value dispatcher: a `&&`/`||` binary.
    static func IsShortCircuitBinary(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.BinaryExpression && nodes.ChildCount(node) == 2 && IsShortCircuitOperator(nodes, source, node)
    }

    // Value-position gate for `a ?? b` — a kind-12 binary whose operator text is the two-character
    // `??`. It is a BRANCH-MERGE like the ternary rather than an arithmetic binary, which is why it
    // belongs to this owner and not to `ColumnarPrimitiveBinaryPlanner`: the right operand is
    // evaluated only when the left is absent.
    static func IsNullCoalesceBinary(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.BinaryExpression && nodes.ChildCount(node) == 2 && HasExactOperatorText(nodes, source, node, "??")
    }

    // IS THIS NODE ONE OF THE THREE BRANCH-MERGE VALUE FORMS? The ternary, `&&`/`||` and `??` are
    // one family: each evaluates part of itself on only one of two paths and joins at a merge label.
    // `MayPlanRoot` deliberately answers a NARROWER question (it is the emitter front door's gate and
    // must not claim a `??` root, whose schema-v3 fragment the legacy arm still serves); this is the
    // VALUE-POSITION question, which the nested dispatcher has answered for all three since this
    // owner landed.
    static func IsBranchMergeValue(nodes: ColumnarNodeTable, source: string, node: int): bool {
        if nodes == null || source == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, node)
        if candidate < 0 {
            return false
        }

        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.TernaryExpression {
            return nodes.ChildCount(candidate) == 3
        }

        return IsShortCircuitBinary(nodes, source, candidate) || IsNullCoalesceBinary(nodes, source, candidate)
    }

    // THE TYPE OF A BRANCH-MERGE VALUE, DISCOVERED BY PLANNING IT — into a METHOD-BODY scratch, which
    // is the whole point of this seam existing beside `ColumnarDirectCallPlanner.TryGetPlannableValueType`
    // rather than inside it. That owner's scratch is a schema-v3 expression plan, and the reference
    // arm of `??` lowers to `dup; brtrue; pop; <fallback>` — `pop` is a METHOD-BODY opcode, so a v3
    // scratch does not decline it, it THROWS ("The opcode does not use an operand-free row"). Typing a
    // `??` argument through a v4 scratch runs the identical rows the real append will run, so the type
    // side and the append side cannot disagree, and no shape reaches the plan only to crash it.
    //
    // The scratch is discarded rather than sealed: a method body is sealed only when it terminates on
    // every path, and a bare value expression never does. Validation of the rows that matter happens
    // when the SAME planner appends them into the real body.
    static func TryGetBranchMergeValueType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, methodBodySchema: bool, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || handles == null {
            return false
        }

        scratch := new ColumnarCodePlan()
        scratch.EnablePlanLocalMirror(bindings.PlanLocalMirrorTypes())
        scratch.EnableNestedValueFrame()
        if methodBodySchema {
            scratch.PrepareMethodBody()
        } else {
            scratch.PrepareV3()
        }
        return TryAppendRoot(nodes, source, node, bindings, handles, scratch, out resultType) && resultType != null
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
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "conditional expression")
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
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "conditional expression")
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateRootInputs(nodes, source, node, bindings, handles, plan)
        plan.PrepareV3()
        resultType := typeof(int)
        if !TryAppendRoot(nodes, source, node, bindings, handles, plan, out resultType) {
            return plan.Status
        }

        plan.CompleteV3(resultType)
        return plan.Status
    }

    // THE ROOT-APPEND SEQUENCE, OWNED ONCE (015-B12) — the third application of the factoring `015-B7`
    // gave the direct-call owner and `015-B9` gave the primitive-binary one, for the same reason. A
    // conditional root is an admission test, a checkpoint, a root fragment, the append and the
    // fragment's completion; whether the plan around it is a standalone schema-v3 expression (`Plan`
    // wraps this between `PrepareV3` and `CompleteV3`) or an already-open schema-v4 METHOD BODY
    // (`ColumnarMethodBodyPlanner`'s expression door calls it directly) is the wrapper's business, not
    // the sequence's. Both callers therefore produce the SAME row sequence, which is the whole of
    // producing the same bytes.
    //
    // ⚠ THE FRAGMENT KIND IS THE CANDIDATE'S OWN, AND *NOTHING IN THE PLAN CHECKS THAT*.
    // `BeginFragment` is handed `kind` — 13 for a ternary, 12 for a short-circuit binary — so one
    // sequence covers two door kinds without either arm hard-coding the other's kind.
    //
    // `015-B12`'s control `C3` hard-coded it to `TernaryExpression()` and the whole estate stayed
    // GREEN, so the first version of this comment — which claimed `HasValidV2Fragments` would catch
    // the disagreement — was WRONG and is corrected here rather than quietly dropped. That validator
    // asks only `FragmentKinds[i] >= 0`; it never compares the recorded kind with the kind of the
    // node `FragmentSourceNodeIndices[i]` points at. The fragment kind is therefore DESCRIPTIVE
    // metadata that no invariant enforces, which is exactly why the estate now asserts it directly
    // for both arms — a claim with no instrument behind it is the thing this arc exists to avoid.
    //
    // Byte identity is against ONE owner, and the route is measured rather than assumed:
    // `ColumnarIlEmitter.EmitExpressionCore` offers four pre-cascade owners first (boolean,
    // unary-literal, scalar-literal, `nameof`) and none has a kind-13 or short-circuit arm; then
    // `ColumnarRangeIndexPlanner.FacadeRootMayNeedFacts` admits both shapes through its FIRST test,
    // which is this class's own `MayPlanRoot`; and inside the cascade the construction arm answers only
    // 15/36/58, the direct-call arm only kind 9, and the primitive-binary arm only kind-12 binaries
    // whose operator text is a CLAIMED one. `&&` and `||` are not claimed there, and the reason is a
    // LENGTH fact worth naming: that owner's `HasExactOperatorText` tests `length == expected.Length`
    // before it compares text, so a two-character `&&` can never match its one-character `&`. Both
    // shapes therefore fall to the FOURTH arm, which is this class.
    //
    // The null contract is the softer one the second caller needs: `Plan` still THROWS through
    // `ValidateRootInputs` before it gets here, so its behaviour is unchanged, and a door that hands
    // this a null table declines instead of crashing.
    static func TryAppendRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || handles == null || plan == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, node)
        if candidate < 0 {
            return false
        }

        kind := nodes.Kind(candidate)
        isTernary := kind == ColumnarExpressionNodeKind.TernaryExpression && nodes.ChildCount(candidate) == 3
        isShortCircuit := IsShortCircuitBinary(nodes, source, candidate)
        isNullCoalesce := IsNullCoalesceBinary(nodes, source, candidate)
        if !isTernary && !isShortCircuit && !isNullCoalesce {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, kind, candidate)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            planned := false
            if isTernary {
                planned = TryPlanTernary(nodes, source, candidate, bindings, handles, plan, fragment, 0, out resultType, out nestedOwnership)
            } else if isNullCoalesce {
                planned = TryPlanNullCoalesce(nodes, source, candidate, bindings, handles, plan, fragment, 0, out resultType, out nestedOwnership)
            } else {
                planned = TryPlanShortCircuit(nodes, source, candidate, bindings, handles, plan, fragment, 0, out resultType, out nestedOwnership)
            }
            if !planned {
                plan.Rollback(checkpoint)
                return false
            }

            plan.CompleteFragment(fragment, resultType)
            return true
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

        // EITHER ARM MAY BE A `throw` (kind 83), and a throwing arm produces no value at all — the
        // conditional is then worth the OTHER arm's type, which is C#'s reading and the analyzer's.
        // A throwing arm also ENDS ITS PATH: `ValidateMethodBodyStack` merges no height into the row
        // after a `throw`, so the `br` to the merge label is written only when the then arm falls
        // through, and the merge label is reached from whichever arm still produces a value. Both
        // arms throwing leaves the merge unreachable and has no type to report, so it declines here
        // (the analyzer reports it before emission is ever asked).
        throwWhenTrue := ColumnarThrowExpressionPlanner.IsThrowExpression(nodes, nodes.Child(node, 1))
        throwWhenFalse := ColumnarThrowExpressionPlanner.IsThrowExpression(nodes, nodes.Child(node, 2))
        if throwWhenTrue && throwWhenFalse {
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
        if throwWhenTrue {
            if !ColumnarThrowExpressionPlanner.TryAppendThrow(nodes, source, nodes.Child(node, 1), bindings, handles, plan, fragment, depth) {
                return false
            }
        } else {
            if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 1), bindings, handles, plan, fragment, depth + 1, out whenTrueType, out nestedOwnership) {
                return false
            }
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
        }

        plan.AppendMarkLabel(falseLabel)

        whenFalseType := typeof(int)
        if throwWhenFalse {
            if !ColumnarThrowExpressionPlanner.TryAppendThrow(nodes, source, nodes.Child(node, 2), bindings, handles, plan, fragment, depth) {
                return false
            }
            plan.AppendMarkLabel(endLabel)
            resultType = whenTrueType
            return true
        }

        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 2), bindings, handles, plan, fragment, depth + 1, out whenFalseType, out nestedOwnership) {
            return false
        }
        if !throwWhenTrue && whenTrueType != whenFalseType {
            return false
        }

        plan.AppendMarkLabel(endLabel)
        resultType = throwWhenTrue ? whenFalseType : whenTrueType
        return true
    }

    // `a ?? b` — the NULL-COALESCING branch-merge, in the three left-operand shapes the language has
    // and the legacy `ColumnarIlEmitter` `op == "??"` arm lowers:
    //
    //   * a REFERENCE left: `<a>; dup; brtrue end; pop; <b>; end:` — the duplicated reference IS the
    //     result on the non-null path, so nothing re-evaluates `a`.
    //   * a `Nullable<T>` left: the value is parked in a plan local, `HasValue` decides, and the
    //     present path unwraps with `GetValueOrDefault()`. The RESULT is the ELEMENT type `T`, not
    //     `T?` — `n ?? 0` is an `int`.
    //   * a GENERIC PARAMETER left: the nullness question is asked of the BOXED value (one `box`,
    //     never two) while the result stays `T`, so a value-type instantiation always takes the left
    //     branch and a reference instantiation takes it exactly when the reference is non-null.
    //
    // The right operand may be a `throw` (kind 83) in every one of the three, which is the form
    // `x ?? throw new ArgumentNullException(...)` production code writes constantly: the fallback
    // path raises instead of producing a value, so no `br` joins the merge from it and the whole
    // expression is worth the left with its nullability removed.
    static func TryPlanNullCoalesce(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if !IsNullCoalesceBinary(nodes, source, node) {
            return false
        }

        leftType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, out leftType, out nestedOwnership) || leftType == null {
            return false
        }

        fallback := nodes.Child(node, 1)
        if ColumnarTypeOfPlanner.IsSupportedNullable(leftType) {
            return TryPlanNullableCoalesce(nodes, source, fallback, bindings, handles, plan, fragment, depth, leftType, out resultType, out nestedOwnership)
        }
        if leftType.IsGenericParameter {
            return TryPlanTypeParameterCoalesce(nodes, source, fallback, bindings, handles, plan, fragment, depth, leftType, out resultType, out nestedOwnership)
        }
        if leftType.IsValueType {
            return false
        }
        return TryPlanReferenceCoalesce(nodes, source, fallback, bindings, handles, plan, fragment, depth, leftType, out resultType, out nestedOwnership)
    }

    // REFERENCE LEFT: the duplicated reference survives the test and becomes the result.
    static func TryPlanReferenceCoalesce(nodes: ColumnarNodeTable, source: string, fallback: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, leftType: Type, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = leftType
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        // `pop` IS A METHOD-BODY OPCODE, and a schema-v3 expression plan does not decline it — it
        // THROWS ("The opcode does not use an operand-free row"). So a v3 position takes the PARKED
        // shape below instead: the same shape the generic-parameter arm already writes, using nothing
        // a v3 fragment refuses.
        //
        // WHAT THE v3 REFUSAL COST, AND WHY IT LOOKED LIKE SOMETHING ELSE ENTIRELY. A call's ARGUMENTS
        // are typed through a v3 plan, so a reference `??` anywhere inside one could not be typed at
        // all — and a call whose arguments have no types cannot have an overload chosen from them. For
        // every API the legacy emitter models by NAME that was invisible (`sb.Append(a ?? "")`,
        // `list.Add(a ?? "")`, `Math.Max((a ?? "").Length, 1)` all emit through that door). For a
        // GENERIC method, whose type arguments are INFERRED from the argument types, there is no such
        // door: `hash.Add(text ?? "")` answered `instance call 'HashCode.Add' with 1 argument(s) is
        // not modeled` while `hash.Add(text)` one line above emitted, and the report that found it
        // concluded the model was matching on the argument SHAPE. It was not; the argument had no type
        // to match with. `hash.Add(n ?? 0)` over a `Nullable<int>` emitted throughout, because that
        // arm parks instead of popping — which is exactly the difference this closes.
        if !plan.IsMethodBodySchema() {
            return TryPlanParkedReferenceCoalesce(nodes, source, fallback, bindings, handles, plan, fragment, depth, leftType, out nestedOwnership)
        }

        endLabel := plan.DefineLabel()
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), endLabel)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
        if !TryAppendCoalesceFallback(nodes, source, fallback, bindings, handles, plan, fragment, depth, leftType, out nestedOwnership) {
            return false
        }

        plan.AppendMarkLabel(endLabel)
        return true
    }

    // THE SAME REFERENCE MERGE WITHOUT `dup`/`pop`: park the left, test the parked value, and reload
    // it on the present path. One plan local and one extra `ldloc` buy a shape a schema-v3 fragment
    // accepts, and the value semantics are identical — the left is evaluated exactly once, and the
    // fallback runs only when it is null.
    //
    // A `throw` FALLBACK JOINS NOTHING, which is why the `br` is conditional here and in the
    // generic-parameter arm: a `br` after a `throw` is unreachable and the verifier says so.
    static func TryPlanParkedReferenceCoalesce(nodes: ColumnarNodeTable, source: string, fallback: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, leftType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        typePool := plan.AddType(leftType)
        parkedLocal := plan.DeclarePlanLocal(typePool)
        leftLabel := plan.DefineLabel()
        endLabel := plan.DefineLabel()

        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), parkedLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), parkedLocal)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), leftLabel)
        if !TryAppendCoalesceFallback(nodes, source, fallback, bindings, handles, plan, fragment, depth, leftType, out nestedOwnership) {
            return false
        }

        if !ColumnarThrowExpressionPlanner.IsThrowExpression(nodes, fallback) {
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
        }
        plan.AppendMarkLabel(leftLabel)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), parkedLocal)
        plan.AppendMarkLabel(endLabel)
        return true
    }

    // `Nullable<T>` LEFT: park, ask `HasValue`, unwrap on the present path. The result is `T`.
    static func TryPlanNullableCoalesce(nodes: ColumnarNodeTable, source: string, fallback: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, leftType: Type, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        elementType := leftType.GetGenericArguments()[0]
        resultType = elementType
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned

        let hasValueGetter: System.Reflection.MethodInfo? = null
        let getValueOrDefault: System.Reflection.MethodInfo? = null
        if !TryResolveNullableMembers(leftType, out hasValueGetter, out getValueOrDefault) {
            return false
        }

        nullableLocal := plan.DeclarePlanLocal(plan.AddType(leftType))
        hasValuePool := plan.AddMethod(hasValueGetter)
        unwrapPool := plan.AddMethod(getValueOrDefault)
        elseLabel := plan.DefineLabel()
        endLabel := plan.DefineLabel()

        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), nullableLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), nullableLocal)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), hasValuePool)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), elseLabel)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), nullableLocal)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), unwrapPool)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
        plan.AppendMarkLabel(elseLabel)
        if !TryAppendCoalesceFallback(nodes, source, fallback, bindings, handles, plan, fragment, depth, elementType, out nestedOwnership) {
            return false
        }

        plan.AppendMarkLabel(endLabel)
        return true
    }

    // GENERIC-PARAMETER LEFT: the box is a TEST, never the result.
    static func TryPlanTypeParameterCoalesce(nodes: ColumnarNodeTable, source: string, fallback: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, leftType: Type, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = leftType
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        typePool := plan.AddType(leftType)
        parkedLocal := plan.DeclarePlanLocal(typePool)
        leftLabel := plan.DefineLabel()
        endLabel := plan.DefineLabel()

        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), parkedLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), parkedLocal)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), typePool)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), leftLabel)
        if !TryAppendCoalesceFallback(nodes, source, fallback, bindings, handles, plan, fragment, depth, leftType, out nestedOwnership) {
            return false
        }

        if !ColumnarThrowExpressionPlanner.IsThrowExpression(nodes, fallback) {
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
        }
        plan.AppendMarkLabel(leftLabel)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), parkedLocal)
        plan.AppendMarkLabel(endLabel)
        return true
    }

    // The FALLBACK operand of a `??`, at the storage type the merge demands: a `throw` raises and
    // joins nothing, a `null` literal is the one shape the nested value owner does not claim (it
    // has no type of its own — here the position gives it the left's), and everything else is the
    // ordinary value plus the ONE argument-conversion owner's conversion to the merge type.
    static func TryAppendCoalesceFallback(nodes: ColumnarNodeTable, source: string, fallback: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, mergeType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if ColumnarThrowExpressionPlanner.IsThrowExpression(nodes, fallback) {
            return ColumnarThrowExpressionPlanner.TryAppendThrow(nodes, source, fallback, bindings, handles, plan, fragment, depth)
        }
        if nodes.Kind(fallback) == ColumnarExpressionNodeKind.NullLiteralExpression {
            if mergeType.IsValueType || mergeType.IsGenericParameter {
                return false
            }
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
            return true
        }

        fallbackType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, fallback, bindings, handles, plan, fragment, depth + 1, out fallbackType, out nestedOwnership) || fallbackType == null {
            return false
        }
        if fallbackType == mergeType {
            return true
        }
        return ColumnarDirectCallPlanner.AppendArgumentConversion(plan, fallbackType, mergeType, bindings.SourceTypeDefinitions)
    }

    // `Nullable<T>.get_HasValue` and `Nullable<T>.GetValueOrDefault()` closed over this instantiation,
    // through the ONE closed-generic member resolver the emitter also uses — so an element type that
    // is itself an emitted source struct resolves the same way here as it does there.
    static func TryResolveNullableMembers(nullableType: Type, out hasValueGetter: System.Reflection.MethodInfo?, out getValueOrDefault: System.Reflection.MethodInfo?): bool {
        hasValueGetter = null
        getValueOrDefault = null
        openNullable := nullableType.GetGenericTypeDefinition()
        hasValueProperty := openNullable.GetProperty("HasValue", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance)
        if hasValueProperty == null {
            return false
        }
        openGetter := hasValueProperty.GetGetMethod()
        openUnwrap := openNullable.GetMethod("GetValueOrDefault", Type.EmptyTypes)
        if openGetter == null || openUnwrap == null {
            return false
        }

        hasValueGetter = ColumnarClosedGenericMemberResolver.ResolveMethod(nullableType, openGetter)
        getValueOrDefault = ColumnarClosedGenericMemberResolver.ResolveMethod(nullableType, openUnwrap)
        return hasValueGetter != null && getValueOrDefault != null
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

    static func ValidateRootInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || handles == null || plan == null {
            throw new InvalidOperationException("Conditional planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Conditional planning received an invalid node index.")
        }
    }
}
