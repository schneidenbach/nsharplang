namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

// These controls pin the existing base-walk predicate itself.  The new base-binding work must derive
// from this one successful selection rather than change what an ordinary `override` can target.
func OverrideResolverNoParameters(): Type[] {
    return new Type[](0)
}

func OverrideResolverParameterPair(first: Type, second: Type): Type[] {
    values := new Type[](2)
    values[0] = first
    values[1] = second
    return values
}

func OverrideResolverRequiredMethod(owner: Type, name: string, parameters: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameters)
    if method == null {
        throw new InvalidOperationException("The override-resolver fixture did not find '" + name + "'.")
    }
    return method
}

func OverrideResolverAssertMissing(
    baseType: Type?,
    name: string,
    returnType: Type,
    parameterTypes: Type[]
) {
    target: MethodInfo? = OverrideResolverRequiredMethod(typeof(Exception), "ToString", OverrideResolverNoParameters())
    if ColumnarOverrideTargetResolver.TryFindOverrideTarget(
        baseType,
        name,
        returnType,
        parameterTypes,
        out target
    ) {
        throw new InvalidOperationException("Expected no override target for '" + name + "'.")
    }
    if target != null {
        throw new InvalidOperationException("A failed override lookup retained its out target for '" + name + "'.")
    }
}

func OverrideResolverEmitIntBody(method: MethodBuilder) {
    il := TypeOfMethodBuilderIL(method)
    il.Emit(OpCodes.Ldc_I4_0)
    il.Emit(OpCodes.Ret)
}

func OverrideResolverEmitNullBody(method: MethodBuilder) {
    il := TypeOfMethodBuilderIL(method)
    il.Emit(OpCodes.Ldnull)
    il.Emit(OpCodes.Ret)
}

func OverrideResolverDefineGenericParameter(method: MethodBuilder): Type {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string[])
    defineParameters := ExecutorRequiredMethod(
        typeof(MethodBuilder),
        "DefineGenericParameters",
        parameterTypes
    )
    names := new string[](1)
    names[0] = "T"
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, names)
    defined := TypeOfRequiredInvocation(defineParameters, method, arguments)
    if defined == null {
        throw new InvalidOperationException("DefineGenericParameters returned null.")
    }
    parameters := method.GetGenericArguments()
    if parameters.Length != 1 || !parameters[0].get_IsGenericParameter() {
        throw new InvalidOperationException("The generic override-resolver fixture did not define one parameter.")
    }
    return parameters[0]
}

func OverrideResolverBakedCandidateOwner(): Type {
    builder := TypeOfCreateBuilder(
        "OverrideResolverCandidates",
        "ColumnarOverrideTargetResolverTests.Candidates",
        0
    )
    noParameters := OverrideResolverNoParameters()
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    oneString := new Type[](1)
    oneString[0] = typeof(string)

    publicCandidate := builder.DefineMethod("PublicCandidate", (MethodAttributes)454, typeof(int), noParameters)
    OverrideResolverEmitIntBody(publicCandidate)

    privateCandidate := builder.DefineMethod("PrivateCandidate", (MethodAttributes)193, typeof(int), noParameters)
    OverrideResolverEmitIntBody(privateCandidate)

    protectedCandidate := builder.DefineMethod("ProtectedCandidate", (MethodAttributes)196, typeof(int), noParameters)
    OverrideResolverEmitIntBody(protectedCandidate)

    staticCandidate := builder.DefineMethod("StaticCandidate", (MethodAttributes)22, typeof(int), noParameters)
    OverrideResolverEmitIntBody(staticCandidate)

    finalCandidate := builder.DefineMethod("FinalCandidate", (MethodAttributes)486, typeof(int), noParameters)
    OverrideResolverEmitIntBody(finalCandidate)

    genericCandidate := builder.DefineMethod("GenericCandidate", (MethodAttributes)454, typeof(int), noParameters)
    genericParameter := OverrideResolverDefineGenericParameter(genericCandidate)
    if !genericCandidate.get_IsGenericMethod() || !genericParameter.get_IsGenericParameter() {
        throw new InvalidOperationException("The generic override-resolver fixture did not retain generic method facts.")
    }
    OverrideResolverEmitIntBody(genericCandidate)

    plainCandidate := builder.DefineMethod("PlainCandidate", (MethodAttributes)6, typeof(int), noParameters)
    OverrideResolverEmitIntBody(plainCandidate)

    firstRoute := builder.DefineMethod("Route", (MethodAttributes)454, typeof(int), oneInt)
    OverrideResolverEmitIntBody(firstRoute)
    secondRoute := builder.DefineMethod("Route", (MethodAttributes)454, typeof(int), oneString)
    OverrideResolverEmitIntBody(secondRoute)

    pairRoute := builder.DefineMethod(
        "PairRoute",
        (MethodAttributes)454,
        typeof(int),
        OverrideResolverParameterPair(typeof(int), typeof(string))
    )
    OverrideResolverEmitIntBody(pairRoute)
    return IdentityBake(builder)
}

