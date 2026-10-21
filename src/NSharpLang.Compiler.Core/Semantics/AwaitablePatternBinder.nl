namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Diagnostics.CodeAnalysis
import System.Reflection
import System.Runtime.CompilerServices
import NSharpLang.Compiler.Ast


// One C# await-pattern binding result for reflected awaitables. Analyzer, lowering and the
// playground share this selection so they cannot disagree about generic arity, visibility, or the
// continuation contract. Source-declared candidates are fed through the same selector below by
// their semantic owners while their CLR types are still unbaked.
class AwaitablePatternBinding {
    AwaitableType: Type
    AwaiterType: Type
    GetAwaiter: MethodInfo?
    IsCompletedGetter: MethodInfo?
    GetResult: MethodInfo
    CompletionSlot: MethodInfo
    IsCritical: bool
    GetAwaiterIsExtension: bool

    constructor(awaitableType: Type, awaiterType: Type, getAwaiter: MethodInfo?, isCompletedGetter: MethodInfo?, getResult: MethodInfo, completionSlot: MethodInfo, isCritical: bool, getAwaiterIsExtension: bool = false) {
        AwaitableType = awaitableType
        AwaiterType = awaiterType
        GetAwaiter = getAwaiter
        IsCompletedGetter = isCompletedGetter
        GetResult = getResult
        CompletionSlot = completionSlot
        IsCritical = isCritical
        GetAwaiterIsExtension = getAwaiterIsExtension
    }
}

class SourceAwaiterPatternBinding {
    IsCompleted: PropertyDeclaration
    GetResult: FunctionDeclaration
    Completion: FunctionDeclaration
    IsCritical: bool

    constructor(isCompleted: PropertyDeclaration, getResult: FunctionDeclaration, completion: FunctionDeclaration, isCritical: bool) {
        IsCompleted = isCompleted
        GetResult = getResult
        Completion = completion
        IsCritical = isCritical
    }
}

// The analyzer's source-symbol binding retains the declarations it selected as well as their
// substituted result types. Emission may use different CLR handles for a TypeBuilder, but it takes
// the same selected source members and the same awaiter contract as analysis.
class AnalyzerAwaitablePatternBinding {
    AwaitableType: TypeInfo
    AwaiterType: TypeInfo
    ResultType: TypeInfo
    GetAwaiter: AnalyzerMemberSelection?
    IsCompleted: AnalyzerMemberSelection?
    GetResult: AnalyzerMemberSelection?
    ReflectedAwaiter: AwaitablePatternBinding?
    GetAwaiterExtension: TypeInfo?
    GetAwaiterFunction: FunctionTypeInfo?
    GetAwaiterMethod: MethodInfo?
    GetAwaiterIsExtension: bool
    GetAwaiterTypeArguments: TypeInfo[]
    GetAwaiterDeclaration: FunctionDeclaration?
    SourceAwaiter: SourceAwaiterPatternBinding?
    SourceAwaiterTypeName: string?

    constructor(awaitableType: TypeInfo, awaiterType: TypeInfo, resultType: TypeInfo, getAwaiter: AnalyzerMemberSelection?, isCompleted: AnalyzerMemberSelection?, getResult: AnalyzerMemberSelection?, reflectedAwaiter: AwaitablePatternBinding?, getAwaiterExtension: TypeInfo? = null, getAwaiterFunction: FunctionTypeInfo? = null, getAwaiterMethod: MethodInfo? = null, getAwaiterIsExtension: bool = false, sourceAwaiter: SourceAwaiterPatternBinding? = null, sourceAwaiterTypeName: string? = null, getAwaiterTypeArguments: TypeInfo[]? = null) {
        AwaitableType = awaitableType
        AwaiterType = awaiterType
        ResultType = resultType
        GetAwaiter = getAwaiter
        IsCompleted = isCompleted
        GetResult = getResult
        ReflectedAwaiter = reflectedAwaiter
        GetAwaiterExtension = getAwaiterExtension
        GetAwaiterFunction = getAwaiterFunction
        GetAwaiterMethod = getAwaiterMethod
        GetAwaiterIsExtension = getAwaiterIsExtension
        GetAwaiterTypeArguments = getAwaiterTypeArguments ?? new TypeInfo[](0)
        GetAwaiterDeclaration = getAwaiterFunction == null ? null : getAwaiterFunction.SourceDeclaration
        SourceAwaiter = sourceAwaiter
        SourceAwaiterTypeName = sourceAwaiterTypeName
    }
}

class AwaitablePatternBinder {
    static PublicInstance: BindingFlags => BindingFlags.Public | BindingFlags.Instance

    // Bind using the await site’s ordinary member accessibility. Reflected members in another
    // assembly therefore have to be public; private members never become candidates merely because
    // reflection can see them. Nullable<T> is rejected before member lookup because C# does not
    // lift the await pattern through nullable value types.
    static func TryBindReflection(awaitableType: Type, out binding: AwaitablePatternBinding?): bool {
        binding = null
        if awaitableType == null || Nullable.GetUnderlyingType(awaitableType) != null || awaitableType.IsGenericParameter {
            return false
        }

        getAwaiter := SelectZeroArgumentInstanceMethod(awaitableType, "GetAwaiter")
        if getAwaiter == null || getAwaiter.ReturnType == typeof(void) {
            return false
        }

        awaiterType := getAwaiter.ReturnType
        awaiterBinding: AwaitablePatternBinding? = null
        if !TryBindReflectionAwaiter(awaiterType, out awaiterBinding) || awaiterBinding == null {
            return false
        }

        binding = new AwaitablePatternBinding(awaitableType, awaiterType, getAwaiter, awaiterBinding.IsCompletedGetter, awaiterBinding.GetResult, awaiterBinding.CompletionSlot, awaiterBinding.IsCritical)
        return true
    }

    static func TryBindReflectionAwaiter(awaiterType: Type, out binding: AwaitablePatternBinding?): bool {
        binding = null
        if awaiterType == null || awaiterType.IsGenericParameter {
            return false
        }

        isCompleted := SelectReadableBooleanProperty(awaiterType, "IsCompleted")
        getResult := SelectZeroArgumentInstanceMethod(awaiterType, "GetResult")
        if isCompleted == null || getResult == null {
            return false
        }

        critical := FindCompletionInterface(awaiterType, typeof(ICriticalNotifyCompletion)) != null
        contract := critical ? typeof(ICriticalNotifyCompletion) : typeof(INotifyCompletion)
        if !critical && FindCompletionInterface(awaiterType, contract) == null {
            return false
        }

        completionName := critical ? "UnsafeOnCompleted" : "OnCompleted"
        completionSlot := ResolveInterfaceSlot(awaiterType, contract, completionName)
        if completionSlot == null {
            return false
        }

        binding = new AwaitablePatternBinding(awaiterType, awaiterType, null, isCompleted.GetMethod, getResult, completionSlot, critical)
        return true
    }

