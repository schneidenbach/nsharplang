namespace NSharpLang.Compiler.Columnar

class ColumnarStructFieldColumns {
    FieldNames: string[]
    FieldTypeCanonicals: string[]
    FieldStaticFlags: bool[]
    FieldReadonlyFlags: bool[]
    FieldPrivateFlags: bool[]
    // The written accessibility words, in the `Modifiers` bit space, one word per field. Zero means
    // none was written and the casing convention alone decides.
    FieldVisibilityFlags: int[]
    FieldThreadStaticFlags: bool[]
    FieldConstFlags: bool[]
    // Whether the row was written as `event Name: DelegateType` rather than as a field. The storage is
    // the same storage; what the bit adds is the pair of accessors and the `EventInfo` row beside it,
    // and private storage whatever the event's own visibility says.
    FieldEventFlags: bool[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]

    constructor(
        fieldNames: string[],
        fieldTypeCanonicals: string[],
        fieldStaticFlags: bool[],
        fieldReadonlyFlags: bool[],
        fieldPrivateFlags: bool[],
        fieldVisibilityFlags: int[],
        fieldThreadStaticFlags: bool[],
        fieldConstFlags: bool[],
        fieldEventFlags: bool[],
        fieldInitKinds: int[],
        fieldInitTexts: string[]
    ) {
        FieldNames = fieldNames
        FieldTypeCanonicals = fieldTypeCanonicals
        FieldStaticFlags = fieldStaticFlags
        FieldReadonlyFlags = fieldReadonlyFlags
        FieldPrivateFlags = fieldPrivateFlags
        FieldVisibilityFlags = fieldVisibilityFlags
        FieldThreadStaticFlags = fieldThreadStaticFlags
        FieldConstFlags = fieldConstFlags
        FieldEventFlags = fieldEventFlags
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
        fieldVisibilityFlags := new int[](count)
        fieldThreadStaticFlags := new bool[](count)
        fieldConstFlags := new bool[](count)
        fieldEventFlags := new bool[](count)

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
            fieldVisibilityFlags[fieldIndex] = ColumnarStructFieldVisibilityModifiers(fieldModifierFlags)
            fieldThreadStaticFlags[fieldIndex] = ColumnarStructFieldFlagIsThreadStatic(fieldModifierFlags)
            fieldConstFlags[fieldIndex] = ColumnarStructFieldFlagIsConst(fieldModifierFlags)
            fieldEventFlags[fieldIndex] = ColumnarStructFieldFlagIsEvent(fieldModifierFlags)
            fieldIndex = fieldIndex + 1
        }

        return new ColumnarStructFieldColumns(
            fieldNames,
            fieldTypes,
            fieldStatics,
            fieldReadonlyFlags,
            fieldPrivateFlags,
            fieldVisibilityFlags,
            fieldThreadStaticFlags,
            fieldConstFlags,
            fieldEventFlags,
            fieldInitKinds,
            fieldInitTexts
        )
    }
}
