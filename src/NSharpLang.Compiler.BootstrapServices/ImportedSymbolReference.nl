namespace NSharpLang.Compiler

public class ImportedSymbolReference {
    SourcePath: string
    ImportPath: string
    Line: int
    Column: int
    Length: int

    constructor(SourcePath: string, ImportPath: string, Line: int, Column: int, Length: int) {
        this.SourcePath = SourcePath
        this.ImportPath = ImportPath
        this.Line = Line
        this.Column = Column
        this.Length = Length
    }
}
