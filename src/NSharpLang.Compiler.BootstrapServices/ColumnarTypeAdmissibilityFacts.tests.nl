namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Reflection
import System.Reflection.Emit


// The type-admissibility predicate family answers ONE question per member — "may the emitter carry a
// value of this CLR type?" — and the C# emitter carries a duplicate of every member here. These
// contracts pin the answers a reflection differential over a 245-type corpus proved were WRONG in the
// N# owners: a span head admitted without its element, a Result/Union head admitted without its
// arguments, the direct-call interop heads dropped, an EnumBuilder that could never be recognised, a
// byref parameter slot that was never substituted, and a bare catch that swallowed every failure.
func AdmissibilityRuntimeType(fullName: string): Type {
    result := Type.GetType(fullName)
    if result == null {
        throw new InvalidOperationException("Admissibility fixture runtime type '" + fullName + "' was not found.")
    }
    return result
}

func AdmissibilityClosed1(definitionName: string, argument: Type): Type {
    definition := AdmissibilityRuntimeType(definitionName)
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

func AdmissibilityClosed2(definitionName: string, first: Type, second: Type): Type {
    definition := AdmissibilityRuntimeType(definitionName)
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return definition.MakeGenericType(arguments)
}

func AdmissibilitySpan(element: Type): Type {
    return AdmissibilityClosed1("System.Span`1", element)
}

func AdmissibilityReadOnlySpan(element: Type): Type {
    return AdmissibilityClosed1("System.ReadOnlySpan`1", element)
}

func AdmissibilityQueueOfInt(): Type {
    return AdmissibilityClosed1("System.Collections.Generic.Queue`1", typeof(int))
}

// `NSharpLang.Runtime.dll` is NOT on the estate test host's probing path, so
// `Type.GetType("NSharpLang.Runtime.Result`2, NSharpLang.Runtime")` answers null here. The planner
// matches these heads by EXACT FULL NAME, so the definition is installed the same way
// `TypeOfInstallRuntimeUnion` already installs the union head for the typeof contracts. (The
// receiver-side owner compares by handle IDENTITY and therefore cannot be driven from this host at
// all; its agreement with the planner is established by the reflection differential instead.)
func AdmissibilityInstallRuntimeDefinition(exactName: string): Type {
    builder := TypeOfCreateBuilder(exactName, "NSharpLang.Runtime", 2)
    createType := ExecutorRequiredMethod(typeof(TypeBuilder), "CreateType", new Type[](0))
    value := TypeOfRequiredInvocation(createType, builder, new object[](0))
    runtimeType := value as Type
    if runtimeType == null {
        throw new InvalidOperationException("Runtime definition fixture '" + exactName + "' did not produce a Type.")
    }
    return runtimeType
}

func AdmissibilityResult(ok: Type, err: Type): Type {
    definition := AdmissibilityInstallRuntimeDefinition("NSharpLang.Runtime.Result`2")
    arguments := new Type[](2)
    arguments[0] = ok
    arguments[1] = err
    return definition.MakeGenericType(arguments)
}

func AdmissibilityUnion(left: Type, right: Type): Type {
    definition := AdmissibilityInstallRuntimeDefinition("NSharpLang.Runtime.Union`2")
    arguments := new Type[](2)
    arguments[0] = left
    arguments[1] = right
    return definition.MakeGenericType(arguments)
}

// A LIVE EnumBuilder. `EnumBuilder` is abstract on this runtime, so the instance is
// `EnumBuilderImpl` (persisted emit) or `RuntimeEnumBuilder` (run emit) — which is exactly why an
// exact-name test on the base type could never be true.
func AdmissibilityEnumBuilder(): Type {
    assemblyBuilderType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.AssemblyBuilder")
    assemblyBuilderAccessType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.AssemblyBuilderAccess")
    moduleBuilderType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.ModuleBuilder")
    typeAttributesType := TypeOfRequiredRuntimeType(typeof(AssemblyName), "System.Reflection.TypeAttributes")

    assemblyNameConstructorTypes := new Type[](1)
    assemblyNameConstructorTypes[0] = typeof(string)
    assemblyNameConstructor := ExecutorRequiredConstructor(typeof(AssemblyName), assemblyNameConstructorTypes)
    assemblyNameArguments := new object[](1)
    ExecutorSetObject(assemblyNameArguments, 0, "AdmissibilityEnumAsm")
    assemblyName := TypeOfRequiredConstruction(assemblyNameConstructor, assemblyNameArguments)

    defineAssemblyTypes := new Type[](2)
    defineAssemblyTypes[0] = typeof(AssemblyName)
    defineAssemblyTypes[1] = assemblyBuilderAccessType
    defineAssembly := ExecutorRequiredMethod(assemblyBuilderType, "DefineDynamicAssembly", defineAssemblyTypes)
    defineAssemblyArguments := new object[](2)
    ExecutorSetObject(defineAssemblyArguments, 0, assemblyName)
    ExecutorSetObject(defineAssemblyArguments, 1, TypeOfRequiredStaticField(assemblyBuilderAccessType, "Run"))
    assemblyBuilder := TypeOfRequiredInvocation(defineAssembly, null, defineAssemblyArguments)

    defineModuleTypes := new Type[](1)
    defineModuleTypes[0] = typeof(string)
    defineModule := ExecutorRequiredMethod(assemblyBuilderType, "DefineDynamicModule", defineModuleTypes)
    defineModuleArguments := new object[](1)
    ExecutorSetObject(defineModuleArguments, 0, "AdmissibilityEnumModule")
    moduleBuilder := TypeOfRequiredInvocation(defineModule, assemblyBuilder, defineModuleArguments)

    defineEnumTypes := new Type[](3)
    defineEnumTypes[0] = typeof(string)
    defineEnumTypes[1] = typeAttributesType
    defineEnumTypes[2] = typeof(Type)
    defineEnum := ExecutorRequiredMethod(moduleBuilderType, "DefineEnum", defineEnumTypes)
    defineEnumArguments := new object[](3)
    ExecutorSetObject(defineEnumArguments, 0, "AdmissibilityEnum")
    ExecutorSetObject(defineEnumArguments, 1, TypeOfRequiredStaticField(typeAttributesType, "Public"))
    ExecutorSetObject(defineEnumArguments, 2, typeof(int))
    created := TypeOfRequiredInvocation(defineEnum, moduleBuilder, defineEnumArguments)

    enumBuilder := created as Type
    if enumBuilder == null {
        throw new InvalidOperationException("ModuleBuilder.DefineEnum did not return a Type.")
    }
    return enumBuilder
}

// Successor contract to the C# emitter's IsSupportedReadOnlySpanType/IsSupportedSpanType pair: the
// span HEAD alone is not the question. Before this, the N# owner answered on the head only and
// admitted nine span shapes the emitter declines — including `Span<T>` over a source TypeBuilder,
// whose `GetConstructor` throws NotSupportedException on the conversion path.
test "span admissibility requires a blittable element, not just the span head" {
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(int)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(byte)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(bool)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(char)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(double)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(float)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(long)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(ulong)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(short)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(ushort)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(sbyte)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(uint)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilityReadOnlySpan(typeof(char)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilityReadOnlySpan(typeof(int)))

    // Every one of these was ADMITTED before the element constraint was restored.
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(object)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(DateTime)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(decimal)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(IntPtr)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilityReadOnlySpan(typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilityReadOnlySpan(typeof(object)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilityReadOnlySpan(typeof(int[])))

    // Non-span shapes stay out, and the open definition is not a span value.
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(typeof(int))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(typeof(int[]))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilityRuntimeType("System.Span`1"))

    // The receiver-side owner already asked the same question and must keep agreeing with it.
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedSpanLikeReceiver(AdmissibilitySpan(typeof(int)))
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedSpanLikeReceiver(AdmissibilitySpan(typeof(string)))
}

// The interop heads are ColumnarRuntimeTypeFacts' to own. Naming `Stream` inline dropped FileStream
// and DirectoryInfo, and TextWriter was absent altogether — three types the emitter admits.
test "type admissibility routes the interop heads through the runtime facts owner" {
    // `typeof(FileStream)` / `typeof(DirectoryInfo)` DECLINE at emit — the same reason the subject
    // kernel reaches them by name — so the seeded lookup names them here too.
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Stream))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(StreamReader))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Process))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(ProcessStartInfo))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.FileStream"))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.DirectoryInfo"))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.TextWriter"))

    // Neighbours of the admitted heads that are NOT modelled stay out.
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.MemoryStream"))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.FileInfo"))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.StreamWriter"))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.TextReader"))

    // The receiver-side owner answers the same on the two heads it was also missing.
    assert ColumnarRuntimeInstanceMemberResolver.IsAdmittedValueType(AdmissibilityRuntimeType("System.IO.FileStream"))
    assert ColumnarRuntimeInstanceMemberResolver.IsAdmittedValueType(AdmissibilityRuntimeType("System.IO.DirectoryInfo"))
    assert !ColumnarRuntimeInstanceMemberResolver.IsAdmittedValueType(AdmissibilityRuntimeType("System.IO.FileInfo"))
}

