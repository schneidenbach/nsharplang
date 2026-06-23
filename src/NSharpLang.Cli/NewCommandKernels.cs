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

    internal static NewArgumentSummary GetArgumentSummary(string[] args)
    {
        var resultIndices = t_resultIndices ??= new int[5];
        var code = RequiredBindings.NewArgumentSummary(args, resultIndices);
        if (code != 0)
            throw new InvalidOperationException("N# new argument summary kernel rejected the arguments.");

        var firstPositional = resultIndices[0] == -1 ? null : args[resultIndices[0]];
        var secondPositional = resultIndices[1] == -1 ? null : args[resultIndices[1]];
        var templateOption = resultIndices[2] == -1 ? null : args[resultIndices[2]];
        return new NewArgumentSummary(
            firstPositional,
            secondPositional,
            templateOption,
            resultIndices[3] != 0,
            resultIndices[4] != 0);
    }

    internal static NewProjectTemplateKind NormalizeTemplateKind(string value)
    {
        var result = RequiredBindings.NewTemplateKind(value);
        if (result is < 0 or > 6)
            throw new InvalidOperationException("N# new template normalization kernel rejected the template.");

        return (NewProjectTemplateKind)result;
    }

    internal static NewProjectTemplateKind ResolveTemplateKind(string value, bool systems)
    {
        var result = RequiredBindings.NewEffectiveTemplateKind(value, systems ? 1 : 0);
        if (result is < 0 or > 6)
            throw new InvalidOperationException("N# new template resolution kernel rejected the template.");

        return (NewProjectTemplateKind)result;
    }

    internal static NewTemplateSourceFileKind[] GetTemplateSourceFileKinds(string template)
    {
        var resultKinds = t_sourceFileKinds ??= new int[2];
        var count = RequiredBindings.NewTemplateSourceFileKinds(template, resultKinds);
        if (count < 0 || count > resultKinds.Length)
            throw new InvalidOperationException("N# new template source manifest kernel rejected the template.");

        var kinds = new NewTemplateSourceFileKind[count];
        for (var i = 0; i < count; i++)
        {
            if (resultKinds[i] is < 1 or > 7)
                throw new InvalidOperationException("N# new template source manifest kernel rejected the template.");

            kinds[i] = (NewTemplateSourceFileKind)resultKinds[i];
        }

        return kinds;
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

    internal static string GetProjectYamlText(string projectName, string template)
        => RequireText(RequiredBindings.NewProjectYamlText(projectName, template));

    internal static string GetGlobalJsonText()
        => RequiredBindings.NewGlobalJsonText();

    internal static string GetNuGetConfigText(string feedValue)
        => RequiredBindings.NewNuGetConfigText(feedValue);

    internal static string GetTemplateSourceText(
        string template,
        NewTemplateSourceFileKind sourceFileKind)
        => RequireText(RequiredBindings.NewTemplateSourceText(template, (int)sourceFileKind));

    private static string RequireText(string text)
        => !string.IsNullOrEmpty(text)
            ? text
            : throw new InvalidOperationException("N# new text kernel returned empty output.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
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
}
