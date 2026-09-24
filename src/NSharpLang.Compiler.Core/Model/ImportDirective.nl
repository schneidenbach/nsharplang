namespace NSharpLang.Compiler.Ast

class ImportDirective {
    Namespace: string
    Alias: string?
    Line: int
    Column: int

    constructor(namespaceName: string, alias: string?, line: int, column: int) {
        this.Namespace = namespaceName
        this.Alias = alias
        this.Line = line
        this.Column = column
    }
}
