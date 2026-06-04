using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <see cref="NSharpLang.Compiler.CodeIntelligence.FixApplicator"/>
/// text-edit ordering. The C# baseline mirrors the previous LINQ shape: attach the source index,
/// sort bottom-to-top/right-to-left, sort range ends ascending, then preserve same-position insert
/// order by applying equal-key edits in reverse input order. The N# candidate runs after the host
/// has compacted the four numeric coordinates to dense ranks and returns ordered source indices.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceTextEditOrderingBenchmarks
{
    private const int LargeEditCount = 8192;
    private const int RepresentativeEditCount = 1024;

    private TextEditOrderChecksumInto _nsharpTextEditOrderChecksumInto =
        (_, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _bucketCounts = Array.Empty<int>();
    private int[] _bucketOffsets = Array.Empty<int>();
    private int[] _endPositionRanks = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _startPositionRanks = Array.Empty<int>();
    private int[] _tempIndices = Array.Empty<int>();
    private TextEdit[] _edits = Array.Empty<TextEdit>();
    private int _editCount;
    private int _endPositionRankCount;
    private int _startPositionRankCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _editCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeEditCount
            : LargeEditCount;
        _nsharpTextEditOrderChecksumInto =
            NSharpCompiledMethod.Bind<TextEditOrderChecksumInto>(
                DogfoodCompilerSources.CodeIntelligenceTextEditOrdering,
                "TextEditOrderChecksumInto");

        _edits = BuildEdits(_editCount);
        _startPositionRanks = new int[_editCount];
        _endPositionRanks = new int[_editCount];
        _tempIndices = new int[_editCount];
        _nsharpResultIndices = new int[_editCount];

        _startPositionRankCount = BuildRanks(EditOrderingPosition.Start, _startPositionRanks);
        _endPositionRankCount = BuildRanks(EditOrderingPosition.End, _endPositionRanks);
        var maxRankCount = Math.Max(_startPositionRankCount, _endPositionRankCount);
        _bucketCounts = new int[maxRankCount + 1];
        _bucketOffsets = new int[maxRankCount + 1];

        var expectedChecksum = CSharpTextEdits_OrderForApplication();
        var actualChecksum = NSharpTextEdits_OrderForApplication();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# text-edit order checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expected = SortWithCSharp();
        for (var i = 0; i < expected.Count; i++)
        {
            if (_nsharpResultIndices[i] != expected[i])
            {
                throw new InvalidOperationException(
                    $"N# text-edit order mismatch for {Corpus} at ordered item {i}: " +
                    $"expected source index {expected[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTextEdits_OrderForApplication()
    {
        var ordered = SortWithCSharp();
        return ChecksumOrderedEdits(ordered);
    }

    [Benchmark]
    public int NSharpTextEdits_OrderForApplication() =>
        _nsharpTextEditOrderChecksumInto(
            _startPositionRanks,
            _endPositionRanks,
            _startPositionRankCount,
            _endPositionRankCount,
            _bucketCounts,
            _bucketOffsets,
            _tempIndices,
            _nsharpResultIndices);

    private List<int> SortWithCSharp() =>
        _edits
            .Select((edit, index) => new { Edit = edit, Index = index })
            .OrderByDescending(item => item.Edit.StartLine)
            .ThenByDescending(item => item.Edit.StartColumn)
            .ThenBy(item => item.Edit.EndLine)
            .ThenBy(item => item.Edit.EndColumn)
            .ThenByDescending(item => item.Index)
            .Select(item => item.Index)
            .ToList();

    private int ChecksumOrderedEdits(IReadOnlyList<int> ordered)
    {
        var checksum = ordered.Count;
        for (var i = 0; i < ordered.Count; i++)
        {
            var index = ordered[i];
            checksum += (i + 1) * 97 + (index + 1) * 31;
            checksum += _startPositionRanks[index] * 17 + _endPositionRanks[index] * 13;
        }

        return checksum;
    }

    private int BuildRanks(EditOrderingPosition position, int[] ranks)
    {
        var rankMap = new Dictionary<(int Line, int Column), int>();
        var uniqueValues = new (int Line, int Column)[_edits.Length];
        var uniqueCount = 0;
        for (var i = 0; i < _edits.Length; i++)
        {
            var value = GetPosition(_edits[i], position);
            if (rankMap.ContainsKey(value))
                continue;

            rankMap.Add(value, 0);
            uniqueValues[uniqueCount] = value;
            uniqueCount++;
        }

        Array.Sort(uniqueValues, 0, uniqueCount);
        for (var i = 0; i < uniqueCount; i++)
        {
            rankMap[uniqueValues[i]] = i + 1;
        }

        for (var i = 0; i < _edits.Length; i++)
        {
            ranks[i] = rankMap[GetPosition(_edits[i], position)];
        }

        return uniqueCount;
    }

    private static TextEdit[] BuildEdits(int count)
    {
        var edits = new TextEdit[count];
        for (var i = 0; i < count; i++)
        {
            var startLine = 1 + ((i * 37 + i / 11) % 640);
            var startColumn = (i * 19 + i / 7) % 120;
            var endLine = startLine + (i % 13 == 0 ? 1 : 0);
            var endColumn = endLine == startLine
                ? startColumn + (i % 5)
                : (i * 23 + 3) % 80;

            if (i % 17 == 0)
            {
                startLine = 80 + (i % 9);
                startColumn = 4 + (i % 3);
                endLine = startLine;
                endColumn = startColumn;
            }

            edits[i] = new TextEdit(startLine, startColumn, endLine, endColumn, $"replacement-{i % 31}");
        }

        return edits;
    }

    private static (int Line, int Column) GetPosition(TextEdit edit, EditOrderingPosition position) =>
        position switch
        {
            EditOrderingPosition.Start => (edit.StartLine, edit.StartColumn),
            EditOrderingPosition.End => (edit.EndLine, edit.EndColumn),
            _ => (0, 0)
        };

    private enum EditOrderingPosition
    {
        Start,
        End
    }

    private delegate int TextEditOrderChecksumInto(
        int[] startPositionRanks,
        int[] endPositionRanks,
        int startPositionRankCount,
        int endPositionRankCount,
        int[] bucketCounts,
        int[] bucketOffsets,
        int[] tempIndices,
        int[] resultIndices);
}
