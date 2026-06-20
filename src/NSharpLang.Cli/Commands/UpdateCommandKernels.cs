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

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.UpdateHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetMissingProjectFileMessage()
    {
        if (TryGetMessage(bindings => bindings.UpdateMissingProjectFileMessage(), out var message))
            return message;

        return GetMissingProjectFileMessageWithCSharp();
    }

    internal static string GetNoNuGetDependenciesMessage()
    {
        if (TryGetMessage(bindings => bindings.UpdateNoNuGetDependenciesMessage(), out var message))
            return message;

        return GetNoNuGetDependenciesMessageWithCSharp();
    }

    internal static string GetPackageNotFoundMessage(string packageName)
    {
        if (TryGetMessage(bindings => bindings.UpdatePackageNotFoundMessage(packageName), out var message))
            return message;

        return GetPackageNotFoundMessageWithCSharp(packageName);
    }

    internal static string GetResolveLatestFailureMessage(string packageName)
    {
        if (TryGetMessage(bindings => bindings.UpdateResolveLatestFailureMessage(packageName), out var message))
            return message;

        return GetResolveLatestFailureMessageWithCSharp(packageName);
    }

    internal static string GetPackageUpToDateMessage(string packageName, string version)
    {
        if (TryGetMessage(bindings => bindings.UpdatePackageUpToDateMessage(packageName, version), out var message))
            return message;

        return GetPackageUpToDateMessageWithCSharp(packageName, version);
    }

    internal static string GetPackageUpdateMessage(string packageName, string currentVersion, string latestVersion)
    {
        if (TryGetMessage(
                bindings => bindings.UpdatePackageUpdateMessage(packageName, currentVersion, latestVersion),
                out var message))
            return message;

        return GetPackageUpdateMessageWithCSharp(packageName, currentVersion, latestVersion);
    }

    internal static string GetUpdatedPackagesMessage(int updatedCount)
    {
        var updatedCountText = updatedCount.ToString();
        if (TryGetMessage(
                bindings => bindings.UpdateUpdatedPackagesMessage(updatedCountText, updatedCount),
                out var message))
            return message;

        return GetUpdatedPackagesMessageWithCSharp(updatedCount);
    }

    internal static string GetDryRunMessage()
    {
        if (TryGetMessage(bindings => bindings.UpdateDryRunMessage(), out var message))
            return message;

        return GetDryRunMessageWithCSharp();
    }

    internal static string GetAllPackagesUpToDateMessage()
    {
        if (TryGetMessage(bindings => bindings.UpdateAllPackagesUpToDateMessage(), out var message))
            return message;

        return GetAllPackagesUpToDateMessageWithCSharp();
    }

    internal static string GetFailedMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.UpdateFailedMessage(message), out var result))
            return result;

        return GetFailedMessageWithCSharp(message);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product update command messages route through CliUpdate*Message kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Update Dependencies\n"
           + "\n"
           + "Usage: nlc update [package] [options]\n"
           + "\n"
           + "Update NuGet dependencies to their latest versions. If a package name is\n"
           + "given, only that package is updated. Otherwise all NuGet dependencies\n"
           + "are checked.\n"
           + "\n"
           + "Options:\n"
           + "  --dry-run       Show what would change without modifying files\n"
           + "  --help, -h      Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc update\n"
           + "  nlc update Newtonsoft.Json\n"
           + "  nlc update --dry-run\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Update completed successfully\n"
           + "  1  Update failed";

    private static string GetMissingProjectFileMessageWithCSharp()
        => "No project.yml found.";

    private static string GetNoNuGetDependenciesMessageWithCSharp()
        => "No NuGet dependencies to update.";

    private static string GetPackageNotFoundMessageWithCSharp(string packageName)
        => $"Package '{packageName}' not found in dependencies.";

    private static string GetResolveLatestFailureMessageWithCSharp(string packageName)
        => $"  Could not resolve latest version for {packageName}";

    private static string GetPackageUpToDateMessageWithCSharp(string packageName, string version)
        => $"  {packageName}@{version} is up to date";

    private static string GetPackageUpdateMessageWithCSharp(
        string packageName,
        string currentVersion,
        string latestVersion)
        => $"  {packageName}: {(currentVersion.Length == 0 ? "unversioned" : currentVersion)} -> {latestVersion}";

    private static string GetUpdatedPackagesMessageWithCSharp(int updatedCount)
        => $"Updated {updatedCount} package{(updatedCount == 1 ? "" : "s")}.";

    private static string GetDryRunMessageWithCSharp()
        => "(dry run — no changes made)";

    private static string GetAllPackagesUpToDateMessageWithCSharp()
        => "All packages are up to date.";

    private static string GetFailedMessageWithCSharp(string message)
        => $"Update failed: {message}";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFirstPositionalArgIndex>(
                programType,
                "CliFirstPositionalArgIndex"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateArgumentSummaryInto>(
                programType,
                "CliUpdateArgumentSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateHelpText>(
                programType,
                "CliUpdateHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateMissingProjectFileMessage>(
                programType,
                "CliUpdateMissingProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateNoNuGetDependenciesMessage>(
                programType,
                "CliUpdateNoNuGetDependenciesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdatePackageNotFoundMessage>(
                programType,
                "CliUpdatePackageNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateResolveLatestFailureMessage>(
                programType,
                "CliUpdateResolveLatestFailureMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdatePackageUpToDateMessage>(
                programType,
                "CliUpdatePackageUpToDateMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdatePackageUpdateMessage>(
                programType,
                "CliUpdatePackageUpdateMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateUpdatedPackagesMessage>(
                programType,
                "CliUpdateUpdatedPackagesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateDryRunMessage>(
                programType,
                "CliUpdateDryRunMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateAllPackagesUpToDateMessage>(
                programType,
                "CliUpdateAllPackagesUpToDateMessage"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateFailedMessage>(
                programType,
                "CliUpdateFailedMessage")));

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliUpdateArgumentSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate string CliUpdateHelpText();
    private delegate string CliUpdateMissingProjectFileMessage();
    private delegate string CliUpdateNoNuGetDependenciesMessage();
    private delegate string CliUpdatePackageNotFoundMessage(string packageName);
    private delegate string CliUpdateResolveLatestFailureMessage(string packageName);
    private delegate string CliUpdatePackageUpToDateMessage(string packageName, string version);
    private delegate string CliUpdatePackageUpdateMessage(string packageName, string currentVersion, string latestVersion);
    private delegate string CliUpdateUpdatedPackagesMessage(string updatedCountText, int updatedCount);
    private delegate string CliUpdateDryRunMessage();
    private delegate string CliUpdateAllPackagesUpToDateMessage();
    private delegate string CliUpdateFailedMessage(string message);

    private sealed record Bindings(
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliUpdateArgumentSummaryInto UpdateArgumentSummary,
        CliUpdateHelpText UpdateHelpText,
        CliUpdateMissingProjectFileMessage UpdateMissingProjectFileMessage,
        CliUpdateNoNuGetDependenciesMessage UpdateNoNuGetDependenciesMessage,
        CliUpdatePackageNotFoundMessage UpdatePackageNotFoundMessage,
        CliUpdateResolveLatestFailureMessage UpdateResolveLatestFailureMessage,
        CliUpdatePackageUpToDateMessage UpdatePackageUpToDateMessage,
        CliUpdatePackageUpdateMessage UpdatePackageUpdateMessage,
        CliUpdateUpdatedPackagesMessage UpdateUpdatedPackagesMessage,
        CliUpdateDryRunMessage UpdateDryRunMessage,
        CliUpdateAllPackagesUpToDateMessage UpdateAllPackagesUpToDateMessage,
        CliUpdateFailedMessage UpdateFailedMessage);

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
