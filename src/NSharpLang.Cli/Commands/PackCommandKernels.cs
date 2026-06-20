using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct PackOptionSummary(
    string? ProjectOption,
    string? OutputDir,
    string? VersionOverride,
    string Configuration,
    bool IncludeSymbols,
    bool JsonOutput,
    bool ShowHelp);

internal enum PackVersionSourceKind
{
    Missing = 0,
    Override = 1,
    Project = 2
}

internal enum PackOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class PackCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out PackOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[7];
        try
        {
            var code = bindings.PackOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var outputDir)
                || !TryGetOptionalArg(args, resultIndices[2], out var versionOverride)
                || !TryGetOptionalArg(args, resultIndices[3], out var configuration))
            {
                summary = default;
                return false;
            }

            summary = new PackOptionSummary(
                projectOption,
                outputDir,
                versionOverride,
                configuration ?? "Release",
                resultIndices[4] != 0,
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

    internal static bool TryGetOutputMode(bool json, out PackOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.PackOutputMode(json ? 1 : 0);
            if (code is < 1 or > 2)
                return false;

            outputMode = (PackOutputModeKind)code;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

    internal static bool TryGetEffectiveVersionSource(
        string? versionOverride,
        string? projectVersion,
        out PackVersionSourceKind versionSource)
    {
        versionSource = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.PackEffectiveVersionSource(
                versionOverride == null ? 0 : 1,
                versionOverride ?? string.Empty,
                projectVersion ?? string.Empty);
            if (result is < 0 or > 2)
                return false;

            versionSource = (PackVersionSourceKind)result;
            return true;
        }
        catch
        {
            versionSource = default;
            return false;
        }
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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliPackOptionSummaryInto>(
                programType,
                "CliPackOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliPackOutputMode>(
                programType,
                "CliPackOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliPackEffectiveVersionSource>(
                programType,
                "CliPackEffectiveVersionSource")));

    private delegate int CliPackOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliPackOutputMode(int json);

    private delegate int CliPackEffectiveVersionSource(
        int hasVersionOverride,
        string versionOverride,
        string projectVersion);

    private sealed record Bindings(
        CliPackOptionSummaryInto PackOptionSummary,
        CliPackOutputMode PackOutputMode,
        CliPackEffectiveVersionSource PackEffectiveVersionSource);
}
