using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for declared type-name candidate selection inside the IL compiler. The C#
/// baseline mirrors the fallback suffix/import disambiguation in GetDeclaredTypeNameCandidates:
/// enumerate declared names, filter blanks, distinct, materialize matching exact/suffix names,
/// materialize imported-namespace matches, then choose the unique imported match or unique match.
/// The N# candidate runs on compact unique-name/import-flag/query-width tail-hash arrays and
/// returns the selected unique-name index directly.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceDeclaredTypeNameCandidateBenchmarks
{
    private const int LargeRawNameCount = 8192;
    private const int RepresentativeRawNameCount = 1024;

    private readonly HashSet<string> _importedNamespaces = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _uniqueNameIndices = new(StringComparer.Ordinal);
    private Func<string[], int[], int[], string, int, int, int[], int> _nsharpDeclaredTypeNameCandidateChecksum =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _importedNamespaceFlags = Array.Empty<int>();
    private int[] _nameWeights = Array.Empty<int>();
    private string[] _rawDeclaredNames = Array.Empty<string>();
    private int _expectedIndex;
    private int _queryTailHash;
    private int _uniqueNameCount;
    private int[] _tailHashes = Array.Empty<int>();
    private string _query = string.Empty;
    private string[] _uniqueDeclaredNames = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        DeclaredTypeNameCandidateQueryKind.ImportedSuffix,
        DeclaredTypeNameCandidateQueryKind.UniqueSuffix,
        DeclaredTypeNameCandidateQueryKind.UniqueTinySuffix,
        DeclaredTypeNameCandidateQueryKind.ExactFullName,
        DeclaredTypeNameCandidateQueryKind.Ambiguous,
        DeclaredTypeNameCandidateQueryKind.Missing)]
    public DeclaredTypeNameCandidateQueryKind Query { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var rawNameCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeRawNameCount
            : LargeRawNameCount;
        _nsharpDeclaredTypeNameCandidateChecksum =
            NSharpCompiledMethod.Bind<Func<string[], int[], int[], string, int, int, int[], int>>(
                DogfoodCompilerSources.TypeLookup,
                "DeclaredTypeNameCandidateChecksum");

        BuildDeclaredNames(rawNameCount);
        SelectQuery();
        RefreshTailHashes();

        var expected = CSharpDeclaredTypeNames_SelectCandidate();
        var actual = NSharpDeclaredTypeNames_SelectCandidate();
        if (expected != actual)
        {
            throw new InvalidOperationException(
                $"N# declared type-name candidate checksum mismatch for {Corpus}/{Query}: " +
                $"expected {expected}, got {actual}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDeclaredTypeNames_SelectCandidate()
    {
        var declaredNames = _rawDeclaredNames
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        var matchingDeclaredNames = declaredNames
            .Where(name => string.Equals(name, _query, StringComparison.Ordinal)
                || name.EndsWith("." + _query, StringComparison.Ordinal))
            .ToArray();

        var importedNamespaceMatches = matchingDeclaredNames
            .Where(name =>
            {
                var namespaceName = GetNamespaceFromTypeName(name);
                return string.IsNullOrEmpty(namespaceName)
                    || _importedNamespaces.Contains(namespaceName);
            })
            .ToArray();

        string? selectedName = null;
        if (importedNamespaceMatches.Length == 1)
        {
            selectedName = importedNamespaceMatches[0];
        }
        else if (matchingDeclaredNames.Length == 1)
        {
            selectedName = matchingDeclaredNames[0];
        }

        if (selectedName == null)
        {
            return 0;
        }

        var index = _uniqueNameIndices[selectedName];
        return (index + 1) * 97 + _nameWeights[index] * 31;
    }

    [Benchmark]
    public int NSharpDeclaredTypeNames_SelectCandidate() =>
        _nsharpDeclaredTypeNameCandidateChecksum(
            _uniqueDeclaredNames,
            _importedNamespaceFlags,
            _tailHashes,
            _query,
            _queryTailHash,
            _uniqueNameCount,
            _nameWeights);

    private void BuildDeclaredNames(int rawNameCount)
    {
        _importedNamespaces.Clear();
        _importedNamespaces.Add("Project.Imported");

        var rawNames = new List<string>(rawNameCount + rawNameCount / 13);
        AddRawName(rawNames, "Project.Imported.Customer");
        AddRawName(rawNames, "Project.Other.Customer");
        AddRawName(rawNames, "Project.Local.Invoice");
        AddRawName(rawNames, "Project.Tiny.Foo");
        AddRawName(rawNames, "Project.Alpha.Shared");
        AddRawName(rawNames, "Project.Beta.Shared");

        for (var i = rawNames.Count; i < rawNameCount; i++)
        {
            var name = $"Project.Generated.Namespace{i % 251}.GeneratedType{i:D5}";
            AddRawName(rawNames, name);
            if (i % 13 == 0)
            {
                rawNames.Add(name);
            }
        }

        _rawDeclaredNames = rawNames.ToArray();
        BuildUniqueProjection();
    }

    private static void AddRawName(List<string> rawNames, string name)
    {
        rawNames.Add(name);
        rawNames.Add(name);
    }

    private void BuildUniqueProjection()
    {
        _uniqueNameIndices.Clear();
        var uniqueNames = new List<string>(_rawDeclaredNames.Length);
        foreach (var name in _rawDeclaredNames)
        {
            if (string.IsNullOrWhiteSpace(name) || _uniqueNameIndices.ContainsKey(name))
            {
                continue;
            }

            _uniqueNameIndices.Add(name, uniqueNames.Count);
            uniqueNames.Add(name);
        }

        _uniqueDeclaredNames = uniqueNames.ToArray();
        _uniqueNameCount = _uniqueDeclaredNames.Length;
        _importedNamespaceFlags = new int[_uniqueNameCount];
        _tailHashes = new int[_uniqueNameCount];
        _nameWeights = new int[_uniqueNameCount];

        for (var i = 0; i < _uniqueNameCount; i++)
        {
            var name = _uniqueDeclaredNames[i];
            var namespaceName = GetNamespaceFromTypeName(name);
            _importedNamespaceFlags[i] = string.IsNullOrEmpty(namespaceName)
                || _importedNamespaces.Contains(namespaceName)
                    ? 1
                    : 0;
            _nameWeights[i] = name.Length;
        }
    }

    private void SelectQuery()
    {
        (_query, _expectedIndex) = Query switch
        {
            DeclaredTypeNameCandidateQueryKind.ImportedSuffix => ("Customer", _uniqueNameIndices["Project.Imported.Customer"]),
            DeclaredTypeNameCandidateQueryKind.UniqueSuffix => ("Invoice", _uniqueNameIndices["Project.Local.Invoice"]),
            DeclaredTypeNameCandidateQueryKind.UniqueTinySuffix => ("Foo", _uniqueNameIndices["Project.Tiny.Foo"]),
            DeclaredTypeNameCandidateQueryKind.ExactFullName => (_uniqueDeclaredNames[_uniqueNameCount / 2], _uniqueNameCount / 2),
            DeclaredTypeNameCandidateQueryKind.Ambiguous => ("Shared", -1),
            DeclaredTypeNameCandidateQueryKind.Missing => ("MissingGeneratedType", -1),
            _ => throw new ArgumentOutOfRangeException(nameof(Query))
        };

        var expected = _expectedIndex >= 0
            ? (_expectedIndex + 1) * 97 + _nameWeights[_expectedIndex] * 31
            : 0;
        if (CSharpDeclaredTypeNames_SelectCandidate() != expected)
        {
            throw new InvalidOperationException($"Declared type-name candidate test data is invalid for {Query}.");
        }
    }

    private void RefreshTailHashes()
    {
        var width = Math.Min(4, _query.Length);
        _queryTailHash = GetTailHash(_query, width);

        for (var i = 0; i < _uniqueNameCount; i++)
        {
            _tailHashes[i] = GetTailHash(_uniqueDeclaredNames[i], width);
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

    private static string GetNamespaceFromTypeName(string typeName)
    {
        var separatorIndex = typeName.LastIndexOf('.');
        return separatorIndex >= 0 ? typeName[..separatorIndex] : string.Empty;
    }
}

public enum DeclaredTypeNameCandidateQueryKind
{
    ImportedSuffix,
    UniqueSuffix,
    UniqueTinySuffix,
    ExactFullName,
    Ambiguous,
    Missing
}
