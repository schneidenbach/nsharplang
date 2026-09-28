namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic


// Native contracts for WHAT A CONDITION PROVES AT EMIT — the reader that lets the emitter unwrap a
// `Nullable<T>` the analyzer already narrowed.
//
// (1) IT IS THE ANALYZER'S RULE OVER THE OTHER REPRESENTATION, and the arms are written against
// `AnalyzerFlowNarrowing`'s one for one: `x != null` proves `x` in the TRUE branch, `x == null` in
// the FALSE one, a parenthesis is transparent, `!c` swaps the two lists, `a && b` proves both sides
// in the true branch and nothing in the false one, `a || b` is the mirror, and `x.HasValue` proves
// its receiver in the true branch alone.
//
// (2) A FACT IS ABOUT A STABLE PATH, SPELLED AS THE ANALYZER SPELLS IT. `doc.Text != null` proves
// `"doc.Text"`, `this.Slot` proves `"this.Slot"`, and a `?.` chain proves its tested receivers along
// with the path — the analyzer files the same null facts under the same dotted names, and the
// emitter unwraps a proved `Nullable<T>` path exactly as it unwraps a proved local. A call or an
// index anywhere in the chain is not stable and proves nothing.
//
// (3) NOTHING IS EVALUATED. A condition whose value cannot be seen on the syntax proves nothing in
// either direction, and the ONE exception is the literal `true`/`false` that collapses an `&&` or an
// `||` onto its surviving side — the same exception the analyzer makes and for the same reason.
//
// (4) THE ASSIGNMENT SCAN IS WHAT ENDS A NARROWING. Every path a subtree writes — an assignment, a
// step, a `ref`/`out` argument, a declaration, a loop variable — stops being narrowed, and so does
// every path UNDER it, which is what keeps a loop that resets the name honest.
func NarrowingNullTree(name: string, operatorText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, name)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, operatorText.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))

    return builder.Build(root)
}

func NarrowingNames(tree: ColumnarRangePlannerTestTree, wantThen: bool): List<string> {
    split := ColumnarFlowNarrowingFacts.Extract(tree.Nodes, tree.Source, tree.Root)
    if wantThen {
        return split.Then
    }

    return split.Else
}

func NarrowingProves(tree: ColumnarRangePlannerTestTree, wantThen: bool, name: string): bool {
    return NarrowingNames(tree, wantThen).Contains(name)
}

test "x != null PROVES x IN THE TRUE BRANCH AND x == null PROVES IT IN THE FALSE ONE" {
    notEqual := NarrowingNullTree("value", "!=")

    assert NarrowingProves(notEqual, true, "value")
    assert NarrowingNames(notEqual, false).Count == 0

    equal := NarrowingNullTree("value", "==")

    assert NarrowingProves(equal, false, "value")
    assert NarrowingNames(equal, true).Count == 0
}

test "census flow rules: a loop body receives the true facts from its null condition" {
    condition := NarrowingNullTree("value", "!=")
    split := ColumnarFlowNarrowingFacts.Extract(condition.Nodes, condition.Source, condition.Root)

    assert split.Then.Count == 1
    assert split.Then[0] == "value"
    assert split.Else.Count == 0
}

test "THE LITERAL MAY BE WRITTEN ON EITHER SIDE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    operatorStart := builder.AddToken("!=")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "value")
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))
    reversed := builder.Build(root)

    assert NarrowingProves(reversed, true, "value")
}

test "A PARENTHESIS IS TRANSPARENT AND A ! SWAPS THE TWO LISTS" {
    inner := NarrowingNullTree("value", "!=")
    builder := new ColumnarRangePlannerNodeBuilder()
    identifier := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "value")
    operatorStart := builder.AddToken("!=")
    literal := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    comparison := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(identifier, literal))
    parenthesized := builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(comparison))
    bangStart := builder.AddToken("!")
    negation := builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression, bangStart, 1, 0, builder.Source.Length, ColumnarRangePlannerChildren1(parenthesized))

    parenthesizedTree := builder.Build(parenthesized)

    assert NarrowingProves(parenthesizedTree, true, "value")
    assert NarrowingProves(inner, true, "value")

    negatedTree := builder.Build(negation)

    assert NarrowingProves(negatedTree, false, "value")
    assert NarrowingNames(negatedTree, true).Count == 0
}

