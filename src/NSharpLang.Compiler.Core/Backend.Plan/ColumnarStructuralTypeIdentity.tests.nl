namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// These contracts name the metadata identity a selected Type carries.  They deliberately exercise
// live runtime handles, metadata-universe handles, runtime builders, and persisted builders without
// relying on a particular TypeBuilder closure-cache implementation.
func StructuralIdentityRequiredKey(
    selected: ColumnarSelectedTypeReference,
    description: string
): ColumnarStructuralTypeKey {
    key := selected.Key
    if key == null {
        throw new InvalidOperationException(description + " did not select a structural key.")
    }
    return key
}

func StructuralIdentityOneParameterMap(
    parameterName: string,
    parameter: Type
): Dictionary<string, Type> {
    parameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameters[parameterName] = parameter
    return parameters
}

func StructuralIdentityRequiredRuntimeType(
    assemblyQualifiedName: string
): Type {
    resolved := Type.GetType(assemblyQualifiedName)
    if resolved == null {
        throw new InvalidOperationException(
            "The structural identity fixture could not resolve '" + assemblyQualifiedName + "'."
        )
    }
    return resolved
}

func StructuralIdentityAssertExternalNamed(
    table: ColumnarStructuralTypeReferenceTable,
    runtimeType: Type,
    expectedName: string
): bool {
    selected := table.SelectRuntimeType(runtimeType)
    key := StructuralIdentityRequiredKey(selected, expectedName)
    expectedAssembly := runtimeType.get_Assembly().GetName().get_FullName()
    if expectedAssembly == null {
        throw new InvalidOperationException(expectedName + " has no assembly identity.")
    }
    assert selected.RuntimeType == runtimeType
    assert key.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert key.PrimitiveName == ""
    assert key.SourceDeclarationName == ""
    assert key.AssemblyIdentity == expectedAssembly
    assert key.NamespaceName == "System"
    assert key.IsValueType
    assert key.NestedNameCount == 1
    assert key.NestedName(0) == expectedName
    assert key.ChildCount == 0
    assert table.ValidatePair(selected, runtimeType)
    return true
}

func StructuralIdentityAssertGenericParameter(
    table: ColumnarStructuralTypeReferenceTable,
    runtimeType: Type,
    expectedKind: ColumnarStructuralTypeReferenceKind,
    expectedOwnerKind: ColumnarStructuralGenericOwnerKind,
    expectedSourceFileId: int,
    expectedDeclaringTypeName: string,
    expectedMemberOrdinal: int,
    expectedParameterOrdinal: int
): bool {
    selected := table.SelectRuntimeType(runtimeType)
    key := StructuralIdentityRequiredKey(selected, "generic parameter")
    assert key.Kind == expectedKind
    assert Object.ReferenceEquals(key.EmissionIdentity, table.Identity)
    assert key.GenericOwnerKind == expectedOwnerKind
    assert key.GenericOwnerSourceFileId == expectedSourceFileId
    assert key.GenericOwnerDeclaringTypeName == expectedDeclaringTypeName
    assert key.GenericOwnerMemberOrdinal == expectedMemberOrdinal
    assert key.GenericParameterOrdinal == expectedParameterOrdinal
    assert key.ChildCount == 0
    assert table.ValidatePair(selected, runtimeType)
    return true
}

func StructuralIdentityFirstGenericMethodParameter(
    method: MethodBuilder,
    parameterName: string
): Type {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string[])
    defineParameters := ExecutorRequiredMethod(
        typeof(MethodBuilder),
        "DefineGenericParameters",
        parameterTypes
    )
    names := new string[](1)
    names[0] = parameterName
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, names)
    invocation := TypeOfRequiredInvocation(defineParameters, method, arguments)
    if invocation == null {
        throw new InvalidOperationException("DefineGenericParameters returned null.")
    }
    parameters := method.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException("The method generic fixture did not define one parameter.")
    }
    return parameters[0]
}

