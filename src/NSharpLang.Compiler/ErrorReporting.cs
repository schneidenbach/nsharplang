using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace NSharpLang.Compiler;

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
    UnreachableStatement = 312,
    InvalidExpressionStatement = 313,
    UnverifiedErrorResult = 314,

    // Function/Method errors (400-499)
    WrongArgumentCount = 401,
    NoMatchingOverload = 402,
    MissingRequiredParameter = 403,
    DuplicateParameter = 404,
    InvalidParameter = 405,
    RefOutMismatch = 406,
    ParamsNotLast = 407,
    MultipleParams = 408,
    RequiredParameterAfterOptional = 409,
    InvalidDefaultParameterValue = 410,
    MethodGroupUsedAsValue = 411,

    // Pattern matching errors (500-599)
    NonExhaustiveMatch = 501,
    UnreachablePattern = 502,
    InvalidPattern = 503,
    PatternTypeMismatch = 504,
    GuardNotBoolean = 505,
    ImpossiblePattern = 506,

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

    // Compiler diagnostics (900-999)
    UnusedVariable = 901,
    UnreachableCode = 902,
    VisibilityConventionWarning = 903,
    ObsoleteUsage = 904,
    PossibleNullAccess = 905,
    UnnecessaryTypeAnnotation = 906,
    NullabilityWarning = 907,
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

    // Rich context for Elm-level error messages
    public string? ActualType { get; init; }
    public string? ExpectedType { get; init; }
    public string? HumanExplanation { get; init; }
    public string? ContextualHint { get; init; }
    public string? DocsUrl { get; init; }
    public List<string>? Suggestions { get; init; }
    public Dictionary<string, string>? RelatedInfo { get; init; }

    public string DiagnosticId => $"NL{(int)Code:D3}";

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
            ErrorCode.WrongArgumentCount or ErrorCode.NoMatchingOverload => "FUNCTION CALL ERROR",
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

internal static class DiagnosticSpanResolver
{
    public static (int Column, int Length) Resolve(string? sourceLine, int oneBasedColumn, int requestedLength)
    {
        if (requestedLength > 0)
            return (oneBasedColumn, Math.Max(1, requestedLength));

        if (string.IsNullOrEmpty(sourceLine))
            return (oneBasedColumn, 1);

        var start = oneBasedColumn - 1;
        if (start < 0 || start >= sourceLine.Length)
            return (oneBasedColumn, 1);

        if (char.IsWhiteSpace(sourceLine[start]))
        {
            var visibleStart = FindNextVisibleTokenStart(sourceLine, start);
            if (visibleStart < 0)
                visibleStart = FindPreviousVisibleTokenStart(sourceLine, start);

            if (visibleStart >= 0)
                return (visibleStart + 1, InferVisibleTokenLength(sourceLine, visibleStart));

            return (oneBasedColumn, 1);
        }

        return (oneBasedColumn, InferVisibleTokenLength(sourceLine, start));
    }

    private static int FindNextVisibleTokenStart(string sourceLine, int start)
    {
        for (var index = start; index < sourceLine.Length; index++)
        {
            if (!char.IsWhiteSpace(sourceLine[index]))
                return index;
        }

        return -1;
    }

    private static int FindPreviousVisibleTokenStart(string sourceLine, int start)
    {
        var index = Math.Min(start, sourceLine.Length - 1);
        while (index >= 0 && char.IsWhiteSpace(sourceLine[index]))
            index--;

        if (index < 0)
            return -1;

        while (index > 0 && IsDiagnosticTokenChar(sourceLine[index - 1]))
            index--;

        return index;
    }

    private static int InferVisibleTokenLength(string sourceLine, int zeroBasedStart)
    {
        if (zeroBasedStart < 0 || zeroBasedStart >= sourceLine.Length)
            return 1;

        if (sourceLine[zeroBasedStart] == '"')
            return ScanQuotedDiagnosticTokenLength(sourceLine, zeroBasedStart, '"');

        if (sourceLine[zeroBasedStart] == '\'')
            return ScanQuotedDiagnosticTokenLength(sourceLine, zeroBasedStart, '\'');

        if (sourceLine[zeroBasedStart] == '$' &&
            zeroBasedStart + 1 < sourceLine.Length &&
            sourceLine[zeroBasedStart + 1] == '"')
        {
            return 1 + ScanQuotedDiagnosticTokenLength(sourceLine, zeroBasedStart + 1, '"');
        }

        var end = zeroBasedStart;
        while (end < sourceLine.Length && IsDiagnosticTokenChar(sourceLine[end]))
            end++;

        if (end > zeroBasedStart)
            return end - zeroBasedStart;

        return zeroBasedStart + 1 < sourceLine.Length &&
               IsPunctuationPair(sourceLine[zeroBasedStart], sourceLine[zeroBasedStart + 1])
            ? 2
            : 1;
    }

