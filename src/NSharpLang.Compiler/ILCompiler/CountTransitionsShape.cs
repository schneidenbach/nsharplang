using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// RUST-PERF P-ctrans (docs/design/roadmap-to-done.md — the realization of "P3" for the count-transitions
/// kernel, the last addressable Rust gap at ~2.5–4.5×). Recognizes the canonical adjacent-difference count loop:
/// <code>
///   previous := a[0]                       // (seed; the detector does NOT require this — see below)
///   for i := 1; i &lt; bound; i++ {
///       current := a[i]                     // temp bound to the array element
///       if current != previous {            // not-equal vs the PRIOR element (carried in `previous`)
///           count = count + 1               // single unit counter increment, no else
///       }
///       previous = current                  // carry: previous becomes a[i] for the next iteration
///   }
/// </code>
/// the codegen rewrites into a masked SIMD shifted compare (<c>a[i] != a[i-1]</c>) — see
/// <c>SimdReductions.CountTransitionsInt32</c>.
///
/// The loop carries state (<c>previous</c>), but the rewrite stays value-preserving WITHOUT any non-local
/// init analysis: the emitter passes the live value of <c>previous</c> as the helper's <c>seedPrevious</c>,
/// so the helper compares <c>a[start]</c> against the seed (exactly what the scalar loop's first iteration does)
/// and <c>a[i]</c> against <c>a[i-1]</c> for the rest. Whatever <c>previous</c> was initialized to (a[0] in the
/// kernel, or anything else), seeding reproduces the scalar result. So this detector is purely LOCAL to the loop,
/// like the other shapes.
///
/// Detection is structural and CONSERVATIVE (no types here — the emitter adds the int/array guard); a false
/// negative is harmless (scalar loop unchanged), a false positive must be impossible. Enforced:
/// <list type="bullet">
/// <item>condition is <c>index &lt; bound</c> with a loop-invariant side-effect-free bound (id/int-literal/array
///   <c>.Length</c>) that is not the index;</item>
/// <item>the body is exactly: a temp <c>current := a[index]</c>; an <c>if current != previous { count++ }</c>
///   with no else and a single unit counter increment; a carry <c>previous = current</c>;</item>
/// <item>the array is indexed only by <c>index</c>; counter/array/index/previous/current are five DISTINCT
///   names — so `previous` is a genuine loop-carried scalar (read in the compare, written only by the carry),
///   the counter is written only by the increment, and there is no aliasing.</item>
/// </list>
/// </summary>
public sealed record CountTransitionsShape(
    IdentifierExpression CounterRef,
    IdentifierExpression ArrayRef,
    IdentifierExpression IndexRef,
    IdentifierExpression PreviousRef,
    Expression Bound)
{
    /// <summary>The counter local/parameter name.</summary>
    public string Counter => CounterRef.Name;

    /// <summary>The scanned array local/parameter name.</summary>
    public string Array => ArrayRef.Name;

    /// <summary>The loop index local/parameter name.</summary>
    public string Index => IndexRef.Name;

    /// <summary>The carried "previous element" local/parameter name (the helper's seed).</summary>
    public string Previous => PreviousRef.Name;

    /// <summary>Matches the while-form (the unit index increment is the loop's last body statement).</summary>
    public static CountTransitionsShape? TryMatch(WhileStatement loop)
    {
        if (!TryMatchCondition(loop.Condition, out var indexId, out var bound))
            return null;
        // Body: temp ; if ; carry ; increment.
        if (loop.Body is not BlockStatement { Statements: { Count: 4 } statements })
            return null;
        if (statements[3] is not ExpressionStatement { Expression: { } increment } || !IsUnitIncrement(increment, indexId.Name))
            return null;
        return TryMatchBody(statements[0], statements[1], statements[2], indexId, bound);
    }

    /// <summary>Matches the for-form (the unit index increment is the iterator; the body is temp; if; carry).
    /// The caller emits <see cref="ForStatement.Initializer"/> separately.</summary>
    public static CountTransitionsShape? TryMatch(ForStatement loop)
    {
        if (!TryMatchCondition(loop.Condition, out var indexId, out var bound))
            return null;
        if (loop.Iterator is null || !IsUnitIncrement(loop.Iterator, indexId.Name))
            return null;
        if (loop.Body is not BlockStatement { Statements: { Count: 3 } statements })
            return null;
        return TryMatchBody(statements[0], statements[1], statements[2], indexId, bound);
    }

    private static CountTransitionsShape? TryMatchBody(Statement tempStatement, Statement ifStatement, Statement carryStatement, IdentifierExpression indexId, Expression bound)
    {
        var index = indexId.Name;

        // temp: current := a[index].
        if (tempStatement is not VariableDeclarationStatement { Initializer: { } tempInit } tempDecl)
            return null;
        if (!TryMatchArrayIndex(tempInit, index, out var arrayRef))
            return null;
        var current = tempDecl.Name;

        // if: no else; condition `current != previous` (either operand order); body a single unit counter increment.
        if (ifStatement is not IfStatement { ElseStatement: null } ifStmt)
            return null;
        if (ifStmt.Condition is not BinaryExpression { Operator: BinaryOperator.NotEqual } compare)
            return null;
        if (!TryResolvePrevious(compare, current, out var previousId))
            return null;
        if (TryGetSingleStatement(ifStmt.ThenStatement) is not ExpressionStatement { Expression: { } counterExpr })
            return null;
        if (!TryMatchUnitCounterIncrement(counterExpr, out var counterId))
            return null;

        // carry: previous = current.
        if (carryStatement is not ExpressionStatement
            {
                Expression: AssignmentExpression { Operator: AssignmentOperator.Assign, Target: IdentifierExpression carryTarget, Value: IdentifierExpression carryValue }
            })
            return null;
        if (carryTarget.Name != previousId.Name || carryValue.Name != current)
            return null;

        // Five distinct names: no aliasing / no other writes to the carried scalar or counter.
        var counter = counterId.Name;
        var previous = previousId.Name;
        var array = arrayRef.Name;
        if (!AllDistinct(counter, array, index, previous, current))
            return null;

        return new CountTransitionsShape(counterId, arrayRef, indexId, previousId, bound);
    }

    // The compare is `current != previous` or `previous != current`; `previous` is the operand that is NOT the
    // current temp. It must be a plain identifier (a loop-carried scalar), never the index.
    private static bool TryResolvePrevious(BinaryExpression compare, string current, out IdentifierExpression previousId)
    {
        previousId = null!;
        if (compare.Left is IdentifierExpression left && left.Name == current && compare.Right is IdentifierExpression right)
        {
            previousId = right;
            return true;
        }
        if (compare.Right is IdentifierExpression r && r.Name == current && compare.Left is IdentifierExpression l)
        {
            previousId = l;
            return true;
        }

        return false;
    }

    private static bool AllDistinct(string a, string b, string c, string d, string e)
        => a != b && a != c && a != d && a != e
           && b != c && b != d && b != e
           && c != d && c != e
           && d != e;

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

    private static Statement? TryGetSingleStatement(Statement statement) => statement switch
    {
        BlockStatement { Statements: { Count: 1 } s } => s[0],
        ExpressionStatement => statement,
        _ => null,
    };

    // count = count + 1  OR  count += 1  OR  count++ / ++count.
    private static bool TryMatchUnitCounterIncrement(Expression increment, out IdentifierExpression counterId)
    {
        counterId = null!;
        switch (increment)
        {
            case UnaryExpression { Operator: UnaryOperator.PostIncrement or UnaryOperator.PreIncrement, Operand: IdentifierExpression u }:
                counterId = u;
                return true;
            case AssignmentExpression { Target: IdentifierExpression t, Operator: AssignmentOperator.Assign, Value: BinaryExpression { Operator: BinaryOperator.Add } add }
                when add.Left is IdentifierExpression al && al.Name == t.Name && IsLiteralOne(add.Right):
                counterId = t;
                return true;
            case AssignmentExpression { Target: IdentifierExpression t, Operator: AssignmentOperator.AddAssign, Value: { } v }
                when IsLiteralOne(v):
                counterId = t;
                return true;
            default:
                return false;
        }
    }

    private static bool IsUnitIncrement(Expression increment, string name) => increment switch
    {
        UnaryExpression { Operator: UnaryOperator.PostIncrement or UnaryOperator.PreIncrement, Operand: IdentifierExpression id }
            => id.Name == name,
        AssignmentExpression { Target: IdentifierExpression target, Operator: AssignmentOperator.Assign, Value: BinaryExpression { Operator: BinaryOperator.Add } add }
            => target.Name == name && add.Left is IdentifierExpression addLeft && addLeft.Name == name && IsLiteralOne(add.Right),
        AssignmentExpression { Target: IdentifierExpression target, Operator: AssignmentOperator.AddAssign, Value: { } value }
            => target.Name == name && IsLiteralOne(value),
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
