namespace NSharpLang.Compiler

import System.Collections.Generic
import System.Text

// THE FORMATTER'S WHOLE STATE: THREE CURSORS, ONE STREAM AND TWO CONFIGURED CONSTANTS.
//
// `Formatter` carried six private fields and mutated them from forty-three members. That is what
// makes its two walker SCCs — 14 members over 1,282 lines, and 6 members over 282 — immovable: any
// arm lifted out of C# would need a callback back into the formatter to touch the depth or the
// comment cursor, and a callback is exactly what the ownership mandate forbids. This owner takes
// ALL SIX, so an arm that moves later reaches its state through a method on an N# object.
//
// WHAT IT OWNS, IN THREE GROUPS:
//
//   1. THE INDENT DEPTH. One counter, pushed and popped around every nested body. It is the file's
//      most-written field by an order of magnitude — 76 writes across 20 members, against a single
//      read — and it is read in exactly one place, `Indent`, which is why the two live together.
//   2. THE COMMENT STREAM AND ITS CURSOR. The comments the lexer collected, plus the index of the
//      first one not yet emitted. Comments are emitted in source order and never revisited, so a
//      forward-only index is the whole bookkeeping.
//   3. THE LAST EMITTED SOURCE LINE. The one value that decides whether a blank line is preserved.
//      Every caller asks the same question of it — "was there a gap in the source before this
//      line?" — which is why that question is a method here and not six copies of an inequality.
//
// THE TWO CONFIGURED CONSTANTS (the indent string and the maximum line length) are derived from a
// `FormatterConfig` once, at construction, and never written again; the C# marked both `readonly`.
// They live here rather than in the formatter because `RebuildConfig` needs both, and because the
// indent string is meaningless apart from the depth that repeats it.
class FormatterWalkState {
    indentString: string
    maxLineLength: int

    indentDepth: int
    comments: List<CommentTrivia>
    commentIndex: int
    lastEmittedSourceLine: int

    IndentString: string => indentString
    MaxLineLength: int => maxLineLength
    IndentDepth: int => indentDepth
    CommentIndex: int => commentIndex
    CommentCount: int => comments.Count

    // The gap tracker is READ AND WRITTEN by the walk arms that stay in C#, so it is a settable
    // property rather than a method pair. Every write is "the item I just emitted ended here".
    LastEmittedSourceLine: int {
        get {
            return lastEmittedSourceLine
        }
        set {
            lastEmittedSourceLine = value
        }
    }

    constructor(config: FormatterConfig?) {
        effectiveConfig := config ?? new FormatterConfig()
        indentString = effectiveConfig.GetIndentString()
        maxLineLength = effectiveConfig.MaxLineLength
        indentDepth = 0
        comments = new List<CommentTrivia>()
        commentIndex = 0
        lastEmittedSourceLine = 0
    }

    // ---- the file ------------------------------------------------------------------------------

    // One file's worth of state, reset at the top of every format. A null comment list is an empty
    // one: the formatter is asked to format ASTs that were never lexed, and those carry no trivia.
    //
    // BOTH CURSORS GO BACK TO ZERO, AND THE DEPTH DOES NOT. That is the C# exactly — `Format`
    // assigned `_comments`, `_commentIndex` and `_lastEmittedSourceLine` and left `_indent` alone —
    // and it is correct only because the depth is balanced: every arm that pushes pops on the way
    // out, so a completed format always returns to the depth it started at.
    func BeginFile(fileComments: List<CommentTrivia>?) {
        comments = fileComments ?? new List<CommentTrivia>()
        commentIndex = 0
        lastEmittedSourceLine = 0
    }

    // The configuration this state was built from, reconstructed. `FormatSafe` formats its own
    // output a second time to prove the formatter is idempotent, and the second formatter must be
    // configured identically — but the config was consumed into a STRING at construction, so the
    // size and the tab/space choice have to be read back out of it.
    //
    // A tab indent is one tab character, so its size is 1 and not its length; a space indent's size
    // IS its length. `Contains` takes the string "\t" rather than the character '\t' because the
    // pinned toolset does not carry the char overload (finding 93.4).
    func RebuildConfig(): FormatterConfig {
        usesTabs := indentString.Contains("\t")
        rebuilt := new FormatterConfig()

        if usesTabs {
            rebuilt.IndentSize = 1
        } else {
            rebuilt.IndentSize = indentString.Length
        }

        rebuilt.UseSpaces = !usesTabs
        rebuilt.MaxLineLength = maxLineLength
        return rebuilt
    }

    // ---- the indent depth ----------------------------------------------------------------------

