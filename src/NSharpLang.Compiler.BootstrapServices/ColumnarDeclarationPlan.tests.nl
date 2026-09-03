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

// A one-node body table: the method rows this slice plans never look inside a body, so the smallest
// well-formed table is the honest fixture.
func DeclarationPlanEmptyBody(): ColumnarNodeTable {
    zero := new int[](1)
    return new ColumnarNodeTable(zero, zero, zero, zero, zero, new int[](0), zero, zero)
}

func DeclarationPlanMethodInput(name: string, returnCanonical: string, isStatic: bool): ColumnarFunctionInput {
    return new ColumnarFunctionInput(
        name,
        returnCanonical,
        new string[](0),
        new string[](0),
        DeclarationPlanEmptyBody(),
        0,
        isStatic
    )
}

func DeclarationPlanMethodStruct(name: string, methods: List<ColumnarFunctionInput>): ColumnarStructInput {
    return new ColumnarStructInput(
        name,
        new string[](0),
        new string[](0),
        methods,
        new List<ColumnarConstructorInput>(),
        new List<ColumnarPropertyInput>(),
        true
    )
}

test "the method rows publish every base MethodAttributes word, and a free function is NOT a static method" {
    assert ColumnarDeclarationPlanner.StaticMethodAttribute() == 16
    assert ColumnarDeclarationPlanner.VirtualMethodAttribute() == 64
    assert ColumnarDeclarationPlanner.HideBySigMethodAttribute() == 128
    assert ColumnarDeclarationPlanner.NewSlotMethodAttribute() == 256
    assert ColumnarDeclarationPlanner.AbstractMethodAttribute() == 1024
    assert ColumnarDeclarationPlanner.SpecialNameMethodAttribute() == 2048

    // Public|Static|HideBySig, and +SpecialName for an operator.
    assert ColumnarDeclarationPlanner.StaticMethodAttributes(false) == 150
    assert ColumnarDeclarationPlanner.StaticMethodAttributes(true) == 2198
    // Public|HideBySig, before any implementing-interface widening the host still applies.
    assert ColumnarDeclarationPlanner.InstanceMethodAttributes() == 134
    // Public|Virtual|HideBySig|NewSlot, +Abstract when the interface supplies no default body.
    assert ColumnarDeclarationPlanner.InterfaceMethodAttributes(true) == 454
    assert ColumnarDeclarationPlanner.InterfaceMethodAttributes(false) == 1478

    // A FREE FUNCTION carries NO HideBySig: free functions do not overload, so there is no signature
    // to hide by. This is the one word that is NOT the static-method word, and confusing them would
    // change metadata on every free function in the estate.
    assert ColumnarDeclarationPlanner.FreeFunctionAttributes() == 22
    assert ColumnarDeclarationPlanner.FreeFunctionAttributes() != ColumnarDeclarationPlanner.StaticMethodAttributes(false)
}

test "the operator rule is a name prefix that decides metadata, and it is ordinal and case-sensitive" {
    assert ColumnarDeclarationPlanner.IsOperatorMethodName("op_Addition")
    assert ColumnarDeclarationPlanner.IsOperatorMethodName("op_")
    assert !ColumnarDeclarationPlanner.IsOperatorMethodName("Op_Addition")
    assert !ColumnarDeclarationPlanner.IsOperatorMethodName("operator")
    assert !ColumnarDeclarationPlanner.IsOperatorMethodName("Add")
    assert !ColumnarDeclarationPlanner.IsOperatorMethodName(null)
}

test "this occupies argument zero, so an instance method's parameter ordinals shift by one" {
    assert ColumnarDeclarationPlanner.ParameterOrdinalShift(true) == 1
    assert ColumnarDeclarationPlanner.ParameterOrdinalShift(false) == 0
    assert ColumnarDeclarationPlanner.ParameterOrdinalFor(0, true) == 1
    assert ColumnarDeclarationPlanner.ParameterOrdinalFor(2, true) == 3
    assert ColumnarDeclarationPlanner.ParameterOrdinalFor(0, false) == 0
    assert ColumnarDeclarationPlanner.ParameterOrdinalFor(2, false) == 2

    assert ColumnarDeclarationPlanner.IsVoidReturnCanonical("void")
    assert !ColumnarDeclarationPlanner.IsVoidReturnCanonical("Void")
    assert !ColumnarDeclarationPlanner.IsVoidReturnCanonical("int")
}

test "the method rows carry a word per struct method, per interface member and per free function" {
    methods := new List<ColumnarFunctionInput>()
    methods.Add(DeclarationPlanMethodInput("Area", "int", false))
    methods.Add(DeclarationPlanMethodInput("Make", "int", true))
    methods.Add(DeclarationPlanMethodInput("op_Addition", "int", true))
    methods.Add(DeclarationPlanMethodInput("Reset", "void", false))

    structs := new List<ColumnarStructInput>()
    structs.Add(DeclarationPlanMethodStruct("Shape", methods))
    interfaces := new List<ColumnarInterfaceInput>()
    interfaces.Add(DeclarationPlanInterfaceInput("Greeter"))

    program := DeclarationPlanTypeDefProgram("namespace Demo\n", structs, interfaces)
    rows := ColumnarDeclarationPlanner.BuildMethods(program)

    assert rows.StructCount == 1
    assert rows.StructMethodAttributeWords[0][0] == 134
    assert rows.StructMethodAttributeWords[0][1] == 150
    // The operator is static AND SpecialName, decided from its name alone.
    assert rows.StructMethodAttributeWords[0][2] == 2198
    assert !rows.StructMethodIsVoidReturn[0][0]
    assert rows.StructMethodIsVoidReturn[0][3]

    // The probe interface declares no members, so its row is an empty word list, not a missing one.
    assert rows.InterfaceCount == 1
    assert rows.InterfaceMethodAttributeWords[0].Length == 0
    assert rows.FunctionCount == 0
}