    // The external extension resolver has already applied namespace visibility, receiver
    // applicability and overload ranking. This shared final binder validates and returns that exact
    // selected extension plus the same reflected awaiter members used by ordinary instance patterns.
    static func TryBindReflectionGetAwaiterExtension(awaitableType: Type, method: MethodInfo, out binding: AwaitablePatternBinding?): bool {
        binding = null
        if awaitableType == null || method == null || (method.IsGenericMethod && method.ContainsGenericParameters) || !method.IsStatic || !HasExtensionAttribute(method) || method.GetParameters().Length != 1 || method.ReturnType == typeof(void) {
            return false
        }
        if !method.GetParameters()[0].ParameterType.IsAssignableFrom(awaitableType) {
            return false
        }
        awaiterType := method.ReturnType
        awaiterBinding: AwaitablePatternBinding? = null
        if !TryBindReflectionAwaiter(awaiterType, out awaiterBinding) || awaiterBinding == null {
            return false
        }
        binding = new AwaitablePatternBinding(awaitableType, awaiterType, method, awaiterBinding.IsCompletedGetter, awaiterBinding.GetResult, awaiterBinding.CompletionSlot, awaiterBinding.IsCritical, true)
        return true
    }

    // This is the common overload filter for source member tables too. `member` is the semantic
    // member object owned by the caller (a DeclaredMemberInfo or an emitted method definition); the
    // caller supplies all candidates from the member chain, and this routine returns the one that
    // can actually be invoked with no type or value arguments at the await site.
    static func IsZeroArgumentNonGenericInstanceMethod(parameterCount: int, typeParameterCount: int, isStatic: bool, hasOptionalParameters: bool): bool {
        return parameterCount == 0 && typeParameterCount == 0 && !isStatic && !hasOptionalParameters
    }

    static func IsSourceMemberAccessible(member: DeclaredMemberInfo, accessingTypeName: string?): bool {
        if member == null {
            return false
        }
        sameType := accessingTypeName != null && accessingTypeName == member.ContainingType
        level := MemberAccessibility.LevelOfDeclaredModifiers(member.DeclaredModifiers)
        return MemberAccessibility.IsAccessible(level, sameType, false, true, true)
    }

    static func IsNullableValueType(candidate: TypeInfo): bool {
        nullable := candidate as NullableTypeInfo
        if nullable != null {
            return IsValueType(nullable.InnerType)
        }
        reflected := candidate as ReflectionTypeInfo
        return reflected != null && Nullable.GetUnderlyingType(reflected.Type) != null
    }

    static func IsValueType(candidate: TypeInfo): bool {
        if AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(candidate) {
            return true
        }
        reflected := candidate as ReflectionTypeInfo
        if reflected != null {
            return reflected.Type.IsValueType
        }
        constructed := candidate as GenericTypeInfo
        if constructed != null {
            definition := constructed.GenericDefinition
            if definition == null {
                return false
            }
            if definition as StructTypeInfo != null {
                return true
            }
            reflectedDefinition := definition as ReflectionTypeInfo
            return reflectedDefinition != null && reflectedDefinition.Type.IsValueType
        }
        return false
    }

    // The playground interpreter operates on source declarations rather than CLR objects. It uses
    // the same source member selector and semantic interface contract as analysis, then executes the
    // exact declarations returned here. An explicit implementation is selected from its resolved
    // interface slot, never by a member-name suffix or declaration order.
    static func SelectSourceMethod(owner: Declaration?, name: string, parameterCount: int): FunctionDeclaration? {
        if owner == null || name == null || parameterCount < 0 {
            return null
        }
        members := SourceMembers(owner)
        if members == null {
            return null
        }
        for member in members {
            function := member as FunctionDeclaration
            if function == null || function.Name != name || function.Parameters.Count != parameterCount || (function.TypeParameters != null && function.TypeParameters.Count != 0) || IsStaticSourceFunction(function) || HasOptionalSourceParameters(function) {
                continue
            }
            return function
        }
        return null
    }

    static func TryBindSourceAwaiter(owner: Declaration?, semanticModel: SemanticModel?, out binding: SourceAwaiterPatternBinding?, out failureReason: string): bool {
        binding = null
        failureReason = "source awaiter binding failed"
        if owner == null || semanticModel == null {
            failureReason = "source awaiter declaration or semantic model is missing"
            return false
        }
        members := SourceMembers(owner)
        if members == null {
            failureReason = "source awaiter declaration has no members"
            return false
        }

        isCompleted: PropertyDeclaration? = null
        for member in members {
            property := member as PropertyDeclaration
            if property != null && property.Name == "IsCompleted" && !IsStaticSourceProperty(property) && HasReadableSourceProperty(property) && SourcePropertyIsBoolean(property, semanticModel) {
                isCompleted = property
                break
            }
        }
        getResult := SelectSourceMethod(owner, "GetResult", 0)
        criticalReference: TypeReference? = null
        notifyReference: TypeReference? = null
        critical := TryFindSourceCompletionInterface(owner, semanticModel, typeof(ICriticalNotifyCompletion), out criticalReference)
        hasNotify := TryFindSourceCompletionInterface(owner, semanticModel, typeof(INotifyCompletion), out notifyReference)
        if isCompleted == null {
            failureReason = "source awaiter is missing an accessible bool IsCompleted property"
            return false
        }
        if getResult == null {
            failureReason = "source awaiter is missing a non-generic zero-argument GetResult method"
            return false
        }
        if !hasNotify && !critical {
            failureReason = "source awaiter does not resolve to INotifyCompletion or ICriticalNotifyCompletion"
            return false
        }

        contractReference := critical ? criticalReference : notifyReference
        contractType := critical ? typeof(ICriticalNotifyCompletion) : typeof(INotifyCompletion)
        completionName := critical ? "UnsafeOnCompleted" : "OnCompleted"
        completion := FindSourceInterfaceImplementation(owner, members, semanticModel, contractReference, contractType, completionName)
        if completion == null {
            failureReason = "source awaiter does not provide the selected completion interface slot " + completionName
            return false
        }
        binding = new SourceAwaiterPatternBinding(isCompleted, getResult, completion, critical)
        failureReason = ""
        return true
    }

