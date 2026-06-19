using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct LintOptionSummary(
    string? ProjectOption,
    bool UseText,
    bool UseJson,
    bool ShowHelp);

internal static class LintCommandKernels
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    [ThreadStatic]
    private static int[]? t_optionResultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out LintOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionResultIndices ??= new int[4];
        try
        {
            var code = bindings.LintOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption))
            {
                summary = default;
                return false;
            }

            summary = new LintOptionSummary(
                projectOption,
                resultIndices[1] != 0,
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

    internal static bool TryGetFileArgs(string[] args, out string[] files)
    {
        files = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            var count = bindings.LintFileArgIndices(
                args,
                scratch.ProjectValueIndices,
                scratch.ResultIndices);

            if (count < 0 || count > args.Length)
                return false;

            if (count == 0)
                return true;

            files = new string[count];
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= args.Length)
                {
                    files = Array.Empty<string>();
                    return false;
                }

                files[i] = args[sourceIndex];
            }

            return true;
        }
        catch
        {
            files = Array.Empty<string>();
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliLintOptionSummaryInto>(
                programType,
                "CliLintOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliLintFileArgIndicesInto>(
                programType,
                "CliLintFileArgIndicesInto")));

    private delegate int CliLintOptionSummaryInto(string[] args, int[] resultIndices);

    private delegate int CliLintFileArgIndicesInto(
        string[] args,
        int[] projectValueIndices,
        int[] resultIndices);

    private sealed record Bindings(
        CliLintOptionSummaryInto LintOptionSummary,
        CliLintFileArgIndicesInto LintFileArgIndices);

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

    private sealed class Scratch
    {
        internal int[] ProjectValueIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ProjectValueIndices.Length != count)
                ProjectValueIndices = new int[count];

            if (ResultIndices.Length != count)
                ResultIndices = new int[count];
        }
    }
}
