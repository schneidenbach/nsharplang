namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Ordinary runtime lookup is intentionally classified instead of returning a boolean. A
// fixed-arity declaration with unusable arguments is owned and rejected; a generic, params,
// by-ref, varargs, or optional-expansion shape belongs to a later call owner; and a missing
// name/arity leaves extension and other lookup tiers available.
enum ColumnarOrdinaryRuntimeDirectCallStatus {
    NotFound,
    Excluded,
    Rejected,
    Selected
}

// Immutable-by-convention facts for one exact baked/runtime MethodInfo. The lookup type is the
// receiver or explicit static owner. DeclaringType preserves an inherited method's real CLR
// owner, while Kind records the exact call/callvirt instruction required by that receiver.
class ColumnarOrdinaryRuntimeDirectCallSelection {
    Status: ColumnarOrdinaryRuntimeDirectCallStatus
    Method: MethodInfo?
    LookupType: Type
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type
    Kind: ColumnarExternalCallKind
    IsStatic: bool
    ReceiverIsReference: bool
    IsAbstract: bool

    IsSelected: bool => Status == ColumnarOrdinaryRuntimeDirectCallStatus.Selected
    IsOwnedRejected: bool => Status == ColumnarOrdinaryRuntimeDirectCallStatus.Rejected
    IsExcluded: bool => Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    IsNotFound: bool => Status == ColumnarOrdinaryRuntimeDirectCallStatus.NotFound
    UsesCallVirtual: bool => Kind == ColumnarExternalCallKind.CallVirtual

    constructor(status: ColumnarOrdinaryRuntimeDirectCallStatus, method: MethodInfo?, lookupType: Type, declaringType: Type, parameterTypes: Type[], returnType: Type, kind: ColumnarExternalCallKind, isStatic: bool, receiverIsReference: bool, isAbstract: bool) {
        if lookupType == null || declaringType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Ordinary runtime direct-call selection facts cannot be null.")
        }

        if status == ColumnarOrdinaryRuntimeDirectCallStatus.Selected {
            if method == null || kind == ColumnarExternalCallKind.None {
                throw new InvalidOperationException("A selected ordinary runtime direct call requires exact method and dispatch facts.")
            }
        } else if method != null || kind != ColumnarExternalCallKind.None || parameterTypes.Length != 0 {
            throw new InvalidOperationException("An unselected ordinary runtime direct call cannot carry executable method facts.")
        }

        Status = status
        Method = method
        LookupType = lookupType
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
        Kind = kind
        IsStatic = isStatic
        ReceiverIsReference = receiverIsReference
        IsAbstract = isAbstract
    }
}

// A trailing-optional runtime method selection: the explicit call arguments occupy the leading
// ParameterTypes and every parameter from ExplicitArgumentCount onward is filled from its null
// metadata default. This is the shape `app.Run()` needs (`WebApplication.Run(string url = null)`).
class ColumnarRuntimeOptionalCallSelection {
    IsSelected: bool
    Method: MethodInfo?
    LookupType: Type
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type
    ExplicitArgumentCount: int
    IsStatic: bool
    ReceiverIsReference: bool
    UsesCallVirtual: bool

    constructor(isSelected: bool, method: MethodInfo?, lookupType: Type, declaringType: Type, parameterTypes: Type[], returnType: Type, explicitArgumentCount: int, isStatic: bool, receiverIsReference: bool) {
        if lookupType == null || declaringType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Runtime optional-call selection facts cannot be null.")
        }

        if isSelected && (method == null || explicitArgumentCount < 0 || explicitArgumentCount >= parameterTypes.Length) {
            throw new InvalidOperationException("A selected trailing-optional runtime call requires an exact handle and at least one filled default.")
        }

