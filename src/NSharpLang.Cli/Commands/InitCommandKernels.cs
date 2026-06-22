using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct InitOptionSummary(
    string? NameOption,
    string? TypeOption,
    bool Force,
    bool ShowHelp);

internal static class InitCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out InitOptionSummary summary)
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

            if (!TryGetOptionalArg(args, resultIndices[0], out var nameOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var typeOption))
            {
                summary = default;
                return false;
            }

            summary = new InitOptionSummary(
                nameOption,
                typeOption,
                resultIndices[2] != 0,
                resultIndices[3] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static string GetHelpText()
        => RequiredBindings.InitHelpText();

    internal static string GetInvalidTypeMessage(string type)
        => RequiredBindings.InitInvalidTypeMessage(type);

    internal static string GetProjectFileExistsMessage()
        => RequiredBindings.InitProjectFileExistsMessage();

    internal static string GetCreatedFileMessage(string sourceFile)
        => RequiredBindings.InitCreatedFileMessage(sourceFile);

    internal static string GetSuccessMessage()
        => RequiredBindings.InitSuccessMessage();

    internal static string GetFailedMessage(string message)
        => RequiredBindings.InitFailedMessage(message);

    internal static string GetProjectYamlText(string projectName, string projectType)
        => RequiredBindings.InitProjectYamlText(projectName, projectType);

    internal static string GetCsprojText()
        => RequiredBindings.InitCsprojText();

    internal static string GetProgramSourceText()
        => RequiredBindings.InitProgramSourceText();

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliInitOptionSummaryInto>(
                programType,
                "CliInitOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliInitHelpText>(
                programType,
                "CliInitHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliInitInvalidTypeMessage>(
                programType,
                "CliInitInvalidTypeMessage"),
            DogfoodKernelLoader.CreateDelegate<CliInitProjectFileExistsMessage>(
                programType,
                "CliInitProjectFileExistsMessage"),
            DogfoodKernelLoader.CreateDelegate<CliInitCreatedFileMessage>(
                programType,
                "CliInitCreatedFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliInitSuccessMessage>(
                programType,
                "CliInitSuccessMessage"),
            DogfoodKernelLoader.CreateDelegate<CliInitFailedMessage>(
                programType,
                "CliInitFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliInitProjectYamlText>(
                programType,
                "CliInitProjectYamlText"),
            DogfoodKernelLoader.CreateDelegate<CliInitCsprojText>(
                programType,
                "CliInitCsprojText"),
            DogfoodKernelLoader.CreateDelegate<CliInitProgramSourceText>(
                programType,
                "CliInitProgramSourceText")));

    private delegate int CliInitOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate string CliInitHelpText();
    private delegate string CliInitInvalidTypeMessage(string type);
    private delegate string CliInitProjectFileExistsMessage();
    private delegate string CliInitCreatedFileMessage(string sourceFile);
    private delegate string CliInitSuccessMessage();
    private delegate string CliInitFailedMessage(string message);
    private delegate string CliInitProjectYamlText(string projectName, string projectType);
    private delegate string CliInitCsprojText();
    private delegate string CliInitProgramSourceText();

    private sealed record Bindings(
        CliInitOptionSummaryInto OptionSummary,
        CliInitHelpText InitHelpText,
        CliInitInvalidTypeMessage InitInvalidTypeMessage,
        CliInitProjectFileExistsMessage InitProjectFileExistsMessage,
        CliInitCreatedFileMessage InitCreatedFileMessage,
        CliInitSuccessMessage InitSuccessMessage,
        CliInitFailedMessage InitFailedMessage,
        CliInitProjectYamlText InitProjectYamlText,
        CliInitCsprojText InitCsprojText,
        CliInitProgramSourceText InitProgramSourceText);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# init command kernels are unavailable.");

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
