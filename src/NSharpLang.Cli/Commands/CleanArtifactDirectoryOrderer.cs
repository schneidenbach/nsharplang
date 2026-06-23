using System;
using System.Collections.Generic;

namespace NSharpLang.Cli.Commands;

internal static class CleanArtifactDirectoryOrderer
{
    private static readonly string[] ArtifactDirectories =
    {
        "bin",
        "obj",
        ".nlc"
    };

    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string[] Order(IReadOnlyList<string> directories)
    {
        var bindings = RequiredBindings;
        var directoryCount = directories.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureInputCapacity(directoryCount);

        try
        {
            scratch.ResetPathRanks();
            var maxPathLength = 0;
            for (var i = 0; i < directoryCount; i++)
            {
                var directory = directories[i];
                scratch.KindRanks[i] = GetArtifactDirectoryKindRank(directory, bindings);
                var isUnderNodeModules = IsUnderNodeModulesDirectory(directory, bindings);
                scratch.NodeModuleFlags[i] = isUnderNodeModules ? 1 : 0;
                scratch.PathLengths[i] = directory.Length;
                scratch.AddPath(directory);

                if (directory.Length > maxPathLength)
                    maxPathLength = directory.Length;
            }

            scratch.EnsureScratchCapacity(scratch.UniquePathCount, maxPathLength);
            for (var i = 0; i < directoryCount; i++)
            {
                scratch.PathRanks[i] = scratch.GetPathRank(directories[i]);
            }

            var orderedCount = bindings.OrderArtifactDirectoryIndices(
                scratch.KindRanks,
                scratch.NodeModuleFlags,
                scratch.PathRanks,
                scratch.PathLengths,
                scratch.SeenPathRanks,
                scratch.LengthCounts,
                scratch.LengthOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > directoryCount || orderedCount > scratch.ResultIndices.Length)
                throw new InvalidOperationException("N# clean artifact directory order kernel returned an invalid result count.");

            var orderedDirectories = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= directoryCount)
                    throw new InvalidOperationException("N# clean artifact directory order kernel returned an invalid directory index.");

                orderedDirectories[i] = directories[sourceIndex];
            }

            return orderedDirectories;
        }
        finally
        {
            scratch.ResetPathRanks();
        }
    }

    private static int GetArtifactDirectoryKindRank(string path, Bindings bindings)
    {
        var code = bindings.ArtifactDirectoryKindRank(path);
        if (code < 0 || code > ArtifactDirectories.Length)
            throw new InvalidOperationException("N# clean artifact directory kind kernel returned an invalid rank.");

        return code;
    }

    private static bool IsUnderNodeModulesDirectory(string path, Bindings bindings)
    {
        var code = bindings.IsUnderNodeModulesDirectory(path);
        if (code == 0)
            return false;

        if (code == 1)
            return true;

        throw new InvalidOperationException("N# clean node_modules directory kernel returned an invalid code.");
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliCleanArtifactDirectoryKindRank>(
                programType,
                "CliCleanArtifactDirectoryKindRank"),
            DogfoodKernelLoader.CreateDelegate<CliCleanIsUnderNodeModulesDirectory>(
                programType,
                "CliCleanIsUnderNodeModulesDirectory"),
            DogfoodKernelLoader.CreateDelegate<CliCleanArtifactDirectoryIndicesInto>(
                programType,
                "CliCleanArtifactDirectoryIndicesInto")));

    private static Bindings RequiredBindings
        => s_bindings.Value
            ?? throw new InvalidOperationException("N# clean artifact directory order kernels are unavailable.");

    private delegate int CliCleanArtifactDirectoryKindRank(string path);

    private delegate int CliCleanIsUnderNodeModulesDirectory(string path);

    private delegate int CliCleanArtifactDirectoryIndicesInto(
        int[] kindRanks,
        int[] nodeModuleFlags,
        int[] pathRanks,
        int[] pathLengths,
        int[] seenPathRanks,
        int[] lengthCounts,
        int[] lengthOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private sealed record Bindings(
        CliCleanArtifactDirectoryKindRank ArtifactDirectoryKindRank,
        CliCleanIsUnderNodeModulesDirectory IsUnderNodeModulesDirectory,
        CliCleanArtifactDirectoryIndicesInto OrderArtifactDirectoryIndices);

    private sealed class Scratch
    {
        private readonly Dictionary<string, int> _pathRanks = new(StringComparer.Ordinal);

        internal int[] KindRanks = Array.Empty<int>();
        internal int[] LengthCounts = Array.Empty<int>();
        internal int[] LengthOffsets = Array.Empty<int>();
        internal int[] NodeModuleFlags = Array.Empty<int>();
        internal int[] PathLengths = Array.Empty<int>();
        internal int[] PathRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenPathRanks = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();
        internal int UniquePathCount;

        internal void EnsureInputCapacity(int directoryCount)
        {
            if (KindRanks.Length != directoryCount)
            {
                KindRanks = new int[directoryCount];
                NodeModuleFlags = new int[directoryCount];
                PathRanks = new int[directoryCount];
                PathLengths = new int[directoryCount];
                TempIndices = new int[directoryCount];
                ResultIndices = new int[directoryCount];
            }
        }

        internal void EnsureScratchCapacity(int uniquePathCount, int maxPathLength)
        {
            var pathRankCapacity = uniquePathCount + 1;
            if (SeenPathRanks.Length != pathRankCapacity)
            {
                SeenPathRanks = new int[pathRankCapacity];
            }

            var lengthCapacity = maxPathLength + 1;
            if (LengthCounts.Length != lengthCapacity)
            {
                LengthCounts = new int[lengthCapacity];
                LengthOffsets = new int[lengthCapacity];
            }
        }

        internal void AddPath(string path)
        {
            if (_pathRanks.ContainsKey(path))
                return;

            UniquePathCount++;
            _pathRanks.Add(path, UniquePathCount);
        }

        internal int GetPathRank(string path) => _pathRanks[path];

        internal void ResetPathRanks()
        {
            _pathRanks.Clear();
            UniquePathCount = 0;
        }
    }
}
