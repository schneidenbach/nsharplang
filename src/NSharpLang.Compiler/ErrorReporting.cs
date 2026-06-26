using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace NSharpLang.Compiler;

/// <summary>
/// Enhanced compiler error with rich context and suggestions
/// </summary>
public record CompilerError
{
    public ErrorCode Code { get; init; }
    public string Message { get; init; }
    public string? FileName { get; init; }
    public int Line { get; init; }
    public int Column { get; init; }
    public int Length { get; init; } = 1;
    public string? Suggestion { get; init; }
    public string? SourceSnippet { get; init; }
    public ErrorSeverity Severity { get; init; }

    // Rich context for Elm-level error messages
    public string? ActualType { get; init; }
    public string? ExpectedType { get; init; }
    public string? HumanExplanation { get; init; }
    public string? ContextualHint { get; init; }
    public string? DocsUrl { get; init; }
    public List<string>? Suggestions { get; init; }
    public Dictionary<string, string>? RelatedInfo { get; init; }
    public string? DiagnosticIdOverride { get; init; }

    public string DiagnosticId => DiagnosticIdOverride ?? $"NL{(int)Code:D3}";

    public CompilerError(ErrorCode code, string message, int line, int column, ErrorSeverity severity)
    {
        Code = code;
        Message = message;
        Line = line;
        Column = column;
        Severity = severity;
    }

    /// <summary>
    /// Format diagnostics for external tooling such as MSBuild and LSP.
    /// Keeps the richer compiler context without ANSI color sequences.
    /// </summary>
    public string FormatForTooling(bool includeCode = true, bool includeLocation = false)
    {
        var builder = new StringBuilder();
        builder.Append(includeCode ? $"{DiagnosticId}: {Message}" : Message);

        if (includeLocation)
        {
            var location = FileName != null
                ? $"{FileName}:{Line}:{Column}"
                : $"line {Line}, column {Column}";
            builder.AppendLine();
            builder.Append($"at {location}");
        }

        if (!string.IsNullOrWhiteSpace(HumanExplanation))
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.Append(HumanExplanation.Trim());
        }

