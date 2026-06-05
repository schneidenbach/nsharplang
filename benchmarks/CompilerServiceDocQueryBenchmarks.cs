using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for the candidate ranking kernel inside <c>nlc query doc</c> type lookup.
///
/// The C# baseline mirrors the existing post-scoring selection shape in <c>DocQuery.SelectBestType</c>:
/// order by descending match score, then namespace length, then full name with ordinal-ignore-case
/// comparison, and take the first result. The N# candidate runs after the host has projected the
/// reflection candidates into compact score/namespace/name arrays and selects the best index with a
/// single allocation-free scan.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceDocQueryBestTypeBenchmarks
{
    private const int LargeCandidateCount = 8192;
    private const int RepresentativeCandidateCount = 1024;

    private DocQueryBestTypeIndex _nsharpBestTypeIndex =
        (_, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private DocTypeCandidate[] _candidates = Array.Empty<DocTypeCandidate>();
    private string[] _fullNames = Array.Empty<string>();
    private int[] _namespaceLengths = Array.Empty<int>();
    private int[] _scores = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var candidateCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeCandidateCount
            : LargeCandidateCount;

        _nsharpBestTypeIndex = NSharpCompiledMethod.Bind<DocQueryBestTypeIndex>(
            DogfoodCompilerSources.CodeIntelligenceDocQuery,
            "DocQueryBestTypeIndex");

        _candidates = BuildCandidates(candidateCount);
        _scores = new int[candidateCount];
        _namespaceLengths = new int[candidateCount];
        _fullNames = new string[candidateCount];

        for (var i = 0; i < candidateCount; i++)
        {
            var candidate = _candidates[i];
            _scores[i] = candidate.Score;
            _namespaceLengths[i] = candidate.NamespaceLength;
            _fullNames[i] = candidate.FullName;
        }

        var expectedIndex = CSharpDocQuery_SelectBestTypeIndex();
        var actualIndex = NSharpDocQuery_SelectBestTypeIndex();
        if (expectedIndex != actualIndex)
        {
            throw new InvalidOperationException(
                $"N# doc-query best-type mismatch for {Corpus}: expected index {expectedIndex}, got {actualIndex}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDocQuery_SelectBestTypeIndex()
    {
        var best = _candidates
            .OrderByDescending(candidate => candidate.Score)
            .ThenBy(candidate => candidate.NamespaceLength)
            .ThenBy(candidate => candidate.FullName, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();

        return best?.Index ?? -1;
    }

    [Benchmark]
    public int NSharpDocQuery_SelectBestTypeIndex() =>
        _nsharpBestTypeIndex(_scores, _namespaceLengths, _fullNames, _candidates.Length);

    private static DocTypeCandidate[] BuildCandidates(int count)
    {
        var namespaces = new[]
        {
            "System",
            "System.Collections",
            "System.Collections.Generic",
            "System.IO",
            "System.Linq",
            "System.Net.Http",
            "System.Text",
            "System.Threading.Tasks",
            "Microsoft.Extensions.DependencyInjection",
            "Microsoft.CodeAnalysis",
            "NSharpLang.Compiler.CodeIntelligence",
            "NSharpLang.Compiler.Symbols"
        };

        var names = new[]
        {
            "Console",
            "List",
            "Dictionary",
            "Enumerable",
            "Regex",
            "StringBuilder",
            "HttpClient",
            "Task",
            "CancellationToken",
            "Compilation",
            "SemanticModel",
            "DocQuery",
            "CompletionItem",
            "DiagnosticResult",
            "SymbolResult",
            "ProjectSnapshot"
        };

        var candidates = new DocTypeCandidate[count];
        for (var i = 0; i < count; i++)
        {
            var ns = namespaces[(i * 7 + i / 13) % namespaces.Length];
            var name = names[(i * 11 + i / 17) % names.Length];
            var score = 200 + ((i * 37 + i / 5) % 850);
            if (i % 29 == 0)
            {
                score += 300;
            }

            candidates[i] = new DocTypeCandidate(
                i,
                score,
                ns.Length,
                $"{ns}.{name}{i % 257}");
        }

        if (count > 8)
        {
            candidates[3] = new DocTypeCandidate(3, 2400, "System".Length, "System.ConsoleZ");
            candidates[count / 2] = new DocTypeCandidate(count / 2, 2400, "System".Length, "System.ConsoleA");
        }

        return candidates;
    }

    private sealed record DocTypeCandidate(
        int Index,
        int Score,
        int NamespaceLength,
        string FullName);

    private delegate int DocQueryBestTypeIndex(
        int[] scores,
        int[] namespaceLengths,
        string[] fullNames,
        int count);
}

/// <summary>
/// Dogfood benchmark for member ordering inside <c>nlc query doc</c> type descriptions.
///
/// The C# baseline mirrors <c>DocQuery.GetTypeMembers</c>: order by member kind, then by member
/// name using ordinal-ignore-case comparison, and materialize the array. The N# candidate runs
/// after the host has projected fixed member-kind ranks and exact .NET name ranks, then returns
/// ordered source indices through caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceDocQueryMemberOrderingBenchmarks
{
    private const int LargeMemberCount = 8192;
    private const int RepresentativeMemberCount = 1024;

    private DocQueryMemberOrderChecksumInto _nsharpMemberOrderChecksumInto =
        (_, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _kindCounts = Array.Empty<int>();
    private int[] _kindOffsets = Array.Empty<int>();
    private int[] _kindRanks = Array.Empty<int>();
    private DocMemberEntry[] _members = Array.Empty<DocMemberEntry>();
    private int[] _nameCounts = Array.Empty<int>();
    private int[] _nameOffsets = Array.Empty<int>();
    private int[] _nameRanks = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _tempIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var memberCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeMemberCount
            : LargeMemberCount;

        _nsharpMemberOrderChecksumInto = NSharpCompiledMethod.Bind<DocQueryMemberOrderChecksumInto>(
            DogfoodCompilerSources.CodeIntelligenceDocQuery,
            "DocQueryMemberOrderChecksumInto");

        _members = BuildMembers(memberCount);
        _kindRanks = new int[memberCount];
        _nameRanks = new int[memberCount];
        _nameCounts = new int[memberCount + 1];
        _nameOffsets = new int[memberCount + 1];
        _kindCounts = new int[16];
        _kindOffsets = new int[16];
        _tempIndices = new int[memberCount];
        _nsharpResultIndices = new int[memberCount];

        BuildCompactRanks();

        var expectedChecksum = CSharpDocQuery_OrderMembers();
        var actualChecksum = NSharpDocQuery_OrderMembers();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# doc-query member-order checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expected = OrderedMembersWithCSharp();
        for (var i = 0; i < expected.Length; i++)
        {
            if (_nsharpResultIndices[i] != expected[i].Index)
            {
                throw new InvalidOperationException(
                    $"N# doc-query member-order mismatch for {Corpus} at ordered item {i}: " +
                    $"expected source index {expected[i].Index}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDocQuery_OrderMembers()
    {
        var ordered = OrderedMembersWithCSharp();
        return ChecksumOrderedMembers(ordered);
    }

    [Benchmark]
    public int NSharpDocQuery_OrderMembers() =>
        _nsharpMemberOrderChecksumInto(
            _kindRanks,
            _nameRanks,
            _nameCounts,
            _nameOffsets,
            _kindCounts,
            _kindOffsets,
            _tempIndices,
            _nsharpResultIndices);

    private void BuildCompactRanks()
    {
        var names = new string[_members.Length];
        for (var i = 0; i < _members.Length; i++)
        {
            var member = _members[i];
            _kindRanks[i] = GetDocMemberKindRank(member.Kind);
            names[i] = member.Name;
        }

        Array.Sort(names, StringComparer.OrdinalIgnoreCase);
        var nameRanks = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var rank = 1;
        foreach (var name in names)
        {
            if (nameRanks.ContainsKey(name))
                continue;

            nameRanks.Add(name, rank);
            rank++;
        }

        for (var i = 0; i < _members.Length; i++)
        {
            _nameRanks[i] = nameRanks[_members[i].Name];
        }
    }

    private DocMemberEntry[] OrderedMembersWithCSharp() =>
        _members
            .OrderBy(member => member.Kind)
            .ThenBy(member => member.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private int ChecksumOrderedMembers(DocMemberEntry[] ordered)
    {
        var checksum = ordered.Length;
        for (var i = 0; i < ordered.Length; i++)
        {
            var index = ordered[i].Index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _kindRanks[index] * 17 + _nameRanks[index] * 13;
        }

        return checksum;
    }

    private static DocMemberEntry[] BuildMembers(int count)
    {
        var names = new[]
        {
            "Add",
            "Clear",
            "Contains",
            "CopyTo",
            "Count",
            "Create",
            "Dispose",
            "Equals",
            "GetEnumerator",
            "GetHashCode",
            "Item",
            "Remove",
            "ToArray",
            "ToString",
            "TryGetValue",
            "Value"
        };
        var kinds = new[]
        {
            "method",
            "property",
            "field",
            "event",
            "constructor",
            "nested type"
        };

        var members = new DocMemberEntry[count];
        for (var i = 0; i < count; i++)
        {
            var kind = kinds[(i * 5 + i / 11) % kinds.Length];
            var baseName = names[(i * 7 + i / 13) % names.Length];
            var name = i % 19 == 0
                ? baseName
                : $"{baseName}{i % 251}";
            if (i % 41 == 0)
            {
                name = name.ToUpperInvariant();
            }

            members[i] = new DocMemberEntry(i, name, kind);
        }

        return members;
    }

    internal static int GetDocMemberKindRank(string kind) =>
        kind switch
        {
            "constructor" => 1,
            "event" => 2,
            "field" => 3,
            "method" => 4,
            "nested type" => 5,
            "property" => 6,
            _ => 0
        };

    private sealed record DocMemberEntry(int Index, string Name, string Kind);

    private delegate int DocQueryMemberOrderChecksumInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] resultIndices);
}