test "structural primitive keys converge across runtime and metadata contexts without accepting a full-name spoof" {
    table := new ColumnarStructuralTypeReferenceTable()
    runtimeSelected := table.SelectRuntimeType(typeof(int))
    runtimeKey := StructuralIdentityRequiredKey(runtimeSelected, "runtime int")
    assert runtimeKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert runtimeKey.PrimitiveName == "int32"
    assert runtimeKey.ChildCount == 0
    assert table.ValidatePair(runtimeSelected, typeof(int))

    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        core := context.LoadFromAssemblyName("System.Runtime")
        metadataInt := core.GetType("System.Int32")
        if metadataInt == null {
            throw new InvalidOperationException("The metadata context did not define System.Int32.")
        }
        assert metadataInt != typeof(int)

        metadataSelected := table.SelectRuntimeType(metadataInt)
        metadataKey := StructuralIdentityRequiredKey(metadataSelected, "metadata int")
        assert metadataKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
        assert metadataKey.PrimitiveName == "int32"
        assert Object.ReferenceEquals(runtimeKey, metadataKey)
        assert table.ValidatePair(metadataSelected, metadataInt)
    } finally {
        scan.Dispose()
    }

    spoof := TypeOfCreateBuilder(
        "System.Int32",
        "ColumnarStructuralIdentity.Spoof",
        0
    )
    assert spoof.get_FullName() == "System.Int32"
    assert ColumnarStructuralTypeKeyFacts.PrimitiveIdentity(spoof) == ""
    assert throws InvalidOperationException {
        table.SelectRuntimeType(spoof)
    }
}

test "structural Decimal and DateTime selections retain external metadata identity" {
    table := new ColumnarStructuralTypeReferenceTable()
    decimalType := typeof(decimal)
    dateTimeType := typeof(DateTime)
    assert StructuralIdentityAssertExternalNamed(table, decimalType, "Decimal")
    assert StructuralIdentityAssertExternalNamed(table, dateTimeType, "DateTime")

    decimalSelected := table.SelectRuntimeType(decimalType)
    dateTimeSelected := table.SelectRuntimeType(dateTimeType)
    decimalKey := StructuralIdentityRequiredKey(decimalSelected, "Decimal")
    dateTimeKey := StructuralIdentityRequiredKey(dateTimeSelected, "DateTime")
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(decimalKey, dateTimeKey)
}

test "structural external nested keys preserve outer-to-inner names and CLR value shape" {
    table := new ColumnarStructuralTypeReferenceTable()
    environment := StructuralIdentityRequiredRuntimeType(
        "System.Environment, System.Private.CoreLib"
    )
    valueNested := environment.GetNestedType("SpecialFolder")
    if valueNested == null {
        throw new InvalidOperationException("System.Environment.SpecialFolder was not found.")
    }
    dictionary := StructuralIdentityRequiredRuntimeType(
        "System.Collections.Generic.Dictionary`2, System.Private.CoreLib"
    )
    referenceNested := dictionary.GetNestedType("KeyCollection")
    if referenceNested == null {
        throw new InvalidOperationException("Dictionary<TKey, TValue>.KeyCollection was not found.")
    }

    valueSelected := table.SelectRuntimeType(valueNested)
    valueKey := StructuralIdentityRequiredKey(valueSelected, "SpecialFolder")
    assert valueKey.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert valueKey.NamespaceName == "System"
    assert valueKey.NestedNameCount == 2
    assert valueKey.NestedName(0) == "Environment"
    assert valueKey.NestedName(1) == "SpecialFolder"
    assert valueKey.IsValueType
    assert valueKey.ChildCount == 0
    assert table.ValidatePair(valueSelected, valueNested)

    referenceSelected := table.SelectRuntimeType(referenceNested)
    referenceKey := StructuralIdentityRequiredKey(referenceSelected, "KeyCollection")
    assert referenceKey.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert referenceKey.NamespaceName == "System.Collections.Generic"
    assert referenceKey.NestedNameCount == 2
    assert referenceKey.NestedName(0) == "Dictionary`2"
    assert referenceKey.NestedName(1) == "KeyCollection"
    assert !referenceKey.IsValueType
    assert referenceKey.ChildCount == 0
    assert table.ValidatePair(referenceSelected, referenceNested)
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(valueKey, referenceKey)
}

