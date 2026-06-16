using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class NSharpCodeIntelligenceDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    private static readonly ConditionalWeakTable<BindingMap, BindingLookupCache> s_bindingLookupCaches = new();
    private static readonly ConditionalWeakTable<ProjectSnapshot, SnapshotCache> s_snapshotCaches = new();
    private static readonly ConditionalWeakTable<string, SourceLineCache> s_sourceLineCaches = new();
    [ThreadStatic]
    private static BindingCandidateColumnScratch? t_bindingCandidateColumnScratch;
    internal static bool TryGetBindingCandidateColumns(
        int column,
        (int StartColumn, int EndColumn)? span,
        out int[] candidateColumns)
    {
        candidateColumns = Array.Empty<int>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var maxCandidateCount = 3;
        if (span is { } spanValue && spanValue.StartColumn > 0 && spanValue.EndColumn >= spanValue.StartColumn)
        {
            var spanLength = spanValue.EndColumn - spanValue.StartColumn + 1;
            if (spanLength < 0)
                return false;

            maxCandidateCount += spanLength;
        }

        var scratch = t_bindingCandidateColumnScratch ??= new BindingCandidateColumnScratch();
        scratch.EnsureCapacity(maxCandidateCount);
        scratch.QueryColumns[0] = column;
        scratch.SpanStartColumns[0] = span?.StartColumn ?? -1;
        scratch.SpanEndColumns[0] = span?.EndColumn ?? -1;

        try
        {
            var total = bindings.BindingLookupCandidateColumns(
                scratch.QueryColumns,
                scratch.SpanStartColumns,
                scratch.SpanEndColumns,
                scratch.ResultStarts,
                scratch.ResultCounts,
                scratch.ResultColumns);
            var count = scratch.ResultCounts[0];
            if (total < 0 || total > scratch.ResultColumns.Length || count < 0 || count > total)
                return false;

            candidateColumns = new int[count];
            Array.Copy(scratch.ResultColumns, scratch.ResultStarts[0], candidateColumns, 0, count);
            return true;
        }
        catch
        {
            candidateColumns = Array.Empty<int>();
            return false;
        }
    }

    internal static bool TryExtractIdentifierSpan(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int column,
        out (int StartColumn, int EndColumn)? span)
    {
        span = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractIdentifierSpan(bindings, line, column, out span);
        }
        catch
        {
            span = null;
            return false;
        }
    }

    internal static bool TryExtractDocComment(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int definitionLine,
        out string? documentation)
    {
        documentation = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractDocComment(bindings, definitionLine, out documentation);
        }
        catch
        {
            documentation = null;
            return false;
        }
    }

    internal static bool TrySelectedSpanMatchesDeclarationName(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int declarationColumn,
        string declarationName,
        int selectedStartColumn,
        int selectedEndColumn,
        out bool matches)
    {
        matches = false;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TrySelectedSpanMatchesDeclarationName(
                bindings,
                line,
                declarationColumn,
                declarationName,
                selectedStartColumn,
                selectedEndColumn,
                out matches);
        }
        catch
        {
            matches = false;
            return false;
        }
    }

    internal static bool TryFindIdentifierNameColumn(
        string? source,
        string name,
        int line,
        int fallbackColumn,
        out int column)
    {
        column = fallbackColumn;
        if (source == null || string.IsNullOrWhiteSpace(name))
            return false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_sourceLineCaches.GetValue(source, static key => new SourceLineCache(key));
            return cache.TryFindIdentifierNameColumn(bindings, name, line, fallbackColumn, out column);
        }
        catch
        {
            column = fallbackColumn;
            return false;
        }
    }

    internal static bool TryExtractCompletionPrefix(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int column,
        out string? prefix)
    {
        prefix = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractCompletionPrefix(bindings, line, column, out prefix);
        }
        catch
        {
            prefix = null;
            return false;
        }
    }

    internal static bool TryExtractIdentifierName(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int column,
        out string? name)
    {
        name = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractIdentifierName(bindings, line, column, out name);
        }
        catch
        {
            name = null;
            return false;
        }
    }

    internal static bool TryExtractMemberReceiverName(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int memberStartColumn,
        out string? receiverName)
    {
        receiverName = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractMemberReceiverName(bindings, line, memberStartColumn, out receiverName);
        }
        catch
        {
            receiverName = null;
            return false;
        }
    }

    internal static bool TryExtractSourceContext(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        out string? context)
    {
        context = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractSourceContext(bindings, line, out context);
        }
        catch
        {
            context = null;
            return false;
        }
    }

    internal static bool TryExtractSourceLine(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        out string? text)
    {
        text = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractSourceLine(bindings, line, out text);
        }
        catch
        {
            text = null;
            return false;
        }
    }

    internal static bool TryExtractSourceLine(string source, int line, out string? text)
    {
        text = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_sourceLineCaches.GetValue(source, static key => new SourceLineCache(key));
            return cache.TryExtractSourceLine(bindings, line, out text);
        }
        catch
        {
            text = null;
            return false;
        }
    }

    internal static bool TryExtractEditorIdentifierSpan(
        string source,
        int line,
        int column,
        out (int StartColumn, int EndColumn, string Name)? span)
    {
        span = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_sourceLineCaches.GetValue(source, static key => new SourceLineCache(key));
            return cache.TryExtractEditorIdentifierSpan(bindings, line, column, out span);
        }
        catch
        {
            span = null;
            return false;
        }
    }

    internal static bool TryExtractVariableDeclarationName(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        out string? name)
    {
        name = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractVariableDeclarationName(bindings, line, out name);
        }
        catch
        {
            name = null;
            return false;
        }
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
        if (bindings == null)
            return false;

        if (candidateColumns.Length == 0)
            return true;

        try
        {
            var cache = s_bindingLookupCaches.GetValue(bindingMap, static map => new BindingLookupCache(map));
            return cache.TryResolve(bindings, filePath, line, candidateColumns, out declaration);
        }
        catch
        {
            declaration = null;
            return false;
        }
    }

    internal static bool TryFindNearestBindingDeclarationByName(
        BindingMap bindingMap,
        string filePath,
        string name,
        int line,
        out SymbolDeclaration? declaration)
    {
        declaration = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (string.IsNullOrEmpty(name))
            return true;

        try
        {
            var cache = s_bindingLookupCaches.GetValue(bindingMap, static map => new BindingLookupCache(map));
            return cache.TryFindNearestDeclaration(bindings, filePath, name, line, out declaration);
        }
        catch
        {
            declaration = null;
            return false;
        }
    }

    private static FileCache GetFileCache(ProjectSnapshot snapshot, string filePath, string source)
    {
        var snapshotCache = s_snapshotCaches.GetValue(snapshot, static _ => new SnapshotCache());
        return snapshotCache.GetFileCache(Path.GetFullPath(filePath), source);
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<BuildCodeIntelligenceLineRangesInto>(programType, "BuildCodeIntelligenceLineRangesInto"),
                CreateDelegate<BuildCodeIntelligenceMemberReceiverCacheInto>(programType, "BuildCodeIntelligenceMemberReceiverCacheInto"),
                CreateDelegate<BuildCodeIntelligenceVariableDeclarationNameCacheInto>(programType, "BuildCodeIntelligenceVariableDeclarationNameCacheInto"),
                CreateDelegate<CodeIntelligenceDeclarationNameMatchesFromLinesInto>(programType, "CodeIntelligenceDeclarationNameMatchesFromLinesInto"),
                CreateDelegate<CodeIntelligenceIdentifierNameColumnsFromLinesInto>(programType, "CodeIntelligenceIdentifierNameColumnsFromLinesInto"),
                CreateDelegate<CodeIntelligenceIdentifierSpansFromLinesInto>(programType, "CodeIntelligenceIdentifierSpansFromLinesInto"),
                CreateDelegate<CodeIntelligenceEditorIdentifierSpansFromLinesInto>(programType, "CodeIntelligenceEditorIdentifierSpansFromLinesInto"),
                CreateDelegate<CodeIntelligenceCompletionPrefixesFromLinesInto>(programType, "CodeIntelligenceCompletionPrefixesFromLinesInto"),
                CreateDelegate<CodeIntelligenceDocCommentLinesFromLinesInto>(programType, "CodeIntelligenceDocCommentLinesFromLinesInto"),
                CreateDelegate<CodeIntelligenceMemberReceiversFromCacheInto>(programType, "CodeIntelligenceMemberReceiversFromCacheInto"),
                CreateDelegate<CodeIntelligenceSourceContextsFromLinesInto>(programType, "CodeIntelligenceSourceContextsFromLinesInto"),
                CreateDelegate<CodeIntelligenceSourceLinesFromLinesInto>(programType, "CodeIntelligenceSourceLinesFromLinesInto"),
                CreateDelegate<CodeIntelligenceVariableDeclarationNamesFromCacheInto>(programType, "CodeIntelligenceVariableDeclarationNamesFromCacheInto"),
                CreateDelegate<BindingLookupCandidateColumnsInto>(programType, "BindingLookupCandidateColumnsInto"),
                CreateDelegate<BindingLookupBuildSlotsInto>(programType, "BindingLookupBuildSlotsInto"),
                CreateDelegate<BindingLookupQueryDeclarationIndicesInto>(programType, "BindingLookupQueryDeclarationIndicesInto"),
                CreateDelegate<BindingLookupBuildNearestDeclarationIndexInto>(programType, "BindingLookupBuildNearestDeclarationIndexInto"),
                CreateDelegate<BindingLookupFindNearestDeclarationIndicesInto>(programType, "BindingLookupFindNearestDeclarationIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    private delegate int BuildCodeIntelligenceLineRangesInto(string source, int[] starts, int[] lengths);

    private delegate int BuildCodeIntelligenceMemberReceiverCacheInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] receiverStartsBySeparator,
        int[] receiverLengthsBySeparator);

    private delegate int BuildCodeIntelligenceVariableDeclarationNameCacheInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] nameStartsByLine,
        int[] nameLengthsByLine);

    private delegate int CodeIntelligenceIdentifierSpansFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] queryColumns,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceEditorIdentifierSpansFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] queryColumns,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceDeclarationNameMatchesFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] declarationColumns,
        string[] declarationNames,
        int[] selectedStartColumns,
        int[] selectedEndColumns,
        int[] resultMatches);

    private delegate int CodeIntelligenceIdentifierNameColumnsFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        string[] declarationNames,
        int[] fallbackColumns,
        int[] resultColumns);

    private delegate int CodeIntelligenceCompletionPrefixesFromLinesInto(
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] queryColumns,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceDocCommentLinesFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int definitionLine,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceMemberReceiversFromCacheInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] receiverStartsBySeparator,
        int[] receiverLengthsBySeparator,
        int[] queryLines,
        int[] memberStartColumns,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceSourceContextsFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceSourceLinesFromLinesInto(
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceVariableDeclarationNamesFromCacheInto(
        int lineCount,
        int[] nameStartsByLine,
        int[] nameLengthsByLine,
        int[] queryLines,
        int[] resultStarts,
        int[] resultLengths);

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

    private delegate int BindingLookupFindNearestDeclarationIndicesInto(
        int[] sortedNameIds,
        int[] sortedFileRanks,
        int[] sortedLineNumbers,
        int[] sortedColumns,
        int[] sortedDeclarationIndices,
        int[] queryNameIds,
        int[] queryFileRanks,
        int[] queryLineNumbers,
        int[] resultDeclarationIndices);

    private sealed record Bindings(
        BuildCodeIntelligenceLineRangesInto BuildLineRanges,
        BuildCodeIntelligenceMemberReceiverCacheInto BuildMemberReceiverCache,
        BuildCodeIntelligenceVariableDeclarationNameCacheInto BuildVariableDeclarationNameCache,
        CodeIntelligenceDeclarationNameMatchesFromLinesInto DeclarationNameMatchesFromLines,
        CodeIntelligenceIdentifierNameColumnsFromLinesInto IdentifierNameColumnsFromLines,
        CodeIntelligenceIdentifierSpansFromLinesInto IdentifierSpansFromLines,
        CodeIntelligenceEditorIdentifierSpansFromLinesInto EditorIdentifierSpansFromLines,
        CodeIntelligenceCompletionPrefixesFromLinesInto CompletionPrefixesFromLines,
        CodeIntelligenceDocCommentLinesFromLinesInto DocCommentLinesFromLines,
        CodeIntelligenceMemberReceiversFromCacheInto MemberReceiversFromCache,
        CodeIntelligenceSourceContextsFromLinesInto SourceContextsFromLines,
        CodeIntelligenceSourceLinesFromLinesInto SourceLinesFromLines,
        CodeIntelligenceVariableDeclarationNamesFromCacheInto VariableDeclarationNamesFromCache,
        BindingLookupCandidateColumnsInto BindingLookupCandidateColumns,
        BindingLookupBuildSlotsInto BindingLookupBuildSlots,
        BindingLookupQueryDeclarationIndicesInto BindingLookupQueryDeclarationIndices,
        BindingLookupBuildNearestDeclarationIndexInto BindingLookupBuildNearestDeclarationIndex,
        BindingLookupFindNearestDeclarationIndicesInto BindingLookupFindNearestDeclarationIndices);

    private sealed class BindingCandidateColumnScratch
    {
        public int[] QueryColumns = new int[1];
        public int[] ResultColumns = Array.Empty<int>();
        public int[] ResultCounts = new int[1];
        public int[] ResultStarts = new int[1];
        public int[] SpanEndColumns = new int[1];
        public int[] SpanStartColumns = new int[1];

        public void EnsureCapacity(int resultCapacity)
        {
            if (ResultColumns.Length < resultCapacity)
            {
                ResultColumns = new int[resultCapacity];
            }
        }
    }

    private sealed class BindingLookupCache
    {
        private readonly object _gate = new();
        private readonly Dictionary<(string? File, int Line, int Column), int> _declarationIndices = new();
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);
        private readonly BindingMap _map;
        private readonly Dictionary<string, int> _nameIds = new(StringComparer.Ordinal);

        private int[] _bindingColumns = Array.Empty<int>();
        private int[] _bindingDeclarationIndices = Array.Empty<int>();
        private int[] _bindingFileRanks = Array.Empty<int>();
        private int[] _bindingLineNumbers = Array.Empty<int>();
        private int[] _bindingSlotIndices = Array.Empty<int>();
        private int[] _declarationColumns = Array.Empty<int>();
        private int[] _declarationFileRanks = Array.Empty<int>();
        private int[] _declarationLineNumbers = Array.Empty<int>();
        private int[] _declarationNameIds = Array.Empty<int>();
        private int[] _declarationSlotIndices = Array.Empty<int>();
        private SymbolDeclaration[] _declarations = Array.Empty<SymbolDeclaration>();
        private int[] _queryColumns = Array.Empty<int>();
        private int[] _queryFileRanks = Array.Empty<int>();
        private int[] _queryLineNumbers = Array.Empty<int>();
        private int[] _queryNameIds = Array.Empty<int>();
        private int[] _resultDeclarationIndices = Array.Empty<int>();
        private int[] _sortStackLefts = Array.Empty<int>();
        private int[] _sortTempDeclarationIndices = Array.Empty<int>();
        private int[] _sortedDeclarationColumns = Array.Empty<int>();
        private int[] _sortedDeclarationFileRanks = Array.Empty<int>();
        private int[] _sortedDeclarationIndices = Array.Empty<int>();
        private int[] _sortedDeclarationLineNumbers = Array.Empty<int>();
        private int[] _sortedDeclarationNameIds = Array.Empty<int>();
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

        public bool TryFindNearestDeclaration(
            Bindings bindings,
            string filePath,
            string name,
            int line,
            out SymbolDeclaration? declaration)
        {
            declaration = null;
            lock (_gate)
            {
                EnsureBuilt(bindings);
                if (_declarations.Length == 0)
                    return true;

                var fileRank = GetExistingFileRank(filePath);
                if (fileRank < 0)
                    return true;

                var nameId = GetExistingNameId(name);
                if (nameId < 0)
                    return true;

                EnsureQueryCapacity(1);
                _queryNameIds[0] = nameId;
                _queryFileRanks[0] = fileRank;
                _queryLineNumbers[0] = line;
                _resultDeclarationIndices[0] = -1;

                bindings.BindingLookupFindNearestDeclarationIndices(
                    _sortedDeclarationNameIds,
                    _sortedDeclarationFileRanks,
                    _sortedDeclarationLineNumbers,
                    _sortedDeclarationColumns,
                    _sortedDeclarationIndices,
                    _queryNameIds,
                    _queryFileRanks,
                    _queryLineNumbers,
                    _resultDeclarationIndices);

                var declarationIndex = _resultDeclarationIndices[0];
                if (declarationIndex >= 0 && declarationIndex < _declarations.Length)
                {
                    declaration = _declarations[declarationIndex];
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
            _nameIds.Clear();

            var declarationCount = _map.DeclarationEntries.Count;
            _declarations = new SymbolDeclaration[declarationCount];
            _declarationFileRanks = new int[declarationCount];
            _declarationLineNumbers = new int[declarationCount];
            _declarationColumns = new int[declarationCount];
            _declarationNameIds = new int[declarationCount];
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
                _declarationNameIds[declarationIndex] = GetOrAddNameId(declaration.Name);
                _declarationIndices[(declaration.File, declaration.Line, declaration.Column)] = declarationIndex;
                declarationIndex++;
            }

            BuildNearestDeclarationIndex(bindings);

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

        private void BuildNearestDeclarationIndex(Bindings bindings)
        {
            var declarationCount = _declarations.Length;
            _sortedDeclarationNameIds = new int[declarationCount];
            _sortedDeclarationFileRanks = new int[declarationCount];
            _sortedDeclarationLineNumbers = new int[declarationCount];
            _sortedDeclarationColumns = new int[declarationCount];
            _sortedDeclarationIndices = new int[declarationCount];
            _sortTempDeclarationIndices = new int[declarationCount + 1];
            _sortStackLefts = new int[declarationCount + 1];

            if (declarationCount == 0)
                return;

            var dogfoodCount = bindings.BindingLookupBuildNearestDeclarationIndex(
                _declarationNameIds,
                _declarationFileRanks,
                _declarationLineNumbers,
                _declarationColumns,
                _sortTempDeclarationIndices,
                _sortStackLefts,
                _sortedDeclarationNameIds,
                _sortedDeclarationFileRanks,
                _sortedDeclarationLineNumbers,
                _sortedDeclarationColumns,
                _sortedDeclarationIndices);

            if (dogfoodCount == declarationCount)
                return;

            var order = new int[declarationCount];
            for (var i = 0; i < declarationCount; i++)
            {
                order[i] = i;
            }

            Array.Sort(order, CompareDeclarationOrder);

            for (var sortedIndex = 0; sortedIndex < declarationCount; sortedIndex++)
            {
                var declarationIndex = order[sortedIndex];
                _sortedDeclarationNameIds[sortedIndex] = _declarationNameIds[declarationIndex];
                _sortedDeclarationFileRanks[sortedIndex] = _declarationFileRanks[declarationIndex];
                _sortedDeclarationLineNumbers[sortedIndex] = _declarationLineNumbers[declarationIndex];
                _sortedDeclarationColumns[sortedIndex] = _declarationColumns[declarationIndex];
                _sortedDeclarationIndices[sortedIndex] = declarationIndex;
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

            return _declarationColumns[left].CompareTo(_declarationColumns[right]);
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

        private int GetOrAddNameId(string name)
        {
            if (_nameIds.TryGetValue(name, out var id))
                return id;

            id = _nameIds.Count + 1;
            _nameIds.Add(name, id);
            return id;
        }

        private int GetExistingFileRank(string? file)
        {
            if (file == null)
                return 0;

            return _fileRanks.TryGetValue(file, out var rank) ? rank : -1;
        }

        private int GetExistingNameId(string name) => _nameIds.TryGetValue(name, out var id) ? id : -1;

        private void EnsureQueryCapacity(int count)
        {
            if (_queryFileRanks.Length >= count)
                return;

            _queryNameIds = new int[count];
            _queryFileRanks = new int[count];
            _queryLineNumbers = new int[count];
            _queryColumns = new int[count];
            _resultDeclarationIndices = new int[count];
        }
    }

    private sealed class SourceLineCache
    {
        private readonly object _gate = new();
        private readonly int[] _lineLengths;
        private readonly int[] _lineStarts;
        private readonly string[] _queryNames = new string[1];
        private readonly int[] _queryColumns = new int[1];
        private readonly int[] _queryLines = new int[1];
        private readonly int[] _resultLengths = new int[1];
        private readonly int[] _resultStarts = new int[1];
        private readonly string _source;
        private bool _lineRangesBuilt;
        private int _lineCount;

        public SourceLineCache(string source)
        {
            _source = source;
            var capacity = source.Length + 1;
            _lineStarts = new int[capacity];
            _lineLengths = new int[capacity];
            _queryNames[0] = string.Empty;
        }

        public bool TryExtractSourceLine(Bindings bindings, int line, out string? text)
        {
            text = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                bindings.SourceLinesFromLines(
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                if (start < 0)
                    return true;

                text = _source.Substring(start, _resultLengths[0]);
                return true;
            }
        }

        public bool TryFindIdentifierNameColumn(
            Bindings bindings,
            string name,
            int line,
            int fallbackColumn,
            out int column)
        {
            column = fallbackColumn;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                _queryNames[0] = name;
                _queryColumns[0] = fallbackColumn;
                _resultStarts[0] = fallbackColumn;

                try
                {
                    bindings.IdentifierNameColumnsFromLines(
                        _source,
                        _lineStarts,
                        _lineLengths,
                        _lineCount,
                        _queryLines,
                        _queryNames,
                        _queryColumns,
                        _resultStarts);

                    column = _resultStarts[0];
                    return true;
                }
                finally
                {
                    _queryNames[0] = string.Empty;
                }
            }
        }

        public bool TryExtractEditorIdentifierSpan(
            Bindings bindings,
            int line,
            int column,
            out (int StartColumn, int EndColumn, string Name)? span)
        {
            span = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                _queryColumns[0] = column;
                bindings.EditorIdentifierSpansFromLines(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _queryColumns,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                var length = _resultLengths[0];
                if (start < 0 || length <= 0)
                    return true;

                var absoluteStart = _lineStarts[line - 1] + start - 1;
                span = (start, start + length - 1, _source.Substring(absoluteStart, length));
                return true;
            }
        }

        private void EnsureLineRanges(Bindings bindings)
        {
            if (_lineRangesBuilt)
                return;

            _lineCount = bindings.BuildLineRanges(_source, _lineStarts, _lineLengths);
            _lineRangesBuilt = true;
        }
    }

    private sealed class SnapshotCache
    {
        private readonly object _gate = new();
        private readonly Dictionary<string, FileCache> _files = new(StringComparer.OrdinalIgnoreCase);

        public FileCache GetFileCache(string filePath, string source)
        {
            lock (_gate)
            {
                if (_files.TryGetValue(filePath, out var cache) && cache.Matches(source))
                    return cache;

                cache = new FileCache(source);
                _files[filePath] = cache;
                return cache;
            }
        }
    }

    private sealed class FileCache
    {
        private readonly object _gate = new();
        private readonly int[] _docCommentLengths;
        private readonly int[] _docCommentStarts;
        private readonly int[] _lineLengths;
        private readonly int[] _lineStarts;
        private readonly int[] _declarationColumns = new int[1];
        private readonly int[] _memberStartColumns = new int[1];
        private readonly int[] _queryColumns = new int[1];
        private readonly int[] _queryLines = new int[1];
        private readonly string[] _queryNames = new string[1];
        private readonly int[] _receiverLengthsBySeparator;
        private readonly int[] _receiverStartsBySeparator;
        private readonly int[] _resultLengths = new int[1];
        private readonly int[] _resultMatches = new int[1];
        private readonly int[] _resultStarts = new int[1];
        private readonly int[] _selectedEndColumns = new int[1];
        private readonly int[] _selectedStartColumns = new int[1];
        private readonly string _source;
        private readonly int[] _variableDeclarationNameLengthsByLine;
        private readonly int[] _variableDeclarationNameStartsByLine;
        private bool _lineRangesBuilt;
        private int _lineCount;
        private bool _receiverCacheBuilt;
        private bool _variableDeclarationNameCacheBuilt;

        public FileCache(string source)
        {
            _source = source;
            var capacity = source.Length + 1;
            _docCommentStarts = new int[capacity];
            _docCommentLengths = new int[capacity];
            _lineStarts = new int[capacity];
            _lineLengths = new int[capacity];
            _receiverStartsBySeparator = new int[capacity];
            _receiverLengthsBySeparator = new int[capacity];
            _variableDeclarationNameStartsByLine = new int[capacity];
            _variableDeclarationNameLengthsByLine = new int[capacity];
        }

        public bool Matches(string source) =>
            ReferenceEquals(_source, source) || string.Equals(_source, source, StringComparison.Ordinal);

        public bool TryExtractIdentifierSpan(
            Bindings bindings,
            int line,
            int column,
            out (int StartColumn, int EndColumn)? span)
        {
            span = null;
            lock (_gate)
            {
                var found = TryExtractIdentifierSpanCore(bindings, line, column, out var start, out var length);
                if (!found)
                    return true;

                span = (start, start + length - 1);
                return true;
            }
        }

        public bool TryExtractDocComment(Bindings bindings, int definitionLine, out string? documentation)
        {
            documentation = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                var lineCount = bindings.DocCommentLinesFromLines(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    definitionLine,
                    _docCommentStarts,
                    _docCommentLengths);

                if (lineCount <= 0)
                    return true;

                var builder = new StringBuilder();
                for (var i = 0; i < lineCount; i++)
                {
                    if (i > 0)
                    {
                        builder.Append('\n');
                    }

                    builder.Append(_source, _docCommentStarts[i], _docCommentLengths[i]);
                }

                documentation = builder.ToString();
                return true;
            }
        }

        public bool TrySelectedSpanMatchesDeclarationName(
            Bindings bindings,
            int line,
            int declarationColumn,
            string declarationName,
            int selectedStartColumn,
            int selectedEndColumn,
            out bool matches)
        {
            matches = false;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                _declarationColumns[0] = declarationColumn;
                _queryNames[0] = declarationName;
                _selectedStartColumns[0] = selectedStartColumn;
                _selectedEndColumns[0] = selectedEndColumn;

                bindings.DeclarationNameMatchesFromLines(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _declarationColumns,
                    _queryNames,
                    _selectedStartColumns,
                    _selectedEndColumns,
                    _resultMatches);

                matches = _resultMatches[0] != 0;
                _queryNames[0] = string.Empty;
                return true;
            }
        }

        public bool TryExtractCompletionPrefix(Bindings bindings, int line, int column, out string? prefix)
        {
            prefix = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                _queryColumns[0] = column;
                bindings.CompletionPrefixesFromLines(
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _queryColumns,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                if (start < 0)
                    return true;

                prefix = _source.Substring(start, _resultLengths[0]);
                return true;
            }
        }

        public bool TryExtractIdentifierName(
            Bindings bindings,
            int line,
            int column,
            out string? name)
        {
            name = null;
            lock (_gate)
            {
                var found = TryExtractIdentifierSpanCore(bindings, line, column, out var start, out var length);
                if (!found)
                    return true;

                var absoluteStart = _lineStarts[line - 1] + start - 1;
                name = _source.Substring(absoluteStart, length);
                return true;
            }
        }

        public bool TryExtractMemberReceiverName(
            Bindings bindings,
            int line,
            int memberStartColumn,
            out string? receiverName)
        {
            receiverName = null;
            lock (_gate)
            {
                EnsureReceiverCache(bindings);

                _queryLines[0] = line;
                _memberStartColumns[0] = memberStartColumn;
                bindings.MemberReceiversFromCache(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _receiverStartsBySeparator,
                    _receiverLengthsBySeparator,
                    _queryLines,
                    _memberStartColumns,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                var length = _resultLengths[0];
                if (start < 0 || length <= 0)
                    return true;

                var absoluteStart = _lineStarts[line - 1] + start - 1;
                receiverName = _source.Substring(absoluteStart, length);
                return true;
            }
        }

        public bool TryExtractSourceContext(Bindings bindings, int line, out string? context)
        {
            context = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                bindings.SourceContextsFromLines(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                if (start < 0)
                    return true;

                context = _source.Substring(start, _resultLengths[0]);
                return true;
            }
        }

        public bool TryExtractSourceLine(Bindings bindings, int line, out string? text)
        {
            text = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                bindings.SourceLinesFromLines(
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                if (start < 0)
                    return true;

                text = _source.Substring(start, _resultLengths[0]);
                return true;
            }
        }

        public bool TryExtractVariableDeclarationName(Bindings bindings, int line, out string? name)
        {
            name = null;
            lock (_gate)
            {
                EnsureVariableDeclarationNameCache(bindings);

                _queryLines[0] = line;
                bindings.VariableDeclarationNamesFromCache(
                    _lineCount,
                    _variableDeclarationNameStartsByLine,
                    _variableDeclarationNameLengthsByLine,
                    _queryLines,
                    _resultStarts,
                    _resultLengths);

                var startColumn = _resultStarts[0];
                var length = _resultLengths[0];
                if (startColumn < 0 || length <= 0)
                    return true;

                var absoluteStart = _lineStarts[line - 1] + startColumn - 1;
                name = _source.Substring(absoluteStart, length);
                return true;
            }
        }

        private bool TryExtractIdentifierSpanCore(
            Bindings bindings,
            int line,
            int column,
            out int start,
            out int length)
        {
            EnsureLineRanges(bindings);

            _queryLines[0] = line;
            _queryColumns[0] = column;
            bindings.IdentifierSpansFromLines(
                _source,
                _lineStarts,
                _lineLengths,
                _lineCount,
                _queryLines,
                _queryColumns,
                _resultStarts,
                _resultLengths);

            start = _resultStarts[0];
            length = _resultLengths[0];
            return start >= 0 && length > 0;
        }

        private void EnsureLineRanges(Bindings bindings)
        {
            if (_lineRangesBuilt)
                return;

            _lineCount = bindings.BuildLineRanges(_source, _lineStarts, _lineLengths);
            _lineRangesBuilt = true;
        }

        private void EnsureReceiverCache(Bindings bindings)
        {
            if (_receiverCacheBuilt)
                return;

            EnsureLineRanges(bindings);
            bindings.BuildMemberReceiverCache(
                _source,
                _lineStarts,
                _lineLengths,
                _lineCount,
                _receiverStartsBySeparator,
                _receiverLengthsBySeparator);
            _receiverCacheBuilt = true;
        }

        private void EnsureVariableDeclarationNameCache(Bindings bindings)
        {
            if (_variableDeclarationNameCacheBuilt)
                return;

            EnsureLineRanges(bindings);
            bindings.BuildVariableDeclarationNameCache(
                _source,
                _lineStarts,
                _lineLengths,
                _lineCount,
                _variableDeclarationNameStartsByLine,
                _variableDeclarationNameLengthsByLine);
            _variableDeclarationNameCacheBuilt = true;
        }
    }
}
