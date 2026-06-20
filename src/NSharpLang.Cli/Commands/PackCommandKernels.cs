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

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.PackHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetMissingProjectFileJsonMessage()
    {
        if (TryGetMessage(bindings => bindings.PackMissingProjectFileJsonMessage(), out var message))
            return message;

        return GetMissingProjectFileJsonMessageWithCSharp();
    }

    internal static string GetMissingProjectFileTextMessage()
    {
        if (TryGetMessage(bindings => bindings.PackMissingProjectFileTextMessage(), out var message))
            return message;

        return GetMissingProjectFileTextMessageWithCSharp();
    }

    internal static string GetParseFailedJsonMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.PackParseFailedJsonMessage(message), out var result))
            return result;

        return GetParseFailedJsonMessageWithCSharp(message);
    }

    internal static string GetParseFailedTextMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.PackParseFailedTextMessage(message), out var result))
            return result;

        return GetParseFailedTextMessageWithCSharp(message);
    }

    internal static string GetStartMessage(string name, string? version)
    {
        if (TryGetMessage(
                bindings => bindings.PackStartMessage(name, version == null ? 0 : 1, version ?? string.Empty),
                out var message))
            return message;

        return GetStartMessageWithCSharp(name, version);
    }

    internal static string GetMissingVersionJsonMessage()
    {
        if (TryGetMessage(bindings => bindings.PackMissingVersionJsonMessage(), out var message))
            return message;

        return GetMissingVersionJsonMessageWithCSharp();
    }

    internal static string GetMissingVersionTextMessage()
    {
        if (TryGetMessage(bindings => bindings.PackMissingVersionTextMessage(), out var message))
            return message;

        return GetMissingVersionTextMessageWithCSharp();
    }

    internal static string GetBuildFailedJsonMessage()
    {
        if (TryGetMessage(bindings => bindings.PackBuildFailedJsonMessage(), out var message))
            return message;

        return GetBuildFailedJsonMessageWithCSharp();
    }

    internal static string GetBuildFailedTextMessage()
    {
        if (TryGetMessage(bindings => bindings.PackBuildFailedTextMessage(), out var message))
            return message;

        return GetBuildFailedTextMessageWithCSharp();
    }

    internal static string GetSuccessMessage()
    {
        if (TryGetMessage(bindings => bindings.PackSuccessMessage(), out var message))
            return message;

        return GetSuccessMessageWithCSharp();
    }

    internal static string GetPackagePathLine(string packagePath)
    {
        if (TryGetMessage(bindings => bindings.PackPackagePathLine(packagePath), out var message))
            return message;

        return GetPackagePathLineWithCSharp(packagePath);
    }

    internal static string GetFailedJsonMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.PackFailedJsonMessage(message), out var result))
            return result;

        return GetFailedJsonMessageWithCSharp(message);
    }

    internal static string GetFailedTextMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.PackFailedTextMessage(message), out var result))
            return result;

        return GetFailedTextMessageWithCSharp(message);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product pack messages route through CliPack* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Pack\n"
           + "\n"
           + "Usage: nlc pack [options]\n"
           + "\n"
           + "Generate a NuGet package from the current N# project.\n"
           + "\n"
           + "Reads package metadata from the 'package' section of project.yml and packs\n"
           + "the native nlc IL build output. The package section is optional but\n"
           + "recommended for library projects intended for distribution.\n"
           + "\n"
           + "project.yml example:\n"
           + "  name: MyLibrary\n"
           + "  version: 1.2.0\n"
           + "  outputType: library\n"
           + "  package:\n"
           + "    author: Your Name\n"
           + "    description: A concise description of your library\n"
           + "    license: MIT\n"
           + "    repository: https://github.com/you/MyLibrary\n"
           + "    tags:\n"
           + "      - dotnet\n"
           + "      - nsharp\n"
           + "\n"
           + "Options:\n"
           + "  --output <dir>          Output directory for the .nupkg file\n"
           + "  --version <ver>         Override the version from project.yml\n"
           + "  --configuration <cfg>   Build configuration (default: Release)\n"
           + "  --include-symbols       Also produce a .snupkg symbols package\n"
           + "  --project <dir>         Project root directory (default: current directory)\n"
           + "  --json                  Output structured JSON (schemaVersion 1 envelope)\n"
           + "  --help, -h              Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc pack\n"
           + "  nlc pack --output ./artifacts\n"
           + "  nlc pack --version 2.0.0-beta.1\n"
           + "  nlc pack --include-symbols\n"
           + "  nlc pack --json\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Pack succeeded\n"
           + "  1  Pack failed";

    private static string GetMissingProjectFileJsonMessageWithCSharp()
        => "No project.yml found. Run 'nlc new <name>' to create a project.";

    private static string GetMissingProjectFileTextMessageWithCSharp()
        => "Error: No project.yml found in current directory.\nRun 'nlc new <name>' to create a project.";

    private static string GetParseFailedJsonMessageWithCSharp(string message)
        => $"Failed to parse project.yml: {message}";

    private static string GetParseFailedTextMessageWithCSharp(string message)
        => $"Error: Failed to parse project.yml: {message}";

    private static string GetStartMessageWithCSharp(string name, string? version)
        => $"Packing {name} {version ?? "(no version)"}...";

    private static string GetMissingVersionJsonMessageWithCSharp()
        => "Package version is required. Set version in project.yml or pass --version.";

    private static string GetMissingVersionTextMessageWithCSharp()
        => "Error: Package version is required. Set version in project.yml or pass --version.";

    private static string GetBuildFailedJsonMessageWithCSharp()
        => "Pack build failed.";

    private static string GetBuildFailedTextMessageWithCSharp()
        => "Error: Pack build failed.";

    private static string GetSuccessMessageWithCSharp()
        => "Pack successful!";

    private static string GetPackagePathLineWithCSharp(string packagePath)
        => $"  Package: {packagePath}";

    private static string GetFailedJsonMessageWithCSharp(string message)
        => $"Pack failed: {message}";

    private static string GetFailedTextMessageWithCSharp(string message)
        => $"Error: Pack failed: {message}";

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
                "CliPackFailedTextMessage")));

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
        CliPackFailedTextMessage PackFailedTextMessage);
}
