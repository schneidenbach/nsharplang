using System;
using System.IO;

namespace NSharpLang.Compiler;

internal static class ProjectSourceFileFilter
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    internal static string[] Filter(
        string[] files,
        string projectRoot,
        string[] excludePatterns,
        bool includeTests)
    {
        var bindings = RequiredBindings;

        var fileCount = files.Length;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(fileCount);

        try
        {
            for (var i = 0; i < fileCount; i++)
            {
                var file = files[i];
                if (file == null)
                    throw new InvalidOperationException("N# project source-file filter received a null source file.");

                var relativePath = Path.GetRelativePath(projectRoot, file);
                scratch.RelativePaths[i] = relativePath;
            }

            var keptCount = bindings.ProjectSourceFilterKeptIndices(
                scratch.RelativePaths,
                excludePatterns,
                includeTests ? 1 : 0,
                scratch.ResultIndices);

            if (keptCount < 0 || keptCount > fileCount)
                throw new InvalidOperationException("N# project source-file filter kernel returned an invalid file count.");

            var result = new string[keptCount];
            for (var i = 0; i < keptCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= fileCount)
                    throw new InvalidOperationException("N# project source-file filter kernel returned an invalid source index.");

                result[i] = files[sourceIndex];
            }

            return result;
        }
        finally
        {
            scratch.ClearRelativePaths(fileCount);
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<ProjectSourceFilterKeptIndicesInto>(
                programType,
                "ProjectSourceFilterKeptIndicesInto")));

    private static Bindings RequiredBindings =>
        s_bindings.Value
        ?? throw new InvalidOperationException("N# project source-file filter kernel is unavailable.");

    private delegate int ProjectSourceFilterKeptIndicesInto(
        string[] relativePaths,
        string[] excludePatterns,
        int includeTests,
        int[] resultIndices);

    private sealed record Bindings(ProjectSourceFilterKeptIndicesInto ProjectSourceFilterKeptIndices);

    private sealed class Scratch
    {
        internal string[] RelativePaths = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            // The kernel iterates relativePaths.Length, so this buffer must be sized exactly.
            if (RelativePaths.Length != count)
            {
                RelativePaths = new string[count];
                ResultIndices = new int[count];
            }
        }

        internal void ClearRelativePaths(int count) => Array.Clear(RelativePaths, 0, count);
    }
}
