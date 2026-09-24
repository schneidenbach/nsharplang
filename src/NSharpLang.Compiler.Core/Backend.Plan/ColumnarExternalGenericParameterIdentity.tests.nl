namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// These contracts use external reflection metadata only. A generic parameter from an external
// method or type must carry its portable metadata owner, even when it enters through a table that
// also has source registrations. Source parameters remain a separate, emission-local family.
func ExternalGenericIdentityRequiredKey(
    selected: ColumnarSelectedTypeReference,
    description: string
): ColumnarStructuralTypeKey {
    key := selected.Key
    if key == null {
        throw new InvalidOperationException(description + " did not select a structural key.")
    }
    return key
}

func ExternalGenericIdentityRequiredExternalOwner(
    key: ColumnarStructuralTypeKey,
    description: string
): ColumnarStructuralExternalGenericOwnerIdentity {
    owner := key.ExternalGenericOwner
    if owner == null {
        throw new InvalidOperationException(description + " did not retain an external owner.")
    }
    return owner
}

func ExternalGenericIdentityRequiredMlcType(
    context: MetadataLoadContext,
    assemblyName: string,
    fullName: string
): Type {
    assembly := context.LoadFromAssemblyName(assemblyName)
    resolved := assembly.GetType(fullName)
    if resolved == null {
        throw new InvalidOperationException(
            "The metadata context did not define '" + fullName + "' in '" + assemblyName + "'."
        )
    }
    return resolved
}

func ExternalGenericIdentityRequiredRuntimeType(canonicalName: string): Type {
    resolved := Type.GetType(canonicalName)
    if resolved == null {
        throw new InvalidOperationException("The runtime did not define '" + canonicalName + "'.")
    }
    return resolved
}

func ExternalGenericIdentityRequiredAssemblyIdentity(runtimeType: Type): string {
    assembly := runtimeType.get_Assembly()
    name := assembly.GetName()
    identity := name.get_FullName()
    if identity == null {
        throw new InvalidOperationException("The external type did not have an assembly identity.")
    }
    return identity
}

func ExternalGenericIdentityModuleVersionId(method: MethodInfo): string {
    module := method.get_Module()
    return module.get_ModuleVersionId().ToString()
}

func ExternalGenericIdentityRequiredTypeParameter(
    definition: Type,
    ordinal: int
): Type {
    parameters := definition.GetGenericArguments()
    if ordinal < 0 || ordinal >= parameters.Length {
        throw new InvalidOperationException("The requested external type parameter was absent.")
    }
    parameter := parameters[ordinal]
    if !parameter.get_IsGenericParameter() || !parameter.get_IsGenericTypeParameter() || parameter.get_IsGenericMethodParameter() {
        throw new InvalidOperationException("The requested external parameter was not a VAR.")
    }
    return parameter
}

func ExternalGenericIdentityRequiredSelectOverload(
    owner: Type,
    callbackGenericArgumentCount: int
): MethodInfo {
    methods := owner.GetMethods((BindingFlags)24)
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == "Select" && candidate.get_IsStatic() && candidate.get_IsGenericMethodDefinition() {
            genericArguments := candidate.GetGenericArguments()
            parameters := candidate.GetParameters()
            if genericArguments.Length == 2 && parameters.Length == 2 {
                callbackType := parameters[1].get_ParameterType()
                if callbackType.get_IsGenericType() && callbackType.GetGenericArguments().Length == callbackGenericArgumentCount {
                    return candidate
                }
            }
        }
        index += 1
    }
    throw new InvalidOperationException("The requested Enumerable.Select overload was absent.")
}

func ExternalGenericIdentityRequiredMethodParameter(
    method: MethodInfo,
    ordinal: int
): Type {
    parameters := method.GetGenericArguments()
    if ordinal < 0 || ordinal >= parameters.Length {
        throw new InvalidOperationException("The requested external method parameter was absent.")
    }
    parameter := parameters[ordinal]
    if !parameter.get_IsGenericParameter() || parameter.get_IsGenericTypeParameter() || !parameter.get_IsGenericMethodParameter() {
        throw new InvalidOperationException("The requested external parameter was not an MVAR.")
    }
    return parameter
}

func ExternalGenericIdentityExternalParameterKey(
    key: ColumnarStructuralTypeKey,
    owner: ColumnarStructuralExternalGenericOwnerIdentity
): ColumnarStructuralTypeKey {
    return new ColumnarStructuralTypeKey(
        key.Kind,
        null,
        "",
        "",
        "",
        "",
        new string[](0),
        false,
        owner.Kind,
        -1,
        "",
        -1,
        key.GenericParameterOrdinal,
        owner,
        new ColumnarStructuralTypeKey[](0)
    )
}

