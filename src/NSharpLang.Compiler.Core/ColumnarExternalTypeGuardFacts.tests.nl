namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// `015-A5` makes `ColumnarTypeOfPlanner` the compiler's SOLE owner of `IsSupportedExternalType`, and
// `ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver` the sole owner of the AspNet
// RECEIVER test the two BCL-property entry points ask; the C# emitter's duplicates of both are
// deleted in the same slice. A sweep of the whole estate before the cut found ZERO mentions of
// `IsSupportedExternalType`, `IsSupportedAspNetReceiver` or `ContainsOpenGenericParameters` in any
// test, and exactly ONE block naming `IsSupportedExternalReferenceShape` — which is VACUOUS with
// respect to both fixes below, because its two inputs (`System.Int32*` and `Dictionary<,>`'s open
// definition) are RuntimeTypes, where the fixed spelling and the deleted defective one agree.
// Nothing in the estate could tell the fix from the defect. These blocks close that gap.
//
// The reroute is DELIBERATELY not behaviour-preserving. The deleted C# head asked
//
//     t.IsValueType || t.IsByRef || t.IsPointer || t.ContainsGenericParameters
//
// and both of the last two terms are wrong for the shapes the emitter actually meets:
//
//   * an ARRAY of an AspNet type reads `IsPointer` FALSE and `HasElementType` TRUE, so the C# head
//     admitted `WebApplication[]` as an "external reference type" WITHOUT EVER CONSULTING THE ARRAY
//     ELEMENT RULE. Measured on the baseline compiler, that left a half-open surface: a
//     `WebApplication[]` parameter could be indexed and have its `Length` read, but the same array
//     could not be CREATED and could not be walked by `for`, because those two paths do read
//     `IsSupportedElementType`. The guard below asks `HasElementType`, so array-ness is decided in
//     one place — the array arm — and the surface is coherent in both directions.
//
//   * an OPEN GENERIC declared in an AspNet namespace is a `TypeBuilderImpl`, on which
//     `ContainsGenericParameters` reads FALSE. Its `HasElementType` is ALSO false, so the array fix
//     does not catch it: this is a SECOND, DISTINCT guard, and `ContainsOpenGenericParameters` is
//     the owner that answers it by walking the definition and its argument tree directly.
//
// A source file may declare a file-scoped `namespace Microsoft.AspNetCore.Builder`, so both shapes
// are reachable from ordinary N# source and neither is hypothetical.
func ExternalGuardAspNetBuilder(simpleName: string, genericParameterCount: int): Type {
    return TypeOfCreateBuilder("Microsoft.AspNetCore.Builder." + simpleName, "ExternalTypeGuardAsm." + simpleName, genericParameterCount)
}

func ExternalGuardHostingBuilder(simpleName: string, genericParameterCount: int): Type {
    return TypeOfCreateBuilder("Microsoft.Extensions.Hosting." + simpleName, "ExternalTypeGuardHostingAsm." + simpleName, genericParameterCount)
}

func ExternalGuardPlainBuilder(simpleName: string, genericParameterCount: int): Type {
    return TypeOfCreateBuilder("Contoso.Plain." + simpleName, "ExternalTypeGuardPlainAsm." + simpleName, genericParameterCount)
}

