using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for declared-type suffix lookup in the IL compiler. The C# baseline mirrors
/// the fallback shape in <c>TryLookupUniqueDeclaredTypeBySuffix</c>: scan dictionary keys for exact
/// or dotted-suffix matches, project values, distinct, take two, and materialize. The N# candidate
/// scans compact key/value-rank/query-width tail-hash arrays and returns the unique value rank directly.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceDeclaredTypeLookupBenchmarks
{
    private const int LargeTypeCount = 8192;
    private const int RepresentativeTypeCount = 1024;

    private Func<string[], int[], int[], string, int, int, int[], int> _nsharpDeclaredTypeLookupChecksum =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private Dictionary<string, int> _declaredTypes = new(StringComparer.Ordinal);
    private int _expectedRank;
    private int _queryTailHash;
    private int[] _rankWeights = Array.Empty<int>();
    private int[] _tailHashes = Array.Empty<int>();
    private string _query = string.Empty;
    private string[] _typeKeys = Array.Empty<string>();
    private int[] _valueRanks = Array.Empty<int>();
    private int _typeCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        DeclaredTypeLookupQueryKind.UniqueShortName,
        DeclaredTypeLookupQueryKind.UniqueTinyName,
        DeclaredTypeLookupQueryKind.ExactFullName,
        DeclaredTypeLookupQueryKind.Missing,
        DeclaredTypeLookupQueryKind.Ambiguous)]
    public DeclaredTypeLookupQueryKind Query { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _typeCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeTypeCount
            : LargeTypeCount;
        _nsharpDeclaredTypeLookupChecksum =
            NSharpCompiledMethod.Bind<Func<string[], int[], int[], string, int, int, int[], int>>(
                DogfoodCompilerSources.TypeLookup,
                "DeclaredTypeUniqueSuffixValueRankChecksum");

        _typeKeys = new string[_typeCount];
        _valueRanks = new int[_typeCount];
        _tailHashes = new int[_typeCount];
        _declaredTypes = new Dictionary<string, int>(_typeCount, StringComparer.Ordinal);
        _rankWeights = new int[_typeCount + 1];

        BuildDeclaredTypes();
        SelectQuery();
        RefreshTailHashes();

        var expected = CSharpDeclaredTypes_LookupUniqueSuffix();
        var actual = NSharpDeclaredTypes_LookupUniqueSuffix();
        if (expected != actual)
        {
            throw new InvalidOperationException(
                $"N# declared-type lookup checksum mismatch for {Corpus}/{Query}: " +
                $"expected {expected}, got {actual}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDeclaredTypes_LookupUniqueSuffix()
    {
        var matches = _declaredTypes
            .Where(entry => string.Equals(entry.Key, _query, StringComparison.Ordinal)
                || entry.Key.EndsWith("." + _query, StringComparison.Ordinal))
            .Select(entry => entry.Value)
            .Distinct()
            .Take(2)
            .ToArray();

        if (matches.Length == 0)
        {
            return 0;
        }

        if (matches.Length > 1)
        {
            return -1;
        }

        var rank = matches[0];
        return rank * 97 + _rankWeights[rank] * 31;
    }

    [Benchmark]
    public int NSharpDeclaredTypes_LookupUniqueSuffix() =>
        _nsharpDeclaredTypeLookupChecksum(
            _typeKeys,
            _valueRanks,
            _tailHashes,
            _query,
            _queryTailHash,
            _typeCount,
            _rankWeights);

    private void BuildDeclaredTypes()
    {
        for (var i = 0; i < _typeCount; i++)
        {
            var key = i switch
            {
                17 => "Project.Alpha.SharedCustomer",
                29 => "Project.Beta.SharedCustomer",
                43 => "Project.Tiny.Foo",
                _ => $"Project.Namespace{i % 251}.GeneratedType{i:D5}"
            };

            var rank = i + 1;
            _typeKeys[i] = key;
            _valueRanks[i] = rank;
            _rankWeights[rank] = key.Length;
            _declaredTypes.Add(key, rank);
        }
    }

    private void SelectQuery()
    {
        (_query, _expectedRank) = Query switch
        {
            DeclaredTypeLookupQueryKind.UniqueShortName => ("GeneratedType00042", 43),
            DeclaredTypeLookupQueryKind.UniqueTinyName => ("Foo", 44),
            DeclaredTypeLookupQueryKind.ExactFullName => (_typeKeys[_typeCount / 2], (_typeCount / 2) + 1),
            DeclaredTypeLookupQueryKind.Missing => ("MissingGeneratedType", 0),
            DeclaredTypeLookupQueryKind.Ambiguous => ("SharedCustomer", -1),
            _ => throw new ArgumentOutOfRangeException(nameof(Query))
        };

        var expected = _expectedRank > 0
            ? _expectedRank * 97 + _rankWeights[_expectedRank] * 31
            : _expectedRank;
        if (CSharpDeclaredTypes_LookupUniqueSuffix() != expected)
        {
            throw new InvalidOperationException($"Declared-type lookup test data is invalid for {Query}.");
        }
    }

    private void RefreshTailHashes()
    {
        var width = Math.Min(4, _query.Length);
        _queryTailHash = GetTailHash(_query, width);

        for (var i = 0; i < _typeCount; i++)
        {
            _tailHashes[i] = GetTailHash(_typeKeys[i], width);
        }
    }

    private static int GetTailHash(string text, int width)
    {
        var hash = 0;
        for (var offset = 0; offset < width && offset < text.Length; offset++)
        {
            hash = hash * 31 + text[text.Length - 1 - offset];
        }

        return hash;
    }
}

public enum DeclaredTypeLookupQueryKind
{
    UniqueShortName,
    UniqueTinyName,
    ExactFullName,
    Missing,
    Ambiguous
}
