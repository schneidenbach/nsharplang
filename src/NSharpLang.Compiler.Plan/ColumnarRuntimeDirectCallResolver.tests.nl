namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func RuntimeDirectCallIdentity(valueType: Type): string {
    identity := valueType.get_AssemblyQualifiedName()
    if identity == null || identity.Length == 0 {
        throw new InvalidOperationException("The runtime direct-call fixture requires an exact type identity.")
    }

    return identity
}

func RuntimeDirectCallVoidType(): Type {
    return TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Void")
}

func RuntimeDirectCallPlan(kind: ColumnarExternalCallKind, lookupType: Type, memberName: string, parameterTypes: Type[], returnType: Type): ColumnarExternalCallPlan {
    parameterTypeNames := new string[](parameterTypes.Length)
    index := 0
    while index < parameterTypes.Length {
        parameterTypeNames[index] = RuntimeDirectCallIdentity(parameterTypes[index])

        index = index + 1
    }

    return new ColumnarExternalCallPlan(true, kind, RuntimeDirectCallIdentity(lookupType), memberName, parameterTypeNames, RuntimeDirectCallIdentity(returnType))
}

func RequiredRuntimeDirectCallMethod(lookupType: Type, memberName: string, parameterTypes: Type[]): MethodInfo {
    method := lookupType.GetMethod(memberName, parameterTypes)
    if method == null {
        throw new InvalidOperationException("The runtime direct-call method fixture was not found.")
    }

    return method
}

func SelectRuntimeDirectCall(plan: ColumnarExternalCallPlan, lookupType: Type, expectedStatic: bool): ColumnarRuntimeDirectCallSelection {
    selection := ColumnarRuntimeDirectCallSelection.Empty()
    assert ColumnarRuntimeDirectCallResolver.TrySelect(plan, lookupType, expectedStatic, out selection)

    assert selection.Method != null
    return selection
}

func RuntimeDirectCallVarArgsMethod(): MethodInfo {
    builder := TypeOfCreateSourceBuilder("RuntimeDirectCallVarArgsProbe", false)

    callingConventionsType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Reflection.CallingConventions")

    voidType := RuntimeDirectCallVoidType()
    defineParameterTypes := new Type[](5)
    defineParameterTypes[0] = typeof(string)
    defineParameterTypes[1] = typeof(MethodAttributes)
    defineParameterTypes[2] = callingConventionsType
    defineParameterTypes[3] = typeof(Type)
    defineParameterTypes[4] = typeof(Type[])
    defineMethod := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineMethod", defineParameterTypes)

    defineArguments := new object[](5)
    ExecutorSetObject(defineArguments, 0, "VarArgsProbe")
    ExecutorSetObject(defineArguments, 1, (MethodAttributes)22)
    varArgsConvention := TypeOfRequiredStaticField(callingConventionsType, "VarArgs")

    ExecutorSetObject(defineArguments, 2, varArgsConvention)
    ExecutorSetObject(defineArguments, 3, voidType)
    ExecutorSetObject(defineArguments, 4, new Type[](0))
    methodValue := TypeOfRequiredInvocation(defineMethod, builder, defineArguments)

    methodBuilder := methodValue as MethodBuilder
    if methodBuilder == null {
        throw new InvalidOperationException("The runtime direct-call VarArgs method was not defined.")
    }

    il := TypeOfMethodBuilderIL(methodBuilder)
    il.Emit(OpCodes.Ret)
    createType := ExecutorRequiredMethod(typeof(TypeBuilder), "CreateType", new Type[](0))

    bakedValue := TypeOfRequiredInvocation(createType, builder, new object[](0))

    bakedType := bakedValue as Type
    if bakedType == null {
        throw new InvalidOperationException("The runtime direct-call VarArgs type was not baked.")
    }

    return RequiredRuntimeDirectCallMethod(bakedType, "VarArgsProbe", new Type[](0))
}

