using System;
using System.Collections.Generic;

namespace NSharpLang.Cli.Commands;

internal static class TreeDependencyDeduplicator
{
    [ThreadStatic]
    private static Scratch? t_scratch;
    [ThreadStatic]
    private static StableDistinctScratch? t_stableDistinctScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryDeduplicate(
        TreeCommand.TreeDependency[] dependencies,
        out TreeCommand.TreeDependency[] orderedDependencies)
    {
        orderedDependencies = Array.Empty<TreeCommand.TreeDependency>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (dependencies.Length == 0)
            return true;

        var dependencyCount = dependencies.Length;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureInputCapacity(dependencyCount);
        scratch.ResetRanks();

        try
        {
            BuildRanks(dependencies, scratch, out var uniqueKindCount, out var uniqueNameCount);
            scratch.EnsureScratchCapacity(dependencyCount, uniqueKindCount, uniqueNameCount);

            var orderedCount = bindings.DeduplicateIndices(
                scratch.KindRanks,
                scratch.NameRanks,
                scratch.NameCounts,
                scratch.NameOffsets,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.TempIndices,
                scratch.SortedIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > dependencyCount || orderedCount > scratch.ResultIndices.Length)
                return false;

            orderedDependencies = new TreeCommand.TreeDependency[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= dependencyCount)
                {
                    orderedDependencies = Array.Empty<TreeCommand.TreeDependency>();
                    return false;
                }

                orderedDependencies[i] = dependencies[sourceIndex];
            }

            return true;
        }
        catch
        {
            orderedDependencies = Array.Empty<TreeCommand.TreeDependency>();
            return false;
        }
        finally
        {
            scratch.ResetRanks();
        }
    }

    internal static bool TryDeduplicateTargetFrameworks(
        IReadOnlyList<string> targetFrameworks,
        out string[] distinctFrameworks)
    {
        distinctFrameworks = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var frameworkCount = targetFrameworks.Count;
        if (frameworkCount == 0)
            return true;

        var scratch = t_stableDistinctScratch ??= new StableDistinctScratch();
        scratch.EnsureCapacity(frameworkCount);

        try
        {
            var uniqueRankCount = 0;
            for (var i = 0; i < frameworkCount; i++)
            {
                var framework = targetFrameworks[i];
                if (!scratch.RanksByFramework.TryGetValue(framework, out var rank))
                {
                    rank = ++uniqueRankCount;
                    scratch.RanksByFramework.Add(framework, rank);
                }

                scratch.Ranks[i] = rank;
            }

            scratch.EnsureRankCapacity(uniqueRankCount);
            var resultCount = bindings.StableDistinctRankIndices(
                scratch.Ranks,
                uniqueRankCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (resultCount < 0 || resultCount > frameworkCount || resultCount > scratch.ResultIndices.Length)
            {
                distinctFrameworks = Array.Empty<string>();
                return false;
            }

            distinctFrameworks = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= frameworkCount)
                {
                    distinctFrameworks = Array.Empty<string>();
                    return false;
                }

                distinctFrameworks[i] = targetFrameworks[sourceIndex];
            }

            return true;
        }
        catch
        {
            distinctFrameworks = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.RanksByFramework.Clear();
        }
    }

    private static void BuildRanks(
        TreeCommand.TreeDependency[] dependencies,
        Scratch scratch,
        out int uniqueKindCount,
        out int uniqueNameCount)
    {
        for (var i = 0; i < dependencies.Length; i++)
        {
            var dependency = dependencies[i];
            if (!scratch.KindRankMap.ContainsKey(dependency.Kind))
            {
                scratch.KindRankMap.Add(dependency.Kind, 0);
                scratch.UniqueKinds[scratch.UniqueKindCount] = dependency.Kind;
                scratch.UniqueKindCount++;
            }

            if (!scratch.NameRankMap.ContainsKey(dependency.Name))
            {
                scratch.NameRankMap.Add(dependency.Name, 0);
                scratch.UniqueNames[scratch.UniqueNameCount] = dependency.Name;
                scratch.UniqueNameCount++;
            }
        }

        uniqueKindCount = scratch.UniqueKindCount;
        uniqueNameCount = scratch.UniqueNameCount;
        Array.Sort(scratch.UniqueKinds, 0, uniqueKindCount, StringComparer.Ordinal);
        for (var i = 0; i < uniqueKindCount; i++)
        {
            scratch.KindRankMap[scratch.UniqueKinds[i]] = i + 1;
        }

        Array.Sort(scratch.UniqueNames, 0, uniqueNameCount, StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < uniqueNameCount; i++)
        {
            scratch.NameRankMap[scratch.UniqueNames[i]] = i + 1;
        }

        for (var i = 0; i < dependencies.Length; i++)
        {
            scratch.KindRanks[i] = scratch.KindRankMap[dependencies[i].Kind];
            scratch.NameRanks[i] = scratch.NameRankMap[dependencies[i].Name];
        }
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var programType = DogfoodKernelLoader.TryGetProgramType();
            if (programType == null)
                return null;

            return new Bindings(
                DogfoodKernelLoader.CreateDelegate<CliTreeDependencyDeduplicateIndicesInto>(
                    programType,
                    "CliTreeDependencyDeduplicateIndicesInto"),
                DogfoodKernelLoader.CreateDelegate<CliStableDistinctRankIndicesInto>(
                    programType,
                    "CliStableDistinctRankIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private delegate int CliTreeDependencyDeduplicateIndicesInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] sortedIndices,
        int[] resultIndices);

    private delegate int CliStableDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private sealed record Bindings(
        CliTreeDependencyDeduplicateIndicesInto DeduplicateIndices,
        CliStableDistinctRankIndicesInto StableDistinctRankIndices);

    private sealed class Scratch
    {
        internal readonly Dictionary<string, int> KindRankMap = new(StringComparer.Ordinal);
        internal readonly Dictionary<string, int> NameRankMap = new(StringComparer.OrdinalIgnoreCase);

        internal int[] KindCounts = Array.Empty<int>();
        internal int[] KindOffsets = Array.Empty<int>();
        internal int[] KindRanks = Array.Empty<int>();
        internal int[] NameCounts = Array.Empty<int>();
        internal int[] NameOffsets = Array.Empty<int>();
        internal int[] NameRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SortedIndices = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();
        internal string[] UniqueKinds = Array.Empty<string>();
        internal string[] UniqueNames = Array.Empty<string>();
        internal int UniqueKindCount;
        internal int UniqueNameCount;

        internal void EnsureInputCapacity(int dependencyCount)
        {
            if (KindRanks.Length != dependencyCount)
            {
                KindRanks = new int[dependencyCount];
                NameRanks = new int[dependencyCount];
                UniqueKinds = new string[dependencyCount];
                UniqueNames = new string[dependencyCount];
            }
        }

        internal void EnsureScratchCapacity(int dependencyCount, int uniqueKindCount, int uniqueNameCount)
        {
            if (TempIndices.Length != dependencyCount)
            {
                TempIndices = new int[dependencyCount];
                SortedIndices = new int[dependencyCount];
                ResultIndices = new int[dependencyCount];
            }

            var kindBucketCapacity = uniqueKindCount + 1;
            if (KindCounts.Length != kindBucketCapacity)
            {
                KindCounts = new int[kindBucketCapacity];
                KindOffsets = new int[kindBucketCapacity];
            }

            var nameBucketCapacity = uniqueNameCount + 1;
            if (NameCounts.Length != nameBucketCapacity)
            {
                NameCounts = new int[nameBucketCapacity];
                NameOffsets = new int[nameBucketCapacity];
            }
        }

        internal void ResetRanks()
        {
            KindRankMap.Clear();
            NameRankMap.Clear();
            if (UniqueKindCount > 0)
            {
                Array.Clear(UniqueKinds, 0, UniqueKindCount);
                UniqueKindCount = 0;
            }

            if (UniqueNameCount > 0)
            {
                Array.Clear(UniqueNames, 0, UniqueNameCount);
                UniqueNameCount = 0;
            }
        }
    }

    private sealed class StableDistinctScratch
    {
        internal readonly Dictionary<string, int> RanksByFramework = new(StringComparer.OrdinalIgnoreCase);
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
