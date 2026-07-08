namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic

public class ColumnarEnumInput {
    nameValue: string
    memberNamesValue: string[]
    memberValuesValue: int[]
    isStringBackedValue: bool
    memberStringValuesValue: string[]
    SourceFileId: int

    Name: string => nameValue
    MemberNames: string[] => memberNamesValue
    MemberValues: int[] => memberValuesValue
    IsStringBacked: bool => isStringBackedValue
    MemberStringValues: string[] => memberStringValuesValue

    constructor(
        name: string,
        memberNames: string[],
        memberValues: int[],
        isStringBacked: bool = false,
        memberStringValues: string[]? = null,
        sourceFileId: int = 0) {
        nameValue = name
        memberNamesValue = memberNames
        memberValuesValue = memberValues
        isStringBackedValue = isStringBacked
        memberStringValuesValue = memberStringValues ?? new string[](0)
        SourceFileId = sourceFileId
    }
}

public class ColumnarUnionInput {
    nameValue: string
    caseNamesValue: string[]
    caseFieldNamesValue: string[][]
    caseFieldTypeCanonicalsValue: string[][]
    typeParamNamesValue: string[]
    isValueStructValue: bool
    SourceFileId: int

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
        isValueStruct: bool = false,
        sourceFileId: int = 0) {
        nameValue = name
        caseNamesValue = caseNames
        caseFieldNamesValue = caseFieldNames
        caseFieldTypeCanonicalsValue = caseFieldTypeCanonicals
        typeParamNamesValue = typeParamNames ?? new string[](0)
        isValueStructValue = isValueStruct
        SourceFileId = sourceFileId
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
    ModifierFlags: int
    SourceFileId: int
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
        isAsync: bool = false,
        modifierFlags: int = 0,
        sourceFileId: int = 0) {
        Name = name
        ReturnCanonical = returnCanonical
        IsAsync = isAsync
        ModifierFlags = modifierFlags
        SourceFileId = sourceFileId
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
    SourceFileId: int

    constructor(
        body: ColumnarFunctionInput,
        chainInitKind: int,
        chainArgKinds: int[],
        chainArgTexts: string[],
        paramDefaultKinds: int[]? = null,
        paramDefaultTexts: string[]? = null,
        isSynthesizedInitializer: bool = false,
        sourceFileId: int = 0) {
        Body = body
        ChainInitKind = chainInitKind
        ChainArgKinds = chainArgKinds
        ChainArgTexts = chainArgTexts
        ParamDefaultKinds = paramDefaultKinds ?? new int[](0)
        ParamDefaultTexts = paramDefaultTexts ?? new string[](0)
        IsSynthesizedInitializer = isSynthesizedInitializer
        SourceFileId = sourceFileId
    }
}

public class ColumnarPropertyInput {
    IsStatic: bool
    Name: string
    TypeCanonical: string
    Getter: ColumnarFunctionInput
    Setter: ColumnarFunctionInput?
    SourceFileId: int

    constructor(
        name: string,
        typeCanonical: string,
        getter: ColumnarFunctionInput,
        setter: ColumnarFunctionInput?,
        isStatic: bool = false,
        sourceFileId: int = 0) {
        IsStatic = isStatic
        Name = name
        TypeCanonical = typeCanonical
        Getter = getter
        Setter = setter
        SourceFileId = sourceFileId
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
    FieldReadonlyFlags: bool[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]
    IsRecord: bool
    TypeParamNames: string[]
    SourceFileId: int

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
        typeParamNames: string[]? = null,
        fieldReadonlyFlags: bool[]? = null,
        sourceFileId: int = 0) {
        Name = name
        FieldNames = fieldNames
        FieldTypeCanonicals = fieldTypeCanonicals
        Methods = methods
        Constructors = constructors
        Properties = properties
        IsReference = isReference
        BaseNames = baseNames ?? new string[](0)
        FieldStaticFlags = fieldStaticFlags ?? new bool[](fieldNames.Length)
        FieldReadonlyFlags = fieldReadonlyFlags ?? new bool[](fieldNames.Length)
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
        SourceFileId = sourceFileId
    }
}

public class ColumnarInterfaceInput {
    Name: string
    BaseInterfaceNames: string[]
    MethodNames: string[]
    MethodReturnCanonicals: string[]
    MethodParamNames: string[][]
    MethodParamCanonicals: string[][]
    MethodBodies: ColumnarFunctionInput?[]
    SourceFileId: int

    constructor(
        name: string,
        baseInterfaceNames: string[],
        methodNames: string[],
        methodReturnCanonicals: string[],
        methodParamNames: string[][],
        methodParamCanonicals: string[][],
        methodBodies: ColumnarFunctionInput?[]? = null,
        sourceFileId: int = 0) {
        Name = name
        BaseInterfaceNames = baseInterfaceNames
        MethodNames = methodNames
        MethodReturnCanonicals = methodReturnCanonicals
        MethodParamNames = methodParamNames
        MethodParamCanonicals = methodParamCanonicals
        MethodBodies = methodBodies ?? new ColumnarFunctionInput?[](methodNames.Length)
        SourceFileId = sourceFileId
    }
}

public class ColumnarProgramInput {
    Source: string
    Sources: ColumnarSourceFile[]
    Functions: IReadOnlyList<ColumnarFunctionInput>
    Enums: IReadOnlyList<ColumnarEnumInput>
    Structs: IReadOnlyList<ColumnarStructInput>
    Unions: IReadOnlyList<ColumnarUnionInput>
    Interfaces: IReadOnlyList<ColumnarInterfaceInput>

    constructor(
        source: string,
        functions: IReadOnlyList<ColumnarFunctionInput>,
        enums: IReadOnlyList<ColumnarEnumInput>,
        structs: IReadOnlyList<ColumnarStructInput>,
        unions: IReadOnlyList<ColumnarUnionInput>,
        interfaces: IReadOnlyList<ColumnarInterfaceInput>,
        sourceFiles: ColumnarSourceFile[]? = null) {
        Source = source
        Sources = sourceFiles ?? BuildSingleSourceFiles(source)
        Functions = functions
        Enums = enums
        Structs = structs
        Unions = unions
        Interfaces = interfaces
    }

    public func GetSourceForFileId(fileId: int): string {
        if fileId >= 0 && fileId < Sources.Length {
            return Sources[fileId].Source
        }

        return Source
    }

    static func BuildSingleSourceFiles(source: string): ColumnarSourceFile[] {
        sources := new string[](1)
        fileNames := new string[](1)
        sources[0] = source
        fileNames[0] = ""
        return ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames)
    }
}
