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
        => RequiredBindings.CleanHelpText();

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
        => RequiredBindings.CleanProjectDirectoryNotFoundMessage(projectRoot);

    internal static string GetNoArtifactsFoundMessage(string projectRoot)
        => RequiredBindings.CleanNoArtifactsFoundMessage(projectRoot);

    internal static string GetRemovedArtifactsHeader(int count)
        => RequiredBindings.CleanRemovedArtifactsHeader(count, count.ToString());

    internal static string GetRemovedArtifactLine(string path)
        => RequiredBindings.CleanRemovedArtifactLine(path);

    internal static string GetClearedNuGetCachesMessage()
        => RequiredBindings.CleanClearedNuGetCachesMessage();

    internal static string GetClearNuGetCachesFailedMessage(string detail)
        => RequiredBindings.CleanClearNuGetCachesFailedMessage(detail);

    internal static string GetCleanFailedMessage(string message)
        => RequiredBindings.CleanFailedMessage(message);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# clean command kernels are unavailable.");

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
