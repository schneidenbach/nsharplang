using System;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal static class CompilationBackendSelectionKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static CompilationBackend Resolve(string? backendOption, ProjectConfig? config)
    {
        var selectedValue = GetSelectedBackendValue(backendOption, config);
        if (TryGetEffectiveBackendKind(backendOption, config?.Backend, out var backend, out var statusCode))
        {
            return statusCode switch
            {
                1 => backend,
                -1 => throw new InvalidOperationException(CompilationBackendExtensions.RetiredTranspileBackendMessage),
                _ => throw new InvalidOperationException($"Invalid backend: '{selectedValue}'. Must be 'il'.")
            };
        }

        throw new InvalidOperationException("N# compilation backend selection kernel rejected the backend configuration.");
    }

    internal static bool TryGetEffectiveBackendKind(
        string? backendOption,
        string? projectBackend,
        out CompilationBackend backend,
        out int statusCode)
    {
        backend = default;
        statusCode = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.EffectiveBackendKind(backendOption ?? string.Empty, projectBackend ?? string.Empty);
            if (code == 1)
            {
                backend = CompilationBackend.Il;
                statusCode = code;
                return true;
            }

            if (code is -1 or 0)
            {
                statusCode = code;
                return true;
            }

            return false;
        }
        catch
        {
            backend = default;
            statusCode = 0;
            return false;
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
}
