namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Runtime.InteropServices

func BaseBindingTwoTypes(first: Type, second: Type): Type[] {
    values := new Type[](2)
    values[0] = first
    values[1] = second
    return values
}

func BaseBindingRequiredKey(selected: ColumnarSelectedTypeReference, role: string): ColumnarStructuralTypeKey {
    key := selected.Key
    if key == null {
        throw new InvalidOperationException("The base binding has no " + role + " structural key.")
    }
    return key
}

func BaseBindingInvokeNoArguments(owner: Type, name: string): object? {
    noParameters := new Type[](0)
    constructor := ExecutorRequiredConstructor(owner, noParameters)
    instance := constructor.Invoke(new object[](0))
    if instance == null {
        throw new InvalidOperationException("The base-binding fixture instance was not created.")
    }
    method := ExecutorRequiredMethod(owner, name, noParameters)
    return method.Invoke(instance, new object[](0))
}

test "a closed external generic base match retains its actual owner and open signature" {
    comparerDefinition := ExternalMemberRequiredType(
        "System.Collections.Generic.Comparer`1, System.Private.CoreLib"
    )
    comparerOfInt := ExternalMemberCloseOne(comparerDefinition, typeof(int))
    parameters := BaseBindingTwoTypes(typeof(int), typeof(int))
    matchedBase := new ColumnarBaseMethodMatch(
        comparerOfInt,
        "Compare",
        typeof(int),
        parameters
    )
    assert matchedBase.Matched
    assert ColumnarConstructionPlanner.SameObject(matchedBase.RequiredFoundContext(), comparerOfInt)
    target := matchedBase.RequiredTarget()
    assert ColumnarConstructionPlanner.SameObject(target.get_DeclaringType(), comparerOfInt)
    matchedSignature := matchedBase.RequiredSignature()
    assert matchedSignature.ParameterCount == 2
    assert ColumnarConstructionPlanner.SameObject(matchedSignature.EffectiveReturnRuntimeType, typeof(int))
    assert ColumnarConstructionPlanner.SameObject(matchedSignature.EffectiveParameter(0).RuntimeType, typeof(int))

    table := new ColumnarStructuralTypeReferenceTable()
    binding := new ColumnarBaseMethodBinding(matchedBase, table)
    descriptor := binding.Descriptor
    assert ColumnarConstructionPlanner.SameObject(binding.ValidatedTarget(table), target)
    assert descriptor.Validate(table)
    assert ColumnarConstructionPlanner.SameObject(descriptor.OpenMethod.get_DeclaringType(), comparerDefinition)
    assert descriptor.ParameterCount == 2
    openParameter := descriptor.Parameter(0).Open
    effectiveParameter := descriptor.Parameter(0).Effective
    assert openParameter.RuntimeType.get_IsGenericParameter()
    assert ColumnarConstructionPlanner.SameObject(effectiveParameter.RuntimeType, typeof(int))
    openKey := BaseBindingRequiredKey(openParameter.Type, "open parameter")
    effectiveKey := BaseBindingRequiredKey(effectiveParameter.Type, "effective parameter")
    assert ColumnarExternalMethodSignatureRelation.KeysRelate(
        openKey,
        effectiveKey,
        BaseBindingRequiredKey(descriptor.OpenDeclaringType, "open declaring type"),
        BaseBindingRequiredKey(descriptor.DeclaringContext, "declaring context")
    )

    foreignTable := new ColumnarStructuralTypeReferenceTable()
    assert throws InvalidOperationException {
        binding.ValidatedTarget(foreignTable)
    }
}

test "the deriving base match records an ancestor and never captures a skipped builder root" {
    noParameters := new Type[](0)
    ancestor := new ColumnarBaseMethodMatch(
        typeof(ArgumentException),
        "ToString",
        typeof(string),
        noParameters
    )
    assert ancestor.Matched
    assert ColumnarConstructionPlanner.SameObject(ancestor.RequiredFoundContext(), typeof(Exception))
    assert ColumnarConstructionPlanner.SameObject(ancestor.RequiredTarget().get_DeclaringType(), typeof(Exception))

    skippedBuilder := TypeOfCreateSourceBuilder("BaseBindingSkippedBuilder", false)
    skipped := new ColumnarBaseMethodMatch(
        skippedBuilder,
        "ToString",
        typeof(string),
        noParameters
    )
    assert skipped.Matched
    assert ColumnarConstructionPlanner.SameObject(skipped.RequiredFoundContext(), typeof(object))
    assert ColumnarConstructionPlanner.SameObject(skipped.RequiredTarget().get_DeclaringType(), typeof(object))
    table := new ColumnarStructuralTypeReferenceTable()
    binding := new ColumnarBaseMethodBinding(skipped, table)
    assert binding.Descriptor.Validate(table)
    assert ColumnarConstructionPlanner.SameObject(binding.Descriptor.LookupContextRuntimeType, typeof(object))
}

