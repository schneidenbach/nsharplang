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

        if (NSharpCodeIntelligenceDogfoodAdapter.TryExtractEditorIdentifierSpan(
                text,
                line + 1,
                character + 1,
                out var dogfoodSpan))
        {
            if (dogfoodSpan == null)
                return false;

            span = new EditorIdentifierSpan(
                dogfoodSpan.Value.StartColumn,
                dogfoodSpan.Value.EndColumn,
                dogfoodSpan.Value.Name);
            return true;
        }

        return TryGetEditorIdentifierSpanAtPositionFallback(text, line, character, out span);
    }

    public static string? GetSourceLine(string source, int line)
    {
        if (NSharpCodeIntelligenceDogfoodAdapter.TryExtractSourceLine(source, line, out var dogfoodLine))
        {
            return dogfoodLine;
        }

        return GetSourceLineFallback(source, line);
    }

    private static bool TryGetEditorIdentifierSpanAtPositionFallback(
        string text,
        int line,
        int character,
        out EditorIdentifierSpan span)
    {
        span = default;
        if (!TryGetLogicalLineRange(text, line, out var lineStart, out var lineLength) || lineLength == 0)
            return false;

        if (character >= lineLength)
        {
            character = lineLength - 1;
            if (!IsIdentifierChar(text[lineStart + character]))
                return false;
        }
        else if (!IsIdentifierChar(text[lineStart + character]))
        {
            return false;
        }

        var start = character;
        while (start > 0 && IsIdentifierChar(text[lineStart + start - 1]))
        {
            start--;
        }

        var end = character;
        while (end + 1 < lineLength && IsIdentifierChar(text[lineStart + end + 1]))
        {
            end++;
        }

        span = new EditorIdentifierSpan(
            start + 1,
            end + 1,
            text.Substring(lineStart + start, end - start + 1));
        return true;
    }

    private static string? GetSourceLineFallback(string source, int line)
    {
        if (line <= 0)
            return null;

        return TryGetLogicalLineRange(source, line - 1, out var lineStart, out var lineLength)
            ? source.Substring(lineStart, lineLength)
            : null;
    }

    private static bool TryGetLogicalLineRange(string source, int line, out int start, out int length)
    {
        start = 0;
        length = 0;
        if (line < 0)
            return false;

        var currentLine = 0;
        var lineStart = 0;
        for (var index = 0; index < source.Length; index++)
        {
            var ch = source[index];
            if (ch != '\r' && ch != '\n')
            {
                continue;
            }

            if (currentLine == line)
            {
                start = lineStart;
                length = index - lineStart;
                return true;
            }

            if (ch == '\r' && index + 1 < source.Length && source[index + 1] == '\n')
            {
                index++;
            }

            currentLine++;
            lineStart = index + 1;
        }

        if (currentLine != line)
            return false;

        start = lineStart;
        length = source.Length - lineStart;
        return true;
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';
}
