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
}
