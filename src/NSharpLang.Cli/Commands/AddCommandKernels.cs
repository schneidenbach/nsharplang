using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct AddArgumentSummary(
    string? VersionOption,
    string? PathOption,
    string? PackageOperand,
    bool Framework,
    bool Prerelease,
    bool ShowHelp);

internal static class AddCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out AddArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[6];
        try
        {
            var code = bindings.AddArgumentSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var versionOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var pathOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var packageOperand))
            {
                summary = default;
                return false;
            }

            summary = new AddArgumentSummary(
                versionOption,
                pathOption,
                packageOperand,
                resultIndices[3] != 0,
                resultIndices[4] != 0,
                resultIndices[5] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetPackageOperand(
        string[] args,
        string[] optionsWithValues,
        out string? package)
    {
        package = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.FirstPositionalArgIndex(args, optionsWithValues);
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
            DogfoodKernelLoader.CreateDelegate<CliAddArgumentSummaryInto>(
                programType,
                "CliAddArgumentSummaryInto")));

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliAddArgumentSummaryInto(
        string[] args,
        int[] resultIndices);

    private sealed record Bindings(
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliAddArgumentSummaryInto AddArgumentSummary);

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
