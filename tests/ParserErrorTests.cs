using Xunit;
using NSharpLang.Compiler;
using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Tests;

/// <summary>
/// Tests for Parser error reporting with INVALID sources
/// These tests verify that Parser correctly reports errors with proper codes and locations
/// </summary>
public class ParserErrorTests
{
    private static List<Token> Tokenize(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        return lexer.Tokenize();
    }

    private static ParseResult Parse(string source)
    {
        var tokens = Tokenize(source);
        var parser = new Parser(tokens, "test.nl", source);
        return parser.ParseCompilationUnit();
    }

    #region Single Line Errors

    [Fact]
    public void Parser_ReportsError_IncompleteMemberAccess_SingleLine()
    {
        var source = @"
func test() {
    x.
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.Single(result.Errors);

        var error = result.Errors[0];
        Assert.Equal(ErrorCode.ExpectedToken, error.Code);
        Assert.Equal(3, error.Line); // Line with "x."
        Assert.NotNull(error.HumanExplanation);
        Assert.Contains("dot", error.HumanExplanation, StringComparison.OrdinalIgnoreCase);
        Assert.NotNull(error.Suggestions);
        Assert.NotEmpty(error.Suggestions);
    }

    [Fact]
    public void Parser_ReportsError_MissingClosingParen_SingleLine()
    {
        var source = @"
func test() {
    Console.WriteLine(""hello""
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.Contains(result.Errors, e => e.Code == ErrorCode.ExpectedToken);

        var error = result.Errors.First(e => e.Code == ErrorCode.ExpectedToken);
        Assert.Equal(4, error.Line); // Line with missing )
        Assert.NotNull(error.HumanExplanation);
    }

    [Fact]
    public void Parser_ReportsError_InvalidTokenInExpression()
    {
        var source = @"
func test() {
    x = 5 @@ 3
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);
        // The error should be on line 3 where the invalid token is
        Assert.Contains(result.Errors, e => e.Line == 3);
    }

    #endregion

    #region Multi-Line Errors

    [Fact]
    public void Parser_ReportsMultipleErrors_DifferentLines()
    {
        var source = @"
func test1() {
    x.
}

func test2() {
    y.
}

func test3() {
    z.
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.True(result.Errors.Count >= 3, $"Expected at least 3 errors, got {result.Errors.Count}");

        // Verify each error is on the correct line
        Assert.Contains(result.Errors, e => e.Line == 3 && e.Code == ErrorCode.ExpectedToken);
        Assert.Contains(result.Errors, e => e.Line == 7 && e.Code == ErrorCode.ExpectedToken);
        Assert.Contains(result.Errors, e => e.Line == 11 && e.Code == ErrorCode.ExpectedToken);
    }

    [Fact]
    public void Parser_ReportsMultipleErrors_SameFunction()
    {
        var source = @"
func test() {
    x.
    y.
    z.
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.True(result.Errors.Count >= 3, $"Expected at least 3 errors, got {result.Errors.Count}");

        // Each error should be on its own line
        Assert.Contains(result.Errors, e => e.Line == 3);
        Assert.Contains(result.Errors, e => e.Line == 4);
        Assert.Contains(result.Errors, e => e.Line == 5);

        // All should have proper error codes
        Assert.All(result.Errors, e => Assert.Equal(ErrorCode.ExpectedToken, e.Code));
    }

    #endregion

    #region Error Code Verification

    [Fact]
    public void Parser_ReturnsCorrectErrorCode_ExpectedToken()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.Equal(ErrorCode.ExpectedToken, error.Code);
    }

    [Fact]
    public void Parser_ReturnsCorrectErrorCode_UnexpectedToken()
    {
        var source = "class Test { ] }"; // Random closing bracket
        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);
        // Should report some kind of error  - just verify we have an error code
        Assert.All(result.Errors, e => Assert.True(e.Code != default(ErrorCode)));
    }

    #endregion

    #region Error Message Quality

    [Fact]
    public void Parser_ProvidesHumanExplanation()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.NotNull(error.HumanExplanation);
        Assert.NotEmpty(error.HumanExplanation);
        // Should be conversational, not technical
        Assert.DoesNotContain("null", error.HumanExplanation, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parser_ProvidesSuggestions_ForIncompleteMemberAccess()
    {
        var source = "func test() { employees. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.NotNull(error.Suggestions);
        Assert.NotEmpty(error.Suggestions);
        // Suggestions should be actionable
        Assert.All(error.Suggestions, s => Assert.NotEmpty(s));
    }

    [Fact]
    public void Parser_ProvidesSourceSnippet()
    {
        var source = @"func test() {
    x.
}";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.NotNull(error.SourceSnippet);
        Assert.Contains("x.", error.SourceSnippet);
    }

    [Fact]
    public void Parser_ProvidesDocsUrl()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);
        Assert.NotNull(error.DocsUrl);
        Assert.Contains("https://docs.nsharp.dev/errors/", error.DocsUrl);
        Assert.Contains($"NL{(int)error.Code:D3}", error.DocsUrl);
    }

    #endregion

    #region Complex Multi-Error Scenarios

    [Fact]
    public void Parser_HandlesComplexMultiError_AcrossFile()
    {
        var source = @"
// Line 2
func test1() {
    // Line 4
    x.   // Error on line 5
}

// Line 8
class Test {
    // Line 10
    prop := 5 @@ 3  // Error on line 11 (invalid operator)
}

// Line 14
func test2() {
    // Line 16
    Console.WriteLine(""test""  // Error on line 17 (missing paren)
}

// Line 20
func test3() {
    // Line 22
    y.   // Error on line 23
}";

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.True(result.Errors.Count >= 3, $"Expected at least 3 errors, got {result.Errors.Count}");

        // Verify errors are distributed across the file
        var errorLines = result.Errors.Select(e => e.Line).Distinct().ToList();
        Assert.True(errorLines.Count >= 3, "Errors should be on different lines");

        // All errors should have proper metadata
        Assert.All(result.Errors, error =>
        {
            Assert.True(error.Line > 0, "Error line should be positive");
            Assert.True(error.Column > 0, "Error column should be positive");
            Assert.NotNull(error.Message);
            Assert.NotEmpty(error.Message);
        });
    }

    #endregion

    #region Formatting Tests

    [Fact]
    public void Parser_ErrorFormat_IsReadable()
    {
        var source = "func test() { x. }";
        var result = Parse(source);

        Assert.False(result.Success);
        var error = result.Errors.FirstOrDefault();
        Assert.NotNull(error);

        var formatted = error.Format(useColors: false);
        Assert.NotEmpty(formatted);

        // Should contain key components
        Assert.Contains($"NL{(int)error.Code:D3}", formatted); // Error code
        Assert.Contains("test.nl", formatted); // File name
        Assert.Contains($"{error.Line}", formatted); // Line number
    }

    #endregion

    #region Edge Cases

    [Fact]
    public void Parser_HandlesError_AtStartOfFile()
    {
        var source = "@@ invalid";
        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);

        var error = result.Errors[0];
        Assert.True(error.Line >= 1, "Error line should be at least 1");
    }

    [Fact]
    public void Parser_HandlesError_AtEndOfFile()
    {
        var source = @"
func test() {
    x = 5
";  // Missing closing brace

        var result = Parse(source);

        Assert.False(result.Success);
        Assert.NotEmpty(result.Errors);
    }

    [Fact]
    public void Parser_HandlesEmptyInput()
    {
        var source = "";
        var result = Parse(source);

        // Empty input should parse successfully (empty compilation unit)
        // OR report an appropriate error if required
        Assert.NotNull(result);
    }

    #endregion
}