test "runtime direct calls materialize baked static and void plans exactly" {
    voidType := RuntimeDirectCallVoidType()
    stringArgumentNames := new string[](1)
    stringArgumentNames[0] = "System.String"
    typePlan := ColumnarExternalBindingPlans.GetStaticCallPlan("Type", "GetType", stringArgumentNames)

    typeSelection := SelectRuntimeDirectCall(typePlan, typeof(Type), true)

    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    assert typeSelection.Method != null
    assert typeSelection.LookupType == typeof(Type)
    assert typeSelection.DeclaringType == typeof(Type)
    assert typeSelection.ParameterTypes.Length == 1
    assert typeSelection.ParameterTypes[0] == typeof(string)
    assert typeSelection.ReturnType == typeof(Type)
    assert typeSelection.Kind == ColumnarExternalCallKind.Call
    assert typeSelection.IsStatic
    assert !typeSelection.ReceiverIsReference
    assert !typeSelection.UsesCallVirtual

    writerPlan := ColumnarExternalBindingPlans.GetInstanceCallPlan("System.IO.TextWriter", "WriteLine", stringArgumentNames)

    writerType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.TextWriter")

    writerSelection := SelectRuntimeDirectCall(writerPlan, writerType, false)

    assert writerSelection.Method != null
    assert writerSelection.DeclaringType == writerType
    assert writerSelection.ReturnType == voidType
    assert !writerSelection.IsStatic
    assert writerSelection.ReceiverIsReference
    assert writerSelection.UsesCallVirtual

    readerType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.StreamReader")
    readerPlan := ColumnarExternalBindingPlans.GetInstanceCallPlan("System.IO.StreamReader", "ReadToEndAsync", new string[](0))

    readerSelection := SelectRuntimeDirectCall(readerPlan, readerType, false)
    readerReturnType := Type.GetType(readerPlan.ReturnTypeName)

    assert readerReturnType != null
    assert readerSelection.Method != null
    assert readerSelection.LookupType == readerType
    assert readerSelection.ReturnType == readerReturnType
    assert readerSelection.ReceiverIsReference
    assert readerSelection.UsesCallVirtual
}

test "runtime direct calls close plan-pinned generic methods and reject mismatched or unpinned generics" {
    intArrayArguments := new string[](2)
    intArrayArguments[0] = "System.String"
    intArrayArguments[1] = "System.Int32[]"
    joinPlan := ColumnarExternalBindingPlans.GetStaticCallPlan("String", "Join", intArrayArguments)
    assert joinPlan.IsSupported
    assert joinPlan.TypeArgumentNames.Length == 1

    joinSelection := SelectRuntimeDirectCall(joinPlan, typeof(string), true)
    assert joinSelection.Method != null
    assert joinSelection.Method.get_IsGenericMethod(), "The selected Join handle must be the closed generic instantiation."
    assert !joinSelection.Method.get_IsGenericMethodDefinition(), "The selected Join handle must not stay an open definition."
    assert joinSelection.ParameterTypes.Length == 2
    assert joinSelection.ParameterTypes[0] == typeof(string)
    assert joinSelection.ParameterTypes[1] == typeof(IEnumerable<int>)
    assert joinSelection.ReturnType == typeof(string)
    assert joinSelection.Kind == ColumnarExternalCallKind.Call
    assert joinSelection.IsStatic
    assert !joinSelection.UsesCallVirtual

    // A pin that cannot reproduce the planned CLOSED signature declines: Join<string> closes to
    // IEnumerable<string>, never the planned IEnumerable<int>.
    mismatched := ColumnarExternalBindingPlans.GetStaticCallPlan("String", "Join", intArrayArguments)
    mismatchedArguments := new string[](1)
    mismatchedArguments[0] = "System.String, System.Private.CoreLib"
    mismatched.TypeArgumentNames = mismatchedArguments
    mismatchedSelection := ColumnarRuntimeDirectCallSelection.Empty()
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(mismatched, typeof(string), true, out mismatchedSelection), "A pinned closure that cannot reproduce the planned signature must decline."

    // Without a pin the original non-generic contract holds: no generic handle can be selected.
    unpinned := ColumnarExternalBindingPlans.GetStaticCallPlan("String", "Join", intArrayArguments)
    unpinned.TypeArgumentNames = new string[](0)
    unpinnedSelection := ColumnarRuntimeDirectCallSelection.Empty()
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(unpinned, typeof(string), true, out unpinnedSelection), "An unpinned plan must never select a generic method."
}

