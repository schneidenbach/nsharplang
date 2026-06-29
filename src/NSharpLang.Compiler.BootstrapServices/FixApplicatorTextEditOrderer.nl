namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler

public class FixApplicatorTextEditOrderer {
    public static func OrderTextEdits(edits: IReadOnlyCollection<TextEdit>): List<TextEdit> {
        count := edits.Count
        editList := new List<TextEdit>()
        foreach edit in edits {
            editList.Add(edit as TextEdit)
        }

        startLines := new int[](count)
        startColumns := new int[](count)
        endLines := new int[](count)
        endColumns := new int[](count)
        resultIndices := new int[](count)
        i := 0
        while i < count {
            edit := editList[i]
            startLines[i] = edit.StartLine
            startColumns[i] = edit.StartColumn
            endLines[i] = edit.EndLine
            endColumns[i] = edit.EndColumn
            resultIndices[i] = i
            i = i + 1
        }

        i = 1
        while i < count {
            currentIndex := resultIndices[i]
            j := i

            while j > 0 {
                previousIndex := resultIndices[j - 1]
                if !TextEditOrderIndexComesBefore(
                    currentIndex,
                    previousIndex,
                    startLines,
                    startColumns,
                    endLines,
                    endColumns) {
                    break
                }

                resultIndices[j] = previousIndex
                j = j - 1
            }

            resultIndices[j] = currentIndex
            i = i + 1
        }

        ordered := new List<TextEdit>()
        i = 0
        while i < count {
            ordered.Add(editList[resultIndices[i]])
            i = i + 1
        }

        return ordered
    }

    static func TextEditOrderIndexComesBefore(
        leftIndex: int,
        rightIndex: int,
        startLines: int[],
        startColumns: int[],
        endLines: int[],
        endColumns: int[]): bool {
        leftStartLine := startLines[leftIndex]
        rightStartLine := startLines[rightIndex]
        if leftStartLine != rightStartLine {
            return leftStartLine > rightStartLine
        }

        leftStartColumn := startColumns[leftIndex]
        rightStartColumn := startColumns[rightIndex]
        if leftStartColumn != rightStartColumn {
            return leftStartColumn > rightStartColumn
        }

        leftEndLine := endLines[leftIndex]
        rightEndLine := endLines[rightIndex]
        if leftEndLine != rightEndLine {
            return leftEndLine < rightEndLine
        }

        leftEndColumn := endColumns[leftIndex]
        rightEndColumn := endColumns[rightIndex]
        if leftEndColumn != rightEndColumn {
            return leftEndColumn < rightEndColumn
        }

        return leftIndex > rightIndex
    }
}
