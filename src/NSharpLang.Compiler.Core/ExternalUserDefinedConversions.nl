namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// USER-DEFINED CONVERSIONS DECLARED BY AN EXTERNAL TYPE, SELECTED ONCE FOR THE WHOLE COMPILER.
//
// A referenced assembly's type may declare `op_Implicit` / `op_Explicit`, and the language has to
// honour them exactly where C# does: `Union<int, string> u = 5` reaches the runtime union's
// `implicit operator Union<T0, T1>(T0)`, `decimal d = 5` does NOT (that is a built-in numeric
// widening and never a user-defined one), and `Union<float, decimal> u = 5` is an ERROR rather than
// an arbitrary pick between the two arms.
//
// THIS OWNER IS THE ONLY PLACE THAT DECIDES. The analyzer asks it whether a value may be written
// where a type is expected, and the emitter asks it which `MethodInfo` to `call`; if the two asked
// different questions the analyzer would accept programs the emitter then declined. Both ask HERE,
// over CLR `Type` values, which is the one vocabulary the two phases share — the analyzer's types
// come from its MetadataLoadContext and the emitter's from the runtime, and every comparison below
// goes through `TypeInfoIdentityFacts`, which is exact in both worlds.
//
// THE ALGORITHM IS ECMA-334 §10.5.3 (implicit) AND §10.5.4 (explicit), not a first-match scan:
//   * the CANDIDATE set is the operators declared by the source type, by the target type and by
//     their base classes — conversion operators are not inherited members, so each level is read
//     with `DeclaredOnly` and the chain is walked explicitly;
//   * an operator is APPLICABLE when a STANDARD conversion (identity, numeric widening, reference,
//     boxing, nullable lifting of those — never another user-defined one) reaches its parameter
//     from the source and reaches the target from its result;
//   * the most specific SOURCE type and most specific TARGET type are then chosen, and exactly one
//     operator must span them. Anything else is `Ambiguous`, which is a diagnostic and never a
//     silent selection.
//
// WHAT IT DELIBERATELY DOES NOT DO. A LIFTED user-defined conversion (C#'s `S? -> T?` built from
// `S -> T`) is not synthesised: the operators read are the ones actually declared, so a nullable end
// participates only through a declared operator that names it. And an owner whose metadata cannot be
// enumerated — a type still being emitted, or an external generic closed over one — contributes no
// candidates rather than a guess; `ContainsGenericParameters` and the builder test screen those out
// before any member is read.
//
// Nothing here reports, records or caches. An unresolvable question is `None`, and the caller
// decides what that means.
enum ExternalConversionStatus {
    None,
    Selected,
    Ambiguous
}

// The answer. `Selected` carries the exact handle to call; `Ambiguous` carries the two operators
// that tied, which is what the diagnostic names.
class ExternalConversionSelection {
    Status: ExternalConversionStatus
    Method: MethodInfo?
    CompetingMethod: MethodInfo?

    IsSelected: bool => Status == ExternalConversionStatus.Selected
    IsAmbiguous: bool => Status == ExternalConversionStatus.Ambiguous

    constructor(status: ExternalConversionStatus, method: MethodInfo?, competingMethod: MethodInfo?) {
        if status == ExternalConversionStatus.Selected {
            if method == null || competingMethod != null {
                throw new InvalidOperationException("A selected external conversion is exactly one operator.")
            }
        } else if status == ExternalConversionStatus.Ambiguous {
            if method == null || competingMethod == null {
                throw new InvalidOperationException("An ambiguous external conversion names the two operators that tied.")
            }
        } else if method != null || competingMethod != null {
            throw new InvalidOperationException("An unresolved external conversion cannot carry an operator.")
        }

        Status = status
        Method = method
        CompetingMethod = competingMethod
    }

    // The operator as a diagnostic names it: `Union<float, decimal>.op_Implicit(float)`. Metadata
    // names only, with the arity suffix stripped and the owner's arguments written out, because that
    // is the spelling the reader has in front of them.
    func OperatorText(method: MethodInfo?): string {
        if method == null {
            return ""
        }

        owner := method.get_DeclaringType()
        ownerText := "?"
        if owner != null {
            ownerText = ExternalUserDefinedConversions.TypeText(owner)
        }

        parameters := method.GetParameters()
        parameterText := "?"
        if parameters.Length == 1 {
            parameterType := parameters[0].get_ParameterType()
            if parameterType != null {
                parameterText = ExternalUserDefinedConversions.TypeText(parameterType)
            }
        }

        return ownerText + "." + method.get_Name() + "(" + parameterText + ")"
    }