// THE SHARED BUILDER FIXTURE CANNOT SEE THE SECOND GUARD, AND THAT IS MEASURED RATHER THAN ASSUMED.
// `TypeOfCreateBuilder` goes through `AssemblyBuilder.DefineDynamicAssembly`, which produces a
// `RuntimeTypeBuilder` — and on THAT implementation `ContainsGenericParameters` reads TRUE for an
// open generic, so the deleted C# spelling would decline it too and no assert could tell the two
// apart. The compiler's emit path uses `PersistedAssemblyBuilder`, whose `TypeBuilderImpl` reads
// FALSE. That single difference IS the second defect, so the contract has to build the persisted
// shape itself; anything less pins the behaviour while proving nothing about the fix.
//
//   RuntimeTypeBuilder   open `1 -> ContainsGenericParameters TRUE   (fixed and defective agree)
//   TypeBuilderImpl      open `1 -> ContainsGenericParameters FALSE  (they disagree — the defect)
//
// The first guard needs no such care: an array is a `SymbolType` on both builders.
func ExternalGuardPersistedBuilder(fullName: string, genericParameterCount: int, parent: Type): Type {
    // `TypeBuilder` is type-forwarded to System.Private.CoreLib while `PersistedAssemblyBuilder`
    // lives in System.Reflection.Emit, so the owner-assembly lookup the other fixtures use cannot
    // find it. Resolve it by assembly-qualified name instead.
    persistedBuilderType := Type.GetType(
        "System.Reflection.Emit.PersistedAssemblyBuilder, System.Reflection.Emit"
    )
    if persistedBuilderType == null {
        throw new InvalidOperationException(
            "System.Reflection.Emit.PersistedAssemblyBuilder was not found."
        )
    }
    moduleBuilderType := TypeOfRequiredRuntimeType(
        typeof(TypeBuilder),
        "System.Reflection.Emit.ModuleBuilder"
    )
    typeAttributesType := TypeOfRequiredRuntimeType(
        typeof(AssemblyName),
        "System.Reflection.TypeAttributes"
    )

    assemblyNameConstructorTypes := new Type[](1)
    assemblyNameConstructorTypes[0] = typeof(string)
    assemblyNameConstructor := ExecutorRequiredConstructor(
        typeof(AssemblyName),
        assemblyNameConstructorTypes
    )
    assemblyNameArguments := new object[](1)
    ExecutorSetObject(assemblyNameArguments, 0, "ExternalTypeGuardPersistedAsm")
    assemblyName := TypeOfRequiredConstruction(assemblyNameConstructor, assemblyNameArguments)

    // The constructor is `(AssemblyName, Assembly, IEnumerable<CustomAttributeBuilder>? = null)`,
    // so an EXACT two-type lookup finds nothing. Select by the first two parameter types and pass
    // null for whatever optional tail the overload carries; that survives the tail changing.
    persistedConstructor: ConstructorInfo? = null
    persistedParameterCount := 0
    candidates := persistedBuilderType.GetConstructors()
    candidateIndex := 0
    while candidateIndex < candidates.Length {
        candidate := candidates[candidateIndex]
        candidateParameters := candidate.GetParameters()
        if persistedConstructor == null && candidateParameters.Length >= 2 && candidateParameters[0].get_ParameterType() == typeof(AssemblyName) && candidateParameters[1].get_ParameterType() == typeof(Assembly) {
            persistedConstructor = candidate
            persistedParameterCount = candidateParameters.Length
        }

        candidateIndex += 1
    }

    if persistedConstructor == null {
        throw new InvalidOperationException(
            "PersistedAssemblyBuilder has no (AssemblyName, Assembly, ...) constructor."
        )
    }

    persistedArguments := new object[](persistedParameterCount)
    ExecutorSetObject(persistedArguments, 0, assemblyName)
    ExecutorSetObject(persistedArguments, 1, typeof(object).get_Assembly())
    persistedBuilder := TypeOfRequiredConstruction(persistedConstructor, persistedArguments)

    defineModuleTypes := new Type[](1)
    defineModuleTypes[0] = typeof(string)
    defineModule := ExecutorRequiredMethod(
        persistedBuilderType,
        "DefineDynamicModule",
        defineModuleTypes
    )
    defineModuleArguments := new object[](1)
    ExecutorSetObject(defineModuleArguments, 0, "ExternalTypeGuardPersistedModule")
    moduleBuilder := TypeOfRequiredInvocation(
        defineModule,
        persistedBuilder,
        defineModuleArguments
    )

    defineTypeTypes := new Type[](3)
    defineTypeTypes[0] = typeof(string)
    defineTypeTypes[1] = typeAttributesType
    defineTypeTypes[2] = typeof(Type)
    defineType := ExecutorRequiredMethod(moduleBuilderType, "DefineType", defineTypeTypes)
    defineTypeArguments := new object[](3)
    ExecutorSetObject(defineTypeArguments, 0, fullName)
    ExecutorSetObject(
        defineTypeArguments,
        1,
        TypeOfRequiredStaticField(typeAttributesType, "Public")
    )
    ExecutorSetObject(defineTypeArguments, 2, parent)
    created := TypeOfRequiredInvocation(defineType, moduleBuilder, defineTypeArguments)
    builder := created as TypeBuilder
    if builder == null {
        throw new InvalidOperationException(
            "The persisted-emit fixture did not return a TypeBuilder."
        )
    }

    if genericParameterCount > 0 {
        genericParameterTypes := new Type[](1)
        genericParameterTypes[0] = typeof(string[])
        defineParameters := ExecutorRequiredMethod(
            typeof(TypeBuilder),
            "DefineGenericParameters",
            genericParameterTypes
        )
        parameterNames := new string[](genericParameterCount)
        parameterIndex := 0
        while parameterIndex < parameterNames.Length {
            parameterNames[parameterIndex] = "T" + parameterIndex.ToString()
            parameterIndex += 1
        }
        defineParameterArguments := new object[](1)
        ExecutorSetObject(defineParameterArguments, 0, parameterNames)
        TypeOfRequiredInvocation(defineParameters, builder, defineParameterArguments)
    }

    return builder
}

