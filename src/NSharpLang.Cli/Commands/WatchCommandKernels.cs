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

    internal static WatchTargetSummary GetTargetSummary(string[] args)
    {
        var resultIndices = t_targetSummaryIndices ??= new int[1];
        var code = RequiredBindings.TargetSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# watch target summary kernel rejected the arguments.");

        var targetKindValue = resultIndices[0];
        if (targetKindValue < 0 || targetKindValue > 5)
            throw new InvalidOperationException("N# watch target summary kernel rejected the arguments.");

        return new WatchTargetSummary((WatchTargetKind)targetKindValue);
    }

    internal static WatchOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[4];
        var code = RequiredBindings.OptionSummary(args, resultIndices);
        if (code != 0
            || !TryGetOptionalArg(args, resultIndices[0], out var projectOption)
            || !TryGetOptionalArg(args, resultIndices[1], out var debounceMsOption)
            || !TryGetOptionalArg(args, resultIndices[2], out var maxRunsOption))
        {
            throw new InvalidOperationException("N# watch option summary kernel rejected the arguments.");
        }

        return new WatchOptionSummary(
            projectOption,
            debounceMsOption,
            maxRunsOption,
            resultIndices[3] != 0);
    }

    internal static string[] GetForwardedArgs(string[] args)
    {
        var resultIndices = t_resultIndices;
        if (resultIndices == null || resultIndices.Length < args.Length)
        {
            resultIndices = new int[args.Length];
            t_resultIndices = resultIndices;
        }

        var count = RequiredBindings.WatchForwardedArgIndices(args, resultIndices);
        if (count < 0 || count > args.Length)
            throw new InvalidOperationException("N# watch forwarded-argument kernel rejected the arguments.");

        var forwardedArgs = new string[count];
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = resultIndices[i];
            if (sourceIndex <= 0 || sourceIndex >= args.Length)
                throw new InvalidOperationException("N# watch forwarded-argument kernel rejected the arguments.");

            forwardedArgs[i] = args[sourceIndex];
        }

        return forwardedArgs;
    }

    internal static int ParsePositiveInt(string value)
    {
        var result = t_positiveIntResult ??= new int[1];
        var code = RequiredBindings.PositiveInt(value, result);
        if (code is not 0 and not 1)
            throw new InvalidOperationException("N# watch positive-integer kernel rejected the value.");

        return result[0];
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

    internal static bool ShouldTriggerForChangedPath(string path)
    {
        var code = RequiredBindings.WatchShouldTriggerForChangedPath(path);
        if (code == 0)
            return false;

        if (code == 1)
            return true;

        throw new InvalidOperationException("N# watch changed-path kernel rejected the path.");
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
