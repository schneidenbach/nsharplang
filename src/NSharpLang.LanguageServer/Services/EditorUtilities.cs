using System;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// Shared editor utility methods used across multiple LSP handlers
/// </summary>
public static class EditorUtilities
{
    /// <summary>
    /// Extracts the identifier word at the given 0-based line and character position.
    /// Returns empty string if position is on whitespace, operator, or out of bounds.
    /// </summary>
    public static string GetWordAtPosition(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return string.Empty;

        var lineText = lines[line];
        if (lineText.Length == 0) return string.Empty;
        if (character < 0) return string.Empty;

        // Handle cursor-at-end: clamp to last character and check if it's an identifier char.
        // This restores the behavior where hovering at the end of a word still resolves it.
        if (character >= lineText.Length)
        {
            character = lineText.Length - 1;
            if (!IsIdentifierChar(lineText[character])) return string.Empty;
        }
        else if (!IsIdentifierChar(lineText[character]))
        {
            return string.Empty;
        }

        int start = character;
        while (start > 0 && IsIdentifierChar(lineText[start - 1]))
            start--;

        int end = character;
        while (end < lineText.Length && IsIdentifierChar(lineText[end]))
            end++;

        return lineText.Substring(start, end - start);
    }

    public static bool IsIdentifierChar(char c) => char.IsLetterOrDigit(c) || c == '_';

    /// <summary>
    /// Returns true when the given position is in string literal text, but not in
    /// an interpolated expression hole where identifiers are real code.
    /// </summary>
    public static bool IsPositionInsideStringLiteral(string text, int line, int character)
    {
        var targetOffset = GetOffset(text, line, character);
        if (targetOffset is null) return false;

        for (var i = 0; i < text.Length; i++)
        {
            if (text[i] == '$' && i + 1 < text.Length && text[i + 1] == '"')
            {
                if (i + 3 < text.Length && text[i + 2] == '"' && text[i + 3] == '"')
                {
                    if (ScanInterpolatedRawString(text, i, targetOffset.Value, out var rawEnd, out var rawContainsTarget))
                    {
                        return rawContainsTarget;
                    }

                    i = rawEnd;
                    continue;
                }

                if (ScanInterpolatedString(text, i, targetOffset.Value, out var interpolatedEnd, out var interpolatedContainsTarget))
                {
                    return interpolatedContainsTarget;
                }

                i = interpolatedEnd;
                continue;
            }

            if (text[i] == '"')
            {
                if (i + 2 < text.Length && text[i + 1] == '"' && text[i + 2] == '"')
                {
                    if (ScanRawString(text, i, targetOffset.Value, hasDollarPrefix: false, out var rawEnd, out var rawContainsTarget))
                    {
                        return rawContainsTarget;
                    }

                    i = rawEnd;
                    continue;
                }

                if (ScanRegularString(text, i, targetOffset.Value, out var regularEnd, out var regularContainsTarget))
                {
                    return regularContainsTarget;
                }

                i = regularEnd;
            }
        }

        return false;
    }

    private static int? GetOffset(string text, int line, int character)
    {
        if (line < 0 || character < 0) return null;

        var currentLine = 0;
        var currentColumn = 0;
        for (var i = 0; i <= text.Length; i++)
        {
            if (currentLine == line && currentColumn == character) return i;
            if (i == text.Length) break;

            if (text[i] == '\n')
            {
                currentLine++;
                currentColumn = 0;
            }
            else
            {
                currentColumn++;
            }
        }

        return null;
    }

    private static bool ScanRawString(string text, int start, int targetOffset, bool hasDollarPrefix, out int end, out bool containsTarget)
    {
        var contentStart = start + (hasDollarPrefix ? 4 : 3);
        for (var i = contentStart; i < text.Length - 2; i++)
        {
            if (targetOffset >= contentStart && targetOffset < i)
            {
                end = i;
                containsTarget = true;
                return true;
            }

            if (text[i] == '"' && text[i + 1] == '"' && text[i + 2] == '"')
            {
                end = i + 2;
                containsTarget = targetOffset >= contentStart && targetOffset < i;
                return containsTarget;
            }
        }

        end = text.Length - 1;
        containsTarget = targetOffset >= contentStart;
        return containsTarget;
    }

