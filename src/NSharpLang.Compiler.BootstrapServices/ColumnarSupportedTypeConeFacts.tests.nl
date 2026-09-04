namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// `015-A2` makes `ColumnarTypeOfPlanner` the compiler's SOLE owner of the nineteen predicates inside
// the `IsSupportedType` cone: the C# emitter's duplicates are deleted in the same slice, and deleting
// them is exactly what makes the reflection differential that proved the two sides equivalent
// unrunnable from here on. A grep of the whole estate before the cut found TWELVE of the nineteen
// with ZERO native contracts, so these blocks pin the answers the emitter now DEPENDS on: the
// byte-only buffer heads, the liftable nullable element set, the blittable span element set, the
// byref-like classification, enum classification across two builder shapes, the array element
// surface, the closed generic families, and the enum split that is the only reason two
// builder-containment walks exist instead of one.

// ValueTuple/Action/Func arities past two need N identical arguments; the shared fixtures stop at two.
func ConeClosedInts(definitionName: string, arity: int): Type {
    definition := AdmissibilityRuntimeType(definitionName)
    arguments := new Type[](arity)
    index := 0
    while index < arity {
        arguments[index] = typeof(int)
        index += 1
    }
    return definition.MakeGenericType(arguments)
}

// A source enum reaches the predicates as a TypeBuilder whose BASE is System.Enum — the shape the
// `t is TypeBuilder && BaseType == typeof(Enum)` arm exists for. The shared builder fixture defines
// types without a parent, so this one names DefineType's three-argument overload.
func ConeEnumParentedBuilder(): Type {
    assemblyBuilderType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.AssemblyBuilder")
    assemblyBuilderAccessType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.AssemblyBuilderAccess")
    moduleBuilderType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.ModuleBuilder")
    typeAttributesType := TypeOfRequiredRuntimeType(typeof(AssemblyName), "System.Reflection.TypeAttributes")

    assemblyNameConstructorTypes := new Type[](1)
    assemblyNameConstructorTypes[0] = typeof(string)
    assemblyNameConstructor := ExecutorRequiredConstructor(typeof(AssemblyName), assemblyNameConstructorTypes)
    assemblyNameArguments := new object[](1)
    ExecutorSetObject(assemblyNameArguments, 0, "ConeEnumParentedAsm")
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
    ExecutorSetObject(defineModuleArguments, 0, "ConeEnumParentedModule")
    moduleBuilder := TypeOfRequiredInvocation(defineModule, assemblyBuilder, defineModuleArguments)

    defineTypeTypes := new Type[](3)
    defineTypeTypes[0] = typeof(string)
    defineTypeTypes[1] = typeAttributesType
    defineTypeTypes[2] = typeof(Type)
    defineType := ExecutorRequiredMethod(moduleBuilderType, "DefineType", defineTypeTypes)
    defineTypeArguments := new object[](3)
    ExecutorSetObject(defineTypeArguments, 0, "ConeSourceEnum")
    ExecutorSetObject(defineTypeArguments, 1, TypeOfRequiredStaticField(typeAttributesType, "Public"))
    ExecutorSetObject(defineTypeArguments, 2, AdmissibilityRuntimeType("System.Enum"))
    created := TypeOfRequiredInvocation(defineType, moduleBuilder, defineTypeArguments)
    builder := created as Type
    if builder == null {
        throw new InvalidOperationException("Reflection.Emit did not return an Enum-parented builder.")
    }
    return builder
}

