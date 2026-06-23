using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal readonly record struct ExportCSharpOptionSummary(
    string? ProjectOption,
    string? OutputOption,
    bool ShowHelp);

internal enum ExportTargetKind
{
    Unknown = 0,
    CSharp = 1
}

internal readonly record struct ExportTargetSummary(
    ExportTargetKind TargetKind,
    bool ShowHelp);

internal static class ExportCommandKernels
{
    [ThreadStatic]
    private static OperandScratch? t_operandScratch;
    [ThreadStatic]
    private static ReferenceTypeFilterScratch? t_referenceTypeFilterScratch;
    [ThreadStatic]
    private static StableDistinctScratch? t_stableDistinctScratch;
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;
    [ThreadStatic]
    private static int[]? t_targetSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static ExportTargetSummary GetTargetSummary(string[] args)
    {
        var resultIndices = t_targetSummaryIndices ??= new int[2];
        var code = RequiredBindings.TargetSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# export target parser kernel rejected the arguments.");

        var targetKindValue = resultIndices[0];
        if (targetKindValue is not 0 and not 1)
            throw new InvalidOperationException("N# export target parser kernel rejected the arguments.");

        return new ExportTargetSummary(
            (ExportTargetKind)targetKindValue,
            resultIndices[1] != 0);
    }

    internal static ExportCSharpOptionSummary GetCSharpOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[3];
        var code = RequiredBindings.CSharpOptionSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# export csharp option parser kernel rejected the arguments.");

