using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class BindingLookupKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    private static readonly ConditionalWeakTable<BindingMap, BindingLookupCache> s_bindingLookupCaches = new();
    [ThreadStatic]
    private static BindingCandidateColumnScratch? t_bindingCandidateColumnScratch;

    internal static bool TryGetBindingCandidateColumns(
        int column,
        (int StartColumn, int EndColumn)? span,
        out int[] candidateColumns)
    {
        candidateColumns = Array.Empty<int>();

        var bindings = s_bindings.Value;

        var maxCandidateCount = 3;
        if (span is { } spanValue && spanValue.StartColumn > 0 && spanValue.EndColumn >= spanValue.StartColumn)
        {
            var spanLength = spanValue.EndColumn - spanValue.StartColumn + 1;
            maxCandidateCount += spanLength;
        }

        var scratch = t_bindingCandidateColumnScratch ??= new BindingCandidateColumnScratch();
        scratch.EnsureCapacity(maxCandidateCount);
        scratch.QueryColumns[0] = column;
        scratch.SpanStartColumns[0] = span?.StartColumn ?? -1;
        scratch.SpanEndColumns[0] = span?.EndColumn ?? -1;

        var total = bindings.BindingLookupCandidateColumns(
            scratch.QueryColumns,
            scratch.SpanStartColumns,
            scratch.SpanEndColumns,
            scratch.ResultStarts,
            scratch.ResultCounts,
            scratch.ResultColumns);
        var count = scratch.ResultCounts[0];
        candidateColumns = new int[count];
        Array.Copy(scratch.ResultColumns, scratch.ResultStarts[0], candidateColumns, 0, count);
        return true;
    }

    internal static bool TryResolveBindingDeclaration(
        BindingMap bindingMap,
        string filePath,
        int line,
        int[] candidateColumns,
        out SymbolDeclaration? declaration)
    {
        declaration = null;

        var bindings = s_bindings.Value;

        if (candidateColumns.Length == 0)
            return true;

        var cache = s_bindingLookupCaches.GetValue(bindingMap, static map => new BindingLookupCache(map));
        return cache.TryResolve(bindings, filePath, line, candidateColumns, out declaration);
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<BindingLookupCandidateColumnsInto>(programType, "BindingLookupCandidateColumnsInto"),
            DogfoodKernelLoader.CreateDelegate<BindingLookupBuildSlotsInto>(programType, "BindingLookupBuildSlotsInto"),
            DogfoodKernelLoader.CreateDelegate<BindingLookupQueryDeclarationIndicesInto>(programType, "BindingLookupQueryDeclarationIndicesInto")));

    private delegate int BindingLookupCandidateColumnsInto(
        int[] queryColumns,
        int[] spanStartColumns,
        int[] spanEndColumns,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultColumns);

    private delegate int BindingLookupBuildSlotsInto(
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] slotIndices);

    private delegate int BindingLookupQueryDeclarationIndicesInto(
        int[] declarationFileRanks,
        int[] declarationLineNumbers,
        int[] declarationColumns,
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

    private sealed record Bindings(
        BindingLookupCandidateColumnsInto BindingLookupCandidateColumns,
        BindingLookupBuildSlotsInto BindingLookupBuildSlots,
        BindingLookupQueryDeclarationIndicesInto BindingLookupQueryDeclarationIndices);

    private sealed class BindingLookupCache
    {
        private readonly object _gate = new();
        private readonly Dictionary<(string? File, int Line, int Column), int> _declarationIndices = new();
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);
        private readonly BindingMap _map;
        private int[] _bindingColumns = Array.Empty<int>();
        private int[] _bindingDeclarationIndices = Array.Empty<int>();
        private int[] _bindingFileRanks = Array.Empty<int>();
        private int[] _bindingLineNumbers = Array.Empty<int>();
        private int[] _bindingSlotIndices = Array.Empty<int>();
        private int[] _declarationColumns = Array.Empty<int>();
        private int[] _declarationFileRanks = Array.Empty<int>();
        private int[] _declarationLineNumbers = Array.Empty<int>();
        private int[] _declarationSlotIndices = Array.Empty<int>();
        private SymbolDeclaration[] _declarations = Array.Empty<SymbolDeclaration>();
        private int[] _queryColumns = Array.Empty<int>();
        private int[] _queryFileRanks = Array.Empty<int>();
        private int[] _queryLineNumbers = Array.Empty<int>();
        private int[] _resultDeclarationIndices = Array.Empty<int>();
        private int _version = -1;

        public BindingLookupCache(BindingMap map)
        {
            _map = map;
        }

        public bool TryResolve(
            Bindings bindings,
            string filePath,
            int line,
            int[] candidateColumns,
            out SymbolDeclaration? declaration)
        {
            declaration = null;
            lock (_gate)
            {
                EnsureBuilt(bindings);
                if (_declarations.Length == 0 || candidateColumns.Length == 0)
                    return true;

                var fileRank = GetExistingFileRank(filePath);
                if (fileRank < 0)
                    return true;

                EnsureQueryCapacity(candidateColumns.Length);
                for (var i = 0; i < candidateColumns.Length; i++)
                {
                    _queryFileRanks[i] = fileRank;
                    _queryLineNumbers[i] = line;
                    _queryColumns[i] = candidateColumns[i];
                    _resultDeclarationIndices[i] = -1;
                }

                bindings.BindingLookupQueryDeclarationIndices(
                    _declarationFileRanks,
                    _declarationLineNumbers,
                    _declarationColumns,
                    _declarationSlotIndices,
                    _bindingFileRanks,
                    _bindingLineNumbers,
                    _bindingColumns,
                    _bindingDeclarationIndices,
                    _bindingSlotIndices,
                    _queryFileRanks,
                    _queryLineNumbers,
                    _queryColumns,
                    _resultDeclarationIndices);

                for (var i = 0; i < candidateColumns.Length; i++)
                {
                    var declarationIndex = _resultDeclarationIndices[i];
                    if (declarationIndex >= 0 && declarationIndex < _declarations.Length)
                    {
                        declaration = _declarations[declarationIndex];
                        return true;
                    }
                }

                return true;
            }
        }

        private void EnsureBuilt(Bindings bindings)
        {
            if (_version == _map.Version)
                return;

            _declarationIndices.Clear();
            _fileRanks.Clear();

            var declarationCount = _map.DeclarationEntries.Count;
            _declarations = new SymbolDeclaration[declarationCount];
            _declarationFileRanks = new int[declarationCount];
            _declarationLineNumbers = new int[declarationCount];
            _declarationColumns = new int[declarationCount];
            _declarationSlotIndices = declarationCount > 0
                ? new int[declarationCount * 2 + 1]
                : Array.Empty<int>();

            var declarationIndex = 0;
            foreach (var declaration in _map.DeclarationEntries.Values)
            {
                _declarations[declarationIndex] = declaration;
                _declarationFileRanks[declarationIndex] = GetOrAddFileRank(declaration.File);
                _declarationLineNumbers[declarationIndex] = declaration.Line;
                _declarationColumns[declarationIndex] = declaration.Column;
                _declarationIndices[(declaration.File, declaration.Line, declaration.Column)] = declarationIndex;
                declarationIndex++;
            }

            var bindingCount = _map.BindingEntries.Count;
            _bindingFileRanks = new int[bindingCount];
            _bindingLineNumbers = new int[bindingCount];
            _bindingColumns = new int[bindingCount];
            _bindingDeclarationIndices = new int[bindingCount];
            _bindingSlotIndices = bindingCount > 0
                ? new int[bindingCount * 2 + 1]
                : Array.Empty<int>();

            var bindingIndex = 0;
            foreach (var (usage, declaration) in _map.BindingEntries)
            {
                _bindingFileRanks[bindingIndex] = GetOrAddFileRank(usage.File);
                _bindingLineNumbers[bindingIndex] = usage.Line;
                _bindingColumns[bindingIndex] = usage.Col;
                _bindingDeclarationIndices[bindingIndex] = _declarationIndices.TryGetValue(
                    (declaration.File, declaration.Line, declaration.Column),
                    out var mappedDeclarationIndex)
                    ? mappedDeclarationIndex
                    : -1;
                bindingIndex++;
            }

            bindings.BindingLookupBuildSlots(
                _declarationFileRanks,
                _declarationLineNumbers,
                _declarationColumns,
                _declarationSlotIndices);
            bindings.BindingLookupBuildSlots(
                _bindingFileRanks,
                _bindingLineNumbers,
                _bindingColumns,
                _bindingSlotIndices);

            _version = _map.Version;
        }

        private int GetOrAddFileRank(string? file)
        {
            if (file == null)
                return 0;

            if (_fileRanks.TryGetValue(file, out var rank))
                return rank;

            rank = _fileRanks.Count + 1;
            _fileRanks.Add(file, rank);
            return rank;
        }

        private int GetExistingFileRank(string? file)
        {
            if (file == null)
                return 0;

            return _fileRanks.TryGetValue(file, out var rank) ? rank : -1;
        }

        private void EnsureQueryCapacity(int count)
        {
            if (_queryFileRanks.Length >= count)
                return;

            _queryFileRanks = new int[count];
            _queryLineNumbers = new int[count];
            _queryColumns = new int[count];
            _resultDeclarationIndices = new int[count];
        }
    }
}
