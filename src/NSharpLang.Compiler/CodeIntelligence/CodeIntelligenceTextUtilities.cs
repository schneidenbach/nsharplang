using System;

namespace NSharpLang.Compiler.CodeIntelligence;

public readonly record struct EditorIdentifierSpan(int StartColumn, int EndColumn, string Name)
{
    public int StartCharacter => StartColumn - 1;
    public int EndCharacter => EndColumn;
}

public static class CodeIntelligenceTextUtilities
{
    public static string GetEditorWordAtPosition(string text, int line, int character) =>
        TryGetEditorIdentifierSpanAtPosition(text, line, character, out var span)
            ? span.Name
            : string.Empty;

    public static bool TryGetEditorIdentifierSpanAtPosition(
        string text,
        int line,
        int character,
        out EditorIdentifierSpan span)
    {
        span = default;
        if (line < 0 || character < 0)
            return false;

        if (!CodeIntelligenceSourceTextKernels.TryExtractEditorIdentifierSpan(
                text,
                line + 1,
                character + 1,
                out var dogfoodSpan))
            throw new InvalidOperationException("N# editor identifier span kernel rejected the position.");

        if (dogfoodSpan == null)
            return false;

        span = new EditorIdentifierSpan(
            dogfoodSpan.Value.StartColumn,
            dogfoodSpan.Value.EndColumn,
            dogfoodSpan.Value.Name);
        return true;
    }

    public static string? GetSourceLine(string source, int line)
    {
        if (!CodeIntelligenceSourceTextKernels.TryExtractSourceLine(source, line, out var dogfoodLine))
            throw new InvalidOperationException("N# source line kernel rejected the line.");

        return dogfoodLine;
    }
}