test "AN && PROVES BOTH SIDES IN THE TRUE BRANCH AND NOTHING IN THE FALSE ONE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    leftName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "left")
    leftOperator := builder.AddToken("!=")
    leftNull := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    leftTest := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, leftOperator, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(leftName, leftNull))
    andStart := builder.AddToken("&&")
    rightName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "right")
    rightOperator := builder.AddToken("!=")
    rightNull := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    rightTest := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, rightOperator, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(rightName, rightNull))
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, andStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(leftTest, rightTest))
    tree := builder.Build(root)

    assert NarrowingProves(tree, true, "left")
    assert NarrowingProves(tree, true, "right")
    assert NarrowingNames(tree, false).Count == 0
}

test "AN || PROVES BOTH SIDES IN THE FALSE BRANCH AND NOTHING IN THE TRUE ONE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    leftName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "left")
    leftOperator := builder.AddToken("==")
    leftNull := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    leftTest := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, leftOperator, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(leftName, leftNull))
    orStart := builder.AddToken("||")
    rightName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "right")
    rightOperator := builder.AddToken("==")
    rightNull := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    rightTest := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, rightOperator, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(rightName, rightNull))
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, orStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(leftTest, rightTest))
    tree := builder.Build(root)

    assert NarrowingProves(tree, false, "left")
    assert NarrowingProves(tree, false, "right")
    assert NarrowingNames(tree, true).Count == 0
}

test "x.HasValue PROVES ITS RECEIVER IN THE TRUE BRANCH ALONE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "value")
    builder.AddToken(".")
    memberStart := builder.AddToken("HasValue")
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression, memberStart, 8, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
    tree := builder.Build(root)

    assert NarrowingProves(tree, true, "value")
    assert NarrowingNames(tree, false).Count == 0
}

// `receiver.member`, as the parser lays it out: the member name in the access node's value span and
// the receiver as its one child.
func NarrowingMemberAccess(builder: ColumnarRangePlannerNodeBuilder, receiver: int, member: string): int {
    builder.AddToken(".")
    memberStart := builder.AddToken(member)
    return builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression, memberStart, member.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
}

func NarrowingAgainstNull(builder: ColumnarRangePlannerNodeBuilder, value: int, operatorText: string): int {
    operatorStart := builder.AddToken(operatorText)
    literal := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    return builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression, operatorStart, operatorText.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren2(value, literal))
}

test "A MEMBER PATH IS PROVED UNDER ITS DOTTED NAME, IN BOTH DIRECTIONS" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "doc")
    path := NarrowingMemberAccess(builder, receiver, "Text")
    notEqual := builder.Build(NarrowingAgainstNull(builder, path, "!="))

    assert NarrowingProves(notEqual, true, "doc.Text")
    assert !NarrowingProves(notEqual, true, "doc")
    assert NarrowingNames(notEqual, false).Count == 0

    equal := builder.Build(NarrowingAgainstNull(builder, path, "=="))

    assert NarrowingProves(equal, false, "doc.Text")
    assert NarrowingNames(equal, true).Count == 0
}

test "`this.P` AND A TWO-HOP PATH ARE PATHS, AND A PARENTHESISED RECEIVER IS ITS RECEIVER" {
    builder := new ColumnarRangePlannerNodeBuilder()
    self := builder.AddLeaf(ColumnarExpressionNodeKind.ThisExpression, "this")
    thisPath := NarrowingMemberAccess(builder, self, "Slot")
    thisTree := builder.Build(NarrowingAgainstNull(builder, thisPath, "!="))

    assert NarrowingProves(thisTree, true, "this.Slot")

    outer := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "h")
    parenthesized := builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(outer))
    next := NarrowingMemberAccess(builder, parenthesized, "Next")
    deep := NarrowingMemberAccess(builder, next, "Slot")
    deepTree := builder.Build(NarrowingAgainstNull(builder, deep, "!="))

    assert NarrowingProves(deepTree, true, "h.Next.Slot")
    assert !NarrowingProves(deepTree, true, "h.Next")
}

