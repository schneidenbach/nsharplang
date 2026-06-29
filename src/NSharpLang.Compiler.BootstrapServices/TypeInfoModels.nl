namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast

public class TypeInfo {
}

public class TupleTypeElementInfo {
    Name: string?
    Type: TypeInfo

    constructor(name: string?, elementType: TypeInfo) {
        Name = name
        Type = elementType
    }
}

public class TupleTypeInfo: TypeInfo {
    Elements: List<TupleTypeElementInfo>

    constructor(elements: List<TupleTypeElementInfo>) {
        Elements = elements
    }
}

public class AliasTypeInfo: TypeInfo {
    aliasedTypeValue: TypeReference

    AliasedType: TypeReference => aliasedTypeValue

    constructor(aliasedType: TypeReference) {
        aliasedTypeValue = aliasedType
    }
}
