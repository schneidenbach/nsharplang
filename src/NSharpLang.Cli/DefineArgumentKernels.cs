using System;

namespace NSharpLang.Cli;

internal readonly record struct DefineArgumentExtraction(
    string[] Defines,
    string[] RemainingArgs);

internal static class DefineArgumentKernels
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryExtract(string[] args, out DefineArgumentExtraction extraction)
    {
        extraction = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(args);

        try
        {
            var code = bindings.DefineExtraction(
                args,
                scratch.DefineSymbols,
                scratch.RemainingIndices,
                scratch.ResultCounts);
            if (code != 0)
                return false;

            var defineCount = scratch.ResultCounts[0];
            var remainingCount = scratch.ResultCounts[1];
            if (defineCount < 0 ||
                defineCount > scratch.DefineSymbols.Length ||
                remainingCount < 0 ||
                remainingCount > args.Length)
            {
                return false;
            }

            var defines = new string[defineCount];
            for (var i = 0; i < defineCount; i++)
            {
                var symbol = scratch.DefineSymbols[i];
                if (string.IsNullOrWhiteSpace(symbol))
                    return false;

                defines[i] = symbol;
            }

            var remainingArgs = new string[remainingCount];
            for (var i = 0; i < remainingCount; i++)
            {
                var sourceIndex = scratch.RemainingIndices[i];
                if (sourceIndex < 0 || sourceIndex >= args.Length)
                    return false;

                remainingArgs[i] = args[sourceIndex];
            }

            extraction = new DefineArgumentExtraction(defines, remainingArgs);
            return true;
        }
        catch
        {
            extraction = default;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliDefineExtractionInto>(
                programType,
                "CliDefineExtractionInto")));

    private delegate int CliDefineExtractionInto(
        string[] args,
        string[] defineSymbols,
        int[] remainingIndices,
        int[] resultCounts);

    private sealed record Bindings(CliDefineExtractionInto DefineExtraction);

    private sealed class Scratch
    {
        internal string[] DefineSymbols = Array.Empty<string>();
        internal int[] RemainingIndices = Array.Empty<int>();
        internal int[] ResultCounts = new int[2];

        internal void EnsureCapacity(string[] args)
        {
            var defineCapacity = 0;
            foreach (var arg in args)
                defineCapacity += arg.Length + 1;

            if (DefineSymbols.Length != defineCapacity)
                DefineSymbols = new string[defineCapacity];
            else
                Array.Clear(DefineSymbols, 0, DefineSymbols.Length);

            if (RemainingIndices.Length != args.Length)
                RemainingIndices = new int[args.Length];

            Array.Clear(ResultCounts, 0, ResultCounts.Length);
        }
    }
}