test "same-named baked external types in distinct assemblies retain distinct identities" {
    table := new ColumnarStructuralTypeReferenceTable()
    leftBuilder := TypeOfCreateBuilder(
        "External.Namesake",
        "ColumnarStructuralIdentity.ExternalLeft",
        0
    )
    rightBuilder := TypeOfCreateBuilder(
        "External.Namesake",
        "ColumnarStructuralIdentity.ExternalRight",
        0
    )
    leftRuntime := IdentityBake(leftBuilder)
    rightRuntime := IdentityBake(rightBuilder)
    assert leftRuntime.get_FullName() == "External.Namesake"
    assert rightRuntime.get_FullName() == "External.Namesake"
    assert leftRuntime.get_Assembly().GetName().get_FullName() != rightRuntime.get_Assembly().GetName().get_FullName()
    assert !ColumnarTypeOfPlanner.IsAssemblyBuilderBacked(leftRuntime)
    assert !ColumnarTypeOfPlanner.IsAssemblyBuilderBacked(rightRuntime)

    leftSelected := table.SelectRuntimeType(leftRuntime)
    rightSelected := table.SelectRuntimeType(rightRuntime)
    leftKey := StructuralIdentityRequiredKey(leftSelected, "left baked external")
    rightKey := StructuralIdentityRequiredKey(rightSelected, "right baked external")
    assert leftKey.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert rightKey.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert leftKey.NamespaceName == "External"
    assert rightKey.NamespaceName == "External"
    assert leftKey.NestedNameCount == 1
    assert rightKey.NestedNameCount == 1
    assert leftKey.NestedName(0) == "Namesake"
    assert rightKey.NestedName(0) == "Namesake"
    assert !leftKey.IsValueType
    assert !rightKey.IsValueType
    assert leftKey.AssemblyIdentity != rightKey.AssemblyIdentity
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(leftKey, rightKey)
    assert table.ValidatePair(leftSelected, leftRuntime)
    assert table.ValidatePair(rightSelected, rightRuntime)
}

test "equal source names in separate emissions keep distinct source-definition keys" {
    firstTable := new ColumnarStructuralTypeReferenceTable()
    secondTable := new ColumnarStructuralTypeReferenceTable()
    firstBuilder := TypeOfCreateBuilder(
        "Models.Shared",
        "ColumnarStructuralIdentity.FirstEmission",
        0
    )
    secondBuilder := TypeOfCreateBuilder(
        "Models.Shared",
        "ColumnarStructuralIdentity.SecondEmission",
        0
    )

    firstTable.RegisterSourceDefinition("Models.Shared", firstBuilder, false)
    secondTable.RegisterSourceDefinition("Models.Shared", secondBuilder, false)
    first := firstTable.SelectSourceDefinition("Models.Shared", firstBuilder)
    second := secondTable.SelectSourceDefinition("Models.Shared", secondBuilder)
    firstKey := StructuralIdentityRequiredKey(first, "first source definition")
    secondKey := StructuralIdentityRequiredKey(second, "second source definition")

    assert firstKey.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition
    assert firstKey.SourceDeclarationName == "Models.Shared"
    assert firstKey.ChildCount == 0
    assert secondKey.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition
    assert secondKey.SourceDeclarationName == "Models.Shared"
    assert secondKey.ChildCount == 0
    assert !Object.ReferenceEquals(firstTable.Identity, secondTable.Identity)
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(firstKey, secondKey)
    assert firstTable.ValidatePair(first, firstBuilder)
    assert secondTable.ValidatePair(second, secondBuilder)
    assert !firstTable.ValidatePair(second, secondBuilder)
    assert !secondTable.ValidatePair(first, firstBuilder)
}

test "same source short name in distinct namespaces stays distinct within one emission" {
    table := new ColumnarStructuralTypeReferenceTable()
    north := TypeOfCreateBuilder(
        "North.Widget",
        "ColumnarStructuralIdentity.North",
        0
    )
    south := TypeOfCreateBuilder(
        "South.Widget",
        "ColumnarStructuralIdentity.South",
        0
    )
    assert north.get_Name() == "Widget"
    assert south.get_Name() == "Widget"
    table.RegisterSourceDefinition("North.Widget", north, false)
    table.RegisterSourceDefinition("South.Widget", south, false)
    northSelected := table.SelectSourceDefinition("North.Widget", north)
    southSelected := table.SelectSourceDefinition("South.Widget", south)
    northKey := StructuralIdentityRequiredKey(northSelected, "North.Widget")
    southKey := StructuralIdentityRequiredKey(southSelected, "South.Widget")

    assert northKey.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition
    assert northKey.SourceDeclarationName == "North.Widget"
    assert southKey.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition
    assert southKey.SourceDeclarationName == "South.Widget"
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(northKey, southKey)
    assert table.ValidatePair(northSelected, north)
    assert table.ValidatePair(southSelected, south)
}

