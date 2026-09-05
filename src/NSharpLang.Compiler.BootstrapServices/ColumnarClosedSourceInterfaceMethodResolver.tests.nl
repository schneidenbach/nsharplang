namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Reflection
import System.Reflection.Emit

func ClosedSourceSingleType(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func ClosedSourceSingleInt(value: int): int[] {
    values := new int[](1)
    values[0] = value
    return values
}

func ClosedSourceSingleString(value: string): string[] {
    values := new string[](1)
    values[0] = value
    return values
}

func ClosedSourceDefineTypeParameter(definition: ColumnarStructDef): Type {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string[])
    defineParameters := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "DefineGenericParameters",
        parameterTypes
    )
    names := ClosedSourceSingleString("T")
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, names)
    TypeOfRequiredInvocation(defineParameters, definition.Builder, arguments)
    parameters := definition.Builder.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException("The closed source-interface fixture did not define one type parameter.")
    }
    return parameters[0]
}

func ClosedSourceGenericInterface(name: string): ColumnarStructDef {
    definition := SourceCallInterfaceDefinition(name)
    _parameter := ClosedSourceDefineTypeParameter(definition)
    return definition
}

func ClosedSourceClose(definition: ColumnarStructDef, argument: Type): Type {
    openDefinition: Type = definition.Builder
    return openDefinition.MakeGenericType(ClosedSourceSingleType(argument))
}

func ClosedSourceRegister(
    table: ColumnarStructuralTypeReferenceTable,
    definition: ColumnarStructDef,
    sourceFileId: int
) {
    SourceInterfaceMethodRegister(table, definition)
    if definition.Builder.get_IsGenericTypeDefinition() {
        table.RegisterTypeGenericParameters(
            sourceFileId,
            definition.DeclaredTypeName,
            ClosedSourceSingleString("T"),
            definition.Builder
        )
    }
}

func ClosedSourceRequiredBinding(
    closedInterfaceType: Type,
    mappingOpenDefinition: ColumnarStructDef,
    memberName: string,
    returnType: Type,
    parameterTypes: Type[],
    table: ColumnarStructuralTypeReferenceTable
): ColumnarClosedSourceInterfaceMethodBinding {
    binding: ColumnarClosedSourceInterfaceMethodBinding? = null
    if !ColumnarClosedGenericMemberResolver.TryFindSourceInterfaceMethod(
        closedInterfaceType,
        mappingOpenDefinition,
        memberName,
        returnType,
        parameterTypes,
        table,
        out binding
    ) || binding == null || !binding.Matched {
        throw new InvalidOperationException("The closed source-interface fixture did not resolve its required binding.")
    }
    return binding
}

func ClosedSourceRequiredDescriptor(
    binding: ColumnarClosedSourceInterfaceMethodBinding
): ColumnarClosedSourceInterfaceMethodDescriptor {
    descriptor := binding.Descriptor
    if descriptor == null {
        throw new InvalidOperationException("The closed source-interface fixture did not retain its descriptor.")
    }
    return descriptor
}

func ClosedSourceRequiredTarget(
    binding: ColumnarClosedSourceInterfaceMethodBinding
): MethodInfo {
    target := binding.Target
    if target == null {
        throw new InvalidOperationException("The closed source-interface fixture did not retain its target.")
    }
    return target
}

func ClosedSourceRequiredKey(
    selected: ColumnarSelectedTypeReference
): ColumnarStructuralTypeKey {
    key := selected.Key
    if key == null {
        throw new InvalidOperationException("The closed source-interface fixture did not retain a structural key.")
    }
    return key
}

