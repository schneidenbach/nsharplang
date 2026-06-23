using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct RemoveArgumentSummary(
    string? PackageOperand,
    bool ShowHelp);

internal enum RemoveDependencyLineAction
{
    Keep = 0,
    RemoveSingleLine = 1,
    RemoveMappingBlock = 2
}

internal static class RemoveCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out RemoveArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[2];
        try
        {
            var code = bindings.RemoveArgumentSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var packageOperand))
            {
                summary = default;
                return false;
            }

            summary = new RemoveArgumentSummary(
                packageOperand,
                resultIndices[1] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetDependencyLineAction(
        string line,
        string packageName,
        out RemoveDependencyLineAction action)
    {
        action = RemoveDependencyLineAction.Keep;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.RemoveDependencyLineAction(line, packageName);
            if (result is < 0 or > 2)
                return false;

            action = (RemoveDependencyLineAction)result;
            return true;
        }
        catch
        {
            action = RemoveDependencyLineAction.Keep;
            return false;
        }
    }

    internal static bool TryShouldStopDependencyContinuationLine(string line, out bool shouldStop)
    {
        shouldStop = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.RemoveShouldStopDependencyContinuationLine(line);
            if (result is not 0 and not 1)
                return false;

            shouldStop = result == 1;
            return true;
        }
        catch
        {
            shouldStop = false;
            return false;
        }
    }

    internal static string GetHelpText()
        => RequiredBindings.RemoveHelpText();

    internal static string GetUsageMessage()
        => RequiredBindings.RemoveUsageMessage();

    internal static string GetMissingProjectFileMessage()
        => RequiredBindings.RemoveMissingProjectFileMessage();

    internal static string GetPackageNotFoundMessage(string packageName)
        => RequiredBindings.RemovePackageNotFoundMessage(packageName);

    internal static string GetRemovedMessage(string packageName)
        => RequiredBindings.RemoveRemovedMessage(packageName);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliRemoveArgumentSummaryInto>(
                programType,
                "CliRemoveArgumentSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliRemoveDependencyLineAction>(
                programType,
                "CliRemoveDependencyLineAction"),
            DogfoodKernelLoader.CreateDelegate<CliRemoveShouldStopDependencyContinuationLine>(
                programType,
                "CliRemoveShouldStopDependencyContinuationLine"),
            DogfoodKernelLoader.CreateDelegate<CliRemoveHelpText>(
                programType,
                "CliRemoveHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliRemoveUsageMessage>(
                programType,
                "CliRemoveUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRemoveMissingProjectFileMessage>(
                programType,
                "CliRemoveMissingProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRemovePackageNotFoundMessage>(
                programType,
                "CliRemovePackageNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRemoveRemovedMessage>(
                programType,
                "CliRemoveRemovedMessage")));

    private delegate int CliRemoveArgumentSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliRemoveDependencyLineAction(
        string line,
        string packageName);

    private delegate int CliRemoveShouldStopDependencyContinuationLine(
        string line);

    private delegate string CliRemoveHelpText();
    private delegate string CliRemoveUsageMessage();
    private delegate string CliRemoveMissingProjectFileMessage();
    private delegate string CliRemovePackageNotFoundMessage(string packageName);
    private delegate string CliRemoveRemovedMessage(string packageName);

    private sealed record Bindings(
        CliRemoveArgumentSummaryInto RemoveArgumentSummary,
        CliRemoveDependencyLineAction RemoveDependencyLineAction,
        CliRemoveShouldStopDependencyContinuationLine RemoveShouldStopDependencyContinuationLine,
        CliRemoveHelpText RemoveHelpText,
        CliRemoveUsageMessage RemoveUsageMessage,
        CliRemoveMissingProjectFileMessage RemoveMissingProjectFileMessage,
        CliRemovePackageNotFoundMessage RemovePackageNotFoundMessage,
        CliRemoveRemovedMessage RemoveRemovedMessage);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# remove command kernels are unavailable.");

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