// The buffer lowerings — ArrayPool rent/return, IMemoryOwner.Memory, Memory.Span — are written for
// byte buffers and nothing else, so the ELEMENT is part of each head's question. Four separate named
// heads, not one shape test: a consumer names the head it means.
test "the four buffer heads are admitted at byte and at no other element" {
    arrayPoolByte := AdmissibilityClosed1("System.Buffers.ArrayPool`1", typeof(byte))
    arrayPoolInt := AdmissibilityClosed1("System.Buffers.ArrayPool`1", typeof(int))
    memoryPoolByte := AdmissibilityClosed1("System.Buffers.MemoryPool`1, System.Memory", typeof(byte))
    memoryPoolInt := AdmissibilityClosed1("System.Buffers.MemoryPool`1, System.Memory", typeof(int))
    ownerByte := AdmissibilityClosed1("System.Buffers.IMemoryOwner`1", typeof(byte))
    ownerInt := AdmissibilityClosed1("System.Buffers.IMemoryOwner`1", typeof(int))
    memoryByte := AdmissibilityClosed1("System.Memory`1", typeof(byte))
    memoryInt := AdmissibilityClosed1("System.Memory`1", typeof(int))

    assert ColumnarTypeOfPlanner.IsSupportedArrayPoolType(arrayPoolByte)
    assert ColumnarTypeOfPlanner.IsSupportedMemoryPoolType(memoryPoolByte)
    assert ColumnarTypeOfPlanner.IsSupportedMemoryOwnerType(ownerByte)
    assert ColumnarTypeOfPlanner.IsSupportedMemoryType(memoryByte)

    assert !ColumnarTypeOfPlanner.IsSupportedArrayPoolType(arrayPoolInt)
    assert !ColumnarTypeOfPlanner.IsSupportedMemoryPoolType(memoryPoolInt)
    assert !ColumnarTypeOfPlanner.IsSupportedMemoryOwnerType(ownerInt)
    assert !ColumnarTypeOfPlanner.IsSupportedMemoryType(memoryInt)

    // Each head answers for its OWN definition only.
    assert !ColumnarTypeOfPlanner.IsSupportedArrayPoolType(memoryPoolByte)
    assert !ColumnarTypeOfPlanner.IsSupportedArrayPoolType(ownerByte)
    assert !ColumnarTypeOfPlanner.IsSupportedArrayPoolType(memoryByte)
    assert !ColumnarTypeOfPlanner.IsSupportedMemoryPoolType(arrayPoolByte)
    assert !ColumnarTypeOfPlanner.IsSupportedMemoryOwnerType(memoryByte)
    assert !ColumnarTypeOfPlanner.IsSupportedMemoryType(ownerByte)

    // An open definition is not a value, and a scalar is not a buffer.
    assert !ColumnarTypeOfPlanner.IsSupportedArrayPoolType(AdmissibilityRuntimeType("System.Buffers.ArrayPool`1"))
    assert !ColumnarTypeOfPlanner.IsSupportedMemoryType(AdmissibilityRuntimeType("System.Memory`1"))
    assert !ColumnarTypeOfPlanner.IsSupportedMemoryOwnerType(typeof(int))

    // Type admission is independent of the buffer-specific operations: all five catalog types pass.
    assert ColumnarTypeOfPlanner.IsSupportedType(arrayPoolByte)
    assert ColumnarTypeOfPlanner.IsSupportedType(memoryPoolByte)
    assert ColumnarTypeOfPlanner.IsSupportedType(ownerByte)
    assert ColumnarTypeOfPlanner.IsSupportedType(memoryByte)
    assert ColumnarTypeOfPlanner.IsSupportedType(arrayPoolInt)
}

// `Nullable<T>` is admissible exactly when T is LIFTABLE, and the liftable set is not the same as the
// supported set: DateTime and Guid are supported values that cannot be lifted, and an enum cannot
// either, while a ValueTuple can.
test "nullable admissibility is exactly the liftable element set" {
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(int))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(uint))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(long))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(ulong))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(short))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(ushort))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(byte))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(sbyte))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(bool))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(char))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(double))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(float))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(decimal))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(TimeSpan))

    // Supported as VALUES, not liftable — and the wrapper follows the element.
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.DateTime"))
    assert !ColumnarTypeOfPlanner.IsLiftableNullableElement(AdmissibilityRuntimeType("System.DateTime"))
    assert !ColumnarTypeOfPlanner.IsLiftableNullableElement(AdmissibilityRuntimeType("System.Guid"))
    assert !ColumnarTypeOfPlanner.IsLiftableNullableElement(AdmissibilityRuntimeType("System.DayOfWeek"))
    assert !ColumnarTypeOfPlanner.IsLiftableNullableElement(typeof(string))

    assert ColumnarTypeOfPlanner.IsSupportedNullable(AdmissibilityClosed1("System.Nullable`1", typeof(int)))
    assert ColumnarTypeOfPlanner.IsSupportedNullable(AdmissibilityClosed1("System.Nullable`1", typeof(decimal)))
    assert ColumnarTypeOfPlanner.IsSupportedNullable(AdmissibilityClosed1("System.Nullable`1", typeof(TimeSpan)))
    assert !ColumnarTypeOfPlanner.IsSupportedNullable(AdmissibilityClosed1("System.Nullable`1", AdmissibilityRuntimeType("System.DateTime")))
    assert !ColumnarTypeOfPlanner.IsSupportedNullable(AdmissibilityClosed1("System.Nullable`1", AdmissibilityRuntimeType("System.Guid")))
    assert !ColumnarTypeOfPlanner.IsSupportedNullable(AdmissibilityClosed1("System.Nullable`1", AdmissibilityRuntimeType("System.DayOfWeek")))

    // A tuple element lifts, which is the one recursive arm of the liftable set.
    tuplePair := AdmissibilityClosed2("System.ValueTuple`2", typeof(int), typeof(int))
    assert ColumnarTypeOfPlanner.IsLiftableNullableElement(tuplePair)
    assert ColumnarTypeOfPlanner.IsSupportedNullable(AdmissibilityClosed1("System.Nullable`1", tuplePair))

    // The wrapper predicate answers on the WRAPPER; the bare element and the open definition are not
    // nullables, and a supported nullable is also an admissible array element.
    assert !ColumnarTypeOfPlanner.IsSupportedNullable(typeof(int))
    assert !ColumnarTypeOfPlanner.IsSupportedNullable(AdmissibilityRuntimeType("System.Nullable`1"))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(AdmissibilityClosed1("System.Nullable`1", typeof(int)))
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(AdmissibilityClosed1("System.Nullable`1", AdmissibilityRuntimeType("System.DateTime")))
}

