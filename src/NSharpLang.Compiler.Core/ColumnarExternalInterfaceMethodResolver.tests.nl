namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func ExternalMemberRequiredType(assemblyQualifiedName: string): Type {
    runtimeType := Type.GetType(assemblyQualifiedName)
    if runtimeType == null {
        throw new InvalidOperationException(
            "The external-member fixture could not resolve '" + assemblyQualifiedName + "'."
        )
    }
    return runtimeType
}

func ExternalMemberSingleType(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func ExternalMemberCloseOne(definition: Type, argument: Type): Type {
    return definition.MakeGenericType(ExternalMemberSingleType(argument))
}

func ExternalMemberParameterTypes(method: MethodInfo): Type[] {
    parameters := method.GetParameters()
    result := new Type[](parameters.Length)
    index := 0
    while index < parameters.Length {
        result[index] = parameters[index].get_ParameterType()
        index += 1
    }
    return result
}

func ExternalMemberRequiredGenericMethod(owner: Type, name: string): MethodInfo {
    for candidate in owner.GetMethods() {
        if candidate.get_Name() == name && candidate.get_IsGenericMethod() {
            return candidate
        }
    }
    throw new InvalidOperationException("The external-member generic method was not found: " + name)
}

func ExternalMemberRequiredNamedMethod(owner: Type, name: string): MethodInfo {
    for candidate in owner.GetMethods() {
        if candidate.get_Name() == name {
            return candidate
        }
    }
    throw new InvalidOperationException("The external-member method was not found: " + name)
}

func ExternalMemberRequiredKey(
    selected: ColumnarSelectedTypeReference,
    description: string
): ColumnarStructuralTypeKey {
    key := selected.Key
    if key == null {
        throw new InvalidOperationException(description + " did not retain a structural key.")
    }
    return key
}

func ExternalMemberRequiredBinding(
    lookupContext: Type,
    memberName: string,
    returnType: Type,
    parameterTypes: Type[],
    table: ColumnarStructuralTypeReferenceTable
): ColumnarExternalInterfaceMethodBinding {
    declaration := DeclarationPlanOverrideDeclaration(memberName, "external", false)
    interfaces := new List<Type>()
    interfaces.Add(lookupContext)
    ColumnarExternalInterfaceMethodResolver.AddMatchingTargets(
        declaration,
        interfaces,
        memberName,
        returnType,
        parameterTypes,
        table
    )
    completion := declaration.Complete(null, returnType, parameterTypes)
    targets := completion.Targets
    if targets.Length != 1 || targets[0].ExternalInterfaceBinding == null {
        throw new InvalidOperationException("The external-member fixture did not retain one binding.")
    }
    bindingObject: object? = targets[0].ExternalInterfaceBinding
    return (ColumnarExternalInterfaceMethodBinding)bindingObject
}

func ExternalMemberRequiredDescriptor(
    binding: ColumnarExternalInterfaceMethodBinding
): ColumnarExternalMethodDescriptor {
    descriptor := binding.Descriptor
    if descriptor == null {
        throw new InvalidOperationException("The external-member binding did not retain its descriptor.")
    }
    return descriptor
}

func ExternalMemberBakeInterface(
    typeName: string,
    memberName: string,
    returnType: Type,
    parameterTypes: Type[],
    attributes: MethodAttributes
): Type {
    definition := SourceCallInterfaceDefinition(typeName)
    method := SourceCallDefineInstance(
        definition,
        memberName,
        parameterTypes,
        new int[](0),
        returnType,
        attributes
    )
    if !method.Builder.get_IsAbstract() {
        SourceInterfaceMethodEmitVoid(method.Builder)
    }
    return IdentityBake(definition.Builder)
}

func ExternalMemberBakeModifiedInterface(typeName: string): Type {
    definition := SourceCallInterfaceDefinition(typeName)
    parameterTypes := ExternalMemberSingleType(typeof(int))
    method := definition.Builder.DefineMethod(
        "Transform",
        (MethodAttributes)1478,
        typeof(int),
        parameterTypes
    )
    setSignatureParameterTypes := new Type[](6)
    typeArrayType := typeof(Type).MakeArrayType()
    typeArrayArrayType := typeArrayType.MakeArrayType()
    setSignatureParameterTypes[0] = typeof(Type)
    setSignatureParameterTypes[1] = typeArrayType
    setSignatureParameterTypes[2] = typeArrayType
    setSignatureParameterTypes[3] = typeArrayType
    setSignatureParameterTypes[4] = typeArrayArrayType
    setSignatureParameterTypes[5] = typeArrayArrayType
    setSignature := ExecutorRequiredMethod(
        typeof(MethodBuilder),
        "SetSignature",
        setSignatureParameterTypes
    )

    obsoleteMarker := ExternalMemberRequiredType("System.ObsoleteAttribute, System.Private.CoreLib")
    clsMarker := ExternalMemberRequiredType("System.CLSCompliantAttribute, System.Private.CoreLib")
    serializableMarker := ExternalMemberRequiredType("System.SerializableAttribute, System.Private.CoreLib")
    paramArrayMarker := ExternalMemberRequiredType("System.ParamArrayAttribute, System.Private.CoreLib")
    flagsMarker := ExternalMemberRequiredType("System.FlagsAttribute, System.Private.CoreLib")
    staMarker := ExternalMemberRequiredType("System.STAThreadAttribute, System.Private.CoreLib")
    returnRequired := new Type[](2)
    returnRequired[0] = obsoleteMarker
    returnRequired[1] = clsMarker
    returnOptional := ExternalMemberSingleType(serializableMarker)
    parameterRequired := new Type[][](1)
    parameterRequired[0] = ExternalMemberSingleType(paramArrayMarker)
    parameterOptional := new Type[][](1)
    parameterOptionalMarkers := new Type[](2)
    parameterOptionalMarkers[0] = flagsMarker
    parameterOptionalMarkers[1] = staMarker
    parameterOptional[0] = parameterOptionalMarkers
    arguments := new object[](6)
    ExecutorSetObject(arguments, 0, typeof(int))
    ExecutorSetObject(arguments, 1, returnRequired)
    ExecutorSetObject(arguments, 2, returnOptional)
    ExecutorSetObject(arguments, 3, parameterTypes)
    ExecutorSetObject(arguments, 4, parameterRequired)
    ExecutorSetObject(arguments, 5, parameterOptional)
    setSignature.Invoke(method, arguments)
    return IdentityBake(definition.Builder)
}

func ExternalMemberInterfaceList(first: Type, second: Type?): List<Type> {
    interfaces := new List<Type>()
    interfaces.Add(first)
    if second != null {
        interfaces.Add(second)
    }
    return interfaces
}

test "external matching preserves short circuit order and TypesEquivalent return identity" {
    noParameters := new Type[](0)
    genericDefinition := SourceCallGenericDefinition("ExternalMemberEquivalentReturn")
    genericBuilderType: Type = genericDefinition.Builder
    firstReturn := genericBuilderType.MakeGenericType(ExternalMemberSingleType(typeof(int)))
    secondReturn := genericBuilderType.MakeGenericType(ExternalMemberSingleType(typeof(int)))
    assert firstReturn != secondReturn
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(firstReturn, secondReturn)

    owner := TypeOfCreateSourceBuilder("ExternalMemberUnbakedMatch", false)
    candidate := owner.DefineMethod(
        "Resolve",
        (MethodAttributes)6,
        firstReturn,
        noParameters
    )
    nullParameterRow := SourceCallConstructInstanceFact(
        candidate,
        noParameters,
        new int[](0),
        firstReturn
    )
    nullParameterRow.ParamTypes = null
    nullParameters := nullParameterRow.ParamTypes
    wrongName := new ColumnarExternalInterfaceMethodMatch(
        candidate,
        "Other",
        secondReturn,
        nullParameters
    )
    assert !wrongName.Matched
    wrongReturn := new ColumnarExternalInterfaceMethodMatch(
        candidate,
        "Resolve",
        typeof(string),
        nullParameters
    )
    assert !wrongReturn.Matched
    assert throws NotSupportedException {
        _reachedParameters := new ColumnarExternalInterfaceMethodMatch(
            candidate,
            "Resolve",
            secondReturn,
            noParameters
        )
    }

    comparableDefinition := ExternalMemberRequiredType(
        "System.Collections.Generic.IDictionary`2, System.Private.CoreLib"
    )
    comparableArguments := new Type[](2)
    comparableArguments[0] = typeof(int)
    comparableArguments[1] = typeof(string)
    dictionaryType := comparableDefinition.MakeGenericType(comparableArguments)
    tryGetParameters := new Type[](2)
    tryGetParameters[0] = typeof(int)
    tryGetParameters[1] = typeof(string).MakeByRefType()
    tryGet := ExecutorRequiredMethod(dictionaryType, "TryGetValue", tryGetParameters)
    malformedExpected := new Type[](2)
    malformedExpected[0] = typeof(string)
    firstMismatch := new ColumnarExternalInterfaceMethodMatch(
        tryGet,
        "TryGetValue",
        typeof(bool),
        malformedExpected
    )
    assert !firstMismatch.Matched
    malformedExpected[0] = typeof(int)
    assert throws NullReferenceException {
        _reachedSecondParameter := new ColumnarExternalInterfaceMethodMatch(
            tryGet,
            "TryGetValue",
            typeof(bool),
            malformedExpected
        )
    }
}

test "constructed external binding retains open VAR and effective runtime signature once" {
    comparableDefinition := ExternalMemberRequiredType(
        "System.IComparable`1, System.Private.CoreLib"
    )
    comparableType := ExternalMemberCloseOne(comparableDefinition, typeof(int))
    parameterTypes := ExternalMemberSingleType(typeof(int))
    table := new ColumnarStructuralTypeReferenceTable()
    binding := ExternalMemberRequiredBinding(
        comparableType,
        "CompareTo",
        typeof(int),
        parameterTypes,
        table
    )
    descriptor := ExternalMemberRequiredDescriptor(binding)
    assert descriptor.Validate(table)
    assert Object.ReferenceEquals(binding.ValidatedTarget(table), descriptor.Target)
    assert descriptor.MethodName == "CompareTo"
    assert descriptor.MethodGenericArity == 0
    assert !descriptor.MethodIsStatic
    assert descriptor.ParameterCount == 1
    assert descriptor.GenericParameterCount == 0
    assert descriptor.LookupContext.RuntimeType == comparableType
    assert descriptor.ReflectedContext.RuntimeType == comparableType
    assert descriptor.DeclaringContext.RuntimeType == comparableType
    assert descriptor.OpenDeclaringType.RuntimeType == comparableDefinition

    lookupKey := ExternalMemberRequiredKey(descriptor.LookupContext, "lookup context")
    openOwnerKey := ExternalMemberRequiredKey(descriptor.OpenDeclaringType, "open declaring type")
    openParameter := descriptor.Parameter(0).Open
    effectiveParameter := descriptor.Parameter(0).Effective
    openParameterKey := ExternalMemberRequiredKey(openParameter.Type, "open parameter")
    effectiveParameterKey := ExternalMemberRequiredKey(effectiveParameter.Type, "effective parameter")
    assert lookupKey.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric
    assert lookupKey.ChildCount == 2
    assert ColumnarStructuralTypeKeyFacts.KeysEqual(lookupKey.Child(0), openOwnerKey)
    assert openParameterKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert openParameterKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalType
    assert openParameterKey.GenericParameterOrdinal == 0
    assert openParameterKey.ExternalGenericOwner != null
    assert ColumnarStructuralTypeKeyFacts.KeysEqual(
        openParameterKey.ExternalGenericOwner.DeclaringType,
        openOwnerKey
    )
    assert effectiveParameterKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert effectiveParameterKey.PrimitiveName == "int32"
    assert openParameter.RuntimeType.get_IsGenericTypeParameter()
    assert effectiveParameter.RuntimeType == typeof(int)

    parameterTypes[0] = typeof(string)
    assert descriptor.Parameter(0).Effective.RuntimeType == typeof(int)
    assert descriptor.Validate(table)
    parametersStorage := StructuralImmutabilityRequiredIList(descriptor, "parametersValue")
    assert StructuralImmutabilityRejectsIListItemMutation(
        parametersStorage,
        0,
        descriptor.Parameter(0)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarExternalMethodDescriptor))
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarExternalInterfaceMethodBinding))
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarExternalMethodSignatureTypeDescriptor))

    foreignTable := new ColumnarStructuralTypeReferenceTable()
    assert !descriptor.Validate(foreignTable)
    assert throws InvalidOperationException {
        _foreignTarget := binding.ValidatedTarget(foreignTable)
    }

    collectionDefinition := ExternalMemberRequiredType(
        "System.Collections.Generic.ICollection`1, System.Private.CoreLib"
    )
    intArrayType := typeof(int).MakeArrayType()
    collectionType := ExternalMemberCloseOne(collectionDefinition, intArrayType)
    copyTo := ExternalMemberRequiredNamedMethod(collectionType, "CopyTo")
    copyToParameters := ExternalMemberParameterTypes(copyTo)
    copyBinding := ExternalMemberRequiredBinding(
        collectionType,
        "CopyTo",
        copyTo.get_ReturnType(),
        copyToParameters,
        table
    )
    copyDescriptor := ExternalMemberRequiredDescriptor(copyBinding)
    assert copyDescriptor.Validate(table)
    copyOpenKey := ExternalMemberRequiredKey(
        copyDescriptor.Parameter(0).Open.Type,
        "open CopyTo array"
    )
    copyEffectiveKey := ExternalMemberRequiredKey(
        copyDescriptor.Parameter(0).Effective.Type,
        "effective CopyTo array"
    )
    assert copyOpenKey.Kind == ColumnarStructuralTypeReferenceKind.SzArray
    assert copyOpenKey.Child(0).Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert copyEffectiveKey.Kind == ColumnarStructuralTypeReferenceKind.SzArray
    assert copyEffectiveKey.Child(0).Kind == ColumnarStructuralTypeReferenceKind.SzArray
    assert copyEffectiveKey.Child(0).Child(0).PrimitiveName == "int32"
}

