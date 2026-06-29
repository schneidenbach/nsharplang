namespace NSharpLang.Compiler.Ast

import System.Collections.Generic

public class SoaColumnDeclaration {
    Name: string
    Type: TypeReference
    Line: int
    Column: int

    constructor(name: string, typeReference: TypeReference, line: int = 0, column: int = 0) {
        Name = name
        Type = typeReference
        Line = line
        Column = column
    }
}

public class UnionCase {
    Name: string
    Properties: List<UnionCaseProperty>?
    Line: int
    Column: int

    constructor(name: string, properties: List<UnionCaseProperty>? = null, line: int = 0, column: int = 0) {
        Name = name
        Properties = properties
        Line = line
        Column = column
    }
}

public class UnionCaseProperty {
    Name: string
    Type: TypeReference

    constructor(name: string, typeReference: TypeReference) {
        Name = name
        Type = typeReference
    }
}
