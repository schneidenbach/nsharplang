using System;
using System.IO;

namespace NSharpLang.Compiler;

internal static class ProjectSourceFileFilter
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    /// <summary>
    /// Single-pass replacement for ProjectConfig.GetSourceFiles' post-enumeration filtering
    /// (test-file filter + exclude-glob filter). Materializes the kept files preserving enumeration
    /// order. Returns false (so callers keep the C# path) when the dogfood assembly is unavailable
    /// or any input is unexpected.
    /// </summary>
    internal static bool TryFilter(
        string[] files,
        string projectRoot,
        string[] excludePatterns,
        bool includeTests,
        out string[] filteredFiles)
    {
        filteredFiles = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var fileCount = files.Length;
        if (fileCount == 0)
            return true;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(fileCount);

        try
        {
            for (var i = 0; i < fileCount; i++)
            {
                var file = files[i];
                if (file == null)
                    return false;

                var relativePath = Path.GetRelativePath(projectRoot, file);

                // The production glob uses .NET regex, where '.' (and '.*') does not match '\n' and
                // the trailing '$' anchor matches before a final '\n'. The N# kernel treats '\n' as
                // an ordinary character, so fall back to the exact C# regex path for the (extremely
                // rare) case of a newline in an on-disk file path to preserve exact parity.
                if (relativePath.Contains('\n'))
                    return false;

                scratch.RelativePaths[i] = relativePath;
            }

            var keptCount = bindings.ProjectSourceFilterKeptIndices(
                scratch.RelativePaths,
                excludePatterns,
                includeTests ? 1 : 0,
                scratch.ResultIndices);

            if (keptCount < 0 || keptCount > fileCount)
                return false;

            var result = new string[keptCount];
            for (var i = 0; i < keptCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= fileCount)
                    return false;

                result[i] = files[sourceIndex];
            }

            filteredFiles = result;
            return true;
        }
        catch
        {
            filteredFiles = Array.Empty<string>();
            return false;
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
