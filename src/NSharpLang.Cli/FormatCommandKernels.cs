using System;

namespace NSharpLang.Cli;

internal readonly record struct FormatOptionSummary(
    string? ProjectOption,
    bool VerifyOnly,
    bool DiffOnly,
    bool StdinMode,
    bool ShowHelp);

internal static class FormatCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out FormatOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[5];
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

            summary = new FormatOptionSummary(
                projectOption,
                resultIndices[1] != 0,
                resultIndices[2] != 0,
                resultIndices[3] != 0,
                resultIndices[4] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryShouldFormatDiscoveredPath(string relativePath, out bool shouldFormat)
    {
        shouldFormat = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.ShouldFormatDiscoveredPath(relativePath);
            if (result is not 0 and not 1)
                return false;

            shouldFormat = result == 1;
            return true;
        }
        catch
        {
            shouldFormat = false;
            return false;
        }
    }

    internal static bool TryShouldSkipDiscoveredDirectoryName(string directoryName, out bool shouldSkip)
    {
        shouldSkip = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.ShouldSkipDiscoveredDirectoryName(directoryName);
            if (result is not 0 and not 1)
                return false;

            shouldSkip = result == 1;
            return true;
        }
        catch
        {
            shouldSkip = false;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFormatOptionSummaryInto>(
                programType,
                "CliFormatOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliShouldFormatDiscoveredPath>(
                programType,
                "CliShouldFormatDiscoveredPath"),
            DogfoodKernelLoader.CreateDelegate<CliShouldSkipFormatDirectoryName>(
                programType,
                "CliShouldSkipFormatDirectoryName")));

    private delegate int CliFormatOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliShouldFormatDiscoveredPath(string relativePath);

    private delegate int CliShouldSkipFormatDirectoryName(string directoryName);

    private sealed record Bindings(
        CliFormatOptionSummaryInto OptionSummary,
        CliShouldFormatDiscoveredPath ShouldFormatDiscoveredPath,
        CliShouldSkipFormatDirectoryName ShouldSkipDiscoveredDirectoryName);

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
}
