using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for diagnostic deduplication used by <c>nlc check</c> and strict build lint.
///
/// The C# baseline mirrors the previous CLI shape: LINQ <c>GroupBy</c> over the full diagnostic
/// identity, first-diagnostic preservation, and file/line/column ordering. The N# candidate consumes
/// preassigned compact code/message IDs plus default-comparer file sort ranks, deduplicates with a
/// caller-owned open-addressed table, and sorts result indices in place.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDiagnosticDeduplicationBenchmarks
{
    private const int LargeDiagnosticCount = 8192;
    private const int RepresentativeDiagnosticCount = 1024;

    private Func<int[], int[], int[], int[], int[], int[], int[], int> _nsharpDiagnosticDeduplicationChecksumInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _codeIds = Array.Empty<int>();
    private string[] _codes = Array.Empty<string>();
    private int[] _columns = Array.Empty<int>();
    private int _csharpResultCount;
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int _diagnosticCount;
    private int[] _fileRanks = Array.Empty<int>();
    private string[] _files = Array.Empty<string>();
    private int[] _lines = Array.Empty<int>();
    private int[] _messageIds = Array.Empty<int>();
    private string[] _messages = Array.Empty<string>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _nsharpSlotIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _diagnosticCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDiagnosticCount
            : LargeDiagnosticCount;
        _nsharpDiagnosticDeduplicationChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticDeduplication,
                "DiagnosticDeduplicateCompactChecksumInto");

        _codes = new string[_diagnosticCount];
        _codeIds = new int[_diagnosticCount];
        _files = new string[_diagnosticCount];
        _fileRanks = new int[_diagnosticCount];
        _lines = new int[_diagnosticCount];
        _columns = new int[_diagnosticCount];
        _messages = new string[_diagnosticCount];
        _messageIds = new int[_diagnosticCount];
        _csharpResultIndices = new int[_diagnosticCount];
        _nsharpResultIndices = new int[_diagnosticCount];
        _nsharpSlotIndices = new int[_diagnosticCount * 2 + 1];

        BuildDiagnostics();

        var expectedChecksum = CSharpDiagnosticDeduplication_QueryBatch();
        var actualChecksum = NSharpDiagnosticDeduplication_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# diagnostic deduplication checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _csharpResultCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# diagnostic deduplication mismatch for {Corpus} at result {i}: " +
                    $"expected index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticDeduplication_QueryBatch()
    {
        Array.Clear(_csharpResultIndices);

        var resultIndices = Enumerable.Range(0, _diagnosticCount)
            .GroupBy(i => (_codes[i], _files[i], _lines[i], _columns[i], _messages[i]))
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
    public int NSharpDiagnosticDeduplication_QueryBatch() =>
        _nsharpDiagnosticDeduplicationChecksumInto(
            _codeIds,
            _fileRanks,
            _lines,
            _columns,
            _messageIds,
            _nsharpSlotIndices,
            _nsharpResultIndices);

    private void BuildDiagnostics()
    {
        var codeIdsByText = new Dictionary<string, int>(StringComparer.Ordinal);
        var messageIdsByText = new Dictionary<string, int>(StringComparer.Ordinal);
        var uniqueCount = _diagnosticCount / 4;

        for (var i = 0; i < _diagnosticCount; i++)
        {
            var key = i % uniqueCount;
            var code = (key % 13) switch
            {
                0 or 1 or 2 => "NL102",
                3 => "NL301",
                4 => "NL302",
                5 => "NL401",
                6 => "NL703",
                7 => "NL801",
                _ => $"NL9{key % 97:00}"
            };
            var file = (key % 11) switch
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
            var message = (key % 9) switch
            {
                0 => $"Expected token ';' near shape {key % 64}",
                1 => $"Undefined variable 'value{key % 41}'",
                2 => $"Type mismatch: expected int but found string at site {key % 53}",
                3 => "Circular import detected",
                _ => $"Diagnostic message shape {key % 127}"
            };

            _codes[i] = code;
            _codeIds[i] = GetId(codeIdsByText, code);
            _files[i] = file;
            _lines[i] = (key * 37 % 400) + 1;
            _columns[i] = (key * 17 % 80) + 1;
            _messages[i] = message;
            _messageIds[i] = GetId(messageIdsByText, message);
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

    private static int GetId(Dictionary<string, int> ids, string text)
    {
        if (ids.TryGetValue(text, out var id))
            return id;

        id = ids.Count + 1;
        ids.Add(text, id);
        return id;
    }
}

/// <summary>
/// Dogfood benchmark for the preserve-first-order diagnostic deduplication used by
/// <c>CodeIntelligenceService.GetDiagnostics</c>.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDiagnosticStableDeduplicationBenchmarks
{
    private const int LargeDiagnosticCount = 8192;
    private const int RepresentativeDiagnosticCount = 1024;

    private Func<int[], int[], int[], int[], int[], int[], int[], int> _nsharpDiagnosticDeduplicationChecksumInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _codeIds = Array.Empty<int>();
    private string[] _codes = Array.Empty<string>();
    private int[] _columns = Array.Empty<int>();
    private int _csharpResultCount;
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int _diagnosticCount;
    private int[] _fileIds = Array.Empty<int>();
    private string[] _files = Array.Empty<string>();
    private int[] _lines = Array.Empty<int>();
    private int[] _messageIds = Array.Empty<int>();
    private string[] _messages = Array.Empty<string>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _nsharpSlotIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _diagnosticCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDiagnosticCount
            : LargeDiagnosticCount;
        _nsharpDiagnosticDeduplicationChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticDeduplication,
                "DiagnosticDeduplicateStableChecksumInto");

        _codes = new string[_diagnosticCount];
        _codeIds = new int[_diagnosticCount];
        _files = new string[_diagnosticCount];
        _fileIds = new int[_diagnosticCount];
        _lines = new int[_diagnosticCount];
        _columns = new int[_diagnosticCount];
        _messages = new string[_diagnosticCount];
        _messageIds = new int[_diagnosticCount];
        _csharpResultIndices = new int[_diagnosticCount];
        _nsharpResultIndices = new int[_diagnosticCount];
        _nsharpSlotIndices = new int[_diagnosticCount * 2 + 1];

        BuildDiagnostics();

        var expectedChecksum = CSharpDiagnosticStableDeduplication_QueryBatch();
        var actualChecksum = NSharpDiagnosticStableDeduplication_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# stable diagnostic deduplication checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _csharpResultCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# stable diagnostic deduplication mismatch for {Corpus} at result {i}: " +
                    $"expected index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticStableDeduplication_QueryBatch()
    {
        Array.Clear(_csharpResultIndices);

        var resultIndices = Enumerable.Range(0, _diagnosticCount)
            .GroupBy(i => (_codes[i], _files[i], _lines[i], _columns[i], _messages[i]))
            .Select(group => group.First())
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
    public int NSharpDiagnosticStableDeduplication_QueryBatch() =>
        _nsharpDiagnosticDeduplicationChecksumInto(
            _codeIds,
            _fileIds,
            _lines,
            _columns,
            _messageIds,
            _nsharpSlotIndices,
            _nsharpResultIndices);

    private void BuildDiagnostics()
    {
        var codeIdsByText = new Dictionary<string, int>(StringComparer.Ordinal);
        var fileIdsByText = new Dictionary<string, int>(StringComparer.Ordinal);
        var messageIdsByText = new Dictionary<string, int>(StringComparer.Ordinal);
        var uniqueCount = _diagnosticCount / 4;

        for (var i = 0; i < _diagnosticCount; i++)
        {
            var key = i % uniqueCount;
            var code = (key % 13) switch
            {
                0 or 1 or 2 => "NL102",
                3 => "NL301",
                4 => "NL302",
                5 => "NL401",
                6 => "NL703",
                7 => "NL801",
                _ => $"NL9{key % 97:00}"
            };
            var file = (key % 11) switch
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
            var message = (key % 9) switch
            {
                0 => $"Expected token ';' near shape {key % 64}",
                1 => $"Undefined variable 'value{key % 41}'",
                2 => $"Type mismatch: expected int but found string at site {key % 53}",
                3 => "Circular import detected",
                _ => $"Diagnostic message shape {key % 127}"
            };

            _codes[i] = code;
            _codeIds[i] = GetId(codeIdsByText, code);
            _files[i] = file;
            _fileIds[i] = GetId(fileIdsByText, file);
            _lines[i] = (key * 37 % 400) + 1;
            _columns[i] = (key * 17 % 80) + 1;
            _messages[i] = message;
            _messageIds[i] = GetId(messageIdsByText, message);
        }
    }

    private static int GetId(Dictionary<string, int> ids, string text)
    {
        if (ids.TryGetValue(text, out var id))
            return id;

        id = ids.Count + 1;
        ids.Add(text, id);
        return id;
    }
}
