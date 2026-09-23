namespace NSharpLang.Compiler.Columnar

import System

// Builds a two-child short-circuit binary `<left> <op> <right>` over Boolean-literal operands. The
// operator token sits in the node's value span exactly where the parser records it.
func ConditionalShortCircuitLiteralTree(operatorText: string, leftText: string, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression, leftText)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression, rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, operatorText.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))
    return builder.Build(binary)
}

// Builds `<left> <op> <right>` over INT literals. The one-character bitwise operators are the
// primitive-binary owner's, and that owner's numeric surface EXCLUDES `bool` — so the operator
// partition has to be probed over ints where both owners' operands are admissible, not over the
// Boolean literals the short-circuit builder above uses.
func ConditionalIntBinaryTree(operatorText: string, leftText: string, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression, leftText)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression, rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, operatorText.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))
    return builder.Build(binary)
}

// Builds a short-circuit binary whose right operand is an arbitrary leaf (for non-Boolean declines).
func ConditionalShortCircuitRightLeafTree(operatorText: string, leftText: string, rightKind: int, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression, leftText)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(rightKind, rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, operatorText.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))
    return builder.Build(binary)
}

// Builds a three-child ternary `<cond> ? <then> : <else>` over leaf children.
func ConditionalTernaryLeafTree(conditionKind: int, conditionText: string, thenKind: int, thenText: string, elseKind: int, elseText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    condition := builder.AddLeaf(conditionKind, conditionText)
    thenArm := builder.AddLeaf(thenKind, thenText)
    elseArm := builder.AddLeaf(elseKind, elseText)
    ternary := builder.AddNode(ColumnarExpressionNodeKind.TernaryExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren3(condition, thenArm, elseArm))
    return builder.Build(ternary)
}

// `(true ? true : false) && <rightText>` — a ternary nested inside the left operand of `&&`.
func ConditionalNestedTernaryInAndTree(rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    condition := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression, "true")
    thenArm := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression, "true")
    elseArm := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression, "false")
    ternary := builder.AddNode(ColumnarExpressionNodeKind.TernaryExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren3(condition, thenArm, elseArm))
    operatorStart := builder.AddToken("&&")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression, rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(ternary, right))
    return builder.Build(binary)
}

func ConditionalPlanOwned(tree: ColumnarRangePlannerTestTree): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    bindings := ColumnarRangePlannerEmptyBindings()
    status := ColumnarConditionalPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), plan)
    if status != ColumnarFragmentPlanStatus.Planned {
        throw new InvalidOperationException("Expected conditional planner ownership.")
    }
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ConditionalPlanDeclines(tree: ColumnarRangePlannerTestTree) {
    plan := new ColumnarCodePlan()
    bindings := ColumnarRangePlannerEmptyBindings()
    status := ColumnarConditionalPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), plan)
    assert status == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "conditional planner emits the exact && short-circuit lowering and executes its truth table" {
    plan := ConditionalPlanOwned(ConditionalShortCircuitLiteralTree("&&", "true", "false"))
    assert plan.ResultType == typeof(bool)
    assert plan.LabelCount == 2
    assert plan.OperationCount == 7
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Brfalse()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Br()
    assert plan.OperationKinds[4] == ColumnarCodePlanContract.MarkLabelOperation()
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.LdcI4_0()
    assert plan.OperationKinds[6] == ColumnarCodePlanContract.MarkLabelOperation()

    assert ExecutorRunV3ScalarPlan(plan, typeof(bool)) == "False"
    assert ExecutorRunV3ScalarPlan(ConditionalPlanOwned(ConditionalShortCircuitLiteralTree("&&", "true", "true")), typeof(bool)) == "True"
    assert ExecutorRunV3ScalarPlan(ConditionalPlanOwned(ConditionalShortCircuitLiteralTree("&&", "false", "true")), typeof(bool)) == "False"
    assert ExecutorRunV3ScalarPlan(ConditionalPlanOwned(ConditionalShortCircuitLiteralTree("&&", "false", "false")), typeof(bool)) == "False"
}