func ExternalGenericIdentityRequiredNestedDictionaryType(): Type {
    dictionary := ExternalGenericIdentityDictionaryDefinition()
    nested := dictionary.GetNestedType("KeyCollection")
    if nested == null {
        throw new InvalidOperationException("Dictionary<TKey, TValue>.KeyCollection was absent.")
    }
    return nested
}

func ExternalGenericIdentityDictionaryDefinition(): Type {
    return ExternalGenericIdentityRequiredRuntimeType(
        "System.Collections.Generic.Dictionary`2, System.Private.CoreLib"
    )
}

func ExternalGenericIdentityListDefinition(): Type {
    return ExternalGenericIdentityRequiredRuntimeType(
        "System.Collections.Generic.List`1, System.Private.CoreLib"
    )
}

func ExternalGenericIdentityEnumerableType(): Type {
    return ExternalGenericIdentityRequiredRuntimeType("System.Linq.Enumerable, System.Linq")
}

test "external VAR and MVAR keys converge between runtime and metadata reflection with portable owner facts" {
    table := new ColumnarStructuralTypeReferenceTable()
    runtimeDictionary := ExternalGenericIdentityDictionaryDefinition()
    runtimeVar := ExternalGenericIdentityRequiredTypeParameter(runtimeDictionary, 0)
    runtimeEnumerable := ExternalGenericIdentityEnumerableType()
    runtimeSelect := ExternalGenericIdentityRequiredSelectOverload(runtimeEnumerable, 2)
    runtimeMvar := ExternalGenericIdentityRequiredMethodParameter(runtimeSelect, 0)

    runtimeVarSelected := table.SelectExternalSignatureType(runtimeVar)
    runtimeMvarSelected := table.SelectExternalSignatureType(runtimeMvar)
    runtimeVarKey := ExternalGenericIdentityRequiredKey(runtimeVarSelected, "runtime VAR")
    runtimeMvarKey := ExternalGenericIdentityRequiredKey(runtimeMvarSelected, "runtime MVAR")
    runtimeVarOwner := ExternalGenericIdentityRequiredExternalOwner(runtimeVarKey, "runtime VAR")
    runtimeMvarOwner := ExternalGenericIdentityRequiredExternalOwner(runtimeMvarKey, "runtime MVAR")

    assert runtimeVarKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert runtimeVarKey.EmissionIdentity == null
    assert runtimeVarKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalType
    assert runtimeVarKey.GenericParameterOrdinal == 0
    assert runtimeVarOwner.Kind == ColumnarStructuralGenericOwnerKind.ExternalType
    assert runtimeVarOwner.DeclaringType.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert runtimeVarOwner.DeclaringType.NestedNameCount == 1
    assert runtimeVarOwner.DeclaringType.NestedName(0) == "Dictionary`2"
    assert runtimeVarOwner.MethodMetadataToken == -1
    assert runtimeVarOwner.MethodName == ""
    assert runtimeVarOwner.MethodGenericArity == -1
    assert table.ValidatePair(runtimeVarSelected, runtimeVar)

    assert runtimeMvarKey.Kind == ColumnarStructuralTypeReferenceKind.MethodGenericParameter
    assert runtimeMvarKey.EmissionIdentity == null
    assert runtimeMvarKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalMethod
    assert runtimeMvarKey.GenericParameterOrdinal == 0
    assert runtimeMvarOwner.Kind == ColumnarStructuralGenericOwnerKind.ExternalMethod
    assert runtimeMvarOwner.DeclaringType.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert runtimeMvarOwner.DeclaringType.NestedNameCount == 1
    assert runtimeMvarOwner.DeclaringType.NestedName(0) == "Enumerable"
    assert runtimeMvarOwner.ModuleVersionId.Length > 0
    assert runtimeMvarOwner.MethodMetadataToken != -1
    assert runtimeMvarOwner.MethodName == "Select"
    assert runtimeMvarOwner.MethodGenericArity == 2
    assert runtimeMvarOwner.MethodIsStatic
    assert table.ValidatePair(runtimeMvarSelected, runtimeMvar)

    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        if context == null {
            throw new InvalidOperationException("The metadata context was unavailable.")
        }
        metadataDictionary := ExternalGenericIdentityRequiredMlcType(
            context,
            "System.Private.CoreLib",
            "System.Collections.Generic.Dictionary`2"
        )
        metadataVar := ExternalGenericIdentityRequiredTypeParameter(metadataDictionary, 0)
        metadataEnumerable := ExternalGenericIdentityRequiredMlcType(
            context,
            "System.Linq",
            "System.Linq.Enumerable"
        )
        metadataSelect := ExternalGenericIdentityRequiredSelectOverload(metadataEnumerable, 2)
        metadataMvar := ExternalGenericIdentityRequiredMethodParameter(metadataSelect, 0)
        assert metadataVar != runtimeVar
        assert metadataMvar != runtimeMvar
        metadataDictionaryIdentity := ExternalGenericIdentityRequiredAssemblyIdentity(metadataDictionary)
        runtimeDictionaryIdentity := ExternalGenericIdentityRequiredAssemblyIdentity(runtimeDictionary)
        metadataEnumerableIdentity := ExternalGenericIdentityRequiredAssemblyIdentity(metadataEnumerable)
        runtimeEnumerableIdentity := ExternalGenericIdentityRequiredAssemblyIdentity(runtimeEnumerable)
        metadataModuleVersionId := ExternalGenericIdentityModuleVersionId(metadataSelect)
        runtimeModuleVersionId := ExternalGenericIdentityModuleVersionId(runtimeSelect)
        assert metadataDictionaryIdentity == runtimeDictionaryIdentity
        assert metadataEnumerableIdentity == runtimeEnumerableIdentity
        assert metadataModuleVersionId == runtimeModuleVersionId
        assert metadataSelect.get_MetadataToken() == runtimeSelect.get_MetadataToken()

        metadataVarSelected := table.SelectExternalSignatureType(metadataVar)
        metadataMvarSelected := table.SelectExternalSignatureType(metadataMvar)
        metadataVarKey := ExternalGenericIdentityRequiredKey(metadataVarSelected, "metadata VAR")
        metadataMvarKey := ExternalGenericIdentityRequiredKey(metadataMvarSelected, "metadata MVAR")
        assert Object.ReferenceEquals(runtimeVarKey, metadataVarKey)
        assert Object.ReferenceEquals(runtimeMvarKey, metadataMvarKey)
        assert ColumnarStructuralTypeKeyFacts.KeysEqual(runtimeVarKey, metadataVarKey)
        assert ColumnarStructuralTypeKeyFacts.KeysEqual(runtimeMvarKey, metadataMvarKey)
        assert table.ValidatePair(metadataVarSelected, metadataVar)
        assert table.ValidatePair(metadataMvarSelected, metadataMvar)
    } finally {
        scan.Dispose()
    }
}

