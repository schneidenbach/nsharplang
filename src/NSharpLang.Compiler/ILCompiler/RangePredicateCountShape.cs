using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// RUST-PERF P2 (docs/design/roadmap-to-done.md, systems-perf-backlog.md). Recognizes the canonical
/// range-predicate count loop — the count-ascii kernel (the 5.7–6.3× Rust gap) — that the masked-SIMD
/// codegen (P2(b)) will rewrite into a packed <c>Vector&lt;int&gt;</c> compare + masked accumulate.
///
/// Recognized shape (inclusive range; while- and for-forms; temp or inlined subject):
/// <code>
///   for i := s; i &lt; bound; i++ {
///       value := a[i]                       // optional temp
///       if value &gt;= lo &amp;&amp; value &lt;= hi {     // inclusive range predicate (>= then <=)
///           count = count + 1               // single counter increment, no else
///       }
///   }
/// </code>
/// The while-form is identical with the unit index increment as the loop's LAST body statement.
///
/// Detection is purely structural and CONSERVATIVE (no types here — the emitter adds the int/array guard):
/// a false negative is harmless (the scalar loop is emitted unchanged); a false positive must be impossible.
/// Every safety condition that makes the masked-count rewrite value-preserving is enforced:
/// <list type="bullet">
/// <item>condition is <c>index &lt; bound</c> with a loop-invariant, side-effect-free bound (identifier,
///   int literal, or array <c>.Length</c>) that is not the index;</item>
/// <item>the predicate is exactly <c>subject &gt;= lo &amp;&amp; subject &lt;= hi</c>, where the subject is the
///   array element <c>a[index]</c> (inlined) or a temp bound to <c>a[index]</c>; <c>lo</c>/<c>hi</c> are
///   loop-invariant (literal, or an identifier that is not the index/temp/counter) so evaluating them once
///   in the helper matches the per-iteration scalar evaluation;</item>
/// <item>the <c>if</c> has no <c>else</c> and a single counter increment body (<c>count = count + 1</c> /
///   <c>count += 1</c> / <c>count++</c>);</item>
/// <item>the array is indexed only by <c>index</c>; counter/array/index/(temp) are distinct names — no
///   loop-carried dependence, no other write, no aliasing.</item>
/// </list>
/// </summary>
public sealed record RangePredicateCountShape(
    IdentifierExpression CounterRef,
    IdentifierExpression ArrayRef,
    IdentifierExpression IndexRef,
    Expression Lo,
    Expression Hi,
    Expression Bound)
{
    /// <summary>The counter local/parameter name.</summary>
    public string Counter => CounterRef.Name;

    /// <summary>The scanned array local/parameter name.</summary>
    public string Array => ArrayRef.Name;

    /// <summary>The loop index local/parameter name.</summary>
    public string Index => IndexRef.Name;

    /// <summary>Matches the while-form (the unit index increment is the loop's last body statement).</summary>
    public static RangePredicateCountShape? TryMatch(WhileStatement loop)
    {
        if (!TryMatchCondition(loop.Condition, out var indexId, out var bound))
            return null;
        if (loop.Body is not BlockStatement { Statements: { } statements })
            return null;

        // The last statement is the unit index increment; what precedes it is the predicate part (temp?, if).
        Statement? tempStatement;
        IfStatement? ifStatement;
        Expression increment;
        switch (statements.Count)
        {
            case 2: // if ; i = i + 1
                tempStatement = null;
                ifStatement = statements[0] as IfStatement;
                increment = (statements[1] as ExpressionStatement)?.Expression!;
                break;
            case 3: // value := a[i] ; if ; i = i + 1
                tempStatement = statements[0];
                ifStatement = statements[1] as IfStatement;
                increment = (statements[2] as ExpressionStatement)?.Expression!;
                break;
            default:
                return null;
        }

        if (ifStatement is null || increment is null || !IsUnitIncrement(increment, indexId.Name))
            return null;

        return TryMatchBody(tempStatement, ifStatement, indexId, bound);
    }

    /// <summary>Matches the for-form (the unit index increment is the iterator; the body is the predicate part).
    /// The caller emits <see cref="ForStatement.Initializer"/> separately.</summary>
    public static RangePredicateCountShape? TryMatch(ForStatement loop)
    {
        if (!TryMatchCondition(loop.Condition, out var indexId, out var bound))
            return null;
        if (loop.Iterator is null || !IsUnitIncrement(loop.Iterator, indexId.Name))
            return null;

        Statement? tempStatement;
        IfStatement? ifStatement;
        switch (loop.Body)
        {
            case IfStatement bareIf: // braceless single-statement body
                tempStatement = null;
                ifStatement = bareIf;
                break;
            case BlockStatement { Statements: { Count: 1 } one }:
                tempStatement = null;
                ifStatement = one[0] as IfStatement;
                break;
            case BlockStatement { Statements: { Count: 2 } two }:
                tempStatement = two[0];
                ifStatement = two[1] as IfStatement;
                break;
            default:
                return null;
        }

        if (ifStatement is null)
            return null;

        return TryMatchBody(tempStatement, ifStatement, indexId, bound);
    }

    private static RangePredicateCountShape? TryMatchBody(Statement? tempStatement, IfStatement ifStatement, IdentifierExpression indexId, Expression bound)
    {
        var index = indexId.Name;

        // The if must have no else and the inclusive range predicate `subject >= lo && subject <= hi`.
        if (ifStatement.ElseStatement != null)
            return null;
        if (ifStatement.Condition is not BinaryExpression { Operator: BinaryOperator.And } and)
            return null;
        if (and.Left is not BinaryExpression { Operator: BinaryOperator.GreaterOrEqual } geCmp)
            return null;
        if (and.Right is not BinaryExpression { Operator: BinaryOperator.LessOrEqual } leCmp)
            return null;

        // Resolve the predicate subject and the array. Two forms:
        //   temp:    `value := a[i]` then the predicate compares `value`.
        //   inlined: the predicate compares `a[i]` directly (both comparisons must use the same array).
        string? tempName = null;
        IdentifierExpression arrayRef;
        if (tempStatement != null)
        {
            if (tempStatement is not VariableDeclarationStatement { Initializer: { } tempInit } tempDecl)
                return null;
            if (!TryMatchArrayIndex(tempInit, index, out arrayRef))
                return null;
            tempName = tempDecl.Name;
            if (!IsIdentifier(geCmp.Left, tempName) || !IsIdentifier(leCmp.Left, tempName))
                return null;
        }
        else
        {
            if (!TryMatchArrayIndex(geCmp.Left, index, out arrayRef))
                return null;
            if (!TryMatchArrayIndex(leCmp.Left, index, out var arrayRef2) || arrayRef2.Name != arrayRef.Name)
                return null;
        }

        var lo = geCmp.Right;
        var hi = leCmp.Right;

        // The if-body is a single counter increment with no else.
        if (TryGetSingleStatement(ifStatement.ThenStatement) is not ExpressionStatement { Expression: { } counterExpr })
            return null;
        if (!TryMatchUnitCounterIncrement(counterExpr, out var counterId))
            return null;
        var counter = counterId.Name;

        // lo/hi must be loop-invariant + side-effect-free, and not the index/temp/counter (the only names
        // written in the loop body), so evaluating them once in the helper matches per-iteration evaluation.
        if (!IsInvariantOperand(lo, index, tempName, counter) || !IsInvariantOperand(hi, index, tempName, counter))
            return null;

        // Distinct names: no aliasing / loop-carried dependence.
        if (counter == arrayRef.Name || counter == index || arrayRef.Name == index)
            return null;
        if (tempName != null && (tempName == counter || tempName == arrayRef.Name || tempName == index))
            return null;

        // The bound must be loop-invariant. The counter (and the per-iteration temp) are written
        // every iteration, so a bound that names one (e.g. `while i < count { ... count++ }`) is
        // loop-variant and must not be vectorized — the masked-count helper snapshots the bound
        // once, scanning a different element set than the scalar loop (H1). The index is already
        // excluded by the condition check.
        if (bound is IdentifierExpression boundId && (boundId.Name == counter || boundId.Name == tempName))
            return null;

        return new RangePredicateCountShape(counterId, arrayRef, indexId, lo, hi, bound);
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

    private static bool IsIdentifier(Expression expression, string name)
        => expression is IdentifierExpression id && id.Name == name;

    // A range bound (lo/hi) operand: int literal, or an identifier that is not written in the loop body (i.e.
    // not the index/temp/counter). Those are the only loop-variant names, so any other identifier is invariant.
    private static bool IsInvariantOperand(Expression operand, string index, string? tempName, string counter) => operand switch
    {
        IntLiteralExpression => true,
        IdentifierExpression id => id.Name != index && id.Name != counter && id.Name != tempName,
        _ => false,
    };

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
