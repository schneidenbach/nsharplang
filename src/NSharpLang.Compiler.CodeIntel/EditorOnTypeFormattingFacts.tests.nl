namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

// CONTRACTS FOR WHAT TYPING RE-INDENTS. These came out of `OnTypeFormattingHandler.cs`, where they
// were reachable only by standing an OmniSharp request up: the backwards brace-match, the visual
// column measurement that lets tabs and spaces compare equal, the tab/space split when the editor
// writes the indent back, the naive `//` strip that decides whether a line opened a block, and the
// rule that an already-correct line produces NO edit at all.
func EotfLines(text: string): string[] {
    return text.Split('\n')
}

func EotfSingle(rows: List<EditorTextEditRow>): EditorTextEditRow {
    assert rows.Count == 1
    return rows[0]
}

// THE MATCHING BRACE IS FOUND BY DEPTH, NOT BY THE FIRST ONE SEEN. A nested pair closed on the way
// back must not capture the walk, and the brace just typed must not count itself twice.
test "on-type formatting aligns a closing brace with the line its own opening brace sits on" {
    lines := EotfLines("class C {\n    func f() {\n        if a {\n        }\n            }\n")
    row := EotfSingle(EditorOnTypeFormattingFacts.CloseBraceRows(lines, 4, 4, true))

    assert row.StartLine == 4
    assert row.EndLine == 4
    assert row.StartCharacter == 0
    assert row.EndCharacter == 13
    assert row.NewText == "    }"
}

// A LINE ALREADY AT ITS INDENT IS LEFT ALONE. This is the common keystroke, and handing an editor a
// no-op replacement of the whole line breaks its undo grouping for nothing.
test "on-type formatting produces no edit for a brace already at the right indent" {
    lines := EotfLines("class C {\n}\n")
    assert EditorOnTypeFormattingFacts.CloseBraceRows(lines, 1, 4, true).Count == 0
}

// AN UNMATCHED BRACE ANSWERS NOTHING. A buffer mid-edit routinely has no partner for the brace just
// typed, and guessing an indent for it would fight the typist.
test "on-type formatting answers nothing for a brace with no opener or a line out of range" {
    lines := EotfLines("        }\n")
    assert EditorOnTypeFormattingFacts.CloseBraceRows(lines, 0, 4, true).Count == 0
    assert EditorOnTypeFormattingFacts.CloseBraceRows(lines, 5, 4, true).Count == 0
    assert EditorOnTypeFormattingFacts.CloseBraceRows(lines, -1, 4, true).Count == 0
}

// A CURRENT LINE WITH NO `}` STARTS THE WALK BEFORE ITS OWN BEGINNING, so the brace the editor says
// was typed contributes nothing and the walk opens on the PREVIOUS line instead. The editor only
// asks after a `}` is actually typed, so this shape is reachable only from a caller that lies; it
// is recorded because the answer is an edit, not silence, and nothing else says so.
test "on-type formatting re-indents to the opener above a line the trigger did not happen on" {
    noBrace := EotfLines("class C {\n    x\n")
    row := EotfSingle(EditorOnTypeFormattingFacts.CloseBraceRows(noBrace, 1, 4, true))

    assert row.NewText == "x"
}

// A NEWLINE TAKES THE PREVIOUS LINE'S INDENT, PLUS ONE LEVEL IF THAT LINE OPENED A BLOCK.
test "on-type formatting adds one level after an opening brace and otherwise keeps the level" {
    opened := EotfLines("    func f() {\nx\n")
    assert EotfSingle(EditorOnTypeFormattingFacts.NewlineRows(opened, 1, 4, true)).NewText == "        x"

    flat := EotfLines("    let a = 1\nb\n")
    assert EotfSingle(EditorOnTypeFormattingFacts.NewlineRows(flat, 1, 4, true)).NewText == "    b"
}

