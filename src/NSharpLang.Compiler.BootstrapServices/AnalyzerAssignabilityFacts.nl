namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

// The SHAPE DECISIONS behind the analyzer's assignability question.
//
// `IsAssignable` itself is a dispatch over arms, and the arms are what this owner holds: which
// generic instantiations stand in a known assignable relation, which of those relations are
// covariant, which types a delegate reference conversion may cross, which types a collection
// expression may target and what element type it then demands, when an array widens to a span, and
// what expected type a bare callable reference can bind to at all.
//
// TWO OF THE ARMS DELIBERATELY DO NOT LIVE HERE, and the reason is measured rather than stylistic:
// the duck-interface arm compares member signatures through the analyzer's `ResolveType`, which
// RECORDS into the semantic model and REPORTS diagnostics, and the ActionResult arm probes the
// MetadataLoadContext through the analyzer's using-namespace state. Neither can move without taking
// the type-REFERENCE engine with it. Everything here is silent: it reports nothing, records nothing,
// and holds no state that changes after construction.
//
// THE PENDING-PAIR PROTOCOL. Two of these decisions are only partly answerable without re-entering
// assignability — the known-generic relation has to compare covariant type arguments, and a function
// type has to compare parameters and returns. Rather than call back into the analyzer, they answer
// with an `AnalyzerAssignabilityDecision`: either a DECIDED verdict, or the ORDERED list of
// target/source pairs whose assignability the caller must answer, in which case the relation holds
// exactly when every pair does. That keeps the whole classification here and leaves only the
// recursion with the root.
//
// The well-known-type bag is NULLABLE and that state is live: until the analyzer has loaded its
// MetadataLoadContext there are no metadata facts, and a runtime delegate cannot be recognized at
// all. The bag is built and torn down over an analyzer's lifetime, so this owner is REBUILT at those
// points rather than mutated.

// Either a finished assignability verdict, or the pairs that decide it. `Decided` selects: when it
// is true `Result` is the answer and the pending lists are empty; when it is false the answer is
// "every pending pair is assignable, target ← source, in order".
public class AnalyzerAssignabilityDecision {

    Decided: bool
    Result: bool
    PendingTargets: List<TypeInfo>
    PendingSources: List<TypeInfo>

    constructor(
        decidedValue: bool,
        resultValue: bool,
        pendingTargetValues: List<TypeInfo>,
        pendingSourceValues: List<TypeInfo>) {
        Decided = decidedValue
        Result = resultValue
        PendingTargets = pendingTargetValues
        PendingSources = pendingSourceValues
    }

    public static func Answer(value: bool): AnalyzerAssignabilityDecision {
        return new AnalyzerAssignabilityDecision(
            true,
            value,
            new List<TypeInfo>(),
            new List<TypeInfo>())
    }

    public static func Pending(
        targets: List<TypeInfo>,
        sources: List<TypeInfo>): AnalyzerAssignabilityDecision {
        if targets.Count == 0 {
            return Answer(true)
        }

        return new AnalyzerAssignabilityDecision(false, false, targets, sources)
    }
}

public class AnalyzerAssignabilityFacts {

    declarationContext: AnalyzerDeclarationContext
    wellKnownTypes: AnalyzerWellKnownTypes?

    constructor(context: AnalyzerDeclarationContext, wellKnown: AnalyzerWellKnownTypes?) {
        declarationContext = context
        wellKnownTypes = wellKnown
    }

