namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// These controls cross the new realization door with the same persisted ModuleBuilder family the
// emitter creates. Dynamic-assembly helpers are intentionally not used for the driver assertions:
// the persisted builder keeps the actual pre-bake TypeBuilder/FieldInfo companions that production
// hands to the structural table.
func IteratorRealizationControlPersistedModule(owner: TypeBuilder): ModuleBuilder {
    getModule := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "get_Module",
        System.Type.EmptyTypes
    )
    moduleObject := TypeOfRequiredInvocation(
        getModule,
        owner,
        new object[](0)
    )
    module := moduleObject as ModuleBuilder
    if module == null {
        throw new InvalidOperationException("The persisted realization fixture did not retain a ModuleBuilder.")
    }
    return module
}

func IteratorRealizationControlPersistedHost(fullName: string): TypeBuilder {
    runtimeOwner := ExternalGuardPersistedBuilder(fullName, 0, typeof(object))
    owner := runtimeOwner as TypeBuilder
    if owner == null {
        throw new InvalidOperationException("The persisted realization fixture did not return a TypeBuilder.")
    }
    return owner
}

func IteratorRealizationControlResolution(source: string): ColumnarSemanticTypeResolution {
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = source
    fileNames[0] = "iterator-realization-controls/source.nl"
    return SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        ""
    )
}

func IteratorRealizationControlFunction(
    probe: ColumnarIteratorShapeProbe,
    name: string,
    returnCanonical: string,
    typeParameterNames: string[],
    isAsync: bool,
    sourceFileId: int
): ColumnarFunctionInput {
    return IteratorRealizationControlFunctionWithSignature(
        probe,
        name,
        returnCanonical,
        IteratorNoStrings(),
        IteratorNoStrings(),
        typeParameterNames,
        isAsync,
        sourceFileId
    )
}

func IteratorRealizationControlFunctionWithSignature(
    probe: ColumnarIteratorShapeProbe,
    name: string,
    returnCanonical: string,
    parameterNames: string[],
    parameterCanonicals: string[],
    typeParameterNames: string[],
    isAsync: bool,
    sourceFileId: int
): ColumnarFunctionInput {
    return new ColumnarFunctionInput(
        name,
        returnCanonical,
        parameterNames,
        parameterCanonicals,
        probe.Nodes,
        probe.BodyRoot,
        false,
        typeParameterNames,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        isAsync,
        0,
        sourceFileId
    )
}

func IteratorRealizationControlFactory(owner: TypeBuilder, name: string): MethodBuilder {
    return owner.DefineMethod(
        name,
        (MethodAttributes)22,
        typeof(object),
        System.Type.EmptyTypes
    )
}

func IteratorRealizationControlSetGenericFactorySignature(
    factory: MethodBuilder,
    methodParameter: Type
) {
    typeArrayType := typeof(Type).MakeArrayType()
    typeArrayArrayType := typeArrayType.MakeArrayType()
    setSignatureParameterTypes := new Type[](6)
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
    openEnumerable := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    returnType := openEnumerable.MakeGenericType(
        IteratorRealizationControlSingleType(methodParameter)
    )
    parameterTypes := IteratorRealizationControlSingleType(methodParameter)
    emptyTypes := System.Type.EmptyTypes
    parameterModifiers := new Type[][](1)
    parameterModifiers[0] = emptyTypes
    arguments := new object[](6)
    IteratorSetObject(arguments, 0, returnType)
    IteratorSetObject(arguments, 1, emptyTypes)
    IteratorSetObject(arguments, 2, emptyTypes)
    IteratorSetObject(arguments, 3, parameterTypes)
    IteratorSetObject(arguments, 4, parameterModifiers)
    IteratorSetObject(arguments, 5, parameterModifiers)
    setSignature.Invoke(factory, arguments)
}

func IteratorRealizationControlSingleType(value: Type): Type[] {
    result := new Type[](1)
    result[0] = value
    return result
}

// PersistedAssemblyBuilder uses TypeBuilderImpl. Its public name lookup deliberately refuses fields
// before bake, but the real FieldBuilderImpl instances remain in its retained field inventory. Read
// that inventory only as a test witness: the realization result exposes the real machine builder,
// while the driver keeps its field builders private.
func IteratorRealizationControlActualRuntimeType(value: object): Type {
    getType := ExecutorRequiredMethod(
        typeof(object),
        "GetType",
        System.Type.EmptyTypes
    )
    result := TypeOfRequiredInvocation(getType, value, new object[](0))
    runtimeType := result as Type
    if runtimeType == null {
        throw new InvalidOperationException("The persisted realization fixture did not expose a runtime Type.")
    }
    return runtimeType
}

