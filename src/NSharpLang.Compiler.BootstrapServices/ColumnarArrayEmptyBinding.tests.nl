namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func ArrayEmptyBindingPlan(ownerName: string, typeArgumentName: string, argumentTypeNames: string[]): ColumnarExternalCallPlan {
    typeArguments := new string[](1)
    typeArguments[0] = typeArgumentName
    return ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan(ownerName, "Empty", typeArguments, argumentTypeNames)
}

func ArrayEmptyBindingRejected(source: string, factSource: string, bindings: ColumnarFragmentBindings, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): ColumnarCodePlan {
    tree := DirectCallParsedTree(source)
    ExternalStampScope(tree, factSource)
    return DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)
}

func ArrayEmptyBindingInvokePlan(plan: ColumnarCodePlan): object {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := typeof(DynamicMethod).GetConstructor(constructorTypes)
    if constructorInfo == null {
        throw new InvalidOperationException("Required DynamicMethod constructor was not found.")
    }

    constructorArguments := new object[](3)
    ExecutorSetObject(constructorArguments, 0, "ArrayEmptyBindingProbe")
    ExecutorSetObject(constructorArguments, 1, typeof(string[]))
    ExecutorSetObject(constructorArguments, 2, new Type[](0))
    dynamicMethod := (DynamicMethod)constructorInfo.Invoke(constructorArguments)
    il := dynamicMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(plan, il)
    il.Emit(OpCodes.Ret)
    target: object? = null
    result := dynamicMethod.Invoke(target, new object[](0))
    if result == null {
        throw new InvalidOperationException("Array.Empty<string>() returned null unexpectedly.")
    }
    return result
}

test "explicit generic external binding pins the exact Array Empty string closure" {
    noArguments := new string[](0)
    shortPlan := ArrayEmptyBindingPlan("Array", "System.String", noArguments)
    qualifiedPlan := ArrayEmptyBindingPlan("System.Array", "System.String", noArguments)

    assert shortPlan.IsSupported
    assert qualifiedPlan.IsSupported
    assert shortPlan.Kind == ColumnarExternalCallKind.Call
    assert shortPlan.DeclaringTypeName == "System.Array, System.Private.CoreLib"
    assert shortPlan.MemberName == "Empty"
    assert shortPlan.ParameterTypeNames.Length == 0
    assert shortPlan.TypeArgumentNames.Length == 1
    assert shortPlan.TypeArgumentNames[0] == "System.String, System.Private.CoreLib"
    assert shortPlan.ReturnTypeName == "System.String[], System.Private.CoreLib"
    assert qualifiedPlan.DeclaringTypeName == shortPlan.DeclaringTypeName
    assert qualifiedPlan.TypeArgumentNames[0] == shortPlan.TypeArgumentNames[0]
    assert qualifiedPlan.ReturnTypeName == shortPlan.ReturnTypeName

    selection := ColumnarRuntimeDirectCallSelection.Empty()
    assert ColumnarRuntimeDirectCallResolver.TrySelect(shortPlan, typeof(Array), true, out selection)
    method := selection.Method
    assert method != null
    assert method.get_IsGenericMethod()
    assert !method.get_IsGenericMethodDefinition()
    methodArguments := method.GetGenericArguments()
    assert methodArguments.Length == 1
    assert methodArguments[0] == typeof(string)
    assert selection.ParameterTypes.Length == 0
    assert selection.ReturnType == typeof(string[])

    target: object? = null
    first := method.Invoke(target, new object[](0))
    second := method.Invoke(target, new object[](0))
    assert first != null
    assert Object.ReferenceEquals(first, second)
}

test "direct call planner emits bare and qualified Array Empty string with the same singleton" {
    shortTree := DirectCallParsedTree("Array.Empty<string>()")
    ExternalStampScope(shortTree, "import System")
    shortPlan := DirectCallPlan(shortTree, ColumnarRangePlannerEmptyBindings())

    qualifiedTree := DirectCallParsedTree("System.Array.Empty<string>()")
    ExternalStampScope(qualifiedTree, "import System")
    qualifiedPlan := DirectCallPlan(qualifiedTree, ColumnarRangePlannerEmptyBindings())

    assert shortPlan.ResultType == typeof(string[])
    assert qualifiedPlan.ResultType == typeof(string[])
    assert shortPlan.OperationCount == 1
    assert qualifiedPlan.OperationCount == 1
    assert shortPlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert qualifiedPlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    shortMethod := shortPlan.Methods[shortPlan.OperandIndices[0]]
    qualifiedMethod := qualifiedPlan.Methods[qualifiedPlan.OperandIndices[0]]
    assert shortMethod != null
    assert qualifiedMethod != null
    assert shortMethod.GetGenericArguments()[0] == typeof(string)
    assert qualifiedMethod.GetGenericArguments()[0] == typeof(string)

    shortResult := ArrayEmptyBindingInvokePlan(shortPlan)
    qualifiedResult := ArrayEmptyBindingInvokePlan(qualifiedPlan)
    assert Object.ReferenceEquals(shortResult, qualifiedResult)
}

