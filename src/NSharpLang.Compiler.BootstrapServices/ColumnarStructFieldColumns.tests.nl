namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

test "struct field columns copy every row and decode all four metadata bits" {
    rawNames := new string[](3)
    rawNames[0] = "first"
    rawNames[1] = "second"
    rawNames[2] = "third"
    rawTypes := new string[](3)
    rawTypes[0] = "int"
    rawTypes[1] = "string"
    rawTypes[2] = "bool"
    packedFlags := new int[](3)
    packedFlags[0] = 0
    packedFlags[1] = 7
    packedFlags[2] = 9
    rawInitKinds := new int[](3)
    rawInitKinds[0] = 4
    rawInitKinds[1] = -1
    rawInitKinds[2] = 2
    rawInitTexts := new string[](3)
    rawInitTexts[0] = "11"
    rawInitTexts[1] = "must not survive"
    rawInitTexts[2] = "true"

    columns := ColumnarStructFieldColumns.Build(
        rawNames,
        rawTypes,
        packedFlags,
        rawInitKinds,
        rawInitTexts,
        3
    )

    assert columns.FieldNames.Length == 3
    assert columns.FieldNames[0] == "first"
    assert columns.FieldNames[1] == "second"
    assert columns.FieldNames[2] == "third"
    assert columns.FieldTypeCanonicals[0] == "int"
    assert columns.FieldTypeCanonicals[1] == "string"
    assert columns.FieldTypeCanonicals[2] == "bool"

    assert !columns.FieldStaticFlags[0]
    assert columns.FieldStaticFlags[1]
    assert columns.FieldStaticFlags[2]
    assert !columns.FieldReadonlyFlags[0]
    assert columns.FieldReadonlyFlags[1]
    assert !columns.FieldReadonlyFlags[2]
    assert !columns.FieldPrivateFlags[0]
    assert columns.FieldPrivateFlags[1]
    assert !columns.FieldPrivateFlags[2]
    assert !columns.FieldThreadStaticFlags[0]
    assert !columns.FieldThreadStaticFlags[1]
    assert columns.FieldThreadStaticFlags[2]

    assert columns.FieldInitKinds[0] == 4
    assert columns.FieldInitKinds[1] == -1
    assert columns.FieldInitKinds[2] == 2
    assert columns.FieldInitTexts[0] == "11"
    assert columns.FieldInitTexts[1] == ""
    assert columns.FieldInitTexts[2] == "true"

    rawNames[0] = "changed"
    rawTypes[0] = "changed"
    rawInitKinds[0] = -1
    rawInitTexts[0] = "changed"
    assert columns.FieldNames[0] == "first"
    assert columns.FieldTypeCanonicals[0] == "int"
    assert columns.FieldInitKinds[0] == 4
    assert columns.FieldInitTexts[0] == "11"
}

test "struct input defaults new field metadata columns and retains supplied arrays" {
    fieldNames := new string[](2)
    fieldNames[0] = "left"
    fieldNames[1] = "right"
    fieldTypes := new string[](2)
    fieldTypes[0] = "int"
    fieldTypes[1] = "string"
    methods := new List<ColumnarFunctionInput>()
    constructors := new List<ColumnarConstructorInput>()
    properties := new List<ColumnarPropertyInput>()

    defaulted := new ColumnarStructInput(
        "Defaulted",
        fieldNames,
        fieldTypes,
        methods,
        constructors,
        properties,
        true
    )
    assert defaulted.FieldPrivateFlags.Length == 2
    assert !defaulted.FieldPrivateFlags[0]
    assert !defaulted.FieldPrivateFlags[1]
    assert defaulted.FieldThreadStaticFlags.Length == 2
    assert !defaulted.FieldThreadStaticFlags[0]
    assert !defaulted.FieldThreadStaticFlags[1]

    privateFlags := new bool[](2)
    privateFlags[1] = true
    threadStaticFlags := new bool[](2)
    threadStaticFlags[0] = true
    supplied := new ColumnarStructInput(
        "Supplied",
        fieldNames,
        fieldTypes,
        methods,
        constructors,
        properties,
        true,
        null,
        null,
        null,
        null,
        false,
        null,
        null,
        0,
        false,
        false,
        null,
        0,
        null,
        null,
        privateFlags,
        threadStaticFlags
    )
    assert Object.ReferenceEquals(supplied.FieldPrivateFlags, privateFlags)
    assert Object.ReferenceEquals(supplied.FieldThreadStaticFlags, threadStaticFlags)
}
