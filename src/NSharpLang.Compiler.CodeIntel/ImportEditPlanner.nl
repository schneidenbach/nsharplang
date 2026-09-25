namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar


// Quick fixes and completion acceptance share one source placement owner. The header is
// parsed once per completion request, even when many external types are offered.
class ImportEditPlanner {
    ast: object?
    source: string
    insertLine: int
    insertColumn: int
    importPrefix: string
    newline: string
    HeaderEndLine: int

    constructor(ast: object?, source: string) {
        this.ast = ast
        this.source = source
        newline = "\n"
        firstLf := source.IndexOf('\n')
        firstCr := source.IndexOf('\r')
        if firstCr >= 0 && (firstLf < 0 || firstCr < firstLf) {
            newline = "\r"
            if firstLf == firstCr + 1 {
                newline = "\r\n"
            }
        }

        parser := new ColumnarParserRecovery(source, null)
        parser.RunHeader()
        next := parser.Current()
        HeaderEndLine = 0
        if parser.Position > 0 {
            last := parser.Tokens[parser.Position - 1]
            HeaderEndLine = last.Line + FixApplicatorEditEngine.CountLogicalLines(last.Value) - 1
            lexer := new Lexer(source)
            lexer.Tokenize()
            for comment in lexer.Comments {
                // A comment on a header line may span the intended insertion. Comments that
                // start later belong to the following declaration and remain attached to it.
                beforeDeclaration := comment.Line < next.Line || (comment.Line == next.Line && comment.Column < next.Column)
                if comment.Line <= HeaderEndLine && beforeDeclaration {
                    HeaderEndLine = Math.Max(HeaderEndLine, comment.Line + FixApplicatorEditEngine.CountLogicalLines(comment.Text) - 1)
                }
            }
        }

        insertLine = HeaderEndLine + 1
        insertColumn = 0
        importPrefix = ""
        if HeaderEndLine > 0 && next.Type != TokenType.Eof && next.Line <= HeaderEndLine {
            insertLine = next.Line
            insertColumn = next.Column - 1
            importPrefix = newline
        } else {
            nextLine := ""
            headerText := ""
            if HeaderEndLine > 0 && !CodeFixActionHelpers.TryGetSourceLine(source, insertLine, out nextLine) && CodeFixActionHelpers.TryGetSourceLine(source, HeaderEndLine, out headerText) {
                insertLine = HeaderEndLine
                insertColumn = headerText.Length
                importPrefix = newline
            }
        }
    }

    // Is a type of this namespace already in scope here without a new `import`? The file's own
    // namespace and every ENCLOSING one are (`SimpleNamePrecedence` rules 1 and 2 — their types
    // bind with no import whichever assembly declares them, so offering `import NSharpLang.Compiler`
    // to a file in `NSharpLang.Compiler.Columnar` would write a redundant line), and so is every
    // unaliased import. The global namespace is enclosing for every file, but the empty name is
    // never an import to offer, so it is simply in scope.
    static func IsNamespaceInScope(ast: object?, namespaceName: string): bool {
        unit := ast as CompilationUnit
        if unit == null {
            return false
        }

        // COMPILER: the columnar emitter (the committed seed's and the tip's) declines a static call
        // into a referenced assembly that takes a `cond ? null : value` argument
        // (`emit.call.static-member-unmodeled`); a source callee takes it. The maybe-null candidate is
        // bound to a local first.
        candidateNamespace: string? = null
        if namespaceName.Length > 0 {
            candidateNamespace = namespaceName
        }
        if SimpleNamePrecedence.IsLexicalNamespace(AnalyzerDeclarationFileFacts.GetUnitNamespace(unit), candidateNamespace) {
            return true
        }

        for directive in unit.Imports {
            if directive.Alias == null && directive.Namespace == namespaceName {
                return true
            }
        }

        return false
    }

    static func GetEdits(ast: object?, source: string, namespaceName: string): List<TextEdit> {
        planner := new ImportEditPlanner(ast, source)
        return planner.NamespaceEdits(namespaceName)
    }

    func NamespaceEdits(namespaceName: string): List<TextEdit> {
        edits := new List<TextEdit>()
        if namespaceName.Length > 0 && !IsNamespaceInScope(ast, namespaceName) {
            edits.Add(new TextEdit(insertLine, insertColumn, insertLine, insertColumn, importPrefix + "import " + namespaceName + newline))
        }

        return edits
    }

    // The first edit is always the primary word replacement. Remaining edits are disjoint
    // additional edits; when the import touches that word, one combined primary edit owns both.
    func CompletionEdits(namespaceName: string, typeName: string, line: int, column: int): List<TextEdit> {
        lineText := ""
        CodeFixActionHelpers.TryGetSourceLine(source, line, out lineText)
        start := Math.Clamp(column, 0, lineText.Length)
        finish := start
        while start > 0 && IdentifierText.IsPart(lineText[start - 1]) {
            start = start - 1
        }

        while finish < lineText.Length && IdentifierText.IsPart(lineText[finish]) {
            finish = finish + 1
        }

        imports := NamespaceEdits(namespaceName)
        text := typeName
        if imports.Count > 0 && insertLine == line && insertColumn >= start && insertColumn <= finish {
            text = imports[0].NewText + typeName
            if insertColumn == finish && start < finish {
                text = typeName + imports[0].NewText
            }

            imports.Clear()
        }

        edits := new List<TextEdit>()
        edits.Add(new TextEdit(line, start, line, finish, text))
        edits.AddRange(imports)
        return edits
    }
}
