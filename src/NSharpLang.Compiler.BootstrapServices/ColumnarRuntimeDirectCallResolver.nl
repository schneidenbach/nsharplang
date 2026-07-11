namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// Exact materialization of one already-planned runtime call. LookupType records the type whose
// identity the binding plan selected; DeclaringType records the actual CLR method owner so an
// inherited method cannot silently lose that fact.
class ColumnarRuntimeDirectCallSelection {
    Method: MethodInfo?
    LookupType: Type
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type
    Kind: ColumnarExternalCallKind
    IsStatic: bool
    ReceiverIsReference: bool

    constructor(method: MethodInfo?, lookupType: Type, declaringType: Type, parameterTypes: Type[], returnType: Type, kind: ColumnarExternalCallKind, isStatic: bool, receiverIsReference: bool) {
        Method = method
        LookupType = lookupType
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
        Kind = kind
        IsStatic = isStatic
        ReceiverIsReference = receiverIsReference
    }

    UsesCallVirtual: bool => Kind == ColumnarExternalCallKind.CallVirtual

    static func Empty(): ColumnarRuntimeDirectCallSelection {
        return new ColumnarRuntimeDirectCallSelection(null, typeof(object), typeof(object), new Type[](0), typeof(object), ColumnarExternalCallKind.None, false, false)
    }
}

// Materializes an exact fixed-arity handle from an N#-owned external binding plan. The plan
// supplies every identity, and no overload ranking, coercion, optional/default expansion, or
// generic construction is permitted.
class ColumnarRuntimeDirectCallResolver {
    static func TrySelect(plan: ColumnarExternalCallPlan, lookupType: Type, expectedStatic: bool, out selection: ColumnarRuntimeDirectCallSelection): bool {
        selection = ColumnarRuntimeDirectCallSelection.Empty()
        if !ValidatePlanForm(plan, lookupType, expectedStatic) {
            return false
        }

        parameterTypes := new Type[](plan.ParameterTypeNames.Length)
        if !TryResolveExactPlanTypes(plan.ParameterTypeNames, parameterTypes) {
            return false
        }

        plannedReturnType := typeof(object)
        if !TryResolveExactPlanType(plan.ReturnTypeName, out plannedReturnType) {
            return false
        }

        method: MethodInfo? = null
        try {
            method = lookupType.GetMethod(plan.MemberName, parameterTypes)
        } catch {
            return false
        }

        if method == null {
            return false
        }

        candidates := new MethodInfo[](1)
        candidates[0] = method
        return TrySelectResolvedCandidates(plan, lookupType, expectedStatic, parameterTypes, plannedReturnType, candidates, out selection)
    }

    // This seam keeps corrupt/ambiguous-handle contracts native and deterministic. Production
    // selection always enters through TrySelect and supplies its exact named lookup result.
    static func TrySelectFromCandidates(plan: ColumnarExternalCallPlan, lookupType: Type, expectedStatic: bool, candidates: MethodInfo[], out selection: ColumnarRuntimeDirectCallSelection): bool {
        selection = ColumnarRuntimeDirectCallSelection.Empty()
        if !ValidatePlanForm(plan, lookupType, expectedStatic) || candidates == null {
            return false
        }

        parameterTypes := new Type[](plan.ParameterTypeNames.Length)
        if !TryResolveExactPlanTypes(plan.ParameterTypeNames, parameterTypes) {
            return false
        }

        plannedReturnType := typeof(object)
        if !TryResolveExactPlanType(plan.ReturnTypeName, out plannedReturnType) {
            return false
        }

        namedMethod: MethodInfo? = null
        try {
            namedMethod = lookupType.GetMethod(plan.MemberName, parameterTypes)
        } catch {
            return false
        }

        if namedMethod == null {
            return false
        }

        return TrySelectResolvedCandidates(plan, lookupType, expectedStatic, parameterTypes, plannedReturnType, candidates, out selection)
    }

    static func TrySelectResolvedCandidates(plan: ColumnarExternalCallPlan, lookupType: Type, expectedStatic: bool, plannedParameterTypes: Type[], plannedReturnType: Type, candidates: MethodInfo[], out selection: ColumnarRuntimeDirectCallSelection): bool {
        selection = ColumnarRuntimeDirectCallSelection.Empty()

        exact := ColumnarRuntimeDirectCallSelection.Empty()
        exactCount := 0
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            candidateSelection := ColumnarRuntimeDirectCallSelection.Empty()
            candidateMatches := false
            if candidate != null {
                try {
                    candidateMatches = TryDescribeExactCandidate(plan, lookupType, expectedStatic, plannedParameterTypes, plannedReturnType, candidate, out candidateSelection)
                } catch {
                    candidateMatches = false
                }
            }

            if candidateMatches {
                exact = candidateSelection
                exactCount = exactCount + 1
                if exactCount > 1 {
                    return false
                }
            }

            index = index + 1
        }

