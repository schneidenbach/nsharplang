namespace NSharpLang.Compiler

import System


// THE NULL-CONDITIONAL CALL, AND WHAT IT IS DELIBERATELY NOT.
//
// `receiver?.Member(args)` is the ONE shape the columnar parser builds for `?.`, and it is built into
// a NODE KIND OF ITS OWN rather than into `MemberAccessExpression`, because the two do not mean the
// same thing: this one evaluates its receiver once, tests it for null, and skips the member entirely.
// A planner that read it as an ordinary member access would silently drop the null test, which is a
// wrong program rather than a slow one.
//
// The three refusals below are the whole safety argument for a link-at-a-time parser. `a?.B` as a
// READ, and any NON-conditional link written after a conditional one, would both have to be skipped
// along with the conditional — a chain the kernel cannot express — so the DECLARATION is refused
// instead of half-lowered. `?.M()?.N()` is allowed because `(a?.M())?.N()` means the same thing.
func ConditionalCallTree(source: string): ColumnarNodeTable {
    probe := new ColumnarNumericLiteralParseProbe(source)
    if probe.NodeCount <= 0 || probe.ParseResult[0] < 0 {
        throw new InvalidOperationException("The conditional-call fixture did not produce an expression tree.")
    }

    return new ColumnarNodeTable(probe.NodeKinds, probe.NodeValueStarts, probe.NodeValueLengths, probe.NodeChildStarts, probe.NodeChildCounts, probe.NodeChildren, probe.NodeSpanStarts, probe.NodeSpanLengths)
}

func ConditionalCallRoot(source: string): int {
    probe := new ColumnarNumericLiteralParseProbe(source)
    if probe.NodeCount <= 0 {
        return -1
    }

    return probe.ParseResult[0]
}

// ── the shape ─────────────────────────────────────────────────────────────────────────────────

test "a null-conditional call is a call over a conditional-member node that names the member" {
    source := "handler?.Invoke(value)"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert nodes.Kind(root) == ColumnarExpressionNodeKind.CallExpression()
    assert nodes.ChildCount(root) == 2

    callee := nodes.Child(root, 0)
    assert nodes.Kind(callee) == ColumnarExpressionNodeKind.ConditionalMemberAccessExpression()
    assert nodes.Text(source, callee) == "Invoke"
    assert nodes.ChildCount(callee) == 1

    receiver := nodes.Child(callee, 0)
    assert nodes.Kind(receiver) == ColumnarExpressionNodeKind.IdentifierExpression()
    assert nodes.Text(source, receiver) == "handler"

    argument := nodes.Child(root, 1)
    assert nodes.Kind(argument) == ColumnarExpressionNodeKind.IdentifierExpression()
    assert nodes.Text(source, argument) == "value"
}

// The conditional link's kind must not collide with a STATEMENT kind: the two families share one
// numbering space in the node table, and 72 and 73 are already the yield and await-foreach statements.
test "the conditional-member kind is its own number, distinct from the neighbours it sits between" {
    assert ColumnarExpressionNodeKind.ConditionalMemberAccessExpression() == 74
    assert ColumnarExpressionNodeKind.ConditionalMemberAccessExpression() != ColumnarExpressionNodeKind.MemberAccessExpression()
    assert ColumnarExpressionNodeKind.ConditionalMemberAccessExpression() != ColumnarExpressionNodeKind.BaseMemberExpression()
    assert ColumnarExpressionNodeKind.ConditionalMemberAccessExpression() != ColumnarExpressionNodeKind.GenericTypeReceiverExpression()
}

test "a conditional call over a member-access receiver keeps the receiver chain under it" {
    source := "owner.handler?.Invoke(value)"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    callee := nodes.Child(root, 0)
    assert nodes.Kind(callee) == ColumnarExpressionNodeKind.ConditionalMemberAccessExpression()

    receiver := nodes.Child(callee, 0)
    assert nodes.Kind(receiver) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, receiver) == "handler"
}

// `(a?.M())?.N()` is what `a?.M()?.N()` means, so a second conditional link over the first is exact
// rather than an approximation.
test "a conditional call may be the receiver of another conditional call" {
    source := "first?.Next()?.Run(value)"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert nodes.Kind(root) == ColumnarExpressionNodeKind.CallExpression()
    outerCallee := nodes.Child(root, 0)
    assert nodes.Kind(outerCallee) == ColumnarExpressionNodeKind.ConditionalMemberAccessExpression()
    assert nodes.Text(source, outerCallee) == "Run"

    innerCall := nodes.Child(outerCallee, 0)
    assert nodes.Kind(innerCall) == ColumnarExpressionNodeKind.CallExpression()

    innerCallee := nodes.Child(innerCall, 0)
    assert nodes.Kind(innerCallee) == ColumnarExpressionNodeKind.ConditionalMemberAccessExpression()
    assert nodes.Text(source, innerCallee) == "Next"
}

// ── what it refuses ───────────────────────────────────────────────────────────────────────────

test "a null-conditional READ is refused rather than lowered as an unconditional one" {
    assert ConditionalCallRoot("handler?.Length") < 0
    assert ConditionalCallRoot("owner.handler?.Value") < 0
}

// A link written after a conditional one has to be skipped along WITH it; a chain built a link at a
// time cannot say that, so it refuses.
test "a non-conditional link after a conditional one is refused" {
    assert ConditionalCallRoot("handler?.Invoke(value).Length") < 0
    assert ConditionalCallRoot("handler?.Invoke(value)[0]") < 0
}

test "the ordinary chain is untouched by the rule" {
    source := "owner.handler.Invoke(value).Length"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert root >= 0
    assert nodes.Kind(root) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, root) == "Length"
}
