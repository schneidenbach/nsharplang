using System;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal static class CompilationBackendSelectionKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static void Validate(string? backendOption, ProjectConfig? config)
    {
        var selectedValue = GetSelectedBackendValue(backendOption, config);
        var statusCode = RequiredBindings.EffectiveBackendKind(backendOption ?? string.Empty, config?.Backend ?? string.Empty);
        switch (statusCode)
        {
            case 1:
                return;
            case 0:
                throw new InvalidOperationException($"Invalid backend: '{selectedValue}'. Must be 'il'.");
            default:
                throw new InvalidOperationException("N# compilation backend selection kernel rejected the backend configuration.");
        }
    }

    private static string? GetSelectedBackendValue(string? backendOption, ProjectConfig? config)
        => !string.IsNullOrWhiteSpace(backendOption)
            ? backendOption
            : config?.Backend;

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliEffectiveCompilationBackendKind>(
                programType,
                "CliEffectiveCompilationBackendKind")));

    private delegate int CliEffectiveCompilationBackendKind(string backendOption, string projectBackend);

    private sealed record Bindings(CliEffectiveCompilationBackendKind EffectiveBackendKind);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# compilation backend selection kernels are unavailable.");
}
