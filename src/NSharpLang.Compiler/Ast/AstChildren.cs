using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler.Ast;

/// <summary>
/// Exhaustive direct-child enumeration for every AST expression node.
///
/// The compiler has many hand-rolled expression walkers (linter, definite assignment, capture
/// scans, escape scans, performance analyzers) that each enumerate children independently.
/// Twice now a late-added child slipped through every one of them because their switch defaults
/// fail open (<c>NewExpression.ArrayLengthExpression</c>, <c>StackAllocExpression.LengthExpression</c>),
/// producing missed diagnostics and emit failures. Walkers whose non-leaf cases are purely
/// structural recursion should route them through this helper instead of re-listing children;
/// walkers that need node-specific behavior must still cover every node listed here.
///
/// The default arm throws so a brand-new expression node cannot silently yield no children, and
/// <c>AstChildrenTests</c> reflectively asserts that every <see cref="Expression"/>-typed slot of
/// every expression record (including slots nested in aggregates such as <see cref="Argument"/>,
/// <see cref="PropertyInitializer"/>, <see cref="TupleElement"/>, <see cref="MatchCase"/>, and
/// <see cref="InterpolatedStringHole"/>) is reachable through this enumeration.
///
/// Deliberate boundary: expressions nested inside <see cref="Pattern"/> nodes
/// (<see cref="LiteralPattern.Literal"/>, <see cref="RelationalPattern.Value"/>) are pattern
/// concerns and are not enumerated here; pattern walkers own them.
/// </summary>
public static class AstChildren
{
    /// <summary>Yields every direct child <see cref="Expression"/> of <paramref name="expression"/>.</summary>
    public static IEnumerable<Expression> Of(Expression expression)
    {
        switch (expression)
        {
            // Leaves: no child expressions.
            case IntLiteralExpression:
            case FloatLiteralExpression:
            case CharLiteralExpression:
            case StringLiteralExpression:
            case BoolLiteralExpression:
            case NullLiteralExpression:
            case IdentifierExpression:
            case ThisExpression:
            case BaseExpression:
            case DefaultExpression:
            case TypeOfExpression:
            case SizeOfExpression:
                yield break;

            case InterpolatedStringExpression interpolated:
                foreach (var hole in interpolated.Parts.OfType<InterpolatedStringHole>())
                    yield return hole.Expression;
                yield break;

            case RangeExpression range:
                if (range.Start != null) yield return range.Start;
                if (range.End != null) yield return range.End;
                yield break;

            case BinaryExpression binary:
                yield return binary.Left;
                yield return binary.Right;
                yield break;

            case UnaryExpression unary:
                yield return unary.Operand;
                yield break;

            case MustExpression must:
                yield return must.Expression;
                yield break;

            case MemberAccessExpression member:
                yield return member.Object;
                yield break;

            case IndexAccessExpression index:
                yield return index.Object;
                yield return index.Index;
                yield break;

            case CallExpression call:
                yield return call.Callee;
                foreach (var argument in call.Arguments)
                    yield return argument.Value;
                yield break;

            case AssignmentExpression assignment:
                yield return assignment.Target;
                yield return assignment.Value;
                yield break;

            case LambdaExpression lambda:
                // BlockBody is a statement, not an expression child; walkers that need to
                // descend into lambda bodies must handle LambdaExpression themselves.
                if (lambda.ExpressionBody != null) yield return lambda.ExpressionBody;
                yield break;

            case OnSubscriptionExpression onSubscription:
                yield return onSubscription.Target;
                yield return onSubscription.Handler;
                yield break;

            case TernaryExpression ternary:
                yield return ternary.Condition;
                yield return ternary.ThenExpression;
                yield return ternary.ElseExpression;
                yield break;

            case ArrayLiteralExpression array:
                foreach (var element in array.Elements)
                    yield return element;
                yield break;

            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                    yield return element.Value;
                yield break;

            case ObjectInitializerExpression objectInitializer:
                foreach (var property in objectInitializer.Properties)
                {
                    if (property.IndexExpression != null) yield return property.IndexExpression;
                    yield return property.Value;
                }
                yield break;

            case NewExpression newExpr:
                foreach (var argument in newExpr.ConstructorArguments)
                    yield return argument.Value;
                if (newExpr.Initializer != null) yield return newExpr.Initializer;
                if (newExpr.ArrayLengthExpression != null) yield return newExpr.ArrayLengthExpression;
                yield break;

            case AllocExpression alloc:
                yield return alloc.Expression;
                yield break;

            case StackAllocExpression stackAlloc:
                yield return stackAlloc.LengthExpression;
                yield break;

            case CastExpression cast:
                yield return cast.Expression;
                yield break;

            case IsExpression isExpr:
                yield return isExpr.Expression;
                yield break;

            case MatchExpression match:
                yield return match.Value;
                foreach (var matchCase in match.Cases)
                {
                    if (matchCase.Guard != null) yield return matchCase.Guard;
                    yield return matchCase.Expression;
                }
                yield break;

            case SpreadExpression spread:
                yield return spread.Expression;
                yield break;

            case WithExpression with:
                yield return with.Target;
                foreach (var property in with.Properties)
                {
                    if (property.IndexExpression != null) yield return property.IndexExpression;
                    yield return property.Value;
                }
                yield break;

            case AwaitExpression await:
                yield return await.Expression;
                yield break;

            case ThrowExpression throwExpr:
                yield return throwExpr.Expression;
                yield break;

            case NameofExpression nameofExpr:
                yield return nameofExpr.Target;
                yield break;

            case CheckedExpression checkedExpr:
                yield return checkedExpr.Expression;
                yield break;

            case UncheckedExpression uncheckedExpr:
                yield return uncheckedExpr.Expression;
                yield break;

            case ParenthesizedExpression paren:
                yield return paren.Inner;
                yield break;

            default:
                // Fail closed: a new expression node must be added here (and is then picked up
                // automatically by every walker that recurses through AstChildren).
                throw new InvalidOperationException(
                    $"AstChildren.Of has no case for expression node '{expression.GetType().Name}'. " +
                    "Add it so AST walkers enumerate its children.");
        }
    }
}
