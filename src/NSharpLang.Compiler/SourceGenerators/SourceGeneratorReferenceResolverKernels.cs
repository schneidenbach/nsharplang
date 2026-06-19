using System;

namespace NSharpLang.Compiler.SourceGenerators;

internal static class SourceGeneratorReferenceResolverKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    [ThreadStatic]
    private static int[]? t_targetFrameworkVersionResult;

    internal static bool TryParseTargetFrameworkVersion(
        string targetFramework,
        out bool parsed,
        out int major,
        out int minor)
    {
        parsed = false;
        major = 0;
        minor = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var result = t_targetFrameworkVersionResult ??= new int[2];
        try
        {
            var code = bindings.TargetFrameworkVersion(targetFramework, result);
            if (code is not 0 and not 1)
                return false;

            parsed = code == 1;
            major = result[0];
            minor = result[1];
            return true;
        }
        catch
        {
            parsed = false;
            major = 0;
            minor = 0;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<SourceGeneratorTargetFrameworkVersionInto>(
                programType,
                "SourceGeneratorTargetFrameworkVersionInto")));

    private delegate int SourceGeneratorTargetFrameworkVersionInto(string targetFramework, int[] result);

    private sealed record Bindings(SourceGeneratorTargetFrameworkVersionInto TargetFrameworkVersion);
}
