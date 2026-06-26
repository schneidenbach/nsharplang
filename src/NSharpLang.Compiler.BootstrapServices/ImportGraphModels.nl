namespace NSharpLang.Compiler

import System.Collections.Generic

public enum ImportVisitState {
    Visiting,
    Visited
}

public class ImportEdge {
    SourceFile: string
    TargetFile: string
    ImportPath: string
    Line: int
    Column: int
    Length: int

    constructor(SourceFile: string, TargetFile: string, ImportPath: string, Line: int, Column: int, Length: int) {
        this.SourceFile = SourceFile
        this.TargetFile = TargetFile
        this.ImportPath = ImportPath
        this.Line = Line
        this.Column = Column
        this.Length = Length
    }
}

public class ImportTraversalFrame {
    SourceFile: string
    Edges: IReadOnlyList<ImportEdge>
    NextEdgeIndex: int

    constructor(SourceFile: string, Edges: IReadOnlyList<ImportEdge>) {
        this.SourceFile = SourceFile
        this.Edges = Edges
        this.NextEdgeIndex = 0
    }
}
