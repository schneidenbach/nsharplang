namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// These controls cover the record driver’s mutable declaration-row decisions.  The existing
// record-value-member facts own the ordinary all-three-body path, generic skip, every keyed pool
// row, and runtime-companion corruption.  Here each fixture changes one live row fact that the
// outer driver—not an individual plan builder—must observe.
func RecordSynthesisControlsInput(name: string, isReference: bool): ColumnarStructInput {
    fieldNames := new string[](1)
    fieldNames[0] = "Value"
    fieldTypes := new string[](1)
    fieldTypes[0] = "int"
    return new ColumnarStructInput(
        name,
        fieldNames,
        fieldTypes,
        new List<ColumnarFunctionInput>(),
        new List<ColumnarConstructorInput>(),
        new List<ColumnarPropertyInput>(),
        isReference,
        null,
        null,
        null,
        null,
        true
    )
}

func RecordSynthesisControlsDefinition(name: string, isReference: bool): ColumnarStructDef {
    definition := SynthesizedRecordCallDefinition(name, isReference)
    value := ConstructionDefinePublicField(definition.Builder, "Value", typeof(int))
    definition.Fields["Value"] = value
    fieldNames := new string[](1)
    fieldNames[0] = "Value"
    definition.SetFieldOrder(fieldNames)
    return definition
}

func RecordSynthesisControlsSingleInput(input: ColumnarStructInput): IReadOnlyList<ColumnarStructInput> {
    inputs := new List<ColumnarStructInput>()
    inputs.Add(input)
    return inputs
}

func RecordSynthesisControlsPairInputs(first: ColumnarStructInput, second: ColumnarStructInput): IReadOnlyList<ColumnarStructInput> {
    inputs := new List<ColumnarStructInput>()
    inputs.Add(first)
    inputs.Add(second)
    return inputs
}

func RecordSynthesisControlsFourInputs(first: ColumnarStructInput, second: ColumnarStructInput, third: ColumnarStructInput, fourth: ColumnarStructInput): IReadOnlyList<ColumnarStructInput> {
    inputs := new List<ColumnarStructInput>()
    inputs.Add(first)
    inputs.Add(second)
    inputs.Add(third)
    inputs.Add(fourth)
    return inputs
}

func RecordSynthesisControlsSingleDefinition(definition: ColumnarStructDef): ColumnarStructDef[] {
    definitions := new ColumnarStructDef[](1)
    definitions[0] = definition
    return definitions
}

func RecordSynthesisControlsPairDefinitions(first: ColumnarStructDef, second: ColumnarStructDef): ColumnarStructDef[] {
    definitions := new ColumnarStructDef[](2)
    definitions[0] = first
    definitions[1] = second
    return definitions
}

func RecordSynthesisControlsFourDefinitions(first: ColumnarStructDef, second: ColumnarStructDef, third: ColumnarStructDef, fourth: ColumnarStructDef): ColumnarStructDef[] {
    definitions := new ColumnarStructDef[](4)
    definitions[0] = first
    definitions[1] = second
    definitions[2] = third
    definitions[3] = fourth
    return definitions
}

func RecordSynthesisControlsRegister(table: ColumnarStructuralTypeReferenceTable, definition: ColumnarStructDef) {
    runtimeType: Type = definition.Builder
    table.RegisterSourceDefinition(definition.DeclaredTypeName, runtimeType, false)
}

func RecordSynthesisControlsUserMember(definition: ColumnarStructDef, name: string, parameterTypes: Type[], returnType: Type): ColumnarInstanceMethodDef {
    return SourceCallDefineInstance(
        definition,
        name,
        parameterTypes,
        new int[](0),
        returnType,
        (MethodAttributes)198
    )
}

func RecordSynthesisControlsPreexistingClone(definition: ColumnarStructDef): MethodBuilder {
    recordType: Type = definition.Builder
    existing := SourceCallDefineInstance(
        definition,
        "<Clone>$",
        System.Type.EmptyTypes,
        new int[](0),
        recordType,
        (MethodAttributes)134
    )
    definition.RecordClone = existing.Builder
    return existing.Builder
}

