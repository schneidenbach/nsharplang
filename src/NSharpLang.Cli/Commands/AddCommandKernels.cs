using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

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
    [ThreadStatic]
    private static DependencyExistsScratch? t_dependencyExistsScratch;

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

    internal static bool TryPackageOrFrameworkDependencyExists(
        IReadOnlyList<Reference> dependencies,
        string packageName,
        out bool exists)
    {
        exists = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_dependencyExistsScratch ??= new DependencyExistsScratch();
        scratch.EnsureCapacity(dependencies.Count);

        for (var i = 0; i < dependencies.Count; i++)
        {
            var dependency = dependencies[i];
            scratch.NugetNames[i] = dependency.Nuget ?? string.Empty;
            scratch.NugetPresent[i] = dependency.Nuget == null ? 0 : 1;
            scratch.FrameworkNames[i] = dependency.Framework ?? string.Empty;
            scratch.FrameworkPresent[i] = dependency.Framework == null ? 0 : 1;
        }

        try
        {
            var result = bindings.AddPackageOrFrameworkDependencyExists(
                scratch.NugetNames,
                scratch.NugetPresent,
                scratch.FrameworkNames,
                scratch.FrameworkPresent,
                dependencies.Count,
                packageName);
            if (result is not 0 and not 1)
                return false;

            exists = result == 1;
            return true;
        }
        catch
        {
            exists = false;
            return false;
        }
    }

    internal static bool TryProjectDependencyExists(
        IReadOnlyList<Reference> dependencies,
        string localPath,
        out bool exists)
    {
        exists = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_dependencyExistsScratch ??= new DependencyExistsScratch();
        scratch.EnsureCapacity(dependencies.Count);

        for (var i = 0; i < dependencies.Count; i++)
        {
            var dependency = dependencies[i];
            scratch.ProjectNames[i] = dependency.Project ?? string.Empty;
            scratch.ProjectPresent[i] = dependency.Project == null ? 0 : 1;
        }

        try
        {
            var result = bindings.AddProjectDependencyExists(
                scratch.ProjectNames,
                scratch.ProjectPresent,
                dependencies.Count,
                localPath);
            if (result is not 0 and not 1)
                return false;

            exists = result == 1;
            return true;
        }
        catch
        {
            exists = false;
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

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.AddHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.AddUsageMessage(), out var message))
            return message;

        return GetUsageMessageWithCSharp();
    }

    internal static string GetMissingProjectFileMessage()
    {
        if (TryGetMessage(bindings => bindings.AddMissingProjectFileMessage(), out var message))
            return message;

        return GetMissingProjectFileMessageWithCSharp();
    }

    internal static string GetResolvingLatestVersionMessage(string packageName)
    {
        if (TryGetMessage(bindings => bindings.AddResolvingLatestVersionMessage(packageName), out var message))
            return message;

        return GetResolvingLatestVersionMessageWithCSharp(packageName);
    }

    internal static string GetPackageNotFoundMessage(string packageName)
    {
        if (TryGetMessage(bindings => bindings.AddPackageNotFoundMessage(packageName), out var message))
            return message;

        return GetPackageNotFoundMessageWithCSharp(packageName);
    }

    internal static string GetDuplicatePackageMessage(string packageName)
    {
        if (TryGetMessage(bindings => bindings.AddDuplicatePackageMessage(packageName), out var message))
            return message;

        return GetDuplicatePackageMessageWithCSharp(packageName);
    }

    internal static string GetDuplicateProjectReferenceMessage(string localPath)
    {
        if (TryGetMessage(bindings => bindings.AddDuplicateProjectReferenceMessage(localPath), out var message))
            return message;

        return GetDuplicateProjectReferenceMessageWithCSharp(localPath);
    }

    internal static string GetFrameworkAddedMessage(string packageName)
    {
        if (TryGetMessage(bindings => bindings.AddFrameworkAddedMessage(packageName), out var message))
            return message;

        return GetFrameworkAddedMessageWithCSharp(packageName);
    }

    internal static string GetPackageAddedMessage(string packageName, string version)
    {
        if (TryGetMessage(bindings => bindings.AddPackageAddedMessage(packageName, version), out var message))
            return message;

        return GetPackageAddedMessageWithCSharp(packageName, version);
    }

    internal static string GetProjectReferenceAddedMessage(string localPath)
    {
        if (TryGetMessage(bindings => bindings.AddProjectReferenceAddedMessage(localPath), out var message))
            return message;

        return GetProjectReferenceAddedMessageWithCSharp(localPath);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product add command messages route through CliAdd*Message kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Add Dependency\n"
           + "\n"
           + "Usage: nlc add <package> [options]\n"
           + "       nlc add <package>@<version>\n"
           + "       nlc add --path <local-project>\n"
           + "\n"
           + "Add a NuGet package, framework reference, or local project reference to project.yml.\n"
           + "If no version is specified, the latest version is resolved from NuGet.\n"
           + "\n"
           + "Options:\n"
           + "  --version <ver>   Package version (alternative to @version syntax)\n"
           + "  --prerelease      Allow prerelease versions when resolving latest\n"
           + "  --framework       Add as a framework reference instead of NuGet package\n"
           + "  --path <path>     Add a local project reference (path to project directory or .csproj)\n"
           + "  --help, -h        Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc add Newtonsoft.Json\n"
           + "  nlc add Serilog@3.1.0\n"
           + "  nlc add Serilog --version 3.1.0\n"
           + "  nlc add System.Text.Json --prerelease\n"
           + "  nlc add Microsoft.AspNetCore.App --framework\n"
           + "  nlc add --path ../MyLibrary\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Dependency added successfully\n"
           + "  1  Failed to add dependency";

    private static string GetUsageMessageWithCSharp()
        => "Usage: nlc add <package> [--version <ver>]\n       nlc add <package>@<version>";

    private static string GetMissingProjectFileMessageWithCSharp()
        => "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project.";

    private static string GetResolvingLatestVersionMessageWithCSharp(string packageName)
        => $"Resolving latest version for {packageName}...";

    private static string GetPackageNotFoundMessageWithCSharp(string packageName)
        => $"Could not find package '{packageName}' on NuGet. Check the package name and try again.";

    private static string GetDuplicatePackageMessageWithCSharp(string packageName)
        => $"'{packageName}' is already in dependencies. Use 'nlc update' to change the version.";

    private static string GetDuplicateProjectReferenceMessageWithCSharp(string localPath)
        => $"Project reference '{localPath}' is already in dependencies.";

    private static string GetFrameworkAddedMessageWithCSharp(string packageName)
        => $"Added framework reference '{packageName}' to project.yml";

    private static string GetPackageAddedMessageWithCSharp(string packageName, string version)
        => $"Added {packageName}@{version} to project.yml";

    private static string GetProjectReferenceAddedMessageWithCSharp(string localPath)
        => $"Added project reference '{localPath}' to project.yml";

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
                "CliAddDependencyInsertIndex"),
            DogfoodKernelLoader.CreateDelegate<CliAddPackageOrFrameworkDependencyExists>(
                programType,
                "CliAddPackageOrFrameworkDependencyExists"),
            DogfoodKernelLoader.CreateDelegate<CliAddProjectDependencyExists>(
                programType,
                "CliAddProjectDependencyExists"),
            DogfoodKernelLoader.CreateDelegate<CliAddHelpText>(
                programType,
                "CliAddHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliAddUsageMessage>(
                programType,
                "CliAddUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAddMissingProjectFileMessage>(
                programType,
                "CliAddMissingProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAddResolvingLatestVersionMessage>(
                programType,
                "CliAddResolvingLatestVersionMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAddPackageNotFoundMessage>(
                programType,
                "CliAddPackageNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAddDuplicatePackageMessage>(
                programType,
                "CliAddDuplicatePackageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAddDuplicateProjectReferenceMessage>(
                programType,
                "CliAddDuplicateProjectReferenceMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAddFrameworkAddedMessage>(
                programType,
                "CliAddFrameworkAddedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAddPackageAddedMessage>(
                programType,
                "CliAddPackageAddedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliAddProjectReferenceAddedMessage>(
                programType,
                "CliAddProjectReferenceAddedMessage")));

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

    private delegate int CliAddPackageOrFrameworkDependencyExists(
        string[] nugetNames,
        int[] nugetPresent,
        string[] frameworkNames,
        int[] frameworkPresent,
        int count,
        string packageName);

    private delegate int CliAddProjectDependencyExists(
        string[] projectNames,
        int[] projectPresent,
        int count,
        string localPath);

    private delegate string CliAddHelpText();
    private delegate string CliAddUsageMessage();
    private delegate string CliAddMissingProjectFileMessage();
    private delegate string CliAddResolvingLatestVersionMessage(string packageName);
    private delegate string CliAddPackageNotFoundMessage(string packageName);
    private delegate string CliAddDuplicatePackageMessage(string packageName);
    private delegate string CliAddDuplicateProjectReferenceMessage(string localPath);
    private delegate string CliAddFrameworkAddedMessage(string packageName);
    private delegate string CliAddPackageAddedMessage(string packageName, string version);
    private delegate string CliAddProjectReferenceAddedMessage(string localPath);

    private sealed record Bindings(
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliAddArgumentSummaryInto AddArgumentSummary,
        CliAddPackageSpecInto AddPackageSpec,
        CliAddDependencyInsertIndex AddDependencyInsertIndex,
        CliAddPackageOrFrameworkDependencyExists AddPackageOrFrameworkDependencyExists,
        CliAddProjectDependencyExists AddProjectDependencyExists,
        CliAddHelpText AddHelpText,
        CliAddUsageMessage AddUsageMessage,
        CliAddMissingProjectFileMessage AddMissingProjectFileMessage,
        CliAddResolvingLatestVersionMessage AddResolvingLatestVersionMessage,
        CliAddPackageNotFoundMessage AddPackageNotFoundMessage,
        CliAddDuplicatePackageMessage AddDuplicatePackageMessage,
        CliAddDuplicateProjectReferenceMessage AddDuplicateProjectReferenceMessage,
        CliAddFrameworkAddedMessage AddFrameworkAddedMessage,
        CliAddPackageAddedMessage AddPackageAddedMessage,
        CliAddProjectReferenceAddedMessage AddProjectReferenceAddedMessage);

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

    private sealed class DependencyExistsScratch
    {
        internal string[] NugetNames = Array.Empty<string>();
        internal int[] NugetPresent = Array.Empty<int>();
        internal string[] FrameworkNames = Array.Empty<string>();
        internal int[] FrameworkPresent = Array.Empty<int>();
        internal string[] ProjectNames = Array.Empty<string>();
        internal int[] ProjectPresent = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (NugetNames.Length >= count)
                return;

            NugetNames = new string[count];
            NugetPresent = new int[count];
            FrameworkNames = new string[count];
            FrameworkPresent = new int[count];
            ProjectNames = new string[count];
            ProjectPresent = new int[count];
        }
    }
}
