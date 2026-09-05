namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func IteratorMemberRequiredType(name: string): Type {
    resolved := Type.GetType(name)
    if resolved == null {
        throw new InvalidOperationException("The iterator-member fixture could not resolve '" + name + "'.")
    }
    return resolved
}

func IteratorMemberSingleType(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func IteratorMemberCloseOne(definition: Type, argument: Type): Type {
    return definition.MakeGenericType(IteratorMemberSingleType(argument))
}

func IteratorMemberParameterMap(name: string, parameter: Type): Dictionary<string, Type> {
    parameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameters[name] = parameter
    return parameters
}

func IteratorMemberRequiredKey(
    selected: ColumnarSelectedTypeReference,
    description: string
): ColumnarStructuralTypeKey {
    key := selected.Key
    if key == null {
        throw new InvalidOperationException(description + " did not retain a structural key.")
    }
    return key
}

func IteratorMemberSyncContext(
    table: ColumnarStructuralTypeReferenceTable,
    elementType: Type
): ColumnarIteratorOverrideContext {
    enumerableDefinition := IteratorMemberRequiredType("System.Collections.Generic.IEnumerable`1")
    enumeratorDefinition := IteratorMemberRequiredType("System.Collections.Generic.IEnumerator`1")
    return ColumnarIteratorOverrideContext.ForSync(
        table,
        elementType,
        IteratorMemberCloseOne(enumerableDefinition, elementType),
        IteratorMemberCloseOne(enumeratorDefinition, elementType)
    )
}

func IteratorMemberAsyncContext(
    table: ColumnarStructuralTypeReferenceTable,
    elementType: Type
): ColumnarIteratorOverrideContext {
    enumerableDefinition := IteratorMemberRequiredType("System.Collections.Generic.IAsyncEnumerable`1")
    enumeratorDefinition := IteratorMemberRequiredType("System.Collections.Generic.IAsyncEnumerator`1")
    return ColumnarIteratorOverrideContext.ForAsync(
        table,
        elementType,
        IteratorMemberCloseOne(enumerableDefinition, elementType),
        IteratorMemberCloseOne(enumeratorDefinition, elementType)
    )
}

func IteratorMemberAssertBinding(
    binding: ColumnarIteratorMemberBinding,
    table: ColumnarStructuralTypeReferenceTable,
    expectedMethodName: string,
    expectedOpenOwner: Type,
    expectedContext: Type,
    expectedReturnType: Type,
    expectedParameterCount: int
): bool {
    assert binding.Validate(table)
    assert ColumnarConstructionPlanner.SameObject(binding.ValidatedTarget(table), binding.Target)
    assert binding.MethodName == expectedMethodName
    assert binding.OpenMethod.get_Name() == expectedMethodName
    assert binding.OpenMethod.get_DeclaringType() == expectedOpenOwner
    assert binding.OpenDeclaringType.RuntimeType == expectedOpenOwner
    assert binding.DeclaringContext.RuntimeType == expectedContext
    assert binding.Target.get_DeclaringType() == expectedContext
    assert binding.EffectiveReturn.RuntimeType == expectedReturnType
    assert binding.ParameterCount == expectedParameterCount
    assert binding.MethodGenericArity == 0
    assert !binding.MethodIsStatic
    assert binding.OpenReturn.RequiredModifierCount == binding.EffectiveReturn.RequiredModifierCount
    assert binding.OpenReturn.OptionalModifierCount == binding.EffectiveReturn.OptionalModifierCount
    if ColumnarConstructionPlanner.SameObject(expectedOpenOwner, expectedContext) {
        assert ColumnarConstructionPlanner.SameObject(binding.OpenMethod, binding.Target)
    } else {
        assert !ColumnarConstructionPlanner.SameObject(binding.OpenMethod, binding.Target)
    }
    return true
}

test "iterator binding derives all eleven open members contexts and effective signatures" {
    table := new ColumnarStructuralTypeReferenceTable()
    syncContext := IteratorMemberSyncContext(table, typeof(int))
    asyncContext := IteratorMemberAsyncContext(table, typeof(int))
    voidType := ColumnarTypeOfPlanner.RequiredVoidType()
    valueTaskType := IteratorMemberRequiredType("System.Threading.Tasks.ValueTask")
    valueTaskDefinition := IteratorMemberRequiredType("System.Threading.Tasks.ValueTask`1")
    valueTaskOfBool := IteratorMemberCloseOne(valueTaskDefinition, typeof(bool))
    enumeratorType := IteratorMemberRequiredType("System.Collections.IEnumerator")
    syncEnumeratorDefinition := IteratorMemberRequiredType("System.Collections.Generic.IEnumerator`1")
    syncEnumerableDefinition := IteratorMemberRequiredType("System.Collections.Generic.IEnumerable`1")
    asyncEnumeratorDefinition := IteratorMemberRequiredType("System.Collections.Generic.IAsyncEnumerator`1")
    asyncEnumerableDefinition := IteratorMemberRequiredType("System.Collections.Generic.IAsyncEnumerable`1")
    syncEnumerator := syncContext.EnumeratorContext
    syncEnumerable := syncContext.SequenceContext
    asyncEnumerator := asyncContext.EnumeratorContext
    asyncEnumerable := asyncContext.SequenceContext

    moveNext := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncMoveNext,
        "MoveNext",
        syncContext
    )
    assert IteratorMemberAssertBinding(
        moveNext,
        table,
        "MoveNext",
        IteratorMemberRequiredType("System.Collections.IEnumerator"),
        IteratorMemberRequiredType("System.Collections.IEnumerator"),
        typeof(bool),
        0
    )

    genericCurrent := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncGenericCurrent,
        "get_Current",
        syncContext
    )
    assert IteratorMemberAssertBinding(
        genericCurrent,
        table,
        "get_Current",
        syncEnumeratorDefinition,
        syncEnumerator,
        typeof(int),
        0
    )

    objectCurrent := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncObjectCurrent,
        "Current",
        syncContext
    )
    assert IteratorMemberAssertBinding(
        objectCurrent,
        table,
        "get_Current",
        IteratorMemberRequiredType("System.Collections.IEnumerator"),
        IteratorMemberRequiredType("System.Collections.IEnumerator"),
        typeof(object),
        0
    )

    reset := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncReset,
        "Reset",
        syncContext
    )
    assert IteratorMemberAssertBinding(
        reset,
        table,
        "Reset",
        IteratorMemberRequiredType("System.Collections.IEnumerator"),
        IteratorMemberRequiredType("System.Collections.IEnumerator"),
        voidType,
        0
    )

    dispose := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncDispose,
        "Dispose",
        syncContext
    )
    assert IteratorMemberAssertBinding(
        dispose,
        table,
        "Dispose",
        IteratorMemberRequiredType("System.IDisposable"),
        IteratorMemberRequiredType("System.IDisposable"),
        voidType,
        0
    )

    genericGetEnumerator := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncGenericGetEnumerator,
        "GetEnumerator",
        syncContext
    )
    assert IteratorMemberAssertBinding(
        genericGetEnumerator,
        table,
        "GetEnumerator",
        syncEnumerableDefinition,
        syncEnumerable,
        syncEnumerator,
        0
    )

    objectGetEnumerator := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncObjectGetEnumerator,
        "GetEnumerator",
        syncContext
    )
    assert IteratorMemberAssertBinding(
        objectGetEnumerator,
        table,
        "GetEnumerator",
        IteratorMemberRequiredType("System.Collections.IEnumerable"),
        IteratorMemberRequiredType("System.Collections.IEnumerable"),
        enumeratorType,
        0
    )

    asyncMoveNext := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.AsyncMoveNext,
        "MoveNextAsync",
        asyncContext
    )
    assert IteratorMemberAssertBinding(
        asyncMoveNext,
        table,
        "MoveNextAsync",
        asyncEnumeratorDefinition,
        asyncEnumerator,
        valueTaskOfBool,
        0
    )

    asyncCurrent := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.AsyncCurrent,
        "Current",
        asyncContext
    )
    assert IteratorMemberAssertBinding(
        asyncCurrent,
        table,
        "get_Current",
        asyncEnumeratorDefinition,
        asyncEnumerator,
        typeof(int),
        0
    )

    asyncDispose := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.AsyncDispose,
        "DisposeAsync",
        asyncContext
    )
    assert IteratorMemberAssertBinding(
        asyncDispose,
        table,
        "DisposeAsync",
        IteratorMemberRequiredType("System.IAsyncDisposable"),
        IteratorMemberRequiredType("System.IAsyncDisposable"),
        valueTaskType,
        0
    )

    asyncGetEnumerator := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.AsyncGetEnumerator,
        "GetAsyncEnumerator",
        asyncContext
    )
    assert IteratorMemberAssertBinding(
        asyncGetEnumerator,
        table,
        "GetAsyncEnumerator",
        asyncEnumerableDefinition,
        asyncEnumerable,
        asyncEnumerator,
        1
    )
    cancellationToken := IteratorMemberRequiredType("System.Threading.CancellationToken")
    assert asyncGetEnumerator.Parameter(0).Open.RuntimeType == cancellationToken
    assert asyncGetEnumerator.Parameter(0).Effective.RuntimeType == cancellationToken
}

