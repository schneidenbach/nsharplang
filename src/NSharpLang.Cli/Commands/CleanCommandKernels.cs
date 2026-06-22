using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct CleanOptionSummary(
    string? ProjectOption,
    bool CleanAll,
    bool ShowHelp);

internal static class CleanCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out CleanOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[3];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption))
            {
                summary = default;
                return false;
            }

            summary = new CleanOptionSummary(
                projectOption,
                resultIndices[1] != 0,
                resultIndices[2] != 0);
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
        if (TryGetMessage(bindings => bindings.CleanHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
    {
        if (TryGetMessage(bindings => bindings.CleanProjectDirectoryNotFoundMessage(projectRoot), out var message))
            return message;

        return GetProjectDirectoryNotFoundMessageWithCSharp(projectRoot);
    }

    internal static string GetNoArtifactsFoundMessage(string projectRoot)
    {
        if (TryGetMessage(bindings => bindings.CleanNoArtifactsFoundMessage(projectRoot), out var message))
            return message;

        return GetNoArtifactsFoundMessageWithCSharp(projectRoot);
    }

    internal static string GetRemovedArtifactsHeader(int count)
    {
        if (TryGetMessage(bindings => bindings.CleanRemovedArtifactsHeader(count, count.ToString()), out var message))
            return message;

        return GetRemovedArtifactsHeaderWithCSharp(count);
    }

    internal static string GetRemovedArtifactLine(string path)
    {
        if (TryGetMessage(bindings => bindings.CleanRemovedArtifactLine(path), out var message))
            return message;

        return GetRemovedArtifactLineWithCSharp(path);
    }

    internal static string GetClearedNuGetCachesMessage()
    {
        if (TryGetMessage(bindings => bindings.CleanClearedNuGetCachesMessage(), out var message))
            return message;

        return GetClearedNuGetCachesMessageWithCSharp();
    }

    internal static string GetClearNuGetCachesFailedMessage(string detail)
    {
        if (TryGetMessage(bindings => bindings.CleanClearNuGetCachesFailedMessage(detail), out var message))
            return message;

        return GetClearNuGetCachesFailedMessageWithCSharp(detail);
    }

    internal static string GetCleanFailedMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.CleanFailedMessage(message), out var result))
            return result;

        return GetCleanFailedMessageWithCSharp(message);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product clean command messages and artifact lines route through CliClean* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Clean\n"
           + "\n"
           + "Usage: nlc clean [options]\n"
           + "\n"
           + "Remove local build artifacts for the current project. Equivalent to `cargo clean`\n"
           + "or `go clean`.\n"
           + "\n"
           + "Options:\n"
           + "  --project <dir>   Project root directory (default: current directory)\n"
           + "  --all             Also clear NuGet caches\n"
           + "  --help, -h        Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc clean\n"
           + "  nlc clean --all\n"
           + "  nlc clean --project examples/16-task-cli\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Clean completed successfully\n"
           + "  1  Clean failed";

    private static string GetProjectDirectoryNotFoundMessageWithCSharp(string projectRoot)
        => $"Project directory not found: {projectRoot}";

    private static string GetNoArtifactsFoundMessageWithCSharp(string projectRoot)
        => $"No build artifacts found under {projectRoot}.";

    private static string GetRemovedArtifactsHeaderWithCSharp(int count)
        => $"Removed {count} build artifact director{(count == 1 ? "y" : "ies")}:";

    private static string GetRemovedArtifactLineWithCSharp(string path)
        => $"  {path}";

    private static string GetClearedNuGetCachesMessageWithCSharp()
        => "Cleared NuGet caches.";

    private static string GetClearNuGetCachesFailedMessageWithCSharp(string detail)
        => string.IsNullOrEmpty(detail)
            ? "Failed to clear NuGet caches."
            : $"Failed to clear NuGet caches.\n{detail}";

    private static string GetCleanFailedMessageWithCSharp(string message)
        => $"Clean failed: {message}";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliCleanOptionSummaryInto>(
                programType,
                "CliCleanOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliCleanHelpText>(
                programType,
                "CliCleanHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliCleanProjectDirectoryNotFoundMessage>(
                programType,
                "CliCleanProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCleanNoArtifactsFoundMessage>(
                programType,
                "CliCleanNoArtifactsFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCleanRemovedArtifactsHeader>(
                programType,
                "CliCleanRemovedArtifactsHeader"),
            DogfoodKernelLoader.CreateDelegate<CliCleanRemovedArtifactLine>(
                programType,
                "CliCleanRemovedArtifactLine"),
            DogfoodKernelLoader.CreateDelegate<CliCleanClearedNuGetCachesMessage>(
                programType,
                "CliCleanClearedNuGetCachesMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCleanClearNuGetCachesFailedMessage>(
                programType,
                "CliCleanClearNuGetCachesFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliCleanFailedMessage>(
                programType,
                "CliCleanFailedMessage")));

    private delegate int CliCleanOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate string CliCleanHelpText();
    private delegate string CliCleanProjectDirectoryNotFoundMessage(string projectRoot);
    private delegate string CliCleanNoArtifactsFoundMessage(string projectRoot);
    private delegate string CliCleanRemovedArtifactsHeader(int count, string countText);
    private delegate string CliCleanRemovedArtifactLine(string path);
    private delegate string CliCleanClearedNuGetCachesMessage();
    private delegate string CliCleanClearNuGetCachesFailedMessage(string detail);
    private delegate string CliCleanFailedMessage(string message);

    private sealed record Bindings(
        CliCleanOptionSummaryInto OptionSummary,
        CliCleanHelpText CleanHelpText,
        CliCleanProjectDirectoryNotFoundMessage CleanProjectDirectoryNotFoundMessage,
        CliCleanNoArtifactsFoundMessage CleanNoArtifactsFoundMessage,
        CliCleanRemovedArtifactsHeader CleanRemovedArtifactsHeader,
        CliCleanRemovedArtifactLine CleanRemovedArtifactLine,
        CliCleanClearedNuGetCachesMessage CleanClearedNuGetCachesMessage,
        CliCleanClearNuGetCachesFailedMessage CleanClearNuGetCachesFailedMessage,
        CliCleanFailedMessage CleanFailedMessage);

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
