using System;

namespace NSharpLang.Cli;

internal readonly record struct NewArgumentSummary(
    string? FirstPositional,
    string? SecondPositional,
    string? TemplateOption,
    bool Systems,
    bool ShowHelp);

internal enum NewProjectTemplateKind
{
    Unknown = 0,
    Console = 1,
    Library = 2,
    Test = 3,
    WebApi = 4,
    SystemsCli = 5,
    SystemsLib = 6
}

internal enum NewTemplateSourceFileKind
{
    Program = 1,
    Calculator = 2,
    CalculatorTests = 3,
    WebApiController = 4,
    SystemsTests = 5,
    PacketCore = 6,
    PacketCoreTests = 7
}

internal static class NewCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;
    [ThreadStatic]
    private static int[]? t_sourceFileKinds;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out NewArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[5];
        try
        {
            var code = bindings.NewArgumentSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var firstPositional)
                || !TryGetOptionalArg(args, resultIndices[1], out var secondPositional)
                || !TryGetOptionalArg(args, resultIndices[2], out var templateOption))
            {
                summary = default;
                return false;
            }

            summary = new NewArgumentSummary(
                firstPositional,
                secondPositional,
                templateOption,
                resultIndices[3] != 0,
                resultIndices[4] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetProjectNameOperand(
        string[] args,
        string[] optionsWithValues,
        out string? projectName)
    {
        projectName = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.FirstPositionalArgIndex(args, optionsWithValues);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            projectName = args[index];
            return true;
        }
        catch
        {
            projectName = null;
            return false;
        }
    }

    internal static bool TryNormalizeTemplate(string value, out NewProjectTemplateKind templateKind)
    {
        templateKind = NewProjectTemplateKind.Unknown;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.NewTemplateKind(value);
            if (result is < 0 or > 6)
                return false;

            templateKind = (NewProjectTemplateKind)result;
            return true;
        }
        catch
        {
            templateKind = NewProjectTemplateKind.Unknown;
            return false;
        }
    }

    internal static bool TryResolveTemplate(string value, bool systems, out NewProjectTemplateKind templateKind)
    {
        templateKind = NewProjectTemplateKind.Unknown;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.NewEffectiveTemplateKind(value, systems ? 1 : 0);
            if (result is < 0 or > 6)
                return false;

            templateKind = (NewProjectTemplateKind)result;
            return true;
        }
        catch
        {
            templateKind = NewProjectTemplateKind.Unknown;
            return false;
        }
    }

    internal static bool TryGetTemplateSourceFileKinds(
        string template,
        out NewTemplateSourceFileKind[] sourceFileKinds)
    {
        sourceFileKinds = Array.Empty<NewTemplateSourceFileKind>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultKinds = t_sourceFileKinds ??= new int[2];
        try
        {
            var count = bindings.NewTemplateSourceFileKinds(template, resultKinds);
            if (count < 0 || count > resultKinds.Length)
                return false;

            var kinds = new NewTemplateSourceFileKind[count];
            for (var i = 0; i < count; i++)
            {
                if (resultKinds[i] is < 1 or > 7)
                    return false;

                kinds[i] = (NewTemplateSourceFileKind)resultKinds[i];
            }

            sourceFileKinds = kinds;
            return true;
        }
        catch
        {
            sourceFileKinds = Array.Empty<NewTemplateSourceFileKind>();
            return false;
        }
    }

    internal static string GetHelpText()
    {
        if (TryGetMessage(bindings => bindings.NewHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetUsageMessage()
    {
        if (TryGetMessage(bindings => bindings.NewUsageMessage(), out var message))
            return message;

        return GetUsageMessageWithCSharp();
    }

    internal static string GetInvalidTemplateMessage()
    {
        if (TryGetMessage(bindings => bindings.NewInvalidTemplateMessage(), out var message))
            return message;

        return GetInvalidTemplateMessageWithCSharp();
    }

    internal static string GetDirectoryExistsMessage(string projectDir)
    {
        if (TryGetMessage(bindings => bindings.NewDirectoryExistsMessage(projectDir), out var message))
            return message;

        return GetDirectoryExistsMessageWithCSharp(projectDir);
    }

    internal static string GetCreatingProjectMessage(string template, string projectName)
    {
        if (TryGetMessage(bindings => bindings.NewCreatingProjectMessage(template, projectName), out var message))
            return message;

        return GetCreatingProjectMessageWithCSharp(template, projectName);
    }

    internal static string GetCreatedFileMessage(string projectName, string file)
    {
        if (TryGetMessage(bindings => bindings.NewCreatedFileMessage(projectName, file), out var message))
            return message;

        return GetCreatedFileMessageWithCSharp(projectName, file);
    }

    internal static string GetProjectShapeMessage()
    {
        if (TryGetMessage(bindings => bindings.NewProjectShapeMessage(), out var message))
            return message;

        return GetProjectShapeMessageWithCSharp();
    }

    internal static string GetNextStepsIntroMessage(string template)
    {
        if (TryGetMessage(bindings => bindings.NewNextStepsIntroMessage(template), out var message))
            return message;

        return GetNextStepsIntroMessageWithCSharp(template);
    }

    internal static string GetCdCommandMessage(string projectName)
    {
        if (TryGetMessage(bindings => bindings.NewCdCommandMessage(projectName), out var message))
            return message;

        return GetCdCommandMessageWithCSharp(projectName);
    }

    internal static string GetSystemsReportCommandMessage()
    {
        if (TryGetMessage(bindings => bindings.NewSystemsReportCommandMessage(), out var message))
            return message;

        return GetSystemsReportCommandMessageWithCSharp();
    }

    internal static string GetSystemsBuildCommandMessage()
    {
        if (TryGetMessage(bindings => bindings.NewSystemsBuildCommandMessage(), out var message))
            return message;

        return GetSystemsBuildCommandMessageWithCSharp();
    }

    internal static string GetBuildCommandMessage()
    {
        if (TryGetMessage(bindings => bindings.NewBuildCommandMessage(), out var message))
            return message;

        return GetBuildCommandMessageWithCSharp();
    }

    internal static string GetTestCommandMessage()
    {
        if (TryGetMessage(bindings => bindings.NewTestCommandMessage(), out var message))
            return message;

        return GetTestCommandMessageWithCSharp();
    }

    internal static string GetRunCommandMessage()
    {
        if (TryGetMessage(bindings => bindings.NewRunCommandMessage(), out var message))
            return message;

        return GetRunCommandMessageWithCSharp();
    }

    internal static string GetFailedMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.NewFailedMessage(message), out var result))
            return result;

        return GetFailedMessageWithCSharp(message);
    }

    internal static bool TryGetProjectYamlText(string projectName, string template, out string yaml)
        => TryGetMessage(bindings => bindings.NewProjectYamlText(projectName, template), out yaml);

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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product new command messages route through CliNew* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# New Project\n"
           + "\n"
           + "Usage: nlc new <project-name> [--template <template>] [--systems]\n"
           + "       nlc new systems-cli <project-name>\n"
           + "       nlc new systems-lib <project-name>\n"
           + "\n"
           + "Create a new csproj-free N# project. Fresh projects are project.yml-first:\n"
           + "`nlc build`, `nlc run`, and `nlc test` build directly from project.yml.\n"
           + "Do not hand-author project build settings in .csproj.\n"
           + "\n"
           + "Options:\n"
           + "  --template <template>  Project template: console, library, test, webapi, systems-cli, systems-lib (default: console)\n"
           + "  --type <template>      Alias for --template\n"
           + "  --systems              Enable the systems profile for console/library templates\n"
           + "  --help, -h             Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc new MyApp\n"
           + "  nlc new MyLib --template library\n"
           + "  nlc new MyApi --template webapi\n"
           + "  nlc new systems-cli PacketTool\n"
           + "  nlc new PacketCore --template library --systems\n"
           + "  nlc new lib PacketCore --systems\n"
           + "  cd MyApp && nlc build\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Project created successfully\n"
           + "  1  Project creation failed";

    private static string GetUsageMessageWithCSharp()
        => "Usage: nlc new <project-name> [--template <template>]";

    private static string GetInvalidTemplateMessageWithCSharp()
        => "Invalid template. Expected one of: console, library, test, webapi, systems-cli, systems-lib.";

    private static string GetDirectoryExistsMessageWithCSharp(string projectDir)
        => $"Directory already exists: {projectDir}. Use a different name or remove the existing directory.";

    private static string GetCreatingProjectMessageWithCSharp(string template, string projectName)
        => $"Creating new {template} project: {projectName}";

    private static string GetCreatedFileMessageWithCSharp(string projectName, string file)
        => $"Created: {projectName}/{file}";

    private static string GetProjectShapeMessageWithCSharp()
        => "Project shape: csproj-free source tree; nlc builds directly from project.yml.";

    private static string GetNextStepsIntroMessageWithCSharp(string template)
        => template switch
        {
            "systems-cli" or "systems-lib" => "To check systems policy and inspect performance facts:",
            "test" => "To build and test your project:",
            "library" => "To build your project:",
            _ => "To build and run your project:",
        };

    private static string GetCdCommandMessageWithCSharp(string projectName)
        => $"  cd {projectName}";

    private static string GetSystemsReportCommandMessageWithCSharp()
        => "  nlc check --systems-report";

    private static string GetSystemsBuildCommandMessageWithCSharp()
        => "  nlc build --perf-report";

    private static string GetBuildCommandMessageWithCSharp()
        => "  nlc build";

    private static string GetTestCommandMessageWithCSharp()
        => "  nlc test";

    private static string GetRunCommandMessageWithCSharp()
        => "  nlc run";

    private static string GetFailedMessageWithCSharp(string message)
        => $"Failed to create project: {message}";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFirstPositionalArgIndex>(
                programType,
                "CliFirstPositionalArgIndex"),
            DogfoodKernelLoader.CreateDelegate<CliNewArgumentSummaryInto>(
                programType,
                "CliNewArgumentSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliNewTemplateKind>(
                programType,
                "CliNewTemplateKind"),
            DogfoodKernelLoader.CreateDelegate<CliNewEffectiveTemplateKind>(
                programType,
                "CliNewEffectiveTemplateKind"),
            DogfoodKernelLoader.CreateDelegate<CliNewTemplateSourceFileKindsInto>(
                programType,
                "CliNewTemplateSourceFileKindsInto"),
            DogfoodKernelLoader.CreateDelegate<CliNewHelpText>(
                programType,
                "CliNewHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliNewUsageMessage>(
                programType,
                "CliNewUsageMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewInvalidTemplateMessage>(
                programType,
                "CliNewInvalidTemplateMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewDirectoryExistsMessage>(
                programType,
                "CliNewDirectoryExistsMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewCreatingProjectMessage>(
                programType,
                "CliNewCreatingProjectMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewCreatedFileMessage>(
                programType,
                "CliNewCreatedFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewProjectShapeMessage>(
                programType,
                "CliNewProjectShapeMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewNextStepsIntroMessage>(
                programType,
                "CliNewNextStepsIntroMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewCdCommandMessage>(
                programType,
                "CliNewCdCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewSystemsReportCommandMessage>(
                programType,
                "CliNewSystemsReportCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewSystemsBuildCommandMessage>(
                programType,
                "CliNewSystemsBuildCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewBuildCommandMessage>(
                programType,
                "CliNewBuildCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewTestCommandMessage>(
                programType,
                "CliNewTestCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewRunCommandMessage>(
                programType,
                "CliNewRunCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewFailedMessage>(
                programType,
                "CliNewFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliNewProjectYamlText>(
                programType,
                "CliNewProjectYamlText")));

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliNewArgumentSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliNewTemplateKind(
        string value);

    private delegate int CliNewEffectiveTemplateKind(
        string value,
        int systems);

    private delegate int CliNewTemplateSourceFileKindsInto(
        string template,
        int[] resultKinds);

    private delegate string CliNewHelpText();
    private delegate string CliNewUsageMessage();
    private delegate string CliNewInvalidTemplateMessage();
    private delegate string CliNewDirectoryExistsMessage(string projectDir);
    private delegate string CliNewCreatingProjectMessage(string template, string projectName);
    private delegate string CliNewCreatedFileMessage(string projectName, string file);
    private delegate string CliNewProjectShapeMessage();
    private delegate string CliNewNextStepsIntroMessage(string template);
    private delegate string CliNewCdCommandMessage(string projectName);
    private delegate string CliNewSystemsReportCommandMessage();
    private delegate string CliNewSystemsBuildCommandMessage();
    private delegate string CliNewBuildCommandMessage();
    private delegate string CliNewTestCommandMessage();
    private delegate string CliNewRunCommandMessage();
    private delegate string CliNewFailedMessage(string message);
    private delegate string CliNewProjectYamlText(string projectName, string template);

    private sealed record Bindings(
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliNewArgumentSummaryInto NewArgumentSummary,
        CliNewTemplateKind NewTemplateKind,
        CliNewEffectiveTemplateKind NewEffectiveTemplateKind,
        CliNewTemplateSourceFileKindsInto NewTemplateSourceFileKinds,
        CliNewHelpText NewHelpText,
        CliNewUsageMessage NewUsageMessage,
        CliNewInvalidTemplateMessage NewInvalidTemplateMessage,
        CliNewDirectoryExistsMessage NewDirectoryExistsMessage,
        CliNewCreatingProjectMessage NewCreatingProjectMessage,
        CliNewCreatedFileMessage NewCreatedFileMessage,
        CliNewProjectShapeMessage NewProjectShapeMessage,
        CliNewNextStepsIntroMessage NewNextStepsIntroMessage,
        CliNewCdCommandMessage NewCdCommandMessage,
        CliNewSystemsReportCommandMessage NewSystemsReportCommandMessage,
        CliNewSystemsBuildCommandMessage NewSystemsBuildCommandMessage,
        CliNewBuildCommandMessage NewBuildCommandMessage,
        CliNewTestCommandMessage NewTestCommandMessage,
        CliNewRunCommandMessage NewRunCommandMessage,
        CliNewFailedMessage NewFailedMessage,
        CliNewProjectYamlText NewProjectYamlText);

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
