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
        => RequiredBindings.NewHelpText();

    internal static string GetUsageMessage()
        => RequiredBindings.NewUsageMessage();

    internal static string GetInvalidTemplateMessage()
        => RequiredBindings.NewInvalidTemplateMessage();

    internal static string GetDirectoryExistsMessage(string projectDir)
        => RequiredBindings.NewDirectoryExistsMessage(projectDir);

    internal static string GetCreatingProjectMessage(string template, string projectName)
        => RequiredBindings.NewCreatingProjectMessage(template, projectName);

    internal static string GetCreatedFileMessage(string projectName, string file)
        => RequiredBindings.NewCreatedFileMessage(projectName, file);

    internal static string GetProjectShapeMessage()
        => RequiredBindings.NewProjectShapeMessage();

    internal static string GetNextStepsIntroMessage(string template)
        => RequiredBindings.NewNextStepsIntroMessage(template);

    internal static string GetCdCommandMessage(string projectName)
        => RequiredBindings.NewCdCommandMessage(projectName);

    internal static string GetSystemsReportCommandMessage()
        => RequiredBindings.NewSystemsReportCommandMessage();

    internal static string GetSystemsBuildCommandMessage()
        => RequiredBindings.NewSystemsBuildCommandMessage();

    internal static string GetBuildCommandMessage()
        => RequiredBindings.NewBuildCommandMessage();

    internal static string GetTestCommandMessage()
        => RequiredBindings.NewTestCommandMessage();

    internal static string GetRunCommandMessage()
        => RequiredBindings.NewRunCommandMessage();

    internal static string GetFailedMessage(string message)
        => RequiredBindings.NewFailedMessage(message);

    internal static bool TryGetProjectYamlText(string projectName, string template, out string yaml)
        => TryGetMessage(bindings => bindings.NewProjectYamlText(projectName, template), out yaml);

    internal static string GetGlobalJsonText()
        => RequiredBindings.NewGlobalJsonText();

    internal static string GetNuGetConfigText(string feedValue)
        => RequiredBindings.NewNuGetConfigText(feedValue);

    internal static bool TryGetTemplateSourceText(
        string template,
        NewTemplateSourceFileKind sourceFileKind,
        out string sourceText)
        => TryGetMessage(bindings => bindings.NewTemplateSourceText(template, (int)sourceFileKind), out sourceText);

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
                "CliNewProjectYamlText"),
            DogfoodKernelLoader.CreateDelegate<CliNewGlobalJsonText>(
                programType,
                "CliNewGlobalJsonText"),
            DogfoodKernelLoader.CreateDelegate<CliNewNuGetConfigText>(
                programType,
                "CliNewNuGetConfigText"),
            DogfoodKernelLoader.CreateDelegate<CliNewTemplateSourceText>(
                programType,
                "CliNewTemplateSourceText")));

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
    private delegate string CliNewGlobalJsonText();
    private delegate string CliNewNuGetConfigText(string feedValue);
    private delegate string CliNewTemplateSourceText(string template, int sourceFileKind);

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
        CliNewProjectYamlText NewProjectYamlText,
        CliNewGlobalJsonText NewGlobalJsonText,
        CliNewNuGetConfigText NewNuGetConfigText,
        CliNewTemplateSourceText NewTemplateSourceText);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# new command kernels are unavailable.");

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
