using System;

namespace NSharpLang.Cli;

internal static class BuildCommandKernels
{
    [ThreadStatic]
    private static OperandScratch? t_operandScratch;

    [ThreadStatic]
    private static int[]? t_optionResultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOperandSummary(string[] args, out int count, out int firstOperandIndex)
    {
        count = 0;
        firstOperandIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_operandScratch ??= new OperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            count = bindings.BuildOperandSummary(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (count < 0 || count > args.Length)
            {
                count = 0;
                firstOperandIndex = -1;
                return false;
            }

            firstOperandIndex = count > 0 ? scratch.ResultIndices[0] : -1;
            if ((count > 0 && firstOperandIndex < 0) || firstOperandIndex < -1 || firstOperandIndex >= args.Length)
            {
                count = 0;
                firstOperandIndex = -1;
                return false;
            }

            return true;
        }
        catch
        {
            count = 0;
            firstOperandIndex = -1;
            return false;
        }
    }

    internal static bool TryGetOptionSummary(string[] args, out BuildOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionResultIndices ??= new int[9];
        try
        {
            var code = bindings.BuildOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var output)
                || !TryGetOptionalArg(args, resultIndices[1], out var backend)
                || !TryGetOptionalArg(args, resultIndices[2], out var project))
            {
                summary = default;
                return false;
            }