        if (!string.IsNullOrWhiteSpace(SourceSnippet))
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.AppendLine(SourceSnippet);
            var markerIndent = Column > 0 ? new string(' ', Column - 1) : string.Empty;
            builder.Append($"{markerIndent}{new string('^', Math.Max(1, Length))}");
        }

        if (!string.IsNullOrWhiteSpace(ActualType) || !string.IsNullOrWhiteSpace(ExpectedType))
        {
            builder.AppendLine();
            builder.AppendLine();
            if (!string.IsNullOrWhiteSpace(ActualType))
            {
                builder.AppendLine($"actual: {ActualType}");
            }
            if (!string.IsNullOrWhiteSpace(ExpectedType))
            {
                builder.Append($"expected: {ExpectedType}");
            }
        }

        if (!string.IsNullOrWhiteSpace(ContextualHint))
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.Append(ContextualHint.Trim());
        }

        if (Suggestions is { Count: > 0 })
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.AppendLine("did you mean:");
            foreach (var suggestion in Suggestions)
            {
                builder.AppendLine($"- {suggestion}");
            }
        }
        else if (!string.IsNullOrWhiteSpace(Suggestion))
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.Append($"help: {Suggestion.Trim()}");
        }

        if (!string.IsNullOrWhiteSpace(DocsUrl))
        {
            builder.AppendLine();
            builder.AppendLine();
            builder.Append($"docs: {DocsUrl}");
        }

        return builder.ToString().TrimEnd();
    }

    /// <summary>
    /// Format diagnostics for MSBuild, which renders each newline as a separate error record.
    /// Keep the extra context, but collapse it into a single logical line.
    /// </summary>
    public string FormatForMsBuild()
    {
        var parts = new List<string> { Message };

        if (!string.IsNullOrWhiteSpace(HumanExplanation))
        {
            parts.Add(NormalizeInlineText(HumanExplanation));
        }

        if (!string.IsNullOrWhiteSpace(ActualType))
        {
            parts.Add($"actual: {ActualType}");
        }

        if (!string.IsNullOrWhiteSpace(ExpectedType))
        {
            parts.Add($"expected: {ExpectedType}");
        }

        if (!string.IsNullOrWhiteSpace(ContextualHint))
        {
            parts.Add(NormalizeInlineText(ContextualHint));
        }

        if (Suggestions is { Count: > 0 })
        {
            parts.Add($"did you mean: {string.Join(", ", Suggestions)}");
        }
        else if (!string.IsNullOrWhiteSpace(Suggestion))
        {
            parts.Add($"help: {NormalizeInlineText(Suggestion)}");
        }

        if (!string.IsNullOrWhiteSpace(DocsUrl))
        {
            parts.Add($"docs: {DocsUrl}");
        }

        return string.Join(" | ", parts);
    }

    private static string NormalizeInlineText(string value)
    {
        return string.Join(" ", value
            .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Trim())
            .Where(part => part.Length > 0));
    }

    /// <summary>
    /// Format error in Elm-style with human-friendly explanations
    /// </summary>
    public string Format(bool useColors = true)
    {
        // Use Elm-style formatting if we have rich context
        if (HumanExplanation != null)
        {
            return FormatElmStyle(useColors);
        }

        // Fall back to Rust-style formatting
        return FormatRustStyle(useColors);
    }

    /// <summary>
    /// Format error in Elm-style with conversational tone
    /// </summary>
    private string FormatElmStyle(bool useColors)
    {
        var builder = new StringBuilder();
        var severityText = Severity == ErrorSeverity.Warning ? "WARNING" : (Code switch
        {
            ErrorCode.TypeMismatch or ErrorCode.TypeNotFound => "TYPE MISMATCH",
            ErrorCode.UndefinedVariable or ErrorCode.UndefinedType or ErrorCode.UndefinedMember => "NAMING ERROR",
            ErrorCode.NonExhaustiveMatch => "INCOMPLETE PATTERN MATCH",
            ErrorCode.WrongArgumentCount or ErrorCode.NoMatchingOverload or ErrorCode.UndefinedFunction => "FUNCTION CALL ERROR",
            ErrorCode.CircularImport => "CIRCULAR IMPORT",
            _ => "ERROR"
        });

        // ANSI color codes
        const string Cyan = "\x1b[1;36m";
        const string Reset = "\x1b[0m";
        const string Dim = "\x1b[2m";

        // Header line
        var headerLine = new string('-', 50);
        var fileName = FileName ?? "code";
        if (useColors)
        {
            builder.AppendLine($"{Dim}-- {severityText} {headerLine}{Reset}  {fileName}");
        }
        else
        {
            builder.AppendLine($"-- {severityText} {headerLine}  {fileName}");
        }

        builder.AppendLine();

        // Human explanation
        builder.AppendLine(HumanExplanation);
        builder.AppendLine();

        // Source snippet
        if (SourceSnippet != null)
        {
            if (useColors)
            {
                builder.AppendLine($"{Cyan}{Line}|{Reset}     {SourceSnippet}");
            }
            else
            {
                builder.AppendLine($"{Line}|     {SourceSnippet}");
            }

            var markerIndent = Column > 0 ? new string(' ', Column - 1 + 6) : "      ";
            var markerLength = Math.Max(1, Length);
            var marker = new string('^', markerLength);

            if (useColors)
            {
                builder.AppendLine($"{Cyan}{markerIndent}{marker}{Reset}");
            }
            else
            {
                builder.AppendLine($"{markerIndent}{marker}");
            }
            builder.AppendLine();
        }

        // Type information (for type errors)
        if (ActualType != null && ExpectedType != null)
        {
            builder.AppendLine("This expression has type:");
            builder.AppendLine();
            builder.AppendLine($"    {ActualType}");
            builder.AppendLine();
            builder.AppendLine("But you said it should be:");
            builder.AppendLine();
            builder.AppendLine($"    {ExpectedType}");
            builder.AppendLine();
        }

        // Contextual hint
        if (ContextualHint != null)
        {
            builder.AppendLine($"Hint: {ContextualHint}");
            builder.AppendLine();
        }

        // Multiple suggestions
        if (Suggestions != null && Suggestions.Count > 0)
        {
            builder.AppendLine("Did you mean one of these?");
            builder.AppendLine();
            foreach (var suggestion in Suggestions)
            {
                builder.AppendLine($"    {suggestion}");
            }
            builder.AppendLine();
        }

        // Documentation link
        if (DocsUrl != null)
        {
            if (useColors)
            {
                builder.AppendLine($"{Cyan}Read more:{Reset} {DocsUrl}");
            }
            else
            {
                builder.AppendLine($"Read more: {DocsUrl}");
            }
        }

        return builder.ToString();
    }

    /// <summary>
    /// Format error in Rust-style with source snippet and suggestions
    /// </summary>
    private string FormatRustStyle(bool useColors)
    {
        var builder = new StringBuilder();
        var severityText = Severity == ErrorSeverity.Warning ? "warning" : "error";

        // ANSI color codes
        const string Red = "\x1b[1;31m";      // Bold red for errors
        const string Yellow = "\x1b[1;33m";   // Bold yellow for warnings
        const string Cyan = "\x1b[1;36m";     // Cyan for line numbers
        const string Green = "\x1b[1;32m";    // Green for help text
        const string Bold = "\x1b[1m";        // Bold for emphasis
        const string Reset = "\x1b[0m";       // Reset color

        var severityColor = Severity == ErrorSeverity.Warning ? Yellow : Red;

        // First line: error/warning with code and message
        if (useColors)
        {
            builder.AppendLine($"{severityColor}{severityText}{Reset} {Bold}{DiagnosticId}{Reset}: {Message}");
        }
        else
        {
            builder.AppendLine($"{severityText} {DiagnosticId}: {Message}");
        }

        // Location
        if (FileName != null)
        {
            if (useColors)
            {
                builder.AppendLine($"  {Cyan}-->{Reset} {FileName}:{Line}:{Column}");
            }
            else
            {
                builder.AppendLine($"  --> {FileName}:{Line}:{Column}");
            }
        }
        else
        {
            if (useColors)
            {
                builder.AppendLine($"  {Cyan}-->{Reset} line {Line}, column {Column}");
            }
            else
            {
                builder.AppendLine($"  --> line {Line}, column {Column}");
            }
        }

        // Source snippet with marker
        if (SourceSnippet != null)
        {
            if (useColors)
            {
                builder.AppendLine($"   {Cyan}|{Reset}");
                builder.AppendLine($"{Cyan}{Line,3} |{Reset} {SourceSnippet}");
            }
            else
            {
                builder.AppendLine("   |");
                builder.AppendLine($"{Line,3} | {SourceSnippet}");
            }

            // Calculate marker position (accounting for line number width)
            var markerIndent = Column > 0 ? new string(' ', Column - 1) : "";
            var markerLength = Math.Max(1, Length);
            var marker = new string('^', markerLength);

            if (useColors)
            {
                builder.AppendLine($"   {Cyan}|{Reset} {markerIndent}{severityColor}{marker}{Reset}");
            }
            else
            {
                builder.AppendLine($"   | {markerIndent}{marker}");
            }
        }

        // Suggestion (help text)
        if (Suggestion != null)
        {
            if (useColors)
            {
                builder.AppendLine($"   {Cyan}|{Reset}");
                builder.AppendLine($"{Green}help{Reset}: {Suggestion}");
            }
            else
            {
                builder.AppendLine("   |");
                builder.AppendLine($"help: {Suggestion}");
            }
        }

        return builder.ToString();
    }

    /// <summary>
    /// Create a simple error without source context
    /// </summary>
    public static CompilerError Create(ErrorCode code, string message, int line, int column, ErrorSeverity severity = ErrorSeverity.Error)
    {
        return new CompilerError(code, message, line, column, severity);
    }

    /// <summary>
    /// Create an error with source snippet
    /// </summary>
    public static CompilerError WithSnippet(ErrorCode code, string message, string fileName, int line, int column,
        string sourceSnippet, int length = 0, string? suggestion = null, ErrorSeverity severity = ErrorSeverity.Error)
    {
        var span = DiagnosticSpanResolver.Resolve(sourceSnippet, column, length);

        return new CompilerError(code, message, line, span.Column, severity)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = span.Length,
            Suggestion = suggestion
        };
    }
}