// The toolset that compiles this assembly cannot yet spell `typeof` over a YamlDotNet type, so the
// yaml family is resolved by assembly-qualified NAME — the same idiom the admissibility fixtures
// already use for runtime definitions they cannot name.
func ExternalGuardYamlType(fullName: string): Type {
    result := Type.GetType(fullName + ", YamlDotNet")
    if result == null {
        throw new InvalidOperationException("External-type guard fixture could not resolve '" + fullName + "'.")
    }
    return result
}

// The first clause is an ASSEMBLY test, not a namespace test, and it is asked before any shape
// guard: the compiler carries YamlDotNet values (the project-file reader's converters) and their
// admissibility does not depend on where in that assembly the type lives.
test "the external-type head admits the yaml assembly by assembly identity, not by namespace" {
    converter := ExternalGuardYamlType("YamlDotNet.Serialization.IYamlTypeConverter")
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(converter)
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(ExternalGuardYamlType("YamlDotNet.Serialization.ISerializer"))
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(ExternalGuardYamlType("YamlDotNet.Core.Events.Scalar"))

    // The yaml namespaces begin with neither prefix the AspNet arm tests, so the admission can only
    // have come from the assembly clause.
    yamlNamespace := converter.Namespace ?? ""
    assert !yamlNamespace.StartsWith("Microsoft.AspNetCore.", StringComparison.Ordinal)
    assert !yamlNamespace.StartsWith("Microsoft.Extensions.Hosting", StringComparison.Ordinal)
}

// The second clause admits ORDINARY CLOSED REFERENCE TYPES in two namespace families. This is the
// arm that carries `WebApplication`, `WebApplicationBuilder`, `HttpContext` and the rest, and it is
// the arm both guards below narrow.
test "the external-type head admits ordinary closed reference types in the AspNet and Hosting namespaces" {
    aspNetClass := ExternalGuardAspNetBuilder("AdmittedClass", 0)
    hostingClass := ExternalGuardHostingBuilder("AdmittedHost", 0)

    assert ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetClass)
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(hostingClass)

    // A namespace outside both prefixes is not admitted, so the prefixes are load-bearing rather
    // than a test that everything builder-shaped passes.
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(ExternalGuardPlainBuilder("Rejected", 0))

    // The prefix comparison is ORDINAL and the AspNet one carries a trailing dot, so a namespace
    // that merely starts with the same letters is not admitted.
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(TypeOfCreateBuilder("Microsoft.AspNetCoreExtras.Sneak", "ExternalTypeGuardSneakAsm", 0))
}

