namespace NSharpLang.Compiler.CodeIntelligence

import NSharpLang.Compiler

// CONTRACTS FOR HIGHLIGHTING A SYMBOL IN ONE FILE. These came out of `DocumentHighlightHandler.cs`,
// where the one-file filter and the 1-based-to-0-based arithmetic sat behind a document manager.
func EdhMap(): BindingMap {
    return new BindingMap()
}

func EdhDeclaration(name: string, filePath: string?, line: int, column: int): SymbolDeclaration {
    return new SymbolDeclaration(name, filePath, line, column, "variable")
}

test "a highlight marks the declaration as a write and every use as a read" {
    map := EdhMap()
    declaration := EdhDeclaration("total", "Program.nl", 3, 5)
    map.RecordDeclaration(declaration)
    map.RecordBinding("Program.nl", 4, 12, 5, declaration)
    map.RecordBinding("Program.nl", 5, 9, 5, declaration)

    rows := EditorDocumentHighlightFacts.HighlightRows(map, "Program.nl", 2, 4)
    assert rows.Count == 3

    assert rows[0].IsWrite
    assert rows[0].Line == 2
    assert rows[0].StartCharacter == 4
    assert rows[0].EndCharacter == 9

    assert !rows[1].IsWrite
    assert rows[1].Line == 3
    assert rows[1].StartCharacter == 11
    assert rows[1].EndCharacter == 16
}

// ANOTHER FILE'S USE IS NOT THIS FILE'S HIGHLIGHT. The binding map answers for the project; the
// view is about the document the reader is looking at.
test "a highlight drops a use that belongs to another file" {
    map := EdhMap()
    declaration := EdhDeclaration("total", "Program.nl", 3, 5)
    map.RecordDeclaration(declaration)
    map.RecordBinding("Other.nl", 9, 1, 5, declaration)

    rows := EditorDocumentHighlightFacts.HighlightRows(map, "Program.nl", 2, 4)
    assert rows.Count == 1
    assert rows[0].IsWrite
}

// A DECLARATION IN ANOTHER FILE IS NOT OFFERED EITHER, but its uses here still are.
test "a highlight keeps the uses of a symbol declared elsewhere" {
    map := EdhMap()
    declaration := EdhDeclaration("total", "Other.nl", 1, 1)
    map.RecordDeclaration(declaration)
    map.RecordBinding("Program.nl", 4, 3, 5, declaration)

    rows := EditorDocumentHighlightFacts.HighlightRows(map, "Program.nl", 3, 2)
    assert rows.Count == 1
    assert !rows[0].IsWrite
    assert rows[0].Line == 3
    assert rows[0].StartCharacter == 2
}

test "a highlight answers nothing when the caret is not on a bound symbol" {
    assert EditorDocumentHighlightFacts.HighlightRows(null, "Program.nl", 0, 0).Count == 0
    assert EditorDocumentHighlightFacts.HighlightRows(EdhMap(), "Program.nl", 40, 40).Count == 0
}

test "a highlight compares file names case-insensitively and treats two absent names as one" {
    assert EditorDocumentHighlightFacts.IsSameFile("Program.nl", "program.nl")
    assert EditorDocumentHighlightFacts.IsSameFile(null, null)
    assert !EditorDocumentHighlightFacts.IsSameFile(null, "Program.nl")
    assert !EditorDocumentHighlightFacts.IsSameFile("Program.nl", null)
    assert !EditorDocumentHighlightFacts.IsSameFile("Program.nl", "Other.nl")
}
