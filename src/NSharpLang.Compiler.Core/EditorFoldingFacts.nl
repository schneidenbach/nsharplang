namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// ONE FOLDABLE REGION OF A FILE, in the editor's own 0-based line numbering.
//
// `StartCharacter` and `EndCharacter` are OPTIONAL and their absence is meaningful: a client that
// is told only the lines folds whole lines, and that is the right answer for an import group and a
// comment block. A declaration says where on the last line the region ends, so folding it leaves
// the closing brace visible. `Kind` is the protocol's own vocabulary — the empty string means the
// region has no kind, which is what everything but imports and comments answers.
class EditorFoldingRow {
    startLineValue: int
    startCharacterValue: int?
    endLineValue: int
    endCharacterValue: int?
    kindValue: string

    StartLine: int => startLineValue
    StartCharacter: int? => startCharacterValue
    EndLine: int => endLineValue
    EndCharacter: int? => endCharacterValue
    Kind: string => kindValue

    constructor(StartLine: int, StartCharacter: int?, EndLine: int, EndCharacter: int?, Kind: string) {
        startLineValue = StartLine
        startCharacterValue = StartCharacter
        endLineValue = EndLine
        endCharacterValue = EndCharacter
        kindValue = Kind
    }
}

// WHAT A FILE OFFERS TO FOLD, and in what order. The order is part of the answer: an editor shows
// the regions in the order it is given them, so imports come first, then every declaration in
// source order with its members and block statements nested beneath it, and finally the multi-line
// comments the lexer kept.
//
// A region is offered only when it spans MORE THAN ONE LINE, because folding a single line hides
// nothing and an editor that is handed one draws a control that does nothing.
class EditorFoldingFacts {
    static ImportsKind: string => "imports"
    static CommentKind: string => "comment"
    static NoKind: string => ""

    static func FoldingRows(unit: CompilationUnit?, sourceLines: string[], tokens: List<Token>?): List<EditorFoldingRow> {
        rows := new List<EditorFoldingRow>()

        if unit != null {
            AppendImportRow(unit, rows)
            for declaration in unit.Declarations {
                AppendDeclarationRows(declaration, sourceLines, rows)
            }
        }

        AppendCommentRows(tokens, rows)
        return rows
    }

    // THE IMPORT BLOCK IS ONE REGION, from the first `import` to the last. One import is not a
    // block, and a run that all sits on one line has nothing to hide.
    static func AppendImportRow(unit: CompilationUnit, rows: List<EditorFoldingRow>) {
        imports := unit.Imports
        if imports.Count < 2 {
            return
        }

        firstLine := imports[0].Line
        lastLine := imports[imports.Count - 1].Line
        if lastLine > firstLine {
            rows.Add(new EditorFoldingRow(firstLine - 1, null, lastLine - 1, null, ImportsKind))
        }
    }

    static func AppendDeclarationRows(declaration: Declaration, sourceLines: string[], rows: List<EditorFoldingRow>) {
        startLine := declaration.Line - 1
        endLine := EndLineOfBrace(declaration.Line, sourceLines) - 1

        if endLine > startLine {
            rows.Add(new EditorFoldingRow(startLine, 0, endLine, LineEndColumn(sourceLines, endLine), NoKind))
        }

        members := DeclarationFacts.GetDeclarationMembers(declaration)
        if members != null {
            index := 0
            while index < members.Count {
                member := members[index] as Declaration
                if member != null {
                    AppendDeclarationRows(member, sourceLines, rows)
                }

                index = index + 1
            }
        }

        function := declaration as FunctionDeclaration
        if function != null && function.Body != null {
            AppendStatementRows(function.Body, sourceLines, rows)
        }
    }

    // A BLOCK THAT IS THE BODY OF SOMETHING is the foldable unit, not the statement that owns it —
    // an `if` and its `else` each fold their own block, and the `switch` folds through whatever
    // declaration contains it.
    static func AppendStatementRows(statement: Statement?, sourceLines: string[], rows: List<EditorFoldingRow>) {
        if statement == null {
            return
        }

        block := statement as BlockStatement
        if block != null {
            for inner in block.Statements {
                AppendStatementRows(inner, sourceLines, rows)
            }

            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            AppendBlockRow(ifStatement.ThenStatement, sourceLines, rows)
            if ifStatement.ElseStatement != null {
                AppendBlockRow(ifStatement.ElseStatement, sourceLines, rows)
            }

            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            AppendBlockRow(whileStatement.Body, sourceLines, rows)
            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            AppendBlockRow(forStatement.Body, sourceLines, rows)
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            AppendBlockRow(foreachStatement.Body, sourceLines, rows)
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            AppendBlockRow(tryStatement.TryBlock, sourceLines, rows)
            for catchClause in tryStatement.CatchClauses {
                AppendBlockRow(catchClause.Block, sourceLines, rows)
            }

            if tryStatement.FinallyBlock != null {
                AppendBlockRow(tryStatement.FinallyBlock, sourceLines, rows)
            }
        }
    }

    static func AppendBlockRow(statement: Statement?, sourceLines: string[], rows: List<EditorFoldingRow>) {
        block := statement as BlockStatement
        if block == null || block.Statements.Count == 0 {
            return
        }

        startLine := block.Line - 1
        endLine := EndLineOfBrace(block.Line, sourceLines) - 1
        if endLine > startLine {
            rows.Add(new EditorFoldingRow(startLine, null, endLine, LineEndColumn(sourceLines, endLine), NoKind))
        }

        for inner in block.Statements {
            AppendStatementRows(inner, sourceLines, rows)
        }
    }

    // A MULTI-LINE COMMENT IS ITS OWN REGION, measured by the newlines the lexer kept in its text
    // rather than by a second scan of the file.
    static func AppendCommentRows(tokens: List<Token>?, rows: List<EditorFoldingRow>) {
        if tokens == null {
            return
        }

        for token in tokens {
            if token.Type == TokenType.MultiLineComment {
                startLine := token.Line - 1
                endLine := startLine + token.Value.Split('\n').Length - 1
                if endLine > startLine {
                    rows.Add(new EditorFoldingRow(startLine, null, endLine, null, CommentKind))
                }
            }
        }
    }

    // THE LINE THE BRACE OPENED ON THIS LINE CLOSES ON, counted by depth from the declaration's own
    // line. A declaration with no brace at all — an arrow body, a one-line member — closes where it
    // started, which is what makes it span one line and therefore offer nothing.
    static func EndLineOfBrace(oneBasedStartLine: int, sourceLines: string[]): int {
        if oneBasedStartLine <= 0 {
            return oneBasedStartLine
        }

        depth := 0
        foundOpen := false
        index := oneBasedStartLine - 1
        while index < sourceLines.Length {
            line := sourceLines[index]
            for character in line {
                if character == '{' {
                    depth = depth + 1
                    foundOpen = true
                } else if character == '}' {
                    depth = depth - 1
                    if foundOpen && depth == 0 {
                        return index + 1
                    }
                }
            }

            index = index + 1
        }

        return oneBasedStartLine
    }

    // The last column of a line, with a carriage return not counted — a file with CRLF endings must
    // not fold to a column one past the text a reader can see.
    static func LineEndColumn(sourceLines: string[], zeroBasedLine: int): int {
        if zeroBasedLine < 0 || zeroBasedLine >= sourceLines.Length {
            return 0
        }

        return sourceLines[zeroBasedLine].TrimEnd('\r').Length
    }
}