// THE FIRST GUARD. `HasElementType` is true for arrays of every rank, for pointers and for by-refs.
// The deleted C# head asked `IsPointer`, which is true for only the middle one of those three.
test "the external-type head declines every element-typed shape, not just pointers" {
    aspNetClass := ExternalGuardAspNetBuilder("ElementOwner", 0)
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetClass)

    // Rank-1. `IsPointer` is FALSE here and `HasElementType` is TRUE — the exact reading on which
    // the deleted C# head admitted the array.
    aspNetArray := aspNetClass.MakeArrayType()
    assert !aspNetArray.get_IsPointer()
    assert aspNetArray.get_HasElementType()
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetArray)

    // Rank-2 and jagged. Neither has any lowering behind it, and the C# head admitted both.
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetClass.MakeArrayType(2))
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetArray.MakeArrayType())

    // Pointer and by-ref: the two the deleted head DID catch. They must stay declined, so the fold
    // into one term loses nothing.
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetClass.MakePointerType())
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetClass.MakeByRefType())

    // The Hosting arm is narrowed the same way — the guard runs before either prefix is read.
    hostingClass := ExternalGuardHostingBuilder("ElementHost", 0)
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(hostingClass)
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(hostingClass.MakeArrayType())

    // Array-ness is now decided in exactly ONE place — the array arm's element rule — and this is
    // what that division of labour buys. For a SOURCE-declared AspNet-namespaced class the element
    // rule still admits the element (every TypeBuilder is on its allow-list), so the narrowing does
    // not take away arrays of source types; it takes away only arrays whose element the array arm
    // never covered. A rank-2 array is not an SZ array at all, so the element rule declines it and
    // the two rules agree that it is out.
    assert ColumnarTypeOfPlanner.IsSupportedElementType(aspNetClass)
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(aspNetClass.MakeArrayType(2))
}

// THE SECOND GUARD, AND THE MEASURED REASON IT CANNOT BE THE FIRST ONE. An open generic declared in
// an AspNet namespace has `HasElementType` FALSE, so the array fix does not reach it; and it is a
// `TypeBuilderImpl`, on which `ContainsGenericParameters` reads FALSE, so the deleted C# head's own
// term did not reach it either. Two distinct guards are required, and this block is the proof.
test "the external-type head declines an open generic the element guard cannot see" {
    // THE PERSISTED shape, on purpose: this is the only builder whose open generic reads
    // ContainsGenericParameters FALSE, and therefore the only one on which the fixed guard and the
    // deleted C# one give different answers. Driven on the shared runtime-builder fixture instead,
    // every assert below would pass with the defect installed.
    openDefinition := ExternalGuardPersistedBuilder("Microsoft.AspNetCore.Builder.OpenOwner`1", 1, typeof(object))
    assert !openDefinition.get_ContainsGenericParameters()

    // Neither of the other two guards fires on this shape.
    assert !openDefinition.get_HasElementType()
    assert !openDefinition.get_IsValueType()

    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(openDefinition)
    assert ColumnarTypeOfPlanner.ContainsOpenGenericParameters(openDefinition)

    // The plain persisted class in the same namespace IS admitted, so the decline above is the
    // open-generic guard and not something about persisted builders in general.
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(
        ExternalGuardPersistedBuilder("Microsoft.AspNetCore.Builder.OpenOwnerPeer", 0, typeof(object))
    )

    // A generic PARAMETER is the other open shape, and it is declined by the same owner.
    parameters := openDefinition.GetGenericArguments()
    assert parameters.Length == 1
    assert ColumnarTypeOfPlanner.ContainsOpenGenericParameters(parameters[0])

    // The Hosting arm carries the same guard.
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(ExternalGuardHostingBuilder("OpenHost`1", 1))

    // The guard is about OPENNESS, not about genericity: a CLOSED instantiation over a baked
    // argument stays admitted, so the narrowing is exactly one shape class wide.
    closedArguments := new Type[](1)
    closedArguments[0] = typeof(int)
    closedInstantiation := openDefinition.MakeGenericType(closedArguments)
    assert !ColumnarTypeOfPlanner.ContainsOpenGenericParameters(closedInstantiation)
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(closedInstantiation)
}