func OverrideResolverBakedEmptyType(name: string, assemblyIdentity: string): Type {
    return IdentityBake(TypeOfCreateBuilder(name, assemblyIdentity, 0))
}

func OverrideResolverBakedReferenceSignatureOwner(returnType: Type, parameterType: Type): Type {
    builder := TypeOfCreateBuilder(
        "OverrideResolverReferenceSignatureOwner",
        "ColumnarOverrideTargetResolverTests.ReferenceSignatureOwner",
        0
    )
    parameters := new Type[](1)
    parameters[0] = parameterType
    method := builder.DefineMethod("Twin", (MethodAttributes)454, returnType, parameters)
    OverrideResolverEmitNullBody(method)
    return IdentityBake(builder)
}

func OverrideResolverDeclaredMethodReadThrows(owner: Type): bool {
    try {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly
        methods := owner.GetMethods(flags)
        return methods.Length < 0
    } catch {
        return true
    }
}

func OverrideResolverPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func OverrideResolverReflectiveFailure(
    baseType: Type?,
    name: string?,
    returnType: Type?,
    parameterTypes: Type[]?
): bool {
    lookup := typeof(ColumnarOverrideTargetResolver).GetMethod("TryFindOverrideTarget")
    if lookup == null {
        throw new InvalidOperationException("TryFindOverrideTarget was not reflected.")
    }
    arguments := new object?[](5)
    OverrideResolverPut(arguments, 0, baseType)
    OverrideResolverPut(arguments, 1, name)
    OverrideResolverPut(arguments, 2, returnType)
    OverrideResolverPut(arguments, 3, parameterTypes)
    OverrideResolverPut(
        arguments,
        4,
        OverrideResolverRequiredMethod(typeof(Exception), "ToString", OverrideResolverNoParameters())
    )
    receiver: object? = null
    result := lookup.Invoke(receiver, arguments)
    if result == null || Convert.ToBoolean(result) {
        return false
    }
    return arguments[4] == null
}

test "override targets reset the out value and use Object only for a null base" {
    noParameters := OverrideResolverNoParameters()
    target: MethodInfo? = OverrideResolverRequiredMethod(typeof(Exception), "ToString", noParameters)

    assert ColumnarOverrideTargetResolver.TryFindOverrideTarget(
        null,
        "ToString",
        typeof(string),
        noParameters,
        out target
    )
    assert target != null
    assert target.get_DeclaringType() == typeof(object)

    OverrideResolverAssertMissing(typeof(Exception), "", typeof(string), noParameters)
    OverrideResolverAssertMissing(typeof(Exception), "NoSuchOverride", typeof(string), noParameters)
}

test "override targets reject reflected null inputs before base selection and clear the out slot" {
    noParameters := OverrideResolverNoParameters()
    assert OverrideResolverReflectiveFailure(typeof(Exception), null, typeof(string), noParameters)
    assert OverrideResolverReflectiveFailure(typeof(Exception), "ToString", null, noParameters)
    assert OverrideResolverReflectiveFailure(typeof(Exception), "ToString", typeof(string), null)
}

test "override targets take the current declared level before retaining the actual ancestor" {
    noParameters := OverrideResolverNoParameters()
    current: MethodInfo? = null
    assert ColumnarOverrideTargetResolver.TryFindOverrideTarget(
        typeof(Exception),
        "ToString",
        typeof(string),
        noParameters,
        out current
    )
    assert current != null
    assert current.get_DeclaringType() == typeof(Exception)

    ancestor: MethodInfo? = null
    assert ColumnarOverrideTargetResolver.TryFindOverrideTarget(
        typeof(ArgumentException),
        "ToString",
        typeof(string),
        noParameters,
        out ancestor
    )
    assert ancestor != null
    assert ancestor.get_DeclaringType() == typeof(Exception)
}

