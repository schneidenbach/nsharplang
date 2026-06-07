using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// RUST-PERF P1(a): the counted-reduction loop detector (ReductionLoopShape.TryMatch) that gates the
/// auto-vectorizing codegen. Pure structural detection — no IL emission, no codegen change — so a false
/// negative is harmless (scalar loop unchanged) but a false positive must be impossible. These tests pin the
/// shape it accepts and, importantly, the many near-miss shapes it must REJECT, so vectorization can never
/// fire on a loop where it would change results.
/// </summary>
[Trait("Category", "Simd")]
public class ReductionLoopShapeTests
{
    private static WhileStatement FirstWhile(string body)
    {
        var src = "func f(a: int[], b: int[], n: int): int {\n" + body + "\n    return acc\n}\n";
        var cu = new Parser(new Lexer(src, "t.nl").Tokenize(), "t.nl").ParseCompilationUnit().CompilationUnit;
        var fn = cu!.Declarations.OfType<FunctionDeclaration>().Single();
        return fn.Body!.Statements.OfType<WhileStatement>().First();
    }

    [Fact]
    public void Matches_CanonicalReduction()
    {
        var shape = ReductionLoopShape.TryMatch(FirstWhile(
            "    acc := 0\n    i := 0\n    while i < n {\n        acc = acc + a[i]\n        i = i + 1\n    }"));
        Assert.NotNull(shape);
        Assert.Equal("acc", shape!.Accumulator);
        Assert.Equal("a", shape.Array);
        Assert.Equal("i", shape.Index);
    }

    [Fact]
    public void Matches_CompoundAssignmentForms()
    {
        var shape = ReductionLoopShape.TryMatch(FirstWhile(
            "    acc := 0\n    i := 0\n    while i < n {\n        acc += a[i]\n        i += 1\n    }"));
        Assert.NotNull(shape);
        Assert.Equal("acc", shape!.Accumulator);
        Assert.Equal("a", shape.Array);
    }

    [Fact]
    public void Matches_LengthBound()
    {
        var shape = ReductionLoopShape.TryMatch(FirstWhile(
            "    acc := 0\n    i := 0\n    while i < a.Length {\n        acc = acc + a[i]\n        i = i + 1\n    }"));
        Assert.NotNull(shape);
        Assert.Equal("a", shape!.Array);
    }

    [Theory]
    // Stride != 1 -> not unit stride.
    [InlineData("    acc := 0\n    i := 0\n    while i < n {\n        acc = acc + a[i]\n        i = i + 2\n    }")]
    // Accumulator update is not a plain array element (a[i] * 2).
    [InlineData("    acc := 0\n    i := 0\n    while i < n {\n        acc = acc + a[i] * 2\n        i = i + 1\n    }")]
    // Two arrays read -> loop body is not a single-array reduction.
    [InlineData("    acc := 0\n    i := 0\n    while i < n {\n        acc = acc + a[i] + b[i]\n        i = i + 1\n    }")]
    // Array indexed by something other than the loop index.
    [InlineData("    acc := 0\n    i := 0\n    j := 0\n    while i < n {\n        acc = acc + a[j]\n        i = i + 1\n    }")]
    // <= bound changes the trip count shape.
    [InlineData("    acc := 0\n    i := 0\n    while i <= n {\n        acc = acc + a[i]\n        i = i + 1\n    }")]
    // Extra statement in the body.
    [InlineData("    acc := 0\n    i := 0\n    while i < n {\n        acc = acc + a[i]\n        i = i + 1\n        acc = acc + 1\n    }")]
    // break breaks the regular control flow (body is not the fixed two statements).
    [InlineData("    acc := 0\n    i := 0\n    while i < n {\n        acc = acc + a[i]\n        i = i + 1\n        break\n    }")]
    // Increment before the accumulator update reads the wrong element.
    [InlineData("    acc := 0\n    i := 0\n    while i < n {\n        i = i + 1\n        acc = acc + a[i]\n    }")]
    public void Rejects_NonReductionShapes(string body)
    {
        Assert.Null(ReductionLoopShape.TryMatch(FirstWhile(body)));
    }

    // ---- P1(f): for-form detection (the increment is the iterator; the body is the single accumulator update) --
    private static ForStatement FirstFor(string body)
    {
        var src = "func f(a: int[], b: int[], n: int): int {\n" + body + "\n    return acc\n}\n";
        var cu = new Parser(new Lexer(src, "t.nl").Tokenize(), "t.nl").ParseCompilationUnit().CompilationUnit;
        var fn = cu!.Declarations.OfType<FunctionDeclaration>().Single();
        return fn.Body!.Statements.OfType<ForStatement>().First();
    }

    [Theory]
    // Canonical for-form with i++.
    [InlineData("    acc := 0\n    for i := 0; i < n; i++ {\n        acc = acc + a[i]\n    }")]
    // ++i (pre-increment) iterator.
    [InlineData("    acc := 0\n    for i := 0; i < n; ++i {\n        acc = acc + a[i]\n    }")]
    // i = i + 1 iterator + compound accumulator.
    [InlineData("    acc := 0\n    for i := 0; i < n; i = i + 1 {\n        acc += a[i]\n    }")]
    // i += 1 iterator.
    [InlineData("    acc := 0\n    for i := 0; i < n; i += 1 {\n        acc = acc + a[i]\n    }")]
    // a.Length bound.
    [InlineData("    acc := 0\n    for i := 0; i < a.Length; i++ {\n        acc = acc + a[i]\n    }")]
    // Non-zero start (the helper handles arbitrary start).
    [InlineData("    acc := 0\n    for i := 4; i < n; i++ {\n        acc = acc + a[i]\n    }")]
    public void Matches_ForFormReductions(string body)
    {
        var shape = ReductionLoopShape.TryMatch(FirstFor(body));
        Assert.NotNull(shape);
        Assert.Equal("acc", shape!.Accumulator);
        Assert.Equal("a", shape.Array);
        Assert.Equal("i", shape.Index);
    }

    [Theory]
    // Stride != 1.
    [InlineData("    acc := 0\n    for i := 0; i < n; i += 2 {\n        acc = acc + a[i]\n    }")]
    // Decrement iterator.
    [InlineData("    acc := 0\n    for i := 0; i < n; i-- {\n        acc = acc + a[i]\n    }")]
    // a[i] * 2 (not a plain element).
    [InlineData("    acc := 0\n    for i := 0; i < n; i++ {\n        acc = acc + a[i] * 2\n    }")]
    // Two arrays.
    [InlineData("    acc := 0\n    for i := 0; i < n; i++ {\n        acc = acc + a[i] + b[i]\n    }")]
    // Indexed by something other than the loop var.
    [InlineData("    acc := 0\n    j := 0\n    for i := 0; i < n; i++ {\n        acc = acc + a[j]\n    }")]
    // <= bound changes the trip-count shape.
    [InlineData("    acc := 0\n    for i := 0; i <= n; i++ {\n        acc = acc + a[i]\n    }")]
    // Extra body statement (more than the single accumulator update).
    [InlineData("    acc := 0\n    for i := 0; i < n; i++ {\n        acc = acc + a[i]\n        acc = acc + 1\n    }")]
    public void Rejects_NonReductionForShapes(string body)
    {
        Assert.Null(ReductionLoopShape.TryMatch(FirstFor(body)));
    }
}
