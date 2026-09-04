namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text

class CodeFixProvider {
    FixableDiagnosticCodes: IEnumerable<string> => new string[](0)

    func GetCodeActions(diagnostic: Diagnostic, ast: object, sourceCode: string): List<CodeAction> {
        return new List<CodeAction>()
    }
}

class CodeFixService {
    func GetCodeActions(diagnostic: Diagnostic, ast: object, sourceCode: string): List<CodeAction> {
        actions := new List<CodeAction>()

        if String.Compare(diagnostic.Code, "NL002", StringComparison.Ordinal) == 0 {
            AddActions(actions, new AddMissingImportCodeFixProvider().GetCodeActions(diagnostic, ast, sourceCode))
        } else if String.Compare(diagnostic.Code, "NL001", StringComparison.Ordinal) == 0 {
            AddActions(actions, new RemoveUnusedVariableCodeFixProvider().GetCodeActions(diagnostic, ast, sourceCode))
        } else if String.Compare(diagnostic.Code, "NL003", StringComparison.Ordinal) == 0 {
            AddActions(actions, new RemoveUnnecessaryNullCheckCodeFixProvider().GetCodeActions(diagnostic, ast, sourceCode))
        } else if String.Compare(diagnostic.Code, "NL905", StringComparison.Ordinal) == 0 {
            AddActions(actions, new PossibleNullAccessCodeFixProvider().GetCodeActions(diagnostic, ast, sourceCode))
        } else if String.Compare(diagnostic.Code, "NL011", StringComparison.Ordinal) == 0 {
            AddActions(actions, new AddCommentToEmptyCatchCodeFixProvider().GetCodeActions(diagnostic, ast, sourceCode))
        } else if String.Compare(diagnostic.Code, "NL010", StringComparison.Ordinal) == 0 {
            AddActions(actions, new RemoveUnusedImportCodeFixProvider().GetCodeActions(diagnostic, ast, sourceCode))
        }

        return actions
    }

    static func AddActions(target: List<CodeAction>, source: List<CodeAction>) {
        i := 0
        while i < source.Count {
            target.Add(source[i])
            i = i + 1
        }
    }
}

class AddMissingImportCodeFixProvider {
    FixableDiagnosticCodes: IEnumerable<string> => CodeFixActionHelpers.SingleDiagnosticCode("NL002")

    func GetCodeActions(diagnostic: Diagnostic, ast: object, sourceCode: string): List<CodeAction> {
        actions := new List<CodeAction>()
        namespaceToImport := ""
        suggestion := diagnostic.Suggestion ?? ""
        if CodeFixActionHelpers.TryGetMissingImportNamespace(suggestion, out namespaceToImport) {
            edits := ImportEditPlanner.GetEdits(ast, sourceCode, namespaceToImport)
            if edits.Count > 0 {
                actions.Add(new CodeAction("Add import " + namespaceToImport, "NL002", edits, CodeActionKind.QuickFix))
            }
        }

        return actions
    }
}

class RemoveUnusedVariableCodeFixProvider {
    FixableDiagnosticCodes: IEnumerable<string> => CodeFixActionHelpers.SingleDiagnosticCode("NL001")

    func GetCodeActions(diagnostic: Diagnostic, ast: object, sourceCode: string): List<CodeAction> {
        actions := new List<CodeAction>()
        line := diagnostic.Location.Line

        title := ""
        if CodeFixActionHelpers.TryGetRemoveUnusedVariableEdit(diagnostic.Message, sourceCode, line, out title) {
            edits := new List<TextEdit>()
            edits.Add(new TextEdit(line, 0, line + 1, 0, ""))
            actions.Add(new CodeAction(title, "NL001", edits, CodeActionKind.QuickFix, FixSafety.ReviewNeeded))
        }

        return actions
    }
}

class RemoveUnnecessaryNullCheckCodeFixProvider {
    FixableDiagnosticCodes: IEnumerable<string> => CodeFixActionHelpers.SingleDiagnosticCode("NL003")

