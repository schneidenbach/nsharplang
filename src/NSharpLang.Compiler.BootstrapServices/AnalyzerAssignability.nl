namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// THE ANALYZER'S ASSIGNABILITY DECISION — the whole strongly-connected component, in one owner.
//
// `IsAssignable(target, source)` answers the language's central semantic question: may a value of
// `source` be written where `target` is expected. Everything else here exists because it re-enters
// that question — nominal subtyping walks a base chain and asks again for each base, a user-defined
// implicit conversion asks about the operator's parameter and its result, a delegate score asks
// about each parameter position, a lambda asks about each delegate argument. That mutual recursion
// is why these members are ONE owner and not several: there is no sub-cut of the interior.
//
// THE DISPATCH ORDER IS THE SPECIFICATION. `IsAssignable` is a sequence of arms, and moving one past
// another changes the language. The load-bearing orderings, each of which a differential would catch:
//   * IDENTITY, `null`, `never` and the unknown types come first, so error recovery never produces a
//     second diagnostic and a bottom type is universally assignable.
//   * BY-REF is symmetric and total — if EITHER side is by-ref the answer is "both are, over equal
//     inner types" and no later arm is consulted.
//   * THE UNION ARMS come before everything structural: a source union must satisfy the target for
//     EVERY arm, while a target union needs only ONE arm to accept the source.
//   * THE CALLABLE-REFERENCE ARMS come before `object`. A bare method group is not a value, so it is
//     NOT assignable to `object`, and that exception is the reason the `object` arm sits below them.
//   * FUNCTION-TYPE structural comparison comes before the identity fallback, because
//     `FunctionTypeInfo.ToString()` renders every function type alike.
//   * THE USER-DEFINED CONVERSION is last, so a conversion operator can never shadow a built-in
//     relation.
//
// THE RE-ENTRANCY GUARD IS CORRECTNESS, NOT AN OPTIMISATION. A user-defined implicit conversion can
// name types whose own conversions name it back; without the active-pair guard `HasImplicitConversion`
// recurses forever. It lives OUTSIDE this owner, in `AnalyzerImplicitConversionGuard`, because this
// owner is REBUILT whenever the well-known-type bag is built or torn down and the guard must survive
// that: an owner's fields never change after construction, so state that outlives one owner is held
// by a collaborator that does not.
//
// Do not reintroduce any of this in C#, and do not give it diagnostics: assignability reports nothing
// and records nothing. The two arms that DO look something up — the duck-interface arm and the
// ActionResult arm — are delegated to `AnalyzerStructuralAssignability`, which owns those effects.

// The active `(source, target)` pairs of an in-flight user-defined conversion search. Two parallel
// lists rather than a set of pairs: an EMITTED type cannot key a dictionary on the columnar surface,
// and the scan is exact — `Object.Equals` is the same virtual equality a `HashSet` of pairs would
// use, and the list is only ever as deep as the conversion recursion.
public class AnalyzerImplicitConversionGuard {

    activeSources: List<TypeInfo>
    activeTargets: List<TypeInfo>

    constructor() {
        activeSources = new List<TypeInfo>()
        activeTargets = new List<TypeInfo>()
    }

    // True when the pair was NOT already active and has now been marked so. False means the caller
    // is already inside this exact question and must answer "no" rather than recurse.
    public func TryEnter(source: TypeInfo, target: TypeInfo): bool {
        if IndexOfPair(source, target) >= 0 {
            return false
        }

        activeSources.Add(source)
        activeTargets.Add(target)
        return true
    }

    public func Exit(source: TypeInfo, target: TypeInfo) {
        index := IndexOfPair(source, target)
        if index >= 0 {
            activeSources.RemoveAt(index)
            activeTargets.RemoveAt(index)
        }
    }

    public func Clear() {
        activeSources.Clear()
        activeTargets.Clear()
    }

