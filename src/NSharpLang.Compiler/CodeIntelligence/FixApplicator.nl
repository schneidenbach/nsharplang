namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// Collects source fixes through the parser, linter and code-fix owners in Compiler Core.
static class FixApplicator {
    static func GetFixesForFile(filePath: string, source: string): List<CodeAction> {
        parseResult := ColumnarParserRecovery.ParseFileAst(source, filePath)
        ast: CompilationUnit? = parseResult.CompilationUnit
        if ast == null {
            ast = new CompilationUnit(
                null,
                new List<ImportDirective>(),
                new List<Statement>(),
                null,
                new List<Declaration>(),
                1,
                1
            )
        }

        fileDir := Path.GetDirectoryName(filePath) ?? Directory.GetCurrentDirectory()
        diagnostics := new List<Diagnostic>()
        if parseResult.CompilationUnit != null {
            linter := new Linter(LinterConfig.FromEditorConfig(fileDir))
            diagnostics = linter.Lint(ast, filePath, source)
        }

        fixService := new CodeFixService()
        allActions := new List<CodeAction>()
        for diagnostic in diagnostics {
            allActions.AddRange(fixService.GetCodeActions(diagnostic, ast, source))
        }

        return allActions
    }
}
