using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// RUST-PERF P-minmax (a): the min/max conditional-reduction detector (MinMaxReductionLoopShape.TryMatch) that
/// gates the lane-wise Vector.Min/Vector.Max codegen for the min-max-delta kernel (the ~10.5× Rust gap). Pure
/// structural detection — no IL emission, no codegen change — so a false negative is harmless (scalar loop
/// unchanged) but a false positive must be impossible. These tests pin the shapes it accepts (while/for,
/// temp/inlined subject, min-only/max-only/both, reversed operand order) and the near-miss shapes it must
/// REJECT, so the future vectorization can never fire where it would change results.
/// </summary>
[Trait("Category", "Simd")]
public class MinMaxReductionLoopShapeTests
{
    private static T FirstLoop<T>(string body) where T : Statement
    {
        var src = "func f(a: int[], b: int[], n: int): int {\n" + body + "\n    return max - min\n}\n";
        var cu = new Parser(new Lexer(src, "t.nl").Tokenize(), "t.nl").ParseCompilationUnit().CompilationUnit;
        var fn = cu!.Declarations.OfType<FunctionDeclaration>().Single();
        return fn.Body!.Statements.OfType<T>().First();
    }

    // ---- Accept: the min-max-delta kernel (both reductions) -----------------------------------------------

    [Theory]
    // for-form, temp subject (the min-max-delta benchmark shape).
    [InlineData("    min := a[0]\n    max := a[0]\n    for i := 1; i < n; i++ {\n        value := a[i]\n        if value < min {\n            min = value\n        }\n        if value > max {\n            max = value\n        }\n    }")]
    // for-form, inlined subject.
    [InlineData("    min := a[0]\n    max := a[0]\n    for i := 0; i < a.Length; i++ {\n        if a[i] < min {\n            min = a[i]\n        }\n        if a[i] > max {\n            max = a[i]\n        }\n    }")]
    // for-form, reversed operand order (`min > value`, `max < value`).
    [InlineData("    min := a[0]\n    max := a[0]\n    for i := 1; i < n; i++ {\n        value := a[i]\n        if min > value {\n            min = value\n        }\n        if max < value {\n            max = value\n        }\n    }")]
    public void Matches_ForFormMinMax(string body)
    {
        var shape = MinMaxReductionLoopShape.TryMatch(FirstLoop<ForStatement>(body));
        Assert.NotNull(shape);
        Assert.Equal("a", shape!.Array);
        Assert.Equal("i", shape.Index);
        Assert.Equal(2, shape.Reductions.Count);
        Assert.Contains(shape.Reductions, r => r.IsMin && r.Accumulator == "min");
        Assert.Contains(shape.Reductions, r => !r.IsMin && r.Accumulator == "max");
    }

    [Theory]
    // while-form, temp subject.
    [InlineData("    min := a[0]\n    max := a[0]\n    i := 1\n    while i < n {\n        value := a[i]\n        if value < min {\n            min = value\n        }\n        if value > max {\n            max = value\n        }\n        i = i + 1\n    }")]
    // while-form, inlined subject, i++.
    [InlineData("    min := a[0]\n    max := a[0]\n    i := 0\n    while i < a.Length {\n        if a[i] < min {\n            min = a[i]\n        }\n        if a[i] > max {\n            max = a[i]\n        }\n        i++\n    }")]
    public void Matches_WhileFormMinMax(string body)
    {
        var shape = MinMaxReductionLoopShape.TryMatch(FirstLoop<WhileStatement>(body));
        Assert.NotNull(shape);
        Assert.Equal("a", shape!.Array);
        Assert.Equal("i", shape.Index);
        Assert.Equal(2, shape.Reductions.Count);
    }

    // ---- Accept: a single reduction (min-only / max-only) -------------------------------------------------

    [Fact]
    public void Matches_MinOnly_BracelessFor()
    {
        var shape = MinMaxReductionLoopShape.TryMatch(FirstLoop<ForStatement>(
            "    min := a[0]\n    for i := 1; i < n; i++ {\n        if a[i] < min {\n            min = a[i]\n        }\n    }"));
        Assert.NotNull(shape);
        Assert.Single(shape!.Reductions);
        Assert.True(shape.Reductions[0].IsMin);
        Assert.Equal("min", shape.Reductions[0].Accumulator);
    }

