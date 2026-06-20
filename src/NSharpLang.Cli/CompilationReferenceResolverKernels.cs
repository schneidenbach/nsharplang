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

    internal static bool TrySelectBestScoreIndex(int[] scores, int count, out int bestIndex)
    {
        bestIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (count < 0 || count > scores.Length)
            return false;

        try
        {
            bestIndex = bindings.ReferenceResolutionBestScoreIndex(scores, count);
            if (bestIndex < -1 || bestIndex >= count)
            {
                bestIndex = -1;
                return false;
            }

            if (bestIndex >= 0 && scores[bestIndex] < 0)
            {
                bestIndex = -1;
                return false;
            }

            return true;
        }
        catch
        {
            bestIndex = -1;
            return false;
        }
    }

    internal static bool TryParseTargetFrameworkVersion(
        string targetFramework,
        out bool parsed,
        out int major,
        out int minor)
    {
        parsed = false;
        major = 0;
        minor = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_targetFrameworkVersionResult ??= new int[2];
        try
        {
            var code = bindings.TargetFrameworkVersion(targetFramework, result);
            if (code is not 0 and not 1)
                return false;

            parsed = code == 1;
            major = result[0];
            minor = result[1];
            return true;
        }
        catch
        {
            parsed = false;
            major = 0;
            minor = 0;
            return false;
        }
    }

    internal static bool TryCompareNuGetVersions(string x, string y, out int compare)
    {
        compare = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_nuGetVersionCompareResult ??= new int[9];
        try
        {
            var code = bindings.NuGetVersionCompare(x, y, result);
            if (code != 1)
                return false;

            compare = result[0];
            return compare is >= -1 and <= 1;
        }
        catch
        {
            compare = 0;
            return false;
        }
    }

    internal static bool TryGetFrameworkCompatibilityScore(string? assetFramework, string targetFramework, out int score)
    {
        score = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_frameworkCompatibilityScoreResult ??= new int[5];
        try
        {
            var code = bindings.FrameworkCompatibilityScore(assetFramework ?? string.Empty, targetFramework, result);
            if (code != 1)
                return false;

            score = result[0];
            return true;
        }
        catch
        {
            score = -1;
            return false;
        }
    }

    internal static bool TryNormalizeNuGetDependencyVersion(string? version, out string? normalizedVersion)
    {
        normalizedVersion = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var source = version ?? string.Empty;
        var result = t_nuGetDependencyVersionRangeResult ??= new int[2];
        try
        {
            var code = bindings.NuGetDependencyVersionRange(source, result);
            if (code == 0)
                return true;

            if (code != 1)
                return false;

            var start = result[0];
            var length = result[1];
            if (start < 0 || length <= 0 || start > source.Length || start + length > source.Length)
                return false;

            normalizedVersion = source.Substring(start, length);
            return true;
        }
        catch
        {
            normalizedVersion = null;
            return false;
        }
    }

    internal static bool TrySelectSharedFrameworkCandidateIndex(
        IReadOnlyList<Version> versions,
        int? targetMajor,
        out int selectedIndex)
    {
        selectedIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = versions.Count;
        if (count == 0)
            return true;

        var scratch = t_sharedFrameworkCandidateScratch ??= new SharedFrameworkCandidateScratch();
        scratch.EnsureCapacity(count);

        try
        {
            for (var i = 0; i < count; i++)
            {
                var version = versions[i];
                scratch.MajorVersions[i] = version.Major;
                scratch.MinorVersions[i] = version.Minor;
                scratch.BuildVersions[i] = version.Build;
                scratch.RevisionVersions[i] = version.Revision;
            }

            selectedIndex = bindings.SharedFrameworkCandidateIndex(
                scratch.MajorVersions,
                scratch.MinorVersions,
                scratch.BuildVersions,
                scratch.RevisionVersions,
                count,
                targetMajor.HasValue ? 1 : 0,
                targetMajor.GetValueOrDefault());

            if (selectedIndex < -1 || selectedIndex >= count)
            {
                selectedIndex = -1;
                return false;
            }

            return true;
        }
        catch
        {
            selectedIndex = -1;
            return false;
        }
    }

    internal static bool TrySelectLatestNuGetVersionIndex(string[] versions, out int selectedIndex)
    {
        selectedIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            selectedIndex = bindings.LatestNuGetVersionIndex(versions);
            if (selectedIndex < -1 || selectedIndex >= versions.Length)
            {
                selectedIndex = -1;
                return false;
            }

            return true;
        }
        catch
        {
            selectedIndex = -1;
            return false;
        }
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
            DogfoodKernelLoader.CreateDelegate<CliNuGetVersionCompareInto>(
                programType,
                "CliNuGetVersionCompareInto"),
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
                "CliLatestNuGetVersionIndex")));

    private delegate int CliReferenceTypeFilterIndicesInto(
        int[] typeRanks,
        int targetTypeRank,
        int[] resultIndices);

    private delegate int CliReferenceResolutionBestScoreIndex(int[] scores, int count);

    private delegate int CliTargetFrameworkVersionInto(string targetFramework, int[] result);

    private delegate int CliNuGetVersionCompareInto(string x, string y, int[] result);

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

    private sealed record Bindings(
        CliReferenceTypeFilterIndicesInto ReferenceTypeFilterIndices,
        CliReferenceResolutionBestScoreIndex ReferenceResolutionBestScoreIndex,
        CliTargetFrameworkVersionInto TargetFrameworkVersion,
        CliNuGetVersionCompareInto NuGetVersionCompare,
        CliFrameworkCompatibilityScoreInto FrameworkCompatibilityScore,
        CliNuGetDependencyVersionRangeInto NuGetDependencyVersionRange,
        CliSharedFrameworkCandidateIndex SharedFrameworkCandidateIndex,
        CliLatestNuGetVersionIndex LatestNuGetVersionIndex);

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
