using System;
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
