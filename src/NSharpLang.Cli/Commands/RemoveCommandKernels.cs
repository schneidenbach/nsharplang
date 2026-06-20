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

    internal static bool TryGetPackageOperand(string[] args, out string? package)
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
    {
        if (TryGetMessage(bindings => bindings.RemoveHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.RemoveUsageMessage(), out var message))
            return message;

        return GetUsageMessageWithCSharp();
    }

    internal static string GetMissingProjectFileMessage()
    {
        if (TryGetMessage(bindings => bindings.RemoveMissingProjectFileMessage(), out var message))
            return message;

        return GetMissingProjectFileMessageWithCSharp();
    }

    internal static string GetPackageNotFoundMessage(string packageName)
    {
        if (TryGetMessage(bindings => bindings.RemovePackageNotFoundMessage(packageName), out var message))
            return message;

        return GetPackageNotFoundMessageWithCSharp(packageName);
    }

    internal static string GetRemovedMessage(string packageName)
    {
        if (TryGetMessage(bindings => bindings.RemoveRemovedMessage(packageName), out var message))
            return message;

        return GetRemovedMessageWithCSharp(packageName);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product remove command messages route through CliRemove*Message kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Remove Dependency\n"
           + "\n"
           + "Usage: nlc remove <package>\n"
           + "\n"
           + "Remove a dependency from project.yml.\n"
           + "\n"
           + "Options:\n"
           + "  --help, -h    Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc remove Newtonsoft.Json\n"
           + "  nlc remove Microsoft.AspNetCore.App\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Dependency removed successfully\n"
           + "  1  Failed to remove dependency";

    private static string GetUsageMessageWithCSharp()
        => "Usage: nlc remove <package>";

    private static string GetMissingProjectFileMessageWithCSharp()
        => "No project.yml found.";

    private static string GetPackageNotFoundMessageWithCSharp(string packageName)
        => $"Package '{packageName}' not found in dependencies.";

    private static string GetRemovedMessageWithCSharp(string packageName)
        => $"Removed {packageName} from project.yml";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFirstPositionalArgIndex>(
                programType,
                "CliFirstPositionalArgIndex"),
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

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

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
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliRemoveArgumentSummaryInto RemoveArgumentSummary,
        CliRemoveDependencyLineAction RemoveDependencyLineAction,
        CliRemoveShouldStopDependencyContinuationLine RemoveShouldStopDependencyContinuationLine,
        CliRemoveHelpText RemoveHelpText,
        CliRemoveUsageMessage RemoveUsageMessage,
        CliRemoveMissingProjectFileMessage RemoveMissingProjectFileMessage,
        CliRemovePackageNotFoundMessage RemovePackageNotFoundMessage,
        CliRemoveRemovedMessage RemoveRemovedMessage);

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
