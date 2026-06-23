using System;

namespace NSharpLang.Cli;

internal static class PositionalArgumentKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string[] GetArgs(
        string[] args,
        string[] optionsWithValues)
    {
        var bindings = s_bindings.Value ?? throw new InvalidOperationException("N# positional argument kernels are unavailable.");
        var resultIndices = t_resultIndices;
        if (resultIndices == null || resultIndices.Length < args.Length)
        {
            resultIndices = new int[args.Length];
            t_resultIndices = resultIndices;
        }

        var count = bindings.PositionalArgIndices(args, optionsWithValues, resultIndices);
        if (count < 0 || count > args.Length)
            throw new InvalidOperationException("N# positional argument kernel rejected the arguments.");

        var positionalArgs = new string[count];
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = resultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= args.Length)
                throw new InvalidOperationException("N# positional argument kernel rejected the arguments.");

            positionalArgs[i] = args[sourceIndex];
        }

        return positionalArgs;
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
