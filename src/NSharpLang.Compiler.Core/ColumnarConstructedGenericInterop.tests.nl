namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// EXTERNAL GENERICS CONSTRUCTED OVER A SOURCE DECLARATION'S OWN TYPE PARAMETERS.
//
// `EqualityComparer<TOk>` inside `Outcome<TOk, TErr>` is an EXTERNAL type whose members are
// builder-bound: the head is a BCL definition the reference universe can name exactly, and the
// argument is a `GenericTypeParameterBuilder` this compilation is still emitting. Every fact below
// is about that pairing — which owner answers it, what the member handle is, and what the member's
// type is after substitution — because before this arc the two halves were told apart by a
// `claimed` flag that a type-parameter ARGUMENT sets just as readily as a source HEAD does.
func InteropSourceOwner(name: string, arity: int): TypeBuilder {
    return TypeOfCreateBuilder(name, "ColumnarConstructedGenericInterop." + name, arity)
}

func InteropTypeParameter(owner: TypeBuilder): Type {
    parameters := owner.GetGenericArguments()
    if parameters.Length == 0 {
        throw new InvalidOperationException("The interop fixture owner declares no type parameters.")
    }
    return parameters[0]
}

func InteropClosedOverSelf(owner: TypeBuilder): Type {
    ownerType: Type = owner
    return ownerType.MakeGenericType(owner.GetGenericArguments())
}

test "an external generic over the enclosing declaration's own parameter is a storable type" {
    owner := InteropSourceOwner("Interop.Outcome`2", 2)
    parameter := InteropTypeParameter(owner)

    comparer := AdmissibilityClosed1("System.Collections.Generic.EqualityComparer`1", parameter)
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(comparer)
    assert ColumnarTypeOfPlanner.IsSupportedExternalConstruction(comparer)
    assert ColumnarTypeOfPlanner.IsSupportedType(comparer)

    // The type's own constructed self as the argument of an external interface — the base-list shape.
    equatable := AdmissibilityClosed1("System.IEquatable`1", InteropClosedOverSelf(owner))
    assert ColumnarTypeOfPlanner.IsSupportedExternalConstruction(equatable)
    assert ColumnarTypeOfPlanner.IsSupportedType(equatable)

    // Nested: a construction over a construction over the parameter.
    nested := AdmissibilityClosed1(
        "System.Collections.Generic.IEnumerable`1",
        AdmissibilityClosed1("System.Collections.Generic.List`1", parameter)
    )
    assert ColumnarTypeOfPlanner.IsSupportedExternalConstruction(nested)
    assert ColumnarTypeOfPlanner.IsSupportedType(nested)
}

// The general arm is a rule about a SPELLING THAT MENTIONS a type parameter, not a licence to admit
// every builder-bound construction. A construction over complete arguments has a real lowering that
// decides its own admissibility, and this arm must not reinterpret that answer.
test "a builder-bound construction over complete arguments keeps its family boundary" {
    owner := InteropSourceOwner("Interop.Complete", 0)
    ownerType: Type = owner

    delegateOverSource := AdmissibilityClosed1("System.Func`1", ownerType)
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(delegateOverSource)
    assert !ColumnarTypeOfPlanner.IsSupportedExternalConstruction(delegateOverSource)
    assert !ColumnarTypeOfPlanner.IsSupportedType(delegateOverSource)

    // A by-ref-like head stays with its element-specific owner even over a type parameter.
    parameterOwner := InteropSourceOwner("Interop.SpanOwner`1", 1)
    parameter := InteropTypeParameter(parameterOwner)
    span := AdmissibilitySpan(parameter)
    assert !ColumnarTypeOfPlanner.IsSupportedExternalConstruction(span)
    assert !ColumnarTypeOfPlanner.IsSupportedType(span)
}

// A source declaration that spells a BCL generic's exact name cannot borrow that name's admission:
// the head must come from a real reference, not from the assembly this compilation is emitting.
test "an emitted namesake definition is not an external head" {
    parameterOwner := InteropSourceOwner("Interop.NamesakeOwner`1", 1)
    parameter := InteropTypeParameter(parameterOwner)
    namesake := IdentityBake(
        TypeOfCreateBuilder(
            "System.Collections.Generic.EqualityComparer`1",
            "ColumnarConstructedGenericInterop.Namesake",
            1
        )
    )
    arguments := new Type[](1)
    arguments[0] = parameter
    impostor := namesake.MakeGenericType(arguments)

    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(impostor)
    assert !ColumnarTypeOfPlanner.IsSupportedExternalConstruction(impostor)
}