    // Bind an awaitable whose GetAwaiter member is declared in the current N# compilation. This is
    // the analyzer's one source-symbol entry point: owner-specific member enumeration supplies live
    // semantic declarations, while this binder owns candidate viability, accessibility, generic
    // arity, the IsCompleted/GetResult pair and the required completion interface.
    // The analyzer-facing entry for reflected, source and extension awaitables. Task families may
    // be recognized by their language type owner before this call; every remaining pattern reaches
    // this binder and receives one selected GetAwaiter plus its already-bound awaiter members.
    static func TryBindAnalyzerAwaitable(awaitableType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel?, memberResolution: AnalyzerMemberResolution?, extensions: AnalyzerExtensionMethodResolution?, sourceOverloads: AnalyzerSyntheticCallWalk?, sourceValidator: AnalyzerSyntheticCallValidator?, reflectionArguments: AnalyzerReflectionArgumentBinder?, clrConversion: AnalyzerClrTypeConversion?, accessingTypeName: string?, out binding: AnalyzerAwaitablePatternBinding?): bool {
        binding = null
        if awaitableType == null || declarations == null || semanticModel == null || memberResolution == null || sourceOverloads == null || sourceValidator == null || reflectionArguments == null || clrConversion == null || IsNullableValueType(awaitableType) {
            return false
        }

        reflectedAwaitableType := TryConstructReflectedAwaitableType(awaitableType, clrConversion)
        lookupType := awaitableType
        reflectionReceiverType := reflectedAwaitableType
        if reflectedAwaitableType != null {
            lookupType = new ReflectionTypeInfo(
                reflectedAwaitableType.IsGenericType && !reflectedAwaitableType.IsGenericTypeDefinition ? reflectedAwaitableType.GetGenericTypeDefinition() : reflectedAwaitableType
            )
        } else {
            genericAwaitable := awaitableType as GenericTypeInfo
            reflectedDefinition := genericAwaitable == null ? null : genericAwaitable.GenericDefinition as ReflectionTypeInfo
            if reflectedDefinition != null {
                lookupType = reflectedDefinition
                reflectionReceiverType = reflectedDefinition.Type
            }
        }

        invocation := AwaiterInvocation()
        selectedMember := memberResolution.ResolveMember(lookupType, "GetAwaiter", false, accessingTypeName, true)
        selectedFunction: FunctionTypeInfo? = null
        selectedMethod: MethodInfo? = null
        isExtension := false

        sourceCandidates := AwaiterSourceCandidates(selectedMember)
        if sourceCandidates != null {
            selectedFunction = sourceOverloads.BindNSharpCall(sourceCandidates, invocation, new List<TypeInfo>(), awaitableType)
            if selectedFunction != null && !selectedFunction.SourceHasReceiverParameter && selectedFunction.TypeParameters != null && selectedFunction.TypeParameters.Count != 0 {
                selectedFunction = null
            }
            if selectedFunction != null {
                isExtension = selectedFunction.SourceHasReceiverParameter
            }
        } else {
            reflectedCandidates := AwaiterReflectionCandidates(selectedMember)
            receiverClrType := reflectionReceiverType
            if receiverClrType != null {
                best: ReflectionPreBoundCandidate? = null
                for method in reflectedCandidates {
                    if method.IsStatic || method.IsGenericMethod {
                        continue
                    }
                    candidate := reflectionArguments.PreBindReflectionMethod(method, invocation, receiverClrType, awaitableType, new TypeInfo?[](0))
                    if candidate != null && (best == null || candidate.Score > best.Score) {
                        best = candidate
                    }
                }
                if best != null {
                    selectedMethod = best.RuntimeMethod
                    isExtension = AnalyzerOverloadFacts.IsExtensionMethodCallOnReceiver(best.SignatureMethod, invocation, receiverClrType)
                    selectedResult := AnalyzerReflectionSelectedReturnType(best)
                    if !TryBindAnalyzerSelectedAwaiter(awaitableType, selectedResult, declarations, semanticModel, accessingTypeName, null, selectedMethod, isExtension, clrConversion, new TypeInfo[](0), out binding) {
                        return false
                    }
                    return binding != null
                }
            }
        }

        if selectedFunction != null {
            selectedResult := sourceValidator.ResolveReturnType(selectedFunction, invocation, new List<TypeInfo>(), awaitableType)
            typeArguments := isExtension ? AnalyzerSelectedGenericTypeArguments(selectedFunction, invocation, awaitableType, sourceOverloads) : new TypeInfo[](0)
            return TryBindAnalyzerSelectedAwaiter(awaitableType, selectedResult, declarations, semanticModel, accessingTypeName, selectedFunction, null, isExtension, clrConversion, typeArguments, out binding)
        }

        // `ResolveMember` returns the instance method group first. If that group has no applicable
        // zero-argument member, C# proceeds to extension lookup; if an instance call did bind, its
        // result is validated above and an invalid awaiter never falls back here.
        hasInstanceMember := AwaiterHasApplicableInstanceCandidate(selectedMember, invocation, awaitableType, sourceOverloads, reflectionArguments, clrConversion)
        if hasInstanceMember || extensions == null {
            return false
        }
        getAwaiterExtension := extensions.TryResolveExtensionMethod(awaitableType, "GetAwaiter", accessingTypeName)
        extensionFunctionCandidates := AwaiterSourceCandidates(getAwaiterExtension)
        if extensionFunctionCandidates != null {
            selectedFunction = sourceOverloads.BindNSharpCall(extensionFunctionCandidates, invocation, new List<TypeInfo>(), awaitableType)
            if selectedFunction == null {
                return false
            }
            selectedResult := sourceValidator.ResolveReturnType(selectedFunction, invocation, new List<TypeInfo>(), awaitableType)
            typeArguments := AnalyzerSelectedGenericTypeArguments(selectedFunction, invocation, awaitableType, sourceOverloads)
            return TryBindAnalyzerSelectedAwaiter(awaitableType, selectedResult, declarations, semanticModel, accessingTypeName, selectedFunction, null, true, clrConversion, typeArguments, out binding)
        }

        receiverClrType := ReflectionReceiverTypeForBinding(awaitableType, clrConversion)
        if receiverClrType == null {
            return false
        }
        extensionCandidates := AwaiterReflectionCandidates(getAwaiterExtension)
        bestExtension: ReflectionPreBoundCandidate? = null
        for method in extensionCandidates {
            candidate := reflectionArguments.PreBindReflectionMethod(method, invocation, receiverClrType, awaitableType, new TypeInfo?[](0))
            if candidate != null && (bestExtension == null || candidate.Score > bestExtension.Score) {
                bestExtension = candidate
            }
        }
        if bestExtension == null {
            return false
        }
        selectedMethod = bestExtension.RuntimeMethod
        isExtension = true
        selectedResult := AnalyzerReflectionSelectedReturnType(bestExtension)
        return TryBindAnalyzerSelectedAwaiter(awaitableType, selectedResult, declarations, semanticModel, accessingTypeName, null, selectedMethod, isExtension, clrConversion, new TypeInfo[](0), out binding)
    }

    static func AnalyzerReflectionSelectedReturnType(candidate: ReflectionPreBoundCandidate): TypeInfo {
        if candidate == null {
            return BuiltInTypes.Unknown
        }
        // Prebinding may use an object-shaped CLR surrogate for source generic arguments. The
        // selected call's TypeInfo bindings carry the real receiver inference and must be applied
        // to the open signature before accepting the runtime handle's return type.
        return AnalyzerReflectionTypeConversion.ConvertReturnWithOverrides(candidate.SignatureMethod, candidate.TypeInfoBindings, candidate.Bindings)
    }

    static func AnalyzerSelectedGenericTypeArguments(function: FunctionTypeInfo, call: CallExpression, receiverType: TypeInfo, sourceOverloads: AnalyzerSyntheticCallWalk): TypeInfo[] {
        parameters: List<TypeParameter>? = function == null ? null : function.TypeParameters
        if parameters == null || parameters.Count == 0 {
            return new TypeInfo[](0)
        }
        inferred := sourceOverloads.InferGenericBindings(function, call, new List<TypeInfo>(), receiverType)
        if inferred == null {
            return new TypeInfo[](0)
        }
        parameterCount: int = parameters.Count
        arguments := new TypeInfo[parameterCount]
        index := 0
        while index < parameterCount {
            value: TypeInfo = BuiltInTypes.Unknown
            if !inferred.TryGetValue(parameters[index].Name, out value) || value == null || BuiltInTypes.IsUnknown(value) {
                return new TypeInfo[](0)
            }
            arguments[index] = value
            index += 1
        }
        return arguments
    }

    static func TryConstructReflectedAwaitableType(awaitableType: TypeInfo, clrConversion: AnalyzerClrTypeConversion): Type? {
        exact := clrConversion.TryConvertTypeInfoToClrType(awaitableType)
        if exact != null {
            return exact
        }
        constructed := awaitableType as GenericTypeInfo
        definition := constructed == null ? null : constructed.GenericDefinition as ReflectionTypeInfo
        if constructed == null || definition == null {
            return null
        }
        parameters: Type[] = definition.Type.GetGenericArguments()
        parameterCount: int = parameters.Length
        if parameterCount != constructed.TypeArguments.Count {
            return null
        }
        arguments := new Type[parameterCount]
        index := 0
        while index < parameterCount {
            argument := clrConversion.TryConvertTypeInfoToClrType(constructed.TypeArguments[index])
            if argument == null {
                return null
            }
            arguments[index] = argument
            index += 1
        }
        try {
            return definition.Type.MakeGenericType(arguments)
        } catch failure: ArgumentException {
            // The source resolver has already checked generic constraints; a reconstruction failure
            // only means this reflected member path cannot provide a CLR handle.
            return null
        }
    }