test "closed source lookup is own-first then depth-first and retains the actual ancestor" {
    noParameters := new Type[](0)
    noModifiers := new int[](0)
    root := SourceCallInterfaceDefinition("ClosedSourceOrderRoot")
    left := SourceCallInterfaceDefinition("ClosedSourceOrderLeft")
    right := SourceCallInterfaceDefinition("ClosedSourceOrderRight")
    own := SourceCallInterfaceDefinition("ClosedSourceOrderOwn")
    inherited := SourceCallInterfaceDefinition("ClosedSourceOrderInherited")

    rootMethod := SourceCallDefineInstance(root, "Read", noParameters, noModifiers, typeof(string), (MethodAttributes)1478)
    leftMethod := SourceCallDefineInstance(left, "Read", noParameters, noModifiers, typeof(string), (MethodAttributes)1478)
    rightMethod := SourceCallDefineInstance(right, "Read", noParameters, noModifiers, typeof(string), (MethodAttributes)1478)
    ownMethod := SourceCallDefineInstance(own, "Read", noParameters, noModifiers, typeof(string), (MethodAttributes)1478)
    _inheritedMismatch := SourceCallDefineInstance(inherited, "Read", noParameters, noModifiers, typeof(bool), (MethodAttributes)1478)
    left.InterfaceBases.Add(root)
    own.InterfaceBases.Add(left)
    own.InterfaceBases.Add(right)
    inherited.InterfaceBases.Add(left)
    inherited.InterfaceBases.Add(right)

    table := new ColumnarStructuralTypeReferenceTable()
    ClosedSourceRegister(table, root, 10)
    ClosedSourceRegister(table, left, 11)
    ClosedSourceRegister(table, right, 12)
    ClosedSourceRegister(table, own, 13)
    ClosedSourceRegister(table, inherited, 14)

    ownBinding := ClosedSourceRequiredBinding(own.Builder, own, "Read", typeof(string), noParameters, table)
    assert Object.ReferenceEquals(ClosedSourceRequiredTarget(ownBinding), ownMethod.Builder)
    ownDescriptor := ClosedSourceRequiredDescriptor(ownBinding)
    assert ownDescriptor.OpenDefinition.DeclaringType.SourceProvenanceName == "ClosedSourceOrderOwn"
    assert ownDescriptor.Validate(table)

    inheritedBinding := ClosedSourceRequiredBinding(inherited.Builder, inherited, "Read", typeof(string), noParameters, table)
    assert Object.ReferenceEquals(ClosedSourceRequiredTarget(inheritedBinding), leftMethod.Builder)
    assert !Object.ReferenceEquals(ClosedSourceRequiredTarget(inheritedBinding), rootMethod.Builder)
    assert !Object.ReferenceEquals(ClosedSourceRequiredTarget(inheritedBinding), rightMethod.Builder)
    inheritedDescriptor := ClosedSourceRequiredDescriptor(inheritedBinding)
    assert inheritedDescriptor.OpenDefinition.DeclaringType.SourceProvenanceName == "ClosedSourceOrderLeft"
    assert inheritedDescriptor.MappingOpenDefinition.SourceProvenanceName == "ClosedSourceOrderInherited"
    mappingKey := ClosedSourceRequiredKey(inheritedDescriptor.MappingOpenDefinition)
    contextKey := ClosedSourceRequiredKey(inheritedDescriptor.ClosedContext)
    assert ColumnarStructuralTypeKeyFacts.KeysEqual(mappingKey, contextKey)
    assert inheritedDescriptor.Validate(table)

    firstOnly := SourceCallInterfaceDefinition("ClosedSourceFirstMethodsRow")
    first := SourceCallDefineInstance(firstOnly, "Choose", noParameters, noModifiers, typeof(bool), (MethodAttributes)1478)
    second := SourceCallDefineInstance(firstOnly, "Choose", noParameters, noModifiers, typeof(string), (MethodAttributes)1478)
    ClosedSourceRegister(table, firstOnly, 15)
    missingLater: ColumnarClosedSourceInterfaceMethodBinding? = null
    assert !ColumnarClosedGenericMemberResolver.TryFindSourceInterfaceMethod(
        firstOnly.Builder,
        firstOnly,
        "Choose",
        typeof(string),
        noParameters,
        table,
        out missingLater
    )
    assert missingLater == null
    firstMethodsRow := firstOnly.Methods["Choose"]
    assert Object.ReferenceEquals(firstMethodsRow, first)
    assert !Object.ReferenceEquals(firstMethodsRow, second)

    defaultBody := SourceCallInterfaceDefinition("ClosedSourceDefaultCandidate")
    defaultMethod := SourceCallDefineInstance(defaultBody, "Describe", noParameters, noModifiers, typeof(string), (MethodAttributes)454)
    defaultBody.DefaultInterfaceMethodNames.Add("Describe")
    ClosedSourceRegister(table, defaultBody, 16)
    defaultBinding := ClosedSourceRequiredBinding(defaultBody.Builder, defaultBody, "Describe", typeof(string), noParameters, table)
    assert Object.ReferenceEquals(ClosedSourceRequiredTarget(defaultBinding), defaultMethod.Builder)
}

