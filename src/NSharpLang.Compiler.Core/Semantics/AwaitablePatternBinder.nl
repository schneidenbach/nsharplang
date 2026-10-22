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
    IsCompleted: Declaration
    IsCompletedName: string
    GetResult: FunctionDeclaration
    Completion: FunctionDeclaration?
    CompletionSlot: MethodInfo
    IsCritical: bool

    constructor(isCompleted: Declaration, isCompletedName: string, getResult: FunctionDeclaration, completion: FunctionDeclaration?, completionSlot: MethodInfo, isCritical: bool) {
        IsCompleted = isCompleted
        IsCompletedName = isCompletedName
        GetResult = getResult
        Completion = completion
        CompletionSlot = completionSlot
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

    // Analyzer, planner and playground address the exact semantic binding by source position.
    // Keeping this read beside the binder prevents any consumer from reconstructing a pattern by
    // looking up its member names again.
    static func TryGetAnalyzerBindingAt(semanticModel: SemanticModel?, line: int, column: int, out binding: AnalyzerAwaitablePatternBinding?): bool {
        binding = null
        if semanticModel == null || line < 1 || column < 1 {
            return false
        }
        return semanticModel.AwaitablePatterns.TryGetValue((Line: line, Column: column), out binding) && binding != null
    }

    // Bind using the await site’s ordinary member accessibility. Reflected members in another
    // assembly therefore have to be public; private members never become candidates merely because
    // reflection can see them. Nullable<T> is rejected before member lookup because C# does not
    // lift the await pattern through nullable value types.
    static func TryBindReflection(awaitableType: Type, out binding: AwaitablePatternBinding?): bool {
        hasApplicableInstanceGetAwaiter := false
        return TryBindReflection(awaitableType, out binding, out hasApplicableInstanceGetAwaiter)
    }

    // `hasApplicableInstanceGetAwaiter` distinguishes no instance invocation from an ambiguous or
    // selected-but-invalid instance invocation. C# consults extension methods only in the first
    // case; callers must not repeat the member lookup to make that decision.
    static func TryBindReflection(awaitableType: Type, out binding: AwaitablePatternBinding?, out hasApplicableInstanceGetAwaiter: bool): bool {
        binding = null
        hasApplicableInstanceGetAwaiter = false
        if awaitableType == null || Nullable.GetUnderlyingType(awaitableType) != null || awaitableType.IsGenericParameter {
            return false
        }

        getAwaiter := SelectZeroArgumentInstanceMethod(awaitableType, "GetAwaiter", out hasApplicableInstanceGetAwaiter)
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
        if awaitableType == null || method == null || (method.IsGenericMethod && method.ContainsGenericParameters) || !method.IsStatic || !HasExtensionAttribute(method) || method.GetParameters().Length != 1 || method.GetParameters()[0].IsOptional || method.ReturnType == typeof(void) {
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
            lookupType = new ReflectionTypeInfo(reflectedAwaitableType)
        } else {
            genericAwaitable := awaitableType as GenericTypeInfo
            reflectedDefinition := genericAwaitable == null ? null : genericAwaitable.GenericDefinition as ReflectionTypeInfo
            if reflectedDefinition != null {
                reflectionReceiverType = clrConversion.TryConvertTypeInfoToClrTypeForBinding(awaitableType)
                if reflectionReceiverType == null {
                    reflectionReceiverType = reflectedDefinition.Type
                }
            }
        }

        invocation := AwaiterInvocation()
        selectedMember := memberResolution.ResolveMemberWithoutExtensionFallback(lookupType, "GetAwaiter", false, accessingTypeName, true)
        selectedFunction: FunctionTypeInfo? = null
        selectedMethod: MethodInfo? = null
        selectedResult: TypeInfo = BuiltInTypes.Unknown
        isExtension := false

        sourceCandidates := AwaiterSourceCandidates(selectedMember)
        if sourceCandidates != null {
            selectedFunction = sourceOverloads.BindNSharpCall(sourceCandidates, invocation, new List<TypeInfo>(), awaitableType)
            if selectedFunction != null && !selectedFunction.SourceHasReceiverParameter && selectedFunction.TypeParameters != null && selectedFunction.TypeParameters.Count != 0 {
                selectedFunction = null
            }
            if selectedFunction != null {
                isExtension = selectedFunction.SourceHasReceiverParameter
                if selectedFunction.SourceParameterCount != (isExtension ? 1 : 0) {
                    // C# resolves the ordinary invocation first, then rejects a selected call that
                    // used optional arguments or expanded a params array. Exact overloads still win.
                    return false
                }
            }
        } else {
            reflectedCandidates := AwaiterReflectionCandidates(selectedMember)
            receiverClrType := reflectionReceiverType
            if receiverClrType != null {
                selectedInstance: ReflectionPreBoundCandidate? = null
                if TrySelectReflectedAwaiterInvocation(reflectedCandidates, invocation, receiverClrType, awaitableType, reflectionArguments, false, out selectedInstance) && selectedInstance != null {
                    if selectedInstance.SignatureMethod.GetParameters().Length != 0 {
                        return false
                    }
                    selectedMethod = selectedInstance.RuntimeMethod
                    selectedResult = AnalyzerReflectionSelectedReturnType(selectedInstance)
                    isExtension = false
                    if !TryBindAnalyzerSelectedAwaiter(awaitableType, selectedResult, declarations, semanticModel, memberResolution, sourceOverloads, sourceValidator, reflectionArguments, accessingTypeName, null, selectedMethod, isExtension, clrConversion, new TypeInfo[](0), out binding) {
                        return false
                    }
                    return binding != null
                }
            }
        }

        if selectedFunction != null {
            selectedResult = sourceValidator.ResolveReturnType(selectedFunction, invocation, new List<TypeInfo>(), awaitableType)
            if isExtension && SourceGetAwaiterUsesOptionalOrExpandedReceiver(selectedFunction) {
                return false
            }
            typeArguments := isExtension ? AnalyzerSelectedGenericTypeArguments(selectedFunction, invocation, awaitableType, sourceOverloads) : new TypeInfo[](0)
            if isExtension && typeArguments.Length > 0 {
                selectedResult = ApplySelectedSourceGenericArguments(selectedFunction, selectedResult, typeArguments)
            }
            return TryBindAnalyzerSelectedAwaiter(awaitableType, selectedResult, declarations, semanticModel, memberResolution, sourceOverloads, sourceValidator, reflectionArguments, accessingTypeName, selectedFunction, null, isExtension, clrConversion, typeArguments, out binding)
        }

        // `ResolveMember` returns the instance method group first. If that group has no applicable
        // zero-argument member, C# proceeds to extension lookup; if an instance call did bind, its
        // result is validated above and an invalid awaiter never falls back here.
        hasInstanceMember := AwaiterHasApplicableInstanceCandidate(selectedMember, invocation, awaitableType, sourceOverloads, reflectionArguments, clrConversion)
        if hasInstanceMember {
            return false
        }
        if extensions == null {
            return false
        }
        getAwaiterExtension := extensions.TryResolveExtensionMethod(awaitableType, "GetAwaiter", accessingTypeName)
        extensionFunctionCandidates := AwaiterSourceCandidates(getAwaiterExtension)
        if extensionFunctionCandidates != null {
            selectedFunction = sourceOverloads.BindNSharpCall(extensionFunctionCandidates, invocation, new List<TypeInfo>(), awaitableType)
            if selectedFunction == null || !selectedFunction.SourceHasReceiverParameter || selectedFunction.SourceParameterCount != 1 {
                return false
            }
            if SourceGetAwaiterUsesOptionalOrExpandedReceiver(selectedFunction) {
                return false
            }
            selectedResult = sourceValidator.ResolveReturnType(selectedFunction, invocation, new List<TypeInfo>(), awaitableType)
            typeArguments := AnalyzerSelectedGenericTypeArguments(selectedFunction, invocation, awaitableType, sourceOverloads)
            if typeArguments.Length > 0 {
                selectedResult = ApplySelectedSourceGenericArguments(selectedFunction, selectedResult, typeArguments)
            }
            return TryBindAnalyzerSelectedAwaiter(awaitableType, selectedResult, declarations, semanticModel, memberResolution, sourceOverloads, sourceValidator, reflectionArguments, accessingTypeName, selectedFunction, null, true, clrConversion, typeArguments, out binding)
        }

        receiverClrType := ReflectionReceiverTypeForBinding(awaitableType, clrConversion)
        if receiverClrType == null {
            return false
        }
        extensionCandidates := FilterReflectedGetAwaiterExtensions(AwaiterReflectionCandidates(getAwaiterExtension))
        bestExtension: ReflectionPreBoundCandidate? = null
        if !TrySelectReflectedAwaiterInvocation(extensionCandidates, invocation, receiverClrType, awaitableType, reflectionArguments, true, out bestExtension) || bestExtension == null {
            return false
        }
        extensionParameters := bestExtension.SignatureMethod.GetParameters()
        if extensionParameters.Length != 1 || bestExtension.UsesParams || bestExtension.DefaultsUsed > 0 || extensionParameters[0].IsOptional || AnalyzerOverloadFacts.IsParamsParameter(extensionParameters[0]) {
            return false
        }
        typeArguments := new TypeInfo[](0)
        if bestExtension.SignatureMethod.IsGenericMethodDefinition {
            if !TryFinalizeReflectedAwaiterInvocation(bestExtension, reflectionArguments, out selectedMethod, out selectedResult, out typeArguments) || selectedMethod == null {
                return false
            }
        } else {
            selectedMethod = bestExtension.RuntimeMethod
            selectedResult = AnalyzerReflectionSelectedReturnType(bestExtension)
        }
        isExtension = true
        return TryBindAnalyzerSelectedAwaiter(awaitableType, selectedResult, declarations, semanticModel, memberResolution, sourceOverloads, sourceValidator, reflectionArguments, accessingTypeName, null, selectedMethod, isExtension, clrConversion, typeArguments, out binding)
    }

    static func AnalyzerReflectionSelectedReturnType(candidate: ReflectionPreBoundCandidate): TypeInfo {
        if candidate == null {
            return BuiltInTypes.Unknown
        }
        return AnalyzerReflectionTypeConversion.ConvertReturnWithOverrides(candidate.SignatureMethod, candidate.TypeInfoBindings, candidate.Bindings)
    }

    // Complete a zero-argument await-pattern invocation through the same reflected-call finalizer
    // used by ordinary member and extension calls. In particular, receiver-inferred generic
    // extensions must return their closed runtime method and substituted result type to every
    // downstream consumer; a pre-bound candidate is not yet the invocation result.
    static func TryFinalizeReflectedAwaiterInvocation(candidate: ReflectionPreBoundCandidate, arguments: AnalyzerReflectionArgumentBinder, out method: MethodInfo?, out resultType: TypeInfo, out typeArguments: TypeInfo[]): bool {
        method = null
        resultType = BuiltInTypes.Unknown
        typeArguments = new TypeInfo[](0)
        if candidate == null || arguments == null {
            return false
        }

        state := arguments.BeginFinalizeReflectionCall(candidate, false)
        request := arguments.NextReflectionAnalysis(state)
        if request != null || state.Failed || state.Phase != 2 || state.Result == null {
            return false
        }
        finalizedResultType := state.Result.ReturnType
        if finalizedResultType == null || BuiltInTypes.IsUnknown(finalizedResultType) {
            return false
        }
        method = state.RuntimeMethod
        resultType = finalizedResultType
        typeArguments = AnalyzerReflectionFinalizedGenericTypeArguments(state)
        return method != null && (!state.OpenMethod.IsGenericMethodDefinition || typeArguments.Length == state.OpenMethod.GetGenericArguments().Length)
    }

    static func AnalyzerReflectionFinalizedGenericTypeArguments(state: ReflectionCallFinalizeState): TypeInfo[] {
        if state == null || state.OpenMethod == null || !state.OpenMethod.IsGenericMethodDefinition {
            return new TypeInfo[](0)
        }
        parameters := state.OpenMethod.GetGenericArguments()
        arguments := new TypeInfo[parameters.Length]
        index := 0
        while index < parameters.Length {
            argument: TypeInfo? = null
            if !state.WorkingTypeInfoBindings.TryGetValue(parameters[index], out argument) || argument == null || BuiltInTypes.IsUnknown(argument) {
                clrArgument: Type? = null
                if !state.WorkingBindings.TryGetValue(parameters[index], out clrArgument) || clrArgument == null {
                    return new TypeInfo[](0)
                }
                argument = AnalyzerReflectionTypeConversion.ConvertReflectionType(clrArgument)
            }
            arguments[index] = argument
            index += 1
        }
        return arguments
    }

    static func AnalyzerSelectedGenericTypeArguments(function: FunctionTypeInfo, call: CallExpression, receiverType: TypeInfo, sourceOverloads: AnalyzerSyntheticCallWalk): TypeInfo[] {
        parameters: List<TypeParameter>? = function == null ? null : function.TypeParameters
        if parameters == null || parameters.Count == 0 {
            return new TypeInfo[](0)
        }
        // The chosen GetAwaiter extension has no ordinary arguments; its type arguments come
        // entirely from the receiver. Use the selected call's receiver inference directly so the
        // shared binding carries the same closed method and result the ordinary extension resolver
        // used to establish applicability.
        inferred := sourceOverloads.InferReceiverTypeBindings(function, receiverType)
        if inferred == null {
            inferred = sourceOverloads.InferGenericBindings(function, call, new List<TypeInfo>(), receiverType)
        }
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

    // The ordinary call validator substitutes the inferred receiver bindings into its result. Keep
    // the exact same selected type arguments on the await binding as a final closed result boundary:
    // source extension metadata can retain its open declaration return after overload selection.
    static func ApplySelectedSourceGenericArguments(function: FunctionTypeInfo, resultType: TypeInfo, typeArguments: TypeInfo[]): TypeInfo {
        parameters := function == null ? null : function.TypeParameters
        if parameters == null || parameters.Count == 0 || typeArguments == null || typeArguments.Length != parameters.Count {
            return resultType
        }
        bindings := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        index := 0
        while index < parameters.Count {
            if typeArguments[index] == null || BuiltInTypes.IsUnknown(typeArguments[index]) {
                return resultType
            }
            bindings[parameters[index].Name] = typeArguments[index]
            index += 1
        }
        substitutedResult := AnalyzerSyntheticCallFacts.ApplyGenericBindings(resultType, bindings)
        return substitutedResult
    }

    static func TryConstructReflectedAwaitableType(awaitableType: TypeInfo, clrConversion: AnalyzerClrTypeConversion): Type? {
        constructed := awaitableType as GenericTypeInfo
        definition := constructed == null ? null : constructed.GenericDefinition as ReflectionTypeInfo
        if constructed != null && definition != null && constructed.TypeArguments.Count == 1 && BuiltInTypes.Is(constructed.TypeArguments[0], BuiltInTypes.Void) {
            if AnalyzerFunctionTypeFactory.IsCoreTaskFamilyType(definition.Type, "System.Threading.Tasks.Task`1") {
                return AnalyzerFunctionTypeFactory.RequiredCoreType("System.Threading.Tasks.Task")
            }
            if AnalyzerFunctionTypeFactory.IsCoreTaskFamilyType(definition.Type, "System.Threading.Tasks.ValueTask`1") {
                return AnalyzerFunctionTypeFactory.RequiredCoreType("System.Threading.Tasks.ValueTask")
            }
        }
        exact := clrConversion.TryConvertTypeInfoToClrType(awaitableType)
        if exact != null {
            return exact
        }
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
        return AwaiterMemberInvocation("GetAwaiter")
    }

    static func AwaiterMemberInvocation(name: string): CallExpression {
        receiver: Expression = new IdentifierExpression("awaitable", 1, 1)
        callee: Expression = new MemberAccessExpression(receiver, name, false, 1, 1)
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

    static func FilterReflectedGetAwaiterExtensions(candidates: MethodInfo[]): MethodInfo[] {
        accepted := new List<MethodInfo>()
        if candidates == null {
            return accepted.ToArray()
        }
        for candidate in candidates {
            if candidate == null || !candidate.IsStatic || !HasExtensionAttribute(candidate) {
                continue
            }
            parameters := candidate.GetParameters()
            if parameters.Length > 0 {
                accepted.Add(candidate)
            }
        }
        return accepted.ToArray()
    }

    // C# binds the ordinary extension invocation before applying the await-specific restriction.
    // Keep optional and params receivers in overload resolution so a more-specific invalid method
    // cannot be hidden by a less-specific base overload, then reject the selected invocation here.
    static func SourceGetAwaiterUsesOptionalOrExpandedReceiver(function: FunctionTypeInfo): bool {
        if function == null || !function.SourceHasReceiverParameter || function.SourceParameterCount < 1 {
            return false
        }
        declaration := function.SourceDeclaration
        if declaration == null || declaration.Parameters.Count < 1 {
            return false
        }
        receiver := declaration.Parameters[0]
        if receiver.DefaultValue != null || receiver.Modifier == Ast.ParameterModifier.Params {
            return true
        }
        return false
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
        if definition != null {
            return definition.Type
        }
        return null
    }

    static func TryBindAnalyzerSelectedAwaiter(awaitableType: TypeInfo, awaiterType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel, memberResolution: AnalyzerMemberResolution, sourceOverloads: AnalyzerSyntheticCallWalk, sourceValidator: AnalyzerSyntheticCallValidator, reflectionArguments: AnalyzerReflectionArgumentBinder, accessingTypeName: string?, selectedFunction: FunctionTypeInfo?, selectedMethod: MethodInfo?, isExtension: bool, clrConversion: AnalyzerClrTypeConversion, getAwaiterTypeArguments: TypeInfo[], out binding: AnalyzerAwaitablePatternBinding?): bool {
        binding = null
        if awaiterType == null || BuiltInTypes.IsUnknown(awaiterType) || awaiterType == BuiltInTypes.Void {
            return false
        }
        reflectedLookupType := AnalyzerSelectedReflectedAwaiterLookupType(awaiterType, selectedMethod, clrConversion)
        // A constructed reflected awaiter can have no direct CLR handle while its reference
        // TypeInfo still contains the inferred owner arguments (notably for a generic extension
        // GetAwaiter<T>). Bind its members through the same member and invocation services before
        // trying source declarations. This preserves the closed semantic result even when the
        // metadata handle itself remains open.
        reflectedDefinition := awaiterType as ReflectionTypeInfo
        constructedReflected := awaiterType as GenericTypeInfo
        hasReflectedOwner := reflectedDefinition != null || (constructedReflected != null && constructedReflected.GenericDefinition as ReflectionTypeInfo != null)
        if hasReflectedOwner {
            reflectedResult: TypeInfo = BuiltInTypes.Unknown
            reflectedPattern: AwaitablePatternBinding? = null
            reflectedBound := TryBindAnalyzerReflectedAwaiter(reflectedLookupType, memberResolution, reflectionArguments, clrConversion, accessingTypeName, out reflectedResult, out reflectedPattern)
            if !reflectedBound || reflectedPattern == null {
                return false
            }
            runtimeAwaitableType := TryConstructReflectedAwaitableType(awaitableType, clrConversion)
            if runtimeAwaitableType == null {
                runtimeAwaitableType = ReflectionReceiverTypeForBinding(awaitableType, clrConversion)
            }
            if runtimeAwaitableType == null {
                return false
            }
            completePattern := new AwaitablePatternBinding(runtimeAwaitableType, reflectedPattern.AwaiterType, selectedMethod, reflectedPattern.IsCompletedGetter, reflectedPattern.GetResult, reflectedPattern.CompletionSlot, reflectedPattern.IsCritical, isExtension)
            binding = new AnalyzerAwaitablePatternBinding(awaitableType, awaiterType, reflectedResult, null, null, null, completePattern, null, selectedFunction, selectedMethod, isExtension, null, null, getAwaiterTypeArguments)
            return true
        }
        resultType: TypeInfo = BuiltInTypes.Unknown
        isCompleted: AnalyzerMemberSelection? = null
        getResult: AnalyzerMemberSelection? = null
        reflectedAwaiter: AwaitablePatternBinding? = null
        sourceAwaiter: SourceAwaiterPatternBinding? = null
        sourceAwaiterBound := TryBindAnalyzerSourceAwaiter(awaiterType, declarations, semanticModel, memberResolution, sourceOverloads, sourceValidator, accessingTypeName, out resultType, out isCompleted, out getResult, out reflectedAwaiter, out sourceAwaiter)
        if !sourceAwaiterBound {
            return false
        }
        sourceAwaiterOwner := declarations.ResolveDeclaredAlias(awaiterType)
        constructedSourceAwaiter := sourceAwaiterOwner as GenericTypeInfo
        if constructedSourceAwaiter != null && constructedSourceAwaiter.GenericDefinition != null && declarations.ContainsSourceType(constructedSourceAwaiter.GenericDefinition) {
            sourceAwaiterOwner = constructedSourceAwaiter.GenericDefinition
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

    // Reflection's ordinary member resolver needs the exact constructed CLR receiver in order to
    // resolve members declared on a closed generic awaiter. A reference TypeInfo can be an open
    // metadata definition paired with substituted type arguments; use the selected invocation's
    // runtime return only when the analyzer's closed type converts back to that exact CLR identity.
    // Source type parameters and metadata surrogates therefore keep their semantic spelling.
    static func AnalyzerSelectedReflectedAwaiterLookupType(awaiterType: TypeInfo, selectedMethod: MethodInfo?, clrConversion: AnalyzerClrTypeConversion): TypeInfo {
        if awaiterType == null || selectedMethod == null || selectedMethod.ReturnType == null || selectedMethod.ReturnType.ContainsGenericParameters || clrConversion == null {
            return awaiterType
        }
        closedSemanticType := clrConversion.TryConvertTypeInfoToClrType(awaiterType)
        if closedSemanticType != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(closedSemanticType, selectedMethod.ReturnType) {
            return new ReflectionTypeInfo(selectedMethod.ReturnType)
        }
        return awaiterType
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
            if attribute != null && attribute.AttributeType != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(attribute.AttributeType, typeof(ExtensionAttribute)) {
                return true
            }
        }
        return false
    }

    // The analyzer path binds reflected awaiter members through the same member-group and
    // reflection-call machinery as an ordinary invocation. The returned MethodInfo values are the
    // selected members, already closed over any inferred method arguments; lowering and the
    // playground only map those selected identities to their execution handles.
    static func TryBindAnalyzerReflectedAwaiter(awaiterType: TypeInfo, memberResolution: AnalyzerMemberResolution, reflectionArguments: AnalyzerReflectionArgumentBinder, clrConversion: AnalyzerClrTypeConversion, accessingTypeName: string?, out resultType: TypeInfo, out binding: AwaitablePatternBinding?): bool {
        reason := ""
        return TryBindAnalyzerReflectedAwaiter(awaiterType, memberResolution, reflectionArguments, clrConversion, accessingTypeName, out resultType, out binding, out reason)
    }

    static func TryBindAnalyzerReflectedAwaiter(awaiterType: TypeInfo, memberResolution: AnalyzerMemberResolution, reflectionArguments: AnalyzerReflectionArgumentBinder, clrConversion: AnalyzerClrTypeConversion, accessingTypeName: string?, out resultType: TypeInfo, out binding: AwaitablePatternBinding?, out failureReason: string): bool {
        resultType = BuiltInTypes.Unknown
        binding = null
        failureReason = ""
        if awaiterType == null || memberResolution == null || reflectionArguments == null || clrConversion == null || IsNullableValueType(awaiterType) {
            failureReason = "awaiter type or binding service is missing, or the awaiter is Nullable<T>"
            return false
        }

        exactRuntimeAwaiterType := TryConstructReflectedAwaitableType(awaiterType, clrConversion)
        runtimeAwaiterType := exactRuntimeAwaiterType
        if runtimeAwaiterType == null {
            constructed := awaiterType as GenericTypeInfo
            reflectedDefinition := constructed == null ? null : constructed.GenericDefinition as ReflectionTypeInfo
            if reflectedDefinition != null {
                // Reference types are read through MetadataLoadContext, while source generic
                // arguments can be execution Types. The binding surrogate gives reflection call
                // selection a closed receiver; its TypeInfo receiver still carries the source
                // argument, and the emitted handle is mapped back to the real constructed owner.
                runtimeAwaiterType = clrConversion.TryConvertTypeInfoToClrTypeForBinding(awaiterType)
                if runtimeAwaiterType == null {
                    runtimeAwaiterType = reflectedDefinition.Type
                }
            } else {
                runtimeAwaiterType = clrConversion.TryConvertTypeInfoToClrTypeForBinding(awaiterType)
            }
        }
        // Both closed metadata types and open/source-generic surrogates go through the ordinary
        // member-group and invocation resolvers below. The reflection-only entry point is reserved
        // for compiler-synthesized awaits that have no source await site to bind.
        lookupAwaiterType: TypeInfo = awaiterType
        if exactRuntimeAwaiterType != null {
            lookupAwaiterType = new ReflectionTypeInfo(exactRuntimeAwaiterType)
        }
        isCompletedType := memberResolution.ResolveMemberWithoutExtensionFallback(lookupAwaiterType, "IsCompleted", false, accessingTypeName, false)
        if !BuiltInTypes.Is(isCompletedType, BuiltInTypes.Bool) {
            failureReason = "ordinary member lookup did not find an accessible bool IsCompleted property"
            return false
        }
        if runtimeAwaiterType == null {
            failureReason = "the awaiter has no runtime binding type"
            return false
        }
        isCompletedProperty := SelectReadableBooleanProperty(runtimeAwaiterType, "IsCompleted")
        if isCompletedProperty == null || isCompletedProperty.GetIndexParameters().Length != 0 || isCompletedProperty.GetMethod == null || !isCompletedProperty.GetMethod.IsPublic || isCompletedProperty.GetMethod.IsStatic {
            failureReason = "the selected IsCompleted property has no accessible instance getter"
            return false
        }

        getResultGroup := memberResolution.ResolveMemberWithoutExtensionFallback(lookupAwaiterType, "GetResult", false, accessingTypeName, true)
        invocation := AwaiterMemberInvocation("GetResult")
        selected: ReflectionPreBoundCandidate? = null
        if !TrySelectReflectedAwaiterInvocation(AwaiterReflectionCandidates(getResultGroup), invocation, runtimeAwaiterType, lookupAwaiterType, reflectionArguments, false, out selected) || selected == null {
            failureReason = "ordinary invocation binding did not find a non-generic zero-argument GetResult method"
            return false
        }
        if selected.SignatureMethod.GetParameters().Length != 0 {
            failureReason = "the selected GetResult invocation used optional arguments or expanded a params array"
            return false
        }
        selectedGetResult := selected.RuntimeMethod
        resultType = AnalyzerReflectionSelectedReturnType(selected)
        if selectedGetResult == null {
            failureReason = "the selected GetResult method has no runtime handle"
            return false
        }
        if BuiltInTypes.IsUnknown(resultType) {
            failureReason = "the selected GetResult method has an unknown return type"
            return false
        }
        critical := FindCompletionInterface(runtimeAwaiterType, typeof(ICriticalNotifyCompletion)) != null
        hasNotify := FindCompletionInterface(runtimeAwaiterType, typeof(INotifyCompletion)) != null
        if !hasNotify {
            failureReason = "the awaiter does not implement INotifyCompletion"
            return false
        }
        contract := critical ? typeof(ICriticalNotifyCompletion) : typeof(INotifyCompletion)
        completionName := critical ? "UnsafeOnCompleted" : "OnCompleted"
        completionSlot := ResolveInterfaceSlot(runtimeAwaiterType, contract, completionName)
        if completionSlot == null {
            failureReason = "the awaiter has no mapped completion interface slot"
            return false
        }

        binding = new AwaitablePatternBinding(runtimeAwaiterType, runtimeAwaiterType, null, isCompletedProperty.GetMethod, selectedGetResult, completionSlot, critical)
        return true
    }

    static func ReflectionMethodTypeArgumentsAreInferred(candidate: ReflectionPreBoundCandidate): bool {
        if candidate == null || candidate.SignatureMethod == null || !candidate.SignatureMethod.IsGenericMethodDefinition {
            return candidate != null
        }
        for parameter in candidate.SignatureMethod.GetGenericArguments() {
            clrArgument: Type? = null
            typeInfoArgument: TypeInfo? = null
            if !candidate.Bindings.TryGetValue(parameter, out clrArgument) && !candidate.TypeInfoBindings.TryGetValue(parameter, out typeInfoArgument) {
                return false
            }
            if clrArgument == null && (typeInfoArgument == null || BuiltInTypes.IsUnknown(typeInfoArgument)) {
                return false
            }
        }
        return true
    }

    // The ordinary reflection call binder's candidate set is prebound by the same argument binder
    // used for source calls. An await-pattern invocation has one expression argument at most (the
    // extension receiver), so this shared comparison applies C#'s conversion, hiding and generic
    // tie-breaks over that one position and refuses an ambiguous maximal set.
    static func TrySelectReflectedAwaiterInvocation(methods: MethodInfo[], call: CallExpression, receiverClrType: Type, receiverTypeInfo: TypeInfo, arguments: AnalyzerReflectionArgumentBinder, requireExtension: bool, out selected: ReflectionPreBoundCandidate?): bool {
        selected = null
        if methods == null || call == null || receiverClrType == null || arguments == null {
            return false
        }
        candidates := new List<ReflectionPreBoundCandidate>()
        for method in methods {
            isExtension := AnalyzerOverloadFacts.IsExtensionMethodCallOnReceiver(method, call, receiverClrType)
            if isExtension != requireExtension || (!isExtension && method.IsStatic) {
                continue
            }
            candidate := arguments.PreBindReflectionMethod(method, call, receiverClrType, receiverTypeInfo, new TypeInfo?[](0))
            if candidate != null && ReflectionMethodTypeArgumentsAreInferred(candidate) {
                candidates.Add(candidate)
            }
        }
        if candidates.Count == 0 {
            return false
        }
        if candidates.Count == 1 {
            selected = candidates[0]
            return true
        }

        count := candidates.Count
        comparisons := new int[count * count]
        row := 0
        while row < count {
            column := 0
            while column < count {
                if row != column {
                    comparisons[row * count + column] = CompareReflectedAwaiterInvocations(candidates[row], candidates[column], receiverClrType, requireExtension)
                }
                column += 1
            }
            row += 1
        }
        maximal := AnalyzerOverloadSpecificity.FindMaximalIndexes(comparisons, count)
        if maximal.Count != 1 {
            return false
        }
        selected = candidates[maximal[0]]
        return true
    }

    static func CompareReflectedAwaiterInvocations(left: ReflectionPreBoundCandidate, right: ReflectionPreBoundCandidate, receiverType: Type, isExtension: bool): int {
        if left.Score != right.Score {
            return left.Score > right.Score ? AnalyzerOverloadSpecificity.LeftIsBetter : AnalyzerOverloadSpecificity.RightIsBetter
        }
        if left.DefaultsUsed != right.DefaultsUsed {
            return left.DefaultsUsed < right.DefaultsUsed ? AnalyzerOverloadSpecificity.LeftIsBetter : AnalyzerOverloadSpecificity.RightIsBetter
        }
        if left.UsesParams != right.UsesParams {
            return left.UsesParams ? AnalyzerOverloadSpecificity.RightIsBetter : AnalyzerOverloadSpecificity.LeftIsBetter
        }

        leftParameters := left.SignatureMethod.GetParameters()
        rightParameters := right.SignatureMethod.GetParameters()
        parameterOffset := isExtension ? 1 : 0
        if leftParameters.Length < parameterOffset || rightParameters.Length < parameterOffset {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }
        sameParameters := true
        openLeft := new Type[](isExtension ? 1 : 0)
        openRight := new Type[](isExtension ? 1 : 0)
        if isExtension {
            leftType := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(leftParameters[parameterOffset].ParameterType, left.Bindings)
            rightType := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(rightParameters[parameterOffset].ParameterType, right.Bindings)
            sameParameters = TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(leftType, rightType)
            conversion := AnalyzerOverloadSpecificity.CompareConversionTargets(
                TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(leftType, receiverType),
                TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(rightType, receiverType),
                AnalyzerConversionFacts.IsReflectionAssignableFrom(rightType, leftType),
                AnalyzerConversionFacts.IsReflectionAssignableFrom(leftType, rightType)
            )
            if conversion != AnalyzerOverloadSpecificity.NeitherIsBetter {
                return conversion
            }
            openLeft[0] = leftParameters[parameterOffset].ParameterType
            openRight[0] = rightParameters[parameterOffset].ParameterType
        }

        declaringVerdict := CompareReflectionDeclaringDepth(left.RuntimeMethod.DeclaringType, right.RuntimeMethod.DeclaringType)
        if declaringVerdict != AnalyzerOverloadSpecificity.NeitherIsBetter {
            return declaringVerdict
        }
        return AnalyzerOverloadSpecificity.CompareTieBreaks(
            sameParameters,
            left.SignatureMethod.IsGenericMethodDefinition,
            right.SignatureMethod.IsGenericMethodDefinition,
            left.UsesParams,
            right.UsesParams,
            left.DefaultsUsed,
            right.DefaultsUsed,
            AnalyzerOpenTypeSpecificity.CompareReflectionParameterLists(openLeft, openRight)
        )
    }

    static func CompareReflectionDeclaringDepth(left: Type?, right: Type?): int {
        if left == null || right == null || TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(left, right) {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }
        leftDerives := AnalyzerConversionFacts.IsReflectionAssignableFrom(right, left)
        rightDerives := AnalyzerConversionFacts.IsReflectionAssignableFrom(left, right)
        if leftDerives == rightDerives {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }
        return leftDerives ? AnalyzerOverloadSpecificity.LeftIsBetter : AnalyzerOverloadSpecificity.RightIsBetter
    }

    static func TryBindAnalyzerSourceAwaiter(awaiterType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel, memberResolution: AnalyzerMemberResolution, sourceOverloads: AnalyzerSyntheticCallWalk, sourceValidator: AnalyzerSyntheticCallValidator, accessingTypeName: string?, out resultType: TypeInfo, out isCompleted: AnalyzerMemberSelection?, out getResult: AnalyzerMemberSelection?, out reflectedBinding: AwaitablePatternBinding?, out sourceBinding: SourceAwaiterPatternBinding?): bool {
        resultType = BuiltInTypes.Unknown
        isCompleted = null
        getResult = null
        reflectedBinding = null
        sourceBinding = null
        resolvedAwaiter := declarations.ResolveDeclaredAlias(awaiterType)
        constructed := resolvedAwaiter as GenericTypeInfo
        sourceAwaiterLookupType := resolvedAwaiter
        if constructed != null {
            if constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
                sourceAwaiterLookupType = constructed.GenericDefinition
            } else {
                return false
            }
        }

        if !declarations.ContainsSourceType(sourceAwaiterLookupType) {
            return false
        }

        substitution := AnalyzerSourceAwaitSubstitution(resolvedAwaiter)
        isCompletedSelection := new AnalyzerMemberSelection()
        isCompletedType: TypeInfo = BuiltInTypes.Unknown
        if !declarations.TryFindMember(sourceAwaiterLookupType, "IsCompleted", out isCompletedSelection) || isCompletedSelection.Member == null || !IsSourceReadableAwaiterProperty(isCompletedSelection) || isCompletedSelection.Member.IsStatic || !IsSourceMemberAccessible(isCompletedSelection.Member, accessingTypeName) || isCompletedSelection.Member.Type == null || !declarations.TryResolveTypeForOwner(isCompletedSelection.Member.Type, isCompletedSelection.Owner, substitution, out isCompletedType) || !BuiltInTypes.Is(isCompletedType, BuiltInTypes.Bool) {
            member := isCompletedSelection.Member
            return false
        }

        hasCritical := TypeInfoImplementsCompletionInterface(resolvedAwaiter, typeof(ICriticalNotifyCompletion), semanticModel, 0) || HasReflectedCompletionBase(resolvedAwaiter, declarations, semanticModel, typeof(ICriticalNotifyCompletion))
        critical := hasCritical
        hasNotify := TypeInfoImplementsCompletionInterface(resolvedAwaiter, typeof(INotifyCompletion), semanticModel, 0) || HasReflectedCompletionBase(resolvedAwaiter, declarations, semanticModel, typeof(INotifyCompletion))
        if !hasNotify {
            return false
        }

        getResultInvocation := AwaiterMemberInvocation("GetResult")
        getResultMember := memberResolution.ResolveMemberWithoutExtensionFallback(sourceAwaiterLookupType, "GetResult", false, accessingTypeName, true)
        sourceCandidates := AwaiterSourceCandidates(getResultMember)
        if sourceCandidates == null {
            return false
        }
        selectedGetResult := sourceOverloads.BindNSharpCall(sourceCandidates, getResultInvocation, new List<TypeInfo>(), resolvedAwaiter)
        getResultSelection := new AnalyzerMemberSelection()
        if selectedGetResult == null || selectedGetResult.SourceIsStatic || selectedGetResult.SourceHasReceiverParameter || selectedGetResult.SourceParameterCount != 0 || (selectedGetResult.TypeParameters != null && selectedGetResult.TypeParameters.Count != 0) || !TryFindSourceMemberSelection(selectedGetResult, resolvedAwaiter, declarations, out getResultSelection) || getResultSelection.Member == null {
            return false
        }
        resultType = sourceValidator.ResolveReturnType(selectedGetResult, getResultInvocation, new List<TypeInfo>(), resolvedAwaiter)
        // Member lookup for a source constructed type is keyed by its declaration owner so it can
        // find the shared member table. Close the selected GetResult return over that constructed
        // awaiter before publishing the binding; otherwise `Awaiter<int>.GetResult(): T` leaks the
        // declaration's open T to analysis even though the selected awaiter itself is closed.
        resultType = AnalyzerSyntheticCallFacts.ApplyGenericBindings(resultType, substitution)
        if BuiltInTypes.IsUnknown(resultType) {
            return false
        }
        selectedProperty := SourcePropertyForSelection(declarations, isCompletedSelection)
        selectedGetResultDeclaration := getResultSelection.Member.SourceDeclaration
        if selectedProperty == null || selectedGetResultDeclaration == null {
            return false
        }
        sourceInterfaceAwaiter := IsSourceInterfaceType(resolvedAwaiter, declarations)
        completionName := critical ? "UnsafeOnCompleted" : "OnCompleted"
        contract := critical ? typeof(ICriticalNotifyCompletion) : typeof(INotifyCompletion)
        completion: FunctionDeclaration? = null
        if !sourceInterfaceAwaiter {
            completion = FindSourceInterfaceImplementation(resolvedAwaiter, declarations, semanticModel, contract, completionName)
        }
        slot := ResolveInterfaceSlot(contract, contract, completionName)
        if slot == null || (completion == null && !sourceInterfaceAwaiter && !HasReflectedCompletionBase(resolvedAwaiter, declarations, semanticModel, contract)) {
            return false
        }
        sourceBinding = new SourceAwaiterPatternBinding(selectedProperty, isCompletedSelection.Member.Name, selectedGetResultDeclaration, completion, slot, critical)
        isCompleted = isCompletedSelection
        getResult = getResultSelection
        return true
    }

    static func IsSourceInterfaceType(candidate: TypeInfo, declarations: AnalyzerDeclarationContext): bool {
        if candidate == null || declarations == null {
            return false
        }
        resolved := declarations.ResolveDeclaredAlias(candidate)
        if resolved as InterfaceTypeInfo != null && declarations.ContainsSourceType(resolved) {
            return true
        }
        constructed := resolved as GenericTypeInfo
        genericDefinition := constructed == null ? null : constructed.GenericDefinition
        return genericDefinition != null && genericDefinition as InterfaceTypeInfo != null && declarations.ContainsSourceType(genericDefinition)
    }

    static func IsSourceInterfaceTypeInfo(candidate: TypeInfo): bool {
        if candidate as InterfaceTypeInfo != null {
            return true
        }
        constructed := candidate as GenericTypeInfo
        return constructed != null && constructed.GenericDefinition as InterfaceTypeInfo != null
    }

    // A source-derived class can inherit its exact completion interface implementation from a
    // referenced CLR base. Source declarations are walked first (including every source base); the
    // first reflected base is then checked through its actual interface closure and method map.
    // The emitter calls the shared interface slot on the fully derived object, so the CLR performs
    // the same inherited dispatch as any ordinary awaiter call.
    static func HasReflectedCompletionBase(ownerType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel, contract: Type): bool {
        if ownerType == null || declarations == null || semanticModel == null || contract == null {
            return false
        }

        current := declarations.ResolveDeclaredAlias(ownerType)
        depth := 0
        while current != null && depth < 32 {
            sourceType := current
            constructed := current as GenericTypeInfo
            if constructed != null && constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
                sourceType = constructed.GenericDefinition
            }
            if !declarations.ContainsSourceType(sourceType) {
                break
            }
            shape := SourceShapeForType(current, declarations)
            if shape == null || shape.BaseType == null {
                return false
            }
            next := shape.BaseType
            reflected := next as ReflectionTypeInfo
            constructedBase := next as GenericTypeInfo
            if reflected == null && constructedBase != null {
                reflected = constructedBase.GenericDefinition as ReflectionTypeInfo
            }
            if reflected != null {
                completionName := contract == typeof(ICriticalNotifyCompletion) ? "UnsafeOnCompleted" : "OnCompleted"
                return FindCompletionInterface(reflected.Type, contract) != null && ResolveInterfaceSlot(reflected.Type, contract, completionName) != null
            }
            current = next
            depth += 1
        }
        return false
    }

    static func TryFindSourceMemberSelection(function: FunctionTypeInfo, ownerType: TypeInfo, declarations: AnalyzerDeclarationContext, out selection: AnalyzerMemberSelection): bool {
        selection = new AnalyzerMemberSelection()
        if function == null || declarations == null {
            return false
        }
        for sourceType in SourceTypeChain(ownerType, declarations) {
            shape := SourceShapeForType(sourceType, declarations)
            if shape == null {
                continue
            }
            filePath := declarations.GetDeclarationFile(shape.Owner)
            for member in shape.DeclaredMembers {
                sameDeclaration := member.SourceDeclaration != null && member.SourceDeclaration == function.SourceDeclaration
                sameSourcePosition := member.Line == function.SourceLine && member.Column == function.SourceColumn && filePath != null && function.SourceFilePath != null && string.Equals(filePath, function.SourceFilePath, StringComparison.OrdinalIgnoreCase)
                if member.Kind == DeclaredMemberKind.Function && (sameDeclaration || sameSourcePosition) {
                    selection = new AnalyzerMemberSelection(shape.Owner, member, filePath, member.Line, member.Column, "function", member.IsExported)
                    return true
                }
            }
        }
        return false
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

    // Source classes are not baked while analysis runs, so the CLR cannot answer GetInterfaceMap.
    // Resolve the same interface slot against the declaration chain here: exact Action signature,
    // explicit slot first, then the nearest public implicit implementation. The returned function
    // is retained for the playground interpreter; emitted code dispatches through CompletionSlot.
    static func FindSourceInterfaceImplementation(ownerType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel, contractType: Type, methodName: string): FunctionDeclaration? {
        sourceChain := SourceTypeChain(ownerType, declarations)
        for sourceType in sourceChain {
            shape := SourceShapeForType(sourceType, declarations)
            if shape == null {
                continue
            }
            for member in shape.DeclaredMembers {
                function := member.SourceDeclaration
                if function == null || !ExplicitInterfaceMemberFacts.IsExplicitMemberName(function.Name) || ExplicitInterfaceMemberFacts.SimpleNameOf(function.Name) != methodName || !SourceCompletionMemberHasExactActionSignature(member, function, semanticModel, methodName) {
                    continue
                }
                qualifier := ExplicitInterfaceMemberFacts.QualifierOf(function.Name)
                if SourceTypeClosureContainsQualifier(sourceType, qualifier, contractType, semanticModel, 0) {
                    return function
                }
            }
        }

        for sourceType in sourceChain {
            shape := SourceShapeForType(sourceType, declarations)
            if shape == null {
                continue
            }
            for member in shape.DeclaredMembers {
                function := member.SourceDeclaration
                if function == null || ExplicitInterfaceMemberFacts.IsExplicitMemberName(function.Name) || function.Name != methodName || !IsPublicSourceFunction(function) || !SourceCompletionMemberHasExactActionSignature(member, function, semanticModel, methodName) {
                    continue
                }
                return function
            }
        }
        return null
    }

    static func SourceAwaiterMemberName(member: Declaration): string? {
        field := member as FieldDeclaration
        if field != null {
            return field.Name
        }
        property := member as PropertyDeclaration
        if property != null {
            return property.Name
        }
        return null
    }

    static func SourceAwaiterMemberType(member: Declaration): TypeReference? {
        field := member as FieldDeclaration
        if field != null {
            return field.Type
        }
        property := member as PropertyDeclaration
        if property != null {
            return property.Type
        }
        return null
    }

    static func IsPublicSourceProperty(property: PropertyDeclaration): bool {
        if property == null {
            return false
        }
        modifiers := Convert.ToInt32(property.Modifiers)
        return (modifiers & Convert.ToInt32(Modifiers.Private)) == 0 && (modifiers & Convert.ToInt32(Modifiers.Protected)) == 0
    }

    static func SourceTypeClosureContainsQualifier(typeInfo: TypeInfo, qualifier: string, expectedType: TypeInfo, semanticModel: SemanticModel, depth: int): bool {
        if typeInfo == null || expectedType == null || semanticModel == null || depth > 32 {
            return false
        }
        if TypeInfoIdentityFacts.AreEqual(typeInfo, expectedType) {
            return false
        }
        reflected := typeInfo as ReflectionTypeInfo
        if reflected != null {
            expectedReflection := expectedType as ReflectionTypeInfo
            for implemented in reflected.Type.GetInterfaces() {
                if expectedReflection != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(implemented, expectedReflection.Type) && (implemented.Name == qualifier || implemented.FullName == qualifier) {
                    return true
                }
                if SourceTypeClosureContainsQualifier(new ReflectionTypeInfo(implemented), qualifier, expectedType, semanticModel, depth + 1) {
                    return true
                }
            }
            baseType := reflected.Type.BaseType
            return baseType != null && SourceTypeClosureContainsQualifier(new ReflectionTypeInfo(baseType), qualifier, expectedType, semanticModel, depth + 1)
        }
        constructed := typeInfo as GenericTypeInfo
        substitution := AnalyzerSourceAwaitSubstitution(typeInfo)
        if constructed != null && constructed.GenericDefinition != null {
            typeInfo = constructed.GenericDefinition
        }
        references := SourceTypeReferences(typeInfo)
        if references == null {
            return false
        }
        for reference in references {
            resolved: TypeInfo = BuiltInTypes.Unknown
            if !TryResolveSourceTypeReference(semanticModel, reference, out resolved) {
                continue
            }
            resolved = AnalyzerSyntheticCallFacts.ApplyGenericBindings(resolved, substitution)
            if SourceQualifierIdentifiesResolvedReference(semanticModel, reference, qualifier, resolved) && SourceTypeIncludesInterface(resolved, expectedType, semanticModel, 0) {
                return true
            }
            if SourceTypeClosureContainsQualifier(resolved, qualifier, expectedType, semanticModel, depth + 1) {
                return true
            }
        }
        return false
    }

    static func SourceTypeIncludesInterface(typeInfo: TypeInfo, expectedType: TypeInfo, semanticModel: SemanticModel, depth: int): bool {
        if typeInfo == null || expectedType == null || semanticModel == null || depth > 32 {
            return false
        }
        if TypeInfoIdentityFacts.AreEqual(typeInfo, expectedType) {
            return true
        }
        reflected := typeInfo as ReflectionTypeInfo
        if reflected != null {
            expectedReflection := expectedType as ReflectionTypeInfo
            if expectedReflection != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(reflected.Type, expectedReflection.Type) {
                return true
            }
            for implemented in reflected.Type.GetInterfaces() {
                if expectedReflection != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(implemented, expectedReflection.Type) {
                    return true
                }
            }
            return false
        }
        constructed := typeInfo as GenericTypeInfo
        substitution := AnalyzerSourceAwaitSubstitution(typeInfo)
        if constructed != null && constructed.GenericDefinition != null {
            typeInfo = constructed.GenericDefinition
        }
        references := SourceTypeReferences(typeInfo)
        if references == null {
            return false
        }
        for reference in references {
            resolved: TypeInfo = BuiltInTypes.Unknown
            if TryResolveSourceTypeReference(semanticModel, reference, out resolved) {
                resolved = AnalyzerSyntheticCallFacts.ApplyGenericBindings(resolved, substitution)
                if SourceTypeIncludesInterface(resolved, expectedType, semanticModel, depth + 1) {
                    return true
                }
            }
        }
        return false
    }

    static func SourceTypeReferences(typeInfo: TypeInfo): List<TypeReference>? {
        references := new List<TypeReference>()
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            if classType.BaseClass != null {
                references.Add(classType.BaseClass)
            }
            references.AddRange(classType.Interfaces)
            return references
        }
        structType := typeInfo as StructTypeInfo
        if structType != null {
            references.AddRange(structType.Interfaces)
            return references
        }
        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            references.AddRange(recordType.Interfaces)
            return references
        }
        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            references.AddRange(interfaceType.BaseInterfaces)
            return references
        }
        return null
    }

    static func SourceFunctionMatchesInterfaceSlot(function: FunctionDeclaration, sourceSlot: FunctionDeclaration?, runtimeSlot: MethodInfo?, slotOwnerType: TypeInfo?, semanticModel: SemanticModel, implementationOwnerType: TypeInfo? = null): bool {
        if function == null || semanticModel == null || sourceSlot == null && runtimeSlot == null || function.TypeParameters != null && function.TypeParameters.Count != 0 {
            return false
        }
        slotParameterCount := 0
        if sourceSlot != null {
            slotParameterCount = sourceSlot.Parameters.Count
        } else {
            if runtimeSlot == null {
                return false
            }
            slotParameterCount = runtimeSlot.GetParameters().Length
        }
        if function.Parameters.Count != slotParameterCount {
            return false
        }
        slotSubstitution: Dictionary<string, TypeInfo>? = null
        if slotOwnerType != null {
            slotSubstitution = AnalyzerSourceAwaitSubstitution(slotOwnerType)
        }
        implementationSubstitution := implementationOwnerType == null ? null : AnalyzerSourceAwaitSubstitution(implementationOwnerType)
        index := 0
        while index < slotParameterCount {
            if function.Parameters[index].Type == null {
                return false
            }
            actualParameter: TypeInfo = BuiltInTypes.Unknown
            expectedParameter: TypeInfo = BuiltInTypes.Unknown
            if !TryResolveSourceTypeReference(semanticModel, function.Parameters[index].Type, out actualParameter) {
                return false
            }
            actualParameter = AnalyzerSyntheticCallFacts.ApplyGenericBindings(actualParameter, implementationSubstitution)
            if sourceSlot != null {
                if sourceSlot.Parameters[index].Type == null || !TryResolveSourceTypeReference(semanticModel, sourceSlot.Parameters[index].Type, out expectedParameter) {
                    return false
                }
            } else {
                if runtimeSlot == null {
                    return false
                }
                expectedParameter = AnalyzerReflectionTypeConversion.ConvertReflectionType(runtimeSlot.GetParameters()[index].ParameterType)
            }
            expectedParameter = AnalyzerSyntheticCallFacts.ApplyGenericBindings(expectedParameter, slotSubstitution)
            if !SourceInterfaceSlotTypesMatch(actualParameter, expectedParameter) {
                return false
            }
            index += 1
        }

        actualReturn: TypeInfo = BuiltInTypes.Void
        if function.ReturnType != null && !TryResolveSourceTypeReference(semanticModel, function.ReturnType, out actualReturn) {
            return false
        }
        actualReturn = AnalyzerSyntheticCallFacts.ApplyGenericBindings(actualReturn, implementationSubstitution)
        expectedReturn: TypeInfo = BuiltInTypes.Void
        if sourceSlot != null && sourceSlot.ReturnType != null {
            if !TryResolveSourceTypeReference(semanticModel, sourceSlot.ReturnType, out expectedReturn) {
                return false
            }
        } else {
            if runtimeSlot == null {
                return false
            }
            expectedReturn = AnalyzerReflectionTypeConversion.ConvertReflectionType(runtimeSlot.ReturnType)
        }
        expectedReturn = AnalyzerSyntheticCallFacts.ApplyGenericBindings(expectedReturn, slotSubstitution)
        return SourceInterfaceSlotTypesMatch(actualReturn, expectedReturn)
    }

    // Build the interface dispatch facts for one constructed source object while its closed owner
    // type is still available to the analyzer. The playground attaches this immutable map to the
    // object and executes it directly; it never searches methods by name or repeats generic
    // substitution while an await is suspended.
    static func BuildSourceInterfaceImplementationMap(ownerType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel): List<AnalyzerInterfaceSlotImplementation> {
        result := new List<AnalyzerInterfaceSlotImplementation>()
        if ownerType == null || declarations == null || semanticModel == null {
            return result
        }
        interfaces := new List<TypeInfo>()
        CollectSourceInterfaceClosure(ownerType, declarations, semanticModel, interfaces, 0)
        for interfaceType in interfaces {
            sourceDefinition := declarations.ResolveDeclaredAlias(interfaceType)
            constructed := sourceDefinition as GenericTypeInfo
            if constructed != null && constructed.GenericDefinition != null {
                sourceDefinition = constructed.GenericDefinition
            }
            if declarations.ContainsSourceType(sourceDefinition) {
                shape := SourceShapeForType(interfaceType, declarations)
                if shape == null {
                    continue
                }
                interfaceDeclarationType := interfaceType
                constructedInterface := interfaceType as GenericTypeInfo
                if constructedInterface != null && constructedInterface.GenericDefinition != null {
                    interfaceDeclarationType = constructedInterface.GenericDefinition
                }
                interfaceDeclaration := declarations.FindDeclarationForType(interfaceDeclarationType) as Declaration
                sourceMembers := interfaceDeclaration == null ? null : SourceMembers(interfaceDeclaration)
                if sourceMembers == null {
                    continue
                }
                for slot in sourceMembers {
                    functionSlot := slot as FunctionDeclaration
                    if functionSlot != null {
                        implementation := FindSourceInterfaceImplementationForConstructedOwner(ownerType, functionSlot, null, interfaceType, declarations, semanticModel)
                        if implementation != null {
                            result.Add(new AnalyzerInterfaceSlotImplementation(slot, null, interfaceType, implementation))
                        }
                        continue
                    }
                    if slot as FieldDeclaration != null || slot as PropertyDeclaration != null {
                        implementation := FindSourceInterfacePropertyImplementationForConstructedOwner(ownerType, slot, interfaceType, declarations, semanticModel)
                        if implementation != null {
                            result.Add(new AnalyzerInterfaceSlotImplementation(slot, null, interfaceType, implementation))
                        }
                    }
                }
                continue
            }

            reflectedInterface := interfaceType as ReflectionTypeInfo
            if reflectedInterface == null || !reflectedInterface.Type.IsInterface {
                continue
            }
            for runtimeSlot in reflectedInterface.Type.GetMethods() {
                if runtimeSlot.IsStatic {
                    continue
                }
                implementation := FindSourceInterfaceImplementationForConstructedOwner(ownerType, null, runtimeSlot, interfaceType, declarations, semanticModel)
                if implementation != null {
                    result.Add(new AnalyzerInterfaceSlotImplementation(null, runtimeSlot, interfaceType, implementation))
                }
            }
        }
        AddSelectedSourceDuckInterfaceImplementations(ownerType, declarations, semanticModel, result)
        return result
    }

    // A duck conversion binds against a source interface contract but does not add that interface
    // to the concrete type's nominal interface list. Use only duck slots already selected in the
    // semantic model, then attach the exact source implementation to the constructed owner's
    // dispatch facts. AnalyzerConstruction calls this again after the complete declaration walk so
    // constructions that appear before the selected call in source order receive the same map.
    static func AddSelectedSourceDuckInterfaceImplementations(ownerType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel, result: List<AnalyzerInterfaceSlotImplementation>) {
        if ownerType == null || declarations == null || semanticModel == null || result == null {
            return
        }
        for invocationBinding in semanticModel.InvocationBindings.Values {
            if invocationBinding == null || invocationBinding.IsExtension || invocationBinding.SourceFunction == null || invocationBinding.SourceSlotOwnerType == null {
                continue
            }
            functionSlot := invocationBinding.SourceFunction.SourceDeclaration
            if functionSlot == null {
                continue
            }
            slotOwner := declarations.ResolveDeclaredAlias(invocationBinding.SourceSlotOwnerType)
            constructedSlotOwner := slotOwner as GenericTypeInfo
            if constructedSlotOwner != null && constructedSlotOwner.GenericDefinition != null {
                slotOwner = constructedSlotOwner.GenericDefinition
            }
            duckInterface := slotOwner as InterfaceTypeInfo
            if duckInterface == null || !duckInterface.IsDuckInterface {
                continue
            }
            alreadyMapped := false
            for mapping in result {
                if Object.ReferenceEquals(mapping.SlotDeclaration, functionSlot) && mapping.SlotOwnerType != null && TypeInfoIdentityFacts.AreEqual(mapping.SlotOwnerType, invocationBinding.SourceSlotOwnerType) {
                    alreadyMapped = true
                    break
                }
            }
            if alreadyMapped {
                continue
            }
            implementation := FindSourceInterfaceImplementationForConstructedOwner(ownerType, functionSlot, null, invocationBinding.SourceSlotOwnerType, declarations, semanticModel)
            if implementation != null {
                result.Add(new AnalyzerInterfaceSlotImplementation(functionSlot, null, invocationBinding.SourceSlotOwnerType, implementation))
            }
        }
    }

    // Preserve ordinary virtual dispatch for source objects in the playground with the same
    // analyzer-selected slot identity used for interface dispatch. The runner receives this map
    // from the constructed owner; it never selects an override by name or arity at execution time.
    static func BuildSourceVirtualImplementationMap(ownerType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel): List<AnalyzerInterfaceSlotImplementation> {
        result := new List<AnalyzerInterfaceSlotImplementation>()
        if ownerType == null || declarations == null || semanticModel == null {
            return result
        }
        chain := SourceVirtualTypeChain(ownerType, declarations)
        ownerIndex := 0
        while ownerIndex < chain.Count {
            slotOwnerType := chain[ownerIndex]
            shape := SourceShapeForType(slotOwnerType, declarations)
            if shape != null {
                for slotMember in shape.DeclaredMembers {
                    slot := slotMember.SourceDeclaration as FunctionDeclaration
                    if slot == null || !slotMember.IsOverridable {
                        continue
                    }
                    implementation: FunctionDeclaration? = null
                    implementationIndex := 0
                    while implementationIndex <= ownerIndex && implementation == null {
                        implementationShape := SourceShapeForType(chain[implementationIndex], declarations)
                        if implementationShape != null {
                            for candidateMember in implementationShape.DeclaredMembers {
                                candidate := candidateMember.SourceDeclaration as FunctionDeclaration
                                isOverride := candidate != null && AnalyzerAmbientContext.HasModifier(candidate, Modifiers.Override)
                                if candidate == null || candidate.Name != slot.Name || !Object.ReferenceEquals(candidate, slot) && !isOverride {
                                    continue
                                }
                                if Object.ReferenceEquals(candidate, slot) || SourceFunctionParameterSignatureMatches(candidate, slot, slotOwnerType, semanticModel, chain[implementationIndex]) {
                                    implementation = candidate
                                    break
                                }
                            }
                        }
                        implementationIndex += 1
                    }
                    if implementation != null {
                        result.Add(new AnalyzerInterfaceSlotImplementation(slot, null, slotOwnerType, implementation))
                    }
                }
            }
            ownerIndex += 1
        }
        return result
    }

    // Override dispatch is selected by the parameter signature; covariant return types do not
    // create a different virtual slot. The ordinary override validator checks the return contract.
    static func SourceFunctionParameterSignatureMatches(function: FunctionDeclaration, sourceSlot: FunctionDeclaration, slotOwnerType: TypeInfo, semanticModel: SemanticModel, implementationOwnerType: TypeInfo): bool {
        if function == null || sourceSlot == null || slotOwnerType == null || implementationOwnerType == null || semanticModel == null || function.TypeParameters != null && function.TypeParameters.Count != 0 || function.Parameters.Count != sourceSlot.Parameters.Count {
            return false
        }
        slotSubstitution := AnalyzerSourceAwaitSubstitution(slotOwnerType)
        implementationSubstitution := AnalyzerSourceAwaitSubstitution(implementationOwnerType)
        index := 0
        while index < function.Parameters.Count {
            actualReference := function.Parameters[index].Type
            expectedReference := sourceSlot.Parameters[index].Type
            if actualReference == null || expectedReference == null || function.Parameters[index].Modifier != sourceSlot.Parameters[index].Modifier {
                return false
            }
            actual: TypeInfo = BuiltInTypes.Unknown
            expected: TypeInfo = BuiltInTypes.Unknown
            if !TryResolveSourceTypeReference(semanticModel, actualReference, out actual) || !TryResolveSourceTypeReference(semanticModel, expectedReference, out expected) {
                return false
            }
            actual = AnalyzerSyntheticCallFacts.ApplyGenericBindings(actual, implementationSubstitution)
            expected = AnalyzerSyntheticCallFacts.ApplyGenericBindings(expected, slotSubstitution)
            if !SourceInterfaceSlotTypesMatch(actual, expected) {
                return false
            }
            index += 1
        }
        return true
    }

    static func IsVirtualSourceFunction(function: FunctionDeclaration): bool {
        return function != null && (AnalyzerAmbientContext.HasModifier(function, Modifiers.Virtual) || AnalyzerAmbientContext.HasModifier(function, Modifiers.Abstract) || AnalyzerAmbientContext.HasModifier(function, Modifiers.Override))
    }

    static func SourceVirtualTypeChain(ownerType: TypeInfo, declarations: AnalyzerDeclarationContext): List<TypeInfo> {
        chain := new List<TypeInfo>()
        current := declarations.ResolveDeclaredAlias(ownerType)
        depth := 0
        while current != null && depth < 32 {
            shape := SourceShapeForType(current, declarations)
            if shape == null {
                break
            }
            chain.Add(current)
            if shape.BaseType == null {
                break
            }
            current = shape.BaseType
            depth += 1
        }
        return chain
    }

    static func CollectSourceInterfaceClosure(typeInfo: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel, interfaces: List<TypeInfo>, depth: int) {
        if typeInfo == null || declarations == null || semanticModel == null || interfaces == null || depth > 32 {
            return
        }
        resolved := declarations.ResolveDeclaredAlias(typeInfo)
        reflection := resolved as ReflectionTypeInfo
        if reflection != null {
            runtimeType := reflection.Type
            if runtimeType.IsInterface && !ContainsSourceInterfaceType(interfaces, resolved) {
                interfaces.Add(resolved)
            }
            if runtimeType.IsInterface {
                for inherited in runtimeType.GetInterfaces() {
                    CollectSourceInterfaceClosure(new ReflectionTypeInfo(inherited), declarations, semanticModel, interfaces, depth + 1)
                }
            }
            baseType := runtimeType.BaseType
            if baseType != null {
                CollectSourceInterfaceClosure(new ReflectionTypeInfo(baseType), declarations, semanticModel, interfaces, depth + 1)
            }
            return
        }
        shape := SourceShapeForType(resolved, declarations)
        if shape == null {
            return
        }
        sourceDefinition := resolved
        constructedSource := resolved as GenericTypeInfo
        if constructedSource != null && constructedSource.GenericDefinition != null {
            sourceDefinition = constructedSource.GenericDefinition
        }
        sourceInterface := sourceDefinition as InterfaceTypeInfo
        if sourceInterface != null && !ContainsSourceInterfaceType(interfaces, resolved) {
            interfaces.Add(resolved)
        }
        substitution := AnalyzerSourceAwaitSubstitution(resolved)
        references := SourceTypeReferences(sourceDefinition)
        if references != null {
            for reference in references {
                resolvedReference: TypeInfo = BuiltInTypes.Unknown
                if TryResolveSourceTypeReference(semanticModel, reference, out resolvedReference) {
                    closedReference := AnalyzerSyntheticCallFacts.ApplyGenericBindings(resolvedReference, substitution)
                    CollectSourceInterfaceClosure(closedReference, declarations, semanticModel, interfaces, depth + 1)
                }
            }
        }
    }

    static func ContainsSourceInterfaceType(interfaces: List<TypeInfo>, candidate: TypeInfo): bool {
        for current in interfaces {
            if TypeInfoIdentityFacts.AreEqual(current, candidate) {
                return true
            }
        }
        return false
    }

    static func FindSourceInterfaceImplementationForConstructedOwner(ownerType: TypeInfo, sourceSlot: FunctionDeclaration?, runtimeSlot: MethodInfo?, slotOwnerType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel): FunctionDeclaration? {
        if ownerType == null || slotOwnerType == null || declarations == null || semanticModel == null || sourceSlot == null && runtimeSlot == null {
            return null
        }
        methodName := ""
        if sourceSlot != null {
            methodName = sourceSlot.Name
        } else {
            if runtimeSlot == null {
                return null
            }
            methodName = runtimeSlot.Name
        }
        chain := SourceTypeChain(ownerType, declarations)
        for sourceType in chain {
            shape := SourceShapeForType(sourceType, declarations)
            if shape == null {
                continue
            }
            for member in shape.DeclaredMembers {
                function := member.SourceDeclaration as FunctionDeclaration
                if function == null || !ExplicitInterfaceMemberFacts.IsExplicitMemberName(function.Name) || ExplicitInterfaceMemberFacts.SimpleNameOf(function.Name) != methodName || !SourceFunctionMatchesInterfaceSlot(function, sourceSlot, runtimeSlot, slotOwnerType, semanticModel, sourceType) {
                    continue
                }
                qualifier := ExplicitInterfaceMemberFacts.QualifierOf(function.Name)
                if SourceTypeClosureContainsQualifier(ownerType, qualifier, slotOwnerType, semanticModel, 0) {
                    return function
                }
            }
        }
        for sourceType in chain {
            shape := SourceShapeForType(sourceType, declarations)
            if shape == null {
                continue
            }
            for member in shape.DeclaredMembers {
                function := member.SourceDeclaration as FunctionDeclaration
                if function == null || ExplicitInterfaceMemberFacts.IsExplicitMemberName(function.Name) || function.Name != methodName || !IsPublicSourceFunction(function) || !SourceFunctionMatchesInterfaceSlot(function, sourceSlot, runtimeSlot, slotOwnerType, semanticModel, sourceType) {
                    continue
                }
                return function
            }
        }
        return null
    }

    static func FindSourceInterfacePropertyImplementationForConstructedOwner(ownerType: TypeInfo, sourceSlot: Declaration, slotOwnerType: TypeInfo, declarations: AnalyzerDeclarationContext, semanticModel: SemanticModel): Declaration? {
        if ownerType == null || sourceSlot == null || slotOwnerType == null || declarations == null || semanticModel == null {
            return null
        }
        slotName := SourceAwaiterMemberName(sourceSlot)
        slotType := SourceAwaiterMemberType(sourceSlot)
        if slotName == null || slotType == null {
            return null
        }
        expectedType: TypeInfo = BuiltInTypes.Unknown
        if !TryResolveSourceTypeReference(semanticModel, slotType, out expectedType) {
            return null
        }
        expectedType = AnalyzerSyntheticCallFacts.ApplyGenericBindings(expectedType, AnalyzerSourceAwaitSubstitution(slotOwnerType))
        chain := SourceTypeChain(ownerType, declarations)
        for sourceType in chain {
            sourceDeclarationType := sourceType
            constructedSourceType := sourceType as GenericTypeInfo
            if constructedSourceType != null && constructedSourceType.GenericDefinition != null {
                sourceDeclarationType = constructedSourceType.GenericDefinition
            }
            sourceDeclaration := declarations.FindDeclarationForType(sourceDeclarationType) as Declaration
            sourceMembers := sourceDeclaration == null ? null : SourceMembers(sourceDeclaration)
            if sourceMembers == null {
                continue
            }
            for member in sourceMembers {
                property := member as PropertyDeclaration
                if property == null || !ExplicitInterfaceMemberFacts.IsExplicitMemberName(property.Name) || ExplicitInterfaceMemberFacts.SimpleNameOf(property.Name) != slotName || !SourcePropertyMatchesInterfaceSlotForOwner(property, sourceType, expectedType, semanticModel) {
                    continue
                }
                qualifier := ExplicitInterfaceMemberFacts.QualifierOf(property.Name)
                if SourceTypeClosureContainsQualifier(ownerType, qualifier, slotOwnerType, semanticModel, 0) {
                    return property
                }
            }
        }
        for sourceType in chain {
            sourceDeclarationType := sourceType
            constructedSourceType := sourceType as GenericTypeInfo
            if constructedSourceType != null && constructedSourceType.GenericDefinition != null {
                sourceDeclarationType = constructedSourceType.GenericDefinition
            }
            sourceDeclaration := declarations.FindDeclarationForType(sourceDeclarationType) as Declaration
            sourceMembers := sourceDeclaration == null ? null : SourceMembers(sourceDeclaration)
            if sourceMembers == null {
                continue
            }
            for member in sourceMembers {
                property := member as PropertyDeclaration
                if property == null || ExplicitInterfaceMemberFacts.IsExplicitMemberName(property.Name) || property.Name != slotName || !IsPublicSourceProperty(property) || !SourcePropertyMatchesInterfaceSlotForOwner(property, sourceType, expectedType, semanticModel) {
                    continue
                }
                return property
            }
        }
        return null
    }

    static func SourcePropertyMatchesInterfaceSlotForOwner(property: PropertyDeclaration, ownerType: TypeInfo, expectedType: TypeInfo, semanticModel: SemanticModel): bool {
        if property == null || property.Type == null || ownerType == null || expectedType == null || semanticModel == null {
            return false
        }
        actualType: TypeInfo = BuiltInTypes.Unknown
        if !TryResolveSourceTypeReference(semanticModel, property.Type, out actualType) {
            return false
        }
        actualType = AnalyzerSyntheticCallFacts.ApplyGenericBindings(actualType, AnalyzerSourceAwaitSubstitution(ownerType))
        return SourceInterfaceSlotTypesMatch(actualType, expectedType)
    }

    static func SourceInterfaceSlotTypesMatch(actual: TypeInfo, expected: TypeInfo): bool {
        if TypeInfoIdentityFacts.AreEqual(actual, expected) {
            return true
        }
        actualReflection := actual as ReflectionTypeInfo
        expectedReflection := expected as ReflectionTypeInfo
        return actualReflection != null && expectedReflection != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(actualReflection.Type, expectedReflection.Type)
    }

    static func SourceCompletionMemberHasExactActionSignature(member: DeclaredMemberInfo, function: FunctionDeclaration, semanticModel: SemanticModel, methodName: string): bool {
        if member == null || function == null || semanticModel == null || member.Kind != DeclaredMemberKind.Function || member.IsStatic || member.TypeParameterCount != 0 || member.ParameterCount != 1 || function.Parameters.Count != 1 || function.Parameters[0].Type == null {
            return false
        }
        if ExplicitInterfaceMemberFacts.IsExplicitMemberName(function.Name) {
            if ExplicitInterfaceMemberFacts.SimpleNameOf(function.Name) != methodName {
                return false
            }
        } else if function.Name != methodName {
            return false
        }
        resolvedParameter: TypeInfo = BuiltInTypes.Unknown
        if !TryResolveSourceTypeReference(semanticModel, function.Parameters[0].Type, out resolvedParameter) {
            return false
        }
        reflectedParameter := resolvedParameter as ReflectionTypeInfo
        if reflectedParameter == null || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(reflectedParameter.Type, typeof(Action)) {
            return false
        }
        resolvedReturn: TypeInfo = BuiltInTypes.Void
        if function.ReturnType != null && !TryResolveSourceTypeReference(semanticModel, function.ReturnType, out resolvedReturn) {
            return false
        }
        return BuiltInTypes.Is(resolvedReturn, BuiltInTypes.Void)
    }

    static func SourceTypeChain(ownerType: TypeInfo, declarations: AnalyzerDeclarationContext): List<TypeInfo> {
        chain := new List<TypeInfo>()
        current := declarations.ResolveDeclaredAlias(ownerType)
        depth := 0
        while current != null && depth < 32 {
            sourceType := current
            constructed := current as GenericTypeInfo
            if constructed != null && constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
                sourceType = constructed.GenericDefinition
            }
            if !declarations.ContainsSourceType(sourceType) {
                break
            }
            chain.Add(current)
            shape := SourceShapeForType(current, declarations)
            if shape == null || shape.BaseType == null {
                break
            }
            current = shape.BaseType
            depth += 1
        }
        return chain
    }

    static func SourceShapeForType(ownerType: TypeInfo, declarations: AnalyzerDeclarationContext): AnalyzerSourceMemberShape? {
        sourceType := ownerType
        constructed := ownerType as GenericTypeInfo
        substitution := AnalyzerSourceAwaitSubstitution(ownerType)
        if constructed != null && constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
            sourceType = constructed.GenericDefinition
        }
        shape := new AnalyzerSourceMemberShape()
        return declarations.TryGetSourceMemberShape(sourceType, substitution, out shape) ? shape : null
    }

    static func IsSourceReadableAwaiterProperty(selection: AnalyzerMemberSelection): bool {
        if selection == null || selection.Member == null {
            return false
        }
        if selection.Member.Kind == DeclaredMemberKind.Property {
            return true
        }
        // N#'s source interface value syntax (`IsCompleted: bool`) emits an abstract getter slot,
        // while the declaration model retains the source spelling as a field. At an interface
        // receiver this is the ordinary property contract, not instance storage.
        return selection.Member.Kind == DeclaredMemberKind.Field && selection.Owner as InterfaceTypeInfo != null
    }

    static func SourcePropertyForSelection(declarations: AnalyzerDeclarationContext, selection: AnalyzerMemberSelection): Declaration? {
        if declarations == null || selection == null || selection.Member == null || !IsSourceReadableAwaiterProperty(selection) {
            return null
        }
        declaration := declarations.FindDeclarationForType(selection.Owner) as Declaration
        members := declaration == null ? null : SourceMembers(declaration)
        if members == null {
            return null
        }
        for candidate in members {
            property := candidate as PropertyDeclaration
            if property != null && property.Name == selection.Member.Name && property.Line == selection.Member.Line && property.Column == selection.Member.Column {
                return property
            }
            interfaceValue := candidate as FieldDeclaration
            if selection.Owner as InterfaceTypeInfo != null && interfaceValue != null && interfaceValue.Name == selection.Member.Name && interfaceValue.Line == selection.Member.Line && interfaceValue.Column == selection.Member.Column {
                return interfaceValue
            }
        }
        return null
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

    static func IsPublicSourceFunction(function: FunctionDeclaration): bool {
        let modifiers: int = Convert.ToInt32(function.Modifiers)
        return (modifiers & Convert.ToInt32(Modifiers.Private)) == 0 && (modifiers & Convert.ToInt32(Modifiers.Protected)) == 0
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
        interfaceDeclaration := owner as InterfaceDeclaration
        if interfaceDeclaration != null {
            return interfaceDeclaration.Members
        }
        return null
    }

    // Reflection-only binding is shared by synthesized awaits and the core Task families. Resolve
    // the ordinary instance member group first, retain the most-derived declaration level, then
    // apply zero-argument invocation rules. A hidden base overload never leaks back in when the
    // derived declaration is inapplicable.
    static func SelectZeroArgumentInstanceMethod(owner: Type, name: string): MethodInfo? {
        hasApplicableCandidate := false
        return SelectZeroArgumentInstanceMethod(owner, name, out hasApplicableCandidate)
    }

    static func SelectZeroArgumentInstanceMethod(owner: Type, name: string, out hasApplicableCandidate: bool): MethodInfo? {
        hasApplicableCandidate = false
        if owner == null {
            return null
        }

        methods := owner.GetMethods(PublicInstance)
        nearestDeclaringType: Type? = null
        for candidate in methods {
            if candidate.Name != name || candidate.IsStatic || !candidate.IsPublic || candidate.DeclaringType == null {
                continue
            }
            declaringType := candidate.DeclaringType
            if nearestDeclaringType == null || IsMoreSpecific(declaringType, nearestDeclaringType) {
                nearestDeclaringType = declaringType
            }
        }
        if nearestDeclaringType == null {
            return null
        }

        selected: MethodInfo? = null
        selectedOptionalCount := int.MaxValue
        selectedUsesParams := true
        for candidate in methods {
            if candidate.Name != name || candidate.IsStatic || !candidate.IsPublic || candidate.DeclaringType == null || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(candidate.DeclaringType, nearestDeclaringType) || candidate.IsGenericMethod {
                continue
            }
            parameters := candidate.GetParameters()
            optionalCount := 0
            usesParams := false
            applicable := true
            index := 0
            while index < parameters.Length {
                parameter := parameters[index]
                if IsParamArrayParameter(parameter) && index == parameters.Length - 1 {
                    usesParams = true
                } else if parameter.IsOptional {
                    optionalCount += 1
                } else {
                    applicable = false
                    break
                }
                index += 1
            }
            if !applicable {
                continue
            }
            hasApplicableCandidate = true
            if selected == null || optionalCount < selectedOptionalCount || optionalCount == selectedOptionalCount && selectedUsesParams && !usesParams {
                selected = candidate
                selectedOptionalCount = optionalCount
                selectedUsesParams = usesParams
            } else if optionalCount == selectedOptionalCount && usesParams == selectedUsesParams {
                // Ordinary zero-argument invocation is ambiguous; reflection enumeration order
                // is not a tie-break rule.
                return null
            }
        }
        if selected != null && selected.GetParameters().Length != 0 {
            return null
        }
        return selected
    }

    static func SelectReadableBooleanProperty(owner: Type, name: string): PropertyInfo? {
        if owner == null {
            return null
        }

        selected := ReflectedMemberLookup.FindProperty(owner, name, BindingFlags.Public | BindingFlags.Instance)
        if selected == null || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selected.PropertyType, typeof(bool)) || selected.GetIndexParameters().Length != 0 {
            return null
        }
        getter := selected.GetGetMethod()
        return getter != null && getter.IsPublic && !getter.IsStatic ? selected : null
    }

    static func IsParamArrayParameter(parameter: ParameterInfo): bool {
        if parameter == null {
            return false
        }
        for attribute in parameter.GetCustomAttributesData() {
            if attribute != null && attribute.AttributeType == typeof(ParamArrayAttribute) {
                return true
            }
        }
        return false
    }

    static func ResolveInterfaceSlot(
        awaiterType: Type,
        [DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.PublicMethods | DynamicallyAccessedMemberTypes.NonPublicMethods)] contract: Type,
        methodName: string
    ): MethodInfo? {
        if awaiterType == null || contract == null || methodName == null {
            return null
        }

        // Resolve the interface inherited by this awaiter first, then ask that exact interface for
        // the exact Action slot. Never choose an implementation by scanning names or generated
        // explicit-implementation suffixes: interface dispatch is defined by this slot identity.
        actualContract := FindCompletionInterface(awaiterType, contract)
        if actualContract == null {
            return null
        }
        // `actualContract` can belong to a MetadataLoadContext while `contract` is the executable
        // interface from the runtime. Resolve each slot in its own context, then verify both exact
        // signatures by cross-context type identity. The returned slot is always executable.
        interfaceSlot := ExactCompletionInterfaceSlot(actualContract, methodName)
        dispatchSlot := ExactCompletionInterfaceSlot(contract, methodName)
        if interfaceSlot == null || dispatchSlot == null {
            return null
        }

        // On a baked type the interface map confirms that this slot is implemented. The returned
        // member remains the interface method itself, so callvirt performs implicit, explicit, or
        // inherited dispatch exactly as the CLR mapped it. Metadata-only and TypeBuilder types may
        // not expose a map yet; the exact contract slot remains the right emitted call target.
        try {
            interfaceMap := awaiterType.GetInterfaceMap(actualContract)
            index := 0
            while index < interfaceMap.InterfaceMethods.Length && index < interfaceMap.TargetMethods.Length {
                mappedSlot := interfaceMap.InterfaceMethods[index]
                if Object.Equals(mappedSlot, interfaceSlot) {
                    return dispatchSlot
                }
                index += 1
            }
            return null
            // nlc:ignore NL011
        } catch failure: ArgumentException {
            // nlc:ignore NL011
        } catch failure: InvalidOperationException {
            // nlc:ignore NL011
        } catch failure: NotSupportedException {
        }

        return dispatchSlot
    }

    static func ExactCompletionInterfaceSlot(contract: Type, methodName: string): MethodInfo? {
        if contract == null || methodName == null {
            return null
        }
        selected: MethodInfo? = null
        for candidate in contract.GetMethods() {
            if candidate.Name != methodName || !IsCompletionSlotSignature(candidate) {
                continue
            }
            if selected != null {
                return null
            }
            selected = candidate
        }
        return selected
    }

    static func IsCompletionSlotSignature(slot: MethodInfo): bool {
        return slot != null && !slot.IsStatic && !slot.IsGenericMethod && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(slot.ReturnType, typeof(void)) && slot.GetParameters().Length == 1 && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(slot.GetParameters()[0].ParameterType, typeof(Action))
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