test "external generic methods retain authoritative MVAR owner and open custom modifiers" {
    queryProvider := ExternalMemberRequiredType(
        "System.Linq.IQueryProvider, System.Linq.Expressions"
    )
    genericMethod := ExternalMemberRequiredGenericMethod(queryProvider, "Execute")
    genericParameters := genericMethod.GetGenericArguments()
    assert genericParameters.Length == 1
    table := new ColumnarStructuralTypeReferenceTable()
    genericBinding := ExternalMemberRequiredBinding(
        queryProvider,
        "Execute",
        genericParameters[0],
        ExternalMemberParameterTypes(genericMethod),
        table
    )
    descriptor := ExternalMemberRequiredDescriptor(genericBinding)
    assert descriptor.Validate(table)
    assert descriptor.GenericParameterCount == 1
    genericParameter := descriptor.GenericParameter(0)
    openKey := ExternalMemberRequiredKey(genericParameter.OpenType, "open MVAR")
    effectiveKey := ExternalMemberRequiredKey(genericParameter.EffectiveType, "effective MVAR")
    assert openKey.Kind == ColumnarStructuralTypeReferenceKind.MethodGenericParameter
    assert openKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalMethod
    assert openKey.ExternalGenericOwner != null
    assert openKey.ExternalGenericOwner.MethodMetadataToken == genericMethod.get_MetadataToken()
    assert openKey.ExternalGenericOwner.MethodName == "Execute"
    assert openKey.ExternalGenericOwner.MethodGenericArity == 1
    assert ColumnarStructuralTypeKeyFacts.KeysEqual(openKey, effectiveKey)

    constructedGeneric := genericMethod.MakeGenericMethod(
        ExternalMemberSingleType(typeof(int))
    )
    constructedParameters := ExternalMemberParameterTypes(constructedGeneric)
    constructedMatch := new ColumnarExternalInterfaceMethodMatch(
        constructedGeneric,
        "Execute",
        constructedGeneric.get_ReturnType(),
        constructedParameters
    )
    assert constructedMatch.Matched
    assert throws InvalidOperationException {
        _unsupportedConstructedMethod := new ColumnarExternalMethodDescriptor(
            queryProvider,
            constructedMatch,
            table
        )
    }

    additionDefinition := ExternalMemberRequiredType(
        "System.Numerics.IAdditionOperators`3, System.Private.CoreLib"
    )
    additionArguments := new Type[](3)
    additionArguments[0] = typeof(int)
    additionArguments[1] = typeof(int)
    additionArguments[2] = typeof(int)
    additionType := additionDefinition.MakeGenericType(additionArguments)
    additionParameters := new Type[](2)
    additionParameters[0] = typeof(int)
    additionParameters[1] = typeof(int)
    additionBinding := ExternalMemberRequiredBinding(
        additionType,
        "op_Addition",
        typeof(int),
        additionParameters,
        table
    )
    additionDescriptor := ExternalMemberRequiredDescriptor(additionBinding)
    assert additionDescriptor.Validate(table)
    assert additionDescriptor.MethodIsStatic

    genericStorage := StructuralImmutabilityRequiredIList(descriptor, "genericParametersValue")
    assert StructuralImmutabilityRejectsIListItemMutation(
        genericStorage,
        0,
        genericParameter
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarExternalInterfaceMethodMatchParameter))
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarExternalInterfaceMethodMatch))
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarExternalMethodParameterDescriptor))
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarExternalMethodGenericParameterDescriptor))
}

