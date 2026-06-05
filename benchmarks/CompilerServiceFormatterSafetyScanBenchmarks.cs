using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood probe for <c>Formatter.FormatSafe</c> reparse-error filtering.
///
/// FormatSafe reparses formatted output and rejects the formatting when any reparse
/// diagnostic has <c>ErrorSeverity.Error</c>, then collects the matching error messages
/// (<c>Errors.Where(e =&gt; e.Severity == Error).Select(e =&gt; e.Message)</c>) for a
/// <c>string.Join("; ", ...)</c> warning. The severity filter itself is a cheap scan over a
/// two-value severity enum (<c>Warning = 0</c>, <c>Error = 1</c>); the real cost in the
/// failure path is public message-string materialization, which the host must own.
///
/// The C# baseline here replicates only the compact severity-scan portion of FormatSafe:
/// the <c>Any(severity == Error)</c> success gate and the error-index collection that feeds
/// the message join (without materializing the strings, so the comparison isolates the scan).
/// The N# candidate scans the same compact severity <c>int[]</c> and writes matching error
/// indices into a caller-owned <c>int[]</c>.
///
/// This benchmark is pressure/rejection evidence: the severity scan is trivially cheap and
/// the C# baseline short-circuits, so the N# candidate is not expected to clear the 5x gate.
/// See docs/design/compiler-dogfood-rewrite.md for the recorded rejection rationale.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceFormatterSafetyScanBenchmarks
{
    private const int LargeErrorCount = 8192;
    private const int RepresentativeErrorCount = 1024;

    private Func<int[], int[], int> _nsharpErrorIndicesChecksumInto =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _severities = Array.Empty<int>();
    private int _csharpResultCount;
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var errorCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeErrorCount
            : LargeErrorCount;

        _nsharpErrorIndicesChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int>>(
                DogfoodCompilerSources.FormatterSafetyScan,
                "FormatterSafetyErrorIndicesChecksumInto");

        _severities = new int[errorCount];
        _csharpResultIndices = new int[errorCount];
        _nsharpResultIndices = new int[errorCount];

        BuildSeverities();

        var expectedChecksum = CSharpFormatterSafetyScan_QueryBatch();
        var actualChecksum = NSharpFormatterSafetyScan_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# formatter safety scan checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _csharpResultCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# formatter safety scan mismatch for {Corpus} at result {i}: " +
                    $"expected index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpFormatterSafetyScan_QueryBatch()
    {
        Array.Clear(_csharpResultIndices);

        // Replicates Formatter.FormatSafe: the Any(severity == Error) success gate plus the
        // error-index collection that backs Errors.Where(...).Select(e => e.Message) before
        // string.Join. String materialization stays out of the measurement (host boundary).
        if (!_severities.Any(severity => severity == 1))
        {
            _csharpResultCount = 0;
            return 0;
        }

        var resultIndices = Enumerable.Range(0, _severities.Length)
            .Where(i => _severities[i] == 1)
            .ToArray();

        _csharpResultCount = resultIndices.Length;
        var checksum = resultIndices.Length;
        for (var i = 0; i < resultIndices.Length; i++)
        {
            var index = resultIndices[i];
            _csharpResultIndices[i] = index;
            checksum += (index + 1) * 31 + (i + 1) * 13;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpFormatterSafetyScan_QueryBatch() =>
        _nsharpErrorIndicesChecksumInto(_severities, _nsharpResultIndices);

    private void BuildSeverities()
    {
        // Realistic reparse-failure distribution: mostly warning-severity diagnostics with a
        // minority of error-severity entries scattered through the list, modelling the failure
        // path where FormatSafe must collect the error messages.
        for (var i = 0; i < _severities.Length; i++)
        {
            _severities[i] = (i % 7 == 3 || i % 11 == 5) ? 1 : 0;
        }
    }
}
