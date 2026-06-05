using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for the IL compiler's remaining declared-type exact-name resolution path
/// (<c>ILCompiler.TryGetDeclaredTypeInfo</c> / <c>GetDeclaredTypeMetadataName</c>). The C# baseline
/// mirrors the fallback scan: enumerate declared type names and take the first ordinal exact-name
/// match (<c>EnumerateDeclaredTypes().FirstOrDefault(c =&gt; string.Equals(c.Name, typeName,
/// StringComparison.Ordinal))</c>), returning the matched index. The N# candidate runs the same
/// first-match scan over compact name/tail-hash arrays and returns the selected 1-based index
/// directly, so no string is materialized across the boundary.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceTypeLookupBenchmarks
{
    private const int LargeDeclaredNameCount = 8192;
    private const int RepresentativeDeclaredNameCount = 1024;

    private Func<string[], int[], string, int, int, int[], int> _nsharpDeclaredTypeExactNameChecksum =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _nameWeights = Array.Empty<int>();
    private int[] _tailHashes = Array.Empty<int>();
    private string[] _declaredNames = Array.Empty<string>();
    private int _declaredNameCount;
    private int _expectedIndex;
    private int _queryTailHash;
    private string _query = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        DeclaredTypeExactNameQueryKind.NestedEarly,
        DeclaredTypeExactNameQueryKind.NestedMiddle,
        DeclaredTypeExactNameQueryKind.NestedLate,
        DeclaredTypeExactNameQueryKind.Missing)]
    public DeclaredTypeExactNameQueryKind Query { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var declaredNameCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDeclaredNameCount
            : LargeDeclaredNameCount;
        _nsharpDeclaredTypeExactNameChecksum =
            NSharpCompiledMethod.Bind<Func<string[], int[], string, int, int, int[], int>>(
                DogfoodCompilerSources.TypeLookup,
                "DeclaredTypeExactNameFirstChecksum");

        BuildDeclaredNames(declaredNameCount);
        SelectQuery();
        RefreshTailHashes();

        var expected = CSharpDeclaredType_ResolveExactName();
        var actual = NSharpDeclaredType_ResolveExactName();
        if (expected != actual)
        {
            throw new InvalidOperationException(
                $"N# declared-type exact-name checksum mismatch for {Corpus}/{Query}: " +
                $"expected {expected}, got {actual}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDeclaredType_ResolveExactName()
    {
        var matchIndex = -1;
        for (var i = 0; i < _declaredNameCount; i++)
        {
            if (string.Equals(_declaredNames[i], _query, StringComparison.Ordinal))
            {
                matchIndex = i;
                break;
            }
        }

        if (matchIndex < 0)
        {
            return 0;
        }

        return (matchIndex + 1) * 97 + _nameWeights[matchIndex] * 31;
    }

    [Benchmark]
    public int NSharpDeclaredType_ResolveExactName() =>
        _nsharpDeclaredTypeExactNameChecksum(
            _declaredNames,
            _tailHashes,
            _query,
            _queryTailHash,
            _declaredNameCount,
            _nameWeights);

    private void BuildDeclaredNames(int declaredNameCount)
    {
        // Model EnumerateDeclaredTypes(): top-level and nested type keys for a compilation unit,
        // with deeply nested keys (dotted) interleaved among many generated top-level names.
        var names = new List<string>(declaredNameCount);
        names.Add("Project.Local.Container");
        names.Add("Project.Local.Container.Inner");
        names.Add("Project.Local.Container.Inner.Leaf");

        for (var i = names.Count; i < declaredNameCount; i++)
        {
            var ns = $"Namespace{i % 251}";
            var name = $"Project.Generated.{ns}.GeneratedType{i:D5}";
            names.Add(name);
            if (i % 17 == 0)
            {
                names.Add($"{name}.Nested");
            }
        }

        _declaredNames = names.ToArray();
        _declaredNameCount = _declaredNames.Length;
        _tailHashes = new int[_declaredNameCount];
        _nameWeights = new int[_declaredNameCount];
        for (var i = 0; i < _declaredNameCount; i++)
        {
            _nameWeights[i] = _declaredNames[i].Length;
        }
    }

    private void SelectQuery()
    {
        (_query, _expectedIndex) = Query switch
        {
            DeclaredTypeExactNameQueryKind.NestedEarly => ("Project.Local.Container.Inner", 1),
            DeclaredTypeExactNameQueryKind.NestedMiddle => (
                _declaredNames[_declaredNameCount / 2],
                _declaredNameCount / 2),
            DeclaredTypeExactNameQueryKind.NestedLate => (
                _declaredNames[_declaredNameCount - 1],
                _declaredNameCount - 1),
            DeclaredTypeExactNameQueryKind.Missing => ("Project.Missing.GeneratedTypeXXXXX", -1),
            _ => throw new ArgumentOutOfRangeException(nameof(Query))
        };

        // Guard against accidental earlier duplicates skewing the expected index.
        for (var i = 0; i < _expectedIndex; i++)
        {
            if (string.Equals(_declaredNames[i], _query, StringComparison.Ordinal))
            {
                _expectedIndex = i;
                break;
            }
        }

        var expected = _expectedIndex >= 0
            ? (_expectedIndex + 1) * 97 + _query.Length * 31
            : 0;

        var matchIndex = -1;
        for (var i = 0; i < _declaredNameCount; i++)
        {
            if (string.Equals(_declaredNames[i], _query, StringComparison.Ordinal))
            {
                matchIndex = i;
                break;
            }
        }

        var actual = matchIndex < 0 ? 0 : (matchIndex + 1) * 97 + _nameWeights[matchIndex] * 31;
        if (actual != expected)
        {
            throw new InvalidOperationException($"Declared-type exact-name test data is invalid for {Query}.");
        }
    }

    private void RefreshTailHashes()
    {
        var width = Math.Min(4, _query.Length);
        _queryTailHash = GetTailHash(_query, width);

        for (var i = 0; i < _declaredNameCount; i++)
        {
            _tailHashes[i] = GetTailHash(_declaredNames[i], width);
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

public enum DeclaredTypeExactNameQueryKind
{
    NestedEarly,
    NestedMiddle,
    NestedLate,
    Missing
}
