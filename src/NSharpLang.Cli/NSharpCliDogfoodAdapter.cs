using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli;

internal static class NSharpCliDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static BatchDuplicateIdScratch? t_batchDuplicateIdScratch;
    [ThreadStatic]
    private static BuildOperandScratch? t_buildOperandScratch;
    [ThreadStatic]
    private static DocSymbolOrderScratch? t_docSymbolOrderScratch;
    [ThreadStatic]
    private static TreeDependencyDeduplicateScratch? t_treeDependencyDeduplicateScratch;
    [ThreadStatic]
    private static CompilerErrorSeverityFilterScratch? t_compilerErrorSeverityFilterScratch;
    [ThreadStatic]
    private static FixAppliedFileGroupingScratch? t_fixAppliedFileGroupingScratch;
    [ThreadStatic]
    private static UnifiedDiffHunkScratch? t_unifiedDiffHunkScratch;
    [ThreadStatic]
    private static FixSafetyFilterScratch? t_fixSafetyFilterScratch;
    [ThreadStatic]
    private static CleanArtifactDirectoryScratch? t_cleanArtifactDirectoryScratch;
    [ThreadStatic]
    private static UpdateDependencyFilterScratch? t_updateDependencyFilterScratch;
    [ThreadStatic]
    private static ReferenceTypeFilterScratch? t_referenceTypeFilterScratch;
    [ThreadStatic]
    private static StableDistinctScratch? t_stableDistinctScratch;
    [ThreadStatic]
    private static LintFileArgScratch? t_lintFileArgScratch;
    [ThreadStatic]
    private static int[]? t_publishOptionIndices;
    [ThreadStatic]
    private static TidyDependencyStatusFilterScratch? t_tidyDependencyStatusFilterScratch;
    [ThreadStatic]
    private static TidyRemovalLineScratch? t_tidyRemovalLineScratch;
    [ThreadStatic]
    private static TestOutcomeSummaryScratch? t_testOutcomeSummaryScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings);

    internal static bool TryGetBuildOperandSummary(string[] args, out int count, out int firstOperandIndex)
    {
        count = 0;
        firstOperandIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_buildOperandScratch ??= new BuildOperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            firstOperandIndex = bindings.CliBuildFirstOperandIndex(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (firstOperandIndex < -1 || firstOperandIndex >= args.Length)
            {
                count = 0;
                firstOperandIndex = -1;
                return false;
            }

            count = firstOperandIndex >= 0 ? 1 : 0;
            return true;
        }
        catch
        {
            count = 0;
            firstOperandIndex = -1;
            return false;
        }
    }

    internal static bool TryGetRunSourceOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.CliRunFirstOperandIndex(args);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            operand = args[index];
            return true;
        }
        catch
        {
            operand = null;
            return false;
        }
    }

    internal static bool TryGetPublishArgumentSummary(string[] args, out PublishArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length != 0)
            return false;

        var resultIndices = t_publishOptionIndices ??= new int[8];
        try
        {
            var code = bindings.CliPublishOptionsInto(args, resultIndices);
            if (code < 0 || code > 4)
                return false;

            var validationError = GetPublishValidationError(args, code, resultIndices[7]);
            if (validationError != null)
            {
                summary = new PublishArgumentSummary(
                    validationError,
                    null,
                    null,
                    "Release",
                    null,
                    null,
                    false,
                    false);
                return true;
            }

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var backendOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var configuration)
                || !TryGetOptionalArg(args, resultIndices[3], out var output)
                || !TryGetOptionalArg(args, resultIndices[4], out var runtime))
            {
                summary = default;
                return false;
            }

            summary = new PublishArgumentSummary(
                null,
                projectOption,
                backendOption,
                configuration ?? "Release",
                output,
                runtime,
                resultIndices[5] != 0,
                resultIndices[6] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    private static string? GetPublishValidationError(string[] args, int code, int errorArgIndex)
    {
        if (code == 0)
            return null;

        if (code == 2)
        {
            return "Target-platform publishing is expressed as --runtime <rid>, and nlc publish does not support cross-runtime publishing yet.";
        }

        if (errorArgIndex < 0 || errorArgIndex >= args.Length)
            return null;

        return code switch
        {
            1 => $"Option '{args[errorArgIndex]}' requires a value.",
            3 => $"Unknown publish option '{args[errorArgIndex]}'. Run 'nlc publish --help' for supported options.",
            4 => $"Unexpected publish argument '{args[errorArgIndex]}'. Run 'nlc publish --help' for usage.",
            _ => null
        };
    }

    private static bool TryGetOptionalArg(string[] args, int index, out string? value)
    {
        value = null;
        if (index == -1)
            return true;

        if (index < 0 || index >= args.Length)
            return false;

        value = args[index];
        return true;
    }

    internal static bool TryGetFirstPositionalArg(
        string[] args,
        string[] optionsWithValues,
        out string? positional)
    {
        positional = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.CliFirstPositionalArgIndex(args, optionsWithValues);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            positional = args[index];
            return true;
        }
        catch
        {
            positional = null;
            return false;
        }
    }

    internal static bool TryGetLintFileArgs(string[] args, out string[] files)
    {
        files = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_lintFileArgScratch ??= new LintFileArgScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            var count = bindings.CliLintFileArgIndices(
                args,
                scratch.ProjectValueIndices,
                scratch.ResultIndices);

            if (count < 0 || count > args.Length)
                return false;

            if (count == 0)
                return true;

            files = new string[count];
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= args.Length)
                {
                    files = Array.Empty<string>();
                    return false;
                }

                files[i] = args[sourceIndex];
            }

            return true;
        }
        catch
        {
            files = Array.Empty<string>();
            return false;
        }
    }

    internal static bool TryGetExportCSharpInputOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_buildOperandScratch ??= new BuildOperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            var index = bindings.CliExportCSharpFirstOperandIndex(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            operand = args[index];
            return true;
        }
        catch
        {
            operand = null;
            return false;
        }
    }

    internal static bool TryFindDuplicateBatchRequestIds(
        IReadOnlyList<BatchQueryRequest> requests,
        out string[] duplicateIds)
    {
        duplicateIds = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var requestCount = requests.Count;
        if (requestCount == 0)
            return true;

        var scratch = t_batchDuplicateIdScratch ??= new BatchDuplicateIdScratch();
        scratch.EnsureCapacity(requestCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < requestCount; i++)
            {
                var id = requests[i].Id;
                if (!string.IsNullOrWhiteSpace(id))
                {
                    scratch.AddId(id);
                }
            }

            if (scratch.UniqueIdCount == 0)
                return true;

            scratch.BuildSortedRanks();
            for (var i = 0; i < requestCount; i++)
            {
                var id = requests[i].Id;
                scratch.IdRanks[i] = string.IsNullOrWhiteSpace(id)
                    ? 0
                    : scratch.GetIdRank(id);
            }

            var duplicateCount = bindings.CliBatchDuplicateIdRanks(
                scratch.IdRanks,
                scratch.UniqueIdCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (duplicateCount < 0 ||
                duplicateCount > scratch.UniqueIdCount ||
                duplicateCount > scratch.ResultRanks.Length)
            {
                return false;
            }

            if (duplicateCount == 0)
                return true;

            duplicateIds = new string[duplicateCount];
            for (var i = 0; i < duplicateCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueIdCount)
                {
                    duplicateIds = Array.Empty<string>();
                    return false;
                }

                duplicateIds[i] = scratch.UniqueIds[rank - 1];
            }

            return true;
        }
        catch
        {
            duplicateIds = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ResetIds();
        }
    }

    internal static bool TryCountBatchResultSuccesses(ulong[] okWords, int itemCount, out int successCount)
    {
        successCount = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (itemCount < 0)
            return false;

        if (itemCount == 0)
            return true;

        if (okWords.Length == 0 || itemCount > (long)okWords.Length * 64)
            return false;

        try
        {
            var count = bindings.CliBatchResultPackedSuccessCount(okWords, itemCount);
            if (count < 0 || count > itemCount)
            {
                successCount = 0;
                return false;
            }

            successCount = count;
            return true;
        }
        catch
        {
            successCount = 0;
            return false;
        }
    }

    internal static bool TryOrderDocSymbolsForGeneration(
        IReadOnlyList<SymbolResult> symbols,
        out List<SymbolResult> orderedSymbols)
        => TryOrderDocEntriesForGeneration(symbols, includeAllKinds: false, out orderedSymbols);

    internal static bool TryOrderDocMembersForGeneration(
        IReadOnlyList<SymbolResult> members,
        out List<SymbolResult> orderedMembers)
        => TryOrderDocEntriesForGeneration(members, includeAllKinds: true, out orderedMembers);

    internal static bool TryCreateDocSlugs(string[] rawSlugs, out string[] slugs)
    {
        slugs = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var resultSlugs = new string[rawSlugs.Length];
            var count = bindings.CliDocSlugs(rawSlugs, resultSlugs);
            if (count != rawSlugs.Length)
                return false;

            slugs = resultSlugs;
            return true;
        }
        catch
        {
            slugs = Array.Empty<string>();
            return false;
        }
    }

    internal static bool TryDeduplicateTreeDependencyIndices(
        int[] kindRanks,
        int[] nameRanks,
        int uniqueKindCount,
        int uniqueNameCount,
        out int[] orderedSourceIndices)
    {
        orderedSourceIndices = Array.Empty<int>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (kindRanks.Length != nameRanks.Length)
            return false;

        var dependencyCount = kindRanks.Length;
        if (dependencyCount == 0)
            return true;

        var scratch = t_treeDependencyDeduplicateScratch ??= new TreeDependencyDeduplicateScratch();
        scratch.EnsureCapacity(dependencyCount, uniqueKindCount, uniqueNameCount);

        try
        {
            var orderedCount = bindings.CliTreeDependencyDeduplicateIndices(
                kindRanks,
                nameRanks,
                scratch.NameCounts,
                scratch.NameOffsets,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.TempIndices,
                scratch.SortedIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > dependencyCount || orderedCount > scratch.ResultIndices.Length)
                return false;

            orderedSourceIndices = new int[orderedCount];
            Array.Copy(scratch.ResultIndices, orderedSourceIndices, orderedCount);
            return true;
        }
        catch
        {
            orderedSourceIndices = Array.Empty<int>();
            return false;
        }
    }

    internal static bool TryFilterCompilerErrorsBySeverity(
        IReadOnlyList<CompilerError> errors,
        ErrorSeverity severity,
        out List<CompilerError> filteredErrors)
    {
        filteredErrors = new List<CompilerError>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var targetRank = GetCompilerErrorSeverityRank(severity);
        if (targetRank == 0)
            return false;

        var errorCount = errors.Count;
        if (errorCount == 0)
            return true;

        var scratch = t_compilerErrorSeverityFilterScratch ??= new CompilerErrorSeverityFilterScratch();
        scratch.EnsureCapacity(errorCount);

        try
        {
            for (var i = 0; i < errorCount; i++)
            {
                scratch.SeverityRanks[i] = GetCompilerErrorSeverityRank(errors[i].Severity);
            }

            var filteredCount = bindings.DiagnosticSeverityFilter(
                scratch.SeverityRanks,
                targetRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > errorCount || filteredCount > scratch.ResultIndices.Length)
            {
                filteredErrors = new List<CompilerError>();
                return false;
            }

            filteredErrors = new List<CompilerError>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= errorCount)
                {
                    filteredErrors = new List<CompilerError>();
                    return false;
                }

                filteredErrors.Add(errors[sourceIndex]);
            }

            return true;
        }
        catch
        {
            filteredErrors = new List<CompilerError>();
            return false;
        }
    }

    internal static bool TryOrderCleanArtifactDirectories(
        IReadOnlyList<string> directories,
        out string[] orderedDirectories)
    {
        orderedDirectories = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var directoryCount = directories.Count;
        if (directoryCount == 0)
            return true;

        var scratch = t_cleanArtifactDirectoryScratch ??= new CleanArtifactDirectoryScratch();
        scratch.EnsureInputCapacity(directoryCount);

        try
        {
            scratch.ResetPathRanks();
            var maxPathLength = 0;
            for (var i = 0; i < directoryCount; i++)
            {
                var directory = directories[i];
                scratch.KindRanks[i] = CleanCommand.IsArtifactDirectoryName(Path.GetFileName(directory)) ? 1 : 0;
                scratch.NodeModuleFlags[i] = CleanCommand.IsUnderNodeModulesDirectory(directory) ? 1 : 0;
                scratch.PathLengths[i] = directory.Length;
                scratch.AddPath(directory);

                if (directory.Length > maxPathLength)
                    maxPathLength = directory.Length;
            }

            scratch.EnsureScratchCapacity(scratch.UniquePathCount, maxPathLength);
            for (var i = 0; i < directoryCount; i++)
            {
                scratch.PathRanks[i] = scratch.GetPathRank(directories[i]);
            }

            var orderedCount = bindings.CliCleanArtifactDirectoryIndices(
                scratch.KindRanks,
                scratch.NodeModuleFlags,
                scratch.PathRanks,
                scratch.PathLengths,
                scratch.SeenPathRanks,
                scratch.LengthCounts,
                scratch.LengthOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > directoryCount || orderedCount > scratch.ResultIndices.Length)
                return false;

            orderedDirectories = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= directoryCount)
                {
                    orderedDirectories = Array.Empty<string>();
                    return false;
                }

                orderedDirectories[i] = directories[sourceIndex];
            }

            return true;
        }
        catch
        {
            orderedDirectories = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ResetPathRanks();
        }
    }

    internal static bool TryFilterUpdateTargetNuGetDependencies(
        IReadOnlyList<Reference> dependencies,
        string targetPackage,
        out List<Reference> filteredDependencies)
    {
        filteredDependencies = new List<Reference>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var dependencyCount = dependencies.Count;
        if (dependencyCount == 0)
            return true;

        var scratch = t_updateDependencyFilterScratch ??= new UpdateDependencyFilterScratch();
        scratch.EnsureCapacity(dependencyCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < dependencyCount; i++)
            {
                var packageName = dependencies[i].Nuget;
                if (packageName != null)
                    scratch.AddName(packageName);
            }

            if (!scratch.TryGetNameRank(targetPackage, out var targetNameRank))
            {
                filteredDependencies = new List<Reference>();
                return true;
            }

            for (var i = 0; i < dependencyCount; i++)
            {
                var packageName = dependencies[i].Nuget;
                scratch.NameRanks[i] = packageName == null
                    ? 0
                    : scratch.GetNameRank(packageName);
            }

            var filteredCount = bindings.CliUpdateTargetNuGetDependencyIndices(
                scratch.NameRanks,
                targetNameRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > dependencyCount || filteredCount > scratch.ResultIndices.Length)
                return false;

            filteredDependencies = new List<Reference>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= dependencyCount)
                {
                    filteredDependencies = new List<Reference>();
                    return false;
                }

                filteredDependencies.Add(dependencies[sourceIndex]);
            }

            return true;
        }
        catch
        {
            filteredDependencies = new List<Reference>();
            return false;
        }
        finally
        {
            scratch.ResetNames();
        }
    }

    internal static bool TryFilterUpdateNuGetDependencies(
        IReadOnlyList<Reference> dependencies,
        out List<Reference> filteredDependencies)
    {
        filteredDependencies = new List<Reference>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var dependencyCount = dependencies.Count;
        if (dependencyCount == 0)
            return true;

        var scratch = t_updateDependencyFilterScratch ??= new UpdateDependencyFilterScratch();
        scratch.EnsureCapacity(dependencyCount);

        try
        {
            for (var i = 0; i < dependencyCount; i++)
                scratch.NuGetFlags[i] = dependencies[i].Nuget == null ? 0 : 1;

            var filteredCount = bindings.CliUpdateAllNuGetDependencyIndices(
                scratch.NuGetFlags,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > dependencyCount || filteredCount > scratch.ResultIndices.Length)
                return false;

            filteredDependencies = new List<Reference>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= dependencyCount)
                {
                    filteredDependencies = new List<Reference>();
                    return false;
                }

                var dependency = dependencies[sourceIndex];
                if (dependency.Nuget == null)
                {
                    filteredDependencies = new List<Reference>();
                    return false;
                }

                filteredDependencies.Add(dependency);
            }

            return true;
        }
        catch
        {
            filteredDependencies = new List<Reference>();
            return false;
        }
    }

    internal static bool TryFilterReferencesByType(
        IReadOnlyList<Reference> dependencies,
        ReferenceType targetType,
        out List<Reference> filteredDependencies)
    {
        filteredDependencies = new List<Reference>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var dependencyCount = dependencies.Count;
        if (dependencyCount == 0)
            return true;

        var targetTypeRank = GetReferenceTypeRank(targetType);
        if (targetTypeRank <= 0)
            return false;

        var scratch = t_referenceTypeFilterScratch ??= new ReferenceTypeFilterScratch();
        scratch.EnsureCapacity(dependencyCount);

        try
        {
            for (var i = 0; i < dependencyCount; i++)
                scratch.TypeRanks[i] = GetReferenceTypeRank(dependencies[i].Type);

            var filteredCount = bindings.CliReferenceTypeFilterIndices(
                scratch.TypeRanks,
                targetTypeRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > dependencyCount || filteredCount > scratch.ResultIndices.Length)
                return false;

            filteredDependencies = new List<Reference>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= dependencyCount)
                {
                    filteredDependencies = new List<Reference>();
                    return false;
                }

                var dependency = dependencies[sourceIndex];
                if (dependency.Type != targetType)
                {
                    filteredDependencies = new List<Reference>();
                    return false;
                }

                filteredDependencies.Add(dependency);
            }

            return true;
        }
        catch
        {
            filteredDependencies = new List<Reference>();
            return false;
        }
    }

    internal static bool TryDeduplicateExportReferences<T>(
        IReadOnlyList<T> values,
        IEqualityComparer<T>? comparer,
        out List<T> deduplicatedValues)
        where T : notnull
        => TryDeduplicateStable(values, comparer, out deduplicatedValues);

    internal static bool TryDeduplicateStable<T>(
        IReadOnlyList<T> values,
        IEqualityComparer<T>? comparer,
        out List<T> deduplicatedValues)
        where T : notnull
    {
        deduplicatedValues = new List<T>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_stableDistinctScratch ??= new StableDistinctScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
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
            var resultCount = bindings.CliStableDistinctRankIndices(
                scratch.Ranks,
                uniqueRankCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (resultCount < 0 || resultCount > valueCount || resultCount > scratch.ResultIndices.Length)
            {
                deduplicatedValues = new List<T>();
                return false;
            }

            var result = new List<T>(resultCount);
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= valueCount)
                {
                    deduplicatedValues = new List<T>();
                    return false;
                }

                result.Add(values[sourceIndex]);
            }

            deduplicatedValues = result;
            return true;
        }
        catch
        {
            deduplicatedValues = new List<T>();
            return false;
        }
    }

    internal static bool TryFilterFixesBySafety(
        IReadOnlyList<CodeAction> fixes,
        bool includeReviewNeeded,
        out List<CodeAction> safeActions)
    {
        safeActions = new List<CodeAction>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var fixCount = fixes.Count;
        if (fixCount == 0)
            return true;

        var scratch = t_fixSafetyFilterScratch ??= new FixSafetyFilterScratch();
        scratch.EnsureCapacity(fixCount);

        try
        {
            for (var i = 0; i < fixCount; i++)
            {
                scratch.SafetyRanks[i] = GetFixSafetyRank(fixes[i].Safety);
            }

            var safeCount = bindings.CliFixSafetyFilter(
                scratch.SafetyRanks,
                includeReviewNeeded ? 1 : 0,
                scratch.ResultIndices);

            if (safeCount < 0 || safeCount > fixCount || safeCount > scratch.ResultIndices.Length)
            {
                safeActions = new List<CodeAction>();
                return false;
            }

            safeActions = new List<CodeAction>(safeCount);
            for (var i = 0; i < safeCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= fixCount)
                {
                    safeActions = new List<CodeAction>();
                    return false;
                }

                safeActions.Add(fixes[sourceIndex]);
            }

            return true;
        }
        catch
        {
            safeActions = new List<CodeAction>();
            return false;
        }
    }

    internal static bool TrySelectSkippedFixEntries(
        IReadOnlyList<FixEntry> results,
        bool includeReviewNeeded,
        out List<FixEntry> skipped)
    {
        skipped = new List<FixEntry>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultCount = results.Count;
        if (resultCount == 0)
            return true;

        var scratch = t_fixSafetyFilterScratch ??= new FixSafetyFilterScratch();
        scratch.EnsureCapacity(resultCount);

        try
        {
            for (var i = 0; i < resultCount; i++)
            {
                scratch.SafetyRanks[i] = GetFixEntrySafetyRank(results[i].Safety);
            }

            var skippedCount = bindings.CliFixSkippedIndices(
                scratch.SafetyRanks,
                includeReviewNeeded ? 1 : 0,
                scratch.ResultIndices);

            if (skippedCount < 0 || skippedCount > resultCount || skippedCount > scratch.ResultIndices.Length)
            {
                skipped = new List<FixEntry>();
                return false;
            }

            skipped = new List<FixEntry>(skippedCount);
            for (var i = 0; i < skippedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= resultCount)
                {
                    skipped = new List<FixEntry>();
                    return false;
                }

                skipped.Add(results[sourceIndex]);
            }

            return true;
        }
        catch
        {
            skipped = new List<FixEntry>();
            return false;
        }
    }

    internal static bool TryGroupAppliedFixEntriesByFile(
        IReadOnlyList<FixEntry> applied,
        out FixAppliedFileGrouping grouping)
    {
        grouping = FixAppliedFileGrouping.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var appliedCount = applied.Count;
        if (appliedCount == 0)
            return true;

        var scratch = t_fixAppliedFileGroupingScratch ??= new FixAppliedFileGroupingScratch();
        scratch.EnsureCapacity(appliedCount);

        try
        {
            scratch.Reset();
            for (var i = 0; i < appliedCount; i++)
            {
                var fileRank = scratch.GetOrAddFileRank(applied[i].File);
                scratch.FileRanks[i] = fileRank;
            }

            var groupCount = bindings.CliFixAppliedFileGroups(
                scratch.FileRanks,
                scratch.UniqueFileRankCount,
                scratch.CountsByRank,
                scratch.OffsetsByRank,
                scratch.WriteOffsetsByRank,
                scratch.ResultRanks,
                scratch.ResultStarts,
                scratch.ResultCounts,
                scratch.ResultIndices);

            if (groupCount < 0
                || groupCount > scratch.UniqueFileRankCount
                || groupCount > appliedCount)
            {
                return false;
            }

            var files = new string[groupCount];
            var starts = new int[groupCount];
            var counts = new int[groupCount];
            var indices = new int[appliedCount];

            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var rank = scratch.ResultRanks[groupIndex];
                var start = scratch.ResultStarts[groupIndex];
                var count = scratch.ResultCounts[groupIndex];
                if (rank <= 0
                    || rank > scratch.UniqueFileRankCount
                    || start < 0
                    || count < 0
                    || start + count > appliedCount)
                {
                    return false;
                }

                files[groupIndex] = scratch.FilesByRank[rank] ?? string.Empty;
                starts[groupIndex] = start;
                counts[groupIndex] = count;
            }

            for (var i = 0; i < appliedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= appliedCount)
                {
                    return false;
                }

                indices[i] = sourceIndex;
            }

            grouping = new FixAppliedFileGrouping(files, starts, counts, indices);
            return true;
        }
        catch
        {
            grouping = FixAppliedFileGrouping.Empty;
            return false;
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static bool TryBuildUnifiedDiffHunkRanges(
        IReadOnlyList<UnifiedDiff.DiffLine> lines,
        int contextLines,
        out UnifiedDiffHunkRanges ranges)
    {
        ranges = UnifiedDiffHunkRanges.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null || contextLines < 0)
            return false;

        var lineCount = lines.Count;
        if (lineCount == 0)
            return true;

        var scratch = t_unifiedDiffHunkScratch ??= new UnifiedDiffHunkScratch();
        scratch.EnsureCapacity(lineCount);

        try
        {
            for (var i = 0; i < lineCount; i++)
            {
                var line = lines[i];
                scratch.KindIds[i] = (int)line.Kind;
                scratch.OldLines[i] = line.OldLine;
                scratch.NewLines[i] = line.NewLine;
            }

            var hunkCount = bindings.CliUnifiedDiffHunkRanges(
                scratch.KindIds,
                scratch.OldLines,
                scratch.NewLines,
                contextLines,
                scratch.Ranges.Starts,
                scratch.Ranges.Lengths,
                scratch.Ranges.OldStarts,
                scratch.Ranges.OldCounts,
                scratch.Ranges.NewStarts,
                scratch.Ranges.NewCounts);

            if (hunkCount < 0 || hunkCount > lineCount)
                return false;

            for (var hunkIndex = 0; hunkIndex < hunkCount; hunkIndex++)
            {
                var start = scratch.Ranges.Starts[hunkIndex];
                var length = scratch.Ranges.Lengths[hunkIndex];
                if (start < 0 ||
                    length <= 0 ||
                    start + length > lineCount ||
                    scratch.Ranges.OldStarts[hunkIndex] <= 0 ||
                    scratch.Ranges.NewStarts[hunkIndex] <= 0 ||
                    scratch.Ranges.OldCounts[hunkIndex] < 0 ||
                    scratch.Ranges.NewCounts[hunkIndex] < 0 ||
                    scratch.Ranges.OldCounts[hunkIndex] > length ||
                    scratch.Ranges.NewCounts[hunkIndex] > length)
                {
                    return false;
                }
            }

            scratch.Ranges.Count = hunkCount;
            ranges = scratch.Ranges;
            return true;
        }
        catch
        {
            ranges = UnifiedDiffHunkRanges.Empty;
            return false;
        }
    }

    internal static bool TrySelectTidyPossiblyUnusedDependencies<T>(
        IReadOnlyList<T> results,
        Func<T, string> statusSelector,
        out List<T> possiblyUnused)
    {
        possiblyUnused = new List<T>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultCount = results.Count;
        if (resultCount == 0)
            return true;

        var scratch = t_tidyDependencyStatusFilterScratch ??= new TidyDependencyStatusFilterScratch();
        scratch.EnsureCapacity(resultCount);

        try
        {
            for (var i = 0; i < resultCount; i++)
            {
                scratch.StatusRanks[i] = GetTidyDependencyStatusRank(statusSelector(results[i]));
            }

            var possiblyUnusedCount = bindings.DiagnosticSeverityFilter(
                scratch.StatusRanks,
                TidyPossiblyUnusedStatusRank,
                scratch.ResultIndices);

            if (possiblyUnusedCount < 0 ||
                possiblyUnusedCount > resultCount ||
                possiblyUnusedCount > scratch.ResultIndices.Length)
            {
                possiblyUnused = new List<T>();
                return false;
            }

            possiblyUnused = new List<T>(possiblyUnusedCount);
            for (var i = 0; i < possiblyUnusedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 ||
                    sourceIndex >= resultCount ||
                    scratch.StatusRanks[sourceIndex] != TidyPossiblyUnusedStatusRank)
                {
                    possiblyUnused = new List<T>();
                    return false;
                }

                possiblyUnused.Add(results[sourceIndex]);
            }

            return true;
        }
        catch
        {
            possiblyUnused = new List<T>();
            return false;
        }
    }

    internal static bool TrySummarizeTidyDependencyStatuses<T>(
        IReadOnlyList<T> results,
        Func<T, string> statusSelector,
        out (int PossiblyUnusedCount, int UnknownCount) summary)
    {
        summary = (0, 0);

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultCount = results.Count;
        if (resultCount == 0)
            return true;

        var scratch = t_tidyDependencyStatusFilterScratch ??= new TidyDependencyStatusFilterScratch();
        scratch.EnsureCapacity(resultCount);

        try
        {
            for (var i = 0; i < resultCount; i++)
            {
                scratch.StatusRanks[i] = GetTidyDependencyStatusRank(statusSelector(results[i]));
            }

            var summarizedCount = bindings.CliTidyDependencyStatusSummary(
                scratch.StatusRanks,
                scratch.SummaryCounts);

            if (summarizedCount != resultCount ||
                scratch.SummaryCounts[0] < 0 ||
                scratch.SummaryCounts[1] < 0 ||
                scratch.SummaryCounts[0] > resultCount ||
                scratch.SummaryCounts[1] > resultCount ||
                scratch.SummaryCounts[0] + scratch.SummaryCounts[1] > resultCount)
            {
                summary = (0, 0);
                return false;
            }

            summary = (scratch.SummaryCounts[0], scratch.SummaryCounts[1]);
            return true;
        }
        catch
        {
            summary = (0, 0);
            return false;
        }
    }

    internal static bool TrySummarizeTestOutcomeRanks(
        int[] outcomeRanks,
        int outcomeCount,
        out (bool Ok, int Passed, int Failed, int Skipped) summary)
    {
        summary = (true, 0, 0, 0);

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (outcomeCount < 0 || outcomeCount > outcomeRanks.Length)
            return false;

        if (outcomeCount == 0)
            return true;

        var scratch = t_testOutcomeSummaryScratch ??= new TestOutcomeSummaryScratch();
        scratch.EnsureCapacity();

        try
        {
            var summarizedCount = bindings.CliTestOutcomeSummary(
                outcomeRanks,
                outcomeCount,
                scratch.SummaryCounts);

            var passed = scratch.SummaryCounts[0];
            var failed = scratch.SummaryCounts[1];
            var skipped = scratch.SummaryCounts[2];
            var nonOk = scratch.SummaryCounts[3];
            if (summarizedCount != outcomeCount ||
                passed < 0 ||
                failed < 0 ||
                skipped < 0 ||
                nonOk < 0 ||
                passed > outcomeCount ||
                failed > outcomeCount ||
                skipped > outcomeCount ||
                nonOk > outcomeCount ||
                passed + failed + skipped > outcomeCount ||
                nonOk < failed)
            {
                summary = (true, 0, 0, 0);
                return false;
            }

            summary = (nonOk == 0, passed, failed, skipped);
            return true;
        }
        catch
        {
            summary = (true, 0, 0, 0);
            return false;
        }
    }

    internal static bool TryClassifyTidyDependencyStatusRanks(
        IReadOnlyList<Reference> dependencies,
        IReadOnlyCollection<string> importedNamespaces,
        out int[] statusRanks)
    {
        statusRanks = Array.Empty<int>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var dependencyCount = dependencies.Count;
        if (dependencyCount == 0)
            return true;

        var scratch = t_tidyDependencyStatusFilterScratch ??= new TidyDependencyStatusFilterScratch();
        scratch.EnsureClassificationCapacity(dependencyCount, importedNamespaces.Count);

        try
        {
            for (var i = 0; i < dependencyCount; i++)
            {
                var packageName = dependencies[i].Nuget;
                if (packageName == null || !IsAscii(packageName))
                    return false;

                scratch.PackageNames[i] = packageName;
            }

            var importIndex = 0;
            foreach (var importedNamespace in importedNamespaces)
            {
                if (!IsAscii(importedNamespace))
                    return false;

                scratch.ImportNamespaces[importIndex] = importedNamespace;
                importIndex++;
            }

            var classifiedCount = bindings.CliTidyDependencyStatusRanks(
                scratch.PackageNames,
                scratch.ImportNamespaces,
                scratch.StatusRanks);

            if (classifiedCount != dependencyCount)
            {
                return false;
            }

            statusRanks = new int[dependencyCount];
            for (var i = 0; i < dependencyCount; i++)
            {
                var rank = scratch.StatusRanks[i];
                if (rank is < 1 or > 3)
                {
                    statusRanks = Array.Empty<int>();
                    return false;
                }

                statusRanks[i] = rank;
            }

            return true;
        }
        catch
        {
            statusRanks = Array.Empty<int>();
            return false;
        }
        finally
        {
            scratch.ClearClassificationInputs(dependencyCount, importedNamespaces.Count);
        }
    }

    internal static bool TryFilterTidyRemovalLines(
        IReadOnlyList<string> lines,
        IReadOnlyList<string> packageNames,
        out string[] filteredLines)
    {
        filteredLines = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var lineCount = lines.Count;
        if (lineCount == 0)
            return true;

        var packageCount = packageNames.Count;
        var scratch = t_tidyRemovalLineScratch ??= new TidyRemovalLineScratch();
        scratch.EnsureCapacity(lineCount, packageCount);

        try
        {
            for (var i = 0; i < lineCount; i++)
            {
                var line = lines[i];
                if (line == null || !IsAscii(line))
                    return false;

                scratch.Lines[i] = line;
            }

            for (var i = 0; i < packageCount; i++)
            {
                var packageName = packageNames[i];
                if (packageName == null || !IsAscii(packageName))
                    return false;

                scratch.PackageNames[i] = packageName;
            }

            var processedCount = bindings.CliTidyRemovalLineKeepFlags(
                scratch.Lines,
                scratch.PackageNames,
                scratch.KeepFlags);

            if (processedCount != lineCount)
                return false;

            var keptCount = 0;
            for (var i = 0; i < lineCount; i++)
            {
                var flag = scratch.KeepFlags[i];
                if (flag is not 0 and not 1)
                    return false;

                keptCount += flag;
            }

            var result = new string[keptCount];
            var resultIndex = 0;
            for (var i = 0; i < lineCount; i++)
            {
                if (scratch.KeepFlags[i] == 0)
                    continue;

                result[resultIndex] = scratch.Lines[i];
                resultIndex++;
            }

            filteredLines = result;
            return true;
        }
        catch
        {
            filteredLines = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearInputs(lineCount, packageCount);
        }
    }

    private static bool TryOrderDocEntriesForGeneration(
        IReadOnlyList<SymbolResult> symbols,
        bool includeAllKinds,
        out List<SymbolResult> orderedSymbols)
    {
        orderedSymbols = new List<SymbolResult>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var symbolCount = symbols.Count;
        if (symbolCount == 0)
            return true;

        var scratch = t_docSymbolOrderScratch ??= new DocSymbolOrderScratch();
        scratch.EnsureCapacity(symbolCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < symbolCount; i++)
            {
                scratch.AddName(symbols[i].Name);
            }

            scratch.BuildSortedNameRanks();
            for (var i = 0; i < symbolCount; i++)
            {
                var symbol = symbols[i];
                scratch.KindRanks[i] = GetDocSymbolKindRank(symbol.Kind);
                scratch.NameRanks[i] = scratch.GetNameRank(symbol.Name);
                scratch.IncludeFlags[i] = (includeAllKinds || IsDocumentedSymbolKind(symbol.Kind)) ? 1 : 0;
            }

            var orderedCount = bindings.CliDocSymbolOrderCountingIndices(
                scratch.KindRanks,
                scratch.NameRanks,
                scratch.IncludeFlags,
                scratch.NameCounts,
                scratch.NameOffsets,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > symbolCount || orderedCount > scratch.ResultIndices.Length)
                return false;

            orderedSymbols = new List<SymbolResult>(orderedCount);
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= symbolCount)
                {
                    orderedSymbols = new List<SymbolResult>();
                    return false;
                }

                orderedSymbols.Add(symbols[sourceIndex]);
            }

            return true;
        }
        catch
        {
            orderedSymbols = new List<SymbolResult>();
            return false;
        }
        finally
        {
            scratch.ResetNames();
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
                CreateDelegate<CliBuildFirstOperandIndexInto>(programType, "CliBuildFirstOperandIndexInto"),
                CreateDelegate<CliExportCSharpFirstOperandIndexInto>(programType, "CliExportCSharpFirstOperandIndexInto"),
                CreateDelegate<CliRunFirstOperandIndex>(programType, "CliRunFirstOperandIndex"),
                CreateDelegate<CliPublishOptionsInto>(programType, "CliPublishOptionsInto"),
                CreateDelegate<CliFirstPositionalArgIndex>(programType, "CliFirstPositionalArgIndex"),
                CreateDelegate<CliLintFileArgIndicesInto>(programType, "CliLintFileArgIndicesInto"),
                CreateDelegate<CliBatchDuplicateIdRanksInto>(programType, "CliBatchDuplicateIdRanksInto"),
                CreateDelegate<CliBatchResultPackedSuccessCount>(programType, "CliBatchResultPackedSuccessCount"),
                CreateDelegate<CliDocSymbolOrderCountingIndicesInto>(programType, "CliDocSymbolOrderCountingIndicesInto"),
                CreateDelegate<CliDocSlugsInto>(programType, "CliDocSlugsInto"),
                CreateDelegate<CliTreeDependencyDeduplicateIndicesInto>(programType, "CliTreeDependencyDeduplicateIndicesInto"),
                CreateDelegate<DiagnosticSeverityFilterIndicesInto>(programType, "DiagnosticSeverityFilterIndicesInto"),
                CreateDelegate<CliFixSafetyFilterIndicesInto>(programType, "CliFixSafetyFilterIndicesInto"),
                CreateDelegate<CliFixSkippedIndicesInto>(programType, "CliFixSkippedIndicesInto"),
                CreateDelegate<CliFixAppliedFileGroupsInto>(programType, "CliFixAppliedFileGroupsInto"),
                CreateDelegate<CliUnifiedDiffHunkRangesInto>(programType, "CliUnifiedDiffHunkRangesInto"),
                CreateDelegate<CliCleanArtifactDirectoryIndicesInto>(programType, "CliCleanArtifactDirectoryIndicesInto"),
                CreateDelegate<CliUpdateAllNuGetDependencyIndicesInto>(programType, "CliUpdateAllNuGetDependencyIndicesInto"),
                CreateDelegate<CliUpdateTargetNuGetDependencyIndicesInto>(programType, "CliUpdateTargetNuGetDependencyIndicesInto"),
                CreateDelegate<CliReferenceTypeFilterIndicesInto>(programType, "CliReferenceTypeFilterIndicesInto"),
                CreateDelegate<CliTidyDependencyStatusSummaryInto>(programType, "CliTidyDependencyStatusSummaryInto"),
                CreateDelegate<CliTestOutcomeSummaryInto>(programType, "CliTestOutcomeSummaryInto"),
                CreateDelegate<CliTidyDependencyStatusRanksInto>(programType, "CliTidyDependencyStatusRanksInto"),
                CreateDelegate<CliTidyRemovalLineKeepFlagsInto>(programType, "CliTidyRemovalLineKeepFlagsInto"),
                CreateDelegate<CliStableDistinctRankIndicesInto>(programType, "CliStableDistinctRankIndicesInto"));
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

    private delegate int CliBuildFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private delegate int CliExportCSharpFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private delegate int CliRunFirstOperandIndex(string[] args);

    private delegate int CliPublishOptionsInto(string[] args, int[] resultIndices);

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliLintFileArgIndicesInto(
        string[] args,
        int[] projectValueIndices,
        int[] resultIndices);

    private delegate int CliBatchDuplicateIdRanksInto(
        int[] idRanks,
        int uniqueIdCount,
        int[] countsByRank,
        int[] resultRanks);

    private delegate int CliBatchResultPackedSuccessCount(
        ulong[] okWords,
        int itemCount);

    private delegate int CliDocSymbolOrderCountingIndicesInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] includeFlags,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private delegate int CliDocSlugsInto(string[] rawSlugs, string[] resultSlugs);

    private delegate int CliTreeDependencyDeduplicateIndicesInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] sortedIndices,
        int[] resultIndices);

    private delegate int DiagnosticSeverityFilterIndicesInto(
        int[] severityRanks,
        int targetRank,
        int[] resultIndices);

    private delegate int CliFixSafetyFilterIndicesInto(
        int[] safetyRanks,
        int includeReviewNeeded,
        int[] resultIndices);

    private delegate int CliFixSkippedIndicesInto(
        int[] safetyRanks,
        int includeReviewNeeded,
        int[] resultIndices);

    private delegate int CliFixAppliedFileGroupsInto(
        int[] fileRanks,
        int uniqueFileRankCount,
        int[] countsByRank,
        int[] offsetsByRank,
        int[] writeOffsetsByRank,
        int[] resultRanks,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultIndices);

    private delegate int CliUnifiedDiffHunkRangesInto(
        int[] kindIds,
        int[] oldLines,
        int[] newLines,
        int contextLines,
        int[] resultStarts,
        int[] resultLengths,
        int[] resultOldStarts,
        int[] resultOldCounts,
        int[] resultNewStarts,
        int[] resultNewCounts);

    private delegate int CliCleanArtifactDirectoryIndicesInto(
        int[] kindRanks,
        int[] nodeModuleFlags,
        int[] pathRanks,
        int[] pathLengths,
        int[] seenPathRanks,
        int[] lengthCounts,
        int[] lengthOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private delegate int CliUpdateAllNuGetDependencyIndicesInto(
        int[] nugetFlags,
        int[] resultIndices);

    private delegate int CliUpdateTargetNuGetDependencyIndicesInto(
        int[] nameRanks,
        int targetNameRank,
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

    private delegate int CliTidyDependencyStatusSummaryInto(
        int[] statusRanks,
        int[] resultCounts);

    private delegate int CliTestOutcomeSummaryInto(
        int[] outcomeRanks,
        int count,
        int[] resultCounts);

    private delegate int CliTidyDependencyStatusRanksInto(
        string[] packageNames,
        string[] importNamespaces,
        int[] resultStatusRanks);

    private delegate int CliTidyRemovalLineKeepFlagsInto(
        string[] lines,
        string[] packageNames,
        int[] resultFlags);

    private sealed record Bindings(
        CliBuildFirstOperandIndexInto CliBuildFirstOperandIndex,
        CliExportCSharpFirstOperandIndexInto CliExportCSharpFirstOperandIndex,
        CliRunFirstOperandIndex CliRunFirstOperandIndex,
        CliPublishOptionsInto CliPublishOptionsInto,
        CliFirstPositionalArgIndex CliFirstPositionalArgIndex,
        CliLintFileArgIndicesInto CliLintFileArgIndices,
        CliBatchDuplicateIdRanksInto CliBatchDuplicateIdRanks,
        CliBatchResultPackedSuccessCount CliBatchResultPackedSuccessCount,
        CliDocSymbolOrderCountingIndicesInto CliDocSymbolOrderCountingIndices,
        CliDocSlugsInto CliDocSlugs,
        CliTreeDependencyDeduplicateIndicesInto CliTreeDependencyDeduplicateIndices,
        DiagnosticSeverityFilterIndicesInto DiagnosticSeverityFilter,
        CliFixSafetyFilterIndicesInto CliFixSafetyFilter,
        CliFixSkippedIndicesInto CliFixSkippedIndices,
        CliFixAppliedFileGroupsInto CliFixAppliedFileGroups,
        CliUnifiedDiffHunkRangesInto CliUnifiedDiffHunkRanges,
        CliCleanArtifactDirectoryIndicesInto CliCleanArtifactDirectoryIndices,
        CliUpdateAllNuGetDependencyIndicesInto CliUpdateAllNuGetDependencyIndices,
        CliUpdateTargetNuGetDependencyIndicesInto CliUpdateTargetNuGetDependencyIndices,
        CliReferenceTypeFilterIndicesInto CliReferenceTypeFilterIndices,
        CliTidyDependencyStatusSummaryInto CliTidyDependencyStatusSummary,
        CliTestOutcomeSummaryInto CliTestOutcomeSummary,
        CliTidyDependencyStatusRanksInto CliTidyDependencyStatusRanks,
        CliTidyRemovalLineKeepFlagsInto CliTidyRemovalLineKeepFlags,
        CliStableDistinctRankIndicesInto CliStableDistinctRankIndices);

    private static bool IsDocumentedSymbolKind(SymbolKind kind) =>
        kind is not SymbolKind.Variable and not SymbolKind.Parameter;

    private static int GetDocSymbolKindRank(SymbolKind kind) =>
        kind switch
        {
            SymbolKind.Class => 1,
            SymbolKind.Constructor => 2,
            SymbolKind.Enum => 3,
            SymbolKind.EnumMember => 4,
            SymbolKind.Field => 5,
            SymbolKind.Function => 6,
            SymbolKind.Interface => 7,
            SymbolKind.Method => 8,
            SymbolKind.Parameter => 9,
            SymbolKind.Property => 10,
            SymbolKind.Record => 11,
            SymbolKind.Struct => 12,
            SymbolKind.Test => 13,
            SymbolKind.TypeAlias => 14,
            SymbolKind.Union => 15,
            SymbolKind.Variable => 16,
            _ => 100
        };

    private static bool IsAscii(string value)
    {
        for (var i = 0; i < value.Length; i++)
        {
            if (value[i] > 0x7f)
                return false;
        }

        return true;
    }

    private static int GetReferenceTypeRank(ReferenceType type) =>
        type switch
        {
            ReferenceType.NuGet => 1,
            ReferenceType.Dll => 2,
            ReferenceType.Project => 3,
            ReferenceType.Framework => 4,
            _ => 0
        };

    private static int GetCompilerErrorSeverityRank(ErrorSeverity severity) =>
        severity switch
        {
            ErrorSeverity.Error => 1,
            ErrorSeverity.Warning => 2,
            _ => 0
        };

    private static int GetFixSafetyRank(FixSafety safety) =>
        safety switch
        {
            FixSafety.Safe => 1,
            FixSafety.ReviewNeeded => 2,
            FixSafety.SuggestionOnly => 3,
            _ => 0
        };

    private static int GetFixEntrySafetyRank(string safety) =>
        safety switch
        {
            "safe" => 1,
            "reviewNeeded" => 2,
            "suggestionOnly" => 3,
            _ => 0
        };

    private const int TidyPossiblyUnusedStatusRank = 1;

    private static int GetTidyDependencyStatusRank(string status) =>
        status switch
        {
            "possibly-unused" => TidyPossiblyUnusedStatusRank,
            "used" => 2,
            "unknown" => 3,
            _ => 0
        };

    private sealed class BuildOperandScratch
    {
        internal int[] KindIds = Array.Empty<int>();
        internal int[] NextIndices = Array.Empty<int>();
        internal int[] NextOptionIndices = Array.Empty<int>();
        internal int[] PreviousIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
            {
                KindIds = new int[count];
                NextIndices = new int[count];
                NextOptionIndices = new int[count];
                PreviousIndices = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class LintFileArgScratch
    {
        internal int[] ProjectValueIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ProjectValueIndices.Length != count || ResultIndices.Length != count)
            {
                ProjectValueIndices = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class BatchDuplicateIdScratch
    {
        private readonly Dictionary<string, int> _idRanks = new(StringComparer.Ordinal);

        internal int[] CountsByRank = Array.Empty<int>();
        internal int[] IdRanks = Array.Empty<int>();
        internal int[] ResultRanks = Array.Empty<int>();
        internal string[] UniqueIds = Array.Empty<string>();
        internal int UniqueIdCount;

        internal void EnsureCapacity(int requestCount)
        {
            if (IdRanks.Length != requestCount)
            {
                IdRanks = new int[requestCount];
                ResultRanks = new int[requestCount];
                UniqueIds = new string[requestCount];
            }

            var rankCapacity = requestCount + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        internal void AddId(string id)
        {
            if (_idRanks.ContainsKey(id))
                return;

            _idRanks.Add(id, 0);
            UniqueIds[UniqueIdCount] = id;
            UniqueIdCount++;
        }

        internal void BuildSortedRanks()
        {
            Array.Sort(UniqueIds, 0, UniqueIdCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueIdCount; i++)
            {
                _idRanks[UniqueIds[i]] = i + 1;
            }
        }

        internal int GetIdRank(string id) => _idRanks[id];

        internal void ResetIds()
        {
            _idRanks.Clear();
            if (UniqueIdCount > 0)
            {
                Array.Clear(UniqueIds, 0, UniqueIdCount);
                UniqueIdCount = 0;
            }
        }
    }

    private sealed class DocSymbolOrderScratch
    {
        private readonly Dictionary<string, int> _nameRanks = new(StringComparer.Ordinal);

        internal int[] IncludeFlags = Array.Empty<int>();
        internal int[] KindCounts = Array.Empty<int>();
        internal int[] KindOffsets = Array.Empty<int>();
        internal int[] KindRanks = Array.Empty<int>();
        internal int[] NameCounts = Array.Empty<int>();
        internal int[] NameOffsets = Array.Empty<int>();
        internal int[] NameRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();
        internal string[] UniqueNames = Array.Empty<string>();
        internal int UniqueNameCount;

        internal void EnsureCapacity(int symbolCount)
        {
            if (KindRanks.Length != symbolCount)
            {
                KindRanks = new int[symbolCount];
                NameRanks = new int[symbolCount];
                IncludeFlags = new int[symbolCount];
                TempIndices = new int[symbolCount];
                ResultIndices = new int[symbolCount];
                UniqueNames = new string[symbolCount];
            }

            var nameRankCapacity = symbolCount + 1;
            if (NameCounts.Length != nameRankCapacity)
            {
                NameCounts = new int[nameRankCapacity];
                NameOffsets = new int[nameRankCapacity];
            }

            if (KindCounts.Length != 32)
            {
                KindCounts = new int[32];
                KindOffsets = new int[32];
            }
        }

        internal void AddName(string name)
        {
            if (_nameRanks.ContainsKey(name))
                return;

            _nameRanks.Add(name, 0);
            UniqueNames[UniqueNameCount] = name;
            UniqueNameCount++;
        }

        internal void BuildSortedNameRanks()
        {
            Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueNameCount; i++)
            {
                _nameRanks[UniqueNames[i]] = i + 1;
            }
        }

        internal int GetNameRank(string name) => _nameRanks[name];

        internal void ResetNames()
        {
            _nameRanks.Clear();
            if (UniqueNameCount > 0)
            {
                Array.Clear(UniqueNames, 0, UniqueNameCount);
                UniqueNameCount = 0;
            }
        }
    }

    internal sealed class FixAppliedFileGrouping
    {
        internal static readonly FixAppliedFileGrouping Empty = new(
            Array.Empty<string>(),
            Array.Empty<int>(),
            Array.Empty<int>(),
            Array.Empty<int>());

        internal FixAppliedFileGrouping(string[] files, int[] starts, int[] counts, int[] indices)
        {
            Files = files;
            Starts = starts;
            Counts = counts;
            Indices = indices;
        }

        internal string[] Files { get; }
        internal int GroupCount => Files.Length;
        internal int[] Starts { get; }
        internal int[] Counts { get; }
        internal int[] Indices { get; }
    }

    internal sealed class UnifiedDiffHunkRanges
    {
        internal static readonly UnifiedDiffHunkRanges Empty = new();

        internal int Count { get; set; }
        internal int[] Starts { get; set; } = Array.Empty<int>();
        internal int[] Lengths { get; set; } = Array.Empty<int>();
        internal int[] OldStarts { get; set; } = Array.Empty<int>();
        internal int[] OldCounts { get; set; } = Array.Empty<int>();
        internal int[] NewStarts { get; set; } = Array.Empty<int>();
        internal int[] NewCounts { get; set; } = Array.Empty<int>();
    }

    private sealed class FixAppliedFileGroupingScratch
    {
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);

        internal int[] CountsByRank = Array.Empty<int>();
        internal int[] FileRanks = Array.Empty<int>();
        internal string?[] FilesByRank = Array.Empty<string?>();
        internal int[] OffsetsByRank = Array.Empty<int>();
        internal int[] ResultCounts = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] ResultRanks = Array.Empty<int>();
        internal int[] ResultStarts = Array.Empty<int>();
        internal int UniqueFileRankCount;
        internal int[] WriteOffsetsByRank = Array.Empty<int>();

        internal void EnsureCapacity(int appliedCount)
        {
            if (FileRanks.Length != appliedCount)
            {
                FileRanks = new int[appliedCount];
                ResultCounts = new int[appliedCount];
                ResultIndices = new int[appliedCount];
                ResultRanks = new int[appliedCount];
                ResultStarts = new int[appliedCount];
            }

            var rankCapacity = appliedCount + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
                FilesByRank = new string?[rankCapacity];
                OffsetsByRank = new int[rankCapacity];
                WriteOffsetsByRank = new int[rankCapacity];
            }
        }

        internal int GetOrAddFileRank(string file)
        {
            if (_fileRanks.TryGetValue(file, out var rank))
                return rank;

            rank = UniqueFileRankCount + 1;
            _fileRanks.Add(file, rank);
            FilesByRank[rank] = file;
            UniqueFileRankCount = rank;
            return rank;
        }

        internal void Reset()
        {
            _fileRanks.Clear();
            if (UniqueFileRankCount > 0)
            {
                Array.Clear(FilesByRank, 0, UniqueFileRankCount + 1);
                UniqueFileRankCount = 0;
            }
        }
    }

    private sealed class UnifiedDiffHunkScratch
    {
        internal int[] KindIds = Array.Empty<int>();
        internal int[] NewLines = Array.Empty<int>();
        internal int[] OldLines = Array.Empty<int>();
        internal UnifiedDiffHunkRanges Ranges { get; } = new();

        internal void EnsureCapacity(int lineCount)
        {
            if (KindIds.Length == lineCount)
            {
                Ranges.Count = 0;
                return;
            }

            KindIds = new int[lineCount];
            OldLines = new int[lineCount];
            NewLines = new int[lineCount];
            Ranges.Starts = new int[lineCount];
            Ranges.Lengths = new int[lineCount];
            Ranges.OldStarts = new int[lineCount];
            Ranges.OldCounts = new int[lineCount];
            Ranges.NewStarts = new int[lineCount];
            Ranges.NewCounts = new int[lineCount];
            Ranges.Count = 0;
        }
    }

    private sealed class TreeDependencyDeduplicateScratch
    {
        internal int[] KindCounts = Array.Empty<int>();
        internal int[] KindOffsets = Array.Empty<int>();
        internal int[] NameCounts = Array.Empty<int>();
        internal int[] NameOffsets = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SortedIndices = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();

        internal void EnsureCapacity(int dependencyCount, int uniqueKindCount, int uniqueNameCount)
        {
            if (TempIndices.Length != dependencyCount)
            {
                TempIndices = new int[dependencyCount];
                SortedIndices = new int[dependencyCount];
                ResultIndices = new int[dependencyCount];
            }

            var kindBucketCapacity = uniqueKindCount + 1;
            if (KindCounts.Length != kindBucketCapacity)
            {
                KindCounts = new int[kindBucketCapacity];
                KindOffsets = new int[kindBucketCapacity];
            }

            var nameBucketCapacity = uniqueNameCount + 1;
            if (NameCounts.Length != nameBucketCapacity)
            {
                NameCounts = new int[nameBucketCapacity];
                NameOffsets = new int[nameBucketCapacity];
            }
        }
    }

    private sealed class CompilerErrorSeverityFilterScratch
    {
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeverityRanks = Array.Empty<int>();

        internal void EnsureCapacity(int errorCount)
        {
            if (SeverityRanks.Length != errorCount)
            {
                SeverityRanks = new int[errorCount];
                ResultIndices = new int[errorCount];
            }
        }
    }

    private sealed class FixSafetyFilterScratch
    {
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SafetyRanks = Array.Empty<int>();

        internal void EnsureCapacity(int fixCount)
        {
            if (SafetyRanks.Length != fixCount)
            {
                SafetyRanks = new int[fixCount];
                ResultIndices = new int[fixCount];
            }
        }
    }

    private sealed class CleanArtifactDirectoryScratch
    {
        private readonly Dictionary<string, int> _pathRanks = new(StringComparer.Ordinal);

        internal int[] KindRanks = Array.Empty<int>();
        internal int[] LengthCounts = Array.Empty<int>();
        internal int[] LengthOffsets = Array.Empty<int>();
        internal int[] NodeModuleFlags = Array.Empty<int>();
        internal int[] PathLengths = Array.Empty<int>();
        internal int[] PathRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenPathRanks = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();
        internal int UniquePathCount;

        internal void EnsureInputCapacity(int directoryCount)
        {
            if (KindRanks.Length != directoryCount)
            {
                KindRanks = new int[directoryCount];
                NodeModuleFlags = new int[directoryCount];
                PathRanks = new int[directoryCount];
                PathLengths = new int[directoryCount];
                TempIndices = new int[directoryCount];
                ResultIndices = new int[directoryCount];
            }
        }

        internal void EnsureScratchCapacity(int uniquePathCount, int maxPathLength)
        {
            var pathRankCapacity = uniquePathCount + 1;
            if (SeenPathRanks.Length != pathRankCapacity)
            {
                SeenPathRanks = new int[pathRankCapacity];
            }

            var lengthCapacity = maxPathLength + 1;
            if (LengthCounts.Length != lengthCapacity)
            {
                LengthCounts = new int[lengthCapacity];
                LengthOffsets = new int[lengthCapacity];
            }
        }

        internal void AddPath(string path)
        {
            if (_pathRanks.ContainsKey(path))
                return;

            UniquePathCount++;
            _pathRanks.Add(path, UniquePathCount);
        }

        internal int GetPathRank(string path) => _pathRanks[path];

        internal void ResetPathRanks()
        {
            _pathRanks.Clear();
            UniquePathCount = 0;
        }
    }

    private sealed class UpdateDependencyFilterScratch
    {
        private readonly Dictionary<string, int> _nameRanks = new(StringComparer.OrdinalIgnoreCase);

        internal int[] NuGetFlags = Array.Empty<int>();
        internal int[] NameRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int UniqueNameCount;

        internal void EnsureCapacity(int dependencyCount)
        {
            if (NuGetFlags.Length != dependencyCount
                || NameRanks.Length != dependencyCount
                || ResultIndices.Length != dependencyCount)
            {
                NuGetFlags = new int[dependencyCount];
                NameRanks = new int[dependencyCount];
                ResultIndices = new int[dependencyCount];
            }
        }

        internal void AddName(string name)
        {
            if (_nameRanks.ContainsKey(name))
                return;

            UniqueNameCount++;
            _nameRanks.Add(name, UniqueNameCount);
        }

        internal int GetNameRank(string name) => _nameRanks[name];

        internal bool TryGetNameRank(string name, out int rank) => _nameRanks.TryGetValue(name, out rank);

        internal void ResetNames()
        {
            _nameRanks.Clear();
            UniqueNameCount = 0;
        }
    }

    private sealed class ReferenceTypeFilterScratch
    {
        internal int[] TypeRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int dependencyCount)
        {
            if (TypeRanks.Length != dependencyCount || ResultIndices.Length != dependencyCount)
            {
                TypeRanks = new int[dependencyCount];
                ResultIndices = new int[dependencyCount];
            }
        }
    }

    private sealed class StableDistinctScratch
    {
        internal int[] Ranks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (Ranks.Length != count || ResultIndices.Length != count)
            {
                Ranks = new int[count];
                ResultIndices = new int[count];
            }
        }

        internal void EnsureRankCapacity(int uniqueRankCount)
        {
            var rankCapacity = uniqueRankCount + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }
    }

    private sealed class TidyDependencyStatusFilterScratch
    {
        internal string[] ImportNamespaces = Array.Empty<string>();
        internal string[] PackageNames = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] StatusRanks = Array.Empty<int>();
        internal int[] SummaryCounts = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (StatusRanks.Length != count)
            {
                StatusRanks = new int[count];
                ResultIndices = new int[count];
            }

            if (SummaryCounts.Length != 2)
            {
                SummaryCounts = new int[2];
            }
        }

        internal void EnsureClassificationCapacity(int dependencyCount, int importCount)
        {
            if (PackageNames.Length != dependencyCount)
                PackageNames = new string[dependencyCount];

            if (StatusRanks.Length != dependencyCount)
                StatusRanks = new int[dependencyCount];

            if (ImportNamespaces.Length != importCount)
                ImportNamespaces = new string[importCount];
        }

        internal void ClearClassificationInputs(int dependencyCount, int importCount)
        {
            if (dependencyCount > 0 && dependencyCount <= PackageNames.Length)
                Array.Clear(PackageNames, 0, dependencyCount);

            if (importCount > 0 && importCount <= ImportNamespaces.Length)
                Array.Clear(ImportNamespaces, 0, importCount);
        }
    }

    private sealed class TidyRemovalLineScratch
    {
        internal int[] KeepFlags = Array.Empty<int>();
        internal string[] Lines = Array.Empty<string>();
        internal string[] PackageNames = Array.Empty<string>();

        internal void EnsureCapacity(int lineCount, int packageCount)
        {
            if (Lines.Length != lineCount)
            {
                Lines = new string[lineCount];
                KeepFlags = new int[lineCount];
            }

            if (PackageNames.Length != packageCount)
                PackageNames = new string[packageCount];
        }

        internal void ClearInputs(int lineCount, int packageCount)
        {
            if (lineCount > 0 && lineCount <= Lines.Length)
                Array.Clear(Lines, 0, lineCount);

            if (packageCount > 0 && packageCount <= PackageNames.Length)
                Array.Clear(PackageNames, 0, packageCount);
        }
    }

    private sealed class TestOutcomeSummaryScratch
    {
        internal int[] SummaryCounts = Array.Empty<int>();

        internal void EnsureCapacity()
        {
            if (SummaryCounts.Length != 4)
            {
                SummaryCounts = new int[4];
            }
        }
    }
}
