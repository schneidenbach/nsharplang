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

    internal static RemoveArgumentSummary GetArgumentSummary(string[] args)
    {
        var resultIndices = t_resultIndices ??= new int[2];
        var code = RequiredBindings.RemoveArgumentSummary(args, resultIndices);
        if (code != 0 || !TryGetOptionalArg(args, resultIndices[0], out var packageOperand))
            throw new InvalidOperationException("N# remove argument summary kernel rejected the arguments.");

        return new RemoveArgumentSummary(
            packageOperand,
            resultIndices[1] != 0);
    }

    internal static RemoveDependencyLineAction GetDependencyLineAction(
        string line,
        string packageName)
    {
        var result = RequiredBindings.RemoveDependencyLineAction(line, packageName);
        if (result is < 0 or > 2)
            throw new InvalidOperationException("N# remove dependency-line action kernel rejected the line.");

        return (RemoveDependencyLineAction)result;
    }

    internal static bool ShouldStopDependencyContinuationLine(string line)
    {
        var result = RequiredBindings.RemoveShouldStopDependencyContinuationLine(line);
        if (result is not 0 and not 1)
            throw new InvalidOperationException("N# remove dependency continuation kernel rejected the line.");

        return result == 1;
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
