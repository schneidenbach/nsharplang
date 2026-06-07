using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>Which extremum a recognized conditional reduction computes — <c>min</c> (keeps the smaller value)
/// or <c>max</c> (keeps the larger value).</summary>
public enum MinMaxKind
{
    Min,
    Max,
}

/// <summary>One min/max conditional reduction inside the loop body: <c>if subject &lt; acc { acc = subject }</c>
/// (min) or <c>if subject &gt; acc { acc = subject }</c> (max), reading the shared loop subject (the array
/// element). The emitter lowers each to a <see cref="Runtime.SimdReductions"/> min/max helper seeded with the
/// pre-loop accumulator value.</summary>
public sealed record MinMaxReduction(IdentifierExpression AccumulatorRef, MinMaxKind Kind)
{
    /// <summary>The accumulator local/parameter name.</summary>
    public string Accumulator => AccumulatorRef.Name;

    /// <summary>True for a min reduction (keeps the smaller value), false for a max reduction.</summary>
    public bool IsMin => Kind == MinMaxKind.Min;
}

/// <summary>
/// RUST-PERF P-minmax (docs/design/roadmap-to-done.md, systems-perf-backlog.md). Recognizes the canonical
/// min/max conditional-reduction loop — the min-max-delta kernel (the ~10.5× Rust gap, the single largest
/// remaining one) — that the auto-vectorizing codegen rewrites into lane-wise <c>Vector.Min</c>/<c>Vector.Max</c>
/// reductions. Integer min and max are associative AND commutative (a total order), so reducing across SIMD
/// lanes and multiple accumulators is value-identical to the sequential scalar fold for ANY (start, end).
///
/// Recognized shape (while- and for-forms; temp or inlined subject; one OR two reductions in one body):
/// <code>
///   for i := s; i &lt; bound; i++ {
///       value := a[i]                 // optional temp; otherwise the subject is a[i] inlined
///       if value &lt; min { min = value }  // min reduction (strict &lt;; reversed `min > value` also matches)
///       if value &gt; max { max = value }  // max reduction (strict &gt;; reversed `max < value` also matches)
///   }
/// </code>
/// The while-form is identical with the unit index increment as the loop's LAST body statement. A single
/// reduction (min-only or max-only) is also recognized.
///
/// Detection is purely structural and CONSERVATIVE (no types here — the emitter adds the int/array guard):
/// a false negative is harmless (the scalar loop is emitted unchanged); a false positive must be impossible.
/// Every safety condition that makes the rewrite value-preserving is enforced:
/// <list type="bullet">
/// <item>condition is <c>index &lt; bound</c> with a loop-invariant, side-effect-free bound (identifier,
///   int literal, or array <c>.Length</c>) that is not the index;</item>
/// <item>each reduction is exactly <c>if subject ⋚ acc { acc = subject }</c> with a STRICT <c>&lt;</c>/<c>&gt;</c>
///   and no <c>else</c>; the assigned value equals the compared subject, which is the array element
///   <c>a[index]</c> (inlined) or a temp bound once to <c>a[index]</c>;</item>
/// <item>the array is indexed only by <c>index</c>; accumulator(s), array, index and (temp) are all distinct
///   names, and the accumulators are distinct from each other — so there is no loop-carried dependence, no
///   aliasing, and each accumulator is written by exactly one reduction.</item>
/// </list>
/// </summary>
public sealed record MinMaxReductionLoopShape(
    IdentifierExpression ArrayRef,
    IdentifierExpression IndexRef,
    Expression Bound,
    IReadOnlyList<MinMaxReduction> Reductions)
{
    /// <summary>The scanned array local/parameter name.</summary>
    public string Array => ArrayRef.Name;

    /// <summary>The loop index local/parameter name.</summary>
    public string Index => IndexRef.Name;

    /// <summary>Matches the while-form (the unit index increment is the loop's last body statement).</summary>
    public static MinMaxReductionLoopShape? TryMatch(WhileStatement loop)
    {
        if (!TryMatchCondition(loop.Condition, out var indexId, out var bound))
            return null;

        // Body: the predicate part (optional temp + 1–2 min/max ifs) followed by the unit index increment.
        if (loop.Body is not BlockStatement { Statements: { Count: >= 2 } statements })
            return null;
        if (statements[statements.Count - 1] is not ExpressionStatement { Expression: { } increment }
            || !IsUnitIncrement(increment, indexId.Name))
            return null;

        var body = new List<Statement>(statements.Count - 1);
        for (var i = 0; i < statements.Count - 1; i++)
            body.Add(statements[i]);

        return TryMatchBody(body, indexId, bound);
    }

    /// <summary>Matches the for-form (the unit index increment is the iterator; the body is the predicate part).
    /// The caller emits <see cref="ForStatement.Initializer"/> separately.</summary>
    public static MinMaxReductionLoopShape? TryMatch(ForStatement loop)
    {
        if (!TryMatchCondition(loop.Condition, out var indexId, out var bound))
            return null;
        if (loop.Iterator is null || !IsUnitIncrement(loop.Iterator, indexId.Name))
            return null;

        var body = BodyStatements(loop.Body);
        if (body is null)
            return null;

        return TryMatchBody(body, indexId, bound);
    }

    private static MinMaxReductionLoopShape? TryMatchBody(IReadOnlyList<Statement> statements, IdentifierExpression indexId, Expression bound)
    {
        // Predicate part: an optional leading temp `value := a[index]`, then 1–2 min/max if-statements.
        if (statements.Count < 1 || statements.Count > 3)
            return null;

        var index = indexId.Name;
        var ifStart = 0;
        string? tempName = null;
        IdentifierExpression? arrayRef = null;

        if (statements[0] is VariableDeclarationStatement tempDecl)
        {
            if (tempDecl.Initializer is null || !TryMatchArrayIndex(tempDecl.Initializer, index, out var tempArray))
                return null;
            tempName = tempDecl.Name;
            arrayRef = tempArray;
            ifStart = 1;
        }

        var ifCount = statements.Count - ifStart;
        if (ifCount < 1 || ifCount > 2)
            return null;

        var reductions = new List<MinMaxReduction>(ifCount);
        var seenAccumulators = new HashSet<string>();
        for (var k = ifStart; k < statements.Count; k++)
        {
            if (statements[k] is not IfStatement ifStatement)
                return null;
            if (!TryMatchMinMaxIf(ifStatement, index, tempName, ref arrayRef, out var reduction))
                return null;
            if (!seenAccumulators.Add(reduction.Accumulator)) // each accumulator written by exactly one reduction
                return null;
            reductions.Add(reduction);
        }

        // arrayRef is set by the temp initializer, or (inlined) by the first reduction's subject.
        if (arrayRef is null)
            return null;

        // Distinct names: no aliasing / loop-carried dependence. The array/index/temp are read; the
        // accumulators are written — all must be distinct so a single SIMD reduction per accumulator is exact.
        var array = arrayRef.Name;
        if (array == index)
            return null;
        if (tempName != null && (tempName == array || tempName == index))
            return null;
        foreach (var reduction in reductions)
        {
            if (reduction.Accumulator == array || reduction.Accumulator == index || reduction.Accumulator == tempName)
                return null;
        }

        return new MinMaxReductionLoopShape(arrayRef, indexId, bound, reductions);
    }

    // The for-loop body as a statement list: a block's statements, or a single braceless if (min-only/max-only).
    private static IReadOnlyList<Statement>? BodyStatements(Statement body) => body switch
    {
        BlockStatement block => block.Statements,
        IfStatement => new List<Statement> { body },
        _ => null,
    };

    // `if subject ⋚ acc { acc = subject }` (no else). The assigned value is the subject; the condition compares
    // the subject and the accumulator with a strict </>. min vs max is derived from operand order + operator:
    //   subject < acc  / acc > subject  -> min        subject > acc / acc < subject -> max.
    private static bool TryMatchMinMaxIf(IfStatement ifStatement, string index, string? tempName, ref IdentifierExpression? arrayRef, out MinMaxReduction reduction)
    {
        reduction = null!;
        if (ifStatement.ElseStatement != null)
            return false;

        // Then-body: a single `acc = subject` assignment.
        if (TryGetSingleStatement(ifStatement.ThenStatement) is not ExpressionStatement
            {
                Expression: AssignmentExpression { Operator: AssignmentOperator.Assign } assignment
            })
            return false;
        if (assignment.Target is not IdentifierExpression accumulatorId)
            return false;

        // The assigned value must be the loop subject (binds arrayRef for the inlined form on first use).
        if (!TryMatchSubject(assignment.Value, index, tempName, ref arrayRef))
            return false;

        // Condition: a strict < or > comparing the subject and the accumulator (either operand order).
        if (ifStatement.Condition is not BinaryExpression { Operator: BinaryOperator.Less or BinaryOperator.Greater } comparison)
            return false;

        var leftIsAccumulator = IsIdentifier(comparison.Left, accumulatorId.Name);
        var rightIsAccumulator = IsIdentifier(comparison.Right, accumulatorId.Name);
        var leftIsSubject = IsSubject(comparison.Left, index, tempName, arrayRef);
        var rightIsSubject = IsSubject(comparison.Right, index, tempName, arrayRef);

        MinMaxKind kind;
        if (leftIsSubject && rightIsAccumulator)
            // subject < acc -> min ; subject > acc -> max.
            kind = comparison.Operator == BinaryOperator.Less ? MinMaxKind.Min : MinMaxKind.Max;
        else if (leftIsAccumulator && rightIsSubject)
            // acc > subject -> min ; acc < subject -> max.
            kind = comparison.Operator == BinaryOperator.Greater ? MinMaxKind.Min : MinMaxKind.Max;
        else
            return false;

        reduction = new MinMaxReduction(accumulatorId, kind);
        return true;
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

    // Binds/validates the loop subject. With a temp, the subject is the temp identifier; inlined, it is a[index]
    // for a single array (bound on first use, required equal thereafter).
    private static bool TryMatchSubject(Expression expression, string index, string? tempName, ref IdentifierExpression? arrayRef)
    {
        if (tempName != null)
            return IsIdentifier(expression, tempName);
        if (!TryMatchArrayIndex(expression, index, out var array))
            return false;
        if (arrayRef is null)
        {
            arrayRef = array;
            return true;
        }

        return array.Name == arrayRef.Name;
    }

    // Non-binding subject check for the condition operands (arrayRef is already bound by the assignment value).
    private static bool IsSubject(Expression expression, string index, string? tempName, IdentifierExpression? arrayRef)
    {
        if (tempName != null)
            return IsIdentifier(expression, tempName);
        return arrayRef != null && TryMatchArrayIndex(expression, index, out var array) && array.Name == arrayRef.Name;
    }

    private static Statement? TryGetSingleStatement(Statement statement) => statement switch
    {
        BlockStatement { Statements: { Count: 1 } s } => s[0],
        ExpressionStatement => statement,
        _ => null,
    };

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
