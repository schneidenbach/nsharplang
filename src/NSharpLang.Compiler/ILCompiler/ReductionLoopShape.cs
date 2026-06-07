using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// RUST-PERF P1(a) (docs/design/roadmap-to-done.md, systems-perf-backlog.md). Recognizes the canonical
/// counted-reduction loop shape that the auto-vectorizing codegen (P1(b)) rewrites into an unrolled
/// <c>System.Numerics.Vector&lt;T&gt;</c> accumulation — the measured ~4.5× win on checksum-sum.
///
/// The recognized shape (the systems <c>while</c> form) is exactly:
/// <code>
///   while index &lt; bound {
///       acc = acc + array[index]   // or: acc += array[index]
///       index = index + 1          // or: index += 1
///   }
/// </code>
/// Detection is purely structural (no types here — the emitter adds the int/array type guard). The match is
/// CONSERVATIVE: a non-match simply leaves the standard scalar loop emission untouched (correctness is never
/// at risk from a false negative). A false positive must be impossible, so every safety condition that makes
/// the rewrite value-preserving is enforced here:
/// <list type="bullet">
/// <item>condition is <c>index &lt; bound</c> with a loop-invariant, side-effect-free bound (identifier,
///   int literal, or <c>x.Length</c>/<c>x.Count</c>) that is not the index;</item>
/// <item>body is EXACTLY the two statements above, in that order (the accumulator update reads
///   <c>array[index]</c> before the increment);</item>
/// <item>the array is indexed only by <c>index</c> (uniform unit stride), and accumulator/array/index are
///   three distinct names — so there is no loop-carried dependence, no other write, and no aliasing.</item>
/// </list>
/// Integer wrapping addition is associative, so reordering the additions across SIMD lanes/accumulators is
/// value-preserving. break/continue/return/other writes cannot appear (the body is the fixed two statements).
/// </summary>
public sealed record ReductionLoopShape(string Accumulator, string Array, string Index, Expression Bound)
{
    /// <summary>Returns the matched shape, or null when <paramref name="loop"/> is not a vectorizable counted reduction.</summary>
    public static ReductionLoopShape? TryMatch(WhileStatement loop)
    {
        // Condition: index < bound.
        if (loop.Condition is not BinaryExpression { Operator: BinaryOperator.Less } condition)
            return null;
        if (condition.Left is not IdentifierExpression indexId)
            return null;
        var index = indexId.Name;
        var bound = condition.Right;
        if (!IsSideEffectFreeInvariantBound(bound, index))
            return null;

        // Body: exactly two expression statements.
        if (loop.Body is not BlockStatement { Statements: { Count: 2 } statements })
            return null;
        if (statements[0] is not ExpressionStatement { Expression: AssignmentExpression accumulatorUpdate })
            return null;
        if (statements[1] is not ExpressionStatement { Expression: AssignmentExpression indexIncrement })
            return null;

        // Statement 1: acc = acc + array[index]  OR  acc += array[index].
        if (accumulatorUpdate.Target is not IdentifierExpression accumulatorId)
            return null;
        var accumulator = accumulatorId.Name;
        string array;
        switch (accumulatorUpdate.Operator)
        {
            case AssignmentOperator.Assign:
                if (accumulatorUpdate.Value is not BinaryExpression { Operator: BinaryOperator.Add } sum)
                    return null;
                if (sum.Left is not IdentifierExpression sumLeft || sumLeft.Name != accumulator)
                    return null;
                if (!TryMatchArrayIndex(sum.Right, index, out array))
                    return null;
                break;
            case AssignmentOperator.AddAssign:
                if (!TryMatchArrayIndex(accumulatorUpdate.Value, index, out array))
                    return null;
                break;
            default:
                return null;
        }

        // Statement 2: index = index + 1  OR  index += 1.
        if (indexIncrement.Target is not IdentifierExpression incrementId || incrementId.Name != index)
            return null;
        switch (indexIncrement.Operator)
        {
            case AssignmentOperator.Assign:
                if (indexIncrement.Value is not BinaryExpression { Operator: BinaryOperator.Add } step)
                    return null;
                if (step.Left is not IdentifierExpression stepLeft || stepLeft.Name != index)
                    return null;
                if (!IsLiteralOne(step.Right))
                    return null;
                break;
            case AssignmentOperator.AddAssign:
                if (!IsLiteralOne(indexIncrement.Value))
                    return null;
                break;
            default:
                return null;
        }

        // Accumulator, array, and index must be three distinct names (no aliasing / loop-carried dependence).
        if (accumulator == array || accumulator == index || array == index)
            return null;

        return new ReductionLoopShape(accumulator, array, index, bound);
    }

    private static bool TryMatchArrayIndex(Expression expression, string index, out string array)
    {
        array = string.Empty;
        if (expression is not IndexAccessExpression { IsNullConditional: false } indexAccess)
            return false;
        if (indexAccess.Object is not IdentifierExpression arrayId)
            return false;
        if (indexAccess.Index is not IdentifierExpression indexId || indexId.Name != index)
            return false;
        array = arrayId.Name;
        return true;
    }

    private static bool IsSideEffectFreeInvariantBound(Expression bound, string index) => bound switch
    {
        IdentifierExpression id => id.Name != index,
        IntLiteralExpression => true,
        MemberAccessExpression { IsNullConditional: false, MemberName: "Length" or "Count", Object: IdentifierExpression } => true,
        _ => false,
    };

    private static bool IsLiteralOne(Expression expression)
        => expression is IntLiteralExpression { Value: "1" };
}
