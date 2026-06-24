using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class CodeIntelligenceResultKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static DiagnosticShadowSuppressionScratch? t_diagnosticShadowSuppressionScratch;
    private static DiagnosticDeduplicationScratch? t_diagnosticDeduplicationScratch;
    [ThreadStatic]
    private static ReferenceDeduplicationScratch? t_referenceDeduplicationScratch;

    internal static (int[] ResultIndices, int Count) SuppressLintShadowingDiagnostics(
        IReadOnlyList<DiagnosticResult> diagnostics,
        IReadOnlyList<string> shadowedFiles)
    {
        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return (Array.Empty<int>(), 0);

        var scratch = t_diagnosticShadowSuppressionScratch ??= new DiagnosticShadowSuppressionScratch();
        scratch.EnsureCapacity(diagnosticCount, shadowedFiles.Count);

        try
        {
            scratch.Reset();
            var targetCodeId = scratch.GetCodeId("NL020");
            for (var i = 0; i < diagnosticCount; i++)
            {
                var diagnostic = diagnostics[i];
                var file = diagnostic.File ?? string.Empty;
                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code ?? string.Empty);
                scratch.Files[i] = file;
                scratch.AddFile(file);
            }

            for (var i = 0; i < shadowedFiles.Count; i++)
            {
                scratch.AddFile(shadowedFiles[i] ?? string.Empty);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < diagnosticCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            scratch.ClearShadowFileFlags();
            for (var i = 0; i < shadowedFiles.Count; i++)
            {
                var rank = scratch.GetFileRank(shadowedFiles[i] ?? string.Empty);
                if (rank >= 0 && rank < scratch.ShadowFileFlags.Length)
                {
                    scratch.ShadowFileFlags[rank] = 1;
                }
            }

            var count = RequiredBindings.DiagnosticShadowSuppression(
                scratch.CodeIds,
                scratch.FileRanks,
                targetCodeId,
                scratch.ShadowFileFlags,
                scratch.ResultIndices);

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.ClearFiles(diagnosticCount);
            scratch.Reset();
        }
    }

    internal static (int[] ResultIndices, int Count) DeduplicateDiagnostics(
        IReadOnlyList<DiagnosticResult> diagnostics)
    {
        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return (Array.Empty<int>(), 0);

        var scratch = t_diagnosticDeduplicationScratch ??= new DiagnosticDeduplicationScratch();
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < diagnosticCount; i++)
            {
                var diagnostic = diagnostics[i];
                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code);
                scratch.LineNumbers[i] = diagnostic.Line;
                scratch.Columns[i] = diagnostic.Column;
                scratch.MessageIds[i] = scratch.GetMessageId(diagnostic.Message);
                scratch.Files[i] = diagnostic.File;
                scratch.AddFile(diagnostic.File);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < diagnosticCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            var count = RequiredBindings.DiagnosticDeduplicateCompact(
                scratch.CodeIds,
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.MessageIds,
                scratch.SlotIndices,
                scratch.ResultIndices);

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.ClearFiles(diagnosticCount);
            scratch.ResetIds();
        }
    }

    internal static (int[] ResultIndices, int Count) DeduplicateDiagnosticsPreservingOrder(
        IReadOnlyList<DiagnosticResult> diagnostics)
    {
        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return (Array.Empty<int>(), 0);

        var scratch = t_diagnosticDeduplicationScratch ??= new DiagnosticDeduplicationScratch();
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < diagnosticCount; i++)
            {
                var diagnostic = diagnostics[i];
                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code);
                scratch.FileRanks[i] = scratch.GetFileId(diagnostic.File);
                scratch.LineNumbers[i] = diagnostic.Line;
                scratch.Columns[i] = diagnostic.Column;
                scratch.MessageIds[i] = scratch.GetMessageId(diagnostic.Message);
            }

            var count = RequiredBindings.DiagnosticDeduplicateStable(
                scratch.CodeIds,
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.MessageIds,
                scratch.SlotIndices,
                scratch.ResultIndices);

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.ResetIds();
        }
    }

    internal static (int[] ResultIndices, int Count) DeduplicateReferences(
        IReadOnlyList<ReferenceResult> references)
    {
        var referenceCount = references.Count;
        if (referenceCount == 0)
            return (Array.Empty<int>(), 0);

        var scratch = t_referenceDeduplicationScratch ??= new ReferenceDeduplicationScratch();
        scratch.EnsureCapacity(referenceCount);

        try
        {
            scratch.ResetFiles();
            for (var i = 0; i < referenceCount; i++)
            {
                var reference = references[i];
                scratch.LineNumbers[i] = reference.Line;
                scratch.Columns[i] = reference.Column;
                scratch.Files[i] = reference.File;
                scratch.AddFile(reference.File);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < referenceCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            var count = RequiredBindings.ReferenceDeduplicateCompact(
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.SlotIndices,
                scratch.ResultIndices);

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.ClearFiles(referenceCount);
            scratch.ResetFiles();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<DiagnosticShadowSuppressionIndicesInto>(
                programType,
                "DiagnosticShadowSuppressionIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticDeduplicateCompactInto>(
                programType,
                "DiagnosticDeduplicateCompactInto"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticDeduplicateCompactInto>(
                programType,
                "DiagnosticDeduplicateStableInto"),
            DogfoodKernelLoader.CreateDelegate<ReferenceDeduplicateCompactInto>(
                programType,
                "ReferenceDeduplicateCompactInto")));

    private delegate int DiagnosticShadowSuppressionIndicesInto(
        int[] codeIds,
        int[] fileRanks,
        int targetCodeId,
        int[] shadowFileFlags,
        int[] resultIndices);

    private delegate int DiagnosticDeduplicateCompactInto(
        int[] codeIds,
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] messageIds,
        int[] slotIndices,
        int[] resultIndices);

    private delegate int ReferenceDeduplicateCompactInto(
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] slotIndices,
        int[] resultIndices);

    private sealed record Bindings(
        DiagnosticShadowSuppressionIndicesInto DiagnosticShadowSuppression,
        DiagnosticDeduplicateCompactInto DiagnosticDeduplicateCompact,
        DiagnosticDeduplicateCompactInto DiagnosticDeduplicateStable,
        ReferenceDeduplicateCompactInto ReferenceDeduplicateCompact);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# code intelligence result kernels are unavailable.");

    private sealed class DiagnosticShadowSuppressionScratch
    {
        private readonly Dictionary<string, int> _codeIds = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.OrdinalIgnoreCase);

        public int[] CodeIds = Array.Empty<int>();
        public int[] FileRanks = Array.Empty<int>();
        public string[] Files = Array.Empty<string>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] ShadowFileFlags = Array.Empty<int>();
        public string[] UniqueFiles = Array.Empty<string>();
        public int UniqueFileCount;

        public void EnsureCapacity(int diagnosticCount, int shadowedFileCount)
        {
            if (CodeIds.Length != diagnosticCount)
            {
                CodeIds = new int[diagnosticCount];
                FileRanks = new int[diagnosticCount];
                Files = new string[diagnosticCount];
                ResultIndices = new int[diagnosticCount];
            }

            var uniqueFileCapacity = diagnosticCount + shadowedFileCount;
            if (UniqueFiles.Length < uniqueFileCapacity)
            {
                UniqueFiles = new string[uniqueFileCapacity];
            }

            var shadowFlagCapacity = uniqueFileCapacity + 1;
            if (ShadowFileFlags.Length < shadowFlagCapacity)
            {
                ShadowFileFlags = new int[shadowFlagCapacity];
            }
        }

        public int GetCodeId(string text)
        {
            if (_codeIds.TryGetValue(text, out var id))
                return id;

            id = _codeIds.Count + 1;
            _codeIds.Add(text, id);
            return id;
        }

        public void AddFile(string text)
        {
            if (_fileRanks.ContainsKey(text))
                return;

            _fileRanks.Add(text, 0);
            UniqueFiles[UniqueFileCount] = text;
            UniqueFileCount++;
        }

        public void BuildFileRanks()
        {
            Array.Sort(UniqueFiles, 0, UniqueFileCount, StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < UniqueFileCount; i++)
            {
                _fileRanks[UniqueFiles[i]] = i + 1;
            }
        }

        public int GetFileRank(string text) => _fileRanks.TryGetValue(text, out var rank) ? rank : -1;

        public void ClearFiles(int count)
        {
            if (count > 0)
            {
                Array.Clear(Files, 0, count);
            }
        }

        public void ClearShadowFileFlags()
        {
            if (ShadowFileFlags.Length > 0)
            {
                Array.Clear(ShadowFileFlags);
            }
        }

        public void Reset()
        {
            _codeIds.Clear();
            _fileRanks.Clear();
            if (UniqueFileCount > 0)
            {
                Array.Clear(UniqueFiles, 0, UniqueFileCount);
                UniqueFileCount = 0;
            }
        }
    }

    private sealed class DiagnosticDeduplicationScratch
    {
        private readonly Dictionary<string, int> _codeIds = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _messageIds = new(StringComparer.Ordinal);

        public int[] CodeIds = Array.Empty<int>();
        public int[] Columns = Array.Empty<int>();
        public int[] FileRanks = Array.Empty<int>();
        public string[] Files = Array.Empty<string>();
        public int[] LineNumbers = Array.Empty<int>();
        public int[] MessageIds = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SlotIndices = Array.Empty<int>();
        public string[] UniqueFiles = Array.Empty<string>();
        public int UniqueFileCount;

        public void EnsureCapacity(int count)
        {
            if (CodeIds.Length != count)
            {
                CodeIds = new int[count];
                FileRanks = new int[count];
                LineNumbers = new int[count];
                Columns = new int[count];
                MessageIds = new int[count];
                Files = new string[count];
                ResultIndices = new int[count];
                UniqueFiles = new string[count];
            }

            var slotCapacity = count * 2 + 1;
            if (SlotIndices.Length != slotCapacity)
            {
                SlotIndices = new int[slotCapacity];
            }
        }

        public int GetCodeId(string text) => GetId(_codeIds, text);

        public int GetFileId(string text) => GetId(_fileRanks, text);

        public int GetMessageId(string text) => GetId(_messageIds, text);

        public void AddFile(string text)
        {
            if (_fileRanks.ContainsKey(text))
                return;

            _fileRanks.Add(text, 0);
            UniqueFiles[UniqueFileCount] = text;
            UniqueFileCount++;
        }

        public void BuildFileRanks()
        {
            Array.Sort(UniqueFiles, 0, UniqueFileCount, Comparer<string>.Default);
            for (var i = 0; i < UniqueFileCount; i++)
            {
                _fileRanks[UniqueFiles[i]] = i + 1;
            }
        }

        public int GetFileRank(string text) => _fileRanks[text];

        public void ClearFiles(int count) => Array.Clear(Files, 0, count);

        public void ResetIds()
        {
            _codeIds.Clear();
            _fileRanks.Clear();
            _messageIds.Clear();
            if (UniqueFileCount > 0)
            {
                Array.Clear(UniqueFiles, 0, UniqueFileCount);
                UniqueFileCount = 0;
            }
        }

        private static int GetId(Dictionary<string, int> ids, string text)
        {
            if (ids.TryGetValue(text, out var id))
                return id;

            id = ids.Count + 1;
            ids.Add(text, id);
            return id;
        }
    }

    private sealed class ReferenceDeduplicationScratch
    {
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);

        public int[] Columns = Array.Empty<int>();
        public int[] FileRanks = Array.Empty<int>();
        public string[] Files = Array.Empty<string>();
        public int[] LineNumbers = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SlotIndices = Array.Empty<int>();
        public string[] UniqueFiles = Array.Empty<string>();
        public int UniqueFileCount;

        public void EnsureCapacity(int count)
        {
            if (FileRanks.Length != count)
            {
                FileRanks = new int[count];
                LineNumbers = new int[count];
                Columns = new int[count];
                Files = new string[count];
                ResultIndices = new int[count];
                UniqueFiles = new string[count];
            }

            var slotCapacity = count * 2 + 1;
            if (SlotIndices.Length != slotCapacity)
            {
                SlotIndices = new int[slotCapacity];
            }
        }

        public void AddFile(string text)
        {
            if (_fileRanks.ContainsKey(text))
                return;

            _fileRanks.Add(text, 0);
            UniqueFiles[UniqueFileCount] = text;
            UniqueFileCount++;
        }

        public void BuildFileRanks()
        {
            Array.Sort(UniqueFiles, 0, UniqueFileCount, Comparer<string>.Default);
            for (var i = 0; i < UniqueFileCount; i++)
            {
                _fileRanks[UniqueFiles[i]] = i + 1;
            }
        }

        public int GetFileRank(string text) => _fileRanks[text];

        public void ClearFiles(int count) => Array.Clear(Files, 0, count);

        public void ResetFiles()
        {
            _fileRanks.Clear();
            if (UniqueFileCount > 0)
            {
                Array.Clear(UniqueFiles, 0, UniqueFileCount);
                UniqueFileCount = 0;
            }
        }
    }
}
