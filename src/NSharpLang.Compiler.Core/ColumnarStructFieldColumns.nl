namespace NSharpLang.Compiler.Columnar

class ColumnarStructFieldColumns {
    FieldNames: string[]
    FieldTypeCanonicals: string[]
    FieldStaticFlags: bool[]
    FieldReadonlyFlags: bool[]
    FieldPrivateFlags: bool[]
    FieldThreadStaticFlags: bool[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]

    constructor(
        fieldNames: string[],
        fieldTypeCanonicals: string[],
        fieldStaticFlags: bool[],
        fieldReadonlyFlags: bool[],
        fieldPrivateFlags: bool[],
        fieldThreadStaticFlags: bool[],
        fieldInitKinds: int[],
        fieldInitTexts: string[]
    ) {
        FieldNames = fieldNames
        FieldTypeCanonicals = fieldTypeCanonicals
        FieldStaticFlags = fieldStaticFlags
        FieldReadonlyFlags = fieldReadonlyFlags
        FieldPrivateFlags = fieldPrivateFlags
        FieldThreadStaticFlags = fieldThreadStaticFlags
        FieldInitKinds = fieldInitKinds
        FieldInitTexts = fieldInitTexts
    }

    static func Build(
        rawNames: string[],
        rawTypes: string[],
        packedFlags: int[],
        rawInitKinds: int[],
        rawInitTexts: string[],
        count: int
    ): ColumnarStructFieldColumns {
        fieldNames := new string[](count)
        fieldTypes := new string[](count)
        fieldStatics := new bool[](count)
        fieldReadonlyFlags := new bool[](count)
        fieldInitKinds := new int[](count)
        fieldInitTexts := new string[](count)
        fieldPrivateFlags := new bool[](count)
        fieldThreadStaticFlags := new bool[](count)

        fieldIndex := 0
        while fieldIndex < count {
            fieldName := rawNames[fieldIndex]
            fieldNames[fieldIndex] = fieldName
            fieldType := rawTypes[fieldIndex]
            fieldTypes[fieldIndex] = fieldType
            fieldModifierFlags := packedFlags[fieldIndex]
            fieldStatics[fieldIndex] = ColumnarStructFieldFlagIsStatic(fieldModifierFlags)
            fieldReadonlyFlags[fieldIndex] = ColumnarStructFieldFlagIsReadonly(fieldModifierFlags)
            fieldInitKinds[fieldIndex] = rawInitKinds[fieldIndex]
            if rawInitKinds[fieldIndex] >= 0 {
                fieldInitText := rawInitTexts[fieldIndex]
                fieldInitTexts[fieldIndex] = fieldInitText
            } else {
                fieldInitTexts[fieldIndex] = ""
            }
            fieldPrivateFlags[fieldIndex] = ColumnarStructFieldFlagIsPrivate(fieldModifierFlags)
            fieldThreadStaticFlags[fieldIndex] = ColumnarStructFieldFlagIsThreadStatic(fieldModifierFlags)
            fieldIndex = fieldIndex + 1
        }

        return new ColumnarStructFieldColumns(
            fieldNames,
            fieldTypes,
            fieldStatics,
            fieldReadonlyFlags,
            fieldPrivateFlags,
            fieldThreadStaticFlags,
            fieldInitKinds,
            fieldInitTexts
        )
    }
}