    // The known generic-to-generic assignability relation: a small, deliberately CLOSED table over
    // the runtime collection interfaces. Both sides must carry the real runtime generic definition —
    // a source-declared `List<T>` of the program's own is not this `List<T>` — and the arities must
    // agree. Type arguments must be identical, except that the four covariant targets accept a
    // reference-like argument pair whose assignability the caller answers.
    public func ClassifyKnownGenericAssignability(
        target: TypeInfo,
        source: TypeInfo): AnalyzerAssignabilityDecision {
        targetGeneric := target as GenericTypeInfo
        sourceGeneric := source as GenericTypeInfo
        if targetGeneric == null || sourceGeneric == null {
            return AnalyzerAssignabilityDecision.Answer(false)
        }

        if targetGeneric.TypeArguments.Count != sourceGeneric.TypeArguments.Count {
            return AnalyzerAssignabilityDecision.Answer(false)
        }

        if !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(targetGeneric)
            || !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(sourceGeneric) {
            return AnalyzerAssignabilityDecision.Answer(false)
        }

        if !IsKnownGenericConversion(targetGeneric.Name, sourceGeneric.Name) {
            return AnalyzerAssignabilityDecision.Answer(false)
        }

        isCovariantTarget := IsCovariantKnownGenericTarget(targetGeneric.Name)
        pendingTargets := new List<TypeInfo>()
        pendingSources := new List<TypeInfo>()
        index := 0
        while index < targetGeneric.TypeArguments.Count {
            targetArgument := targetGeneric.TypeArguments[index]
            sourceArgument := sourceGeneric.TypeArguments[index]
            if !TypeInfoIdentityFacts.AreEqual(targetArgument, sourceArgument) {
                if !isCovariantTarget
                    || !IsReferenceLikeForVariance(targetArgument)
                    || !IsReferenceLikeForVariance(sourceArgument) {
                    return AnalyzerAssignabilityDecision.Answer(false)
                }

                pendingTargets.Add(targetArgument)
                pendingSources.Add(sourceArgument)
            }

            index = index + 1
        }

        return AnalyzerAssignabilityDecision.Pending(pendingTargets, pendingSources)
    }

    // Structural function-type assignability. Parameter counts must agree exactly; an INFERRED
    // (unknown) source parameter is accepted without a check rather than rejected, because a lambda
    // whose parameter types are still being inferred must not be pre-judged. Note the directions:
    // a parameter pair is checked source ← target (the target's parameter must be acceptable where
    // the source's is expected) while the return pair is checked target ← source.
    public func ClassifyFunctionTypeAssignability(
        source: FunctionTypeInfo,
        target: FunctionTypeInfo): AnalyzerAssignabilityDecision {
        sourceParameterCount := 0
        if source.ParameterTypes != null {
            sourceParameterCount = source.ParameterTypes.Count
        }

        targetParameterCount := 0
        if target.ParameterTypes != null {
            targetParameterCount = target.ParameterTypes.Count
        }

        if sourceParameterCount != targetParameterCount {
            return AnalyzerAssignabilityDecision.Answer(false)
        }

        pendingTargets := new List<TypeInfo>()
        pendingSources := new List<TypeInfo>()
        index := 0
        while index < targetParameterCount {
            sourceParameter := source.ParameterTypes[index]
            targetParameter := target.ParameterTypes[index]
            if !BuiltInTypes.IsUnknown(sourceParameter) {
                pendingTargets.Add(sourceParameter)
                pendingSources.Add(targetParameter)
            }

            index = index + 1
        }

        sourceReturn := source.ReturnType
        targetReturn := target.ReturnType
        if sourceReturn != null && targetReturn != null
            && !BuiltInTypes.IsUnknown(sourceReturn) {
            pendingTargets.Add(targetReturn)
            pendingSources.Add(sourceReturn)
        }

        return AnalyzerAssignabilityDecision.Pending(pendingTargets, pendingSources)
    }

