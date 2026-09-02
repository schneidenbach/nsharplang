namespace NSharpLang.Compiler

import System.Collections.Generic
import System.Text


// CONTRACTS FOR THE FORMATTER'S STATE (task 019 slice 17). These are the semantic assertions that
// came out of `Formatter.cs` with six private fields and three private members.
//
// THE STATE WAS UNASSERTABLE BEFORE THE MOVE, AND THAT IS THE POINT. Every one of these fields was
// a private of a class whose only public surface is "give me a whole formatted file", so a rule
// about the comment cursor could only ever be inferred from formatted text — and only for the
// shapes a parser happens to produce. Below, each rule is asked directly: set a depth, hand the
// state a comment stream, ask it to emit part of it, and read the cursors back.
//
// SIX THINGS THAT WERE PROSE, AN ACCIDENT OR UNREACHABLE ARE STATED HERE AS CONTRACTS:
//   (a) THE TWO BLANK-LINE QUESTIONS ARE NOT THE SAME QUESTION. Four callers ask
//       `HasBlankLineBefore`, which is false while nothing has been emitted; `EmitRemainingComments`
//       asks the gap alone, and so CAN open a file with a blank line. Both are asserted, together,
//       on the same state.
//   (b) THE DEPTH IS NOT RESET BY `BeginFile`. Formatting a second file on the same formatter
//       inherits whatever depth the first left — which is zero only because every arm pops what it
//       pushes. The dependence is made visible instead of being assumed.
//   (c) `Pop` BELOW ZERO IS LEGAL AND SILENT, and `Indent` then writes nothing. This is what stops
//       an unbalanced walk from throwing in the middle of a format.
//   (d) THE SNAPSHOT CARRIES TWO CURSORS, NOT THREE. A restore puts the comment index and the gap
//       tracker back and leaves the indent depth wherever the measured pass left it.
//   (e) `RebuildConfig` ROUND-TRIPS A TAB INDENT AS SIZE 1, not as the length of the tab string,
//       and is what makes `FormatSafe`'s idempotence check compare like with like.
//   (f) A NULL COMMENT LIST IS AN EMPTY ONE, so an AST that was never lexed formats without a
//       null check at any of the eight call sites.

func FwsSpaces(size: int): FormatterConfig {
    config := new FormatterConfig()
    config.IndentSize = size
    config.UseSpaces = true
    return config
}

func FwsTabs(): FormatterConfig {
    config := new FormatterConfig()
    config.UseSpaces = false
    return config
}

func FwsState(): FormatterWalkState {
    return new FormatterWalkState(FwsSpaces(4))
}

func FwsComment(line: int, text: string): CommentTrivia {
    return new CommentTrivia(line, 1, text, false)
}

// A comment stream from a list of (line, text) pairs spelled as two parallel arrays, because an
// array literal of tuples is not a shape this toolset emits.
func FwsComments(lines: int[], texts: string[]): List<CommentTrivia> {
    comments := new List<CommentTrivia>()
    index := 0
    while index < lines.Length {
        comments.Add(FwsComment(lines[index], texts[index]))
        index = index + 1
    }

    return comments
}

func FwsOneComment(line: int, text: string): List<CommentTrivia> {
    comments := new List<CommentTrivia>()
    comments.Add(FwsComment(line, text))
    return comments
}

// Newlines are compared as a visible token so a failing assertion reads as text rather than as a
// two-line diff, and so a trailing newline cannot be lost in the comparison.
func FwsShow(builder: StringBuilder): string {
    return builder.ToString().Replace("\r\n", "\n").Replace("\n", "|")
}

func FwsBuilder(): StringBuilder {
    return new StringBuilder()
}

// ---- the indent depth ---------------------------------------------------------------------------

test "the depth starts at zero and Indent writes nothing" {
    state := FwsState()
    builder := FwsBuilder()
    state.Indent(builder)
    assert state.IndentDepth == 0
    assert FwsShow(builder) == ""
}