func RecordSynthesisControlsRequiredConstructor(owner: Type): ConstructorInfo {
    constructor := owner.GetConstructor(System.Type.EmptyTypes)
    if constructor == null {
        throw new InvalidOperationException("The synthesized record test fixture has no default constructor.")
    }
    return constructor
}

func RecordSynthesisControlsRequiredMethod(owner: Type, name: string, parameterTypes: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameterTypes)
    if method == null {
        throw new InvalidOperationException("The synthesized record test fixture is missing '" + name + "'.")
    }
    return method
}

func RecordSynthesisControlsNewInstance(owner: Type): object {
    result := RecordSynthesisControlsRequiredConstructor(owner).Invoke(new object[](0))
    if result == null {
        throw new InvalidOperationException("The synthesized record constructor returned null.")
    }
    return result
}

func RecordSynthesisControlsOneObject(): Type[] {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(object)
    return parameterTypes
}

// A user can independently own either virtual slot.  The driver must only synthesize the other
// value member and the reference-only clone, while an already-published clone remains exactly the
// one the declaration row supplied.  The value record is the paired control: it gets value members
// but never a clone wrapper.
test "record synthesis independently preserves partial user members and an existing clone" {
    onlyEquals := RecordSynthesisControlsDefinition("RecordControlsOnlyEquals", true)
    onlyEqualsMember := RecordSynthesisControlsUserMember(
        onlyEquals,
        "Equals",
        RecordSynthesisControlsOneObject(),
        typeof(bool)
    )

    onlyHash := RecordSynthesisControlsDefinition("RecordControlsOnlyHash", true)
    onlyHashMember := RecordSynthesisControlsUserMember(
        onlyHash,
        "GetHashCode",
        System.Type.EmptyTypes,
        typeof(int)
    )

    existingClone := RecordSynthesisControlsDefinition("RecordControlsExistingClone", true)
    expectedClone := RecordSynthesisControlsPreexistingClone(existingClone)

    valueRecord := RecordSynthesisControlsDefinition("RecordControlsValue", false)

    table := new ColumnarStructuralTypeReferenceTable()
    RecordSynthesisControlsRegister(table, onlyEquals)
    RecordSynthesisControlsRegister(table, onlyHash)
    RecordSynthesisControlsRegister(table, existingClone)
    RecordSynthesisControlsRegister(table, valueRecord)
    ColumnarRecordValueMemberPlanner.EmitRecordValueMembers(
        RecordSynthesisControlsFourInputs(
            RecordSynthesisControlsInput(onlyEquals.DeclaredTypeName, true),
            RecordSynthesisControlsInput(onlyHash.DeclaredTypeName, true),
            RecordSynthesisControlsInput(existingClone.DeclaredTypeName, true),
            RecordSynthesisControlsInput(valueRecord.DeclaredTypeName, false)
        ),
        RecordSynthesisControlsFourDefinitions(onlyEquals, onlyHash, existingClone, valueRecord),
        table
    )

    assert ColumnarConstructionPlanner.SameObject(onlyEquals.Methods["Equals"].Builder, onlyEqualsMember.Builder)
    assert onlyEquals.RecordEquals == null
    assert onlyEquals.RecordGetHashCode != null
    assert onlyEquals.RecordClone != null

    assert ColumnarConstructionPlanner.SameObject(onlyHash.Methods["GetHashCode"].Builder, onlyHashMember.Builder)
    assert onlyHash.RecordEquals != null
    assert onlyHash.RecordGetHashCode == null
    assert onlyHash.RecordClone != null

    assert existingClone.RecordEquals != null
    assert existingClone.RecordGetHashCode != null
    assert ColumnarConstructionPlanner.SameObject(existingClone.RecordClone, expectedClone)

    assert valueRecord.RecordEquals != null
    assert valueRecord.RecordGetHashCode != null
    assert valueRecord.RecordClone == null
}