test "external generic owners distinguish type slots, overloaded MVARs, and flattened nested slots" {
    table := new ColumnarStructuralTypeReferenceTable()
    dictionary := ExternalGenericIdentityDictionaryDefinition()
    list := ExternalGenericIdentityListDefinition()
    dictionaryFirst := ExternalGenericIdentityRequiredTypeParameter(dictionary, 0)
    dictionarySecond := ExternalGenericIdentityRequiredTypeParameter(dictionary, 1)
    listFirst := ExternalGenericIdentityRequiredTypeParameter(list, 0)
    dictionaryFirstSelected := table.SelectExternalSignatureType(dictionaryFirst)
    dictionarySecondSelected := table.SelectExternalSignatureType(dictionarySecond)
    listFirstSelected := table.SelectExternalSignatureType(listFirst)
    dictionaryFirstKey := ExternalGenericIdentityRequiredKey(
        dictionaryFirstSelected,
        "Dictionary first VAR"
    )
    dictionarySecondKey := ExternalGenericIdentityRequiredKey(
        dictionarySecondSelected,
        "Dictionary second VAR"
    )
    listFirstKey := ExternalGenericIdentityRequiredKey(
        listFirstSelected,
        "List first VAR"
    )
    assert dictionaryFirstKey.GenericParameterOrdinal == 0
    assert dictionarySecondKey.GenericParameterOrdinal == 1
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(dictionaryFirstKey, dictionarySecondKey)
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(dictionaryFirstKey, listFirstKey)

    enumerable := ExternalGenericIdentityEnumerableType()
    unarySelect := ExternalGenericIdentityRequiredSelectOverload(enumerable, 2)
    indexedSelect := ExternalGenericIdentityRequiredSelectOverload(enumerable, 3)
    unaryParameter := ExternalGenericIdentityRequiredMethodParameter(unarySelect, 0)
    indexedParameter := ExternalGenericIdentityRequiredMethodParameter(indexedSelect, 0)
    unarySelected := table.SelectExternalSignatureType(unaryParameter)
    indexedSelected := table.SelectExternalSignatureType(indexedParameter)
    unaryKey := ExternalGenericIdentityRequiredKey(
        unarySelected,
        "unary Select MVAR"
    )
    indexedKey := ExternalGenericIdentityRequiredKey(
        indexedSelected,
        "indexed Select MVAR"
    )
    unaryOwner := ExternalGenericIdentityRequiredExternalOwner(unaryKey, "unary Select MVAR")
    indexedOwner := ExternalGenericIdentityRequiredExternalOwner(indexedKey, "indexed Select MVAR")
    assert unaryOwner.MethodName == "Select"
    assert indexedOwner.MethodName == "Select"
    assert unaryOwner.MethodGenericArity == 2
    assert indexedOwner.MethodGenericArity == 2
    assert unaryOwner.MethodMetadataToken != indexedOwner.MethodMetadataToken
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(unaryKey, indexedKey)

    nested := ExternalGenericIdentityRequiredNestedDictionaryType()
    nestedParameters := nested.GetGenericArguments()
    assert nestedParameters.Length == 2
    nestedFirst := ExternalGenericIdentityRequiredTypeParameter(nested, 0)
    nestedSecond := ExternalGenericIdentityRequiredTypeParameter(nested, 1)
    nestedFirstSelected := table.SelectExternalSignatureType(nestedFirst)
    nestedSecondSelected := table.SelectExternalSignatureType(nestedSecond)
    nestedFirstKey := ExternalGenericIdentityRequiredKey(
        nestedFirstSelected,
        "nested first flattened VAR"
    )
    nestedSecondKey := ExternalGenericIdentityRequiredKey(
        nestedSecondSelected,
        "nested second flattened VAR"
    )
    nestedOwner := ExternalGenericIdentityRequiredExternalOwner(nestedFirstKey, "nested first flattened VAR")
    assert nestedFirstKey.GenericParameterOrdinal == 0
    assert nestedSecondKey.GenericParameterOrdinal == 1
    assert nestedOwner.DeclaringType.NestedNameCount == 2
    assert nestedOwner.DeclaringType.NestedName(0) == "Dictionary`2"
    assert nestedOwner.DeclaringType.NestedName(1) == "KeyCollection"
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(nestedFirstKey, nestedSecondKey)
    assert table.ValidatePair(nestedFirstSelected, nestedFirst)
    assert table.ValidatePair(nestedSecondSelected, nestedSecond)
}