    func GetCodeActions(diagnostic: Diagnostic, ast: object, sourceCode: string): List<CodeAction> {
        actions := new List<CodeAction>()
        line := diagnostic.Location.Line

        conditionStart := 0
        conditionEnd := 0
        newCondition := ""
        if CodeFixActionHelpers.TryGetUnnecessaryNullCheckEdit(sourceCode, line, out conditionStart, out conditionEnd, out newCondition) {
            edits := new List<TextEdit>()
            edits.Add(new TextEdit(line, conditionStart, line, conditionEnd, newCondition))
            actions.Add(new CodeAction("Remove unnecessary null check (always " + newCondition + ")", "NL003", edits, CodeActionKind.QuickFix, FixSafety.Safe))
        }

        return actions
    }
}

class PossibleNullAccessCodeFixProvider {
    FixableDiagnosticCodes: IEnumerable<string> => CodeFixActionHelpers.SingleDiagnosticCode("NL905")

    func GetCodeActions(diagnostic: Diagnostic, ast: object, sourceCode: string): List<CodeAction> {
        actions := new List<CodeAction>()
        line := diagnostic.Location.Line

        operatorColumn := 0
        replacementText := ""
        if CodeFixActionHelpers.TryGetPossibleNullAccessEdit(sourceCode, line, diagnostic.Location.Column, out operatorColumn, out replacementText) {
            edits := new List<TextEdit>()
            edits.Add(new TextEdit(line, operatorColumn, line, operatorColumn + 1, replacementText))
            if String.Compare(replacementText, "?.", StringComparison.Ordinal) == 0 {
                actions.Add(new CodeAction("Use null-conditional access (review result nullability)", "NL905", edits, CodeActionKind.QuickFix, FixSafety.ReviewNeeded))
            } else if String.Compare(replacementText, "?[", StringComparison.Ordinal) == 0 {
                actions.Add(new CodeAction("Use null-conditional index access (review result nullability)", "NL905", edits, CodeActionKind.QuickFix, FixSafety.ReviewNeeded))
            }
        }

        actions.Add(new CodeAction("Add a guard before using the maybe-null value", "NL905", new List<TextEdit>(), CodeActionKind.QuickFix, FixSafety.SuggestionOnly))
        actions.Add(new CodeAction("Add a fallback with ?? after a safe access", "NL905", new List<TextEdit>(), CodeActionKind.QuickFix, FixSafety.SuggestionOnly))
        actions.Add(new CodeAction("Assert non-null only after proving the value is present", "NL905", new List<TextEdit>(), CodeActionKind.QuickFix, FixSafety.SuggestionOnly))

        return actions
    }
}

class AddCommentToEmptyCatchCodeFixProvider {
    FixableDiagnosticCodes: IEnumerable<string> => CodeFixActionHelpers.SingleDiagnosticCode("NL011")

    func GetCodeActions(diagnostic: Diagnostic, ast: object, sourceCode: string): List<CodeAction> {
        actions := new List<CodeAction>()
        line := diagnostic.Location.Line

        column := 0
        newText := ""
        if CodeFixActionHelpers.TryGetEmptyCatchCommentEdit(sourceCode, line, out column, out newText) {
            edits := new List<TextEdit>()
            edits.Add(new TextEdit(line, column, line, column, newText))
            actions.Add(new CodeAction("Add TODO comment to empty catch block", "NL011", edits, CodeActionKind.QuickFix, FixSafety.Safe))
        }

        return actions
    }
}

class RemoveUnusedImportCodeFixProvider {
    FixableDiagnosticCodes: IEnumerable<string> => CodeFixActionHelpers.SingleDiagnosticCode("NL010")

    func GetCodeActions(diagnostic: Diagnostic, ast: object, sourceCode: string): List<CodeAction> {
        actions := new List<CodeAction>()
        line := diagnostic.Location.Line
        if line <= 0 {
            return actions
        }

        edits := new List<TextEdit>()
        edits.Add(new TextEdit(line, 0, line + 1, 0, ""))
        actions.Add(new CodeAction("Remove unused import", "NL010", edits, CodeActionKind.SourceOrganizeImports, FixSafety.ReviewNeeded))
        return actions
    }
}

class CodeFixActionHelpers {
    static func SingleDiagnosticCode(code: string): string[] {
        codes := new string[](1)
        codes[0] = code
        return codes
    }

