using System;
using System.Linq;
using NSharpLang.Compiler;

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
    {
        if (TryGetMessage(bindings => bindings.InitHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetInvalidTypeMessage(string type)
    {
        if (TryGetMessage(bindings => bindings.InitInvalidTypeMessage(type), out var message))
            return message;

        return GetInvalidTypeMessageWithCSharp(type);
    }

    internal static string GetProjectFileExistsMessage()
    {
        if (TryGetMessage(bindings => bindings.InitProjectFileExistsMessage(), out var message))
            return message;

        return GetProjectFileExistsMessageWithCSharp();
    }

    internal static string GetCreatedFileMessage(string sourceFile)
    {
        if (TryGetMessage(bindings => bindings.InitCreatedFileMessage(sourceFile), out var message))
            return message;

        return GetCreatedFileMessageWithCSharp(sourceFile);
    }

    internal static string GetSuccessMessage()
    {
        if (TryGetMessage(bindings => bindings.InitSuccessMessage(), out var message))
            return message;

        return GetSuccessMessageWithCSharp();
    }

    internal static string GetFailedMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.InitFailedMessage(message), out var result))
            return result;

        return GetFailedMessageWithCSharp(message);
    }

    internal static string GetProjectYamlText(string projectName, string projectType)
    {
        if (TryGetMessage(bindings => bindings.InitProjectYamlText(projectName, projectType), out var text))
            return text;

        return GetProjectYamlTextWithCSharp(projectName, projectType);
    }

    internal static string GetCsprojText()
    {
        if (TryGetMessage(bindings => bindings.InitCsprojText(), out var text))
            return text;

        return GetCsprojTextWithCSharp();
    }

    internal static string GetProgramSourceText()
    {
        if (TryGetMessage(bindings => bindings.InitProgramSourceText(), out var text))
            return text;

        return GetProgramSourceTextWithCSharp();
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product init command messages route through CliInit* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Init\n"
           + "\n"
           + "Usage: nlc init [options]\n"
           + "\n"
           + "Initialize N# in the current directory. Like 'cargo init' — works in an\n"
           + "existing directory instead of creating a new one.\n"
           + "\n"
           + "Options:\n"
           + "  --name <name>   Project name (default: current directory name)\n"
           + "  --type <type>   Output type: exe or library (default: exe)\n"
           + "  --force         Overwrite existing project.yml\n"
           + "  --help, -h      Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc init\n"
           + "  nlc init --name MyLib --type library\n"
           + "  nlc init --force\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Project initialized successfully\n"
           + "  1  Initialization failed";

    private static string GetInvalidTypeMessageWithCSharp(string type)
        => $"Invalid type '{type}'. Expected 'exe' or 'library'.";

    private static string GetProjectFileExistsMessageWithCSharp()
        => "project.yml already exists. Use --force to overwrite.";

    private static string GetCreatedFileMessageWithCSharp(string sourceFile)
        => $"Created: {sourceFile}";

    private static string GetSuccessMessageWithCSharp()
        => "N# project initialized. Run 'nlc build' to compile.";

    private static string GetFailedMessageWithCSharp(string message)
        => $"Init failed: {message}";

    // Stage 6 C#-surface-shrink: fallback/oracle only; product init file content routes through CliInit* kernels.
    private static string GetProjectYamlTextWithCSharp(string projectName, string projectType)
    {
        var template = ProjectFileParser.GenerateTemplate(projectName);
        if (projectType == "library")
        {
            template = template.Replace("outputType: exe", "outputType: library");
            template = string.Join("\n", template.Split('\n')
                .Where(line => !line.TrimStart().StartsWith("entry:", StringComparison.Ordinal)));
        }

        return template;
    }

    private static string GetCsprojTextWithCSharp()
        => "<Project Sdk=\"NSharpLang.Sdk\" />\n";

    private static string GetProgramSourceTextWithCSharp()
        => "func main() {\n    print \"Hello, N#!\"\n}";

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
