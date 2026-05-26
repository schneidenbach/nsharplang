using System.Collections.Generic;

namespace NSharpLang.Playground;

public sealed record PlaygroundCatalogResponse(
    int SchemaVersion,
    string DefaultExampleId,
    int EstimatedMinutes,
    IReadOnlyList<PlaygroundExample> Examples,
    PlaygroundCapabilities Capabilities);

public sealed record PlaygroundCapabilities(
    bool RunsInBrowser,
    bool SupportsDiagnostics,
    bool SupportsFormatting,
    bool SupportsCompletions,
    bool SupportsHover,
    bool SupportsSyntaxHighlighting,
    bool SupportsExecution,
    bool SupportsTests,
    IReadOnlyList<string> Limitations);

public sealed record PlaygroundExample(
    string Id,
    string Title,
    string Summary,
    int Minutes,
    string Goal,
    IReadOnlyList<string> Concepts,
    string CSharpContrast,
    string Code,
    string? TestsCode)
{
    public bool HasTests => !string.IsNullOrWhiteSpace(TestsCode);
}

public sealed record PlaygroundFile(
    string Name,
    string Code);

public sealed record PlaygroundCheckResponse(
    int SchemaVersion,
    bool Ok,
    string File,
    IReadOnlyList<PlaygroundDiagnostic> Diagnostics,
    PlaygroundSummary Summary);

public sealed record PlaygroundFormatResponse(
    int SchemaVersion,
    bool Ok,
    string File,
    string FormattedCode,
    IReadOnlyList<PlaygroundDiagnostic> Diagnostics,
    PlaygroundSummary Summary,
    IReadOnlyList<string> Warnings);

public sealed record PlaygroundCompletionResponse(
    int SchemaVersion,
    bool Ok,
    string File,
    string Context,
    string? Receiver,
    string? ReceiverType,
    IReadOnlyList<PlaygroundCompletionItem> Items,
    IReadOnlyList<PlaygroundDiagnostic> Diagnostics,
    PlaygroundSummary Summary);

public sealed record PlaygroundCompletionItem(
    string Label,
    string Kind,
    string? Detail,
    string? Documentation,
    string InsertText);

public sealed record PlaygroundHoverResponse(
    int SchemaVersion,
    bool Ok,
    string File,
    PlaygroundHover? Hover,
    IReadOnlyList<PlaygroundDiagnostic> Diagnostics,
    PlaygroundSummary Summary);

public sealed record PlaygroundHover(
    string Signature,
    string? Documentation,
    string? DefinedIn,
    string Kind);

public sealed record PlaygroundSummary(
    int Errors,
    int Warnings,
    int Infos);

public sealed record PlaygroundDiagnostic(
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
    string? Hint);