test "Array Empty explicit generic ownership rejects unsupported shapes without plan residue" {
    noArguments := new string[](0)
    oneArgument := new string[](1)
    oneArgument[0] = "System.String"
    twoTypeArguments := new string[](2)
    twoTypeArguments[0] = "System.String"
    twoTypeArguments[1] = "System.String"

    assert !ArrayEmptyBindingPlan("Array", "System.Int32", noArguments).IsSupported
    assert !ArrayEmptyBindingPlan("OtherArray", "System.String", noArguments).IsSupported
    assert !ArrayEmptyBindingPlan("Array", "System.String", oneArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan("Array", "Empty", twoTypeArguments, noArguments).IsSupported

    ownership := ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning := true
    _unsupportedType := ArrayEmptyBindingRejected("Array.Empty<int>()", "import System", ColumnarRangePlannerEmptyBindings(), out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert !legacyWholeSubtreePlanning

    ownership = ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning = true
    _wrongTypeArity := ArrayEmptyBindingRejected("Array.Empty<string, string>()", "import System", ColumnarRangePlannerEmptyBindings(), out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert !legacyWholeSubtreePlanning

    ownership = ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning = true
    _wrongValueArity := ArrayEmptyBindingRejected("Array.Empty<string>(\"value\")", "import System", ColumnarRangePlannerEmptyBindings(), out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert !legacyWholeSubtreePlanning
}

test "Array Empty explicit generic ownership observes value and source owner shadowing" {
    valueBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(valueBindings, "Array", 0, typeof(Type))
    ownership := ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning := true
    _valueShadow := ArrayEmptyBindingRejected("Array.Empty<string>()", "import System", valueBindings, out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert !legacyWholeSubtreePlanning

    qualifiedBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(qualifiedBindings, "System", 0, typeof(Type))
    ownership = ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning = true
    _qualifiedValueShadow := ArrayEmptyBindingRejected("System.Array.Empty<string>()", "import System", qualifiedBindings, out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert !legacyWholeSubtreePlanning

    sourceTree := DirectCallParsedTree("Array.Empty<string>()")
    sourceInputs := new List<ColumnarStructInput>()
    sourceFields := new string[](0)
    sourceBases := new string[](0)
    sourceMethods := new List<ColumnarFunctionInput>()
    sourceTypeParameters: string[]? = null
    sourceInput := ExternalStruct("Array", sourceFields, sourceBases, sourceMethods, sourceTypeParameters, true)
    sourceInputs.Add(sourceInput)
    visibleTypeParameters := new string[](0)
    ExternalStampScopeFull(sourceTree, "class Array {}", "", visibleTypeParameters, sourceInputs, null)
    ownership = ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning = true
    _sourceShadow := DirectCallRejected(sourceTree, ColumnarRangePlannerEmptyBindings(), out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning

    additionalTree := DirectCallParsedTree("Array.Empty<string>()")
    additionalRoots := new string[](1)
    additionalRoots[0] = "Array"
    emptyVisibleTypeParameters := new string[](0)
    ExternalStampScopeFull(additionalTree, "import System", "", emptyVisibleTypeParameters, ExternalEmptyStructs(), additionalRoots)
    ownership = ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning = true
    _additionalShadow := DirectCallRejected(additionalTree, ColumnarRangePlannerEmptyBindings(), out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning

    typeParameterTree := DirectCallParsedTree("Array.Empty<string>()")
    shadowingTypeParameters := new string[](1)
    shadowingTypeParameters[0] = "Array"
    ExternalStampScopeWithTypeParameters(typeParameterTree, "import System", shadowingTypeParameters)
    ownership = ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning = true
    _typeParameterShadow := DirectCallRejected(typeParameterTree, ColumnarRangePlannerEmptyBindings(), out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning

    genericSourceOwner := SourceCallDefinition("Array", true)
    genericSourceParameters := new Type[](0)
    genericSourceMethod := SourceCallPublicStatic(genericSourceOwner, "Empty", genericSourceParameters, typeof(string[]))
    SourceCallMakeGeneric(genericSourceMethod.Builder)
    genericSourceTree := DirectCallParsedTree("Array.Empty<string>()")
    ownership = ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning = false
    _genericSource := DirectCallRejected(genericSourceTree, DirectCallSingleDefinitionBindings(genericSourceOwner), out ownership, out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}