// TWO RETURNS RATHER THAN A NULLABLE LOCAL. `setter := (ColumnarFunctionInput?)null` declines at
// `emit.local.initializer` -- a cast-of-null local initializer is off the columnar surface -- while
// `null` in an ARGUMENT position for a nullable parameter is fine. Measured, not guessed: the estate
// refused the first spelling.
func DeclarationPlanPropertyInput(name: string, isStatic: bool, withSetter: bool): ColumnarPropertyInput {
    if withSetter {
        return new ColumnarPropertyInput(
            name,
            "int",
            DeclarationPlanMethodInput("get_" + name, "int", isStatic),
            DeclarationPlanMethodInput("set_" + name, "void", isStatic),
            isStatic
        )
    }

    return new ColumnarPropertyInput(
        name,
        "int",
        DeclarationPlanMethodInput("get_" + name, "int", isStatic),
        null,
        isStatic
    )
}

func DeclarationPlanPropertyStruct(name: string, properties: List<ColumnarPropertyInput>): ColumnarStructInput {
    return new ColumnarStructInput(
        name,
        new string[](0),
        new string[](0),
        new List<ColumnarFunctionInput>(),
        new List<ColumnarConstructorInput>(),
        properties,
        true
    )
}

test "the accessor words carry SpecialName, and 2198 is an agreement of flags rather than a shared rule" {
    // Public|Static|HideBySig|SpecialName, and the instance word drops Static.
    assert ColumnarDeclarationPlanner.StaticAccessorAttributes() == 2198
    assert ColumnarDeclarationPlanner.InstanceAccessorAttributes() == 2182
    // SpecialName is the whole difference from an ordinary method word: it is what marks the method
    // as an accessor rather than a method that happens to be called `get_X`.
    assert ColumnarDeclarationPlanner.StaticAccessorAttributes() - ColumnarDeclarationPlanner.SpecialNameMethodAttribute() == ColumnarDeclarationPlanner.StaticMethodAttributes(false)
    assert ColumnarDeclarationPlanner.InstanceAccessorAttributes() - ColumnarDeclarationPlanner.SpecialNameMethodAttribute() == ColumnarDeclarationPlanner.InstanceMethodAttributes()
}

test "a property is a name plus two accessor names, and the setter's value is parameter zero" {
    assert ColumnarDeclarationPlanner.PropertyGetterName("Count") == "get_Count"
    assert ColumnarDeclarationPlanner.PropertySetterName("Count") == "set_Count"

    // A setter's `value` IS parameter zero, so its ordinal is the ordinary parameter rule: 0 on a
    // static accessor, 1 on an instance one where `this` takes argument zero. The identity with the
    // method family's rule is asserted so the two can never drift apart.
    assert ColumnarDeclarationPlanner.PropertyValueOrdinal(true) == 0
    assert ColumnarDeclarationPlanner.PropertyValueOrdinal(false) == 1
    assert ColumnarDeclarationPlanner.PropertyValueOrdinal(true) == ColumnarDeclarationPlanner.ParameterOrdinalFor(0, false)
    assert ColumnarDeclarationPlanner.PropertyValueOrdinal(false) == ColumnarDeclarationPlanner.ParameterOrdinalFor(0, true)
}

test "the property rows carry a word, both accessor names and the value ordinal for every property" {
    properties := new List<ColumnarPropertyInput>()
    properties.Add(DeclarationPlanPropertyInput("Total", true, false))
    properties.Add(DeclarationPlanPropertyInput("Count", false, true))

    structs := new List<ColumnarStructInput>()
    structs.Add(DeclarationPlanPropertyStruct("Basket", properties))
    program := DeclarationPlanTypeDefProgram("namespace Demo\n", structs, new List<ColumnarInterfaceInput>())
    rows := ColumnarDeclarationPlanner.BuildProperties(program)

    assert rows.StructCount == 1
    assert rows.AccessorWords[0][0] == 2198
    assert rows.AccessorWords[0][1] == 2182
    assert rows.GetterNames[0][0] == "get_Total"
    assert rows.GetterNames[0][1] == "get_Count"
    // THE SETTER NAME IS PLANNED EVEN WHEN THERE IS NO SETTER; `HasSetter` is what the executor
    // branches on, so a get-only property carries a usable name rather than a null the host must guard.
    assert rows.SetterNames[0][0] == "set_Total"
    assert !rows.HasSetter[0][0]
    assert rows.HasSetter[0][1]
    assert rows.ValueOrdinals[0][0] == 0
    assert rows.ValueOrdinals[0][1] == 1
}
