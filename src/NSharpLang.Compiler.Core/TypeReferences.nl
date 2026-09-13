namespace NSharpLang.Compiler.Ast

import System.Collections.Generic
import NSharpLang.Compiler

class TypeReference {
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

class SimpleTypeReference: TypeReference {
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

class ArrayTypeReference: TypeReference {
    ElementType: TypeReference

    constructor(elementType: TypeReference) {
        ElementType = elementType
    }

    override func ToString(): string {
        return TypeReferenceFacts.GetDisplayName(ElementType) + "[]"
    }
}

class NullableTypeReference: TypeReference {
    InnerType: TypeReference

    constructor(innerType: TypeReference) {
        InnerType = innerType
    }

    override func ToString(): string {
        return TypeReferenceFacts.GetDisplayName(InnerType) + "?"
    }
}

class TupleTypeElement {
    Type: TypeReference
    Name: string?

    constructor(typeReference: TypeReference, name: string?) {
        Type = typeReference
        Name = name
    }
}

class TupleTypeReference: TypeReference {
    Elements: List<TupleTypeElement>

    constructor(elements: List<TupleTypeElement>) {
        Elements = elements
    }

    override func ToString(): string {
        return "(" + TypeReferenceFacts.JoinTupleElementDisplayNames(Elements) + ")"
    }
}

class GenericTypeReference: TypeReference {
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

class FunctionTypeReference: TypeReference {
    ParameterTypes: List<TypeReference>
    ReturnType: TypeReference

    // THE NAME THE SOURCE WROTE, AND WITHOUT IT THIS NODE NAMES NO TYPE AT ALL. `Func<int, bool>`
    // parses into parameter types and a return type, and the identifier `Func` — the one thing that
    // says which namespace supplies this type — was discarded. NL010 then reported `import System`
    // unused in every file whose only mention of it was a `Func<…>` annotation, and `nlc fix` offered
    // to delete that import.
    //
    // A HAND-BUILT TREE ANSWERS THE EMPTY STRING, which is the honest answer: it was not written
    // anywhere, so it mentions no name. Only the parser sets this, from the token it consumed.
    WrittenName: string

    constructor(parameterTypes: List<TypeReference>, returnType: TypeReference) {
        ParameterTypes = parameterTypes
        ReturnType = returnType
        WrittenName = ""
    }

    override func ToString(): string {
        return "(" + TypeReferenceFacts.JoinDisplayNames(ParameterTypes, ", ") + ") -> " + TypeReferenceFacts.GetDisplayName(ReturnType)
    }
}

class UnionTypeReference: TypeReference {
    Arms: List<TypeReference>

    constructor(arms: List<TypeReference>) {
        Arms = arms
    }

    override func ToString(): string {
        return TypeReferenceFacts.JoinDisplayNames(Arms, " | ")
    }
}

class ByRefTypeReference: TypeReference {
    InnerType: TypeReference

    constructor(innerType: TypeReference) {
        InnerType = innerType
    }

    override func ToString(): string {
        return "&" + TypeReferenceFacts.GetDisplayName(InnerType)
    }
}