test "each Push adds one copy of the indent string" {
    state := FwsState()
    builder := FwsBuilder()
    state.Push()
    state.Push()
    state.Indent(builder)
    assert state.IndentDepth == 2
    assert FwsShow(builder) == "        "
}

test "the indent string is the configured one, not a fixed four spaces" {
    two := new FormatterWalkState(FwsSpaces(2))
    builder := FwsBuilder()
    two.Push()
    two.Indent(builder)
    assert two.IndentString == "  "
    assert FwsShow(builder) == "  "
}

test "a tab indent is ONE tab per level whatever the indent size says" {
    config := FwsTabs()
    config.IndentSize = 8
    tabbed := new FormatterWalkState(config)
    builder := FwsBuilder()
    tabbed.Push()
    tabbed.Push()
    tabbed.Indent(builder)
    assert tabbed.IndentString == "\t"
    assert FwsShow(builder) == "\t\t"
}

test "Pop below zero is legal and silent, and Indent then writes nothing" {
    // The C# wrote `_indent--` with no guard. An unbalanced walk degrades to no indentation rather
    // than throwing part-way through a format, and that is asserted rather than assumed.
    state := FwsState()
    builder := FwsBuilder()
    state.Pop()
    state.Pop()
    state.Indent(builder)
    assert state.IndentDepth == -2
    assert FwsShow(builder) == ""
}

test "a null configuration is the default configuration" {
    state := new FormatterWalkState(null)
    assert state.IndentString == "    "
    assert state.MaxLineLength == 100
}

// ---- the file reset -----------------------------------------------------------------------------

test "BeginFile resets BOTH cursors and leaves the depth alone" {
    // (b) The depth is deliberately outside the reset: the C# `Format` assigned three fields and not
    // the fourth, and that is only correct because every arm pops what it pushes.
    state := FwsState()
    state.Push()
    state.LastEmittedSourceLine = 40
    builder := FwsBuilder()
    state.EmitCommentsBefore(50, builder)

    state.BeginFile(FwsOneComment(3, "// second file"))
    assert state.CommentIndex == 0
    assert state.LastEmittedSourceLine == 0
    assert state.IndentDepth == 1
}

test "a null comment list is an empty one" {
    state := FwsState()
    state.BeginFile(null)
    builder := FwsBuilder()
    state.EmitRemainingComments(builder)
    assert state.CommentCount == 0
    assert FwsShow(builder) == ""
}

// ---- the blank-line question ---------------------------------------------------------------------

test "nothing emitted yet means no blank line, whatever the gap" {
    state := FwsState()
    assert state.LastEmittedSourceLine == 0
    assert !state.HasBlankLineBefore(1)
    assert !state.HasBlankLineBefore(900)
}

test "a gap of exactly one line is adjacency, not a blank line" {
    state := FwsState()
    state.LastEmittedSourceLine = 10
    assert !state.HasBlankLineBefore(10)
    assert !state.HasBlankLineBefore(11)
    assert state.HasBlankLineBefore(12)
}

test "a line BEFORE the tracker is not a blank line either" {
    // Reflowed output can hand back an end line below the tracker; a negative gap is not a gap.
    state := FwsState()
    state.LastEmittedSourceLine = 10
    assert !state.HasBlankLineBefore(4)
}

// ---- the formatter's OWN blank lines -------------------------------------------------------------
//
// `Format` writes three blank lines nothing in the source asked for — after the namespace, after
// the import block and after the package. Each is an output line with no source line behind it, so
// each advances the baseline by one; without that the tracker lies by one and the file head grows a
// blank line on every format until `FormatSafe`'s idempotence gate rejects the file.