test "equivalent independently constructed source-builder closures intern one ordered structural key" {
    table := new ColumnarStructuralTypeReferenceTable()
    builder := TypeOfCreateBuilder(
        "Models.ClosureBox",
        "ColumnarStructuralIdentity.Closure",
        1
    )
    definition: Type = builder
    table.RegisterSourceDefinition("Models.ClosureBox", definition, false)
    definitionSelected := table.SelectSourceDefinition("Models.ClosureBox", definition)
    argumentSelected := table.SelectRuntimeType(typeof(int))
    arguments := new Type[](1)
    arguments[0] = typeof(int)
    selectedArguments := new ColumnarSelectedTypeReference[](1)
    selectedArguments[0] = argumentSelected

    firstClosure := definition.MakeGenericType(arguments)
    secondClosure := definition.MakeGenericType(arguments)
    first := table.SelectConstructedGeneric(
        firstClosure,
        definitionSelected,
        selectedArguments
    )
    second := table.SelectConstructedGeneric(
        secondClosure,
        definitionSelected,
        selectedArguments
    )
    firstKey := StructuralIdentityRequiredKey(first, "first source-builder closure")
    secondKey := StructuralIdentityRequiredKey(second, "second source-builder closure")

    assert firstKey.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric
    assert firstKey.ChildCount == 2
    assert firstKey.Child(0).Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition
    assert firstKey.Child(0).SourceDeclarationName == "Models.ClosureBox"
    assert firstKey.Child(1).Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert firstKey.Child(1).PrimitiveName == "int32"
    assert Object.ReferenceEquals(firstKey, secondKey)
    assert ColumnarStructuralTypeKeyFacts.KeysEqual(firstKey, secondKey)
    assert table.ValidatePair(first, firstClosure)
    assert table.ValidatePair(second, secondClosure)
}

