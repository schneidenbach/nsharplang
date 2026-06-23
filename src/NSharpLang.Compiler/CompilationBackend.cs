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

    public static CompilationBackend Parse(string? value)
    {
        switch (value?.Trim().ToLowerInvariant())
        {
            case null:
            case "":
            case "il":
                return CompilationBackend.Il;
            case "transpile":
                throw new InvalidOperationException(RetiredTranspileBackendMessage);
            default:
                throw new InvalidOperationException(
                    $"Invalid backend: '{value}'. Must be 'il'.");
        }
    }
}
