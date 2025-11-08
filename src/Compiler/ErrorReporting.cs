using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace NewCLILang.Compiler;

/// <summary>
/// Error codes for N# compiler diagnostics
/// </summary>
public enum ErrorCode
{
    // Syntax errors (100-199)
    UnexpectedToken = 101,
    ExpectedToken = 102,
    InvalidSyntax = 103,
    UnexpectedEndOfFile = 104,
    InvalidLiteral = 105,
    MissingClosingBrace = 106,
    MissingClosingParen = 107,
    MissingClosingBracket = 108,

    // Type errors (200-299)
    TypeNotFound = 201,
    TypeMismatch = 202,
    CannotInferType = 203,
    InvalidCast = 204,
    AmbiguousType = 205,
    CannotResolveType = 206,
    InvalidTypeArgument = 207,
    GenericConstraintViolation = 208,

    // Semantic errors (300-399)
    UndefinedVariable = 301,
    UndefinedType = 302,
    UndefinedMember = 303,
    DefiniteAssignmentError = 304,
    MissingReturn = 305,
    DuplicateDeclaration = 306,
    CircularDependency = 307,
    InaccessibleMember = 308,
    ReadonlyAssignment = 309,
    ConstantRequired = 310,
    InvalidModifier = 311,

    // Function/Method errors (400-499)
    WrongArgumentCount = 401,
    NoMatchingOverload = 402,
    MissingRequiredParameter = 403,
    DuplicateParameter = 404,
    InvalidParameter = 405,
    RefOutMismatch = 406,
    ParamsNotLast = 407,
    MultipleParams = 408,

    // Pattern matching errors (500-599)
    NonExhaustiveMatch = 501,
    UnreachablePattern = 502,
    InvalidPattern = 503,
    PatternTypeMismatch = 504,
    GuardNotBoolean = 505,

    // Operator errors (600-699)
    InvalidOperatorOverload = 601,
    OperatorParameterCount = 602,
    ComparisonOperatorPair = 603,
    ConversionOperatorInvalid = 604,

    // Import/Using errors (700-799)
    ImportNotFound = 701,
    ImportCollision = 702,
    CircularImport = 703,
    NamespaceNotFound = 704,

    // Class/Struct/Interface errors (800-899)
    MultipleInheritance = 801,
    SealedInheritance = 802,
    AbstractInstantiation = 803,
    InterfaceImplementationMissing = 804,
    DuckInterfaceMismatch = 805,
    ConstructorError = 806,

    // Warnings (900-999)
    UnusedVariable = 901,
    UnreachableCode = 902,
    VisibilityConventionWarning = 903,
    ObsoleteUsage = 904,
    NullabilityWarning = 905,
    UnnecessaryTypeAnnotation = 906,
}

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

    public CompilerError(ErrorCode code, string message, int line, int column, ErrorSeverity severity)
    {
        Code = code;
        Message = message;
        Line = line;
        Column = column;
        Severity = severity;
    }

    /// <summary>
    /// Format error in Rust-style with source snippet and suggestions
    /// </summary>
    public string Format()
    {
        var builder = new StringBuilder();
        var severityText = Severity == ErrorSeverity.Warning ? "warning" : "error";

        // First line: error/warning with code and message
        builder.AppendLine($"{severityText} NL{(int)Code:D3}: {Message}");

        // Location
        if (FileName != null)
        {
            builder.AppendLine($"  --> {FileName}:{Line}:{Column}");
        }
        else
        {
            builder.AppendLine($"  --> line {Line}, column {Column}");
        }

        // Source snippet with marker
        if (SourceSnippet != null)
        {
            builder.AppendLine("   |");
            builder.AppendLine($"{Line,3} | {SourceSnippet}");

            // Calculate marker position (accounting for line number width)
            var markerIndent = Column > 0 ? new string(' ', Column - 1) : "";
            var markerLength = Math.Max(1, Length);
            var marker = new string('^', markerLength);
            builder.AppendLine($"   | {markerIndent}{marker}");
        }

        // Suggestion (help text)
        if (Suggestion != null)
        {
            builder.AppendLine("   |");
            builder.AppendLine($"help: {Suggestion}");
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
        string sourceSnippet, int length = 1, string? suggestion = null, ErrorSeverity severity = ErrorSeverity.Error)
    {
        return new CompilerError(code, message, line, column, severity)
        {
            FileName = fileName,
            SourceSnippet = sourceSnippet,
            Length = length,
            Suggestion = suggestion
        };
    }
}

