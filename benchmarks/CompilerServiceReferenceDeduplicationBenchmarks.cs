using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for reference-result deduplication and ordering used by semantic references.
///
/// The C# baseline mirrors the current service shape: LINQ <c>GroupBy</c> over
/// <c>(file,line,column)</c>, first-reference preservation, and file/line/column ordering. The N#
/// candidate consumes default-comparer file sort ranks, deduplicates with a caller-owned
/// open-addressed table, and sorts result indices in place.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceReferenceDeduplicationBenchmarks
{
    private const int LargeReferenceCount = 8192;
    private const int RepresentativeReferenceCount = 1024;

    private Func<int[], int[], int[], int[], int[], int> _nsharpReferenceDeduplicationChecksumInto =
        (_, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _columns = Array.Empty<int>();
    private int _csharpResultCount;
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int[] _fileRanks = Array.Empty<int>();
    private string[] _files = Array.Empty<string>();
    private int[] _lines = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _nsharpSlotIndices = Array.Empty<int>();
    private int _referenceCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _referenceCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeReferenceCount
            : LargeReferenceCount;
        _nsharpReferenceDeduplicationChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticDeduplication,
                "ReferenceDeduplicateCompactChecksumInto");

        _files = new string[_referenceCount];
        _fileRanks = new int[_referenceCount];
        _lines = new int[_referenceCount];
        _columns = new int[_referenceCount];
        _csharpResultIndices = new int[_referenceCount];
        _nsharpResultIndices = new int[_referenceCount];
        _nsharpSlotIndices = new int[_referenceCount * 2 + 1];

        BuildReferences();

        var expectedChecksum = CSharpReferenceDeduplication_QueryBatch();
        var actualChecksum = NSharpReferenceDeduplication_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# reference deduplication checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _csharpResultCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# reference deduplication mismatch for {Corpus} at result {i}: " +
                    $"expected index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpReferenceDeduplication_QueryBatch()
    {
        Array.Clear(_csharpResultIndices);

        var resultIndices = Enumerable.Range(0, _referenceCount)
            .GroupBy(i => (_files[i], _lines[i], _columns[i]))
            .Select(group => group.First())
            .OrderBy(i => _files[i])
            .ThenBy(i => _lines[i])
            .ThenBy(i => _columns[i])
            .ToArray();

        _csharpResultCount = resultIndices.Length;
        var checksum = resultIndices.Length;
        for (var i = 0; i < resultIndices.Length; i++)
        {
            var index = resultIndices[i];
            _csharpResultIndices[i] = index;
            checksum += (index + 1) * 31 + _lines[index] * 17 + _columns[index] * 13;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpReferenceDeduplication_QueryBatch() =>
        _nsharpReferenceDeduplicationChecksumInto(
            _fileRanks,
            _lines,
            _columns,
            _nsharpSlotIndices,
            _nsharpResultIndices);

    private void BuildReferences()
    {
        var uniqueCount = _referenceCount / 4;

        for (var i = 0; i < _referenceCount; i++)
        {
            var key = i % uniqueCount;
            _files[i] = (key % 11) switch
            {
                0 => $"/repo/src/Program{key % 19}.nl",
                1 => $"/repo/src/generated/File-{key % 23}.nl",
                2 => $"/repo/src/with space/File {key % 17}.nl",
                3 => $@"C:\repo\module\File{key % 29}.nl",
                4 => $"/repo/src/quoted\"File{key % 31}.nl",
                5 => "/repo/src/Main.nl",
                6 => $"/repo/src/cafe/Module{key % 7}.nl",
                _ => $"/repo/src/[weird]/File{key % 37}.nl"
            };
            _lines[i] = (key * 37 % 400) + 1;
            _columns[i] = (key * 17 % 80) + 1;
        }

        AssignFileRanks();
    }

    private void AssignFileRanks()
    {
        var uniqueFiles = _files.Distinct(StringComparer.Ordinal).ToArray();
        Array.Sort(uniqueFiles, Comparer<string>.Default);
        var ranksByFile = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < uniqueFiles.Length; i++)
        {
            ranksByFile.Add(uniqueFiles[i], i + 1);
        }

        for (var i = 0; i < _files.Length; i++)
        {
            _fileRanks[i] = ranksByFile[_files[i]];
        }
    }
}
