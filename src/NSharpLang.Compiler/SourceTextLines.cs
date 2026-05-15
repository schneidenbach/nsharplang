using System;

namespace NSharpLang.Compiler;

/// <summary>
/// Helpers for converting source text into logical lines for editor coordinates.
/// TextEdit columns are measured inside line content only; CR/LF characters are
/// separators and must never contribute to 0-based end-exclusive column values.
/// </summary>
public static class SourceTextLines
{
    public static string[] SplitLogicalLines(string source)
    {
        ArgumentNullException.ThrowIfNull(source);

        return source
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Split('\n');
    }
}
