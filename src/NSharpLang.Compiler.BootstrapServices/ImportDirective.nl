namespace NSharpLang.Compiler.Ast

public class ImportDirective {
    Namespace: string
    Alias: string?
    Line: int
    Column: int

    constructor(Namespace: string, Alias: string?, Line: int, Column: int) {
        this.Namespace = Namespace
        this.Alias = Alias
        this.Line = Line
        this.Column = Column
    }
}