test "external descriptors snapshot required and optional custom modifier order" {
    table := new ColumnarStructuralTypeReferenceTable()
    modifierOwner := ExternalMemberBakeModifiedInterface("ExternalMemberModifiers")
    modifierParameters := ExternalMemberSingleType(typeof(int))
    modifierMethod := ExecutorRequiredMethod(modifierOwner, "Transform", modifierParameters)
    obsoleteMarker := ExternalMemberRequiredType("System.ObsoleteAttribute, System.Private.CoreLib")
    clsMarker := ExternalMemberRequiredType("System.CLSCompliantAttribute, System.Private.CoreLib")
    serializableMarker := ExternalMemberRequiredType("System.SerializableAttribute, System.Private.CoreLib")
    paramArrayMarker := ExternalMemberRequiredType("System.ParamArrayAttribute, System.Private.CoreLib")
    flagsMarker := ExternalMemberRequiredType("System.FlagsAttribute, System.Private.CoreLib")
    staMarker := ExternalMemberRequiredType("System.STAThreadAttribute, System.Private.CoreLib")
    actualReturnRequired := modifierMethod.get_ReturnParameter().GetRequiredCustomModifiers()
    actualReturnOptional := modifierMethod.get_ReturnParameter().GetOptionalCustomModifiers()
    actualParameter := modifierMethod.GetParameters()[0]
    actualParameterRequired := actualParameter.GetRequiredCustomModifiers()
    actualParameterOptional := actualParameter.GetOptionalCustomModifiers()
    if actualReturnRequired.Length != 2 {
        throw new InvalidOperationException("Expected two emitted return modreq entries.")
    }
    if actualReturnOptional.Length != 1 {
        throw new InvalidOperationException("Expected one emitted return modopt entry.")
    }
    if actualParameterRequired.Length != 1 {
        throw new InvalidOperationException("Expected one emitted parameter modreq entry.")
    }
    if actualParameterOptional.Length != 2 {
        throw new InvalidOperationException("Expected two emitted parameter modopt entries.")
    }
    if actualReturnRequired[0] != clsMarker || actualReturnRequired[1] != obsoleteMarker {
        throw new InvalidOperationException("Emitted return modreq order changed.")
    }
    if actualReturnOptional[0] != serializableMarker {
        throw new InvalidOperationException("Emitted return modopt order changed.")
    }
    if actualParameterRequired[0] != paramArrayMarker {
        throw new InvalidOperationException("Emitted parameter modreq order changed.")
    }
    if actualParameterOptional[0] != staMarker || actualParameterOptional[1] != flagsMarker {
        throw new InvalidOperationException("Emitted parameter modopt order changed.")
    }
    matchedSignature := new ColumnarExternalInterfaceMethodMatch(
        modifierMethod,
        modifierMethod.get_Name(),
        modifierMethod.get_ReturnType(),
        modifierParameters
    )
    assert matchedSignature.Matched
    modifierDescriptor := new ColumnarExternalMethodDescriptor(
        modifierOwner,
        matchedSignature,
        table
    )
    assert modifierDescriptor.Validate(table)
    assert modifierDescriptor.OpenReturn.RequiredModifierCount == 2
    assert modifierDescriptor.OpenReturn.OptionalModifierCount == 1
    assert modifierDescriptor.OpenReturn.RequiredModifier(0).RuntimeType == clsMarker
    assert modifierDescriptor.OpenReturn.RequiredModifier(1).RuntimeType == obsoleteMarker
    assert modifierDescriptor.OpenReturn.OptionalModifier(0).RuntimeType == serializableMarker
    assert modifierDescriptor.ParameterCount == 1
    assert actualParameterRequired.Length == 1
    assert actualParameterOptional.Length == 2
    assert modifierDescriptor.Parameter(0).Open.RequiredModifierCount == 1
    assert modifierDescriptor.Parameter(0).Effective.RequiredModifierCount == 1
    assert modifierDescriptor.Parameter(0).Open.OptionalModifierCount == 2
    assert modifierDescriptor.Parameter(0).Effective.OptionalModifierCount == 2
    assert modifierDescriptor.Parameter(0).Open.RequiredModifier(0).RuntimeType == paramArrayMarker
    assert modifierDescriptor.Parameter(0).Open.OptionalModifier(0).RuntimeType == staMarker
    assert modifierDescriptor.Parameter(0).Open.OptionalModifier(1).RuntimeType == flagsMarker
    assert modifierDescriptor.Parameter(0).Open.RequiredModifier(0).Validate(table)
    assert modifierDescriptor.Parameter(0).Effective.RequiredModifier(0).Validate(table)
    openModifiersStorage := StructuralImmutabilityRequiredIList(
        modifierDescriptor.Parameter(0).Open,
        "requiredModifiersValue"
    )
    assert StructuralImmutabilityRejectsIListItemMutation(
        openModifiersStorage,
        0,
        modifierDescriptor.Parameter(0).Open.RequiredModifier(0)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarExternalMethodCustomModifierDescriptor))
}

