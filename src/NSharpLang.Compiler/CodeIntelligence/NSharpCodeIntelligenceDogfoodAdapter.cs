using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class NSharpCodeIntelligenceDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    private static readonly ConditionalWeakTable<ProjectSnapshot, SnapshotCache> s_snapshotCaches = new();
    private static readonly ConditionalWeakTable<string, SourceLineCache> s_sourceLineCaches = new();

    internal static bool IsAvailable => s_bindings.Value != null;

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
                CreateDelegate<CodeIntelligenceIdentifierSpansFromLinesInto>(programType, "CodeIntelligenceIdentifierSpansFromLinesInto"),
                CreateDelegate<CodeIntelligenceCompletionPrefixesFromLinesInto>(programType, "CodeIntelligenceCompletionPrefixesFromLinesInto"),
                CreateDelegate<CodeIntelligenceDocCommentLinesFromLinesInto>(programType, "CodeIntelligenceDocCommentLinesFromLinesInto"),
                CreateDelegate<CodeIntelligenceMemberReceiversFromCacheInto>(programType, "CodeIntelligenceMemberReceiversFromCacheInto"),
                CreateDelegate<CodeIntelligenceSourceContextsFromLinesInto>(programType, "CodeIntelligenceSourceContextsFromLinesInto"),
                CreateDelegate<CodeIntelligenceSourceLinesFromLinesInto>(programType, "CodeIntelligenceSourceLinesFromLinesInto"),
                CreateDelegate<CodeIntelligenceVariableDeclarationNamesFromCacheInto>(programType, "CodeIntelligenceVariableDeclarationNamesFromCacheInto"));
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

    private sealed record Bindings(
        BuildCodeIntelligenceLineRangesInto BuildLineRanges,
        BuildCodeIntelligenceMemberReceiverCacheInto BuildMemberReceiverCache,
        BuildCodeIntelligenceVariableDeclarationNameCacheInto BuildVariableDeclarationNameCache,
        CodeIntelligenceDeclarationNameMatchesFromLinesInto DeclarationNameMatchesFromLines,
        CodeIntelligenceIdentifierSpansFromLinesInto IdentifierSpansFromLines,
        CodeIntelligenceCompletionPrefixesFromLinesInto CompletionPrefixesFromLines,
        CodeIntelligenceDocCommentLinesFromLinesInto DocCommentLinesFromLines,
        CodeIntelligenceMemberReceiversFromCacheInto MemberReceiversFromCache,
        CodeIntelligenceSourceContextsFromLinesInto SourceContextsFromLines,
        CodeIntelligenceSourceLinesFromLinesInto SourceLinesFromLines,
        CodeIntelligenceVariableDeclarationNamesFromCacheInto VariableDeclarationNamesFromCache);

    private sealed class SourceLineCache
    {
        private readonly object _gate = new();
        private readonly int[] _lineLengths;
        private readonly int[] _lineStarts;
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
