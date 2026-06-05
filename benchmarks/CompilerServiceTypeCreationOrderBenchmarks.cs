using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for IL compiler type-builder creation ordering. The C# baseline mirrors the
/// current production shape: stable <c>OrderByDescending</c> over the dot count in each type key,
/// followed by array materialization. The N# candidate counts key depths once and uses stable
/// counting-order buckets to return source indices through caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceTypeCreationOrderBenchmarks
{
    private const int LargeTypeCount = 8192;
    private const int RepresentativeTypeCount = 1024;

    private readonly Dictionary<string, int> _sourceIndexByKey = new(StringComparer.Ordinal);
    private Func<string[], int, int[], int[], int[], int[], int[], int> _nsharpTypeCreationOrderChecksumInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpResultIndices = Array.Empty<int>();
    private int[] _keyWeights = Array.Empty<int>();
    private int[] _nsharpDepthCounts = Array.Empty<int>();
    private int[] _nsharpDepthOffsets = Array.Empty<int>();
    private int[] _nsharpDotCounts = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private string[] _typeKeys = Array.Empty<string>();
    private int _maxKeyLength;
    private int _typeCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _typeCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeTypeCount
            : LargeTypeCount;
        _nsharpTypeCreationOrderChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], int, int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.TypeLookup,
                "TypeCreationOrderChecksumInto");

        _typeKeys = new string[_typeCount];
        _keyWeights = new int[_typeCount];
        _csharpResultIndices = new int[_typeCount];
        _nsharpDotCounts = new int[_typeCount];
        _nsharpResultIndices = new int[_typeCount];

        BuildTypeKeys();
        _nsharpDepthCounts = new int[_maxKeyLength + 1];
        _nsharpDepthOffsets = new int[_maxKeyLength + 1];

        var expectedChecksum = CSharpTypeCreationOrder_StableDepthSort();
        var actualChecksum = NSharpTypeCreationOrder_CountingDepthSort();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# type-creation order checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _typeCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# type-creation order mismatch for {Corpus} at result {i}: " +
                    $"expected index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTypeCreationOrder_StableDepthSort()
    {
        var orderedKeys = _typeKeys
            .OrderByDescending(static key => key.Count(static c => c == '.'))
            .ToArray();

        var checksum = orderedKeys.Length;
        for (var i = 0; i < orderedKeys.Length; i++)
        {
            var sourceIndex = _sourceIndexByKey[orderedKeys[i]];
            _csharpResultIndices[i] = sourceIndex;
            checksum += (i + 1) * 97
                + (sourceIndex + 1) * 31
                + CountDots(orderedKeys[i]) * 17
                + _keyWeights[sourceIndex] * 13;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpTypeCreationOrder_CountingDepthSort() =>
        _nsharpTypeCreationOrderChecksumInto(
            _typeKeys,
            _typeCount,
            _nsharpDotCounts,
            _nsharpDepthCounts,
            _nsharpDepthOffsets,
            _nsharpResultIndices,
            _keyWeights);

    private void BuildTypeKeys()
    {
        _sourceIndexByKey.Clear();
        _maxKeyLength = 0;
        for (var i = 0; i < _typeCount; i++)
        {
            var depth = (i * 7) % 9;
            var key = $"Project.Generated.Type{i:D5}";
            for (var segment = 0; segment < depth; segment++)
            {
                key += $".Nested{(i + segment) % 17}";
            }

            _typeKeys[i] = key;
            _keyWeights[i] = key.Length + depth * 3;
            _sourceIndexByKey.Add(key, i);
            if (key.Length > _maxKeyLength)
            {
                _maxKeyLength = key.Length;
            }
        }
    }

    private static int CountDots(string key)
    {
        var count = 0;
        for (var i = 0; i < key.Length; i++)
        {
            if (key[i] == '.')
            {
                count++;
            }
        }

        return count;
    }
}
