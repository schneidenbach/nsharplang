using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct EnvOptionSummary(
    bool Json,
    bool ShowHelp);

internal enum EnvOutputModeKind
{
    Json = 1,
    Text = 2
}

internal enum EnvTextLineKind
{
    NlcVersion = 1,
    DotnetVersion = 2,
    Runtime = 3,
    Os = 4,
    Arch = 5,
    NugetCache = 6,
    NsharpBin = 7,
    NsharpPackages = 8,
    Project = 9,
    Target = 10,
    OutputType = 11,
    Sdk = 12
}

internal static class EnvCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out EnvOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[2];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            summary = new EnvOptionSummary(
                resultIndices[0] != 0,
                resultIndices[1] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out EnvOutputModeKind outputMode)
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

            outputMode = (EnvOutputModeKind)code;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.EnvHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetTextLine(EnvTextLineKind kind, string value)
    {
        if (TryGetMessage(bindings => bindings.EnvTextLine((int)kind, value), out var message))
            return message;

        return GetTextLineWithCSharp(kind, value);
    }

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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product env help and text labels route through CliEnv* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Environment Info\n"
           + "\n"
           + "Usage: nlc env [options]\n"
           + "\n"
           + "Show toolchain and environment information.\n"
           + "\n"
           + "Options:\n"
           + "  --json          Output as JSON envelope\n"
           + "  --help, -h      Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc env\n"
           + "  nlc env --json\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Always succeeds";

    private static string GetTextLineWithCSharp(EnvTextLineKind kind, string value)
        => kind switch
        {
            EnvTextLineKind.NlcVersion => $"nlc version:    {value}",
            EnvTextLineKind.DotnetVersion => $"dotnet version: {value}",
            EnvTextLineKind.Runtime => $"runtime:        {value}",
            EnvTextLineKind.Os => $"os:             {value}",
            EnvTextLineKind.Arch => $"arch:           {value}",
            EnvTextLineKind.NugetCache => $"nuget cache:    {value}",
            EnvTextLineKind.NsharpBin => $"nsharp bin:     {value}",
            EnvTextLineKind.NsharpPackages => $"nsharp packages: {value}",
            EnvTextLineKind.Project => $"project:        {value}",
            EnvTextLineKind.Target => $"target:         {value}",
            EnvTextLineKind.OutputType => $"output type:    {value}",
            EnvTextLineKind.Sdk => $"sdk:            {value}",
            _ => string.Empty
        };

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliEnvOptionSummaryInto>(
                programType,
                "CliEnvOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliEnvOutputMode>(
                programType,
                "CliEnvOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliEnvHelpText>(
                programType,
                "CliEnvHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliEnvTextLine>(
                programType,
                "CliEnvTextLine")));

    private delegate int CliEnvOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliEnvOutputMode(int json);

    private delegate string CliEnvHelpText();

    private delegate string CliEnvTextLine(
        int lineKind,
        string value);

    private sealed record Bindings(
        CliEnvOptionSummaryInto OptionSummary,
        CliEnvOutputMode OutputMode,
        CliEnvHelpText EnvHelpText,
        CliEnvTextLine EnvTextLine);
}
