using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for analyzer overload parameter-signature distinctness. The C# baseline mirrors
/// the current <c>HasDistinctParameterSignature</c>/<c>ParameterSignaturesMatch</c> path: for each
/// candidate overload, walk the existing overload group, compare parameter arity, and on an arity
/// match build the per-parameter type signature strings (<c>GetParameterTypeSignature</c>) and
/// compare them with ordinal string equality. The N# candidate runs after the analyzer has projected
/// each parameter type to a stable integer rank (distinct type signatures map to distinct ranks) and
/// compares compact rank rows over caller-owned buffers via a single integer scan.
///
/// This is an honest comparison of the distinctness DECISION only. The string-formatting helpers
/// (<c>GetParameterTypeSignature</c> recursion over generics/tuples) are intentionally out of scope:
/// they are string-dominated. The benchmark models the realistic analyzer shape where the candidate
/// distinctness check is invoked repeatedly while merging overloads into a method group.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceAnalyzerOverloadSignatureBenchmarks
{
    private const int RepresentativeCandidateCount = 256;
    private const int LargeCandidateCount = 4096;
    private const int RepresentativeExistingCount = 8;
    private const int LargeExistingCount = 64;
    private const int MaxParameters = 6;
    private const int DistinctTypeCount = 24;

    private Func<int[], int[], int[], int, int[], int[], int[], int, int[], int> _nsharpDistinctChecksumInto =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    // C# baseline shape: existing overloads as parameter-type-signature string rows, candidates the same.
    private string[][] _existingSignatures = Array.Empty<string[]>();
    private string[][] _candidateSignatures = Array.Empty<string[]>();
    private int[] _csharpResults = Array.Empty<int>();

    // N# shape: packed type-rank rows + per-row offsets/lengths.
    private int[] _existingRanks = Array.Empty<int>();
    private int[] _existingOffsets = Array.Empty<int>();
    private int[] _existingLengths = Array.Empty<int>();
    private int[] _candidateRanks = Array.Empty<int>();
    private int[] _candidateOffsets = Array.Empty<int>();
    private int[] _candidateLengths = Array.Empty<int>();
    private int[] _nsharpResults = Array.Empty<int>();

    private int _candidateCount;
    private int _existingCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _candidateCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeCandidateCount
            : LargeCandidateCount;
        _existingCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeExistingCount
            : LargeExistingCount;

        _nsharpDistinctChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int, int[], int[], int[], int, int[], int>>(
                DogfoodCompilerSources.AnalyzerExhaustiveness,
                "AnalyzerOverloadSignatureDistinctChecksumInto");

        BuildExisting();
        BuildCandidates();

        _csharpResults = new int[_candidateCount];
        _nsharpResults = new int[_candidateCount];

        var expectedChecksum = CSharpOverloadDistinct_Checksum();
        var actualChecksum = NSharpOverloadDistinct_Checksum();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# overload distinctness checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _candidateCount; i++)
        {
            if (_csharpResults[i] != _nsharpResults[i])
            {
                throw new InvalidOperationException(
                    $"N# overload distinctness verdict mismatch for {Corpus} at candidate {i}: " +
                    $"expected {_csharpResults[i]}, got {_nsharpResults[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpOverloadDistinct_Checksum()
    {
        var checksum = _candidateCount;
        var distinctCount = 0;
        for (var c = 0; c < _candidateCount; c++)
        {
            var verdict = CSharpHasDistinctParameterSignature(_candidateSignatures[c], _existingSignatures, _existingCount)
                ? 1
                : 0;
            _csharpResults[c] = verdict;
            if (verdict == 1)
            {
                distinctCount++;
            }

            checksum = checksum + (c + 1) * 131 + (verdict + 1) * 17 + (_candidateSignatures[c].Length + 1) * 7;
        }

        checksum = checksum + distinctCount * 9973;
        return checksum;
    }

    [Benchmark]
    public int NSharpOverloadDistinct_Checksum() =>
        _nsharpDistinctChecksumInto(
            _candidateRanks,
            _candidateOffsets,
            _candidateLengths,
            _candidateCount,
            _existingRanks,
            _existingOffsets,
            _existingLengths,
            _existingCount,
            _nsharpResults);

    /// <summary>
    /// Mirrors <c>Analyzer.HasDistinctParameterSignature</c> + <c>ParameterSignaturesMatch</c>: arity
    /// check then per-parameter ordinal string comparison of the type signatures.
    /// </summary>
    private static bool CSharpHasDistinctParameterSignature(string[] candidate, string[][] existing, int existingCount)
    {
        for (var row = 0; row < existingCount; row++)
        {
            var existingRow = existing[row];
            if (existingRow.Length != candidate.Length)
            {
                continue;
            }

            var matches = true;
            for (var i = 0; i < candidate.Length; i++)
            {
                if (!string.Equals(existingRow[i], candidate[i], StringComparison.Ordinal))
                {
                    matches = false;
                    break;
                }
            }

            if (matches)
            {
                return false;
            }
        }

        return true;
    }

    private void BuildExisting()
    {
        _existingSignatures = new string[_existingCount][];
        _existingOffsets = new int[_existingCount];
        _existingLengths = new int[_existingCount];

        var packed = new List<int>(_existingCount * MaxParameters);
        for (var row = 0; row < _existingCount; row++)
        {
            // Deterministic distinct arities/types so existing overloads do not collide with each other.
            var arity = 1 + (row % MaxParameters);
            var signature = new string[arity];
            _existingOffsets[row] = packed.Count;
            _existingLengths[row] = arity;
            for (var i = 0; i < arity; i++)
            {
                var typeRank = ((row * 7) + (i * 13) + 1) % DistinctTypeCount;
                signature[i] = TypeNameForRank(typeRank);
                packed.Add(typeRank);
            }

            _existingSignatures[row] = signature;
        }

        _existingRanks = packed.ToArray();
    }

    private void BuildCandidates()
    {
        _candidateSignatures = new string[_candidateCount][];
        _candidateOffsets = new int[_candidateCount];
        _candidateLengths = new int[_candidateCount];

        var packed = new List<int>(_candidateCount * MaxParameters);
        for (var c = 0; c < _candidateCount; c++)
        {
            // Every 5th candidate is a deliberate duplicate of an existing overload row to exercise the
            // early-match path; the rest are distinct (force a full scan of the existing group).
            int arity;
            int[] ranks;
            if (c % 5 == 0)
            {
                var dupRow = c % _existingCount;
                arity = _existingLengths[dupRow];
                ranks = new int[arity];
                var offset = _existingOffsets[dupRow];
                for (var i = 0; i < arity; i++)
                {
                    ranks[i] = _existingRanks[offset + i];
                }
            }
            else
            {
                arity = 1 + (c % MaxParameters);
                ranks = new int[arity];
                for (var i = 0; i < arity; i++)
                {
                    // Offset the type space so distinct candidates do not accidentally match existing rows.
                    ranks[i] = (((c * 11) + (i * 17) + 5) % DistinctTypeCount) + DistinctTypeCount;
                }
            }

            var signature = new string[arity];
            _candidateOffsets[c] = packed.Count;
            _candidateLengths[c] = arity;
            for (var i = 0; i < arity; i++)
            {
                signature[i] = TypeNameForRank(ranks[i]);
                packed.Add(ranks[i]);
            }

            _candidateSignatures[c] = signature;
        }

        _candidateRanks = packed.ToArray();
    }

    private static string TypeNameForRank(int rank) => (rank % 12) switch
    {
        0 => $"int{rank}",
        1 => $"string{rank}",
        2 => $"bool{rank}",
        3 => $"double{rank}",
        4 => $"List<int{rank}>",
        5 => $"Dictionary<string{rank},int{rank}>",
        6 => $"int{rank}[]",
        7 => $"string{rank}?",
        8 => $"(int{rank},string{rank})",
        9 => $"Status{rank}|Error{rank}",
        10 => $"Func{rank}<int{rank},bool{rank}>",
        _ => $"Custom{rank}"
    };
}
