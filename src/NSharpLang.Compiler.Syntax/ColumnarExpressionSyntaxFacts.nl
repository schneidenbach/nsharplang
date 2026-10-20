namespace NSharpLang.Compiler.Columnar


// Shared parser-shape facts used by N# planners and the shrinking mechanical emitter host.
// The columnar parser deliberately flattens `this.member` into a leaf identifier whose value
// span names only `member` while its full span begins at the `this` token. Trivia is absent from
// the token stream, so the source between those two offsets may contain whitespace or comments.
class ColumnarExpressionSyntaxFacts {
    // C# permits a void-returning expression lambda when its expression is a statement expression;
    // any value produced by that statement is evaluated and discarded. Keep the parser-node check in
    // the shared syntax layer so delegate binding and the lambda body emitter use the same grammar.
    static func IsStatementExpression(nodes: ColumnarNodeTable, source: string, node: int): bool {
        if nodes == null || source == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.CallExpression || kind == ColumnarExpressionNodeKind.NewExpression || kind == ColumnarExpressionNodeKind.BareNew || kind == ColumnarExpressionNodeKind.TargetTypedNewExpression || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression || kind == ColumnarExpressionNodeKind.AssignmentExpression || kind == ColumnarExpressionNodeKind.PostfixUnary || kind == ColumnarExpressionNodeKind.AwaitExpression || kind == ColumnarExpressionNodeKind.OnSubscriptionExpression {
            return true
        }
        if kind == ColumnarExpressionNodeKind.UnaryExpression {
            operatorText := nodes.Text(source, node)
            return operatorText == "++" || operatorText == "--"
        }
        if (kind == ColumnarExpressionNodeKind.ParenthesizedExpression || kind == ColumnarExpressionNodeKind.CheckedContextExpression) && nodes.ChildCount(node) == 1 {
            return IsStatementExpression(nodes, source, nodes.Child(node, 0))
        }
        return false
    }

    static func IsExplicitThisIdentifier(nodes: ColumnarNodeTable, source: string, node: int): bool {
        if nodes == null || source == null || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.IdentifierExpression || nodes.ChildCount(node) != 0 {
            return false
        }

        valueStart := nodes.ValueStart(node)
        spanStart := nodes.SpanStart(node)
        return spanStart >= 0 && spanStart <= source.Length - 4 && valueStart >= spanStart + 5 && valueStart <= source.Length && source[spanStart] == 't' && source[spanStart + 1] == 'h' && source[spanStart + 2] == 'i' && source[spanStart + 3] == 's'
    }
}
