using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Result of applying fixes to a file.
/// </summary>
public record FixResult(
    string File,
    string OriginalSource,
    string FixedSource,
    List<AppliedFix> AppliedFixes);

/// <summary>
/// A single fix that was applied (or would be applied in dry-run mode).
/// </summary>
public record AppliedFix(
    string File,
    string DiagnosticCode,
    string Title,
    List<TextEdit> Edits);

/// <summary>
/// Applies TextEdits to source files. Handles the tricky parts:
/// - Multiple edits per file (applied bottom-to-top so line numbers stay valid)
/// - Overlapping edit detection
/// - Insert-at-line-start (column 0)
/// </summary>
public static class FixApplicator
{
    /// <summary>
    /// Apply a list of TextEdits to source text.
    /// Edits are applied in reverse order (bottom-to-top) so that line numbers
    /// from earlier edits remain valid.
    /// </summary>
    public static string ApplyEdits(string source, List<TextEdit> edits)
    {
        if (edits.Count == 0) return source;

        var lines = source.Split('\n').ToList();

        // Sort edits bottom-to-top, right-to-left so applying them doesn't shift earlier positions
        var sortedEdits = edits
            .OrderByDescending(e => e.StartLine)
            .ThenByDescending(e => e.StartColumn)
            .ThenBy(e => e.EndLine)
            .ThenBy(e => e.EndColumn)
            .ToList();

        // Detect overlapping edits before applying any changes
        for (int i = 0; i < sortedEdits.Count - 1; i++)
        {
            var high = sortedEdits[i];     // higher start position (later in file)
            var low = sortedEdits[i + 1];  // lower start position (earlier in file)

            // high overlaps with low if high's start is strictly before low's end
            bool overlaps = high.StartLine < low.EndLine
                || (high.StartLine == low.EndLine && high.StartColumn < low.EndColumn);

            if (overlaps)
            {
                throw new InvalidOperationException(
                    $"Overlapping edits detected: edit at ({low.StartLine},{low.StartColumn})..({low.EndLine},{low.EndColumn}) " +
                    $"overlaps with edit at ({high.StartLine},{high.StartColumn})..({high.EndLine},{high.EndColumn})");
            }
        }

        foreach (var edit in sortedEdits)
        {
            lines = ApplySingleEdit(lines, edit);
        }

        return string.Join('\n', lines);
    }

    private static List<string> ApplySingleEdit(List<string> lines, TextEdit edit)
    {
        // Handle no-op edits
        if (edit.StartLine == edit.EndLine && edit.StartColumn == edit.EndColumn && string.IsNullOrEmpty(edit.NewText))
            return lines;

        var startLine = edit.StartLine - 1; // Convert to 0-based
        var endLine = edit.EndLine - 1;
        var startCol = edit.StartColumn;
        var endCol = edit.EndColumn;

        // Clamp to valid range
        startLine = Math.Max(0, Math.Min(startLine, lines.Count));
        endLine = Math.Max(0, Math.Min(endLine, lines.Count));

        if (startLine >= lines.Count)
        {
            // Append at end
            if (!string.IsNullOrEmpty(edit.NewText))
            {
                var newLines = edit.NewText.Split('\n');
                lines.AddRange(newLines);
            }
            return lines;
        }

        // Special case: delete entire line(s)
        if (string.IsNullOrEmpty(edit.NewText) && startCol == 0 && endCol == 0 && endLine > startLine)
        {
            var count = Math.Min(endLine - startLine, lines.Count - startLine);
            lines.RemoveRange(startLine, count);
            return lines;
        }

        // Special case: insert at position (start == end)
        if (startLine == endLine && startCol == endCol)
        {
            if (startLine < lines.Count)
            {
                var line = lines[startLine];
                var col = Math.Min(startCol, line.Length);
                lines[startLine] = line.Substring(0, col) + edit.NewText + line.Substring(col);
            }
            else
            {
                lines.Add(edit.NewText);
            }

            // If the new text contains newlines, split the line
            if (edit.NewText.Contains('\n'))
            {
                var combined = lines[startLine];
                lines.RemoveAt(startLine);
                var splitLines = combined.Split('\n');
                lines.InsertRange(startLine, splitLines);
            }

            return lines;
        }

        // General case: replace range
        var startLineText = startLine < lines.Count ? lines[startLine] : "";
        var endLineText = endLine < lines.Count ? lines[endLine] : "";

        var prefix = startCol <= startLineText.Length ? startLineText.Substring(0, startCol) : startLineText;
        var suffix = endCol <= endLineText.Length ? endLineText.Substring(endCol) : "";

        var replacement = prefix + edit.NewText + suffix;

        // Remove the affected lines
        var removeCount = Math.Min(endLine - startLine + 1, lines.Count - startLine);
        if (removeCount > 0)
        {
            lines.RemoveRange(startLine, removeCount);
        }

        // Insert the replacement
        var replacementLines = replacement.Split('\n');
        lines.InsertRange(startLine, replacementLines);

        return lines;
    }

    /// <summary>
    /// Collect all fixable diagnostics for a file and return the code actions.
    /// </summary>
    public static List<CodeAction> GetFixesForFile(string filePath, string source)
    {
        // Parse
        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath, source);
        var parseResult = parser.ParseCompilationUnit();

        if (parseResult.CompilationUnit == null)
            return new List<CodeAction>();

        // Lint to get diagnostics
        var fileDir = System.IO.Path.GetDirectoryName(filePath) ?? System.IO.Directory.GetCurrentDirectory();
        var linter = new Linter(LinterConfig.FromEditorConfig(fileDir));
        var diagnostics = linter.Lint(parseResult.CompilationUnit, filePath);

        // Get fixes from CodeFixService
        var fixService = new CodeFixService();
        var allActions = new List<CodeAction>();

        foreach (var diagnostic in diagnostics)
        {
            var actions = fixService.GetCodeActions(diagnostic, parseResult.CompilationUnit, source);
            // Only include actions that have actual edits
            allActions.AddRange(actions.Where(a => a.Edits.Count > 0));
        }

        return allActions;
    }
}
