namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

func DeclarationPlanEmptyProgramInput(source: string, enums: IReadOnlyList<ColumnarEnumInput>): ColumnarProgramInput {
    // Every argument is spelled: omitting a defaulted parameter of a STATIC method declines emission
    // (§2.1), and only a constructor's trailing default may be left off.
    return ColumnarProgramInput.CreateSingleSource(
        source,
        new List<ColumnarFunctionInput>(),
        enums,
        new List<ColumnarStructInput>(),
        new List<ColumnarUnionInput>(),
        new List<ColumnarInterfaceInput>(),
        null
    )
}

func DeclarationPlanIntEnum(name: string): ColumnarEnumInput {
    memberNames := new string[](2)
    memberNames[0] = "Red"
    memberNames[1] = "Green"
    memberValues := new int[](2)
    memberValues[0] = 0
    memberValues[1] = 7
    return new ColumnarEnumInput(name, memberNames, memberValues, false, null, 0)
}

func DeclarationPlanStringEnum(name: string): ColumnarEnumInput {
    memberNames := new string[](2)
    memberNames[0] = "Small"
    memberNames[1] = "Large"
    memberValues := new int[](2)
    memberValues[0] = 0
    memberValues[1] = 1
    // ONE spelled value and one unspelled, so the fallback rule is exercised rather than described.
    stringValues := new string[](1)
    stringValues[0] = "sm"
    return new ColumnarEnumInput(name, memberNames, memberValues, true, stringValues, 0)
}

test "the declaration planner publishes the CLR attribute words the enum pass used to compose inline" {
    // TypeAttributes.Public|Abstract|Sealed == 1|128|256 == 385, the word a string-backed enum needs
    // because the CLR has no string-underlying enum; DefineEnum composes the rest itself and takes
    // only the visibility.
    assert ColumnarDeclarationPlanner.StringBackedEnumTypeAttributes() == 385
    assert ColumnarDeclarationPlanner.IntBackedEnumTypeAttributes() == 1
    assert ColumnarDeclarationPlanner.PublicTypeAttribute() == 1
    assert ColumnarDeclarationPlanner.AbstractTypeAttribute() == 128
    assert ColumnarDeclarationPlanner.SealedTypeAttribute() == 256
}

test "a string-backed enum member with no spelled value takes its own name" {
    input := DeclarationPlanStringEnum("Size")
    assert ColumnarDeclarationPlanner.EnumMemberStringValueAt(input, 0) == "sm"
    assert ColumnarDeclarationPlanner.EnumMemberStringValueAt(input, 1) == "Large"
}

test "the declaration plan resolves the exact enum name through the file namespace" {
    enums := new List<ColumnarEnumInput>()
    enums.Add(DeclarationPlanIntEnum("Color"))
    program := DeclarationPlanEmptyProgramInput("namespace Demo\n", enums)
    plan := ColumnarDeclarationPlanner.BuildAssemblyAndEnums(program, "Widgets")

    assert plan.AssemblyName == "Widgets"
    assert plan.ModuleName == "Widgets"
    assert plan.EnumCount == 1
    assert plan.EnumExactNames[0] == "Demo.Color"
    assert !plan.EnumIsStringBacked[0]
    assert plan.EnumTypeAttributes[0] == 1
    assert plan.EnumMemberNames[0].Length == 2
    assert plan.EnumMemberNames[0][1] == "Green"
    assert plan.EnumMemberValues[0][1] == 7
}

test "the declaration plan selects the string-backed attribute word and materialises every member value" {
    enums := new List<ColumnarEnumInput>()
    enums.Add(DeclarationPlanStringEnum("Size"))
    program := DeclarationPlanEmptyProgramInput("namespace Demo\n", enums)
    plan := ColumnarDeclarationPlanner.BuildAssemblyAndEnums(program, "Widgets")

    assert plan.EnumIsStringBacked[0]
    assert plan.EnumTypeAttributes[0] == 385
    // The row carries a value for EVERY member, fallback already applied: the executor never re-derives it.
    assert plan.EnumMemberStringValues[0].Length == 2
    assert plan.EnumMemberStringValues[0][0] == "sm"
    assert plan.EnumMemberStringValues[0][1] == "Large"
}