test "structural generic keys preserve registered VAR and MVAR owners and ordinals through public flags" {
    table := new ColumnarStructuralTypeReferenceTable()
    typeBuilder := TypeOfCreateBuilder(
        "Models.GenericOwner",
        "ColumnarStructuralIdentity.GenericOwner",
        2
    )
    typeParameters := typeBuilder.GetGenericArguments()
    assert typeParameters.Length == 2
    assert typeParameters[0].get_IsGenericTypeParameter()
    assert !typeParameters[0].get_IsGenericMethodParameter()
    assert typeParameters[1].get_IsGenericTypeParameter()
    assert !typeParameters[1].get_IsGenericMethodParameter()
    typeParameterMap := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameterMap[typeParameters[0].get_Name()] = typeParameters[0]
    typeParameterMap[typeParameters[1].get_Name()] = typeParameters[1]
    table.RegisterGenericParameters(
        typeParameterMap,
        ColumnarStructuralGenericOwnerIdentity.SourceType(41, "Models.GenericOwner")
    )
    assert StructuralIdentityAssertGenericParameter(
        table,
        typeParameters[0],
        ColumnarStructuralTypeReferenceKind.TypeGenericParameter,
        ColumnarStructuralGenericOwnerKind.SourceType,
        41,
        "Models.GenericOwner",
        -1,
        0
    )
    assert StructuralIdentityAssertGenericParameter(
        table,
        typeParameters[1],
        ColumnarStructuralTypeReferenceKind.TypeGenericParameter,
        ColumnarStructuralGenericOwnerKind.SourceType,
        41,
        "Models.GenericOwner",
        -1,
        1
    )

    methodOwner := TypeOfCreateBuilder(
        "Models.MethodOwner",
        "ColumnarStructuralIdentity.MethodOwner",
        0
    )
    method := methodOwner.DefineMethod(
        "Map",
        (MethodAttributes)22,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        new Type[](0)
    )
    methodParameter := StructuralIdentityFirstGenericMethodParameter(method, "M0")
    assert !methodParameter.get_IsGenericTypeParameter()
    assert methodParameter.get_IsGenericMethodParameter()
    methodParameterMap := StructuralIdentityOneParameterMap(
        methodParameter.get_Name(),
        methodParameter
    )
    table.RegisterGenericParameters(
        methodParameterMap,
        ColumnarStructuralGenericOwnerIdentity.SourceMethod(41, 12)
    )
    assert StructuralIdentityAssertGenericParameter(
        table,
        methodParameter,
        ColumnarStructuralTypeReferenceKind.MethodGenericParameter,
        ColumnarStructuralGenericOwnerKind.SourceMethod,
        41,
        "",
        12,
        0
    )

    otherMethod := methodOwner.DefineMethod(
        "MapAgain",
        (MethodAttributes)22,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        new Type[](0)
    )
    otherParameter := StructuralIdentityFirstGenericMethodParameter(otherMethod, "M0")
    assert !otherParameter.get_IsGenericTypeParameter()
    assert otherParameter.get_IsGenericMethodParameter()
    table.RegisterGenericParameters(
        StructuralIdentityOneParameterMap(
            otherParameter.get_Name(),
            otherParameter
        ),
        ColumnarStructuralGenericOwnerIdentity.SourceMethod(41, 13)
    )
    assert StructuralIdentityAssertGenericParameter(
        table,
        otherParameter,
        ColumnarStructuralTypeReferenceKind.MethodGenericParameter,
        ColumnarStructuralGenericOwnerKind.SourceMethod,
        41,
        "",
        13,
        0
    )
    firstMethodKey := StructuralIdentityRequiredKey(
        table.SelectRuntimeType(methodParameter),
        "first MVAR"
    )
    secondMethodKey := StructuralIdentityRequiredKey(
        table.SelectRuntimeType(otherParameter),
        "second MVAR"
    )
    assert firstMethodKey.GenericParameterOrdinal == 0
    assert secondMethodKey.GenericParameterOrdinal == 0
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(
        firstMethodKey,
        secondMethodKey
    )

    wrongOwnerTable := new ColumnarStructuralTypeReferenceTable()
    assert throws InvalidOperationException {
        wrongOwnerTable.RegisterGenericParameters(
            methodParameterMap,
            ColumnarStructuralGenericOwnerIdentity.SourceType(41, "Models.MethodOwner")
        )
    }
}

test "structural persisted-emitter VAR and MVAR registration uses public generic-kind flags" {
    persistedRuntime := ExternalGuardPersistedBuilder(
        "Models.PersistedGenericOwner",
        1,
        typeof(object)
    )
    persistedOwner := persistedRuntime as TypeBuilder
    if persistedOwner == null {
        throw new InvalidOperationException("The persisted generic fixture did not return a TypeBuilder.")
    }
    persistedTypeParameters := persistedOwner.GetGenericArguments()
    assert persistedTypeParameters.Length == 1
    persistedTypeParameter := persistedTypeParameters[0]
    assert persistedTypeParameter.get_IsGenericTypeParameter()
    assert !persistedTypeParameter.get_IsGenericMethodParameter()

    persistedMethod := persistedOwner.DefineMethod(
        "Map",
        (MethodAttributes)22,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        new Type[](0)
    )
    persistedMethodParameter := StructuralIdentityFirstGenericMethodParameter(persistedMethod, "M0")
    assert !persistedMethodParameter.get_IsGenericTypeParameter()
    assert persistedMethodParameter.get_IsGenericMethodParameter()

    table := new ColumnarStructuralTypeReferenceTable()
    table.RegisterGenericParameters(
        StructuralIdentityOneParameterMap(
            persistedTypeParameter.get_Name(),
            persistedTypeParameter
        ),
        ColumnarStructuralGenericOwnerIdentity.SourceType(
            57,
            "Models.PersistedGenericOwner"
        )
    )
    table.RegisterGenericParameters(
        StructuralIdentityOneParameterMap(
            persistedMethodParameter.get_Name(),
            persistedMethodParameter
        ),
        ColumnarStructuralGenericOwnerIdentity.SourceMethod(57, 4)
    )
    assert StructuralIdentityAssertGenericParameter(
        table,
        persistedTypeParameter,
        ColumnarStructuralTypeReferenceKind.TypeGenericParameter,
        ColumnarStructuralGenericOwnerKind.SourceType,
        57,
        "Models.PersistedGenericOwner",
        -1,
        0
    )
    assert StructuralIdentityAssertGenericParameter(
        table,
        persistedMethodParameter,
        ColumnarStructuralTypeReferenceKind.MethodGenericParameter,
        ColumnarStructuralGenericOwnerKind.SourceMethod,
        57,
        "",
        4,
        0
    )
}

