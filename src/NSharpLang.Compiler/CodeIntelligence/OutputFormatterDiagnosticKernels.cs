using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class OutputFormatterDiagnosticKernels
{
    private const int DiagnosticDetailExpectedType = 1;
    private const int DiagnosticDetailActualType = 2;
    private const int DiagnosticDetailHint = 3;
    private const int DiagnosticDetailSuggestion = 4;
    private const int DiagnosticDetailDocsUrl = 5;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static DiagnosticSummaryScratch? t_diagnosticSummaryScratch;
    [ThreadStatic]
    private static DiagnosticSeverityFilterScratch? t_diagnosticSeverityFilterScratch;

    internal static bool TrySummarizeDiagnosticSeverities(
        IReadOnlyList<DiagnosticResult> diagnostics,
        out DiagnosticSummary summary)
    {
        summary = new DiagnosticSummary(0, 0, 0);

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = diagnostics.Count;
        var scratch = t_diagnosticSummaryScratch ??= new DiagnosticSummaryScratch();
        scratch.EnsureCapacity(count);

        try
        {
            for (var i = 0; i < count; i++)
            {
                scratch.Severities[i] = diagnostics[i].Severity ?? string.Empty;
            }

            var summarized = bindings.DiagnosticSeveritySummary(scratch.Severities, count, scratch.Counts);
            if (summarized != count)
                return false;

            summary = new DiagnosticSummary(
                scratch.Counts[0],
                scratch.Counts[1],
                scratch.Counts[2]);
            return true;
        }
        catch
        {
            summary = new DiagnosticSummary(0, 0, 0);
            return false;
        }
        finally
        {
            Array.Clear(scratch.Severities, 0, count);
            scratch.Counts[0] = 0;
            scratch.Counts[1] = 0;
            scratch.Counts[2] = 0;
        }
    }

    internal static bool TryFilterDiagnosticSeverities(
        IReadOnlyList<DiagnosticResult> diagnostics,
        string targetSeverity,
        out int[] resultIndices,
        out int count)
    {
        resultIndices = Array.Empty<int>();
        count = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return true;

        var scratch = t_diagnosticSeverityFilterScratch ??= new DiagnosticSeverityFilterScratch();
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            var targetRank = scratch.BuildRanks(diagnostics, targetSeverity);
            count = bindings.DiagnosticSeverityFilter(
                scratch.SeverityRanks,
                targetRank,
                scratch.ResultIndices);

            if (count < 0 || count > diagnosticCount)
            {
                count = 0;
                return false;
            }

            resultIndices = scratch.ResultIndices;
            return true;
        }
        catch
        {
            resultIndices = Array.Empty<int>();
            count = 0;
            return false;
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static string GetDiagnosticTitle(string code, string severity)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetDiagnosticTitleWithCSharp(code, severity);

        try
        {
            var title = bindings.DiagnosticTitle(code, severity);
            if (!string.IsNullOrEmpty(title))
                return title;
        }
        catch
        {
        }

        return GetDiagnosticTitleWithCSharp(code, severity);
    }

    internal static string GetExpectedTypeText(string expectedType)
        => GetDiagnosticDetailText(DiagnosticDetailExpectedType, expectedType, $"Expected: `{expectedType}`");

    internal static string GetActualTypeText(string actualType)
        => GetDiagnosticDetailText(DiagnosticDetailActualType, actualType, $"  Actual: `{actualType}`");

    internal static string GetHintText(string hint)
        => GetDiagnosticDetailText(DiagnosticDetailHint, hint, $"Hint: {hint}");

    internal static string GetSuggestionText(string suggestion)
        => GetDiagnosticDetailText(DiagnosticDetailSuggestion, suggestion, $"Suggestion: {suggestion}");

    internal static string GetDocsUrlText(string docsUrl)
        => GetDiagnosticDetailText(DiagnosticDetailDocsUrl, docsUrl, $"See: {docsUrl}");

    private static string GetDiagnosticDetailText(int kind, string value, string fallback)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return fallback;

        try
        {
            var detail = bindings.DiagnosticDetail(kind, value);
            if (!string.IsNullOrEmpty(detail))
                return detail;
        }
        catch
        {
        }

        return fallback;
    }

    internal static string GetNoDiagnosticsText()
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return "No diagnostics found.";

        try
        {
            var text = bindings.DiagnosticNoDiagnostics();
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return "No diagnostics found.";
    }

    internal static string GetFoundSummaryText(DiagnosticSummary summary)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetFoundSummaryTextWithCSharp(summary);

        try
        {
            var text = bindings.DiagnosticFoundSummary(summary.Errors, summary.Warnings, summary.Info);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetFoundSummaryTextWithCSharp(summary);
    }

    internal static string GetSourceLineText(int line, string sourceSnippet)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetSourceLineTextWithCSharp(line, sourceSnippet);

        try
        {
            var text = bindings.DiagnosticSourceLine(line, sourceSnippet);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetSourceLineTextWithCSharp(line, sourceSnippet);
    }

    internal static string GetCaretLineText(int line, int column, int length)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetCaretLineTextWithCSharp(line, column, length);

        try
        {
            var text = bindings.DiagnosticCaretLine(line, column, length);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetCaretLineTextWithCSharp(line, column, length);
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<DiagnosticSeveritySummaryInto>(
                programType,
                "DiagnosticSeveritySummaryInto"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticSeverityFilterIndicesInto>(
                programType,
                "DiagnosticSeverityFilterIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticTitleText>(
                programType,
                "DiagnosticTitleText"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticDetailText>(
                programType,
                "DiagnosticDetailText"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticNoDiagnosticsText>(
                programType,
                "DiagnosticNoDiagnosticsText"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticFoundSummaryText>(
                programType,
                "DiagnosticFoundSummaryText"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticSourceLineText>(
                programType,
                "DiagnosticSourceLineText"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticCaretLineText>(
                programType,
                "DiagnosticCaretLineText")));

    private delegate int DiagnosticSeveritySummaryInto(
        string[] severities,
        int count,
        int[] resultCounts);

    private delegate int DiagnosticSeverityFilterIndicesInto(
        int[] severityRanks,
        int targetRank,
        int[] resultIndices);

    private delegate string DiagnosticTitleText(string code, string severity);

    private delegate string DiagnosticDetailText(int kind, string value);

    private delegate string DiagnosticNoDiagnosticsText();

    private delegate string DiagnosticFoundSummaryText(int errors, int warnings, int info);

    private delegate string DiagnosticSourceLineText(int line, string sourceSnippet);

    private delegate string DiagnosticCaretLineText(int line, int column, int length);

    private sealed record Bindings(
        DiagnosticSeveritySummaryInto DiagnosticSeveritySummary,
        DiagnosticSeverityFilterIndicesInto DiagnosticSeverityFilter,
        DiagnosticTitleText DiagnosticTitle,
        DiagnosticDetailText DiagnosticDetail,
        DiagnosticNoDiagnosticsText DiagnosticNoDiagnostics,
        DiagnosticFoundSummaryText DiagnosticFoundSummary,
        DiagnosticSourceLineText DiagnosticSourceLine,
        DiagnosticCaretLineText DiagnosticCaretLine);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product diagnostic text routes through DiagnosticClusters.nl.
    private static string GetDiagnosticTitleWithCSharp(string code, string severity)
        => $"[{code}] {severity.ToUpperInvariant()}";

    private static string GetFoundSummaryTextWithCSharp(DiagnosticSummary summary)
    {
        var parts = new List<string>();
        if (summary.Errors > 0) parts.Add($"{summary.Errors} error{(summary.Errors == 1 ? "" : "s")}");
        if (summary.Warnings > 0) parts.Add($"{summary.Warnings} warning{(summary.Warnings == 1 ? "" : "s")}");
        if (summary.Info > 0) parts.Add($"{summary.Info} info");
        return $"Found {string.Join(", ", parts)}.";
    }

    private static string GetSourceLineTextWithCSharp(int line, string sourceSnippet)
        => $"    {line} | {sourceSnippet}";

    private static string GetCaretLineTextWithCSharp(int line, int column, int length)
    {
        var padding = new string(' ', line.ToString().Length);
        var caretOffset = Math.Max(0, column - 1);
        var caretLine = new string(' ', caretOffset) + new string('^', Math.Max(1, length));
        return $"    {padding} | {caretLine}";
    }

    private sealed class DiagnosticSummaryScratch
    {
        public readonly int[] Counts = new int[3];
        public string[] Severities = Array.Empty<string>();

        public void EnsureCapacity(int count)
        {
            if (Severities.Length < count)
            {
                Severities = new string[count];
            }
        }
    }

    private sealed class DiagnosticSeverityFilterScratch
    {
        private readonly Dictionary<string, int> _severityRanks = new(StringComparer.OrdinalIgnoreCase);

        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeverityRanks = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (SeverityRanks.Length != count)
            {
                SeverityRanks = new int[count];
                ResultIndices = new int[count];
            }
        }

        public int BuildRanks(IReadOnlyList<DiagnosticResult> diagnostics, string targetSeverity)
        {
            _severityRanks.Clear();
            var targetRank = GetSeverityRank(targetSeverity);
            for (var i = 0; i < diagnostics.Count; i++)
            {
                SeverityRanks[i] = GetSeverityRank(diagnostics[i].Severity ?? string.Empty);
            }

            return targetRank;
        }

        public void Reset() => _severityRanks.Clear();

        private int GetSeverityRank(string severity)
        {
            if (_severityRanks.TryGetValue(severity, out var rank))
                return rank;

            rank = _severityRanks.Count + 1;
            _severityRanks.Add(severity, rank);
            return rank;
        }
    }
}