    static func AwaiterInvocation(): CallExpression {
        receiver: Expression = new IdentifierExpression("awaitable", 1, 1)
        callee: Expression = new MemberAccessExpression(receiver, "GetAwaiter", false, 1, 1)
        return new CallExpression(callee, new List<Argument>(), null, 1, 1)
    }

    static func AwaiterSourceCandidates(candidate: TypeInfo): IReadOnlyList<FunctionTypeInfo>? {
        function := candidate as FunctionTypeInfo
        if function != null {
            functions := new List<FunctionTypeInfo>()
            functions.Add(function)
            return functions
        }
        group := candidate as NSharpMethodGroupInfo
        if group != null {
            return NSharpMethodGroupInfoFactory.GetFunctions(group)
        }
        return null
    }

    static func AwaiterReflectionCandidates(candidate: TypeInfo): MethodInfo[] {
        method := candidate as ReflectionMethodInfo
        if method != null {
            return [method.Method]
        }
        group := candidate as ReflectionMethodGroupInfo
        if group != null {
            return group.Methods
        }
        return new MethodInfo[](0)
    }

    static func AwaiterHasApplicableInstanceCandidate(candidate: TypeInfo, call: CallExpression, receiver: TypeInfo, sourceOverloads: AnalyzerSyntheticCallWalk, reflectionArguments: AnalyzerReflectionArgumentBinder, clrConversion: AnalyzerClrTypeConversion): bool {
        sourceCandidates := AwaiterSourceCandidates(candidate)
        if sourceCandidates != null {
            for function in sourceCandidates {
                candidates := new List<FunctionTypeInfo>()
                candidates.Add(function)
                if !function.SourceHasReceiverParameter && (function.TypeParameters == null || function.TypeParameters.Count == 0) && sourceOverloads.BindNSharpCall(candidates, call, new List<TypeInfo>(), receiver) != null {
                    return true
                }
            }
        }
        receiverClrType := ReflectionReceiverTypeForBinding(receiver, clrConversion)
        if receiverClrType != null {
            for method in AwaiterReflectionCandidates(candidate) {
                if method.IsStatic || method.IsGenericMethod || reflectionArguments.PreBindReflectionMethod(method, call, receiverClrType, receiver, new TypeInfo?[](0)) == null {
                    continue
                }
                return true
            }
        }
        return false
    }

    static func ReflectionReceiverTypeForBinding(receiver: TypeInfo, clrConversion: AnalyzerClrTypeConversion): Type? {
        receiverClrType := clrConversion.TryConvertTypeInfoToClrType(receiver)
        if receiverClrType != null {
            return receiverClrType
        }
        receiverClrType = clrConversion.TryConvertTypeInfoToClrTypeForBinding(receiver)
        if receiverClrType != null {
            return receiverClrType
        }
        constructed := receiver as GenericTypeInfo
        definition := constructed == null ? null : constructed.GenericDefinition as ReflectionTypeInfo
        return definition == null ? null : definition.Type
    }

    static func TryBindAnalyzerSelectedAwaiter(awaitableType: TypeInfo, awaiterType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel, accessingTypeName: string?, selectedFunction: FunctionTypeInfo?, selectedMethod: MethodInfo?, isExtension: bool, clrConversion: AnalyzerClrTypeConversion, getAwaiterTypeArguments: TypeInfo[], out binding: AnalyzerAwaitablePatternBinding?): bool {
        binding = null
        if awaiterType == null || BuiltInTypes.IsUnknown(awaiterType) || awaiterType == BuiltInTypes.Void {
            return false
        }
        // A reflected generic invocation has a closed result in the semantic call result even
        // while the selected MethodInfo still names its open declaring signature. Bind the exact
        // closed result so ConfigureAwait and other constructed awaiter shapes retain their type
        // arguments through the same selected invocation.
        runtimeAwaiterType := clrConversion.TryConvertTypeInfoToClrType(awaiterType)
        if runtimeAwaiterType == null {
            runtimeAwaiterType = clrConversion.TryConvertTypeInfoToClrTypeForBinding(awaiterType)
        }
        if runtimeAwaiterType != null {
            closedReflectedAwaiter: AwaitablePatternBinding? = null
            reflectedAwaiterBound := TryBindReflectionAwaiter(runtimeAwaiterType, out closedReflectedAwaiter)
            if reflectedAwaiterBound && closedReflectedAwaiter != null {
                resultType: TypeInfo = BuiltInTypes.Unknown
                if !AnalyzerAwaitResultType(closedReflectedAwaiter.GetResult.ReturnType, out resultType) {
                    return false
                }
                runtimeAwaitableType := clrConversion.TryConvertTypeInfoToClrType(awaitableType)
                if runtimeAwaitableType == null {
                    runtimeAwaitableType = clrConversion.TryConvertTypeInfoToClrTypeForBinding(awaitableType)
                }
                if runtimeAwaitableType == null {
                    return false
                }
                getAwaiterMethod := selectedMethod
                if getAwaiterMethod == null && selectedFunction != null && !isExtension {
                    getAwaiterMethod = null
                }
                completePattern := new AwaitablePatternBinding(runtimeAwaitableType, runtimeAwaiterType, getAwaiterMethod, closedReflectedAwaiter.IsCompletedGetter, closedReflectedAwaiter.GetResult, closedReflectedAwaiter.CompletionSlot, closedReflectedAwaiter.IsCritical, isExtension)
                binding = new AnalyzerAwaitablePatternBinding(awaitableType, AnalyzerReflectionTypeConversion.ConvertReflectionType(runtimeAwaiterType), resultType, null, null, null, completePattern, null, selectedFunction, selectedMethod, isExtension)
                if selectedFunction != null {
                    binding.GetAwaiterDeclaration = selectedFunction.SourceDeclaration
                }
                return true
            }
        }
        if selectedMethod != null && selectedMethod.ReturnType != null && !selectedMethod.ReturnType.ContainsGenericParameters {
            selectedRuntimeAwaiterType := selectedMethod.ReturnType
            reflectedAwaiterPattern: AwaitablePatternBinding? = null
            if TryBindReflectionAwaiter(selectedRuntimeAwaiterType, out reflectedAwaiterPattern) && reflectedAwaiterPattern != null {
                resultType: TypeInfo = BuiltInTypes.Unknown
                if !AnalyzerAwaitResultType(reflectedAwaiterPattern.GetResult.ReturnType, out resultType) {
                    return false
                }
                selectedRuntimeAwaitableType := selectedMethod.DeclaringType
                if isExtension {
                    parameters := selectedMethod.GetParameters()
                    selectedRuntimeAwaitableType = parameters.Length == 0 ? null : parameters[0].ParameterType
                }
                if selectedRuntimeAwaitableType == null {
                    return false
                }
                completePattern := new AwaitablePatternBinding(selectedRuntimeAwaitableType, selectedRuntimeAwaiterType, selectedMethod, reflectedAwaiterPattern.IsCompletedGetter, reflectedAwaiterPattern.GetResult, reflectedAwaiterPattern.CompletionSlot, reflectedAwaiterPattern.IsCritical, isExtension)
                binding = new AnalyzerAwaitablePatternBinding(awaitableType, new ReflectionTypeInfo(selectedRuntimeAwaiterType), resultType, null, null, null, completePattern, null, null, selectedMethod, isExtension)
                return true
            }
        }
        resultType: TypeInfo = BuiltInTypes.Unknown
        isCompleted: AnalyzerMemberSelection? = null
        getResult: AnalyzerMemberSelection? = null
        reflectedAwaiter: AwaitablePatternBinding? = null
        sourceAwaiterBound := TryBindAnalyzerSourceAwaiter(awaiterType, declarations, accessingTypeName, out resultType, out isCompleted, out getResult, out reflectedAwaiter)
        if !sourceAwaiterBound {
            return false
        }
        sourceAwaiter: SourceAwaiterPatternBinding? = null
        sourceAwaiterOwner := declarations.ResolveDeclaredAlias(awaiterType)
        constructedSourceAwaiter := sourceAwaiterOwner as GenericTypeInfo
        if constructedSourceAwaiter != null && constructedSourceAwaiter.GenericDefinition != null && declarations.ContainsSourceType(constructedSourceAwaiter.GenericDefinition) {
            sourceAwaiterOwner = constructedSourceAwaiter.GenericDefinition
        }
        sourceDeclaration := declarations.FindDeclarationForType(sourceAwaiterOwner) as Declaration
        if sourceDeclaration != null {
            failureReason: string = ""
            TryBindSourceAwaiter(sourceDeclaration, semanticModel, out sourceAwaiter, out failureReason)
        }
        sourceAwaiterTypeName := SourceAwaiterCanonicalName(sourceAwaiterOwner, declarations)
        selectedExtension: TypeInfo? = null
        if isExtension {
            if selectedFunction != null {
                selectedExtension = selectedFunction
            } else if selectedMethod != null {
                selectedExtension = new ReflectionMethodInfo(selectedMethod)
            }
        }
        binding = new AnalyzerAwaitablePatternBinding(awaitableType, awaiterType, resultType, null, isCompleted, getResult, reflectedAwaiter, selectedExtension, selectedFunction, selectedMethod, isExtension, sourceAwaiter, sourceAwaiterTypeName, getAwaiterTypeArguments)
        return true
    }

