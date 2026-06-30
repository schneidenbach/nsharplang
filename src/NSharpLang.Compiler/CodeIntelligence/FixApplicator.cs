using System.Collections.Generic;
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
        return FixApplicatorCore.ApplyEdits(source, edits);
    }

    /// <summary>
    /// Validate a set of edits, detect overlaps, and return them in the only safe application order:
    /// bottom-to-top and right-to-left. This is intentionally public so callers such as nlc fix can
    /// preflight a whole fix plan before writing any files.
    /// </summary>
    public static List<TextEdit> ValidateAndSortEdits(IReadOnlyCollection<TextEdit> edits)
    {
        return FixApplicatorCore.ValidateAndSortEdits(edits);
    }

    /// <summary>
    /// Source-aware validation for automated writes. Rejects coordinates outside the document instead
    /// of silently clamping them, while preserving the single intentional EOF insertion shape.
    /// </summary>
    public static List<TextEdit> ValidateAndSortEdits(string source, IReadOnlyCollection<TextEdit> edits)
    {
        return FixApplicatorCore.ValidateAndSortEdits(source, edits);
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

        // Lint to get fixable diagnostics only after parsing succeeds.
        var fileDir = System.IO.Path.GetDirectoryName(filePath) ?? System.IO.Directory.GetCurrentDirectory();
        var linter = new Linter(LinterConfig.FromEditorConfig(fileDir));
        var diagnostics = parseResult.CompilationUnit == null
            ? new List<Diagnostic>()
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
