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

    internal static PackOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_resultIndices ??= new int[7];
        var code = RequiredBindings.PackOptionSummary(args, resultIndices);
        if (code != 0
            || !TryGetOptionalArg(args, resultIndices[0], out var projectOption)
            || !TryGetOptionalArg(args, resultIndices[1], out var outputDir)
            || !TryGetOptionalArg(args, resultIndices[2], out var versionOverride)
            || !TryGetOptionalArg(args, resultIndices[3], out var configuration))
        {
            throw new InvalidOperationException("N# pack option-summary kernel is unavailable.");
        }

        return new PackOptionSummary(
            projectOption,
            outputDir,
            versionOverride,
            configuration ?? "Release",
            resultIndices[4] != 0,
            resultIndices[5] != 0,
            resultIndices[6] != 0);
    }

    internal static PackOutputModeKind GetOutputMode(bool json)
    {
        var code = RequiredBindings.PackOutputMode(json ? 1 : 0);
        if (code is < 1 or > 2)
            throw new InvalidOperationException("N# pack output-mode kernel is unavailable.");

        return (PackOutputModeKind)code;
    }

    internal static PackVersionSourceKind GetEffectiveVersionSource(
        string? versionOverride,
        string? projectVersion)
    {
        var result = RequiredBindings.PackEffectiveVersionSource(
            versionOverride == null ? 0 : 1,
            versionOverride ?? string.Empty,
            projectVersion ?? string.Empty);
        if (result is < 0 or > 2)
            throw new InvalidOperationException("N# pack version-source kernel is unavailable.");

        return (PackVersionSourceKind)result;
    }

    internal static string GetHelpText()
        => GetMessage(bindings => bindings.PackHelpText());

    internal static string GetMissingProjectFileJsonMessage()
        => GetMessage(bindings => bindings.PackMissingProjectFileJsonMessage());

    internal static string GetMissingProjectFileTextMessage()
        => GetMessage(bindings => bindings.PackMissingProjectFileTextMessage());

    internal static string GetParseFailedJsonMessage(string message)
        => GetMessage(bindings => bindings.PackParseFailedJsonMessage(message));

    internal static string GetParseFailedTextMessage(string message)
        => GetMessage(bindings => bindings.PackParseFailedTextMessage(message));

    internal static string GetStartMessage(string name, string? version)
        => GetMessage(bindings => bindings.PackStartMessage(name, version == null ? 0 : 1, version ?? string.Empty));

    internal static string GetMissingVersionJsonMessage()
        => GetMessage(bindings => bindings.PackMissingVersionJsonMessage());

    internal static string GetMissingVersionTextMessage()
        => GetMessage(bindings => bindings.PackMissingVersionTextMessage());

    internal static string GetBuildFailedJsonMessage()
        => GetMessage(bindings => bindings.PackBuildFailedJsonMessage());

    internal static string GetBuildFailedTextMessage()
        => GetMessage(bindings => bindings.PackBuildFailedTextMessage());

    internal static string GetSuccessMessage()
        => GetMessage(bindings => bindings.PackSuccessMessage());

    internal static string GetPackagePathLine(string packagePath)
        => GetMessage(bindings => bindings.PackPackagePathLine(packagePath));

    internal static string GetFailedJsonMessage(string message)
        => GetMessage(bindings => bindings.PackFailedJsonMessage(message));

    internal static string GetFailedTextMessage(string message)
        => GetMessage(bindings => bindings.PackFailedTextMessage(message));

    internal static string GetNuspecText(
        string projectName,
        string version,
        string packageAuthor,
        string packageDescription,
        string packageTags,
        int packageTagsCount,
        string packageLicense,
        string packageRepository,
        string packageIcon)
        => GetMessage(bindings => bindings.PackNuspecText(
            projectName,
            version,
            packageAuthor,
            packageDescription,
            packageTags,
            packageTagsCount,
            packageLicense,
            packageRepository,
            packageIcon));

    internal static string GetSymbolsNuspecText(string projectName, string version)
        => GetMessage(bindings => bindings.PackSymbolsNuspecText(projectName, version));

    private static string GetMessage(Func<Bindings, string> getMessage)
    {
        var bindings = RequiredBindings;
        var message = getMessage(bindings);
        return !string.IsNullOrEmpty(message)
            ? message
            : throw new InvalidOperationException("N# pack kernel returned empty text.");
    }

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# pack kernels are unavailable.");

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
                "CliPackEffectiveVersionSource"),
            DogfoodKernelLoader.CreateDelegate<CliPackHelpText>(
                programType,
                "CliPackHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliPackMissingProjectFileJsonMessage>(
                programType,
                "CliPackMissingProjectFileJsonMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackMissingProjectFileTextMessage>(
                programType,
                "CliPackMissingProjectFileTextMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackParseFailedJsonMessage>(
                programType,
                "CliPackParseFailedJsonMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackParseFailedTextMessage>(
                programType,
                "CliPackParseFailedTextMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackStartMessage>(
                programType,
                "CliPackStartMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackMissingVersionJsonMessage>(
                programType,
                "CliPackMissingVersionJsonMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackMissingVersionTextMessage>(
                programType,
                "CliPackMissingVersionTextMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackBuildFailedJsonMessage>(
                programType,
                "CliPackBuildFailedJsonMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackBuildFailedTextMessage>(
                programType,
                "CliPackBuildFailedTextMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackSuccessMessage>(
                programType,
                "CliPackSuccessMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackPackagePathLine>(
                programType,
                "CliPackPackagePathLine"),
            DogfoodKernelLoader.CreateDelegate<CliPackFailedJsonMessage>(
                programType,
                "CliPackFailedJsonMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackFailedTextMessage>(
                programType,
                "CliPackFailedTextMessage"),
            DogfoodKernelLoader.CreateDelegate<CliPackNuspecText>(
                programType,
                "CliPackNuspecText"),
            DogfoodKernelLoader.CreateDelegate<CliPackSymbolsNuspecText>(
                programType,
                "CliPackSymbolsNuspecText")));

    private delegate int CliPackOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliPackOutputMode(int json);

    private delegate int CliPackEffectiveVersionSource(
        int hasVersionOverride,
        string versionOverride,
        string projectVersion);

    private delegate string CliPackHelpText();
    private delegate string CliPackMissingProjectFileJsonMessage();
    private delegate string CliPackMissingProjectFileTextMessage();
    private delegate string CliPackParseFailedJsonMessage(string message);
    private delegate string CliPackParseFailedTextMessage(string message);
    private delegate string CliPackStartMessage(string name, int hasVersion, string version);
    private delegate string CliPackMissingVersionJsonMessage();
    private delegate string CliPackMissingVersionTextMessage();
    private delegate string CliPackBuildFailedJsonMessage();
    private delegate string CliPackBuildFailedTextMessage();
    private delegate string CliPackSuccessMessage();
    private delegate string CliPackPackagePathLine(string packagePath);
    private delegate string CliPackFailedJsonMessage(string message);
    private delegate string CliPackFailedTextMessage(string message);
    private delegate string CliPackNuspecText(
        string projectName,
        string version,
        string packageAuthor,
        string packageDescription,
        string packageTags,
        int packageTagsCount,
        string packageLicense,
        string packageRepository,
        string packageIcon);
    private delegate string CliPackSymbolsNuspecText(string projectName, string version);

    private sealed record Bindings(
        CliPackOptionSummaryInto PackOptionSummary,
        CliPackOutputMode PackOutputMode,
        CliPackEffectiveVersionSource PackEffectiveVersionSource,
        CliPackHelpText PackHelpText,
        CliPackMissingProjectFileJsonMessage PackMissingProjectFileJsonMessage,
        CliPackMissingProjectFileTextMessage PackMissingProjectFileTextMessage,
        CliPackParseFailedJsonMessage PackParseFailedJsonMessage,
        CliPackParseFailedTextMessage PackParseFailedTextMessage,
        CliPackStartMessage PackStartMessage,
        CliPackMissingVersionJsonMessage PackMissingVersionJsonMessage,
        CliPackMissingVersionTextMessage PackMissingVersionTextMessage,
        CliPackBuildFailedJsonMessage PackBuildFailedJsonMessage,
        CliPackBuildFailedTextMessage PackBuildFailedTextMessage,
        CliPackSuccessMessage PackSuccessMessage,
        CliPackPackagePathLine PackPackagePathLine,
        CliPackFailedJsonMessage PackFailedJsonMessage,
        CliPackFailedTextMessage PackFailedTextMessage,
        CliPackNuspecText PackNuspecText,
        CliPackSymbolsNuspecText PackSymbolsNuspecText);
}
