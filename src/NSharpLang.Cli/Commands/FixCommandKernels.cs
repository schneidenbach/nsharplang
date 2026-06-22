using System;
using System.Collections.Generic;
using System.Globalization;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal static class FixCommandKernels
{
    [ThreadStatic]
    private static SafetyFilterScratch? t_safetyFilterScratch;
    [ThreadStatic]
    private static AppliedFileGroupingScratch? t_appliedFileGroupingScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryFilterBySafety(
        IReadOnlyList<CodeAction> fixes,
        bool includeReviewNeeded,
        out List<CodeAction> safeActions)
    {
        safeActions = new List<CodeAction>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var fixCount = fixes.Count;
        if (fixCount == 0)
            return true;

        var scratch = t_safetyFilterScratch ??= new SafetyFilterScratch();
        scratch.EnsureCapacity(fixCount);

        try
        {
            for (var i = 0; i < fixCount; i++)
            {
                scratch.SafetyRanks[i] = GetFixSafetyRank(fixes[i].Safety);
            }

            var safeCount = bindings.SafetyFilter(
                scratch.SafetyRanks,
                includeReviewNeeded ? 1 : 0,
                scratch.ResultIndices);

            if (safeCount < 0 || safeCount > fixCount || safeCount > scratch.ResultIndices.Length)
            {
                safeActions = new List<CodeAction>();
                return false;
            }

            safeActions = new List<CodeAction>(safeCount);
            for (var i = 0; i < safeCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= fixCount)
                {
                    safeActions = new List<CodeAction>();
                    return false;
                }

                safeActions.Add(fixes[sourceIndex]);
            }

            return true;
        }
        catch
        {
            safeActions = new List<CodeAction>();
            return false;
        }
    }

    internal static bool TrySelectSkippedEntries(
        IReadOnlyList<FixEntry> results,
        bool includeReviewNeeded,
        out List<FixEntry> skipped)
    {
        skipped = new List<FixEntry>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultCount = results.Count;
        if (resultCount == 0)
            return true;

        var scratch = t_safetyFilterScratch ??= new SafetyFilterScratch();
        scratch.EnsureCapacity(resultCount);

        try
        {
            for (var i = 0; i < resultCount; i++)
            {
                scratch.SafetyRanks[i] = GetFixEntrySafetyRank(results[i].Safety);
            }

            var skippedCount = bindings.SkippedIndices(
                scratch.SafetyRanks,
                includeReviewNeeded ? 1 : 0,
                scratch.ResultIndices);

            if (skippedCount < 0 || skippedCount > resultCount || skippedCount > scratch.ResultIndices.Length)
            {
                skipped = new List<FixEntry>();
                return false;
            }

            skipped = new List<FixEntry>(skippedCount);
            for (var i = 0; i < skippedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= resultCount)
                {
                    skipped = new List<FixEntry>();
                    return false;
                }

                skipped.Add(results[sourceIndex]);
            }

            return true;
        }
        catch
        {
            skipped = new List<FixEntry>();
            return false;
        }
    }

    internal static bool TryGroupAppliedEntriesByFile(
        IReadOnlyList<FixEntry> applied,
        out FixAppliedFileGrouping grouping)
    {
        grouping = FixAppliedFileGrouping.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var appliedCount = applied.Count;
        if (appliedCount == 0)
            return true;

        var scratch = t_appliedFileGroupingScratch ??= new AppliedFileGroupingScratch();
        scratch.EnsureCapacity(appliedCount);

        try
        {
            scratch.Reset();
            for (var i = 0; i < appliedCount; i++)
            {
                var fileRank = scratch.GetOrAddFileRank(applied[i].File);
                scratch.FileRanks[i] = fileRank;
            }

            var groupCount = bindings.AppliedFileGroups(
                scratch.FileRanks,
                scratch.UniqueFileRankCount,
                scratch.CountsByRank,
                scratch.OffsetsByRank,
                scratch.WriteOffsetsByRank,
                scratch.ResultRanks,
                scratch.ResultStarts,
                scratch.ResultCounts,
                scratch.ResultIndices);

            if (groupCount < 0
                || groupCount > scratch.UniqueFileRankCount
                || groupCount > appliedCount)
            {
                return false;
            }

            var files = new string[groupCount];
            var starts = new int[groupCount];
            var counts = new int[groupCount];
            var indices = new int[appliedCount];

            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var rank = scratch.ResultRanks[groupIndex];
                var start = scratch.ResultStarts[groupIndex];
                var count = scratch.ResultCounts[groupIndex];
                if (rank <= 0
                    || rank > scratch.UniqueFileRankCount
                    || start < 0
                    || count < 0
                    || start + count > appliedCount)
                {
                    return false;
                }

                files[groupIndex] = scratch.FilesByRank[rank] ?? string.Empty;
                starts[groupIndex] = start;
                counts[groupIndex] = count;
            }

            for (var i = 0; i < appliedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= appliedCount)
                {
                    return false;
                }

                indices[i] = sourceIndex;
            }

            grouping = new FixAppliedFileGrouping(files, starts, counts, indices);
            return true;
        }
        catch
        {
            grouping = FixAppliedFileGrouping.Empty;
            return false;
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static string GetHelpText()
        => TryGetMessage(bindings => bindings.HelpText(), out var message)
            ? message
            : FallbackHelpText();

    internal static string GetProjectDirectoryNotFoundMessage(string projectDir)
        => TryGetMessage(bindings => bindings.ProjectDirectoryNotFoundMessage(projectDir), out var message)
            ? message
            : FallbackProjectDirectoryNotFoundMessage(projectDir);

    internal static string GetFileNotFoundMessage(string filePath)
        => TryGetMessage(bindings => bindings.FileNotFoundMessage(filePath), out var message)
            ? message
            : FallbackFileNotFoundMessage(filePath);

    internal static string GetNoFilesFoundMessage()
        => TryGetMessage(bindings => bindings.NoFilesFoundMessage(), out var message)
            ? message
            : FallbackNoFilesFoundMessage();

    internal static string GetFailedMessage(string message)
        => TryGetMessage(bindings => bindings.FailedMessage(message), out var result)
            ? result
            : FallbackFailedMessage(message);

    internal static string GetNothingToFixMessage()
        => TryGetMessage(bindings => bindings.NothingToFixMessage(), out var message)
            ? message
            : FallbackNothingToFixMessage();

    internal static string GetAppliedHeader(int appliedCount, int filesModified, bool dryRun)
    {
        var appliedCountText = appliedCount.ToString(CultureInfo.InvariantCulture);
        var filesModifiedText = filesModified.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(
            bindings => bindings.AppliedHeader(
                appliedCountText,
                appliedCount,
                filesModifiedText,
                filesModified,
                dryRun ? 1 : 0),
            out var message)
            ? message
            : FallbackAppliedHeader(appliedCountText, appliedCount, filesModifiedText, filesModified, dryRun);
    }

    internal static string GetAppliedFileHeader(string filePath)
        => TryGetMessage(bindings => bindings.AppliedFileHeader(filePath), out var message)
            ? message
            : FallbackAppliedFileHeader(filePath);

    internal static string GetEntryLine(string diagnosticCode, string title)
        => TryGetMessage(bindings => bindings.EntryLine(diagnosticCode, title), out var message)
            ? message
            : FallbackEntryLine(diagnosticCode, title);

    internal static string GetSkippedHeader(int skippedCount)
    {
        var skippedCountText = skippedCount.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.SkippedHeader(skippedCountText, skippedCount), out var message)
            ? message
            : FallbackSkippedHeader(skippedCountText, skippedCount);
    }

    internal static string GetSkippedReason(string safety)
        => TryGetMessage(bindings => bindings.SkippedReason(safety), out var message)
            ? message
            : FallbackSkippedReason(safety);

    internal static string GetSkippedLine(string diagnosticCode, string title, string reason)
        => TryGetMessage(bindings => bindings.SkippedLine(diagnosticCode, title, reason), out var message)
            ? message
            : FallbackSkippedLine(diagnosticCode, title, reason);

    private static bool TryGetMessage(Func<Bindings, string> getMessage, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = getMessage(bindings);
            return !string.IsNullOrEmpty(message);
        }
        catch
        {
            message = string.Empty;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFixSafetyFilterIndicesInto>(
                programType,
                "CliFixSafetyFilterIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliFixSkippedIndicesInto>(
                programType,
                "CliFixSkippedIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliFixAppliedFileGroupsInto>(
                programType,
                "CliFixAppliedFileGroupsInto"),
            DogfoodKernelLoader.CreateDelegate<CliFixHelpText>(
                programType,
                "CliFixHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliFixProjectDirectoryNotFoundMessage>(
                programType,
                "CliFixProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFixFileNotFoundMessage>(
                programType,
                "CliFixFileNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFixNoFilesFoundMessage>(
                programType,
                "CliFixNoFilesFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFixFailedMessage>(
                programType,
                "CliFixFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFixNothingToFixMessage>(
                programType,
                "CliFixNothingToFixMessage"),
            DogfoodKernelLoader.CreateDelegate<CliFixAppliedHeader>(
                programType,
                "CliFixAppliedHeader"),
            DogfoodKernelLoader.CreateDelegate<CliFixAppliedFileHeader>(
                programType,
                "CliFixAppliedFileHeader"),
            DogfoodKernelLoader.CreateDelegate<CliFixEntryLine>(
                programType,
                "CliFixEntryLine"),
            DogfoodKernelLoader.CreateDelegate<CliFixSkippedHeader>(
                programType,
                "CliFixSkippedHeader"),
            DogfoodKernelLoader.CreateDelegate<CliFixSkippedReason>(
                programType,
                "CliFixSkippedReason"),
            DogfoodKernelLoader.CreateDelegate<CliFixSkippedLine>(
                programType,
                "CliFixSkippedLine")));

    private static int GetFixSafetyRank(FixSafety safety) =>
        safety switch
        {
            FixSafety.Safe => 1,
            FixSafety.ReviewNeeded => 2,
            FixSafety.SuggestionOnly => 3,
            _ => 0
        };

    private static int GetFixEntrySafetyRank(string safety) =>
        safety switch
        {
            "safe" => 1,
            "reviewNeeded" => 2,
            "suggestionOnly" => 3,
            _ => 0
        };

    private delegate int CliFixSafetyFilterIndicesInto(
        int[] safetyRanks,
        int includeReviewNeeded,
        int[] resultIndices);

    private delegate int CliFixSkippedIndicesInto(
        int[] safetyRanks,
        int includeReviewNeeded,
        int[] resultIndices);

    private delegate int CliFixAppliedFileGroupsInto(
        int[] fileRanks,
        int uniqueFileRankCount,
        int[] countsByRank,
        int[] offsetsByRank,
        int[] writeOffsetsByRank,
        int[] resultRanks,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultIndices);

    private delegate string CliFixHelpText();

    private delegate string CliFixProjectDirectoryNotFoundMessage(string projectDir);

    private delegate string CliFixFileNotFoundMessage(string filePath);

    private delegate string CliFixNoFilesFoundMessage();

    private delegate string CliFixFailedMessage(string message);

    private delegate string CliFixNothingToFixMessage();

    private delegate string CliFixAppliedHeader(
        string appliedCountText,
        int appliedCount,
        string filesModifiedText,
        int filesModified,
        int dryRun);

    private delegate string CliFixAppliedFileHeader(string filePath);

    private delegate string CliFixEntryLine(string diagnosticCode, string title);

    private delegate string CliFixSkippedHeader(string skippedCountText, int skippedCount);

    private delegate string CliFixSkippedReason(string safety);

    private delegate string CliFixSkippedLine(string diagnosticCode, string title, string reason);

    private sealed record Bindings(
        CliFixSafetyFilterIndicesInto SafetyFilter,
        CliFixSkippedIndicesInto SkippedIndices,
        CliFixAppliedFileGroupsInto AppliedFileGroups,
        CliFixHelpText HelpText,
        CliFixProjectDirectoryNotFoundMessage ProjectDirectoryNotFoundMessage,
        CliFixFileNotFoundMessage FileNotFoundMessage,
        CliFixNoFilesFoundMessage NoFilesFoundMessage,
        CliFixFailedMessage FailedMessage,
        CliFixNothingToFixMessage NothingToFixMessage,
        CliFixAppliedHeader AppliedHeader,
        CliFixAppliedFileHeader AppliedFileHeader,
        CliFixEntryLine EntryLine,
        CliFixSkippedHeader SkippedHeader,
        CliFixSkippedReason SkippedReason,
        CliFixSkippedLine SkippedLine);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product fix messages route through CliFix* kernels.
    private static string FallbackHelpText()
        => "N# Auto-Fix\n"
           + "\n"
           + "Usage: nlc fix [options] [project-dir]\n"
           + "\n"
           + "Options:\n"
           + "  --json                    Output as JSON (default)\n"
           + "  --text                    Output as human-readable summary\n"
           + "  --project                 Project root directory (default: current directory)\n"
           + "  --file                    Fix a single file\n"
           + "  --dry-run                 Preview fixes without writing files\n"
           + "  --include-review-needed   Also apply fixes that may need review (e.g. unused import removal)\n"
           + "  --help, -h                Show this help text\n"
           + "\n"
           + "Safety levels:\n"
           + "  Safe              Always applied by default\n"
           + "  ReviewNeeded      Only applied with --include-review-needed flag\n"
           + "  SuggestionOnly    Never applied automatically — reported in results only\n"
           + "\n"
           + "Examples:\n"
           + "  nlc fix\n"
           + "  nlc fix --dry-run --text\n"
           + "  nlc fix --include-review-needed\n"
           + "  nlc fix --file Program.nl\n"
           + "  nlc fix --project examples/16-task-cli";

    private static string FallbackProjectDirectoryNotFoundMessage(string projectDir)
        => $"Directory not found: {projectDir}";

    private static string FallbackFileNotFoundMessage(string filePath)
        => $"File not found: {filePath}";

    private static string FallbackNoFilesFoundMessage()
        => "No .nl files found.";

    private static string FallbackFailedMessage(string message)
        => $"Fix failed: {message}";

    private static string FallbackNothingToFixMessage()
        => "Nothing to fix.";

    private static string FallbackAppliedHeader(
        string appliedCountText,
        int appliedCount,
        string filesModifiedText,
        int filesModified,
        bool dryRun)
    {
        var verb = dryRun ? "Would fix" : "Fixed";
        var issueSuffix = appliedCount == 1 ? string.Empty : "s";
        var fileWord = filesModified == 1 ? "file" : "files";
        return $"{verb} {appliedCountText} issue{issueSuffix} in {filesModifiedText} {fileWord}:";
    }

    private static string FallbackAppliedFileHeader(string filePath)
        => $"  {filePath}:";

    private static string FallbackEntryLine(string diagnosticCode, string title)
        => $"    [{diagnosticCode}] {title}";

    private static string FallbackSkippedHeader(string skippedCountText, int skippedCount)
    {
        var suffix = skippedCount == 1 ? string.Empty : "es";
        return $"Skipped {skippedCountText} fix{suffix}:";
    }

    private static string FallbackSkippedReason(string safety)
        => safety == "suggestionOnly"
            ? "suggestion only — manual review required"
            : "requires --include-review-needed flag";

    private static string FallbackSkippedLine(string diagnosticCode, string title, string reason)
        => $"  [{diagnosticCode}] {title} ({reason})";

    private sealed class SafetyFilterScratch
    {
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SafetyRanks = Array.Empty<int>();

        internal void EnsureCapacity(int fixCount)
        {
            if (SafetyRanks.Length != fixCount)
            {
                SafetyRanks = new int[fixCount];
                ResultIndices = new int[fixCount];
            }
        }
    }

    private sealed class AppliedFileGroupingScratch
    {
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);

        internal int[] CountsByRank = Array.Empty<int>();
        internal int[] FileRanks = Array.Empty<int>();
        internal string?[] FilesByRank = Array.Empty<string?>();
        internal int[] OffsetsByRank = Array.Empty<int>();
        internal int[] ResultCounts = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] ResultRanks = Array.Empty<int>();
        internal int[] ResultStarts = Array.Empty<int>();
        internal int UniqueFileRankCount;
        internal int[] WriteOffsetsByRank = Array.Empty<int>();

        internal void EnsureCapacity(int appliedCount)
        {
            if (FileRanks.Length != appliedCount)
            {
                FileRanks = new int[appliedCount];
                ResultCounts = new int[appliedCount];
                ResultIndices = new int[appliedCount];
                ResultRanks = new int[appliedCount];
                ResultStarts = new int[appliedCount];
            }

            var rankCapacity = appliedCount + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
                FilesByRank = new string?[rankCapacity];
                OffsetsByRank = new int[rankCapacity];
                WriteOffsetsByRank = new int[rankCapacity];
            }
        }

        internal int GetOrAddFileRank(string file)
        {
            if (_fileRanks.TryGetValue(file, out var rank))
                return rank;

            rank = UniqueFileRankCount + 1;
            _fileRanks.Add(file, rank);
            FilesByRank[rank] = file;
            UniqueFileRankCount = rank;
            return rank;
        }

        internal void Reset()
        {
            _fileRanks.Clear();
            if (UniqueFileRankCount > 0)
            {
                Array.Clear(FilesByRank, 0, UniqueFileRankCount + 1);
                UniqueFileRankCount = 0;
            }
        }
    }
}

internal sealed class FixAppliedFileGrouping
{
    internal static readonly FixAppliedFileGrouping Empty = new(
        Array.Empty<string>(),
        Array.Empty<int>(),
        Array.Empty<int>(),
        Array.Empty<int>());

    internal FixAppliedFileGrouping(string[] files, int[] starts, int[] counts, int[] indices)
    {
        Files = files;
        Starts = starts;
        Counts = counts;
        Indices = indices;
    }

    internal string[] Files { get; }
    internal int GroupCount => Files.Length;
    internal int[] Starts { get; }
    internal int[] Counts { get; }
    internal int[] Indices { get; }
}
