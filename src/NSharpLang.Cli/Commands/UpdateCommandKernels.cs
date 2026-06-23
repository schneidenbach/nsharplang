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

    internal static UpdateArgumentSummary GetArgumentSummary(string[] args)
    {
        var resultIndices = t_resultIndices ??= new int[3];
        var code = RequiredBindings.UpdateArgumentSummary(args, resultIndices);
        if (code != 0 || !TryGetOptionalArg(args, resultIndices[0], out var targetPackage))
            throw new InvalidOperationException("N# update argument summary kernel rejected the arguments.");

        return new UpdateArgumentSummary(
            targetPackage,
            resultIndices[1] != 0,
            resultIndices[2] != 0);
    }

    internal static string GetHelpText()
        => RequiredBindings.UpdateHelpText();

    internal static string GetMissingProjectFileMessage()
        => RequiredBindings.UpdateMissingProjectFileMessage();

    internal static string GetNoNuGetDependenciesMessage()
        => RequiredBindings.UpdateNoNuGetDependenciesMessage();

    internal static string GetPackageNotFoundMessage(string packageName)
        => RequiredBindings.UpdatePackageNotFoundMessage(packageName);

    internal static string GetResolveLatestFailureMessage(string packageName)
        => RequiredBindings.UpdateResolveLatestFailureMessage(packageName);

    internal static string GetPackageUpToDateMessage(string packageName, string version)
        => RequiredBindings.UpdatePackageUpToDateMessage(packageName, version);

    internal static string GetPackageUpdateMessage(string packageName, string currentVersion, string latestVersion)
        => RequiredBindings.UpdatePackageUpdateMessage(packageName, currentVersion, latestVersion);

    internal static string GetUpdatedPackagesMessage(int updatedCount)
    {
        var updatedCountText = updatedCount.ToString();
        return RequiredBindings.UpdateUpdatedPackagesMessage(updatedCountText, updatedCount);
    }

    internal static string GetDryRunMessage()
        => RequiredBindings.UpdateDryRunMessage();

    internal static string GetAllPackagesUpToDateMessage()
        => RequiredBindings.UpdateAllPackagesUpToDateMessage();

    internal static string GetFailedMessage(string message)
        => RequiredBindings.UpdateFailedMessage(message);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
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

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# update command kernels are unavailable.");

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
