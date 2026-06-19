using System;

namespace NSharpLang.Cli.Daemon;

internal static class DaemonServerKernels
{
    [ThreadStatic]
    private static int[]? t_positionResult;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryParsePosition(string position, out int line, out int column)
    {
        line = 0;
        column = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_positionResult ??= new int[2];
        try
        {
            var code = bindings.ParsePosition(position, result);
            if (code != 0)
                return false;

            line = result[0];
            column = result[1];
            return true;
        }
        catch
        {
            line = 0;
            column = 0;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliDaemonPositionInto>(
                programType,
                "CliDaemonPositionInto")));

    private delegate int CliDaemonPositionInto(string position, int[] result);

    private sealed record Bindings(CliDaemonPositionInto ParsePosition);
}