    static func SourceAwaiterCanonicalName(awaiterType: TypeInfo, declarations: AnalyzerDeclarationContext): string? {
        if awaiterType == null || declarations == null {
            return null
        }
        owner := declarations.ResolveDeclaredAlias(awaiterType)
        constructed := owner as GenericTypeInfo
        if constructed != null && constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
            owner = constructed.GenericDefinition
        }
        if !declarations.ContainsSourceType(owner) {
            return null
        }
        name := TypeArityNames.Key(AnalyzerDeclarationContext.TypeName(owner), AnalyzerDeclarationContext.GenericHeadArity(owner))
        filePath := declarations.GetDeclarationFile(owner)
        namespaceName := declarations.GetNamespaceForFile(filePath)
        if namespaceName != null && namespaceName.Length > 0 {
            return namespaceName + "." + name
        }
        return name
    }

    static func HasExtensionAttribute(method: MethodInfo): bool {
        if method == null {
            return false
        }
        for attribute in method.GetCustomAttributesData() {
            if attribute != null && attribute.AttributeType != null && attribute.AttributeType.FullName == "System.Runtime.CompilerServices.ExtensionAttribute" {
                return true
            }
        }
        return false
    }

    static func TryBindAnalyzerSourceAwaiter(awaiterType: TypeInfo, declarations: AnalyzerDeclarationContext, accessingTypeName: string?, out resultType: TypeInfo, out isCompleted: AnalyzerMemberSelection?, out getResult: AnalyzerMemberSelection?, out reflectedBinding: AwaitablePatternBinding?): bool {
        resultType = BuiltInTypes.Unknown
        isCompleted = null
        getResult = null
        reflectedBinding = null
        resolvedAwaiter := declarations.ResolveDeclaredAlias(awaiterType)
        reflected := resolvedAwaiter as ReflectionTypeInfo
        if reflected != null {
            if !TryBindReflectionAwaiter(reflected.Type, out reflectedBinding) || reflectedBinding == null {
                return false
            }
            return AnalyzerAwaitResultType(reflectedBinding.GetResult.ReturnType, out resultType)
        }

        constructed := resolvedAwaiter as GenericTypeInfo
        if constructed != null {
            definitionInfo := constructed.GenericDefinition as ReflectionTypeInfo
            if definitionInfo != null {
                if !TryBindReflectionAwaiter(definitionInfo.Type, out reflectedBinding) || reflectedBinding == null {
                    return false
                }
                resultType = AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
                    reflectedBinding.GetResult.ReturnType,
                    AnalyzerReflectionTypeOverrides(definitionInfo.Type, constructed.TypeArguments),
                    null
                )
                return !BuiltInTypes.IsUnknown(resultType)
            }
            if constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
                awaiterType = constructed.GenericDefinition
            }
        }

        if !declarations.ContainsSourceType(awaiterType) {
            return false
        }

        substitution := AnalyzerSourceAwaitSubstitution(resolvedAwaiter)
        isCompletedSelection := new AnalyzerMemberSelection()
        isCompletedType: TypeInfo = BuiltInTypes.Unknown
        if !declarations.TryFindMember(awaiterType, "IsCompleted", out isCompletedSelection) || isCompletedSelection.Member == null || isCompletedSelection.Member.Kind != DeclaredMemberKind.Property || isCompletedSelection.Member.IsStatic || !IsSourceMemberAccessible(isCompletedSelection.Member, accessingTypeName) || isCompletedSelection.Member.Type == null || !declarations.TryResolveTypeForOwner(isCompletedSelection.Member.Type, isCompletedSelection.Owner, substitution, out isCompletedType) || !BuiltInTypes.Is(isCompletedType, BuiltInTypes.Bool) {
            return false
        }

        if !AnalyzerSourceTypeImplementsNotifyCompletion(resolvedAwaiter, declarations, 0) {
            return false
        }

        getResultSelection := new AnalyzerMemberSelection()
        if !TrySelectAnalyzerSourceMethod(awaiterType, "GetResult", declarations, accessingTypeName, out getResultSelection) || getResultSelection.Member == null {
            return false
        }
        if getResultSelection.Member.ReturnType == null {
            resultType = BuiltInTypes.Void
        } else if !declarations.TryResolveTypeForOwner(getResultSelection.Member.ReturnType, getResultSelection.Owner, substitution, out resultType) {
            return false
        }
        if BuiltInTypes.IsUnknown(resultType) {
            return false
        }
        isCompleted = isCompletedSelection
        getResult = getResultSelection
        return true
    }

    static func AnalyzerAwaitResultType(returnType: Type, out resultType: TypeInfo): bool {
        resultType = BuiltInTypes.Unknown
        if returnType == AnalyzerReflectionArgumentBinder.LiveVoidType() {
            resultType = BuiltInTypes.Void
            return true
        }
        resultType = AnalyzerReflectionTypeConversion.ConvertReflectionType(returnType)
        return !BuiltInTypes.IsUnknown(resultType)
    }

    static func AnalyzerReflectionTypeOverrides(definition: Type, arguments: List<TypeInfo>): Dictionary<Type, TypeInfo> {
        overrides := new Dictionary<Type, TypeInfo>()
        parameters := definition.GetGenericArguments()
        index := 0
        while index < parameters.Length && index < arguments.Count {
            overrides[parameters[index]] = arguments[index]
            index += 1
        }
        return overrides
    }

    static func TrySelectAnalyzerSourceMethod(owner: TypeInfo, name: string, declarations: AnalyzerDeclarationContext, accessingTypeName: string?, out selection: AnalyzerMemberSelection): bool {
        sourceOwner := owner
        substitution := AnalyzerSourceAwaitSubstitution(owner)
        constructed := sourceOwner as GenericTypeInfo
        if constructed != null && constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
            sourceOwner = constructed.GenericDefinition
        }

        shape := new AnalyzerSourceMemberShape()
        if declarations.TryGetSourceMemberShape(sourceOwner, substitution, out shape) {
            for member in shape.DeclaredMembers {
                if member.Name == name && member.Kind == DeclaredMemberKind.Function && IsZeroArgumentNonGenericInstanceMethod(member.ParameterCount, member.TypeParameterCount, member.IsStatic, member.RequiredParameterCount != 0) && IsSourceMemberAccessible(member, accessingTypeName) {
                    selection = new AnalyzerMemberSelection(shape.Owner, member, declarations.GetDeclarationFile(shape.Owner), member.Line, member.Column, "function", member.IsExported)
                    return true
                }
            }
            if declarations.TryFindMember(sourceOwner, name, out selection) && selection.Member != null {
                return false
            }
        }

        return declarations.TryFindMember(sourceOwner, name, out selection) && selection.Member != null && selection.Member.Kind == DeclaredMemberKind.Function && IsZeroArgumentNonGenericInstanceMethod(selection.Member.ParameterCount, selection.Member.TypeParameterCount, selection.Member.IsStatic, selection.Member.RequiredParameterCount != 0) && IsSourceMemberAccessible(selection.Member, accessingTypeName)
    }

    static func AnalyzerSourceAwaitSubstitution(owner: TypeInfo): Dictionary<string, TypeInfo>? {
        constructed := owner as GenericTypeInfo
        if constructed == null || constructed.GenericDefinition == null {
            return null
        }

        parameters: TypeParameter[]? = null
        classType := constructed.GenericDefinition as ClassTypeInfo
        if classType != null {
            parameters = classType.TypeParameters
        }
        structType := constructed.GenericDefinition as StructTypeInfo
        if structType != null {
            parameters = structType.TypeParameters
        }
        recordType := constructed.GenericDefinition as RecordTypeInfo
        if recordType != null {
            parameters = recordType.TypeParameters
        }
        interfaceType := constructed.GenericDefinition as InterfaceTypeInfo
        if interfaceType != null {
            parameters = interfaceType.TypeParameters
        }
        if parameters == null {
            return null
        }

        substitution := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        index := 0
        while index < parameters.Length && index < constructed.TypeArguments.Count {
            substitution[parameters[index].Name] = constructed.TypeArguments[index]
            index += 1
        }
        return substitution
    }

    static func AnalyzerSourceTypeImplementsNotifyCompletion(awaiterType: TypeInfo, declarations: AnalyzerDeclarationContext, depth: int): bool {
        if depth > 32 || awaiterType == null {
            return false
        }
        resolved := declarations.ResolveDeclaredAlias(awaiterType)
        reflected := resolved as ReflectionTypeInfo
        if reflected != null {
            return FindCompletionInterface(reflected.Type, typeof(INotifyCompletion)) != null
        }
        constructed := resolved as GenericTypeInfo
        if constructed != null {
            definitionInfo := constructed.GenericDefinition as ReflectionTypeInfo
            if definitionInfo != null {
                return FindCompletionInterface(definitionInfo.Type, typeof(INotifyCompletion)) != null
            }
        }

        sourceOwner := resolved
        substitution := AnalyzerSourceAwaitSubstitution(resolved)
        if constructed != null && constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
            sourceOwner = constructed.GenericDefinition
        }
        if !declarations.ContainsSourceType(sourceOwner) {
            return false
        }

        references := new List<TypeReference>()
        classType := sourceOwner as ClassTypeInfo
        if classType != null {
            references.AddRange(classType.Interfaces)
        }
        structType := sourceOwner as StructTypeInfo
        if structType != null {
            references.AddRange(structType.Interfaces)
        }
        recordType := sourceOwner as RecordTypeInfo
        if recordType != null {
            references.AddRange(recordType.Interfaces)
        }
        interfaceType := sourceOwner as InterfaceTypeInfo
        if interfaceType != null {
            references.AddRange(interfaceType.BaseInterfaces)
        }
        for reference in references {
            implemented: TypeInfo = BuiltInTypes.Unknown
            if declarations.TryResolveTypeForOwner(reference, sourceOwner, substitution, out implemented) && AnalyzerSourceTypeIsNotifyCompletion(implemented, declarations, depth + 1) {
                return true
            }
        }

        shape := new AnalyzerSourceMemberShape()
        return declarations.TryGetSourceMemberShape(sourceOwner, substitution, out shape) && shape.BaseType != null && AnalyzerSourceTypeImplementsNotifyCompletion(shape.BaseType, declarations, depth + 1)
    }

    static func AnalyzerSourceTypeIsNotifyCompletion(typeInfo: TypeInfo, declarations: AnalyzerDeclarationContext, depth: int): bool {
        if depth > 32 || typeInfo == null {
            return false
        }
        resolved := declarations.ResolveDeclaredAlias(typeInfo)
        reflected := resolved as ReflectionTypeInfo
        if reflected != null {
            return TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(reflected.Type, typeof(INotifyCompletion))
        }
        constructed := resolved as GenericTypeInfo
        if constructed != null {
            definitionInfo := constructed.GenericDefinition as ReflectionTypeInfo
            if definitionInfo != null {
                return TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(definitionInfo.Type, typeof(INotifyCompletion))
            }
        }
        return AnalyzerSourceTypeImplementsNotifyCompletion(resolved, declarations, depth + 1)
    }

    static func FindSourceInterfaceImplementation(owner: Declaration, members: List<Declaration>, semanticModel: SemanticModel, contractReference: TypeReference?, contractType: Type, methodName: string): FunctionDeclaration? {
        // Interface dispatch selects the explicit map entry even when the class also exposes a
        // public method with the same spelling. Resolve that semantic qualifier first; a public
        // overload is only the implicit implementation when there is no explicit slot mapping.
        for member in members {
            function := member as FunctionDeclaration
            if function == null || !ExplicitInterfaceMemberFacts.IsExplicitMemberName(function.Name) || function.Parameters.Count != 1 || (function.TypeParameters != null && function.TypeParameters.Count != 0) || ExplicitInterfaceMemberFacts.SimpleNameOf(function.Name) != methodName {
                continue
            }
            qualifier := ExplicitInterfaceMemberFacts.QualifierOf(function.Name)
            if SourceQualifierResolvesTo(owner, semanticModel, qualifier, contractReference, contractType) {
                return function
            }
        }

        implicitMethod := SelectSourceMethod(owner, methodName, 1)
        if implicitMethod != null && IsPublicSourceFunction(implicitMethod) {
            return implicitMethod
        }
        return null
    }

    static func TryFindSourceCompletionInterface(owner: Declaration, semanticModel: SemanticModel, expected: Type, out selectedReference: TypeReference?): bool {
        selectedReference = null
        references := SourceInterfaces(owner)
        if references == null {
            return false
        }
        for reference in references {
            resolved: TypeInfo = null
            if TryResolveSourceTypeReference(semanticModel, reference, out resolved) && TypeInfoImplementsCompletionInterface(resolved, expected, semanticModel, 0) {
                selectedReference = reference
                return true
            }
        }
        return false
    }

    // The declaration model has already resolved every written type name, but declaration
    // interfaces are not present in TypeReferenceTypes on all compiler hosts (the browser keeps
    // declaration symbols in the name/identity tables). Re-read that exact resolved symbol by its
    // complete written identity when its source span has no entry. This does not widen to a suffix
    // or a same-simple-name candidate.
    static func TryResolveSourceTypeReference(semanticModel: SemanticModel, reference: TypeReference, out resolved: TypeInfo): bool {
        resolved = BuiltInTypes.Unknown
        position := TypeReferenceFacts.GetStartSpan(reference)
        if position.IsValid && semanticModel.TypeReferenceTypes.TryGetValue((Line: position.StartLine, Column: position.StartColumn), out resolved) && resolved != null {
            return true
        }
        name := TypeReferenceFacts.GetDisplayName(reference)
        if name.Length == 0 {
            return false
        }
        if semanticModel.Types.TryGetValue(name, out resolved) && resolved != null {
            return true
        }
        return semanticModel.TypesByIdentity.TryGetValue(TypeArityNames.Key(name, 0), out resolved) && resolved != null
    }

    static func TypeInfoImplementsCompletionInterface(typeInfo: TypeInfo, expected: Type, semanticModel: SemanticModel, depth: int): bool {
        if typeInfo == null || semanticModel == null || depth > 32 {
            return false
        }
        reflected := typeInfo as ReflectionTypeInfo
        if reflected != null {
            if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(reflected.Type, expected) {
                return true
            }
            for implemented in reflected.Type.GetInterfaces() {
                if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(implemented, expected) {
                    return true
                }
            }
        }
        constructed := typeInfo as GenericTypeInfo
        if constructed != null {
            definition := constructed.GenericDefinition as ReflectionTypeInfo
            if definition != null {
                return TypeInfoImplementsCompletionInterface(definition, expected, semanticModel, depth + 1)
            }
            if constructed.GenericDefinition != null {
                typeInfo = constructed.GenericDefinition
            }
        }

        references := new List<TypeReference>()
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            if classType.BaseClass != null {
                references.Add(classType.BaseClass)
            }
            references.AddRange(classType.Interfaces)
        }
        structType := typeInfo as StructTypeInfo
        if structType != null {
            references.AddRange(structType.Interfaces)
        }
        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            references.AddRange(recordType.Interfaces)
        }
        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            references.AddRange(interfaceType.BaseInterfaces)
        }
        for reference in references {
            resolved: TypeInfo = BuiltInTypes.Unknown
            if TryResolveSourceTypeReference(semanticModel, reference, out resolved) && TypeInfoImplementsCompletionInterface(resolved, expected, semanticModel, depth + 1) {
                return true
            }
        }
        return false
    }

    static func SourceQualifierResolvesTo(owner: Declaration, semanticModel: SemanticModel, qualifier: string, contractReference: TypeReference?, expected: Type): bool {
        if contractReference != null {
            resolvedContract: TypeInfo = BuiltInTypes.Unknown
            if TryResolveSourceTypeReference(semanticModel, contractReference, out resolvedContract) && SourceQualifierIdentifiesResolvedReference(semanticModel, contractReference, qualifier, resolvedContract) && TypeInfoImplementsCompletionInterface(resolvedContract, expected, semanticModel, 0) {
                return true
            }
        }
        references := SourceInterfaces(owner)
        if references != null {
            for reference in references {
                resolvedContract: TypeInfo = BuiltInTypes.Unknown
                if TryResolveSourceTypeReference(semanticModel, reference, out resolvedContract) && SourceTypeClosureContainsQualifier(resolvedContract, qualifier, expected, semanticModel, 0) {
                    return true
                }
            }
        }
        return false
    }

    static func SourceQualifierIdentifiesResolvedReference(semanticModel: SemanticModel, reference: TypeReference, qualifier: string, resolved: TypeInfo): bool {
        if semanticModel == null || reference == null || resolved == null || qualifier == null || qualifier.Length == 0 {
            return false
        }
        if TypeReferenceFacts.GetDisplayName(reference) == qualifier {
            return true
        }
        candidate: TypeInfo? = null
        if semanticModel.Types.TryGetValue(qualifier, out candidate) && candidate != null && TypeInfoIdentityFacts.AreEqual(candidate, resolved) {
            return true
        }
        if semanticModel.TypesByIdentity.TryGetValue(TypeArityNames.Key(qualifier, 0), out candidate) && candidate != null && TypeInfoIdentityFacts.AreEqual(candidate, resolved) {
            return true
        }
        return false
    }

    // An explicit implementation may name an inherited completion slot even when the implementing
    // class writes only a derived source interface (`class Awaiter: ResumableCompletion` where
    // `ResumableCompletion: INotifyCompletion`). Walk the resolved interface closure, carrying the
    // exact source TypeReference at each edge so this remains semantic and never relies on a simple
    // method-name suffix.
    static func SourceTypeClosureContainsQualifier(typeInfo: TypeInfo, qualifier: string, expected: Type, semanticModel: SemanticModel, depth: int): bool {
        if typeInfo == null || semanticModel == null || depth > 32 {
            return false
        }

        reflected := typeInfo as ReflectionTypeInfo
        if reflected != null {
            reflectedName := reflected.Type.FullName
            if (reflected.Type.IsInterface && (reflected.Type.Name == qualifier || reflectedName == qualifier) && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(reflected.Type, expected)) {
                return true
            }
            for implemented in reflected.Type.GetInterfaces() {
                implementedName := implemented.FullName
                if (implemented.Name == qualifier || implementedName == qualifier) && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(implemented, expected) {
                    return true
                }
            }
            baseType := reflected.Type.BaseType
            if baseType != null && SourceTypeClosureContainsQualifier(new ReflectionTypeInfo(baseType), qualifier, expected, semanticModel, depth + 1) {
                return true
            }
            return false
        }

        constructed := typeInfo as GenericTypeInfo
        if constructed != null && constructed.GenericDefinition != null {
            typeInfo = constructed.GenericDefinition
        }

        references := new List<TypeReference>()
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            if classType.BaseClass != null {
                references.Add(classType.BaseClass)
            }
            references.AddRange(classType.Interfaces)
        }
        structType := typeInfo as StructTypeInfo
        if structType != null {
            references.AddRange(structType.Interfaces)
        }
        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            references.AddRange(recordType.Interfaces)
        }
        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            references.AddRange(interfaceType.BaseInterfaces)
        }

        for reference in references {
            resolved: TypeInfo = BuiltInTypes.Unknown
            if !TryResolveSourceTypeReference(semanticModel, reference, out resolved) {
                continue
            }
            if SourceQualifierIdentifiesResolvedReference(semanticModel, reference, qualifier, resolved) && TypeInfoImplementsCompletionInterface(resolved, expected, semanticModel, 0) {
                return true
            }
            if SourceTypeClosureContainsQualifier(resolved, qualifier, expected, semanticModel, depth + 1) {
                return true
            }
        }
        return false
    }

    static func TypeInfoImplementsExactInterface(typeInfo: TypeInfo, expected: Type): bool {
        reflected := typeInfo as ReflectionTypeInfo
        return reflected != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(reflected.Type, expected)
    }

    static func SourcePropertyIsBoolean(property: PropertyDeclaration, semanticModel: SemanticModel): bool {
        if property.Type == null {
            return false
        }
        position := TypeReferenceFacts.GetStartSpan(property.Type)
        resolved: TypeInfo = null
        return semanticModel.TypeReferenceTypes.TryGetValue((Line: position.StartLine, Column: position.StartColumn), out resolved) && resolved != null && BuiltInTypes.Is(resolved, BuiltInTypes.Bool)
    }

    static func HasReadableSourceProperty(property: PropertyDeclaration): bool {
        return property.GetBody != null || property.ExpressionBody != null
    }

    static func IsStaticSourceProperty(property: PropertyDeclaration): bool {
        return (Convert.ToInt32(property.Modifiers) & Convert.ToInt32(Modifiers.Static)) != 0
    }

    static func IsStaticSourceFunction(function: FunctionDeclaration): bool {
        return (Convert.ToInt32(function.Modifiers) & Convert.ToInt32(Modifiers.Static)) != 0
    }

    static func IsPublicSourceFunction(function: FunctionDeclaration): bool {
        let modifiers: int = Convert.ToInt32(function.Modifiers)
        return (modifiers & Convert.ToInt32(Modifiers.Private)) == 0 && (modifiers & Convert.ToInt32(Modifiers.Protected)) == 0
    }

    static func HasOptionalSourceParameters(function: FunctionDeclaration): bool {
        for parameter in function.Parameters {
            if parameter.DefaultValue != null {
                return true
            }
        }
        return false
    }

    static func SourceMembers(owner: Declaration): List<Declaration>? {
        classDeclaration := owner as ClassDeclaration
        if classDeclaration != null {
            return classDeclaration.Members
        }
        structDeclaration := owner as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.Members
        }
        recordDeclaration := owner as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.Members
        }
        return null
    }

    static func SourceInterfaces(owner: Declaration): List<TypeReference>? {
        classDeclaration := owner as ClassDeclaration
        if classDeclaration != null {
            references := new List<TypeReference>()
            if classDeclaration.BaseClass != null {
                references.Add(classDeclaration.BaseClass)
            }
            references.AddRange(classDeclaration.Interfaces)
            return references
        }
        structDeclaration := owner as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.Interfaces
        }
        recordDeclaration := owner as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.Interfaces
        }
        return null
    }

    static func SelectZeroArgumentInstanceMethod(owner: Type, name: string): MethodInfo? {
        if owner == null {
            return null
        }

        selected: MethodInfo? = null
        for candidate in owner.GetMethods(PublicInstance) {
            if candidate.Name != name || candidate.IsStatic || candidate.IsGenericMethod || candidate.GetParameters().Length != 0 || HasOptionalParameters(candidate) {
                continue
            }
            if IsMoreSpecific(candidate.DeclaringType, selected == null ? null : selected.DeclaringType) {
                selected = candidate
            }
        }
        return selected
    }

    static func SelectReadableBooleanProperty(owner: Type, name: string): PropertyInfo? {
        if owner == null {
            return null
        }

        selected: PropertyInfo? = null
        for candidate in owner.GetProperties(PublicInstance) {
            getter := candidate.GetMethod
            if candidate.Name != name || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(candidate.PropertyType, typeof(bool)) || candidate.GetIndexParameters().Length != 0 || getter == null || !getter.IsPublic || getter.IsStatic {
                continue
            }
            if IsMoreSpecific(candidate.DeclaringType, selected == null ? null : selected.DeclaringType) {
                selected = candidate
            }
        }
        return selected
    }

    static func ResolveInterfaceSlot(
        awaiterType: Type,
        [DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.PublicMethods | DynamicallyAccessedMemberTypes.NonPublicMethods)] contract: Type,
        methodName: string
    ): MethodInfo? {
        if awaiterType == null || contract == null || methodName == null {
            return null
        }

        // The contract method is the dispatch slot. Calling it with callvirt on the awaiter lets
        // the CLR select an explicit implementation from the interface map. Looking for a target
        // method by its generated name is wrong when unrelated interfaces expose the same spelling.
        // GetInterfaceMap is available on runtime types and some metadata readers; for metadata-only
        // types the contract's own declared slot is still the semantic member we need to bind.
        try {
            interfaceMap := awaiterType.GetInterfaceMap(contract)
            index := 0
            while index < interfaceMap.InterfaceMethods.Length && index < interfaceMap.TargetMethods.Length {
                slot := interfaceMap.InterfaceMethods[index]
                if slot.Name == methodName && IsCompletionSlotSignature(slot) {
                    return slot
                }
                index += 1
            }
            // Metadata-only types can lack a runtime interface map; use the contract's declared
            // slot below when reflection cannot provide the map.
            // nlc:ignore NL011
        } catch failure: ArgumentException {
            // nlc:ignore NL011
        } catch failure: InvalidOperationException {
            // nlc:ignore NL011
        } catch failure: NotSupportedException {
        }

        for slot in contract.GetMethods() {
            if slot.Name == methodName && IsCompletionSlotSignature(slot) {
                return slot
            }
        }
        return null
    }

    static func IsCompletionSlotSignature(slot: MethodInfo): bool {
        return slot != null && !slot.IsStatic && !slot.IsGenericMethod && slot.GetParameters().Length == 1 && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(slot.GetParameters()[0].ParameterType, typeof(Action))
    }

    static func FindCompletionInterface(awaiterType: Type, requestedContract: Type): Type? {
        if awaiterType == null || requestedContract == null {
            return null
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(awaiterType, requestedContract) {
            return awaiterType
        }

        try {
            for implemented in awaiterType.GetInterfaces() {
                if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(implemented, requestedContract) {
                    return implemented
                }
            }
            // TypeBuilderInstantiation does not answer GetInterfaces; its generic definition does,
            // and the source declaration carries the same non-generic completion contract.
            // nlc:ignore NL011
        } catch failure: NotSupportedException {
            // TypeBuilderInstantiation does not answer GetInterfaces. Its generic definition does,
            // and completion interfaces are non-generic, so the definition's exact contract slot is
            // also the slot of every constructed instantiation.
            // nlc:ignore NL011
        } catch failure: NotImplementedException {
        }

        if awaiterType.IsGenericType && !awaiterType.IsGenericTypeDefinition {
            try {
                definition := awaiterType.GetGenericTypeDefinition()
                for implemented in definition.GetInterfaces() {
                    if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(implemented, requestedContract) {
                        return implemented
                    }
                }
                // The metadata-only definition can omit its interface closure; source declarations
                // remain the semantic source for emitted builders.
                // nlc:ignore NL011
            } catch failure: NotSupportedException {
                // nlc:ignore NL011
            } catch failure: NotImplementedException {
            }
        }
        return null
    }

    static func IsMoreSpecific(candidate: Type?, current: Type?): bool {
        if candidate == null {
            return false
        }
        if current == null {
            return true
        }
        return current.IsAssignableFrom(candidate)
    }

    static func HasOptionalParameters(method: MethodInfo): bool {
        if method == null {
            return false
        }
        for parameter in method.GetParameters() {
            if parameter.IsOptional || parameter.GetCustomAttributes(typeof(ParamArrayAttribute), false).Length > 0 {
                return true
            }
        }
        return false
    }
}
