using System;

namespace NSharpLang.Cli;

internal readonly record struct RunOptionSummary(
    string? BackendOption,
    bool ShowHelp);

internal static class RunCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static RunOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionSummaryIndices ??= new int[2];
        var code = RequiredBindings.RunOptionSummary(args, resultIndices);
        if (code != 0 || !TryGetOptionalArg(args, resultIndices[0], out var backendOption))
            throw new InvalidOperationException("N# run option summary kernel rejected the arguments.");

        return new RunOptionSummary(
            backendOption,
            resultIndices[1] != 0);
    }

    internal static bool TryGetSourceOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.RunFirstOperandIndex(args);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            operand = args[index];
            return true;
        }
        catch
        {
            operand = null;
            return false;
        }
    }

    internal static string GetHelpText()
        => RequiredBindings.RunHelpText();

    internal static string GetFileNotFoundMessage(string sourceFile)
        => RequiredBindings.RunFileNotFoundMessage(sourceFile);

    internal static string GetSourceStartingMessage(string sourceFile)
        => RequiredBindings.RunSourceStartingMessage(sourceFile);

    internal static string GetMissingProjectFileMessage()
        => RequiredBindings.RunMissingProjectFileMessage();

    internal static string GetLibraryProjectMessage()
        => RequiredBindings.RunLibraryProjectMessage();

    internal static string GetProjectStartingMessage()
        => RequiredBindings.RunProjectStartingMessage();

    internal static string GetSingleFileBackendStartMessage(string sourceFile)
        => RequiredBindings.RunSingleFileBackendStartMessage(sourceFile);

    internal static string GetLibrarySourceFileMessage()
        => RequiredBindings.RunLibrarySourceFileMessage();

    internal static string GetFailedMessage(string message)
        => RequiredBindings.RunFailedMessage(message);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# run command kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliRunOptionSummaryInto>(
                programType,
                "CliRunOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliRunFirstOperandIndex>(
                programType,
                "CliRunFirstOperandIndex"),
            DogfoodKernelLoader.CreateDelegate<CliRunHelpText>(
                programType,
                "CliRunHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliRunFileNotFoundMessage>(
                programType,
                "CliRunFileNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRunSourceStartingMessage>(
                programType,
                "CliRunSourceStartingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRunMissingProjectFileMessage>(
                programType,
                "CliRunMissingProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRunLibraryProjectMessage>(
                programType,
                "CliRunLibraryProjectMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRunProjectStartingMessage>(
                programType,
                "CliRunProjectStartingMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRunSingleFileBackendStartMessage>(
                programType,
                "CliRunSingleFileBackendStartMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRunLibrarySourceFileMessage>(
                programType,
                "CliRunLibrarySourceFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliRunFailedMessage>(
                programType,
                "CliRunFailedMessage")));

    private delegate int CliRunOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliRunFirstOperandIndex(string[] args);

    private delegate string CliRunHelpText();
    private delegate string CliRunFileNotFoundMessage(string sourceFile);
    private delegate string CliRunSourceStartingMessage(string sourceFile);
    private delegate string CliRunMissingProjectFileMessage();
    private delegate string CliRunLibraryProjectMessage();
    private delegate string CliRunProjectStartingMessage();
    private delegate string CliRunSingleFileBackendStartMessage(string sourceFile);
    private delegate string CliRunLibrarySourceFileMessage();
    private delegate string CliRunFailedMessage(string message);

    private sealed record Bindings(
        CliRunOptionSummaryInto RunOptionSummary,
        CliRunFirstOperandIndex RunFirstOperandIndex,
        CliRunHelpText RunHelpText,
        CliRunFileNotFoundMessage RunFileNotFoundMessage,
        CliRunSourceStartingMessage RunSourceStartingMessage,
        CliRunMissingProjectFileMessage RunMissingProjectFileMessage,
        CliRunLibraryProjectMessage RunLibraryProjectMessage,
        CliRunProjectStartingMessage RunProjectStartingMessage,
        CliRunSingleFileBackendStartMessage RunSingleFileBackendStartMessage,
        CliRunLibrarySourceFileMessage RunLibrarySourceFileMessage,
        CliRunFailedMessage RunFailedMessage);

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
