namespace NSharpLang.Compiler.CodeIntelligence

import System


// CONTRACTS FOR WHICH POSITIONS OF A BUFFER ARE INSIDE LITERAL TEXT.
//
// The subject is `IsEditorPositionInsideStringLiteral` and the four scans under it, which came out
// of `EditorUtilities.cs` — 275 of that file's 299 lines, a hand-rolled literal lexer with its own
// escape, raw-string and interpolation-depth rules and NOT ONE TEST anywhere in the repository. Its
// single consumer is `PrepareRenameHandler`, which refuses to rename a word inside a string, so
// every wrong answer is either a rename the editor should have refused or a rename it refused for
// no reason.
//
// THE POSITIONS ARE WRITTEN AS OFFSETS INTO A LITERAL BUFFER AND CHECKED BY EYE. Each buffer below
// is short enough that the character at each index can be counted, and the assertions name the
// character they are about, because an off-by-one in a scan is invisible in a `true`/`false` table
// that does not say which character it asked about.
//
// THE FOUR SCANS ARE FOUR RULES, NOT ONE RULE FOUR TIMES. A raw string ends on `"""` and has no
// escapes; a normal string ends on the first UNESCAPED `"` or at the end of its LINE; the two
// interpolated forms differ from those and from each other in where their content starts. The
// assertions are grouped that way so that a scan broken in one form fails in its own group.

func TuInside(text: string, line: int, character: int): bool {
    return CodeIntelligenceTextUtilities.IsEditorPositionInsideStringLiteral(text, line, character)
}


// ── a plain string literal ─────────────────────────────────────────────────────────────────────

test "a position inside a plain literal is inside, and the code around it is not" {
    // `let s = "hello"` — the opening quote is at 8, `h` at 9, the closing quote at 14.
    text := "let s = \"hello\""

    assert TuInside(text, 0, 9)
    assert TuInside(text, 0, 13)
    assert !TuInside(text, 0, 4)
}

test "the delimiters themselves are not inside the literal" {
    // A cursor ON a quote is not in the string's text, and rename must not be refused there for a
    // word that is not in the string either.
    text := "let s = \"hello\""

    assert !TuInside(text, 0, 8)
    assert !TuInside(text, 0, 14)
}

test "an escaped quote does not end the literal" {
    // `let s = "a\"b"` — the quote at 11 is escaped, so `b` at 12 is still inside.
    text := "let s = \"a\\\"b\""

    assert TuInside(text, 0, 12)
}

test "a plain literal ends at the end of its line" {
    // An unterminated literal must not swallow the NEXT line's code: `t` on line 1 is code.
    text := "let s = \"abc\nlet t = 4"

    assert TuInside(text, 0, 10)
    assert !TuInside(text, 1, 4)
}

test "an unterminated literal swallows the rest of its own line" {
    // Half a literal is a literal — the developer is still typing it.
    text := "let s = \"abc"

    assert TuInside(text, 0, 10)
    assert !TuInside(text, 0, 4)
}


// ── a raw string literal ───────────────────────────────────────────────────────────────────────

test "a position inside a raw literal is inside" {
    // `let s = """abc"""` — content runs from 11 to 13.
    text := "let s = \"\"\"abc\"\"\""

    assert TuInside(text, 0, 12)
    assert !TuInside(text, 0, 5)
}


// ── an interpolated literal, where the holes are code ──────────────────────────────────────────

test "the literal text of an interpolated string is inside" {
    // `let s = $"hi {name}"` — `h` at 10 is literal text.
    text := "let s = $\"hi {name}\""

    assert TuInside(text, 0, 10)
    assert !TuInside(text, 0, 4)
}

test "an interpolation hole is NOT inside the literal, because it is code" {
    // `name` begins at 14 and must be renameable.
    text := "let s = $\"hi {name}\""

    assert !TuInside(text, 0, 14)
}

test "a nested literal inside a hole is inside again" {
    // `let s = $"{d["k"]}"` — `d` at 11 is code, `k` at 14 is a string two levels down.
    text := "let s = $\"{d[\"k\"]}\""

    assert !TuInside(text, 0, 11)
    assert TuInside(text, 0, 14)
}

test "a raw interpolated literal separates its holes from its text the same way" {
    // `let s = $"""{a}b"""` — `a` at 13 is code, `b` at 15 is text.
    text := "let s = $\"\"\"{a}b\"\"\""

    assert !TuInside(text, 0, 13)
    assert TuInside(text, 0, 15)
}


// ── the position itself ────────────────────────────────────────────────────────────────────────

test "a position past the end of the buffer is not inside anything" {
    text := "let s = \"hello\""

    assert !TuInside(text, 99, 0)
    assert !TuInside(text, 0, 99)
    assert !TuInside(text, -1, 0)
    assert !TuInside(text, 0, -1)
}

test "a buffer with no literal at all answers false everywhere" {
    text := "let s = 4"

    assert !TuInside(text, 0, 0)
    assert !TuInside(text, 0, 4)
    assert !TuInside(text, 0, 8)
}

// THE OFFSET WALK IS ADDRESSABLE AT THE VERY END, because a cursor sits AFTER the last character.
// A walk that stopped one short would answer false for the position a developer's caret is at when
// they finish typing a line.
test "the offset walk addresses the position after the last character" {
    offset := 0
    assert CodeIntelligenceTextUtilities.TryGetEditorOffset("ab", 0, 2, out offset)
    assert offset == 2
    assert !CodeIntelligenceTextUtilities.TryGetEditorOffset("ab", 0, 3, out offset)

    assert CodeIntelligenceTextUtilities.TryGetEditorOffset("ab\ncd", 1, 0, out offset)
    assert offset == 3
}