test "external selection and completeness retain declared iteration and first Methods policy" {
    voidType := ExecutorVoidType()
    noParameters := new Type[](0)
    left := ExternalMemberBakeInterface(
        "ExternalMemberOrderLeft",
        "Run",
        voidType,
        noParameters,
        (MethodAttributes)454
    )
    right := ExternalMemberBakeInterface(
        "ExternalMemberOrderRight",
        "Run",
        voidType,
        noParameters,
        (MethodAttributes)454
    )
    table := new ColumnarStructuralTypeReferenceTable()
    declaration := DeclarationPlanOverrideDeclaration("Run", "void", false)
    interfaces := new List<Type>()
    interfaces.Add(left)
    interfaces.Add(right)
    interfaces.Add(left)
    ColumnarExternalInterfaceMethodResolver.AddMatchingTargets(
        declaration,
        interfaces,
        "Run",
        voidType,
        noParameters,
        table
    )
    completion := declaration.Complete(null, voidType, noParameters)
    targets := completion.Targets
    assert declaration.ExternalTargetCount == 2
    assert targets.Length == 2
    assert targets[0].Target.get_DeclaringType() == left
    assert targets[1].Target.get_DeclaringType() == right
    assert targets[0].ExternalInterfaceBinding != null
    assert targets[1].ExternalInterfaceBinding != null

    firstBindingObject: object? = targets[0].ExternalInterfaceBinding
    firstBinding := (ColumnarExternalInterfaceMethodBinding)firstBindingObject
    bindingFirst := DeclarationPlanOverrideDeclaration("Run", "void", false)
    bindingFirst.AddExternalTarget(firstBinding)
    bindingFirst.AddExternalTarget(firstBinding.Target)
    bindingFirstCompletion := bindingFirst.Complete(null, voidType, noParameters)
    assert bindingFirst.ExternalTargetCount == 1
    assert bindingFirstCompletion.Targets[0].ExternalInterfaceBinding != null

    bareFirst := DeclarationPlanOverrideDeclaration("Run", "void", false)
    bareFirst.AddExternalTarget(firstBinding.Target)
    bareFirst.AddExternalTarget(firstBinding)
    bareFirstCompletion := bareFirst.Complete(null, voidType, noParameters)
    assert bareFirst.ExternalTargetCount == 1
    assert bareFirstCompletion.Targets[0].ExternalInterfaceBinding == null

    separateDomains := DeclarationPlanOverrideDeclaration("Run", "void", false)
    separateDomains.AddSourceTarget(firstBinding.Target)
    separateDomains.AddExternalTarget(firstBinding)
    separateCompletion := separateDomains.Complete(null, voidType, noParameters)
    assert separateDomains.SourceTargetCount == 1
    assert separateDomains.ExternalTargetCount == 1
    assert separateCompletion.Targets.Length == 2

    complete := SourceCallDefinition("ExternalMemberComplete", true)
    _completeRun := SourceCallDefineInstance(
        complete,
        "Run",
        noParameters,
        new int[](0),
        voidType,
        (MethodAttributes)6
    )
    assert ColumnarExternalInterfaceMethodResolver.InterfacesSatisfied(
        complete,
        ExternalMemberInterfaceList(left, null)
    )

    firstOnly := SourceCallDefinition("ExternalMemberFirstOnly", true)
    _wrongFirst := SourceCallDefineInstance(
        firstOnly,
        "Run",
        noParameters,
        new int[](0),
        typeof(bool),
        (MethodAttributes)6
    )
    _rightLater := SourceCallDefineInstance(
        firstOnly,
        "Run",
        noParameters,
        new int[](0),
        voidType,
        (MethodAttributes)6
    )
    assert !ColumnarExternalInterfaceMethodResolver.InterfacesSatisfied(
        firstOnly,
        ExternalMemberInterfaceList(left, null)
    )

    missingDefault := SourceCallDefinition("ExternalMemberDefaultStillRequired", true)
    assert !ColumnarExternalInterfaceMethodResolver.InterfacesSatisfied(
        missingDefault,
        ExternalMemberInterfaceList(left, null)
    )

    inherited := SourceCallInterfaceDefinition("ExternalMemberInheritedOnly")
    inherited.Builder.AddInterfaceImplementation(left)
    inheritedRuntime := IdentityBake(inherited.Builder)
    assert inheritedRuntime.GetMethods().Length == 0
    assert ColumnarExternalInterfaceMethodResolver.InterfacesSatisfied(
        missingDefault,
        ExternalMemberInterfaceList(inheritedRuntime, null)
    )

    rejectedTable := new ColumnarStructuralTypeReferenceTable()
    rejectedDeclaration := DeclarationPlanOverrideDeclaration("Run", "bool", false)
    ColumnarExternalInterfaceMethodResolver.AddMatchingTargets(
        rejectedDeclaration,
        ExternalMemberInterfaceList(left, null),
        "Run",
        typeof(bool),
        noParameters,
        rejectedTable
    )
    assert rejectedDeclaration.ExternalTargetCount == 0
    assert rejectedTable.RowCount == 0
}

