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
    // THE `params` TAIL'S ELEMENT TYPE, or null when this call binds in NORMAL form — which every
    // call this resolver could select before did. When it is set, `ParameterTypes` is the PER-ARGUMENT
    // list the call site writes (the fixed slots, then the element type once per packed argument) and
    // `DeclaredParameterTypes` is the signature the method actually has; `FixedArgumentCount` is where
    // the packing starts.
    ExpandedElementType: Type?
    DeclaredParameterTypes: Type[]
    FixedArgumentCount: int

    IsExpanded: bool => ExpandedElementType != null
    IsSelected: bool => Status == ColumnarOrdinaryRuntimeDirectCallStatus.Selected
    IsOwnedRejected: bool => Status == ColumnarOrdinaryRuntimeDirectCallStatus.Rejected
    IsExcluded: bool => Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    IsNotFound: bool => Status == ColumnarOrdinaryRuntimeDirectCallStatus.NotFound
    UsesCallVirtual: bool => Kind == ColumnarExternalCallKind.CallVirtual

    constructor(status: ColumnarOrdinaryRuntimeDirectCallStatus, method: MethodInfo?, lookupType: Type, declaringType: Type, parameterTypes: Type[], returnType: Type, kind: ColumnarExternalCallKind, isStatic: bool, receiverIsReference: bool, isAbstract: bool, expandedElementType: Type?, declaredParameterTypes: Type[]?, fixedArgumentCount: int) {
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
        ExpandedElementType = expandedElementType
        DeclaredParameterTypes = declaredParameterTypes ?? parameterTypes
        FixedArgumentCount = fixedArgumentCount
        if expandedElementType != null && (fixedArgumentCount < 0 || fixedArgumentCount > parameterTypes.Length || declaredParameterTypes == null) {
            throw new InvalidOperationException("An expanded ordinary runtime direct call requires its declared signature and the slot the packing starts at.")
        }
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
// fixed-arity, non-generic, non-varargs, non-params invocations. By-reference parameters remain
// ordinary fixed-arity members when the caller supplies the matching ref/out address; a by-reference
// RETURN and an unsupported element signature stay outside this owner. Candidate ranking
// deliberately reuses source-call argument scores so source and runtime calls cannot disagree
// about identity, numeric, reference, and boxing preference tiers.
class ColumnarOrdinaryRuntimeDirectCallResolver {
    static func Resolve(lookupType: Type, memberName: string, argumentTypes: Type[], expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveWithFacts(lookupType, memberName, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length), expectedStatic)
    }

    static func ResolveWithFacts(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveWithFactsCore(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, false)
    }

    // THE SAME RESOLUTION, WITH THE BASE'S `protected` SURFACE IN THE CANDIDATE SET.
    //
    // `lookupType` here is the EXTERNAL BASE of the source type whose body is being emitted, and a
    // derived type owns everything its base declares `protected`: `SetItem(0, v)`,
    // `base.ClearItems()` and `this.SetItem(...)` inside a `Collection<T>` subclass are calls the
    // CLR admits and `GetMethods()`'s default public-only enumeration could not see. Only the
    // inherited-base call sites enter here; every other receiver keeps the public surface, and the
    // level filter still refuses `private` and `assembly` because the base is in another assembly.
    static func ResolveInheritedWithFacts(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveWithFactsCore(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, true)
    }

    static func ResolveWithFactsCore(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, allowInheritedProtected: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        ValidateInputs(lookupType, memberName, argumentTypes)
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        genericDefinition := typeof(object)
        closedArguments := new Type[](0)
        if TryGetBuilderBoundRuntimeDefinition(lookupType, out genericDefinition, out closedArguments) {
            try {
                // THE DEFINITION'S OWN CANDIDATE SURFACE, BASE INTERFACES INCLUDED. A bare
                // `GetMethods()` on an interface definition answers only what that interface
                // DECLARES, so every member an inherited interface declares was invisible to a
                // receiver closed over a source type: `ILogger<TheHandler>.IsEnabled` is declared on
                // the non-generic `ILogger`, and `IList<Row>.Add` on `ICollection<T>`, while the
                // identical calls on `ILogger<string>` and `IList<string>` resolved through the
                // walk below. It is the same walk, asked of the definition.
                candidates := CandidateMethods(genericDefinition, allowInheritedProtected)
                if candidates == null {
                    throw new InvalidOperationException("Runtime generic method enumeration returned null.")
                }

                return ResolveFromCandidatesCore(lookupType, genericDefinition, closedArguments, memberName, argumentTypes, argumentFacts, expectedStatic, candidates, allowInheritedProtected)
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
            candidates := CandidateMethods(lookupType, allowInheritedProtected)
            if candidates == null {
                throw new InvalidOperationException("Runtime method enumeration returned null.")
            }

            return ResolveFromCandidatesCore(lookupType, lookupType, new Type[](0), memberName, argumentTypes, argumentFacts, expectedStatic, candidates, allowInheritedProtected)
        } catch ex: NotSupportedException {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        } catch ex: InvalidOperationException {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }
    }

    // DOES THIS RECEIVER DECLARE ANY REACHABLE INSTANCE METHOD OF THIS NAME AND ARITY?
    //
    // A loose existence question, for an entry gate that has to decide whether a bare name is worth
    // resolving at all. It answers over the SAME candidate set the resolution above uses — including
    // the `protected` surface of an inherited base, and including a base closed over a type this
    // compilation is writing, which answers no member query of its own and is asked through its
    // generic definition instead. A gate that asked a narrower question than the resolution behind it
    // is how `SetItem(0, value)` inside a `Collection<T>` subclass declined as an unresolvable bare
    // call while `this.SetItem(0, value)` — the same member, the same receiver — emitted.
    static func HasInstanceMethodAtArity(lookupType: Type, memberName: string, argumentCount: int, allowInheritedProtected: bool): bool {
        if lookupType == null || memberName == null || memberName.Length == 0 || argumentCount < 0 {
            return false
        }

        genericDefinition := typeof(object)
        closedArguments := new Type[](0)
        candidateLookupType := lookupType
        if TryGetBuilderBoundRuntimeDefinition(lookupType, out genericDefinition, out closedArguments) {
            candidateLookupType = genericDefinition
        }

        candidates: MethodInfo[]? = null
        try {
            candidates = CandidateMethods(candidateLookupType, allowInheritedProtected)
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        } catch ex: InvalidOperationException {
            return false
        } catch ex: ArgumentException {
            return false
        }

        if candidates == null {
            return false
        }

        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            index = index + 1
            if candidate == null || !IsPublicCandidateForLookup(candidate, candidateLookupType, memberName, false, allowInheritedProtected) {
                continue
            }

            parameters := candidate.GetParameters()
            if parameters != null && parameters.Length == argumentCount {
                return true
            }
        }

        return false
    }

    // EVERY METHOD A RECEIVER CAN ANSWER. For a class that is `GetMethods()`, which already walks the
    // base chain. For an INTERFACE it is not: reflection does not include inherited interface members,
    // so `IList<T>.get_Count` — declared on `ICollection<T>` — was invisible and the call declined as
    // unmodeled. The two named shapes above are what that gap cost before it was general; this is the
    // rule they were standing in for.
    //
    // `GetInterfaces()` answers with CLOSED constructed bases, so a rebind is not needed and the
    // declaring type each candidate carries is the real CLR owner the call must be emitted against.
    // Duplicates are harmless: candidate selection compares signatures, and a base interface reached
    // twice offers the same `MethodInfo`.
    // Which accessibilities the candidate enumeration asks metadata for. `Public | Instance | Static`
    // is exactly what a bare `GetMethods()` answers, so the ordinary path is unchanged; the
    // inherited-base form adds `NonPublic`, and the level filter beside it decides what of that is
    // actually reachable.
    static func CandidateMethodFlags(allowInheritedProtected: bool): BindingFlags {
        return CandidateMethodFlags(allowInheritedProtected, null)
    }

    // The FRIEND arm widens the same opt-in for the same reason: an `internal` method of an assembly
    // that named this one in an `InternalsVisibleTo` is a candidate, and `GetMethods` will not return
    // it without `NonPublic`. The level filter beside this decides what of the widened set is
    // actually reachable, so asking for more here never admits more than the relation allows.
    static func CandidateMethodFlags(allowInheritedProtected: bool, lookupType: Type?): BindingFlags {
        flags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static
        if allowInheritedProtected || InternalsVisibleToEmissionScope.GrantsAccessToDeclarer(lookupType) {
            flags = flags | BindingFlags.NonPublic
        }

        return flags
    }

    static func CandidateMethods(lookupType: Type): MethodInfo[] {
        return CandidateMethods(lookupType, false)
    }

    static func CandidateMethods(lookupType: Type, allowInheritedProtected: bool): MethodInfo[] {
        declared := lookupType.GetMethods(CandidateMethodFlags(allowInheritedProtected, lookupType))
        if declared == null || !lookupType.get_IsInterface() {
            return declared
        }

        baseInterfaces := lookupType.GetInterfaces()
        if baseInterfaces == null || baseInterfaces.Length == 0 {
            return declared
        }

        combined := new List<MethodInfo>()
        index := 0
        while index < declared.Length {
            combined.Add(declared[index])
            index = index + 1
        }

        baseIndex := 0
        while baseIndex < baseInterfaces.Length {
            inherited := baseInterfaces[baseIndex].GetMethods(CandidateMethodFlags(allowInheritedProtected, baseInterfaces[baseIndex]))
            baseIndex = baseIndex + 1
            if inherited == null {
                continue
            }

            inheritedIndex := 0
            while inheritedIndex < inherited.Length {
                AddOrKeepMostDerived(combined, inherited[inheritedIndex])
                inheritedIndex = inheritedIndex + 1
            }
        }

        return combined.ToArray()
    }

    // THE MOST DERIVED DECLARATION OF A SIGNATURE WINS, which is what makes the sweep above safe.
    // `IEnumerator<T>` re-declares `get_Current` that `IEnumerator` also declares, and
    // `IEnumerable<T>` re-declares `GetEnumerator`; collecting both would leave two arity-0
    // candidates and turn an exact call into an ambiguity. C# hides the base declaration behind the
    // derived one, and so does this: same name and same parameter types means one candidate, and the
    // one kept is the one whose declaring interface the other is assignable FROM.
    static func AddOrKeepMostDerived(candidates: List<MethodInfo>, inherited: MethodInfo) {
        inheritedParameters := inherited.GetParameters()
        index := 0
        while index < candidates.Count {
            existing := candidates[index]
            if SameCallSignature(existing, existing.GetParameters(), inherited, inheritedParameters) {
                if HidesDeclaration(inherited, existing) {
                    candidates[index] = inherited
                }

                return
            }

            index = index + 1
        }

        candidates.Add(inherited)
    }

    static func SameCallSignature(left: MethodInfo, leftParameters: ParameterInfo[], right: MethodInfo, rightParameters: ParameterInfo[]): bool {
        if left.get_Name() != right.get_Name() || left.get_IsStatic() != right.get_IsStatic() || leftParameters.Length != rightParameters.Length {
            return false
        }

        index := 0
        while index < leftParameters.Length {
            if !ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(leftParameters[index].get_ParameterType(), rightParameters[index].get_ParameterType()) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // Whether `candidate`'s declaring interface is strictly more derived than `existing`'s.
    static func HidesDeclaration(candidate: MethodInfo, existing: MethodInfo): bool {
        candidateOwner := candidate.get_DeclaringType()
        existingOwner := existing.get_DeclaringType()
        if candidateOwner == null || existingOwner == null || ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(candidateOwner, existingOwner) {
            return false
        }

        try {
            return existingOwner.IsAssignableFrom(candidateOwner)
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
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
        return ResolveFromCandidatesCore(lookupType, candidateLookupType, closedArguments, memberName, argumentTypes, argumentFacts, expectedStatic, candidates, false)
    }

    static func ResolveFromCandidatesCore(lookupType: Type, candidateLookupType: Type, closedArguments: Type[], memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidates: MethodInfo[], allowInheritedProtected: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        hadExcludedShape := false
        hadOptionalExpansion := false
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
            if candidate != null && IsPublicCandidateForLookup(candidate, candidateLookupType, memberName, expectedStatic, allowInheritedProtected) {
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
                        hadOptionalExpansion = true
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
                                // A TIE BETWEEN TWO DECLARATIONS OF ONE SIGNATURE IS NOT AN AMBIGUITY
                                // WHEN ONE HIDES THE OTHER (C# §12.5). `Task<TResult>` re-declares
                                // `GetAwaiter()` — returning `TaskAwaiter<TResult>` where the base
                                // `Task`'s returns `TaskAwaiter` — and `GetMethods()` hands back both,
                                // so a written `t.GetAwaiter()` on a `Task<int>` scored two zero-argument
                                // candidates equally and was owned-REJECTED, while the identical call on
                                // a non-generic `Task` bound. A return type is not part of a signature;
                                // the hiding relation is, and the more derived declaration wins.
                                hidesSelected := selected != null && SameCallSignature(selected, selected.GetParameters(), candidate, parameters) && HidesDeclaration(candidate, selected)
                                hiddenBySelected := selected != null && SameCallSignature(selected, selected.GetParameters(), candidate, parameters) && HidesDeclaration(selected, candidate)
                                if hidesSelected {
                                    selected = candidate
                                    selectedParameters = parameterTypes
                                    selectedReturnType = returnType
                                } else if !hiddenBySelected {
                                    bestCount += 1
                                }
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
            // AN EXPANDED CANDIDATE THAT BINDS BY IDENTITY BEATS THE LATER OWNERS, AND ONLY THAT ONE
            // DOES. This is the same tiebreak the fixed-arity result above already applies against a
            // mixed set (`bestScore == argumentTypes.Length * 8`), and it exists because "normal form
            // beats expanded" is NOT an ordering of tiers — C# compares the parameter CONVERSIONS
            // first (§12.6.4.3) and only falls back to the normal/expanded distinction when the
            // parameter sequences are equivalent.
            //
            // The two calls that fix the position between them: `string.Join("|", "only")` is "only"
            // in C#, because the expanded `Join(string, params string?[])` converts its argument by
            // IDENTITY while the generic `Join<char>(string, IEnumerable<char>)` — which is applicable
            // in normal form — needs a reference conversion; and `string.Join(",", entries)` over a
            // `List<string>` is the joined LIST, because the expanded `params object?[]` would pack
            // the list itself and only `Join<string>(string, IEnumerable<T>)` reads it as a sequence.
            // An identity-only pass here answers the first and declines the second; the call owners
            // ask again, without the restriction, after every other tier has declined.
            // A TRAILING-OPTIONAL CANDIDATE IS APPLICABLE IN ITS NORMAL FORM TOO, and it is owned by a
            // resolver of its own that the call sites ask after this one. `"a,b".Split(',')` binds
            // `Split(char, StringSplitOptions = None)` there; the expanded `Split(params char[])`
            // converts its one argument by identity and would otherwise win this pass, silently
            // changing which overload a written call reaches.
            if !hadOptionalExpansion {
                identityExpansion := ResolveExpandedFromCandidates(lookupType, candidateLookupType, closedArguments, memberName, argumentTypes, argumentFacts, expectedStatic, candidates, allowInheritedProtected, true)
                if identityExpansion.IsSelected {
                    return identityExpansion
                }
            }

            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }

        if bestCount > 1 || hadFixedArity {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Rejected, lookupType, expectedStatic)
        }

        return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
    }

    // THE LAST TIER OF THE ORDINARY CALL LADDER: the call site packs a `params` tail.
    //
    // It is asked only after the fixed-arity, generic and trailing-optional resolvers have all
    // declined, because every one of those binds a candidate applicable in its NORMAL form and C#
    // prefers all of them to an expanded one (ECMA-334 §12.6.4.2). The candidate enumeration and the
    // admission rules are the ordinary resolver's own, so a method reachable here is a method
    // reachable there.
    static func ResolveExpandedWithFacts(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        ValidateInputs(lookupType, memberName, argumentTypes)
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        // A BUILDER-BOUND receiver keeps its existing decline: its instantiation answers no member
        // query of its own, and no call site has asked for a packed call through one.
        genericDefinition := typeof(object)
        closedArguments := new Type[](0)
        if TryGetBuilderBoundRuntimeDefinition(lookupType, out genericDefinition, out closedArguments) {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }

        try {
            candidates := CandidateMethods(lookupType, false)
            if candidates == null {
                return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
            }

            return ResolveExpandedFromCandidates(lookupType, lookupType, new Type[](0), memberName, argumentTypes, argumentFacts, expectedStatic, candidates, false, false)
        } catch ex: NotSupportedException {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        } catch ex: InvalidOperationException {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }
    }

    // THE EXPANDED TIER, and it selects nothing a normal-form tier could have selected.
    //
    // Only a candidate whose LAST parameter carries `[ParamArray]` is considered, and only when the
    // site supplied at least as many arguments as the signature has fixed slots. The per-argument
    // parameter types come from the shared owner, so the SAME argument scorer ranks an expanded
    // candidate as it ranks any other and an expanded call cannot disagree with an ordinary one about
    // what converts. A tie between two expanded candidates is an ambiguity and is refused rather than
    // guessed, exactly as the fixed-arity tier refuses one.
    //
    // A BY-REF ARGUMENT NEVER REACHES HERE: a `params` tail cannot be by-ref and the fixed slots are
    // asked the ordinary supported-signature question, so the packing writes only ordinary values.
    static func ResolveExpandedFromCandidates(lookupType: Type, candidateLookupType: Type, closedArguments: Type[], memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidates: MethodInfo[], allowInheritedProtected: bool, identityOnly: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        // NORMAL FORM FIRST, AND FOR THESE CANDIDATES NOBODY ELSE HAS ASKED. A `params` declaration is
        // an EXCLUDED shape to the walk above, so its normal form — the one where the caller already
        // supplies the array — was never scored there either: `string.Join("+", parts)` over a
        // `string[]` has no non-params overload to fall back on. Scoring the declared signature here,
        // before any packing is considered, is what keeps ECMA-334 §12.6.4.2 true; without it the
        // `object?[]` tail would pack the array itself and join its ToString().
        normalForm := ResolveParamsNormalForm(lookupType, candidateLookupType, closedArguments, memberName, argumentTypes, argumentFacts, expectedStatic, candidates, allowInheritedProtected, identityOnly)
        if normalForm.IsSelected {
            return normalForm
        }

        bestScore := -1
        bestCount := 0
        selected: MethodInfo? = null
        selectedExpanded := new Type[](0)
        selectedDeclared := new Type[](0)
        selectedReturnType := typeof(object)
        selectedElement: Type? = null
        selectedFixedCount := -1
        builderBound := closedArguments.Length > 0

        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate != null && !candidate.get_IsGenericMethod() && !candidate.get_IsGenericMethodDefinition() && !IsVarArgs(candidate) && IsPublicCandidateForLookup(candidate, candidateLookupType, memberName, expectedStatic, allowInheritedProtected) {
                parameters := candidate.GetParameters()
                if parameters == null {
                    throw new InvalidOperationException("Runtime method parameters cannot be null.")
                }

                parameterTypes := ResolveParameterTypes(candidate, candidateLookupType, parameters, closedArguments)
                returnType := ResolveReturnType(candidate, candidateLookupType, closedArguments)
                elementType := ColumnarParamsExpansion.ElementTypeOrNull(parameters, parameterTypes)
                if elementType != null && !HasUnsupportedResolvedSignature(parameters, parameterTypes, returnType, closedArguments) && CanDispatch(candidate, lookupType, expectedStatic) {
                    expandedTypes := ColumnarParamsExpansion.ExpandedParameterTypesOrNull(parameters, parameterTypes, 0, argumentTypes.Length)
                    if expandedTypes != null {
                        score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expandedTypes, argumentTypes, argumentFacts)
                        if score > bestScore {
                            bestScore = score
                            bestCount = 1
                            selected = candidate
                            selectedExpanded = expandedTypes
                            selectedDeclared = parameterTypes
                            selectedReturnType = returnType
                            selectedElement = elementType
                            selectedFixedCount = ColumnarParamsExpansion.FixedArgumentCount(parameterTypes, 0)
                        } else if score >= 0 && score == bestScore {
                            bestCount += 1
                        }
                    }
                }
            }

            index += 1
        }

        if bestCount != 1 || selected == null || selectedElement == null || bestScore < 0 {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }

        if identityOnly && bestScore != argumentTypes.Length * 8 {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }

        if builderBound {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }

        return SelectedExpanded(lookupType, selected, selectedExpanded, selectedDeclared, selectedReturnType, selectedElement, selectedFixedCount, expectedStatic)
    }

    // The declared arity of a `params` candidate, scored like any other fixed-arity call.
    static func ResolveParamsNormalForm(lookupType: Type, candidateLookupType: Type, closedArguments: Type[], memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidates: MethodInfo[], allowInheritedProtected: bool, identityOnly: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        bestScore := -1
        bestCount := 0
        selected: MethodInfo? = null
        selectedParameters := new Type[](0)
        selectedReturnType := typeof(object)

        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate != null && !candidate.get_IsGenericMethod() && !candidate.get_IsGenericMethodDefinition() && !IsVarArgs(candidate) && IsPublicCandidateForLookup(candidate, candidateLookupType, memberName, expectedStatic, allowInheritedProtected) {
                parameters := candidate.GetParameters()
                if parameters == null {
                    throw new InvalidOperationException("Runtime method parameters cannot be null.")
                }

                if parameters.Length == argumentTypes.Length {
                    parameterTypes := ResolveParameterTypes(candidate, candidateLookupType, parameters, closedArguments)
                    returnType := ResolveReturnType(candidate, candidateLookupType, closedArguments)
                    if ColumnarParamsExpansion.ElementTypeOrNull(parameters, parameterTypes) != null && !HasUnsupportedResolvedSignature(parameters, parameterTypes, returnType, closedArguments) && CanDispatch(candidate, lookupType, expectedStatic) {
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

            index += 1
        }

        if bestCount != 1 || selected == null || bestScore < 0 || closedArguments.Length > 0 {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }

        if identityOnly && bestScore != argumentTypes.Length * 8 {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.Excluded, lookupType, expectedStatic)
        }

        return Selected(lookupType, selected, selectedParameters, expectedStatic)
    }

    static func SelectedExpanded(lookupType: Type, method: MethodInfo, expandedParameterTypes: Type[], declaredParameterTypes: Type[], returnType: Type, elementType: Type, fixedArgumentCount: int, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        declaringType := method.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("A selected runtime method requires a declaring type.")
        }

        receiverIsReference := !expectedStatic && !lookupType.get_IsValueType()
        kind := receiverIsReference ? ColumnarExternalCallKind.CallVirtual : ColumnarExternalCallKind.Call
        return new ColumnarOrdinaryRuntimeDirectCallSelection(ColumnarOrdinaryRuntimeDirectCallStatus.Selected, method, lookupType, declaringType, expandedParameterTypes, returnType, kind, expectedStatic, receiverIsReference, method.get_IsAbstract(), elementType, declaredParameterTypes, fixedArgumentCount)
    }

    // THE UNIQUE DECLARATION OF THIS NAME AT THIS ARITY, for a call site whose arguments cannot all be
    // typed before emission.
    //
    // A LAMBDA ARGUMENT HAS NO TYPE UNTIL IT IS BOUND against the parameter it is passed to, so
    // `u.Switch(a => ..., b => ...)` cannot be scored the way an ordinary call is — and scoring is the
    // only thing this tier gives up. Candidate admission, the excluded shapes and the dispatch rule
    // are the resolver's own, so a method reachable here is a method reachable there.
    //
    // MORE THAN ONE CANDIDATE IS REFUSED RATHER THAN GUESSED, because the argument types are exactly
    // what would have chosen between them: a site that leaves an ambiguity has to say more.
    static func ResolveUniqueAtArity(lookupType: Type, memberName: string, argumentCount: int, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        if lookupType == null || memberName == null || argumentCount < 0 {
            throw new InvalidOperationException("Ordinary runtime direct-call inputs cannot be null.")
        }

        if lookupType.get_IsGenericTypeDefinition() || lookupType.get_IsGenericParameter() {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
        }

        // A BUILDER-BOUND OWNER'S MEMBERS ARE READ OFF ITS OPEN DEFINITION, with this instantiation's
        // arguments closed into every position — which is exactly what the SCORING resolver above
        // already does for the same receiver. This tier used to refuse the shape outright, and it is
        // the only tier a DELEGATE argument can reach: `items.Find(m => ...)` on a `List<Money>` for a
        // source `Money` therefore declined, while the identical call on a `List<int>` bound, because
        // the baked receiver answered its own member query. `List<Money>` answers none — reflection
        // throws on a member query over a builder-bound instantiation — so the candidates come from
        // `List<T>` and the selected handle is rebound onto the instantiation.
        genericDefinition := typeof(object)
        closedArguments := new Type[](0)
        if TryGetBuilderBoundRuntimeDefinition(lookupType, out genericDefinition, out closedArguments) {
            try {
                return ResolveUniqueAtArityCore(lookupType, genericDefinition, closedArguments, memberName, argumentCount, expectedStatic)
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

        // A SOURCE owner — a `TypeBuilder`, or an instantiation of one — is not an ordinary RUNTIME
        // receiver at all: its members belong to the exact source resolver, and the reflection objects
        // an instantiation hands out cannot even be asked about their custom attributes (the base
        // `ParameterInfo` answers "not implemented"), so it must be refused before any candidate is read.
        if ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(lookupType) {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
        }

        return ResolveUniqueAtArityCore(lookupType, lookupType, closedArguments, memberName, argumentCount, expectedStatic)
    }

    // The unique-at-arity selection itself, over one candidate surface. `candidateLookupType` is the
    // type the candidates were read from — the receiver itself, or its open definition when the
    // receiver is a builder-bound instantiation — and `closedArguments` is non-empty only in the
    // second case, where every declared position closes over it.
    static func ResolveUniqueAtArityCore(lookupType: Type, candidateLookupType: Type, closedArguments: Type[], memberName: string, argumentCount: int, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        admitted := CandidatesAtArityCore(lookupType, candidateLookupType, closedArguments, memberName, argumentCount, expectedStatic)
        if admitted.Count != 1 {
            return Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
        }

        return admitted[0]
    }

    // EVERY DECLARATION OF THIS NAME THIS RECEIVER COULD DISPATCH AT THIS ARITY, in resolution's own
    // admission terms rather than a caller's.
    //
    // `ResolveUniqueAtArity` is this list plus the sentence "exactly one, or nothing". The list itself
    // is what a caller needs when its ARGUMENTS still carry the information that would choose — a
    // collection expression, which has no type until a parameter names its element type, is the shape
    // that has it: `Encoding.UTF8.GetString([72, 105])` leaves two arity-1 declarations standing here
    // (`byte[]` and `ReadOnlySpan<byte>`), and only the `byte[]` one can accept the literal that was
    // actually written. A caller that can answer THAT question filters this list and is left with the
    // overload the language chose; one that cannot keeps asking for the unique answer and is refused
    // exactly as before.
    //
    // The admission rules are not restated anywhere: accessibility, name, staticness, arity, the
    // excluded intrinsic shapes, an unsupported resolved signature and dispatchability are all decided
    // here, once, so a filtered candidate is a candidate resolution itself would have selected.
    static func CandidatesAtArity(lookupType: Type, memberName: string, argumentCount: int, expectedStatic: bool): List<ColumnarOrdinaryRuntimeDirectCallSelection> {
        empty := new List<ColumnarOrdinaryRuntimeDirectCallSelection>()
        if lookupType == null || memberName == null || argumentCount < 0 {
            return empty
        }

        if lookupType.get_IsGenericTypeDefinition() || lookupType.get_IsGenericParameter() {
            return empty
        }

        genericDefinition := typeof(object)
        closedArguments := new Type[](0)
        if TryGetBuilderBoundRuntimeDefinition(lookupType, out genericDefinition, out closedArguments) {
            try {
                return CandidatesAtArityCore(lookupType, genericDefinition, closedArguments, memberName, argumentCount, expectedStatic)
            } catch ex: NotSupportedException {
                return empty
            } catch ex: NotImplementedException {
                return empty
            } catch ex: InvalidOperationException {
                return empty
            } catch ex: ArgumentException {
                return empty
            }
        }

        if ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(lookupType) {
            return empty
        }

        try {
            return CandidatesAtArityCore(lookupType, lookupType, new Type[](0), memberName, argumentCount, expectedStatic)
        } catch ex: NotSupportedException {
            return empty
        } catch ex: NotImplementedException {
            return empty
        } catch ex: InvalidOperationException {
            return empty
        } catch ex: ArgumentException {
            return empty
        }
    }

    static func CandidatesAtArityCore(lookupType: Type, candidateLookupType: Type, closedArguments: Type[], memberName: string, argumentCount: int, expectedStatic: bool): List<ColumnarOrdinaryRuntimeDirectCallSelection> {
        builderBound := closedArguments.Length > 0
        candidates := CandidatesOrEmpty(candidateLookupType)
        if builderBound {
            ValidateBuilderBoundCandidates(candidates)
        }

        admitted := new List<ColumnarOrdinaryRuntimeDirectCallSelection>()
        admittedMethods := new List<MethodInfo>()
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            index = index + 1
            if candidate == null || !IsPublicCandidateForLookup(candidate, candidateLookupType, memberName, expectedStatic) {
                continue
            }

            parameters := candidate.GetParameters()
            if parameters == null || parameters.Length != argumentCount || IsIntrinsicExcludedShape(candidate, parameters) {
                continue
            }

            parameterTypes := ResolveParameterTypes(candidate, candidateLookupType, parameters, closedArguments)
            returnType := ResolveReturnType(candidate, candidateLookupType, closedArguments)
            if HasUnsupportedResolvedSignature(parameters, parameterTypes, returnType, closedArguments) || !CanDispatch(candidate, lookupType, expectedStatic) {
                continue
            }

            let admittedSelection: ColumnarOrdinaryRuntimeDirectCallSelection = null
            if builderBound {
                admittedSelection = SelectedBuilderBound(lookupType, candidateLookupType, candidate, parameterTypes, returnType, expectedStatic)
            } else {
                admittedSelection = Selected(lookupType, candidate, parameterTypes, expectedStatic)
            }
            AdmitUnlessHidden(admittedMethods, admitted, candidate, admittedSelection)
        }

        return admitted
    }

    // A MEMBER DECLARED IN A MORE DERIVED TYPE HIDES ONE OF THE SAME SIGNATURE IN A BASE (C# §12.5),
    // and `Type.GetMethods()` hands back BOTH. `Task<TResult>` re-declares `GetAwaiter()` — returning
    // `TaskAwaiter<TResult>` where the base `Task`'s returns `TaskAwaiter` — so a written
    // `t.GetAwaiter()` on a `Task<int>` left two declarations standing at arity 0 and the
    // unique-at-arity rule refused a call C# resolves without hesitation. A RETURN TYPE is not part of
    // a signature; the hiding relation is, and it is the same one the interface walk beside this
    // already applies.
    //
    // WHEN NEITHER DECLARATION HIDES THE OTHER both are kept, because that is a real ambiguity: two
    // unrelated base interfaces declaring one signature is exactly the shape C# refuses, and the
    // unique-at-arity rule is what refuses it here.
    static func AdmitUnlessHidden(methods: List<MethodInfo>, selections: List<ColumnarOrdinaryRuntimeDirectCallSelection>, candidate: MethodInfo, selection: ColumnarOrdinaryRuntimeDirectCallSelection) {
        candidateParameters := candidate.GetParameters()
        index := 0
        while index < methods.Count {
            existing := methods[index]
            if SameCallSignature(existing, existing.GetParameters(), candidate, candidateParameters) {
                if HidesDeclaration(candidate, existing) {
                    methods[index] = candidate
                    selections[index] = selection
                    return
                }

                if HidesDeclaration(existing, candidate) {
                    return
                }
            }

            index = index + 1
        }

        methods.Add(candidate)
        selections.Add(selection)
    }

    static func ValidateBuilderBoundCandidates(candidates: MethodInfo[]) {
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate != null {
                declaringType := candidate.get_DeclaringType()
                if declaringType != null && DeclaringTypeIsBuilderBoundInstantiation(declaringType) {
                    throw new InvalidOperationException("Builder-bound runtime candidates must come from the open generic definition.")
                }
            }

            index += 1
        }
    }

    // WHAT THIS GUARD IS ACTUALLY ABOUT: a handle read from a TypeBuilder INSTANTIATION instead of
    // from the open definition. It asked `ContainsBuilderBoundType`, which answers true for a bare
    // GENERIC PARAMETER as well — and a candidate read off the definition's own base names exactly
    // that: `IList<T>` implements `ICollection<T>`, so `ICollection<T>::Add` is declared on a type
    // constructed over the definition's own `T` and tripped the guard. A parameter is not a source
    // type; an argument that is one is, and that is the case this rejects.
    static func DeclaringTypeIsBuilderBoundInstantiation(declaringType: Type): bool {
        if declaringType.get_IsGenericParameter() {
            return false
        }

        if ColumnarRuntimeInstanceMemberResolver.IsSourceBuilderShape(declaringType) {
            return true
        }

        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(declaringType) {
            elementType := declaringType.GetElementType()
            return elementType != null && DeclaringTypeIsBuilderBoundInstantiation(elementType)
        }

        if !declaringType.get_IsGenericType() || declaringType.get_IsGenericTypeDefinition() {
            return false
        }

        arguments := declaringType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if DeclaringTypeIsBuilderBoundInstantiation(arguments[index]) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func IsPublicCandidateForLookup(method: MethodInfo, lookupType: Type, memberName: string, expectedStatic: bool): bool {
        return IsPublicCandidateForLookup(method, lookupType, memberName, expectedStatic, false)
    }

    static func IsPublicCandidateForLookup(method: MethodInfo, lookupType: Type, memberName: string, expectedStatic: bool, allowInheritedProtected: bool): bool {
        if !ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.LevelOfMethod(method), allowInheritedProtected, method.get_DeclaringType()) || method.get_Name() != memberName || method.get_IsStatic() != expectedStatic {
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
        substitute := SubstitutesClosedArguments(declaringType, candidateLookupType, closedArguments)
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
        if SubstitutesClosedArguments(declaringType, candidateLookupType, closedArguments) {
            return ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(returnType, closedArguments)
        }

        return returnType
    }

    // WHOSE TYPE PARAMETERS A CANDIDATE'S SIGNATURE MENTIONS. A member read off the definition
    // itself mentions the definition's parameters, and so does one read off a base the definition
    // names over those same parameters (`IList<T>` implements `ICollection<T>`, and
    // `ICollection<T>::Add` takes that very `T`) — substitution is by POSITION, so both close
    // correctly against this instantiation's arguments. A base closed over something else
    // (`ICollection<int>`) mentions no parameter at all and substitutes to itself, so asking is
    // harmless; and with no closed arguments there is nothing to substitute.
    static func SubstitutesClosedArguments(declaringType: Type?, candidateLookupType: Type, closedArguments: Type[]): bool {
        if closedArguments.Length == 0 || declaringType == null {
            return false
        }

        return declaringType == candidateLookupType || declaringType.get_ContainsGenericParameters()
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
    //
    // A PARAMETER is asked the by-ref-aware question and a RETURN is not, because `ref`/`out` is a
    // parameter spelling only.
    static func HasUnsupportedResolvedSignature(parameters: ParameterInfo[], parameterTypes: Type[], returnType: Type, closedArguments: Type[]): bool {
        if parameters.Length != parameterTypes.Length || IsUnsupportedResolvedSignatureType(returnType, closedArguments) {
            return true
        }

        index := 0
        while index < parameterTypes.Length {
            if IsUnsupportedParameterType(parameterTypes[index], closedArguments) {
                return true
            }

            index += 1
        }

        return false
    }

    static func IsUnsupportedSignatureType(signatureType: Type): bool {
        return IsUnsupportedResolvedSignatureType(signatureType, new Type[](0))
    }

    // A PARAMETER may be `ref`/`out`; a RETURN type may not. The two questions were one predicate, and
    // that made every by-ref overload invisible to ordinary resolution — `Interlocked.Exchange`,
    // `int.TryParse`, every `TryGet`. What a by-ref parameter still may not be is a by-ref of something
    // unsupported, so the element is asked the ordinary question.
    static func IsUnsupportedParameterType(parameterType: Type, closedArguments: Type[]): bool {
        if !parameterType.get_IsByRef() {
            return IsUnsupportedResolvedSignatureType(parameterType, closedArguments)
        }

        elementType := parameterType.GetElementType()
        return elementType == null || elementType.get_IsByRef() || elementType.get_IsPointer() || IsUnsupportedResolvedSignatureType(elementType, closedArguments)
    }

    // A generic parameter left in a RESOLVED signature normally means the substitution did not
    // happen, which is why it is refused. On a BUILDER-BOUND instantiation it can also be the
    // correct closed answer: inside `Outcome<TOk, TErr>`, `EqualityComparer<TOk>.Equals` genuinely
    // takes two `TOk`, and `TOk` is one of the instantiation's own arguments. The distinction is
    // identity, not shape — a parameter the instantiation actually substituted IN is closed here;
    // any other one is still open. Identity is asked as REFERENCE equality, because `==` on `Type`
    // is not guaranteed to be reference identity for the builder-bound instantiations this walks.
    static func IsUnsupportedResolvedSignatureType(signatureType: Type, closedArguments: Type[]): bool {
        if signatureType.get_IsByRef() || signatureType.get_IsGenericTypeDefinition() {
            return true
        }

        if !signatureType.get_IsGenericParameter() {
            return false
        }

        index := 0
        while index < closedArguments.Length {
            if Object.ReferenceEquals(closedArguments[index], signatureType) {
                return false
            }

            index += 1
        }

        return true
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
        return new ColumnarOrdinaryRuntimeDirectCallSelection(ColumnarOrdinaryRuntimeDirectCallStatus.Selected, method, lookupType, declaringType, parameterTypes, returnType, kind, expectedStatic, receiverIsReference, method.get_IsAbstract(), null, parameterTypes, -1)
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
        } else if declaringType.get_ContainsGenericParameters() {
            // AN INHERITED DECLARATION IS REBOUND ONTO ITS OWN CLOSED OWNER, not onto the receiver's
            // instantiation: `TypeBuilder.GetMethod` binds a member to the instantiation of the type
            // that DECLARES it, so `ICollection<T>::Add` reached through `IList<Row>` becomes
            // `ICollection<Row>::Add`. A `callvirt` on the base declaration is what a receiver of the
            // derived interface dispatches through anyway, which is the same answer the non-
            // builder-bound walk gives for `IList<string>`.
            inheritedRebound := ColumnarClosedGenericMemberResolver.RebindOntoClosedOwner(method, lookupType)
            inheritedDeclaringType := inheritedRebound.get_DeclaringType()
            if Object.ReferenceEquals(inheritedRebound, method) || inheritedDeclaringType == null || inheritedDeclaringType.get_ContainsGenericParameters() {
                throw new InvalidOperationException("An inherited builder-bound runtime method could not be rebound onto a closed owner.")
            }

            exactMethod = inheritedRebound
            exactDeclaringType = inheritedDeclaringType
        }

        receiverIsReference := !expectedStatic && !lookupType.get_IsValueType()
        kind := receiverIsReference ? ColumnarExternalCallKind.CallVirtual : ColumnarExternalCallKind.Call
        return new ColumnarOrdinaryRuntimeDirectCallSelection(ColumnarOrdinaryRuntimeDirectCallStatus.Selected, exactMethod, lookupType, exactDeclaringType, parameterTypes, returnType, kind, expectedStatic, receiverIsReference, exactMethod.get_IsAbstract(), null, parameterTypes, -1)
    }

    static func Empty(status: ColumnarOrdinaryRuntimeDirectCallStatus, lookupType: Type, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return new ColumnarOrdinaryRuntimeDirectCallSelection(status, null, lookupType, lookupType, new Type[](0), typeof(object), ColumnarExternalCallKind.None, expectedStatic, false, false, null, new Type[](0), -1)
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

    // THE SAME CANDIDATE SURFACE THE SCORING RESOLVER READS, guarded. It used to be a bare
    // `GetMethods()`, which answers only what an INTERFACE declares — so the unique-at-arity tier
    // and the optional fill could not see a base interface's member while the scoring tier could,
    // and the comment above `CandidatesAtArity` promising "a candidate resolution itself would have
    // selected" was not true for one.
    static func CandidatesOrEmpty(lookupType: Type): MethodInfo[] {
        try {
            candidates := CandidateMethods(lookupType)
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