    SelectedText: string => OperatorText(Method)
    CompetingText: string => OperatorText(CompetingMethod)

    static func NoConversion(): ExternalConversionSelection {
        return new ExternalConversionSelection(ExternalConversionStatus.None, null, null)
    }

    static func One(method: MethodInfo): ExternalConversionSelection {
        return new ExternalConversionSelection(ExternalConversionStatus.Selected, method, null)
    }

    static func Tie(first: MethodInfo, second: MethodInfo): ExternalConversionSelection {
        return new ExternalConversionSelection(ExternalConversionStatus.Ambiguous, first, second)
    }
}

class ExternalUserDefinedConversions {

    // A reflected type as a reader spells it: the bare name, the arity suffix dropped, and the
    // arguments written out. Metadata only — no N# keyword table is consulted, because this text is
    // for a diagnostic rather than for resolution.
    static func TypeText(candidate: Type): string {
        if candidate.get_IsArray() {
            elementType := candidate.GetElementType()
            if elementType != null {
                return TypeText(elementType) + "[]"
            }
        }

        // A primitive is spelled the way the PROGRAM spells it — `float`, not `Single` — so the two
        // halves of the diagnostic read as one sentence. The table is the analyzer's own, keyed on
        // metadata name, so it is exact under a MetadataLoadContext too.
        builtIn := AnalyzerReflectionTypeConversion.ConvertBuiltInReflectionType(candidate.get_FullName())
        if builtIn != null {
            boxed := builtIn as object
            rendered := boxed.ToString()
            if rendered != null {
                return rendered
            }
        }

        name := candidate.get_Name()
        tick := name.IndexOf('`')
        if tick < 0 {
            return name
        }

        rendered := name.Substring(0, tick) + "<"
        arguments := candidate.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if index > 0 {
                rendered = rendered + ", "
            }

            rendered = rendered + TypeText(arguments[index])
            index += 1
        }

