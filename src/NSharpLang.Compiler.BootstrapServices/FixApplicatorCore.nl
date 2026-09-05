namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler

class FixApplicatorEditInputs {
    StartLines: int[]
    StartColumns: int[]
    EndLines: int[]
    EndColumns: int[]
    NewTexts: string[]
    Count: int

    constructor(startLines: int[], startColumns: int[], endLines: int[], endColumns: int[], newTexts: string[], count: int) {
        StartLines = startLines
        StartColumns = startColumns
        EndLines = endLines
        EndColumns = endColumns
        NewTexts = newTexts
        Count = count
    }
}

class FixApplicatorCore {
    static func ApplyEdits(source: string, edits: List<TextEdit>): string {
        if edits.Count == 0 {
            return source
        }

        sortedEdits := ValidateAndSortEdits(source, edits)
        inputs := MaterializeEditInputs(sortedEdits)
        output := new string[](1)
        code := FixApplicatorEditEngine.ApplyOrderedTextEdits(source, inputs.StartLines, inputs.StartColumns, inputs.EndLines, inputs.EndColumns, inputs.NewTexts, inputs.Count, output)

        if code != 0 {
            throw new InvalidOperationException("N# fix applicator kernel rejected the edit application.")
        }

        return output[0]
    }

    static func ValidateAndSortEdits(edits: IReadOnlyCollection<TextEdit>): List<TextEdit> {
        sortedEdits := FixApplicatorTextEditOrderer.OrderTextEdits(edits)
        ValidateSortedEdits(null, sortedEdits)
        return sortedEdits
    }

    static func ValidateAndSortEdits(source: string, edits: IReadOnlyCollection<TextEdit>): List<TextEdit> {
        sortedEdits := ValidateAndSortEdits(edits)
        ValidateSortedEdits(source, sortedEdits)
        return sortedEdits
    }

    static func ValidateSortedEdits(source: string?, sortedEdits: List<TextEdit>) {
        inputs := MaterializeEditInputs(sortedEdits)
        errorInfo := new int[](2)

        sourceText := ""
        hasSource := 0
        if source != null {
            sourceText = source
            hasSource = 1
        }

        code := FixApplicatorEditEngine.ValidateOrderedTextEdits(sourceText, hasSource, inputs.StartLines, inputs.StartColumns, inputs.EndLines, inputs.EndColumns, inputs.NewTexts, inputs.Count, errorInfo)

        if code == 0 {
            return
        }

        message := FixApplicatorValidationMessages.BuildValidationMessage(code, errorInfo, inputs.StartLines, inputs.StartColumns, inputs.EndLines, inputs.EndColumns, inputs.Count)
        throw new InvalidOperationException(message)
    }

    static func MaterializeEditInputs(edits: IReadOnlyList<TextEdit>): FixApplicatorEditInputs {
        count := edits.Count
        startLines := new int[](count)
        startColumns := new int[](count)
        endLines := new int[](count)
        endColumns := new int[](count)
        newTexts := new string[](count)

        i := 0
        while i < count {
            edit := edits[i]
            startLines[i] = edit.StartLine
            startColumns[i] = edit.StartColumn
            endLines[i] = edit.EndLine
            endColumns[i] = edit.EndColumn
            newTexts[i] = edit.NewText
            i = i + 1
        }

        return new FixApplicatorEditInputs(startLines, startColumns, endLines, endColumns, newTexts, count)
    }
}
