using System;

namespace NSharpLang.Compiler;

internal static class AssemblyVersionKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    [ThreadStatic]
    private static int[]? t_componentResult;

    internal static bool TryParseComponent(string component, out int value)
    {
        value = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            throw new InvalidOperationException("N# assembly-version parser kernel is unavailable.");

        var result = t_componentResult ??= new int[1];
            var code = bindings.TryParseComponent(component, result);
            if (code == 0)
                return false;

            value = result[0];
            return true;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<AssemblyVersionTryParseComponentInto>(
                programType,
                "AssemblyVersionTryParseComponentInto")));

    private delegate int AssemblyVersionTryParseComponentInto(string component, int[] result);

    private sealed record Bindings(AssemblyVersionTryParseComponentInto TryParseComponent);
}
