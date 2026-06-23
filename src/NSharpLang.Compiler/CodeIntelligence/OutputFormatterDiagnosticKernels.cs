using System;
using System.Collections.Generic;

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

    internal static DiagnosticSummary SummarizeDiagnosticSeverities(IReadOnlyList<DiagnosticResult> diagnostics)
    {
        var count = diagnostics.Count;
        var scratch = t_diagnosticSummaryScratch ??= new DiagnosticSummaryScratch();
        scratch.EnsureCapacity(count);

        try
        {
            for (var i = 0; i < count; i++)
            {
                scratch.Severities[i] = diagnostics[i].Severity ?? string.Empty;
            }

            var summarized = RequiredBindings.DiagnosticSeveritySummary(scratch.Severities, count, scratch.Counts);
            if (summarized != count)
                throw new InvalidOperationException("N# diagnostic severity summary kernel rejected the diagnostics.");

            return new DiagnosticSummary(
                scratch.Counts[0],
                scratch.Counts[1],
                scratch.Counts[2]);
        }
        finally
        {
            Array.Clear(scratch.Severities, 0, count);
            scratch.Counts[0] = 0;
            scratch.Counts[1] = 0;
            scratch.Counts[2] = 0;
        }
    }

    internal static (int[] ResultIndices, int Count) FilterDiagnosticSeverities(
        IReadOnlyList<DiagnosticResult> diagnostics,
        string targetSeverity)
    {
        var diagnosticCount = diagnostics.Count;
        var scratch = t_diagnosticSeverityFilterScratch ??= new DiagnosticSeverityFilterScratch();
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            var targetRank = scratch.BuildRanks(diagnostics, targetSeverity);
            var count = RequiredBindings.DiagnosticSeverityFilter(
                scratch.SeverityRanks,
                targetRank,
                scratch.ResultIndices);

            if (count < 0 || count > diagnosticCount)
                throw new InvalidOperationException("N# diagnostic severity filter kernel rejected the diagnostics.");

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static string GetDiagnosticTitle(string code, string severity)
        => RequiredBindings.DiagnosticTitle(code, severity);

    internal static string GetExpectedTypeText(string expectedType)
        => GetDiagnosticDetailText(DiagnosticDetailExpectedType, expectedType);

    internal static string GetActualTypeText(string actualType)
        => GetDiagnosticDetailText(DiagnosticDetailActualType, actualType);

    internal static string GetHintText(string hint)
        => GetDiagnosticDetailText(DiagnosticDetailHint, hint);

    internal static string GetSuggestionText(string suggestion)
        => GetDiagnosticDetailText(DiagnosticDetailSuggestion, suggestion);

    internal static string GetDocsUrlText(string docsUrl)
        => GetDiagnosticDetailText(DiagnosticDetailDocsUrl, docsUrl);

    private static string GetDiagnosticDetailText(int kind, string value)
        => RequiredBindings.DiagnosticDetail(kind, value);

    internal static string GetNoDiagnosticsText()
        => RequiredBindings.DiagnosticNoDiagnostics();

    internal static string GetFoundSummaryText(DiagnosticSummary summary)
        => RequiredBindings.DiagnosticFoundSummary(summary.Errors, summary.Warnings, summary.Info);

    internal static string GetSourceLineText(int line, string sourceSnippet)
        => RequiredBindings.DiagnosticSourceLine(line, sourceSnippet);

    internal static string GetHeaderLineText(string title, string file, int line, int column)
        => RequiredBindings.DiagnosticHeaderLine(title, file, line, column);

    internal static string GetCaretLineText(int line, int column, int length)
        => RequiredBindings.DiagnosticCaretLine(line, column, length);

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
            DogfoodKernelLoader.CreateDelegate<DiagnosticHeaderLineText>(
                programType,
                "DiagnosticHeaderLineText"),
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

    private delegate string DiagnosticHeaderLineText(string title, string file, int line, int column);

    private delegate string DiagnosticCaretLineText(int line, int column, int length);

    private sealed record Bindings(
        DiagnosticSeveritySummaryInto DiagnosticSeveritySummary,
        DiagnosticSeverityFilterIndicesInto DiagnosticSeverityFilter,
        DiagnosticTitleText DiagnosticTitle,
        DiagnosticDetailText DiagnosticDetail,
        DiagnosticNoDiagnosticsText DiagnosticNoDiagnostics,
        DiagnosticFoundSummaryText DiagnosticFoundSummary,
        DiagnosticSourceLineText DiagnosticSourceLine,
        DiagnosticHeaderLineText DiagnosticHeaderLine,
        DiagnosticCaretLineText DiagnosticCaretLine);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# diagnostic text kernels are unavailable.");

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