public record AnalysisResult(List<CompilerError> Errors, SemanticModel SemanticModel, BindingMap? Bindings = null)
{
    public bool HasErrors => Errors.Any(e => e.Severity == ErrorSeverity.Error);
}

/// <summary>
/// Result of parsing with AST and any errors encountered
/// </summary>
public record ParseResult
{
    public Ast.CompilationUnit? CompilationUnit { get; init; }
    public List<CompilerError> Errors { get; init; } = new();
    public bool Success => CompilationUnit != null && !Errors.Any(e => e.Severity == ErrorSeverity.Error);
}

/// <summary>
/// Builds human-friendly error messages with multi-level explanations
/// </summary>
public static class ErrorMessageBuilder
{
    /// <summary>
    /// Returns the singular or plural form of a noun based on a count.
    /// </summary>
    private static string Pluralize(int count, string singular, string plural)
        => count == 1 ? singular : plural;

    /// <summary>
    /// Create an Elm-style type mismatch error
    /// </summary>
    public static CompilerError TypeMismatch(string fileName, int line, int column, string sourceSnippet,
        int length, string actualType, string expectedType)
    {
        var humanExplanation = $"I am having trouble with this code on line {line}:";
        var contextualHint = TypeConversionSuggester.SuggestConversion(actualType, expectedType);

        return new CompilerError(ErrorCode.TypeMismatch, "Type mismatch", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            ActualType = actualType,
            ExpectedType = expectedType,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint ?? "These types are not compatible. Check if you need to convert or cast.",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL202"
        };
    }

