using System;
using System.Collections.Generic;
using NSharpLang.Compiler.CodeIntelligence;

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

        var lines = new List<string>();
        for (var lineNumber = 1; ; lineNumber++)
        {
            var line = CodeIntelligenceTextUtilities.GetSourceLine(source, lineNumber);
            if (line == null)
                return lines.ToArray();

            lines.Add(line);
        }
    }
}