test "generic iterator binding keeps external open VAR separate from machine VAR and factory MVAR" {
    table := new ColumnarStructuralTypeReferenceTable()
    machine := TypeOfCreateBuilder(
        "IteratorMemberGenericMachine",
        "ColumnarIteratorMember.GenericMachine",
        1
    )
    machineParameters := machine.GetGenericArguments()
    assert machineParameters.Length == 1
    machineParameter := machineParameters[0]
    table.RegisterIteratorType(
        41,
        7,
        "IteratorMemberGenericMachine",
        machine,
        IteratorMemberParameterMap("T", machineParameter)
    )

    factory := machine.DefineMethod(
        "Factory",
        (MethodAttributes)22,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        new Type[](0)
    )
    factoryParameter := StructuralIdentityFirstGenericMethodParameter(factory, "TFactory")
    table.RegisterGenericParameters(
        IteratorMemberParameterMap("TFactory", factoryParameter),
        ColumnarStructuralGenericOwnerIdentity.SourceMethod(41, 7)
    )

    context := IteratorMemberSyncContext(table, machineParameter)
    binding := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncGenericCurrent,
        "get_Current",
        context
    )
    assert binding.Validate(table)
    assert binding.Target.get_DeclaringType() == context.EnumeratorContext
    assert !ColumnarConstructionPlanner.SameObject(binding.Target, binding.OpenMethod)

    openOwnerArguments := binding.OpenMethod.get_DeclaringType().GetGenericArguments()
    assert openOwnerArguments.Length == 1
    assert ColumnarConstructionPlanner.SameObject(binding.OpenReturn.RuntimeType, openOwnerArguments[0])
    assert ColumnarConstructionPlanner.SameObject(binding.EffectiveReturn.RuntimeType, machineParameter)
    openKey := IteratorMemberRequiredKey(binding.OpenReturn.Type, "open iterator VAR")
    machineKey := IteratorMemberRequiredKey(binding.EffectiveReturn.Type, "machine iterator VAR")
    factoryKey := IteratorMemberRequiredKey(
        table.SelectRuntimeType(factoryParameter),
        "factory iterator MVAR"
    )
    assert openKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert openKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalType
    assert machineKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert machineKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.SynthesizedType
    assert machineKey.GenericOwnerSourceFileId == 41
    assert machineKey.GenericOwnerDeclaringTypeName == "iterator:41:7:IteratorMemberGenericMachine"
    assert machineKey.GenericOwnerMemberOrdinal == 7
    assert factoryKey.Kind == ColumnarStructuralTypeReferenceKind.MethodGenericParameter
    assert factoryKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.SourceMethod
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(openKey, machineKey)
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(machineKey, factoryKey)

    reboundReturn := binding.Target.get_ReturnType()
    assert reboundReturn.get_IsGenericParameter()
    assert !ColumnarConstructionPlanner.SameObject(reboundReturn, machineParameter)
    assert binding.Target.GetParameters().Length == 0
    assert throws NotSupportedException {
        reboundReturnParameter := binding.Target.get_ReturnParameter()
        _reboundReturnName := reboundReturnParameter.get_Name()
    }
}

