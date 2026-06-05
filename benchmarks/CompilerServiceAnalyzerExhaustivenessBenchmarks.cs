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
