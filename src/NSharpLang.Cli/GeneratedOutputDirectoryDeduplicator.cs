using System;
using System.Collections.Generic;

namespace NSharpLang.Cli;

internal static class GeneratedOutputDirectoryDeduplicator
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static List<string> Deduplicate(IReadOnlyList<string> directories)
    {
        var directoryCount = directories.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(directoryCount);

        try
        {
            var uniqueRankCount = 0;
            for (var i = 0; i < directoryCount; i++)
            {
                var directory = directories[i];
                if (!scratch.RanksByDirectory.TryGetValue(directory, out var rank))
                {
                    rank = ++uniqueRankCount;
                    scratch.RanksByDirectory.Add(directory, rank);
                }

                scratch.Ranks[i] = rank;
            }

            scratch.EnsureRankCapacity(uniqueRankCount);
            var resultCount = RequiredBindings.StableDistinctRankIndices(
                scratch.Ranks,
                uniqueRankCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (resultCount < 0 || resultCount > directoryCount || resultCount > scratch.ResultIndices.Length)
                throw new InvalidOperationException("N# generated output directory deduplication kernel rejected the directories.");

            var distinctDirectories = new List<string>(resultCount);
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= directoryCount)
                    throw new InvalidOperationException("N# generated output directory deduplication kernel rejected the directories.");

                distinctDirectories.Add(directories[sourceIndex]);
            }

            return distinctDirectories;
        }
        finally
        {
            scratch.RanksByDirectory.Clear();
        }
    }

    internal static int GetSourceBasePathLength(string relativeSourcePath)
    {
        var result = RequiredBindings.GeneratedSourceBasePathLength(relativeSourcePath);
        if (result < -1 || result > relativeSourcePath.Length)
            throw new InvalidOperationException("N# generated source base-path length kernel rejected the path.");

        return result;
    }

    internal static bool ShouldSkipSourcePath(string relativeSourcePath)
    {
        var result = RequiredBindings.ShouldSkipGeneratedSourcePath(relativeSourcePath);
        if (result is not 0 and not 1)
            throw new InvalidOperationException("N# generated source skip kernel rejected the path.");

        return result == 1;
    }

    internal static int GetGeneratedOutputBasePathLength(string relativeGeneratedPath)
    {
        var result = RequiredBindings.GeneratedOutputBasePathLength(relativeGeneratedPath);
        if (result < -1 || result > relativeGeneratedPath.Length)
            throw new InvalidOperationException("N# generated output base-path length kernel rejected the path.");

        return result;
    }

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# generated output cleanup kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliStableDistinctRankIndicesInto>(
                programType,
                "CliStableDistinctRankIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliGeneratedSourceBasePathLength>(
                programType,
                "CliGeneratedSourceBasePathLength"),
            DogfoodKernelLoader.CreateDelegate<CliShouldSkipGeneratedSourcePath>(
                programType,
                "CliShouldSkipGeneratedSourcePath"),
            DogfoodKernelLoader.CreateDelegate<CliGeneratedOutputBasePathLength>(
                programType,
                "CliGeneratedOutputBasePathLength")));

    private delegate int CliStableDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private delegate int CliGeneratedSourceBasePathLength(
        string relativeSourcePath);

    private delegate int CliShouldSkipGeneratedSourcePath(
        string relativeSourcePath);

    private delegate int CliGeneratedOutputBasePathLength(
        string relativeGeneratedPath);

    private sealed record Bindings(
        CliStableDistinctRankIndicesInto StableDistinctRankIndices,
        CliGeneratedSourceBasePathLength GeneratedSourceBasePathLength,
        CliShouldSkipGeneratedSourcePath ShouldSkipGeneratedSourcePath,
        CliGeneratedOutputBasePathLength GeneratedOutputBasePathLength);

    private sealed class Scratch
    {
        internal readonly Dictionary<string, int> RanksByDirectory = new(StringComparer.Ordinal);
        internal int[] Ranks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (Ranks.Length != count)
                Ranks = new int[count];

            if (ResultIndices.Length != count)
                ResultIndices = new int[count];
        }

        internal void EnsureRankCapacity(int uniqueRankCount)
        {
            var rankCapacity = uniqueRankCount + 1;
            if (SeenRanks.Length != rankCapacity)
                SeenRanks = new int[rankCapacity];
        }
    }
}