test "explicit external signature selection ignores forged legacy source registration while genuine source ownership remains local" {
    table := new ColumnarStructuralTypeReferenceTable()
    externalDefinition := ExternalGenericIdentityDictionaryDefinition()
    externalParameter := ExternalGenericIdentityRequiredTypeParameter(externalDefinition, 0)
    table.RegisterSourceDefinition("Legacy.Forged.ExternalVar", externalParameter, false)

    legacySelected := table.SelectSourceDefinition("Legacy.Forged.ExternalVar", externalParameter)
    externalSelected := table.SelectExternalSignatureType(externalParameter)
    runtimeSelected := table.SelectRuntimeType(externalParameter)
    legacyKey := ExternalGenericIdentityRequiredKey(legacySelected, "legacy forged source selection")
    externalKey := ExternalGenericIdentityRequiredKey(externalSelected, "external signature selection")
    runtimeKey := ExternalGenericIdentityRequiredKey(runtimeSelected, "ordinary external selection")
    assert legacyKey.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition
    assert externalKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert externalKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalType
    externalOwner := ExternalGenericIdentityRequiredExternalOwner(externalKey, "external signature selection")
    assert externalOwner.Kind == ColumnarStructuralGenericOwnerKind.ExternalType
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(legacyKey, externalKey)
    assert Object.ReferenceEquals(externalKey, runtimeKey)
    assert table.ValidatePair(legacySelected, externalParameter)
    assert table.ValidatePair(externalSelected, externalParameter)

    forgedParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    forgedParameters[externalParameter.get_Name()] = externalParameter
    table.RegisterGenericParameters(
        forgedParameters,
        ColumnarStructuralGenericOwnerIdentity.SourceType(
            402,
            "Legacy.Forged.ParameterOwner"
        )
    )
    sourceLabelledSelected := table.SelectRuntimeType(externalParameter)
    externalAfterRegistration := table.SelectExternalSignatureType(externalParameter)
    sourceLabelledKey := ExternalGenericIdentityRequiredKey(
        sourceLabelledSelected,
        "source-labelled metadata VAR"
    )
    externalAfterRegistrationKey := ExternalGenericIdentityRequiredKey(
        externalAfterRegistration,
        "external metadata VAR after source registration"
    )
    assert sourceLabelledKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert sourceLabelledKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.SourceType
    assert Object.ReferenceEquals(sourceLabelledKey.EmissionIdentity, table.Identity)
    assert externalAfterRegistrationKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalType
    assert externalAfterRegistrationKey.EmissionIdentity == null
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(
        sourceLabelledKey,
        externalAfterRegistrationKey
    )
    assert table.ValidatePair(sourceLabelledSelected, externalParameter)
    assert table.ValidatePair(externalAfterRegistration, externalParameter)

    sourceDefinition := TypeOfCreateBuilder(
        "Models.ActualSource`1",
        "ExternalGenericIdentity.ActualSource",
        1
    )
    table.RegisterSourceDefinition("Models.ActualSource", sourceDefinition, false)
    names := new string[](1)
    names[0] = "T"
    table.RegisterTypeGenericParameters(401, "Models.ActualSource", names, sourceDefinition)
    sourceParameter := ExternalGenericIdentityRequiredTypeParameter(sourceDefinition, 0)
    sourceSelected := table.SelectRuntimeType(sourceParameter)
    sourceKey := ExternalGenericIdentityRequiredKey(sourceSelected, "registered source VAR")
    assert sourceKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert Object.ReferenceEquals(sourceKey.EmissionIdentity, table.Identity)
    assert sourceKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.SourceType
    assert sourceKey.GenericOwnerSourceFileId == 401
    assert sourceKey.GenericOwnerDeclaringTypeName == "Models.ActualSource"
    assert sourceKey.GenericParameterOrdinal == 0
    assert sourceKey.ExternalGenericOwner == null
    assert table.ValidatePair(sourceSelected, sourceParameter)
}

