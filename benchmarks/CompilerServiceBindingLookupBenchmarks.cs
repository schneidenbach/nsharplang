using System;
using System.Collections.Generic;
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
