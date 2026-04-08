using System;

namespace NSharpLang.Compiler;

public enum CompilationBackend
{
    Transpile,
    Il
}

public static class CompilationBackendExtensions
{
    public static string ToConfigValue(this CompilationBackend backend)
        => backend switch
        {
            CompilationBackend.Transpile => "transpile",
            CompilationBackend.Il => "il",
            _ => throw new ArgumentOutOfRangeException(nameof(backend), backend, "Unknown compilation backend.")
        };

    public static CompilationBackend Parse(string? value)
    {
        if (TryParse(value, out var backend))
        {
            return backend;
        }

        throw new InvalidOperationException(
            $"Invalid backend: '{value}'. Must be 'transpile' or 'il'.");
    }

    public static bool TryParse(string? value, out CompilationBackend backend)
    {
        switch (value?.Trim().ToLowerInvariant())
        {
            case null:
            case "":
            case "transpile":
                backend = CompilationBackend.Transpile;
                return true;
            case "il":
                backend = CompilationBackend.Il;
                return true;
            default:
                backend = default;
                return false;
        }
    }
}
