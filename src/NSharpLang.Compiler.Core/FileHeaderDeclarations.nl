namespace NSharpLang.Compiler.Ast

import System.Collections.Generic


// One dotted-name segment AS WRITTEN, with the span that underlines it. Recovery preserves the
// developer's text here even when the segment is not a valid identifier (`good.9bad` carries
// "9bad"), so the analyzer's report can name what was written instead of a placeholder. A segment
// whose Text is "<error>" is a recovery placeholder with no written text behind it (end of file,
// reserved keyword, detached offender) — the parser has already reported precisely at that site.
class PackageNameSegment {
    Text: string
    Line: int
    Column: int
    Length: int

    constructor(Text: string, Line: int, Column: int, Length: int) {
        this.Text = Text
        this.Line = Line
        this.Column = Column
        this.Length = Length
    }
}

class PackageDeclaration {
    Name: string
    Line: int
    Column: int
    // Populated by the parser; null on hand-constructed nodes, where consumers fall back to
    // splitting Name and anchoring on the declaration.
    Segments: List<PackageNameSegment>?

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