    /// <summary>
    /// Create an Elm-style error for a value returned from a function without a return type annotation.
    /// </summary>
    public static CompilerError ReturnValueRequiresReturnType(string fileName, int line, int column, string sourceSnippet,
        int length, string functionName, string actualType)
    {
        var humanExplanation =
            $"Function `{functionName}` has no return type annotation, so N# treats it as `void`:";
        var addReturnTypeHint = actualType is "null" or "unknown"
            ? $"Add an explicit return type after the parameter list if `{functionName}` should return a value"
            : $"Add `: {actualType}` after the parameter list if `{functionName}` should return this value";
        var suggestion = actualType is "null" or "unknown"
            ? $"Add an explicit return type to `{functionName}` or remove the returned value"
            : $"Add `: {actualType}` to `{functionName}` or remove the returned value";

        var contextualHint =
            $"This code gives back a value of type `{actualType}` from a function that currently returns nothing.\n" +
            addReturnTypeHint + ", " +
            "or remove the value if the function should stay void.";

        return new CompilerError(ErrorCode.TypeMismatch, $"Function '{functionName}' returns {actualType} but has no return type", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            ActualType = actualType,
            ExpectedType = "void",
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestion = suggestion,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL202"
        };
    }

    /// <summary>
    /// Create an Elm-style error for a value returned from an explicitly void function.
    /// </summary>
    public static CompilerError ReturnValueInVoidFunction(string fileName, int line, int column, string sourceSnippet,
        int length, string functionName, string actualType)
    {
        var humanExplanation =
            $"Function `{functionName}` is declared to return `void`, but this code gives back a value:";

        var contextualHint =
            $"A `void` function cannot return a value of type `{actualType}`. Change the return type if the value matters, " +
            "or remove the value if the function only performs side effects.";

        return new CompilerError(ErrorCode.TypeMismatch, $"Function '{functionName}' returns a value but is declared void", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            ActualType = actualType,
            ExpectedType = "void",
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestion = $"Change `{functionName}`'s return type or remove the returned value",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL202"
        };
    }

    /// <summary>
    /// Create an Elm-style error for a return value that does not match the declared return type.
    /// </summary>
    public static CompilerError ReturnTypeMismatch(string fileName, int line, int column, string sourceSnippet,
        int length, string functionName, string actualType, string expectedType)
    {
        var contextualHint = TypeConversionSuggester.SuggestConversion(actualType, expectedType)
            ?? $"`{functionName}` is declared to return `{expectedType}`, so every returned value must be assignable to `{expectedType}`.";

        return new CompilerError(ErrorCode.TypeMismatch, $"Function '{functionName}' should return {expectedType} but returns {actualType}", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            ActualType = actualType,
            ExpectedType = expectedType,
            HumanExplanation = $"This return value does not match `{functionName}`'s return type:",
            ContextualHint = contextualHint,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL202"
        };
    }

