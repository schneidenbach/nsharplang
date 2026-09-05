using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Performance;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Formats code intelligence results as either JSON (default, for LLM consumption)
/// or Elm-style text (--text, for human consumption).
///
/// JSON output uses a versioned envelope: { schemaVersion, command, ... }
/// Text output uses Elm-inspired formatting with clear headers, source snippets, and suggestions.
/// </summary>
public static class OutputFormatter
{
    public static DiagnosticSummary SummarizeDiagnostics(IReadOnlyList<DiagnosticResult> results)
        => OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results);

    public static List<DiagnosticResult> FilterDiagnosticsBySeverity(
        IReadOnlyList<DiagnosticResult> diagnostics,
        string severity)
    {
        return OutputFormatterDiagnosticKernels.FilterDiagnosticSeverityResults(
            diagnostics,
            severity);
    }

    public static List<DiagnosticResult> DeduplicateAndSortDiagnostics(IReadOnlyList<DiagnosticResult> diagnostics)
    {
        return CodeIntelligenceResultKernels.DeduplicateDiagnosticResults(diagnostics);
    }

    // ── JSON Output ────────────────────────────────────────────────────

    public static string SymbolsToJson(List<SymbolResult> results, string? projectRoot = null)
    {
        return OutputFormatterJsonKernels.SymbolsToJson(results, projectRoot);
    }

    public static string OutlineToJson(OutlineResult result)
    {
        return OutputFormatterJsonKernels.OutlineToJson(result);
    }

    public static string DiagnosticsToJson(List<DiagnosticResult> results, string? projectRoot = null)
    {
        return OutputFormatterJsonKernels.DiagnosticsToJson(results, projectRoot);
    }

    public static string DiagnosticClustersToJson(List<DiagnosticResult> results, string? projectRoot = null)
    {
        return OutputFormatterJsonKernels.DiagnosticClustersToJson(results, projectRoot);
    }

    public static string CheckToJson(List<DiagnosticResult> results, string? projectRoot, int checkedFiles)
    {
        return OutputFormatterJsonKernels.CheckToJson(results, projectRoot, checkedFiles);
    }

    public static string LintToJson(List<DiagnosticResult> results, string? projectRoot, int lintedFiles)
    {
        return OutputFormatterJsonKernels.LintToJson(results, projectRoot, lintedFiles);
    }

    public static string TypeToJson(TypeResult result, string file, int line, int col)
    {
        return OutputFormatterJsonKernels.TypeToJson(result, file, line, col);
    }

    /// <summary>
    /// Emits the versioned performance report envelope for <c>nlc build --perf-report</c>.
    /// The report groups performance facts by category. Categories without a wired fact source
    /// are emitted as empty arrays so the envelope shape is stable for downstream consumers;
    /// </summary>
    public static string BuildPerfReportToJson(
        string? projectRoot,
        bool ok = true,
        IReadOnlyList<PerfReportSite>? allocationSites = null,
        IReadOnlyList<PerfReportSite>? delegateSites = null,
        IReadOnlyList<PerfReportSite>? boxingSites = null,
        IReadOnlyList<PerfReportSite>? dispatchSites = null,
        IReadOnlyList<PerfReportSite>? closureCaptures = null,
        IReadOnlyList<PerfReportSite>? poolSites = null,
        IReadOnlyList<PerfReportSite>? resourceSites = null,
        IReadOnlyList<PerfReportSite>? boundaryLeakSites = null,
        IReadOnlyList<PerfReportSite>? hotReadinessSites = null,
        IReadOnlyList<PerfReportSite>? implicitTrapSites = null,
        IReadOnlyList<PerfReportTrustedSite>? trustedSites = null)
    {
        return OutputFormatterJsonKernels.BuildPerfReportToJson(
            projectRoot,
            ok,
            allocationSites ?? Array.Empty<PerfReportSite>(),
            delegateSites ?? Array.Empty<PerfReportSite>(),
            boxingSites ?? Array.Empty<PerfReportSite>(),
            dispatchSites ?? Array.Empty<PerfReportSite>(),
            closureCaptures ?? Array.Empty<PerfReportSite>(),
            poolSites ?? Array.Empty<PerfReportSite>(),
            resourceSites ?? Array.Empty<PerfReportSite>(),
            boundaryLeakSites ?? Array.Empty<PerfReportSite>(),
            hotReadinessSites ?? Array.Empty<PerfReportSite>(),
            implicitTrapSites ?? Array.Empty<PerfReportSite>(),
            trustedSites ?? Array.Empty<PerfReportTrustedSite>());
    }

    public static string CheckSystemsReportToJson(
        List<DiagnosticResult> diagnostics,
        string? projectRoot,
        int checkedFiles,
        SystemsReport report)
    {
        return OutputFormatterJsonKernels.CheckSystemsReportToJson(
            diagnostics,
            projectRoot,
            checkedFiles,
            report);
    }

    public static string TrustedToJson(SystemsReport report, string? projectRoot)
    {
        return OutputFormatterJsonKernels.TrustedToJson(report, projectRoot);
    }

    public static string PerfToJson(string file, int line, int col, string? projectRoot,
        IReadOnlyList<object>? facts = null)
    {
        return OutputFormatterJsonKernels.PerfToJson(
            file,
            line,
            col,
            projectRoot,
            facts ?? Array.Empty<object>());
    }

    public static string DefinitionToJson(DefinitionResult result)
    {
        return OutputFormatterJsonKernels.DefinitionToJson(result);
    }

    public static string DefinitionSearchToJson(string query, IReadOnlyList<DefinitionResult> results)
    {
        return OutputFormatterJsonKernels.DefinitionSearchToJson(query, results);
    }

    public static string ReferencesToJson(string symbolName, string symbolKind,
        LocationResult? definedAt, List<ReferenceResult> results)
    {
        return OutputFormatterJsonKernels.ReferencesToJson(symbolName, symbolKind, definedAt, results);
    }

    public static string CompletionsToJson(CompletionResult result, string file, int line, int col)
    {
        return OutputFormatterJsonKernels.CompletionsToJson(result, file, line, col);
    }

    public static string InspectToJson(InspectResult result, string file, int line, int col)
    {
        return OutputFormatterJsonKernels.InspectToJson(result, file, line, col);
    }

    public static string InspectSummaryToJson(InspectResult result, string file, int line, int col)
    {
        return OutputFormatterJsonKernels.InspectSummaryToJson(result, file, line, col);
    }

    public static string CompletionsToText(CompletionResult result, string file, int line, int col)
    {
        return OutputFormatterTextBuilders.CompletionsToText(result, file, line, col);
    }

    public static string InspectToText(InspectResult result, string file, int line, int col)
    {
        return OutputFormatterTextBuilders.InspectToText(result, file, line, col);
    }

    public static string DocToJson(DocResult result, string query)
    {
        return OutputFormatterJsonKernels.DocToJson(result, query);
    }

    // ── Hover ──────────────────────────────────────────────────────────────

    public static string HoverToJson(HoverResult result, string file, int line, int col)
    {
        return OutputFormatterJsonKernels.HoverToJson(result, file, line, col);
    }

    public static string HoverToText(HoverResult result, string file, int line, int col)
    {
        return OutputFormatterTextBuilders.HoverToText(result, file, line, col);
    }

    // ── Call Graph ─────────────────────────────────────────────────────────

    public static string CallGraphToJson(CallGraphResult result)
    {
        return OutputFormatterJsonKernels.CallGraphToJson(result);
    }

    public static string CallGraphToText(CallGraphResult result)
    {
        return OutputFormatterTextBuilders.CallGraphToText(result);
    }

    // ── Implementors ───────────────────────────────────────────────────────

    public static string ImplementorsToJson(ImplementorsResult result)
    {
        return OutputFormatterJsonKernels.ImplementorsToJson(result);
    }

    public static string ImplementorsToText(ImplementorsResult result)
    {
        return OutputFormatterTextBuilders.ImplementorsToText(result);
    }

    // ── Error ──────────────────────────────────────────────────────────────

    public static string ErrorToJson(string command, string error, string? projectRoot = null,
        string? errorCode = null, object? details = null)
    {
        return OutputFormatterJsonKernels.ErrorToJson(
            command,
            error,
            projectRoot,
            errorCode,
            details);
    }

    // ── Elm-Style Text Output ──────────────────────────────────────────

    public static string DiagnosticsToText(List<DiagnosticResult> results)
    {
        return OutputFormatterTextBuilders.DiagnosticsToText(results);
    }

    public static string SymbolsToText(List<SymbolResult> results)
    {
        return OutputFormatterTextBuilders.SymbolsToText(results);
    }

    public static string OutlineToText(OutlineResult result)
    {
        return OutputFormatterTextBuilders.OutlineToText(result);
    }

    public static string TypeToText(TypeResult result, string file, int line, int col)
    {
        return OutputFormatterTextBuilders.TypeToText(result, file, line, col);
    }

    public static string DefinitionToText(DefinitionResult result)
    {
        return OutputFormatterTextBuilders.DefinitionToText(result);
    }

    public static string DefinitionSearchToText(string query, IReadOnlyList<DefinitionResult> results)
    {
        return OutputFormatterTextBuilders.DefinitionSearchToText(query, results);
    }

    public static string ReferencesToText(string symbolName, List<ReferenceResult> results)
    {
        return OutputFormatterTextBuilders.ReferencesToText(symbolName, results);
    }

    public static string DocToText(DocResult result)
    {
        return OutputFormatterTextBuilders.DocToText(result);
    }
}