        var projectOption = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        var outputOption = resultIndices[1] == -1 ? null : args[resultIndices[1]];
        return new ExportCSharpOptionSummary(
            projectOption,
            outputOption,
            resultIndices[2] != 0);
    }

    internal static string? GetCSharpInputOperand(string[] args)
    {
        var scratch = t_operandScratch ??= new OperandScratch();
        scratch.EnsureCapacity(args.Length);

        var index = RequiredBindings.CSharpFirstOperandIndex(
            args,
            scratch.KindIds,
            scratch.NextIndices,
            scratch.PreviousIndices,
            scratch.NextOptionIndices,
            scratch.ResultIndices);
        if (index == -1)
            return null;

        if (index < 0 || index >= args.Length)
            throw new InvalidOperationException("N# export csharp input parser kernel rejected the arguments.");

        return args[index];
    }

    internal static List<Reference> FilterReferencesByType(
        IReadOnlyList<Reference> dependencies,
        ReferenceType targetType)
    {
        var bindings = RequiredBindings;
        var dependencyCount = dependencies.Count;
        var targetTypeRank = GetReferenceTypeRank(targetType);
        if (targetTypeRank <= 0)
            throw new InvalidOperationException("N# export reference filter kernel received an unsupported reference type.");

        var scratch = t_referenceTypeFilterScratch ??= new ReferenceTypeFilterScratch();
        scratch.EnsureCapacity(dependencyCount);

        for (var i = 0; i < dependencyCount; i++)
            scratch.TypeRanks[i] = GetReferenceTypeRank(dependencies[i].Type);

        var filteredCount = bindings.ReferenceTypeFilterIndices(
            scratch.TypeRanks,
            targetTypeRank,
            scratch.ResultIndices);

        if (filteredCount < 0 || filteredCount > dependencyCount || filteredCount > scratch.ResultIndices.Length)
            throw new InvalidOperationException("N# export reference filter kernel rejected the dependency table.");

        var filteredDependencies = new List<Reference>(filteredCount);
        for (var i = 0; i < filteredCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= dependencyCount)
            {
                throw new InvalidOperationException("N# export reference filter kernel returned an invalid source index.");
            }

            var dependency = dependencies[sourceIndex];
            if (dependency.Type != targetType)
            {
                throw new InvalidOperationException("N# export reference filter kernel returned a mismatched dependency.");
            }

            filteredDependencies.Add(dependency);
        }

        return filteredDependencies;
    }

    internal static List<T> DeduplicateReferences<T>(
        IReadOnlyList<T> values,
        IEqualityComparer<T>? comparer)
        where T : notnull
    {
        var bindings = RequiredBindings;
        var valueCount = values.Count;
        var scratch = t_stableDistinctScratch ??= new StableDistinctScratch();
        scratch.EnsureCapacity(valueCount);

        var ranksByValue = comparer == null
            ? new Dictionary<T, int>()
            : new Dictionary<T, int>(comparer);
        var uniqueRankCount = 0;

        for (var i = 0; i < valueCount; i++)
        {
            var value = values[i];
            if (!ranksByValue.TryGetValue(value, out var rank))
            {
                rank = ++uniqueRankCount;
                ranksByValue.Add(value, rank);
            }

            scratch.Ranks[i] = rank;
        }

        scratch.EnsureRankCapacity(uniqueRankCount);
        var resultCount = bindings.StableDistinctRankIndices(
            scratch.Ranks,
            uniqueRankCount,
            scratch.SeenRanks,
            scratch.ResultIndices);

        if (resultCount < 0 || resultCount > valueCount || resultCount > scratch.ResultIndices.Length)
            throw new InvalidOperationException("N# export reference deduplication kernel rejected the reference table.");

        var result = new List<T>(resultCount);
        for (var i = 0; i < resultCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= valueCount)
            {
                throw new InvalidOperationException("N# export reference deduplication kernel returned an invalid source index.");
            }

            result.Add(values[sourceIndex]);
        }

        return result;
    }

    internal static bool IsTestSourceFile(string sourceFile)
    {
        var result = RequiredBindings.IsTestSourceFile(sourceFile);
        if (result is not 0 and not 1)
            throw new InvalidOperationException("N# export test-source classifier kernel rejected the path.");

        return result != 0;
    }

    internal static string GetHelpText()
        => RequiredBindings.HelpText();

    internal static string GetCSharpHelpText()
        => RequiredBindings.CSharpHelpText();

    internal static string GetUnknownTargetMessage(string target)
        => RequiredBindings.UnknownTargetMessage(target);

    internal static string GetSourceAndProjectConflictMessage()
        => RequiredBindings.SourceAndProjectConflictMessage();

    internal static string GetPathNotFoundMessage(string path)
        => RequiredBindings.PathNotFoundMessage(path);

    internal static string GetNoInputMessage()
        => RequiredBindings.NoInputMessage();

    internal static string GetFailedMessage(string message)
        => RequiredBindings.FailedMessage(message);

    internal static string GetExpectedNlFileMessage(string path)
        => RequiredBindings.ExpectedNlFileMessage(path);

    internal static string GetMissingOutputMessage(string sourceFile)
        => RequiredBindings.MissingOutputMessage(sourceFile);

    internal static string GetRefuseOverwriteMessage()
        => RequiredBindings.RefuseOverwriteMessage();

    internal static string GetSingleFileSuccessMessage(string fileName, string outputPath)
        => RequiredBindings.SingleFileSuccessMessage(fileName, outputPath);

    internal static string GetNoProjectFileMessage(string projectRoot)
        => RequiredBindings.NoProjectFileMessage(projectRoot);

    internal static string GetProjectSuccessMessage(string projectName, string projectFilePath)
        => RequiredBindings.ProjectSuccessMessage(projectName, projectFilePath);

    internal static string GetTestsSuccessMessage(string testProjectFilePath)
        => RequiredBindings.TestsSuccessMessage(testProjectFilePath);

    internal static string GetCSharpMainProjectFileText(
        string sdk,
        string targetFramework,
        string outputType,
        string assemblyName,
        string version,
        string packageAuthor,
        string packageDescription,
        string packageTags,
        int packageTagsCount,
        string packageLicense,
        string packageRepository,
        string packageIconFileName,
        int includePackageIcon,
        string[] packageNames,
        string[] packageVersions,
        int[] packagePrivateAssetsAll,
        string[] packageIncludeAssets,
        string[] frameworkReferences,
        string[] projectReferences,
        string[] dllReferenceNames,
        string[] dllReferenceHintPaths)
    {
        return RequiredBindings.CSharpMainProjectFileText(
            sdk,
            targetFramework,
            outputType,
            assemblyName,
            version,
            packageAuthor,
            packageDescription,
            packageTags,
            packageTagsCount,
            packageLicense,
            packageRepository,
            packageIconFileName,
            includePackageIcon,
            packageNames,
            packageVersions,
            packagePrivateAssetsAll,
            packageIncludeAssets,
            frameworkReferences,
            projectReferences,
            dllReferenceNames,
            dllReferenceHintPaths);
    }

    internal static string GetCSharpTestProjectFileText(
        string targetFramework,
        string[] packageNames,
        string[] packageVersions,
        int[] packagePrivateAssetsAll,
        string[] packageIncludeAssets,
        string[] frameworkReferences,
        string[] projectReferences,
        string[] dllReferenceNames,
        string[] dllReferenceHintPaths)
    {
        return RequiredBindings.CSharpTestProjectFileText(
            targetFramework,
            packageNames,
            packageVersions,
            packagePrivateAssetsAll,
            packageIncludeAssets,
            frameworkReferences,
            projectReferences,
            dllReferenceNames,
            dllReferenceHintPaths);
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliExportCSharpFirstOperandIndexInto>(
                programType,
                "CliExportCSharpFirstOperandIndexInto"),
            DogfoodKernelLoader.CreateDelegate<CliReferenceTypeFilterIndicesInto>(
                programType,
                "CliReferenceTypeFilterIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliStableDistinctRankIndicesInto>(
                programType,
                "CliStableDistinctRankIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliExportCSharpOptionSummaryInto>(
                programType,
                "CliExportCSharpOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliExportTargetSummaryInto>(
                programType,
                "CliExportTargetSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliExportIsTestSourceFile>(
                programType,
                "CliExportIsTestSourceFile"),
            DogfoodKernelLoader.CreateDelegate<CliExportHelpText>(
                programType,
                "CliExportHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliExportCSharpHelpText>(
                programType,
                "CliExportCSharpHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliExportUnknownTargetMessage>(
                programType,
                "CliExportUnknownTargetMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportSourceAndProjectConflictMessage>(
                programType,
                "CliExportSourceAndProjectConflictMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportPathNotFoundMessage>(
                programType,
                "CliExportPathNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportNoInputMessage>(
                programType,
                "CliExportNoInputMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportFailedMessage>(
                programType,
                "CliExportFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportExpectedNlFileMessage>(
                programType,
                "CliExportExpectedNlFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportMissingOutputMessage>(
                programType,
                "CliExportMissingOutputMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportRefuseOverwriteMessage>(
                programType,
                "CliExportRefuseOverwriteMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportSingleFileSuccessMessage>(
                programType,
                "CliExportSingleFileSuccessMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportNoProjectFileMessage>(
                programType,
                "CliExportNoProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportProjectSuccessMessage>(
                programType,
                "CliExportProjectSuccessMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportTestsSuccessMessage>(
                programType,
                "CliExportTestsSuccessMessage"),
            DogfoodKernelLoader.CreateDelegate<CliExportCSharpMainProjectFileText>(
                programType,
                "CliExportCSharpMainProjectFileText"),
            DogfoodKernelLoader.CreateDelegate<CliExportCSharpTestProjectFileText>(
                programType,
                "CliExportCSharpTestProjectFileText")));

    private delegate int CliExportCSharpFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
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

    private delegate int CliExportCSharpOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliExportTargetSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliExportIsTestSourceFile(
        string sourceFile);

    private delegate string CliExportHelpText();

    private delegate string CliExportCSharpHelpText();

    private delegate string CliExportUnknownTargetMessage(string target);

    private delegate string CliExportSourceAndProjectConflictMessage();

    private delegate string CliExportPathNotFoundMessage(string path);

    private delegate string CliExportNoInputMessage();

    private delegate string CliExportFailedMessage(string message);

    private delegate string CliExportExpectedNlFileMessage(string path);

    private delegate string CliExportMissingOutputMessage(string sourceFile);

    private delegate string CliExportRefuseOverwriteMessage();

    private delegate string CliExportSingleFileSuccessMessage(string fileName, string outputPath);

    private delegate string CliExportNoProjectFileMessage(string projectRoot);

    private delegate string CliExportProjectSuccessMessage(string projectName, string projectFilePath);

    private delegate string CliExportTestsSuccessMessage(string testProjectFilePath);

    private delegate string CliExportCSharpMainProjectFileText(
        string sdk,
        string targetFramework,
        string outputType,
        string assemblyName,
        string version,
        string packageAuthor,
        string packageDescription,
        string packageTags,
        int packageTagsCount,
        string packageLicense,
        string packageRepository,
        string packageIconFileName,
        int includePackageIcon,
        string[] packageNames,
        string[] packageVersions,
        int[] packagePrivateAssetsAll,
        string[] packageIncludeAssets,
        string[] frameworkReferences,
        string[] projectReferences,
        string[] dllReferenceNames,
        string[] dllReferenceHintPaths);

    private delegate string CliExportCSharpTestProjectFileText(
        string targetFramework,
        string[] packageNames,
        string[] packageVersions,
        int[] packagePrivateAssetsAll,
        string[] packageIncludeAssets,
        string[] frameworkReferences,
        string[] projectReferences,
        string[] dllReferenceNames,
        string[] dllReferenceHintPaths);

    private sealed record Bindings(
        CliExportCSharpFirstOperandIndexInto CSharpFirstOperandIndex,
        CliReferenceTypeFilterIndicesInto ReferenceTypeFilterIndices,
        CliStableDistinctRankIndicesInto StableDistinctRankIndices,
        CliExportCSharpOptionSummaryInto CSharpOptionSummary,
        CliExportTargetSummaryInto TargetSummary,
        CliExportIsTestSourceFile IsTestSourceFile,
        CliExportHelpText HelpText,
        CliExportCSharpHelpText CSharpHelpText,
        CliExportUnknownTargetMessage UnknownTargetMessage,
        CliExportSourceAndProjectConflictMessage SourceAndProjectConflictMessage,
        CliExportPathNotFoundMessage PathNotFoundMessage,
        CliExportNoInputMessage NoInputMessage,
        CliExportFailedMessage FailedMessage,
        CliExportExpectedNlFileMessage ExpectedNlFileMessage,
        CliExportMissingOutputMessage MissingOutputMessage,
        CliExportRefuseOverwriteMessage RefuseOverwriteMessage,
        CliExportSingleFileSuccessMessage SingleFileSuccessMessage,
        CliExportNoProjectFileMessage NoProjectFileMessage,
        CliExportProjectSuccessMessage ProjectSuccessMessage,
        CliExportTestsSuccessMessage TestsSuccessMessage,
        CliExportCSharpMainProjectFileText CSharpMainProjectFileText,
        CliExportCSharpTestProjectFileText CSharpTestProjectFileText);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# export command kernels are unavailable.");

    private static int GetReferenceTypeRank(ReferenceType type) =>
        type switch
        {
            ReferenceType.NuGet => 1,
            ReferenceType.Dll => 2,
            ReferenceType.Project => 3,
            ReferenceType.Framework => 4,
            _ => 0
        };

    private sealed class OperandScratch
    {
        internal int[] KindIds = Array.Empty<int>();
        internal int[] NextIndices = Array.Empty<int>();
        internal int[] NextOptionIndices = Array.Empty<int>();
        internal int[] PreviousIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
                KindIds = new int[count];

            if (NextIndices.Length != count)
                NextIndices = new int[count];

            if (NextOptionIndices.Length != count)
                NextOptionIndices = new int[count];

            if (PreviousIndices.Length != count)
                PreviousIndices = new int[count];

            if (ResultIndices.Length != count)
                ResultIndices = new int[count];
        }
    }

    private sealed class ReferenceTypeFilterScratch
    {
        internal int[] TypeRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int dependencyCount)
        {
            if (TypeRanks.Length != dependencyCount)
                TypeRanks = new int[dependencyCount];

            if (ResultIndices.Length != dependencyCount)
                ResultIndices = new int[dependencyCount];
        }
    }

    private sealed class StableDistinctScratch
    {
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
