using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct AddArgumentSummary(
    string? VersionOption,
    string? PathOption,
    string? PackageOperand,
    bool Framework,
    bool Prerelease,
    bool ShowHelp);

internal readonly record struct AddPackageSpec(
    string PackageName,
    string? Version);

internal static class AddCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;
    [ThreadStatic]
    private static int[]? t_packageSpecResult;

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

    internal static bool TryGetPackageSpec(string raw, string? explicitVersion, out AddPackageSpec spec)
    {
        spec = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_packageSpecResult ??= new int[4];
        try
        {
            var explicitVersionPresent = explicitVersion == null ? 0 : 1;
            var code = bindings.AddPackageSpec(raw, explicitVersion ?? string.Empty, explicitVersionPresent, result);
            if (code != 0)
                return false;

            var packageLength = result[0];
            if (packageLength < 0 || packageLength > raw.Length)
                return false;

            var versionSource = result[1];
            var versionStart = result[2];
            var versionLength = result[3];

            string? version = null;
            if (versionSource == 1)
            {
                if (!TrySlice(raw, versionStart, versionLength, out version))
                    return false;
            }
            else if (versionSource == 2)
            {
                if (explicitVersion == null || !TrySlice(explicitVersion, versionStart, versionLength, out version))
                    return false;
            }
            else if (versionSource != 0)
            {
                return false;
            }

            spec = new AddPackageSpec(raw[..packageLength], version);
            return true;
        }
        catch
        {
            spec = default;
            return false;
        }
    }

    internal static bool TryGetDependencyInsertIndex(string[] lines, out int insertIndex)
    {
        insertIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.AddDependencyInsertIndex(lines);
            if (result < -1 || result > lines.Length)
                return false;

            insertIndex = result;
            return true;
        }
        catch
        {
            insertIndex = -1;
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
                "CliAddArgumentSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliAddPackageSpecInto>(
                programType,
                "CliAddPackageSpecInto"),
            DogfoodKernelLoader.CreateDelegate<CliAddDependencyInsertIndex>(
                programType,
                "CliAddDependencyInsertIndex")));

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliAddArgumentSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliAddPackageSpecInto(
        string raw,
        string explicitVersion,
        int explicitVersionPresent,
        int[] result);

    private delegate int CliAddDependencyInsertIndex(
        string[] lines);

    private sealed record Bindings(
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliAddArgumentSummaryInto AddArgumentSummary,
        CliAddPackageSpecInto AddPackageSpec,
        CliAddDependencyInsertIndex AddDependencyInsertIndex);

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

    private static bool TrySlice(string value, int start, int length, out string slice)
    {
        slice = string.Empty;
        if (start < 0 || length < 0 || start + length > value.Length)
            return false;

        slice = value.Substring(start, length);
        return true;
    }
}
