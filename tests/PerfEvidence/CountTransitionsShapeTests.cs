using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// RUST-PERF P-ctrans (a): the adjacent-difference count detector (CountTransitionsShape.TryMatch) that gates the
/// shifted-compare masked-SIMD codegen (P-ctrans(b)) for the count-transitions kernel (the last ~2.5–4.5× Rust
/// gap). Pure structural detection — no IL emission — so a false negative is harmless (scalar loop unchanged) but
/// a false positive must be impossible. These tests pin the accepted shapes (for/while, the carried `previous`
/// compare + carry) and the near-miss rejections, so the future vectorization can never fire where it would
/// change results.
/// </summary>
[Trait("Category", "Simd")]
public class CountTransitionsShapeTests
{
    private static T FirstLoop<T>(string body) where T : Statement
    {
        var src = "func f(a: int[], b: int[], n: int): int {\n" + body + "\n    return count\n}\n";
        var cu = new Parser(new Lexer(src, "t.nl").Tokenize(), "t.nl").ParseCompilationUnit().CompilationUnit;
        var fn = cu!.Declarations.OfType<FunctionDeclaration>().Single();
        return fn.Body!.Statements.OfType<T>().First();
    }

    [Theory]
    // for-form (the count-transitions benchmark shape).
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        previous = current\n    }")]
    // for-form, a.Length bound, count++.
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < a.Length; i++ {\n        current := a[i]\n        if current != previous {\n            count++\n        }\n        previous = current\n    }")]
    // reversed compare operand order (previous != current), count += 1.
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if previous != current {\n            count += 1\n        }\n        previous = current\n    }")]
    public void Matches_ForFormCountTransitions(string body)
    {
        var shape = CountTransitionsShape.TryMatch(FirstLoop<ForStatement>(body));
        Assert.NotNull(shape);
        Assert.Equal("count", shape!.Counter);
        Assert.Equal("a", shape.Array);
        Assert.Equal("i", shape.Index);
        Assert.Equal("previous", shape.Previous);
    }

    [Fact]
    public void Matches_WhileFormCountTransitions()
    {
        var shape = CountTransitionsShape.TryMatch(FirstLoop<WhileStatement>(
            "    count := 0\n    previous := a[0]\n    i := 1\n    while i < n {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        previous = current\n        i = i + 1\n    }"));
        Assert.NotNull(shape);
        Assert.Equal("count", shape!.Counter);
        Assert.Equal("previous", shape.Previous);
    }

    [Theory]
    // Has an else branch.
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        } else {\n            count = count - 1\n        }\n        previous = current\n    }")]
    // Equality (==) instead of != — a different predicate (counts equal adjacents).
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current == previous {\n            count = count + 1\n        }\n        previous = current\n    }")]
    // Counter increments by 2 (not a unit count).
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current != previous {\n            count += 2\n        }\n        previous = current\n    }")]
    // Missing the carry (only temp + if).
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n    }")]
    // Carry assigns from a re-read a[i] (inlined carry) instead of the temp — not the temp form we accept.
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        previous = a[i]\n    }")]
    // Carry writes a different variable (not previous).
    [InlineData("    count := 0\n    previous := a[0]\n    other := 0\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        other = current\n    }")]
    // Compare is against a[i] directly (both operands not identifiers / no carried scalar).
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current != a[i] {\n            count = count + 1\n        }\n        previous = current\n    }")]
    // Array indexed by something other than the loop var.
    [InlineData("    count := 0\n    previous := a[0]\n    j := 0\n    for i := 1; i < n; i++ {\n        current := a[j]\n        if current != previous {\n            count = count + 1\n        }\n        previous = current\n    }")]
    // Extra statement in the loop body (4 statements).
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i++ {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        previous = current\n        count = count + 0\n    }")]
    // Loop-variant bound (bound is the index).
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < i; i++ {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        previous = current\n    }")]
    // Non-unit increment.
    [InlineData("    count := 0\n    previous := a[0]\n    for i := 1; i < n; i += 2 {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        previous = current\n    }")]
    public void Rejects_NonCountTransitionsForShapes(string body)
    {
        Assert.Null(CountTransitionsShape.TryMatch(FirstLoop<ForStatement>(body)));
    }

    [Theory]
    // Bound is the carried value; scalar code re-reads it after `previous = current`.
    [InlineData("previous")]
    // Bound is the counter; scalar code can re-read it after the conditional increment.
    [InlineData("count")]
    // Bound is declared by the accepted temp statement.
    [InlineData("current")]
    public void Rejects_BoundsWrittenByMatchedForLoopBody(string bound)
    {
        var shape = CountTransitionsShape.TryMatch(FirstLoop<ForStatement>(
            "    count := 4\n    previous := 4\n    current := 4\n    for i := 0; i < " + bound + "; i++ {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        previous = current\n    }"));
        Assert.Null(shape);
    }

    [Theory]
    // while-form: increment not last (carry follows it).
    [InlineData("    count := 0\n    previous := a[0]\n    i := 1\n    while i < n {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        i = i + 1\n        previous = current\n    }")]
    // while-form: missing the carry.
    [InlineData("    count := 0\n    previous := a[0]\n    i := 1\n    while i < n {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        i = i + 1\n    }")]
    public void Rejects_NonCountTransitionsWhileShapes(string body)
    {
        Assert.Null(CountTransitionsShape.TryMatch(FirstLoop<WhileStatement>(body)));
    }

    [Fact]
    public void Rejects_BoundsWrittenByMatchedWhileLoopBody()
    {
        var shape = CountTransitionsShape.TryMatch(FirstLoop<WhileStatement>(
            "    count := 0\n    previous := 4\n    i := 0\n    while i < previous {\n        current := a[i]\n        if current != previous {\n            count = count + 1\n        }\n        previous = current\n        i = i + 1\n    }"));
        Assert.Null(shape);
    }
}
