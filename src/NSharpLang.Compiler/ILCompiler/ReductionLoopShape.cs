using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// RUST-PERF P1 (docs/design/roadmap-to-done.md). Recognizes the canonical
/// counted-reduction loop shape that the auto-vectorizing codegen (P1(b)/(d)/(f)) rewrites into an unrolled
/// <c>System.Numerics.Vector&lt;T&gt;</c> accumulation — the measured ~4.5× win on checksum-sum.
///
/// Two surface forms are recognized, both reducing to the same shape (accumulator, array, index, bound):
/// <code>
///   // while-form (the index increment is the second body statement)
///   while index &lt; bound { acc = acc + array[index]; index = index + 1 }
///   // for-form (the index increment is the ITERATOR; the body is the single accumulator update)
///   for index := start; index &lt; bound; index++ { acc = acc + array[index] }
/// </code>
/// Detection is purely structural (no types here — the emitter adds the int/array type guard). The match is
/// CONSERVATIVE: a non-match simply leaves the standard scalar loop emission untouched (correctness is never
/// at risk from a false negative). A false positive must be impossible, so every safety condition that makes
/// the rewrite value-preserving is enforced here:
/// <list type="bullet">
/// <item>condition is <c>index &lt; bound</c> with a loop-invariant, side-effect-free bound (identifier,
///   int literal, or <c>x.Length</c> — the codegen requires <c>x</c> to be an array so this is the pure
///   ldlen intrinsic) that is not the index;</item>
/// <item>the accumulator update reads <c>array[index]</c> before the increment (it is the only/first body
///   statement; the for-form's increment is the iterator, the while-form's is the second statement);</item>
/// <item>the index increments by exactly one (<c>i++</c>/<c>++i</c>/<c>i = i + 1</c>/<c>i += 1</c>);</item>
/// <item>the array is indexed only by <c>index</c> (uniform unit stride), and accumulator/array/index are
///   three distinct names — so there is no loop-carried dependence, no other write, and no aliasing.</item>
/// </list>
/// Integer wrapping addition is associative, so reordering the additions across SIMD lanes/accumulators is
/// value-preserving. break/continue/return/other writes cannot appear (the body is the fixed update).
/// </summary>
public sealed record ReductionLoopShape(
    IdentifierExpression AccumulatorRef,
    IdentifierExpression ArrayRef,
    IdentifierExpression IndexRef,
    Expression Bound)
{
    /// <summary>The accumulator local/parameter name.</summary>
    public string Accumulator => AccumulatorRef.Name;

    /// <summary>The summed array local/parameter name.</summary>
    public string Array => ArrayRef.Name;

    /// <summary>The loop index local/parameter name.</summary>
    public string Index => IndexRef.Name;

    /// <summary>Returns the matched shape, or null when <paramref name="loop"/> is not a vectorizable counted
    /// reduction (while-form: the index increment is the second body statement).</summary>
    public static ReductionLoopShape? TryMatch(WhileStatement loop)
    {
        if (!TryMatchCondition(loop.Condition, out var indexId, out var bound))
            return null;

        // Body: exactly two expression statements — the accumulator update then the index increment.
        if (loop.Body is not BlockStatement { Statements: { Count: 2 } statements })
            return null;
        if (statements[0] is not ExpressionStatement { Expression: AssignmentExpression accumulatorUpdate })
            return null;
        if (statements[1] is not ExpressionStatement { Expression: AssignmentExpression indexIncrement })
            return null;

        if (!TryMatchAccumulatorUpdate(accumulatorUpdate, indexId.Name, out var accumulatorId, out var arrayRef))
            return null;
        if (!IsUnitIndexIncrement(indexIncrement, indexId.Name))
            return null;

        return Build(accumulatorId, arrayRef, indexId, bound);
    }

    /// <summary>Returns the matched shape, or null when <paramref name="loop"/> is not a vectorizable counted
    /// reduction (for-form: the index increment is the iterator and the body is the single accumulator update).
    /// The caller is responsible for emitting <see cref="ForStatement.Initializer"/> separately — the shape
    /// describes only the condition/iterator/body, exactly like the while-form.</summary>
    public static ReductionLoopShape? TryMatch(ForStatement loop)
    {
        if (!TryMatchCondition(loop.Condition, out var indexId, out var bound))
            return null;

        // Iterator increments the index by one; the body is the single accumulator-update statement.
        if (loop.Iterator is null || !IsUnitIndexIncrement(loop.Iterator, indexId.Name))
            return null;
        if (TryGetSingleBodyStatement(loop.Body) is not ExpressionStatement { Expression: AssignmentExpression accumulatorUpdate })
            return null;

        if (!TryMatchAccumulatorUpdate(accumulatorUpdate, indexId.Name, out var accumulatorId, out var arrayRef))
            return null;

        return Build(accumulatorId, arrayRef, indexId, bound);
    }

    // Condition: index < bound, with a side-effect-free loop-invariant bound that is not the index.
    private static bool TryMatchCondition(Expression? condition, out IdentifierExpression indexId, out Expression bound)
    {
        indexId = null!;
        bound = null!;
        if (condition is not BinaryExpression { Operator: BinaryOperator.Less } less)
            return false;
        if (less.Left is not IdentifierExpression id)
            return false;
        if (!IsSideEffectFreeInvariantBound(less.Right, id.Name))
            return false;
        indexId = id;
        bound = less.Right;
        return true;
    }

    // Enforces the three-distinct-names rule (no aliasing / loop-carried dependence) and builds the shape.
    private static ReductionLoopShape? Build(IdentifierExpression accumulatorId, IdentifierExpression arrayRef, IdentifierExpression indexId, Expression bound)
    {
        var accumulator = accumulatorId.Name;
        var index = indexId.Name;
        if (accumulator == arrayRef.Name || accumulator == index || arrayRef.Name == index)
            return null;
        // The bound must be loop-invariant. The accumulator is written every iteration, so a bound
        // that names it (e.g. `while i < acc { acc = acc + a[i]; i = i + 1 }`) is loop-variant: the
        // vectorized form snapshots the bound once at entry, summing a different element set than
        // the scalar loop. Reject it (H1). The index is already excluded by the condition check.
        if (bound is IdentifierExpression boundId && boundId.Name == accumulator)
            return null;
        return new ReductionLoopShape(accumulatorId, arrayRef, indexId, bound);
    }

    // The for-loop body, or the single statement inside a one-statement block.
    private static Statement? TryGetSingleBodyStatement(Statement body) => body switch
    {
        BlockStatement { Statements: { Count: 1 } s } => s[0],
        ExpressionStatement => body,
        _ => null,
    };

    // acc = acc + array[index]  OR  acc += array[index].
    private static bool TryMatchAccumulatorUpdate(AssignmentExpression accumulatorUpdate, string index, out IdentifierExpression accumulatorId, out IdentifierExpression arrayRef)
    {
        accumulatorId = null!;
        arrayRef = null!;
        if (accumulatorUpdate.Target is not IdentifierExpression accId)
            return false;
        switch (accumulatorUpdate.Operator)
        {
            case AssignmentOperator.Assign:
                if (accumulatorUpdate.Value is not BinaryExpression { Operator: BinaryOperator.Add } sum)
                    return false;
                if (sum.Left is not IdentifierExpression sumLeft || sumLeft.Name != accId.Name)
                    return false;
                if (!TryMatchArrayIndex(sum.Right, index, out arrayRef))
                    return false;
                break;
            case AssignmentOperator.AddAssign:
                if (!TryMatchArrayIndex(accumulatorUpdate.Value, index, out arrayRef))
                    return false;
                break;
            default:
                return false;
        }

        accumulatorId = accId;
        return true;
    }

    // A unit index increment in any accepted form: i++ / ++i (for-iterator) or i = i + 1 / i += 1 (either form).
    // (The while-body path only ever passes an AssignmentExpression — its `i++` would not parse as the second
    // body statement's AssignmentExpression — so this does not change while-form matching.)
    private static bool IsUnitIndexIncrement(Expression increment, string index) => increment switch
    {
        UnaryExpression { Operator: UnaryOperator.PostIncrement or UnaryOperator.PreIncrement, Operand: IdentifierExpression id }
            => id.Name == index,
        AssignmentExpression { Target: IdentifierExpression target, Operator: AssignmentOperator.Assign, Value: BinaryExpression { Operator: BinaryOperator.Add } add }
            => target.Name == index && add.Left is IdentifierExpression addLeft && addLeft.Name == index && IsLiteralOne(add.Right),
        AssignmentExpression { Target: IdentifierExpression target, Operator: AssignmentOperator.AddAssign, Value: var value }
            => target.Name == index && IsLiteralOne(value),
        _ => false,
    };

    private static bool TryMatchArrayIndex(Expression expression, string index, out IdentifierExpression array)
    {
        array = null!;
        if (expression is not IndexAccessExpression { IsNullConditional: false } indexAccess)
            return false;
        if (indexAccess.Object is not IdentifierExpression arrayId)
            return false;
        if (indexAccess.Index is not IdentifierExpression indexId || indexId.Name != index)
            return false;
        array = arrayId;
        return true;
    }

    // Shape-level bound check (no types here). `.Length` on an identifier is allowed at the shape level; the
    // codegen further requires the receiver to be an ARRAY (so `.Length` is the pure ldlen intrinsic, not a
    // possibly-side-effecting custom property). `.Count` is excluded — a custom collection's Count getter may
    // have side effects, and the vectorized form evaluates the bound a different number of times.
    private static bool IsSideEffectFreeInvariantBound(Expression bound, string index) => bound switch
    {
        IdentifierExpression id => id.Name != index,
        IntLiteralExpression => true,
        MemberAccessExpression { IsNullConditional: false, MemberName: "Length", Object: IdentifierExpression } => true,
        _ => false,
    };

    private static bool IsLiteralOne(Expression expression)
        => expression is IntLiteralExpression { Value: "1" };
}
