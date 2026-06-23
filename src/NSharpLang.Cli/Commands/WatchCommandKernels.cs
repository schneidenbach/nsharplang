using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct WatchOptionSummary(
    string? ProjectOption,
    string? DebounceMsOption,
    string? MaxRunsOption,
    bool ShowHelp);

internal enum WatchTargetKind
{
    Unknown = 0,
    Check = 1,
    Build = 2,
    Test = 3,
    Lint = 4,
    Format = 5
}

internal readonly record struct WatchTargetSummary(WatchTargetKind TargetKind);

internal static class WatchCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;
    [ThreadStatic]
    private static int[]? t_resultIndices;
    [ThreadStatic]
    private static int[]? t_targetSummaryIndices;
    [ThreadStatic]
    private static int[]? t_positiveIntResult;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetTargetSummary(string[] args, out WatchTargetSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_targetSummaryIndices ??= new int[1];
        try
        {
            var code = bindings.TargetSummary(args, resultIndices);
            if (code != 0)
                return false;

            var targetKindValue = resultIndices[0];
            if (targetKindValue < 0 || targetKindValue > 5)
                return false;

            summary = new WatchTargetSummary((WatchTargetKind)targetKindValue);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOptionSummary(string[] args, out WatchOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[4];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var debounceMsOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var maxRunsOption))
            {
                summary = default;
                return false;
            }

            summary = new WatchOptionSummary(
                projectOption,
                debounceMsOption,
                maxRunsOption,
                resultIndices[3] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetForwardedArgs(string[] args, out string[] forwardedArgs)
    {
        forwardedArgs = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length <= 1)
            return true;

        var resultIndices = t_resultIndices;
        if (resultIndices == null || resultIndices.Length < args.Length)
        {
            resultIndices = new int[args.Length];
            t_resultIndices = resultIndices;
        }

        try
        {
            var count = bindings.WatchForwardedArgIndices(args, resultIndices);
            if (count < 0 || count > args.Length)
                return false;

            if (count == 0)
                return true;

            forwardedArgs = new string[count];
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = resultIndices[i];
                if (sourceIndex <= 0 || sourceIndex >= args.Length)
                {
                    forwardedArgs = Array.Empty<string>();
                    return false;
                }

                forwardedArgs[i] = args[sourceIndex];
            }

            return true;
        }
        catch
        {
            forwardedArgs = Array.Empty<string>();
            return false;
        }
    }

    internal static bool TryParsePositiveInt(string value, out int parsed)
    {
        parsed = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_positiveIntResult ??= new int[1];
        try
        {
            var code = bindings.PositiveInt(value, result);
            if (code < 0)
                return false;

            parsed = result[0];
            return true;
        }
        catch
        {
            parsed = 0;
            return false;
        }
    }

    internal static string GetTargetCommandName(WatchTargetKind targetKind)
        => RequiredBindings.WatchTargetCommandName((int)targetKind);

    internal static string GetHelpText()
        => RequiredBindings.WatchHelpText();

    internal static string GetUnsupportedTargetMessage(string target)
        => RequiredBindings.WatchUnsupportedTargetMessage(target);

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
        => RequiredBindings.WatchProjectDirectoryNotFoundMessage(projectRoot);

    internal static string GetPositiveIntExpectedMessage(string flag)
        => RequiredBindings.WatchPositiveIntExpectedMessage(flag);

    internal static string GetStartedMessage(string projectRoot)
        => RequiredBindings.WatchStartedMessage(projectRoot);

    internal static string GetChangeDetectedMessage(string timeText, string watchedCommand)
        => RequiredBindings.WatchChangeDetectedMessage(timeText, watchedCommand);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliWatchOptionSummaryInto>(
                programType,
                "CliWatchOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliWatchForwardedArgIndicesInto>(
                programType,
                "CliWatchForwardedArgIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliWatchShouldTriggerForChangedPath>(
                programType,
                "CliWatchShouldTriggerForChangedPath"),
            DogfoodKernelLoader.CreateDelegate<CliWatchTargetSummaryInto>(
                programType,
                "CliWatchTargetSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliWatchPositiveIntInto>(
                programType,
                "CliWatchPositiveIntInto"),
            DogfoodKernelLoader.CreateDelegate<CliWatchTargetCommandName>(
                programType,
                "CliWatchTargetCommandName"),
            DogfoodKernelLoader.CreateDelegate<CliWatchHelpText>(
                programType,
                "CliWatchHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliWatchUnsupportedTargetMessage>(
                programType,
                "CliWatchUnsupportedTargetMessage"),
            DogfoodKernelLoader.CreateDelegate<CliWatchProjectDirectoryNotFoundMessage>(
                programType,
                "CliWatchProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliWatchPositiveIntExpectedMessage>(
                programType,
                "CliWatchPositiveIntExpectedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliWatchStartedMessage>(
                programType,
                "CliWatchStartedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliWatchChangeDetectedMessage>(
                programType,
                "CliWatchChangeDetectedMessage")));

    private delegate int CliWatchOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliWatchForwardedArgIndicesInto(string[] args, int[] resultIndices);

    private delegate int CliWatchShouldTriggerForChangedPath(string path);

    private delegate int CliWatchTargetSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliWatchPositiveIntInto(string value, int[] result);

    private delegate string CliWatchTargetCommandName(int targetKind);

    private delegate string CliWatchHelpText();

    private delegate string CliWatchUnsupportedTargetMessage(string target);

    private delegate string CliWatchProjectDirectoryNotFoundMessage(string projectRoot);

    private delegate string CliWatchPositiveIntExpectedMessage(string flag);

    private delegate string CliWatchStartedMessage(string projectRoot);

    private delegate string CliWatchChangeDetectedMessage(string timeText, string watchedCommand);

    private sealed record Bindings(
        CliWatchOptionSummaryInto OptionSummary,
        CliWatchForwardedArgIndicesInto WatchForwardedArgIndices,
        CliWatchShouldTriggerForChangedPath WatchShouldTriggerForChangedPath,
        CliWatchTargetSummaryInto TargetSummary,
        CliWatchPositiveIntInto PositiveInt,
        CliWatchTargetCommandName WatchTargetCommandName,
        CliWatchHelpText WatchHelpText,
        CliWatchUnsupportedTargetMessage WatchUnsupportedTargetMessage,
        CliWatchProjectDirectoryNotFoundMessage WatchProjectDirectoryNotFoundMessage,
        CliWatchPositiveIntExpectedMessage WatchPositiveIntExpectedMessage,
        CliWatchStartedMessage WatchStartedMessage,
        CliWatchChangeDetectedMessage WatchChangeDetectedMessage);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# watch command kernels are unavailable.");

    internal static bool TryShouldTriggerForChangedPath(string path, out bool shouldTrigger)
    {
        shouldTrigger = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.WatchShouldTriggerForChangedPath(path);
            if (code == 0)
                return true;

            if (code == 1)
            {
                shouldTrigger = true;
                return true;
            }

            return false;
        }
        catch
        {
            shouldTrigger = false;
            return false;
        }
    }

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
