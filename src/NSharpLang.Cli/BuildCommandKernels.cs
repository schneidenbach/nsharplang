using System;

namespace NSharpLang.Cli;

internal static class BuildCommandKernels
{
    [ThreadStatic]
    private static OperandScratch? t_operandScratch;

    [ThreadStatic]
    private static int[]? t_optionResultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static (int Count, int FirstOperandIndex) GetOperandSummary(string[] args)
    {
        var scratch = t_operandScratch ??= new OperandScratch();
        scratch.EnsureCapacity(args.Length);

        var count = RequiredBindings.BuildOperandSummary(
            args,
            scratch.KindIds,
            scratch.NextIndices,
            scratch.PreviousIndices,
            scratch.NextOptionIndices,
            scratch.ResultIndices);
        if (count < 0 || count > args.Length)
            throw new InvalidOperationException("N# build operand summary kernel rejected the arguments.");

        var firstOperandIndex = count > 0 ? scratch.ResultIndices[0] : -1;
        if ((count > 0 && firstOperandIndex < 0) || firstOperandIndex < -1 || firstOperandIndex >= args.Length)
            throw new InvalidOperationException("N# build operand summary kernel rejected the arguments.");

        return (count, firstOperandIndex);
    }

    internal static BuildOptionSummary GetOptionSummary(string[] args)
    {
        var resultIndices = t_optionResultIndices ??= new int[9];
        var code = RequiredBindings.BuildOptionSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# build option summary kernel rejected the arguments.");

        var output = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        var backend = resultIndices[1] == -1 ? null : args[resultIndices[1]];
        var project = resultIndices[2] == -1 ? null : args[resultIndices[2]];
        return new BuildOptionSummary(
            output,
            backend,
            project,
            resultIndices[3] != 0,
            resultIndices[4] != 0,
            resultIndices[5] != 0,
            resultIndices[6] != 0,
            resultIndices[7] != 0,
            resultIndices[8] != 0);
    }

    internal static string GetHelpText()
        => RequiredBindings.BuildHelpText();

    internal static string GetFileNotFoundMessage(string sourceFile)
        => RequiredBindings.BuildFileNotFoundMessage(sourceFile);

    internal static string GetFailedMessage(string message)
        => RequiredBindings.BuildFailedMessage(message);

    internal static string GetProjectStartMessage(string projectRoot)
        => RequiredBindings.BuildProjectStartMessage(projectRoot);

    internal static string GetSingleFileStartMessage(string sourceFile)
        => RequiredBindings.BuildSingleFileStartMessage(sourceFile);

    internal static string GetMissingProjectFileMessage()
        => RequiredBindings.BuildMissingProjectFileMessage();

    internal static string GetFailedElapsedMessage(string elapsedText)
        => RequiredBindings.BuildFailedElapsedMessage(elapsedText);

    internal static string GetSuccessElapsedMessage(bool release, string elapsedText)
        => RequiredBindings.BuildSuccessElapsedMessage(release ? 1 : 0, elapsedText);

    internal static string GetSuccessMessage(bool release)
        => RequiredBindings.BuildSuccessMessage(release ? 1 : 0);

    internal static string GetOutputPathMessage(string outputPath)
        => RequiredBindings.BuildOutputPathMessage(outputPath);

    internal static string GetTimingsMessage(string resolveElapsed, string compileElapsed, string totalElapsed)
        => RequiredBindings.BuildTimingsMessage(resolveElapsed, compileElapsed, totalElapsed);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# build command kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliBuildOperandSummaryInto>(
                programType,
                "CliBuildOperandSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliBuildOptionSummaryInto>(
                programType,
                "CliBuildOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliBuildHelpText>(
                programType,
                "CliBuildHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliBuildFileNotFoundMessage>(
                programType,
                "CliBuildFileNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildFailedMessage>(
                programType,
                "CliBuildFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildProjectStartMessage>(
                programType,
                "CliBuildProjectStartMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildSingleFileStartMessage>(
                programType,
                "CliBuildSingleFileStartMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildMissingProjectFileMessage>(
                programType,
                "CliBuildMissingProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildFailedElapsedMessage>(
                programType,
                "CliBuildFailedElapsedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildSuccessElapsedMessage>(
                programType,
                "CliBuildSuccessElapsedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildSuccessMessage>(
                programType,
                "CliBuildSuccessMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildOutputPathMessage>(
                programType,
                "CliBuildOutputPathMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBuildTimingsMessage>(
                programType,
                "CliBuildTimingsMessage")));

    private delegate int CliBuildOperandSummaryInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private delegate int CliBuildOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate string CliBuildHelpText();
    private delegate string CliBuildFileNotFoundMessage(string sourceFile);
    private delegate string CliBuildFailedMessage(string message);
    private delegate string CliBuildProjectStartMessage(string projectRoot);
    private delegate string CliBuildSingleFileStartMessage(string sourceFile);
    private delegate string CliBuildMissingProjectFileMessage();
    private delegate string CliBuildFailedElapsedMessage(string elapsedText);
    private delegate string CliBuildSuccessElapsedMessage(int release, string elapsedText);
    private delegate string CliBuildSuccessMessage(int release);
    private delegate string CliBuildOutputPathMessage(string outputPath);
    private delegate string CliBuildTimingsMessage(string resolveElapsed, string compileElapsed, string totalElapsed);

    private sealed record Bindings(
        CliBuildOperandSummaryInto BuildOperandSummary,
        CliBuildOptionSummaryInto BuildOptionSummary,
        CliBuildHelpText BuildHelpText,
        CliBuildFileNotFoundMessage BuildFileNotFoundMessage,
        CliBuildFailedMessage BuildFailedMessage,
        CliBuildProjectStartMessage BuildProjectStartMessage,
        CliBuildSingleFileStartMessage BuildSingleFileStartMessage,
        CliBuildMissingProjectFileMessage BuildMissingProjectFileMessage,
        CliBuildFailedElapsedMessage BuildFailedElapsedMessage,
        CliBuildSuccessElapsedMessage BuildSuccessElapsedMessage,
        CliBuildSuccessMessage BuildSuccessMessage,
        CliBuildOutputPathMessage BuildOutputPathMessage,
        CliBuildTimingsMessage BuildTimingsMessage);

    private sealed class OperandScratch
    {
        internal int[] KindIds = Array.Empty<int>();
        internal int[] NextIndices = Array.Empty<int>();
        internal int[] NextOptionIndices = Array.Empty<int>();
        internal int[] PreviousIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
                KindIds = new int[count];

            if (NextIndices.Length != count)
                NextIndices = new int[count];

            if (NextOptionIndices.Length != count)
                NextOptionIndices = new int[count];

            if (PreviousIndices.Length != count)
                PreviousIndices = new int[count];

            if (ResultIndices.Length != count)
                ResultIndices = new int[count];
        }
    }
}
