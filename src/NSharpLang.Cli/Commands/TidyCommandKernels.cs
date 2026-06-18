using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal static class TidyCommandKernels
{    private const int PossiblyUnusedStatusRank = 1;

    [ThreadStatic]
    private static DependencyStatusScratch? t_dependencyStatusScratch;
    [ThreadStatic]
    private static RemovalLineScratch? t_removalLineScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TrySelectPossiblyUnusedDependencies<T>(
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

        var scratch = t_dependencyStatusScratch ??= new DependencyStatusScratch();
        scratch.EnsureCapacity(resultCount);

        try
        {
            for (var i = 0; i < resultCount; i++)
            {
                scratch.StatusRanks[i] = GetStatusRank(statusSelector(results[i]));
            }

            var possiblyUnusedCount = bindings.StatusFilter(
                scratch.StatusRanks,
                PossiblyUnusedStatusRank,
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
                    scratch.StatusRanks[sourceIndex] != PossiblyUnusedStatusRank)
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

    internal static bool TrySummarizeDependencyStatuses<T>(
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

        var scratch = t_dependencyStatusScratch ??= new DependencyStatusScratch();
        scratch.EnsureCapacity(resultCount);

        try
        {
            for (var i = 0; i < resultCount; i++)
            {
                scratch.StatusRanks[i] = GetStatusRank(statusSelector(results[i]));
            }

            var summarizedCount = bindings.StatusSummary(
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

    internal static bool TryClassifyDependencyStatusRanks(
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

        var scratch = t_dependencyStatusScratch ??= new DependencyStatusScratch();
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

            var classifiedCount = bindings.DependencyStatusRanks(
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

    internal static bool TryFilterRemovalLines(
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
        var scratch = t_removalLineScratch ??= new RemovalLineScratch();
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

            var processedCount = bindings.RemovalLineKeepFlags(
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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<DiagnosticSeverityFilterIndicesInto>(
                programType,
                "DiagnosticSeverityFilterIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliTidyDependencyStatusSummaryInto>(
                programType,
                "CliTidyDependencyStatusSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTidyDependencyStatusRanksInto>(
                programType,
                "CliTidyDependencyStatusRanksInto"),
            DogfoodKernelLoader.CreateDelegate<CliTidyRemovalLineKeepFlagsInto>(
                programType,
                "CliTidyRemovalLineKeepFlagsInto")));

    private static int GetStatusRank(string status) =>
        status switch
        {
            "possibly-unused" => PossiblyUnusedStatusRank,
            "used" => 2,
            "unknown" => 3,
            _ => 0
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

    private delegate int DiagnosticSeverityFilterIndicesInto(
        int[] severityRanks,
        int targetRank,
        int[] resultIndices);

    private delegate int CliTidyDependencyStatusSummaryInto(
        int[] statusRanks,
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
        DiagnosticSeverityFilterIndicesInto StatusFilter,
        CliTidyDependencyStatusSummaryInto StatusSummary,
        CliTidyDependencyStatusRanksInto DependencyStatusRanks,
        CliTidyRemovalLineKeepFlagsInto RemovalLineKeepFlags);

    private sealed class DependencyStatusScratch
    {
        internal string[] ImportNamespaces = Array.Empty<string>();
        internal string[] PackageNames = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] StatusRanks = Array.Empty<int>();
        internal int[] SummaryCounts = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (StatusRanks.Length != count)
                StatusRanks = new int[count];

            if (ResultIndices.Length != count)
                ResultIndices = new int[count];

            if (SummaryCounts.Length != 2)
                SummaryCounts = new int[2];
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

    private sealed class RemovalLineScratch
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
}
