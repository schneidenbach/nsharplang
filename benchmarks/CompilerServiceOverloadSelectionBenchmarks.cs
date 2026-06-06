using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for the IL compiler declared-method overload/candidate ranking. The C# baseline
/// mirrors <c>ILCompiler.BindDeclaredMethodCall</c> over an in-memory overload set: <c>.ToList()</c>
/// materialization of the overloads, a per-candidate <c>GetParameters().Select(...).ToArray()</c>
/// parameter-type projection, and the four-level tie-break (score &gt; non-generic &gt; non-params
/// &gt; fewer-defaults) that allocates a bound-call record per improving candidate.
///
/// The N# candidate represents the overload set as compact primitive columns (per-candidate
/// validity, score, generic/params flags, defaults-used, plus a flattened parameter-type-id table
/// with per-candidate offsets/counts) computed once by the host, then runs the same first-wins-on-tie
/// ranking over every call site in one compiled batch loop with no per-candidate allocation.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceOverloadSelectionBenchmarks
{
    private const int RepresentativeCallCount = 1024;
    private const int LargeCallCount = 8192;

    private Func<int[], int[], int[], int[], int[], int[], int[], int, int[], int> _nsharpOverloadSelectBatchChecksumInto =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private OverloadCandidate[] _candidates = Array.Empty<OverloadCandidate>();
    private CallSite[] _callSites = Array.Empty<CallSite>();

    // Compact candidate columns shared across all call sites.
    private int[] _validFlags = Array.Empty<int>();
    private int[] _scores = Array.Empty<int>();
    private int[] _genericFlags = Array.Empty<int>();
    private int[] _paramsFlags = Array.Empty<int>();
    private int[] _defaultsUsed = Array.Empty<int>();
    private int[] _callOffsets = Array.Empty<int>();
    private int[] _callCounts = Array.Empty<int>();
    private int[] _resultIndices = Array.Empty<int>();
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int _callCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpOverloadSelectBatchChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int[], int[], int[], int[], int, int[], int>>(
                DogfoodCompilerSources.OverloadCandidates,
                "OverloadSelectBatchChecksumInto");

        _callCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeCallCount
            : LargeCallCount;

        BuildCorpus();

        var expected = CSharpOverloadSelection_BindDeclaredMethodCall();
        var actual = NSharpOverloadSelection_CompactBatch();
        if (expected != actual)
        {
            throw new InvalidOperationException(
                $"N# overload-selection checksum mismatch for {Corpus}: expected {expected}, got {actual}.");
        }

        for (var i = 0; i < _callCount; i++)
        {
            if (_csharpResultIndices[i] != _resultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# overload-selection index mismatch for {Corpus} at call {i}: " +
                    $"expected {_csharpResultIndices[i]}, got {_resultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpOverloadSelection_BindDeclaredMethodCall()
    {
        var checksum = 0;
        var resolved = 0;
        for (var c = 0; c < _callCount; c++)
        {
            var call = _callSites[c];

            // Mirror BindDeclaredMethodCall: materialize the overload set, project parameter types per
            // candidate, then run the four-level tie-break with a bound-call record per improvement.
            var overloadList = _candidates
                .Skip(call.Offset)
                .Take(call.Count)
                .ToList();

            BoundCandidate? best = null;
            var bestScore = -1;
            var bestUsesParams = true;
            var bestDefaultsUsed = int.MaxValue;
            var bestIsGeneric = true;
            var bestLocalIndex = -1;

            for (var localIndex = 0; localIndex < overloadList.Count; localIndex++)
            {
                var overload = overloadList[localIndex];
                if (!overload.Valid)
                {
                    continue;
                }

                // Re-project the parameter types per candidate, as the production binder does via
                // GetParameters().Select(...).ToArray().
                var parameterTypes = overload.ParameterTypeIds
                    .Select(static id => id)
                    .ToArray();

                var score = overload.Score;
                var usesParams = overload.UsesParams;
                var defaultsUsed = overload.DefaultsUsed;
                var isGeneric = overload.IsGeneric;

                if (best == null
                    || score > bestScore
                    || (score == bestScore && bestIsGeneric && !isGeneric)
                    || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams && !usesParams)
                    || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams == usesParams
                        && defaultsUsed < bestDefaultsUsed))
                {
                    best = new BoundCandidate(score, isGeneric, usesParams, defaultsUsed, parameterTypes.Length);
                    bestScore = score;
                    bestUsesParams = usesParams;
                    bestDefaultsUsed = defaultsUsed;
                    bestIsGeneric = isGeneric;
                    bestLocalIndex = localIndex;
                }
            }

            _csharpResultIndices[c] = bestLocalIndex;
            if (best != null)
            {
                resolved++;
                checksum += (c + 1) * 97
                    + (bestLocalIndex + 1) * 31
                    + best.Score * 17
                    + (best.IsGeneric ? 1 : 0) * 13
                    + (best.UsesParams ? 1 : 0) * 7
                    + best.DefaultsUsed * 3;
            }
        }

        return resolved + checksum;
    }

    [Benchmark]
    public int NSharpOverloadSelection_CompactBatch() =>
        _nsharpOverloadSelectBatchChecksumInto(
            _validFlags,
            _scores,
            _genericFlags,
            _paramsFlags,
            _defaultsUsed,
            _callOffsets,
            _callCounts,
            _callCount,
            _resultIndices);

    private void BuildCorpus()
    {
        var candidates = new List<OverloadCandidate>();
        _callSites = new CallSite[_callCount];
        _callOffsets = new int[_callCount];
        _callCounts = new int[_callCount];
        _resultIndices = new int[_callCount];
        _csharpResultIndices = new int[_callCount];

        for (var c = 0; c < _callCount; c++)
        {
            var offset = candidates.Count;

            // Representative overload groups: 1-5 overloads, mixed arity, mixed generic/params/defaults.
            var groupSize = 1 + ((c * 7) % 5);
            for (var k = 0; k < groupSize; k++)
            {
                var arity = (c + k) % 4;
                var paramTypeIds = new int[arity];
                for (var p = 0; p < arity; p++)
                {
                    paramTypeIds[p] = ((c + k + p) % 11) + 1;
                }

                // Mix the rank columns so the tie-break exercises every level deterministically.
                var valid = ((c + k) % 9) != 0; // some candidates fail to bind
                var score = ((c * 3) + (k * 2)) % 7;
                var isGeneric = ((c + k) % 3) == 0;
                var usesParams = ((c + 2 * k) % 4) == 0;
                var defaultsUsed = (c + k) % 3;

                candidates.Add(new OverloadCandidate(
                    valid,
                    score,
                    isGeneric,
                    usesParams,
                    defaultsUsed,
                    paramTypeIds));
            }

            _callSites[c] = new CallSite(offset, groupSize);
            _callOffsets[c] = offset;
            _callCounts[c] = groupSize;
        }

        _candidates = candidates.ToArray();

        var total = _candidates.Length;
        _validFlags = new int[total];
        _scores = new int[total];
        _genericFlags = new int[total];
        _paramsFlags = new int[total];
        _defaultsUsed = new int[total];

        for (var i = 0; i < total; i++)
        {
            var candidate = _candidates[i];
            _validFlags[i] = candidate.Valid ? 1 : 0;
            _scores[i] = candidate.Score;
            _genericFlags[i] = candidate.IsGeneric ? 1 : 0;
            _paramsFlags[i] = candidate.UsesParams ? 1 : 0;
            _defaultsUsed[i] = candidate.DefaultsUsed;
        }
    }

    private sealed record OverloadCandidate(
        bool Valid,
        int Score,
        bool IsGeneric,
        bool UsesParams,
        int DefaultsUsed,
        int[] ParameterTypeIds);

    private sealed record BoundCandidate(int Score, bool IsGeneric, bool UsesParams, int DefaultsUsed, int ParameterCount);

    private readonly record struct CallSite(int Offset, int Count);
}