    func IndexOfPair(source: TypeInfo, target: TypeInfo): int {
        index := 0
        while index < activeSources.Count {
            existingSource: TypeInfo = activeSources[index]
            existingTarget: TypeInfo = activeTargets[index]
            if Object.Equals(existingSource, source) {
                if Object.Equals(existingTarget, target) {
                    return index
                }
            }

            index = index + 1
        }

        return -1
    }
}

public class AnalyzerAssignability {

    declarationContext: AnalyzerDeclarationContext
    assignabilityFacts: AnalyzerAssignabilityFacts
    structuralAssignability: AnalyzerStructuralAssignability
    typeSubstitution: AnalyzerTypeSubstitution
    clrTypeConversion: AnalyzerClrTypeConversion
    conversionGuard: AnalyzerImplicitConversionGuard

    constructor(
        context: AnalyzerDeclarationContext,
        facts: AnalyzerAssignabilityFacts,
        structural: AnalyzerStructuralAssignability,
        substitution: AnalyzerTypeSubstitution,
        clrConversion: AnalyzerClrTypeConversion,
        guard: AnalyzerImplicitConversionGuard) {
        declarationContext = context
        assignabilityFacts = facts
        structuralAssignability = structural
        typeSubstitution = substitution
        clrTypeConversion = clrConversion
        conversionGuard = guard
    }

    public func IsAssignable(target: TypeInfo, source: TypeInfo): bool {
        resolvedTarget := declarationContext.ResolveDeclaredAlias(target)
        resolvedSource := declarationContext.ResolveDeclaredAlias(source)

        if Object.ReferenceEquals(resolvedTarget, resolvedSource) {
            return true
        }

        if BuiltInTypes.Is(resolvedSource, BuiltInTypes.Null) {
            nullTarget := resolvedTarget as NullableTypeInfo
            if nullTarget != null {
                return true
            }

            // null is assignable to any reference type: string, classes, interfaces, arrays,
            // delegates.
            if AnalyzerConversionFacts.IsReferenceType(resolvedTarget) {
                return true
            }
        }

        if BuiltInTypes.Is(resolvedSource, BuiltInTypes.Never) {
            return true
        }

        // Unknown handling — distinguished by KIND at the construction site, not here. ErrorRecovery
        // suppresses follow-on errors because one was already reported upstream; InferenceHole and
        // DeferredExternal are accepted for now but stay distinguishable for future tightening.
        if BuiltInTypes.IsUnknown(resolvedSource) || BuiltInTypes.IsUnknown(resolvedTarget) {
            return true
        }

        targetByRef := resolvedTarget as ByRefTypeInfo
        sourceByRef := resolvedSource as ByRefTypeInfo
        if targetByRef != null || sourceByRef != null {
            if targetByRef == null || sourceByRef == null {
                return false
            }

            return TypeInfoIdentityFacts.AreEqual(targetByRef.InnerType, sourceByRef.InnerType)
        }

        sourceUnion := resolvedSource as AnonymousUnionTypeInfo
        targetUnion := resolvedTarget as AnonymousUnionTypeInfo
        if sourceUnion != null && targetUnion != null {
            return EveryArmAcceptedBySomeArm(targetUnion, sourceUnion)
        }

        if targetUnion != null {
            return SomeArmAccepts(targetUnion, resolvedSource)
        }

        if sourceUnion != null {
            return EveryArmAssignableTo(resolvedTarget, sourceUnion)
        }

        sourceFunction := resolvedSource as FunctionTypeInfo
        sourceIsDeclaredFunction := false
        if sourceFunction != null {
            sourceIsDeclaredFunction = AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(sourceFunction)
        }

        if sourceIsDeclaredFunction {
            if !assignabilityFacts.CanBindCallableReferenceToExpectedType(resolvedTarget) {
                return false
            }

            callableTarget := resolvedTarget as ReflectionTypeInfo
            if callableTarget != null {
                targetClrType := callableTarget.Type
                if AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(targetClrType) {
                    delegateSignature := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(targetClrType)
                    return IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(
                        sourceFunction,
                        delegateSignature)
                }
            }
        } else {
            if AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(resolvedSource) {
                return false
            }
        }

        if AnalyzerCallableReferenceFacts.IsCallableReferenceType(resolvedTarget) {
            return false
        }

        // Everything is assignable to object, EXCEPT the bare method references refused above —
        // they are not values.
        if BuiltInTypes.Is(resolvedTarget, BuiltInTypes.Object) {
            return true
        }

        if assignabilityFacts.IsArrayToSpanAssignable(resolvedTarget, resolvedSource) {
            return true
        }

        if TypeInfoIdentityFacts.IsRuntimeSpanToReadOnlySpanConversion(resolvedTarget, resolvedSource) {
            return true
        }

        // Nullable widening: T → T?, and T? → U? through the inner types.
        nullableTarget := resolvedTarget as NullableTypeInfo
        if nullableTarget != null {
            nullableSource := resolvedSource as NullableTypeInfo
            if nullableSource != null {
                return IsAssignable(nullableTarget.InnerType, nullableSource.InnerType)
            }

            return IsAssignable(nullableTarget.InnerType, resolvedSource)
        }

        sourceReflection := resolvedSource as ReflectionTypeInfo
        targetReflection := resolvedTarget as ReflectionTypeInfo

        // Both sides reflected: CLR semantics decide.
        if sourceReflection != null && targetReflection != null {
            return AnalyzerConversionFacts.IsReflectionAssignableFrom(
                targetReflection.Type,
                sourceReflection.Type)
        }

        // Mixed: reflected target, built-in source — convert the source and compare in the CLR.
        if targetReflection != null {
            simpleSource := resolvedSource as SimpleTypeInfo
            if simpleSource != null {
                sourceClrType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedSource)
                if sourceClrType != null {
                    targetClrType := targetReflection.Type
                    return targetClrType.IsAssignableFrom(sourceClrType)
                }
            }
        }

