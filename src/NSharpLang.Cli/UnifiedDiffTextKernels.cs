using System;

namespace NSharpLang.Cli;

internal static class UnifiedDiffTextKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string GetBeforeHeaderText(string label)
        => RequiredBindings.BeforeHeader(label);

    internal static string GetAfterHeaderText(string label)
        => RequiredBindings.AfterHeader(label);

    internal static string GetHunkHeaderText(int oldStart, int oldCount, int newStart, int newCount)
        => RequiredBindings.HunkHeader(oldStart, oldCount, newStart, newCount);

    internal static string GetLinePrefixText(UnifiedDiff.DiffKind kind)
        => RequiredBindings.LinePrefix((int)kind);

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

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# unified diff text kernels are unavailable.");
}
