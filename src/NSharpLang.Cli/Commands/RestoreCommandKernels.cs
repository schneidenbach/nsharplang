using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal readonly record struct RestoreOptionSummary(bool ShowHelp);

internal static class RestoreCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;
    [ThreadStatic]
    private static ReferenceTypeFilterScratch? t_referenceTypeFilterScratch;
    [ThreadStatic]
    private static StableDistinctScratch? t_stableDistinctScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out RestoreOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[1];
        try
        {
            var code = bindings.RestoreOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            summary = new RestoreOptionSummary(resultIndices[0] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryDeduplicateProjectReferences(
        IReadOnlyList<string> projectReferences,
        out string[] deduplicatedReferences)
    {
        deduplicatedReferences = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var referenceCount = projectReferences.Count;
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

    internal static string GetHelpText()
        => RequiredBindings.RestoreHelpText();

    internal static string GetMissingProjectFileMessage()
        => RequiredBindings.RestoreMissingProjectFileMessage();

    internal static string GetGeneratedPropsMessage()
        => RequiredBindings.RestoreGeneratedPropsMessage();

    internal static string GetFailedMessage(string message)
        => RequiredBindings.RestoreFailedMessage(message);

    internal static string GetGeneratedPropsText(
        string targetFramework,
        string outputType,
        string projectName,
        string backend,
        string testFramework,
        string baseSdk,
        string[] projectReferences)
        => RequiredBindings.RestoreGeneratedPropsText(
            targetFramework,
            outputType,
            projectName,
            backend,
            testFramework,
            baseSdk,
            projectReferences);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliReferenceTypeFilterIndicesInto>(
                programType,
                "CliReferenceTypeFilterIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliStableDistinctRankIndicesInto>(
                programType,
                "CliStableDistinctRankIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliRestoreOptionSummaryInto>(
                programType,
                "CliRestoreOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliRestoreHelpText>(
                programType,
                "CliRestoreHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliRestoreMissingProjectFileMessage>(
                programType,
                "CliRestoreMissingProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRestoreGeneratedPropsMessage>(
                programType,
                "CliRestoreGeneratedPropsMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRestoreFailedMessage>(
                programType,
                "CliRestoreFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRestoreGeneratedPropsText>(
                programType,
                "CliRestoreGeneratedPropsText")));

    private delegate int CliRestoreOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliReferenceTypeFilterIndicesInto(
        int[] typeRanks,
        int targetTypeRank,
        int[] resultIndices);

    private delegate int CliStableDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private delegate string CliRestoreHelpText();
    private delegate string CliRestoreMissingProjectFileMessage();
    private delegate string CliRestoreGeneratedPropsMessage();
    private delegate string CliRestoreFailedMessage(string message);
    private delegate string CliRestoreGeneratedPropsText(
        string targetFramework,
        string outputType,
        string projectName,
        string backend,
        string testFramework,
        string baseSdk,
        string[] projectReferences);

    private sealed record Bindings(
        CliReferenceTypeFilterIndicesInto ReferenceTypeFilterIndices,
        CliStableDistinctRankIndicesInto StableDistinctRankIndices,
        CliRestoreOptionSummaryInto RestoreOptionSummary,
        CliRestoreHelpText RestoreHelpText,
        CliRestoreMissingProjectFileMessage RestoreMissingProjectFileMessage,
        CliRestoreGeneratedPropsMessage RestoreGeneratedPropsMessage,
        CliRestoreFailedMessage RestoreFailedMessage,
        CliRestoreGeneratedPropsText RestoreGeneratedPropsText);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# restore command kernels are unavailable.");

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
