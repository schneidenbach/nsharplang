namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// WHICH OUTLINE ICON A DECLARATION GETS. These are the protocol's own symbol kinds, named here by
// the only names N# can give them, and mapped to the wire numbers by the caller — the outline
// shows a record as a class and a union as an enum, and THAT decision is here rather than in the
// mapping, because it is a judgement about N# and not about LSP.
enum EditorSymbolKind {
    Function,
    Method,
    Class,
    Struct,
    Interface,
    Enum,
    EnumMember,
    Field,
    Property,
    Constructor
}

// ONE ROW OF THE OUTLINE, in the editor's own 0-based numbering, with its children beneath it.
//
// TWO SPANS, AND THE RELATIONSHIP BETWEEN THEM IS A PROTOCOL RULE: the full range must CONTAIN the
// selection range, or a client is entitled to drop the symbol. That is why the end column is
// measured and then widened rather than simply reported.
class EditorDocumentSymbolRow {
    nameValue: string
    kindValue: EditorSymbolKind
    detailValue: string?
    startLineValue: int
    endLineValue: int
    endCharacterValue: int
    selectionEndCharacterValue: int
    childrenValue: List<EditorDocumentSymbolRow>

    Name: string => nameValue
    Kind: EditorSymbolKind => kindValue
    Detail: string? => detailValue
    StartLine: int => startLineValue
    EndLine: int => endLineValue
    EndCharacter: int => endCharacterValue
    SelectionEndCharacter: int => selectionEndCharacterValue
    Children: List<EditorDocumentSymbolRow> => childrenValue

    constructor(Name: string, Kind: EditorSymbolKind, Detail: string?, StartLine: int, EndLine: int, EndCharacter: int, SelectionEndCharacter: int, Children: List<EditorDocumentSymbolRow>) {
        nameValue = Name
        kindValue = Kind
        detailValue = Detail
        startLineValue = StartLine
        endLineValue = EndLine
        endCharacterValue = EndCharacter
        selectionEndCharacterValue = SelectionEndCharacter
        childrenValue = Children
    }
}

// THE OUTLINE OF A FILE: what a reader sees in the editor's symbol tree, in source order, nested.
//
// A DECLARATION THE OUTLINE HAS NO ROW FOR IS SKIPPED, NOT GUESSED AT — an import, a top-level
// statement, an extension block. Skipping is why the walk returns a nullable row and the callers
// test it.
//
// THE END OF A DECLARATION IS FOUND BY BRACE DEPTH, and a declaration with no brace at all — an
// arrow-bodied member, a field — ends on the line it began. `EditorFoldingFacts` asks the same
// question for a different purpose and answers it the same way; the two are kept apart because
// folding measures a REGION TO HIDE and the outline measures a SYMBOL TO SELECT, and only the
// second has to contain its own selection range.
class EditorDocumentSymbolFacts {
    static func SymbolRows(unit: CompilationUnit?, sourceLines: string[]?): List<EditorDocumentSymbolRow> {
        rows := new List<EditorDocumentSymbolRow>()
        if unit == null {
            return rows
        }

        for declaration in unit.Declarations {
            row := SymbolRow(declaration, sourceLines)
            if row != null {
                rows.Add(row)
            }
        }

        return rows
    }

    static func SymbolRow(declaration: Declaration, sourceLines: string[]?): EditorDocumentSymbolRow? {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            return MakeRow(functionDeclaration.Name, EditorSymbolKind.Function, DetailText(functionDeclaration.ReturnType), functionDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, NoChildren())
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            return MakeRow(classDeclaration.Name, EditorSymbolKind.Class, null, classDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, MemberRows(classDeclaration.Members, sourceLines))
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            return MakeRow(structDeclaration.Name, EditorSymbolKind.Struct, null, structDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, MemberRows(structDeclaration.Members, sourceLines))
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            return MakeRow(recordDeclaration.Name, EditorSymbolKind.Class, "record", recordDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, MemberRows(recordDeclaration.Members, sourceLines))
        }

