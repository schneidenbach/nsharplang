namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic

public class ColumnarEnumInput {
    nameValue: string
    memberNamesValue: string[]
    memberValuesValue: int[]

    Name: string => nameValue
    MemberNames: string[] => memberNamesValue
    MemberValues: int[] => memberValuesValue

    constructor(name: string, memberNames: string[], memberValues: int[]) {
        nameValue = name
        memberNamesValue = memberNames
        memberValuesValue = memberValues
    }
}

public class ColumnarUnionInput {
    nameValue: string
    caseNamesValue: string[]
    caseFieldNamesValue: string[][]
    caseFieldTypeCanonicalsValue: string[][]
    typeParamNamesValue: string[]
    isValueStructValue: bool

    Name: string => nameValue
    CaseNames: string[] => caseNamesValue
    CaseFieldNames: string[][] => caseFieldNamesValue
    CaseFieldTypeCanonicals: string[][] => caseFieldTypeCanonicalsValue
    TypeParamNames: string[] => typeParamNamesValue
    IsValueStruct: bool => isValueStructValue

    constructor(
        name: string,
        caseNames: string[],
        caseFieldNames: string[][],
        caseFieldTypeCanonicals: string[][],
        typeParamNames: string[]? = null,
        isValueStruct: bool = false) {
        nameValue = name
        caseNamesValue = caseNames
        caseFieldNamesValue = caseFieldNames
        caseFieldTypeCanonicalsValue = caseFieldTypeCanonicals
        typeParamNamesValue = typeParamNames ?? new string[](0)
        isValueStructValue = isValueStruct
    }
}

public class ColumnarFunctionInput {
    Name: string
    ReturnCanonical: string
    ParamNames: string[]
    ParamCanonicals: string[]
    ParamModifierKinds: int[]
    ParamDefaultKinds: int[]
    ParamDefaultTexts: string[]
    BodyNodes: ColumnarNodeTable
    BodyRoot: int
    IsStatic: bool
    IsAsync: bool
    ReturnTupleElementNames: string[]?
    ParamTupleElementNames: string[][]?
    TypeParamNames: string[]
    TypeParamSpecialConstraints: int[]
    TypeParamTypeConstraints: string[][]
    public LocalFunctions: List<ColumnarLocalFunctionInput>?

    constructor(
        name: string,
        returnCanonical: string,
        paramNames: string[],
        paramCanonicals: string[],
        bodyNodes: ColumnarNodeTable,
        bodyRoot: int,
        isStatic: bool = false,
        typeParamNames: string[]? = null,
        typeParamSpecialConstraints: int[]? = null,
        typeParamTypeConstraints: string[][]? = null,
        returnTupleElementNames: string[]? = null,
        paramTupleElementNames: string[][]? = null,
        paramModifierKinds: int[]? = null,
        paramDefaultKinds: int[]? = null,
        paramDefaultTexts: string[]? = null,
        isAsync: bool = false) {
        Name = name
        ReturnCanonical = returnCanonical
        IsAsync = isAsync
        ParamNames = paramNames
        ParamCanonicals = paramCanonicals
        ParamModifierKinds = paramModifierKinds ?? new int[](0)
        ParamDefaultKinds = paramDefaultKinds ?? new int[](0)
        ParamDefaultTexts = paramDefaultTexts ?? new string[](0)
        BodyNodes = bodyNodes
        BodyRoot = bodyRoot
        IsStatic = isStatic
        ReturnTupleElementNames = returnTupleElementNames
        ParamTupleElementNames = paramTupleElementNames
        TypeParamNames = typeParamNames ?? new string[](0)
        TypeParamSpecialConstraints = typeParamSpecialConstraints ?? new int[](TypeParamNames.Length)
        if typeParamTypeConstraints == null {
            typeParamTypeConstraints = new string[][](TypeParamNames.Length)
            t := 0
            while t < typeParamTypeConstraints.Length {
                typeParamTypeConstraints[t] = new string[](0)
                t = t + 1
            }
        }
        TypeParamTypeConstraints = typeParamTypeConstraints
    }
}

public class ColumnarLocalFunctionInput {
    NodeIndex: int
    Function: ColumnarFunctionInput

    constructor(nodeIndex: int, function: ColumnarFunctionInput) {
        NodeIndex = nodeIndex
        Function = function
    }
}

public class ColumnarConstructorInput {
    Body: ColumnarFunctionInput
    ChainInitKind: int
    ChainArgKinds: int[]
    ChainArgTexts: string[]
    ParamDefaultKinds: int[]
    ParamDefaultTexts: string[]
    IsSynthesizedInitializer: bool

    constructor(
        body: ColumnarFunctionInput,
        chainInitKind: int,
        chainArgKinds: int[],
        chainArgTexts: string[],
        paramDefaultKinds: int[]? = null,
        paramDefaultTexts: string[]? = null,
        isSynthesizedInitializer: bool = false) {
        Body = body
        ChainInitKind = chainInitKind
        ChainArgKinds = chainArgKinds
        ChainArgTexts = chainArgTexts
        ParamDefaultKinds = paramDefaultKinds ?? new int[](0)
        ParamDefaultTexts = paramDefaultTexts ?? new string[](0)
        IsSynthesizedInitializer = isSynthesizedInitializer
    }
}

public class ColumnarPropertyInput {
    IsStatic: bool
    Name: string
    TypeCanonical: string
    Getter: ColumnarFunctionInput
    Setter: ColumnarFunctionInput?

    constructor(
        name: string,
        typeCanonical: string,
        getter: ColumnarFunctionInput,
        setter: ColumnarFunctionInput?,
        isStatic: bool = false) {
        IsStatic = isStatic
        Name = name
        TypeCanonical = typeCanonical
        Getter = getter
        Setter = setter
    }
}

public class ColumnarStructInput {
    Name: string
    FieldNames: string[]
    FieldTypeCanonicals: string[]
    Methods: IReadOnlyList<ColumnarFunctionInput>
    Constructors: IReadOnlyList<ColumnarConstructorInput>
    Properties: IReadOnlyList<ColumnarPropertyInput>
    IsReference: bool
    BaseNames: string[]
    FieldStaticFlags: bool[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]
    IsRecord: bool
    TypeParamNames: string[]

    constructor(
        name: string,
        fieldNames: string[],
        fieldTypeCanonicals: string[],
        methods: IReadOnlyList<ColumnarFunctionInput>,
        constructors: IReadOnlyList<ColumnarConstructorInput>,
        properties: IReadOnlyList<ColumnarPropertyInput>,
        isReference: bool,
        baseNames: string[]? = null,
        fieldStaticFlags: bool[]? = null,
        fieldInitKinds: int[]? = null,
        fieldInitTexts: string[]? = null,
        isRecord: bool = false,
        typeParamNames: string[]? = null) {
        Name = name
        FieldNames = fieldNames
        FieldTypeCanonicals = fieldTypeCanonicals
        Methods = methods
        Constructors = constructors
        Properties = properties
        IsReference = isReference
        BaseNames = baseNames ?? new string[](0)
        FieldStaticFlags = fieldStaticFlags ?? new bool[](fieldNames.Length)
        if fieldInitKinds == null {
            fieldInitKinds = new int[](fieldNames.Length)
            i := 0
            while i < fieldInitKinds.Length {
                fieldInitKinds[i] = -1
                i = i + 1
            }
        }
        FieldInitKinds = fieldInitKinds
        FieldInitTexts = fieldInitTexts ?? new string[](fieldNames.Length)
        IsRecord = isRecord
        TypeParamNames = typeParamNames ?? new string[](0)
    }
}
