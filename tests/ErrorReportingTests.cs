using Xunit;
using NewCLILang.Compiler;

namespace NewCLILang.Tests;

public class ErrorReportingTests
{
    [Fact]
    public void ErrorCode_Format_IncludesCode()
    {
        var error = CompilerError.Create(
            ErrorCode.TypeMismatch,
            "Cannot assign 'string' to 'int'",
            10,
            5,
            ErrorSeverity.Error
        );

        var formatted = error.Format();

        Assert.Contains("NL202", formatted); // TypeMismatch = 202
        Assert.Contains("error", formatted);
        Assert.Contains("Cannot assign 'string' to 'int'", formatted);
    }

    [Fact]
    public void ErrorCode_Format_IncludesLocation()
    {
        var error = CompilerError.Create(
            ErrorCode.UndefinedVariable,
            "Variable 'x' not found",
            15,
            10,
            ErrorSeverity.Error
        );

        var formatted = error.Format();

        Assert.Contains("line 15", formatted);
        Assert.Contains("column 10", formatted);
    }

    [Fact]
    public void ErrorCode_Format_IncludesSuggestion()
    {
        var error = CompilerError.Create(
            ErrorCode.NonExhaustiveMatch,
            "Match is not exhaustive",
            20,
            5,
            ErrorSeverity.Error
        ) with
        {
            Suggestion = "Add wildcard pattern '_'"
        };

        var formatted = error.Format();

        Assert.Contains("help:", formatted);
        Assert.Contains("Add wildcard pattern '_'", formatted);
    }

    [Fact]
    public void ErrorCode_Format_IncludesSourceSnippet()
    {
        var error = CompilerError.WithSnippet(
            ErrorCode.TypeMismatch,
            "Type mismatch",
            "test.nl",
            10,
            5,
            "    return \"string\"",
            6,
            "Change return type to string"
        );

        var formatted = error.Format();

        Assert.Contains("test.nl:10:5", formatted);
        Assert.Contains("return \"string\"", formatted);
        Assert.Contains("^^^", formatted); // Marker
        Assert.Contains("Change return type to string", formatted);
    }

    [Fact]
    public void ErrorSuggestions_TypeNotFound_ReturnsHelpfulMessage()
    {
        var suggestion = ErrorSuggestions.GetSuggestion(ErrorCode.TypeNotFound);

        Assert.NotNull(suggestion);
        Assert.Contains("type is defined", suggestion);
    }

    [Fact]
    public void ErrorSuggestions_MissingReturn_ReturnsHelpfulMessage()
    {
        var suggestion = ErrorSuggestions.GetSuggestion(ErrorCode.MissingReturn);

        Assert.NotNull(suggestion);
        Assert.Contains("return statement", suggestion);
    }

    [Fact]
    public void ErrorSuggestions_NonExhaustiveMatch_WithAdditionalInfo()
    {
        var suggestion = ErrorSuggestions.GetSuggestion(
            ErrorCode.NonExhaustiveMatch,
            null,
            "Success, Failure"
        );

        Assert.NotNull(suggestion);
        Assert.Contains("Success, Failure", suggestion);
    }

    [Fact]
    public void Warning_Format_ShowsWarning()
    {
        var warning = CompilerError.Create(
            ErrorCode.UnusedVariable,
            "Variable 'x' is unused",
            5,
            10,
            ErrorSeverity.Warning
        );

        var formatted = warning.Format();

        Assert.Contains("warning", formatted);
        Assert.Contains("NL901", formatted); // UnusedVariable = 901
    }

    [Fact]
    public void CompilerError_WithSuggestion_OverridesDefault()
    {
        var error = CompilerError.Create(
            ErrorCode.TypeMismatch,
            "Type mismatch",
            10,
            5,
            ErrorSeverity.Error
        ) with
        {
            Suggestion = "Custom suggestion"
        };

        var formatted = error.Format();

        Assert.Contains("Custom suggestion", formatted);
        Assert.DoesNotContain("Ensure types are compatible", formatted);
    }
}
