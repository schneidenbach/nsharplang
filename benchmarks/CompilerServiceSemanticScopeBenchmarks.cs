using System;
using System.Collections.Generic;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for scoped visible-symbol lookup used by CLI completion.
///
/// The C# baseline uses the production <see cref="SemanticModel.GetVisibleVariablesAtPosition"/>
/// scan/sort/dictionary path. The N# candidate performs the hot scope selection and shadowing
/// pass over compact arrays, leaving final TypeInfo object ownership at the host boundary.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceSemanticScopeVisibleVariablesBenchmarks
{
    private SemanticScopeVisibleSymbolChecksumInto _nsharpChecksum = null!;

    private int[] _expectedScopeIds = Array.Empty<int>();
    private SemanticModel _model = new();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int[] _resultCounts = Array.Empty<int>();
    private int[] _resultScopeIds = Array.Empty<int>();
    private int[] _resultStarts = Array.Empty<int>();
    private int[] _resultSymbolIndices = Array.Empty<int>();
    private int[] _scopeDepths = Array.Empty<int>();
    private int[] _scopeEndColumns = Array.Empty<int>();
    private int[] _scopeEndLines = Array.Empty<int>();
    private int[] _scopeParentIds = Array.Empty<int>();
    private int[] _scopeStartColumns = Array.Empty<int>();
    private int[] _scopeStartLines = Array.Empty<int>();
    private int[] _scopeSymbolCounts = Array.Empty<int>();
    private int[] _scopeSymbolStarts = Array.Empty<int>();
    private int[] _slotNameIds = Array.Empty<int>();
    private int[] _sortedScopeIds = Array.Empty<int>();
    private int[] _sortedScopeMaxEndLines = Array.Empty<int>();
    private int[] _sortedScopeStartColumns = Array.Empty<int>();
    private int[] _sortedScopeStartLines = Array.Empty<int>();
    private int[] _symbolNameIds = Array.Empty<int>();
    private int[] _symbolNameLengths = Array.Empty<int>();
    private int[] _symbolTypeNameLengths = Array.Empty<int>();
    private int[] _touchedSlots = Array.Empty<int>();
    private readonly Dictionary<string, int> _nameIds = new(StringComparer.Ordinal);
    private int _symbolIndex;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpChecksum =
            NSharpCompiledMethod.Bind<SemanticScopeVisibleSymbolChecksumInto>(
                DogfoodCompilerSources.CodeIntelligenceSemanticScopes,
                "SemanticScopeVisibleSymbolChecksumInto");

        var depthPerChain = Corpus == CompilerLexerCorpus.Representative ? 8 : 16;
        var chainCount = Corpus == CompilerLexerCorpus.Representative ? 64 : 256;
        var symbolsPerScope = Corpus == CompilerLexerCorpus.Representative ? 4 : 6;
        var queryCount = Corpus == CompilerLexerCorpus.Representative ? 4096 : 8192;

        BuildScopeCorpus(chainCount, depthPerChain, symbolsPerScope, queryCount);

        var expectedChecksum = CSharpSemanticScopeVisibleVariables_QueryBatch();
        var actualChecksum = NSharpSemanticScopeVisibleVariables_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# semantic scope checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpSemanticScopeVisibleVariables_QueryBatch()
    {
        var checksum = 0;
        var total = 0;

        for (var i = 0; i < _queryLines.Length; i++)
        {
            var visible = _model.GetVisibleVariablesAtPosition(_queryLines[i], _queryColumns[i]);
            total += visible.Count;
            checksum += (_expectedScopeIds[i] + 1) * 31;

            var ordinal = 0;
            foreach (var (name, type) in visible)
            {
                checksum = checksum
                    + name.Length * 13
                    + type.ToString().Length * 7
                    + (ordinal + 1);
                ordinal++;
            }
        }

        return checksum + total * 17;
    }

    [Benchmark]
    public int NSharpSemanticScopeVisibleVariables_QueryBatch() =>
        _nsharpChecksum(
            _scopeParentIds,
            _scopeStartLines,
            _scopeStartColumns,
            _scopeEndLines,
            _scopeEndColumns,
            _scopeDepths,
            _scopeSymbolStarts,
            _scopeSymbolCounts,
            _symbolNameIds,
            _symbolNameLengths,
            _symbolTypeNameLengths,
            _sortedScopeIds,
            _sortedScopeStartLines,
            _sortedScopeStartColumns,
            _sortedScopeMaxEndLines,
            _queryLines,
            _queryColumns,
            _resultScopeIds,
            _resultStarts,
            _resultCounts,
            _resultSymbolIndices,
            _slotNameIds,
            _touchedSlots);

    private void BuildScopeCorpus(int chainCount, int depthPerChain, int symbolsPerScope, int queryCount)
    {
        _model = new SemanticModel();
        _nameIds.Clear();
        _symbolIndex = 0;

        var scopeCount = chainCount * depthPerChain;
        var symbolCount = scopeCount * (symbolsPerScope + 1);
        _scopeParentIds = new int[scopeCount];
        _scopeStartLines = new int[scopeCount];
        _scopeStartColumns = new int[scopeCount];
        _scopeEndLines = new int[scopeCount];
        _scopeEndColumns = new int[scopeCount];
        _scopeDepths = new int[scopeCount];
        _scopeSymbolStarts = new int[scopeCount];
        _scopeSymbolCounts = new int[scopeCount];
        _sortedScopeIds = new int[scopeCount];
        _sortedScopeStartLines = new int[scopeCount];
        _sortedScopeStartColumns = new int[scopeCount];
        _sortedScopeMaxEndLines = new int[scopeCount];
        _symbolNameIds = new int[symbolCount];
        _symbolNameLengths = new int[symbolCount];
        _symbolTypeNameLengths = new int[symbolCount];

        for (var chain = 0; chain < chainCount; chain++)
        {
            var baseLine = chain * 1000 + 1;
            var parent = -1;
            var openedScopes = new int[depthPerChain];

            for (var depth = 0; depth < depthPerChain; depth++)
            {
                var scopeId = _model.OpenScope(parent, baseLine + depth, 1);
                openedScopes[depth] = scopeId;
                parent = scopeId;

                _scopeParentIds[scopeId] = depth == 0 ? -1 : openedScopes[depth - 1];
                _scopeStartLines[scopeId] = baseLine + depth;
                _scopeStartColumns[scopeId] = 1;
                _scopeEndLines[scopeId] = baseLine + 900 - depth;
                _scopeEndColumns[scopeId] = 120;
                _scopeDepths[scopeId] = depth;
                _scopeSymbolStarts[scopeId] = _symbolIndex;

                AddScopedVariable(scopeId, "shadowed", $"T_shadow_{chain}_{depth}");
                for (var symbol = 1; symbol < symbolsPerScope; symbol++)
                {
                    AddScopedVariable(scopeId, $"v_{chain}_{depth}_{symbol}", $"T_{chain}_{depth}_{symbol}");
                }

                AddScopedFunction(scopeId, $"fn_{chain}_{depth}", $"F_{chain}_{depth}");
                _scopeSymbolCounts[scopeId] = _symbolIndex - _scopeSymbolStarts[scopeId];
            }

            for (var depth = depthPerChain - 1; depth >= 0; depth--)
            {
                _model.CloseScope(openedScopes[depth], baseLine + 900 - depth, 120);
            }
        }

        BuildSortedScopeIndex(scopeCount);

        _queryLines = new int[queryCount];
        _queryColumns = new int[queryCount];
        _expectedScopeIds = new int[queryCount];

        for (var i = 0; i < queryCount; i++)
        {
            var chain = i * 17 % chainCount;
            var visibleDepth = i % depthPerChain;
            var baseLine = chain * 1000 + 1;
            _queryLines[i] = baseLine + visibleDepth;
            _queryColumns[i] = 40;
            _expectedScopeIds[i] = chain * depthPerChain + visibleDepth;
        }

        var maxVisibleSymbols = depthPerChain * (symbolsPerScope + 1);
        _resultScopeIds = new int[queryCount];
        _resultStarts = new int[queryCount];
        _resultCounts = new int[queryCount];
        _resultSymbolIndices = new int[queryCount * maxVisibleSymbols];
        _slotNameIds = new int[Math.Max(1, _symbolNameIds.Length * 2 + 1)];
        _touchedSlots = new int[Math.Max(1, maxVisibleSymbols)];
    }

    private void AddScopedVariable(int scopeId, string name, string typeName)
    {
        var type = new SimpleTypeInfo(typeName);
        _model.RecordScopedVariable(scopeId, name, type);
        AddSymbol(name, typeName);
    }

    private void AddScopedFunction(int scopeId, string name, string typeName)
    {
        var type = new SimpleTypeInfo(typeName);
        _model.RecordScopedFunction(scopeId, name, type);
        AddSymbol(name, typeName);
    }

    private void AddSymbol(string name, string typeName)
    {
        _symbolNameIds[_symbolIndex] = GetOrAddNameId(name);
        _symbolNameLengths[_symbolIndex] = name.Length;
        _symbolTypeNameLengths[_symbolIndex] = typeName.Length;
        _symbolIndex++;
    }

    private int GetOrAddNameId(string name)
    {
        if (_nameIds.TryGetValue(name, out var id))
            return id;

        id = _nameIds.Count + 1;
        _nameIds.Add(name, id);
        return id;
    }

    private void BuildSortedScopeIndex(int scopeCount)
    {
        var order = new int[scopeCount];
        for (var i = 0; i < scopeCount; i++)
        {
            order[i] = i;
        }

        Array.Sort(order, CompareScopeStartOrder);

        var maxEndLine = 0;
        for (var sortedIndex = 0; sortedIndex < scopeCount; sortedIndex++)
        {
            var scopeIndex = order[sortedIndex];
            _sortedScopeIds[sortedIndex] = scopeIndex;
            _sortedScopeStartLines[sortedIndex] = _scopeStartLines[scopeIndex];
            _sortedScopeStartColumns[sortedIndex] = _scopeStartColumns[scopeIndex];

            if (_scopeEndLines[scopeIndex] > maxEndLine)
                maxEndLine = _scopeEndLines[scopeIndex];

            _sortedScopeMaxEndLines[sortedIndex] = maxEndLine;
        }
    }

    private int CompareScopeStartOrder(int left, int right)
    {
        var diff = _scopeStartLines[left].CompareTo(_scopeStartLines[right]);
        if (diff != 0)
            return diff;

        diff = _scopeStartColumns[left].CompareTo(_scopeStartColumns[right]);
        if (diff != 0)
            return diff;

        return left.CompareTo(right);
    }

    private delegate int SemanticScopeVisibleSymbolChecksumInto(
        int[] scopeParentIds,
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] scopeEndColumns,
        int[] scopeDepths,
        int[] scopeSymbolStarts,
        int[] scopeSymbolCounts,
        int[] symbolNameIds,
        int[] symbolNameLengths,
        int[] symbolTypeNameLengths,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines,
        int[] queryLines,
        int[] queryColumns,
        int[] resultScopeIds,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultSymbolIndices,
        int[] slotNameIds,
        int[] touchedSlots);
}

