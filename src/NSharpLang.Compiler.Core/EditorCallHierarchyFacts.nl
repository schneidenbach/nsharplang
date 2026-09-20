namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

// ONE CALL THE SOURCE MAKES, at the AST's own 1-based coordinates and named by the thing being
// called rather than by what it resolves to — resolution is a separate question, asked of the
// symbol tables afterwards, and a call to something that does not exist is still a call.
class EditorCallSiteRow {
    nameValue: string
    lineValue: int
    columnValue: int

    Name: string => nameValue
    Line: int => lineValue
    Column: int => columnValue

    constructor(Name: string, Line: int, Column: int) {
        nameValue = Name
        lineValue = Line
        columnValue = Column
    }
}

// A FUNCTION AS THE HIERARCHY VIEW POINTS AT IT, 0-based: the whole declaration, and the narrower
// span the editor highlights when the reader clicks the node.
class EditorCallHierarchyRange {
    startLineValue: int
    startCharacterValue: int
    endLineValue: int
    endCharacterValue: int
    selectionEndCharacterValue: int

    StartLine: int => startLineValue
    StartCharacter: int => startCharacterValue
    EndLine: int => endLineValue
    EndCharacter: int => endCharacterValue
    SelectionEndCharacter: int => selectionEndCharacterValue

    constructor(StartLine: int, StartCharacter: int, EndLine: int, EndCharacter: int, SelectionEndCharacter: int) {
        startLineValue = StartLine
        startCharacterValue = StartCharacter
        endLineValue = EndLine
        endCharacterValue = EndCharacter
        selectionEndCharacterValue = SelectionEndCharacter
    }
}

// WHICH FUNCTION IS WHERE, AND WHAT IT CALLS.
//
// Three questions the call-hierarchy view asks of the syntax tree, and all three used to be asked
// three times over in C# — the same nested member walk appeared in the prepare handler, the
// incoming handler and the outgoing handler, each with its own copy and its own small drift.
//
// THE MEMBER WALK DESCENDS, unlike the implementation and outline walks: a method is a function
// for this purpose, so a class's members are searched and so are a struct's, a record's and an
// interface's. The FIRST match in source order wins.
//
// THIS IS NOT `CodeIntelligenceCallGraph`. That owner answers `query callgraph`, which reports
// every caller in a project keyed by a qualified owner name. This one answers a view that has
// already been handed ONE function and asks what that function reaches — a narrower walk over one
// declaration, at editor coordinates.
class EditorCallHierarchyFacts {

    // THE FUNCTION WITH THIS NAME DECLARED ON THIS LINE. Name and line together, because a name
    // alone is ambiguous across overloads and a line alone says nothing about what was clicked.
    static func FunctionAtLine(unit: CompilationUnit?, name: string, oneBasedLine: int): FunctionDeclaration? {
        if unit == null {
            return null
        }

        return FunctionAtLineIn(unit.Declarations, name, oneBasedLine)
    }

    static func FunctionAtLineIn(declarations: List<Declaration>, name: string, oneBasedLine: int): FunctionDeclaration? {
        for declaration in declarations {
            functionDeclaration := declaration as FunctionDeclaration
            if functionDeclaration != null && String.Equals(functionDeclaration.Name, name, StringComparison.Ordinal) && functionDeclaration.Line == oneBasedLine {
                return functionDeclaration
            }

            members := MemberList(declaration)
            if members != null {
                nested := FunctionAtLineIn(members, name, oneBasedLine)
                if nested != null {
                    return nested
                }
            }
        }

        return null
    }

    // THE FUNCTION A LINE FALLS INSIDE. "Inside" reaches from the declaration's own line to the
    // line `DeclarationFacts` estimates it ends on, so the view and every other consumer of that
    // estimate cannot disagree about how far a function reaches.
    static func EnclosingFunction(unit: CompilationUnit?, oneBasedLine: int): FunctionDeclaration? {
        if unit == null {
            return null
        }

        return EnclosingFunctionIn(unit.Declarations, oneBasedLine)
    }

    static func EnclosingFunctionIn(declarations: List<Declaration>, oneBasedLine: int): FunctionDeclaration? {
        for declaration in declarations {
            functionDeclaration := declaration as FunctionDeclaration
            if functionDeclaration != null && oneBasedLine >= functionDeclaration.Line && oneBasedLine <= DeclarationFacts.EstimateDeclarationEndLine(functionDeclaration) {
                return functionDeclaration
            }

            members := MemberList(declaration)
            if members != null {
                nested := EnclosingFunctionIn(members, oneBasedLine)
                if nested != null {
                    return nested
                }
            }
        }

        return null
    }

