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
        try
        {
            var code = bindings.TryParseComponent(component, result);
            if (code == 0)
                return false;

            if (code != 1)
                throw new InvalidOperationException("N# assembly-version parser kernel rejected the result buffer.");

            value = result[0];
            return true;
        }
        catch (Exception ex) when (ex is not InvalidOperationException)
        {
            value = 0;
            throw new InvalidOperationException("N# assembly-version parser kernel failed.", ex);
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<AssemblyVersionTryParseComponentInto>(
                programType,
                "AssemblyVersionTryParseComponentInto")));

    private delegate int AssemblyVersionTryParseComponentInto(string component, int[] result);

    private sealed record Bindings(AssemblyVersionTryParseComponentInto TryParseComponent);
}