        if exactCount != 1 {
            return false
        }

        selection = exact
        return true
    }

    static func ValidatePlanForm(plan: ColumnarExternalCallPlan, lookupType: Type, expectedStatic: bool): bool {
        if plan == null || lookupType == null || !plan.IsSupported {
            return false
        }

        if plan.Kind == ColumnarExternalCallKind.None {
            return false
        }

        if plan.MemberName == null || plan.MemberName.Length == 0 {
            return false
        }

        if plan.ParameterTypeNames == null {
            return false
        }

        if plan.ReturnTypeName == null || plan.ReturnTypeName.Length == 0 {
            return false
        }

        if !ExternalAssemblyScan.HasExactTypeIdentity(lookupType, plan.DeclaringTypeName) {
            return false
        }

        if expectedStatic {
            return plan.Kind == ColumnarExternalCallKind.Call
        }

        if plan.Kind != ColumnarExternalCallKind.Call && plan.Kind != ColumnarExternalCallKind.CallVirtual {
            return false
        }

        // Ordinary explicit reference receivers require callvirt for virtual dispatch and the
        // standard null check. Value receivers instead require their direct managed-address call.
        return lookupType.get_IsValueType() ? plan.Kind == ColumnarExternalCallKind.Call : plan.Kind == ColumnarExternalCallKind.CallVirtual
    }

    static func TryDescribeExactCandidate(plan: ColumnarExternalCallPlan, lookupType: Type, expectedStatic: bool, plannedParameterTypes: Type[], plannedReturnType: Type, method: MethodInfo, out selection: ColumnarRuntimeDirectCallSelection): bool {
        selection = ColumnarRuntimeDirectCallSelection.Empty()
        if method == null {
            return false
        }

        if method.get_Name() != plan.MemberName {
            return false
        }

        if !method.get_IsPublic() {
            return false
        }

        if method.get_IsStatic() != expectedStatic {
            return false
        }

        if method.get_IsGenericMethod() {
            return false
        }

        if method.get_IsGenericMethodDefinition() {
            return false
        }

        callingConvention := (int)method.get_CallingConvention()
        if (callingConvention & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0 {
            return false
        }

        if plan.Kind == ColumnarExternalCallKind.Call && method.get_IsAbstract() {
            return false
        }

        declaringType := method.get_DeclaringType()
        if declaringType == null || !DeclaringTypeCanOwnLookup(declaringType, lookupType) {
            return false
        }

        returnType := method.get_ReturnType()
        if returnType == null || returnType != plannedReturnType || returnType.get_IsByRef() || !ExternalAssemblyScan.HasExactTypeIdentity(returnType, plan.ReturnTypeName) {
            return false
        }

        parameters := method.GetParameters()
        if parameters.Length != plan.ParameterTypeNames.Length || parameters.Length != plannedParameterTypes.Length {
            return false
        }

        parameterTypes := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameterType := parameters[index].get_ParameterType()
            if parameterType == null || parameterType != plannedParameterTypes[index] || parameterType.get_IsByRef() || !ExternalAssemblyScan.HasExactTypeIdentity(parameterType, plan.ParameterTypeNames[index]) {
                return false
            }

            parameterTypes[index] = parameterType
            index = index + 1
        }

        selection = new ColumnarRuntimeDirectCallSelection(method, lookupType, declaringType, parameterTypes, returnType, plan.Kind, expectedStatic, !expectedStatic && !lookupType.get_IsValueType())

        return true
    }

    static func TryResolveExactPlanTypes(identities: string[], resolvedTypes: Type[]): bool {
        if identities == null || resolvedTypes == null || identities.Length != resolvedTypes.Length {
            return false
        }

        index := 0
        while index < identities.Length {
            resolved := typeof(object)
            if !TryResolveExactPlanType(identities[index], out resolved) {
                return false
            }

            resolvedTypes[index] = resolved
            index = index + 1
        }

        return true
    }

    static func TryResolveExactPlanType(identity: string, out resolvedType: Type): bool {
        resolvedType = typeof(object)
        if identity == null || identity.Length == 0 {
            return false
        }

        candidate: Type? = null
        try {
            candidate = Type.GetType(identity)
        } catch {
            return false
        }

        if candidate == null || !ExternalAssemblyScan.HasExactTypeIdentity(candidate, identity) {
            return false
        }

        resolvedType = candidate
        return true
    }

    static func DeclaringTypeCanOwnLookup(declaringType: Type, lookupType: Type): bool {
        if declaringType == lookupType {
            return true
        }

        if declaringType.get_IsValueType() || lookupType.get_IsValueType() {
            return false
        }

        return declaringType.IsAssignableFrom(lookupType)
    }
}
