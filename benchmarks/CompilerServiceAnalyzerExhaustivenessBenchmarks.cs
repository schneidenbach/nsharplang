using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for analyzer enum-match exhaustiveness finalization. The C# baseline mirrors
/// the current <c>CheckEnumMatchExhaustiveness</c> tail: build an all-member hash set from enum
/// declaration members, run <c>Except</c> against covered members, and materialize missing names.
/// The N# candidate runs after the analyzer has projected covered-member flags in declaration
/// order and writes missing member source indices through caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceAnalyzerEnumExhaustivenessBenchmarks
{
    private const int LargeMemberCount = 8192;
    private const int RepresentativeMemberCount = 1024;

    private Func<int[], int, int[], int[], int> _nsharpMissingMemberChecksumInto =
        (_, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private readonly HashSet<string> _coveredMembers = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _memberIndexByName = new(StringComparer.Ordinal);
    private int[] _coveredFlags = Array.Empty<int>();
    private int _memberCount;
    private BenchmarkEnumMember[] _members = Array.Empty<BenchmarkEnumMember>();
    private int[] _nameWeights = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private string[] _csharpMissingMembers = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        EnumExhaustivenessCoverageShape.MissingEveryFourth,
        EnumExhaustivenessCoverageShape.OneMissingNearEnd,
        EnumExhaustivenessCoverageShape.AllCovered)]
    public EnumExhaustivenessCoverageShape Shape { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _memberCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeMemberCount
            : LargeMemberCount;
        _nsharpMissingMemberChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int[], int>>(
                DogfoodCompilerSources.AnalyzerExhaustiveness,
                "AnalyzerMissingMemberChecksumInto");

        _members = new BenchmarkEnumMember[_memberCount];
        _coveredFlags = new int[_memberCount];
        _nameWeights = new int[_memberCount];
        _nsharpResultIndices = new int[_memberCount];
        BuildMembers();
        BuildCoveredMembers();

        var expectedChecksum = CSharpEnumExhaustiveness_MissingMembers();
        var actualChecksum = NSharpEnumExhaustiveness_MissingMembers();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# enum exhaustiveness checksum mismatch for {Corpus}/{Shape}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        var actualMissing = ReadNSharpMissingMembers();
        if (!_csharpMissingMembers.SequenceEqual(actualMissing))
        {
            var mismatch = FirstMismatch(_csharpMissingMembers, actualMissing);
            throw new InvalidOperationException(
                $"N# enum exhaustiveness mismatch for {Corpus}/{Shape} at result {mismatch}: " +
                $"expected {FormatAt(_csharpMissingMembers, mismatch)}, got {FormatAt(actualMissing, mismatch)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpEnumExhaustiveness_MissingMembers()
    {
        var allMembers = _members
            .Select(member => member.Name)
            .ToHashSet(StringComparer.Ordinal);
        _csharpMissingMembers = allMembers
            .Except(_coveredMembers)
            .ToArray();

        return ChecksumMissingMembers(_csharpMissingMembers);
    }

    [Benchmark]
    public int NSharpEnumExhaustiveness_MissingMembers() =>
        _nsharpMissingMemberChecksumInto(
            _coveredFlags,
            _memberCount,
            _nameWeights,
            _nsharpResultIndices);

    private void BuildMembers()
    {
        _memberIndexByName.Clear();

        for (var i = 0; i < _members.Length; i++)
        {
            var name = (i % 11) switch
            {
                0 => $"Created{i:D5}",
                1 => $"Queued{i:D5}",
                2 => $"Running{i:D5}",
                3 => $"Succeeded{i:D5}",
                4 => $"Failed{i:D5}",
                5 => $"Cancelled{i:D5}",
                6 => $"Retrying{i:D5}",
                7 => $"Archived{i:D5}",
                8 => $"référence{i:D5}",
                9 => $"HTTPStatus{i:D5}",
                _ => $"Value_{i:D5}"
            };

            _members[i] = new BenchmarkEnumMember(name);
            _memberIndexByName.Add(name, i);
            _nameWeights[i] = name.Length;
        }
    }

    private void BuildCoveredMembers()
    {
        _coveredMembers.Clear();
        Array.Clear(_coveredFlags);

        for (var i = 0; i < _members.Length; i++)
        {
            var covered = Shape switch
            {
                EnumExhaustivenessCoverageShape.AllCovered => true,
                EnumExhaustivenessCoverageShape.MissingEveryFourth => i % 4 != 0,
                EnumExhaustivenessCoverageShape.OneMissingNearEnd => i != _members.Length - 7,
                _ => false
            };

            if (!covered)
            {
                continue;
            }

            _coveredMembers.Add(_members[i].Name);
            _coveredFlags[i] = 1;
        }
    }

    private string[] ReadNSharpMissingMembers()
    {
        var result = new string[_csharpMissingMembers.Length];
        for (var i = 0; i < result.Length; i++)
        {
            var sourceIndex = _nsharpResultIndices[i];
            result[i] = sourceIndex >= 0 && sourceIndex < _members.Length
                ? _members[sourceIndex].Name
                : string.Empty;
        }

        return result;
    }

    private int ChecksumMissingMembers(IReadOnlyList<string> missingMembers)
    {
        var checksum = missingMembers.Count;
        for (var i = 0; i < missingMembers.Count; i++)
        {
            var sourceIndex = GetSourceIndex(missingMembers[i]);
            checksum = checksum
                + (i + 1) * 97
                + (sourceIndex + 1) * 31
                + _nameWeights[sourceIndex] * 17;
        }

        return checksum;
    }

    private int GetSourceIndex(string name)
    {
        if (_memberIndexByName.TryGetValue(name, out var index))
        {
            return index;
        }

        throw new InvalidOperationException($"Unknown enum member name '{name}'.");
    }

    private static int FirstMismatch(IReadOnlyList<string> expected, IReadOnlyList<string> actual)
    {
        var count = Math.Min(expected.Count, actual.Count);
        for (var i = 0; i < count; i++)
        {
            if (!string.Equals(expected[i], actual[i], StringComparison.Ordinal))
            {
                return i;
            }
        }

        return count;
    }

    private static string FormatAt(IReadOnlyList<string> values, int index) =>
        index >= 0 && index < values.Count ? values[index] : "<missing>";

    private readonly record struct BenchmarkEnumMember(string Name);
}

public enum EnumExhaustivenessCoverageShape
{
    MissingEveryFourth,
    OneMissingNearEnd,
    AllCovered
}

/// <summary>
/// Dogfood benchmark for analyzer union-match exhaustiveness finalization. The C# baseline mirrors
/// the current <c>CheckMatchExhaustiveness</c> tail: build an all-case hash set, run
/// <c>Except</c> against covered cases, then partition missing cases into partially-covered and
/// never-covered lists. The N# candidate runs after the analyzer has projected covered and partial
/// flags in declaration order and writes all three result-index streams through caller-owned
/// buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceAnalyzerUnionExhaustivenessBenchmarks
{
    private const int LargeCaseCount = 8192;
    private const int RepresentativeCaseCount = 1024;

    private Func<int[], int[], int, int[], int[], int[], int[], int[], int> _nsharpMissingCaseChecksumInto =
        (_, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private readonly HashSet<string> _coveredCases = new(StringComparer.Ordinal);
    private readonly HashSet<string> _partiallyCoveredCases = new(StringComparer.Ordinal);
    private int[] _coveredFlags = Array.Empty<int>();
    private string[] _csharpMissingCases = Array.Empty<string>();
    private string[] _csharpNeverCoveredCases = Array.Empty<string>();
    private string[] _csharpPartialMissingCases = Array.Empty<string>();
    private int _caseCount;
    private string[] _caseNames = Array.Empty<string>();
    private int[] _nameWeights = Array.Empty<int>();
    private int[] _neverCoveredIndices = Array.Empty<int>();
    private List<string> _nsharpMaterializedMissingCases = [];
    private List<string> _nsharpMaterializedNeverCoveredCases = [];
    private List<string> _nsharpMaterializedPartialMissingCases = [];
    private int[] _nsharpMissingIndices = Array.Empty<int>();
    private int[] _nsharpPartialMissingIndices = Array.Empty<int>();
    private int[] _partialFlags = Array.Empty<int>();
    private int[] _projectedCoveredFlags = Array.Empty<int>();
    private int[] _projectedNeverCoveredIndices = Array.Empty<int>();
    private int[] _projectedPartialFlags = Array.Empty<int>();
    private int[] _projectedResultCounts = Array.Empty<int>();
    private int[] _resultCounts = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        UnionExhaustivenessCoverageShape.MissingEveryFourthWithPartials,
        UnionExhaustivenessCoverageShape.OnePartialAndOneNever,
        UnionExhaustivenessCoverageShape.AllCovered)]
    public UnionExhaustivenessCoverageShape Shape { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _caseCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeCaseCount
            : LargeCaseCount;
        _nsharpMissingCaseChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int, int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.AnalyzerExhaustiveness,
                "AnalyzerUnionMissingCaseChecksumInto");

        _caseNames = new string[_caseCount];
        _coveredFlags = new int[_caseCount];
        _partialFlags = new int[_caseCount];
        _projectedCoveredFlags = new int[_caseCount];
        _projectedPartialFlags = new int[_caseCount];
        _nameWeights = new int[_caseCount];
        _nsharpMissingIndices = new int[_caseCount];
        _nsharpPartialMissingIndices = new int[_caseCount];
        _neverCoveredIndices = new int[_caseCount];
        _projectedNeverCoveredIndices = new int[_caseCount];
        _resultCounts = new int[3];
        _projectedResultCounts = new int[3];

        BuildCaseNames();
        BuildCoverage();

        var expectedNameChecksum = CSharpUnionExhaustiveness_MissingCases();
        var expectedIndexChecksum = IndexChecksum(
            _csharpMissingCases,
            _csharpPartialMissingCases,
            _csharpNeverCoveredCases);
        var actualChecksum = NSharpUnionExhaustiveness_MissingCases();
        var materializedChecksum = NSharpMaterializedUnionExhaustiveness_MissingCases();
        var projectedChecksum = NSharpProjectedUnionExhaustiveness_MissingCases();
        if (expectedIndexChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# union exhaustiveness checksum mismatch for {Corpus}/{Shape}: " +
                $"expected {expectedIndexChecksum}, got {actualChecksum}.");
        }

        if (expectedNameChecksum != materializedChecksum)
        {
            throw new InvalidOperationException(
                $"N# materialized union exhaustiveness checksum mismatch for {Corpus}/{Shape}: " +
                $"expected {expectedNameChecksum}, got {materializedChecksum}.");
        }

        if (expectedIndexChecksum != projectedChecksum)
        {
            throw new InvalidOperationException(
                $"N# projected union exhaustiveness checksum mismatch for {Corpus}/{Shape}: " +
                $"expected {expectedIndexChecksum}, got {projectedChecksum}.");
        }

        AssertSequenceEqual(_csharpMissingCases, _nsharpMissingIndices, _resultCounts[0], "missing");
        AssertSequenceEqual(_csharpPartialMissingCases, _nsharpPartialMissingIndices, _resultCounts[1], "partial");
        AssertSequenceEqual(_csharpNeverCoveredCases, _neverCoveredIndices, _resultCounts[2], "never-covered");
    }

    [Benchmark(Baseline = true)]
    public int CSharpUnionExhaustiveness_MissingCases()
    {
        var allCases = _caseNames.ToHashSet();
        _csharpMissingCases = allCases.Except(_coveredCases).ToArray();
        _csharpPartialMissingCases = _csharpMissingCases.Where(_partiallyCoveredCases.Contains).ToArray();
        _csharpNeverCoveredCases = _csharpMissingCases.Except(_csharpPartialMissingCases).ToArray();

        return NameChecksum(
            _csharpMissingCases,
            _csharpPartialMissingCases,
            _csharpNeverCoveredCases);
    }

    [Benchmark]
    public int NSharpUnionExhaustiveness_MissingCases() =>
        _nsharpMissingCaseChecksumInto(
            _coveredFlags,
            _partialFlags,
            _caseCount,
            _nameWeights,
            _nsharpMissingIndices,
            _nsharpPartialMissingIndices,
            _neverCoveredIndices,
            _resultCounts);

    [Benchmark]
    public int NSharpMaterializedUnionExhaustiveness_MissingCases()
    {
        var checksum = _nsharpMissingCaseChecksumInto(
            _coveredFlags,
            _partialFlags,
            _caseCount,
            _nameWeights,
            _nsharpMissingIndices,
            _nsharpPartialMissingIndices,
            _neverCoveredIndices,
            _resultCounts);
        if (checksum < 0)
        {
            throw new InvalidOperationException(
                $"N# union exhaustiveness returned invalid checksum {checksum} for {Corpus}/{Shape}.");
        }

        _nsharpMaterializedMissingCases = MaterializeCaseNames(_nsharpMissingIndices, _resultCounts[0]);
        _nsharpMaterializedPartialMissingCases = MaterializeCaseNames(_nsharpPartialMissingIndices, _resultCounts[1]);
        _nsharpMaterializedNeverCoveredCases = MaterializeCaseNames(_neverCoveredIndices, _resultCounts[2]);
        return NameChecksum(
            _nsharpMaterializedMissingCases,
            _nsharpMaterializedPartialMissingCases,
            _nsharpMaterializedNeverCoveredCases);
    }

    [Benchmark]
    public int NSharpProjectedUnionExhaustiveness_MissingCases()
    {
        BuildProjectedFlags();
        return _nsharpMissingCaseChecksumInto(
            _projectedCoveredFlags,
            _projectedPartialFlags,
            _caseCount,
            _nameWeights,
            _nsharpMissingIndices,
            _nsharpPartialMissingIndices,
            _projectedNeverCoveredIndices,
            _projectedResultCounts);
    }

    private void BuildCaseNames()
    {
        for (var i = 0; i < _caseNames.Length; i++)
        {
            var name = (i % 9) switch
            {
                0 => $"Created{i:D5}",
                1 => $"Queued{i:D5}",
                2 => $"Running{i:D5}",
                3 => $"Succeeded{i:D5}",
                4 => $"Failed{i:D5}",
                5 => $"Cancelled{i:D5}",
                6 => $"HTTPStatus{i:D5}",
                7 => $"Value_{i:D5}",
                _ => $"Archived{i:D5}"
            };

            _caseNames[i] = name;
            _nameWeights[i] = name.Length;
        }
    }

    private void BuildCoverage()
    {
        _coveredCases.Clear();
        _partiallyCoveredCases.Clear();
        Array.Clear(_coveredFlags);
        Array.Clear(_partialFlags);

        for (var i = 0; i < _caseNames.Length; i++)
        {
            var partiallyCovered = Shape switch
            {
                UnionExhaustivenessCoverageShape.MissingEveryFourthWithPartials => i % 8 == 0,
                UnionExhaustivenessCoverageShape.OnePartialAndOneNever => i == _caseNames.Length - 11,
                _ => false
            };
            var covered = Shape switch
            {
                UnionExhaustivenessCoverageShape.AllCovered => true,
                UnionExhaustivenessCoverageShape.MissingEveryFourthWithPartials => i % 4 != 0,
                UnionExhaustivenessCoverageShape.OnePartialAndOneNever => i != _caseNames.Length - 11 && i != _caseNames.Length - 7,
                _ => false
            };

            if (covered)
            {
                _coveredCases.Add(_caseNames[i]);
                _coveredFlags[i] = 1;
            }

            if (partiallyCovered)
            {
                _partiallyCoveredCases.Add(_caseNames[i]);
                _partialFlags[i] = 1;
            }
        }
    }

    private void BuildProjectedFlags()
    {
        Array.Clear(_projectedCoveredFlags);
        Array.Clear(_projectedPartialFlags);

        for (var i = 0; i < _caseNames.Length; i++)
        {
            var name = _caseNames[i];
            _projectedCoveredFlags[i] = _coveredCases.Contains(name) ? 1 : 0;
            _projectedPartialFlags[i] = _partiallyCoveredCases.Contains(name) ? 1 : 0;
        }
    }

    private int IndexChecksum(
        IReadOnlyList<string> missingCases,
        IReadOnlyList<string> partialMissingCases,
        IReadOnlyList<string> neverCoveredCases)
    {
        var checksum = missingCases.Count * 31 + partialMissingCases.Count * 17 + neverCoveredCases.Count * 13;
        for (var i = 0; i < missingCases.Count; i++)
        {
            var sourceIndex = GetSourceIndex(missingCases[i]);
            checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + _nameWeights[sourceIndex] * 17;
        }

        for (var i = 0; i < partialMissingCases.Count; i++)
        {
            var sourceIndex = GetSourceIndex(partialMissingCases[i]);
            checksum = checksum + (i + 1) * 43 + (sourceIndex + 1) * 19;
        }

        for (var i = 0; i < neverCoveredCases.Count; i++)
        {
            var sourceIndex = GetSourceIndex(neverCoveredCases[i]);
            checksum = checksum + (i + 1) * 37 + (sourceIndex + 1) * 23;
        }

        return checksum;
    }

    private static int NameChecksum(
        IReadOnlyList<string> missingCases,
        IReadOnlyList<string> partialMissingCases,
        IReadOnlyList<string> neverCoveredCases)
    {
        var checksum = missingCases.Count * 31 + partialMissingCases.Count * 17 + neverCoveredCases.Count * 13;
        for (var i = 0; i < missingCases.Count; i++)
        {
            checksum = checksum + (i + 1) * 97 + missingCases[i].Length * 17;
        }

        for (var i = 0; i < partialMissingCases.Count; i++)
        {
            checksum = checksum + (i + 1) * 43 + partialMissingCases[i].Length * 19;
        }

        for (var i = 0; i < neverCoveredCases.Count; i++)
        {
            checksum = checksum + (i + 1) * 37 + neverCoveredCases[i].Length * 23;
        }

        return checksum;
    }

    private List<string> MaterializeCaseNames(int[] indices, int count)
    {
        var result = new List<string>(count);
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = indices[i];
            if (sourceIndex < 0 || sourceIndex >= _caseNames.Length)
            {
                throw new InvalidOperationException(
                    $"N# union exhaustiveness returned invalid source index {sourceIndex} for {Corpus}/{Shape}.");
            }

            result.Add(_caseNames[sourceIndex]);
        }

        return result;
    }

    private void AssertSequenceEqual(IReadOnlyList<string> expected, int[] indices, int count, string label)
    {
        if (expected.Count != count)
        {
            throw new InvalidOperationException(
                $"N# union exhaustiveness {label} count mismatch for {Corpus}/{Shape}: expected {expected.Count}, got {count}.");
        }

        for (var i = 0; i < count; i++)
        {
            var sourceIndex = indices[i];
            var actual = sourceIndex >= 0 && sourceIndex < _caseNames.Length
                ? _caseNames[sourceIndex]
                : string.Empty;
            if (!string.Equals(expected[i], actual, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"N# union exhaustiveness {label} mismatch for {Corpus}/{Shape} at result {i}: " +
                    $"expected {expected[i]}, got {actual}.");
            }
        }
    }

    private int GetSourceIndex(string name)
    {
        for (var i = 0; i < _caseNames.Length; i++)
        {
            if (string.Equals(_caseNames[i], name, StringComparison.Ordinal))
                return i;
        }

        throw new InvalidOperationException($"Unknown union case name '{name}'.");
    }
}

public enum UnionExhaustivenessCoverageShape
{
    MissingEveryFourthWithPartials,
    OnePartialAndOneNever,
    AllCovered
}
