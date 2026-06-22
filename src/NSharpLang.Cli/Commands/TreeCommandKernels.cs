using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct TreeOptionSummary(
    string? ProjectOption,
    string? DepthOption,
    bool Json,
    bool ShowHelp);

internal enum TreeOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class TreeCommandKernels
{
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    [ThreadStatic]
    private static int[]? t_depthResult;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out TreeOptionSummary summary)
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

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var depthOption))
            {
                summary = default;
                return false;
            }

            summary = new TreeOptionSummary(
                projectOption,
                depthOption,
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

    internal static bool TryGetMaxDepth(string[] args, int defaultDepth, out int maxDepth)
    {
        maxDepth = defaultDepth;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_depthResult ??= new int[1];
        try
        {
            var code = bindings.MaxDepth(args, defaultDepth, result);
            if (code < 0)
                return false;

            maxDepth = result[0];
            return true;
        }
        catch
        {
            maxDepth = defaultDepth;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out TreeOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.OutputMode(json ? 1 : 0);
            if (code is < 1 or > 2)
                return false;

            outputMode = (TreeOutputModeKind)code;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

    internal static string GetHelpText()
        => RequiredBindings.TreeHelpText();

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
        => RequiredBindings.TreeProjectDirectoryNotFoundMessage(projectRoot);

    internal static string GetTreeFailedMessage(string message)
        => RequiredBindings.TreeFailedMessage(message);

    internal static string GetNoProjectFileMessage()
        => RequiredBindings.TreeNoProjectFileMessage();

    internal static string GetProjectYmlLimitationMessage()
        => RequiredBindings.TreeProjectYmlLimitationMessage();

    internal static string GetTransitiveResolutionFailedLimitation(string detail)
        => RequiredBindings.TreeTransitiveResolutionFailedLimitation(detail);

    internal static string GetDotnetRestoreRetryMessage(string detail)
        => RequiredBindings.TreeDotnetRestoreRetryMessage(detail);

    internal static string GetDotnetListFailedMessage()
        => RequiredBindings.TreeDotnetListFailedMessage();

    internal static string GetProjectHeader(string name, string targetFramework)
        => RequiredBindings.TreeProjectHeader(name, targetFramework);

    internal static string GetNoDependenciesLine()
        => RequiredBindings.TreeNoDependenciesLine();

    internal static string GetDependencyText(string name, string? version, string kind)
    {
        var versionText = string.IsNullOrWhiteSpace(version) ? string.Empty : version!;
        return RequiredBindings.TreeDependencyText(name, versionText, kind);
    }

    internal static string GetDependencyLine(bool isLast, string dependencyText)
        => RequiredBindings.TreeDependencyLine(isLast ? 1 : 0, dependencyText);

    internal static string GetTransitiveHeader(int count)
        => RequiredBindings.TreeTransitiveHeader(count.ToString());

    internal static string GetTransitiveDependencyLine(string dependencyText)
        => RequiredBindings.TreeTransitiveDependencyLine(dependencyText);

    internal static string GetLimitationsHeader()
        => RequiredBindings.TreeLimitationsHeader();

    internal static string GetLimitationLine(string limitation)
        => RequiredBindings.TreeLimitationLine(limitation);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# tree command kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliTreeOptionSummaryInto>(
                programType,
                "CliTreeOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliTreeMaxDepthInto>(
                programType,
                "CliTreeMaxDepthInto"),
            DogfoodKernelLoader.CreateDelegate<CliTreeOutputMode>(
                programType,
                "CliTreeOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliTreeHelpText>(
                programType,
                "CliTreeHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliTreeProjectDirectoryNotFoundMessage>(
                programType,
                "CliTreeProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTreeFailedMessage>(
                programType,
                "CliTreeFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTreeNoProjectFileMessage>(
                programType,
                "CliTreeNoProjectFileMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTreeProjectYmlLimitationMessage>(
                programType,
                "CliTreeProjectYmlLimitationMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTreeTransitiveResolutionFailedLimitation>(
                programType,
                "CliTreeTransitiveResolutionFailedLimitation"),
            DogfoodKernelLoader.CreateDelegate<CliTreeDotnetRestoreRetryMessage>(
                programType,
                "CliTreeDotnetRestoreRetryMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTreeDotnetListFailedMessage>(
                programType,
                "CliTreeDotnetListFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliTreeProjectHeader>(
                programType,
                "CliTreeProjectHeader"),
            DogfoodKernelLoader.CreateDelegate<CliTreeNoDependenciesLine>(
                programType,
                "CliTreeNoDependenciesLine"),
            DogfoodKernelLoader.CreateDelegate<CliTreeDependencyText>(
                programType,
                "CliTreeDependencyText"),
            DogfoodKernelLoader.CreateDelegate<CliTreeDependencyLine>(
                programType,
                "CliTreeDependencyLine"),
            DogfoodKernelLoader.CreateDelegate<CliTreeTransitiveHeader>(
                programType,
                "CliTreeTransitiveHeader"),
            DogfoodKernelLoader.CreateDelegate<CliTreeTransitiveDependencyLine>(
                programType,
                "CliTreeTransitiveDependencyLine"),
            DogfoodKernelLoader.CreateDelegate<CliTreeLimitationsHeader>(
                programType,
                "CliTreeLimitationsHeader"),
            DogfoodKernelLoader.CreateDelegate<CliTreeLimitationLine>(
                programType,
                "CliTreeLimitationLine")));

    private delegate int CliTreeOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliTreeMaxDepthInto(
        string[] args,
        int defaultDepth,
        int[] result);

    private delegate int CliTreeOutputMode(int json);

    private delegate string CliTreeHelpText();
    private delegate string CliTreeProjectDirectoryNotFoundMessage(string projectRoot);
    private delegate string CliTreeFailedMessage(string message);
    private delegate string CliTreeNoProjectFileMessage();
    private delegate string CliTreeProjectYmlLimitationMessage();
    private delegate string CliTreeTransitiveResolutionFailedLimitation(string detail);
    private delegate string CliTreeDotnetRestoreRetryMessage(string detail);
    private delegate string CliTreeDotnetListFailedMessage();
    private delegate string CliTreeProjectHeader(string name, string targetFramework);
    private delegate string CliTreeNoDependenciesLine();
    private delegate string CliTreeDependencyText(string name, string version, string kind);
    private delegate string CliTreeDependencyLine(int isLast, string dependencyText);
    private delegate string CliTreeTransitiveHeader(string countText);
    private delegate string CliTreeTransitiveDependencyLine(string dependencyText);
    private delegate string CliTreeLimitationsHeader();
    private delegate string CliTreeLimitationLine(string limitation);

    private sealed record Bindings(
        CliTreeOptionSummaryInto OptionSummary,
        CliTreeMaxDepthInto MaxDepth,
        CliTreeOutputMode OutputMode,
        CliTreeHelpText TreeHelpText,
        CliTreeProjectDirectoryNotFoundMessage TreeProjectDirectoryNotFoundMessage,
        CliTreeFailedMessage TreeFailedMessage,
        CliTreeNoProjectFileMessage TreeNoProjectFileMessage,
        CliTreeProjectYmlLimitationMessage TreeProjectYmlLimitationMessage,
        CliTreeTransitiveResolutionFailedLimitation TreeTransitiveResolutionFailedLimitation,
        CliTreeDotnetRestoreRetryMessage TreeDotnetRestoreRetryMessage,
        CliTreeDotnetListFailedMessage TreeDotnetListFailedMessage,
        CliTreeProjectHeader TreeProjectHeader,
        CliTreeNoDependenciesLine TreeNoDependenciesLine,
        CliTreeDependencyText TreeDependencyText,
        CliTreeDependencyLine TreeDependencyLine,
        CliTreeTransitiveHeader TreeTransitiveHeader,
        CliTreeTransitiveDependencyLine TreeTransitiveDependencyLine,
        CliTreeLimitationsHeader TreeLimitationsHeader,
        CliTreeLimitationLine TreeLimitationLine);

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
