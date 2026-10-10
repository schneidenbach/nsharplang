namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// ONE LINK OF THE EXPAND-SELECTION CHAIN, in the editor's own 0-based numbering. Every link starts
// at column zero of its first line and ends at the last character of its last line: this feature
// selects whole lines, never part of one, so the shape carries no start column at all.
class EditorSelectionRangeRow {
    startLineValue: int
    endLineValue: int
    endCharacterValue: int

    StartLine: int => startLineValue
    EndLine: int => endLineValue
    EndCharacter: int => endCharacterValue

    constructor(StartLine: int, EndLine: int, EndCharacter: int) {
        startLineValue = StartLine
        endLineValue = EndLine
        endCharacterValue = EndCharacter
    }
}

// WHAT EXPANDING THE SELECTION REACHES NEXT, from the outside in.
//
// THE CHAIN IS ORDERED OUTERMOST FIRST, and the caller threads it into the protocol's nested
// shape by starting from the whole file and wrapping each link in turn — so the LAST row is the
// tightest thing that contains the caret and the first expansion the reader sees.
//
// THE CARET'S COLUMN IS NOT CONSULTED, and that is not an omission. The C# this came from threaded
// a target column through every frame and into a containment test that accepted optional column
// bounds — which every caller left unset. Selecting by line is the shipped behaviour; the column
// was dead weight that read as a rule, and it is gone rather than preserved as a lie. The rows
// below pin that the answer is the same wherever on the line the caret sits.
//
// A FRAME THAT CONTAINS THE CARET STOPS THE SEARCH AT ITS OWN LEVEL. Once a declaration or a
// statement has claimed the line, its SIBLINGS are not examined — the first one that contains the
// caret is the one that does, and a file where two frames claim the same line is a file the parser
// has already mis-shaped.
class EditorSelectionRangeFacts {

    // THE WHOLE FILE IS ALWAYS THE OUTERMOST SELECTION, whatever the AST said — an editor that
    // keeps expanding must eventually reach everything.
    static func WholeFileRow(sourceLines: string[]): EditorSelectionRangeRow {
        lastLine := sourceLines.Length - 1
        if lastLine < 0 {
            lastLine = 0
        }

        endCharacter := 0
        if sourceLines.Length > 0 {
            endCharacter = sourceLines[sourceLines.Length - 1].TrimEnd('\r').Length
        }

        return new EditorSelectionRangeRow(0, lastLine, endCharacter)
    }

    // EVERY FRAME CONTAINING THE CARET, outermost first. `zeroBasedLine` is the editor's own line.
    static func ContainingRows(unit: CompilationUnit?, zeroBasedLine: int, sourceLines: string[]): List<EditorSelectionRangeRow> {
        rows := new List<EditorSelectionRangeRow>()
        if unit == null {
            return rows
        }

        targetLine := zeroBasedLine + 1
        for declaration in unit.Declarations {
            if AppendDeclarationRows(declaration, targetLine, sourceLines, rows) {
                return rows
            }
        }

        return rows
    }

    static func AppendDeclarationRows(declaration: Declaration, targetLine: int, sourceLines: string[], rows: List<EditorSelectionRangeRow>): bool {
        startLine := declaration.Line
        endLine := EndLineOfBrace(declaration.Line, sourceLines)
        if targetLine < startLine || targetLine > endLine {
            return false
        }

        rows.Add(MakeRow(startLine, endLine, sourceLines))

        members := TypeMembers(declaration)
        if members != null {
            for member in members {
                if AppendDeclarationRows(member, targetLine, sourceLines, rows) {
                    return true
                }
            }
        }

        // AN ENUM MEMBER AND A COLUMN ARE ONE LINE EACH, and reached by name rather than by a brace
        // scan — neither has a body for the scan to find.
        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            for enumMember in enumDeclaration.Members {
                if enumMember.Line > 0 && enumMember.Line == targetLine {
                    rows.Add(MakeRow(enumMember.Line, enumMember.Line, sourceLines))
                    return true
                }
            }
        }

        soaDeclaration := declaration as SoaRecordDeclaration
        if soaDeclaration != null {
            for column in soaDeclaration.Columns {
                if column.Line > 0 && column.Line == targetLine {
                    rows.Add(MakeRow(column.Line, column.Line, sourceLines))
                    return true
                }
            }
        }

        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null && functionDeclaration.Body != null {
            AppendStatementRows(functionDeclaration.Body, targetLine, sourceLines, rows)
        }