    private static bool ScanRegularString(string text, int start, int targetOffset, out int end, out bool containsTarget)
    {
        for (var i = start + 1; i < text.Length; i++)
        {
            if (text[i] == '\n')
            {
                end = i;
                containsTarget = targetOffset > start && targetOffset < i;
                return containsTarget;
            }

            if (text[i] == '"' && !IsEscaped(text, i))
            {
                end = i;
                containsTarget = targetOffset > start && targetOffset < i;
                return containsTarget;
            }
        }

        end = text.Length - 1;
        containsTarget = targetOffset > start;
        return containsTarget;
    }

    private static bool ScanInterpolatedRawString(string text, int start, int targetOffset, out int end, out bool containsTarget)
    {
        var contentStart = start + 4;
        var interpolationDepth = 0;
        var nestedStringDepth = 0;

        for (var i = contentStart; i < text.Length - 2; i++)
        {
            if (targetOffset == i)
            {
                end = i;
                containsTarget = interpolationDepth == 0 || nestedStringDepth > 0;
                return containsTarget;
            }

            if (nestedStringDepth > 0)
            {
                if (text[i] == '"') nestedStringDepth--;
                continue;
            }

            if (text[i] == '{')
            {
                if (i + 1 < text.Length && text[i + 1] == '{')
                {
                    i++;
                    continue;
                }

                interpolationDepth++;
                continue;
            }

            if (text[i] == '}' && interpolationDepth > 0)
            {
                interpolationDepth--;
                continue;
            }

            if (text[i] == '"')
            {
                if (interpolationDepth > 0)
                {
                    nestedStringDepth++;
                    continue;
                }

                if (text[i + 1] == '"' && text[i + 2] == '"')
                {
                    end = i + 2;
                    containsTarget = false;
                    return false;
                }
            }
        }

        end = text.Length - 1;
        containsTarget = targetOffset >= contentStart && interpolationDepth == 0;
        return containsTarget;
    }

    private static bool ScanInterpolatedString(string text, int start, int targetOffset, out int end, out bool containsTarget)
    {
        var interpolationDepth = 0;
        var nestedStringDepth = 0;

        for (var i = start + 2; i < text.Length; i++)
        {
            if (text[i] == '\n')
            {
                end = i;
                containsTarget = targetOffset > start + 1 && targetOffset < i && interpolationDepth == 0;
                return containsTarget;
            }

            if (targetOffset == i)
            {
                end = i;
                containsTarget = interpolationDepth == 0 || nestedStringDepth > 0;
                return containsTarget;
            }

            if (text[i] == '\\')
            {
                i++;
                continue;
            }

            if (nestedStringDepth > 0)
            {
                if (text[i] == '"') nestedStringDepth--;
                continue;
            }

            if (text[i] == '{')
            {
                if (interpolationDepth == 0 && i + 1 < text.Length && text[i + 1] == '{')
                {
                    i++;
                    continue;
                }

                interpolationDepth++;
                continue;
            }

            if (text[i] == '}' && interpolationDepth > 0)
            {
                interpolationDepth--;
                continue;
            }

            if (text[i] == '}' && interpolationDepth == 0 && i + 1 < text.Length && text[i + 1] == '}')
            {
                i++;
                continue;
            }

            if (text[i] == '"')
            {
                if (interpolationDepth > 0)
                {
                    nestedStringDepth++;
                    continue;
                }

                end = i;
                containsTarget = false;
                return false;
            }
        }

        end = text.Length - 1;
        containsTarget = targetOffset > start + 1 && interpolationDepth == 0;
        return containsTarget;
    }

    private static bool IsEscaped(string text, int quoteIndex)
    {
        var slashCount = 0;
        for (var i = quoteIndex - 1; i >= 0 && text[i] == '\\'; i--)
        {
            slashCount++;
        }

        return slashCount % 2 == 1;
    }
}