test "structural keys snapshot caller arrays and reject an altered constructed child" {
    table := new ColumnarStructuralTypeReferenceTable()
    dateTimeAssembly := typeof(DateTime).get_Assembly().GetName().get_FullName()
    if dateTimeAssembly == null {
        throw new InvalidOperationException("DateTime has no assembly identity.")
    }
    mutableNames := new string[](1)
    mutableNames[0] = "DateTime"
    emptyChildren := new ColumnarStructuralTypeKey[](0)
    dateTimeKey := new ColumnarStructuralTypeKey(
        ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition,
        null,
        "",
        "",
        dateTimeAssembly,
        "System",
        mutableNames,
        true,
        ColumnarStructuralGenericOwnerKind.SourceType,
        -1,
        "",
        -1,
        -1,
        null,
        emptyChildren
    )
    mutableNames[0] = "Altered"
    assert dateTimeKey.NestedName(0) == "DateTime"
    dateTimeSelected := new ColumnarSelectedTypeReference(
        table.Identity,
        dateTimeKey,
        typeof(DateTime),
        true,
        null,
        ""
    )
    assert table.ValidatePair(dateTimeSelected, typeof(DateTime))

    builder := TypeOfCreateBuilder(
        "Models.SnapshotBox",
        "ColumnarStructuralIdentity.Snapshot",
        1
    )
    definition: Type = builder
    table.RegisterSourceDefinition("Models.SnapshotBox", definition, false)
    definitionSelected := table.SelectSourceDefinition("Models.SnapshotBox", definition)
    argumentSelected := table.SelectRuntimeType(typeof(int))
    definitionKey := StructuralIdentityRequiredKey(
        definitionSelected,
        "snapshot definition"
    )
    intKey := StructuralIdentityRequiredKey(argumentSelected, "snapshot int")
    stringKey := StructuralIdentityRequiredKey(
        table.SelectRuntimeType(typeof(string)),
        "snapshot string"
    )
    arguments := new Type[](1)
    arguments[0] = typeof(int)
    runtimeClosure := definition.MakeGenericType(arguments)
    mutableChildren := new ColumnarStructuralTypeKey[](2)
    mutableChildren[0] = definitionKey
    mutableChildren[1] = intKey
    snapshotKey := new ColumnarStructuralTypeKey(
        ColumnarStructuralTypeReferenceKind.ConstructedGeneric,
        null,
        "",
        "",
        "",
        "",
        new string[](0),
        false,
        ColumnarStructuralGenericOwnerKind.SourceType,
        -1,
        "",
        -1,
        -1,
        null,
        mutableChildren
    )
    mutableChildren[1] = stringKey
    assert snapshotKey.ChildCount == 2
    assert Object.ReferenceEquals(snapshotKey.Child(1), intKey)
    snapshotSelected := new ColumnarSelectedTypeReference(
        table.Identity,
        snapshotKey,
        runtimeClosure,
        true,
        null,
        ""
    )
    assert table.ValidatePair(snapshotSelected, runtimeClosure)

    alteredChildren := new ColumnarStructuralTypeKey[](2)
    alteredChildren[0] = definitionKey
    alteredChildren[1] = stringKey
    alteredKey := new ColumnarStructuralTypeKey(
        ColumnarStructuralTypeReferenceKind.ConstructedGeneric,
        null,
        "",
        "",
        "",
        "",
        new string[](0),
        false,
        ColumnarStructuralGenericOwnerKind.SourceType,
        -1,
        "",
        -1,
        -1,
        null,
        alteredChildren
    )
    alteredSelected := new ColumnarSelectedTypeReference(
        table.Identity,
        alteredKey,
        runtimeClosure,
        true,
        null,
        ""
    )
    assert !table.ValidatePair(alteredSelected, runtimeClosure)
}