test "closed source descriptors retain open and effective identities from one successful match" {
    definition := ClosedSourceGenericInterface("ClosedSourceDescriptor")
    typeParameter := definition.Builder.GetGenericArguments()[0]
    table := new ColumnarStructuralTypeReferenceTable()
    ClosedSourceRegister(table, definition, 21)
    sourceParameterTypes := ClosedSourceSingleType(typeParameter)
    sourceModifierKinds := ClosedSourceSingleInt(2)
    sourceMethod := SourceCallDefineInstance(
        definition,
        "Map",
        sourceParameterTypes,
        sourceModifierKinds,
        typeParameter,
        (MethodAttributes)1478
    )
    openExpectedParameters := ClosedSourceSingleType(typeParameter)
    openBinding := ClosedSourceRequiredBinding(
        definition.Builder,
        definition,
        "Map",
        typeParameter,
        openExpectedParameters,
        table
    )
    assert Object.ReferenceEquals(ClosedSourceRequiredTarget(openBinding), sourceMethod.Builder)
    openDescriptor := ClosedSourceRequiredDescriptor(openBinding)
    openMappingKey := ClosedSourceRequiredKey(openDescriptor.MappingOpenDefinition)
    openContextKey := ClosedSourceRequiredKey(openDescriptor.ClosedContext)
    assert ColumnarStructuralTypeKeyFacts.KeysEqual(openMappingKey, openContextKey)
    assert openDescriptor.Validate(table)

    closedArguments := ClosedSourceSingleType(typeof(int))
    closedType := ClosedSourceClose(definition, typeof(int))
    effectiveParameters := ClosedSourceSingleType(typeof(int))
    binding := ClosedSourceRequiredBinding(
        closedType,
        definition,
        "Map",
        typeof(int),
        effectiveParameters,
        table
    )
    descriptor := ClosedSourceRequiredDescriptor(binding)
    openReturnKey := ClosedSourceRequiredKey(descriptor.OpenDefinition.ReturnType)
    openParameterKey := ClosedSourceRequiredKey(descriptor.OpenDefinition.ParameterType(0))
    mappingKey := ClosedSourceRequiredKey(descriptor.MappingOpenDefinition)
    contextKey := ClosedSourceRequiredKey(descriptor.ClosedContext)
    effectiveReturnKey := ClosedSourceRequiredKey(descriptor.EffectiveReturnType)
    effectiveParameterKey := ClosedSourceRequiredKey(descriptor.EffectiveParameterType(0))

    assert openReturnKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert openParameterKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert openReturnKey.GenericOwnerDeclaringTypeName == "ClosedSourceDescriptor"
    assert openParameterKey.GenericOwnerDeclaringTypeName == "ClosedSourceDescriptor"
    assert mappingKey.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition
    assert contextKey.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric
    assert contextKey.ChildCount == 2
    assert ColumnarStructuralTypeKeyFacts.KeysEqual(contextKey.Child(0), mappingKey)
    assert contextKey.Child(1).Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert contextKey.Child(1).PrimitiveName == "int32"
    assert effectiveReturnKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert effectiveReturnKey.PrimitiveName == "int32"
    assert effectiveParameterKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert effectiveParameterKey.PrimitiveName == "int32"
    assert descriptor.OpenDefinition.ParameterModifierKind(0) == 2
    assert descriptor.Validate(table)
    originalTarget := ClosedSourceRequiredTarget(binding)
    assert Object.ReferenceEquals(binding.ValidatedTarget(table), originalTarget)
    foreignTable := new ColumnarStructuralTypeReferenceTable()
    assert !descriptor.Validate(foreignTable)
    assert throws InvalidOperationException {
        _foreignTarget := binding.ValidatedTarget(foreignTable)
    }

    sourceParameterTypes[0] = typeof(string)
    sourceModifierKinds[0] = 1
    sourceMethod.ReturnType = typeof(string)
    sourceMethod.Builder = definition.Builder.DefineMethod(
        "Replacement",
        (MethodAttributes)1478,
        typeof(string),
        new Type[](0)
    )
    assert descriptor.Validate(table)
    assert Object.ReferenceEquals(binding.ValidatedTarget(table), originalTarget)
    assert descriptor.OpenDefinition.ReturnType.RuntimeType == typeParameter
    assert descriptor.OpenDefinition.ParameterType(0).RuntimeType == typeParameter
}

