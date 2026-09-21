namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

// ONE ROW OF THE "GO TO SYMBOL IN WORKSPACE" LIST, in the coordinates the editor puts on the wire.
//
// THE COORDINATES CARRY A SHIPPED OFF-BY-ONE AND THIS CONTRACT PINS IT RATHER THAN REPAIRING IT.
// The location table is already 0-based, and this list subtracts one from it again, so every row
// points one line and one column EARLIER than the name it names — and a name on the first line or
// in the first column is clamped to zero rather than going negative. Repairing it would move every
// entry in every client's quick-open list in the same release as an ownership move; it is recorded
// here, visible, for a release that means to change it.
class EditorWorkspaceSymbolRow {
    nameValue: string
    kindValue: EditorSymbolTableKind
    lineValue: int
    startCharacterValue: int
    endCharacterValue: int
    containerNameValue: string?

    Name: string => nameValue
    Kind: EditorSymbolTableKind => kindValue
    Line: int => lineValue
    StartCharacter: int => startCharacterValue
    EndCharacter: int => endCharacterValue
    ContainerName: string? => containerNameValue

    constructor(Name: string, Kind: EditorSymbolTableKind, Line: int, StartCharacter: int, EndCharacter: int, ContainerName: string?) {
        nameValue = Name
        kindValue = Kind
        lineValue = Line
        startCharacterValue = StartCharacter
        endCharacterValue = EndCharacter
        containerNameValue = ContainerName
    }
}

// WHICH NAMES A WORKSPACE SEARCH OFFERS, AND WHERE EACH ONE SITS.
//
// One file's contribution to `workspace/symbol`. The handler asks this of every open document and
// concatenates the answers, so the ORDER here is the order the reader sees within a file: every
// top-level name in symbol-table order, and immediately after a type, its own members.
//
// THE MATCH IS A SUBSEQUENCE, not a substring: "PrsNm" finds "PersonName" because every character
// of the query appears in the name, in order, case-insensitively. An empty query matches
// everything, which is what makes the palette list the whole workspace before anything is typed.
class EditorWorkspaceSymbolFacts {
    static func MatchesQuery(name: string, query: string): bool {
        if string.IsNullOrEmpty(query) {
            return true
        }

        nameLower := name.ToLowerInvariant()
        queryLower := query.ToLowerInvariant()
        nameIndex := 0

        for queryPosition := 0; queryPosition < queryLower.Length; queryPosition++ {
            wanted := queryLower[queryPosition]
            found := -1

            for namePosition := nameIndex; namePosition < nameLower.Length; namePosition++ {
                if nameLower[namePosition] == wanted {
                    found = namePosition
                    break
                }
            }

            if found < 0 {
                return false
            }

            nameIndex = found + 1
        }

        return true
    }

    // WHERE THE LIST SAYS A NAME IS. A name the location table never saw is reported at the top of
    // the file — line 1, column 1 — which the row's own arithmetic then turns into (0, 0).
    static func RowFor(name: string, kind: EditorSymbolTableKind, locations: Dictionary<string, EditorSymbolLocationRow>, containerName: string?): EditorWorkspaceSymbolRow {
        line := 1
        column := 1

        located: EditorSymbolLocationRow? = null
        if locations.TryGetValue(name, out located) && located != null {
            line = located.Line
            column = located.Column
        }

        startCharacter := Math.Max(0, column - 1)
        return new EditorWorkspaceSymbolRow(name, kind, Math.Max(0, line - 1), startCharacter, startCharacter + name.Length, containerName)
    }

    // ONE FILE'S ANSWER TO A WORKSPACE SEARCH. A type's members are offered too, each carrying the
    // type's name as its container; a function's parameters and locals are not, because the symbol
    // table only descends one level and only for the six kinds that name a type.
    static func SymbolRows(unit: CompilationUnit?, text: string?, query: string): List<EditorWorkspaceSymbolRow> {
        rows := new List<EditorWorkspaceSymbolRow>()
        locations := EditorSymbolTableFacts.SymbolLocationTable(unit, text)

        for entry in EditorSymbolTableFacts.SymbolInfoTable(unit, text) {
            name := entry.Key
            info := entry.Value

            if !MatchesQuery(name, query) {
                continue
            }

            rows.Add(RowFor(name, info.Kind, locations, null))

            if !EditorSymbolTableFacts.IsTypeKind(info.Kind) {
                continue
            }

            for member in info.Members {
                if !MatchesQuery(member.Name, query) {
                    continue
                }

                rows.Add(RowFor(member.Name, member.Kind, locations, name))
            }
        }

        return rows
    }
}
