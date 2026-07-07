namespace NSharpLang.Compiler.Ast

import System.Collections.Generic
import NSharpLang.Compiler

public class TypeReference {
    spanValue: SourceSpan
    spanAssignedValue: bool

    Span: SourceSpan {
        get {
            if !spanAssignedValue {
                return SourceSpan.None
            }

            return spanValue
        }
        set {
            spanValue = value
            spanAssignedValue = true
        }
    }
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

    override func ToString(): string {
        return Name
    }
}

public class ArrayTypeReference: TypeReference {
    ElementType: TypeReference

    constructor(elementType: TypeReference) {
        ElementType = elementType
    }

    override func ToString(): string {
        return TypeReferenceFacts.GetDisplayName(ElementType) + "[]"
    }
}

public class NullableTypeReference: TypeReference {
    InnerType: TypeReference

    constructor(innerType: TypeReference) {
        InnerType = innerType
    }

    override func ToString(): string {
        return TypeReferenceFacts.GetDisplayName(InnerType) + "?"
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

    override func ToString(): string {
        return "(" + TypeReferenceFacts.JoinTupleElementDisplayNames(Elements) + ")"
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

    override func ToString(): string {
        return Name + "<" + TypeReferenceFacts.JoinDisplayNames(TypeArguments, ", ") + ">"
    }
}

public class FunctionTypeReference: TypeReference {
    ParameterTypes: List<TypeReference>
    ReturnType: TypeReference

    constructor(parameterTypes: List<TypeReference>, returnType: TypeReference) {
        ParameterTypes = parameterTypes
        ReturnType = returnType
    }

    override func ToString(): string {
        return "(" + TypeReferenceFacts.JoinDisplayNames(ParameterTypes, ", ") + ") -> " + TypeReferenceFacts.GetDisplayName(ReturnType)
    }
}

public class UnionTypeReference: TypeReference {
    Arms: List<TypeReference>

    constructor(arms: List<TypeReference>) {
        Arms = arms
    }

    override func ToString(): string {
        return TypeReferenceFacts.JoinDisplayNames(Arms, " | ")
    }
}

public class ByRefTypeReference: TypeReference {
    InnerType: TypeReference

    constructor(innerType: TypeReference) {
        InnerType = innerType
    }

    override func ToString(): string {
        return "&" + TypeReferenceFacts.GetDisplayName(InnerType)
    }
}