test "closed source descriptor construction rejects a row changed after matching" {
    definition := ClosedSourceGenericInterface("ClosedSourceChangedRow")
    typeParameter := definition.Builder.GetGenericArguments()[0]
    table := new ColumnarStructuralTypeReferenceTable()
    ClosedSourceRegister(table, definition, 31)
    parameterTypes := ClosedSourceSingleType(typeParameter)
    modifierKinds := ClosedSourceSingleInt(1)
    sourceMethod := SourceCallDefineInstance(
        definition,
        "Map",
        parameterTypes,
        modifierKinds,
        typeParameter,
        (MethodAttributes)1478
    )
    closedType := ClosedSourceClose(definition, typeof(int))
    matchedSignature := new ColumnarClosedSourceInterfaceMethodMatch(
        closedType,
        sourceMethod,
        typeof(int),
        ClosedSourceSingleType(typeof(int))
    )
    assert matchedSignature.Matched
    originalBuilder := sourceMethod.Builder
    validDescriptor := new ColumnarClosedSourceInterfaceMethodDescriptor(
        definition,
        definition,
        "Map",
        sourceMethod,
        matchedSignature,
        table
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarClosedSourceInterfaceMethodMatch)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarClosedSourceInterfaceMethodParameterDescriptor)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarClosedSourceInterfaceMethodDescriptor)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarClosedSourceInterfaceMethodBinding)
    )
    assert StructuralImmutabilityRejectsIListItemMutation(
        StructuralImmutabilityRequiredIList(matchedSignature, "openParametersValue"),
        0,
        typeof(string)
    )
    assert StructuralImmutabilityRejectsIListItemMutation(
        StructuralImmutabilityRequiredIList(matchedSignature, "effectiveParametersValue"),
        0,
        typeof(string)
    )
    assert StructuralImmutabilityRejectsIListItemMutation(
        StructuralImmutabilityRequiredIList(validDescriptor, "effectiveParametersValue"),
        0,
        validDescriptor.EffectiveParameter(0)
    )
    parameterTypes[0] = typeof(string)
    assert validDescriptor.Validate(table)
    assert matchedSignature.OpenParameterRuntimeType(0) == typeParameter
    assert throws InvalidOperationException {
        _invalid := new ColumnarClosedSourceInterfaceMethodDescriptor(
            definition,
            definition,
            "Map",
            sourceMethod,
            matchedSignature,
            table
        )
    }
    parameterTypes[0] = typeParameter
    sourceMethod.ReturnType = typeof(string)
    assert throws InvalidOperationException {
        _invalidReturn := new ColumnarClosedSourceInterfaceMethodDescriptor(
            definition,
            definition,
            "Map",
            sourceMethod,
            matchedSignature,
            table
        )
    }
    sourceMethod.ReturnType = typeParameter
    sourceMethod.Builder = definition.Builder.DefineMethod(
        "Replacement",
        (MethodAttributes)1478,
        typeof(string),
        new Type[](0)
    )
    assert throws InvalidOperationException {
        _invalidBuilder := new ColumnarClosedSourceInterfaceMethodDescriptor(
            definition,
            definition,
            "Map",
            sourceMethod,
            matchedSignature,
            table
        )
    }
    sourceMethod.Builder = originalBuilder
}