// The span element set is NARROWER than the array element set: no string, no object, no handles, no
// decimal — the span read/write/slice lowerings are written for the blittable scalars, plus enums,
// which carry their underlying integral value.
test "the span element set is the blittable scalars plus enums" {
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(bool))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(int))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(uint))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(long))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(ulong))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(byte))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(sbyte))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(short))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(ushort))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(char))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(double))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(float))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(AdmissibilityRuntimeType("System.DayOfWeek"))

    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(decimal))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(string))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(object))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(IntPtr))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(AdmissibilityRuntimeType("System.DateTime"))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(typeof(int[]))

    // The head predicate is this element set composed with the two span definitions, so an enum span
    // is admitted and a decimal span is not.
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(AdmissibilityRuntimeType("System.DayOfWeek")))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(decimal)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilityReadOnlySpan(typeof(IntPtr)))
}

// Byref-like is a STORAGE question, not an admissibility one: `Span<string>` is byref-like even
// though the emitter declines it. It is the guard that keeps a byref-like argument out of a Result
// slot, where it could not be stored in a field or a local.
test "byref-like classification is the span family and TypedReference" {
    assert ColumnarTypeOfPlanner.IsByRefLike(AdmissibilitySpan(typeof(int)))
    assert ColumnarTypeOfPlanner.IsByRefLike(AdmissibilityReadOnlySpan(typeof(byte)))
    assert ColumnarTypeOfPlanner.IsByRefLike(AdmissibilitySpan(typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(string)))
    assert ColumnarTypeOfPlanner.IsByRefLike(AdmissibilityRuntimeType("System.TypedReference"))

    assert !ColumnarTypeOfPlanner.IsByRefLike(typeof(int))
    assert !ColumnarTypeOfPlanner.IsByRefLike(typeof(string))
    assert !ColumnarTypeOfPlanner.IsByRefLike(typeof(decimal))
    assert !ColumnarTypeOfPlanner.IsByRefLike(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.IsByRefLike(AdmissibilityRuntimeType("System.DateTime"))
    assert !ColumnarTypeOfPlanner.IsByRefLike(typeof(int[]))

    // An un-finalized builder answers without throwing out of the member.
    assert !ColumnarTypeOfPlanner.IsByRefLike(TypeOfCreateBuilder("ConeByRefLikeShape", "ConeByRefLikeAsm", 0))
}

// Enum classification has three arms — an EnumBuilder, a TypeBuilder parented on System.Enum, and an
// ordinary runtime enum — and the emitter reads it through the array element surface and the span
// element set as well as directly.
test "enum classification covers runtime enums and both builder shapes" {
    assert ColumnarTypeOfPlanner.IsEnumType(AdmissibilityRuntimeType("System.DayOfWeek"))
    assert ColumnarTypeOfPlanner.IsEnumType(AdmissibilityRuntimeType("System.AttributeTargets"))
    assert ColumnarTypeOfPlanner.IsEnumType(AdmissibilityRuntimeType("System.StringComparison"))
    assert ColumnarTypeOfPlanner.IsEnumType(AdmissibilityEnumBuilder())
    assert ColumnarTypeOfPlanner.IsEnumType(ConeEnumParentedBuilder())

    // `System.Enum` itself is the base class, not an enum; and a builder with no enum parent is not.
    assert !ColumnarTypeOfPlanner.IsEnumType(AdmissibilityRuntimeType("System.Enum"))
    assert !ColumnarTypeOfPlanner.IsEnumType(TypeOfCreateBuilder("ConeNonEnumShape", "ConeNonEnumAsm", 0))
    assert !ColumnarTypeOfPlanner.IsEnumType(typeof(int))
    assert !ColumnarTypeOfPlanner.IsEnumType(typeof(string))
    assert !ColumnarTypeOfPlanner.IsEnumType(AdmissibilityRuntimeType("System.DayOfWeek").MakeArrayType())

    // The two surfaces that read it.
    assert ColumnarTypeOfPlanner.IsSupportedElementType(AdmissibilityRuntimeType("System.DayOfWeek"))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(AdmissibilityRuntimeType("System.DayOfWeek").MakeArrayType())
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.DayOfWeek"))
}

// The ARRAY element surface is its own list, and it is neither a superset nor a subset of the
// supported-value surface: decimal and DateTime are supported values that are NOT array elements,
// while string, object and the three reflection handles are.
test "the array element surface admits handles and jagged arrays and stops at rank two" {
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(bool))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(int))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(uint))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(long))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(ulong))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(byte))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(sbyte))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(short))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(ushort))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(char))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(double))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(float))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(string))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(object))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(IntPtr))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(UIntPtr))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(Type))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(Version))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(Assembly))

    // Jagged arrays recurse; a rank-two array is not an SZ array and stops the walk.
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(int[]))
    assert ColumnarTypeOfPlanner.IsSupportedElementType(typeof(int[]).MakeArrayType())
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(AdmissibilityRuntimeType("System.Int32[,]"))

    // Supported VALUES that are not array elements — the two surfaces are genuinely different lists.
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(decimal))
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(typeof(decimal))
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(AdmissibilityRuntimeType("System.DateTime"))
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(AdmissibilityQueueOfInt())
}