    // Entering and leaving a nested body. The pair is not guarded: `Pop` below zero is possible and
    // is exactly what `_indent--` did, and `Indent` then writes nothing, so an unbalanced walk
    // degrades to no indentation rather than throwing in the middle of a format.
    func Push() {
        indentDepth = indentDepth + 1
    }

    func Pop() {
        indentDepth = indentDepth - 1
    }

    // The one read of the depth in the whole formatter: the indent string, repeated depth times.
    func Indent(builder: StringBuilder) {
        i := 0
        while i < indentDepth {
            builder.Append(indentString)
            i = i + 1
        }
    }

    // ---- the blank-line question -----------------------------------------------------------------

    // "Did the source leave a blank line between the last thing emitted and this one?"
    //
    // FOUR CALLERS SPELLED THIS INEQUALITY OUT AND KEPT THE FOUR COPIES IN STEP BY HAND — the
    // namespace and the declaration loop in `Format`, the member loop in `FormatMembers`, and the
    // statement loop in `FormatBlock`. Both halves matter: a gap of more than one line is a blank
    // line, and a tracker still at zero means nothing has been emitted yet, so there is no gap to
    // preserve and the file does not open with a blank line.
    //
    // `EmitRemainingComments` deliberately does NOT ask this question — see there.
    func HasBlankLineBefore(line: int): bool {
        return lastEmittedSourceLine > 0 && line - lastEmittedSourceLine > 1
    }

    // "I just wrote a blank line the source did not have."
    //
    // THIS IS WHAT MAKES THE FORMATTER IDEMPOTENT ACROSS THE FILE HEAD. `Format` writes a blank
    // line after the namespace, after the import block and after the package UNCONDITIONALLY —
    // those separators are the language's spelling, not the source's. The tracker, though, holds a
    // SOURCE line, and a synthetic output line that nothing accounts for makes the gap tracker lie
    // by exactly one: `import System` / `// header` (no blank between them) formats to
    // `import System` / blank / `// header`, and a SECOND format then reads a two-line gap where
    // the first read a one-line gap and writes a second blank. Each pass adds another, so the
    // formatter's own idempotence gate rejects the file and `nlc format` refuses to touch it.
    //
    // Advancing the baseline by one line is the whole accounting: the blank just written STANDS IN
    // FOR one line of the source's own gap, so a source that already had that blank still reads as
    // one gap and a source that did not now reads as none. The guard keeps zero meaning "nothing
    // emitted yet" — every caller has already emitted a line, so it never fires, and it is there so
    // a future caller cannot turn the file's opening into a phantom gap.
    func AccountForEmittedBlankLine() {
        if lastEmittedSourceLine > 0 {
            lastEmittedSourceLine = lastEmittedSourceLine + 1
        }
    }

    // ---- the comment stream ----------------------------------------------------------------------

    // Emit every comment that stood before the given source line, in order, at the current indent.
    //
    // The cursor only ever moves forward, so a comment emitted here is never emitted again, and a
    // comment whose line is at or after `beforeLine` waits for the next call. Each emitted comment
    // becomes the new gap baseline, which is what lets a blank line between two comments survive.
    func EmitCommentsBefore(beforeLine: int, builder: StringBuilder) {
        while commentIndex < comments.Count && comments[commentIndex].Line < beforeLine {
            comment := comments[commentIndex]

            if HasBlankLineBefore(comment.Line) {
                builder.AppendLine()
            }

            Indent(builder)
            builder.AppendLine(comment.Text)
            lastEmittedSourceLine = comment.Line
            commentIndex = commentIndex + 1
        }
    }

    // Everything left over, after the last declaration has been formatted.
    //
    // THIS ARM ASKS A WEAKER QUESTION THAN `HasBlankLineBefore` AND THE DIFFERENCE IS REAL, NOT AN
    // OVERSIGHT: it tests the gap alone, with no "has anything been emitted yet" guard. In a file
    // whose only content is a comment the tracker is still zero, and `comment.Line - 0 > 1` is true
    // for any comment below line 1 — so a file that opens with a blank line and then a comment keeps
    // that blank line, where the guarded question would have swallowed it. Reproduced as it stands.
    func EmitRemainingComments(builder: StringBuilder) {
        while commentIndex < comments.Count {
            comment := comments[commentIndex]

            if comment.Line - lastEmittedSourceLine > 1 {
                builder.AppendLine()
            }

            Indent(builder)
            builder.AppendLine(comment.Text)
            lastEmittedSourceLine = comment.Line
            commentIndex = commentIndex + 1
        }
    }
}
