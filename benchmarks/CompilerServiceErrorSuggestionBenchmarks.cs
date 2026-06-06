using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for compiler typo-suggestion scoring.
///
/// The C# baseline mirrors <see cref="SmartSuggester.SuggestSimilarNames" />: LINQ projection,
/// per-candidate lowercase strings, edit-distance matrix allocation, score filtering, and
/// descending score ordering. The N# candidate keeps the same score contract but returns candidate
/// indices into caller-owned buffers using reusable edit-distance rows and case-insensitive char
/// comparisons without lowercase string allocation.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceErrorSuggestionBenchmarks
{
    private const int LargeTypoCount = 2048;
    private const int MaxSuggestions = 3;
    private const int RepresentativeTypoCount = 256;

    private TypoSuggestionChecksumInto _nsharpSuggestionChecksum =
        (_, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _candidates = Array.Empty<string>();
    private Dictionary<string, int> _candidateIndices = new(StringComparer.Ordinal);
    private int[] _csharpResultCounts = Array.Empty<int>();
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int[] _csharpResultStarts = Array.Empty<int>();
    private int[] _currentDistances = Array.Empty<int>();
    private int[] _nsharpResultCounts = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _nsharpResultStarts = Array.Empty<int>();
    private int[] _previousDistances = Array.Empty<int>();
    private SmartSuggester _suggester = new(new List<string>());
    private string[] _typos = Array.Empty<string>();
    private int _typoCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpSuggestionChecksum =
            NSharpCompiledMethod.Bind<TypoSuggestionChecksumInto>(
                DogfoodCompilerSources.ErrorSuggestions,
                "TypoSuggestionChecksumInto");

        _typoCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeTypoCount
            : LargeTypoCount;
        _candidates = BuildCandidates(Corpus);
        _candidateIndices = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < _candidates.Length; i++)
        {
            _candidateIndices[_candidates[i]] = i;
        }

        _typos = BuildTypos(_typoCount);
        _suggester = new SmartSuggester(_candidates.ToList());
        _csharpResultStarts = new int[_typoCount];
        _csharpResultCounts = new int[_typoCount];
        _nsharpResultStarts = new int[_typoCount];
        _nsharpResultCounts = new int[_typoCount];
        _csharpResultIndices = new int[_typoCount * MaxSuggestions];
        _nsharpResultIndices = new int[_typoCount * MaxSuggestions];

        var maxCandidateLength = _candidates.Max(candidate => candidate.Length);
        _previousDistances = new int[maxCandidateLength + 1];
        _currentDistances = new int[maxCandidateLength + 1];

        var expectedChecksum = CSharpTypoSuggestions_QueryBatch();
        var actualChecksum = NSharpTypoSuggestions_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# typo-suggestion checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpResultStarts.SequenceEqual(_nsharpResultStarts) ||
            !_csharpResultCounts.SequenceEqual(_nsharpResultCounts))
        {
            throw new InvalidOperationException($"N# typo-suggestion segment mismatch for {Corpus}.");
        }

        var expectedTotal = _csharpResultCounts.Sum();
        for (var i = 0; i < expectedTotal; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# typo-suggestion mismatch for {Corpus} at result {i}: " +
                    $"expected {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTypoSuggestions_QueryBatch()
    {
        Array.Clear(_csharpResultIndices);

        var writeIndex = 0;
        for (var i = 0; i < _typos.Length; i++)
        {
            var suggestions = _suggester.SuggestSimilarNames(_typos[i], MaxSuggestions);
            _csharpResultStarts[i] = writeIndex;
            _csharpResultCounts[i] = suggestions.Count;
            for (var j = 0; j < suggestions.Count; j++)
            {
                _csharpResultIndices[writeIndex] = _candidateIndices[suggestions[j]];
                writeIndex++;
            }
        }

        return SuggestionChecksum(writeIndex, _csharpResultStarts, _csharpResultCounts, _csharpResultIndices);
    }

    [Benchmark]
    public int NSharpTypoSuggestions_QueryBatch() =>
        _nsharpSuggestionChecksum(
            _typos,
            _candidates,
            MaxSuggestions,
            _previousDistances,
            _currentDistances,
            _nsharpResultStarts,
            _nsharpResultCounts,
            _nsharpResultIndices);

    private static string[] BuildCandidates(CompilerLexerCorpus corpus)
    {
        var baseNames = new[]
        {
            "customer",
            "customers",
            "customerName",
            "customerEmail",
            "customerAddress",
            "order",
            "orders",
            "orderTotal",
            "orderDate",
            "orderStatus",
            "invoice",
            "invoiceNumber",
            "inventory",
            "inventoryCount",
            "product",
            "productName",
            "productPrice",
            "person",
            "personName",
            "people",
            "Console",
            "StringBuilder",
            "DateTime",
            "Dictionary",
            "CancellationToken",
            "HttpClient",
            "JsonSerializer",
            "WriteLine",
            "ReadLine",
            "ProcessAsync",
            "CalculateTotal",
            "ValidateInput",
            "InitializeCache",
            "LoadProject",
            "ResolveSymbol",
            "AnalyzeExpression",
            "GenerateDiagnostic",
            "FormatMessage",
            "GetVisibleVariables",
            "LookupIdentifier"
        };

        if (corpus == CompilerLexerCorpus.Representative)
            return baseNames;

        var names = new string[512];
        for (var i = 0; i < names.Length; i++)
        {
            var baseName = baseNames[i % baseNames.Length];
            names[i] = (i % 5) switch
            {
                0 => $"{baseName}{i}",
                1 => $"{baseName}Service{i % 97}",
                2 => $"{baseName}Repository{i % 89}",
                3 => $"{baseName}Handler{i % 83}",
                _ => $"{baseName}Context{i % 79}"
            };
        }

        return names;
    }

    private static string[] BuildTypos(int count)
    {
        var seeds = new[]
        {
            "custmer",
            "customerNmae",
            "ordrTotal",
            "invocieNumber",
            "inventryCount",
            "prodcutPrice",
            "persnName",
            "Consol",
            "StringBuiler",
            "DateTiem",
            "Dictionry",
            "CancelationToken",
            "HttpClinet",
            "JsonSerialzer",
            "WriteLin",
            "ProcessAsyn",
            "CalculateTotl",
            "ValidateInpt",
            "InitializeCahce",
            "LoadProjet",
            "ResolveSymbl",
            "AnalyzeExpresion",
            "GenerateDiagnostc",
            "FormatMesage",
            "LookupIdentifer"
        };

        var typos = new string[count];
        for (var i = 0; i < count; i++)
        {
            typos[i] = i % 17 == 0
                ? $"{seeds[i % seeds.Length]}{i % 11}"
                : seeds[i % seeds.Length];
        }

        return typos;
    }

    private static int SuggestionChecksum(
        int total,
        int[] starts,
        int[] counts,
        int[] indices)
    {
        var checksum = total;
        for (var i = 0; i < counts.Length; i++)
        {
            var start = starts[i];
            var count = counts[i];
            checksum += start * 7 + count * 97;
            for (var j = 0; j < count; j++)
            {
                checksum += indices[start + j] * 31 + (j + 1) * 17;
            }
        }

        return checksum;
    }

    private delegate int TypoSuggestionChecksumInto(
        string[] typos,
        string[] candidates,
        int maxSuggestions,
        int[] previousDistances,
        int[] currentDistances,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultIndices);
}
