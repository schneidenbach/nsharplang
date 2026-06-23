using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class OutputFormatterReferenceFileKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static ReferenceFileSummaryScratch? t_diagnosticClusterFileSummaryScratch;
    [ThreadStatic]
    private static ReferenceFileSummaryScratch? t_inspectSummaryReferenceFileScratch;

    internal static bool TryBuildInspectSummaryReferenceFiles(
        IReadOnlyList<ReferenceResult> references,
        out string[] referenceFiles)
    {
        referenceFiles = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var referenceCount = references.Count;
        var scratch = t_inspectSummaryReferenceFileScratch ??= new ReferenceFileSummaryScratch();
        scratch.EnsureCapacity(referenceCount);

        try
        {
            scratch.ResetFiles();
            for (var i = 0; i < referenceCount; i++)
            {
                var file = NormalizePath(references[i].File);
                scratch.Files[i] = file;
                scratch.AddFile(file);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < referenceCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            var resultCount = bindings.ReferenceFileSummaryRanks(
                scratch.FileRanks,
                scratch.UniqueFileCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (resultCount < 0 || resultCount > scratch.UniqueFileCount || resultCount > scratch.ResultRanks.Length)
                return false;

            referenceFiles = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueFileCount)
                {
                    referenceFiles = Array.Empty<string>();
                    return false;
                }

                referenceFiles[i] = scratch.UniqueFiles[rank - 1];
            }

            return true;
        }
        catch
        {
            referenceFiles = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearFiles(referenceCount);
            scratch.ResetFiles();
        }
    }

    internal static bool TryBuildDiagnosticClusterFiles(
        IReadOnlyList<DiagnosticResult> diagnostics,
        out string[] files)
    {
        files = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var diagnosticCount = diagnostics.Count;
        var scratch = t_diagnosticClusterFileSummaryScratch ??=
            new ReferenceFileSummaryScratch(StringComparer.OrdinalIgnoreCase, StringComparer.OrdinalIgnoreCase);
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            scratch.ResetFiles();
            for (var i = 0; i < diagnosticCount; i++)
            {
                var file = diagnostics[i].File;
                scratch.Files[i] = file;
                scratch.AddFile(file);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < diagnosticCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            var resultCount = bindings.ReferenceFileSummaryRanks(
                scratch.FileRanks,
                scratch.UniqueFileCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (resultCount < 0 || resultCount > scratch.UniqueFileCount || resultCount > scratch.ResultRanks.Length)
                return false;

            files = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueFileCount)
                {
                    files = Array.Empty<string>();
                    return false;
                }

                files[i] = scratch.UniqueFiles[rank - 1];
            }

            return true;
        }
        catch
        {
            files = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearFiles(diagnosticCount);
            scratch.ResetFiles();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<ReferenceFileSummaryRanksInto>(
                programType,
                "ReferenceFileSummaryRanksInto")));

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private delegate int ReferenceFileSummaryRanksInto(
        int[] fileRanks,
        int uniqueFileCount,
        int[] countsByRank,
        int[] resultRanks);

    private sealed record Bindings(ReferenceFileSummaryRanksInto ReferenceFileSummaryRanks);

    private sealed class ReferenceFileSummaryScratch
    {
        private readonly Dictionary<string, int> _fileRanks;
        private readonly IComparer<string> _sortComparer;

        public ReferenceFileSummaryScratch()
            : this(StringComparer.Ordinal, StringComparer.Ordinal)
        {
        }

        public ReferenceFileSummaryScratch(IEqualityComparer<string> equalityComparer, IComparer<string> sortComparer)
        {
            _fileRanks = new Dictionary<string, int>(equalityComparer);
            _sortComparer = sortComparer;
        }

        public int[] CountsByRank = Array.Empty<int>();
        public int[] FileRanks = Array.Empty<int>();
        public string[] Files = Array.Empty<string>();
        public int[] ResultRanks = Array.Empty<int>();
        public string[] UniqueFiles = Array.Empty<string>();
        public int UniqueFileCount;

        public void EnsureCapacity(int count)
        {
            if (FileRanks.Length != count)
            {
                FileRanks = new int[count];
                Files = new string[count];
                ResultRanks = new int[count];
                UniqueFiles = new string[count];
            }

            var rankCapacity = count + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
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
            Array.Sort(UniqueFiles, 0, UniqueFileCount, _sortComparer);
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
