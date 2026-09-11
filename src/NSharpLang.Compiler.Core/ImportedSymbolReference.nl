namespace NSharpLang.Compiler

// ONE UNALIASED FILE IMPORT THAT BROUGHT A NAME INTO SCOPE, and the position at which it did.
//
// `DeclaresType` is what the collision report needs to suggest a fix that COMPILES. Aliasing an
// import always clears NL702, but it only leaves the aliased symbol reachable when that symbol is a
// TYPE: `Alias.Tag` as a type reference and `new Alias.Tag(...)` both resolve and emit, while an
// alias-qualified CALL — `Alias.Format(v)` — stops the build at NL103
// `emit.call.static-member-unmodeled`. So a colliding type is told to alias, and a colliding
// function is told to rename, because that is the fix the compiler will actually accept.
class ImportedSymbolReference {
    SourcePath: string
    ImportPath: string
    Line: int
    Column: int
    Length: int
    DeclaresType: bool

    constructor(SourcePath: string, ImportPath: string, Line: int, Column: int, Length: int, DeclaresType: bool) {
        this.SourcePath = SourcePath
        this.ImportPath = ImportPath
        this.Line = Line
        this.Column = Column
        this.Length = Length
        this.DeclaresType = DeclaresType
    }
}
