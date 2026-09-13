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
// (2) ONLY A SIMPLE NAME IS COLLECTED. A member path's storage is not the body's to re-type, so
// `doc.Text != null` proves nothing this reader can act on — the analyzer still records the null
// state, and the emitter simply has nothing to unwrap.
//
// (3) NOTHING IS EVALUATED. A condition whose value cannot be seen on the syntax proves nothing in
// either direction, and the ONE exception is the literal `true`/`false` that collapses an `&&` or an
// `||` onto its surviving side — the same exception the analyzer makes and for the same reason.
//
// (4) THE ASSIGNMENT SCAN IS WHAT ENDS A NARROWING. Every name a subtree writes — an assignment, a
// step, a declaration, a loop variable — stops being narrowed, which is what keeps a loop that
// resets the name honest.
func NarrowingNullTree(name: string, operatorText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, operatorText.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))

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

test "THE LITERAL MAY BE WRITTEN ON EITHER SIDE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    operatorStart := builder.AddToken("!=")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "value")
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(left, right))
    reversed := builder.Build(root)

    assert NarrowingProves(reversed, true, "value")
}

test "A PARENTHESIS IS TRANSPARENT AND A ! SWAPS THE TWO LISTS" {
    inner := NarrowingNullTree("value", "!=")
    builder := new ColumnarRangePlannerNodeBuilder()
    identifier := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "value")
    operatorStart := builder.AddToken("!=")
    literal := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    comparison := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(identifier, literal))
    parenthesized := builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(comparison))
    bangStart := builder.AddToken("!")
    negation := builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression(), bangStart, 1, 0, builder.Source.Length, ColumnarRangePlannerChildren1(parenthesized))

    parenthesizedTree := builder.Build(parenthesized)

    assert NarrowingProves(parenthesizedTree, true, "value")
    assert NarrowingProves(inner, true, "value")

    negatedTree := builder.Build(negation)

    assert NarrowingProves(negatedTree, false, "value")
    assert NarrowingNames(negatedTree, true).Count == 0
}

test "AN && PROVES BOTH SIDES IN THE TRUE BRANCH AND NOTHING IN THE FALSE ONE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    leftName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "left")
    leftOperator := builder.AddToken("!=")
    leftNull := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    leftTest := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), leftOperator, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(leftName, leftNull))
    andStart := builder.AddToken("&&")
    rightName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "right")
    rightOperator := builder.AddToken("!=")
    rightNull := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    rightTest := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), rightOperator, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(rightName, rightNull))
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), andStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(leftTest, rightTest))
    tree := builder.Build(root)

    assert NarrowingProves(tree, true, "left")
    assert NarrowingProves(tree, true, "right")
    assert NarrowingNames(tree, false).Count == 0
}

test "AN || PROVES BOTH SIDES IN THE FALSE BRANCH AND NOTHING IN THE TRUE ONE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    leftName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "left")
    leftOperator := builder.AddToken("==")
    leftNull := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    leftTest := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), leftOperator, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(leftName, leftNull))
    orStart := builder.AddToken("||")
    rightName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "right")
    rightOperator := builder.AddToken("==")
    rightNull := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    rightTest := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), rightOperator, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(rightName, rightNull))
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), orStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(leftTest, rightTest))
    tree := builder.Build(root)

    assert NarrowingProves(tree, false, "left")
    assert NarrowingProves(tree, false, "right")
    assert NarrowingNames(tree, true).Count == 0
}

test "x.HasValue PROVES ITS RECEIVER IN THE TRUE BRANCH ALONE" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "value")
    builder.AddToken(".")
    memberStart := builder.AddToken("HasValue")
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, 8, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
    tree := builder.Build(root)

    assert NarrowingProves(tree, true, "value")
    assert NarrowingNames(tree, false).Count == 0
}

test "A MEMBER PATH AND AN UNREADABLE CONDITION BOTH PROVE NOTHING" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "doc")
    builder.AddToken(".")
    memberStart := builder.AddToken("Text")
    path := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, 4, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
    operatorStart := builder.AddToken("!=")
    literal := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    root := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 2, 0, builder.Source.Length, ColumnarRangePlannerChildren2(path, literal))
    tree := builder.Build(root)

    assert NarrowingNames(tree, true).Count == 0
    assert NarrowingNames(tree, false).Count == 0

    // A comparison against something that is not the null literal is not a null test at all.
    other := new ColumnarRangePlannerNodeBuilder()
    left := other.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "value")
    otherOperator := other.AddToken("!=")
    right := other.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    otherRoot := other.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), otherOperator, 2, 0, other.Source.Length, ColumnarRangePlannerChildren2(left, right))
    otherTree := other.Build(otherRoot)

    assert NarrowingNames(otherTree, true).Count == 0
    assert NarrowingNames(otherTree, false).Count == 0
}

test "THE ASSIGNMENT SCAN FINDS EVERY NAME A SUBTREE WRITES AND NO OTHER" {
    builder := new ColumnarRangePlannerNodeBuilder()
    target := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "value")
    assignStart := builder.AddToken("=")
    source := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "other")
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
    initializer := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    declaration := builder.AddNode(24, nameStart, 5, 0, builder.Source.Length, ColumnarRangePlannerChildren1(initializer))
    tree := builder.Build(declaration)

    assigned := new HashSet<string>()
    ColumnarFlowNarrowingFacts.CollectAssignedNames(tree.Nodes, tree.Source, tree.Root, assigned)

    assert assigned.Contains("value")
}
