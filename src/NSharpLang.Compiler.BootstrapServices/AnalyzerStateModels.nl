namespace NSharpLang.Compiler

public enum AttributeArgumentConstantKind {
    Null,
    Bool,
    Integer,
    Floating,
    Char,
    String,
    Type,
    Enum,
    Array,
    UnknownStaticMember
}

public enum DiscardedExpressionContext {
    ExpressionStatement,
    ForIterator
}

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
