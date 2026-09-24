namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler

// ONE HIGHLIGHT IN THE FILE THE READER IS LOOKING AT, in the editor's own 0-based numbering.
//
// `IsWrite` separates the DECLARATION from every use of it: the editor paints the place a name was
// introduced differently from the places it is read.
class EditorHighlightRow {
    lineValue: int
    startCharacterValue: int
    endCharacterValue: int
    isWriteValue: bool

    Line: int => lineValue
    StartCharacter: int => startCharacterValue
    EndCharacter: int => endCharacterValue
    IsWrite: bool => isWriteValue

    constructor(Line: int, StartCharacter: int, EndCharacter: int, IsWrite: bool) {
        lineValue = Line
        startCharacterValue = StartCharacter
        endCharacterValue = EndCharacter
        isWriteValue = IsWrite
    }
}

// EVERY OCCURRENCE OF THE SYMBOL UNDER THE CARET, IN THIS FILE.
//
// The binding map answers for a whole project, and this view is about ONE file: the declaration is
// offered only when it was declared here, and a use in another file is dropped rather than
// reported against the wrong document. Nothing is painted when the caret is not on a bound symbol
// — a name search would light up unrelated symbols that happen to share the spelling.
//
// THE COMPARISON IS CASE-INSENSITIVE and two absent paths are the same path, which is what the
// editor has always done: the binding map's file names and the editor's come from different ends
// (one from the compiler, one from a `file://` URI) and a case difference between them is not a
// different file on any filesystem this ships to.
class EditorDocumentHighlightFacts {
    static func IsSameFile(left: string?, right: string?): bool {
        if left == null || right == null {
            return left == right
        }

        return string.Equals(left, right, StringComparison.OrdinalIgnoreCase)
    }

    static func HighlightRows(bindings: BindingMap?, filePath: string?, line: int, character: int): List<EditorHighlightRow> {
        rows := new List<EditorHighlightRow>()
        if bindings == null {
            return rows
        }

        // The binding map counts from one; the editor's position counts from zero.
        result := bindings.FindAllReferences(filePath, line + 1, character + 1)
        declaration := result.Declaration
        if declaration == null {
            return rows
        }

        if IsSameFile(declaration.File, filePath) {
            declarationStart := declaration.Column - 1
            rows.Add(new EditorHighlightRow(declaration.Line - 1, declarationStart, declarationStart + Math.Max(1, declaration.Name.Length), true))
        }

        for usage in result.Usages {
            if !IsSameFile(usage.File, filePath) {
                continue
            }

            usageStart := usage.Column - 1
            rows.Add(new EditorHighlightRow(usage.Line - 1, usageStart, usageStart + Math.Max(1, usage.Length), false))
        }

        return rows
    }
}
