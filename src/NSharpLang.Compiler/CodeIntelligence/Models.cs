using System.Collections.Generic;
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
    LocationResult? Definition,
    string? Nullability = null);

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

/// <summary>
/// Symbol summary for an inspect query.
/// </summary>
public record InspectSymbolResult(
    string Name,
    string Kind,
    LocationResult? Definition);

/// <summary>
/// Reference summary for an inspect query.
/// </summary>
public record InspectReferencesResult(
    int Count,
    int DefinitionCount,
    ReferenceResult[] Results);

/// <summary>
/// Aggregated one-shot inspect result for LLM-friendly navigation.
/// </summary>
public record InspectResult(
    InspectSymbolResult? Symbol,
    TypeResult? Type,
    DefinitionResult? Definition,
    InspectReferencesResult References,
    CompletionResult Completions);

/// <summary>
/// Compact inspect result for token-efficient LLM navigation.
/// </summary>
public record InspectSummaryResult(
    InspectSummarySymbolResult? Symbol,
    InspectSummaryTypeResult? Type,
    LocationResult? Definition,
    InspectSummaryReferencesResult References,
    InspectSummaryCompletionsResult Completions);

/// <summary>
/// Compact symbol summary for inspect summary mode.
/// </summary>
public record InspectSummarySymbolResult(
    string Name,
    string Kind);

/// <summary>
/// Compact type summary for inspect summary mode.
/// </summary>
public record InspectSummaryTypeResult(
    string Name,
    string ResolvedType,
    string Kind,
    string? Nullability = null);

/// <summary>
/// Compact reference sample for inspect summary mode.
/// </summary>
public record InspectReferenceSummaryResult(
    string File,
    int Line,
    int Column,
    bool IsDefinition);

/// <summary>
/// Compact reference summary for inspect summary mode.
/// </summary>
public record InspectSummaryReferencesResult(
    int Count,
    int DefinitionCount,
    string[] Files,
    InspectReferenceSummaryResult[] Sample);

/// <summary>
/// Compact completion summary for inspect summary mode.
/// </summary>
public record InspectSummaryCompletionsResult(
    string Context,
    string? Receiver,
    string? ReceiverType,
    int TotalCount,
    Dictionary<string, int> GroupCounts,
    Dictionary<string, string[]> Groups);

// ── Hover ──────────────────────────────────────────────────────────────

/// <summary>
/// Hover result: signature + docs + definition location for a symbol at a position.
/// Shared by the CLI (nlc query hover) and the LSP HoverHandler.
/// </summary>
public record HoverResult(
    string Signature,
    string? Documentation,
    string? DefinedIn,
    string Kind);

// ── Call Graph ─────────────────────────────────────────────────────────

/// <summary>
/// A single call site edge: a callee name plus its source location.
/// </summary>
public record CallSiteResult(
    string Name,
    string? File,
    int Line,
    int Column);

/// <summary>
/// Call graph results for a function: all callers and callees found in the project.
/// </summary>
public record CallGraphResult(
    string? Function,
    List<CallSiteResult> Callers,
    List<CallSiteResult> Callees,
    bool Truncated);

// ── Implementors ───────────────────────────────────────────────────────

/// <summary>
/// A single concrete type that implements an interface.
/// </summary>
public record ImplementorResult(
    string TypeName,
    string Kind,
    string? File,
    int Line,
    int Column);

/// <summary>
/// All concrete types that implement a given interface.
/// </summary>
public record ImplementorsResult(
    string Interface,
    List<ImplementorResult> Results);
