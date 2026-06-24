using System;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class CodeIntelligenceSignatureKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string GetFallbackSignatureText(string kind, string name, string? typeName)
        => RequiredBindings.FallbackSignatureText(
            kind,
            name,
            typeName ?? string.Empty,
            typeName != null ? 1 : 0);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CodeIntelligenceFallbackSignatureText>(
                programType,
                "CodeIntelligenceFallbackSignatureText")));

    private delegate string CodeIntelligenceFallbackSignatureText(
        string kind,
        string name,
        string typeName,
        int hasType);

    private sealed record Bindings(
        CodeIntelligenceFallbackSignatureText FallbackSignatureText);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# code intelligence signature kernels are unavailable.");
}
