using System;
using System.Collections.Generic;

namespace NSharpLang.Cli;

internal static class GeneratedOutputDirectoryDeduplicator
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryDeduplicate(
        IReadOnlyList<string> directories,
        out List<string> distinctDirectories)
    {
        distinctDirectories = new List<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var directoryCount = directories.Count;
        if (directoryCount == 0)
            return true;

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
            var resultCount = bindings.StableDistinctRankIndices(
                scratch.Ranks,
                uniqueRankCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (resultCount < 0 || resultCount > directoryCount || resultCount > scratch.ResultIndices.Length)
            {
                distinctDirectories = new List<string>();
                return false;
            }

            distinctDirectories = new List<string>(resultCount);
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= directoryCount)
                {
                    distinctDirectories = new List<string>();
                    return false;
                }

                distinctDirectories.Add(directories[sourceIndex]);
            }

            return true;
        }
        catch
        {
            distinctDirectories = new List<string>();
            return false;
        }
        finally
        {
            scratch.RanksByDirectory.Clear();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliStableDistinctRankIndicesInto>(
                programType,
                "CliStableDistinctRankIndicesInto")));

    private delegate int CliStableDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private sealed record Bindings(CliStableDistinctRankIndicesInto StableDistinctRankIndices);

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
