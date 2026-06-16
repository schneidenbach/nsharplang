using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal static class RestoreCommandKernels
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static ReferenceTypeFilterScratch? t_referenceTypeFilterScratch;
    [ThreadStatic]
    private static StableDistinctScratch? t_stableDistinctScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryDeduplicateProjectReferences(
        IReadOnlyList<string> projectReferences,
        out string[] deduplicatedReferences)
    {
        deduplicatedReferences = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var referenceCount = projectReferences.Count;
        if (referenceCount == 0)
            return true;

        var scratch = t_stableDistinctScratch ??= new StableDistinctScratch();
        scratch.EnsureCapacity(referenceCount);

        try
        {
            var uniqueRankCount = 0;
            for (var i = 0; i < referenceCount; i++)
            {
                var reference = projectReferences[i];
                if (!scratch.RanksByReference.TryGetValue(reference, out var rank))
                {
                    rank = ++uniqueRankCount;
                    scratch.RanksByReference.Add(reference, rank);
                }

                scratch.Ranks[i] = rank;
            }

            scratch.EnsureRankCapacity(uniqueRankCount);
            var resultCount = bindings.StableDistinctRankIndices(
                scratch.Ranks,
                uniqueRankCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (resultCount < 0 || resultCount > referenceCount || resultCount > scratch.ResultIndices.Length)
            {
                deduplicatedReferences = Array.Empty<string>();
                return false;
            }

            deduplicatedReferences = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= referenceCount)
                {
                    deduplicatedReferences = Array.Empty<string>();
                    return false;
                }

                deduplicatedReferences[i] = projectReferences[sourceIndex];
            }

            return true;
        }
        catch
        {
            deduplicatedReferences = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.RanksByReference.Clear();
        }
    }

    internal static bool TryFilterReferencesByType(
        IReadOnlyList<Reference> references,
        ReferenceType targetType,
        out List<Reference> filteredReferences)
    {
        filteredReferences = new List<Reference>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var referenceCount = references.Count;
        if (referenceCount == 0)
            return true;

        var targetTypeRank = GetReferenceTypeRank(targetType);
        if (targetTypeRank <= 0)
            return false;

        var scratch = t_referenceTypeFilterScratch ??= new ReferenceTypeFilterScratch();
        scratch.EnsureCapacity(referenceCount);

        try
        {
            for (var i = 0; i < referenceCount; i++)
                scratch.TypeRanks[i] = GetReferenceTypeRank(references[i].Type);

            var filteredCount = bindings.ReferenceTypeFilterIndices(
                scratch.TypeRanks,
                targetTypeRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > referenceCount || filteredCount > scratch.ResultIndices.Length)
                return false;

            filteredReferences = new List<Reference>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= referenceCount)
                {
                    filteredReferences = new List<Reference>();
                    return false;
                }

                var reference = references[sourceIndex];
                if (reference.Type != targetType)
                {
                    filteredReferences = new List<Reference>();
                    return false;
                }

                filteredReferences.Add(reference);
            }

            return true;
        }
        catch
        {
            filteredReferences = new List<Reference>();
            return false;
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
                CreateDelegate<CliReferenceTypeFilterIndicesInto>(
                    programType,
                    "CliReferenceTypeFilterIndicesInto"),
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

    private delegate int CliReferenceTypeFilterIndicesInto(
        int[] typeRanks,
        int targetTypeRank,
        int[] resultIndices);

    private delegate int CliStableDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private sealed record Bindings(
        CliReferenceTypeFilterIndicesInto ReferenceTypeFilterIndices,
        CliStableDistinctRankIndicesInto StableDistinctRankIndices);

    private static int GetReferenceTypeRank(ReferenceType type) =>
        type switch
        {
            ReferenceType.NuGet => 1,
            ReferenceType.Dll => 2,
            ReferenceType.Project => 3,
            ReferenceType.Framework => 4,
            _ => 0
        };

    private sealed class ReferenceTypeFilterScratch
    {
        internal int[] TypeRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int referenceCount)
        {
            if (TypeRanks.Length != referenceCount)
                TypeRanks = new int[referenceCount];

            if (ResultIndices.Length != referenceCount)
                ResultIndices = new int[referenceCount];
        }
    }

    private sealed class StableDistinctScratch
    {
        internal readonly Dictionary<string, int> RanksByReference = new(StringComparer.OrdinalIgnoreCase);
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