test "conditional planner emits the exact || short-circuit lowering and executes its truth table" {
    plan := ConditionalPlanOwned(ConditionalShortCircuitLiteralTree("||", "true", "false"))
    assert plan.ResultType == typeof(bool)
    assert plan.LabelCount == 2
    assert plan.OperationCount == 7
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Brtrue()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Br()
    assert plan.OperationKinds[4] == ColumnarCodePlanContract.MarkLabelOperation()
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.LdcI4_1()
    assert plan.OperationKinds[6] == ColumnarCodePlanContract.MarkLabelOperation()

    assert ExecutorRunV3ScalarPlan(plan, typeof(bool)) == "True"
    assert ExecutorRunV3ScalarPlan(ConditionalPlanOwned(ConditionalShortCircuitLiteralTree("||", "false", "true")), typeof(bool)) == "True"
    assert ExecutorRunV3ScalarPlan(ConditionalPlanOwned(ConditionalShortCircuitLiteralTree("||", "false", "false")), typeof(bool)) == "False"
    assert ExecutorRunV3ScalarPlan(ConditionalPlanOwned(ConditionalShortCircuitLiteralTree("||", "true", "true")), typeof(bool)) == "True"
}

test "conditional planner emits the ternary branch-merge and selects the matching int arm" {
    plan := ConditionalPlanOwned(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "true", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.IntLiteralExpression, "9"))
    assert plan.ResultType == typeof(int)
    assert plan.LabelCount == 2
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Brfalse()
    assert ExecutorRunV3ScalarPlan(plan, typeof(int)) == "7"

    elsePlan := ConditionalPlanOwned(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "false", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.IntLiteralExpression, "9"))
    assert ExecutorRunV3ScalarPlan(elsePlan, typeof(int)) == "9"
}

test "conditional planner unifies reference-typed ternary arms" {
    plan := ConditionalPlanOwned(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "true", ColumnarExpressionNodeKind.StringLiteralExpression, "\"yes\"", ColumnarExpressionNodeKind.StringLiteralExpression, "\"no\""))
    assert plan.ResultType == typeof(string)
    assert ExecutorRunV3ScalarPlan(plan, typeof(string)) == "yes"
}

test "conditional planner plans a nested ternary inside a short-circuit operand" {
    truePlan := ConditionalPlanOwned(ConditionalNestedTernaryInAndTree("true"))
    assert truePlan.ResultType == typeof(bool)
    assert ExecutorRunV3ScalarPlan(truePlan, typeof(bool)) == "True"

    falsePlan := ConditionalPlanOwned(ConditionalNestedTernaryInAndTree("false"))
    assert ExecutorRunV3ScalarPlan(falsePlan, typeof(bool)) == "False"
}

test "conditional planner declines mixed-type ternary arms and rolls back" {
    ConditionalPlanDeclines(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "true", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.StringLiteralExpression, "\"no\""))
}

test "conditional planner declines a non-Boolean ternary condition and rolls back" {
    ConditionalPlanDeclines(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.IntLiteralExpression, "5", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.IntLiteralExpression, "9"))
}

test "conditional planner declines a non-Boolean short-circuit operand and rolls back" {
    ConditionalPlanDeclines(ConditionalShortCircuitRightLeafTree("&&", "true", ColumnarExpressionNodeKind.IntLiteralExpression, "5"))
    ConditionalPlanDeclines(ConditionalShortCircuitRightLeafTree("||", "false", ColumnarExpressionNodeKind.IntLiteralExpression, "5"))
}

test "conditional planner root gate claims ternary and short-circuit only" {
    ternary := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "true", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.IntLiteralExpression, "9")
    assert ColumnarConditionalPlanner.MayPlanRoot(ternary.Nodes, ternary.Source, ternary.Root)

    andTree := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    assert ColumnarConditionalPlanner.MayPlanRoot(andTree.Nodes, andTree.Source, andTree.Root)
    assert ColumnarConditionalPlanner.IsShortCircuitBinary(andTree.Nodes, andTree.Source, andTree.Root)

    orTree := ConditionalShortCircuitLiteralTree("||", "true", "false")
    assert ColumnarConditionalPlanner.MayPlanRoot(orTree.Nodes, orTree.Source, orTree.Root)

    plusTree := ConditionalShortCircuitLiteralTree("+", "true", "false")
    assert !ColumnarConditionalPlanner.MayPlanRoot(plusTree.Nodes, plusTree.Source, plusTree.Root)
    assert !ColumnarConditionalPlanner.IsShortCircuitBinary(plusTree.Nodes, plusTree.Source, plusTree.Root)

    identifier := new ColumnarRangePlannerNodeBuilder()
    identifierRoot := identifier.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "flag")
    identifierTree := identifier.Build(identifierRoot)
    assert !ColumnarConditionalPlanner.MayPlanRoot(identifierTree.Nodes, identifierTree.Source, identifierTree.Root)
}

