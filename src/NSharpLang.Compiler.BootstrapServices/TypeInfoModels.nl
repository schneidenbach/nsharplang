namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast

public class TypeInfo {
}

public class AliasTypeInfo: TypeInfo {
    aliasedTypeValue: TypeReference

    AliasedType: TypeReference => aliasedTypeValue

    constructor(aliasedType: TypeReference) {
        aliasedTypeValue = aliasedType
    }
}
