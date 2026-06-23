using System;

namespace NSharpLang.Compiler;

internal static class FormatterConfigKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    [ThreadStatic]
    private static int[]? t_intResult;

    internal static bool TryParseInt(string value, out int parsed)
    {
        parsed = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            throw new InvalidOperationException("N# formatter config integer parser kernel is unavailable.");

        var result = t_intResult ??= new int[1];
        try
        {
            var code = bindings.TryParseInt(value, result);
            if (code == 0)
                return false;
            if (code != 1)
                throw new InvalidOperationException("N# formatter config integer parser kernel rejected the result buffer.");

            parsed = result[0];
            return true;
        }
        catch (Exception ex)
        {
            parsed = 0;
            throw new InvalidOperationException("N# formatter config integer parser kernel failed.", ex);
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<EditorConfigTryParseIntInto>(
                programType,
                "EditorConfigTryParseIntInto")));

    private delegate int EditorConfigTryParseIntInto(string value, int[] result);

    private sealed record Bindings(EditorConfigTryParseIntInto TryParseInt);
}
