using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Compiler;

internal static class SourceFileDeduplicator
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    internal static bool TryDeduplicateOrdinalIgnoreCase(
        IReadOnlyList<string> sourceFiles,
        out List<string> deduplicatedSourceFiles)
    {
        deduplicatedSourceFiles = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = sourceFiles.Count;
        if (count == 0)
            return true;

        var scratch = t_scratch ??= new Scratch(StringComparer.OrdinalIgnoreCase);
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetKeys();
            for (var i = 0; i < count; i++)
            {
                var sourceFile = sourceFiles[i];
                if (sourceFile == null)
                {
                    deduplicatedSourceFiles = [];
                    return false;
                }

                scratch.Ranks[i] = scratch.AddKey(sourceFile);
            }

            var deduplicatedCount = bindings.FirstDistinctRankIndices(
                scratch.Ranks,
                scratch.UniqueKeyCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (deduplicatedCount < 0 || deduplicatedCount > count || deduplicatedCount > scratch.ResultIndices.Length)
            {
                deduplicatedSourceFiles = [];
                return false;
            }

            var result = new List<string>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= count)
                {
                    deduplicatedSourceFiles = [];
                    return false;
                }

                result.Add(sourceFiles[sourceIndex]);
            }

            deduplicatedSourceFiles = result;
            return true;
        }
        catch
        {
            deduplicatedSourceFiles = [];
            return false;
        }
        finally
        {
            scratch.ResetKeys();
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
                CreateDelegate<FirstDistinctRankIndicesInto>(
                    programType,
                    "FirstDistinctRankIndicesInto"));
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

    private delegate int FirstDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private sealed record Bindings(FirstDistinctRankIndicesInto FirstDistinctRankIndices);

    private sealed class Scratch(IEqualityComparer<string> comparer)
    {
        private readonly Dictionary<string, int> _keyRanks = new(comparer);

        internal int[] Ranks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();
        internal int UniqueKeyCount;

        internal void EnsureCapacity(int count)
        {
            if (Ranks.Length != count)
            {
                Ranks = new int[count];
                ResultIndices = new int[count];
            }

            var rankCapacity = count + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        internal int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        internal void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }
}
