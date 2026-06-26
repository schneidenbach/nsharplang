namespace NSharpLang.Compiler

public class ErrorTupleResultGuard {
    ResultName: string
    ErrorName: string
    Line: int
    Column: int

    constructor(ResultName: string, ErrorName: string, Line: int, Column: int) {
        this.ResultName = ResultName
        this.ErrorName = ErrorName
        this.Line = Line
        this.Column = Column
    }
}