func IteratorRealizationControlRetainedFields(machine: TypeBuilder): IList {
    builderType := IteratorRealizationControlActualRuntimeType(machine)
    assert builderType.get_FullName() == "System.Reflection.Emit.TypeBuilderImpl"
    flags := BindingFlags.Instance | BindingFlags.NonPublic
    definitionsField := builderType.GetField("_fieldDefinitions", flags)
    if definitionsField == null {
        throw new InvalidOperationException("The persisted machine did not retain its field inventory.")
    }
    definitionsObject := definitionsField.GetValue(machine)
    definitions := definitionsObject as IList
    if definitions == null {
        throw new InvalidOperationException("The persisted machine field inventory was not an IList.")
    }
    return definitions
}

func IteratorRealizationControlRequiredRetainedField(
    machine: TypeBuilder,
    name: string
): FieldInfo {
    definitions := IteratorRealizationControlRetainedFields(machine)
    index := 0
    while index < definitions.Count {
        candidateObject := definitions[index]
        candidate := candidateObject as FieldInfo
        if candidate != null && candidate.get_Name() == name {
            return candidate
        }
        index += 1
    }
    throw new InvalidOperationException("The persisted machine did not retain the captured field '" + name + "'.")
}

func IteratorRealizationControlStableIdentity(
    sourceFileId: int,
    functionOrdinal: int,
    shape: ColumnarIteratorShape
): string {
    return "iterator:" + sourceFileId.ToString() + ":" + functionOrdinal.ToString() + ":" + shape.TypeName
}

// The table exposes its mutable source map as a field rather than a catalog door. These two typed
// static methods are invoked only through reflection after that exact object is read: they let the control
// inspect an observed registration without inventing a public catalog door or relying on an object
// to Dictionary conversion the current N# emitter does not model.
class IteratorRealizationControlRegistryAccess {
    static func Contains(map: Dictionary<string, Type>, stableIdentity: string): bool {
        return map.ContainsKey(stableIdentity)
    }

    static func Required(map: Dictionary<string, Type>, stableIdentity: string): Type {
        value := typeof(object)
        if !map.TryGetValue(stableIdentity, out value) {
            throw new InvalidOperationException("The realized iterator type was not registered under its stable identity.")
        }
        return value
    }

    static func Count(map: Dictionary<string, Type>): int {
        return map.Count
    }
}

func IteratorRealizationControlSourceTypeMapObject(
    table: ColumnarStructuralTypeReferenceTable
): object {
    flags := BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic
    field := typeof(ColumnarStructuralTypeReferenceTable).GetField(
        "sourceTypesByName",
        flags
    )
    if field == null {
        throw new InvalidOperationException("The structural table source identity map was not found.")
    }
    value := field.GetValue(table)
    if value == null {
        throw new InvalidOperationException("The structural table source identity map was null.")
    }
    return value
}

func IteratorRealizationControlRegistryMethod(name: string): MethodInfo {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(Dictionary<string, Type>)
    parameterTypes[1] = typeof(string)
    method := typeof(IteratorRealizationControlRegistryAccess).GetMethod(name, parameterTypes)
    if method == null {
        throw new InvalidOperationException("The registry inspection runner was not found.")
    }
    return method
}

func IteratorRealizationControlRegistryCountMethod(): MethodInfo {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(Dictionary<string, Type>)
    method := typeof(IteratorRealizationControlRegistryAccess).GetMethod("Count", parameterTypes)
    if method == null {
        throw new InvalidOperationException("The registry count inspection runner was not found.")
    }
    return method
}

func IteratorRealizationControlMapCount(mapObject: object): int {
    args := new object[](1)
    IteratorSetObject(args, 0, mapObject)
    result := TypeOfRequiredInvocation(
        IteratorRealizationControlRegistryCountMethod(),
        null,
        args
    )
    return Convert.ToInt32(result)
}

func IteratorRealizationControlMapContains(
    mapObject: object,
    stableIdentity: string
): bool {
    args := new object[](2)
    IteratorSetObject(args, 0, mapObject)
    IteratorSetObject(args, 1, stableIdentity)
    result := TypeOfRequiredInvocation(
        IteratorRealizationControlRegistryMethod("Contains"),
        null,
        args
    )
    return Convert.ToBoolean(result)
}

func IteratorRealizationControlRequiredType(
    mapObject: object,
    stableIdentity: string
): Type {
    args := new object[](2)
    IteratorSetObject(args, 0, mapObject)
    IteratorSetObject(args, 1, stableIdentity)
    result := TypeOfRequiredInvocation(
        IteratorRealizationControlRegistryMethod("Required"),
        null,
        args
    )
    selected := result as Type
    if selected == null {
        throw new InvalidOperationException("The registry inspection runner returned a non-Type companion.")
    }
    return selected
}