        IsSelected = isSelected
        Method = method
        LookupType = lookupType
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
        ExplicitArgumentCount = explicitArgumentCount
        IsStatic = isStatic
        ReceiverIsReference = receiverIsReference
        UsesCallVirtual = !isStatic && receiverIsReference
    }

    static func None(lookupType: Type): ColumnarRuntimeOptionalCallSelection {
        return new ColumnarRuntimeOptionalCallSelection(false, null, lookupType, lookupType, new Type[](0), typeof(object), 0, false, false)
    }

    static func Selected(lookupType: Type, method: MethodInfo, parameterTypes: Type[], returnType: Type, explicitArgumentCount: int, expectedStatic: bool): ColumnarRuntimeOptionalCallSelection {
        declaringType := method.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("A selected trailing-optional runtime call requires a declaring type.")
        }

        receiverIsReference := !expectedStatic && !lookupType.get_IsValueType()
        return new ColumnarRuntimeOptionalCallSelection(true, method, lookupType, declaringType, parameterTypes, returnType, explicitArgumentCount, expectedStatic, receiverIsReference)
    }
}

// Reflection-backed overload selection for ordinary public runtime methods. This owns only
// fixed-arity, non-generic, non-varargs, non-by-ref, non-params invocations. Candidate ranking
// deliberately reuses source-call argument scores so source and runtime calls cannot disagree
// about identity, numeric, reference, and boxing preference tiers.
class ColumnarOrdinaryRuntimeDirectCallResolver {
    static func Resolve(lookupType: Type, memberName: string, argumentTypes: Type[], expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveWithFacts(lookupType, memberName, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length), expectedStatic)
    }

    static func ResolveWithFacts(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        ValidateInputs(lookupType, memberName, argumentTypes)
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        inheritedReadOnlyDictionaryCall := Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
        if TryResolveInheritedReadOnlyDictionaryEnumeratorCall(
            lookupType,
            memberName,
            argumentTypes,
            expectedStatic,
            out inheritedReadOnlyDictionaryCall
        ) {
            return inheritedReadOnlyDictionaryCall
        }

        inheritedDictionaryEntryCall := Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
        if TryResolveInheritedDictionaryEntryEnumeratorCall(
            lookupType,
            memberName,
            argumentTypes,
            expectedStatic,
            out inheritedDictionaryEntryCall
        ) {
            return inheritedDictionaryEntryCall
        }

        genericDefinition := typeof(object)
        closedArguments := new Type[](0)
        if TryGetBuilderBoundRuntimeDefinition(lookupType, out genericDefinition, out closedArguments) {
            try {
                candidates := genericDefinition.GetMethods()
                if candidates == null {
                    throw new InvalidOperationException("Runtime generic method enumeration returned null.")
                }

                return ResolveFromCandidatesCore(lookupType, genericDefinition, closedArguments, memberName, argumentTypes, argumentFacts, expectedStatic, candidates)
            } catch ex: NotSupportedException {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            } catch ex: NotImplementedException {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            } catch ex: InvalidOperationException {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            } catch ex: ArgumentException {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            }
        }

        try {
            candidates := lookupType.GetMethods()
            if candidates == null {
                throw new InvalidOperationException("Runtime method enumeration returned null.")
            }

            return ResolveFromCandidatesWithFacts(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, candidates)
        } catch ex: NotSupportedException {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        } catch ex: InvalidOperationException {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }
    }

    // IReadOnlyDictionary<TKey, TValue> inherits its generic GetEnumerator from
    // IEnumerable<KeyValuePair<TKey, TValue>>, and reflection does not include inherited interface
    // members in GetMethods(). SystemsAnalyzer needs that exact call for a string-keyed dictionary
    // whose value is one direct source reference declaration. Rebind the declared interface method
    // onto the closed KVP sequence; every other inherited method and dictionary shape stays on the
    // ordinary lookup boundary.
    static func TryResolveInheritedReadOnlyDictionaryEnumeratorCall(
        lookupType: Type,
        memberName: string,
        argumentTypes: Type[],
        expectedStatic: bool,
        out selection: ColumnarOrdinaryRuntimeDirectCallSelection
    ): bool {
        selection = Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
        if expectedStatic || memberName != "GetEnumerator" || argumentTypes.Length != 0 || !IsExactStringSourceReferenceReadOnlyDictionary(lookupType) {
            return false
        }

        dictionaryArguments := lookupType.GetGenericArguments()
        pairArguments := new Type[](2)
        pairArguments[0] = dictionaryArguments[0]
        pairArguments[1] = dictionaryArguments[1]
        pairType := typeof(KeyValuePair<int, int>).GetGenericTypeDefinition().MakeGenericType(pairArguments)

        sequenceArguments := new Type[](1)
        sequenceArguments[0] = pairType
        sequenceDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
        sequenceType := sequenceDefinition.MakeGenericType(sequenceArguments)
        noParameters := new Type[](0)
        openMethod := sequenceDefinition.GetMethod("GetEnumerator", noParameters)
        if openMethod == null {
            throw new InvalidOperationException("IEnumerable<T>.GetEnumerator() was not found in the compiler runtime.")
        }
        method := TypeBuilder.GetMethod(sequenceType, openMethod)
        if method == null {
            throw new InvalidOperationException("IEnumerable<T>.GetEnumerator() could not be rebound for the source dictionary entry type.")
        }

        enumeratorType := ColumnarTypeOfPlanner.RequiredEnumeratorDefinition().MakeGenericType(sequenceArguments)
        selection = new ColumnarOrdinaryRuntimeDirectCallSelection(
            ColumnarOrdinaryRuntimeDirectCallStatus.Selected,
            method,
            lookupType,
            sequenceType,
            noParameters,
            enumeratorType,
            ColumnarExternalCallKind.CallVirtual,
            false,
            true,
            method.get_IsAbstract()
        )
        return true
    }

    static func IsExactStringSourceReferenceReadOnlyDictionary(lookupType: Type): bool {
        if lookupType == null || lookupType is TypeBuilder || !lookupType.get_IsGenericType() || lookupType.get_IsGenericTypeDefinition() || lookupType.GetGenericTypeDefinition() != ColumnarTypeOfPlanner.RequiredReadOnlyDictionaryDefinition() {
            return false
        }
        arguments := lookupType.GetGenericArguments()
        if arguments.Length != 2 || arguments[0] != typeof(string) {
            return false
        }
        valueType := arguments[1]
        return valueType is TypeBuilder && !ColumnarTypeOfPlanner.IsEnumBuilder(valueType) && !valueType.get_IsGenericTypeDefinition() && !valueType.get_IsValueType()
    }

    // Type.GetMethods on IEnumerator<T> does not enumerate the nongeneric IEnumerator methods it
    // inherits. The Analyzer's original explicit-enumerator loop needs the one exact inherited
    // member it calls: MoveNext on IEnumerator<KeyValuePair<string, string>>. Keep Reset and every
    // other generic-enumerator shape outside this prerequisite.
    static func TryResolveInheritedDictionaryEntryEnumeratorCall(
        lookupType: Type,
        memberName: string,
        argumentTypes: Type[],
        expectedStatic: bool,
        out selection: ColumnarOrdinaryRuntimeDirectCallSelection
    ): bool {
        selection = Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
        if expectedStatic || memberName != "MoveNext" || argumentTypes.Length != 0 || !IsExactStringDictionaryEntryEnumerator(lookupType) {
            return false
        }

        movementType := Type.GetType("System.Collections.IEnumerator")
        if movementType == null {
            throw new InvalidOperationException("System.Collections.IEnumerator was not found in the compiler runtime.")
        }
        noParameters := new Type[](0)
        method := movementType.GetMethod("MoveNext", noParameters)
        if method == null {
            throw new InvalidOperationException("System.Collections.IEnumerator.MoveNext() was not found in the compiler runtime.")
        }

        selection = Selected(lookupType, method, noParameters, false)
        return true
    }

    static func IsExactStringDictionaryEntryEnumerator(lookupType: Type): bool {
        if lookupType == null || !lookupType.get_IsGenericType() || lookupType.get_IsGenericTypeDefinition() {
            return false
        }
        enumeratorDefinition := Type.GetType("System.Collections.Generic.IEnumerator`1")
        if enumeratorDefinition == null || lookupType.GetGenericTypeDefinition() != enumeratorDefinition {
            return false
        }
        enumeratorArguments := lookupType.GetGenericArguments()
        if enumeratorArguments.Length != 1 || !ColumnarCanonicalTypeResolver.IsExactStringDictionaryEntryElement(enumeratorArguments[0]) {
            return false
        }
        return true
    }

    // A deterministic candidate seam keeps classification tests independent of reflection's
    // enumeration order. Production always enters through Resolve and supplies GetMethods().
    static func ResolveFromCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], expectedStatic: bool, candidates: MethodInfo[]): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveFromCandidatesWithFacts(lookupType, memberName, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length), expectedStatic, candidates)
    }

    static func ResolveFromCandidatesWithFacts(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidates: MethodInfo[]): ColumnarOrdinaryRuntimeDirectCallSelection {
        ValidateInputs(lookupType, memberName, argumentTypes)
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)
        if candidates == null {
            throw new InvalidOperationException("Ordinary runtime direct-call candidates cannot be null.")
        }

        genericDefinition := typeof(object)
        closedArguments := new Type[](0)
        if TryGetBuilderBoundRuntimeDefinition(lookupType, out genericDefinition, out closedArguments) {
            try {
                return ResolveFromCandidatesCore(lookupType, genericDefinition, closedArguments, memberName, argumentTypes, argumentFacts, expectedStatic, candidates)
            } catch ex: NotSupportedException {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            } catch ex: NotImplementedException {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            } catch ex: InvalidOperationException {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            } catch ex: ArgumentException {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            }
        }

        return ResolveFromCandidatesCore(lookupType, lookupType, closedArguments, memberName, argumentTypes, argumentFacts, expectedStatic, candidates)
    }

    static func ResolveFromCandidatesCore(lookupType: Type, candidateLookupType: Type, closedArguments: Type[], memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidates: MethodInfo[]): ColumnarOrdinaryRuntimeDirectCallSelection {
        hadExcludedShape := false
        hadFixedArity := false
        bestScore := -1
        bestCount := 0
        selected: MethodInfo? = null
        selectedParameters := new Type[](0)
        selectedReturnType := typeof(object)
        builderBound := closedArguments.Length > 0
        if builderBound {
            ValidateBuilderBoundCandidates(candidates)
        }

        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate != null && IsPublicCandidateForLookup(candidate, candidateLookupType, memberName, expectedStatic) {
                parameters := candidate.GetParameters()
                if parameters == null {
                    throw new InvalidOperationException("Runtime method parameters cannot be null.")
                }

                if IsIntrinsicExcludedShape(candidate, parameters) {
                    if ExcludedShapeCanOwnArity(candidate, parameters, argumentTypes.Length) {
                        hadExcludedShape = true
                    }
                } else {
                    parameterTypes := ResolveParameterTypes(candidate, candidateLookupType, parameters, closedArguments)
                    returnType := ResolveReturnType(candidate, candidateLookupType, closedArguments)
                    if HasUnsupportedResolvedSignature(parameters, parameterTypes, returnType, closedArguments) {
                        if ExcludedShapeCanOwnArity(candidate, parameters, argumentTypes.Length) {
                            hadExcludedShape = true
                        }
                    } else if HasOptionalExpansion(parameters, argumentTypes.Length) {
                        hadExcludedShape = true
                    } else if parameters.Length == argumentTypes.Length {
                        hadFixedArity = true
                        if CanDispatch(candidate, lookupType, expectedStatic) {
                            score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(parameterTypes, argumentTypes, argumentFacts)
                            if score > bestScore {
                                bestScore = score
                                bestCount = 1
                                selected = candidate
                                selectedParameters = parameterTypes
                                selectedReturnType = returnType
                            } else if score >= 0 && score == bestScore {
                                bestCount += 1
                            }
                        }
                    }
                }
            }

            index += 1
        }

        // Exact fixed-arity matches remain deterministic beside excluded overloads. Weaker
        // numeric/reference/boxing matches do not: a generic or expanded candidate may bind
        // more specifically, so defer that mixed set to the later call owner.
        if bestCount == 1 && selected != null && (!hadExcludedShape || bestScore == argumentTypes.Length * 8) {
            if builderBound {
                return SelectedBuilderBound(lookupType, candidateLookupType, selected, selectedParameters, selectedReturnType, expectedStatic)
            }

            return Selected(lookupType, selected, selectedParameters, expectedStatic)
        }

        if hadExcludedShape {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }

        if bestCount > 1 || hadFixedArity {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Rejected, lookupType, expectedStatic)
        }

        return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
    }

    static func ValidateBuilderBoundCandidates(candidates: MethodInfo[]) {
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate != null {
                declaringType := candidate.get_DeclaringType()
                if declaringType != null && ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(declaringType) {
                    throw new InvalidOperationException("Builder-bound runtime candidates must come from the open generic definition.")
                }
            }

            index += 1
        }
    }

    static func IsPublicCandidateForLookup(method: MethodInfo, lookupType: Type, memberName: string, expectedStatic: bool): bool {
        if !method.get_IsPublic() || method.get_Name() != memberName || method.get_IsStatic() != expectedStatic {
            return false
        }

        declaringType := method.get_DeclaringType()
        if declaringType == null {
            return false
        }

        if declaringType == lookupType {
            return true
        }

        if declaringType.get_IsValueType() || lookupType.get_IsValueType() {
            return false
        }

        try {
            return declaringType.IsAssignableFrom(lookupType)
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    static func TryGetBuilderBoundRuntimeDefinition(lookupType: Type, out definition: Type, out closedArguments: Type[]): bool {
        definition = typeof(object)
        closedArguments = new Type[](0)
        if !lookupType.get_IsGenericType() || lookupType.get_IsGenericTypeDefinition() || !ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(lookupType) {
            return false
        }

        candidate := lookupType.GetGenericTypeDefinition()
        // Source-headed generic instantiations belong to the source method resolver. This
        // fallback owns only runtime generic definitions closed over a source builder.
        if candidate is TypeBuilder {
            return false
        }

        arguments := lookupType.GetGenericArguments()
        if arguments.Length == 0 {
            return false
        }

        definition = candidate
        closedArguments = arguments
        return true
    }

    static func ResolveParameterTypes(method: MethodInfo, candidateLookupType: Type, parameters: ParameterInfo[], closedArguments: Type[]): Type[] {
        parameterTypes := new Type[](parameters.Length)
        declaringType := method.get_DeclaringType()
        substitute := closedArguments.Length > 0 && declaringType == candidateLookupType
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null {
                throw new InvalidOperationException("Runtime method parameters cannot be null.")
            }

            parameterType := parameter.get_ParameterType()
            if parameterType == null {
                throw new InvalidOperationException("Runtime method parameter types cannot be null.")
            }

            parameterTypes[index] = substitute ? ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(parameterType, closedArguments) : parameterType

            index += 1
        }

        return parameterTypes
    }

    static func ResolveReturnType(method: MethodInfo, candidateLookupType: Type, closedArguments: Type[]): Type {
        returnType := method.get_ReturnType()
        if returnType == null {
            throw new InvalidOperationException("Runtime method return types cannot be null.")
        }

        declaringType := method.get_DeclaringType()
        if closedArguments.Length > 0 && declaringType == candidateLookupType {
            return ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(returnType, closedArguments)
        }

        return returnType
    }

    static func IsIntrinsicExcludedShape(method: MethodInfo, parameters: ParameterInfo[]): bool {
        if method.get_IsGenericMethod() || method.get_IsGenericMethodDefinition() || IsVarArgs(method) {
            return true
        }

        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null || ColumnarExtensionMethodResolver.IsParamsParameter(parameter) {
                return true
            }

            index += 1
        }

        return false
    }

    // A RESOLVED SIGNATURE IS ONE THE EMITTER CAN SPELL, and after substitution the surviving generic
    // parameters are not all the same thing. `closedArguments` are the type arguments the RECEIVER was
    // closed over, and `ResolveParameterTypes` has already put them where the definition's own
    // parameters stood — so a generic parameter still standing in the resolved signature is either one
    // of THOSE (`Action<T>.Invoke(T)` inside `Holder<T>`, where `T` is the enclosing type's own
    // parameter and is a perfectly emittable type in its body) or one the substitution could not
    // reach, which is genuinely open and stays refused.
    static func HasUnsupportedResolvedSignature(parameters: ParameterInfo[], parameterTypes: Type[], returnType: Type, closedArguments: Type[]): bool {
        if parameters.Length != parameterTypes.Length || IsUnsupportedSignatureType(returnType, closedArguments) {
            return true
        }

        index := 0
        while index < parameterTypes.Length {
            if IsUnsupportedSignatureType(parameterTypes[index], closedArguments) {
                return true
            }

            index += 1
        }

        return false
    }

    static func IsUnsupportedSignatureType(signatureType: Type, closedArguments: Type[]): bool {
        if signatureType.get_IsByRef() || signatureType.get_IsGenericTypeDefinition() {
            return true
        }

        if !signatureType.get_IsGenericParameter() {
            return false
        }

        return !ContainsExactType(closedArguments, signatureType)
    }

    static func ContainsExactType(candidates: Type[], value: Type): bool {
        index := 0
        while index < candidates.Length {
            if candidates[index] == value {
                return true
            }

            index += 1
        }

        return false
    }

    static func ExcludedShapeCanOwnArity(method: MethodInfo, parameters: ParameterInfo[], argumentCount: int): bool {
        if HasParamsParameter(parameters) {
            return argumentCount >= parameters.Length - 1
        }

        if HasOptionalExpansion(parameters, argumentCount) {
            return true
        }

        if IsVarArgs(method) {
            return argumentCount >= parameters.Length
        }

        return argumentCount == parameters.Length
    }

    static func HasParamsParameter(parameters: ParameterInfo[]): bool {
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter != null && ColumnarExtensionMethodResolver.IsParamsParameter(parameter) {
                return true
            }

            index += 1
        }

        return false
    }

    static func HasOptionalExpansion(parameters: ParameterInfo[], argumentCount: int): bool {
        if argumentCount >= parameters.Length {
            return false
        }

        index := argumentCount
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null || !parameter.get_IsOptional() {
                return false
            }

            index += 1
        }

        return true
    }

    static func CanDispatch(method: MethodInfo, lookupType: Type, expectedStatic: bool): bool {
        if expectedStatic {
            return !method.get_IsAbstract()
        }

        return !lookupType.get_IsValueType() || !method.get_IsAbstract()
    }

    static func IsVarArgs(method: MethodInfo): bool {
        convention := (int)method.get_CallingConvention()
        return (convention & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0
    }

    static func Selected(lookupType: Type, method: MethodInfo, parameterTypes: Type[], expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        declaringType := method.get_DeclaringType()
        returnType := method.get_ReturnType()
        if declaringType == null || returnType == null {
            throw new InvalidOperationException("A selected runtime method requires declaring and return types.")
        }

        receiverIsReference := !expectedStatic && !lookupType.get_IsValueType()
        kind := receiverIsReference ? ColumnarExternalCallKind.CallVirtual : ColumnarExternalCallKind.Call
        return new ColumnarOrdinaryRuntimeDirectCallSelection(ColumnarOrdinaryRuntimeDirectCallStatus.Selected, method, lookupType, declaringType, parameterTypes, returnType, kind, expectedStatic, receiverIsReference, method.get_IsAbstract())
    }

    static func SelectedBuilderBound(lookupType: Type, genericDefinition: Type, method: MethodInfo, parameterTypes: Type[], returnType: Type, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        declaringType := method.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("A selected builder-bound runtime method requires an exact declaring type.")
        }

        exactMethod := method
        exactDeclaringType := declaringType
        if declaringType == genericDefinition {
            rebound := TypeBuilder.GetMethod(lookupType, method)
            if rebound == null {
                throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact builder-bound runtime method.")
            }

            exactMethod = (MethodInfo)rebound
            reboundDeclaringType := exactMethod.get_DeclaringType()
            if reboundDeclaringType == null || !ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(reboundDeclaringType, lookupType) {
                throw new InvalidOperationException("The rebound builder-bound runtime method has the wrong declaring type.")
            }

            exactDeclaringType = reboundDeclaringType
        }

        receiverIsReference := !expectedStatic && !lookupType.get_IsValueType()
        kind := receiverIsReference ? ColumnarExternalCallKind.CallVirtual : ColumnarExternalCallKind.Call
        return new ColumnarOrdinaryRuntimeDirectCallSelection(ColumnarOrdinaryRuntimeDirectCallStatus.Selected, exactMethod, lookupType, exactDeclaringType, parameterTypes, returnType, kind, expectedStatic, receiverIsReference, exactMethod.get_IsAbstract())
    }

    static func Empty(status: ColumnarOrdinaryRuntimeDirectCallStatus, lookupType: Type, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return new ColumnarOrdinaryRuntimeDirectCallSelection(status, null, lookupType, lookupType, new Type[](0), typeof(object), ColumnarExternalCallKind.None, expectedStatic, false, false)
    }

    // A fallback tier for the exact-arity resolver above: when no candidate binds at the supplied
    // arity, select a single ordinary method whose trailing parameters are all fillable null-default
    // optionals (`app.Run()` -> WebApplication.Run(string url = null)). Builder-bound source generics
    // and every excluded shape (generic, params, by-ref, varargs) keep their existing decline; the
    // explicit leading arguments are ranked with the shared direct-call scoring, and any tie declines.
    static func ResolveOptionalFill(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarRuntimeOptionalCallSelection {
        ValidateInputs(lookupType, memberName, argumentTypes)
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        genericDefinition := typeof(object)
        closedArguments := new Type[](0)
        if TryGetBuilderBoundRuntimeDefinition(lookupType, out genericDefinition, out closedArguments) {
            return ColumnarRuntimeOptionalCallSelection.None(lookupType)
        }

        candidates := CandidatesOrEmpty(lookupType)
        argumentCount := argumentTypes.Length
        bestScore := -1
        bestParameterCount := 0
        bestCount := 0
        selected: MethodInfo? = null
        selectedParameters := new Type[](0)
        selectedReturnType := typeof(object)
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate != null && IsPublicCandidateForLookup(candidate, lookupType, memberName, expectedStatic) {
                parameters := candidate.GetParameters()
                if parameters != null && !IsIntrinsicExcludedShape(candidate, parameters) && parameters.Length > argumentCount {
                    parameterTypes := ResolveParameterTypes(candidate, lookupType, parameters, closedArguments)
                    returnType := ResolveReturnType(candidate, lookupType, closedArguments)
                    if !HasUnsupportedResolvedSignature(parameters, parameterTypes, returnType, closedArguments) && OptionalTailFillable(parameters, parameterTypes, argumentCount) && CanDispatch(candidate, lookupType, expectedStatic) {
                        leading := LeadingParameterTypes(parameterTypes, argumentCount)
                        score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(leading, argumentTypes, argumentFacts)
                        if score >= 0 {
                            parameterCount := parameters.Length
                            if score > bestScore || (score == bestScore && parameterCount < bestParameterCount) {
                                bestScore = score
                                bestParameterCount = parameterCount
                                bestCount = 1
                                selected = candidate
                                selectedParameters = parameterTypes
                                selectedReturnType = returnType
                            } else if score == bestScore && parameterCount == bestParameterCount {
                                bestCount = bestCount + 1
                            }
                        }
                    }
                }
            }

            index = index + 1
        }

        if bestCount == 1 && selected != null {
            return ColumnarRuntimeOptionalCallSelection.Selected(lookupType, selected, selectedParameters, selectedReturnType, argumentCount, expectedStatic)
        }

        return ColumnarRuntimeOptionalCallSelection.None(lookupType)
    }

    static func CandidatesOrEmpty(lookupType: Type): MethodInfo[] {
        try {
            candidates := lookupType.GetMethods()
            if candidates == null {
                return new MethodInfo[](0)
            }

            return candidates
        } catch ex: NotSupportedException {
            return new MethodInfo[](0)
        } catch ex: InvalidOperationException {
            return new MethodInfo[](0)
        }
    }

    static func OptionalTailFillable(parameters: ParameterInfo[], parameterTypes: Type[], startIndex: int): bool {
        if parameters.Length != parameterTypes.Length {
            return false
        }

        index := startIndex
        while index < parameterTypes.Length {
            if !ColumnarExtensionMethodResolver.CanFillOptional(parameters[index], parameterTypes[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func LeadingParameterTypes(parameterTypes: Type[], count: int): Type[] {
        result := new Type[](count)
        index := 0
        while index < count {
            result[index] = parameterTypes[index]
            index = index + 1
        }

        return result
    }

    static func ValidateInputs(lookupType: Type, memberName: string, argumentTypes: Type[]) {
        if lookupType == null || memberName == null || argumentTypes == null {
            throw new InvalidOperationException("Ordinary runtime direct-call inputs cannot be null.")
        }

        index := 0
        while index < argumentTypes.Length {
            if argumentTypes[index] == null {
                throw new InvalidOperationException("Ordinary runtime direct-call argument types cannot be null.")
            }

            index += 1
        }
    }
}
