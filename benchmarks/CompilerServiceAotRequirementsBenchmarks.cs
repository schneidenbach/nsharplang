using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Performance;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for AOT requirement grouping before public surface attribute emission.
/// The C# baseline mirrors <c>AotRequirements.FromBlockers</c>: filter public blockers, group by
/// enclosing declaration, aggregate AOT flags, distinct/sort construct names, and take the first
/// three constructs for the stable annotation message. The N# candidate runs after the host has
/// assigned compact declaration ranks and ordinal construct ranks, then emits grouped flags and
/// sorted construct rank samples through caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceAotRequirementGroupingBenchmarks
{
    private const int LargeBlockerCount = 8192;
    private const int RepresentativeBlockerCount = 1024;

    private AotBlocker[] _blockers = Array.Empty<AotBlocker>();
    private int[] _constructRanks = Array.Empty<int>();
    private int[] _constructSeenByDeclaration = Array.Empty<int>();
    private Dictionary<string, int> _constructRanksByName = new(StringComparer.Ordinal);
    private int[] _declarationCounts = Array.Empty<int>();
    private int[] _declarationRanks = Array.Empty<int>();
    private Dictionary<string, int> _declarationRanksByName = new(StringComparer.Ordinal);
    private int[] _kindIds = Array.Empty<int>();
    private Func<int[], int[], int[], int, int, int[], int[], int[], int[], int[], int[], int[], int[], int[], int[], int> _nsharpAotRequirementChecksumInto =
        (_, _, _, _, _, _, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _requiresDynamicByRank = Array.Empty<int>();
    private int[] _requiresUnreferencedByRank = Array.Empty<int>();
    private int[] _resultConstructCounts = Array.Empty<int>();
    private int[] _resultConstructRanks = Array.Empty<int>();
    private int[] _resultConstructStarts = Array.Empty<int>();
    private int[] _resultDeclarationRanks = Array.Empty<int>();
    private int[] _resultRequiresDynamic = Array.Empty<int>();
    private int[] _resultRequiresUnreferenced = Array.Empty<int>();
    private int _uniqueConstructCount;
    private int _uniqueDeclarationCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var blockerCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeBlockerCount
            : LargeBlockerCount;
        _nsharpAotRequirementChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int, int, int[], int[], int[], int[], int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.AotRequirements,
                "AotRequirementGroupChecksumInto");

        _blockers = BuildBlockers(blockerCount);
        BuildRanks();
        _declarationCounts = new int[_uniqueDeclarationCount + 1];
        _requiresUnreferencedByRank = new int[_uniqueDeclarationCount + 1];
        _requiresDynamicByRank = new int[_uniqueDeclarationCount + 1];
        _constructSeenByDeclaration = new int[(_uniqueDeclarationCount + 1) * (_uniqueConstructCount + 1)];
        _resultDeclarationRanks = new int[_uniqueDeclarationCount];
        _resultRequiresUnreferenced = new int[_uniqueDeclarationCount];
        _resultRequiresDynamic = new int[_uniqueDeclarationCount];
        _resultConstructStarts = new int[_uniqueDeclarationCount];
        _resultConstructCounts = new int[_uniqueDeclarationCount];
        _resultConstructRanks = new int[_uniqueDeclarationCount * 3];

        var expectedChecksum = CSharpAotRequirements_GroupPublicBlockers();
        var actualChecksum = NSharpAotRequirements_GroupPublicBlockers();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# AOT requirement grouping checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpAotRequirements_GroupPublicBlockers()
    {
        var grouped = _blockers
            .Where(blocker => blocker.IsOnPublicSurface && !string.IsNullOrEmpty(blocker.EnclosingDeclaration))
            .GroupBy(blocker => blocker.EnclosingDeclaration!, StringComparer.Ordinal);

        var checksum = 0;
        var groupCount = 0;
        foreach (var group in grouped)
        {
            var requiresUnreferenced = group.Any(blocker => blocker.Kind == AotSafetyKind.MetadataRequired);
            var requiresDynamic = group.Any(blocker => blocker.Kind is AotSafetyKind.DynamicCodeRequired or AotSafetyKind.ExpressionTreeRequired);
            var constructRanks = group
                .Select(blocker => blocker.Construct)
                .Distinct(StringComparer.Ordinal)
                .OrderBy(construct => construct, StringComparer.Ordinal)
                .Take(3)
                .Select(construct => _constructRanksByName[construct])
                .ToArray();

            checksum += (groupCount + 1) * 97
                + _declarationRanksByName[group.Key] * 31
                + (requiresUnreferenced ? 1 : 0) * 17
                + (requiresDynamic ? 1 : 0) * 13
                + constructRanks.Length * 7;
            for (var offset = 0; offset < constructRanks.Length; offset++)
            {
                checksum += constructRanks[offset] * (offset + 1) * 11;
            }

            groupCount++;
        }

        return checksum + groupCount;
    }

    [Benchmark]
    public int NSharpAotRequirements_GroupPublicBlockers() =>
        _nsharpAotRequirementChecksumInto(
            _declarationRanks,
            _kindIds,
            _constructRanks,
            _uniqueDeclarationCount,
            _uniqueConstructCount,
            _declarationCounts,
            _requiresUnreferencedByRank,
            _requiresDynamicByRank,
            _constructSeenByDeclaration,
            _resultDeclarationRanks,
            _resultRequiresUnreferenced,
            _resultRequiresDynamic,
            _resultConstructStarts,
            _resultConstructCounts,
            _resultConstructRanks);

    private void BuildRanks()
    {
        _declarationRanks = new int[_blockers.Length];
        _kindIds = new int[_blockers.Length];
        _constructRanks = new int[_blockers.Length];
        _declarationRanksByName = new Dictionary<string, int>(StringComparer.Ordinal);
        _constructRanksByName = new Dictionary<string, int>(StringComparer.Ordinal);
        var constructs = new List<string>();

        for (var i = 0; i < _blockers.Length; i++)
        {
            var blocker = _blockers[i];
            if (!blocker.IsOnPublicSurface || string.IsNullOrEmpty(blocker.EnclosingDeclaration))
            {
                continue;
            }

            if (!_declarationRanksByName.TryGetValue(blocker.EnclosingDeclaration, out var declarationRank))
            {
                declarationRank = _declarationRanksByName.Count + 1;
                _declarationRanksByName.Add(blocker.EnclosingDeclaration, declarationRank);
            }

            _declarationRanks[i] = declarationRank;
            _kindIds[i] = (int)blocker.Kind;
            if (!_constructRanksByName.ContainsKey(blocker.Construct))
            {
                _constructRanksByName.Add(blocker.Construct, 0);
                constructs.Add(blocker.Construct);
            }
        }

        constructs.Sort(StringComparer.Ordinal);
        for (var i = 0; i < constructs.Count; i++)
        {
            _constructRanksByName[constructs[i]] = i + 1;
        }

        for (var i = 0; i < _blockers.Length; i++)
        {
            if (_declarationRanks[i] != 0)
            {
                _constructRanks[i] = _constructRanksByName[_blockers[i].Construct];
            }
        }

        _uniqueDeclarationCount = _declarationRanksByName.Count;
        _uniqueConstructCount = constructs.Count;
    }

    private static AotBlocker[] BuildBlockers(int count)
    {
        var constructs = new[]
        {
            "Activator.CreateInstance",
            "Expression.Compile",
            "GetCustomAttributes",
            "GetField",
            "GetFields",
            "GetMethod",
            "GetMethods",
            "GetProperty",
            "GetRuntimeMethod",
            "GetType",
            "MakeGenericMethod",
            "MakeGenericType"
        };

        var blockers = new AotBlocker[count];
        var declarationCount = Math.Max(8, count / 8);
        for (var i = 0; i < count; i++)
        {
            var ignored = i % 17 == 0;
            var missingDeclaration = i % 43 == 0;
            var kind = (i % 5) switch
            {
                0 => AotSafetyKind.MetadataRequired,
                1 => AotSafetyKind.DynamicCodeRequired,
                2 => AotSafetyKind.ExpressionTreeRequired,
                3 => AotSafetyKind.MetadataRequired,
                _ => AotSafetyKind.DynamicCodeRequired
            };

            blockers[i] = new AotBlocker(
                kind,
                $"src/File{i % 19}.nl",
                i % 200 + 1,
                i % 80 + 1,
                constructs[(i * 7) % constructs.Length].Length,
                constructs[(i * 7) % constructs.Length],
                ignored ? AbiBoundary.ClrInternal : AbiBoundary.ClrPublic,
                missingDeclaration ? null : $"PublicApi{i % declarationCount}");
        }

        return blockers;
    }
}
