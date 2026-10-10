namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

class EditorRenameEditFixture {
    static func Strings(values: string[]): List<string> {
        list := new List<string>()
        index := 0
        while index < values.Length {
            list.Add(values[index])
            index = index + 1
        }

        return list
    }

    static func Ints(values: int[]): List<int> {
        list := new List<int>()
        index := 0
        while index < values.Length {
            list.Add(values[index])
            index = index + 1
        }

        return list
    }
}

test "a reference's protocol range is its 1-based position made 0-based, widened by its length" {
    row := EditorRenameEditFacts.EditRow(1, 12, 10)

    assert row.Line == 0
    assert row.StartCharacter == 11
    assert row.EndCharacter == 21
}

test "a reference at the first column of the first line starts at zero" {
    row := EditorRenameEditFacts.EditRow(1, 1, 1)

    assert row.Line == 0
    assert row.StartCharacter == 0
    assert row.EndCharacter == 1
}

// THE ORDER IS NOT COSMETIC: an edit that lengthens a name shifts every later offset, so the LAST
// occurrence has to be rewritten first.
test "a later line is applied before an earlier one" {
    assert EditorRenameEditFacts.AppliesBefore(9, 1, 3, 1)
    assert !EditorRenameEditFacts.AppliesBefore(3, 1, 9, 1)
}

test "on one line, a later column is applied before an earlier one" {
    assert EditorRenameEditFacts.AppliesBefore(4, 20, 4, 5)
    assert !EditorRenameEditFacts.AppliesBefore(4, 5, 4, 20)
}

test "a position does not apply before itself" {
    assert !EditorRenameEditFacts.AppliesBefore(4, 5, 4, 5)
}

test "one file's edits come out last-first" {
    files := EditorRenameEditFixture.Strings(["Program.nl", "Program.nl", "Program.nl"])
    lines := EditorRenameEditFixture.Ints([3, 9, 5])
    columns := EditorRenameEditFixture.Ints([1, 1, 1])
    lengths := EditorRenameEditFixture.Ints([4, 4, 4])

    plan := EditorRenameEditFacts.Plan(files, lines, columns, lengths)

    assert plan.Count == 1
    assert plan[0].File == "Program.nl"

    edits := plan[0].Edits
    assert edits.Count == 3
    assert edits[0].Line == 8
    assert edits[1].Line == 4
    assert edits[2].Line == 2
}

test "two occurrences on one line come out rightmost first" {
    files := EditorRenameEditFixture.Strings(["Program.nl", "Program.nl"])
    lines := EditorRenameEditFixture.Ints([4, 4])
    columns := EditorRenameEditFixture.Ints([5, 20])
    lengths := EditorRenameEditFixture.Ints([3, 3])

    plan := EditorRenameEditFacts.Plan(files, lines, columns, lengths)
    edits := plan[0].Edits

    assert edits.Count == 2
    assert edits[0].StartCharacter == 19
    assert edits[1].StartCharacter == 4
}

test "references are grouped by file, in first-appearance order" {
    files := EditorRenameEditFixture.Strings(["A.nl", "B.nl", "A.nl", "C.nl", "B.nl"])
    lines := EditorRenameEditFixture.Ints([1, 2, 3, 4, 5])
    columns := EditorRenameEditFixture.Ints([1, 1, 1, 1, 1])
    lengths := EditorRenameEditFixture.Ints([2, 2, 2, 2, 2])

    plan := EditorRenameEditFacts.Plan(files, lines, columns, lengths)

    assert plan.Count == 3
    assert plan[0].File == "A.nl"
    assert plan[1].File == "B.nl"
    assert plan[2].File == "C.nl"

    assert plan[0].Edits.Count == 2
    assert plan[1].Edits.Count == 2
    assert plan[2].Edits.Count == 1
}

// EACH FILE IS ORDERED INDEPENDENTLY, because each file's buffer shifts independently.
test "each file's edits are ordered within that file alone" {
    files := EditorRenameEditFixture.Strings(["A.nl", "B.nl", "A.nl"])
    lines := EditorRenameEditFixture.Ints([2, 99, 7])
    columns := EditorRenameEditFixture.Ints([1, 1, 1])
    lengths := EditorRenameEditFixture.Ints([2, 2, 2])

    plan := EditorRenameEditFacts.Plan(files, lines, columns, lengths)

    assert plan[0].Edits[0].Line == 6
    assert plan[0].Edits[1].Line == 1
    assert plan[1].Edits[0].Line == 98
}

test "no references make no file groups at all" {
    files := new List<string>()
    lines := new List<int>()
    columns := new List<int>()
    lengths := new List<int>()

    plan := EditorRenameEditFacts.Plan(files, lines, columns, lengths)

    assert plan.Count == 0
}

// A STABLE SORT KEEPS EQUAL POSITIONS IN THE ORDER THE SEARCH FOUND THEM, which is what
// `OrderByDescending` shipped.
test "two references at the same position keep the search's own order" {
    files := EditorRenameEditFixture.Strings(["A.nl", "A.nl"])
    lines := EditorRenameEditFixture.Ints([4, 4])
    columns := EditorRenameEditFixture.Ints([5, 5])
    lengths := EditorRenameEditFixture.Ints([1, 9])

    plan := EditorRenameEditFacts.Plan(files, lines, columns, lengths)
    edits := plan[0].Edits

    assert edits[0].EndCharacter == 5
    assert edits[1].EndCharacter == 13
}
