using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for diagnostic severity filtering in <c>nlc query diagnostics</c>,
/// batch diagnostics, and daemon diagnostics.
///
/// The C# baseline mirrors the current CLI shape: case-insensitive severity comparison and list
/// materialization. The N# candidate runs after the host has assigned compact
/// <see cref="StringComparer.OrdinalIgnoreCase" /> severity ranks and writes matching diagnostic
/// indices into caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliDiagnosticSeverityFilterBenchmarks
{
    private const int LargeDiagnosticCount = 8192;
    private const int RepresentativeDiagnosticCount = 1024;
    private const string TargetSeverity = "ERROR";

    private Func<int[], int, int[], int> _nsharpDiagnosticSeverityFilterChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpResultIndices = Array.Empty<int>();
    private DiagnosticEntry[] _diagnostics = Array.Empty<DiagnosticEntry>();
    private int _diagnosticCount;
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _severityRanks = Array.Empty<int>();
    private int _targetRank;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _diagnosticCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDiagnosticCount
            : LargeDiagnosticCount;
        _nsharpDiagnosticSeverityFilterChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticSeverityFilterChecksumInto");

        _diagnostics = BuildDiagnostics(_diagnosticCount);
        _severityRanks = new int[_diagnosticCount];
        _csharpResultIndices = new int[_diagnosticCount];
        _nsharpResultIndices = new int[_diagnosticCount];
        BuildSeverityRanks();

        var expectedChecksum = CSharpDiagnosticSeverityFilter_QueryDiagnostics();
        var actualChecksum = NSharpDiagnosticSeverityFilter_QueryDiagnostics();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# diagnostic severity filter checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expectedIndices = _diagnostics
            .Where(diagnostic => diagnostic.Severity.Equals(TargetSeverity, StringComparison.OrdinalIgnoreCase))
            .Select(diagnostic => diagnostic.Index)
            .ToArray();
        if (expectedIndices.Length == 0)
        {
            throw new InvalidOperationException($"Diagnostic severity filter benchmark corpus {Corpus} has no matching diagnostics.");
        }

        for (var i = 0; i < expectedIndices.Length; i++)
        {
            if (_csharpResultIndices[i] != expectedIndices[i] || _nsharpResultIndices[i] != expectedIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# diagnostic severity filter mismatch for {Corpus} at result {i}: " +
                    $"expected source index {expectedIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticSeverityFilter_QueryDiagnostics()
    {
        var filtered = _diagnostics
            .Where(diagnostic => diagnostic.Severity.Equals(TargetSeverity, StringComparison.OrdinalIgnoreCase))
            .ToList();

        var checksum = filtered.Count;
        for (var i = 0; i < filtered.Count; i++)
        {
            var index = filtered[i].Index;
            _csharpResultIndices[i] = index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _severityRanks[index] * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpDiagnosticSeverityFilter_QueryDiagnostics() =>
        _nsharpDiagnosticSeverityFilterChecksumInto(
            _severityRanks,
            _targetRank,
            _nsharpResultIndices);

    private void BuildSeverityRanks()
    {
        var ranksBySeverity = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        void AddSeverity(string severity)
        {
            if (ranksBySeverity.ContainsKey(severity))
                return;

            ranksBySeverity.Add(severity, ranksBySeverity.Count + 1);
        }

        AddSeverity(TargetSeverity);
        for (var i = 0; i < _diagnostics.Length; i++)
        {
            AddSeverity(_diagnostics[i].Severity);
        }

        _targetRank = ranksBySeverity[TargetSeverity];
        for (var i = 0; i < _diagnostics.Length; i++)
        {
            _severityRanks[i] = ranksBySeverity[_diagnostics[i].Severity];
        }
    }

    private static DiagnosticEntry[] BuildDiagnostics(int count)
    {
        var severities = new[] { "error", "warning", "info", "hint", "Error", "ERROR", "warning", "trace", "INFO" };
        var diagnostics = new DiagnosticEntry[count];
        for (var i = 0; i < count; i++)
        {
            var severity = severities[(i * 7 + i / 17) % severities.Length];
            diagnostics[i] = new DiagnosticEntry(i, severity);
        }

        return diagnostics;
    }

    private sealed record DiagnosticEntry(int Index, string Severity);
}

/// <summary>
/// Dogfood benchmark for compiler-error severity filtering in CLI parse/backend error paths.
///
/// The C# baseline mirrors the current CLI shape: enum severity comparison and list
/// materialization over <see cref="CompilerError" /> objects. The N# candidate runs after the host
/// projects <see cref="ErrorSeverity" /> values into compact ranks and writes matching error
/// indices into caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliCompilerErrorSeverityFilterBenchmarks
{
    private const int LargeErrorCount = 8192;
    private const int RepresentativeErrorCount = 1024;
    private const ErrorSeverity TargetSeverity = ErrorSeverity.Error;

    private Func<int[], int, int[], int> _nsharpDiagnosticSeverityFilterChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpResultIndices = Array.Empty<int>();
    private CompilerError[] _errors = Array.Empty<CompilerError>();
    private int _errorCount;
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _severityRanks = Array.Empty<int>();
    private int _targetRank;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _errorCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeErrorCount
            : LargeErrorCount;
        _nsharpDiagnosticSeverityFilterChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticSeverityFilterChecksumInto");

        _errors = BuildCompilerErrors(_errorCount);
        _severityRanks = new int[_errorCount];
        _csharpResultIndices = new int[_errorCount];
        _nsharpResultIndices = new int[_errorCount];
        BuildSeverityRanks();

        var expectedChecksum = CSharpCompilerErrorSeverityFilter_Cli();
        var actualChecksum = NSharpCompilerErrorSeverityFilter_Cli();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# compiler-error severity filter checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expectedIndices = _errors
            .Where(error => error.Severity == TargetSeverity)
            .Select(error => error.Line - 1)
            .ToArray();
        if (expectedIndices.Length == 0)
        {
            throw new InvalidOperationException($"Compiler-error severity filter benchmark corpus {Corpus} has no matching errors.");
        }

        for (var i = 0; i < expectedIndices.Length; i++)
        {
            if (_csharpResultIndices[i] != expectedIndices[i] || _nsharpResultIndices[i] != expectedIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# compiler-error severity filter mismatch for {Corpus} at result {i}: " +
                    $"expected source index {expectedIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCompilerErrorSeverityFilter_Cli()
    {
        var filtered = _errors
            .Where(error => error.Severity == TargetSeverity)
            .ToList();

        var checksum = filtered.Count;
        for (var i = 0; i < filtered.Count; i++)
        {
            var index = filtered[i].Line - 1;
            _csharpResultIndices[i] = index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _severityRanks[index] * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpCompilerErrorSeverityFilter_Cli() =>
        _nsharpDiagnosticSeverityFilterChecksumInto(
            _severityRanks,
            _targetRank,
            _nsharpResultIndices);

    private void BuildSeverityRanks()
    {
        _targetRank = GetSeverityRank(TargetSeverity);
        for (var i = 0; i < _errors.Length; i++)
        {
            _severityRanks[i] = GetSeverityRank(_errors[i].Severity);
        }
    }

    private static CompilerError[] BuildCompilerErrors(int count)
    {
        var errors = new CompilerError[count];
        for (var i = 0; i < count; i++)
        {
            var severity = ((i * 7 + i / 11) % 5) switch
            {
                0 or 3 => ErrorSeverity.Error,
                _ => ErrorSeverity.Warning
            };
            errors[i] = new CompilerError(
                ErrorCode.InvalidSyntax,
                $"diagnostic {i}",
                i + 1,
                (i % 113) + 1,
                severity);
        }

        return errors;
    }

    private static int GetSeverityRank(ErrorSeverity severity) =>
        severity switch
        {
            ErrorSeverity.Error => 1,
            ErrorSeverity.Warning => 2,
            _ => 0
        };
}