    private static int ScanQuotedDiagnosticTokenLength(string sourceLine, int quoteStart, char quote)
    {
        var index = quoteStart + 1;
        while (index < sourceLine.Length)
        {
            if (sourceLine[index] == '\\')
            {
                index += 2;
                continue;
            }

            if (sourceLine[index] == quote)
                return index - quoteStart + 1;

            index++;
        }

        return Math.Max(1, sourceLine.Length - quoteStart);
    }

    private static bool IsDiagnosticTokenChar(char ch)
        => char.IsLetterOrDigit(ch) || ch is '_' or '.' or '!' or '?';

    private static bool IsPunctuationPair(char first, char second)
        => (first, second) is
            (':', '=') or
            ('=', '>') or
            ('=', '=') or
            ('!', '=') or
            ('>', '=') or
            ('<', '=') or
            ('&', '&') or
            ('|', '|') or
            ('?', '?');
}

public enum ErrorSeverity
{
    Warning,
    Error
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
    public bool HasWarnings => Errors.Any(e => e.Severity == ErrorSeverity.Warning);

    // Implicit conversion for backwards compatibility
    public static implicit operator Ast.CompilationUnit?(ParseResult result) => result.CompilationUnit;
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

            ErrorCode.UnverifiedErrorResult
                => "Check the paired error first, or return/throw from the error branch before using the result",

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

            ErrorCode.MethodGroupUsedAsValue
                => "Call the method with parentheses, or pass it to a parameter with a delegate type",

            ErrorCode.ReadonlyAssignment
                => "Readonly fields can only be assigned in constructor",

            ErrorCode.VisibilityConventionWarning
                => "Use PascalCase for public members or camelCase for private members",

            ErrorCode.ImportCollision
                => "Use 'import ... as Alias' to resolve naming conflicts",

            ErrorCode.CircularImport
                => "Reorganize imports to avoid cycles. Move shared types to a separate file that both files can import",

            ErrorCode.DuckInterfaceMismatch when additionalInfo != null
                => $"Implement missing method: {additionalInfo}",

            ErrorCode.InvalidOperatorOverload
                => "Operators must be public static and have correct parameter types",

            ErrorCode.ComparisonOperatorPair
                => "Define both operators in the pair (== with !=, < with >, <= with >=)",

            ErrorCode.UnreachableStatement
                => "Remove unreachable code or restructure control flow",

            ErrorCode.InvalidExpressionStatement
                => "Use the value by assigning it, printing it, passing it to a call, or remove the expression",

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

    public static int LevenshteinDistance(string s, string t)
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

/// <summary>
/// Smart suggester for typos using enhanced Levenshtein distance
/// </summary>
public class SmartSuggester
{
    private readonly List<string> _candidates;

    public SmartSuggester(List<string> candidates)
    {
        _candidates = candidates;
    }

    /// <summary>
    /// Suggest similar names based on typo
    /// </summary>
    public List<string> SuggestSimilarNames(string typo, int maxSuggestions = 3)
    {
        return _candidates
            .Select(c => (Name: c, Score: ScoreSimilarity(typo, c)))
            .Where(x => x.Score > 0.5)  // Only suggest if reasonably similar
            .OrderByDescending(x => x.Score)
            .Take(maxSuggestions)
            .Select(x => x.Name)
            .ToList();
    }

    private double ScoreSimilarity(string a, string b)
    {
        var distance = ErrorSuggestions.LevenshteinDistance(a.ToLower(), b.ToLower());
        var maxLen = Math.Max(a.Length, b.Length);
        var distanceScore = 1.0 - ((double)distance / maxLen);

        var prefixScore = CommonPrefixLength(a, b) / (double)Math.Min(a.Length, b.Length);

        return (distanceScore * 0.7) + (prefixScore * 0.3);
    }