        return true
    }

    // ONLY THE FOUR DECLARATION FORMS THAT HOLD MEMBERS ARE DESCENDED INTO. An enum's members and
    // an soa record's columns are not `Declaration`s and are handled above.
    static func TypeMembers(declaration: Declaration): List<Declaration>? {
        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            return classDeclaration.Members
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.Members
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.Members
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return interfaceDeclaration.Members
        }

        return null
    }

    static func AppendStatementRows(statement: Statement, targetLine: int, sourceLines: string[], rows: List<EditorSelectionRangeRow>): bool {
        block := statement as BlockStatement
        if block != null {
            blockEnd := EndLineOfBrace(block.Line, sourceLines)
            if targetLine < block.Line || targetLine > blockEnd {
                return false
            }

            rows.Add(MakeRow(block.Line, blockEnd, sourceLines))
            for inner in block.Statements {
                if AppendStatementRows(inner, targetLine, sourceLines, rows) {
                    return true
                }
            }

            return true
        }

        // AN `if` REACHES TO THE END OF ITS LAST BRANCH, following an `else if` chain to its end.
        ifStatement := statement as IfStatement
        if ifStatement != null {
            ifEnd := IfEndLine(ifStatement, sourceLines)
            if targetLine < ifStatement.Line || targetLine > ifEnd {
                return false
            }

            rows.Add(MakeRow(ifStatement.Line, ifEnd, sourceLines))
            if AppendStatementRows(ifStatement.ThenStatement, targetLine, sourceLines, rows) {
                return true
            }

            if ifStatement.ElseStatement != null {
                if AppendStatementRows(ifStatement.ElseStatement, targetLine, sourceLines, rows) {
                    return true
                }
            }

            return true
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            return AppendLoopRows(forStatement.Line, forStatement.Body, targetLine, sourceLines, rows)
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            return AppendLoopRows(foreachStatement.Line, foreachStatement.Body, targetLine, sourceLines, rows)
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            return AppendLoopRows(whileStatement.Line, whileStatement.Body, targetLine, sourceLines, rows)
        }

        // A `try` REACHES TO THE END OF WHATEVER CLOSES IT — the finally block, else the last
        // catch, else the try block itself.
        tryStatement := statement as TryStatement
        if tryStatement != null {
            tryEnd := TryEndLine(tryStatement, sourceLines)
            if targetLine < tryStatement.Line || targetLine > tryEnd {
                return false
            }

            rows.Add(MakeRow(tryStatement.Line, tryEnd, sourceLines))
            if AppendStatementRows(tryStatement.TryBlock, targetLine, sourceLines, rows) {
                return true
            }

            for catchClause in tryStatement.CatchClauses {
                if AppendStatementRows(catchClause.Block, targetLine, sourceLines, rows) {
                    return true
                }
            }

            if tryStatement.FinallyBlock != null {
                if AppendStatementRows(tryStatement.FinallyBlock, targetLine, sourceLines, rows) {
                    return true
                }
            }

            return true
        }

        // A `switch` IS ONE FRAME AND IS NOT DESCENDED INTO. Its cases are not blocks, so there is
        // no tighter frame to offer; expanding from inside a case reaches the whole switch.
        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            switchEnd := EndLineOfBrace(switchStatement.Line, sourceLines)
            if targetLine < switchStatement.Line || targetLine > switchEnd {
                return false
            }

            rows.Add(MakeRow(switchStatement.Line, switchEnd, sourceLines))
            return true
        }

        // EVERY OTHER STATEMENT IS ONE LINE — a return, a binding, an expression. It matches only
        // the line it begins on, which is why a multi-line call expression offers its own first
        // line and then jumps to the block around it.
        if statement.Line == targetLine {
            rows.Add(MakeRow(statement.Line, statement.Line, sourceLines))
            return true
        }

        return false
    }

    static func AppendLoopRows(headerLine: int, body: Statement, targetLine: int, sourceLines: string[], rows: List<EditorSelectionRangeRow>): bool {
        loopEnd := StatementEndLine(body, sourceLines, headerLine)
        if targetLine < headerLine || targetLine > loopEnd {
            return false
        }

        rows.Add(MakeRow(headerLine, loopEnd, sourceLines))
        AppendStatementRows(body, targetLine, sourceLines, rows)
        return true
    }

    static func IfEndLine(ifStatement: IfStatement, sourceLines: string[]): int {
        if ifStatement.ElseStatement != null {
            nested := ifStatement.ElseStatement as IfStatement
            if nested != null {
                return IfEndLine(nested, sourceLines)
            }

            return StatementEndLine(ifStatement.ElseStatement, sourceLines, ifStatement.Line)
        }

        return StatementEndLine(ifStatement.ThenStatement, sourceLines, ifStatement.Line)
    }

    static func TryEndLine(tryStatement: TryStatement, sourceLines: string[]): int {
        if tryStatement.FinallyBlock != null {
            return EndLineOfBrace(tryStatement.FinallyBlock.Line, sourceLines)
        }

        if tryStatement.CatchClauses.Count > 0 {
            return EndLineOfBrace(tryStatement.CatchClauses[tryStatement.CatchClauses.Count - 1].Block.Line, sourceLines)
        }

        return EndLineOfBrace(tryStatement.TryBlock.Line, sourceLines)
    }

    // A BRACED BODY ENDS WHERE ITS BRACE CLOSES; a single-statement body ends on its own line, and
    // a body the parser could not place falls back to the line of whatever owns it.
    static func StatementEndLine(body: Statement, sourceLines: string[], fallbackLine: int): int {
        block := body as BlockStatement
        if block != null {
            return EndLineOfBrace(block.Line, sourceLines)
        }

        if body.Line > 0 {
            return body.Line
        }

        return fallbackLine
    }

    static func MakeRow(oneBasedStartLine: int, oneBasedEndLine: int, sourceLines: string[]): EditorSelectionRangeRow {
        startLine := oneBasedStartLine - 1
        if startLine < 0 {
            startLine = 0
        }

        endLine := oneBasedEndLine - 1
        if endLine < startLine {
            endLine = startLine
        }

        endCharacter := 0
        if endLine < sourceLines.Length {
            endCharacter = sourceLines[endLine].TrimEnd('\r').Length
        }

        return new EditorSelectionRangeRow(startLine, endLine, endCharacter)
    }

    // THE LINE THE BRACE OPENED HERE CLOSES ON, counted by depth. A frame with no brace closes
    // where it started.
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
}