test "an emitted blank line closes exactly one line of gap" {
    state := FwsState()
    state.LastEmittedSourceLine = 10
    assert state.HasBlankLineBefore(12)

    state.AccountForEmittedBlankLine()
    assert state.LastEmittedSourceLine == 11
    // The gap the blank line just filled no longer reads as one.
    assert !state.HasBlankLineBefore(12)
    // A WIDER gap still does: the accounting is one line, not "no gaps from here on".
    assert state.HasBlankLineBefore(13)
}

test "an emitted blank line before anything has been emitted does NOT open the file" {
    // Zero means "nothing emitted yet" and must keep meaning that, or the first declaration in a
    // file would read a phantom gap against line 1.
    state := FwsState()
    assert state.LastEmittedSourceLine == 0
    state.AccountForEmittedBlankLine()
    assert state.LastEmittedSourceLine == 0
    assert !state.HasBlankLineBefore(900)
}

// ---- the comment stream ---------------------------------------------------------------------------

test "only the comments strictly before the line are emitted" {
    state := FwsState()
    state.BeginFile(FwsComments([1, 5, 9], ["// a", "// b", "// c"]))
    builder := FwsBuilder()
    state.EmitCommentsBefore(5, builder)
    assert state.CommentIndex == 1
    assert FwsShow(builder) == "// a|"
    assert state.LastEmittedSourceLine == 1
}

test "the cursor only moves forward, so a comment is never emitted twice" {
    state := FwsState()
    state.BeginFile(FwsComments([1, 2], ["// a", "// b"]))
    builder := FwsBuilder()
    state.EmitCommentsBefore(9, builder)
    state.EmitCommentsBefore(9, builder)
    assert state.CommentIndex == 2
    assert FwsShow(builder) == "// a|// b|"
}

test "a comment is emitted at the CURRENT indent" {
    state := FwsState()
    state.BeginFile(FwsOneComment(1, "// inside"))
    state.Push()
    builder := FwsBuilder()
    state.EmitCommentsBefore(9, builder)
    assert FwsShow(builder) == "    // inside|"
}

test "each emitted comment becomes the new gap baseline, so a blank line BETWEEN comments survives" {
    state := FwsState()
    state.BeginFile(FwsComments([1, 4], ["// a", "// b"]))
    builder := FwsBuilder()
    state.EmitCommentsBefore(9, builder)
    assert FwsShow(builder) == "// a||// b|"
    assert state.LastEmittedSourceLine == 4
}

test "two adjacent comments get no blank line between them" {
    state := FwsState()
    state.BeginFile(FwsComments([1, 2], ["// a", "// b"]))
    builder := FwsBuilder()
    state.EmitCommentsBefore(9, builder)
    assert FwsShow(builder) == "// a|// b|"
}

test "EmitCommentsBefore never opens a file with a blank line" {
    // (a), first half: the guarded question is false while the tracker is zero, so a comment on
    // line 9 of an otherwise empty file is emitted flush.
    state := FwsState()
    state.BeginFile(FwsOneComment(9, "// far down"))
    builder := FwsBuilder()
    state.EmitCommentsBefore(20, builder)
    assert FwsShow(builder) == "// far down|"
}

test "EmitRemainingComments CAN open a file with a blank line, and that is the difference" {
    // (a), second half: the trailing arm asks the gap alone. On the SAME state and the SAME comment
    // the two arms disagree, which is why the weaker test is reproduced rather than unified.
    state := FwsState()
    state.BeginFile(FwsOneComment(9, "// far down"))
    builder := FwsBuilder()
    state.EmitRemainingComments(builder)
    assert FwsShow(builder) == "|// far down|"
}

test "a trailing comment on line 1 gets no blank line even from the weaker test" {
    state := FwsState()
    state.BeginFile(FwsOneComment(1, "// top"))
    builder := FwsBuilder()
    state.EmitRemainingComments(builder)
    assert FwsShow(builder) == "// top|"
}

