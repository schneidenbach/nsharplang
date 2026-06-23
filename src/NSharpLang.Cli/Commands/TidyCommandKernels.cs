using System;
using System.Collections.Generic;
using System.Globalization;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal readonly record struct TidyOptionSummary(
    string? ProjectOption,
    bool Fix,
    bool Json,
    bool ShowHelp);

internal static class TidyCommandKernels
{
    private const int PossiblyUnusedStatusRank = 1;

    [ThreadStatic]
    private static DependencyStatusScratch? t_dependencyStatusScratch;
    [ThreadStatic]
    private static RemovalLineScratch? t_removalLineScratch;
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;
    [ThreadStatic]
    private static int[]? t_importNamespaceSpan;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static TidyOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[4];
        var code = RequiredBindings.OptionSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# tidy option summary kernel rejected the arguments.");

        var projectOption = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        return new TidyOptionSummary(
            projectOption,
            resultIndices[1] != 0,
            resultIndices[2] != 0,
            resultIndices[3] != 0);
    }

    internal static int GetOutputMode(bool json)
        => RequiredBindings.OutputMode(json ? 1 : 0);

    internal static string? GetImportedNamespace(string line)
    {
        var span = t_importNamespaceSpan ??= new int[3];
        var code = RequiredBindings.ImportNamespaceSpan(line, span);
        if (code != 0)
            throw new InvalidOperationException("N# tidy import namespace kernel rejected the line.");

        var hasImport = span[0];
        if (hasImport == 0)
            return null;

        if (hasImport != 1)
            throw new InvalidOperationException("N# tidy import namespace kernel returned an invalid presence flag.");

        var start = span[1];
        var length = span[2];
        if (start < 0 || length <= 0 || start + length > line.Length)
            throw new InvalidOperationException("N# tidy import namespace kernel returned an invalid span.");

        return line.Substring(start, length);
    }

    internal static List<T> SelectPossiblyUnusedDependencies<T>(
        IReadOnlyList<T> results,
        Func<T, string> statusSelector)
    {
        var resultCount = results.Count;
        var scratch = t_dependencyStatusScratch ??= new DependencyStatusScratch();
        scratch.EnsureCapacity(resultCount);

        for (var i = 0; i < resultCount; i++)
        {
            scratch.StatusRanks[i] = GetStatusRank(statusSelector(results[i]));
        }

        var possiblyUnusedCount = RequiredBindings.StatusFilter(
            scratch.StatusRanks,
            PossiblyUnusedStatusRank,
            scratch.ResultIndices);

        if (possiblyUnusedCount < 0 ||
            possiblyUnusedCount > resultCount ||
            possiblyUnusedCount > scratch.ResultIndices.Length)
        {
            throw new InvalidOperationException("N# tidy dependency status filter kernel rejected the results.");
        }

        var possiblyUnused = new List<T>(possiblyUnusedCount);
        for (var i = 0; i < possiblyUnusedCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 ||
                sourceIndex >= resultCount ||
                scratch.StatusRanks[sourceIndex] != PossiblyUnusedStatusRank)
            {
                throw new InvalidOperationException("N# tidy dependency status filter kernel returned an invalid source index.");
            }

            possiblyUnused.Add(results[sourceIndex]);
        }

        return possiblyUnused;
    }

    internal static (int PossiblyUnusedCount, int UnknownCount) SummarizeDependencyStatuses<T>(
        IReadOnlyList<T> results,
        Func<T, string> statusSelector)
    {
        var resultCount = results.Count;
        var scratch = t_dependencyStatusScratch ??= new DependencyStatusScratch();
        scratch.EnsureCapacity(resultCount);

        for (var i = 0; i < resultCount; i++)
        {
            scratch.StatusRanks[i] = GetStatusRank(statusSelector(results[i]));
        }

        var summarizedCount = RequiredBindings.StatusSummary(
            scratch.StatusRanks,
            scratch.SummaryCounts);

        if (summarizedCount != resultCount ||
            scratch.SummaryCounts[0] < 0 ||
            scratch.SummaryCounts[1] < 0 ||
            scratch.SummaryCounts[0] > resultCount ||
            scratch.SummaryCounts[1] > resultCount ||
            scratch.SummaryCounts[0] + scratch.SummaryCounts[1] > resultCount)
        {
            throw new InvalidOperationException("N# tidy dependency status summary kernel rejected the results.");
        }

        return (scratch.SummaryCounts[0], scratch.SummaryCounts[1]);
    }

    internal static int[] ClassifyDependencyStatusRanks(
        IReadOnlyList<Reference> dependencies,
        IReadOnlyCollection<string> importedNamespaces)
    {
        var dependencyCount = dependencies.Count;
        var scratch = t_dependencyStatusScratch ??= new DependencyStatusScratch();
        scratch.EnsureClassificationCapacity(dependencyCount, importedNamespaces.Count);

        try
        {
            for (var i = 0; i < dependencyCount; i++)
            {
                var packageName = dependencies[i].Nuget;
                if (packageName == null)
                    throw new InvalidOperationException("N# tidy dependency classifier kernel received a non-NuGet dependency.");

                scratch.PackageNames[i] = packageName;
            }

            var importIndex = 0;
            foreach (var importedNamespace in importedNamespaces)
            {
                scratch.ImportNamespaces[importIndex] = importedNamespace;
                importIndex++;
            }

            var classifiedCount = RequiredBindings.DependencyStatusRanks(
                scratch.PackageNames,
                scratch.ImportNamespaces,
                scratch.StatusRanks);

            if (classifiedCount != dependencyCount)
                throw new InvalidOperationException("N# tidy dependency classifier kernel rejected the inputs.");

            var statusRanks = new int[dependencyCount];
            for (var i = 0; i < dependencyCount; i++)
            {
                var rank = scratch.StatusRanks[i];
                if (rank is < 1 or > 3)
                    throw new InvalidOperationException("N# tidy dependency classifier kernel produced an invalid status rank.");

                statusRanks[i] = rank;
            }

            return statusRanks;
        }
        finally
        {
            scratch.ClearClassificationInputs(dependencyCount, importedNamespaces.Count);
        }
    }

    internal static string[] FilterRemovalLines(
        IReadOnlyList<string> lines,
        IReadOnlyList<string> packageNames)
    {
        var lineCount = lines.Count;
        if (lineCount == 0)
            return Array.Empty<string>();

        var packageCount = packageNames.Count;
        var scratch = t_removalLineScratch ??= new RemovalLineScratch();
        scratch.EnsureCapacity(lineCount, packageCount);

        try
        {
            for (var i = 0; i < lineCount; i++)
            {
                var line = lines[i];
                if (line == null)
                    throw new InvalidOperationException("N# tidy dependency removal kernel received a null line.");

                scratch.Lines[i] = line;
            }

            for (var i = 0; i < packageCount; i++)
            {
                var packageName = packageNames[i];
                if (packageName == null)
                    throw new InvalidOperationException("N# tidy dependency removal kernel received a null package name.");

                scratch.PackageNames[i] = packageName;
            }

            var processedCount = RequiredBindings.RemovalLineKeepFlags(
                scratch.Lines,
                scratch.PackageNames,
                scratch.KeepFlags);

            if (processedCount != lineCount)
                throw new InvalidOperationException("N# tidy dependency removal kernel rejected the inputs.");

            var keptCount = 0;
            for (var i = 0; i < lineCount; i++)
            {
                var flag = scratch.KeepFlags[i];
                if (flag is not 0 and not 1)
                    throw new InvalidOperationException("N# tidy dependency removal kernel returned an invalid keep flag.");

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

            return result;
        }
        finally
        {
            scratch.ClearInputs(lineCount, packageCount);
        }
    }

    internal static string GetHelpText()
        => GetMessage(bindings => bindings.HelpText());

    internal static string GetMissingProjectFileJsonMessage()
        => GetMessage(bindings => bindings.MissingProjectFileJsonMessage());

    internal static string GetMissingProjectFileTextMessage()
        => GetMessage(bindings => bindings.MissingProjectFileTextMessage());

    internal static string GetParseFailedMessage(string message)
        => GetMessage(bindings => bindings.ParseFailedMessage(message));

    internal static string GetNothingToRemoveMessage()
        => GetMessage(bindings => bindings.NothingToRemoveMessage());

    internal static string GetRemovedDependenciesMessage(int count)
    {
        var countText = count.ToString(CultureInfo.InvariantCulture);
        return GetMessage(bindings => bindings.RemovedDependenciesMessage(countText, count));
    }

    internal static string GetNoNuGetDependenciesMessage(string projectRoot)
        => GetMessage(bindings => bindings.NoNuGetDependenciesMessage(projectRoot));

    internal static string GetTableHeader(string packageLabel, string statusLabel)
        => GetMessage(bindings => bindings.TableHeader(packageLabel, statusLabel));

    internal static string GetTableSeparator(string packageSeparator, string statusSeparator)
        => GetMessage(bindings => bindings.TableSeparator(packageSeparator, statusSeparator));

    internal static string GetTableRow(string packageLabel, string statusLabel, string reason)
        => GetMessage(bindings => bindings.TableRow(packageLabel, statusLabel, reason));

    internal static string GetPossiblyUnusedFoundMessage(int count)
    {
        var countText = count.ToString(CultureInfo.InvariantCulture);
        return GetMessage(bindings => bindings.PossiblyUnusedFoundMessage(countText, count));
    }

    internal static string GetAllDependenciesAccountedForMessage(int unknownCount)
    {
        var unknownCountText = unknownCount.ToString(CultureInfo.InvariantCulture);
        return GetMessage(bindings => bindings.AllDependenciesAccountedForMessage(unknownCountText));
    }

    internal static string GetAllDependenciesInUseMessage()
        => GetMessage(bindings => bindings.AllDependenciesInUseMessage());

    internal static string GetUnknownReasonMessage()
        => GetMessage(bindings => bindings.UnknownReasonMessage());

    internal static string GetUsedReasonMessage(string namespacePrefix)
        => GetMessage(bindings => bindings.UsedReasonMessage(namespacePrefix));

    internal static string GetPossiblyUnusedReasonMessage(string prefix1, string prefix2)
        => GetMessage(bindings => bindings.PossiblyUnusedReasonMessage(prefix1, prefix2));

    private static string GetMessage(Func<Bindings, string> getMessage)
    {
        var bindings = RequiredBindings;
        var message = getMessage(bindings);
        return !string.IsNullOrEmpty(message)
            ? message
            : throw new InvalidOperationException("N# tidy message kernel returned empty output.");
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
                "CliTidyRemovalLineKeepFlagsInto"),
            DogfoodKernelLoader.CreateDelegate<CliTidyOptionSummaryInto>(
                programType,
                "CliTidyOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTidyOutputMode>(
                programType,
                "CliTidyOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliTidyImportNamespaceSpanInto>(
                programType,
                "CliTidyImportNamespaceSpanInto"),
            DogfoodKernelLoader.CreateDelegate<CliTidyHelpText>(
                programType,
                "CliTidyHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliTidyMissingProjectFileJsonMessage>(
                programType,
                "CliTidyMissingProjectFileJsonMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyMissingProjectFileTextMessage>(
                programType,
                "CliTidyMissingProjectFileTextMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyParseFailedMessage>(
                programType,
                "CliTidyParseFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyNothingToRemoveMessage>(
                programType,
                "CliTidyNothingToRemoveMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyRemovedDependenciesMessage>(
                programType,
                "CliTidyRemovedDependenciesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyNoNuGetDependenciesMessage>(
                programType,
                "CliTidyNoNuGetDependenciesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyTableHeader>(
                programType,
                "CliTidyTableHeader"),
            DogfoodKernelLoader.CreateDelegate<CliTidyTableSeparator>(
                programType,
                "CliTidyTableSeparator"),
            DogfoodKernelLoader.CreateDelegate<CliTidyTableRow>(
                programType,
                "CliTidyTableRow"),
            DogfoodKernelLoader.CreateDelegate<CliTidyPossiblyUnusedFoundMessage>(
                programType,
                "CliTidyPossiblyUnusedFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyAllDependenciesAccountedForMessage>(
                programType,
                "CliTidyAllDependenciesAccountedForMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyAllDependenciesInUseMessage>(
                programType,
                "CliTidyAllDependenciesInUseMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyUnknownReasonMessage>(
                programType,
                "CliTidyUnknownReasonMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyUsedReasonMessage>(
                programType,
                "CliTidyUsedReasonMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTidyPossiblyUnusedReasonMessage>(
                programType,
                "CliTidyPossiblyUnusedReasonMessage")));

    private static int GetStatusRank(string status) =>
        status switch
        {
            "possibly-unused" => PossiblyUnusedStatusRank,
            "used" => 2,
            "unknown" => 3,
            _ => 0
        };

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

    private delegate int CliTidyOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliTidyOutputMode(int json);

    private delegate int CliTidyImportNamespaceSpanInto(
        string line,
        int[] resultSpan);

    private delegate string CliTidyHelpText();

    private delegate string CliTidyMissingProjectFileJsonMessage();

    private delegate string CliTidyMissingProjectFileTextMessage();

    private delegate string CliTidyParseFailedMessage(string message);

    private delegate string CliTidyNothingToRemoveMessage();

    private delegate string CliTidyRemovedDependenciesMessage(string countText, int count);

    private delegate string CliTidyNoNuGetDependenciesMessage(string projectRoot);

    private delegate string CliTidyTableHeader(string packageLabel, string statusLabel);

    private delegate string CliTidyTableSeparator(string packageSeparator, string statusSeparator);

    private delegate string CliTidyTableRow(string packageLabel, string statusLabel, string reason);

    private delegate string CliTidyPossiblyUnusedFoundMessage(string countText, int count);

    private delegate string CliTidyAllDependenciesAccountedForMessage(string unknownCountText);

    private delegate string CliTidyAllDependenciesInUseMessage();

    private delegate string CliTidyUnknownReasonMessage();

    private delegate string CliTidyUsedReasonMessage(string namespacePrefix);

    private delegate string CliTidyPossiblyUnusedReasonMessage(string prefix1, string prefix2);

    private sealed record Bindings(
        DiagnosticSeverityFilterIndicesInto StatusFilter,
        CliTidyDependencyStatusSummaryInto StatusSummary,
        CliTidyDependencyStatusRanksInto DependencyStatusRanks,
        CliTidyRemovalLineKeepFlagsInto RemovalLineKeepFlags,
        CliTidyOptionSummaryInto OptionSummary,
        CliTidyOutputMode OutputMode,
        CliTidyImportNamespaceSpanInto ImportNamespaceSpan,
        CliTidyHelpText HelpText,
        CliTidyMissingProjectFileJsonMessage MissingProjectFileJsonMessage,
        CliTidyMissingProjectFileTextMessage MissingProjectFileTextMessage,
        CliTidyParseFailedMessage ParseFailedMessage,
        CliTidyNothingToRemoveMessage NothingToRemoveMessage,
        CliTidyRemovedDependenciesMessage RemovedDependenciesMessage,
        CliTidyNoNuGetDependenciesMessage NoNuGetDependenciesMessage,
        CliTidyTableHeader TableHeader,
        CliTidyTableSeparator TableSeparator,
        CliTidyTableRow TableRow,
        CliTidyPossiblyUnusedFoundMessage PossiblyUnusedFoundMessage,
        CliTidyAllDependenciesAccountedForMessage AllDependenciesAccountedForMessage,
        CliTidyAllDependenciesInUseMessage AllDependenciesInUseMessage,
        CliTidyUnknownReasonMessage UnknownReasonMessage,
        CliTidyUsedReasonMessage UsedReasonMessage,
        CliTidyPossiblyUnusedReasonMessage PossiblyUnusedReasonMessage);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# tidy command kernels are unavailable.");

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