    // Which types a collection expression may be assigned to, and the element type it then demands.
    // The generic arm is nominal: the instantiation must carry the real runtime definition, so a
    // program's own `List<T>` does not silently accept `[1, 2, 3]`. The reflection arm matches the
    // metadata name and is deliberately NARROWER — the three read-only/sorted spellings the generic
    // arm accepts have no reflection counterpart here.
    public func TryGetCollectionElementType(
        candidate: TypeInfo,
        out elementType: TypeInfo): bool {
        elementType = BuiltInTypes.Unknown

        genericType := candidate as GenericTypeInfo
        if genericType != null {
            if TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(genericType)
                && IsCollectionGenericName(genericType.Name)
                && genericType.TypeArguments.Count > 0 {
                elementType = genericType.TypeArguments[0]
                return true
            }
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            reflected := reflectionType.Type
            // `IsGenericType && !IsGenericTypeDefinition` IS `IsConstructedGenericType`, and that
            // distinction is load-bearing: an OPEN definition such as `List<>` names no element
            // type, so it must answer nothing rather than answer with a type parameter.
            if IsCollectionReflectionName(reflected.get_Name())
                && reflected.get_IsGenericType()
                && !reflected.get_IsGenericTypeDefinition() {
                arguments := reflected.GetGenericArguments()
                if arguments.Length > 0 {
                    firstArgument := arguments[0]
                    elementType = new ReflectionTypeInfo(firstArgument)
                    return true
                }
            }
        }

        return false
    }

