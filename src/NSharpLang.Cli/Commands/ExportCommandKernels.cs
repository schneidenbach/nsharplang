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

    internal static bool TryGetTargetSummary(string[] args, out ExportTargetSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_targetSummaryIndices ??= new int[2];
        try
        {
            var code = bindings.TargetSummary(args, resultIndices);
            if (code != 0)
                return false;

            var targetKindValue = resultIndices[0];
            if (targetKindValue is not 0 and not 1)
                return false;

            summary = new ExportTargetSummary(
                (ExportTargetKind)targetKindValue,
                resultIndices[1] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetCSharpOptionSummary(string[] args, out ExportCSharpOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[3];
        try
        {
            var code = bindings.CSharpOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var outputOption))
            {
                summary = default;
                return false;
            }

            summary = new ExportCSharpOptionSummary(
                projectOption,
                outputOption,
                resultIndices[2] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetCSharpInputOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_operandScratch ??= new OperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            var index = bindings.CSharpFirstOperandIndex(
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

            var filteredCount = bindings.ReferenceTypeFilterIndices(
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

    internal static bool TryDeduplicateReferences<T>(
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
            var resultCount = bindings.StableDistinctRankIndices(
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

    internal static bool TryIsTestSourceFile(string sourceFile, out bool isTestSource)
    {
        isTestSource = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.IsTestSourceFile(sourceFile);
            if (result is not 0 and not 1)
                return false;

            isTestSource = result != 0;
            return true;
        }
        catch
        {
            isTestSource = false;
            return false;
        }
    }

    internal static string GetHelpText()
        => TryGetMessage(bindings => bindings.HelpText(), out var message)
            ? message
            : FallbackHelpText();

    internal static string GetCSharpHelpText()
        => TryGetMessage(bindings => bindings.CSharpHelpText(), out var message)
            ? message
            : FallbackCSharpHelpText();

    internal static string GetUnknownTargetMessage(string target)
        => TryGetMessage(bindings => bindings.UnknownTargetMessage(target), out var message)
            ? message
            : FallbackUnknownTargetMessage(target);

    internal static string GetSourceAndProjectConflictMessage()
        => TryGetMessage(bindings => bindings.SourceAndProjectConflictMessage(), out var message)
            ? message
            : FallbackSourceAndProjectConflictMessage();

    internal static string GetPathNotFoundMessage(string path)
        => TryGetMessage(bindings => bindings.PathNotFoundMessage(path), out var message)
            ? message
            : FallbackPathNotFoundMessage(path);

    internal static string GetNoInputMessage()
        => TryGetMessage(bindings => bindings.NoInputMessage(), out var message)
            ? message
            : FallbackNoInputMessage();

    internal static string GetFailedMessage(string message)
        => TryGetMessage(bindings => bindings.FailedMessage(message), out var result)
            ? result
            : FallbackFailedMessage(message);

    internal static string GetExpectedNlFileMessage(string path)
        => TryGetMessage(bindings => bindings.ExpectedNlFileMessage(path), out var message)
            ? message
            : FallbackExpectedNlFileMessage(path);

    internal static string GetMissingOutputMessage(string sourceFile)
        => TryGetMessage(bindings => bindings.MissingOutputMessage(sourceFile), out var message)
            ? message
            : FallbackMissingOutputMessage(sourceFile);

    internal static string GetRefuseOverwriteMessage()
        => TryGetMessage(bindings => bindings.RefuseOverwriteMessage(), out var message)
            ? message
            : FallbackRefuseOverwriteMessage();

    internal static string GetSingleFileSuccessMessage(string fileName, string outputPath)
        => TryGetMessage(bindings => bindings.SingleFileSuccessMessage(fileName, outputPath), out var message)
            ? message
            : FallbackSingleFileSuccessMessage(fileName, outputPath);

    internal static string GetNoProjectFileMessage(string projectRoot)
        => TryGetMessage(bindings => bindings.NoProjectFileMessage(projectRoot), out var message)
            ? message
            : FallbackNoProjectFileMessage(projectRoot);

    internal static string GetProjectSuccessMessage(string projectName, string projectFilePath)
        => TryGetMessage(bindings => bindings.ProjectSuccessMessage(projectName, projectFilePath), out var message)
            ? message
            : FallbackProjectSuccessMessage(projectName, projectFilePath);

    internal static string GetTestsSuccessMessage(string testProjectFilePath)
        => TryGetMessage(bindings => bindings.TestsSuccessMessage(testProjectFilePath), out var message)
            ? message
            : FallbackTestsSuccessMessage(testProjectFilePath);

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
                "CliExportTestsSuccessMessage")));

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
        CliExportTestsSuccessMessage TestsSuccessMessage);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product export messages route through CliExport* kernels.
    private static string FallbackHelpText()
        => "N# Export\n"
           + "\n"
           + "Usage: nlc export <target> [options]\n"
           + "\n"
           + "Export N# sources into other representations without changing the build backend.\n"
           + "\n"
           + "Targets:\n"
           + "  csharp              Export a single file or an entire project bundle to C#\n"
           + "\n"
           + "Examples:\n"
           + "  nlc export csharp Program.nl\n"
           + "  nlc export csharp Program.nl -o Program.cs\n"
           + "  nlc export csharp --project .\n"
           + "  nlc export csharp examples/12-multi-file-projects/WeatherDemo -o ./weather-csharp\n"
           + "\n"
           + "Run 'nlc export <target> --help' for target-specific options.";

    private static string FallbackCSharpHelpText()
        => "N# Export C#\n"
           + "\n"
           + "Usage:\n"
           + "  nlc export csharp <file.nl> [-o output.cs]\n"
           + "  nlc export csharp <project-dir> [-o bundle-dir]\n"
           + "  nlc export csharp --project <project-dir> [-o bundle-dir]\n"
           + "\n"
           + "Exports N# sources to C# without using generated C# as a build backend.\n"
           + "\n"
           + "Single-file mode:\n"
           + "  Writes the exported C# to stdout by default, or to the file passed with -o/--output.\n"
           + "\n"
           + "Project mode:\n"
           + "  Writes a self-contained C# bundle containing:\n"
           + "  - the exported main project\n"
           + "  - a sibling test project when .tests.nl files exist\n"
           + "  - exported N# project references under _nsharp_refs\n"
           + "\n"
           + "Options:\n"
           + "  --project <dir>    Export a project from a specific directory\n"
           + "  --output <path>    Output .cs file or bundle directory (-o shorthand)\n"
           + "  --help, -h         Show this help text\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Export succeeded\n"
           + "  1  Export failed";

    private static string FallbackUnknownTargetMessage(string target)
        => $"Unknown export target '{target}'. Expected 'csharp'.";

    private static string FallbackSourceAndProjectConflictMessage()
        => "Specify either a source path or --project, not both.";

    private static string FallbackPathNotFoundMessage(string path)
        => $"Path not found: {path}";

    private static string FallbackNoInputMessage()
        => "No input provided. Pass a .nl file or project directory, or run from a directory containing project.yml.";

    private static string FallbackFailedMessage(string message)
        => $"Export failed: {message}";

    private static string FallbackExpectedNlFileMessage(string path)
        => $"Expected an .nl file, got: {path}";

    private static string FallbackMissingOutputMessage(string sourceFile)
        => $"The export pipeline did not produce output for {sourceFile}.";

    private static string FallbackRefuseOverwriteMessage()
        => "Refusing to overwrite the source .nl file. Choose a different output path.";

    private static string FallbackSingleFileSuccessMessage(string fileName, string outputPath)
        => $"Exported {fileName} to {outputPath}";

    private static string FallbackNoProjectFileMessage(string projectRoot)
        => $"No project.yml found in {projectRoot}.";

    private static string FallbackProjectSuccessMessage(string projectName, string projectFilePath)
        => $"Exported {projectName} to {projectFilePath}";

    private static string FallbackTestsSuccessMessage(string testProjectFilePath)
        => $"Exported tests to {testProjectFilePath}";

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