test "an unnamespaced file leaves the enum name unqualified, and a program with no enums plans no rows" {
    enums := new List<ColumnarEnumInput>()
    enums.Add(DeclarationPlanIntEnum("Color"))
    bare := ColumnarDeclarationPlanner.BuildAssemblyAndEnums(
        DeclarationPlanEmptyProgramInput("func main() {\n}\n", enums),
        "Widgets"
    )
    assert bare.EnumExactNames[0] == "Color"

    empty := ColumnarDeclarationPlanner.BuildAssemblyAndEnums(
        DeclarationPlanEmptyProgramInput("namespace Demo\n", new List<ColumnarEnumInput>()),
        "Widgets"
    )
    assert empty.EnumCount == 0
    assert empty.EnumExactNames.Length == 0
}

test "the declaration planner refuses a null program before it allocates a row" {
    assert throws InvalidOperationException {
        ColumnarDeclarationPlanner.BuildAssemblyAndEnums(null, "Widgets")
    }
}

func DeclarationPlanTypeDefProgram(
    source: string,
    structs: IReadOnlyList<ColumnarStructInput>,
    interfaces: IReadOnlyList<ColumnarInterfaceInput>
): ColumnarProgramInput {
    return ColumnarProgramInput.CreateSingleSource(
        source,
        new List<ColumnarFunctionInput>(),
        new List<ColumnarEnumInput>(),
        structs,
        new List<ColumnarUnionInput>(),
        interfaces,
        null
    )
}

func DeclarationPlanStructInput(name: string, isReference: bool): ColumnarStructInput {
    return new ColumnarStructInput(
        name,
        new string[](0),
        new string[](0),
        new List<ColumnarFunctionInput>(),
        new List<ColumnarConstructorInput>(),
        new List<ColumnarPropertyInput>(),
        isReference
    )
}

func DeclarationPlanInterfaceInput(name: string): ColumnarInterfaceInput {
    return new ColumnarInterfaceInput(
        name,
        new string[](0),
        new string[](0),
        new string[](0),
        new string[][](0),
        new string[][](0)
    )
}

test "the typedef rows publish the interface word and BOTH halves of the nested-visibility asymmetry" {
    // Public|Interface|Abstract == 1|32|128 == 161.
    assert ColumnarDeclarationPlanner.InterfaceTypeAttribute() == 32
    assert ColumnarDeclarationPlanner.InterfaceTypeAttributes() == 161

    // A TOP-LEVEL type ORs Public; a NESTED one ORs its own visibility word INSTEAD, never both.
    // Folding the two would flip the visibility of every nested type in the estate, so all four
    // combinations are pinned rather than described.
    assert ColumnarDeclarationPlanner.StructTypeAttributesFor(true, false, 0) == 1
    assert ColumnarDeclarationPlanner.StructTypeAttributesFor(false, false, 0) == 257
    assert ColumnarDeclarationPlanner.StructTypeAttributesFor(true, true, 2) == 2
    assert ColumnarDeclarationPlanner.StructTypeAttributesFor(false, true, 2) == 258
    // And a nested type never acquires Public by accident, whatever its visibility word.
    assert ColumnarDeclarationPlanner.StructTypeAttributesFor(true, true, 4) == 4
}

test "the typedef rows resolve every declared type name and select its attribute word" {
    structs := new List<ColumnarStructInput>()
    structs.Add(DeclarationPlanStructInput("Product", true))
    structs.Add(DeclarationPlanStructInput("Point", false))
    interfaces := new List<ColumnarInterfaceInput>()
    interfaces.Add(DeclarationPlanInterfaceInput("Greeter"))

    program := DeclarationPlanTypeDefProgram("namespace Demo\n", structs, interfaces)
    rows := ColumnarDeclarationPlanner.BuildTypeDefs(program)

    assert rows.InterfaceCount == 1
    assert rows.InterfaceExactNames[0] == "Demo.Greeter"
    assert rows.InterfaceTypeAttributes[0] == 161

    assert rows.StructCount == 2
    assert rows.StructExactNames[0] == "Demo.Product"
    assert rows.StructTypeAttributes[0] == 1
    assert rows.StructExactNames[1] == "Demo.Point"
    assert rows.StructTypeAttributes[1] == 257
    // A top-level type carries the EMPTY enclosing name, which is what the executor branches on.
    assert rows.StructEnclosingExactNames[0].Length == 0
    assert rows.StructEnclosingExactNames[1].Length == 0
}