    /// <summary>
    /// Create an Elm-style undefined variable error
    /// </summary>
    public static CompilerError UndefinedVariable(string fileName, int line, int column, string sourceSnippet,
        int length, string varName, List<string> similarNames)
    {
        var humanExplanation = $"I cannot find a `{varName}` variable on line {line}:";

        var contextualHint = similarNames.Any()
            ? "Variables need to be declared before they can be used. If you meant to\n" +
              "use a variable from outside this function, make sure it's in scope."
            : "Make sure you've declared this variable before using it.";

        return new CompilerError(ErrorCode.UndefinedVariable, $"Variable '{varName}' not found", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestions = similarNames.Any() ? similarNames : null,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL301"
        };
    }

    /// <summary>
    /// Create an Elm-style undefined function error
    /// </summary>
    public static CompilerError UndefinedFunction(string fileName, int line, int column, string sourceSnippet,
        int length, string functionName, List<string> similarNames)
    {
        var humanExplanation = $"I cannot find a function named `{functionName}` on line {line}:";

        var contextualHint = similarNames.Any()
            ? "Function calls need a function, method, or callable value with this name in scope.\n" +
              "If this is from another file or namespace, import it before calling it."
            : $"Define `func {functionName}(...)` before calling it, or import the function if it lives elsewhere.";

        return new CompilerError(ErrorCode.UndefinedFunction, $"Function '{functionName}' not found", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestions = similarNames.Any() ? similarNames : null,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL412"
        };
    }

    /// <summary>
    /// Create an Elm-style non-exhaustive match error
    /// </summary>
    public static CompilerError NonExhaustiveMatch(string fileName, int line, int column, string sourceSnippet,
        int length, List<string> missingCases)
    {
        var humanExplanation = $"This `match` expression does not cover all possibilities on line {line}:";

        var contextualHint =
            $"You need to handle these cases:\n\n" +
            string.Join("\n", missingCases.Select(c => $"    {c}")) + "\n\n" +
            "Pattern matching in N# must be exhaustive, meaning every possible value\n" +
            "must be handled. You can either add the missing cases, or use a wildcard '_'\n" +
            "pattern to catch everything else:\n\n" +
            "    _ => handleOtherCases()\n\n" +
            "Why? This helps prevent runtime errors. The compiler checks that you've thought\n" +
            "about all possibilities!";

        return new CompilerError(ErrorCode.NonExhaustiveMatch, "Pattern matching is not exhaustive", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            RelatedInfo = new Dictionary<string, string> { ["missingCases"] = string.Join(", ", missingCases) },
            DocsUrl = "https://docs.n-sharp.dev/errors/NL501"
        };
    }

    /// <summary>
    /// Create an Elm-style undefined type error
    /// </summary>
    public static CompilerError UndefinedType(string fileName, int line, int column, string sourceSnippet,
        int length, string typeName, List<string> similarTypes)
    {
        var humanExplanation = $"I cannot find a type called `{typeName}` on line {line}:";

        var contextualHint = similarTypes.Any()
            ? "Check that the type is imported. If it's from another namespace,\n" +
              "you may need to add an import statement at the top of your file."
            : "Make sure the type is defined and imported correctly.";

        return new CompilerError(ErrorCode.UndefinedType, $"Type '{typeName}' not found", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestions = similarTypes.Any() ? similarTypes : null,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL302"
        };
    }

    /// <summary>
    /// Create an Elm-style wrong argument count error
    /// </summary>
    public static CompilerError WrongArgumentCount(string fileName, int line, int column, string sourceSnippet,
        int length, string functionName, int expected, int actual)
    {
        var humanExplanation = $"I am having trouble with this function call on line {line}:";

        var expectedArguments = $"{expected} {Pluralize(expected, "argument", "arguments")}";
        var contextualHint = expected > actual
            ? $"The function `{functionName}` expects {expectedArguments}, but you are\n" +
              $"passing {actual}. You may have forgotten to pass some arguments."
            : $"The function `{functionName}` expects {expectedArguments}, but you are\n" +
              $"passing {actual}. You may have passed too many arguments.";

        return new CompilerError(ErrorCode.WrongArgumentCount, $"Function '{functionName}' expects {expectedArguments} but got {actual}", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL401"
        };
    }

