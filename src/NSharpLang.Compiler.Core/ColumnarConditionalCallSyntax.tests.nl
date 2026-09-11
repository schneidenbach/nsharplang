namespace NSharpLang.Compiler

import System


// THE NULL-CONDITIONAL CALL, IN THE SHAPE THE BACKEND ACTUALLY BUILDS.
//
// `receiver?.Member(args)` is NOT a node kind of its own. The `?.` wraps the RECEIVER in a kind-75
// `NullGuardExpression`, and everything above it stays what it always was: an ordinary kind-8
// `MemberAccessExpression` naming the member, and an ordinary kind-9 `CallExpression` over that for
// the argument list. That is what lets a conditional call reach the SAME owners the dotted
// `current.Invoke(h)` reaches — a delegate's `Invoke` included — instead of a parallel call tier.
//
// The guard is where the SHORT CIRCUIT hangs: `ColumnarIlEmitter` emits the chain from its root, so
// `a?.M().B` skips the `.B` along with the call rather than refusing the declaration.
// `ColumnarParserKernels.tests.nl` pins the guard's own shape; the contracts here are the CALL forms
// the delegate-invocation work depends on.
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

test "a null-conditional call is an ordinary call over an ordinary access with a guarded receiver" {
    source := "handler?.Invoke(value)"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert nodes.Kind(root) == ColumnarExpressionNodeKind.CallExpression()
    assert nodes.ChildCount(root) == 2

    callee := nodes.Child(root, 0)
    assert nodes.Kind(callee) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, callee) == "Invoke"
    assert nodes.ChildCount(callee) == 1

    guard := nodes.Child(callee, 0)
    assert nodes.Kind(guard) == ColumnarExpressionNodeKind.NullGuardExpression()
    assert nodes.ChildCount(guard) == 1

    receiver := nodes.Child(guard, 0)
    assert nodes.Kind(receiver) == ColumnarExpressionNodeKind.IdentifierExpression()
    assert nodes.Text(source, receiver) == "handler"

    argument := nodes.Child(root, 1)
    assert nodes.Kind(argument) == ColumnarExpressionNodeKind.IdentifierExpression()
    assert nodes.Text(source, argument) == "value"
}

// The guard's kind must not collide with a STATEMENT kind: the two families share one numbering
// space in the node table, and 72, 73 and 74 are already the yield, await-foreach and `default` kinds.
test "the null-guard kind is its own number, distinct from the neighbours it sits between" {
    assert ColumnarExpressionNodeKind.NullGuardExpression() == 75
    assert ColumnarExpressionNodeKind.NullGuardExpression() != ColumnarExpressionNodeKind.MemberAccessExpression()
    assert ColumnarExpressionNodeKind.NullGuardExpression() != ColumnarExpressionNodeKind.BaseMemberExpression()
    assert ColumnarExpressionNodeKind.NullGuardExpression() != ColumnarExpressionNodeKind.DefaultExpression()
    assert ColumnarExpressionNodeKind.NullGuardExpression() != ColumnarExpressionNodeKind.GenericTypeReceiverExpression()
}

test "a conditional call over a member-access receiver keeps the receiver chain under the guard" {
    source := "owner.handler?.Invoke(value)"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    callee := nodes.Child(root, 0)
    assert nodes.Kind(callee) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, callee) == "Invoke"

    guard := nodes.Child(callee, 0)
    assert nodes.Kind(guard) == ColumnarExpressionNodeKind.NullGuardExpression()

    receiver := nodes.Child(guard, 0)
    assert nodes.Kind(receiver) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, receiver) == "handler"
}

// `(a?.M())?.N()` is what `a?.M()?.N()` means, so a second guard over the first call is exact rather
// than an approximation.
test "a conditional call may itself be the guarded receiver of another conditional call" {
    source := "first?.Next()?.Run(value)"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert nodes.Kind(root) == ColumnarExpressionNodeKind.CallExpression()
    outerCallee := nodes.Child(root, 0)
    assert nodes.Kind(outerCallee) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, outerCallee) == "Run"

    outerGuard := nodes.Child(outerCallee, 0)
    assert nodes.Kind(outerGuard) == ColumnarExpressionNodeKind.NullGuardExpression()

    innerCall := nodes.Child(outerGuard, 0)
    assert nodes.Kind(innerCall) == ColumnarExpressionNodeKind.CallExpression()

    innerCallee := nodes.Child(innerCall, 0)
    assert nodes.Kind(innerCallee) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, innerCallee) == "Next"
    assert nodes.Kind(nodes.Child(innerCallee, 0)) == ColumnarExpressionNodeKind.NullGuardExpression()
}

// ── what it no longer refuses ─────────────────────────────────────────────────────────────────

// The READ form and a plain link written after a conditional one were both REFUSED while the chain
// was built a link at a time and had nowhere to put the short circuit. The guard is that place, so
// both parse — and the emitter's chain root is what makes the plain link skip along with the
// conditional one.
test "a null-conditional READ is the same access with a guarded receiver" {
    source := "handler?.Length"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert nodes.Kind(root) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, root) == "Length"
    assert nodes.Kind(nodes.Child(root, 0)) == ColumnarExpressionNodeKind.NullGuardExpression()
}

test "a non-conditional link after a conditional one parses, and only the conditional link is guarded" {
    source := "handler?.Invoke(value).Length"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert nodes.Kind(root) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, root) == "Length"

    call := nodes.Child(root, 0)
    assert nodes.Kind(call) == ColumnarExpressionNodeKind.CallExpression()

    callee := nodes.Child(call, 0)
    assert nodes.Kind(callee) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Kind(nodes.Child(callee, 0)) == ColumnarExpressionNodeKind.NullGuardExpression()
}

test "an indexed link after a conditional one parses the same way" {
    source := "handler?.Invoke(value)[0]"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert nodes.Kind(root) == ColumnarExpressionNodeKind.IndexAccessExpression()
    call := nodes.Child(root, 0)
    assert nodes.Kind(call) == ColumnarExpressionNodeKind.CallExpression()
    assert nodes.Kind(nodes.Child(nodes.Child(call, 0), 0)) == ColumnarExpressionNodeKind.NullGuardExpression()
}

test "the ordinary chain carries no guard at all" {
    source := "owner.handler.Invoke(value).Length"
    nodes := ConditionalCallTree(source)
    root := ConditionalCallRoot(source)

    assert root >= 0
    assert nodes.Kind(root) == ColumnarExpressionNodeKind.MemberAccessExpression()
    assert nodes.Text(source, root) == "Length"

    guards := 0
    node := 0
    while node < nodes.Kinds.Length {
        if nodes.Kind(node) == ColumnarExpressionNodeKind.NullGuardExpression() {
            guards = guards + 1
        }

        node = node + 1
    }

    assert guards == 0
}