test "runtime direct calls preserve overload inherited interface and value receiver facts" {
    voidType := RuntimeDirectCallVoidType()
    charParameters := new Type[](1)
    charParameters[0] = typeof(char)
    indexOfPlan := RuntimeDirectCallPlan(ColumnarExternalCallKind.CallVirtual, typeof(string), "IndexOf", charParameters, typeof(int))

    indexOfSelection := SelectRuntimeDirectCall(indexOfPlan, typeof(string), false)

    assert indexOfSelection.Method != null
    assert indexOfSelection.ParameterTypes[0] == typeof(char)
    assert indexOfSelection.ReturnType == typeof(int)
    assert indexOfSelection.ReceiverIsReference
    assert indexOfSelection.UsesCallVirtual

    noParameters := new Type[](0)
    stringWriterType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.StringWriter")

    textWriterType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.TextWriter")

    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    inheritedPlan := RuntimeDirectCallPlan(ColumnarExternalCallKind.CallVirtual, stringWriterType, "WriteLine", stringParameters, voidType)

    inheritedSelection := SelectRuntimeDirectCall(inheritedPlan, stringWriterType, false)

    assert inheritedSelection.LookupType == stringWriterType
    assert inheritedSelection.DeclaringType == textWriterType
    assert inheritedSelection.Method != null
    assert inheritedSelection.ReceiverIsReference
    assert inheritedSelection.UsesCallVirtual

    disposableType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IDisposable")

    interfacePlan := RuntimeDirectCallPlan(ColumnarExternalCallKind.CallVirtual, disposableType, "Dispose", noParameters, voidType)

    interfaceSelection := SelectRuntimeDirectCall(interfacePlan, disposableType, false)

    assert interfaceSelection.DeclaringType == disposableType
    assert interfaceSelection.Method != null
    interfaceMethod := interfaceSelection.Method
    if interfaceMethod == null {
        throw new InvalidOperationException("The interface direct-call fixture lost its method.")
    }

    assert interfaceMethod.get_IsAbstract()
    assert interfaceSelection.ReceiverIsReference
    assert interfaceSelection.UsesCallVirtual

    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    valuePlan := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Index), "GetOffset", intParameters, typeof(int))

    valueSelection := SelectRuntimeDirectCall(valuePlan, typeof(Index), false)

    assert valueSelection.Method != null
    assert valueSelection.DeclaringType == typeof(Index)
    assert !valueSelection.IsStatic
    assert !valueSelection.ReceiverIsReference
    assert !valueSelection.UsesCallVirtual
}

test "runtime direct calls reject corrupt identities and staticness" {
    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    valid := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Type), "GetType", stringParameters, typeof(Type))

    rejected := ColumnarRuntimeDirectCallSelection.Empty()

    unsupported := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Type), "GetType", stringParameters, typeof(Type))

    unsupported.IsSupported = false
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(unsupported, typeof(Type), true, out rejected)

    noKind := RuntimeDirectCallPlan(ColumnarExternalCallKind.None, typeof(Type), "GetType", stringParameters, typeof(Type))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(noKind, typeof(Type), true, out rejected)

    wrongOwner := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(string), "GetType", stringParameters, typeof(Type))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(wrongOwner, typeof(Type), true, out rejected)

    wrongMember := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Type), "get_Assembly", stringParameters, typeof(Type))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(wrongMember, typeof(Type), true, out rejected)

    objectParameters := new Type[](1)
    objectParameters[0] = typeof(object)
    wrongParameter := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Type), "GetType", objectParameters, typeof(Type))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(wrongParameter, typeof(Type), true, out rejected)

    wrongReturn := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Type), "GetType", stringParameters, typeof(object))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(wrongReturn, typeof(Type), true, out rejected)

    malformedParameter := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Type), "GetType", stringParameters, typeof(Type))

    malformedParameter.ParameterTypeNames[0] = "[[not-a-type"
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(malformedParameter, typeof(Type), true, out rejected)

    malformedReturn := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Type), "GetType", stringParameters, typeof(Type))

    malformedReturn.ReturnTypeName = "[[not-a-type"
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(malformedReturn, typeof(Type), true, out rejected)

    virtualStatic := RuntimeDirectCallPlan(ColumnarExternalCallKind.CallVirtual, typeof(Type), "GetType", stringParameters, typeof(Type))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(virtualStatic, typeof(Type), true, out rejected)

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(valid, typeof(Type), false, out rejected)
}

test "runtime direct calls reject abstract direct and value virtual forms" {
    voidType := RuntimeDirectCallVoidType()
    noParameters := new Type[](0)
    disposableType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IDisposable")

    abstractDirect := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, disposableType, "Dispose", noParameters, voidType)

    rejected := ColumnarRuntimeDirectCallSelection.Empty()
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(abstractDirect, disposableType, false, out rejected)

    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    valueVirtual := RuntimeDirectCallPlan(ColumnarExternalCallKind.CallVirtual, typeof(Index), "GetOffset", intParameters, typeof(int))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(valueVirtual, typeof(Index), false, out rejected)

    inaccessible := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(object), "MemberwiseClone", noParameters, typeof(object))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(inaccessible, typeof(object), false, out rejected)
}