// THE TRAILING COMMENT IS NOT PART OF THE LINE'S CODE, so a brace followed by a note still opens a
// block — and a `//` that only LOOKS trailing takes the rest of the line with it, which is the
// naive rule this scan is documented to be.
test "on-type formatting does not let a trailing comment hide the brace that opened the block" {
    commented := EotfLines("    func f() { // opens\nx\n")
    assert EotfSingle(EditorOnTypeFormattingFacts.NewlineRows(commented, 1, 4, true)).NewText == "        x"

    assert EditorOnTypeFormattingFacts.StripTrailingComment("a // b") == "a "
    assert EditorOnTypeFormattingFacts.StripTrailingComment("a b") == "a b"
    assert EditorOnTypeFormattingFacts.StripTrailingComment("\"http://x\"") == "\"http:"
}

// THE FIRST LINE OF A FILE HAS NO PREVIOUS LINE, so pressing Enter onto it answers nothing.
test "on-type formatting answers nothing for a newline on the first line or past the end" {
    lines := EotfLines("x\ny\n")
    assert EditorOnTypeFormattingFacts.NewlineRows(lines, 0, 4, true).Count == 0
    assert EditorOnTypeFormattingFacts.NewlineRows(lines, 9, 4, true).Count == 0
}

// INDENT IS VISUAL COLUMNS. A tab is worth a whole tab stop, and the measurement stops at the first
// character that is not whitespace rather than counting whitespace found later in the line.
test "on-type formatting counts a tab as a whole tab stop and stops at the first code character" {
    assert EditorOnTypeFormattingFacts.LineIndentWidth("    x  y", 4) == 4
    assert EditorOnTypeFormattingFacts.LineIndentWidth("\t\tx", 4) == 8
    assert EditorOnTypeFormattingFacts.LineIndentWidth("\t x", 2) == 3
    assert EditorOnTypeFormattingFacts.LineIndentWidth("", 4) == 0
    assert EditorOnTypeFormattingFacts.LineIndentWidth("    ", 4) == 4
}

// WRITING THE INDENT BACK RESPECTS THE EDITOR'S CHOICE, and a width that is not a multiple of the
// tab stop is paid out in tabs and then spaces rather than being rounded.
test "on-type formatting writes spaces, or whole tabs plus the remainder in spaces" {
    assert EditorOnTypeFormattingFacts.IndentText(6, 4, true) == "      "
    assert EditorOnTypeFormattingFacts.IndentText(6, 4, false) == "\t  "
    assert EditorOnTypeFormattingFacts.IndentText(8, 4, false) == "\t\t"
    assert EditorOnTypeFormattingFacts.IndentText(0, 4, false) == ""
}

// A TAB-INDENTED FILE GETS TAB INDENTS BACK, and a carriage return is not part of the line the
// editor is told to replace.
test "on-type formatting spans the line as it reads without its carriage return" {
    lines := EotfLines("class C {\r\n\t\t}\r\n")
    row := EotfSingle(EditorOnTypeFormattingFacts.CloseBraceRows(lines, 1, 4, false))

    assert row.EndCharacter == 3
    assert row.NewText == "}"
}

// ONLY TWO CHARACTERS TRIGGER ANYTHING. Anything else the editor forwards answers with no rows,
// which is how the handler declines without inventing a failure.
test "on-type formatting has exactly two triggers, the closing brace and the newline" {
    lines := EotfLines("class C {\n        }\n")
    assert EditorOnTypeFormattingFacts.FormattingRows(lines, EditorOnTypeFormattingFacts.CloseBraceTrigger, 1, 4, true).Count == 1
    assert EditorOnTypeFormattingFacts.FormattingRows(lines, EditorOnTypeFormattingFacts.NewlineTrigger, 1, 4, true).Count == 1
    assert EditorOnTypeFormattingFacts.FormattingRows(lines, ";", 1, 4, true).Count == 0
    assert EditorOnTypeFormattingFacts.FormattingRows(lines, "{", 1, 4, true).Count == 0
}
