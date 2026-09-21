namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

// ONE EDIT, IN THE EDITOR'S OWN 0-BASED COORDINATES. The compiler's reference results are 1-based
// because diagnostics are; the protocol's ranges are 0-based. The conversion is a decision — it is
// where an off-by-one lives or does not — so it is made once, here, rather than in the handler.
class EditorRenameEditRow {
    lineValue: int
    startCharacterValue: int
    endCharacterValue: int

    Line: int => lineValue
    StartCharacter: int => startCharacterValue
    EndCharacter: int => endCharacterValue

    constructor(Line: int, StartCharacter: int, EndCharacter: int) {
        lineValue = Line
        startCharacterValue = StartCharacter
        endCharacterValue = EndCharacter
    }
}

// ONE FILE'S EDITS, IN THE ORDER THEY MUST BE APPLIED.
class EditorRenameFileEdits {
    fileValue: string
    editsValue: List<EditorRenameEditRow>

    File: string => fileValue
    Edits: List<EditorRenameEditRow> => editsValue

    constructor(File: string, Edits: List<EditorRenameEditRow>) {
        fileValue = File
        editsValue = Edits
    }
}

// HOW A RENAME'S EDITS ARE GROUPED AND ORDERED.
//
// The language server used to spell this as one `GroupBy(...).ToDictionary(...)` with an
// `OrderByDescending(Line).ThenByDescending(Column)` inside it, which put three separate decisions
// in one expression that no test could reach: which edits belong to one file, what order they go
// in, and how a 1-based compiler position becomes a 0-based protocol range.
//
// THE ORDER IS NOT COSMETIC. Edits are applied to a buffer whose later offsets shift when an
// earlier one changes length, so a rename that lengthens a name must rewrite the LAST occurrence
// first. Descending by line, then by column, is what makes a rename from `x` to `xxxxx` land
// correctly, and it is the behaviour this server has always had.
//
// THE FILE GROUPS COME OUT IN FIRST-APPEARANCE ORDER, which is what `GroupBy` yields and what the
// handler then hands to `WorkspaceEdit.Changes`. Nothing downstream depends on it — a workspace
// edit is a map — but it is pinned so that a future reordering is a decision someone makes rather
// than one that happens.
class EditorRenameEditFacts {

    // A REFERENCE'S PROTOCOL RANGE. `Line` and `Column` are 1-based and `Length` counts the name's
    // characters, so the range is `[Column - 1, Column - 1 + Length)` on line `Line - 1`.
    static func EditRow(line: int, column: int, length: int): EditorRenameEditRow {
        start := column - 1
        return new EditorRenameEditRow(line - 1, start, start + length)
    }

    // WHETHER `left` MUST BE APPLIED BEFORE `right`: later in the file goes first.
    static func AppliesBefore(leftLine: int, leftColumn: int, rightLine: int, rightColumn: int): bool {
        if leftLine != rightLine {
            return leftLine > rightLine
        }

        return leftColumn > rightColumn
    }

    // THE WHOLE PLAN: every reference grouped by the file it is in, each file's edits ordered
    // last-first, and every position converted once.
    //
    // The caller hands rows rather than `ReferenceResult`s so that this owner never learns what a
    // reference is; the handler already has to resolve each result's file name to a URI, which is
    // the one step only it can take.
    static func Plan(files: List<string>, lines: List<int>, columns: List<int>, lengths: List<int>): List<EditorRenameFileEdits> {
        groups := new List<EditorRenameFileEdits>()
        groupLines := new List<List<int>>()
        groupColumns := new List<List<int>>()

        index := 0
        while index < files.Count {
            path := files[index]
            line := lines[index]
            column := columns[index]
            length := lengths[index]

            slot := IndexOfFile(groups, path)
            if slot < 0 {
                groups.Add(new EditorRenameFileEdits(path, new List<EditorRenameEditRow>()))
                groupLines.Add(new List<int>())
                groupColumns.Add(new List<int>())
                slot = groups.Count - 1
            }

            InsertOrdered(groups[slot].Edits, groupLines[slot], groupColumns[slot], line, column, EditRow(line, column, length))

            index = index + 1
        }

        return groups
    }

    static func IndexOfFile(groups: List<EditorRenameFileEdits>, path: string): int {
        index := 0
        while index < groups.Count {
            if groups[index].File == path {
                return index
            }

            index = index + 1
        }

        return -1
    }

    // A STABLE ORDERED INSERT, because `OrderByDescending` is a stable sort: two references that
    // agree on both line and column keep the order the reference search produced them in.
    static func InsertOrdered(edits: List<EditorRenameEditRow>, editLines: List<int>, editColumns: List<int>, line: int, column: int, row: EditorRenameEditRow) {
        position := 0
        while position < edits.Count {
            if AppliesBefore(line, column, editLines[position], editColumns[position]) {
                edits.Insert(position, row)
                editLines.Insert(position, line)
                editColumns.Insert(position, column)
                return
            }

            position = position + 1
        }

        edits.Add(row)
        editLines.Add(line)
        editColumns.Add(column)
    }
}
