using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal static class CompilationReferenceResolverKernels
{
    [ThreadStatic]
    private static ReferenceTypeFilterScratch? t_referenceTypeFilterScratch;

    [ThreadStatic]
    private static int[]? t_targetFrameworkVersionResult;

    [ThreadStatic]
    private static int[]? t_nuGetVersionCompareResult;

    [ThreadStatic]
    private static int[]? t_frameworkCompatibilityScoreResult;

    [ThreadStatic]
    private static int[]? t_nuGetDependencyVersionRangeResult;

    [ThreadStatic]
    private static SharedFrameworkCandidateScratch? t_sharedFrameworkCandidateScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static List<Reference> FilterReferencesByType(
        IReadOnlyList<Reference> references,
        ReferenceType targetType)
    {
        var referenceCount = references.Count;
        var targetTypeId = (int)targetType;
        if (targetTypeId < 0 || targetTypeId > (int)ReferenceType.Framework)
            throw new ArgumentOutOfRangeException(nameof(targetType), "Reference type is not supported.");

        var scratch = t_referenceTypeFilterScratch ??= new ReferenceTypeFilterScratch();
        scratch.EnsureCapacity(referenceCount);

        for (var i = 0; i < referenceCount; i++)
        {
            var typeId = (int)references[i].Type;
            if (typeId < 0 || typeId > (int)ReferenceType.Framework)
                throw new InvalidOperationException("N# reference resolver type filter received an unsupported reference type.");

            scratch.TypeRanks[i] = typeId;
        }

        var filteredCount = RequiredBindings.ReferenceTypeFilterIndices(
            scratch.TypeRanks,
            targetTypeId,
            scratch.ResultIndices);

        if (filteredCount < 0 || filteredCount > referenceCount || filteredCount > scratch.ResultIndices.Length)
            throw new InvalidOperationException("N# reference resolver type filter kernel returned an invalid result count.");

        var filteredReferences = new List<Reference>(filteredCount);
        for (var i = 0; i < filteredCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= referenceCount)
                throw new InvalidOperationException("N# reference resolver type filter kernel returned an invalid reference index.");

            var reference = references[sourceIndex];
            if (reference.Type != targetType)
                throw new InvalidOperationException("N# reference resolver type filter kernel selected the wrong reference type.");

            filteredReferences.Add(reference);
        }

        return filteredReferences;
    }

    internal static int SelectBestScoreIndex(int[] scores, int count)
    {
        if (count < 0 || count > scores.Length)
            throw new ArgumentOutOfRangeException(nameof(count), "Score count must fit within the score array.");

        var bestIndex = RequiredBindings.ReferenceResolutionBestScoreIndex(scores, count);
        if (bestIndex < -1 || bestIndex >= count)
            throw new InvalidOperationException("N# reference resolver score kernel returned an invalid score index.");

        if (bestIndex >= 0 && scores[bestIndex] < 0)
            throw new InvalidOperationException("N# reference resolver score kernel selected an incompatible score.");

        return bestIndex;
    }

    internal static (bool Parsed, int Major, int Minor) ParseTargetFrameworkVersion(string targetFramework)
    {
        var result = t_targetFrameworkVersionResult ??= new int[2];

        var code = RequiredBindings.TargetFrameworkVersion(targetFramework, result);
        if (code is not 0 and not 1)
            throw new InvalidOperationException("N# reference resolver target-framework parser returned an invalid code.");

        return code == 1
            ? (true, result[0], result[1])
            : (false, 0, 0);
    }

    internal static int GetFrameworkCompatibilityScore(string? assetFramework, string targetFramework)
    {
        var result = t_frameworkCompatibilityScoreResult ??= new int[5];

        var code = RequiredBindings.FrameworkCompatibilityScore(assetFramework ?? string.Empty, targetFramework, result);
        if (code != 1)
            throw new InvalidOperationException("N# reference resolver framework compatibility kernel returned an invalid code.");

        return result[0];
    }

    internal static string? NormalizeNuGetDependencyVersion(string? version)
    {
        var source = version ?? string.Empty;
        var result = t_nuGetDependencyVersionRangeResult ??= new int[2];

        var code = RequiredBindings.NuGetDependencyVersionRange(source, result);
        if (code == 0)
            return null;

        if (code != 1)
            throw new InvalidOperationException("N# reference resolver dependency-version kernel returned an invalid code.");

        var start = result[0];
        var length = result[1];
        if (start < 0 || length <= 0 || start > source.Length || start + length > source.Length)
            throw new InvalidOperationException("N# reference resolver dependency-version kernel returned an invalid range.");

        return source.Substring(start, length);
    }

    internal static int SelectSharedFrameworkCandidateIndex(
        IReadOnlyList<Version> versions,
        int? targetMajor)
    {
        var count = versions.Count;
        var scratch = t_sharedFrameworkCandidateScratch ??= new SharedFrameworkCandidateScratch();
        scratch.EnsureCapacity(count);

        for (var i = 0; i < count; i++)
        {
            var version = versions[i];
            scratch.MajorVersions[i] = version.Major;
            scratch.MinorVersions[i] = version.Minor;
            scratch.BuildVersions[i] = version.Build;
            scratch.RevisionVersions[i] = version.Revision;
        }

        var selectedIndex = RequiredBindings.SharedFrameworkCandidateIndex(
            scratch.MajorVersions,
            scratch.MinorVersions,
            scratch.BuildVersions,
            scratch.RevisionVersions,
            count,
            targetMajor.HasValue ? 1 : 0,
            targetMajor.GetValueOrDefault());

        if (selectedIndex < -1 || selectedIndex >= count)
            throw new InvalidOperationException("N# reference resolver shared-framework kernel returned an invalid candidate index.");

        return selectedIndex;
    }

    internal static int SelectLatestNuGetVersionIndex(string[] versions)
    {
        var selectedIndex = RequiredBindings.LatestNuGetVersionIndex(versions);
        if (selectedIndex < -1 || selectedIndex >= versions.Length)
            throw new InvalidOperationException("N# reference resolver latest NuGet version kernel returned an invalid version index.");

        return selectedIndex;
    }

    internal static int SelectBestNuGetVersionIndex(string[] versions)
    {
        var compareScratch = t_nuGetVersionCompareResult ??= new int[9];
        var selectedIndex = RequiredBindings.BestNuGetVersionIndex(versions, compareScratch);
        if (selectedIndex < -1 || selectedIndex >= versions.Length)
            throw new InvalidOperationException("N# reference resolver best NuGet version kernel returned an invalid version index.");

        return selectedIndex;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliReferenceTypeFilterIndicesInto>(
                programType,
                "CliReferenceTypeFilterIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliReferenceResolutionBestScoreIndex>(
                programType,
                "CliReferenceResolutionBestScoreIndex"),
            DogfoodKernelLoader.CreateDelegate<CliTargetFrameworkVersionInto>(
                programType,
                "CliTargetFrameworkVersionInto"),
            DogfoodKernelLoader.CreateDelegate<CliFrameworkCompatibilityScoreInto>(
                programType,
                "CliFrameworkCompatibilityScoreInto"),
            DogfoodKernelLoader.CreateDelegate<CliNuGetDependencyVersionRangeInto>(
                programType,
                "CliNuGetDependencyVersionRangeInto"),
            DogfoodKernelLoader.CreateDelegate<CliSharedFrameworkCandidateIndex>(
                programType,
                "CliSharedFrameworkCandidateIndex"),
            DogfoodKernelLoader.CreateDelegate<CliLatestNuGetVersionIndex>(
                programType,
                "CliLatestNuGetVersionIndex"),
            DogfoodKernelLoader.CreateDelegate<CliBestNuGetVersionIndex>(
                programType,
                "CliBestNuGetVersionIndex")));

    private static Bindings RequiredBindings
        => s_bindings.Value
            ?? throw new InvalidOperationException("N# reference resolver kernels are unavailable.");

    private delegate int CliReferenceTypeFilterIndicesInto(
        int[] typeRanks,
        int targetTypeRank,
        int[] resultIndices);

    private delegate int CliReferenceResolutionBestScoreIndex(int[] scores, int count);

    private delegate int CliTargetFrameworkVersionInto(string targetFramework, int[] result);

    private delegate int CliFrameworkCompatibilityScoreInto(
        string assetFramework,
        string targetFramework,
        int[] result);

    private delegate int CliNuGetDependencyVersionRangeInto(string version, int[] result);

    private delegate int CliSharedFrameworkCandidateIndex(
        int[] majorVersions,
        int[] minorVersions,
        int[] buildVersions,
        int[] revisionVersions,
        int count,
        int targetParsed,
        int targetMajor);

    private delegate int CliLatestNuGetVersionIndex(string[] versions);

    private delegate int CliBestNuGetVersionIndex(string[] versions, int[] compareScratch);

    private sealed record Bindings(
        CliReferenceTypeFilterIndicesInto ReferenceTypeFilterIndices,
        CliReferenceResolutionBestScoreIndex ReferenceResolutionBestScoreIndex,
        CliTargetFrameworkVersionInto TargetFrameworkVersion,
        CliFrameworkCompatibilityScoreInto FrameworkCompatibilityScore,
        CliNuGetDependencyVersionRangeInto NuGetDependencyVersionRange,
        CliSharedFrameworkCandidateIndex SharedFrameworkCandidateIndex,
        CliLatestNuGetVersionIndex LatestNuGetVersionIndex,
        CliBestNuGetVersionIndex BestNuGetVersionIndex);

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

    private sealed class SharedFrameworkCandidateScratch
    {
        internal int[] MajorVersions = Array.Empty<int>();
        internal int[] MinorVersions = Array.Empty<int>();
        internal int[] BuildVersions = Array.Empty<int>();
        internal int[] RevisionVersions = Array.Empty<int>();

        internal void EnsureCapacity(int candidateCount)
        {
            if (MajorVersions.Length >= candidateCount)
                return;

            MajorVersions = new int[candidateCount];
            MinorVersions = new int[candidateCount];
            BuildVersions = new int[candidateCount];
            RevisionVersions = new int[candidateCount];
        }
    }
}