// `ContainsOpenGenericParameters` walks the ARGUMENT TREE, which is the reason it can answer where
// `ContainsGenericParameters` cannot: openness carried by a nested argument is still openness.
test "the open-generic owner walks the argument tree rather than asking the type once" {
    openDefinition := ExternalGuardAspNetBuilder("NestedOwner`1", 1)
    parameter := openDefinition.GetGenericArguments()[0]

    // `List<T>` over a builder-bound generic parameter is neither a definition nor a parameter, and
    // its own `IsGenericTypeDefinition` is false — only the walk finds the openness.
    listArguments := new Type[](1)
    listArguments[0] = parameter
    listOfParameter := typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(listArguments)
    assert !listOfParameter.get_IsGenericTypeDefinition()
    assert !listOfParameter.get_IsGenericParameter()
    assert ColumnarTypeOfPlanner.ContainsOpenGenericParameters(listOfParameter)

    // And a fully closed nest is not open, so the walk terminates on the right answer.
    closedListArguments := new Type[](1)
    closedListArguments[0] = typeof(string)
    assert !ColumnarTypeOfPlanner.ContainsOpenGenericParameters(typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(closedListArguments))
    assert !ColumnarTypeOfPlanner.ContainsOpenGenericParameters(typeof(int))
    assert !ColumnarTypeOfPlanner.ContainsOpenGenericParameters(typeof(string))
}

// A VALUE type in an AspNet namespace was declined by the deleted C# head and is declined here. This
// is the one term of the C# guard that was already right, and it must survive the rewrite.
test "the external-type head still declines value types in the admitted namespaces" {
    // The value-type term is only LOAD-BEARING inside an admitted namespace: everywhere else the
    // namespace test declines the type anyway, so asserting on `int` and `DateTime` alone would
    // pass with the term deleted. The struct below is declared IN `Microsoft.AspNetCore.Builder`,
    // where nothing but `IsValueType` can turn it down.
    valueTypeBase := TypeOfRequiredRuntimeType(typeof(AssemblyName), "System.ValueType")
    aspNetStruct := ExternalGuardPersistedBuilder(
        "Microsoft.AspNetCore.Builder.AdmittedNamespaceStruct",
        0,
        valueTypeBase
    )
    assert aspNetStruct.get_IsValueType()
    assert (aspNetStruct.Namespace ?? "").StartsWith("Microsoft.AspNetCore.", StringComparison.Ordinal)
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetStruct)
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(aspNetStruct)

    // And the ordinary out-of-namespace shapes stay declined whatever their kind.
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(typeof(int))
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(typeof(DateTime))
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(typeof(string))
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.IsSupportedExternalType(typeof(object))
}

// THE SECOND COLUMN. The two BCL-property entry points ask a RECEIVER question, so `015-A5` routes
// them to the resolver's receiver head rather than spelling the namespace rule a third time. That is
// only sound if the two owners agree, and the reflection differential measured them agreeing
// cell-for-cell over 275 types. These asserts pin the agreement on every shape the two guards move.
test "the resolver receiver head answers the same as the planner head on every guarded shape" {
    aspNetClass := ExternalGuardAspNetBuilder("ReceiverOwner", 0)
    hostingClass := ExternalGuardHostingBuilder("ReceiverHost", 0)
    openDefinition := ExternalGuardAspNetBuilder("ReceiverOpen`1", 1)

    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(aspNetClass)
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(hostingClass)

    // Both guards, on the receiver side.
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(aspNetClass.MakeArrayType())
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(aspNetClass.MakeArrayType(2))
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(hostingClass.MakeArrayType())
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(openDefinition)

    // The receiver head is the AspNet arm ALONE — it carries no yaml-assembly clause — so the two
    // owners part company on exactly one input class, and that difference is deliberate.
    converter := ExternalGuardYamlType("YamlDotNet.Serialization.IYamlTypeConverter")
    assert ColumnarTypeOfPlanner.IsSupportedExternalType(converter)
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(converter)

    // On every AspNet-namespaced input the two agree, which is what makes the routing sound.
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(aspNetClass) == ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetClass)
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(aspNetClass.MakeArrayType()) == ColumnarTypeOfPlanner.IsSupportedExternalType(aspNetClass.MakeArrayType())
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(openDefinition) == ColumnarTypeOfPlanner.IsSupportedExternalType(openDefinition)
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver(hostingClass) == ColumnarTypeOfPlanner.IsSupportedExternalType(hostingClass)
}