test "iterator binding rejects a foreign table and a corrupted structural runtime pair" {
    table := new ColumnarStructuralTypeReferenceTable()
    machine := TypeOfCreateBuilder(
        "IteratorMemberValidationMachine",
        "ColumnarIteratorMember.ValidationMachine",
        1
    )
    machineParameters := machine.GetGenericArguments()
    machineParameter := machineParameters[0]
    table.RegisterIteratorType(
        52,
        3,
        "IteratorMemberValidationMachine",
        machine,
        IteratorMemberParameterMap("T", machineParameter)
    )
    context := IteratorMemberSyncContext(table, machineParameter)
    binding := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.SyncGenericCurrent,
        "get_Current",
        context
    )
    retainedTarget := binding.ValidatedTarget(table)
    foreignTable := new ColumnarStructuralTypeReferenceTable()
    assert !binding.Validate(foreignTable)
    assert throws InvalidOperationException {
        _foreignTarget := binding.ValidatedTarget(foreignTable)
    }

    runtimeTypeField := typeof(ColumnarExternalMethodSignatureTypeDescriptor).GetField("runtimeTypeValue")
    if runtimeTypeField == null {
        throw new InvalidOperationException("The iterator effective-return runtime companion field was not found.")
    }
    runtimeTypeField.SetValue(
        binding.EffectiveReturn,
        typeof(string)
    )
    assert ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(
        binding.OpenReturn,
        binding.EffectiveReturn,
        binding.OpenDeclaringType,
        binding.DeclaringContext
    )
    assert !binding.Validate(table)
    assert throws InvalidOperationException {
        _corruptedTarget := binding.ValidatedTarget(table)
    }
    assert ColumnarConstructionPlanner.SameObject(binding.Target, retainedTarget)
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarIteratorOverrideContext))
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(typeof(ColumnarIteratorMemberBinding))

    asyncBinding := new ColumnarIteratorMemberBinding(
        ColumnarIteratorOverrideTargetKind.AsyncGetEnumerator,
        "GetAsyncEnumerator",
        IteratorMemberAsyncContext(table, typeof(int))
    )
    parameterStorage := StructuralImmutabilityRequiredIList(asyncBinding, "parametersValue")
    assert parameterStorage.Count == 1
    assert StructuralImmutabilityRejectsIListItemMutation(
        parameterStorage,
        0,
        asyncBinding.Parameter(0)
    )
}

