namespace NSharpLang.Compiler.Ast

class PackageDeclaration {
    Name: string
    Line: int
    Column: int

    constructor(Name: string, Line: int, Column: int) {
        this.Name = Name
        this.Line = Line
        this.Column = Column
    }
}

class NamespaceDeclaration {
    Name: string
    Line: int
    Column: int

    constructor(Name: string, Line: int, Column: int) {
        this.Name = Name
        this.Line = Line
        this.Column = Column
    }
}
