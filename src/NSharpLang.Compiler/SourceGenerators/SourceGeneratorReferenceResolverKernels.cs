using System;

namespace NSharpLang.Compiler.SourceGenerators;

internal static class SourceGeneratorReferenceResolverKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    [ThreadStatic]
    private static int[]? t_targetFrameworkVersionResult;

    internal static (bool Parsed, int Major, int Minor) ParseTargetFrameworkVersion(string targetFramework)
    {
        var result = t_targetFrameworkVersionResult ??= new int[2];

        var code = RequiredBindings.TargetFrameworkVersion(targetFramework, result);
        if (code is not 0 and not 1)
            throw new InvalidOperationException("N# source-generator target-framework parser returned an invalid code.");

        return code == 1
            ? (true, result[0], result[1])
            : (false, 0, 0);
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<SourceGeneratorTargetFrameworkVersionInto>(
                programType,
                "SourceGeneratorTargetFrameworkVersionInto")));

    private delegate int SourceGeneratorTargetFrameworkVersionInto(string targetFramework, int[] result);

    private sealed record Bindings(SourceGeneratorTargetFrameworkVersionInto TargetFrameworkVersion);

    private static Bindings RequiredBindings
        => s_bindings.Value
            ?? throw new InvalidOperationException("N# source-generator reference resolver kernels are unavailable.");
}