        soaDeclaration := declaration as SoaRecordDeclaration
        if soaDeclaration != null {
            return MakeRow(soaDeclaration.Name, EditorSymbolKind.Class, "soa", soaDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, ColumnRows(soaDeclaration, sourceLines))
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return MakeRow(interfaceDeclaration.Name, EditorSymbolKind.Interface, null, interfaceDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, MemberRows(interfaceDeclaration.Members, sourceLines))
        }

        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            return MakeRow(enumDeclaration.Name, EditorSymbolKind.Enum, null, enumDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, EnumMemberRows(enumDeclaration, sourceLines))
        }

        unionDeclaration := declaration as UnionDeclaration
        if unionDeclaration != null {
            return MakeRow(unionDeclaration.Name, EditorSymbolKind.Enum, "union", unionDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, NoChildren())
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            return MakeRow(fieldDeclaration.Name, EditorSymbolKind.Field, DetailText(fieldDeclaration.Type), fieldDeclaration.Line, fieldDeclaration.Line, sourceLines, NoChildren())
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            return MakeRow(propertyDeclaration.Name, EditorSymbolKind.Property, DetailText(propertyDeclaration.Type), propertyDeclaration.Line, propertyDeclaration.Line, sourceLines, NoChildren())
        }

        testDeclaration := declaration as TestDeclaration
        if testDeclaration != null {
            return MakeRow(testDeclaration.Description, EditorSymbolKind.Method, "test", testDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, NoChildren())
        }

        setupDeclaration := declaration as SetupDeclaration
        if setupDeclaration != null {
            return MakeRow("setup", EditorSymbolKind.Constructor, "setup", setupDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, NoChildren())
        }

        teardownDeclaration := declaration as TeardownDeclaration
        if teardownDeclaration != null {
            return MakeRow("teardown", EditorSymbolKind.Constructor, "teardown", teardownDeclaration.Line, EndLine(declaration.Line, sourceLines), sourceLines, NoChildren())
        }

        return null
    }

    // THE DETAIL IS THE TYPE AS IT WAS WRITTEN, and `TypeReferenceFacts` already owns that
    // spelling — it is the same text every `TypeReference`'s own `ToString` answers, arm for arm.
    // A member with no declared type carries no detail rather than the word "void".
    static func DetailText(typeRef: TypeReference?): string? {
        if typeRef == null {
            return null
        }

        return TypeReferenceFacts.GetDisplayName(typeRef)
    }

    static func NoChildren(): List<EditorDocumentSymbolRow> {
        return new List<EditorDocumentSymbolRow>()
    }

    static func MemberRows(members: List<Declaration>, sourceLines: string[]?): List<EditorDocumentSymbolRow> {
        rows := new List<EditorDocumentSymbolRow>()
        for member in members {
            row := SymbolRow(member, sourceLines)
            if row != null {
                rows.Add(row)
            }
        }

        return rows
    }

    static func EnumMemberRows(declaration: EnumDeclaration, sourceLines: string[]?): List<EditorDocumentSymbolRow> {
        rows := new List<EditorDocumentSymbolRow>()
        for member in declaration.Members {
            rows.Add(MakeRow(member.Name, EditorSymbolKind.EnumMember, null, member.Line, member.Line, sourceLines, NoChildren()))
        }

        return rows
    }

    static func ColumnRows(declaration: SoaRecordDeclaration, sourceLines: string[]?): List<EditorDocumentSymbolRow> {
        rows := new List<EditorDocumentSymbolRow>()
        for column in declaration.Columns {
            rows.Add(MakeRow(column.Name, EditorSymbolKind.Field, DetailText(column.Type), column.Line, column.Line, sourceLines, NoChildren()))
        }

        return rows
    }

    // THE TWO SPANS, AND THE THREE CLAMPS THAT KEEP THEM LEGAL.
    //
    //   * The end line never precedes the start line, whatever the brace scan found.
    //   * The selection cannot run past the end of the line it sits on, so a symbol whose name is
    //     longer than its own source line — a test's description, which is a sentence — stops at
    //     the line's end instead of pointing past it.
    //   * On a SINGLE-LINE symbol the full range is then widened to cover the selection, because
    //     the protocol requires containment and the line's own length is not always enough.
    //
    // A file whose text is not available measures nothing: the end column is left at the widest
    // value an int can carry, which is what the editor was shipped doing.
    static func MakeRow(name: string, kind: EditorSymbolKind, detail: string?, oneBasedStartLine: int, oneBasedEndLine: int, sourceLines: string[]?, children: List<EditorDocumentSymbolRow>): EditorDocumentSymbolRow {
        startLine := oneBasedStartLine - 1
        if startLine < 0 {
            startLine = 0
        }

        endLine := oneBasedEndLine - 1
        if endLine < startLine {
            endLine = startLine
        }

        endCharacter := UnmeasuredLineEnd
        if sourceLines != null && endLine < sourceLines.Length {
            endCharacter = sourceLines[endLine].TrimEnd('\r').Length
        }

        startLineLength := endCharacter
        if sourceLines != null && startLine < sourceLines.Length {
            startLineLength = sourceLines[startLine].TrimEnd('\r').Length
        }

        selectionEnd := name.Length
        if selectionEnd > startLineLength {
            selectionEnd = startLineLength
        }

        if startLine == endLine && endCharacter < selectionEnd {
            endCharacter = selectionEnd
        }

        return new EditorDocumentSymbolRow(name, kind, detail, startLine, endLine, endCharacter, selectionEnd, children)
    }

    // The end column for a file whose text the editor did not hand over. It is deliberately the
    // largest int rather than zero: a range that covers everything is a range a client will not
    // reject for failing to contain its own selection.
    static UnmeasuredLineEnd: int => 2147483647

    // THE LINE THE DECLARATION'S OWN BRACE CLOSES ON, counted by depth. A declaration with no brace
    // closes where it started.
    static func EndLine(oneBasedStartLine: int, sourceLines: string[]?): int {
        if sourceLines == null || oneBasedStartLine <= 0 {
            return oneBasedStartLine
        }

        depth := 0
        foundOpen := false
        index := oneBasedStartLine - 1
        while index < sourceLines.Length {
            line := sourceLines[index]
            column := 0
            while column < line.Length {
                character := line[column]
                if character == '{' {
                    depth = depth + 1
                    foundOpen = true
                } else if character == '}' {
                    depth = depth - 1
                    if foundOpen && depth == 0 {
                        return index + 1
                    }
                }

                column = column + 1
            }

            index = index + 1
        }

        return oneBasedStartLine
    }
}