test "metadata base binding retains observed cross-universe signature handles" {
    resolver := new PathAssemblyResolver(
        Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll")
    )
    context := new MetadataLoadContext(resolver, "System.Private.CoreLib")
    metadataCore := context.LoadFromAssemblyName("System.Private.CoreLib")
    metadataComparerDefinition := metadataCore.GetType(
        "System.Collections.Generic.Comparer`1"
    )
    metadataInt := metadataCore.GetType("System.Int32")
    if metadataComparerDefinition == null || metadataInt == null {
        throw new InvalidOperationException(
            "The metadata comparer fixture types were not found."
        )
    }
    metadataComparer := ExternalMemberCloseOne(
        metadataComparerDefinition,
        metadataInt
    )
    runtimeParameters := BaseBindingTwoTypes(typeof(int), typeof(int))
    matchedBase := new ColumnarBaseMethodMatch(
        metadataComparer,
        "Compare",
        typeof(int),
        runtimeParameters
    )
    assert matchedBase.Matched
    assert ColumnarBaseMethodMatch.SameTypeIdentity(metadataInt, typeof(int))
    assert !ColumnarConstructionPlanner.SameObject(metadataInt, typeof(int))
    matchedSignature := matchedBase.RequiredSignature()
    assert ColumnarConstructionPlanner.SameObject(
        matchedSignature.EffectiveReturnRuntimeType,
        metadataInt
    )
    assert ColumnarConstructionPlanner.SameObject(
        matchedSignature.EffectiveParameter(0).RuntimeType,
        metadataInt
    )
    assert !ColumnarConstructionPlanner.SameObject(
        matchedSignature.EffectiveParameter(0).RuntimeType,
        runtimeParameters[0]
    )

    table := new ColumnarStructuralTypeReferenceTable()
    binding := new ColumnarBaseMethodBinding(matchedBase, table)
    descriptor := binding.Descriptor
    assert descriptor.Validate(table)
    assert ColumnarConstructionPlanner.SameObject(
        descriptor.LookupContextRuntimeType,
        metadataComparer
    )
    assert ColumnarConstructionPlanner.SameObject(
        descriptor.EffectiveReturn.RuntimeType,
        metadataInt
    )
    assert ColumnarConstructionPlanner.SameObject(
        descriptor.Parameter(0).Effective.RuntimeType,
        metadataInt
    )
    assert descriptor.Parameter(0).Open.RuntimeType.get_IsGenericParameter()
    assert ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(
        descriptor.Parameter(0).Open,
        descriptor.Parameter(0).Effective,
        descriptor.OpenDeclaringType,
        descriptor.DeclaringContext
    )
    context.Dispose()
}

test "ordinary completion realizes the host declaration name and copied resolved signature" {
    parameterTypes := BaseBindingTwoTypes(typeof(string), typeof(string))
    row := DeclarationPlanOverrideDeclaration("Compare", "int", true)
    table := new ColumnarStructuralTypeReferenceTable()
    completion := row.Complete(
        typeof(StringComparer),
        "HostCompare",
        typeof(int),
        parameterTypes,
        table
    )
    assert completion.IsValid
    assert completion.DeclarationName == "HostCompare"
    assert ColumnarConstructionPlanner.SameObject(completion.DeclarationReturnType, typeof(int))
    assert completion.DeclarationParameterCount == 2
    assert ColumnarConstructionPlanner.SameObject(completion.DeclarationParameterType(0), typeof(string))
    assert completion.Targets.Length == 1
    assert completion.Targets[0].MemberName == "Compare"
    assert completion.Targets[0].BaseMethodBinding != null

    parameterTypes[0] = typeof(long)
    assert ColumnarConstructionPlanner.SameObject(completion.DeclarationParameterType(0), typeof(string))

    owner := TypeOfCreateSourceBuilder("BaseBindingRealizedHost", false)
    body := completion.DefineMethod(owner)
    assert body.get_Name() == "HostCompare"
    assert ColumnarConstructionPlanner.SameObject(body.get_ReturnType(), typeof(int))
    il := TypeOfMethodBuilderIL(body)
    il.Emit(OpCodes.Ldc_I4_0)
    il.Emit(OpCodes.Ret)
    runtimeOwner := IdentityBake(owner)
    runtimeBody := ExecutorRequiredMethod(
        runtimeOwner,
        "HostCompare",
        BaseBindingTwoTypes(typeof(string), typeof(string))
    )
    assert ColumnarConstructionPlanner.SameObject(runtimeBody.get_ReturnType(), typeof(int))

    legacy := row.Complete(
        typeof(StringComparer),
        typeof(int),
        BaseBindingTwoTypes(typeof(string), typeof(string))
    )
    assert legacy.IsValid
    assert throws InvalidOperationException {
        legacy.DefineMethod(TypeOfCreateSourceBuilder("BaseBindingLegacyHost", false))
    }
}