// The first row must finish all three bodies before the second malformed row reaches the old
// GetHashCode slot guard.  The clean twin is deliberately separate so a prior consumed plan or
// half-defined builder cannot masquerade as successful outer-loop completion.
test "record synthesis retains an earlier completed record when a later stale hash slot rejects" {
    first := RecordSynthesisControlsDefinition("RecordControlsEarlier", true)
    later := RecordSynthesisControlsDefinition("RecordControlsLaterMalformed", true)
    later.MethodOverloads["GetHashCode"] = new List<ColumnarInstanceMethodDef>()

    table := new ColumnarStructuralTypeReferenceTable()
    RecordSynthesisControlsRegister(table, first)
    RecordSynthesisControlsRegister(table, later)
    assert throws InvalidOperationException {
        ColumnarRecordValueMemberPlanner.EmitRecordValueMembers(
            RecordSynthesisControlsPairInputs(
                RecordSynthesisControlsInput(first.DeclaredTypeName, true),
                RecordSynthesisControlsInput(later.DeclaredTypeName, true)
            ),
            RecordSynthesisControlsPairDefinitions(first, later),
            table
        )
    }

    assert first.RecordEquals != null
    assert first.RecordGetHashCode != null
    assert first.RecordClone != null
    assert later.RecordEquals != null
    assert later.RecordGetHashCode == null
    assert later.RecordClone == null

    // Equals was defined before the later hash-slot guard, but that handle alone would not prove
    // its body reached execution. Bake and invoke it after the caught failure.
    laterRuntime := IdentityBake(later.Builder)
    laterValue := RecordSynthesisControlsNewInstance(laterRuntime)
    sameLaterValue := RecordSynthesisControlsNewInstance(laterRuntime)
    laterEquals := RecordSynthesisControlsRequiredMethod(laterRuntime, "Equals", RecordSynthesisControlsOneObject())
    laterEqualsArguments := new object[](1)
    ExecutorSetObject(laterEqualsArguments, 0, sameLaterValue)
    assert Convert.ToBoolean(laterEquals.Invoke(laterValue, laterEqualsArguments))

    firstRuntime := IdentityBake(first.Builder)
    firstValue := RecordSynthesisControlsNewInstance(firstRuntime)
    sameValue := RecordSynthesisControlsNewInstance(firstRuntime)
    equals := RecordSynthesisControlsRequiredMethod(firstRuntime, "Equals", RecordSynthesisControlsOneObject())
    equalsArguments := new object[](1)
    ExecutorSetObject(equalsArguments, 0, sameValue)
    assert Convert.ToBoolean(equals.Invoke(firstValue, equalsArguments))
    hash := RecordSynthesisControlsRequiredMethod(firstRuntime, "GetHashCode", System.Type.EmptyTypes)
    assert Convert.ToInt32(hash.Invoke(firstValue, new object[](0))) == 391
    clone := RecordSynthesisControlsRequiredMethod(firstRuntime, "<Clone>$", System.Type.EmptyTypes)
    cloneValue := clone.Invoke(firstValue, new object[](0))
    assert cloneValue != null
    assert !ColumnarConstructionPlanner.SameObject(cloneValue, firstValue)

    cleanFirst := RecordSynthesisControlsDefinition("RecordControlsCleanFirst", true)
    cleanLater := RecordSynthesisControlsDefinition("RecordControlsCleanLater", true)
    cleanTable := new ColumnarStructuralTypeReferenceTable()
    RecordSynthesisControlsRegister(cleanTable, cleanFirst)
    RecordSynthesisControlsRegister(cleanTable, cleanLater)
    ColumnarRecordValueMemberPlanner.EmitRecordValueMembers(
        RecordSynthesisControlsPairInputs(
            RecordSynthesisControlsInput(cleanFirst.DeclaredTypeName, true),
            RecordSynthesisControlsInput(cleanLater.DeclaredTypeName, true)
        ),
        RecordSynthesisControlsPairDefinitions(cleanFirst, cleanLater),
        cleanTable
    )
    assert cleanFirst.RecordEquals != null
    assert cleanFirst.RecordGetHashCode != null
    assert cleanFirst.RecordClone != null
    assert cleanLater.RecordEquals != null
    assert cleanLater.RecordGetHashCode != null
    assert cleanLater.RecordClone != null

    cleanLaterRuntime := IdentityBake(cleanLater.Builder)
    cleanLaterValue := RecordSynthesisControlsNewInstance(cleanLaterRuntime)
    sameCleanLaterValue := RecordSynthesisControlsNewInstance(cleanLaterRuntime)
    cleanLaterEquals := RecordSynthesisControlsRequiredMethod(cleanLaterRuntime, "Equals", RecordSynthesisControlsOneObject())
    cleanLaterEqualsArguments := new object[](1)
    ExecutorSetObject(cleanLaterEqualsArguments, 0, sameCleanLaterValue)
    assert Convert.ToBoolean(cleanLaterEquals.Invoke(cleanLaterValue, cleanLaterEqualsArguments))
    cleanLaterHash := RecordSynthesisControlsRequiredMethod(cleanLaterRuntime, "GetHashCode", System.Type.EmptyTypes)
    assert Convert.ToInt32(cleanLaterHash.Invoke(cleanLaterValue, new object[](0))) == 391
    cleanLaterClone := RecordSynthesisControlsRequiredMethod(cleanLaterRuntime, "<Clone>$", System.Type.EmptyTypes)
    cleanLaterCloneValue := cleanLaterClone.Invoke(cleanLaterValue, new object[](0))
    assert cleanLaterCloneValue != null
    assert !ColumnarConstructionPlanner.SameObject(cleanLaterCloneValue, cleanLaterValue)
}

