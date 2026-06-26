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

    internal static RestoreOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[1];
        var code = RequiredBindings.RestoreOptionSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# restore option summary kernel rejected the arguments.");

        return new RestoreOptionSummary(resultIndices[0] != 0);
    }

    internal static string[] DeduplicateProjectReferences(IReadOnlyList<string> projectReferences)
    {
        var bindings = RequiredBindings;
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
                throw new InvalidOperationException("N# restore project-reference deduplication kernel rejected the references.");

            var deduplicatedReferences = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= referenceCount)
                    throw new InvalidOperationException("N# restore project-reference deduplication kernel returned an invalid source index.");

                deduplicatedReferences[i] = projectReferences[sourceIndex];
            }

            return deduplicatedReferences;
        }
        finally
        {
            scratch.RanksByReference.Clear();
        }
    }

    internal static List<Reference> FilterReferencesByType(
        IReadOnlyList<Reference> references,
        ReferenceType targetType)
    {
        var bindings = RequiredBindings;
        var referenceCount = references.Count;
        var targetTypeId = (int)targetType;
        if (targetTypeId < 0 || targetTypeId > (int)ReferenceType.Framework)
            throw new InvalidOperationException("N# restore reference filter kernel received an unsupported reference type.");

        var scratch = t_referenceTypeFilterScratch ??= new ReferenceTypeFilterScratch();
        scratch.EnsureCapacity(referenceCount);

        for (var i = 0; i < referenceCount; i++)
            scratch.TypeRanks[i] = (int)references[i].Type;

        var filteredCount = bindings.ReferenceTypeFilterIndices(
            scratch.TypeRanks,
            targetTypeId,
            scratch.ResultIndices);

        if (filteredCount < 0 || filteredCount > referenceCount || filteredCount > scratch.ResultIndices.Length)
            throw new InvalidOperationException("N# restore reference filter kernel rejected the references.");

        var filteredReferences = new List<Reference>(filteredCount);
        for (var i = 0; i < filteredCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= referenceCount)
            {
                throw new InvalidOperationException("N# restore reference filter kernel returned an invalid source index.");
            }

            var reference = references[sourceIndex];
            if (reference.Type != targetType)
            {
                throw new InvalidOperationException("N# restore reference filter kernel returned a mismatched reference.");
            }

            filteredReferences.Add(reference);
        }

        return filteredReferences;
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

}
