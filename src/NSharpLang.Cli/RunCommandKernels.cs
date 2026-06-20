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

    internal static bool TryGetOptionSummary(string[] args, out RunOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[2];
        try
        {
            var code = bindings.RunOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var backendOption))
            {
                summary = default;
                return false;
            }

            summary = new RunOptionSummary(
                backendOption,
                resultIndices[1] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
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
    {
        if (TryGetMessage(bindings => bindings.RunHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetFileNotFoundMessage(string sourceFile)
    {
        if (TryGetMessage(bindings => bindings.RunFileNotFoundMessage(sourceFile), out var message))
            return message;

        return GetFileNotFoundMessageWithCSharp(sourceFile);
    }

    internal static string GetSourceStartingMessage(string sourceFile)
    {
        if (TryGetMessage(bindings => bindings.RunSourceStartingMessage(sourceFile), out var message))
            return message;

        return GetSourceStartingMessageWithCSharp(sourceFile);
    }

    internal static string GetFailedMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.RunFailedMessage(message), out var result))
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product run messages route through CliRun* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Run\n"
           + "\n"
           + "Usage: nlc run [file.nl]\n"
           + "\n"
           + "Build and run either the current project or a single N# source file.\n"
           + "\n"
           + "Options:\n"
           + "  --backend <mode>   Compilation backend: il\n"
           + "  --define <symbol>  Define a conditional-compilation symbol for #if (-d shorthand);\n"
           + "                     repeatable, and accepts comma-separated lists\n"
           + "  --help, -h         Show this help text\n"
           + "\n"
           + "Conditional compilation:\n"
           + "  DEBUG is defined automatically when running (a debug build).\n"
           + "  Project-wide symbols can also be set via 'defines:' in project.yml.\n"
           + "\n"
           + "Examples:\n"
           + "  nlc run\n"
           + "  nlc run --backend il\n"
           + "  nlc run Program.nl\n"
           + "  nlc run --define FEATURE_X\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Program ran successfully\n"
           + "  1  Build or execution failed";

    private static string GetFileNotFoundMessageWithCSharp(string sourceFile)
        => $"File not found: {sourceFile}";

    private static string GetSourceStartingMessageWithCSharp(string sourceFile)
        => $"Running {sourceFile}...";

    private static string GetFailedMessageWithCSharp(string message)
        => $"Run failed: {message}";

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
            DogfoodKernelLoader.CreateDelegate<CliRunFailedMessage>(
                programType,
                "CliRunFailedMessage")));

    private delegate int CliRunOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliRunFirstOperandIndex(string[] args);

    private delegate string CliRunHelpText();
    private delegate string CliRunFileNotFoundMessage(string sourceFile);
    private delegate string CliRunSourceStartingMessage(string sourceFile);
    private delegate string CliRunFailedMessage(string message);

    private sealed record Bindings(
        CliRunOptionSummaryInto RunOptionSummary,
        CliRunFirstOperandIndex RunFirstOperandIndex,
        CliRunHelpText RunHelpText,
        CliRunFileNotFoundMessage RunFileNotFoundMessage,
        CliRunSourceStartingMessage RunSourceStartingMessage,
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