/// <summary>
/// Dogfood benchmark for sorted semantic-scope index construction used before scoped completion
/// and receiver lookup queries.
///
/// The C# baseline mirrors the current cache builder: allocate an order array, sort scope ids with a
/// comparer over start line/column/source id, then materialize sorted arrays and prefix max end lines.
/// The N# candidate fills caller-owned buffers, detects the common source-order case, and falls back
/// to comparer-free primitive quicksort for out-of-order scope tables.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceSemanticScopeIndexBuildBenchmarks
{
    private SemanticScopeBuildSortedIndexInto _nsharpBuildSortedIndex = null!;
    private SemanticScopeBuildSortedIndexChecksumInto _nsharpChecksum = null!;

    private int[] _csharpSortedScopeIds = Array.Empty<int>();
    private int[] _csharpSortedScopeMaxEndLines = Array.Empty<int>();
    private int[] _csharpSortedScopeStartColumns = Array.Empty<int>();
    private int[] _csharpSortedScopeStartLines = Array.Empty<int>();
    private int[] _nsharpSortedScopeIds = Array.Empty<int>();
    private int[] _nsharpSortedScopeMaxEndLines = Array.Empty<int>();
    private int[] _nsharpSortedScopeStartColumns = Array.Empty<int>();
    private int[] _nsharpSortedScopeStartLines = Array.Empty<int>();
    private int[] _scopeEndLines = Array.Empty<int>();
    private int[] _scopeStartColumns = Array.Empty<int>();
    private int[] _scopeStartLines = Array.Empty<int>();
    private int[] _stackLefts = Array.Empty<int>();
    private int[] _stackRights = Array.Empty<int>();
    private int[] _tempScopeIds = Array.Empty<int>();
    private int _scopeCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _scopeCount = Corpus == CompilerLexerCorpus.Representative ? 1024 : 8192;
        _nsharpBuildSortedIndex =
            NSharpCompiledMethod.Bind<SemanticScopeBuildSortedIndexInto>(
                DogfoodCompilerSources.CodeIntelligenceSemanticScopes,
                "SemanticScopeBuildSortedIndexInto");
        _nsharpChecksum =
            NSharpCompiledMethod.Bind<SemanticScopeBuildSortedIndexChecksumInto>(
                DogfoodCompilerSources.CodeIntelligenceSemanticScopes,
                "SemanticScopeBuildSortedIndexChecksumInto");

        _scopeStartLines = new int[_scopeCount];
        _scopeStartColumns = new int[_scopeCount];
        _scopeEndLines = new int[_scopeCount];
        _tempScopeIds = new int[_scopeCount];
        _stackLefts = new int[_scopeCount];
        _stackRights = new int[_scopeCount];
        _csharpSortedScopeIds = new int[_scopeCount];
        _csharpSortedScopeStartLines = new int[_scopeCount];
        _csharpSortedScopeStartColumns = new int[_scopeCount];
        _csharpSortedScopeMaxEndLines = new int[_scopeCount];
        _nsharpSortedScopeIds = new int[_scopeCount];
        _nsharpSortedScopeStartLines = new int[_scopeCount];
        _nsharpSortedScopeStartColumns = new int[_scopeCount];
        _nsharpSortedScopeMaxEndLines = new int[_scopeCount];

        BuildSourceOrderedScopeStarts();

        var expectedChecksum = CSharpSemanticScopeIndex_BuildChecksum();
        var actualChecksum = NSharpSemanticScopeIndex_BuildChecksum();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# semantic scope index checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpSemanticScopeIndex_Build()
    {
        BuildSortedScopeIndexWithCSharp(
            _csharpSortedScopeIds,
            _csharpSortedScopeStartLines,
            _csharpSortedScopeStartColumns,
            _csharpSortedScopeMaxEndLines);

        return _scopeCount
            + _csharpSortedScopeIds[0] * 31
            + _csharpSortedScopeMaxEndLines[_scopeCount - 1] * 17;
    }

    [Benchmark]
    public int NSharpSemanticScopeIndex_Build()
    {
        var count = _nsharpBuildSortedIndex(
            _scopeStartLines,
            _scopeStartColumns,
            _scopeEndLines,
            _tempScopeIds,
            _stackLefts,
            _stackRights,
            _nsharpSortedScopeIds,
            _nsharpSortedScopeStartLines,
            _nsharpSortedScopeStartColumns,
            _nsharpSortedScopeMaxEndLines);

        return count
            + _nsharpSortedScopeIds[0] * 31
            + _nsharpSortedScopeMaxEndLines[count - 1] * 17;
    }

    private int CSharpSemanticScopeIndex_BuildChecksum()
    {
        var order = new int[_scopeCount];
        for (var i = 0; i < _scopeCount; i++)
        {
            order[i] = i;
        }

        Array.Sort(order, CompareScopeStartOrder);

        var maxEndLine = 0;
        var checksum = _scopeCount * 17;
        for (var sortedIndex = 0; sortedIndex < _scopeCount; sortedIndex++)
        {
            var scopeIndex = order[sortedIndex];
            if (_scopeEndLines[scopeIndex] > maxEndLine)
                maxEndLine = _scopeEndLines[scopeIndex];

            checksum = checksum
                + (sortedIndex + 1) * 97
                + (scopeIndex + 1) * 31
                + _scopeStartLines[scopeIndex] * 13
                + _scopeStartColumns[scopeIndex] * 7
                + maxEndLine * 3;
        }

        return checksum;
    }

    private int NSharpSemanticScopeIndex_BuildChecksum() =>
        _nsharpChecksum(
            _scopeStartLines,
            _scopeStartColumns,
            _scopeEndLines,
            _tempScopeIds,
            _stackLefts,
            _stackRights,
            _nsharpSortedScopeIds,
            _nsharpSortedScopeStartLines,
            _nsharpSortedScopeStartColumns,
            _nsharpSortedScopeMaxEndLines);

    private void BuildSortedScopeIndexWithCSharp(
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines)
    {
        var order = new int[_scopeCount];
        for (var i = 0; i < _scopeCount; i++)
        {
            order[i] = i;
        }

        Array.Sort(order, CompareScopeStartOrder);

        var maxEndLine = 0;
        for (var sortedIndex = 0; sortedIndex < _scopeCount; sortedIndex++)
        {
            var scopeIndex = order[sortedIndex];
            sortedScopeIds[sortedIndex] = scopeIndex;
            sortedScopeStartLines[sortedIndex] = _scopeStartLines[scopeIndex];
            sortedScopeStartColumns[sortedIndex] = _scopeStartColumns[scopeIndex];

            if (_scopeEndLines[scopeIndex] > maxEndLine)
                maxEndLine = _scopeEndLines[scopeIndex];

            sortedScopeMaxEndLines[sortedIndex] = maxEndLine;
        }
    }

    private void BuildSourceOrderedScopeStarts()
    {
        var line = 1;
        for (var i = 0; i < _scopeCount; i++)
        {
            var depth = i & 15;
            _scopeStartLines[i] = line;
            _scopeStartColumns[i] = 1 + (depth & 3);
            _scopeEndLines[i] = line + 40 - depth;

            line += i % 7 == 0 ? 0 : 1;
        }

        for (var i = 1; i < _scopeCount; i++)
        {
            if (_scopeStartLines[i] < _scopeStartLines[i - 1])
                _scopeStartLines[i] = _scopeStartLines[i - 1];
            if (_scopeStartLines[i] == _scopeStartLines[i - 1] &&
                _scopeStartColumns[i] < _scopeStartColumns[i - 1])
            {
                _scopeStartColumns[i] = _scopeStartColumns[i - 1] + 1;
            }
        }
    }

    private int CompareScopeStartOrder(int left, int right)
    {
        var diff = _scopeStartLines[left].CompareTo(_scopeStartLines[right]);
        if (diff != 0)
            return diff;

        diff = _scopeStartColumns[left].CompareTo(_scopeStartColumns[right]);
        if (diff != 0)
            return diff;

        return left.CompareTo(right);
    }

    private delegate int SemanticScopeBuildSortedIndexInto(
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] tempScopeIds,
        int[] stackLefts,
        int[] stackRights,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines);

    private delegate int SemanticScopeBuildSortedIndexChecksumInto(
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] tempScopeIds,
        int[] stackLefts,
        int[] stackRights,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines);
}