test "override targets admit only public nonfinal nongeneric virtual instance candidates" {
    owner := OverrideResolverBakedCandidateOwner()
    noParameters := OverrideResolverNoParameters()

    publicTarget: MethodInfo? = null
    if !ColumnarOverrideTargetResolver.TryFindOverrideTarget(
        owner,
        "PublicCandidate",
        typeof(int),
        noParameters,
        out publicTarget
    ) {
        throw new InvalidOperationException("The public virtual candidate was not selected.")
    }
    if publicTarget == null || publicTarget.get_DeclaringType() != owner {
        throw new InvalidOperationException("The public virtual candidate did not retain its declared owner.")
    }

    OverrideResolverAssertMissing(owner, "PrivateCandidate", typeof(int), noParameters)
    OverrideResolverAssertMissing(owner, "ProtectedCandidate", typeof(int), noParameters)
    OverrideResolverAssertMissing(owner, "StaticCandidate", typeof(int), noParameters)
    OverrideResolverAssertMissing(owner, "FinalCandidate", typeof(int), noParameters)
    OverrideResolverAssertMissing(owner, "GenericCandidate", typeof(int), noParameters)
    OverrideResolverAssertMissing(owner, "PlainCandidate", typeof(int), noParameters)
}

test "override target signatures reject wrong arity return and parameter positions" {
    owner := OverrideResolverBakedCandidateOwner()
    noParameters := OverrideResolverNoParameters()
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    oneString := new Type[](1)
    oneString[0] = typeof(string)

    OverrideResolverAssertMissing(owner, "Route", typeof(int), noParameters)
    OverrideResolverAssertMissing(owner, "Route", typeof(string), oneString)

    route: MethodInfo? = null
    if !ColumnarOverrideTargetResolver.TryFindOverrideTarget(owner, "Route", typeof(int), oneString, out route) {
        throw new InvalidOperationException("The matching Route overload was not selected.")
    }
    if route == null {
        throw new InvalidOperationException("The matching Route overload returned a null target.")
    }
    routeParameters := route.GetParameters()
    if routeParameters.Length != 1 || routeParameters[0].get_ParameterType() != typeof(string) {
        throw new InvalidOperationException("The matching Route overload did not retain its string parameter.")
    }

    OverrideResolverAssertMissing(
        owner,
        "PairRoute",
        typeof(int),
        OverrideResolverParameterPair(typeof(string), typeof(string))
    )
    OverrideResolverAssertMissing(
        owner,
        "PairRoute",
        typeof(int),
        OverrideResolverParameterPair(typeof(int), typeof(int))
    )
    pair: MethodInfo? = null
    pairParameters := OverrideResolverParameterPair(typeof(int), typeof(string))
    if !ColumnarOverrideTargetResolver.TryFindOverrideTarget(owner, "PairRoute", typeof(int), pairParameters, out pair) {
        throw new InvalidOperationException("The ordered PairRoute signature was not selected.")
    }
    if pair == null {
        throw new InvalidOperationException("The matching PairRoute signature returned a null target.")
    }
    selectedPairParameters := pair.GetParameters()
    if selectedPairParameters.Length != 2 || selectedPairParameters[0].get_ParameterType() != typeof(int) || selectedPairParameters[1].get_ParameterType() != typeof(string) {
        throw new InvalidOperationException("The matching PairRoute signature did not retain its ordered parameters.")
    }
}