public enum ErrorSeverity
{
    Warning,
    Error
}

public record AnalysisResult(List<CompilerError> Errors)
{
    public bool HasErrors => Errors.Any(e => e.Severity == ErrorSeverity.Error);
}

/// <summary>
/// Helper class for generating helpful error suggestions
/// </summary>
public static class ErrorSuggestions
{
    /// <summary>
    /// Get a helpful suggestion for a given error code and context
    /// </summary>
    public static string? GetSuggestion(ErrorCode code, string? context = null, string? additionalInfo = null)
    {
        return code switch
        {
            ErrorCode.TypeNotFound when context != null && IsPossibleTypo(context)
                => $"Did you mean '{FindSimilarType(context)}'?",

            ErrorCode.TypeNotFound
                => "Check that the type is defined and imported correctly",

            ErrorCode.MissingReturn
                => "Add a return statement or change return type to void",

            ErrorCode.DefiniteAssignmentError
                => "Initialize property in constructor or provide default value",

            ErrorCode.UndefinedVariable when context != null
                => $"Variable '{context}' is not defined in current scope",

            ErrorCode.TypeMismatch
                => "Ensure types are compatible or add explicit cast",

            ErrorCode.CannotInferType
                => "Add explicit type annotation: 'let x: Type = ...'",

            ErrorCode.NonExhaustiveMatch when additionalInfo != null
                => $"Add missing cases: {additionalInfo}, or use wildcard '_' to match all remaining",

            ErrorCode.NonExhaustiveMatch
                => "Ensure all cases are covered or add wildcard pattern '_'",

            ErrorCode.GuardNotBoolean
                => "Guard expression must be boolean type",

            ErrorCode.WrongArgumentCount
                => "Check the function signature for required parameters",

            ErrorCode.ReadonlyAssignment
                => "Readonly fields can only be assigned in constructor",

            ErrorCode.VisibilityConventionWarning
                => "Use PascalCase for public members or camelCase for private members",

            ErrorCode.ImportCollision
                => "Use 'import ... as Alias' to resolve naming conflicts",

            ErrorCode.DuckInterfaceMismatch when additionalInfo != null
                => $"Implement missing method: {additionalInfo}",

            ErrorCode.InvalidOperatorOverload
                => "Operators must be public static and have correct parameter types",

            ErrorCode.ComparisonOperatorPair
                => "Define both operators in the pair (== with !=, < with >, <= with >=)",

            _ => null
        };
    }

    private static bool IsPossibleTypo(string name)
    {
        // Simple heuristic: check for common type names
        var commonTypes = new[] { "string", "int", "bool", "double", "float", "long", "decimal", "object", "DateTime", "Guid" };
        return commonTypes.Any(t => LevenshteinDistance(name.ToLower(), t.ToLower()) <= 2);
    }

    private static string FindSimilarType(string name)
    {
        // Placeholder - in real implementation, search symbol table
        var commonTypes = new[] { "string", "int", "bool", "double", "float", "long", "decimal", "object", "DateTime", "Guid" };
        return commonTypes
            .OrderBy(t => LevenshteinDistance(name.ToLower(), t.ToLower()))
            .First();
    }

    private static int LevenshteinDistance(string s, string t)
    {
        int n = s.Length;
        int m = t.Length;
        int[,] d = new int[n + 1, m + 1];

        if (n == 0) return m;
        if (m == 0) return n;

        for (int i = 0; i <= n; d[i, 0] = i++) { }
        for (int j = 0; j <= m; d[0, j] = j++) { }

        for (int i = 1; i <= n; i++)
        {
            for (int j = 1; j <= m; j++)
            {
                int cost = (t[j - 1] == s[i - 1]) ? 0 : 1;
                d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + cost);
            }
        }

        return d[n, m];
    }
}
