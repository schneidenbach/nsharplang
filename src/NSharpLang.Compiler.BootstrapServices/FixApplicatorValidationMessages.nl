namespace NSharpLang.Compiler.CodeIntelligence

public class FixApplicatorValidationMessages {
    public static func BuildValidationMessage(
        code: int,
        errorInfo: int[],
        startLines: int[],
        startColumns: int[],
        endLines: int[],
        endColumns: int[],
        count: int): string {
        if code == 1 {
            index := ValidationIndex(errorInfo, 0, count)
            return "Invalid edit position: " + FormatEditRange(startLines, startColumns, endLines, endColumns, index) + ". Lines are 1-based and columns must be non-negative."
        }

        if code == 2 {
            index := ValidationIndex(errorInfo, 0, count)
            return "Invalid edit range: " + FormatEditRange(startLines, startColumns, endLines, endColumns, index) + " ends before it starts."
        }

        if code == 3 {
            lowIndex := ValidationIndex(errorInfo, 0, count)
            highIndex := ValidationIndex(errorInfo, 1, count)
            return "Overlapping edits detected: edit at "
                + FormatEditRange(startLines, startColumns, endLines, endColumns, lowIndex)
                + " overlaps with edit at "
                + FormatEditRange(startLines, startColumns, endLines, endColumns, highIndex)
        }

        if code == 4 {
            index := ValidationIndex(errorInfo, 0, count)
            return "Invalid edit range: " + FormatEditRange(startLines, startColumns, endLines, endColumns, index) + " is outside the document."
        }

        return "N# fix applicator kernel rejected the edit validation."
    }

    static func ValidationIndex(errorInfo: int[], slot: int, count: int): int {
        if slot < 0 || slot >= errorInfo.Length {
            return 0
        }

        index := errorInfo[slot]
        if index < 0 {
            return 0
        }

        if index >= count {
            if count <= 0 {
                return 0
            }

            return count - 1
        }

        return index
    }

    static func FormatEditRange(
        startLines: int[],
        startColumns: int[],
        endLines: int[],
        endColumns: int[],
        index: int): string {
        return "("
            + startLines[index].ToString()
            + ","
            + startColumns[index].ToString()
            + ")..("
            + endLines[index].ToString()
            + ","
            + endColumns[index].ToString()
            + ")"
    }
}