    /// <summary>
    /// Create an Elm-style no matching overload error
    /// </summary>
    public static CompilerError NoMatchingOverload(string fileName, int line, int column, string sourceSnippet,
        int length, string functionName, int actualArgumentCount, IReadOnlyList<string> argumentTypes, IReadOnlyList<string> candidateSignatures)
    {
        var argumentText = argumentTypes.Count == 0
            ? "no arguments"
            : string.Join(", ", argumentTypes.Select(type => $"`{type}`"));
        var signatureText = candidateSignatures.Count == 0
            ? "No callable overloads were found."
            : "Available overloads:\n" + string.Join("\n", candidateSignatures.Select(signature => $"  - {signature}"));

        var argumentCountText = $"{actualArgumentCount} {Pluralize(actualArgumentCount, "argument", "arguments")}";
        var humanExplanation = $"I cannot find an overload of `{functionName}` that matches this call:";
        var contextualHint =
            $"This call passes {argumentCountText}: {argumentText}.\n" +
            $"{signatureText}\n\n" +
            "Check the argument count and types. If you meant to reference the method itself, use it in a context with a delegate type instead of calling it.";

        return new CompilerError(ErrorCode.NoMatchingOverload, $"No overload of '{functionName}' accepts {argumentCountText} with these types", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL402"
        };
    }

    /// <summary>
    /// Create an Elm-style method group used as value error.
    /// </summary>
    public static CompilerError MethodGroupUsedAsValue(string fileName, int line, int column, string sourceSnippet,
        int length, string methodName)
    {
        var humanExplanation = $"`{methodName}` names a method, not a value:";
        var contextualHint =
            "Methods need a call site like `name()` before they produce a value.\n" +
            "A bare method name is only valid when the surrounding API expects a delegate.";

        return new CompilerError(ErrorCode.MethodGroupUsedAsValue, $"Method '{methodName}' must be called or passed to a delegate", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestion = $"If you meant to use the result, call `{methodName}(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL411"
        };
    }

    /// <summary>
    /// Create an Elm-style invalid expression statement error
    /// </summary>
    public static CompilerError InvalidExpressionStatement(string fileName, int line, int column, string sourceSnippet,
        int length, string expressionDescription)
    {
        var humanExplanation = "This expression is written as a statement, but it does not do anything by itself:";
        var contextualHint =
            $"The expression `{expressionDescription}` produces a value or names a member, but the value is ignored.\n" +
            "Only assignments, calls, increments, decrements, await expressions, and object construction can be used as statements.";

        return new CompilerError(ErrorCode.InvalidExpressionStatement, "This expression statement has no effect", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestion = "Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL313"
        };
    }

    /// <summary>
    /// Create an Elm-style invalid for-loop iterator expression error
    /// </summary>
    public static CompilerError InvalidForIteratorExpression(string fileName, int line, int column, string sourceSnippet,
        int length, string expressionDescription)
    {
        var humanExplanation = "This expression appears in the update clause of a for loop, but it does not do anything by itself:";
        var contextualHint =
            $"The expression `{expressionDescription}` produces a value or names a member, but the value is ignored.\n" +
            "Only assignments, calls, increments, decrements, await expressions, and object construction can be used as for-loop iterators.";

        return new CompilerError(ErrorCode.InvalidExpressionStatement, "This for-loop iterator has no effect", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestion = "Use an assignment such as `i = i + 1`, an increment/decrement such as `i++`, a side-effecting call, or remove the iterator.",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL313"
        };
    }

    /// <summary>
    /// Create an Elm-style import not found error
    /// </summary>
    public static CompilerError ImportNotFound(string fileName, int line, int column, string sourceSnippet,
        int length, string importPath)
    {
        var humanExplanation = $"I cannot find the file you're trying to import on line {line}:";

        var contextualHint =
            $"Make sure the file exists at the path '{importPath}'.\n" +
            "The path should be relative to your project root.\n\n" +
            "Common issues:\n" +
            "  - Check for typos in the file path\n" +
            "  - Make sure the file extension is correct\n" +
            "  - Verify the file is in the expected directory";

        return new CompilerError(ErrorCode.ImportNotFound, $"Cannot find import '{importPath}'", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL701"
        };
    }

    /// <summary>
    /// Create an Elm-style circular import error
    /// </summary>
    public static CompilerError CircularImport(string fileName, int line, int column, string sourceSnippet,
        int length, string importPath)
    {
        var humanExplanation = $"I found a circular import on line {line}:";

        var contextualHint =
            $"The file '{importPath}' creates an import cycle back to this file.\n\n" +
            "Circular imports are not allowed because they make it impossible to determine\n" +
            "the correct order of symbol resolution.\n\n" +
            "To fix this, reorganize your code so imports flow in one direction. Consider:\n" +
            "  - Moving shared types to a separate file that both files import\n" +
            "  - Combining the files if they are tightly coupled";

        return new CompilerError(ErrorCode.CircularImport, $"Circular import: '{importPath}' creates a cycle", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL703"
        };
    }

