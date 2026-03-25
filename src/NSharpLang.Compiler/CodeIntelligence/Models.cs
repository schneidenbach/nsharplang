using System.Text.Json.Serialization;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Symbol kinds for code intelligence results.
/// These are compiler-level kinds — NOT the same as LSP SymbolKind.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SymbolKind
{
    Function,
    Class,
    Struct,
    Record,
    Interface,
    Enum,
    Union,
    Property,
    Field,
    Method,
    Variable,
    Parameter,
    Constructor,
    EnumMember,
    TypeAlias,
    Test
}

/// <summary>
/// A symbol in the codebase — function, class, property, etc.
/// </summary>
public record SymbolResult(
    string Name,
    SymbolKind Kind,
    string File,
    int Line,
    int Column,
    string? TypeName,
    string[]? Modifiers,
    SymbolResult[]? Members,
    ParameterResult[]? Parameters);

/// <summary>
/// A function/method parameter.
/// </summary>
public record ParameterResult(
    string Name,
    string Type,
    bool HasDefault,
    string? DefaultValue);

/// <summary>
/// Structural outline of a single file.
/// </summary>
public record OutlineResult(
    string File,
    string[] Imports,
    OutlineEntry[] Outline);

/// <summary>
/// A single entry in a file's structural outline (may have children).
/// </summary>
public record OutlineEntry(
    string Name,
    SymbolKind Kind,
    int Line,
    int EndLine,
    string? ReturnType,
    string? TypeName,
    OutlineEntry[]? Children);

/// <summary>
/// A compiler diagnostic (error, warning, or info) with Elm-level rich context.
/// </summary>
public record DiagnosticResult(
    string Code,
    string Severity,
    string Message,
    string File,
    int Line,
    int Column,
    int Length,
    string? SourceSnippet,
    string? Explanation,
    string? Suggestion,
    string? Hint,
    string? ExpectedType,
    string? ActualType,
    string? DocsUrl);

/// <summary>
/// Summary counts of diagnostics by severity.
/// </summary>
public record DiagnosticSummary(int Errors, int Warnings, int Info);

/// <summary>
/// Result of a type query at a position.
/// </summary>
public record TypeResult(
    string Name,
    string ResolvedType,
    string Kind,
    LocationResult? Definition);

/// <summary>
/// Result of a go-to-definition query.
/// </summary>
public record DefinitionResult(
    string Name,
    string Kind,
    string File,
    int Line,
    int Column,
    int Length);

/// <summary>
/// A single reference to a symbol.
/// </summary>
public record ReferenceResult(
    string File,
    int Line,
    int Column,
    int Length,
    string? Context,
    bool IsDefinition);

/// <summary>
/// A file:line:col location.
/// </summary>
public record LocationResult(
    string File,
    int Line,
    int Column);
