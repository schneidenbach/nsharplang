namespace NSharpLang.Compiler.Columnar

import System

// Builds a two-child short-circuit binary `<left> <op> <right>` over Boolean-literal operands. The
// operator token sits in the node's value span exactly where the parser records it.
func ConditionalShortCircuitLiteralTree(operatorText: string, leftText: string, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression(), leftText)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression(), rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, operatorText.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))
    return builder.Build(binary)
}

// Builds a short-circuit binary whose right operand is an arbitrary leaf (for non-Boolean declines).
func ConditionalShortCircuitRightLeafTree(operatorText: string, leftText: string, rightKind: int, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression(), leftText)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(rightKind, rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, operatorText.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))
    return builder.Build(binary)
}

// Builds a three-child ternary `<cond> ? <then> : <else>` over leaf children.
func ConditionalTernaryLeafTree(conditionKind: int, conditionText: string, thenKind: int, thenText: string, elseKind: int, elseText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    condition := builder.AddLeaf(conditionKind, conditionText)
    thenArm := builder.AddLeaf(thenKind, thenText)
    elseArm := builder.AddLeaf(elseKind, elseText)
    ternary := builder.AddNode(ColumnarExpressionNodeKind.TernaryExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren3(condition, thenArm, elseArm))
    return builder.Build(ternary)
}

// `(true ? true : false) && <rightText>` — a ternary nested inside the left operand of `&&`.
func ConditionalNestedTernaryInAndTree(rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    condition := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true")
    thenArm := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true")
    elseArm := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression(), "false")
    ternary := builder.AddNode(ColumnarExpressionNodeKind.TernaryExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren3(condition, thenArm, elseArm))
    operatorStart := builder.AddToken("&&")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression(), rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(ternary, right))
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
    plan := ConditionalPlanOwned(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.IntLiteralExpression(), "9"))
    assert plan.ResultType == typeof(int)
    assert plan.LabelCount == 2
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Brfalse()
    assert ExecutorRunV3ScalarPlan(plan, typeof(int)) == "7"

    elsePlan := ConditionalPlanOwned(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "false", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.IntLiteralExpression(), "9"))
    assert ExecutorRunV3ScalarPlan(elsePlan, typeof(int)) == "9"
}

test "conditional planner unifies reference-typed ternary arms" {
    plan := ConditionalPlanOwned(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.StringLiteralExpression(), "\"yes\"", ColumnarExpressionNodeKind.StringLiteralExpression(), "\"no\""))
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
    ConditionalPlanDeclines(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.StringLiteralExpression(), "\"no\""))
}

test "conditional planner declines a non-Boolean ternary condition and rolls back" {
    ConditionalPlanDeclines(ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.IntLiteralExpression(), "5", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.IntLiteralExpression(), "9"))
}

test "conditional planner declines a non-Boolean short-circuit operand and rolls back" {
    ConditionalPlanDeclines(ConditionalShortCircuitRightLeafTree("&&", "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "5"))
    ConditionalPlanDeclines(ConditionalShortCircuitRightLeafTree("||", "false", ColumnarExpressionNodeKind.IntLiteralExpression(), "5"))
}

test "conditional planner root gate claims ternary and short-circuit only" {
    ternary := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.IntLiteralExpression(), "9")
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
    identifierRoot := identifier.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "flag")
    identifierTree := identifier.Build(identifierRoot)
    assert !ColumnarConditionalPlanner.MayPlanRoot(identifierTree.Nodes, identifierTree.Source, identifierTree.Root)
}

test "conditional planner type preflight agrees with emission ownership" {
    ternary := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.IntLiteralExpression(), "9")
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