test "ordinary nonoverride realization retains the supplied wrapped return and ordered parameters without selection" {
    taskDefinition := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.Threading.Tasks.Task`1"
    )
    taskOfInt := ExternalMemberCloseOne(taskDefinition, typeof(int))
    parameters := BaseBindingTwoTypes(typeof(string), typeof(int))
    table := new ColumnarStructuralTypeReferenceTable()
    row := DeclarationPlanOverrideDeclaration("UnrelatedRowName", "unused", false)
    completion := row.Complete(
        null,
        "AsyncWorker",
        taskOfInt,
        parameters,
        table
    )
    assert completion.IsValid
    assert completion.MethodAttributes == 134
    assert completion.DeclarationName == "AsyncWorker"
    assert ColumnarConstructionPlanner.SameObject(completion.DeclarationReturnType, taskOfInt)
    assert completion.DeclarationParameterCount == 2
    assert ColumnarConstructionPlanner.SameObject(
        completion.DeclarationParameterType(0),
        typeof(string)
    )
    assert ColumnarConstructionPlanner.SameObject(
        completion.DeclarationParameterType(1),
        typeof(int)
    )
    assert table.RowCount == 0

    parameters[0] = typeof(long)
    parameters[1] = typeof(bool)
    assert ColumnarConstructionPlanner.SameObject(
        completion.DeclarationParameterType(0),
        typeof(string)
    )
    assert ColumnarConstructionPlanner.SameObject(
        completion.DeclarationParameterType(1),
        typeof(int)
    )
    parameterStorage := StructuralImmutabilityRequiredIList(
        completion,
        "declarationParameterTypesValue"
    )
    assert StructuralImmutabilityRejectsIListItemMutation(
        parameterStorage,
        0,
        typeof(long)
    )

    owner := TypeOfCreateSourceBuilder("BaseBindingAsyncDeclaration", false)
    body := completion.DefineMethod(owner)
    il := TypeOfMethodBuilderIL(body)
    il.Emit(OpCodes.Ldnull)
    il.Emit(OpCodes.Ret)
    runtimeOwner := IdentityBake(owner)
    runtimeBody := ExecutorRequiredMethod(
        runtimeOwner,
        "AsyncWorker",
        BaseBindingTwoTypes(typeof(string), typeof(int))
    )
    assert ColumnarConstructionPlanner.SameObject(runtimeBody.get_ReturnType(), taskOfInt)
    runtimeParameters := runtimeBody.GetParameters()
    assert runtimeParameters.Length == 2
    assert ColumnarConstructionPlanner.SameObject(
        runtimeParameters[0].get_ParameterType(),
        typeof(string)
    )
    assert ColumnarConstructionPlanner.SameObject(
        runtimeParameters[1].get_ParameterType(),
        typeof(int)
    )
    assert table.RowCount == 0
}

test "base binding validates independent runtime companions and immutable ordered storage" {
    comparerDefinition := ExternalMemberRequiredType(
        "System.Collections.Generic.Comparer`1, System.Private.CoreLib"
    )
    comparerOfInt := ExternalMemberCloseOne(comparerDefinition, typeof(int))
    parameters := BaseBindingTwoTypes(typeof(int), typeof(int))
    matchedBase := new ColumnarBaseMethodMatch(
        comparerOfInt,
        "Compare",
        typeof(int),
        parameters
    )
    table := new ColumnarStructuralTypeReferenceTable()
    binding := new ColumnarBaseMethodBinding(matchedBase, table)
    descriptor := binding.Descriptor
    assert descriptor.Validate(table)
    assert ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(
        descriptor.OpenReturn,
        descriptor.EffectiveReturn,
        descriptor.OpenDeclaringType,
        descriptor.DeclaringContext
    )

    runtimeTypeField := typeof(ColumnarExternalMethodSignatureTypeDescriptor).GetField(
        "runtimeTypeValue"
    )
    if runtimeTypeField == null {
        throw new InvalidOperationException(
            "The base effective-return runtime companion field was not found."
        )
    }
    runtimeTypeField.SetValue(descriptor.EffectiveReturn, typeof(string))
    assert ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(
        descriptor.OpenReturn,
        descriptor.EffectiveReturn,
        descriptor.OpenDeclaringType,
        descriptor.DeclaringContext
    )
    assert !descriptor.Validate(table)
    assert throws InvalidOperationException {
        _corruptedTarget := binding.ValidatedTarget(table)
    }

    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarBaseMethodMatchParameter)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarBaseMethodSignatureMatch)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarBaseMethodMatch)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarBaseMethodBinding)
    )
    signatureStorage := StructuralImmutabilityRequiredIList(
        matchedBase.RequiredSignature(),
        "parametersValue"
    )
    assert signatureStorage.Count == 2
    assert StructuralImmutabilityRejectsIListItemMutation(
        signatureStorage,
        0,
        matchedBase.RequiredSignature().EffectiveParameter(1)
    )
}

