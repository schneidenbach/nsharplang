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
                "CliNewTemplateSourceFileKindsInto")));

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

    private sealed record Bindings(
        CliFirstPositionalArgIndex FirstPositionalArgIndex,
        CliNewArgumentSummaryInto NewArgumentSummary,
        CliNewTemplateKind NewTemplateKind,
        CliNewEffectiveTemplateKind NewEffectiveTemplateKind,
        CliNewTemplateSourceFileKindsInto NewTemplateSourceFileKinds);

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
