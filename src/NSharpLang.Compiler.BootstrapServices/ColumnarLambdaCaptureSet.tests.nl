namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

// Build a HashSet<string> (ordinal) from a name array — the capture fixtures' enclosing-capturable and
// bound-parameter sets.
func CaptureSetNames(values: string[]): HashSet<string> {
    set := new HashSet<string>(StringComparer.Ordinal)
    index := 0
    while index < values.Length {
        set.Add(values[index])
        index = index + 1
    }

    return set
}

func CaptureSetEmptyNames(): HashSet<string> {
    return new HashSet<string>(StringComparer.Ordinal)
}

test "capture set captures an enclosing name read in the body" {
    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "count")
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "count"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 1
    assert captures.Contains("count")
}

test "capture set captures multiple enclosing names through a container expression" {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "total")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "amount")
    operatorStart := builder.AddToken("+")
    children := new int[](2)
    children[0] = left
    children[1] = right
    root := builder.AddNode(
        ColumnarExpressionNodeKind.BinaryExpression(),
        operatorStart,
        1,
        operatorStart,
        1,
        children
    )
    tree := builder.Build(root)

    enclosing := new string[](2)
    enclosing[0] = "total"
    enclosing[1] = "amount"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 2
    assert captures.Contains("total")
    assert captures.Contains("amount")
}

test "capture set excludes a name bound by the lambda's own parameters" {
    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "x")
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "x"
    bound := new string[](1)
    bound[0] = "x"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetNames(bound),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 0
}

test "capture set excludes a nested lambda's parameter but captures its free names" {
    builder := new ColumnarRangePlannerNodeBuilder()
    nestedParameter := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "y")
    bodyLeft := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "y")
    bodyRight := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "z")
    operatorStart := builder.AddToken("+")
    bodyChildren := new int[](2)
    bodyChildren[0] = bodyLeft
    bodyChildren[1] = bodyRight
    nestedBody := builder.AddNode(
        ColumnarExpressionNodeKind.BinaryExpression(),
        operatorStart,
        1,
        operatorStart,
        1,
        bodyChildren
    )
    // Kind 39 is the parser's lambda node: children = [param identifiers..., body].
    lambdaChildren := new int[](2)
    lambdaChildren[0] = nestedParameter
    lambdaChildren[1] = nestedBody
    root := builder.AddNode(39, -1, 0, 0, builder.Source.Length, lambdaChildren)
    tree := builder.Build(root)

    enclosing := new string[](2)
    enclosing[0] = "y"
    enclosing[1] = "z"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 1
    assert captures.Contains("z")
    assert !captures.Contains("y")
}

test "capture set captures a member-access base but not the member name" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "item")
    // A member access (kind 8) carries the member NAME in its value span and the receiver as its only
    // child, so the member name is never a capture candidate; only the base is walked.
    memberStart := builder.AddToken("Tags")
    memberChildren := new int[](1)
    memberChildren[0] = receiver
    root := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        memberStart,
        4,
        memberStart,
        4,
        memberChildren
    )
    tree := builder.Build(root)

    enclosing := new string[](2)
    enclosing[0] = "item"
    enclosing[1] = "Tags"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 1
    assert captures.Contains("item")
    assert !captures.Contains("Tags")
}

test "capture set steps over the type child of a cast expression" {
    builder := new ColumnarRangePlannerNodeBuilder()
    typeChild := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "Widget")
    valueChild := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "w")
    // A cast (kind 16) has its TYPE subtree at child[0] and the value at child[1]; the type child is
    // never a capture candidate.
    castChildren := new int[](2)
    castChildren[0] = typeChild
    castChildren[1] = valueChild
    root := builder.AddNode(
        ColumnarExpressionNodeKind.CastExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        castChildren
    )
    tree := builder.Build(root)

    enclosing := new string[](2)
    enclosing[0] = "Widget"
    enclosing[1] = "w"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 1
    assert captures.Contains("w")
    assert !captures.Contains("Widget")
}

test "capture set skips a typeof subtree entirely" {
    builder := new ColumnarRangePlannerNodeBuilder()
    typeChild := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "T")
    typeofChildren := new int[](1)
    typeofChildren[0] = typeChild
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        typeofChildren
    )
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "T"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 0
}

test "capture set skips a value-less masquerading type identifier" {
    builder := new ColumnarRangePlannerNodeBuilder()
    // A value-less identifier (valueStart -1) is a masquerading TYPE node, never a name read; the scan
    // must skip it without reading its text.
    root := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), -1, 0, 0, 0, new int[](0))
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "ignored"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 0
}

test "capture set does not capture a name absent from the enclosing scope" {
    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "localOnly")
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "other"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 0
}