test "base binding participates in all-target validation before any override is attached" {
    noParameters := new Type[](0)
    matchedBase := new ColumnarBaseMethodMatch(
        typeof(Exception),
        "ToString",
        typeof(string),
        noParameters
    )
    table := new ColumnarStructuralTypeReferenceTable()
    binding := new ColumnarBaseMethodBinding(matchedBase, table)
    descriptor := binding.Descriptor
    runtimeTypeField := typeof(ColumnarExternalMethodSignatureTypeDescriptor).GetField(
        "runtimeTypeValue"
    )
    if runtimeTypeField == null {
        throw new InvalidOperationException(
            "The atomic base-return runtime companion field was not found."
        )
    }
    corruptedReturn := descriptor.EffectiveReturn
    voidType := ExecutorVoidType()
    runtimeTypeField.SetValue(corruptedReturn, voidType)
    assert ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(
        descriptor.OpenReturn,
        descriptor.EffectiveReturn,
        descriptor.OpenDeclaringType,
        descriptor.DeclaringContext
    )
    assert !descriptor.Validate(table)

    targets := new ColumnarResolvedMethodOverride[](2)
    targets[0] = new ColumnarResolvedMethodOverride(
        ColumnarMethodOverrideDeclaration.BaseTargetKind(),
        0,
        "ToString",
        "string",
        new string[](0),
        matchedBase.RequiredTarget()
    )
    targets[1] = new ColumnarResolvedMethodOverride(
        ColumnarMethodOverrideDeclaration.BaseTargetKind(),
        1,
        "ToString",
        "string",
        new string[](0),
        binding
    )
    completion := new ColumnarMethodOverrideCompletion(
        true,
        "",
        "",
        "BaseBindingAtomicOwner",
        198,
        "ImplementationBody",
        typeof(string),
        noParameters,
        targets
    )
    owner := TypeOfCreateSourceBuilder("BaseBindingAtomicOwner", false)
    ConstructionSetParent(owner, typeof(Exception))
    body := completion.DefineMethod(owner)
    il := TypeOfMethodBuilderIL(body)
    il.Emit(OpCodes.Ldstr, "base target was attached before validation completed")
    il.Emit(OpCodes.Ret)
    assert throws InvalidOperationException {
        completion.Apply(owner, body, table)
    }

    runtimeOwner := IdentityBake(owner)
    result := BaseBindingInvokeNoArguments(runtimeOwner, "ToString")
    assert Convert.ToString(result) != "base target was attached before validation completed"

    positiveTable := new ColumnarStructuralTypeReferenceTable()
    positiveMatch := new ColumnarBaseMethodMatch(
        typeof(Exception),
        "ToString",
        typeof(string),
        noParameters
    )
    positiveBinding := new ColumnarBaseMethodBinding(positiveMatch, positiveTable)
    positiveTargets := new ColumnarResolvedMethodOverride[](1)
    positiveTargets[0] = new ColumnarResolvedMethodOverride(
        ColumnarMethodOverrideDeclaration.BaseTargetKind(),
        0,
        "ToString",
        "string",
        new string[](0),
        positiveBinding
    )
    positiveCompletion := new ColumnarMethodOverrideCompletion(
        true,
        "",
        "",
        "BaseBindingAtomicPositiveOwner",
        198,
        "PositiveImplementation",
        typeof(string),
        noParameters,
        positiveTargets
    )
    positiveOwner := TypeOfCreateSourceBuilder("BaseBindingAtomicPositiveOwner", false)
    ConstructionSetParent(positiveOwner, typeof(Exception))
    positiveBody := positiveCompletion.DefineMethod(positiveOwner)
    positiveIl := TypeOfMethodBuilderIL(positiveBody)
    positiveIl.Emit(OpCodes.Ldstr, "validated base target attached")
    positiveIl.Emit(OpCodes.Ret)
    positiveCompletion.Apply(positiveOwner, positiveBody, positiveTable)
    positiveRuntimeOwner := IdentityBake(positiveOwner)
    positiveResult := BaseBindingInvokeNoArguments(positiveRuntimeOwner, "ToString")
    assert Convert.ToString(positiveResult) == "validated base target attached"
}
