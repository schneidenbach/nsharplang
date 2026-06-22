using System;

namespace NSharpLang.Cli;

internal static class UnifiedDiffTextKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string GetBeforeHeaderText(string label)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetBeforeHeaderTextWithCSharp(label);

        try
        {
            var text = bindings.BeforeHeader(label);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetBeforeHeaderTextWithCSharp(label);
    }

    internal static string GetAfterHeaderText(string label)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetAfterHeaderTextWithCSharp(label);

        try
        {
            var text = bindings.AfterHeader(label);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetAfterHeaderTextWithCSharp(label);
    }

    internal static string GetHunkHeaderText(int oldStart, int oldCount, int newStart, int newCount)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetHunkHeaderTextWithCSharp(oldStart, oldCount, newStart, newCount);

        try
        {
            var text = bindings.HunkHeader(oldStart, oldCount, newStart, newCount);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetHunkHeaderTextWithCSharp(oldStart, oldCount, newStart, newCount);
    }

    internal static string GetLinePrefixText(UnifiedDiff.DiffKind kind)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetLinePrefixTextWithCSharp(kind);

        try
        {
            var text = bindings.LinePrefix((int)kind);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetLinePrefixTextWithCSharp(kind);
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliUnifiedDiffBeforeHeaderText>(
                programType,
                "CliUnifiedDiffBeforeHeaderText"),
            DogfoodKernelLoader.CreateDelegate<CliUnifiedDiffAfterHeaderText>(
                programType,
                "CliUnifiedDiffAfterHeaderText"),
            DogfoodKernelLoader.CreateDelegate<CliUnifiedDiffHunkHeaderText>(
                programType,
                "CliUnifiedDiffHunkHeaderText"),
            DogfoodKernelLoader.CreateDelegate<CliUnifiedDiffLinePrefixText>(
                programType,
                "CliUnifiedDiffLinePrefixText")));

    private delegate string CliUnifiedDiffBeforeHeaderText(string label);

    private delegate string CliUnifiedDiffAfterHeaderText(string label);

    private delegate string CliUnifiedDiffHunkHeaderText(int oldStart, int oldCount, int newStart, int newCount);

    private delegate string CliUnifiedDiffLinePrefixText(int kindId);

    private sealed record Bindings(
        CliUnifiedDiffBeforeHeaderText BeforeHeader,
        CliUnifiedDiffAfterHeaderText AfterHeader,
        CliUnifiedDiffHunkHeaderText HunkHeader,
        CliUnifiedDiffLinePrefixText LinePrefix);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product diff text routes through CliArguments.nl.
    private static string GetBeforeHeaderTextWithCSharp(string label)
        => $"--- {label}";

    private static string GetAfterHeaderTextWithCSharp(string label)
        => $"+++ {label}";

    private static string GetHunkHeaderTextWithCSharp(int oldStart, int oldCount, int newStart, int newCount)
        => $"@@ -{oldStart},{oldCount} +{newStart},{newCount} @@";

    private static string GetLinePrefixTextWithCSharp(UnifiedDiff.DiffKind kind)
        => kind switch
        {
            UnifiedDiff.DiffKind.Added => "+",
            UnifiedDiff.DiffKind.Removed => "-",
            _ => " "
        };
}