test "conditional planner type preflight agrees with emission ownership" {
    ternary := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "true", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.IntLiteralExpression, "9")
    ternaryPlan := new ColumnarCodePlan()
    ternaryBindings := ColumnarRangePlannerEmptyBindings()
    ternaryOwned := false
    ternaryLegacy := false
    ternaryType := typeof(int)
    assert ColumnarConditionalPlanner.TryGetTypeRoot(ternary.Nodes, ternary.Source, ternary.Root, ternaryBindings, ColumnarRangeIndexHandles.Resolve(), ternaryPlan, out ternaryOwned, out ternaryLegacy, out ternaryType)
    assert ternaryOwned
    assert ternaryType == typeof(int)

    andTree := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    andPlan := new ColumnarCodePlan()
    andBindings := ColumnarRangePlannerEmptyBindings()
    andOwned := false
    andLegacy := false
    andType := typeof(int)
    assert ColumnarConditionalPlanner.TryGetTypeRoot(andTree.Nodes, andTree.Source, andTree.Root, andBindings, ColumnarRangeIndexHandles.Resolve(), andPlan, out andOwned, out andLegacy, out andType)
    assert andOwned
    assert andType == typeof(bool)
}

// ---- 015-B12: THE ROOT-APPEND SEQUENCE, OWNED ONCE AND ENTERED FROM TWO WRAPPERS ----

// `TryAppendRoot` is the sequence `Plan` used to inline. The contract that matters is that it appends
// the SAME rows whichever wrapper calls it, because that is the whole of emitting the same bytes: the
// standalone schema-v3 wrapper brackets it with `PrepareV3`/`CompleteV3`, and the method-body door
// calls it on an already-open schema-v4 plan and brackets it with nothing.
test "the conditional root-append sequence produces one row sequence for both of its wrappers" {
    ternary := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "true", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.IntLiteralExpression, "9")

    viaPlan := new ColumnarCodePlan()
    assert ColumnarConditionalPlanner.Plan(ternary.Nodes, ternary.Source, ternary.Root, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), viaPlan) == ColumnarFragmentPlanStatus.Planned

    viaAppend := new ColumnarCodePlan()
    viaAppend.PrepareV3()
    appendType := typeof(int)
    assert ColumnarConditionalPlanner.TryAppendRoot(ternary.Nodes, ternary.Source, ternary.Root, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), viaAppend, out appendType)
    assert appendType == typeof(int)

    // The wrapper contributes no rows of its own: `CompleteV3` seals a plan, it does not append to it.
    assert viaPlan.OperationCount == viaAppend.OperationCount
    i := 0
    while i < viaPlan.OperationCount {
        assert viaPlan.OperationKinds[i] == viaAppend.OperationKinds[i]
        assert viaPlan.OpCodeValues[i] == viaAppend.OpCodeValues[i]
        assert viaPlan.OperandKinds[i] == viaAppend.OperandKinds[i]
        assert viaPlan.OperandIndices[i] == viaAppend.OperandIndices[i]
        i = i + 1
    }
    assert viaPlan.LabelCount == viaAppend.LabelCount

    // ⚠ AND THE ROOT FRAGMENT'S RECORDED KIND IS THE CANDIDATE'S OWN, ASSERTED BECAUSE NOTHING ELSE
    // ASSERTS IT. `HasValidV2Fragments` checks only that a fragment kind is non-negative — it never
    // compares the recorded kind against the node `FragmentSourceNodeIndices` points at — so a
    // sequence that hard-coded one arm's kind for both would pass every other contract in the tree.
    assert viaAppend.FragmentKinds[0] == ColumnarExpressionNodeKind.TernaryExpression
    assert viaAppend.FragmentSourceNodeIndices[0] == ternary.Root
    assert viaPlan.FragmentKinds[0] == viaAppend.FragmentKinds[0]
}

