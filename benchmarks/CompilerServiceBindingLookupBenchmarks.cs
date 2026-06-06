using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for semantic binding position lookup before reference/definition result
/// materialization.
///
/// The C# baseline uses the production <see cref="BindingMap.GetBindingAt"/> dictionaries. The N#
/// candidate runs the same declaration-first lookup contract over compact file-rank/line/column
/// arrays and prebuilt open-addressed slot tables.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceBindingLookupBenchmarks
{
    private const int LargeBindingCount = 32768;
    private const int LargeDeclarationCount = 4096;
    private const int LargeQueryCount = 65536;
    private const int RepresentativeBindingCount = 4096;
    private const int RepresentativeDeclarationCount = 512;
    private const int RepresentativeQueryCount = 8192;

    private BindingLookupBuildSlotsInto _nsharpBuildSlots =
        (_, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private BindingLookupQueryChecksumInto _nsharpQueryChecksum =
        (_, _, _, _, _, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private readonly Dictionary<(string? File, int Line, int Column), int> _declarationIndices = new();

    private BindingMap _bindingMap = new();
    private int[] _bindingColumns = Array.Empty<int>();
    private int[] _bindingDeclarationIndices = Array.Empty<int>();
    private int[] _bindingFileRanks = Array.Empty<int>();
    private int[] _bindingLines = Array.Empty<int>();
    private int[] _bindingSlotIndices = Array.Empty<int>();
    private int[] _declarationColumns = Array.Empty<int>();
    private int _declarationCount;
    private int[] _declarationFileRanks = Array.Empty<int>();
    private int[] _declarationLines = Array.Empty<int>();
    private int[] _declarationNameLengths = Array.Empty<int>();
    private int[] _declarationSlotIndices = Array.Empty<int>();
    private string[] _filesByRank = Array.Empty<string>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _queryFileRanks = Array.Empty<int>();
    private string?[] _queryFiles = Array.Empty<string?>();
    private int[] _queryLines = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpBuildSlots =
            NSharpCompiledMethod.Bind<BindingLookupBuildSlotsInto>(
                DogfoodCompilerSources.CodeIntelligenceBindingLookup,
                "BindingLookupBuildSlotsInto");
        _nsharpQueryChecksum =
            NSharpCompiledMethod.Bind<BindingLookupQueryChecksumInto>(
                DogfoodCompilerSources.CodeIntelligenceBindingLookup,
                "BindingLookupQueryChecksumInto");

        _declarationCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDeclarationCount
            : LargeDeclarationCount;
        var bindingCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeBindingCount
            : LargeBindingCount;
        var queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;

        _bindingMap = new BindingMap();
        _declarationIndices.Clear();

        _declarationFileRanks = new int[_declarationCount];
        _declarationLines = new int[_declarationCount];
        _declarationColumns = new int[_declarationCount];
        _declarationNameLengths = new int[_declarationCount];
        _declarationSlotIndices = new int[_declarationCount * 2 + 1];
        _bindingFileRanks = new int[bindingCount];
        _bindingLines = new int[bindingCount];
        _bindingColumns = new int[bindingCount];
        _bindingDeclarationIndices = new int[bindingCount];
        _bindingSlotIndices = new int[bindingCount * 2 + 1];
        _queryFileRanks = new int[queryCount];
        _queryFiles = new string?[queryCount];
        _queryLines = new int[queryCount];
        _queryColumns = new int[queryCount];
        _nsharpResultIndices = new int[queryCount];

        BuildFiles();
        BuildDeclarations();
        BuildBindings(bindingCount);
        BuildQueries(queryCount, bindingCount);

        var insertedDeclarations = _nsharpBuildSlots(
            _declarationFileRanks,
            _declarationLines,
            _declarationColumns,
            _declarationSlotIndices);
        if (insertedDeclarations != _declarationCount)
        {
            throw new InvalidOperationException(
                $"N# binding lookup declaration slot build inserted {insertedDeclarations}, expected {_declarationCount}.");
        }

        var insertedBindings = _nsharpBuildSlots(
            _bindingFileRanks,
            _bindingLines,
            _bindingColumns,
            _bindingSlotIndices);
        if (insertedBindings != bindingCount)
        {
            throw new InvalidOperationException(
                $"N# binding lookup binding slot build inserted {insertedBindings}, expected {bindingCount}.");
        }

        var expectedChecksum = CSharpBindingLookup_QueryBatch();
        var actualChecksum = NSharpBindingLookup_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# binding lookup checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < queryCount; i++)
        {
            var expectedIndex = ResolveExpectedDeclarationIndex(i);
            if (_nsharpResultIndices[i] != expectedIndex)
            {
                throw new InvalidOperationException(
                    $"N# binding lookup mismatch for {Corpus} at query {i}: " +
                    $"expected declaration index {expectedIndex}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpBindingLookup_QueryBatch()
    {
        var checksum = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var declaration = _bindingMap.GetBindingAt(_queryFiles[i], _queryLines[i], _queryColumns[i]);
            if (declaration == null)
                continue;

            checksum++;
            checksum = checksum
                + declaration.Line * 31
                + declaration.Column * 17
                + declaration.Name.Length * 13;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpBindingLookup_QueryBatch() =>
        _nsharpQueryChecksum(
            _declarationFileRanks,
            _declarationLines,
            _declarationColumns,
            _declarationNameLengths,
            _declarationSlotIndices,
            _bindingFileRanks,
            _bindingLines,
            _bindingColumns,
            _bindingDeclarationIndices,
            _bindingSlotIndices,
            _queryFileRanks,
            _queryLines,
            _queryColumns,
            _nsharpResultIndices);

    private void BuildFiles()
    {
        var fileCount = Corpus == CompilerLexerCorpus.Representative ? 32 : 256;
        _filesByRank = new string[fileCount + 1];
        for (var i = 1; i <= fileCount; i++)
        {
            _filesByRank[i] = (i % 7) switch
            {
                0 => $"/repo/src/Program{i}.nl",
                1 => $"/repo/src/Features/Feature{i}.nl",
                2 => $"/repo/src/with space/File {i}.nl",
                3 => $@"C:\repo\module\File{i}.nl",
                4 => $"/repo/src/generated/File-{i}.nl",
                5 => $"/repo/src/cafe/Module{i}.nl",
                _ => $"/repo/src/[weird]/File{i}.nl"
            };
        }
    }

    private void BuildDeclarations()
    {
        for (var i = 0; i < _declarationCount; i++)
        {
            var fileRank = i % (_filesByRank.Length - 1) + 1;
            var line = i * 3 + 1;
            var column = i * 17 % 120 + 1;
            var name = $"symbol{i}";
            var kind = (i % 5) switch
            {
                0 => "class",
                1 => "function",
                2 => "variable",
                3 => "field",
                _ => "record"
            };

            var declaration = new SymbolDeclaration(name, _filesByRank[fileRank], line, column, kind);
            _bindingMap.RecordDeclaration(declaration);

            _declarationFileRanks[i] = fileRank;
            _declarationLines[i] = line;
            _declarationColumns[i] = column;
            _declarationNameLengths[i] = name.Length;
            _declarationIndices[(declaration.File, declaration.Line, declaration.Column)] = i;
        }
    }

    private void BuildBindings(int bindingCount)
    {
        for (var i = 0; i < bindingCount; i++)
        {
            var declarationIndex = i % _declarationCount;
            var fileRank = i * 13 % (_filesByRank.Length - 1) + 1;
            var line = 100_000 + i;
            var column = i * 29 % 120 + 1;
            var declaration = new SymbolDeclaration(
                $"symbol{declarationIndex}",
                _filesByRank[_declarationFileRanks[declarationIndex]],
                _declarationLines[declarationIndex],
                _declarationColumns[declarationIndex],
                declarationIndex % 5 == 0 ? "class" : "variable");

            _bindingMap.RecordBinding(_filesByRank[fileRank], line, column, declaration.Name.Length, declaration);

            _bindingFileRanks[i] = fileRank;
            _bindingLines[i] = line;
            _bindingColumns[i] = column;
            _bindingDeclarationIndices[i] = declarationIndex;
        }
    }

    private void BuildQueries(int queryCount, int bindingCount)
    {
        for (var i = 0; i < queryCount; i++)
        {
            switch (i % 10)
            {
                case <= 4:
                {
                    var bindingIndex = i * 37 % bindingCount;
                    SetQuery(i, _bindingFileRanks[bindingIndex], _bindingLines[bindingIndex], _bindingColumns[bindingIndex]);
                    break;
                }
                case <= 7:
                {
                    var declarationIndex = i * 17 % _declarationCount;
                    SetQuery(
                        i,
                        _declarationFileRanks[declarationIndex],
                        _declarationLines[declarationIndex],
                        _declarationColumns[declarationIndex]);
                    break;
                }
                default:
                {
                    var fileRank = i * 19 % (_filesByRank.Length - 1) + 1;
                    SetQuery(i, fileRank, 900_000 + i, i * 11 % 120 + 1);
                    break;
                }
            }
        }
    }

    private void SetQuery(int index, int fileRank, int line, int column)
    {
        _queryFileRanks[index] = fileRank;
        _queryFiles[index] = _filesByRank[fileRank];
        _queryLines[index] = line;
        _queryColumns[index] = column;
    }

    private int ResolveExpectedDeclarationIndex(int queryIndex)
    {
        var declaration = _bindingMap.GetBindingAt(
            _queryFiles[queryIndex],
            _queryLines[queryIndex],
            _queryColumns[queryIndex]);
        return declaration == null
            ? -1
            : _declarationIndices[(declaration.File, declaration.Line, declaration.Column)];
    }

    private delegate int BindingLookupBuildSlotsInto(
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] slotIndices);

    private delegate int BindingLookupQueryChecksumInto(
        int[] declarationFileRanks,
        int[] declarationLineNumbers,
        int[] declarationColumns,
        int[] declarationNameLengths,
        int[] declarationSlotIndices,
        int[] bindingFileRanks,
        int[] bindingLineNumbers,
        int[] bindingColumns,
        int[] bindingDeclarationIndices,
        int[] bindingSlotIndices,
        int[] queryFileRanks,
        int[] queryLineNumbers,
        int[] queryColumns,
        int[] resultDeclarationIndices);
}

/// <summary>
/// Dogfood benchmark for strict binding candidate-column ordering before declaration/binding lookup.
///
/// The C# baseline mirrors the current source-context helper: insert nearby columns into a
/// <see cref="HashSet{T}" />, include the selected identifier span, then sort by distance from the
/// requested column. The N# candidate preserves the same stable insertion and distance ordering
/// over caller-owned integer buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceBindingCandidateColumnBenchmarks
{
    private const int LargeQueryCount = 65536;
    private const int MaxCandidateColumns = 32;
    private const int RepresentativeQueryCount = 8192;

    private BindingLookupCandidateColumnChecksumInto _nsharpCandidateColumnChecksum =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpResultColumns = Array.Empty<int>();
    private int[] _csharpResultCounts = Array.Empty<int>();
    private int[] _csharpResultStarts = Array.Empty<int>();
    private int[] _nsharpResultColumns = Array.Empty<int>();
    private int[] _nsharpResultCounts = Array.Empty<int>();
    private int[] _nsharpResultStarts = Array.Empty<int>();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _spanEndColumns = Array.Empty<int>();
    private int[] _spanStartColumns = Array.Empty<int>();
    private int _queryCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpCandidateColumnChecksum =
            NSharpCompiledMethod.Bind<BindingLookupCandidateColumnChecksumInto>(
                DogfoodCompilerSources.CodeIntelligenceBindingLookup,
                "BindingLookupCandidateColumnChecksumInto");

        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _queryColumns = new int[_queryCount];
        _spanStartColumns = new int[_queryCount];
        _spanEndColumns = new int[_queryCount];
        _csharpResultStarts = new int[_queryCount];
        _csharpResultCounts = new int[_queryCount];
        _nsharpResultStarts = new int[_queryCount];
        _nsharpResultCounts = new int[_queryCount];
        _csharpResultColumns = new int[_queryCount * MaxCandidateColumns];
        _nsharpResultColumns = new int[_queryCount * MaxCandidateColumns];

        BuildQueries();

        var expectedChecksum = CSharpBindingCandidateColumns_QueryBatch();
        var actualChecksum = NSharpBindingCandidateColumns_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# binding candidate-column checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpResultStarts.SequenceEqual(_nsharpResultStarts) ||
            !_csharpResultCounts.SequenceEqual(_nsharpResultCounts))
        {
            throw new InvalidOperationException($"N# binding candidate-column segment mismatch for {Corpus}.");
        }

        var expectedTotal = _csharpResultCounts.Sum();
        for (var i = 0; i < expectedTotal; i++)
        {
            if (_csharpResultColumns[i] != _nsharpResultColumns[i])
            {
                throw new InvalidOperationException(
                    $"N# binding candidate-column mismatch for {Corpus} at result {i}: " +
                    $"expected {_csharpResultColumns[i]}, got {_nsharpResultColumns[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpBindingCandidateColumns_QueryBatch()
    {
        var writeIndex = 0;
        for (var i = 0; i < _queryColumns.Length; i++)
        {
            var columns = BuildCandidateColumnsWithCurrentShape(
                _queryColumns[i],
                _spanStartColumns[i],
                _spanEndColumns[i]);

            _csharpResultStarts[i] = writeIndex;
            _csharpResultCounts[i] = columns.Length;
            for (var j = 0; j < columns.Length; j++)
            {
                _csharpResultColumns[writeIndex + j] = columns[j];
            }

            writeIndex += columns.Length;
        }

        return CandidateColumnChecksum(writeIndex, _csharpResultStarts, _csharpResultCounts, _csharpResultColumns);
    }

    [Benchmark]
    public int NSharpBindingCandidateColumns_QueryBatch() =>
        _nsharpCandidateColumnChecksum(
            _queryColumns,
            _spanStartColumns,
            _spanEndColumns,
            _nsharpResultStarts,
            _nsharpResultCounts,
            _nsharpResultColumns);

    private void BuildQueries()
    {
        for (var i = 0; i < _queryCount; i++)
        {
            var column = i % 97 + 1;
            if (i % 31 == 0)
                column = 0;
            if (i % 43 == 0)
                column = -3;

            _queryColumns[i] = column;

            if (i % 7 == 0)
            {
                _spanStartColumns[i] = -1;
                _spanEndColumns[i] = -1;
                continue;
            }

            var spanLength = i % 13 + 1;
            var start = Math.Max(1, column - spanLength / 2);
            _spanStartColumns[i] = start;
            _spanEndColumns[i] = start + spanLength - 1;
        }
    }

    private static int[] BuildCandidateColumnsWithCurrentShape(
        int column,
        int spanStartColumn,
        int spanEndColumn)
    {
        var seen = new HashSet<int>();

        if (column > 0)
            seen.Add(column);
        if (column > 1)
            seen.Add(column - 1);
        seen.Add(column + 1);

        if (spanStartColumn > 0 && spanEndColumn >= spanStartColumn)
        {
            for (var candidate = spanStartColumn; candidate <= spanEndColumn; candidate++)
            {
                seen.Add(candidate);
            }
        }

        return seen.OrderBy(candidate => Math.Abs(candidate - column)).ToArray();
    }

    private static int CandidateColumnChecksum(
        int total,
        int[] starts,
        int[] counts,
        int[] columns)
    {
        var checksum = total;
        for (var i = 0; i < counts.Length; i++)
        {
            var start = starts[i];
            var count = counts[i];
            checksum += count * 97 + start * 7;
            for (var j = 0; j < count; j++)
            {
                checksum += columns[start + j] * 31 + (j + 1) * 17;
            }
        }

        return checksum;
    }

    private delegate int BindingLookupCandidateColumnChecksumInto(
        int[] queryColumns,
        int[] spanStartColumns,
        int[] spanEndColumns,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultColumns);
}

/// <summary>
/// Dogfood benchmark for nearest-declaration sorted-index construction used by the source-context
/// definition fallback.
///
/// The C# baseline mirrors the production cache builder: allocate an order array, sort declaration
/// ids with a comparer over name/file/line/column, then materialize sorted compact arrays. The N#
/// candidate uses dense name-id counting with caller-owned buffers, writes the sorted arrays
/// directly, and returns a fallback signal when same-name declarations are not already in source
/// order.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceBindingLookupNearestDeclarationIndexBuildBenchmarks
{
    private BindingLookupBuildNearestDeclarationIndexInto _nsharpBuildNearestIndex = null!;
    private BindingLookupBuildNearestDeclarationIndexChecksumInto _nsharpChecksum = null!;

    private int[] _csharpSortedColumns = Array.Empty<int>();
    private int[] _csharpSortedDeclarationIndices = Array.Empty<int>();
    private int[] _csharpSortedFileRanks = Array.Empty<int>();
    private int[] _csharpSortedLineNumbers = Array.Empty<int>();
    private int[] _csharpSortedNameIds = Array.Empty<int>();
    private int[] _declarationColumns = Array.Empty<int>();
    private int[] _declarationFileRanks = Array.Empty<int>();
    private int[] _declarationLineNumbers = Array.Empty<int>();
    private int[] _declarationNameIds = Array.Empty<int>();
    private int[] _nsharpSortedColumns = Array.Empty<int>();
    private int[] _nsharpSortedDeclarationIndices = Array.Empty<int>();
    private int[] _nsharpSortedFileRanks = Array.Empty<int>();
    private int[] _nsharpSortedLineNumbers = Array.Empty<int>();
    private int[] _nsharpSortedNameIds = Array.Empty<int>();
    private int[] _stackLefts = Array.Empty<int>();
    private int[] _tempDeclarationIndices = Array.Empty<int>();
    private int _declarationCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _declarationCount = Corpus == CompilerLexerCorpus.Representative ? 1024 : 8192;
        _nsharpBuildNearestIndex =
            NSharpCompiledMethod.Bind<BindingLookupBuildNearestDeclarationIndexInto>(
                DogfoodCompilerSources.CodeIntelligenceBindingLookup,
                "BindingLookupBuildNearestDeclarationIndexInto");
        _nsharpChecksum =
            NSharpCompiledMethod.Bind<BindingLookupBuildNearestDeclarationIndexChecksumInto>(
                DogfoodCompilerSources.CodeIntelligenceBindingLookup,
                "BindingLookupBuildNearestDeclarationIndexChecksumInto");

        _declarationNameIds = new int[_declarationCount];
        _declarationFileRanks = new int[_declarationCount];
        _declarationLineNumbers = new int[_declarationCount];
        _declarationColumns = new int[_declarationCount];
        _tempDeclarationIndices = new int[_declarationCount + 1];
        _stackLefts = new int[_declarationCount + 1];
        _csharpSortedNameIds = new int[_declarationCount];
        _csharpSortedFileRanks = new int[_declarationCount];
        _csharpSortedLineNumbers = new int[_declarationCount];
        _csharpSortedColumns = new int[_declarationCount];
        _csharpSortedDeclarationIndices = new int[_declarationCount];
        _nsharpSortedNameIds = new int[_declarationCount];
        _nsharpSortedFileRanks = new int[_declarationCount];
        _nsharpSortedLineNumbers = new int[_declarationCount];
        _nsharpSortedColumns = new int[_declarationCount];
        _nsharpSortedDeclarationIndices = new int[_declarationCount];

        BuildDeclarationCorpus();

        var expectedChecksum = CSharpNearestDeclarationIndex_BuildChecksum();
        var actualChecksum = NSharpNearestDeclarationIndex_BuildChecksum();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# nearest declaration index checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpNearestDeclarationIndex_Build()
    {
        BuildNearestDeclarationIndexWithCSharp(
            _csharpSortedNameIds,
            _csharpSortedFileRanks,
            _csharpSortedLineNumbers,
            _csharpSortedColumns,
            _csharpSortedDeclarationIndices);

        return _declarationCount
            + _csharpSortedNameIds[0] * 31
            + _csharpSortedDeclarationIndices[_declarationCount - 1] * 17;
    }

    [Benchmark]
    public int NSharpNearestDeclarationIndex_Build()
    {
        var count = _nsharpBuildNearestIndex(
            _declarationNameIds,
            _declarationFileRanks,
            _declarationLineNumbers,
            _declarationColumns,
            _tempDeclarationIndices,
            _stackLefts,
            _nsharpSortedNameIds,
            _nsharpSortedFileRanks,
            _nsharpSortedLineNumbers,
            _nsharpSortedColumns,
            _nsharpSortedDeclarationIndices);

        return count
            + _nsharpSortedNameIds[0] * 31
            + _nsharpSortedDeclarationIndices[count - 1] * 17;
    }

    private int CSharpNearestDeclarationIndex_BuildChecksum()
    {
        BuildNearestDeclarationIndexWithCSharp(
            _csharpSortedNameIds,
            _csharpSortedFileRanks,
            _csharpSortedLineNumbers,
            _csharpSortedColumns,
            _csharpSortedDeclarationIndices);

        return CalculateChecksum(
            _csharpSortedNameIds,
            _csharpSortedFileRanks,
            _csharpSortedLineNumbers,
            _csharpSortedColumns,
            _csharpSortedDeclarationIndices);
    }

    private int NSharpNearestDeclarationIndex_BuildChecksum() =>
        _nsharpChecksum(
            _declarationNameIds,
            _declarationFileRanks,
            _declarationLineNumbers,
            _declarationColumns,
            _tempDeclarationIndices,
            _stackLefts,
            _nsharpSortedNameIds,
            _nsharpSortedFileRanks,
            _nsharpSortedLineNumbers,
            _nsharpSortedColumns,
            _nsharpSortedDeclarationIndices);

    private void BuildDeclarationCorpus()
    {
        var nameCount = Corpus == CompilerLexerCorpus.Representative ? 64 : 512;
        var fileCount = Corpus == CompilerLexerCorpus.Representative ? 16 : 128;

        for (var i = 0; i < _declarationCount; i++)
        {
            _declarationNameIds[i] = i * 37 % nameCount + 1;
            _declarationFileRanks[i] = i * 17 % fileCount + 1;
            _declarationLineNumbers[i] = i / nameCount * 5 + (_declarationNameIds[i] % 3) + 1;
            _declarationColumns[i] = i * 29 % 160 + 1;
        }
    }

    private void BuildNearestDeclarationIndexWithCSharp(
        int[] sortedNameIds,
        int[] sortedFileRanks,
        int[] sortedLineNumbers,
        int[] sortedColumns,
        int[] sortedDeclarationIndices)
    {
        var order = new int[_declarationCount];
        for (var i = 0; i < _declarationCount; i++)
        {
            order[i] = i;
        }

        Array.Sort(order, CompareDeclarationOrder);

        for (var sortedIndex = 0; sortedIndex < _declarationCount; sortedIndex++)
        {
            var declarationIndex = order[sortedIndex];
            sortedNameIds[sortedIndex] = _declarationNameIds[declarationIndex];
            sortedFileRanks[sortedIndex] = _declarationFileRanks[declarationIndex];
            sortedLineNumbers[sortedIndex] = _declarationLineNumbers[declarationIndex];
            sortedColumns[sortedIndex] = _declarationColumns[declarationIndex];
            sortedDeclarationIndices[sortedIndex] = declarationIndex;
        }
    }

    private int CompareDeclarationOrder(int left, int right)
    {
        var diff = _declarationNameIds[left].CompareTo(_declarationNameIds[right]);
        if (diff != 0)
            return diff;

        diff = _declarationFileRanks[left].CompareTo(_declarationFileRanks[right]);
        if (diff != 0)
            return diff;

        diff = _declarationLineNumbers[left].CompareTo(_declarationLineNumbers[right]);
        if (diff != 0)
            return diff;

        diff = _declarationColumns[left].CompareTo(_declarationColumns[right]);
        if (diff != 0)
            return diff;

        return left.CompareTo(right);
    }

    private int CalculateChecksum(
        int[] sortedNameIds,
        int[] sortedFileRanks,
        int[] sortedLineNumbers,
        int[] sortedColumns,
        int[] sortedDeclarationIndices)
    {
        var checksum = _declarationCount * 17;
        for (var i = 0; i < _declarationCount; i++)
        {
            checksum = checksum
                + (i + 1) * 97
                + sortedNameIds[i] * 31
                + sortedFileRanks[i] * 23
                + sortedLineNumbers[i] * 13
                + sortedColumns[i] * 7
                + sortedDeclarationIndices[i] * 3;
        }

        return checksum;
    }

    private delegate int BindingLookupBuildNearestDeclarationIndexInto(
        int[] declarationNameIds,
        int[] declarationFileRanks,
        int[] declarationLineNumbers,
        int[] declarationColumns,
        int[] tempDeclarationIndices,
        int[] stackLefts,
        int[] sortedNameIds,
        int[] sortedFileRanks,
        int[] sortedLineNumbers,
        int[] sortedColumns,
        int[] sortedDeclarationIndices);

    private delegate int BindingLookupBuildNearestDeclarationIndexChecksumInto(
        int[] declarationNameIds,
        int[] declarationFileRanks,
        int[] declarationLineNumbers,
        int[] declarationColumns,
        int[] tempDeclarationIndices,
        int[] stackLefts,
        int[] sortedNameIds,
        int[] sortedFileRanks,
        int[] sortedLineNumbers,
        int[] sortedColumns,
        int[] sortedDeclarationIndices);
}

/// <summary>
/// Dogfood benchmark for the source-context fallback that chooses the nearest in-file declaration
/// with a matching name before falling back to AST declaration scans.
///
/// The C# baseline mirrors <c>FindNearestBindingDeclarationByName</c>: scan declarations by name,
/// filter to the current file and preceding lines, sort by line/column descending, then pick the
/// first declaration. The N# candidate consumes sorted compact declaration facts and answers each
/// query with a binary-search upper bound over caller-owned integer buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceNearestDeclarationLookupBenchmarks
{
    private const int LargeDeclarationCount = 4096;
    private const int LargeQueryCount = 4096;
    private const int RepresentativeDeclarationCount = 512;
    private const int RepresentativeQueryCount = 4096;

    private NearestDeclarationChecksumInto _nsharpNearestDeclarationChecksum =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private readonly Dictionary<(string? File, int Line, int Column), int> _declarationIndices = new();
    private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _nameIds = new(StringComparer.Ordinal);

    private BindingMap _bindingMap = new();
    private int _declarationCount;
    private SymbolDeclaration[] _declarations = Array.Empty<SymbolDeclaration>();
    private int[] _queryFileRanks = Array.Empty<int>();
    private string[] _queryFiles = Array.Empty<string>();
    private int[] _queryLines = Array.Empty<int>();
    private int[] _queryNameIds = Array.Empty<int>();
    private string[] _queryNames = Array.Empty<string>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _sortedColumns = Array.Empty<int>();
    private int[] _sortedDeclarationIndices = Array.Empty<int>();
    private int[] _sortedFileRanks = Array.Empty<int>();
    private int[] _sortedLines = Array.Empty<int>();
    private int[] _sortedNameIds = Array.Empty<int>();
    private string[] _filesByRank = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpNearestDeclarationChecksum =
            NSharpCompiledMethod.Bind<NearestDeclarationChecksumInto>(
                DogfoodCompilerSources.CodeIntelligenceBindingLookup,
                "BindingLookupFindNearestDeclarationChecksumInto");

        _declarationCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDeclarationCount
            : LargeDeclarationCount;
        var queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;

        _bindingMap = new BindingMap();
        _declarationIndices.Clear();
        _fileRanks.Clear();
        _nameIds.Clear();

        _declarations = new SymbolDeclaration[_declarationCount];
        _queryFileRanks = new int[queryCount];
        _queryFiles = new string[queryCount];
        _queryLines = new int[queryCount];
        _queryNameIds = new int[queryCount];
        _queryNames = new string[queryCount];
        _nsharpResultIndices = new int[queryCount];

        BuildFiles();
        BuildDeclarations();
        BuildSortedDeclarations();
        BuildQueries(queryCount);

        var expectedChecksum = CSharpNearestDeclarationByName_QueryBatch();
        var actualChecksum = NSharpNearestDeclarationByName_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# nearest declaration checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < queryCount; i++)
        {
            var expectedIndex = ResolveExpectedDeclarationIndex(i);
            if (_nsharpResultIndices[i] != expectedIndex)
            {
                throw new InvalidOperationException(
                    $"N# nearest declaration mismatch for {Corpus} at query {i}: " +
                    $"expected declaration index {expectedIndex}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpNearestDeclarationByName_QueryBatch()
    {
        var checksum = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var declaration = _bindingMap.FindDeclarationsByName(_queryNames[i])
                .Where(candidate => string.Equals(candidate.File, _queryFiles[i], StringComparison.Ordinal)
                                    && candidate.Line <= _queryLines[i])
                .OrderByDescending(candidate => candidate.Line)
                .ThenByDescending(candidate => candidate.Column)
                .FirstOrDefault();
            if (declaration == null)
                continue;

            var declarationIndex = _declarationIndices[(declaration.File, declaration.Line, declaration.Column)];
            checksum++;
            checksum = checksum
                + GetNameId(declaration.Name) * 13
                + declaration.Line * 31
                + declaration.Column * 17
                + declarationIndex;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpNearestDeclarationByName_QueryBatch() =>
        _nsharpNearestDeclarationChecksum(
            _sortedNameIds,
            _sortedFileRanks,
            _sortedLines,
            _sortedColumns,
            _sortedDeclarationIndices,
            _queryNameIds,
            _queryFileRanks,
            _queryLines,
            _nsharpResultIndices);

    private void BuildFiles()
    {
        var fileCount = Corpus == CompilerLexerCorpus.Representative ? 16 : 128;
        _filesByRank = new string[fileCount + 1];
        for (var i = 1; i <= fileCount; i++)
        {
            _filesByRank[i] = (i % 5) switch
            {
                0 => $"/repo/src/Program{i}.nl",
                1 => $"/repo/src/Features/Feature{i}.nl",
                2 => $"/repo/src/with space/File {i}.nl",
                3 => $@"C:\repo\module\File{i}.nl",
                _ => $"/repo/src/generated/File-{i}.nl"
            };
            _fileRanks[_filesByRank[i]] = i;
        }
    }

    private void BuildDeclarations()
    {
        var nameCount = Corpus == CompilerLexerCorpus.Representative ? 32 : 256;
        for (var i = 0; i < _declarationCount; i++)
        {
            var fileRank = i * 7 % (_filesByRank.Length - 1) + 1;
            var name = $"symbol{i % nameCount}";
            var line = i * 5 / nameCount + i % 11 + 1;
            var column = i * 17 % 120 + 1;
            var kind = i % 3 == 0 ? "variable" : i % 3 == 1 ? "function" : "class";
            var declaration = new SymbolDeclaration(name, _filesByRank[fileRank], line, column, kind);

            _bindingMap.RecordDeclaration(declaration);
            _declarations[i] = declaration;
            _declarationIndices[(declaration.File, declaration.Line, declaration.Column)] = i;
            GetNameId(name);
        }
    }

    private void BuildSortedDeclarations()
    {
        var order = new int[_declarationCount];
        for (var i = 0; i < order.Length; i++)
        {
            order[i] = i;
        }

        Array.Sort(order, CompareDeclarationOrder);

        _sortedNameIds = new int[_declarationCount];
        _sortedFileRanks = new int[_declarationCount];
        _sortedLines = new int[_declarationCount];
        _sortedColumns = new int[_declarationCount];
        _sortedDeclarationIndices = new int[_declarationCount];

        for (var sortedIndex = 0; sortedIndex < order.Length; sortedIndex++)
        {
            var declarationIndex = order[sortedIndex];
            var declaration = _declarations[declarationIndex];
            _sortedNameIds[sortedIndex] = GetNameId(declaration.Name);
            _sortedFileRanks[sortedIndex] = _fileRanks[declaration.File!];
            _sortedLines[sortedIndex] = declaration.Line;
            _sortedColumns[sortedIndex] = declaration.Column;
            _sortedDeclarationIndices[sortedIndex] = declarationIndex;
        }
    }

    private void BuildQueries(int queryCount)
    {
        var nameCount = Corpus == CompilerLexerCorpus.Representative ? 32 : 256;
        for (var i = 0; i < queryCount; i++)
        {
            switch (i % 10)
            {
                case <= 5:
                {
                    var declarationIndex = i * 37 % _declarationCount;
                    var declaration = _declarations[declarationIndex];
                    SetQuery(
                        i,
                        declaration.Name,
                        declaration.File!,
                        declaration.Line + i % 17);
                    break;
                }
                case <= 7:
                {
                    var declarationIndex = i * 19 % _declarationCount;
                    var declaration = _declarations[declarationIndex];
                    SetQuery(
                        i,
                        declaration.Name,
                        declaration.File!,
                        Math.Max(0, declaration.Line - 1));
                    break;
                }
                case 8:
                {
                    var fileRank = i * 13 % (_filesByRank.Length - 1) + 1;
                    SetQuery(i, $"symbol{i % nameCount}", _filesByRank[fileRank], 1_000_000 + i);
                    break;
                }
                default:
                {
                    var fileRank = i * 11 % (_filesByRank.Length - 1) + 1;
                    SetQuery(i, $"missing{i}", _filesByRank[fileRank], 1_000_000 + i);
                    break;
                }
            }
        }
    }

    private void SetQuery(int index, string name, string file, int line)
    {
        _queryNames[index] = name;
        _queryNameIds[index] = _nameIds.TryGetValue(name, out var nameId) ? nameId : -1;
        _queryFiles[index] = file;
        _queryFileRanks[index] = _fileRanks[file];
        _queryLines[index] = line;
    }

    private int ResolveExpectedDeclarationIndex(int queryIndex)
    {
        var declaration = _bindingMap.FindDeclarationsByName(_queryNames[queryIndex])
            .Where(candidate => string.Equals(candidate.File, _queryFiles[queryIndex], StringComparison.Ordinal)
                                && candidate.Line <= _queryLines[queryIndex])
            .OrderByDescending(candidate => candidate.Line)
            .ThenByDescending(candidate => candidate.Column)
            .FirstOrDefault();

        return declaration == null
            ? -1
            : _declarationIndices[(declaration.File, declaration.Line, declaration.Column)];
    }

    private int CompareDeclarationOrder(int left, int right)
    {
        var leftDeclaration = _declarations[left];
        var rightDeclaration = _declarations[right];
        var diff = GetNameId(leftDeclaration.Name).CompareTo(GetNameId(rightDeclaration.Name));
        if (diff != 0)
            return diff;

        diff = _fileRanks[leftDeclaration.File!].CompareTo(_fileRanks[rightDeclaration.File!]);
        if (diff != 0)
            return diff;

        diff = leftDeclaration.Line.CompareTo(rightDeclaration.Line);
        if (diff != 0)
            return diff;

        return leftDeclaration.Column.CompareTo(rightDeclaration.Column);
    }

    private int GetNameId(string name)
    {
        if (_nameIds.TryGetValue(name, out var id))
            return id;

        id = _nameIds.Count + 1;
        _nameIds.Add(name, id);
        return id;
    }

    private delegate int NearestDeclarationChecksumInto(
        int[] sortedNameIds,
        int[] sortedFileRanks,
        int[] sortedLineNumbers,
        int[] sortedColumns,
        int[] sortedDeclarationIndices,
        int[] queryNameIds,
        int[] queryFileRanks,
        int[] queryLineNumbers,
        int[] resultDeclarationIndices);
}