test "runtime direct calls reject byref generic and optional expansion shapes" {
    byRefInt := BoundByRefType()
    tryParseParameters := new Type[](2)
    tryParseParameters[0] = typeof(string)
    tryParseParameters[1] = byRefInt
    tryParse := RequiredRuntimeDirectCallMethod(typeof(int), "TryParse", tryParseParameters)

    assert tryParse.GetParameters()[1].get_ParameterType().get_IsByRef()
    byRefParameterPlan := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(int), "TryParse", tryParseParameters, typeof(bool))

    rejected := ColumnarRuntimeDirectCallSelection.Empty()
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(byRefParameterPlan, typeof(int), true, out rejected)

    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    spanItem := RequiredRuntimeDirectCallMethod(typeof(Span<int>), "get_Item", intParameters)

    byRefReturn := spanItem.get_ReturnType()
    assert byRefReturn.get_IsByRef()
    byRefReturnPlan := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Span<int>), "get_Item", intParameters, byRefReturn)

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(byRefReturnPlan, typeof(Span<int>), false, out rejected)

    noParameters := new Type[](0)
    genericDefinition := RequiredRuntimeDirectCallMethod(typeof(Array), "Empty", noParameters)

    genericArguments := new Type[](1)
    genericArguments[0] = typeof(int)
    constructedGeneric := genericDefinition.MakeGenericMethod(genericArguments)

    genericPlan := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(Array), "Empty", noParameters, typeof(int[]))

    definitionCandidates := new MethodInfo[](1)
    definitionCandidates[0] = genericDefinition
    assert !ColumnarRuntimeDirectCallResolver.TrySelectFromCandidates(genericPlan, typeof(Array), true, definitionCandidates, out rejected)

    constructedCandidates := new MethodInfo[](1)
    constructedCandidates[0] = constructedGeneric
    assert !ColumnarRuntimeDirectCallResolver.TrySelectFromCandidates(genericPlan, typeof(Array), true, constructedCandidates, out rejected)

    charParameters := new Type[](1)
    charParameters[0] = typeof(char)
    optionalExpansion := RuntimeDirectCallPlan(ColumnarExternalCallKind.CallVirtual, typeof(string), "Split", charParameters, typeof(string[]))

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(optionalExpansion, typeof(string), false, out rejected)
}

test "runtime direct calls reject wrong and ambiguous candidate handles" {
    mathType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Math")

    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    plan := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, mathType, "Abs", intParameters, typeof(int))

    exact := RequiredRuntimeDirectCallMethod(mathType, "Abs", intParameters)

    longParameters := new Type[](1)
    longParameters[0] = typeof(long)
    wrong := RequiredRuntimeDirectCallMethod(mathType, "Abs", longParameters)

    rejected := ColumnarRuntimeDirectCallSelection.Empty()

    wrongCandidates := new MethodInfo[](1)
    wrongCandidates[0] = wrong
    assert !ColumnarRuntimeDirectCallResolver.TrySelectFromCandidates(plan, mathType, true, wrongCandidates, out rejected)

    duplicateCandidates := new MethodInfo[](2)
    duplicateCandidates[0] = exact
    duplicateCandidates[1] = exact
    assert !ColumnarRuntimeDirectCallResolver.TrySelectFromCandidates(plan, mathType, true, duplicateCandidates, out rejected)

    mixedCandidates := new MethodInfo[](2)
    mixedCandidates[0] = wrong
    mixedCandidates[1] = exact
    selected := ColumnarRuntimeDirectCallSelection.Empty()
    assert ColumnarRuntimeDirectCallResolver.TrySelectFromCandidates(plan, mathType, true, mixedCandidates, out selected)

    assert selected.Method != null
    assert selected.ParameterTypes.Length == 1
    assert selected.ParameterTypes[0] == typeof(int)
    assert selected.ReturnType == typeof(int)
}

test "runtime direct calls reject VarArgs handles" {
    voidType := RuntimeDirectCallVoidType()
    method := RuntimeDirectCallVarArgsMethod()
    callingConvention := (int)method.get_CallingConvention()
    assert (callingConvention & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0

    declaringType := method.get_DeclaringType()
    if declaringType == null {
        throw new InvalidOperationException("The runtime direct-call VarArgs owner was not preserved.")
    }

    noParameters := new Type[](0)
    plan := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, declaringType, "VarArgsProbe", noParameters, voidType)

    rejected := ColumnarRuntimeDirectCallSelection.Empty()
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(plan, declaringType, true, out rejected)

    candidates := new MethodInfo[](1)
    candidates[0] = method
    assert !ColumnarRuntimeDirectCallResolver.TrySelectFromCandidates(plan, declaringType, true, candidates, out rejected)
}