// The short-circuit arm of the same sequence, and the same equality. `&&` and `||` differ only in the
// branch opcode and the merge constant, so both are walked rather than one.
test "the conditional root-append sequence covers both short-circuit operators" {
    andTree := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    andPlan := new ColumnarCodePlan()
    andPlan.PrepareV3()
    andType := typeof(int)
    assert ColumnarConditionalPlanner.TryAppendRoot(andTree.Nodes, andTree.Source, andTree.Root, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), andPlan, out andType)
    assert andType == typeof(bool)
    assert andPlan.LabelCount == 2

    orTree := ConditionalShortCircuitLiteralTree("||", "true", "false")
    orPlan := new ColumnarCodePlan()
    orPlan.PrepareV3()
    orType := typeof(int)
    assert ColumnarConditionalPlanner.TryAppendRoot(orTree.Nodes, orTree.Source, orTree.Root, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), orPlan, out orType)
    assert orType == typeof(bool)

    // Same row COUNT, different branch opcode — the two operators are one sequence with one flag.
    // The SHORT-CIRCUIT arm's root fragment carries kind 12, not 13 — the other half of the same
    // unenforced invariant, and the half a hard-coded ternary kind would have broken silently.
    assert andPlan.FragmentKinds[0] == ColumnarExpressionNodeKind.BinaryExpression
    assert orPlan.FragmentKinds[0] == ColumnarExpressionNodeKind.BinaryExpression
    assert andPlan.FragmentKinds[0] != ColumnarExpressionNodeKind.TernaryExpression

    assert andPlan.OperationCount == orPlan.OperationCount
    differing := 0
    i := 0
    while i < andPlan.OperationCount {
        if andPlan.OpCodeValues[i] != orPlan.OpCodeValues[i] {
            differing = differing + 1
        }
        i = i + 1
    }
    assert differing == 2
}

// The SOFTER null contract the door needs. `Plan` keeps throwing through `ValidateRootInputs`; the
// append entry a door may call with anything returns false instead of crashing the compiler.
test "the conditional root-append entry declines malformed input where Plan throws" {
    tree := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    resultType := typeof(int)

    assert !ColumnarConditionalPlanner.TryAppendRoot(null, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
    assert !ColumnarConditionalPlanner.TryAppendRoot(tree.Nodes, null, tree.Root, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
    assert !ColumnarConditionalPlanner.TryAppendRoot(tree.Nodes, tree.Source, -1, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
    assert !ColumnarConditionalPlanner.TryAppendRoot(tree.Nodes, tree.Source, tree.Nodes.Kinds.Length, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
    assert !ColumnarConditionalPlanner.TryAppendRoot(tree.Nodes, tree.Source, tree.Root, null, ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
    assert !ColumnarConditionalPlanner.TryAppendRoot(tree.Nodes, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), null, plan, out resultType)
    assert !ColumnarConditionalPlanner.TryAppendRoot(tree.Nodes, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), null, out resultType)

    // A decline leaves the plan untouched, which is what lets a door reuse one plan across one.
    assert plan.OperationCount == 0

    // And a shape that is neither a ternary nor a short-circuit declines rather than being claimed.
    plusTree := ConditionalShortCircuitLiteralTree("+", "true", "false")
    assert !ColumnarConditionalPlanner.TryAppendRoot(plusTree.Nodes, plusTree.Source, plusTree.Root, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
}

// ⚠ THE OPERATOR PARTITION IS A LENGTH FACT, AND IT IS WHY THE DOOR'S KIND-12 SPLIT IS SAFE.
// `ColumnarPrimitiveBinaryPlanner` claims one-character `&` and `|`; this owner claims two-character
// `&&` and `||`. Nothing arbitrates between them but `HasExactOperatorText`'s length test, so the
// partition is asserted from BOTH sides rather than assumed from one.
test "the two kind-12 owners partition the operator texts by length" {
    handles := ColumnarRangeIndexHandles.Resolve()

    andAnd := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    assert ColumnarConditionalPlanner.IsShortCircuitBinary(andAnd.Nodes, andAnd.Source, andAnd.Root)
    assert !ColumnarPrimitiveBinaryPlanner.MayPlanRoot(andAnd.Nodes, andAnd.Source, andAnd.Root)

    orOr := ConditionalShortCircuitLiteralTree("||", "true", "false")
    assert ColumnarConditionalPlanner.IsShortCircuitBinary(orOr.Nodes, orOr.Source, orOr.Root)
    assert !ColumnarPrimitiveBinaryPlanner.MayPlanRoot(orOr.Nodes, orOr.Source, orOr.Root)

    bitAnd := ConditionalShortCircuitLiteralTree("&", "true", "false")
    assert !ColumnarConditionalPlanner.IsShortCircuitBinary(bitAnd.Nodes, bitAnd.Source, bitAnd.Root)
    assert ColumnarPrimitiveBinaryPlanner.MayPlanRoot(bitAnd.Nodes, bitAnd.Source, bitAnd.Root)

    bitOr := ConditionalShortCircuitLiteralTree("|", "true", "false")
    assert !ColumnarConditionalPlanner.IsShortCircuitBinary(bitOr.Nodes, bitOr.Source, bitOr.Root)
    assert ColumnarPrimitiveBinaryPlanner.MayPlanRoot(bitOr.Nodes, bitOr.Source, bitOr.Root)

    // And the length test is the reason: a `&&` node is a kind-12 binary exactly as `&` is, so kind
    // alone cannot separate them and the door's split must ask the operator, which it does.
    assert andAnd.Nodes.Kind(andAnd.Root) == bitAnd.Nodes.Kind(bitAnd.Root)
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    resultType := typeof(int)
    assert !ColumnarPrimitiveBinaryPlanner.TryAppendRoot(andAnd.Nodes, andAnd.Source, andAnd.Root, ColumnarRangePlannerEmptyBindings(), handles, plan, out resultType)
}

// ---- `??` and the throw expression on the plan side (census ITER3) ----

// Builds `<left> ?? <right>` over string-literal leaves. The `??` token sits in the value span
// exactly where the parser records a binary operator.
func ConditionalCoalesceLiteralTree(leftText: string, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.StringLiteralExpression, leftText)
    operatorStart := builder.AddToken("??")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.StringLiteralExpression, rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))
    return builder.Build(binary)
}

// Builds `<left> ?? throw <string>` — the throw arm's operand is a leaf, which is all the gate below
// needs: the operand's own planning is the nested value owner's business.
func ConditionalCoalesceThrowTree(leftText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.StringLiteralExpression, leftText)
    operatorStart := builder.AddToken("??")
    operand := builder.AddLeaf(ColumnarExpressionNodeKind.StringLiteralExpression, "\"boom\"")
    throwNode := builder.AddNode(ColumnarExpressionNodeKind.ThrowExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(operand))
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, throwNode))
    return builder.Build(binary)
}