    /// <summary>
    /// Create a better syntax error message
    /// </summary>
    public static CompilerError UnexpectedToken(string fileName, int line, int column, string sourceSnippet,
        int length, string unexpectedToken, string? expectedToken = null)
    {
        var humanExplanation = $"I found something unexpected on line {line}:";

        var contextualHint = expectedToken != null
            ? $"I was expecting to see {expectedToken}, but I found {unexpectedToken} instead.\n" +
              "Check for missing semicolons, parentheses, or other syntax elements."
            : $"The token `{unexpectedToken}` is not valid here.\n" +
              "Check your syntax - you may be missing a semicolon, closing brace, or parenthesis.";

        var message = expectedToken != null
            ? $"Expected {expectedToken} but found {unexpectedToken}"
            : $"Unexpected token: {unexpectedToken}";

        return new CompilerError(ErrorCode.UnexpectedToken, message, line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL101"
        };
    }

    /// <summary>
    /// Create an Elm-style missing return error
    /// </summary>
    public static CompilerError MissingReturn(string fileName, int line, int column, string sourceSnippet,
        int length, string returnType)
    {
        var humanExplanation = $"This function is declared to return `{returnType}`, but not all code paths " +
                               "return a value:";

        var contextualHint =
            $"Every code path through this function must end with a `return` statement that\n" +
            $"provides a `{returnType}` value. If you don't need to return anything, change the\n" +
            "return type to `void`.";

        return new CompilerError(ErrorCode.MissingReturn, $"Not all code paths return a value of type '{returnType}'", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            ExpectedType = returnType,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestion = $"Add a `return` statement, or change the return type to `void`",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL305"
        };
    }

    /// <summary>
    /// Create an Elm-style wrong argument type error
    /// </summary>
    public static CompilerError WrongArgumentType(string fileName, int line, int column, string sourceSnippet,
        int length, string functionName, int argIndex, string paramName, string actualType, string expectedType)
    {
        var humanExplanation = $"Argument {argIndex} in the call to `{functionName}` has the wrong type:";

        var contextualHint = TypeConversionSuggester.SuggestConversion(actualType, expectedType)
            ?? $"The parameter `{paramName}` expects a `{expectedType}` value, but you passed a\n" +
               $"`{actualType}`. These types are not compatible.";

        return new CompilerError(ErrorCode.TypeMismatch, $"Cannot pass `{actualType}` as argument for parameter `{paramName}` of type `{expectedType}`", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            ActualType = actualType,
            ExpectedType = expectedType,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL202"
        };
    }

    /// <summary>
    /// Create an Elm-style duplicate declaration error
    /// </summary>
    public static CompilerError DuplicateDeclaration(string fileName, int line, int column, string sourceSnippet,
        int length, string name, string kind)
    {
        var humanExplanation = $"I found a duplicate {kind} named `{name}` on line {line}:";

        var contextualHint =
            $"The name `{name}` is already defined. Each {kind} must have a unique name\n" +
            "within its scope. Rename one of the declarations to fix this.";

        return new CompilerError(ErrorCode.DuplicateDeclaration, $"Duplicate {kind} '{name}'", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL306"
        };
    }

    /// <summary>
    /// Create an Elm-style error for a `return`, `break`, or `continue` that would leave a `finally` block (NL319,
    /// the CS0157 analog). ECMA-335 requires a finally handler to complete via its own end; the runtime must always
    /// finish running it, so no control transfer may exit it early.
    /// </summary>
    public static CompilerError ControlTransferOutOfFinally(string fileName, int line, int column, string sourceSnippet,
        int length, string keyword)
    {
        var humanExplanation = $"This `{keyword}` would leave the enclosing `finally` block:";

        var target = keyword == "return" ? "the function" : "a loop outside the `finally`";
        var contextualHint =
            $"Control cannot leave a `finally` block — the runtime must always finish running it,\n" +
            $"whether the `try` completed normally or an exception is in flight. This `{keyword}`\n" +
            $"would exit the `finally` early to reach {target}, which the CLR forbids.\n" +
            "`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`.";

        return new CompilerError(ErrorCode.ControlTransferOutOfFinally, $"Control cannot leave a 'finally' block with '{keyword}'", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestion = $"Move the `{keyword}` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL319"
        };
    }

