using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class NSharpCodeIntelligenceDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    private static readonly ConditionalWeakTable<ProjectSnapshot, SnapshotCache> s_snapshotCaches = new();

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
                CreateDelegate<CodeIntelligenceIdentifierSpansFromLinesInto>(programType, "CodeIntelligenceIdentifierSpansFromLinesInto"),
                CreateDelegate<CodeIntelligenceMemberReceiversFromCacheInto>(programType, "CodeIntelligenceMemberReceiversFromCacheInto"),
                CreateDelegate<CodeIntelligenceSourceContextsFromLinesInto>(programType, "CodeIntelligenceSourceContextsFromLinesInto"));
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

    private delegate int CodeIntelligenceIdentifierSpansFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] queryColumns,
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

    private sealed record Bindings(
        BuildCodeIntelligenceLineRangesInto BuildLineRanges,
        BuildCodeIntelligenceMemberReceiverCacheInto BuildMemberReceiverCache,
        CodeIntelligenceIdentifierSpansFromLinesInto IdentifierSpansFromLines,
        CodeIntelligenceMemberReceiversFromCacheInto MemberReceiversFromCache,
        CodeIntelligenceSourceContextsFromLinesInto SourceContextsFromLines);

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
        private readonly int[] _lineLengths;
        private readonly int[] _lineStarts;
        private readonly int[] _memberStartColumns = new int[1];
        private readonly int[] _queryColumns = new int[1];
        private readonly int[] _queryLines = new int[1];
        private readonly int[] _receiverLengthsBySeparator;
        private readonly int[] _receiverStartsBySeparator;
        private readonly int[] _resultLengths = new int[1];
        private readonly int[] _resultStarts = new int[1];
        private readonly string _source;
        private bool _lineRangesBuilt;
        private int _lineCount;
        private bool _receiverCacheBuilt;

        public FileCache(string source)
        {
            _source = source;
            var capacity = source.Length + 1;
            _lineStarts = new int[capacity];
            _lineLengths = new int[capacity];
            _receiverStartsBySeparator = new int[capacity];
            _receiverLengthsBySeparator = new int[capacity];
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
    }
}