/// <summary>
/// Dogfood benchmark for position-aware scoped identifier lookup used by member completion.
///
/// The C# baseline uses the production <see cref="SemanticModel.LookupIdentifierAtPosition"/>
/// scan path. The N# candidate finds the containing scope with the compact sorted scope index,
/// walks the parent chain, and writes the resolved symbol index into caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceSemanticScopeLookupBenchmarks
{
    private SemanticScopeLookupSymbolChecksumInto _nsharpChecksum = null!;

    private int[] _expectedScopeIds = Array.Empty<int>();
    private readonly Dictionary<string, int> _nameIds = new(StringComparer.Ordinal);
    private SemanticModel _model = new();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int[] _queryNameIds = Array.Empty<int>();
    private string[] _queryNames = Array.Empty<string>();
    private int[] _resultScopeIds = Array.Empty<int>();
    private int[] _resultSymbolIndices = Array.Empty<int>();
    private int[] _scopeDepths = Array.Empty<int>();
    private int[] _scopeEndColumns = Array.Empty<int>();
    private int[] _scopeEndLines = Array.Empty<int>();
    private int[] _scopeParentIds = Array.Empty<int>();
    private int[] _scopeStartColumns = Array.Empty<int>();
    private int[] _scopeStartLines = Array.Empty<int>();
    private int[] _scopeSymbolCounts = Array.Empty<int>();
    private int[] _scopeSymbolStarts = Array.Empty<int>();
    private int[] _sortedScopeIds = Array.Empty<int>();
    private int[] _sortedScopeMaxEndLines = Array.Empty<int>();
    private int[] _sortedScopeStartColumns = Array.Empty<int>();
    private int[] _sortedScopeStartLines = Array.Empty<int>();
    private int[] _symbolNameIds = Array.Empty<int>();
    private int[] _symbolNameLengths = Array.Empty<int>();
    private int[] _symbolTypeNameLengths = Array.Empty<int>();
    private int _symbolIndex;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpChecksum =
            NSharpCompiledMethod.Bind<SemanticScopeLookupSymbolChecksumInto>(
                DogfoodCompilerSources.CodeIntelligenceSemanticScopes,
                "SemanticScopeLookupSymbolChecksumInto");

        var depthPerChain = Corpus == CompilerLexerCorpus.Representative ? 8 : 16;
        var chainCount = Corpus == CompilerLexerCorpus.Representative ? 64 : 256;
        var symbolsPerScope = Corpus == CompilerLexerCorpus.Representative ? 4 : 6;
        var queryCount = Corpus == CompilerLexerCorpus.Representative ? 8192 : 16384;

        BuildScopeCorpus(chainCount, depthPerChain, symbolsPerScope, queryCount);

        var expectedChecksum = CSharpSemanticScopeLookup_QueryBatch();
        var actualChecksum = NSharpSemanticScopeLookup_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# semantic scope lookup checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpSemanticScopeLookup_QueryBatch()
    {
        var checksum = 0;
        var found = 0;

        for (var i = 0; i < _queryNames.Length; i++)
        {
            var type = _model.LookupIdentifierAtPosition(_queryNames[i], _queryLines[i], _queryColumns[i]);
            checksum += (_expectedScopeIds[i] + 1) * 31;
            if (type != null)
            {
                found++;
                checksum += _queryNames[i].Length * 13
                    + type.ToString().Length * 7;
            }
        }

        return checksum + found * 17;
    }

    [Benchmark]
    public int NSharpSemanticScopeLookup_QueryBatch() =>
        _nsharpChecksum(
            _scopeParentIds,
            _scopeStartLines,
            _scopeStartColumns,
            _scopeEndLines,
            _scopeEndColumns,
            _scopeDepths,
            _scopeSymbolStarts,
            _scopeSymbolCounts,
            _symbolNameIds,
            _symbolNameLengths,
            _symbolTypeNameLengths,
            _sortedScopeIds,
            _sortedScopeStartLines,
            _sortedScopeStartColumns,
            _sortedScopeMaxEndLines,
            _queryNameIds,
            _queryLines,
            _queryColumns,
            _resultScopeIds,
            _resultSymbolIndices);

    private void BuildScopeCorpus(int chainCount, int depthPerChain, int symbolsPerScope, int queryCount)
    {
        _model = new SemanticModel();
        _nameIds.Clear();
        _symbolIndex = 0;

        var scopeCount = chainCount * depthPerChain;
        var symbolCount = scopeCount * (symbolsPerScope + 1);
        _scopeParentIds = new int[scopeCount];
        _scopeStartLines = new int[scopeCount];
        _scopeStartColumns = new int[scopeCount];
        _scopeEndLines = new int[scopeCount];
        _scopeEndColumns = new int[scopeCount];
        _scopeDepths = new int[scopeCount];
        _scopeSymbolStarts = new int[scopeCount];
        _scopeSymbolCounts = new int[scopeCount];
        _sortedScopeIds = new int[scopeCount];
        _sortedScopeStartLines = new int[scopeCount];
        _sortedScopeStartColumns = new int[scopeCount];
        _sortedScopeMaxEndLines = new int[scopeCount];
        _symbolNameIds = new int[symbolCount];
        _symbolNameLengths = new int[symbolCount];
        _symbolTypeNameLengths = new int[symbolCount];

        for (var chain = 0; chain < chainCount; chain++)
        {
            var baseLine = chain * 1000 + 1;
            var parent = -1;
            var openedScopes = new int[depthPerChain];

            for (var depth = 0; depth < depthPerChain; depth++)
            {
                var scopeId = _model.OpenScope(parent, baseLine + depth, 1);
                openedScopes[depth] = scopeId;
                parent = scopeId;

                _scopeParentIds[scopeId] = depth == 0 ? -1 : openedScopes[depth - 1];
                _scopeStartLines[scopeId] = baseLine + depth;
                _scopeStartColumns[scopeId] = 1;
                _scopeEndLines[scopeId] = baseLine + 900 - depth;
                _scopeEndColumns[scopeId] = 120;
                _scopeDepths[scopeId] = depth;
                _scopeSymbolStarts[scopeId] = _symbolIndex;

                AddScopedVariable(scopeId, "shadowed", $"T_shadow_{chain}_{depth}");
                for (var symbol = 1; symbol < symbolsPerScope; symbol++)
                {
                    AddScopedVariable(scopeId, $"v_{chain}_{depth}_{symbol}", $"T_{chain}_{depth}_{symbol}");
                }

                AddScopedFunction(scopeId, $"fn_{chain}_{depth}", $"F_{chain}_{depth}");
                _scopeSymbolCounts[scopeId] = _symbolIndex - _scopeSymbolStarts[scopeId];
            }

            for (var depth = depthPerChain - 1; depth >= 0; depth--)
            {
                _model.CloseScope(openedScopes[depth], baseLine + 900 - depth, 120);
            }
        }

        BuildSortedScopeIndex(scopeCount);
        BuildQueries(chainCount, depthPerChain, symbolsPerScope, queryCount);

        _resultScopeIds = new int[queryCount];
        _resultSymbolIndices = new int[queryCount];
    }

    private void BuildQueries(int chainCount, int depthPerChain, int symbolsPerScope, int queryCount)
    {
        _queryNames = new string[queryCount];
        _queryNameIds = new int[queryCount];
        _queryLines = new int[queryCount];
        _queryColumns = new int[queryCount];
        _expectedScopeIds = new int[queryCount];

        for (var i = 0; i < queryCount; i++)
        {
            var chain = i * 19 % chainCount;
            var visibleDepth = i % depthPerChain;
            var baseLine = chain * 1000 + 1;
            var queryKind = i % 5;
            var name = queryKind switch
            {
                0 => "shadowed",
                1 => $"v_{chain}_{visibleDepth}_{1 + (i % (symbolsPerScope - 1))}",
                2 => $"fn_{chain}_{visibleDepth}",
                3 => $"v_{chain}_{Math.Max(0, visibleDepth - 1)}_1",
                _ => $"missing_{i & 15}"
            };

            _queryNames[i] = name;
            _queryNameIds[i] = GetOrAddNameId(name);
            _queryLines[i] = baseLine + visibleDepth;
            _queryColumns[i] = 40;
            _expectedScopeIds[i] = chain * depthPerChain + visibleDepth;
        }
    }

    private void AddScopedVariable(int scopeId, string name, string typeName)
    {
        var type = new SimpleTypeInfo(typeName);
        _model.RecordScopedVariable(scopeId, name, type);
        AddSymbol(name, typeName);
    }

    private void AddScopedFunction(int scopeId, string name, string typeName)
    {
        var type = new SimpleTypeInfo(typeName);
        _model.RecordScopedFunction(scopeId, name, type);
        AddSymbol(name, typeName);
    }

    private void AddSymbol(string name, string typeName)
    {
        _symbolNameIds[_symbolIndex] = GetOrAddNameId(name);
        _symbolNameLengths[_symbolIndex] = name.Length;
        _symbolTypeNameLengths[_symbolIndex] = typeName.Length;
        _symbolIndex++;
    }

    private int GetOrAddNameId(string name)
    {
        if (_nameIds.TryGetValue(name, out var id))
            return id;

        id = _nameIds.Count + 1;
        _nameIds.Add(name, id);
        return id;
    }

    private void BuildSortedScopeIndex(int scopeCount)
    {
        var order = new int[scopeCount];
        for (var i = 0; i < scopeCount; i++)
        {
            order[i] = i;
        }

        Array.Sort(order, CompareScopeStartOrder);

        var maxEndLine = 0;
        for (var sortedIndex = 0; sortedIndex < scopeCount; sortedIndex++)
        {
            var scopeIndex = order[sortedIndex];
            _sortedScopeIds[sortedIndex] = scopeIndex;
            _sortedScopeStartLines[sortedIndex] = _scopeStartLines[scopeIndex];
            _sortedScopeStartColumns[sortedIndex] = _scopeStartColumns[scopeIndex];

            if (_scopeEndLines[scopeIndex] > maxEndLine)
                maxEndLine = _scopeEndLines[scopeIndex];

            _sortedScopeMaxEndLines[sortedIndex] = maxEndLine;
        }
    }

    private int CompareScopeStartOrder(int left, int right)
    {
        var diff = _scopeStartLines[left].CompareTo(_scopeStartLines[right]);
        if (diff != 0)
            return diff;

        diff = _scopeStartColumns[left].CompareTo(_scopeStartColumns[right]);
        if (diff != 0)
            return diff;

        return left.CompareTo(right);
    }

    private delegate int SemanticScopeLookupSymbolChecksumInto(
        int[] scopeParentIds,
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] scopeEndColumns,
        int[] scopeDepths,
        int[] scopeSymbolStarts,
        int[] scopeSymbolCounts,
        int[] symbolNameIds,
        int[] symbolNameLengths,
        int[] symbolTypeNameLengths,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines,
        int[] queryNameIds,
        int[] queryLines,
        int[] queryColumns,
        int[] resultScopeIds,
        int[] resultSymbolIndices);
}
