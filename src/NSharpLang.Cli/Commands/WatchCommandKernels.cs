using System;

namespace NSharpLang.Cli.Commands;

internal static class WatchCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetForwardedArgs(string[] args, out string[] forwardedArgs)
    {
        forwardedArgs = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length <= 1)
            return true;

        var resultIndices = t_resultIndices;
        if (resultIndices == null || resultIndices.Length < args.Length)
        {
            resultIndices = new int[args.Length];
            t_resultIndices = resultIndices;
        }

        try
        {
            var count = bindings.WatchForwardedArgIndices(args, resultIndices);
            if (count < 0 || count > args.Length)
                return false;

            if (count == 0)
                return true;

            forwardedArgs = new string[count];
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = resultIndices[i];
                if (sourceIndex <= 0 || sourceIndex >= args.Length)
                {
                    forwardedArgs = Array.Empty<string>();
                    return false;
                }

                forwardedArgs[i] = args[sourceIndex];
            }

            return true;
        }
        catch
        {
            forwardedArgs = Array.Empty<string>();
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliWatchForwardedArgIndicesInto>(
                programType,
                "CliWatchForwardedArgIndicesInto")));

    private delegate int CliWatchForwardedArgIndicesInto(string[] args, int[] resultIndices);

    private sealed record Bindings(CliWatchForwardedArgIndicesInto WatchForwardedArgIndices);
}