test "a static member of a builder-bound external construction is rebound onto the instantiation" {
    owner := InteropSourceOwner("Interop.Receiver`1", 1)
    parameter := InteropTypeParameter(owner)
    comparer := AdmissibilityClosed1("System.Collections.Generic.EqualityComparer`1", parameter)

    assert ColumnarGenericTypeReceiverFacts.IsBuilderBoundConstruction(comparer)
    assert !ColumnarGenericTypeReceiverFacts.IsBuilderBoundConstruction(
        AdmissibilityClosed1("System.Collections.Generic.EqualityComparer`1", typeof(int))
    )

    getter: MethodInfo? = null
    resultType := typeof(object)
    assert ColumnarGenericTypeReceiverFacts.TryResolveStaticGetter(comparer, "Default", out getter, out resultType)
    assert getter != null
    // The REBOUND wrapper reports the open definition's return type, so the substituted member type
    // is the answer the planner has to carry alongside the handle.
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(resultType, comparer)
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(resultType, getter.get_ReturnType())

    missing: MethodInfo? = null
    missingType := typeof(object)
    assert !ColumnarGenericTypeReceiverFacts.TryResolveStaticGetter(comparer, "Nonexistent", out missing, out missingType)

    field: FieldInfo? = null
    fieldType := typeof(object)
    // `Default` is a PROPERTY: the field query answers nothing rather than guessing from the name.
    assert !ColumnarGenericTypeReceiverFacts.TryResolveStaticField(comparer, "Default", out field, out fieldType)

    // An INSTANCE member reached through the type name is not a static read.
    instanceGetter: MethodInfo? = null
    instanceType := typeof(object)
    assert !ColumnarGenericTypeReceiverFacts.TryResolveStaticGetter(comparer, "Equals", out instanceGetter, out instanceType)
}

test "a signature type that is one of the instantiation's own arguments is closed, not open" {
    owner := InteropSourceOwner("Interop.Signature`2", 2)
    parameters := owner.GetGenericArguments()
    noArguments := new Type[](0)

    assert ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedResolvedSignatureType(parameters[0], noArguments)
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedResolvedSignatureType(parameters[0], parameters)
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedResolvedSignatureType(typeof(int), parameters)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedResolvedSignatureType(typeof(int).MakeByRefType(), parameters)

    // A parameter belonging to some OTHER owner is still open here.
    otherOwner := InteropSourceOwner("Interop.OtherSignature`1", 1)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedResolvedSignatureType(
        InteropTypeParameter(otherOwner),
        parameters
    )

    // The no-argument overload keeps the historical answer exactly.
    assert ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedSignatureType(parameters[1])
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedSignatureType(typeof(string))
}

// `EqualityComparer<T>.Default` is typed `EqualityComparer<T>`, which the CLR spells as the generic
// type DEFINITION. Substitution must close it; leaving it open hands the planner a type that names
// no storage at all.
test "substitution closes a member type that is its own owner's definition" {
    definition := AdmissibilityRuntimeType("System.Collections.Generic.EqualityComparer`1")
    property := definition.GetProperty("Default", BindingFlags.Public | BindingFlags.Static)
    if property == null {
        throw new InvalidOperationException("EqualityComparer<T>.Default was not found in the compiler runtime.")
    }
    assert property.get_PropertyType().get_IsGenericTypeDefinition()

    closedArguments := new Type[](1)
    closedArguments[0] = typeof(int)
    substituted := ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(
        property.get_PropertyType(),
        closedArguments
    )
    assert !substituted.get_IsGenericTypeDefinition()
    assert substituted == AdmissibilityClosed1("System.Collections.Generic.EqualityComparer`1", typeof(int))
}

func InteropResolution(typeParameters: Dictionary<string, Type>?): ColumnarSemanticTypeResolution {
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "import System\nimport System.Collections.Generic\nfunc ConstructedGenericInteropAnchor(): int { return 0 }\n"
    fileNames[0] = "constructed-generic-interop/baseline.nl"
    return SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        typeParameters,
        ""
    )
}