            summary = new BuildOptionSummary(
                output,
                backend,
                project,
                resultIndices[3] != 0,
                resultIndices[4] != 0,
                resultIndices[5] != 0,
                resultIndices[6] != 0,
                resultIndices[7] != 0,
                resultIndices[8] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.BuildHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetFileNotFoundMessage(string sourceFile)
    {
        if (TryGetMessage(bindings => bindings.BuildFileNotFoundMessage(sourceFile), out var message))
            return message;

        return GetFileNotFoundMessageWithCSharp(sourceFile);
    }

    internal static string GetFailedMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.BuildFailedMessage(message), out var result))
            return result;

        return GetFailedMessageWithCSharp(message);
    }

    internal static string GetProjectStartMessage(string projectRoot)
    {
        if (TryGetMessage(bindings => bindings.BuildProjectStartMessage(projectRoot), out var message))
            return message;

        return GetProjectStartMessageWithCSharp(projectRoot);
    }

    internal static string GetSingleFileStartMessage(string sourceFile)
    {
        if (TryGetMessage(bindings => bindings.BuildSingleFileStartMessage(sourceFile), out var message))
            return message;

        return GetSingleFileStartMessageWithCSharp(sourceFile);
    }

    internal static string GetMissingProjectFileMessage()
    {
        if (TryGetMessage(bindings => bindings.BuildMissingProjectFileMessage(), out var message))
            return message;

        return GetMissingProjectFileMessageWithCSharp();
    }

    internal static string GetFailedElapsedMessage(string elapsedText)
    {
        if (TryGetMessage(bindings => bindings.BuildFailedElapsedMessage(elapsedText), out var message))
            return message;

        return GetFailedElapsedMessageWithCSharp(elapsedText);
    }

    internal static string GetSuccessElapsedMessage(bool release, string elapsedText)
    {
        if (TryGetMessage(bindings => bindings.BuildSuccessElapsedMessage(release ? 1 : 0, elapsedText), out var message))
            return message;

        return GetSuccessElapsedMessageWithCSharp(release, elapsedText);
    }

    internal static string GetSuccessMessage(bool release)
    {
        if (TryGetMessage(bindings => bindings.BuildSuccessMessage(release ? 1 : 0), out var message))
            return message;

        return GetSuccessMessageWithCSharp(release);
    }

    internal static string GetOutputPathMessage(string outputPath)
    {
        if (TryGetMessage(bindings => bindings.BuildOutputPathMessage(outputPath), out var message))
            return message;

        return GetOutputPathMessageWithCSharp(outputPath);
    }

    internal static string GetTimingsMessage(string resolveElapsed, string compileElapsed, string totalElapsed)
    {
        if (TryGetMessage(bindings => bindings.BuildTimingsMessage(resolveElapsed, compileElapsed, totalElapsed), out var message))
            return message;

        return GetTimingsMessageWithCSharp(resolveElapsed, compileElapsed, totalElapsed);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product build messages route through CliBuild* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Build\n"
           + "\n"
           + "Usage: nlc build [file.nl] [options]\n"
           + "\n"
           + "Build a project or a single N# source file.\n"
           + "\n"
           + "When run in a directory with project.yml, compiles directly from project.yml\n"
           + "through the native IL backend. No user-authored .csproj is needed.\n"
           + "\n"
           + "Options:\n"
           + "  --backend <mode>   Compilation backend: il\n"
           + "  --project <dir>    Project root directory (default: current directory)\n"
           + "  --release          Build with Release configuration/output layout (default: Debug)\n"
           + "  --verbose          Show detailed build output\n"
           + "  --timings          Emit per-phase timing breakdown after build\n"
           + "  --perf-report      Emit a versioned JSON performance report after build\n"
           + "  --aot              Analyze for Native AOT safety; AOT blockers become build errors\n"
           + "  --output <path>    Output directory for build artifacts (-o shorthand)\n"
           + "  --define <symbol>  Define a conditional-compilation symbol for #if (-d shorthand);\n"
           + "                     repeatable, and accepts comma-separated lists\n"
           + "  --help, -h         Show this help text\n"
           + "\n"
           + "Conditional compilation:\n"
           + "  DEBUG is defined automatically for debug builds (omitted with --release).\n"
           + "  Project-wide symbols can also be set via 'defines:' in project.yml.\n"
           + "\n"
           + "Examples:\n"
           + "  nlc build              Build the current project\n"
           + "  nlc build --backend il Build the current project with the IL backend\n"
           + "  nlc build --release    Release configuration/output layout\n"
           + "  nlc build --verbose    Show detailed build output\n"
           + "  nlc build --timings    Show phase-level timing breakdown\n"
           + "  nlc build --perf-report Emit a JSON performance report\n"
           + "  nlc build --aot        Fail the build on Native AOT blockers\n"
           + "  nlc build -o ./dist    Build to a specific output directory\n"
           + "  nlc build --define FEATURE_X  Build with FEATURE_X defined\n"
           + "  nlc build Program.nl   Build a single file\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Build succeeded\n"
           + "  1  Build failed";

    private static string GetFileNotFoundMessageWithCSharp(string sourceFile)
        => $"File not found: {sourceFile}";

    private static string GetFailedMessageWithCSharp(string message)
        => $"Build failed: {message}";

    private static string GetProjectStartMessageWithCSharp(string projectRoot)
        => $"Building project in {projectRoot} with the IL backend...";

    private static string GetSingleFileStartMessageWithCSharp(string sourceFile)
        => $"Building {sourceFile} with the IL backend...";

    private static string GetMissingProjectFileMessageWithCSharp()
        => "No project.yml found in current directory. Run 'nlc new <name>' to create a project, or use 'nlc build <file.nl>' for a single file.";

    private static string GetFailedElapsedMessageWithCSharp(string elapsedText)
        => $"  Build failed in {elapsedText}";

    private static string GetSuccessElapsedMessageWithCSharp(bool release, string elapsedText)
        => $"Build successful! (il, {(release ? "release" : "debug")}) [{elapsedText}]";

    private static string GetSuccessMessageWithCSharp(bool release)
        => $"Build successful! (il, {(release ? "release" : "debug")})";

    private static string GetOutputPathMessageWithCSharp(string outputPath)
        => $"Output: {outputPath}";

    private static string GetTimingsMessageWithCSharp(string resolveElapsed, string compileElapsed, string totalElapsed)
        => "Build timings:\n"
           + $"  Resolve:    {resolveElapsed}\n"
           + $"  Emit IL:    {compileElapsed}\n"
           + $"  Total:      {totalElapsed}";

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