// `Result<T, E>` and `Union<A, B>` were admitted on the DEFINITION NAME alone, so
// `Result<Queue<int>, string>` — whose Ok value has no emit lowering at all — read as a supported
// type and could reach a collection element or a tuple slot.
test "result and anonymous-union admissibility constrains the arguments, not just the head" {
    queue := AdmissibilityQueueOfInt()

    assert ColumnarTypeOfPlanner.IsSupportedResultType(AdmissibilityResult(typeof(int), typeof(string)))
    assert ColumnarTypeOfPlanner.IsSupportedResultType(AdmissibilityResult(typeof(string), typeof(bool)))
    assert !ColumnarTypeOfPlanner.IsSupportedResultType(AdmissibilityResult(queue, typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedResultType(AdmissibilityResult(typeof(string), queue))
    assert !ColumnarTypeOfPlanner.IsSupportedResultType(typeof(int))

    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionType(AdmissibilityUnion(typeof(int), typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedAnonymousUnionType(AdmissibilityUnion(queue, typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedAnonymousUnionType(typeof(int))

    // The root predicate carries the constraint, which is the reachable consequence.
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityResult(typeof(int), typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityResult(queue, typeof(string)))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityUnion(typeof(int), typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityUnion(queue, typeof(string)))
}

// `EnumBuilder` is ABSTRACT on this runtime. The exact-name test could never be true, so every
// EnumBuilder read as BAKED — and `List<SomeEnumBuilder>` then took the plain-reflection member
// path, where `GetMethod` throws NotSupportedException.
test "enum builder detection walks the runtime base chain" {
    enumBuilder := AdmissibilityEnumBuilder()

    // The instance is NOT of the abstract base type — the fact the exact-name test tripped on.
    assert enumBuilder.GetType().FullName != "System.Reflection.Emit.EnumBuilder"

    assert ColumnarTypeOfPlanner.IsEnumBuilder(enumBuilder)
    assert ColumnarRuntimeInstanceMemberResolver.IsEnumBuilder(enumBuilder)
    assert !ColumnarTypeOfPlanner.IsEnumBuilder(typeof(int))
    assert !ColumnarTypeOfPlanner.IsEnumBuilder(typeof(string))
    assert !ColumnarTypeOfPlanner.IsEnumBuilder(AdmissibilityRuntimeType("System.StringComparison"))
    assert !ColumnarRuntimeInstanceMemberResolver.IsEnumBuilder(AdmissibilityRuntimeType("System.StringComparison"))

    // It is still an enum by the language's own classification.
    assert ColumnarTypeOfPlanner.IsEnumType(enumBuilder)

    // The consequences the exact-name test lost.
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(enumBuilder)
    assert ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(enumBuilder)
    assert ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(enumBuilder)
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(enumBuilder.MakeArrayType())
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(enumBuilder)))
    assert ColumnarRuntimeInstanceMemberResolver.IsSourceBuilderShape(enumBuilder)

    assert !ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(enumBuilder)
    assert !ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(enumBuilder)
}

func ColumnarTypeAdmissibilityOneType(only: Type): Type[] {
    arguments := new Type[](1)
    arguments[0] = only
    return arguments
}

// A `ref`/`out` slot in an open signature is `T&`. Without a byref arm the substitution returned the
// UNSUBSTITUTED open `T&`, so a closed argument was compared against an open parameter.
test "closed-generic substitution carries byref parameter slots" {
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    openParameter := listDefinition.GetGenericArguments()[0]

    closedArguments := new Type[](2)
    closedArguments[0] = typeof(int)
    closedArguments[1] = typeof(string)

    substituted := ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(openParameter.MakeByRefType(), closedArguments)
    assert substituted == typeof(int).MakeByRefType()
    assert substituted.get_IsByRef()
    assert substituted.GetElementType() == typeof(int)

    // The arms that already worked keep working, and a byref over an array recurses.
    assert ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(openParameter, closedArguments) == typeof(int)
    assert ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(openParameter.MakeArrayType(), closedArguments) == typeof(int[])
    assert ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(openParameter.MakeArrayType().MakeByRefType(), closedArguments) == typeof(int[]).MakeByRefType()
    assert ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(typeof(string), closedArguments) == typeof(string)
    assert ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(typeof(string).MakeByRefType(), closedArguments) == typeof(string).MakeByRefType()
}

// The swallow around `IsInterface` is narrow on purpose: a bare catch turned "this type could not be
// read" into the confident answer "not an interface".
test "runtime interface classification answers the ordinary shapes" {
    assert ColumnarBaseTypePlanner.IsRuntimeInterfaceType(AdmissibilityRuntimeType("System.IDisposable"))
    assert ColumnarBaseTypePlanner.IsRuntimeInterfaceType(AdmissibilityClosed1("System.Collections.Generic.IReadOnlyList`1", typeof(int)))
    assert !ColumnarBaseTypePlanner.IsRuntimeInterfaceType(typeof(string))
    assert !ColumnarBaseTypePlanner.IsRuntimeInterfaceType(typeof(int))
    assert !ColumnarBaseTypePlanner.IsRuntimeInterfaceType(AdmissibilityRuntimeType("System.StringComparison"))
    assert !ColumnarBaseTypePlanner.IsRuntimeInterfaceType(typeof(int[]))
    assert !ColumnarBaseTypePlanner.IsRuntimeInterfaceType(typeof(List<int>).GetGenericTypeDefinition())

    // An un-finalized builder still classifies without throwing out of the member.
    builder := TypeOfCreateBuilder("AdmissibilityBuilderShape", "AdmissibilityBuilderAsm", 0)
    assert !ColumnarBaseTypePlanner.IsRuntimeInterfaceType(builder)
}