test "the declaration plan carries its typedef table" {
    structs := new List<ColumnarStructInput>()
    structs.Add(DeclarationPlanStructInput("Product", true))
    program := DeclarationPlanTypeDefProgram("namespace Demo\n", structs, new List<ColumnarInterfaceInput>())
    plan := ColumnarDeclarationPlanner.BuildAssemblyAndEnums(program, "Widgets")

    assert plan.TypeDefs.StructCount == 1
    assert plan.TypeDefs.StructExactNames[0] == "Demo.Product"
    assert plan.TypeDefs.InterfaceCount == 0
}

// A struct whose READONLY-FLAGS array is deliberately SHORTER than its field list -- the shape the
// bounds guard exists for, and one the emitter accepts today.
func DeclarationPlanFieldStruct(
    name: string,
    fieldNames: string[],
    fieldCanonicals: string[],
    staticFlags: bool[],
    readonlyFlags: bool[]
): ColumnarStructInput {
    return new ColumnarStructInput(
        name,
        fieldNames,
        fieldCanonicals,
        new List<ColumnarFunctionInput>(),
        new List<ColumnarConstructorInput>(),
        new List<ColumnarPropertyInput>(),
        true,
        null,
        staticFlags,
        null,
        null,
        false,
        null,
        readonlyFlags
    )
}

test "the field rows publish all four FieldAttributes words" {
    assert ColumnarDeclarationPlanner.PublicFieldAttribute() == 6
    assert ColumnarDeclarationPlanner.StaticFieldAttribute() == 16
    assert ColumnarDeclarationPlanner.InitOnlyFieldAttribute() == 32

    assert ColumnarDeclarationPlanner.FieldAttributesFor(false, false) == 6
    assert ColumnarDeclarationPlanner.FieldAttributesFor(false, true) == 38
    assert ColumnarDeclarationPlanner.FieldAttributesFor(true, false) == 22
    assert ColumnarDeclarationPlanner.FieldAttributesFor(true, true) == 54
}

test "the readonly flag is bounds-guarded and a field past the flags array is simply not readonly" {
    names := new string[](3)
    names[0] = "First"
    names[1] = "Second"
    names[2] = "Third"
    canonicals := new string[](3)
    canonicals[0] = "int"
    canonicals[1] = "string?"
    canonicals[2] = "int"
    statics := new bool[](3)
    statics[2] = true
    // TWO flags for THREE fields: reading index 2 unguarded would throw on a shape the emitter accepts.
    readonlys := new bool[](2)
    readonlys[1] = true
    input := DeclarationPlanFieldStruct("Box", names, canonicals, statics, readonlys)

    assert !ColumnarDeclarationPlanner.FieldIsReadonlyAt(input, 0)
    assert ColumnarDeclarationPlanner.FieldIsReadonlyAt(input, 1)
    assert !ColumnarDeclarationPlanner.FieldIsReadonlyAt(input, 2)

    // A NULLABLE field is one whose CANONICAL text ends in `?`.
    assert !ColumnarDeclarationPlanner.FieldIsNullableAt(input, 0)
    assert ColumnarDeclarationPlanner.FieldIsNullableAt(input, 1)
    assert !ColumnarDeclarationPlanner.FieldIsNullableAt(input, 2)
}

test "the field rows carry a word, a static flag and a nullable flag for every field of every struct" {
    names := new string[](3)
    names[0] = "First"
    names[1] = "Second"
    names[2] = "Third"
    canonicals := new string[](3)
    canonicals[0] = "int"
    canonicals[1] = "string?"
    canonicals[2] = "int"
    statics := new bool[](3)
    statics[2] = true
    readonlys := new bool[](2)
    readonlys[1] = true

    structs := new List<ColumnarStructInput>()
    structs.Add(DeclarationPlanFieldStruct("Box", names, canonicals, statics, readonlys))
    program := DeclarationPlanTypeDefProgram("namespace Demo\n", structs, new List<ColumnarInterfaceInput>())
    rows := ColumnarDeclarationPlanner.BuildFields(program)

    assert rows.StructCount == 1
    assert rows.FieldNames[0].Length == 3
    assert rows.FieldNames[0][1] == "Second"
    // instance 6, readonly instance 38, static (past the flags array, so not readonly) 22.
    assert rows.FieldAttributeWords[0][0] == 6
    assert rows.FieldAttributeWords[0][1] == 38
    assert rows.FieldAttributeWords[0][2] == 22
    assert !rows.FieldIsStatic[0][0]
    assert rows.FieldIsStatic[0][2]
    assert !rows.FieldIsNullable[0][0]
    assert rows.FieldIsNullable[0][1]
}