test "persisted realization preserves sync registration before an element decline and keeps async before registration" {
    syncSource := "import System.Collections.Generic\nfunc* Gen(): IEnumerable<IteratorRealizationUnresolvableElement> { yield 1 }\n"
    syncProbe := new ColumnarIteratorShapeProbe(
        syncSource,
        "IEnumerable<IteratorRealizationUnresolvableElement>",
        IteratorNoStrings(),
        IteratorNoStrings(),
        IteratorNoStrings(),
        false
    )
    assert syncProbe.Shape.Supported
    syncResolution := IteratorRealizationControlResolution(syncSource)
    syncHost := IteratorRealizationControlPersistedHost("IteratorRealizationSyncMissingHost")
    syncModule := IteratorRealizationControlPersistedModule(syncHost)
    syncFactory := IteratorRealizationControlFactory(syncHost, "Create")
    syncTypes := new List<TypeBuilder>()
    noNames := IteratorNoStrings()
    syncFunction := IteratorRealizationControlFunction(
        syncProbe,
        "Gen",
        "IEnumerable<IteratorRealizationUnresolvableElement>",
        noNames,
        false,
        701
    )
    syncFactoryIl := syncFactory.GetILGenerator()
    syncMethodTypeParameters := System.Type.EmptyTypes
    syncShape := syncProbe.Shape
    syncEnclosingType: Type? = null
    syncEnclosingFieldNames: string[]? = null
    syncEnclosingFields: FieldInfo[]? = null
    syncEnclosingFieldCanonicals: string[]? = null
    syncEnclosingMethodNames: string[]? = null
    syncEnclosingMethods: MethodInfo[]? = null
    syncResult: ColumnarIteratorRealizationResult = ColumnarIteratorRealization.EmitSync(
        syncModule,
        syncFunction,
        17,
        syncSource,
        syncResolution,
        syncFactoryIl,
        syncTypes,
        syncMethodTypeParameters,
        syncShape,
        "SyncMissing",
        syncEnclosingType,
        syncEnclosingFieldNames,
        syncEnclosingFields,
        syncEnclosingFieldCanonicals,
        syncEnclosingMethodNames,
        syncEnclosingMethods
    )
    assert !syncResult.Succeeded
    assert syncResult.DeclineSite == "emit.iterator.element-type"
    assert syncResult.DeclineMessage == "iterator element type 'IteratorRealizationUnresolvableElement' could not be resolved for 'SyncMissing'"
    assert syncResult.DeclineMember == "SyncMissing"
    assert syncTypes.Count == 0

    syncStableIdentity := IteratorRealizationControlStableIdentity(701, 17, syncShape)
    syncTable := syncResolution.StructuralTypeReferences
    syncMapObject := IteratorRealizationControlSourceTypeMapObject(syncTable)
    syncMachine := IteratorRealizationControlRequiredType(
        syncMapObject,
        syncStableIdentity
    )
    syncSelected := syncTable.SelectSynthesizedDefinition(syncStableIdentity, syncMachine)
    assert syncTable.ValidatePair(syncSelected, syncMachine)

    asyncSource := "import System.Collections.Generic\nasync func* Gen(): IAsyncEnumerable<IteratorRealizationUnresolvableElement> { yield 1 }\n"
    asyncProbe := new ColumnarIteratorShapeProbe(
        asyncSource,
        "IAsyncEnumerable<IteratorRealizationUnresolvableElement>",
        IteratorNoStrings(),
        IteratorNoStrings(),
        IteratorNoStrings(),
        false,
        true
    )
    assert asyncProbe.Shape.Supported
    asyncResolution := IteratorRealizationControlResolution(asyncSource)
    asyncHost := IteratorRealizationControlPersistedHost("IteratorRealizationAsyncMissingHost")
    asyncModule := IteratorRealizationControlPersistedModule(asyncHost)
    asyncFactory := IteratorRealizationControlFactory(asyncHost, "Create")
    asyncTypes := new List<TypeBuilder>()
    asyncFunction := IteratorRealizationControlFunction(
        asyncProbe,
        "Gen",
        "IAsyncEnumerable<IteratorRealizationUnresolvableElement>",
        noNames,
        true,
        702
    )
    asyncMap := IteratorRealizationControlSourceTypeMapObject(asyncResolution.StructuralTypeReferences)
    asyncMapCountBefore := IteratorRealizationControlMapCount(asyncMap)
    asyncFactoryIl := asyncFactory.GetILGenerator()
    asyncResult: ColumnarIteratorRealizationResult = ColumnarIteratorRealization.EmitAsync(
        asyncModule,
        asyncFunction,
        18,
        asyncSource,
        asyncResolution,
        asyncFactoryIl,
        asyncTypes
    )
    assert !asyncResult.Succeeded
    assert asyncResult.DeclineSite == "emit.iterator.element-type"
    assert asyncResult.DeclineMessage == "iterator element type 'IteratorRealizationUnresolvableElement' could not be resolved for 'Gen'"
    assert asyncResult.DeclineMember == "Gen"
    assert asyncTypes.Count == 0
    assert IteratorRealizationControlMapCount(asyncMap) == asyncMapCountBefore

    // AnalyzeShape observes ordinal zero. EmitAsync deliberately recomputes the machine name from
    // its supplied ordinal, so this is the actual registration identity whose absence matters.
    asyncStableIdentity := "iterator:702:18:<Gen>d__18"
    assert !IteratorRealizationControlMapContains(asyncMap, asyncStableIdentity)
}