    static func MemberList(declaration: Declaration): List<Declaration>? {
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

    // THE SPAN OF A NODE, 0-based. The selection is always the name's width from the declaration's
    // own column; the full range reaches the estimated end line, and ends at column ZERO when it
    // reaches a later line — a range whose end column preceded its start would be rejected, so on
    // a ONE-LINE function the end is pushed out to the name's width instead.
    //
    // A CALLER THE WALK COULD NOT FIND still gets a node, placed on the line of the call itself.
    // That is what lets a reference in a file the editor has not parsed appear in the list under
    // whatever name the reference carried, rather than disappearing from it.
    static func FunctionRange(declaration: FunctionDeclaration?, name: string, fallbackZeroBasedLine: int): EditorCallHierarchyRange {
        startLine := fallbackZeroBasedLine
        startCharacter := 0
        endLine := fallbackZeroBasedLine

        if declaration != null {
            startLine = declaration.Line - 1
            if startLine < 0 {
                startLine = 0
            }

            startCharacter = declaration.Column - 1
            if startCharacter < 0 {
                startCharacter = 0
            }

            endLine = DeclarationFacts.EstimateDeclarationEndLine(declaration) - 1
            if endLine < 0 {
                endLine = 0
            }
        }

        endCharacter := 0
        if endLine == startLine {
            endCharacter = startCharacter + name.Length
        }

        return new EditorCallHierarchyRange(startLine, startCharacter, endLine, endCharacter, startCharacter + name.Length)
    }

    // EVERY CALL THE FUNCTION MAKES, in the order the walk meets them.
    //
    // A CALL IS NAMED BY THE LAST THING IN ITS CALLEE — the identifier, or the member after the
    // dot — and located where that CALLEE begins, not where the argument list opens. A callee the
    // walk cannot name, such as an invoked lambda or an indexer result, contributes no row but its
    // arguments are still searched.
    static func OutgoingCallSites(declaration: FunctionDeclaration): List<EditorCallSiteRow> {
        rows := new List<EditorCallSiteRow>()
        if declaration.Body != null {
            AppendFromStatements(declaration.Body.Statements, rows)
        }

        if declaration.ExpressionBody != null {
            AppendFromExpression(declaration.ExpressionBody, rows)
        }

        return rows
    }

    // THE STATEMENT WALK IS DELIBERATELY PARTIAL, and this is the shipped reach: an expression
    // statement, a binding's initialiser, a return value, a nested block, both arms of an `if`
    // with its condition, a `while` with its condition, a `for` BODY — without its condition or
    // its iterator — and a `foreach` collection with its body. A `try`, a `switch`, a `using` and
    // a `lock` are NOT walked, so calls inside them do not appear in the outgoing list. Recorded
    // rather than widened: widening it is a behaviour change and belongs to whoever wants it.
    static func AppendFromStatements(statements: List<Statement>, rows: List<EditorCallSiteRow>) {
        for statement in statements {
            expressionStatement := statement as ExpressionStatement
            if expressionStatement != null {
                AppendFromExpression(expressionStatement.Expression, rows)
                continue
            }

            variableDeclaration := statement as VariableDeclarationStatement
            if variableDeclaration != null {
                if variableDeclaration.Initializer != null {
                    AppendFromExpression(variableDeclaration.Initializer, rows)
                }

                continue
            }

            returnStatement := statement as ReturnStatement
            if returnStatement != null {
                if returnStatement.Value != null {
                    AppendFromExpression(returnStatement.Value, rows)
                }

                continue
            }

            block := statement as BlockStatement
            if block != null {
                AppendFromStatements(block.Statements, rows)
                continue
            }

            ifStatement := statement as IfStatement
            if ifStatement != null {
                AppendFromExpression(ifStatement.Condition, rows)
                AppendFromStatement(ifStatement.ThenStatement, rows)
                if ifStatement.ElseStatement != null {
                    AppendFromStatement(ifStatement.ElseStatement, rows)
                }

                continue
            }

            whileStatement := statement as WhileStatement
            if whileStatement != null {
                AppendFromExpression(whileStatement.Condition, rows)
                AppendFromStatement(whileStatement.Body, rows)
                continue
            }

            forStatement := statement as ForStatement
            if forStatement != null {
                AppendFromStatement(forStatement.Body, rows)
                continue
            }

            foreachStatement := statement as ForeachStatement
            if foreachStatement != null {
                AppendFromExpression(foreachStatement.Collection, rows)
                AppendFromStatement(foreachStatement.Body, rows)
            }
        }
    }

    // A single statement is walked as a one-statement list, so an unbraced branch behaves exactly
    // as a braced one does.
    static func AppendFromStatement(statement: Statement, rows: List<EditorCallSiteRow>) {
        block := statement as BlockStatement
        if block != null {
            AppendFromStatements(block.Statements, rows)
            return
        }

        single := new List<Statement>()
        single.Add(statement)
        AppendFromStatements(single, rows)
    }

    static func AppendFromExpression(expression: Expression, rows: List<EditorCallSiteRow>) {
        call := expression as CallExpression
        if call != null {
            name := CalleeName(call.Callee)
            if name != null {
                rows.Add(new EditorCallSiteRow(name, call.Callee.Line, call.Callee.Column))
            }

            for argument in call.Arguments {
                AppendFromExpression(argument.Value, rows)
            }

            // The callee is walked AFTER the arguments, which is what puts a chained call's outer
            // name before its inner one.
            AppendFromExpression(call.Callee, rows)
            return
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            AppendFromExpression(memberAccess.Object, rows)
            return
        }

        binary := expression as BinaryExpression
        if binary != null {
            AppendFromExpression(binary.Left, rows)
            AppendFromExpression(binary.Right, rows)
            return
        }

        unary := expression as UnaryExpression
        if unary != null {
            AppendFromExpression(unary.Operand, rows)
            return
        }

        indexAccess := expression as IndexAccessExpression
        if indexAccess != null {
            AppendFromExpression(indexAccess.Object, rows)
            AppendFromExpression(indexAccess.Index, rows)
            return
        }

        assignment := expression as AssignmentExpression
        if assignment != null {
            AppendFromExpression(assignment.Target, rows)
            AppendFromExpression(assignment.Value, rows)
            return
        }

        lambda := expression as LambdaExpression
        if lambda != null {
            if lambda.BlockBody != null {
                AppendFromStatement(lambda.BlockBody, rows)
            }

            if lambda.ExpressionBody != null {
                AppendFromExpression(lambda.ExpressionBody, rows)
            }
        }
    }

    static func CalleeName(callee: Expression): string? {
        identifier := callee as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        memberAccess := callee as MemberAccessExpression
        if memberAccess != null {
            return memberAccess.MemberName
        }

        return null
    }
}
