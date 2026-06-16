using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Cli;

internal static class GeneratedOutputDirectoryDeduplicator
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

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
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<CliStableDistinctRankIndicesInto>(
                    programType,
                    "CliStableDistinctRankIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

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