        return rendered + ">"
    }

    static func NullableDefinitionFullName(): string {
        return "System.Nullable`1"
    }

    // The implicit question (§10.5.3): may a `source` value be written where `target` is expected,
    // by a conversion the two types declare between them.
    static func ResolveImplicit(sourceType: Type?, targetType: Type?): ExternalConversionSelection {
        return Resolve(sourceType, targetType, false)
    }

    // The explicit question (§10.5.4): the same, for a written cast. Every implicit operator is also
    // an explicit one, and applicability reaches in BOTH directions — a cast may narrow into the
    // operator's parameter and narrow out of its result.
    static func ResolveExplicit(sourceType: Type?, targetType: Type?): ExternalConversionSelection {
        return Resolve(sourceType, targetType, true)
    }

    static func Resolve(sourceType: Type?, targetType: Type?, allowExplicit: bool): ExternalConversionSelection {
        if sourceType == null || targetType == null {
            return ExternalConversionSelection.NoConversion()
        }

        if sourceType.get_IsByRef() || targetType.get_IsByRef() || sourceType.get_IsPointer() || targetType.get_IsPointer() {
            return ExternalConversionSelection.NoConversion()
        }

        // Identity is not a user-defined conversion, and asking would make every self-returning
        // operator look applicable.
        if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(sourceType, targetType) {
            return ExternalConversionSelection.NoConversion()
        }

        candidates := new List<MethodInfo>()
        AppendEndCandidates(sourceType, allowExplicit, candidates)
        AppendEndCandidates(targetType, allowExplicit, candidates)
        if candidates.Count == 0 {
            return ExternalConversionSelection.NoConversion()
        }

        applicable := new List<MethodInfo>()
        index := 0
        while index < candidates.Count {
            candidate := candidates[index]
            if IsApplicable(candidate, sourceType, targetType, allowExplicit) {
                applicable.Add(candidate)
            }

            index += 1
        }

        if applicable.Count == 0 {
            return ExternalConversionSelection.NoConversion()
        }

        mostSpecificSource: Type? = null
        if !TryMostSpecificSourceType(applicable, sourceType, allowExplicit, out mostSpecificSource) || mostSpecificSource == null {
            return ExternalConversionSelection.Tie(applicable[0], applicable[1])
        }

        mostSpecificTarget: Type? = null
        if !TryMostSpecificTargetType(applicable, targetType, allowExplicit, out mostSpecificTarget) || mostSpecificTarget == null {
            return ExternalConversionSelection.Tie(applicable[0], applicable[1])
        }

        spanning := new List<MethodInfo>()
        index = 0
        while index < applicable.Count {
            candidate := applicable[index]
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(ParameterTypeOf(candidate), mostSpecificSource) && TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(candidate.get_ReturnType(), mostSpecificTarget) {
                spanning.Add(candidate)
            }

            index += 1
        }

        if spanning.Count == 1 {
            return ExternalConversionSelection.One(spanning[0])
        }

        if spanning.Count == 0 {
            return ExternalConversionSelection.NoConversion()
        }

        return ExternalConversionSelection.Tie(spanning[0], spanning[1])
    }

    // A cheap pre-filter for the hot path: does either end declare ANY conversion operator at all.
    // Assignability asks about millions of pairs and almost none of them name a type that declares
    // one, so this answers before a candidate list is ever built.
    static func DeclaresConversionOperators(candidate: Type?): bool {
        owner := candidate
        depth := 0
        while owner != null && depth < 64 {
            methods := DeclaredPublicStaticMethodsOrNull(owner)
            if methods != null {
                index := 0
                while index < methods.Length {
                    method := methods[index]
                    name := method.get_Name()
                    if name == "op_Implicit" || name == "op_Explicit" {
                        return true
                    }

                    index += 1
                }
            }

            owner = BaseTypeOrNull(owner)
            depth += 1
        }

        return false
    }

    // The candidate set of ONE end: its own declarations and its base classes'. Conversion operators
    // are not inherited members in C#, which is why each level is read `DeclaredOnly` rather than
    // letting reflection flatten the hierarchy.
    static func AppendEndCandidates(endType: Type, allowExplicit: bool, candidates: List<MethodInfo>) {
        owner: Type? = endType
        depth := 0
        while owner != null && depth < 64 {
            AppendDeclaredConversionOperators(owner, allowExplicit, candidates)
            owner = BaseTypeOrNull(owner)
            depth += 1
        }
    }

    static func AppendDeclaredConversionOperators(owner: Type, allowExplicit: bool, candidates: List<MethodInfo>) {
        methods := DeclaredPublicStaticMethodsOrNull(owner)
        if methods == null {
            return
        }

        index := 0
        while index < methods.Length {
            method := methods[index]
            if IsConversionOperator(method, allowExplicit) && !AlreadyPresent(candidates, method) {
                candidates.Add(method)
            }

            index += 1
        }
    }

    // The metadata read, with every shape that cannot answer screened out FIRST. A type still being
    // emitted, or an external generic closed over one, has no readable member list — the former
    // because its members are `MethodBuilder`s that are not yet methods, the latter because a
    // `TypeBuilder` instantiation throws on every member query. Both contribute nothing.
    static func DeclaredPublicStaticMethodsOrNull(owner: Type?): MethodInfo[]? {
        if owner == null {
            return null
        }

        if owner.get_IsGenericParameter() || owner.get_ContainsGenericParameters() {
            return null
        }

        if TypeInfoIdentityFacts.IsBuilderBound(owner) {
            return null
        }

        try {
            return owner.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly)
        } catch {
            return null
        }
    }

    static func BaseTypeOrNull(owner: Type): Type? {
        try {
            return owner.get_BaseType()
        } catch {
            return null
        }
    }

    static func IsConversionOperator(method: MethodInfo, allowExplicit: bool): bool {
        if !method.get_IsStatic() || !method.get_IsPublic() || !method.get_IsSpecialName() {
            return false
        }

        name := method.get_Name()
        if name != "op_Implicit" {
            if !allowExplicit || name != "op_Explicit" {
                return false
            }
        }

        if method.get_IsGenericMethodDefinition() || method.get_IsGenericMethod() {
            return false
        }

        parameters := method.GetParameters()
        if parameters.Length != 1 {
            return false
        }

        parameterType := parameters[0].get_ParameterType()
        if parameterType == null || parameterType.get_IsByRef() || parameterType.get_IsPointer() {
            return false
        }

        returnType := method.get_ReturnType()
        if returnType == null || returnType.get_IsByRef() || returnType.get_IsPointer() || returnType.get_FullName() == "System.Void" {
            return false
        }

        return true
    }

    // Two reads of the same declaration are one candidate. The two ends can share a base class, and
    // a MetadataLoadContext hands back a fresh `MethodInfo` for every query, so the comparison is on
    // the signature the operator IS rather than on the handle it arrived in.
    static func AlreadyPresent(candidates: List<MethodInfo>, method: MethodInfo): bool {
        index := 0
        while index < candidates.Count {
            existing := candidates[index]
            if existing.get_Name() == method.get_Name() && SameDeclaration(existing, method) {
                return true
            }

            index += 1
        }

        return false
    }

    static func SameDeclaration(left: MethodInfo, right: MethodInfo): bool {
        leftOwner := left.get_DeclaringType()
        rightOwner := right.get_DeclaringType()
        if leftOwner == null || rightOwner == null {
            return false
        }

        if !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(leftOwner, rightOwner) {
            return false
        }

        return TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(ParameterTypeOf(left), ParameterTypeOf(right)) && TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(left.get_ReturnType(), right.get_ReturnType())
    }

    static func ParameterTypeOf(method: MethodInfo): Type {
        parameters := method.GetParameters()
        if parameters.Length != 1 {
            throw new InvalidOperationException("A conversion operator candidate has exactly one parameter.")
        }

        parameterType := parameters[0].get_ParameterType()
        if parameterType == null {
            throw new InvalidOperationException("A conversion operator parameter cannot be untyped.")
        }

        return parameterType
    }

    // §10.5.3: the source must reach the operator's parameter and the operator's result must reach
    // the target, both by a STANDARD conversion. §10.5.4 relaxes each to either direction, which is
    // what lets a cast narrow on the way in and on the way out.
    static func IsApplicable(candidate: MethodInfo, sourceType: Type, targetType: Type, allowExplicit: bool): bool {
        parameterType := ParameterTypeOf(candidate)
        returnType := candidate.get_ReturnType()

        if !StandardConversionExists(sourceType, parameterType) {
            if !allowExplicit || !StandardConversionExists(parameterType, sourceType) {
                return false
            }
        }

        if !StandardConversionExists(returnType, targetType) {
            if !allowExplicit || !StandardConversionExists(targetType, returnType) {
                return false
            }
        }

        return true
    }

    // The most specific SOURCE type. The operator whose parameter IS the source wins outright;
    // otherwise the parameter types are ranked, and a rank with no unique winner is a tie.
    static func TryMostSpecificSourceType(applicable: List<MethodInfo>, sourceType: Type, allowExplicit: bool, out mostSpecific: Type?): bool {
        mostSpecific = null
        parameterTypes := new List<Type>()
        index := 0
        while index < applicable.Count {
            parameterType := ParameterTypeOf(applicable[index])
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(parameterType, sourceType) {
                mostSpecific = sourceType
                return true
            }

            parameterTypes.Add(parameterType)
            index += 1
        }

        // The implicit form only ever widens into the parameter, so the narrowest parameter is the
        // most specific one. The explicit form may also narrow into it, and then the WIDEST of the
        // parameters the source widens out of is the most specific.
        if !allowExplicit {
            return TryMostEncompassed(parameterTypes, out mostSpecific)
        }

        widenedInto := new List<Type>()
        index = 0
        while index < parameterTypes.Count {
            if StandardConversionExists(sourceType, parameterTypes[index]) {
                widenedInto.Add(parameterTypes[index])
            }

            index += 1
        }

        if widenedInto.Count > 0 {
            return TryMostEncompassed(widenedInto, out mostSpecific)
        }

        return TryMostEncompassing(parameterTypes, out mostSpecific)
    }

    // The most specific TARGET type, the mirror of the source rule: the operator whose result IS the
    // target wins outright, and otherwise the WIDEST result the target accepts is the most specific.
    static func TryMostSpecificTargetType(applicable: List<MethodInfo>, targetType: Type, allowExplicit: bool, out mostSpecific: Type?): bool {
        mostSpecific = null
        returnTypes := new List<Type>()
        index := 0
        while index < applicable.Count {
            returnType := applicable[index].get_ReturnType()
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(returnType, targetType) {
                mostSpecific = targetType
                return true
            }

            returnTypes.Add(returnType)
            index += 1
        }

        if !allowExplicit {
            return TryMostEncompassing(returnTypes, out mostSpecific)
        }

        widenedOutOf := new List<Type>()
        index = 0
        while index < returnTypes.Count {
            if StandardConversionExists(returnTypes[index], targetType) {
                widenedOutOf.Add(returnTypes[index])
            }

            index += 1
        }

        if widenedOutOf.Count > 0 {
            return TryMostEncompassing(widenedOutOf, out mostSpecific)
        }

        return TryMostEncompassed(returnTypes, out mostSpecific)
    }

    // The one type in the set that every other one encompasses — the narrowest. Unique or nothing.
    static func TryMostEncompassed(types: List<Type>, out mostSpecific: Type?): bool {
        return TryUniqueExtreme(types, true, out mostSpecific)
    }

    // The one type in the set that encompasses every other one — the widest. Unique or nothing.
    static func TryMostEncompassing(types: List<Type>, out mostSpecific: Type?): bool {
        return TryUniqueExtreme(types, false, out mostSpecific)
    }

    static func TryUniqueExtreme(types: List<Type>, encompassed: bool, out mostSpecific: Type?): bool {
        mostSpecific = null
        if types.Count == 0 {
            return false
        }

        winner: Type? = null
        index := 0
        while index < types.Count {
            candidate := types[index]
            wins := true
            other := 0
            while other < types.Count {
                comparand := types[other]
                if !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(candidate, comparand) {
                    reaches := encompassed ? StandardConversionExists(candidate, comparand) : StandardConversionExists(comparand, candidate)
                    if !reaches {
                        wins = false
                        break
                    }
                }

                other += 1
            }

            if wins {
                if winner != null && !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(winner, candidate) {
                    return false
                }

                winner = candidate
            }

            index += 1
        }

        if winner == null {
            return false
        }

        mostSpecific = winner
        return true
    }

    // A STANDARD implicit conversion (ECMA-334 §10.4.2): identity, implicit numeric, implicit
    // nullable, implicit reference and boxing. User-defined conversions are excluded BY DEFINITION,
    // which is also why this never recurses back into the resolution above.
    static func StandardConversionExists(fromType: Type?, toType: Type?): bool {
        if fromType == null || toType == null {
            return false
        }

        if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(fromType, toType) {
            return true
        }

        fromUnderlying := NullableUnderlyingTypeOrNull(fromType)
        toUnderlying := NullableUnderlyingTypeOrNull(toType)

        if toUnderlying != null {
            // `S -> T?` and `S? -> T?` lift the identity and numeric conversions; nothing else.
            liftedSource := fromUnderlying ?? fromType
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(liftedSource, toUnderlying) {
                return true
            }

            return IsImplicitNumericConversion(liftedSource, toUnderlying)
        }

        // `T? -> T` is explicit in C#, never standard-implicit.
        if fromUnderlying != null {
            return false
        }

        if IsImplicitNumericConversion(fromType, toType) {
            return true
        }

        return AnalyzerConversionFacts.IsReflectionAssignableFrom(toType, fromType)
    }

    static func IsImplicitNumericConversion(fromType: Type, toType: Type): bool {
        fromCode := AnalyzerConversionFacts.ClrNumericCode(fromType.get_FullName())
        toCode := AnalyzerConversionFacts.ClrNumericCode(toType.get_FullName())
        return AnalyzerConversionFacts.IsNumericWidening(fromCode, toCode)
    }

    // `Nullable<T>`'s argument, read by metadata NAME rather than by `typeof` — the analyzer's types
    // come from a MetadataLoadContext where the projected `System.Nullable´1` is not the runtime's,
    // and `Nullable.GetUnderlyingType` would answer null for every one of them.
    static func NullableUnderlyingTypeOrNull(candidate: Type): Type? {
        if !candidate.get_IsGenericType() || candidate.get_IsGenericTypeDefinition() {
            return null
        }

        definition: Type? = null
        try {
            definition = candidate.GetGenericTypeDefinition()
        } catch {
            return null
        }

        if definition == null || definition.get_FullName() != NullableDefinitionFullName() {
            return null
        }

        arguments := candidate.GetGenericArguments()
        if arguments.Length != 1 {
            return null
        }

        return arguments[0]
    }
}
