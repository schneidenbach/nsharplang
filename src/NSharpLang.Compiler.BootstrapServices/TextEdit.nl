namespace NSharpLang.Compiler

public class TextEdit {
    StartLine: int
    StartColumn: int
    EndLine: int
    EndColumn: int
    NewText: string

    constructor(StartLine: int, StartColumn: int, EndLine: int, EndColumn: int, NewText: string) {
        this.StartLine = StartLine
        this.StartColumn = StartColumn
        this.EndLine = EndLine
        this.EndColumn = EndColumn
        this.NewText = NewText
    }

    override func Equals(value: object): bool {
        other := value as TextEdit
        if other == null {
            return false
        }

        return StartLine == other.StartLine
            && StartColumn == other.StartColumn
            && EndLine == other.EndLine
            && EndColumn == other.EndColumn
            && NewText == other.NewText
    }

    override func GetHashCode(): int {
        hash := 17
        hash = hash * 23 + StartLine
        hash = hash * 23 + StartColumn
        hash = hash * 23 + EndLine
        hash = hash * 23 + EndColumn
        if NewText != null {
            hash = hash * 23 + NewText.GetHashCode()
        }
        return hash
    }
}