test "override target identity admits same-image MLC signatures and rejects another assembly identity" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        metadataCore := context.LoadFromAssemblyName("System.Private.CoreLib")
        metadataBoolean := metadataCore.GetType("System.Boolean")
        metadataObject := metadataCore.GetType("System.Object")
        if metadataBoolean == null || metadataObject == null {
            throw new InvalidOperationException("The metadata core fixture did not define Object and Boolean.")
        }
        if metadataBoolean == typeof(bool) || metadataObject == typeof(object) {
            throw new InvalidOperationException("The metadata core fixture did not create non-runtime Type instances.")
        }
        if metadataBoolean.get_AssemblyQualifiedName() != typeof(bool).get_AssemblyQualifiedName() || metadataObject.get_AssemblyQualifiedName() != typeof(object).get_AssemblyQualifiedName() {
            throw new InvalidOperationException("The metadata core fixture did not retain same-image assembly-qualified names.")
        }

        metadataParameters := new Type[](1)
        metadataParameters[0] = metadataObject
        target: MethodInfo? = null
        if !ColumnarOverrideTargetResolver.TryFindOverrideTarget(
            typeof(Exception),
            "Equals",
            metadataBoolean,
            metadataParameters,
            out target
        ) {
            throw new InvalidOperationException("The same-image metadata signature did not select Object.Equals.")
        }
        if target == null || target.get_DeclaringType() != typeof(object) {
            throw new InvalidOperationException("The same-image lookup did not retain Object as the actual winning owner.")
        }
        if target.get_ReturnType() != typeof(bool) || target.get_ReturnType() == metadataBoolean {
            throw new InvalidOperationException("The same-image lookup did not retain the actual runtime return companion.")
        }
        selectedParameters := target.GetParameters()
        if selectedParameters.Length != 1 || selectedParameters[0].get_ParameterType() != typeof(object) || selectedParameters[0].get_ParameterType() == metadataObject {
            throw new InvalidOperationException("The same-image lookup did not retain the actual runtime parameter companion.")
        }

        firstTwin := OverrideResolverBakedEmptyType(
            "ColumnarOverrideTargetResolverTests.ExternalTwin",
            "ColumnarOverrideTargetResolverTests.FirstTwinAssembly"
        )
        secondTwin := OverrideResolverBakedEmptyType(
            "ColumnarOverrideTargetResolverTests.ExternalTwin",
            "ColumnarOverrideTargetResolverTests.SecondTwinAssembly"
        )
        assert firstTwin != secondTwin
        assert firstTwin.get_FullName() == secondTwin.get_FullName()
        assert firstTwin.get_AssemblyQualifiedName() != secondTwin.get_AssemblyQualifiedName()
        assert !ColumnarOverrideTargetResolver.SameTypeIdentity(firstTwin, secondTwin)
        signatureOwner := OverrideResolverBakedReferenceSignatureOwner(firstTwin, firstTwin)
        sameParameters := new Type[](1)
        sameParameters[0] = firstTwin
        sameTarget: MethodInfo? = null
        if !ColumnarOverrideTargetResolver.TryFindOverrideTarget(
            signatureOwner,
            "Twin",
            firstTwin,
            sameParameters,
            out sameTarget
        ) || sameTarget == null {
            throw new InvalidOperationException("The same-Twin signature did not select its virtual method.")
        }
        sameTargetParameters := sameTarget.GetParameters()
        if sameTarget.get_DeclaringType() != signatureOwner || !sameTarget.get_IsVirtual() || sameTarget.get_ReturnType() != firstTwin || sameTargetParameters.Length != 1 || sameTargetParameters[0].get_ParameterType() != firstTwin {
            throw new InvalidOperationException("The same-Twin signature did not retain its actual virtual companions.")
        }

        OverrideResolverAssertMissing(signatureOwner, "Twin", secondTwin, sameParameters)
        foreignParameters := new Type[](1)
        foreignParameters[0] = secondTwin
        OverrideResolverAssertMissing(signatureOwner, "Twin", firstTwin, foreignParameters)
    } finally {
        scan.Dispose()
    }
}

test "override targets skip unbaked builders and catch a closed builder member-read refusal" {
    builder := TypeOfCreateBuilder(
        "OverrideResolverUnbakedGeneric",
        "ColumnarOverrideTargetResolverTests.UnbakedGeneric",
        1
    )
    definition: Type = builder
    noParameters := OverrideResolverNoParameters()
    declaredOnDefinition := ColumnarOverrideTargetResolver.DeclaredMethodsOrEmpty(definition)
    if declaredOnDefinition.Length != 0 {
        throw new InvalidOperationException("An unbaked TypeBuilder was reflected despite the explicit skip.")
    }
    definitionTarget: MethodInfo? = null
    if !ColumnarOverrideTargetResolver.TryFindOverrideTarget(
        definition,
        "ToString",
        typeof(string),
        noParameters,
        out definitionTarget
    ) || definitionTarget == null || definitionTarget.get_DeclaringType() != typeof(object) {
        throw new InvalidOperationException("The unbaked TypeBuilder did not skip to its Object ancestor.")
    }

    closedArguments := new Type[](1)
    closedArguments[0] = typeof(int)
    closed := definition.MakeGenericType(closedArguments)
    if closed is TypeBuilder {
        throw new InvalidOperationException("The closed builder fixture did not produce a distinct reflection shape.")
    }
    if !OverrideResolverDeclaredMethodReadThrows(closed) {
        throw new InvalidOperationException("The closed builder fixture did not reach a GetMethods refusal.")
    }
    declaredOnClosed := ColumnarOverrideTargetResolver.DeclaredMethodsOrEmpty(closed)
    if declaredOnClosed.Length != 0 {
        throw new InvalidOperationException("The resolver did not catch the closed builder GetMethods refusal.")
    }
    closedTarget: MethodInfo? = null
    if !ColumnarOverrideTargetResolver.TryFindOverrideTarget(
        closed,
        "ToString",
        typeof(string),
        noParameters,
        out closedTarget
    ) || closedTarget == null || closedTarget.get_DeclaringType() != typeof(object) {
        throw new InvalidOperationException("The caught closed builder read did not continue to Object.ToString.")
    }
    OverrideResolverAssertMissing(closed, "NoSuchUnbakedBuilderTarget", typeof(string), noParameters)
}

