namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// Collects source fixes through the parser, linter and code-fix owners in Compiler Core.
//
// THE ANALYSED UNIT IS THE CALLER'S TO SUPPLY, AND TWO OF THE LINTER'S RULES NEED IT. NL010 and NL002
// are answered by what a file BOUND — which namespace supplied each name it wrote — and those facts
// live on the unit the ANALYZER walked. A unit this owner parses for itself has none, so `nlc fix`
// would have offered fixes for every rule except the two whose fixes matter most: the one that
// deletes an import and the one that adds one. `FixCommand` loads the project once and hands the
// analysed unit down, so the fix list is the same list `nlc check` reports.
static class FixApplicator {
    // TWO EXPLICIT ARITIES RATHER THAN ONE DEFAULTED PARAMETER: omitting a defaulted argument on a
    // static call is a recorded columnar emit decline, and this owner is called from a product path.
    static func GetFixesForFile(filePath: string, source: string): List<CodeAction> {
        return GetFixesForFile(filePath, source, null)
    }

    static func GetFixesForFile(filePath: string, source: string, analyzedUnit: CompilationUnit?): List<CodeAction> {
        ast: CompilationUnit? = analyzedUnit
        lintable := analyzedUnit != null
        if ast == null {
            parseResult := ColumnarParserRecovery.ParseFileAst(source, filePath)
            ast = parseResult.CompilationUnit
            lintable = parseResult.CompilationUnit != null
        }

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
        if lintable {
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
