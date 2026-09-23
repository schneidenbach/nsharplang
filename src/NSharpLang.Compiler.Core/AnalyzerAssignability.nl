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
class AnalyzerImplicitConversionGuard {
    activeSources: List<TypeInfo>
    activeTargets: List<TypeInfo>

    constructor() {
        activeSources = new List<TypeInfo>()
        activeTargets = new List<TypeInfo>()
    }

    // True when the pair was NOT already active and has now been marked so. False means the caller
    // is already inside this exact question and must answer "no" rather than recurse.
    func TryEnter(source: TypeInfo, target: TypeInfo): bool {
        if IndexOfPair(source, target) >= 0 {
            return false
        }

        activeSources.Add(source)
        activeTargets.Add(target)
        return true
    }

    func Exit(source: TypeInfo, target: TypeInfo) {
        index := IndexOfPair(source, target)
        if index >= 0 {
            activeSources.RemoveAt(index)
            activeTargets.RemoveAt(index)
        }
    }

    func Clear() {
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

class AnalyzerAssignability {
    declarationContext: AnalyzerDeclarationContext
    assignabilityFacts: AnalyzerAssignabilityFacts
    structuralAssignability: AnalyzerStructuralAssignability
    typeSubstitution: AnalyzerTypeSubstitution
    clrTypeConversion: AnalyzerClrTypeConversion
    conversionGuard: AnalyzerImplicitConversionGuard
    activeExternalDefinitions: HashSet<Type>
    externalConversionOwners: Dictionary<Type, bool>

    constructor(context: AnalyzerDeclarationContext, facts: AnalyzerAssignabilityFacts, structural: AnalyzerStructuralAssignability, substitution: AnalyzerTypeSubstitution, clrConversion: AnalyzerClrTypeConversion, guard: AnalyzerImplicitConversionGuard) {
        declarationContext = context
        assignabilityFacts = facts
        structuralAssignability = structural
        typeSubstitution = substitution
        clrTypeConversion = clrConversion
        conversionGuard = guard
        activeExternalDefinitions = new HashSet<Type>()
        externalConversionOwners = new Dictionary<Type, bool>()
    }

    // 023/1e — THE TWO-ARGUMENT FORM IS THE CONSTANT-FREE ONE, AND IT STAYS THE DEFAULT.
    // `IsAssignable` has 45 call sites across 26 owners, and only about fifteen of them have the
    // initialiser expression in hand when they ask. Threading a constant through all 45 would move 30
    // call sites that have nothing to say; instead the constant-aware overload takes the fact and this
    // form delegates with `None()`, so a position that cannot supply one keeps today's answer BY
    // CONSTRUCTION rather than by care.
    func IsAssignable(target: TypeInfo, source: TypeInfo): bool {
        return IsAssignableWithConstant(target, source, ConstantOperandFacts.None())
    }

    // The two implicit CONSTANT conversions (ECMA-334 §10.2.4 and §10.2.11) are decided first, because
    // they are the only ones whose answer depends on the VALUE rather than on the two types. Everything
    // below this point is the ordinary type-to-type question and is unchanged.
    func IsAssignableWithConstant(target: TypeInfo, source: TypeInfo, constant: ConstantOperandFacts): bool {
        if constant.HasIntegerLiteral && IsConstantConvertible(target, source, constant) {
            return true
        }

        return IsAssignableCore(target, source)
    }

    // §10.2.4 — the literal ZERO converts to any enum type. An external enum is an `ExternalTypeInfo`
    // carrying only a NAME, so the enum question can only be asked of the resolved CLR type, which is
    // what `clrTypeConversion` is already here to answer.
    // §10.2.11 — an in-range integer constant converts to the narrower integral target. The source must
    // be the unsuffixed `int` a bare literal types as; a suffixed literal has its own fixed type and
    // `ConstantConversionFacts` refuses it.
    func IsConstantConvertible(target: TypeInfo, source: TypeInfo, constant: ConstantOperandFacts): bool {
        resolvedTarget := declarationContext.ResolveDeclaredAlias(target)
        clrTarget := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedTarget)
        return ConstantConversionFacts.AcceptsIntegerConstant(clrTarget, constant.LiteralText, constant.IsNegative)
    }

    // A TUPLE CONVERTS TO A TUPLE ELEMENT BY ELEMENT, THROUGH CONVERSIONS THE CLR SPELLS AS IDENTITY.
    // Element NAMES are not part of tuple identity, so a `(Min: int, Max: int)` value fits an
    // `(int, int)` slot and the other way round; a nullable ANNOTATION over a reference type is not a
    // CLR type either, so `(string, string)` fits `(string?, string)` and a `null` element fits any
    // slot that accepts null. Those two are exactly what `return (null, last, IsConstructor: true)`
    // needs against a declared `(string?, string, IsConstructor: bool)`, and without this arm the whole
    // tuple was compared by identity and reported NL202 against a literal the writer spelled correctly.
    //
    // A REPRESENTATION-CHANGING element conversion is deliberately NOT admitted. C# converts
    // `(string, string)` to `(object, object)` and `(int, int)` to `(long, long)` by taking the tuple
    // apart and building a new one; N# emits no such per-element conversion, so accepting it here would
    // hand the emitter a shape it can only decline. A `Nullable<int>` is a real CLR type and stays a
    // difference from `int` for the same reason.
    func AreTupleElementsAssignable(target: TupleTypeInfo, source: TupleTypeInfo): bool {
        if target.Elements.Count != source.Elements.Count {
            return false
        }

        index := 0
        while index < target.Elements.Count {
            if !IsTupleElementCompatible(target.Elements[index].Type, source.Elements[index].Type) {
                return false
            }

            index = index + 1
        }

        return true
    }

    func IsTupleElementCompatible(target: TypeInfo, source: TypeInfo): bool {
        resolvedTarget := declarationContext.ResolveDeclaredAlias(target)
        resolvedSource := declarationContext.ResolveDeclaredAlias(source)
        if TypeInfoIdentityFacts.AreEqual(resolvedTarget, resolvedSource) {
            return true
        }

        if BuiltInTypes.Is(resolvedSource, BuiltInTypes.Null) {
            return AnalyzerConversionFacts.AcceptsNull(resolvedTarget)
        }

        // Nested tuples compare the same way, at any depth.
        nestedTarget := resolvedTarget as TupleTypeInfo
        nestedSource := resolvedSource as TupleTypeInfo
        if nestedTarget != null && nestedSource != null {
            return AreTupleElementsAssignable(nestedTarget, nestedSource)
        }

        targetInner := ReferenceNullableInnerType(resolvedTarget)
        sourceInner := ReferenceNullableInnerType(resolvedSource)
        if targetInner == null && sourceInner == null {
            return false
        }

        if targetInner == null {
            return IsTupleElementCompatible(resolvedTarget, sourceInner)
        }

        if sourceInner == null {
            return IsTupleElementCompatible(targetInner, resolvedSource)
        }

        return IsTupleElementCompatible(targetInner, sourceInner)
    }

    // The inner type of a nullable annotation over a REFERENCE type — the one nullable spelling that is
    // not a CLR type of its own. `int?` IS `Nullable<int>` and answers null here.
    func ReferenceNullableInnerType(candidate: TypeInfo): TypeInfo? {
        nullable := candidate as NullableTypeInfo
        if nullable == null {
            return null
        }

        inner := declarationContext.ResolveDeclaredAlias(nullable.InnerType)
        if !AnalyzerConversionFacts.IsReferenceType(inner) {
            return null
        }

        return inner
    }

    // The same type with a REFERENCE nullable annotation dropped, and every other type unchanged.
    // `string?` becomes `string`; `int?` stays `int?`, because that one is `Nullable<int>` and losing
    // it would be losing a CLR type rather than an annotation.
    func WithoutReferenceNullability(candidate: TypeInfo): TypeInfo {
        inner := ReferenceNullableInnerType(declarationContext.ResolveDeclaredAlias(candidate))
        if inner == null {
            return candidate
        }

        return inner
    }

    func IsAssignableCore(target: TypeInfo, source: TypeInfo): bool {
        resolvedTarget := declarationContext.ResolveDeclaredAlias(target)
        resolvedSource := declarationContext.ResolveDeclaredAlias(source)

        if Object.ReferenceEquals(resolvedTarget, resolvedSource) {
            return true
        }

        // null is assignable to a nullable annotation and to any reference type: string, classes,
        // interfaces, arrays, delegates.
        if BuiltInTypes.Is(resolvedSource, BuiltInTypes.Null) && AnalyzerConversionFacts.AcceptsNull(resolvedTarget) {
            return true
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

            // AN `out` ARGUMENT'S INCOMING NULLABILITY IS NOT PART OF THE CONTRACT. The callee assigns
            // the variable before it returns and never reads what was there, so C# accepts a `string?`
            // variable for an `out string` parameter and gives it the parameter's declared nullability
            // on the way out. A `ref` argument is the opposite and still has to match in both
            // directions, which is why the relaxation is keyed on the `out` spelling the call site
            // recorded rather than on the by-ref shell alone. Only a REFERENCE annotation is dropped:
            // `int?` and `int` are different CLR types and passing one for the other is a real error.
            if targetByRef.IsOutArgument || sourceByRef.IsOutArgument {
                return TypeInfoIdentityFacts.AreEqual(WithoutReferenceNullability(targetByRef.InnerType), WithoutReferenceNullability(sourceByRef.InnerType))
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

        sourceTuple := resolvedSource as TupleTypeInfo
        targetTuple := resolvedTarget as TupleTypeInfo
        if sourceTuple != null && targetTuple != null {
            return AreTupleElementsAssignable(targetTuple, sourceTuple)
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
                // WHETHER THE TARGET IS A DELEGATE IS ASKED IN THE TOTAL FORM, the same one the LAMBDA
                // arm below asks: a runtime delegate answers by CLR base identity and one loaded into a
                // `MetadataLoadContext` answers by its base chain's NAMES. Asking only the runtime
                // spelling let a method group reach a delegate the COMPILER HAPPENED TO HAVE LOADED and
                // no other, so `local: NotifyCollectionChangedEventHandler = Handler` — and the same
                // name in an `on` handler slot or a delegate parameter — was refused over exactly the
                // delegates users name. One question, one answer.
                if AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(targetClrType) || AnalyzerCallableReferenceFacts.IsMetadataDelegateType(targetClrType) {
                    delegateSignature := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(targetClrType)
                    return IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(sourceFunction, delegateSignature)
                }
            }
        } else {
            sourceGroup := resolvedSource as NSharpMethodGroupInfo
            if sourceGroup != null {
                return IsMethodGroupAssignableToDelegate(sourceGroup, resolvedTarget)
            }

            if AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(resolvedSource) {
                // A REFLECTED METHOD GROUP CONVERTS TO A DELEGATE TOO. C#'s rule does not ask where the
                // group was declared: a group converts when EXACTLY ONE of its methods is applicable to
                // the delegate's signature. Before this, `local: Func<string, bool> = Directory.Exists`
                // reported NL202 and a reflected group at any target-typed position was refused.
                return IsReflectionMethodGroupAssignableToDelegate(resolvedSource, resolvedTarget)
            }
        }

        // A LAMBDA REACHES ANY DELEGATE TYPE, not only `Func` and `Action`. C# converts an anonymous
        // function to a delegate type whose `Invoke` the lambda's signature is compatible with, and
        // the delegate's NAME is no part of that rule: `ConsoleCancelEventHandler`, `Predicate<T>`,
        // `Comparison<T>`, `ThreadStart` and a user-declared `delegate` all carry their signature in
        // exactly the same place. The signature is read out of `Invoke` (which is also where the
        // lambda's own parameter types came from, in `AnalyzerLambdaAnalysis.FunctionSignature`) and
        // compared by the ordinary function-type relation. WHETHER THE TARGET IS A DELEGATE AT ALL is
        // the callable-reference family's own question, asked here in the same total form the
        // must-be-invocable rule asks it: a runtime delegate answers by CLR base identity and one
        // loaded into a `MetadataLoadContext` answers by its base chain's NAMES, so the relation does
        // not depend on which side of that boundary the reference set happens to be on. Both spellings
        // exclude the two abstract roots, because `Delegate` itself is not a conversion target.
        if sourceFunction != null && !sourceIsDeclaredFunction {
            delegateTarget := resolvedTarget as ReflectionTypeInfo
            if delegateTarget != null && AnalyzerCallableReferenceFacts.IsInvocableMemberType(delegateTarget) {
                delegateSignature := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(delegateTarget.Type)
                return IsFunctionTypeAssignable(sourceFunction, delegateSignature)
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

        if AnalyzerAssignabilityFacts.AreArrayTypesCompatible(resolvedTarget, resolvedSource) {
            return true
        }

        // ECMA-335 ARRAY COVARIANCE. `S[]` is a `T[]` when `S` has an implicit REFERENCE conversion to
        // `T`. The conversion is a no-op on the value — one `string[]` object viewed as an `object[]` —
        // which is why the CLR restricts it to reference elements and why a store through the covariant
        // view is checked at runtime with `ArrayTypeMismatchException`.
        if IsArrayCovariantAssignable(resolvedTarget, resolvedSource) {
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

        // THE THREE REFLECTED ARMS TAKE AN ACCEPTANCE AND NOTHING ELSE. The CLR's own subtyping is
        // the right answer for two types it knows about — but it is not the WHOLE answer, because a
        // referenced assembly's type may also declare a user-defined conversion, and
        // `IsAssignableFrom` knows nothing about `implicit operator XName(string)` or
        // `implicit operator DateTimeOffset(DateTime)`. Each of these arms used to RETURN the CLR's
        // verdict, which sent every such pair to a type error before the user-defined arm at the
        // bottom of this sequence could be asked. A refusal now falls through, exactly as the
        // constructed-generic bridge below already did.

        // Both sides reflected: CLR semantics decide, when they say yes.
        if sourceReflection != null && targetReflection != null {
            if AnalyzerConversionFacts.IsReflectionAssignableFrom(targetReflection.Type, sourceReflection.Type) {
                return true
            }
        }

        // Mixed: reflected target, built-in source — convert the source and compare in the CLR.
        if targetReflection != null {
            simpleSource := resolvedSource as SimpleTypeInfo
            if simpleSource != null {
                sourceClrType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedSource)
                if sourceClrType != null && targetReflection.Type.IsAssignableFrom(sourceClrType) {
                    return true
                }
            }
        }

        // Mixed: built-in target, reflected source.
        simpleTarget := resolvedTarget as SimpleTypeInfo
        if simpleTarget != null && sourceReflection != null {
            targetClrType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedTarget)
            if targetClrType != null && targetClrType.IsAssignableFrom(sourceReflection.Type) {
                return true
            }
        }

        // Mixed, the remaining shapes: ONE side is reflected and the other is a source spelling
        // with an exact CLR form — a source `IComparer<string>` target against a reflected
        // `StringComparer`, a reflected `Array` target against a source `string[]`. The CLR's own
        // subtyping answers, through the identity-aware walk so load-context duplicates still
        // match. Only an ACCEPTANCE is taken: a CLR refusal falls through, so every later arm
        // (numeric widening, span views, collection expressions, user-defined conversions) keeps
        // its say.
        if sourceReflection != null || targetReflection != null {
            bridgeTargetType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedTarget)
            bridgeSourceType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedSource)
            if bridgeTargetType != null && bridgeSourceType != null && AnalyzerConversionFacts.IsReflectionAssignableFrom(bridgeTargetType, bridgeSourceType) {
                return true
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
    func IsSubtypeOf(source: TypeInfo, target: TypeInfo): bool {
        effectiveSource := source
        substitution: Dictionary<string, TypeInfo>? = null
        externalDefinition: Type? = null
        genericSource := effectiveSource as GenericTypeInfo
        if genericSource != null {
            genericDefinition := typeSubstitution.ResolveGenericDefinition(genericSource)
            if genericDefinition != null {
                reflectionDefinition := genericDefinition as ReflectionTypeInfo
                if reflectionDefinition == null {
                    substitution = declarationContext.CreateGenericSubstitution(genericDefinition, genericSource.TypeArguments)
                    effectiveSource = genericDefinition
                } else {
                    externalDefinition = reflectionDefinition.Type
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
            if AnyInterfaceAssignable(interfaceSource.BaseInterfaces, interfaceSource, substitution, target) {
                return true
            }
        }

        // A SOURCE ENUM'S BASE CHAIN IS THE CLR'S. An enum declaration names no base type of its own,
        // so the only place the relation lives is the runtime type every emitted enum derives from:
        // `System.Enum`, and through it `System.ValueType`, `object` and the interfaces `System.Enum`
        // implements. The arms above cover a source-declared type's OWN base list, which an enum has
        // none of, so without this one `flags.HasFlag(other)` — whose parameter is `System.Enum` —
        // reported "no overload accepts 1 argument with these types" for the one argument the CLR
        // would have taken. The walk is the identity-aware one, so the reflection world the target
        // was loaded from does not have to be the compiler's own.
        enumSource := effectiveSource as EnumTypeInfo
        enumBaseTarget := target as ReflectionTypeInfo
        if enumSource != null && enumBaseTarget != null {
            return AnalyzerConversionFacts.IsReflectionAssignableFrom(enumBaseTarget.Type, typeof(Enum))
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

        // THE BUILT-IN SPELLINGS HAD NO SUBTYPE ARM AT ALL, AND THAT MADE EVERY GENERIC-INTERFACE
        // CONSTRAINT ON A PRIMITIVE A FALSE REPORT. `string` and `int` arrive as `SimpleTypeInfo`,
        // which is neither a class, a struct, a record, an interface nor a reflected type, so the
        // walk above fell straight through to `false` and `where T: IComparable<T>` — the shape
        // `website/docs/functions.md` and `types.md` both publish — answered "`string` does not
        // implement `IComparable<string>`". The arms above cover a SOURCE-DECLARED type's own
        // interface list; nothing covered a built-in whose interfaces only the CLR knows.
        //
        // ACCEPTANCE-ONLY, like the bridge in `IsAssignable`: a CLR refusal falls through to the
        // `false` below rather than being returned, so no later judgement is pre-empted.
        //
        // THE TARGET MUST BE AN INTERFACE, and that restriction is the measured defect's exact shape
        // rather than caution for its own sake. What was missing is a built-in's INTERFACE LIST,
        // which only the CLR holds; its base-class chain is a different question that the arms above
        // and `IsAssignable`'s own numeric and boxing rules already answer. Widening this to class
        // targets would make `IsSubtypeOf(int, object)` newly true — a contract in
        // `AnalyzerAssignability.tests.nl` pins it false — and would put boxing into a predicate that
        // several callers read as nominal subtyping. One defect, one arm.
        bridgeTarget := clrTypeConversion.TryConvertTypeInfoToClrType(target)
        if bridgeTarget != null && bridgeTarget.get_IsInterface() {
            bridgeSource := clrTypeConversion.TryConvertTypeInfoToClrType(effectiveSource)
            if bridgeSource != null && AnalyzerConversionFacts.IsReflectionAssignableFrom(bridgeTarget, bridgeSource) {
                return true
            }
        }

        // AN EXTERNAL GENERIC CONSTRUCTED OVER A TYPE THE CLR HAS NO HANDLE FOR — `Comparer<Item>`
        // where `Item` is a type this compilation is still emitting. Neither bridge above can ask
        // the CLR about it: the exact conversion has no closed type to offer, and the surrogate one
        // would erase every argument to `object`, which answers `Comparer<A>` IS an `IComparer<B>`.
        //
        // Its DEFINITION is a real reflected type, though, and the definition's base and interface
        // lists are spelled in the definition's own parameters — which this instantiation supplies
        // by position. Substituting them yields real N# types (`IComparer<Item>`), and the ordinary
        // assignability question is asked of those. No surrogate reaches the answer.
        if externalDefinition != null && !IsSubtypeWalkActive(externalDefinition) {
            return ExternalDefinitionSubtypeReaches(externalDefinition, genericSource, target)
        }

        return false
    }

    // The substituted base and interface lists of one constructed external generic. Re-entrancy is
    // fenced per definition because a definition's own interface list can name the definition again
    // (`Comparer<T>` implements `IComparer<T>`, whose walk would ask about `Comparer<T>` once more
    // through a user-defined conversion probe).
    func ExternalDefinitionSubtypeReaches(definition: Type, genericSource: GenericTypeInfo?, target: TypeInfo): bool {
        if genericSource == null || definition.GetGenericArguments().Length != genericSource.TypeArguments.Count {
            return false
        }

        typeOverride := AnalyzerReflectionTypeOverride.ForGenericArguments(definition, genericSource)
        activeExternalDefinitions.Add(definition)
        try {
            baseDefinition := definition.get_BaseType()
            if baseDefinition != null && !baseDefinition.get_IsGenericParameter() {
                if IsAssignable(target, NullabilityMetadataReflection.ConvertReflectedType(baseDefinition, null, typeOverride)) {
                    return true
                }
            }

            for implemented in definition.GetInterfaces() {
                if IsAssignable(target, NullabilityMetadataReflection.ConvertReflectedType(implemented, null, typeOverride)) {
                    return true
                }
            }
        } finally {
            activeExternalDefinitions.Remove(definition)
        }

        return false
    }

    func IsSubtypeWalkActive(definition: Type): bool {
        return activeExternalDefinitions.Contains(definition)
    }

    // A method group against a real CLR delegate's signature: the same score the overload resolver
    // ranks candidates with, read only for its success.
    func IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(source: FunctionTypeInfo, target: FunctionTypeInfo): bool {
        score := 0
        return TryGetRuntimeDelegateMethodGroupMatchScore(source, target, out score)
    }

    // Signature match with a SCORE, so a method group with several candidates can pick the best. An
    // unknown source parameter contributes nothing and is not a mismatch — a lambda still being
    // inferred must not be pre-judged. Note the RETURN is scored target ← source reversed
    // (`TryGetDelegateSignatureConversionScore(target.ReturnType, source.ReturnType)`), which is
    // covariance.
    func TryGetRuntimeDelegateMethodGroupMatchScore(source: FunctionTypeInfo, target: FunctionTypeInfo, out score: int): bool {
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
                if !TryGetDelegateSignatureConversionScore(sourceParameter, targetParameter, out parameterScore) {
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
    func TryGetDelegateSignatureConversionScore(target: TypeInfo, source: TypeInfo, out score: int): bool {
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

        // A POSITION THAT ADMITS NULL ADMITS WHATEVER ITS INNER TYPE ADMITS. Read in the two
        // directions this scorer is called in, that is the whole nullability rule for a delegate
        // signature: a method whose PARAMETER is `string?` accepts everything a `string` parameter
        // accepts, and a delegate whose RETURN is `string?` accepts a method returning `string`. The
        // converse stays refused, because the parameter direction is reversed by the caller.
        //
        // Without this, `names.Select(formatTypeRef)` on a `List<string>` reported NL402 "No overload
        // of 'Select' matches method group 'formatTypeRef'" for a `formatTypeRef(typeRef:
        // TypeReference?)` — a conversion the same method group makes without complaint when the
        // delegate type is written out, because the reference-conversion gate below refuses a
        // nullable shell before the relation is ever asked.
        nullableTarget := resolvedTarget as NullableTypeInfo
        if nullableTarget != null {
            innerScore := 0
            if TryGetDelegateSignatureConversionScore(nullableTarget.InnerType, resolvedSource, out innerScore) {
                score = 4
                return true
            }
        }

        if !assignabilityFacts.MayUseDelegateReferenceConversion(resolvedTarget) || !assignabilityFacts.MayUseDelegateReferenceConversion(resolvedSource) {
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

        if IsKnownGenericTypeAssignable(resolvedTarget, resolvedSource) || IsSubtypeOf(resolvedSource, resolvedTarget) {
            score = 4
            return true
        }

        return false
    }

    // A lambda's function type against a constructed GENERIC delegate. A function type that carries a
    // SOURCE identity is a method group, not a lambda, and is scored as one instead.
    //
    // `Func` and `Action` state their shape in their TYPE ARGUMENTS, which is why they are read
    // positionally and without reflection: those two instantiations routinely close over a type this
    // compilation is still writing, and such an instantiation cannot be reflected at all. EVERY OTHER
    // GENERIC DELEGATE — `Predicate<T>`, `Comparison<T>`, `EventHandler<T>`, `Converter<T, R>`, a
    // referenced assembly's own — states its shape in its `Invoke`, which is read through the
    // definition. Reading the shape from where the delegate actually carries it is the whole rule;
    // the delegate's NAME is no part of it.
    func IsLambdaAssignableToDelegate(functionType: FunctionTypeInfo, delegateType: GenericTypeInfo): bool {
        if AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(functionType) {
            delegateSignature := AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(delegateType)
            if delegateSignature == null {
                delegateSignature = GenericDelegateInvokeSignature(delegateType)
            }

            if delegateSignature != null {
                return IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(functionType, delegateSignature)
            }

            return false
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

        if delegateType.Name != "Action" {
            invokeSignature := GenericDelegateInvokeSignature(delegateType)
            if invokeSignature == null {
                return false
            }

            return IsLambdaAssignableToSignature(functionType, invokeSignature)
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

    // A METHOD GROUP — several declarations sharing one name — against a delegate type. C#'s rule is
    // that the group converts when EXACTLY ONE of its methods is applicable to that delegate's
    // signature: `func Widen(value: int)` and `func Widen(value: string)` both named `Widen` give a
    // `Func<int, string>` one candidate and a `Func<string, string>` the other. Two applicable
    // candidates is an ambiguity to report rather than a choice to make here, and none is simply not
    // a conversion.
    //
    // A LONE declaration never reaches this: it is a `FunctionTypeInfo` and the arm above scores it
    // directly. The two REFLECTION group shapes do not reach it either — their candidates are
    // `MethodInfo`s, which the call binder selects among with the argument facts it holds.
    func IsMethodGroupAssignableToDelegate(group: NSharpMethodGroupInfo, target: TypeInfo): bool {
        if !assignabilityFacts.CanBindCallableReferenceToExpectedType(target) {
            return false
        }

        delegateSignature := DelegateSignatureOfExpectedType(target)
        if delegateSignature == null {
            return false
        }

        candidates := NSharpMethodGroupInfoFactory.GetFunctions(group)
        applicable := 0
        for candidate in candidates {
            if IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(candidate, delegateSignature) {
                applicable = applicable + 1
            }
        }

        return applicable == 1
    }

    // THE REFLECTED HALVES OF THE SAME RULE. The two reflection shapes carry `MethodInfo`s rather
    // than source signatures, so each candidate is read into a signature first
    // (`AnalyzerFunctionTypeFactory.CreateFromReflectionMethodGroup`, which declines a generic
    // definition and a by-ref position) and then scored by the SAME relation a source candidate is
    // scored by. Exactly one applicable candidate converts; two is an ambiguity to report rather
    // than a choice to make here, and none is simply not a conversion.
    func IsReflectionMethodGroupAssignableToDelegate(source: TypeInfo, target: TypeInfo): bool {
        if !assignabilityFacts.CanBindCallableReferenceToExpectedType(target) {
            return false
        }

        delegateSignature := DelegateSignatureOfExpectedType(target)
        if delegateSignature == null {
            return false
        }

        reflectionMethod := source as ReflectionMethodInfo
        if reflectionMethod != null {
            single := AnalyzerFunctionTypeFactory.CreateFromReflectionMethodGroup(reflectionMethod.Method)
            return single != null && IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(single, delegateSignature)
        }

        reflectionGroup := source as ReflectionMethodGroupInfo
        if reflectionGroup == null {
            return false
        }

        applicable := 0
        methods := reflectionGroup.Methods
        for method in methods {
            candidate := AnalyzerFunctionTypeFactory.CreateFromReflectionMethodGroup(method)
            if candidate != null && IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(candidate, delegateSignature) {
                applicable = applicable + 1
            }
        }

        return applicable == 1
    }

    // The signature a delegate-shaped expected type declares, whichever way it is spelled. The
    // maybe-null and oblivious shells are transparent, for the same reason they are transparent to
    // the callable-reference gate: a `Func<int, int>?` field still names that delegate.
    func DelegateSignatureOfExpectedType(expectedType: TypeInfo): FunctionTypeInfo? {
        resolved := declarationContext.ResolveDeclaredAlias(expectedType)

        nullableExpected := resolved as NullableTypeInfo
        if nullableExpected != null {
            return DelegateSignatureOfExpectedType(nullableExpected.InnerType)
        }

        obliviousExpected := resolved as ObliviousTypeInfo
        if obliviousExpected != null {
            return DelegateSignatureOfExpectedType(obliviousExpected.InnerType)
        }

        functionExpected := resolved as FunctionTypeInfo
        if functionExpected != null {
            return functionExpected
        }

        reflectionExpected := resolved as ReflectionTypeInfo
        if reflectionExpected != null {
            if !AnalyzerCallableReferenceFacts.IsInvocableMemberType(reflectionExpected) {
                return null
            }

            return AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(reflectionExpected.Type)
        }

        genericExpected := resolved as GenericTypeInfo
        if genericExpected != null {
            namedSignature := AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(genericExpected)
            if namedSignature != null {
                return namedSignature
            }

            return GenericDelegateInvokeSignature(genericExpected)
        }

        return null
    }

    // The `Invoke` a constructed generic delegate declares, in the instantiation's own vocabulary.
    // The CLOSED type answers when the reference set can spell it; otherwise the DEFINITION does,
    // with this instantiation's arguments substituted into the positions it spells as bare type
    // parameters — which is how a delegate closed over a type this compilation is writing answers.
    func GenericDelegateInvokeSignature(delegateType: GenericTypeInfo): FunctionTypeInfo? {
        closedClrType := clrTypeConversion.TryConvertTypeInfoToClrType(delegateType)
        if closedClrType != null && (AnalyzerCallableReferenceFacts.IsMetadataDelegateType(closedClrType) || AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(closedClrType)) {
            return AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(closedClrType)
        }

        definitionReflection := delegateType.GenericDefinition as ReflectionTypeInfo
        if definitionReflection == null {
            return null
        }

        return AnalyzerFunctionTypeFactory.CreateFromDelegateDefinition(definitionReflection.Type, delegateType.TypeArguments)
    }

    // A LAMBDA against a delegate signature that is already reified. The direction of each check is
    // the conversion's own: a lambda parameter is the TARGET of the delegate's argument
    // (contravariance) and the lambda's result is the SOURCE of the delegate's return (covariance).
    // A position the lambda has not inferred yet contributes nothing rather than failing.
    func IsLambdaAssignableToSignature(functionType: FunctionTypeInfo, delegateSignature: FunctionTypeInfo): bool {
        lambdaParameters := ParameterTypesOrEmpty(functionType)
        delegateParameters := ParameterTypesOrEmpty(delegateSignature)
        if lambdaParameters.Count != delegateParameters.Count {
            return false
        }

        index := 0
        while index < delegateParameters.Count {
            lambdaParameter := lambdaParameters[index]
            if !BuiltInTypes.IsUnknown(lambdaParameter) {
                if !IsAssignable(lambdaParameter, delegateParameters[index]) {
                    return false
                }
            }

            index = index + 1
        }

        lambdaReturn := functionType.ReturnType
        delegateReturn := delegateSignature.ReturnType
        if lambdaReturn == null || delegateReturn == null || BuiltInTypes.IsUnknown(lambdaReturn) {
            return true
        }

        if BuiltInTypes.Is(delegateReturn, BuiltInTypes.Void) {
            return true
        }

        return IsAssignable(delegateReturn, lambdaReturn)
    }

    // A user-defined implicit conversion operator whose parameter accepts the source and whose result
    // the target accepts, declared BY EITHER END of the conversion. Both ends are asked because a
    // conversion is written wherever it reads best: `implicit operator Fahrenheit(c: Celsius)` lives
    // on the value being converted FROM, while a wrapper's `implicit operator Wrap<T>(value: T)` can
    // only live on the type being converted TO — the `T` end may be `int`, which declares nothing.
    // Guarded against re-entry: a pair already being asked answers false rather than recursing.
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
        if DeclaresImplicitConversion(source, source, target) || DeclaresImplicitConversion(target, source, target) {
            return true
        }

        return ClassifyExternalConversion(source, target, false).IsSelected
    }

    // The EXTERNAL half of the user-defined conversion question. A referenced assembly's type — the
    // runtime's `Union<T0, T1>`, a `DateTime`, a vendor wrapper — declares its operators in metadata
    // rather than in a source declaration, so the arm above, which reads `DeclaredMembers`, can never
    // see them. The answer comes from `ExternalUserDefinedConversions`, which is the SAME owner the
    // emitter asks for the handle to call: an analyzer that accepted a conversion the emitter then
    // could not find would turn a type error into a backend decline.
    //
    // Both ends convert through the EXACT CLR conversion, never the surrogate one, so an N#-declared
    // type never reaches the metadata question as `object`.
    func ClassifyExternalConversion(source: TypeInfo, target: TypeInfo, allowExplicit: bool): ExternalConversionSelection {
        sourceClrType := clrTypeConversion.TryConvertTypeInfoToClrType(source)
        if sourceClrType == null {
            return ExternalConversionSelection.NoConversion()
        }

        targetClrType := clrTypeConversion.TryConvertTypeInfoToClrType(target)
        if targetClrType == null {
            return ExternalConversionSelection.NoConversion()
        }

        if !DeclaresExternalConversionOperators(sourceClrType) && !DeclaresExternalConversionOperators(targetClrType) {
            return ExternalConversionSelection.NoConversion()
        }

        return ExternalUserDefinedConversions.Resolve(sourceClrType, targetClrType, allowExplicit)
    }

    // The classification a DIAGNOSTIC asks for, in the caller's own argument order. Assignability
    // itself answers false for an ambiguous conversion — a tie is not a conversion — and a reporting
    // site consults this to say WHY rather than repeating the ordinary "these types differ".
    func ClassifyUserDefinedConversion(target: TypeInfo, source: TypeInfo): ExternalConversionSelection {
        return ClassifyExternalConversion(source, target, false)
    }

    // Does either end declare any conversion operator at all — memoised, because assignability asks
    // this of every pair it cannot otherwise relate and almost none of them name such a type. The
    // memo is per-owner and this owner is rebuilt whenever the well-known-type bag is, so it never
    // outlives the reflection context whose types key it.
    func DeclaresExternalConversionOperators(candidate: Type): bool {
        declares := false
        if externalConversionOwners.TryGetValue(candidate, out declares) {
            return declares
        }

        declares = ExternalUserDefinedConversions.DeclaresConversionOperators(candidate)
        externalConversionOwners[candidate] = declares
        return declares
    }

    // One end's declarations, asked about the whole conversion. The operator's own signature is read
    // through the OWNER's substitution, so `implicit operator Wrap<T>(value: T)` reached as
    // `Wrap<int>` is asked as `int -> Wrap<int>`.
    func DeclaresImplicitConversion(owner: TypeInfo, source: TypeInfo, target: TypeInfo): bool {
        substitution: Dictionary<string, TypeInfo>? = null
        declarationOwner := typeSubstitution.GetSourceDeclarationOwner(owner, out substitution)
        if declarationOwner == null {
            return false
        }

        ownerMembers := DeclaredMembersOf(declarationOwner)
        if ownerMembers == null {
            return false
        }

        for member in ownerMembers {
            if IsImplicitConversionOperator(member) {
                parameterTypes := member.ParameterTypes
                parameterType := typeSubstitution.ResolveTypeForSourceOwner(parameterTypes[0], declarationOwner, substitution)
                if IsAssignable(parameterType, source) {
                    memberReturnType := member.ReturnType
                    if memberReturnType != null {
                        returnType := typeSubstitution.ResolveTypeForSourceOwner(memberReturnType, declarationOwner, substitution)
                        if IsAssignable(target, returnType) {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    // The known-generic relation, with its covariant argument pairs answered here. This is slice 6's
    // pending-pair protocol ABSORBED: the classification stays in `AnalyzerAssignabilityFacts` and
    // the recursion it could not express is now simply a call.
    // ARRAY COVARIANCE, AS ONE RELATION FOR EVERY POSITION. A `yield`, a `return`, an argument, an
    // assignment and an array literal's element all ask this same question, and they ask it here so
    // they cannot drift apart.
    func IsArrayCovariantAssignable(target: TypeInfo, source: TypeInfo): bool {
        targetElement: TypeInfo = BuiltInTypes.Unknown
        sourceElement: TypeInfo = BuiltInTypes.Unknown
        if !AnalyzerAssignabilityFacts.TryGetArrayConversionElements(target, source, out targetElement, out sourceElement) {
            return false
        }

        return IsImplicitReferenceConversion(targetElement, sourceElement)
    }

    // THE IMPLICIT REFERENCE CONVERSION, AND IT IS DELIBERATELY NARROWER THAN `IsAssignable`.
    //
    // Array covariance is the one relation in the language that is stated over reference conversions
    // rather than over assignability, and the difference is not academic: `IsAssignable` also admits
    // boxing, numeric widening, span views, collection-expression targets and USER-DEFINED implicit
    // operators, and none of those may be carried across an array. A `Celsius[]` is not a
    // `Fahrenheit[]` however many `implicit operator`s connect the two, because the CLR conversion is
    // a no-op on the array object and every element would have to be rewritten. So this predicate
    // names the reference relations and nothing else.
    //
    // BOTH HALVES MUST BE REFERENCE TYPES. `int[]` is not an `object[]` — the elements are four bytes
    // of storage, not a pointer — and that refusal is what the value-element hint explains.
    //
    // The oblivious shell is transparent on both sides: an imported `string![]!` and a source
    // `string[]` are the same array.
    func IsImplicitReferenceConversion(target: TypeInfo, source: TypeInfo): bool {
        resolvedTarget := AnalyzerAssignabilityFacts.UnwrapOblivious(declarationContext.ResolveDeclaredAlias(target))
        resolvedSource := AnalyzerAssignabilityFacts.UnwrapOblivious(declarationContext.ResolveDeclaredAlias(source))

        if BuiltInTypes.IsUnknown(resolvedTarget) || BuiltInTypes.IsUnknown(resolvedSource) {
            return false
        }

        // NULLABILITY IS ARRAY-COVARIANT FOR READS, AND IN ONE DIRECTION ONLY. A reference nullable
        // annotation is not a CLR type — `string?` and `string` are one runtime type — so viewing a
        // `T[]` as a `T?[]` is a no-op on the array object and every element read out of the widened
        // view is honestly typed `T?`. This is the relation `object[]` needs to reach `MethodInfo.Invoke`'s
        // `object?[]?`, and C# admits it (with a warning about the write).
        //
        // THE REVERSE IS NOT ADMITTED. A `T?[]` may already hold a null, so reading it back as `T[]`
        // would promise something the array does not have — which is why only the TARGET's annotation
        // is peeled, and a nullable SOURCE stops here exactly as it did before.
        targetNullableAnnotation := resolvedTarget as NullableTypeInfo
        sourceNullableAnnotation := resolvedSource as NullableTypeInfo
        if targetNullableAnnotation != null && sourceNullableAnnotation == null {
            return IsImplicitReferenceConversion(targetNullableAnnotation.InnerType, resolvedSource)
        }

        if !AnalyzerConversionFacts.IsReferenceType(resolvedTarget) || !AnalyzerConversionFacts.IsReferenceType(resolvedSource) {
            return false
        }

        if Object.ReferenceEquals(resolvedTarget, resolvedSource) || TypeInfoIdentityFacts.AreEqual(resolvedTarget, resolvedSource) {
            return true
        }

        // Every reference type converts to `object` without touching the value.
        if BuiltInTypes.Is(resolvedTarget, BuiltInTypes.Object) {
            return true
        }

        // Covariance composes: `string[][]` is an `object[][]`.
        if IsArrayCovariantAssignable(resolvedTarget, resolvedSource) {
            return true
        }

        // The CLR's own subtyping, through the identity-aware walk so load-context duplicates match.
        // ACCEPTANCE-ONLY, exactly as the bridges in `IsAssignableCore`: a refusal falls through to
        // the source-declared arms below rather than ending the question.
        bridgeTargetType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedTarget)
        bridgeSourceType := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedSource)
        if bridgeTargetType != null && bridgeSourceType != null && AnalyzerConversionFacts.IsReflectionAssignableFrom(bridgeTargetType, bridgeSourceType) {
            return true
        }

        // The N#-declared base chains and interface lists.
        if IsSubtypeOf(resolvedSource, resolvedTarget) {
            return true
        }

        // The variant generic interfaces — `IEnumerable<string>` to `IEnumerable<object>` — which the
        // CLR carries by reference conversion too. The variant ARGUMENTS are resolved by this
        // relation rather than by `IsAssignable`, for the same reason the relation exists: CLR
        // variance is itself defined over reference conversions, so an `implicit operator` between
        // two argument types does not make `IEnumerable<A>` an `IEnumerable<B>`.
        return ResolvePendingReferencePairs(assignabilityFacts.ClassifyKnownGenericAssignability(resolvedTarget, resolvedSource))
    }

    // `ResolvePendingPairs` for the reference relation: each pending pair is answered by
    // `IsImplicitReferenceConversion` instead of by `IsAssignable`.
    func ResolvePendingReferencePairs(decision: AnalyzerAssignabilityDecision): bool {
        if decision.Decided {
            return decision.Result
        }

        pendingTargets := decision.PendingTargets
        pendingSources := decision.PendingSources
        index := 0
        while index < pendingTargets.Count {
            if !IsImplicitReferenceConversion(pendingTargets[index], pendingSources[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

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

    func EveryArmAcceptedBySomeArm(targetUnion: AnonymousUnionTypeInfo, sourceUnion: AnonymousUnionTypeInfo): bool {
        sourceArms := sourceUnion.Arms
        for sourceArm in sourceArms {
            if !SomeArmAccepts(targetUnion, sourceArm) {
                return false
            }
        }

        return true
    }

    func SomeArmAccepts(targetUnion: AnonymousUnionTypeInfo, source: TypeInfo): bool {
        targetArms := targetUnion.Arms
        for targetArm in targetArms {
            if IsAssignable(targetArm, source) {
                return true
            }
        }

        return false
    }

    func EveryArmAssignableTo(target: TypeInfo, sourceUnion: AnonymousUnionTypeInfo): bool {
        sourceArms := sourceUnion.Arms
        for sourceArm in sourceArms {
            if !IsAssignable(target, sourceArm) {
                return false
            }
        }

        return true
    }

    func AnyInterfaceAssignable(interfaces: TypeReference[], owner: TypeInfo, substitution: Dictionary<string, TypeInfo>?, target: TypeInfo): bool {
        for interfaceItem in interfaces {
            interfaceType := typeSubstitution.ResolveTypeForSourceOwner(interfaceItem, owner, substitution)
            if IsAssignable(target, interfaceType) {
                return true
            }
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