    [Fact]
    public void Matches_MaxOnly_Temp()
    {
        var shape = MinMaxReductionLoopShape.TryMatch(FirstLoop<ForStatement>(
            "    max := a[0]\n    for i := 1; i < n; i++ {\n        value := a[i]\n        if value > max {\n            max = value\n        }\n    }"));
        Assert.NotNull(shape);
        Assert.Single(shape!.Reductions);
        Assert.False(shape.Reductions[0].IsMin);
        Assert.Equal("max", shape.Reductions[0].Accumulator);
    }

    // ---- Reject: for-form near misses --------------------------------------------------------------------

    [Theory]
    // Non-strict comparison (<= / >=): a harmless conservative reject (still value-identical, but pin the shape).
    [InlineData("    min := a[0]\n    max := a[0]\n    for i := 1; i < n; i++ {\n        value := a[i]\n        if value <= min {\n            min = value\n        }\n        if value > max {\n            max = value\n        }\n    }")]
    // Has an else branch.
    [InlineData("    min := a[0]\n    max := a[0]\n    for i := 1; i < n; i++ {\n        if a[i] < min {\n            min = a[i]\n        } else {\n            max = a[i]\n        }\n    }")]
    // The assigned value is not the compared subject (`min = value + 1`).
    [InlineData("    min := a[0]\n    for i := 1; i < n; i++ {\n        value := a[i]\n        if value < min {\n            min = value + 1\n        }\n    }")]
    // Array indexed by something other than the loop var.
    [InlineData("    min := a[0]\n    j := 0\n    for i := 1; i < n; i++ {\n        if a[j] < min {\n            min = a[j]\n        }\n    }")]
    // Two different arrays across the two reductions (inlined).
    [InlineData("    min := a[0]\n    max := a[0]\n    for i := 0; i < n; i++ {\n        if a[i] < min {\n            min = a[i]\n        }\n        if b[i] > max {\n            max = b[i]\n        }\n    }")]
    // Temp subject but the predicate compares a different variable.
    [InlineData("    min := a[0]\n    for i := 1; i < n; i++ {\n        value := a[i]\n        if i < min {\n            min = i\n        }\n    }")]
    // Both ifs write the SAME accumulator (would emit two reductions into one acc).
    [InlineData("    min := a[0]\n    for i := 1; i < n; i++ {\n        if a[i] < min {\n            min = a[i]\n        }\n        if a[i] > min {\n            min = a[i]\n        }\n    }")]
    // Extra statement in the loop body (beyond temp + 2 ifs).
    [InlineData("    min := a[0]\n    max := a[0]\n    for i := 1; i < n; i++ {\n        value := a[i]\n        if value < min {\n            min = value\n        }\n        if value > max {\n            max = value\n        }\n        min = min + 0\n    }")]
    // Extra statement inside an if-body.
    [InlineData("    min := a[0]\n    for i := 1; i < n; i++ {\n        if a[i] < min {\n            min = a[i]\n            min = a[i]\n        }\n    }")]
    // Loop-variant bound (bound is the index).
    [InlineData("    min := a[0]\n    for i := 1; i < i; i++ {\n        if a[i] < min {\n            min = a[i]\n        }\n    }")]
    // Non-unit increment.
    [InlineData("    min := a[0]\n    for i := 1; i < n; i += 2 {\n        if a[i] < min {\n            min = a[i]\n        }\n    }")]
    // Condition compares the accumulator against a constant, not the subject.
    [InlineData("    min := a[0]\n    for i := 1; i < n; i++ {\n        if a[i] < 5 {\n            min = a[i]\n        }\n    }")]
    public void Rejects_NonMinMaxForShapes(string body)
    {
        Assert.Null(MinMaxReductionLoopShape.TryMatch(FirstLoop<ForStatement>(body)));
    }

    // ---- Reject: while-form near misses ------------------------------------------------------------------

    [Theory]
    // Missing the index increment as the last statement.
    [InlineData("    min := a[0]\n    i := 1\n    while i < n {\n        if a[i] < min {\n            min = a[i]\n        }\n    }")]
    // Increment by 2 (not a unit increment).
    [InlineData("    min := a[0]\n    i := 1\n    while i < n {\n        if a[i] < min {\n            min = a[i]\n        }\n        i = i + 2\n    }")]
    // Increment is not last (a statement follows it).
    [InlineData("    min := a[0]\n    i := 1\n    while i < n {\n        i = i + 1\n        if a[i] < min {\n            min = a[i]\n        }\n    }")]
    public void Rejects_NonMinMaxWhileShapes(string body)
    {
        Assert.Null(MinMaxReductionLoopShape.TryMatch(FirstLoop<WhileStatement>(body)));
    }
}
