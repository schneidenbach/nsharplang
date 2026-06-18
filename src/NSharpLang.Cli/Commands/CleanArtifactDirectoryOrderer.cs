using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Cli.Commands;

internal static class CleanArtifactDirectoryOrderer
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryOrder(
        IReadOnlyList<string> directories,
        out string[] orderedDirectories)
    {
        orderedDirectories = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var directoryCount = directories.Count;
        if (directoryCount == 0)
            return true;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureInputCapacity(directoryCount);

        try
        {
            scratch.ResetPathRanks();
            var maxPathLength = 0;
            for (var i = 0; i < directoryCount; i++)
            {
                var directory = directories[i];
                scratch.KindRanks[i] = CleanCommand.IsArtifactDirectoryName(Path.GetFileName(directory)) ? 1 : 0;
                scratch.NodeModuleFlags[i] = CleanCommand.IsUnderNodeModulesDirectory(directory) ? 1 : 0;
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
                return false;

            orderedDirectories = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= directoryCount)
                {
                    orderedDirectories = Array.Empty<string>();
                    return false;
                }

                orderedDirectories[i] = directories[sourceIndex];
            }

            return true;
        }
        catch
        {
            orderedDirectories = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ResetPathRanks();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliCleanArtifactDirectoryIndicesInto>(
                programType,
                "CliCleanArtifactDirectoryIndicesInto")));

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

    private sealed record Bindings(CliCleanArtifactDirectoryIndicesInto OrderArtifactDirectoryIndices);

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