test "iterator lookup failures preserve method property and rebound phases without structural capture" {
    directTable := new ColumnarStructuralTypeReferenceTable()
    directContext := IteratorMemberSyncContext(directTable, typeof(int))
    assert directTable.RowCount == 0
    assert throws InvalidOperationException {
        _missingDirect := new ColumnarIteratorMemberBinding(
            ColumnarIteratorOverrideTargetKind.SyncReset,
            "MissingReset",
            directContext
        )
    }
    assert directTable.RowCount == 0
    assert throws NullReferenceException {
        _missingProperty := new ColumnarIteratorMemberBinding(
            ColumnarIteratorOverrideTargetKind.SyncObjectCurrent,
            "MissingCurrent",
            directContext
        )
    }
    assert directTable.RowCount == 0
    assert throws ArgumentNullException {
        _nullDirect := new ColumnarIteratorMemberBinding(
            ColumnarIteratorOverrideTargetKind.SyncReset,
            null,
            directContext
        )
    }
    assert directTable.RowCount == 0
    assert throws ArgumentNullException {
        _nullProperty := new ColumnarIteratorMemberBinding(
            ColumnarIteratorOverrideTargetKind.SyncObjectCurrent,
            null,
            directContext
        )
    }
    assert directTable.RowCount == 0

    runtimeReboundTable := new ColumnarStructuralTypeReferenceTable()
    runtimeReboundContext := IteratorMemberSyncContext(runtimeReboundTable, typeof(int))
    assert throws NullReferenceException {
        _missingRuntimeRebound := new ColumnarIteratorMemberBinding(
            ColumnarIteratorOverrideTargetKind.SyncGenericCurrent,
            "MissingCurrent",
            runtimeReboundContext
        )
    }
    assert runtimeReboundTable.RowCount == 0
    assert throws ArgumentNullException {
        _nullRuntimeRebound := new ColumnarIteratorMemberBinding(
            ColumnarIteratorOverrideTargetKind.SyncGenericCurrent,
            null,
            runtimeReboundContext
        )
    }
    assert runtimeReboundTable.RowCount == 0

    builderTable := new ColumnarStructuralTypeReferenceTable()
    machine := TypeOfCreateBuilder(
        "IteratorMemberMissingMachine",
        "ColumnarIteratorMember.MissingMachine",
        1
    )
    machineParameter := machine.GetGenericArguments()[0]
    builderTable.RegisterIteratorType(
        63,
        4,
        "IteratorMemberMissingMachine",
        machine,
        IteratorMemberParameterMap("T", machineParameter)
    )
    builderContext := IteratorMemberSyncContext(builderTable, machineParameter)
    assert throws NullReferenceException {
        _missingBuilderRebound := new ColumnarIteratorMemberBinding(
            ColumnarIteratorOverrideTargetKind.SyncGenericCurrent,
            "MissingCurrent",
            builderContext
        )
    }
    assert builderTable.RowCount == 0
}

