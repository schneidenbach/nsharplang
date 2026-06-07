using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// RUST-PERF P2(a): the range-predicate count detector (RangePredicateCountShape.TryMatch) that will gate the
/// masked-SIMD count codegen (P2(b)) for the count-ascii kernel. Pure structural detection — no IL emission,
/// no codegen change — so a false negative is harmless (scalar loop unchanged) but a false positive must be
/// impossible. These tests pin the shapes it accepts (while/for, temp/inlined subject) and the many near-miss
/// shapes it must REJECT, so the future vectorization can never fire where it would change results.
/// </summary>
[Trait("Category", "Simd")]
public class RangePredicateCountShapeTests
{
    private static T FirstLoop<T>(string body) where T : Statement
    {
        var src = "func f(a: int[], b: int[], n: int, lo: int, hi: int): int {\n" + body + "\n    return count\n}\n";
        var cu = new Parser(new Lexer(src, "t.nl").Tokenize(), "t.nl").ParseCompilationUnit().CompilationUnit;
        var fn = cu!.Declarations.OfType<FunctionDeclaration>().Single();
        return fn.Body!.Statements.OfType<T>().First();
    }

    [Theory]
    // while-form, temp subject, literal bounds, count = count + 1.
    [InlineData("    count := 0\n    i := 0\n    while i < n {\n        value := a[i]\n        if value >= 32 && value <= 126 {\n            count = count + 1\n        }\n        i = i + 1\n    }")]
    // while-form, inlined subject, param bounds, count += 1.
    [InlineData("    count := 0\n    i := 0\n    while i < n {\n        if a[i] >= lo && a[i] <= hi {\n            count += 1\n        }\n        i = i + 1\n    }")]
    // while-form, temp subject, count++.
    [InlineData("    count := 0\n    i := 0\n    while i < a.Length {\n        value := a[i]\n        if value >= lo && value <= hi {\n            count++\n        }\n        i = i + 1\n    }")]
    public void Matches_WhileFormRangeCount(string body)
    {
        var shape = RangePredicateCountShape.TryMatch(FirstLoop<WhileStatement>(body));
        Assert.NotNull(shape);
        Assert.Equal("count", shape!.Counter);
        Assert.Equal("a", shape.Array);
        Assert.Equal("i", shape.Index);
    }

    [Theory]
    // for-form, temp subject (the count-ascii benchmark shape).
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        value := a[i]\n        if value >= 32 && value <= 126 {\n            count = count + 1\n        }\n    }")]
    // for-form, inlined subject, param bounds, count++.
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] >= lo && a[i] <= hi {\n            count++\n        }\n    }")]
    // for-form, a.Length bound, count += 1.
    [InlineData("    count := 0\n    for i := 0; i < a.Length; i++ {\n        value := a[i]\n        if value >= lo && value <= hi {\n            count += 1\n        }\n    }")]
    public void Matches_ForFormRangeCount(string body)
    {
        var shape = RangePredicateCountShape.TryMatch(FirstLoop<ForStatement>(body));
        Assert.NotNull(shape);
        Assert.Equal("count", shape!.Counter);
        Assert.Equal("a", shape.Array);
        Assert.Equal("i", shape.Index);
    }

    [Theory]
    // Has an else branch.
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] >= lo && a[i] <= hi {\n            count++\n        } else {\n            count = count - 1\n        }\n    }")]
    // Exclusive comparisons (> / <) change the matched set vs the helper's inclusive compare.
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] > lo && a[i] < hi {\n            count++\n        }\n    }")]
    // OR instead of AND.
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] >= lo || a[i] <= hi {\n            count++\n        }\n    }")]
    // Counter increments by 2 (not a unit count).
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] >= lo && a[i] <= hi {\n            count += 2\n        }\n    }")]
    // count = count + 2.
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] >= lo && a[i] <= hi {\n            count = count + 2\n        }\n    }")]
    // Extra statement in the if-body.
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] >= lo && a[i] <= hi {\n            count++\n            count++\n        }\n    }")]
    // Extra statement in the loop body (beyond temp/if).
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        value := a[i]\n        if value >= lo && value <= hi {\n            count++\n        }\n        count = count + 0\n    }")]
    // Array indexed by something other than the loop var.
    [InlineData("    count := 0\n    j := 0\n    for i := 0; i < n; i++ {\n        if a[j] >= lo && a[j] <= hi {\n            count++\n        }\n    }")]
    // Two different arrays across the two comparisons (inlined).
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] >= lo && b[i] <= hi {\n            count++\n        }\n    }")]
    // lo references the loop index (loop-variant bound).
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        if a[i] >= i && a[i] <= hi {\n            count++\n        }\n    }")]
    // Temp subject but the predicate compares a different variable.
    [InlineData("    count := 0\n    for i := 0; i < n; i++ {\n        value := a[i]\n        if i >= lo && i <= hi {\n            count++\n        }\n    }")]
    // H1: the loop bound IS the counter, which is written every iteration (loop-variant). The
    // masked-count helper snapshots the bound once, scanning a different element set than the
    // scalar loop.
    [InlineData("    count := 0\n    for i := 0; i < count; i++ {\n        if a[i] >= lo && a[i] <= hi {\n            count++\n        }\n    }")]
    public void Rejects_NonRangeCountForShapes(string body)
    {
        Assert.Null(RangePredicateCountShape.TryMatch(FirstLoop<ForStatement>(body)));
    }

    [Theory]
    // while-form: missing the index increment as the last statement.
    [InlineData("    count := 0\n    i := 0\n    while i < n {\n        if a[i] >= lo && a[i] <= hi {\n            count++\n        }\n    }")]
    // while-form: counter increments by 2.
    [InlineData("    count := 0\n    i := 0\n    while i < n {\n        if a[i] >= lo && a[i] <= hi {\n            count += 2\n        }\n        i = i + 1\n    }")]
    // H1 (while-form): the loop bound IS the counter (loop-variant).
    [InlineData("    count := 0\n    i := 0\n    while i < count {\n        if a[i] >= lo && a[i] <= hi {\n            count++\n        }\n        i = i + 1\n    }")]
    public void Rejects_NonRangeCountWhileShapes(string body)
    {
        Assert.Null(RangePredicateCountShape.TryMatch(FirstLoop<WhileStatement>(body)));
    }
}