// `??` IS THE CONDITIONAL OWNER'S THIRD SHAPE, AND ITS GATE IS THE SAME LENGTH FACT `&&` RESTS ON:
// a `??` is a kind-12 binary exactly as `?` never is and `&` is, so only the operator text separates
// it from the primitive-binary owner's claim.
test "the null-coalesce gate claims ?? and nothing else on kind 12" {
    coalesce := ConditionalCoalesceLiteralTree("\"a\"", "\"b\"")
    assert ColumnarConditionalPlanner.IsNullCoalesceBinary(coalesce.Nodes, coalesce.Source, coalesce.Root)
    assert !ColumnarConditionalPlanner.IsShortCircuitBinary(coalesce.Nodes, coalesce.Source, coalesce.Root)
    assert !ColumnarPrimitiveBinaryPlanner.MayPlanRoot(coalesce.Nodes, coalesce.Source, coalesce.Root)

    andAnd := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    assert !ColumnarConditionalPlanner.IsNullCoalesceBinary(andAnd.Nodes, andAnd.Source, andAnd.Root)

    ternary := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "true", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.IntLiteralExpression, "9")
    assert !ColumnarConditionalPlanner.IsNullCoalesceBinary(ternary.Nodes, ternary.Source, ternary.Root)
}

// ⚠ THE V3 ROOT GATE DELIBERATELY DOES NOT CLAIM `??`. `MayPlanRoot` is what the EMITTER's cascade
// asks, and the emitter's own `op == "??"` arm still serves a `??` root in a body the plan-IR door
// declines. Widening `MayPlanRoot` would move that root onto a schema-v3 fragment, where `throw` is
// not an admissible opcode at all — so the claim stays on the METHOD-BODY door, which reaches
// `TryAppendRoot` directly.
test "the v3 root gate leaves a null-coalesce root to the emitter" {
    coalesce := ConditionalCoalesceLiteralTree("\"a\"", "\"b\"")
    assert !ColumnarConditionalPlanner.MayPlanRoot(coalesce.Nodes, coalesce.Source, coalesce.Root)
}

// A `throw` IS A METHOD-BODY (schema v4) SHAPE, and the gate says so before any row is appended: the
// `throw` opcode is only admissible in a method body, so a v3 expression fragment declines the whole
// candidate rather than appending a row it cannot execute.
test "a throw expression declines in a schema-v3 expression fragment" {
    tree := ConditionalCoalesceThrowTree("\"a\"")
    throwNode := tree.Nodes.Child(tree.Root, 1)
    assert ColumnarThrowExpressionPlanner.IsThrowExpression(tree.Nodes, throwNode)

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    assert !ColumnarThrowExpressionPlanner.TryAppendThrow(tree.Nodes, tree.Source, throwNode, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), plan, -1, 0)
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