test "iterator row rereads its lookup name and retains a valid target before attachment failure" {
    table := new ColumnarStructuralTypeReferenceTable()
    context := IteratorMemberSyncContext(table, typeof(int))
    owner := TypeOfCreateSourceBuilder("IteratorMemberApplyOrder", false)
    enumeratorType := IteratorMemberRequiredType("System.Collections.IEnumerator")
    owner.AddInterfaceImplementation(enumeratorType)
    foreignBodyOwner := TypeOfCreateSourceBuilder("IteratorMemberApplyOrderForeign", false)
    wrongBody := foreignBodyOwner.DefineMethod(
        "ResetBody",
        (MethodAttributes)486,
        typeof(bool),
        new Type[](0)
    )
    row := new ColumnarIteratorOverrideDeclaration(
        4,
        "System.Collections.IEnumerator.Reset",
        "MissingReset",
        ColumnarIteratorOverrideTargetKind.SyncReset
    )
    assert throws InvalidOperationException {
        row.Apply(context, owner, wrongBody)
    }
    assert row.ResolvedBinding == null
    assert row.ResolvedTarget == null

    row.LookupName = "Reset"
    assert throws ArgumentException {
        row.Apply(context, owner, wrongBody)
    }
    assert row.ResolvedBinding != null
    assert row.ResolvedTarget != null
    assert row.ResolvedBinding.Validate(table)
    assert row.ResolvedTarget.get_Name() == "Reset"

    incompatible := new ColumnarIteratorOverrideDeclaration(
        4,
        "System.Collections.IEnumerator.Reset",
        "MoveNext",
        ColumnarIteratorOverrideTargetKind.SyncReset
    )
    correctVoidBody := owner.DefineMethod(
        "CorrectResetBody",
        (MethodAttributes)486,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        new Type[](0)
    )
    assert throws InvalidOperationException {
        incompatible.Apply(context, owner, correctVoidBody)
    }
    assert incompatible.ResolvedBinding == null
    assert incompatible.ResolvedTarget == null
}

test "iterator override contexts snapshot handles without eager validation" {
    context := new ColumnarIteratorOverrideContext(null, null, null, null, false)
    assert context.StructuralTypeReferences == null
    assert context.ElementType == null
    assert context.SequenceContext == null
    assert context.EnumeratorContext == null
    assert !context.IsAsync
}
