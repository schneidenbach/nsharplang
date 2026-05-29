using System;

namespace NSharpLang.Compiler;

public enum CompilationBackend
{
    Il
}

public static class CompilationBackendExtensions
{
    public const string RetiredTranspileBackendMessage =
        "The 'transpile' backend has been removed. " +
        "Use backend: il for build/run/check/test/publish. " +
        "To export N# sources to C#, run 'nlc export csharp'.";

    public static string ToConfigValue(this CompilationBackend backend)
        => backend switch
        {
            CompilationBackend.Il => "il",
            _ => throw new ArgumentOutOfRangeException(nameof(backend), backend, "Unknown compilation backend.")
        };

    public static CompilationBackend Parse(string? value)
    {
        if (string.Equals(value?.Trim(), "transpile", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(RetiredTranspileBackendMessage);
        }

        if (TryParse(value, out var backend))
        {
            return backend;
        }

        throw new InvalidOperationException(
            $"Invalid backend: '{value}'. Must be 'il'.");
    }

    public static bool TryParse(string? value, out CompilationBackend backend)
    {
        switch (value?.Trim().ToLowerInvariant())
        {
            case null:
            case "":
            case "il":
                backend = CompilationBackend.Il;
                return true;
            default:
                backend = default;
                return false;
        }
    }
}