test "closed source matching preserves return arity and parameter short circuit order" {
    definition := ClosedSourceGenericInterface("ClosedSourceShortCircuit")
    typeParameter := definition.Builder.GetGenericArguments()[0]
    malformedParameters := new Type[](2)
    malformedParameters[0] = typeParameter
    malformedBuilder := definition.Builder.DefineMethod(
        "Malformed",
        (MethodAttributes)1478,
        typeof(string),
        new Type[](0)
    )
    malformed := new ColumnarInstanceMethodDef(
        malformedBuilder,
        malformedParameters,
        new int[](0),
        typeof(string)
    )
    closedType := ClosedSourceClose(definition, typeof(int))

    wrongReturn := new ColumnarClosedSourceInterfaceMethodMatch(
        closedType,
        malformed,
        typeof(bool),
        new Type[](0)
    )
    assert !wrongReturn.Matched

    wrongArity := new ColumnarClosedSourceInterfaceMethodMatch(
        closedType,
        malformed,
        typeof(string),
        ClosedSourceSingleType(typeof(int))
    )
    assert !wrongArity.Matched

    mismatchedParameters := new Type[](2)
    mismatchedParameters[0] = typeof(string)
    mismatchedParameters[1] = typeof(string)
    firstMismatch := new ColumnarClosedSourceInterfaceMethodMatch(
        closedType,
        malformed,
        typeof(string),
        mismatchedParameters
    )
    assert !firstMismatch.Matched

    reachingParameters := new Type[](2)
    reachingParameters[0] = typeof(int)
    reachingParameters[1] = typeof(string)
    assert throws NullReferenceException {
        _reachedMalformed := new ColumnarClosedSourceInterfaceMethodMatch(
            closedType,
            malformed,
            typeof(string),
            reachingParameters
        )
    }
}