test "`x.HasValue` PROVES A MEMBER PATH IN THE TRUE BRANCH ALONE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "h")
    path := NarrowingMemberAccess(builder, receiver, "Slot")
    hasValue := NarrowingMemberAccess(builder, path, "HasValue")
    tree := builder.Build(hasValue)

    assert NarrowingProves(tree, true, "h.Slot")
    assert NarrowingNames(tree, false).Count == 0

    bangStart := builder.AddToken("!")
    negated := builder.Build(builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression, bangStart, 1, 0, builder.Source.Length, ColumnarRangePlannerChildren1(hasValue)))

    assert NarrowingProves(negated, false, "h.Slot")
    assert NarrowingNames(negated, true).Count == 0
}

test "A `?.` CHAIN PROVES ITS TESTED RECEIVER WITH THE PATH, ON THE SIDE THAT RULES BOTH OUT" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "h")
    guard := builder.AddNode(ColumnarExpressionNodeKind.NullGuardExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
    chain := NarrowingMemberAccess(builder, guard, "Slot")
    equal := builder.Build(NarrowingAgainstNull(builder, chain, "=="))

    // `h?.Slot == null` is true when EITHER is null — the true side proves nothing.
    assert NarrowingNames(equal, true).Count == 0
    assert NarrowingProves(equal, false, "h")
    assert NarrowingProves(equal, false, "h.Slot")

    notEqual := builder.Build(NarrowingAgainstNull(builder, chain, "!="))

    assert NarrowingProves(notEqual, true, "h")
    assert NarrowingProves(notEqual, true, "h.Slot")
    assert NarrowingNames(notEqual, false).Count == 0
}

test "A CALL OR AN INDEX IN THE PATH, AND AN UNREADABLE CONDITION, PROVE NOTHING" {
    builder := new ColumnarRangePlannerNodeBuilder()
    callee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "Load")
    call := builder.AddNode(ColumnarExpressionNodeKind.CallExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(callee))
    throughCall := NarrowingMemberAccess(builder, call, "Text")
    callTree := builder.Build(NarrowingAgainstNull(builder, throughCall, "!="))

    assert NarrowingNames(callTree, true).Count == 0
    assert NarrowingNames(callTree, false).Count == 0

    rows := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "rows")
    position := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression, "0")
    index := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(rows, position))
    throughIndex := NarrowingMemberAccess(builder, index, "Text")
    indexTree := builder.Build(NarrowingAgainstNull(builder, throughIndex, "!="))

    assert NarrowingNames(indexTree, true).Count == 0

    // A comparison against something that is not the null literal is not a null test at all.
    other := new ColumnarRangePlannerNodeBuilder()
    left := other.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "value")
    otherOperator := other.AddToken("!=")
    right := other.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression, "0")
    otherRoot := other.AddNode(ColumnarExpressionNodeKind.BinaryExpression, otherOperator, 2, 0, other.Source.Length, ColumnarRangePlannerChildren2(left, right))
    otherTree := other.Build(otherRoot)

    assert NarrowingNames(otherTree, true).Count == 0
    assert NarrowingNames(otherTree, false).Count == 0
}

test "A WRITE ENDS THE PATH IT NAMES AND EVERY PATH UNDER IT, AND NO SIBLING" {
    assert ColumnarFlowNarrowingFacts.IsInvalidatedBy("h.Slot", "h.Slot")
    assert ColumnarFlowNarrowingFacts.IsInvalidatedBy("h.Slot", "h")
    assert ColumnarFlowNarrowingFacts.IsInvalidatedBy("h.Next.Slot", "h.Next")
    assert !ColumnarFlowNarrowingFacts.IsInvalidatedBy("h", "h.Slot")
    assert !ColumnarFlowNarrowingFacts.IsInvalidatedBy("hx.Slot", "h")
    assert !ColumnarFlowNarrowingFacts.IsInvalidatedBy("h.SlotB", "h.Slot")
}