        // Mixed: built-in target, reflected source.
        simpleTarget := resolvedTarget as SimpleTypeInfo
        if simpleTarget != null && sourceReflection != null {
            targetClrType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedTarget)
            if targetClrType != null {
                sourceClrType := sourceReflection.Type
                return targetClrType.IsAssignableFrom(sourceClrType)
            }
        }

        // Function-type structural comparison MUST precede the identity fallback below, because
        // every FunctionTypeInfo renders identically.
        targetFunction := resolvedTarget as FunctionTypeInfo
        if sourceFunction != null && targetFunction != null {
            return IsFunctionTypeAssignable(sourceFunction, targetFunction)
        }

        // Structural equality preserves nominal identities inside arrays, nullable types, tuples,
        // unions, functions and generic instantiations.
        if TypeInfoIdentityFacts.AreEqual(resolvedTarget, resolvedSource) {
            return true
        }

        if structuralAssignability.IsAspNetActionResultGenericAssignable(resolvedTarget, resolvedSource) {
            return true
        }

        if IsKnownGenericTypeAssignable(resolvedTarget, resolvedSource) {
            return true
        }

        if AnalyzerConversionFacts.IsImplicitNumericConversion(resolvedSource, resolvedTarget) {
            return true
        }

        // Nominal subtyping over the N#-declared base chains and interface lists.
        if IsSubtypeOf(resolvedSource, resolvedTarget) {
            return true
        }

        // An enum value is assignable wherever its underlying type is.
        enumSource := resolvedSource as EnumTypeInfo
        if enumSource != null {
            declaration := enumSource.Declaration
            underlyingType: TypeInfo = BuiltInTypes.Int
            if declaration.Type == EnumType.String {
                underlyingType = BuiltInTypes.String
            }

            if IsAssignable(resolvedTarget, underlyingType) {
                return true
            }
        }

        // A lambda's function type against a Func/Action instantiation.
        genericTarget := resolvedTarget as GenericTypeInfo
        if sourceFunction != null && genericTarget != null {
            if TypeInfoIdentityFacts.IsRuntimeDelegateDefinition(genericTarget) {
                return IsLambdaAssignableToDelegate(sourceFunction, genericTarget)
            }
        }

        // Duck-interface structural typing.
        interfaceTarget := resolvedTarget as InterfaceTypeInfo
        if interfaceTarget != null {
            if interfaceTarget.IsDuckInterface {
                return structuralAssignability.ImplementsDuckInterface(resolvedSource, interfaceTarget)
            }
        }

        // Collection expressions: an array literal may target a collection whose element type
        // accepts the array's.
        arraySource := resolvedSource as ArrayTypeInfo
        if arraySource != null {
            collectionElementType: TypeInfo = BuiltInTypes.Unknown
            if assignabilityFacts.TryGetCollectionElementType(resolvedTarget, out collectionElementType) {
                return IsAssignable(collectionElementType, arraySource.ElementType)
            }
        }

        // User-defined implicit conversions, last so they can never shadow a built-in relation.
        if HasImplicitConversion(resolvedSource, resolvedTarget) {
            return true
        }

        return false
    }

    // Nominal subtyping: walk the base class chain and the interface lists of N#-declared types. A
    // generic instantiation is first replaced by its OPEN definition, under the substitution its
    // arguments induce, so `Box<int>`'s bases are read as `Box<T>`'s with `T` bound.
    public func IsSubtypeOf(source: TypeInfo, target: TypeInfo): bool {
        effectiveSource := source
        substitution: Dictionary<string, TypeInfo>? = null
        genericSource := effectiveSource as GenericTypeInfo
        if genericSource != null {
            genericDefinition := typeSubstitution.ResolveGenericDefinition(genericSource)
            if genericDefinition != null {
                reflectionDefinition := genericDefinition as ReflectionTypeInfo
                if reflectionDefinition == null {
                    substitution = declarationContext.CreateGenericSubstitution(
                        genericDefinition,
                        genericSource.TypeArguments)
                    effectiveSource = genericDefinition
                }
            }
        }

        classSource := effectiveSource as ClassTypeInfo
        if classSource != null {
            baseClass := classSource.BaseClass
            if baseClass != null {
                baseType := typeSubstitution.ResolveTypeForSourceOwner(baseClass, classSource, substitution)
                if IsAssignable(target, baseType) {
                    return true
                }
            }

            if AnyInterfaceAssignable(classSource.Interfaces, classSource, substitution, target) {
                return true
            }
        }

        structSource := effectiveSource as StructTypeInfo
        if structSource != null {
            if AnyInterfaceAssignable(structSource.Interfaces, structSource, substitution, target) {
                return true
            }
        }

        recordSource := effectiveSource as RecordTypeInfo
        if recordSource != null {
            if AnyInterfaceAssignable(recordSource.Interfaces, recordSource, substitution, target) {
                return true
            }
        }

        interfaceSource := effectiveSource as InterfaceTypeInfo
        if interfaceSource != null {
            if AnyInterfaceAssignable(
                    interfaceSource.BaseInterfaces,
                    interfaceSource,
                    substitution,
                    target) {
                return true
            }
        }

        reflectionSource := effectiveSource as ReflectionTypeInfo
        reflectionTarget := target as ReflectionTypeInfo
        if reflectionSource != null && reflectionTarget != null {
            sourceClrType := reflectionSource.Type
            targetClrType := reflectionTarget.Type
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(sourceClrType, targetClrType) {
                return false
            }

            return AnalyzerConversionFacts.IsReflectionAssignableFrom(targetClrType, sourceClrType)
        }

        return false
    }

    // A method group against a real CLR delegate's signature: the same score the overload resolver
    // ranks candidates with, read only for its success.
    public func IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(
        source: FunctionTypeInfo,
        target: FunctionTypeInfo): bool {
        score := 0
        return TryGetRuntimeDelegateMethodGroupMatchScore(source, target, out score)
    }

    // Signature match with a SCORE, so a method group with several candidates can pick the best. An
    // unknown source parameter contributes nothing and is not a mismatch — a lambda still being
    // inferred must not be pre-judged. Note the RETURN is scored target ← source reversed
    // (`TryGetDelegateSignatureConversionScore(target.ReturnType, source.ReturnType)`), which is
    // covariance.
    public func TryGetRuntimeDelegateMethodGroupMatchScore(
        source: FunctionTypeInfo,
        target: FunctionTypeInfo,
        out score: int): bool {
        score = 0
        sourceParameters := ParameterTypesOrEmpty(source)
        targetParameters := ParameterTypesOrEmpty(target)
        if sourceParameters.Count != targetParameters.Count {
            return false
        }

        index := 0
        while index < targetParameters.Count {
            sourceParameter := sourceParameters[index]
            targetParameter := targetParameters[index]
            if !BuiltInTypes.IsUnknown(sourceParameter) {
                sourceModifier := AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(source, index)
                targetModifier := AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(target, index)
                normalizedSource := AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(sourceModifier)
                normalizedTarget := AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(targetModifier)
                if normalizedSource != normalizedTarget {
                    return false
                }

                parameterScore := 0
                if !TryGetDelegateSignatureConversionScore(
                        sourceParameter,
                        targetParameter,
                        out parameterScore) {
                    return false
                }

                score = score + parameterScore
            }

            index = index + 1
        }

        sourceReturn := source.ReturnType
        targetReturn := target.ReturnType
        if sourceReturn != null && targetReturn != null {
            if !BuiltInTypes.IsUnknown(sourceReturn) {
                returnScore := 0
                if !TryGetDelegateSignatureConversionScore(targetReturn, sourceReturn, out returnScore) {
                    return false
                }

                score = score + returnScore
            }
        }

        return true
    }

    // How well one delegate-signature position converts to another, as a score rather than a
    // verdict: 8 exact, 4 a reference conversion, 2 an open type parameter, 1 an unknown. The ladder
    // is what makes an EXACT overload beat a merely convertible one.
    func TryGetDelegateSignatureConversionScore(
        target: TypeInfo,
        source: TypeInfo,
        out score: int): bool {
        score = 0
        resolvedTarget := declarationContext.ResolveDeclaredAlias(target)
        resolvedSource := declarationContext.ResolveDeclaredAlias(source)

        if Object.ReferenceEquals(resolvedTarget, resolvedSource) {
            score = 8
            return true
        }

        if TypeInfoIdentityFacts.AreEqual(resolvedTarget, resolvedSource) {
            score = 8
            return true
        }

        if BuiltInTypes.IsUnknown(resolvedSource) || BuiltInTypes.IsUnknown(resolvedTarget) {
            score = 1
            return true
        }

        if IsGenericParameterReflection(resolvedTarget) || IsGenericParameterReflection(resolvedSource) {
            score = 2
            return true
        }

        if !assignabilityFacts.MayUseDelegateReferenceConversion(resolvedTarget)
            || !assignabilityFacts.MayUseDelegateReferenceConversion(resolvedSource) {
            return false
        }

        sourceReflection := resolvedSource as ReflectionTypeInfo
        targetReflection := resolvedTarget as ReflectionTypeInfo
        if sourceReflection != null && targetReflection != null {
            sourceClrType := sourceReflection.Type
            targetClrType := targetReflection.Type
            if !targetClrType.IsAssignableFrom(sourceClrType) {
                return false
            }

            score = 4
            return true
        }

        if targetReflection != null {
            targetClrType := targetReflection.Type
            convertedSource := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedSource)
            if convertedSource != null {
                if !targetClrType.IsAssignableFrom(convertedSource) {
                    return false
                }

                score = 4
                return true
            }

            objectType := typeof(object)
            if Object.Equals(targetClrType, objectType) || IsSubtypeOf(resolvedSource, resolvedTarget) {
                score = 4
                return true
            }

            return false
        }

        if sourceReflection != null {
            sourceClrType := sourceReflection.Type
            convertedTarget := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedTarget)
            if convertedTarget != null {
                if !convertedTarget.IsAssignableFrom(sourceClrType) {
                    return false
                }

                score = 4
                return true
            }

            return false
        }

        if IsKnownGenericTypeAssignable(resolvedTarget, resolvedSource)
            || IsSubtypeOf(resolvedSource, resolvedTarget) {
            score = 4
            return true
        }

        return false
    }

    // A lambda's function type against a `Func<...>` / `Action<...>` instantiation. A function type
    // that carries a SOURCE identity is a method group, not a lambda, and is scored as one instead.
    // Note the parameter direction: a lambda parameter is checked as the TARGET of the delegate's
    // argument, which is contravariance.
    func IsLambdaAssignableToDelegate(
        functionType: FunctionTypeInfo,
        delegateType: GenericTypeInfo): bool {
        if AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(functionType) {
            delegateSignature := AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
                delegateType)
            if delegateSignature != null {
                return IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(functionType, delegateSignature)
            }
        }

        parameterTypes := ParameterTypesOrEmpty(functionType)
        typeArguments := delegateType.TypeArguments

        if delegateType.Name == "Func" {
            expectedParameterCount := typeArguments.Count - 1
            if parameterTypes.Count != expectedParameterCount {
                return false
            }

            index := 0
            while index < expectedParameterCount {
                lambdaParameter := parameterTypes[index]
                if !BuiltInTypes.IsUnknown(lambdaParameter) {
                    if !IsAssignable(lambdaParameter, typeArguments[index]) {
                        return false
                    }
                }

                index = index + 1
            }

            returnType := functionType.ReturnType
            if returnType != null {
                if !BuiltInTypes.IsUnknown(returnType) {
                    if !IsAssignable(typeArguments[typeArguments.Count - 1], returnType) {
                        return false
                    }
                }
            }

            return true
        }

        if parameterTypes.Count != typeArguments.Count {
            return false
        }

        actionIndex := 0
        while actionIndex < typeArguments.Count {
            lambdaParameter := parameterTypes[actionIndex]
            if !BuiltInTypes.IsUnknown(lambdaParameter) {
                if !IsAssignable(lambdaParameter, typeArguments[actionIndex]) {
                    return false
                }
            }

            actionIndex = actionIndex + 1
        }

        return true
    }

    // A user-defined implicit conversion operator declared BY the source type, whose parameter
    // accepts the source and whose result the target accepts. Guarded against re-entry: a pair
    // already being asked answers false rather than recursing.
    func HasImplicitConversion(source: TypeInfo, target: TypeInfo): bool {
        if !conversionGuard.TryEnter(source, target) {
            return false
        }

        answer := false
        try {
            answer = HasImplicitConversionCore(source, target)
        } finally {
            conversionGuard.Exit(source, target)
        }

        return answer
    }

    func HasImplicitConversionCore(source: TypeInfo, target: TypeInfo): bool {
        substitution: Dictionary<string, TypeInfo>? = null
        declarationOwner := typeSubstitution.GetSourceDeclarationOwner(source, out substitution)
        if declarationOwner == null {
            return false
        }

        sourceMembers := DeclaredMembersOf(declarationOwner)
        if sourceMembers == null {
            return false
        }

        index := 0
        while index < sourceMembers.Length {
            member := sourceMembers[index]
            if IsImplicitConversionOperator(member) {
                parameterTypes := member.ParameterTypes
                parameterType := typeSubstitution.ResolveTypeForSourceOwner(
                    parameterTypes[0],
                    declarationOwner,
                    substitution)
                if IsAssignable(parameterType, source) {
                    memberReturnType := member.ReturnType
                    if memberReturnType != null {
                        returnType := typeSubstitution.ResolveTypeForSourceOwner(
                            memberReturnType,
                            declarationOwner,
                            substitution)
                        if IsAssignable(target, returnType) {
                            return true
                        }
                    }
                }
            }

            index = index + 1
        }

        return false
    }

    // The known-generic relation, with its covariant argument pairs answered here. This is slice 6's
    // pending-pair protocol ABSORBED: the classification stays in `AnalyzerAssignabilityFacts` and
    // the recursion it could not express is now simply a call.
    func IsKnownGenericTypeAssignable(target: TypeInfo, source: TypeInfo): bool {
        decision := assignabilityFacts.ClassifyKnownGenericAssignability(target, source)
        return ResolvePendingPairs(decision)
    }

    func IsFunctionTypeAssignable(source: FunctionTypeInfo, target: FunctionTypeInfo): bool {
        decision := assignabilityFacts.ClassifyFunctionTypeAssignability(source, target)
        return ResolvePendingPairs(decision)
    }

    func ResolvePendingPairs(decision: AnalyzerAssignabilityDecision): bool {
        if decision.Decided {
            return decision.Result
        }

        pendingTargets := decision.PendingTargets
        pendingSources := decision.PendingSources
        index := 0
        while index < pendingTargets.Count {
            if !IsAssignable(pendingTargets[index], pendingSources[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    func EveryArmAcceptedBySomeArm(
        targetUnion: AnonymousUnionTypeInfo,
        sourceUnion: AnonymousUnionTypeInfo): bool {
        sourceArms := sourceUnion.Arms
        index := 0
        while index < sourceArms.Count {
            if !SomeArmAccepts(targetUnion, sourceArms[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    func SomeArmAccepts(targetUnion: AnonymousUnionTypeInfo, source: TypeInfo): bool {
        targetArms := targetUnion.Arms
        index := 0
        while index < targetArms.Count {
            if IsAssignable(targetArms[index], source) {
                return true
            }

            index = index + 1
        }

        return false
    }

    func EveryArmAssignableTo(target: TypeInfo, sourceUnion: AnonymousUnionTypeInfo): bool {
        sourceArms := sourceUnion.Arms
        index := 0
        while index < sourceArms.Count {
            if !IsAssignable(target, sourceArms[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    func AnyInterfaceAssignable(
        interfaces: TypeReference[],
        owner: TypeInfo,
        substitution: Dictionary<string, TypeInfo>?,
        target: TypeInfo): bool {
        index := 0
        while index < interfaces.Length {
            interfaceType := typeSubstitution.ResolveTypeForSourceOwner(
                interfaces[index],
                owner,
                substitution)
            if IsAssignable(target, interfaceType) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func IsImplicitConversionOperator(member: DeclaredMemberInfo): bool {
        if member.Kind != DeclaredMemberKind.Function {
            return false
        }

        if !member.IsConversionOperator || !member.IsImplicitConversion {
            return false
        }

        if member.ReturnType == null {
            return false
        }

        return member.ParameterTypes.Length == 1
    }

    static func DeclaredMembersOf(declarationOwner: TypeInfo): DeclaredMemberInfo[]? {
        classType := declarationOwner as ClassTypeInfo
        if classType != null {
            return classType.DeclaredMembers
        }

        structType := declarationOwner as StructTypeInfo
        if structType != null {
            return structType.DeclaredMembers
        }

        recordType := declarationOwner as RecordTypeInfo
        if recordType != null {
            return recordType.DeclaredMembers
        }

        return null
    }

    static func IsGenericParameterReflection(candidate: TypeInfo): bool {
        reflection := candidate as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        reflected := reflection.Type
        return reflected.get_IsGenericParameter()
    }

    static func ParameterTypesOrEmpty(functionType: FunctionTypeInfo): List<TypeInfo> {
        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null {
            return new List<TypeInfo>()
        }

        return parameterTypes
    }
}
