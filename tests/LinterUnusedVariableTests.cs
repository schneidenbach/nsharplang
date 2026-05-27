using System.Collections.Generic;
using System.Linq;
using Xunit;
using NSharpLang.Compiler;

namespace NSharpLang.Tests;

/// <summary>
/// Focused tests for NL001: Unused Variable diagnostics
/// Testing both false positives and diagnostic positioning
/// </summary>
public class LinterUnusedVariableTests
{
    private List<Diagnostic> Lint(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var parseResult = parser.ParseCompilationUnit();
        var linter = new Linter();
        return linter.Lint(parseResult.CompilationUnit!, "test.nl");
    }

    #region Diagnostic Positioning Tests

    [Fact]
    public void UnusedVariable_DiagnosticPointsToVariableName_NotKeyword()
    {
        // The squiggly should be under "unused", not "let"
        var source = "func main() { let unused = 42 }";

        var diagnostics = Lint(source);

        var unusedDiag = diagnostics.FirstOrDefault(d => d.Code == "NL001");
        Assert.NotNull(unusedDiag);

        // Column should point to "unused" (after "let ")
        // "let unused" -> 'unused' starts at column 18 (after "func main() { let ")
        Assert.True(unusedDiag.Location.Column >= 18,
            $"Expected column >= 18 (at variable name), but got {unusedDiag.Location.Column}");
    }

    [Fact]
    public void UnusedVariable_InferredDeclaration_DiagnosticPointsToVariableName()
    {
        var source = "func main() { unused := 42 }";

        var diagnostics = Lint(source);

        var unusedDiag = diagnostics.FirstOrDefault(d => d.Code == "NL001");
        Assert.NotNull(unusedDiag);

        // "unused :=" -> 'unused' starts at column 15.
        Assert.True(unusedDiag.Location.Column >= 15,
            $"Expected column >= 15 (at variable name), but got {unusedDiag.Location.Column}");
    }

    #endregion

    #region String Interpolation Tests

    [Fact]
    public void VariableUsedInStringInterpolation_ShouldNotBeMarkedUnused()
    {
        var source = @"func main(): void
    let name = ""Alice""
    print($""Hello {name}"")";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        // Should not have unused variable warning for 'name'
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'name'"));
    }

    [Fact]
    public void VariableUsedInInterpolatedRawString_ShouldNotBeMarkedUnused()
    {
        var source = @"func main(): void
    let value = 42
    let message = $""""""
        The value is {value}
    """"""";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        // Should not have unused variable warning for 'value'
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'value'"));
    }

    [Fact]
    public void MultipleVariablesInStringInterpolation_ShouldNotBeMarkedUnused()
    {
        var source = @"func main(): void
    let first = ""John""
    let last = ""Doe""
    let age = 30
    print($""{first} {last} is {age} years old"")";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        // None of the variables should be marked as unused
        Assert.Empty(unusedDiags);
    }

    #endregion

    #region Foreach Loop Tests

    [Fact]
    public void LoopVariable_Foreach_ShouldNotBeMarkedUnused()
    {
        var source = @"func main(): void
    let numbers = [1, 2, 3]
    foreach (num in numbers)
        print(num)";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        // Loop variable 'num' should not be marked unused
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'num'"));
        // 'numbers' should not be marked unused either
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'numbers'"));
    }

    [Fact]
    public void VariableUsedInForeachBody_ShouldNotBeMarkedUnused()
    {
        var source = @"func main(): void
    let multiplier = 2
    let numbers = [1, 2, 3]
    foreach (num in numbers)
        print(num * multiplier)";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        // 'multiplier' is used inside foreach body
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'multiplier'"));
    }

    [Fact]
    public void ForLoop_LoopVariableShouldNotBeMarkedUnused()
    {
        var source = @"func main(): void
    for (let i = 0; i < 10; i++)
        print(i)";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'i'"));
    }

    #endregion

    #region LINQ and Method Chain Tests

    [Fact]
    public void VariableUsedInLINQChain_ShouldNotBeMarkedUnused()
    {
        var source = @"func main(): void
    let numbers = [1, 2, 3, 4, 5]
    let doubled = numbers.Select(x => x * 2).ToList()
    Console.WriteLine(doubled)";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        // 'doubled' is used in Console.WriteLine, should not be marked unused
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'doubled'"));
        // 'numbers' is used in the LINQ chain, should not be marked unused
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'numbers'"));
    }

    [Fact]
    public void VariableUsedInMethodChain_ShouldNotBeMarkedUnused()
    {
        var source = @"func main(): void
    let text = ""hello""
    let result = text.ToUpper().Trim()
    print(result)";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'text'"));
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'result'"));
    }

    #endregion

    #region Assert Statement Tests

    [Fact]
    public void VariableUsedInAssertCondition_ShouldNotBeMarkedUnused()
    {
        var source = @"test ""assert reads locals"" {
    first := CreateIssue(""First"")
    second := CreateIssue(""Second"")

    assert first.Id == 1
    assert second.Id == 2
}";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'first'"));
        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'second'"));
    }

    [Fact]
    public void VariableUsedInAssertMessage_ShouldNotBeMarkedUnused()
    {
        var source = @"test ""assert reads message"" {
    expectedMessage := ""should be true""

    assert true, expectedMessage
}";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'expectedMessage'"));
    }

    [Fact]
    public void VariableUsedInAssertThrowsBody_ShouldNotBeMarkedUnused()
    {
        var source = @"test ""assert throws reads locals"" {
    value := ""bad""

    assert throws InvalidOperationException {
        ThrowIfInvalid(value)
    }
}";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        Assert.DoesNotContain(unusedDiags, d => d.Message.Contains("'value'"));
    }

    #endregion

    #region True Unused Variables (should still be detected)

    [Fact]
    public void TrulyUnusedVariable_ShouldBeDetected()
    {
        var source = "func main() { let unused = 42; print(\"hello\") }";

        var diagnostics = Lint(source);

        var unusedDiags = diagnostics.Where(d => d.Code == "NL001").ToList();

        Assert.Single(unusedDiags);
        Assert.Contains("'unused'", unusedDiags[0].Message);
    }

    #endregion
}