test "THE ASSIGNMENT SCAN NAMES A MEMBER TARGET BY ITS PATH, AND A `ref`/`out` ARGUMENT IS A WRITE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "h")
    target := NarrowingMemberAccess(builder, receiver, "Slot")
    assignStart := builder.AddToken("=")
    value := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression, "null")
    assignment := builder.AddNode(ColumnarExpressionNodeKind.AssignmentExpression, assignStart, 1, 0, builder.Source.Length, ColumnarRangePlannerChildren2(target, value))
    callee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "Refill")
    outStart := builder.AddToken("out")
    refilled := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "current")
    outArgument := builder.AddNode(ColumnarExpressionNodeKind.RefOutArgument, outStart, 3, 0, builder.Source.Length, ColumnarRangePlannerChildren1(refilled))
    call := builder.AddNode(ColumnarExpressionNodeKind.CallExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(callee, outArgument))
    block := builder.AddNode(ColumnarStatementNodeKind.BlockStatement, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(assignment, call))
    tree := builder.Build(block)

    assigned := new HashSet<string>()
    ColumnarFlowNarrowingFacts.CollectAssignedNames(tree.Nodes, tree.Source, tree.Root, assigned)

    assert assigned.Contains("h.Slot")
    assert assigned.Contains("current")
    assert !assigned.Contains("h")
    assert !assigned.Contains("Refill")
}

test "THE ASSIGNMENT SCAN FINDS EVERY NAME A SUBTREE WRITES AND NO OTHER" {
    builder := new ColumnarRangePlannerNodeBuilder()
    target := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "value")
    assignStart := builder.AddToken("=")
    source := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "other")
    assignment := builder.AddNode(14, assignStart, 1, 0, builder.Source.Length, ColumnarRangePlannerChildren2(target, source))
    statement := builder.AddNode(23, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(assignment))
    tree := builder.Build(statement)

    assigned := new HashSet<string>()
    ColumnarFlowNarrowingFacts.CollectAssignedNames(tree.Nodes, tree.Source, tree.Root, assigned)

    assert assigned.Contains("value")
    assert !assigned.Contains("other")
}

test "A `:=` DECLARATION BINDS ITS NAME AND SO ENDS ANY NARROWING OF IT" {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := builder.AddToken("value")
    initializer := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression, "1")
    declaration := builder.AddNode(24, nameStart, 5, 0, builder.Source.Length, ColumnarRangePlannerChildren1(initializer))
    tree := builder.Build(declaration)

    assigned := new HashSet<string>()
    ColumnarFlowNarrowingFacts.CollectAssignedNames(tree.Nodes, tree.Source, tree.Root, assigned)

    assert assigned.Contains("value")
}

// A `ref` or `out` ARGUMENT WRITES THE NAME IT PASSES, as the analyzer's loop kill set says; an `in`
// argument only reads it.
func NarrowingModifiedArgument(modifier: string): HashSet<string> {
    builder := new ColumnarRangePlannerNodeBuilder()
    keywordStart := builder.AddToken(modifier)
    target := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression, "value")
    argument := builder.AddNode(ColumnarExpressionNodeKind.RefOutArgument, keywordStart, modifier.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(target))
    tree := builder.Build(argument)

    assigned := new HashSet<string>()
    ColumnarFlowNarrowingFacts.CollectAssignedNames(tree.Nodes, tree.Source, tree.Root, assigned)
    return assigned
}

test "A `ref` OR `out` ARGUMENT WRITES ITS NAME AND AN `in` ARGUMENT DOES NOT" {
    assert NarrowingModifiedArgument("out").Contains("value")
    assert NarrowingModifiedArgument("ref").Contains("value")
    assert NarrowingModifiedArgument("in").Count == 0
}