    private int CommonPrefixLength(string a, string b)
    {
        int count = 0;
        int minLen = Math.Min(a.Length, b.Length);
        for (int i = 0; i < minLen; i++)
        {
            if (char.ToLower(a[i]) == char.ToLower(b[i]))
                count++;
            else
                break;
        }
        return count;
    }
}

/// <summary>
/// Provides contextual hints for type conversions
/// </summary>
public static class TypeConversionSuggester
{
    private static readonly HashSet<string> NumericTypes = new()
    {
        "int", "long", "short", "byte", "sbyte",
        "ushort", "uint", "ulong", "float", "double", "decimal", "char"
    };

    private static bool IsNumericType(string typeName) => NumericTypes.Contains(typeName);

    public static string? SuggestConversion(string fromType, string toType)
    {
        return (fromType, toType) switch
        {
            ("string", "int") =>
                "Strings and integers are different types. To convert a string to an int,\n" +
                "you can use int.Parse(yourString) or int.TryParse(yourString, out result).",

            ("int", "string") =>
                "You can convert an integer to a string using .ToString() or string\n" +
                "interpolation: $\"{yourNumber}\"",

            ("int", "double") =>
                "Implicit conversion from int to double works automatically.",

            ("double", "int") =>
                "Cannot implicitly convert 'double' to 'int'. Use an explicit cast: (int)value\n" +
                "Warning: This truncates decimals (e.g. 3.7 becomes 3) and may lose data if the value exceeds the target type's range.",

            ("string", "double") =>
                "Use double.Parse(yourString) or double.TryParse(yourString, out result).",

            ("double", "string") =>
                "Use value.ToString() or $\"{value}\"",

            ("int", "long") =>
                "Implicit conversion from int to long works automatically.",

            ("long", "int") =>
                "Cannot implicitly convert 'long' to 'int'. Use an explicit cast: (int)value\n" +
                "Warning: This conversion may lose data if the value exceeds the target type's range.",

            // Nullable conversions
            (var from, var to) when to == from + "?" =>
                "This conversion is implicit. Non-nullable values can be assigned to nullable types.",

            (var from, var to) when from == to + "?" =>
                "You're trying to use a nullable value where a non-nullable is expected.\n" +
                "You need to handle the null case, perhaps with 'if (x != null)' or the\n" +
                "null-coalescing operator 'x ?? defaultValue'.",

            // Array/List conversions
            (var from, var to) when from.EndsWith("[]") && to.StartsWith("List<") =>
                "Use .ToList() to convert an array to a List, or use 'new List<T>(array)'.",

            (var from, var to) when from.StartsWith("List<") && to.EndsWith("[]") =>
                "Use .ToArray() to convert a List to an array.",

            // Numeric narrowing conversions — catch-all for all remaining numeric pairs
            (var from, var to) when IsNumericType(from) && IsNumericType(to) =>
                $"Cannot implicitly convert '{from}' to '{to}'. Use an explicit cast: ({to})value\n" +
                "Warning: This conversion may lose data if the value exceeds the target type's range.",

            _ => null
        };
    }
}

/// <summary>
/// Builds human-friendly error messages with multi-level explanations
/// </summary>
public static class ErrorMessageBuilder
{
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

        var contextualHint = expected > actual
            ? $"The function `{functionName}` expects {expected} arguments, but you are\n" +
              $"passing {actual}. You may have forgotten to pass some arguments."
            : $"The function `{functionName}` expects {expected} arguments, but you are\n" +
              $"passing {actual}. You may have passed too many arguments.";

        return new CompilerError(ErrorCode.WrongArgumentCount, $"Function '{functionName}' expects {expected} arguments but got {actual}", line, column, ErrorSeverity.Error)
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

        var humanExplanation = $"I cannot find an overload of `{functionName}` that matches this call:";
        var contextualHint =
            $"This call passes {actualArgumentCount} argument(s): {argumentText}.\n" +
            $"{signatureText}\n\n" +
            "Check the argument count and types. If you meant to reference the method itself, use it in a context with a delegate type instead of calling it.";

        return new CompilerError(ErrorCode.NoMatchingOverload, $"No overload of '{functionName}' accepts {actualArgumentCount} argument(s) with these types", line, column, ErrorSeverity.Error)
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
