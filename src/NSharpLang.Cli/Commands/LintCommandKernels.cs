using System;

namespace NSharpLang.Cli.Commands;

internal static class LintCommandKernels
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

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
    {
        try
        {
            var programType = DogfoodKernelLoader.TryGetProgramType();
            if (programType == null)
                return null;

            return new Bindings(
                DogfoodKernelLoader.CreateDelegate<CliLintFileArgIndicesInto>(
                    programType,
                    "CliLintFileArgIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private delegate int CliLintFileArgIndicesInto(
        string[] args,
        int[] projectValueIndices,
        int[] resultIndices);

    private sealed record Bindings(CliLintFileArgIndicesInto LintFileArgIndices);

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
