using System;

namespace NSharpLang.Compiler;

internal static class FormatterConfigKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    [ThreadStatic]
    private static int[]? t_intResult;

    internal static int? ParseInt(string value)
    {
        var result = t_intResult ??= new int[1];
        var code = RequiredBindings.ParseInt(value, result);
        if (code == 0)
            return null;

        return result[0];
    }

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# formatter config integer parser kernel is unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<EditorConfigTryParseIntInto>(
                programType,
                "EditorConfigTryParseIntInto")));

    private delegate int EditorConfigTryParseIntInto(string value, int[] result);

    private sealed record Bindings(EditorConfigTryParseIntInto ParseInt);
}
