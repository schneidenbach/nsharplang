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

    constructor(sourceFile: string, targetFile: string, importPath: string, line: int, column: int, length: int) {
        this.SourceFile = sourceFile
        this.TargetFile = targetFile
        this.ImportPath = importPath
        this.Line = line
        this.Column = column
        this.Length = length
    }
}

public class ImportTraversalFrame {
    SourceFile: string
    Edges: IReadOnlyList<ImportEdge>
    NextEdgeIndex: int

    constructor(sourceFile: string, edges: IReadOnlyList<ImportEdge>) {
        this.SourceFile = sourceFile
        this.Edges = edges
        this.NextEdgeIndex = 0
    }
}