test "external override execution validates every descriptor before any attachment" {
    voidType := ExecutorVoidType()
    noParameters := new Type[](0)
    firstInterface := ExternalMemberBakeInterface(
        "ExternalMemberAtomicFirst",
        "Run",
        voidType,
        noParameters,
        (MethodAttributes)454
    )
    secondInterface := ExternalMemberBakeInterface(
        "ExternalMemberAtomicSecond",
        "Run",
        voidType,
        noParameters,
        (MethodAttributes)454
    )
    table := new ColumnarStructuralTypeReferenceTable()
    declaration := DeclarationPlanOverrideDeclaration("Run", "void", false)
    ColumnarExternalInterfaceMethodResolver.AddMatchingTargets(
        declaration,
        ExternalMemberInterfaceList(firstInterface, secondInterface),
        "Run",
        voidType,
        noParameters,
        table
    )
    completion := declaration.Complete(null, voidType, noParameters)
    targets := completion.Targets
    assert targets.Length == 2
    malformedBindingObject: object? = targets[1].ExternalInterfaceBinding
    malformedBinding := (ColumnarExternalInterfaceMethodBinding)malformedBindingObject
    malformedDescriptor := ExternalMemberRequiredDescriptor(malformedBinding)
    returnTypeField := typeof(ColumnarExternalMethodSignatureTypeDescriptor).GetField("typeValue")
    if returnTypeField == null {
        throw new InvalidOperationException("The external effective-return identity field was not found.")
    }
    returnTypeField.SetValue(
        malformedDescriptor.EffectiveReturn,
        table.SelectRuntimeType(typeof(string))
    )
    assert !malformedDescriptor.Validate(table)

    owner := TypeOfCreateSourceBuilder("ExternalMemberAtomicOwner", false)
    owner.AddInterfaceImplementation(firstInterface)
    owner.AddInterfaceImplementation(secondInterface)
    body := owner.DefineMethod(
        "ImplementationBody",
        (MethodAttributes)486,
        voidType,
        noParameters
    )
    SourceInterfaceMethodEmitVoid(body)
    assert throws InvalidOperationException {
        completion.Apply(owner, body)
    }
    assert throws InvalidOperationException {
        completion.Apply(owner, body, table)
    }

    ownerRuntime := IdentityBake(owner)
    firstTargets := SourceInterfaceMethodMapTargets(ownerRuntime, firstInterface)
    secondTargets := SourceInterfaceMethodMapTargets(ownerRuntime, secondInterface)
    assert firstTargets.Count == 1
    assert secondTargets.Count == 1
    firstMapped := SourceInterfaceMethodRequiredMethod(firstTargets[0])
    secondMapped := SourceInterfaceMethodRequiredMethod(secondTargets[0])
    assert firstMapped.get_DeclaringType() == firstInterface
    assert secondMapped.get_DeclaringType() == secondInterface
    assert firstMapped.get_Name() == "Run"
    assert secondMapped.get_Name() == "Run"
}