// Source selection is intentionally late: definition of Equals claims the source method slot before
// the selected source companion is required for its plan.  Both a missing registration and one whose
// exact name points at a foreign builder must therefore stop before Hash/Clone, not silently recover
// a Type from another table entry.
test "record synthesis rejects missing and foreign source companions after Equals publication" {
    missing := RecordSynthesisControlsDefinition("RecordControlsMissingSource", true)
    missingTable := new ColumnarStructuralTypeReferenceTable()
    assert throws InvalidOperationException {
        ColumnarRecordValueMemberPlanner.EmitRecordValueMembers(
            RecordSynthesisControlsSingleInput(RecordSynthesisControlsInput(missing.DeclaredTypeName, true)),
            RecordSynthesisControlsSingleDefinition(missing),
            missingTable
        )
    }
    assert missing.RecordEquals != null
    assert missing.Methods.ContainsKey("Equals")
    assert missing.RecordGetHashCode == null
    assert missing.RecordClone == null

    foreign := RecordSynthesisControlsDefinition("RecordControlsForeignSource", true)
    foreignCompanion := SourceCallDefinition("RecordControlsForeignCompanion", true)
    foreignTable := new ColumnarStructuralTypeReferenceTable()
    foreignType: Type = foreignCompanion.Builder
    foreignTable.RegisterSourceDefinition(foreign.DeclaredTypeName, foreignType, false)
    assert throws InvalidOperationException {
        ColumnarRecordValueMemberPlanner.EmitRecordValueMembers(
            RecordSynthesisControlsSingleInput(RecordSynthesisControlsInput(foreign.DeclaredTypeName, true)),
            RecordSynthesisControlsSingleDefinition(foreign),
            foreignTable
        )
    }
    assert foreign.RecordEquals != null
    assert foreign.Methods.ContainsKey("Equals")
    assert foreign.RecordGetHashCode == null
    assert foreign.RecordClone == null
}

// `FieldOrder` is live source metadata.  The first field is intentionally builder-bound and the
// later name intentionally absent: reaching the latter would throw from the field map.  A successful
// clone therefore proves the scan broke exactly at the first builder-bound field, while the skipped
// value members show that the same field fact controls both value-member branches.
test "record synthesis stops FieldOrder scanning at the first builder-bound field" {
    nested := SourceCallDefinition("RecordControlsNestedBuilder", true)
    definition := SynthesizedRecordCallDefinition("RecordControlsFieldStop", true)
    boundField := ConstructionDefinePublicField(definition.Builder, "Bound", nested.Builder)
    definition.Fields["Bound"] = boundField
    fieldNames := new string[](2)
    fieldNames[0] = "Bound"
    fieldNames[1] = "NeverRead"
    definition.SetFieldOrder(fieldNames)

    table := new ColumnarStructuralTypeReferenceTable()
    RecordSynthesisControlsRegister(table, definition)
    ColumnarRecordValueMemberPlanner.EmitRecordValueMembers(
        RecordSynthesisControlsSingleInput(RecordSynthesisControlsInput(definition.DeclaredTypeName, true)),
        RecordSynthesisControlsSingleDefinition(definition),
        table
    )

    assert definition.RecordEquals == null
    assert definition.RecordGetHashCode == null
    assert definition.RecordClone != null
}
