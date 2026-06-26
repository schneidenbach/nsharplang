namespace NSharpLang.Compiler.Columnar

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
