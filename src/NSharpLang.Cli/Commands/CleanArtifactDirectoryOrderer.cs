using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

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
                if (!TryGetArtifactDirectoryKindRank(directory, bindings, out scratch.KindRanks[i]) ||
                    !TryIsUnderNodeModulesDirectory(directory, bindings, out var isUnderNodeModules))
                {
                    return false;
                }

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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product clean artifact classification and ordering route through N#.
    internal static string[] OrderWithCSharpFallback(IEnumerable<string> directories)
        => directories
            .Distinct(StringComparer.Ordinal)
            .Where(dir => !IsUnderNodeModulesDirectoryWithCSharp(dir))
            .Where(dir => IsArtifactDirectoryNameWithCSharp(Path.GetFileName(dir)))
            .OrderByDescending(dir => dir.Length)
            .ToArray();

    internal static bool TryGetArtifactDirectoryKindRank(string path, out int kindRank)
    {
        kindRank = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        return TryGetArtifactDirectoryKindRank(path, bindings, out kindRank);
    }

    internal static bool TryIsUnderNodeModulesDirectory(string path, out bool isUnderNodeModules)
    {
        isUnderNodeModules = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        return TryIsUnderNodeModulesDirectory(path, bindings, out isUnderNodeModules);
    }

    private static bool TryGetArtifactDirectoryKindRank(string path, Bindings bindings, out int kindRank)
    {
        kindRank = 0;

        try
        {
            var code = bindings.ArtifactDirectoryKindRank(path);
            if (code < 0 || code > ArtifactDirectories.Length)
                return false;

            kindRank = code;
            return true;
        }
        catch
        {
            kindRank = 0;
            return false;
        }
    }

    private static bool TryIsUnderNodeModulesDirectory(string path, Bindings bindings, out bool isUnderNodeModules)
    {
        isUnderNodeModules = false;

        try
        {
            var code = bindings.IsUnderNodeModulesDirectory(path);
            if (code == 0)
                return true;

            if (code == 1)
            {
                isUnderNodeModules = true;
                return true;
            }

            return false;
        }
        catch
        {
            isUnderNodeModules = false;
            return false;
        }
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

    private static bool IsArtifactDirectoryNameWithCSharp(string name) =>
        ArtifactDirectories.Contains(name, StringComparer.Ordinal);

    private static bool IsUnderNodeModulesDirectoryWithCSharp(string dir) =>
        NormalizePath(dir).Contains("/node_modules/", StringComparison.Ordinal);

    private static string NormalizePath(string path) => path.Replace('\\', '/');

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