    // `T[]` → `Span<T>` / `ReadOnlySpan<T>`. Nominal on both halves: the target must be the real
    // runtime span definition (a same-named source type does not qualify) and the element types must
    // be identical after alias resolution — a span is not variant.
    public func IsArrayToSpanAssignable(target: TypeInfo, source: TypeInfo): bool {
        array := source as ArrayTypeInfo
        targetGeneric := target as GenericTypeInfo
        if array == null || targetGeneric == null {
            return false
        }

        if targetGeneric.TypeArguments.Count != 1 {
            return false
        }

        if !AnalyzerConversionFacts.IsSpanTypeName(targetGeneric.Name) {
            return false
        }

        spanDefinition := targetGeneric.GenericDefinition as ReflectionTypeInfo
        if spanDefinition == null {
            return false
        }

        runtimeSpan := Type.GetType("System.Span`1, System.Private.CoreLib")
        runtimeReadOnlySpan := Type.GetType("System.ReadOnlySpan`1, System.Private.CoreLib")
        isSpanDefinition := runtimeSpan != null
            && TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
                spanDefinition.Type,
                runtimeSpan)
        isReadOnlySpanDefinition := runtimeReadOnlySpan != null
            && TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
                spanDefinition.Type,
                runtimeReadOnlySpan)
        if !isSpanDefinition && !isReadOnlySpanDefinition {
            return false
        }

        return TypeInfoIdentityFacts.AreEqual(
            declarationContext.ResolveDeclaredAlias(targetGeneric.TypeArguments[0]),
            declarationContext.ResolveDeclaredAlias(array.ElementType))
    }

    // Variance is only offered where a CLR reference conversion could carry it, so the nullable and
    // oblivious shells are transparent and everything else defers to the delegate-reference rule.
    public func IsReferenceLikeForVariance(candidate: TypeInfo): bool {
        resolved := declarationContext.ResolveDeclaredAlias(candidate)

        nullableType := resolved as NullableTypeInfo
        if nullableType != null {
            return IsReferenceLikeForVariance(nullableType.InnerType)
        }

        obliviousType := resolved as ObliviousTypeInfo
        if obliviousType != null {
            return IsReferenceLikeForVariance(obliviousType.InnerType)
        }

        return MayUseDelegateReferenceConversion(resolved)
    }

    // Whether a delegate signature position may be crossed by a reference conversion at all. A
    // generic instantiation qualifies — it is a reference type unless it is the one value-typed
    // shape spelled generically, `Nullable<T>` — and anything else answers the reference-type rule.
    public func MayUseDelegateReferenceConversion(candidate: TypeInfo): bool {
        resolved := declarationContext.ResolveDeclaredAlias(candidate)

        genericType := resolved as GenericTypeInfo
        if genericType != null {
            return genericType.Name != "Nullable"
        }

        return AnalyzerConversionFacts.IsReferenceType(resolved)
    }

    // The expected types a bare callable reference (a method group, a lambda) can bind to: a source
    // function type, the two compiler-known delegate generics by NAME, or a real runtime delegate.
    // The nullable and oblivious shells are transparent; every other expected type rejects it, which
    // is what turns `x := SomeMethod` into a diagnostic rather than a value.
    public func CanBindCallableReferenceToExpectedType(expectedType: TypeInfo): bool {
        resolvedExpected := declarationContext.ResolveDeclaredAlias(expectedType)

        functionType := resolvedExpected as FunctionTypeInfo
        if functionType != null {
            return true
        }

        genericType := resolvedExpected as GenericTypeInfo
        if genericType != null {
            return genericType.Name == "Func" || genericType.Name == "Action"
        }

        reflectionType := resolvedExpected as ReflectionTypeInfo
        if reflectionType != null {
            return IsDelegateType(reflectionType.Type)
                || AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(reflectionType.Type)
        }

        obliviousType := resolvedExpected as ObliviousTypeInfo
        if obliviousType != null {
            return CanBindCallableReferenceToExpectedType(obliviousType.InnerType)
        }

        nullableType := resolvedExpected as NullableTypeInfo
        if nullableType != null {
            return CanBindCallableReferenceToExpectedType(nullableType.InnerType)
        }

        return false
    }

    // A CONCRETE delegate type in the load context: something that derives from `System.Delegate`
    // without BEING one of the two abstract roots, since neither root names a callable signature.
    // Without metadata facts nothing is a delegate.
    public func IsDelegateType(candidate: Type): bool {
        facts := wellKnownTypes
        if facts == null {
            return false
        }

        if !facts.Delegate.IsAssignableFrom(candidate) {
            return false
        }

        fullName := candidate.get_FullName()
        return fullName != "System.Delegate" && fullName != "System.MulticastDelegate"
    }

    // The known generic-to-generic relation, stated once. Read as "a source on the right is
    // assignable to a target on the left".
    static func IsKnownGenericConversion(targetName: string, sourceName: string): bool {
        if targetName == "IEnumerable" {
            return sourceName == "IEnumerable" || sourceName == "List"
                || sourceName == "ICollection" || sourceName == "IList"
                || sourceName == "HashSet" || sourceName == "Queue"
        }

        if targetName == "IQueryable" {
            return sourceName == "IQueryable"
        }

        if targetName == "ICollection" {
            return sourceName == "List" || sourceName == "IList" || sourceName == "HashSet"
        }

        if targetName == "IList" {
            return sourceName == "List"
        }

        if targetName == "IReadOnlyCollection" {
            return sourceName == "List" || sourceName == "IReadOnlyList"
                || sourceName == "HashSet" || sourceName == "Queue"
        }

        if targetName == "IReadOnlyList" {
            return sourceName == "List"
        }

        return false
    }

    // The four read-only/streaming targets whose type argument is covariant. The mutable ones are
    // NOT: `ICollection<Animal>` must not accept an `ICollection<Dog>`, or a caller could add a cat.
    static func IsCovariantKnownGenericTarget(name: string): bool {
        return name == "IEnumerable" || name == "IQueryable"
            || name == "IReadOnlyCollection" || name == "IReadOnlyList"
    }

    static func IsCollectionGenericName(name: string): bool {
        return name == "List" || name == "HashSet" || name == "IList"
            || name == "ICollection" || name == "IEnumerable" || name == "IQueryable"
            || name == "ISet" || name == "Queue" || name == "Stack"
            || name == "LinkedList" || name == "Collection"
            || name == "ObservableCollection" || name == "SortedSet"
            || name == "IReadOnlyList" || name == "IReadOnlyCollection"
    }

    static func IsCollectionReflectionName(name: string): bool {
        return name.StartsWith("List`") || name.StartsWith("HashSet`")
            || name.StartsWith("IList`") || name.StartsWith("ICollection`")
            || name.StartsWith("IEnumerable`") || name.StartsWith("IQueryable`")
            || name.StartsWith("ISet`") || name.StartsWith("Queue`")
            || name.StartsWith("Stack`") || name.StartsWith("LinkedList`")
            || name.StartsWith("Collection`") || name.StartsWith("ObservableCollection`")
    }
}