    static func TryGetMissingImportNamespace(suggestion: string, out namespaceToImport: string): bool {
        namespaceToImport = ""
        prefix := "Add 'import "
        if !CodeFixStartsWith(suggestion, prefix) {
            return false
        }

        namespaceStart := prefix.Length
        namespaceEnd := CodeFixIndexOfCharFrom(suggestion, '\'', namespaceStart)
        if namespaceEnd <= namespaceStart {
            return false
        }

        namespaceToImport = suggestion.Substring(namespaceStart, namespaceEnd - namespaceStart)
        return true
    }

    static func TryGetRemoveUnusedVariableEdit(message: string, source: string, line: int, out title: string): bool {
        title = ""

        nameStartQuote := message.IndexOf('\'')
        nameEndQuote := CodeFixLastIndexOfChar(message, '\'')
        if nameStartQuote < 0 || nameEndQuote <= nameStartQuote {
            return false
        }

        variableName := message.Substring(nameStartQuote + 1, nameEndQuote - nameStartQuote - 1)
        sourceLine := ""
        if !TryGetSourceLine(source, line, out sourceLine) {
            return false
        }

        if sourceLine.IndexOf("let " + variableName, StringComparison.Ordinal) < 0 && sourceLine.IndexOf("var " + variableName, StringComparison.Ordinal) < 0 && sourceLine.IndexOf("const " + variableName, StringComparison.Ordinal) < 0 {
            return false
        }

        title = "Remove unused variable '" + variableName + "'"
        return true
    }

    static func TryGetUnnecessaryNullCheckEdit(source: string, line: int, out startColumn: int, out endColumn: int, out newText: string): bool {
        startColumn = 0
        endColumn = 0
        newText = ""

        if line <= 0 {
            return false
        }

        sourceLine := ""
        if !TryGetSourceLine(source, line, out sourceLine) {
            return false
        }

        notNullPattern := "!= null"
        nullPattern := "== null"
        patternStart := sourceLine.IndexOf(notNullPattern, StringComparison.Ordinal)
        replacement := "true"
        if patternStart < 0 {
            patternStart = sourceLine.IndexOf(nullPattern, StringComparison.Ordinal)
            replacement = "false"
        }

        if patternStart < 0 {
            return false
        }

        if !TryFindStatementConditionRange(sourceLine, patternStart, out startColumn, out endColumn) {
            return false
        }

        newText = replacement
        return true
    }

    static func TryGetEmptyCatchCommentEdit(source: string, line: int, out column: int, out newText: string): bool {
        column = 0
        newText = ""

        catchLine := ""
        if !TryGetSourceLine(source, line, out catchLine) {
            return false
        }

        indentLength := CodeFixLeadingWhitespaceCount(catchLine) + 4
        builder := new StringBuilder(indentLength + 27)
        builder.Append('\n')

        i := 0
        while i < indentLength {
            builder.Append(' ')
            i = i + 1
        }

        builder.Append("// TODO: handle exception")
        column = catchLine.Length
        newText = builder.ToString()
        return true
    }

    static func TryGetPossibleNullAccessEdit(source: string, line: int, column: int, out operatorColumn: int, out newText: string): bool {
        operatorColumn = 0
        newText = ""

        sourceLine := ""
        if !TryGetSourceLine(source, line, out sourceLine) {
            return false
        }

        diagnosticColumn := column - 1
        if diagnosticColumn < 0 {
            diagnosticColumn = 0
        }

        operatorIndex := CodeFixFindNullAccessOperator(sourceLine, diagnosticColumn)
        if operatorIndex < 0 {
            return false
        }

        operatorColumn = operatorIndex
        if sourceLine[operatorIndex] == '.' {
            newText = "?."
        } else {
            newText = "?["
        }

        return true
    }