func InteropResolvesWithTypeParams(
    canonical: string,
    owner: TypeBuilder,
    typeParameters: Dictionary<string, Type>,
    out resolved: Type
): bool {
    resolution := InteropResolution(typeParameters)
    // Structural selection identifies a generic parameter through its REGISTERED source owner, the
    // same registration the emitter performs for every source declaration it defines.
    ownerType: Type = owner
    exactName := ownerType.get_FullName() ?? "InteropOwner"
    parameterNames := new string[](ownerType.GetGenericArguments().Length)
    nameIndex := 0
    while nameIndex < parameterNames.Length {
        parameterNames[nameIndex] = "T" + nameIndex.ToString()
        nameIndex += 1
    }
    resolution.Structs.StructuralTypeReferences.RegisterSourceDefinition(exactName, ownerType, false)
    resolution.Structs.StructuralTypeReferences.RegisterTypeGenericParameters(0, exactName, parameterNames, ownerType)
    return ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
        canonical,
        typeParameters,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
}

// THE GENERAL CANONICALIZATION ARM. The modeled family rows above it state narrower ELEMENT policies
// for the families whose lowerings care; when a row declines — or names a head no row covers — the
// definition is resolved through ordinary scoped type resolution at the written arity and closed
// with `MakeGenericType`. `Dictionary<TKey, TValue>` and `IEnumerable<T>` are exactly the spellings
// their rows refused, and no row mentions `EqualityComparer` at all.
test "the general canonicalization arm closes any external head over the declaration's parameters" {
    owner := InteropSourceOwner("Interop.Canonical`2", 2)
    parameters := owner.GetGenericArguments()
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters["T0"] = parameters[0]
    typeParameters["T1"] = parameters[1]

    resolved := typeof(object)
    assert InteropResolvesWithTypeParams("Dictionary<T0,T1>", owner, typeParameters, out resolved)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(
        resolved,
        AdmissibilityClosed2("System.Collections.Generic.Dictionary`2", parameters[0], parameters[1])
    )

    assert InteropResolvesWithTypeParams("IEnumerable<T1>", owner, typeParameters, out resolved)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(
        resolved,
        AdmissibilityClosed1("System.Collections.Generic.IEnumerable`1", parameters[1])
    )

    assert InteropResolvesWithTypeParams("EqualityComparer<T1>", owner, typeParameters, out resolved)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(
        resolved,
        AdmissibilityClosed1("System.Collections.Generic.EqualityComparer`1", parameters[1])
    )

    assert InteropResolvesWithTypeParams("KeyValuePair<T0,T1>", owner, typeParameters, out resolved)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(
        resolved,
        AdmissibilityClosed2("System.Collections.Generic.KeyValuePair`2", parameters[0], parameters[1])
    )
}

test "array and nullable suffixes keep the declaration's parameters" {
    owner := InteropSourceOwner("Interop.Suffix`1", 1)
    parameter := InteropTypeParameter(owner)
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters["T0"] = parameter

    resolved := typeof(object)
    // A `?` on a reference-shaped construction is the construction itself, exactly as the ordinary
    // resolver reads it for a complete reference type.
    assert InteropResolvesWithTypeParams("Func<T0,bool>?", owner, typeParameters, out resolved)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(
        resolved,
        AdmissibilityClosed2("System.Func`2", parameter, typeof(bool))
    )

    assert InteropResolvesWithTypeParams("Action<T0>?", owner, typeParameters, out resolved)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(
        resolved,
        AdmissibilityClosed1("System.Action`1", parameter)
    )

    assert InteropResolvesWithTypeParams("T0[]", owner, typeParameters, out resolved)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(resolved, parameter.MakeArrayType())

    // An ARRAY of a builder-bound construction keeps the element boundary it already had: the array
    // arm asks the same `IsSupportedElementType` the ordinary resolver asks.
    assert !InteropResolvesWithTypeParams("List<T0>[]", owner, typeParameters, out resolved)
}

test "the general arm needs a real external definition at the written arity" {
    owner := InteropSourceOwner("Interop.Arity`1", 1)
    parameter := InteropTypeParameter(owner)
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters["T0"] = parameter

    resolved := typeof(object)
    // Right head, wrong arity.
    assert !InteropResolvesWithTypeParams("EqualityComparer<T0,T0>", owner, typeParameters, out resolved)
    // No such head anywhere in the reference universe.
    assert !InteropResolvesWithTypeParams("NoSuchExternalHead<T0>", owner, typeParameters, out resolved)

    // The arm applies only to a spelling that mentions a visible parameter: with an empty map the
    // resolver keeps its existing answer for the same spelling.
    emptyMap := new Dictionary<string, Type>(StringComparer.Ordinal)
    assert !InteropResolvesWithTypeParams("EqualityComparer<T0>", owner, emptyMap, out resolved)
}