test "external owner keys reject foreign tables and forged facts, refuse unregistered builders, and remain readonly" {
    table := new ColumnarStructuralTypeReferenceTable()
    enumerable := ExternalGenericIdentityEnumerableType()
    method := ExternalGenericIdentityRequiredSelectOverload(enumerable, 2)
    parameter := ExternalGenericIdentityRequiredMethodParameter(method, 0)
    selected := table.SelectExternalSignatureType(parameter)
    key := ExternalGenericIdentityRequiredKey(selected, "external MVAR")
    owner := ExternalGenericIdentityRequiredExternalOwner(key, "external MVAR")
    assert table.ValidatePair(selected, parameter)

    foreignTable := new ColumnarStructuralTypeReferenceTable()
    foreignSelected := foreignTable.SelectExternalSignatureType(parameter)
    assert !table.ValidatePair(foreignSelected, parameter)

    forgedOwner := new ColumnarStructuralExternalGenericOwnerIdentity(
        owner.Kind,
        owner.DeclaringType,
        owner.ModuleVersionId + ".forged",
        owner.MethodMetadataToken,
        owner.MethodName,
        owner.MethodGenericArity,
        owner.MethodCallingConvention,
        owner.MethodIsStatic
    )
    forgedKey := ExternalGenericIdentityExternalParameterKey(key, forgedOwner)
    forgedSelected := new ColumnarSelectedTypeReference(
        table.Identity,
        forgedKey,
        parameter,
        true,
        null,
        ""
    )
    assert !table.ValidatePair(forgedSelected, parameter)

    unregisteredBuilder := TypeOfCreateBuilder(
        "Models.UnregisteredExternalShape`1",
        "ExternalGenericIdentity.UnregisteredBuilder",
        1
    )
    unregisteredParameter := ExternalGenericIdentityRequiredTypeParameter(unregisteredBuilder, 0)
    assert throws InvalidOperationException {
        table.SelectRuntimeType(unregisteredParameter)
    }
    assert throws InvalidOperationException {
        table.SelectExternalSignatureType(unregisteredParameter)
    }

    ownerIdentityType := typeof(ColumnarStructuralExternalGenericOwnerIdentity)
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(ownerIdentityType)
}