// The predicate is a SHAPE test, not a kind test: a kind-83 node with the wrong child count is not a
// throw expression this owner will plan.
test "the throw expression predicate demands exactly one operand" {
    tree := ConditionalCoalesceThrowTree("\"a\"")
    assert !ColumnarThrowExpressionPlanner.IsThrowExpression(tree.Nodes, tree.Root)
    assert !ColumnarThrowExpressionPlanner.IsThrowExpression(tree.Nodes, -1)
}

// A THROW OPERAND THAT IS NOT AN EXCEPTION IS REFUSED. The runtime raises a reference, and a string
// literal is a reference that is not one — so the owner declines and the plan rolls back empty.
test "a throw expression declines an operand that is not an exception" {
    tree := ConditionalCoalesceThrowTree("\"a\"")
    throwNode := tree.Nodes.Child(tree.Root, 1)

    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    assert !ColumnarThrowExpressionPlanner.TryAppendThrow(tree.Nodes, tree.Source, throwNode, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), plan, -1, 0)
}

// ---- THE BRANCH-MERGE VALUE FAMILY AS SEEN BY THE CALL OWNER'S SYNTAX PREFLIGHT ----

// `IsBranchMergeValue` is the VALUE-position question, and it is deliberately wider than
// `MayPlanRoot`: the root gate must not claim a `??` (the legacy emitter arm still serves a
// schema-v3 `??` fragment), while every value position has owned all three forms since the
// dispatcher grew its arms.
test "the branch-merge value gate claims the ternary and all three merge binaries" {
    ternary := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression, "true", ColumnarExpressionNodeKind.IntLiteralExpression, "7", ColumnarExpressionNodeKind.IntLiteralExpression, "9")
    assert ColumnarConditionalPlanner.IsBranchMergeValue(ternary.Nodes, ternary.Source, ternary.Root)

    andTree := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    assert ColumnarConditionalPlanner.IsBranchMergeValue(andTree.Nodes, andTree.Source, andTree.Root)

    orTree := ConditionalShortCircuitLiteralTree("||", "true", "false")
    assert ColumnarConditionalPlanner.IsBranchMergeValue(orTree.Nodes, orTree.Source, orTree.Root)

    coalesce := ConditionalShortCircuitLiteralTree("??", "true", "false")
    assert ColumnarConditionalPlanner.IsBranchMergeValue(coalesce.Nodes, coalesce.Source, coalesce.Root)
    assert !ColumnarConditionalPlanner.MayPlanRoot(coalesce.Nodes, coalesce.Source, coalesce.Root)

    plusTree := ConditionalIntBinaryTree("+", "20", "22")
    assert !ColumnarConditionalPlanner.IsBranchMergeValue(plusTree.Nodes, plusTree.Source, plusTree.Root)
}

// The gate the call owner runs before it types an argument. It admits the branch-merge forms and
// still refuses a bare arithmetic binary, which is the partition `015-B9` drew and this slice keeps.
test "the call argument preflight admits a branch-merge and still refuses a bare arithmetic binary" {
    ternaryCall := DirectCallParsedTree("Accept(flag ? 1 : 2)")
    assert ColumnarDirectCallPlanner.IsAdmittedValueSyntax(ternaryCall.Nodes, ternaryCall.Source, ternaryCall.Root, 0)

    coalesceCall := DirectCallParsedTree("Accept(name ?? fallback)")
    assert ColumnarDirectCallPlanner.IsAdmittedValueSyntax(coalesceCall.Nodes, coalesceCall.Source, coalesceCall.Root, 0)

    shortCircuitCall := DirectCallParsedTree("Accept(left && right)")
    assert ColumnarDirectCallPlanner.IsAdmittedValueSyntax(shortCircuitCall.Nodes, shortCircuitCall.Source, shortCircuitCall.Root, 0)

    // The condition of an admitted ternary may itself be a comparison: an operand of a branch-merge
    // is planned through the construction-value surface, so the preflight asks the wider question.
    compoundCall := DirectCallParsedTree("Accept(count > 0 && count < 10 ? 1 : 2)")
    assert ColumnarDirectCallPlanner.IsAdmittedValueSyntax(compoundCall.Nodes, compoundCall.Source, compoundCall.Root, 0)

    arithmeticCall := DirectCallParsedTree("Accept(20 + 22)")
    assert !ColumnarDirectCallPlanner.IsAdmittedValueSyntax(arithmeticCall.Nodes, arithmeticCall.Source, arithmeticCall.Root, 0)
}
