using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Applies TextEdits to source files. Handles the tricky parts:
/// - Multiple edits per file (applied bottom-to-top so line numbers stay valid)
/// - Overlapping edit detection
/// - Insert-at-line-start (column 0)
///
/// TextEdit coordinates are 1-based lines and 0-based, end-exclusive columns.
/// Whole-line deletion ranges may end at the next line, column 0; for the final
/// document line that means one line past EOF at column 0.
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

        var lines = SourceTextLines.SplitLogicalLines(source).ToList();

        var sortedEdits = ValidateAndSortEdits(source, edits);

        foreach (var edit in sortedEdits)
        {
            lines = ApplySingleEdit(lines, edit);
        }

        return string.Join('\n', lines);
    }

    /// <summary>
    /// Validate a set of edits, detect overlaps, and return them in the only safe application order:
    /// bottom-to-top and right-to-left. This is intentionally public so callers such as nlc fix can
    /// preflight a whole fix plan before writing any files.
    /// </summary>
    public static List<TextEdit> ValidateAndSortEdits(IReadOnlyCollection<TextEdit> edits)
    {
        // Sort edits bottom-to-top, right-to-left so applying them doesn't shift earlier positions.
        // Same-position zero-width inserts are applied in reverse input order so the final text
        // preserves the caller's input order.
        var sortedEdits = edits
            .Select((edit, index) => new { Edit = edit, Index = index })
            .OrderByDescending(item => item.Edit.StartLine)
            .ThenByDescending(item => item.Edit.StartColumn)
            .ThenBy(item => item.Edit.EndLine)
            .ThenBy(item => item.Edit.EndColumn)
            .ThenByDescending(item => item.Index)
            .Select(item => item.Edit)
            .ToList();

        foreach (var edit in sortedEdits)
        {
            if (edit.StartLine < 1 || edit.EndLine < 1 || edit.StartColumn < 0 || edit.EndColumn < 0)
            {
                throw new InvalidOperationException(
                    $"Invalid edit position: ({edit.StartLine},{edit.StartColumn})..({edit.EndLine},{edit.EndColumn}). " +
                    "Lines are 1-based and columns must be non-negative.");
            }

            var endBeforeStart = edit.EndLine < edit.StartLine
                || (edit.EndLine == edit.StartLine && edit.EndColumn < edit.StartColumn);
            if (endBeforeStart)
            {
                throw new InvalidOperationException(
                    $"Invalid edit range: ({edit.StartLine},{edit.StartColumn})..({edit.EndLine},{edit.EndColumn}) ends before it starts.");
            }
        }

        ValidateNonOverlapping(sortedEdits);
        return sortedEdits;
    }

    /// <summary>
    /// Source-aware validation for automated writes. Rejects coordinates outside the document instead
    /// of silently clamping them, while preserving the single intentional EOF insertion shape.
    /// </summary>
    public static List<TextEdit> ValidateAndSortEdits(string source, IReadOnlyCollection<TextEdit> edits)
    {
        var sortedEdits = ValidateAndSortEdits(edits);
        var lines = SourceTextLines.SplitLogicalLines(source);
        var eofLine = lines.Length + 1;

        foreach (var edit in sortedEdits)
        {
            var isEofInsert = edit.StartLine == eofLine
                && edit.EndLine == eofLine
                && edit.StartColumn == 0
                && edit.EndColumn == 0;
            if (isEofInsert)
                continue;

            var isLastLineWholeLineDeletion = string.IsNullOrEmpty(edit.NewText)
                && edit.EndLine == eofLine
                && edit.EndColumn == 0
                && edit.StartLine == lines.Length
                && edit.StartColumn == 0;
            if (isLastLineWholeLineDeletion)
                continue;

            if (!IsPositionInDocument(lines, edit.StartLine, edit.StartColumn)
                || !IsPositionInDocument(lines, edit.EndLine, edit.EndColumn))
            {
                throw new InvalidOperationException(
                    $"Invalid edit range: ({edit.StartLine},{edit.StartColumn})..({edit.EndLine},{edit.EndColumn}) is outside the document.");
            }
        }

        return sortedEdits;
    }

    private static void ValidateNonOverlapping(List<TextEdit> sortedEdits)
    {
        // Detect overlapping edits before applying any changes.
        for (int i = 0; i < sortedEdits.Count - 1; i++)
        {
            var high = sortedEdits[i];     // higher start position (later in file)
            var low = sortedEdits[i + 1];  // lower start position (earlier in file)

            // high overlaps with low if high's start is strictly before low's end.
            // Equal start/end is allowed only for multiple zero-width inserts at the same position.
            bool overlaps = high.StartLine < low.EndLine
                || (high.StartLine == low.EndLine && high.StartColumn < low.EndColumn);

            if (overlaps)
            {
                throw new InvalidOperationException(
                    $"Overlapping edits detected: edit at ({low.StartLine},{low.StartColumn})..({low.EndLine},{low.EndColumn}) " +
                    $"overlaps with edit at ({high.StartLine},{high.StartColumn})..({high.EndLine},{high.EndColumn})");
            }
        }
    }

    private static bool IsPositionInDocument(string[] lines, int line, int column)
    {
        if (line < 1 || line > lines.Length)
            return false;

        return column <= lines[line - 1].Length;
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
                var newLines = SourceTextLines.SplitLogicalLines(edit.NewText);
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
                var splitLines = SourceTextLines.SplitLogicalLines(combined);
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
        var replacementLines = SourceTextLines.SplitLogicalLines(replacement);
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

        var ast = parseResult.CompilationUnit ?? new CompilationUnit(
            null,
            new List<ImportDirective>(),
            new List<Statement>(),
            null,
            new List<Declaration>(),
            1,
            1);

        // Lint to get diagnostics. Source-only migration lints still run when parsing failed.
        var fileDir = System.IO.Path.GetDirectoryName(filePath) ?? System.IO.Directory.GetCurrentDirectory();
        var linter = new Linter(LinterConfig.FromEditorConfig(fileDir));
        var diagnostics = parseResult.CompilationUnit == null
            ? linter.LintSource(source, filePath)
            : linter.Lint(ast, filePath, source);

        // Get fixes from CodeFixService
        var fixService = new CodeFixService();
        var allActions = new List<CodeAction>();

        foreach (var diagnostic in diagnostics)
        {
            var actions = fixService.GetCodeActions(diagnostic, ast, source);
            allActions.AddRange(actions);
        }

        return allActions;
    }
}