test "EmitRemainingComments takes everything left, whatever its line" {
    state := FwsState()
    state.BeginFile(FwsComments([1, 2, 3], ["// a", "// b", "// c"]))
    builder := FwsBuilder()
    state.EmitCommentsBefore(2, builder)
    state.EmitRemainingComments(builder)
    assert state.CommentIndex == 3
    assert FwsShow(builder) == "// a|// b|// c|"
}

test "an exhausted stream emits nothing and moves no cursor" {
    state := FwsState()
    state.BeginFile(FwsOneComment(1, "// only"))
    builder := FwsBuilder()
    state.EmitRemainingComments(builder)
    state.EmitRemainingComments(builder)
    state.EmitCommentsBefore(900, builder)
    assert FwsShow(builder) == "// only|"
    assert state.LastEmittedSourceLine == 1
}

// ---- the measurement pass ------------------------------------------------------------------------

test "a snapshot restores the comment cursor and the gap tracker" {
    state := FwsState()
    state.BeginFile(FwsComments([1, 2], ["// a", "// b"]))
    saved := state.Snapshot()
    builder := FwsBuilder()
    state.EmitCommentsBefore(9, builder)
    assert state.CommentIndex == 2

    state.Restore(saved)
    assert state.CommentIndex == 0
    assert state.LastEmittedSourceLine == 0
}

test "the restored cursor makes the same comments available AGAIN" {
    // This is exactly what the measurement pass needs: the throwaway builder consumed the comments,
    // and the real pass must still emit them.
    state := FwsState()
    state.BeginFile(FwsOneComment(1, "// a"))
    saved := state.Snapshot()
    scratch := FwsBuilder()
    state.EmitCommentsBefore(9, scratch)
    state.Restore(saved)

    real := FwsBuilder()
    state.EmitCommentsBefore(9, real)
    assert FwsShow(scratch) == "// a|"
    assert FwsShow(real) == "// a|"
}

test "the snapshot does NOT carry the indent depth" {
    // (d) The C# saved two locals, not three. A throw inside a measured expression leaves the depth
    // where the abandoned walk left it, and a clean restore does too.
    state := FwsState()
    saved := state.Snapshot()
    state.Push()
    state.Push()
    state.Restore(saved)
    assert state.IndentDepth == 2
}

test "a snapshot is a value, not a view: later writes do not move it" {
    state := FwsState()
    state.LastEmittedSourceLine = 5
    saved := state.Snapshot()
    state.LastEmittedSourceLine = 60
    assert saved.LastEmittedSourceLine == 5
    state.Restore(saved)
    assert state.LastEmittedSourceLine == 5
}

// ---- the configuration round trip ------------------------------------------------------------------

test "a space indent round-trips as its own size" {
    state := new FormatterWalkState(FwsSpaces(2))
    rebuilt := state.RebuildConfig()
    assert rebuilt.IndentSize == 2
    assert rebuilt.UseSpaces
    assert rebuilt.MaxLineLength == 100
}

test "a tab indent round-trips as size ONE, not as the tab string's length" {
    // (e) The config was consumed into a string at construction; reading it back as `Length` would
    // be right for spaces and wrong for tabs, and the idempotence check would then reformat with a
    // different configuration than the one that produced the text it is comparing.
    state := new FormatterWalkState(FwsTabs())
    rebuilt := state.RebuildConfig()
    assert rebuilt.IndentSize == 1
    assert !rebuilt.UseSpaces
}

test "the rebuilt configuration reproduces the same indent string" {
    original := new FormatterWalkState(FwsSpaces(3))
    round := new FormatterWalkState(original.RebuildConfig())
    assert round.IndentString == original.IndentString
    assert round.MaxLineLength == original.MaxLineLength
}

test "the maximum line length crosses from the configuration and is not defaulted twice" {
    config := FwsSpaces(4)
    config.MaxLineLength = 42
    state := new FormatterWalkState(config)
    assert state.MaxLineLength == 42
    assert state.RebuildConfig().MaxLineLength == 42
}
