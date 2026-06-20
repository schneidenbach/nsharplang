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
    {
        if (TryGetMessage(bindings => bindings.TreeHelpText(), out var message))
            return message;

        return GetHelpTextWithCSharp();
    }

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
    {
        if (TryGetMessage(bindings => bindings.TreeProjectDirectoryNotFoundMessage(projectRoot), out var message))
            return message;

        return GetProjectDirectoryNotFoundMessageWithCSharp(projectRoot);
    }

    internal static string GetTreeFailedMessage(string message)
    {
        if (TryGetMessage(bindings => bindings.TreeFailedMessage(message), out var result))
            return result;

        return GetTreeFailedMessageWithCSharp(message);
    }

    internal static string GetNoProjectFileMessage()
    {
        if (TryGetMessage(bindings => bindings.TreeNoProjectFileMessage(), out var message))
            return message;

        return GetNoProjectFileMessageWithCSharp();
    }

    internal static string GetProjectYmlLimitationMessage()
    {
        if (TryGetMessage(bindings => bindings.TreeProjectYmlLimitationMessage(), out var message))
            return message;

        return GetProjectYmlLimitationMessageWithCSharp();
    }

    internal static string GetTransitiveResolutionFailedLimitation(string detail)
    {
        if (TryGetMessage(bindings => bindings.TreeTransitiveResolutionFailedLimitation(detail), out var message))
            return message;

        return GetTransitiveResolutionFailedLimitationWithCSharp(detail);
    }

    internal static string GetDotnetRestoreRetryMessage(string detail)
    {
        if (TryGetMessage(bindings => bindings.TreeDotnetRestoreRetryMessage(detail), out var message))
            return message;

        return GetDotnetRestoreRetryMessageWithCSharp(detail);
    }

    internal static string GetDotnetListFailedMessage()
    {
        if (TryGetMessage(bindings => bindings.TreeDotnetListFailedMessage(), out var message))
            return message;

        return GetDotnetListFailedMessageWithCSharp();
    }

    internal static string GetProjectHeader(string name, string targetFramework)
    {
        if (TryGetMessage(bindings => bindings.TreeProjectHeader(name, targetFramework), out var message))
            return message;

        return GetProjectHeaderWithCSharp(name, targetFramework);
    }

    internal static string GetNoDependenciesLine()
    {
        if (TryGetMessage(bindings => bindings.TreeNoDependenciesLine(), out var message))
            return message;

        return GetNoDependenciesLineWithCSharp();
    }

    internal static string GetDependencyText(string name, string? version, string kind)
    {
        var versionText = string.IsNullOrWhiteSpace(version) ? string.Empty : version!;
        if (TryGetMessage(bindings => bindings.TreeDependencyText(name, versionText, kind), out var message))
            return message;

        return GetDependencyTextWithCSharp(name, versionText, kind);
    }

    internal static string GetDependencyLine(bool isLast, string dependencyText)
    {
        if (TryGetMessage(bindings => bindings.TreeDependencyLine(isLast ? 1 : 0, dependencyText), out var message))
            return message;

        return GetDependencyLineWithCSharp(isLast, dependencyText);
    }

    internal static string GetTransitiveHeader(int count)
    {
        if (TryGetMessage(bindings => bindings.TreeTransitiveHeader(count.ToString()), out var message))
            return message;

        return GetTransitiveHeaderWithCSharp(count);
    }

    internal static string GetTransitiveDependencyLine(string dependencyText)
    {
        if (TryGetMessage(bindings => bindings.TreeTransitiveDependencyLine(dependencyText), out var message))
            return message;

        return GetTransitiveDependencyLineWithCSharp(dependencyText);
    }

    internal static string GetLimitationsHeader()
    {
        if (TryGetMessage(bindings => bindings.TreeLimitationsHeader(), out var message))
            return message;

        return GetLimitationsHeaderWithCSharp();
    }

    internal static string GetLimitationLine(string limitation)
    {
        if (TryGetMessage(bindings => bindings.TreeLimitationLine(limitation), out var message))
            return message;

        return GetLimitationLineWithCSharp(limitation);
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

    // Stage 6 C#-surface-shrink: fallback/oracle only; product tree command messages route through CliTree* kernels.
    private static string GetHelpTextWithCSharp()
        => "N# Dependency Tree\n"
           + "\n"
           + "Usage: nlc tree [options]\n"
           + "\n"
           + "Show the project's dependencies and transitive NuGet packages when available.\n"
           + "\n"
           + "Options:\n"
           + "  --project <dir>   Project root directory (default: current directory)\n"
           + "  --depth <n>       Maximum tree depth to display\n"
           + "  --json            Output as JSON envelope\n"
           + "  --help, -h        Show this help text\n"
           + "\n"
           + "Examples:\n"
           + "  nlc tree\n"
           + "  nlc tree --depth 1\n"
           + "  nlc tree --json\n"
           + "\n"
           + "Behavior:\n"
           + "  project.yml projects list direct runtime dependencies without requiring .csproj files.\n"
           + "  Transitive NuGet dependencies are included when an MSBuild project file is present.\n"
           + "\n"
           + "Exit codes:\n"
           + "  0  Tree displayed successfully\n"
           + "  1  Failed to display tree";

    private static string GetProjectDirectoryNotFoundMessageWithCSharp(string projectRoot)
        => $"Project directory not found: {projectRoot}";

    private static string GetTreeFailedMessageWithCSharp(string message)
        => $"Tree failed: {message}";

    private static string GetNoProjectFileMessageWithCSharp()
        => "No project.yml or .csproj found. nlc tree reads direct dependencies from project.yml; transitive NuGet dependency output requires an MSBuild project file.";

    private static string GetProjectYmlLimitationMessageWithCSharp()
        => "project.yml output lists direct runtime dependencies only. Transitive NuGet dependencies require an MSBuild project file so dotnet can resolve the package graph.";

    private static string GetTransitiveResolutionFailedLimitationWithCSharp(string detail)
        => $"Transitive NuGet dependency resolution through MSBuild failed: {detail}";

    private static string GetDotnetRestoreRetryMessageWithCSharp(string detail)
        => $"{detail} Run 'dotnet restore' and retry.";

    private static string GetDotnetListFailedMessageWithCSharp()
        => "dotnet list package failed.";

    private static string GetProjectHeaderWithCSharp(string name, string targetFramework)
        => $"{name} ({targetFramework})";

    private static string GetNoDependenciesLineWithCSharp()
        => "  (no dependencies)";

    private static string GetDependencyTextWithCSharp(string name, string version, string kind)
        => $"{name}{(version.Length == 0 ? string.Empty : $"@{version}")} [{kind}]";

    private static string GetDependencyLineWithCSharp(bool isLast, string dependencyText)
        => $"{(isLast ? "└── " : "├── ")}{dependencyText}";

    private static string GetTransitiveHeaderWithCSharp(int count)
        => $"  transitive ({count} packages):";

    private static string GetTransitiveDependencyLineWithCSharp(string dependencyText)
        => $"    {dependencyText}";

    private static string GetLimitationsHeaderWithCSharp()
        => "Limitations:";

    private static string GetLimitationLineWithCSharp(string limitation)
        => $"  - {limitation}";

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
