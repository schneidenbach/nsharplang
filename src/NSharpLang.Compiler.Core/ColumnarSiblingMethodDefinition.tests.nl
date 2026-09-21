namespace NSharpLang.Compiler.Columnar

import System


// THE kind-38 CHILD LAYOUT, PINNED AGAINST A HAND-BUILT TABLE.
//
// These rows replace the ones that pinned `ColumnarGenericExtensionReceiverChain`, the TEXT reading
// of a generic callee's receiver that this layout supersedes. That owner answered a question about
// SPELLING — is every dot-separated segment of the callee's value span a plain identifier — and its
// whole purpose was to refuse a receiver the tree did not carry. The tree carries it now, so the
// question is about the CHILD RUN instead, and it is asked here.
//
// `values.OfType<string>()` builds as: an identifier receiver, a member access naming `OfType` over
// it, a kind-38 whose children are [that member access, the `string` type root], and a call whose
// child 0 is the kind-38. The dotted value span is retained beside the children because the
// dotted-name tiers still read the written spelling.
func GenericCalleeDottedFixture(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "values")
    memberStart := builder.AddToken(".OfType")
    memberChildren: int[] = [receiver]
    member := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart + 1, 6, 0, memberStart + 7, memberChildren)
    typeArgument := builder.AddLeaf(0, "string")
    calleeChildren: int[] = [member, typeArgument]
    callee := builder.AddNode(38, 0, memberStart + 7, 0, builder.Source.Length, calleeChildren)
    callChildren: int[] = [callee]
    call := builder.AddNode(ColumnarExpressionNodeKind.CallExpression(), -1, 0, 0, builder.Source.Length, callChildren)
    return builder.Build(call)
}

// The bare spelling `Pick<int>(…)`: child 0 is a kind-6 identifier, so there is NO receiver to load
// and `ReceiverNode` says so rather than handing back a type-argument root.
func GenericCalleeBareFixture(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    calleeStart := builder.AddToken("Pick")
    calleeExpression := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), calleeStart, 4, calleeStart, 4, new int[](0))
    first := builder.AddLeaf(0, "int")
    second := builder.AddLeaf(0, "string")
    calleeChildren: int[] = [calleeExpression, first, second]
    callee := builder.AddNode(38, calleeStart, 4, calleeStart, builder.Source.Length, calleeChildren)
    return builder.Build(callee)
}

test "a dotted generic callee carries its receiver as child 0 and its type arguments after it" {
    tree := GenericCalleeDottedFixture()
    nodes := tree.Nodes
    call := tree.Root
    callee := nodes.Child(call, 0)

    assert nodes.Kind(callee) == 38
    // FOUR children on the kind-38 would be three type arguments under the old layout. The count is
    // the type-argument count PLUS the callee expression, and the facts owner is what states that.
    assert nodes.ChildCount(callee) == 2
    assert ColumnarGenericCalleeFacts.TypeArgumentCount(nodes, callee) == 1

    calleeExpression := ColumnarGenericCalleeFacts.CalleeExpressionNode(nodes, callee)
    assert nodes.Kind(calleeExpression) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(tree.Source, calleeExpression) == "OfType"

    receiver := ColumnarGenericCalleeFacts.ReceiverNode(nodes, callee)
    assert receiver >= 0
    assert nodes.Kind(receiver) == ColumnarExpressionNodeKind.IdentifierExpression()
    assert nodes.Text(tree.Source, receiver) == "values"

    typeArgument := ColumnarGenericCalleeFacts.TypeArgumentNode(nodes, callee, 0)
    assert typeArgument != receiver
    assert typeArgument != calleeExpression
    assert nodes.Text(tree.Source, typeArgument) == "string"

    // The written spelling is still on the node, because the dotted-name tiers read it.
    assert nodes.Text(tree.Source, callee) == "values.OfType"
}

test "a bare generic callee has no receiver and its type arguments start at child 1" {
    tree := GenericCalleeBareFixture()
    nodes := tree.Nodes
    callee := tree.Root

    assert nodes.Kind(callee) == 38
    assert nodes.ChildCount(callee) == 3
    assert ColumnarGenericCalleeFacts.TypeArgumentCount(nodes, callee) == 2
    assert ColumnarGenericCalleeFacts.ReceiverNode(nodes, callee) == -1

    calleeExpression := ColumnarGenericCalleeFacts.CalleeExpressionNode(nodes, callee)
    assert nodes.Kind(calleeExpression) == ColumnarExpressionNodeKind.IdentifierExpression()
    assert nodes.Text(tree.Source, calleeExpression) == "Pick"

    assert nodes.Text(tree.Source, ColumnarGenericCalleeFacts.TypeArgumentNode(nodes, callee, 0)) == "int"
    assert nodes.Text(tree.Source, ColumnarGenericCalleeFacts.TypeArgumentNode(nodes, callee, 1)) == "string"
}