// The closed generic families are CLOSED LISTS. The ten collection heads are the ones with modelled
// member lowerings; the tuple arities are exactly two through seven, because arity one has no
// language spelling and arity eight is the TRest form the emitter does not lower.
test "the collection heads are exactly ten and the tuple arities exactly two through seven" {
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(List<int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(Dictionary<int, int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(SortedDictionary<int, int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(HashSet<int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(Stack<int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(IReadOnlyList<int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(IReadOnlyCollection<int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(IReadOnlySet<int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(IEnumerable<int>))
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(AdmissibilityClosed2("System.Collections.Generic.IReadOnlyDictionary`2", typeof(string), typeof(int)))

    // Neighbours on the same surface with no modelled lowering, and the open definitions.
    assert !ColumnarTypeOfPlanner.IsSupportedCollectionType(AdmissibilityQueueOfInt())
    assert !ColumnarTypeOfPlanner.IsSupportedCollectionType(AdmissibilityClosed2("System.Collections.Generic.KeyValuePair`2", typeof(string), typeof(int)))
    assert !ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(List<int>).GetGenericTypeDefinition())
    assert !ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(int[]))
    assert !ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(string))

    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(ConeClosedInts("System.ValueTuple`2", 2))
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(ConeClosedInts("System.ValueTuple`3", 3))
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(ConeClosedInts("System.ValueTuple`4", 4))
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(ConeClosedInts("System.ValueTuple`5", 5))
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(ConeClosedInts("System.ValueTuple`6", 6))
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(ConeClosedInts("System.ValueTuple`7", 7))
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(AdmissibilityClosed2("System.ValueTuple`2", typeof(int), typeof(string)))

    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(ConeClosedInts("System.ValueTuple`1", 1))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(ConeClosedInts("System.ValueTuple`8", 8))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(AdmissibilityRuntimeType("System.ValueTuple`2"))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(typeof(int))

    // Catalog-resolved slots are admissible; the tuple lowering still declines enum slots.
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(AdmissibilityClosed2("System.ValueTuple`2", typeof(int), AdmissibilityQueueOfInt()))
    assert !ColumnarTypeOfPlanner.IsSupportedValueTuple(AdmissibilityClosed2("System.ValueTuple`2", typeof(int), AdmissibilityRuntimeType("System.DayOfWeek")))
}

// The task family is Task/ValueTask plus their single-argument forms over a SUPPORTED result; the
// delegate family is Action at arities zero through four and Func at one through five, each with
// every argument constrained. Both stop where the emitter's lowerings stop.
test "the task and delegate families are closed lists with constrained arguments" {
    assert ColumnarTypeOfPlanner.IsSupportedTaskType(AdmissibilityRuntimeType("System.Threading.Tasks.Task"))
    assert ColumnarTypeOfPlanner.IsSupportedTaskType(AdmissibilityRuntimeType("System.Threading.Tasks.ValueTask"))
    assert ColumnarTypeOfPlanner.IsSupportedTaskType(AdmissibilityClosed1("System.Threading.Tasks.Task`1", typeof(int)))
    assert ColumnarTypeOfPlanner.IsSupportedTaskType(AdmissibilityClosed1("System.Threading.Tasks.Task`1", typeof(string)))
    assert ColumnarTypeOfPlanner.IsSupportedTaskType(AdmissibilityClosed1("System.Threading.Tasks.ValueTask`1", typeof(int)))

    assert ColumnarTypeOfPlanner.IsSupportedTaskType(AdmissibilityClosed1("System.Threading.Tasks.Task`1", AdmissibilityQueueOfInt()))
    assert !ColumnarTypeOfPlanner.IsSupportedTaskType(AdmissibilityRuntimeType("System.Threading.Tasks.Task`1"))
    assert !ColumnarTypeOfPlanner.IsSupportedTaskType(typeof(int))

    assert ColumnarTypeOfPlanner.IsSupportedDelegateType(typeof(Action))
    assert ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Action`1", 1))
    assert ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Action`2", 2))
    assert ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Action`3", 3))
    assert ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Action`4", 4))
    assert ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Func`1", 1))
    assert ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Func`5", 5))

    // Operation-specific arities and families remain narrow; catalog-resolved arguments pass.
    assert !ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Action`5", 5))
    assert !ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Func`6", 6))
    assert !ColumnarTypeOfPlanner.IsSupportedDelegateType(ConeClosedInts("System.Predicate`1", 1))
    assert ColumnarTypeOfPlanner.IsSupportedDelegateType(AdmissibilityClosed1("System.Func`1", AdmissibilityQueueOfInt()))
    assert !ColumnarTypeOfPlanner.IsSupportedDelegateType(AdmissibilityRuntimeType("System.Action`1"))
}

// TWO containment walks exist for ONE reason: a source ENUM is builder-bound but may still be a
// collection element, because its underlying integral value is what gets stored. This is the only
// input on which the two answers differ.
test "the two builder-containment walks differ on exactly the source enum" {
    sourceEnum := ConeEnumParentedBuilder()
    sourceStruct := TypeOfCreateBuilder("ConeContainmentStruct", "ConeContainmentAsm", 0)

    assert ColumnarTypeOfPlanner.IsEnumType(sourceEnum)
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(sourceEnum)
    assert !ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(sourceEnum)

    // Every other shape answers the same on both walks.
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(sourceStruct)
    assert ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(sourceStruct)
    assert !ColumnarTypeOfPlanner.ContainsBuilderBoundType(typeof(int))
    assert !ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(typeof(int))
    assert !ColumnarTypeOfPlanner.ContainsBuilderBoundType(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.ContainsBuilderBoundType(AdmissibilityRuntimeType("System.DayOfWeek"))
    assert !ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(AdmissibilityRuntimeType("System.DayOfWeek"))

    // Both walks recurse through SZ arrays and through generic arguments.
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(sourceStruct.MakeArrayType())
    assert ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(sourceStruct.MakeArrayType())
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceStruct)))
    assert ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceStruct)))

    // The consumer that reads the difference: a hash-set element must not be builder-bound unless it
    // is an enum, while an ordinary collection element may be.
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(sourceEnum)
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(sourceStruct)
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(sourceEnum)
    assert !ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(sourceStruct)
}