    static func TryGetSourceLine(source: string, line: int, out sourceLine: string): bool {
        sourceLine = ""
        if line <= 0 {
            return false
        }

        currentLine := 1
        lineStart := 0
        index := 0
        sourceLength := source.Length
        while index < sourceLength {
            if source[index] == '\r' {
                if currentLine == line {
                    sourceLine = source.Substring(lineStart, index - lineStart)
                    return true
                }

                currentLine = currentLine + 1
                hasNext := index + 1 < sourceLength
                if hasNext {
                    if source[index + 1] == '\n' {
                        index = index + 2
                        lineStart = index
                        continue
                    }
                }

                index = index + 1
                lineStart = index
                continue
            }

            if source[index] == '\n' {
                if currentLine == line {
                    sourceLine = source.Substring(lineStart, index - lineStart)
                    return true
                }

                currentLine = currentLine + 1
                lineStart = index + 1
                index = index + 1
                continue
            }

            index = index + 1
        }

        if currentLine == line {
            sourceLine = source.Substring(lineStart, sourceLength - lineStart)
            return true
        }

        return false
    }

    static func CodeFixFindNullAccessOperator(sourceLine: string, diagnosticColumn: int): int {
        if diagnosticColumn >= 0 && diagnosticColumn < sourceLine.Length {
            if sourceLine[diagnosticColumn] == '.' || sourceLine[diagnosticColumn] == '[' {
                return diagnosticColumn
            }
        }

        i := diagnosticColumn
        lastIndex := sourceLine.Length - 1
        if i > lastIndex {
            i = lastIndex
        }

        while i >= 0 {
            if sourceLine[i] == '.' || sourceLine[i] == '[' {
                if i > 0 && sourceLine[i - 1] == '?' {
                    return -1
                }

                return i
            }

            i = i - 1
        }

        return -1
    }

    static func TryFindStatementConditionRange(sourceLine: string, patternStart: int, out startColumn: int, out endColumn: int): bool {
        startColumn = 0
        endColumn = 0

        ifIndex := sourceLine.IndexOf("if ", StringComparison.Ordinal)
        whileIndex := sourceLine.IndexOf("while ", StringComparison.Ordinal)

        keywordIndex := -1
        keywordLength := 2
        if ifIndex >= 0 && ifIndex < patternStart {
            keywordIndex = ifIndex
        }

        if whileIndex >= 0 && whileIndex < patternStart && (keywordIndex < 0 || whileIndex > keywordIndex) {
            keywordIndex = whileIndex
            keywordLength = 5
        }

        if keywordIndex < 0 {
            return false
        }

        conditionStart := keywordIndex + keywordLength
        while conditionStart < sourceLine.Length && CodeFixIsWhitespace(sourceLine[conditionStart]) {
            conditionStart = conditionStart + 1
        }

        braceIndex := CodeFixIndexOfCharFrom(sourceLine, '{', patternStart)
        conditionEnd := sourceLine.Length
        if braceIndex >= 0 {
            conditionEnd = braceIndex
        }

        while conditionEnd > conditionStart && CodeFixIsWhitespace(sourceLine[conditionEnd - 1]) {
            conditionEnd = conditionEnd - 1
        }

        if conditionStart >= conditionEnd {
            return false
        }

        startColumn = conditionStart
        endColumn = conditionEnd
        return true
    }

    static func CodeFixIndexOfCharFrom(text: string, ch: char, start: int): int {
        index := start
        if index < 0 {
            index = 0
        }

        while index < text.Length {
            if text[index] == ch {
                return index
            }

            index = index + 1
        }

        return -1
    }

    static func CodeFixStartsWith(text: string, prefix: string): bool {
        if text.Length < prefix.Length {
            return false
        }

        index := 0
        while index < prefix.Length {
            if text[index] != prefix[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func CodeFixLastIndexOfChar(text: string, ch: char): int {
        index := text.Length - 1
        while index >= 0 {
            if text[index] == ch {
                return index
            }

            index = index - 1
        }

        return -1
    }

    static func CodeFixLeadingWhitespaceCount(text: string): int {
        index := 0
        while index < text.Length && CodeFixIsWhitespace(text[index]) {
            index = index + 1
        }

        return index
    }

    static func CodeFixIsWhitespace(ch: char): bool {
        if ch == ' ' {
            return true
        }

        if ch <= '~' {
            return ch >= '\t' && ch <= '\r'
        }

        return Char.IsWhiteSpace(ch)
    }
}
