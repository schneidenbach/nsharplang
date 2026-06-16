using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class OutputFormatterDiagnosticKernels
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
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

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<DiagnosticSeveritySummaryInto>(
                    programType,
                    "DiagnosticSeveritySummaryInto"),
                CreateDelegate<DiagnosticSeverityFilterIndicesInto>(
                    programType,
                    "DiagnosticSeverityFilterIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    private delegate int DiagnosticSeveritySummaryInto(
        string[] severities,
        int count,
        int[] resultCounts);

    private delegate int DiagnosticSeverityFilterIndicesInto(
        int[] severityRanks,
        int targetRank,
        int[] resultIndices);

    private sealed record Bindings(
        DiagnosticSeveritySummaryInto DiagnosticSeveritySummary,
        DiagnosticSeverityFilterIndicesInto DiagnosticSeverityFilter);

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
