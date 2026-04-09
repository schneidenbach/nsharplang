using System;

namespace NSharpLang.Compiler;

public enum CompilationBackend
{
    Transpile,
    Il
}

public static class CompilationBackendExtensions
{
    public const string RetiredTranspileBackendMessage =
        "The 'transpile' backend and 'nlc transpile' command have been retired. " +
        "Use the IL backend for build/run/check/test/bench/publish. C# export is no longer a supported product workflow.";

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
            case "transpile":
                backend = CompilationBackend.Transpile;
                return true;
            default:
                backend = default;
                return false;
        }
    }
}
