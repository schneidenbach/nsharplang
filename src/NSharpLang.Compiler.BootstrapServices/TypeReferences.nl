namespace NSharpLang.Compiler.Ast

import System.Collections.Generic

public class TypeReference {
    Span: SourceSpan = SourceSpan.None
}

public class SimpleTypeReference: TypeReference {
    Name: string
    Line: int
    Column: int

    NameSpan: SourceSpan => Span.IsValid ? Span : SourceSpan.FromStartAndLength(Line, Column, Name.Length)

    constructor(name: string, line: int = 0, column: int = 0) {
        Name = name
        Line = line
        Column = column
    }
}

public class ArrayTypeReference: TypeReference {
    ElementType: TypeReference

    constructor(elementType: TypeReference) {
        ElementType = elementType
    }
}

public class NullableTypeReference: TypeReference {
    InnerType: TypeReference

    constructor(innerType: TypeReference) {
        InnerType = innerType
    }
}

public class TupleTypeElement {
    Type: TypeReference
    Name: string?

    constructor(typeReference: TypeReference, name: string?) {
        Type = typeReference
        Name = name
    }
}

public class TupleTypeReference: TypeReference {
    Elements: List<TupleTypeElement>

    constructor(elements: List<TupleTypeElement>) {
        Elements = elements
    }
}

public class GenericTypeReference: TypeReference {
    Name: string
    TypeArguments: List<TypeReference>
    Line: int
    Column: int

    NameSpan: SourceSpan => SourceSpan.FromStartAndLength(Line, Column, Name.Length)

    constructor(name: string, typeArguments: List<TypeReference>, line: int = 0, column: int = 0) {
        Name = name
        TypeArguments = typeArguments
        Line = line
        Column = column
    }
}

public class ByRefTypeReference: TypeReference {
    InnerType: TypeReference

    constructor(innerType: TypeReference) {
        InnerType = innerType
    }
}