test "closed source completeness uses structural type equivalence and skips defaults" {
    mapping := ClosedSourceGenericInterface("ClosedSourceCompleteness")
    typeParameter := mapping.Builder.GetGenericArguments()[0]
    noModifiers := new int[](0)
    requiredMethod := SourceCallDefineInstance(
        mapping,
        "Map",
        ClosedSourceSingleType(typeParameter),
        noModifiers,
        typeParameter,
        (MethodAttributes)1478
    )
    _defaultMethod := SourceCallDefineInstance(
        mapping,
        "Describe",
        new Type[](0),
        noModifiers,
        typeof(string),
        (MethodAttributes)454
    )
    mapping.DefaultInterfaceMethodNames.Add("Describe")
    implementer := SourceCallDefinition("ClosedSourceCompleteImplementer", true)
    _implementation := SourceCallDefineInstance(
        implementer,
        "Map",
        ClosedSourceSingleType(typeof(int)),
        noModifiers,
        typeof(int),
        (MethodAttributes)6
    )
    closedType := ClosedSourceClose(mapping, typeof(int))
    assert ColumnarClosedGenericMemberResolver.SourceInterfaceMembersSatisfied(implementer, mapping, closedType)

    firstOnlyImplementer := SourceCallDefinition("ClosedSourceFirstOnlyImplementer", true)
    _wrongFirst := SourceCallDefineInstance(
        firstOnlyImplementer,
        "Map",
        ClosedSourceSingleType(typeof(string)),
        noModifiers,
        typeof(string),
        (MethodAttributes)6
    )
    _rightLater := SourceCallDefineInstance(
        firstOnlyImplementer,
        "Map",
        ClosedSourceSingleType(typeof(int)),
        noModifiers,
        typeof(int),
        (MethodAttributes)6
    )
    assert !ColumnarClosedGenericMemberResolver.SourceInterfaceMembersSatisfied(firstOnlyImplementer, mapping, closedType)

    shapeDefinition := SourceCallGenericDefinition("ClosedSourceEquivalentShape")
    shapeType: Type = shapeDefinition.Builder
    shapeArguments := ClosedSourceSingleType(typeof(int))
    firstShape := shapeType.MakeGenericType(shapeArguments)
    secondShape := shapeType.MakeGenericType(shapeArguments)
    assert firstShape != secondShape
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(firstShape, secondShape)
    shapeInterface := SourceCallInterfaceDefinition("ClosedSourceEquivalentInterface")
    shapeImplementer := SourceCallDefinition("ClosedSourceEquivalentImplementer", true)
    voidType := ExecutorVoidType()
    _shapeRequired := SourceCallDefineInstance(
        shapeInterface,
        "Accept",
        ClosedSourceSingleType(firstShape),
        noModifiers,
        voidType,
        (MethodAttributes)1478
    )
    _shapeImplementation := SourceCallDefineInstance(
        shapeImplementer,
        "Accept",
        ClosedSourceSingleType(secondShape),
        noModifiers,
        voidType,
        (MethodAttributes)6
    )
    assert ColumnarClosedGenericMemberResolver.SourceInterfaceMembersSatisfied(
        shapeImplementer,
        shapeInterface,
        shapeInterface.Builder
    )
    requiredMethod.Builder = null
    requiredMethod.ParamModifierKinds = null
    assert ColumnarClosedGenericMemberResolver.SourceInterfaceMembersSatisfied(implementer, mapping, closedType)
}

test "closed source rows share first-seen MethodInfo dedup with ordinary and bare targets" {
    source := SourceCallInterfaceDefinition("ClosedSourceDedup")
    noParameters := new Type[](0)
    voidType := ExecutorVoidType()
    sourceMethod := SourceCallDefineInstance(source, "Run", noParameters, new int[](0), voidType, (MethodAttributes)1478)
    table := new ColumnarStructuralTypeReferenceTable()
    ClosedSourceRegister(table, source, 41)
    ordinary := SourceInterfaceMethodRequiredBinding(source, "Run", voidType, noParameters, table)
    closedBinding := ClosedSourceRequiredBinding(source.Builder, source, "Run", voidType, noParameters, table)

    closedFirst := DeclarationPlanOverrideDeclaration("Run", "void", false)
    closedFirst.AddSourceTarget(closedBinding)
    closedFirst.AddSourceTarget(ordinary)
    closedFirst.AddSourceTarget(sourceMethod.Builder)
    closedCompletion := closedFirst.Complete(null, voidType, noParameters)
    assert closedFirst.SourceTargetCount == 1
    assert closedCompletion.Targets.Length == 1
    assert closedCompletion.Targets[0].ClosedSourceInterfaceBinding != null
    assert closedCompletion.Targets[0].SourceInterfaceBinding == null

    ordinaryFirst := DeclarationPlanOverrideDeclaration("Run", "void", false)
    ordinaryFirst.AddSourceTarget(ordinary)
    ordinaryFirst.AddSourceTarget(closedBinding)
    ordinaryFirst.AddSourceTarget(sourceMethod.Builder)
    ordinaryCompletion := ordinaryFirst.Complete(null, voidType, noParameters)
    assert ordinaryFirst.SourceTargetCount == 1
    assert ordinaryCompletion.Targets[0].SourceInterfaceBinding != null
    assert ordinaryCompletion.Targets[0].ClosedSourceInterfaceBinding == null

    bareFirst := DeclarationPlanOverrideDeclaration("Run", "void", false)
    bareFirst.AddSourceTarget(sourceMethod.Builder)
    bareFirst.AddSourceTarget(closedBinding)
    bareFirst.AddSourceTarget(ordinary)
    bareCompletion := bareFirst.Complete(null, voidType, noParameters)
    assert bareFirst.SourceTargetCount == 1
    assert bareCompletion.Targets[0].SourceInterfaceBinding == null
    assert bareCompletion.Targets[0].ClosedSourceInterfaceBinding == null
}

