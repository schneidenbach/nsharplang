using System;

namespace NSharpLang.Cli;

internal static class PositionalArgumentKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgs(
        string[] args,
        string[] optionsWithValues,
        out string[] positionalArgs)
    {
        positionalArgs = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var resultIndices = t_resultIndices;
        if (resultIndices == null || resultIndices.Length < args.Length)
        {
            resultIndices = new int[args.Length];
            t_resultIndices = resultIndices;
        }

        try
        {
            var count = bindings.PositionalArgIndices(args, optionsWithValues, resultIndices);
            if (count < 0 || count > args.Length)
                return false;

            if (count == 0)
                return true;

            positionalArgs = new string[count];
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = resultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= args.Length)
                {
                    positionalArgs = Array.Empty<string>();
                    return false;
                }

                positionalArgs[i] = args[sourceIndex];
            }

            return true;
        }
        catch
        {
            positionalArgs = Array.Empty<string>();
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliPositionalArgIndicesInto>(
                programType,
                "CliPositionalArgIndicesInto")));

    private delegate int CliPositionalArgIndicesInto(
        string[] args,
        string[] optionsWithValues,
        int[] resultIndices);

    private sealed record Bindings(CliPositionalArgIndicesInto PositionalArgIndices);
}