    /// <summary>
    /// Create an Elm-style error for a `lock` statement whose lockee is a value type (NL320, the CS0185 analog).
    /// When the lockee is an unconstrained generic type parameter, pass <paramref name="isTypeParameter"/> so the
    /// hint explains the constraint route instead of calling the type a value type outright.
    /// </summary>
    public static CompilerError LockRequiresReferenceType(string fileName, int line, int column, string sourceSnippet,
        int length, string typeName, bool isTypeParameter = false)
    {
        var humanExplanation = isTypeParameter
            ? $"This `lock` statement needs a reference type, but `{typeName}` is a type parameter that may be a value type:"
            : $"This `lock` statement needs a reference type, but `{typeName}` is a value type:";

        var contextualHint = isTypeParameter
            ? $"`Monitor` locks on object IDENTITY. If `{typeName}` is instantiated with a value type, the\n" +
              "value would be boxed into a fresh object on every `lock`, so no two threads would ever\n" +
              "contend on the same lock — the lock would guard nothing."
            : "`Monitor` locks on object IDENTITY. A value type has no stable identity: it would be\n" +
              "boxed into a fresh object on every `lock`, so no two threads would ever contend on\n" +
              "the same lock — the lock would guard nothing.";

        var suggestion = isTypeParameter
            ? $"Constrain `{typeName}` to a reference type (`where {typeName}: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`"
            : "Lock on a dedicated `object` field instead: `sync: object = new object()`";

        return new CompilerError(ErrorCode.LockRequiresReferenceType, $"'{typeName}' is not a reference type as required by the lock statement", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            ActualType = typeName,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestion = suggestion,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL320"
        };
    }

    /// <summary>
    /// Create an Elm-style error for a member write whose receiver is a temporary VALUE COPY
    /// (NL322, the CS1612 analog): assigning through a value-typed expression that is not a
    /// variable — a List indexer result, a call result, a property result — writes into a copy
    /// that is immediately discarded, so the assignment would be silently lost.
    /// </summary>
    public static CompilerError MemberWriteThroughValueCopy(string fileName, int line, int column, string sourceSnippet,
        int length, string memberName, string receiverTypeName, string receiverDescription)
    {
        return new CompilerError(ErrorCode.MemberWriteThroughValueCopy,
            $"Cannot assign to '{memberName}' because its receiver is a temporary copy of '{receiverTypeName}', not a variable", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            ActualType = receiverTypeName,
            HumanExplanation = $"This assignment writes through {receiverDescription}, but `{receiverTypeName}` is a value type:",
            ContextualHint = "A value type is copied every time it is returned from a call, an indexer, or a\n" +
                             "property. This write would land in that temporary copy and be thrown away with it —\n" +
                             "the original value would never change.",
            Suggestion = $"Copy the value into a local first, modify the local, then store the whole value back (e.g. `tmp := …` / `tmp.{memberName} = …` / store `tmp`)",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL322"
        };
    }

    /// <summary>
    /// Create an Elm-style undefined member error
    /// </summary>
    public static CompilerError UndefinedMember(string fileName, int line, int column, string sourceSnippet,
        int length, string memberName, string typeName, List<string> similarMembers)
    {
        var humanExplanation = $"I cannot find a member called `{memberName}` on type `{typeName}`:";

        var contextualHint = similarMembers.Any()
            ? $"The type `{typeName}` does not have a member named `{memberName}`.\n" +
              "Check for typos, or make sure you're accessing the right type."
            : $"The type `{typeName}` does not have a member named `{memberName}`.\n" +
              "Check the type's documentation for available members.";

        return new CompilerError(ErrorCode.UndefinedMember, $"Member '{memberName}' not found on type '{typeName}'", line, column, ErrorSeverity.Error)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            HumanExplanation = humanExplanation,
            ContextualHint = contextualHint,
            Suggestions = similarMembers.Any() ? similarMembers : null,
            DocsUrl = "https://docs.n-sharp.dev/errors/NL303"
        };
    }
}
