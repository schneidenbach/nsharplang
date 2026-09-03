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
