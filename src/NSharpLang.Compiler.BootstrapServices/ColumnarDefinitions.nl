namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

public class ColumnarEnumDef {
    enumTypeValue: Type
    constantsValue: Dictionary<string, int>
    stringConstantsValue: Dictionary<string, string>?

    EnumType: Type => enumTypeValue
    Constants: Dictionary<string, int> => constantsValue
    StringConstants: Dictionary<string, string>? => stringConstantsValue
    IsStringBacked: bool => stringConstantsValue != null

    constructor(enumType: Type, constants: Dictionary<string, int>, stringConstants: Dictionary<string, string>? = null) {
        enumTypeValue = enumType
        constantsValue = constants
        stringConstantsValue = stringConstants
    }
}

public class ColumnarUnionDef {
    Base: TypeBuilder
    Cases: Dictionary<string, ColumnarUnionCaseDef>
    TypeParamCount: int
    IsValueStruct: bool
    TagGetter: MethodInfo?

    constructor(baseBuilder: TypeBuilder, typeParamCount: int = 0) {
        Base = baseBuilder
        Cases = new Dictionary<string, ColumnarUnionCaseDef>(StringComparer.Ordinal)
        TypeParamCount = typeParamCount
        IsValueStruct = false
    }
}

public class ColumnarUnionCaseDef {
    CaseType: TypeBuilder
    Ctor: ConstructorBuilder
    FieldOrder: string[]
    Fields: Dictionary<string, FieldBuilder>
    UnionBase: TypeBuilder
    IsValueStruct: bool
    ValueStructTag: int
    ValueStructFactory: MethodInfo?
    ValueStructTagGetter: MethodInfo?

    constructor(caseType: TypeBuilder, ctor: ConstructorBuilder, fieldOrder: string[], fields: Dictionary<string, FieldBuilder>, unionBase: TypeBuilder) {
        CaseType = caseType
        Ctor = ctor
        FieldOrder = fieldOrder
        Fields = fields
        UnionBase = unionBase
        IsValueStruct = false
        ValueStructTag = 0
    }
}