test "structural validation rejects malformed source-provenance tokens and names" {
    table := new ColumnarStructuralTypeReferenceTable()
    left := TypeOfCreateBuilder(
        "Models.Left",
        "ColumnarStructuralIdentity.ProvenanceLeft",
        0
    )
    right := TypeOfCreateBuilder(
        "Models.Right",
        "ColumnarStructuralIdentity.ProvenanceRight",
        0
    )
    table.RegisterSourceDefinition("Models.Left", left, false)
    table.RegisterSourceDefinition("Models.Right", right, false)
    selected := table.SelectSourceDefinition("Models.Left", left)
    key := StructuralIdentityRequiredKey(selected, "left source definition")
    assert table.ValidatePair(selected, left)

    tampered := new ColumnarSelectedTypeReference(
        table.Identity,
        key,
        left,
        true,
        table.Identity,
        "Models.Right"
    )
    assert !table.ValidatePair(tampered, left)

    foreignTable := new ColumnarStructuralTypeReferenceTable()
    foreignToken := new ColumnarSelectedTypeReference(
        table.Identity,
        key,
        left,
        true,
        foreignTable.Identity,
        "Models.Left"
    )
    assert !table.ValidatePair(foreignToken, left)

    nameOnly := new ColumnarSelectedTypeReference(
        table.Identity,
        key,
        left,
        true,
        null,
        "Models.Left"
    )
    assert !table.ValidatePair(nameOnly, left)

    tokenOnly := new ColumnarSelectedTypeReference(
        table.Identity,
        key,
        left,
        true,
        table.Identity,
        ""
    )
    assert !table.ValidatePair(tokenOnly, left)
}

test "structural validation rejects synthesized identity as supplied source provenance" {
    table := new ColumnarStructuralTypeReferenceTable()
    stableIdentity := "iterator:71:3:Models.IteratorState"
    builder := TypeOfCreateBuilder(
        "Models.IteratorState",
        "ColumnarStructuralIdentity.Synthesized",
        0
    )
    table.RegisterSynthesizedDefinition(stableIdentity, builder)
    selected := table.SelectSynthesizedDefinition(stableIdentity, builder)
    key := StructuralIdentityRequiredKey(selected, "synthesized definition")
    assert key.Kind == ColumnarStructuralTypeReferenceKind.SynthesizedDefinition
    assert table.ValidatePair(selected, builder)

    forged := new ColumnarSelectedTypeReference(
        table.Identity,
        key,
        builder,
        true,
        table.Identity,
        stableIdentity
    )
    assert !table.ValidatePair(forged, builder)
}

test "erased enum source registrations share the primitive key and retain distinct provenance" {
    table := new ColumnarStructuralTypeReferenceTable()
    table.RegisterSourceDefinition("Models.LeftState", typeof(string), true)
    table.RegisterSourceDefinition("Models.RightState", typeof(string), true)
    left := table.SelectSourceDefinition("Models.LeftState", typeof(string))
    right := table.SelectSourceDefinition("Models.RightState", typeof(string))
    leftKey := StructuralIdentityRequiredKey(left, "left erased enum")
    rightKey := StructuralIdentityRequiredKey(right, "right erased enum")

    assert left.RuntimeType == typeof(string)
    assert right.RuntimeType == typeof(string)
    assert leftKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert leftKey.PrimitiveName == "string"
    assert leftKey.ChildCount == 0
    assert rightKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert rightKey.PrimitiveName == "string"
    assert rightKey.ChildCount == 0
    assert Object.ReferenceEquals(leftKey, rightKey)
    assert left.SourceProvenanceName == "Models.LeftState"
    assert right.SourceProvenanceName == "Models.RightState"
    assert left.SourceProvenanceName != right.SourceProvenanceName
    assert table.ValidatePair(left, typeof(string))
    assert table.ValidatePair(right, typeof(string))

    unknownProvenance := new ColumnarSelectedTypeReference(
        table.Identity,
        leftKey,
        typeof(string),
        true,
        table.Identity,
        "Models.UnknownState"
    )
    assert !table.ValidatePair(unknownProvenance, typeof(string))
}