test "persisted generic realization rebinds its retained machine-VAR field through the factory MVAR owner" {
    source := "import System.Collections.Generic\nfunc* Gen<T>(value: T): IEnumerable<T> { yield value }\n"
    probe := new ColumnarIteratorShapeProbe(
        source,
        "IEnumerable<T>",
        IteratorOne("value"),
        IteratorOne("T"),
        IteratorOne("T"),
        false
    )
    assert probe.Shape.Supported

    resolution := IteratorRealizationControlResolution(source)
    host := IteratorRealizationControlPersistedHost("IteratorRealizationGenericHost")
    module := IteratorRealizationControlPersistedModule(host)
    factory := IteratorRealizationControlFactory(host, "Gen")
    factoryMvar := StructuralIdentityFirstGenericMethodParameter(factory, "T")
    assert factoryMvar.get_IsGenericParameter()
    assert factoryMvar.get_IsGenericMethodParameter()
    assert !factoryMvar.get_IsGenericTypeParameter()
    IteratorRealizationControlSetGenericFactorySignature(factory, factoryMvar)

    function := IteratorRealizationControlFunctionWithSignature(
        probe,
        "Gen",
        "IEnumerable<T>",
        IteratorOne("value"),
        IteratorOne("T"),
        IteratorOne("T"),
        false,
        703
    )
    types := new List<TypeBuilder>()
    methodTypeParameters := IteratorRealizationControlSingleType(factoryMvar)
    factoryIl := factory.GetILGenerator()
    noShape: ColumnarIteratorShape? = null
    noEnclosingType: Type? = null
    noEnclosingFieldNames: string[]? = null
    noEnclosingFields: FieldInfo[]? = null
    noEnclosingFieldCanonicals: string[]? = null
    noEnclosingMethodNames: string[]? = null
    noEnclosingMethods: MethodInfo[]? = null
    result: ColumnarIteratorRealizationResult = ColumnarIteratorRealization.EmitSync(
        module,
        function,
        19,
        source,
        resolution,
        factoryIl,
        types,
        methodTypeParameters,
        noShape,
        "Gen",
        noEnclosingType,
        noEnclosingFieldNames,
        noEnclosingFields,
        noEnclosingFieldCanonicals,
        noEnclosingMethodNames,
        noEnclosingMethods
    )
    assert result.Succeeded
    assert types.Count == 1

    machine := types[0]
    machineDefinition: Type = machine
    machineParameters := machine.GetGenericArguments()
    assert machineParameters.Length == 1
    machineVar := machineParameters[0]
    assert machineVar.get_IsGenericParameter()
    assert machineVar.get_IsGenericTypeParameter()
    assert !machineVar.get_IsGenericMethodParameter()
    assert !Object.ReferenceEquals(machineVar, factoryMvar)

    rawValueField := IteratorRealizationControlRequiredRetainedField(machine, "value")
    assert Object.ReferenceEquals(rawValueField.get_DeclaringType(), machine)
    factoryMachine := machineDefinition.MakeGenericType(
        IteratorRealizationControlSingleType(factoryMvar)
    )
    factoryValueField := TypeBuilder.GetField(factoryMachine, rawValueField)
    assert Object.ReferenceEquals(factoryValueField.get_DeclaringType(), factoryMachine)

    // On this persisted unbaked family, the constructed owner carries the factory MVAR while its
    // real FieldType reports the machine VAR. Select the observed handle, not a reconstructed MVAR.
    factoryValueType := factoryValueField.get_FieldType()
    assert Object.ReferenceEquals(factoryValueType, machineVar)
    assert !Object.ReferenceEquals(factoryValueType, factoryMvar)
    table := resolution.StructuralTypeReferences
    selected := table.SelectRuntimeType(factoryValueType)
    assert table.ValidatePair(selected, factoryValueType)
    key := selected.Key
    if key == null {
        throw new InvalidOperationException("The realized factory field companion did not select a structural key.")
    }
    assert key.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert key.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.SynthesizedType
    assert key.GenericOwnerSourceFileId == 703
    assert key.GenericOwnerDeclaringTypeName == "iterator:703:19:<Gen>d__19"
    assert key.GenericOwnerMemberOrdinal == 19
    assert key.GenericParameterOrdinal == 0
}
