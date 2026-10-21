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

    constructor(awaitableType: TypeInfo, awaiterType: TypeInfo, resultType: TypeInfo, getAwaiter: AnalyzerMemberSelection?, isCompleted: AnalyzerMemberSelection?, getResult: AnalyzerMemberSelection?, reflectedAwaiter: AwaitablePatternBinding?, getAwaiterExtension: TypeInfo? = null) {
        AwaitableType = awaitableType
        AwaiterType = awaiterType
        ResultType = resultType
        GetAwaiter = getAwaiter
        IsCompleted = isCompleted
        GetResult = getResult
        ReflectedAwaiter = reflectedAwaiter
        GetAwaiterExtension = getAwaiterExtension
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
        if awaitableType == null || method == null || method.IsGenericMethod || !method.IsStatic || !HasExtensionAttribute(method) || method.GetParameters().Length != 1 || method.ReturnType == typeof(void) {
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
    static func TryBindAnalyzerSourceAwaitable(awaitableType: TypeInfo, declarations: AnalyzerDeclarationContext, accessingTypeName: string?, out binding: AnalyzerAwaitablePatternBinding?): bool {
        binding = null
        if awaitableType == null || declarations == null || IsNullableValueType(awaitableType) {
            return false
        }

        owner := awaitableType
        substitution := AnalyzerSourceAwaitSubstitution(owner)
        constructed := owner as GenericTypeInfo
        if constructed != null && constructed.GenericDefinition != null && declarations.ContainsSourceType(constructed.GenericDefinition) {
            owner = constructed.GenericDefinition
        }
        if !declarations.ContainsSourceType(owner) {
            return false
        }

        getAwaiter := new AnalyzerMemberSelection()
        if !TrySelectAnalyzerSourceMethod(owner, "GetAwaiter", declarations, accessingTypeName, out getAwaiter) || getAwaiter.Member == null || getAwaiter.Member.ReturnType == null {
            return false
        }

        awaiterType: TypeInfo = BuiltInTypes.Unknown
        if !declarations.TryResolveTypeForOwner(getAwaiter.Member.ReturnType, getAwaiter.Owner, substitution, out awaiterType) || BuiltInTypes.IsUnknown(awaiterType) {
            return false
        }

        resultType: TypeInfo = BuiltInTypes.Unknown
        isCompleted: AnalyzerMemberSelection? = null
        getResult: AnalyzerMemberSelection? = null
        reflectedAwaiter: AwaitablePatternBinding? = null
        if !TryBindAnalyzerSourceAwaiter(awaiterType, declarations, accessingTypeName, out resultType, out isCompleted, out getResult, out reflectedAwaiter) {
            return false
        }
        binding = new AnalyzerAwaitablePatternBinding(awaitableType, awaiterType, resultType, getAwaiter, isCompleted, getResult, reflectedAwaiter)
        return true
    }

    // The analyzer-facing entry for reflected, source and extension awaitables. Task families may
    // be recognized by their language type owner before this call; every remaining pattern reaches
    // this binder and receives one selected GetAwaiter plus its already-bound awaiter members.
    static func TryBindAnalyzerAwaitable(awaitableType: TypeInfo, declarations: AnalyzerDeclarationContext, extensions: AnalyzerExtensionMethodResolution?, accessingTypeName: string?, out binding: AnalyzerAwaitablePatternBinding?): bool {
        binding = null
        if awaitableType == null || declarations == null || IsNullableValueType(awaitableType) {
            return false
        }

        reflected := awaitableType as ReflectionTypeInfo
        if reflected != null {
            reflectedPattern: AwaitablePatternBinding? = null
            if TryBindReflection(reflected.Type, out reflectedPattern) && reflectedPattern != null {
                resultType: TypeInfo = BuiltInTypes.Unknown
                if !AnalyzerAwaitResultType(reflectedPattern.GetResult.ReturnType, out resultType) {
                    return false
                }
                binding = new AnalyzerAwaitablePatternBinding(awaitableType, new ReflectionTypeInfo(reflectedPattern.AwaiterType), resultType, null, null, null, reflectedPattern)
                return true
            }
        }

        constructed := awaitableType as GenericTypeInfo
        if constructed != null {
            definitionInfo := constructed.GenericDefinition as ReflectionTypeInfo
            if definitionInfo != null {
                reflectedPattern: AwaitablePatternBinding? = null
                if TryBindReflection(definitionInfo.Type, out reflectedPattern) && reflectedPattern != null {
                    resultType := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
                        reflectedPattern.GetResult.ReturnType,
                        AnalyzerReflectionTypeOverrides(definitionInfo.Type, constructed.TypeArguments),
                        null
                    )
                    if BuiltInTypes.IsUnknown(resultType) {
                        return false
                    }
                    binding = new AnalyzerAwaitablePatternBinding(awaitableType, new ReflectionTypeInfo(reflectedPattern.AwaiterType), resultType, null, null, null, reflectedPattern)
                    return true
                }
            }
        }

        sourceBinding: AnalyzerAwaitablePatternBinding? = null
        if TryBindAnalyzerSourceAwaitable(awaitableType, declarations, accessingTypeName, out sourceBinding) && sourceBinding != null {
            binding = sourceBinding
            return true
        }

        if extensions == null {
            return false
        }
        getAwaiterExtension := extensions.TryResolveExtensionMethod(awaitableType, "GetAwaiter", accessingTypeName)
        awaiterType: TypeInfo = BuiltInTypes.Unknown
        selectedExtension: TypeInfo? = null
        if !TrySelectAnalyzerGetAwaiterExtension(getAwaiterExtension, out selectedExtension, out awaiterType) || selectedExtension == null || BuiltInTypes.IsUnknown(awaiterType) {
            return false
        }

        resultType: TypeInfo = BuiltInTypes.Unknown
        isCompleted: AnalyzerMemberSelection? = null
        getResult: AnalyzerMemberSelection? = null
        reflectedAwaiter: AwaitablePatternBinding? = null
        if !TryBindAnalyzerSourceAwaiter(awaiterType, declarations, accessingTypeName, out resultType, out isCompleted, out getResult, out reflectedAwaiter) {
            return false
        }
        binding = new AnalyzerAwaitablePatternBinding(awaitableType, awaiterType, resultType, null, isCompleted, getResult, reflectedAwaiter, selectedExtension)
        return true
    }

    static func TrySelectAnalyzerGetAwaiterExtension(candidate: TypeInfo, out selected: TypeInfo?, out returnType: TypeInfo): bool {
        selected = null
        returnType = BuiltInTypes.Unknown
        function := candidate as FunctionTypeInfo
        if function != null {
            if !IsAnalyzerExtensionGetAwaiter(function) || function.ReturnType == null {
                return false
            }
            selected = function
            returnType = function.ReturnType
            return true
        }

        sourceGroup := candidate as NSharpMethodGroupInfo
        if sourceGroup != null {
            index := 0
            while index < sourceGroup.Functions.Count {
                functionCandidate := sourceGroup.Functions[index]
                if !IsAnalyzerExtensionGetAwaiter(functionCandidate) || functionCandidate.ReturnType == null {
                    index += 1
                    continue
                }
                if selected != null {
                    selected = null
                    returnType = BuiltInTypes.Unknown
                    return false
                }
                selected = functionCandidate
                returnType = functionCandidate.ReturnType
                index += 1
            }
            return selected != null
        }

        reflectedMethod := candidate as ReflectionMethodInfo
        if reflectedMethod != null {
            return TrySelectReflectedGetAwaiterExtension([reflectedMethod.Method], out selected, out returnType)
        }
        reflectedGroup := candidate as ReflectionMethodGroupInfo
        if reflectedGroup != null {
            return TrySelectReflectedGetAwaiterExtension(reflectedGroup.Methods, out selected, out returnType)
        }
        return false
    }

    static func IsAnalyzerExtensionGetAwaiter(function: FunctionTypeInfo): bool {
        if function == null || !function.SourceIsStatic || !function.SourceHasReceiverParameter || function.SourceParameterCount != 1 || function.ParameterTypes == null || function.ParameterTypes.Count != 1 || function.ReturnType == null {
            return false
        }
        genericParameters := function.TypeParameters
        if genericParameters != null && genericParameters.Count != 0 {
            return false
        }
        requiredCount := function.RequiredParameterCount ?? function.SourceParameterCount
        return requiredCount == 1 && !function.HasParamsParameter
    }

    static func TrySelectReflectedGetAwaiterExtension(methods: MethodInfo[], out selected: TypeInfo?, out returnType: TypeInfo): bool {
        selected = null
        returnType = BuiltInTypes.Unknown
        for method in methods {
            if method == null || !method.IsStatic || method.IsGenericMethod || method.GetParameters().Length != 1 || !HasExtensionAttribute(method) {
                continue
            }
            if selected != null {
                selected = null
                returnType = BuiltInTypes.Unknown
                return false
            }
            selected = new ReflectionMethodInfo(method)
            returnType = AnalyzerReflectionTypeConversion.ConvertReflectionType(method.ReturnType)
        }
        return selected != null && !BuiltInTypes.IsUnknown(returnType)
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
        implicitMethod := SelectSourceMethod(owner, methodName, 1)
        if implicitMethod != null && IsPublicSourceFunction(implicitMethod) {
            return implicitMethod
        }
        if contractReference == null {
            return null
        }
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
            if TryResolveSourceTypeReference(semanticModel, reference, out resolved) && TypeInfoImplementsCompletionInterface(resolved, expected) {
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

    static func TypeInfoImplementsCompletionInterface(typeInfo: TypeInfo, expected: Type): bool {
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
                return TypeInfoImplementsCompletionInterface(definition, expected)
            }
        }
        return false
    }

    static func SourceQualifierResolvesTo(owner: Declaration, semanticModel: SemanticModel, qualifier: string, contractReference: TypeReference?, expected: Type): bool {
        if contractReference != null && TypeReferenceFacts.GetDisplayName(contractReference) == qualifier {
            resolvedContract: TypeInfo = BuiltInTypes.Unknown
            if TryResolveSourceTypeReference(semanticModel, contractReference, out resolvedContract) && TypeInfoImplementsExactInterface(resolvedContract, expected) {
                return true
            }
        }
        references := SourceInterfaces(owner)
        if references != null {
            for reference in references {
                if TypeReferenceFacts.GetDisplayName(reference) == qualifier {
                    resolvedContract: TypeInfo = BuiltInTypes.Unknown
                    if TryResolveSourceTypeReference(semanticModel, reference, out resolvedContract) && TypeInfoImplementsExactInterface(resolvedContract, expected) {
                        return true
                    }
                }
            }
        }
        resolved: TypeInfo? = null
        if semanticModel.Types.TryGetValue(qualifier, out resolved) && resolved != null {
            return TypeInfoImplementsExactInterface(resolved, expected)
        }
        if semanticModel.TypesByIdentity.TryGetValue(TypeArityNames.Key(qualifier, 0), out resolved) && resolved != null {
            return TypeInfoImplementsExactInterface(resolved, expected)
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
