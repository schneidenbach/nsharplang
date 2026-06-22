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

internal enum TidyOutputModeKind
{
    Json = 1,
    Text = 2
}

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

    internal static bool TryGetOptionSummary(string[] args, out TidyOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[4];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption))
            {
                summary = default;
                return false;
            }

            summary = new TidyOptionSummary(
                projectOption,
                resultIndices[1] != 0,
                resultIndices[2] != 0,
                resultIndices[3] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out TidyOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.OutputMode(json ? 1 : 0);
            if (code is < 1 or > 2)
                return false;

            outputMode = (TidyOutputModeKind)code;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

    internal static bool TryGetImportedNamespace(string line, out string? importedNamespace)
    {
        importedNamespace = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var span = t_importNamespaceSpan ??= new int[3];
        try
        {
            var code = bindings.ImportNamespaceSpan(line, span);
            if (code != 0)
                return false;

            var hasImport = span[0];
            if (hasImport == 0)
                return true;

            if (hasImport != 1)
                return false;

            var start = span[1];
            var length = span[2];
            if (start < 0 || length <= 0 || start + length > line.Length)
                return false;

            importedNamespace = line.Substring(start, length);
            return true;
        }
        catch
        {
            importedNamespace = null;
            return false;
        }
    }

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

    internal static string GetHelpText()
        => TryGetMessage(bindings => bindings.HelpText(), out var message)
            ? message
            : FallbackHelpText();

    internal static string GetMissingProjectFileJsonMessage()
        => TryGetMessage(bindings => bindings.MissingProjectFileJsonMessage(), out var message)
            ? message
            : FallbackMissingProjectFileJsonMessage();

    internal static string GetMissingProjectFileTextMessage()
        => TryGetMessage(bindings => bindings.MissingProjectFileTextMessage(), out var message)
            ? message
            : FallbackMissingProjectFileTextMessage();

    internal static string GetParseFailedMessage(string message)
        => TryGetMessage(bindings => bindings.ParseFailedMessage(message), out var result)
            ? result
            : FallbackParseFailedMessage(message);

    internal static string GetNothingToRemoveMessage()
        => TryGetMessage(bindings => bindings.NothingToRemoveMessage(), out var message)
            ? message
            : FallbackNothingToRemoveMessage();

    internal static string GetRemovedDependenciesMessage(int count)
    {
        var countText = count.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.RemovedDependenciesMessage(countText, count), out var message)
            ? message
            : FallbackRemovedDependenciesMessage(countText, count);
    }

    internal static string GetNoNuGetDependenciesMessage(string projectRoot)
        => TryGetMessage(bindings => bindings.NoNuGetDependenciesMessage(projectRoot), out var message)
            ? message
            : FallbackNoNuGetDependenciesMessage(projectRoot);

    internal static string GetTableHeader(string packageLabel, string statusLabel)
        => TryGetMessage(bindings => bindings.TableHeader(packageLabel, statusLabel), out var message)
            ? message
            : FallbackTableHeader(packageLabel, statusLabel);

    internal static string GetTableSeparator(string packageSeparator, string statusSeparator)
        => TryGetMessage(bindings => bindings.TableSeparator(packageSeparator, statusSeparator), out var message)
            ? message
            : FallbackTableSeparator(packageSeparator, statusSeparator);

    internal static string GetTableRow(string packageLabel, string statusLabel, string reason)
        => TryGetMessage(bindings => bindings.TableRow(packageLabel, statusLabel, reason), out var message)
            ? message
            : FallbackTableRow(packageLabel, statusLabel, reason);

    internal static string GetPossiblyUnusedFoundMessage(int count)
    {
        var countText = count.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.PossiblyUnusedFoundMessage(countText, count), out var message)
            ? message
            : FallbackPossiblyUnusedFoundMessage(countText, count);
    }

    internal static string GetAllDependenciesAccountedForMessage(int unknownCount)
    {
        var unknownCountText = unknownCount.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.AllDependenciesAccountedForMessage(unknownCountText), out var message)
            ? message
            : FallbackAllDependenciesAccountedForMessage(unknownCountText);
    }

    internal static string GetAllDependenciesInUseMessage()
        => TryGetMessage(bindings => bindings.AllDependenciesInUseMessage(), out var message)
            ? message
            : FallbackAllDependenciesInUseMessage();

    internal static string GetUnknownReasonMessage()
        => TryGetMessage(bindings => bindings.UnknownReasonMessage(), out var message)
            ? message
            : FallbackUnknownReasonMessage();

    internal static string GetUsedReasonMessage(string namespacePrefix)
        => TryGetMessage(bindings => bindings.UsedReasonMessage(namespacePrefix), out var message)
            ? message
            : FallbackUsedReasonMessage(namespacePrefix);

    internal static string GetPossiblyUnusedReasonMessage(string prefix1, string prefix2)
        => TryGetMessage(bindings => bindings.PossiblyUnusedReasonMessage(prefix1, prefix2), out var message)
            ? message
            : FallbackPossiblyUnusedReasonMessage(prefix1, prefix2);

    private static bool TryGetMessage(Func<Bindings, string> getMessage, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = getMessage(bindings);
            return !string.IsNullOrEmpty(message);
        }
        catch
        {
            message = string.Empty;
            return false;
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product tidy messages and table rendering route through CliTidy* kernels.
    private static string FallbackHelpText()
        => "N# Tidy\n"
           + "\n"
           + "Usage: nlc tidy [options]\n"
           + "\n"
           + "Identify and optionally remove unused NuGet dependencies from project.yml.\n"
           + "\n"
           + "Each dependency is classified as:\n"
           + "  used            — an import statement plausibly references the package namespace\n"
           + "  possibly-unused — no import statement references the package namespace\n"
           + "  unknown         — cannot determine usage (e.g. single-segment package names)\n"
           + "\n"
           + "The command is conservative: 'unknown' is reported rather than incorrectly\n"
           + "flagging a dependency as unused.\n"
           + "\n"
           + "Options:\n"
           + "  --project <dir>   Project directory (default: current directory)\n"
           + "  --fix             Remove all possibly-unused dependencies from project.yml\n"
           + "  --json            Emit structured JSON output\n"
           + "  --help, -h        Show this help text\n"
           + "\n"
           + "JSON schema (schemaVersion 1):\n"
           + "  { schemaVersion, command, ok, projectRoot,\n"
           + "    dependencies: [{ name, version, status, reason }] }\n"
           + "\n"
           + "Examples:\n"
           + "  nlc tidy                   Report unused dependencies\n"
           + "  nlc tidy --fix             Remove possibly-unused dependencies\n"
           + "  nlc tidy --json            Machine-readable output\n"
           + "  nlc tidy --project ./lib   Analyse a different project\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  All dependencies in use (or tidy succeeded)\n"
           + "  1  Error (missing project.yml, parse failure)";

    private static string FallbackMissingProjectFileJsonMessage()
        => "No project.yml found in the specified directory.";

    private static string FallbackMissingProjectFileTextMessage()
        => "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project.";

    private static string FallbackParseFailedMessage(string message)
        => $"Failed to parse project.yml: {message}";

    private static string FallbackNothingToRemoveMessage()
        => "Nothing to remove.";

    private static string FallbackRemovedDependenciesMessage(string countText, int count)
        => $"Removed {countText} possibly-unused {(count == 1 ? "dependency" : "dependencies")}.";

    private static string FallbackNoNuGetDependenciesMessage(string projectRoot)
        => $"No NuGet dependencies found in {projectRoot}";

    private static string FallbackTableHeader(string packageLabel, string statusLabel)
        => $"  {packageLabel}  {statusLabel}  Reason";

    private static string FallbackTableSeparator(string packageSeparator, string statusSeparator)
        => $"  {packageSeparator}  {statusSeparator}  ------";

    private static string FallbackTableRow(string packageLabel, string statusLabel, string reason)
        => $"  {packageLabel}  {statusLabel}  {reason}";

    private static string FallbackPossiblyUnusedFoundMessage(string countText, int count)
        => $"{countText} possibly-unused {(count == 1 ? "dependency" : "dependencies")} found. Run 'nlc tidy --fix' to remove them.";

    private static string FallbackAllDependenciesAccountedForMessage(string unknownCountText)
        => $"All dependencies accounted for ({unknownCountText} could not be determined).";

    private static string FallbackAllDependenciesInUseMessage()
        => "All dependencies appear to be in use.";

    private static string FallbackUnknownReasonMessage()
        => "Cannot determine namespace for single-segment package name; manual review required.";

    private static string FallbackUsedReasonMessage(string namespacePrefix)
        => $"Import statement references namespace matching '{namespacePrefix}'.";

    private static string FallbackPossiblyUnusedReasonMessage(string prefix1, string prefix2)
        => $"No import statement found referencing '{prefix1}' or '{prefix2}'.";

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
