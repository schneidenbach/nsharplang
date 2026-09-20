namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

// ONE WHOLE-LINE REPLACEMENT THE EDITOR SHOULD MAKE, in the editor's own 0-based line numbering.
//
// Every row on-type formatting produces rewrites exactly one line from its first character to its
// last, so the shape carries the line twice rather than pretending to a generality it does not
// have: `StartLine` and `EndLine` are always the same line, `StartCharacter` is always 0, and
// `EndCharacter` is the length of the line as it stands before the edit.
class EditorTextEditRow {
    startLineValue: int
    startCharacterValue: int
    endLineValue: int
    endCharacterValue: int
    newTextValue: string

    StartLine: int => startLineValue
    StartCharacter: int => startCharacterValue
    EndLine: int => endLineValue
    EndCharacter: int => endCharacterValue
    NewText: string => newTextValue

    constructor(StartLine: int, StartCharacter: int, EndLine: int, EndCharacter: int, NewText: string) {
        startLineValue = StartLine
        startCharacterValue = StartCharacter
        endLineValue = EndLine
        endCharacterValue = EndCharacter
        newTextValue = NewText
    }
}

// WHAT TYPING A CHARACTER SHOULD RE-INDENT. Two triggers answer anything: the closing brace, which
// aligns itself with the line its own opening brace sits on, and the newline, which either keeps
// the previous line's indent or adds one level because that line opened a block.
//
// NO EDIT IS AN ANSWER, and the common one: a line already at the indent it should have is left
// alone, so an editor that asks on every keystroke is not handed a no-op edit that clears its undo
// grouping. An empty row list means exactly that, and is NOT an error.
class EditorOnTypeFormattingFacts {
    static CloseBraceTrigger: string => "}"
    static NewlineTrigger: string => "\n"

    static func FormattingRows(sourceLines: string[], trigger: string, line: int, tabSize: int, insertSpaces: bool): List<EditorTextEditRow> {
        if trigger == CloseBraceTrigger {
            return CloseBraceRows(sourceLines, line, tabSize, insertSpaces)
        }

        if trigger == NewlineTrigger {
            return NewlineRows(sourceLines, line, tabSize, insertSpaces)
        }

        return new List<EditorTextEditRow>()
    }

    // A CLOSING BRACE BELONGS AT THE INDENT OF THE LINE THAT OPENED IT. The match is found by
    // walking backwards from the brace just typed, counting depth, so a nested pair passed on the
    // way cannot claim it. The walk begins one character LEFT of the last `}` on the current line,
    // which is what makes the brace being typed the one whose partner is wanted; a current line
    // with no `}` at all starts the walk before its own beginning and therefore contributes nothing.
    static func CloseBraceRows(sourceLines: string[], currentLine: int, tabSize: int, insertSpaces: bool): List<EditorTextEditRow> {
        rows := new List<EditorTextEditRow>()
        if currentLine < 0 || currentLine >= sourceLines.Length {
            return rows
        }

        braceDepth := 1
        matchLine := -1
        index := currentLine
        while index >= 0 && matchLine < 0 {
            lineText := sourceLines[index].TrimEnd('\r')
            column := lineText.Length - 1
            if index == currentLine {
                column = lineText.LastIndexOf('}') - 1
            }

            while column >= 0 && matchLine < 0 {
                character := lineText[column]
                if character == '}' {
                    braceDepth = braceDepth + 1
                } else if character == '{' {
                    braceDepth = braceDepth - 1
                    if braceDepth == 0 {
                        matchLine = index
                    }
                }

                column = column - 1
            }

            index = index - 1
        }

        if matchLine < 0 {
            return rows
        }

        AppendIndentRow(rows, sourceLines, currentLine, LineIndentWidth(sourceLines[matchLine], tabSize), tabSize, insertSpaces)
        return rows
    }

    // AFTER A NEWLINE THE PREVIOUS LINE DECIDES, and it decides by what it ends with once its
    // trailing comment is taken off: an opening brace asks for one more level, anything else asks
    // for the level the previous line already had.
    static func NewlineRows(sourceLines: string[], currentLine: int, tabSize: int, insertSpaces: bool): List<EditorTextEditRow> {
        rows := new List<EditorTextEditRow>()
        if currentLine < 1 || currentLine >= sourceLines.Length {
            return rows
        }

        previousLineText := sourceLines[currentLine - 1].TrimEnd('\r')
        targetIndent := LineIndentWidth(previousLineText, tabSize)
        if StripTrailingComment(previousLineText).TrimEnd().EndsWith("{") {
            targetIndent = targetIndent + tabSize
        }

        AppendIndentRow(rows, sourceLines, currentLine, targetIndent, tabSize, insertSpaces)
        return rows
    }

    // The one shape both triggers produce: replace the whole line with the indent it should have
    // plus what it already says, and produce nothing at all when it already says it.
    static func AppendIndentRow(rows: List<EditorTextEditRow>, sourceLines: string[], currentLine: int, targetIndent: int, tabSize: int, insertSpaces: bool) {
        currentLineText := sourceLines[currentLine].TrimEnd('\r')
        if LineIndentWidth(currentLineText, tabSize) == targetIndent {
            return
        }

        rows.Add(new EditorTextEditRow(
            currentLine,
            0,
            currentLine,
            currentLineText.Length,
            IndentText(targetIndent, tabSize, insertSpaces) + currentLineText.TrimStart()
        ))
    }

    // INDENT IS MEASURED IN VISUAL COLUMNS, not in characters, so a tab and the spaces that reach
    // the same column compare equal and a file that mixes them is not re-indented on every keystroke.
    static func LineIndentWidth(line: string, tabSize: int): int {
        width := 0
        index := 0
        while index < line.Length {
            character := line[index]
            if character == ' ' {
                width = width + 1
            } else if character == '\t' {
                width = width + tabSize
            } else {
                return width
            }

            index = index + 1
        }

        return width
    }

    // The same width written back out in the editor's own whitespace. A tab file spends whole tabs
    // first and pays the remainder in spaces, because a width that is not a multiple of the tab
    // stop cannot be reached with tabs alone.
    static func IndentText(width: int, tabSize: int, insertSpaces: bool): string {
        if insertSpaces {
            return new string(' ', width)
        }

        return new string('\t', width / tabSize) + new string(' ', width % tabSize)
    }

    // A LINE'S CODE STOPS AT ITS FIRST `//`. This is deliberately the naive scan and not the
    // lexer's: on-type formatting runs on a buffer that is mid-edit and routinely does not lex, and
    // the only question being asked is whether the line ended by opening a block.
    static func StripTrailingComment(line: string): string {
        commentStart := line.IndexOf("//", StringComparison.Ordinal)
        if commentStart >= 0 {
            return line.Substring(0, commentStart)
        }

        return line
    }
}
