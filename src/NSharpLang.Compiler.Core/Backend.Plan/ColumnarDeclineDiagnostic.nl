namespace NSharpLang.Compiler

class ColumnarDeclineDiagnostic {
    detailValue: string?
    fileNameValue: string?
    lineValue: int
    columnValue: int
    spanLengthValue: int

    Detail: string? => detailValue
    FileName: string? => fileNameValue
    Line: int => lineValue
    Column: int => columnValue
    SpanLength: int => spanLengthValue

    static Empty: ColumnarDeclineDiagnostic => new ColumnarDeclineDiagnostic(null, null, 0, 0, 1)

    constructor(detail: string?, fileName: string?, line: int, column: int, spanLength: int) {
        detailValue = detail
        fileNameValue = fileName
        lineValue = line
        columnValue = column
        spanLengthValue = spanLength
    }
}
