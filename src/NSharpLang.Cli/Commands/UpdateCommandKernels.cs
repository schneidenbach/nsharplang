using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct UpdateArgumentSummary(
    string? TargetPackage,
    bool DryRun,
    bool ShowHelp);

internal static class UpdateCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out UpdateArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[3];
        try
        {
            var code = bindings.UpdateArgumentSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var targetPackage))
            {
                summary = default;
                return false;
            }

            summary = new UpdateArgumentSummary(
                targetPackage,
                resultIndices[1] != 0,
                resultIndices[2] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetTargetPackage(string[] args, out string? package)
    {
        package = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.FirstPositionalArgIndex(args, Array.Empty<string>());
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            package = args[index];
            return true;
        }
        catch
        {
            package = null;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFirstPositionalArgIndex>(
                programType,
                "CliFirstPositionalArgIndex"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateArgumentSummaryInto>(
                programType,
                "CliUpdateArgumentSummaryInto")));

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliUpdateArgumentSummaryInto(
        string[] args,
        int[] resultIndices);

    private sealed record Bindings(
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliUpdateArgumentSummaryInto UpdateArgumentSummary);

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