test "closed source execution validates every structural pair before any attachment" {
    voidType := ExecutorVoidType()
    firstInterface := ClosedSourceGenericInterface("ClosedSourceAtomicFirst")
    secondInterface := ClosedSourceGenericInterface("ClosedSourceAtomicSecond")
    firstParameter := firstInterface.Builder.GetGenericArguments()[0]
    secondParameter := secondInterface.Builder.GetGenericArguments()[0]
    firstMethod := SourceCallDefineInstance(
        firstInterface,
        "Run",
        ClosedSourceSingleType(firstParameter),
        new int[](0),
        voidType,
        (MethodAttributes)454
    )
    secondMethod := SourceCallDefineInstance(
        secondInterface,
        "Run",
        ClosedSourceSingleType(secondParameter),
        new int[](0),
        voidType,
        (MethodAttributes)454
    )
    SourceInterfaceMethodEmitVoid(firstMethod.Builder)
    SourceInterfaceMethodEmitVoid(secondMethod.Builder)
    table := new ColumnarStructuralTypeReferenceTable()
    ClosedSourceRegister(table, firstInterface, 51)
    ClosedSourceRegister(table, secondInterface, 52)
    closedArguments := ClosedSourceSingleType(typeof(int))
    firstClosed := ClosedSourceClose(firstInterface, typeof(int))
    secondClosed := ClosedSourceClose(secondInterface, typeof(int))
    effectiveParameters := ClosedSourceSingleType(typeof(int))
    firstBinding := ClosedSourceRequiredBinding(firstClosed, firstInterface, "Run", voidType, effectiveParameters, table)
    malformedBinding := ClosedSourceRequiredBinding(secondClosed, secondInterface, "Run", voidType, effectiveParameters, table)
    malformedDescriptor := ClosedSourceRequiredDescriptor(malformedBinding)
    effectiveReturnField := typeof(ColumnarClosedSourceInterfaceMethodDescriptor).GetField("effectiveReturnTypeValue")
    if effectiveReturnField == null {
        throw new InvalidOperationException("The closed source-interface effective return identity field was not found.")
    }
    effectiveReturnField.SetValue(malformedDescriptor, table.SelectRuntimeType(typeof(string)))
    assert !malformedDescriptor.Validate(table)

    owner := TypeOfCreateSourceBuilder("ClosedSourceAtomicOwner", false)
    owner.AddInterfaceImplementation(firstClosed)
    owner.AddInterfaceImplementation(secondClosed)
    body := owner.DefineMethod(
        "ImplementationBody",
        (MethodAttributes)486,
        voidType,
        effectiveParameters
    )
    SourceInterfaceMethodEmitVoid(body)
    row := DeclarationPlanOverrideDeclaration("Run", "void", false)
    row.AddSourceTarget(firstBinding)
    row.AddSourceTarget(malformedBinding)
    completion := row.Complete(null, voidType, effectiveParameters)
    assert throws InvalidOperationException {
        completion.Apply(owner, body)
    }
    assert throws InvalidOperationException {
        completion.Apply(owner, body, table)
    }

    firstRuntimeDefinition := IdentityBake(firstInterface.Builder)
    _secondRuntimeDefinition := IdentityBake(secondInterface.Builder)
    ownerRuntime := IdentityBake(owner)
    firstRuntimeClosed := firstRuntimeDefinition.MakeGenericType(closedArguments)
    targets := SourceInterfaceMethodMapTargets(ownerRuntime, firstRuntimeClosed)
    assert targets.Count == 1
    mappedTarget := SourceInterfaceMethodRequiredMethod(targets[0])
    assert mappedTarget.get_Name() == "Run"
    assert mappedTarget.get_DeclaringType() == firstRuntimeClosed
}
