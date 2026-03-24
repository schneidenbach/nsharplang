using Xunit;
using NSharpLang.Compiler;
using System.Collections.Generic;

namespace NSharpLang.Tests;

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

        var formatted = error.Format(useColors: false);

        Assert.Contains("NL202", formatted); // TypeMismatch = 202
        Assert.Contains("error", formatted);
        Assert.Contains("Cannot assign 'string' to 'int'", formatted);
    }

    [Fact]
    public void DiagnosticId_UsesNlPrefix()
    {
        var error = CompilerError.Create(
            ErrorCode.TypeMismatch,
            "Type mismatch",
            1,
            1,
            ErrorSeverity.Error
        );

        Assert.Equal("NL202", error.DiagnosticId);
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

        var formatted = error.Format(useColors: false);

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

        var formatted = error.Format(useColors: false);

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

        var formatted = error.Format(useColors: false);

        Assert.Contains("test.nl:10:5", formatted);
        Assert.Contains("return \"string\"", formatted);
        Assert.Contains("^^^", formatted); // Marker
        Assert.Contains("Change return type to string", formatted);
    }

    [Fact]
    public void FormatForTooling_PreservesRichContextWithoutLocation()
    {
        var error = ErrorMessageBuilder.TypeMismatch(
            "test.nl",
            10,
            5,
            "x: int = \"hello\"",
            7,
            "string",
            "int"
        );

        var formatted = error.FormatForTooling(includeCode: true, includeLocation: false);

        Assert.Contains("NL202: Type mismatch", formatted);
        Assert.Contains("I am having trouble", formatted);
        Assert.Contains("x: int = \"hello\"", formatted);
        Assert.Contains("^^^^^^^", formatted);
        Assert.Contains("actual: string", formatted);
        Assert.Contains("expected: int", formatted);
        Assert.DoesNotContain("at test.nl:10:5", formatted);
    }

    [Fact]
    public void FormatForMsBuild_CollapsesRichContextOntoOneLine()
    {
        var error = ErrorMessageBuilder.TypeMismatch(
            "test.nl",
            10,
            5,
            "x: int = \"hello\"",
            7,
            "string",
            "int"
        );

        var formatted = error.FormatForMsBuild();

        Assert.Contains("Type mismatch", formatted);
        Assert.Contains("actual: string", formatted);
        Assert.Contains("expected: int", formatted);
        Assert.Contains("I am having trouble", formatted);
        Assert.DoesNotContain("\n", formatted);
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

        var formatted = warning.Format(useColors: false);

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

        var formatted = error.Format(useColors: false);

        Assert.Contains("Custom suggestion", formatted);
        Assert.DoesNotContain("Ensure types are compatible", formatted);
    }

    // Elm-style error message tests
    [Fact]
    public void ElmStyle_TypeMismatch_ShowsHumanExplanation()
    {
        var error = ErrorMessageBuilder.TypeMismatch(
            "test.nl",
            10,
            5,
            "x: int = \"hello\"",
            7,
            "string",
            "int"
        );

        var formatted = error.Format(useColors: false);

        Assert.Contains("TYPE MISMATCH", formatted);
        Assert.Contains("I am having trouble", formatted);
        Assert.Contains("This expression has type:", formatted);
        Assert.Contains("string", formatted);
        Assert.Contains("But you said it should be:", formatted);
        Assert.Contains("int", formatted);
        Assert.Contains("int.Parse", formatted);
    }

    [Fact]
    public void ElmStyle_UndefinedVariable_SuggestsSimilarNames()
    {
        var similarNames = new List<string> { "person", "personName" };
        var error = ErrorMessageBuilder.UndefinedVariable(
            "test.nl",
            15,
            10,
            "print(persn.Name)",
            5,
            "persn",
            similarNames
        );

        var formatted = error.Format(useColors: false);

        Assert.Contains("NAMING ERROR", formatted);
        Assert.Contains("I cannot find", formatted);
        Assert.Contains("persn", formatted);
        Assert.Contains("Did you mean one of these?", formatted);
        Assert.Contains("person", formatted);
        Assert.Contains("personName", formatted);
    }

    [Fact]
    public void ElmStyle_NonExhaustiveMatch_ListsMissingCases()
    {
        var missingCases = new List<string> { "Pending", "Cancelled" };
        var error = ErrorMessageBuilder.NonExhaustiveMatch(
            "test.nl",
            20,
            12,
            "match result {",
            5,
            missingCases
        );

        var formatted = error.Format(useColors: false);

        Assert.Contains("INCOMPLETE PATTERN MATCH", formatted);
        Assert.Contains("does not cover all possibilities", formatted);
        Assert.Contains("Pending", formatted);
        Assert.Contains("Cancelled", formatted);
        Assert.Contains("must be exhaustive", formatted);
        Assert.Contains("wildcard '_'", formatted);
        Assert.Contains("prevent runtime errors", formatted);
    }

    [Fact]
    public void ElmStyle_UndefinedType_SuggestsSimilarTypes()
    {
        var similarTypes = new List<string> { "Person", "Persons" };
        var error = ErrorMessageBuilder.UndefinedType(
            "test.nl",
            8,
            15,
            "p: Persn",
            5,
            "Persn",
            similarTypes
        );

        var formatted = error.Format(useColors: false);

        Assert.Contains("NAMING ERROR", formatted);
        Assert.Contains("I cannot find a type called `Persn`", formatted);
        Assert.Contains("Did you mean one of these?", formatted);
        Assert.Contains("Person", formatted);
        Assert.Contains("Persons", formatted);
    }

    [Fact]
    public void ElmStyle_ErrorsIncludeDocsUrl()
    {
        var error = ErrorMessageBuilder.TypeMismatch(
            "test.nl",
            10,
            5,
            "x: int = \"hello\"",
            7,
            "string",
            "int"
        );

        var formatted = error.Format(useColors: false);

        Assert.Contains("https://docs.n-sharp.dev/errors/NL202", formatted);
    }

    // SmartSuggester tests
    [Fact]
    public void SmartSuggester_FindsTypos()
    {
        var candidates = new List<string> { "Console", "System", "List", "string" };
        var suggester = new SmartSuggester(candidates);

        var suggestions = suggester.SuggestSimilarNames("Consol");

        Assert.Contains("Console", suggestions);
    }

    [Fact]
    public void SmartSuggester_RanksByLevenshteinDistance()
    {
        var candidates = new List<string> { "userName", "userEmail", "userId", "name" };
        var suggester = new SmartSuggester(candidates);

        var suggestions = suggester.SuggestSimilarNames("usreName");

        Assert.NotEmpty(suggestions);
        Assert.Contains("userName", suggestions);
    }

    [Fact]
    public void SmartSuggester_ConsidersPrefixMatch()
    {
        var candidates = new List<string> { "getUserName", "getUsername", "setUserName" };
        var suggester = new SmartSuggester(candidates);

        var suggestions = suggester.SuggestSimilarNames("getUserNam");

        Assert.NotEmpty(suggestions);
        Assert.Contains("getUserName", suggestions);
    }

    [Fact]
    public void SmartSuggester_ReturnsEmptyForPoorMatches()
    {
        var candidates = new List<string> { "apple", "banana", "cherry" };
        var suggester = new SmartSuggester(candidates);

        var suggestions = suggester.SuggestSimilarNames("xyz123");

        Assert.Empty(suggestions);
    }

    [Fact]
    public void SmartSuggester_LimitsToMaxSuggestions()
    {
        var candidates = new List<string> { "test1", "test2", "test3", "test4", "test5" };
        var suggester = new SmartSuggester(candidates);

        var suggestions = suggester.SuggestSimilarNames("test", maxSuggestions: 2);

        Assert.True(suggestions.Count <= 2);
    }

    // TypeConversionSuggester tests
    [Fact]
    public void TypeConversionSuggester_StringToInt()
    {
        var hint = TypeConversionSuggester.SuggestConversion("string", "int");

        Assert.NotNull(hint);
        Assert.Contains("int.Parse", hint);
        Assert.Contains("int.TryParse", hint);
    }

    [Fact]
    public void TypeConversionSuggester_IntToString()
    {
        var hint = TypeConversionSuggester.SuggestConversion("int", "string");

        Assert.NotNull(hint);
        Assert.Contains(".ToString()", hint);
        Assert.Contains("$\"{", hint);
    }

    [Fact]
    public void TypeConversionSuggester_NullableToNonNullable()
    {
        var hint = TypeConversionSuggester.SuggestConversion("int?", "int");

        Assert.NotNull(hint);
        Assert.Contains("nullable", hint);
        Assert.Contains("??", hint);
    }

    [Fact]
    public void TypeConversionSuggester_NonNullableToNullable()
    {
        var hint = TypeConversionSuggester.SuggestConversion("int", "int?");

        Assert.NotNull(hint);
        Assert.Contains("implicit", hint);
    }

    [Fact]
    public void TypeConversionSuggester_ArrayToList()
    {
        var hint = TypeConversionSuggester.SuggestConversion("int[]", "List<int>");

        Assert.NotNull(hint);
        Assert.Contains(".ToList()", hint);
    }

    [Fact]
    public void TypeConversionSuggester_ListToArray()
    {
        var hint = TypeConversionSuggester.SuggestConversion("List<int>", "int[]");

        Assert.NotNull(hint);
        Assert.Contains(".ToArray()", hint);
    }

    [Fact]
    public void TypeConversionSuggester_DoubleToInt_WarnsAboutTruncation()
    {
        var hint = TypeConversionSuggester.SuggestConversion("double", "int");

        Assert.NotNull(hint);
        Assert.Contains("(int)", hint);
        Assert.Contains("truncates", hint);
    }

    // Backward compatibility tests
    [Fact]
    public void RustStyle_StillWorksWithoutElmContext()
    {
        var error = CompilerError.Create(
            ErrorCode.TypeMismatch,
            "Cannot assign 'string' to 'int'",
            10,
            5,
            ErrorSeverity.Error
        ) with
        {
            SourceSnippet = "x: int = \"hello\"",
            Length = 7
        };

        var formatted = error.Format(useColors: false);

        // Should use Rust-style formatting (not Elm-style)
        Assert.Contains("error NL202", formatted);
        Assert.Contains("Cannot assign 'string' to 'int'", formatted);
        Assert.DoesNotContain("TYPE MISMATCH", formatted);
    }

    [Fact]
    public void LevenshteinDistance_CalculatesCorrectly()
    {
        Assert.Equal(0, ErrorSuggestions.LevenshteinDistance("test", "test"));
        Assert.Equal(1, ErrorSuggestions.LevenshteinDistance("test", "tests"));
        Assert.Equal(1, ErrorSuggestions.LevenshteinDistance("test", "Test"));
        Assert.Equal(3, ErrorSuggestions.LevenshteinDistance("kitten", "sitting"));
    }
}
