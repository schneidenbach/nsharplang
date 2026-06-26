namespace NSharpLang.Compiler

public struct DiagnosticSpan(line: int, column: int, length: int) {
    Line: int = line
    Column: int = column
    Length: int = length
}
