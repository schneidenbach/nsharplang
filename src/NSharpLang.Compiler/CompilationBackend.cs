using System;

namespace NSharpLang.Compiler;

public static class CompilationBackendExtensions
{

    public static void Validate(string? value)
    {
        switch (value?.Trim().ToLowerInvariant())
        {
            case null:
            case "":
            case "il":
                return;
            default:
                throw new InvalidOperationException(
                    $"Invalid backend: '{value}'. Must be 'il'.");
        }
    }
}