// ---- the SOURCE-base override lookup -----------------------------------------------------------
//
// `ColumnarBaseMethodMatch` reads a base chain through Reflection, which a base being emitted in the
// SAME assembly cannot answer: its `TypeBuilder` is unbaked and declares nothing. These pin the
// second door — the source base's own declaration table — and above all its type-identity rule,
// which must never fall back to comparing NAMES of builder-bound types.

func SourceBaseMatchWithoutBase(name: string, returnType: Type, parameterTypes: Type[]): ColumnarSourceBaseMethodMatch {
    noBase: ColumnarStructDef? = null
    return new ColumnarSourceBaseMethodMatch(noBase, name, returnType, parameterTypes)
}

test "a source-base match with nothing to walk does not match and finds no name" {
    probe := SourceBaseMatchWithoutBase("Area", typeof(int), OverrideResolverNoParameters())
    assert !probe.Matched
    assert !probe.FoundName
    assert probe.Target == null
    assert probe.Owner == null
}

test "a source-base match refuses to hand out a target it never found" {
    probe := SourceBaseMatchWithoutBase("Area", typeof(int), OverrideResolverNoParameters())
    threw := false
    try {
        probe.RequiredTarget()
    } catch ex: InvalidOperationException {
        threw = true
    }
    assert threw
}

test "a source-base match for an empty member name stays unmatched" {
    assert !SourceBaseMatchWithoutBase("", typeof(int), OverrideResolverNoParameters()).Matched
}

test "two complete external identities compare by identity, not by builder rules" {
    // Neither side is builder-bound, so the comparison is the same assembly-qualified rule the
    // runtime chain uses and an ordinary signature still matches.
    assert ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(typeof(int), typeof(int))
    assert ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(typeof(string), typeof(string))
    assert !ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(typeof(int), typeof(long))
    assert !ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(null, typeof(int))
    assert !ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(typeof(int), null)
}

test "a type parameter is the same type only when it is the same object" {
    // A BUILDER HAS NO STABLE ASSEMBLY-QUALIFIED NAME. Two distinct type parameters both spelled `T`
    // would compare equal under any name rule, silently letting an unrelated member be overridden.
    listParameter := typeof(System.Collections.Generic.List<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
    otherParameter := typeof(System.Collections.Generic.IEnumerable<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
    assert listParameter.get_IsGenericParameter()
    assert ColumnarSourceBaseMethodMatch.IsBuilderBound(listParameter)
    assert ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(listParameter, listParameter)
    assert !ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(listParameter, otherParameter)
}

test "builder-boundness reaches through arrays, by-refs and generic arguments" {
    listParameter := typeof(System.Collections.Generic.List<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
    assert ColumnarSourceBaseMethodMatch.IsBuilderBound(listParameter.MakeArrayType())
    assert ColumnarSourceBaseMethodMatch.IsBuilderBound(listParameter.MakeByRefType())

    // A fully external shape is not builder-bound however deeply it nests.
    assert !ColumnarSourceBaseMethodMatch.IsBuilderBound(typeof(int))
    assert !ColumnarSourceBaseMethodMatch.IsBuilderBound(typeof(int[]))
    assert !ColumnarSourceBaseMethodMatch.IsBuilderBound(typeof(System.Collections.Generic.List<int>))
    assert !ColumnarSourceBaseMethodMatch.IsBuilderBound(typeof(System.Collections.Generic.Dictionary<string, System.Collections.Generic.List<int>>))

    // An OPEN generic definition is not itself builder-bound: it is a complete external identity that
    // simply has parameters, and comparing two of them by name is correct.
    assert !ColumnarSourceBaseMethodMatch.IsBuilderBound(typeof(System.Collections.Generic.List<int>).GetGenericTypeDefinition())
}
