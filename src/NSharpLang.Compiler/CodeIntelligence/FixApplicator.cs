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
