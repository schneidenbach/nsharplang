namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.IO
import System.Linq
import System.Numerics
import System.Reflection
import System.Reflection.Emit
import System.Threading.Tasks

class RuntimeGenericInProbe {
    static func Echo<T>(in value: T): T {
        return value
    }
}

// Generic external methods closed by inference from their arguments. `System.Numerics.Vector`'s static
// surface is the witness for inference through a CONSTRUCTED generic argument; `System.HashCode` and
// `System.Array` witness inference from plain and array arguments.
func GenericMethodRequiredMethod(selection: ColumnarOrdinaryRuntimeDirectCallSelection): MethodInfo {
    method := selection.Method
    if method == null {
        throw new InvalidOperationException("A selected generic runtime method must carry a method handle.")
    }
    return method
}

func GenericMethodTypes1(first: Type): Type[] {
    result := new Type[](1)
    result[0] = first
    return result
}

func GenericMethodTypes2(first: Type, second: Type): Type[] {
    result := new Type[](2)
    result[0] = first
    result[1] = second
    return result
}

func GenericMethodTypes3(first: Type, second: Type, third: Type): Type[] {
    result := new Type[](3)
    result[0] = first
    result[1] = second
    result[2] = third
    return result
}

test "runtime generic method resolver infers a method type parameter from a constructed generic argument" {
    vectorOwner := typeof(Vector<int>).GetGenericTypeDefinition().get_Assembly().GetType("System.Numerics.Vector")
    if vectorOwner == null {
        throw new InvalidOperationException("System.Numerics.Vector was not found in the compiler runtime.")
    }

    sum := ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "Sum", GenericMethodTypes1(typeof(Vector<int>)), true)
    assert sum.IsSelected
    sumMethod := GenericMethodRequiredMethod(sum)
    assert !sumMethod.get_IsGenericMethodDefinition()
    assert sumMethod.GetGenericArguments()[0] == typeof(int)
    assert sum.ParameterTypes.Length == 1
    assert sum.ParameterTypes[0] == typeof(Vector<int>)
    assert sum.ReturnType == typeof(int)
    assert sum.IsStatic
    assert !sum.UsesCallVirtual

    longSum := ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "Sum", GenericMethodTypes1(typeof(Vector<long>)), true)
    assert longSum.IsSelected
    assert longSum.ReturnType == typeof(long)

    minimum := ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "Min", GenericMethodTypes2(typeof(Vector<int>), typeof(Vector<int>)), true)
    assert minimum.IsSelected
    assert minimum.ReturnType == typeof(Vector<int>)

    greaterOrEqual := ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "GreaterThanOrEqual", GenericMethodTypes2(typeof(Vector<int>), typeof(Vector<int>)), true)
    assert greaterOrEqual.IsSelected
    assert greaterOrEqual.ReturnType == typeof(Vector<int>)

    conditional := ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "ConditionalSelect", GenericMethodTypes3(typeof(Vector<int>), typeof(Vector<int>), typeof(Vector<int>)), true)
    assert conditional.IsSelected
    assert conditional.ReturnType == typeof(Vector<int>)
}

test "runtime generic method resolver infers each type parameter from its own argument" {
    combine := ColumnarRuntimeGenericMethodResolver.Resolve(typeof(HashCode), "Combine", GenericMethodTypes2(typeof(byte), typeof(string)), true)
    assert combine.IsSelected
    combineMethod := GenericMethodRequiredMethod(combine)
    typeArguments := combineMethod.GetGenericArguments()
    assert typeArguments.Length == 2
    assert typeArguments[0] == typeof(byte)
    assert typeArguments[1] == typeof(string)
    assert combine.ParameterTypes[0] == typeof(byte)
    assert combine.ParameterTypes[1] == typeof(string)
    assert combine.ReturnType == typeof(int)
}

test "runtime generic method inference keeps the read-only direction on a bare argument" {
    argumentTypes := GenericMethodTypes1(typeof(string))
    selection := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(
        typeof(RuntimeGenericInProbe),
        "Echo",
        argumentTypes,
        ColumnarDirectCallArgumentFacts.Empty(1),
        true
    )

    assert selection.IsSelected
    selectedMethod := GenericMethodRequiredMethod(selection)
    assert selectedMethod.GetGenericArguments()[0] == typeof(string)
    assert selection.ParameterTypes[0] == typeof(string).MakeByRefType()
    assert ColumnarOrdinaryRuntimeDirectCallResolver.ReflectedModifierKinds(selectedMethod.GetParameters())[0] == 5
}

test "explicit runtime generic binding accepts a bare value for an in parameter" {
    argumentTypes := GenericMethodTypes1(typeof(string))
    selection := ColumnarExplicitRuntimeGenericMethodResolver.ResolveWithFacts(
        typeof(RuntimeGenericInProbe),
        "Echo",
        GenericMethodTypes1(typeof(string)),
        argumentTypes,
        ColumnarDirectCallArgumentFacts.Empty(1),
        true
    )

    assert selection.IsSelected
    assert selection.ParameterTypes[0] == typeof(string).MakeByRefType()
}

test "runtime generic method resolver infers through array and interface positions" {
    fill := ColumnarRuntimeGenericMethodResolver.Resolve(typeof(Array), "Fill", GenericMethodTypes2(typeof(int[]), typeof(int)), true)
    assert fill.IsSelected
    assert GenericMethodRequiredMethod(fill).GetGenericArguments()[0] == typeof(int)
    assert fill.ParameterTypes[0] == typeof(int[])

    // `List<T>(IEnumerable<T>)`-shaped inference: the definition is found on the argument's own
    // interface list, not on the argument type itself.
    indexOf := ColumnarRuntimeGenericMethodResolver.Resolve(typeof(Array), "IndexOf", GenericMethodTypes2(typeof(string[]), typeof(string)), true)
    assert indexOf.IsSelected
    assert indexOf.ReturnType == typeof(int)
}

test "runtime generic method resolver refuses inference it cannot complete" {
    vectorOwner := typeof(Vector<int>).GetGenericTypeDefinition().get_Assembly().GetType("System.Numerics.Vector")
    if vectorOwner == null {
        throw new InvalidOperationException("System.Numerics.Vector was not found in the compiler runtime.")
    }

    // A type parameter two positions bind DIFFERENTLY is refused rather than guessed.
    assert !ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "Min", GenericMethodTypes2(typeof(Vector<int>), typeof(Vector<long>)), true).IsSelected

    // Wrong arity, wrong staticness, and a name the owner does not declare.
    assert !ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "Sum", GenericMethodTypes2(typeof(Vector<int>), typeof(Vector<int>)), true).IsSelected
    assert !ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "Sum", GenericMethodTypes1(typeof(Vector<int>)), false).IsSelected
    assert !ColumnarRuntimeGenericMethodResolver.Resolve(vectorOwner, "NoSuchReduction", GenericMethodTypes1(typeof(Vector<int>)), true).IsSelected

    // A non-generic declaration stays the ordinary tier's business.
    assert !ColumnarRuntimeGenericMethodResolver.Resolve(typeof(Math), "Abs", GenericMethodTypes1(typeof(int)), true).IsSelected
}

// CLOSING OVER A TYPE PARAMETER OF THE DECLARATION BEING EMITTED. `HashCode.Combine(_state, _ok)`
// inside `Result<TOk, TErr>.GetHashCode` hands this tier a `GenericTypeParameterBuilder` as an
// argument type. That IS closable — `MakeGenericMethod` answers a `MethodBuilderInstantiation` and
// `call` encodes it as a MethodSpec the CLR resolves once per constructed type — so the inference
// admits it where every other open shape stays unbindable.
//
// The closed SIGNATURE is the half a reader cannot infer: `MethodBuilderInstantiation.GetParameters`
// reports the DEFINITION's own `T1, T2`, so the parameter types are substituted here rather than read
// back. Scoring a call against the definition's parameters would compare each argument to an
// unrelated type parameter.
test "runtime generic method resolver closes a method over a type parameter of the type being emitted" {
    openDefinition: Type = TypeOfCreateBuilder("GenericMethodEmittedOwner`1", "ColumnarRuntimeGenericMethodTests.EmittedOwner", 1)
    typeParameter := openDefinition.GetGenericArguments()[0]

    combine := ColumnarRuntimeGenericMethodResolver.Resolve(typeof(HashCode), "Combine", GenericMethodTypes2(typeof(byte), typeParameter), true)

    assert combine.IsSelected
    combineMethod := GenericMethodRequiredMethod(combine)
    typeArguments := combineMethod.GetGenericArguments()
    assert typeArguments.Length == 2
    assert typeArguments[0] == typeof(byte)
    assert Object.ReferenceEquals(typeArguments[1], typeParameter)

    // The SUBSTITUTED signature, not the definition's `T1, T2`.
    assert combine.ParameterTypes.Length == 2
    assert combine.ParameterTypes[0] == typeof(byte)
    assert Object.ReferenceEquals(combine.ParameterTypes[1], typeParameter)
    assert combine.ReturnType == typeof(int)

    // Every OTHER open shape stays unbindable: a still-open constructed generic argument carries no
    // handle the emitter could call, and an open definition is not a type argument at all.
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    assert !ColumnarRuntimeGenericMethodResolver.Resolve(typeof(HashCode), "Combine", GenericMethodTypes2(typeof(byte), listDefinition), true).IsSelected
}

// ─── THE EXPLICIT TWIN: TYPE ARGUMENTS THE CALL SITE WROTE ────────────────────────────────────────

func ExplicitGenericRequiredMethod(selection: ColumnarExplicitGenericCallSelection): MethodInfo {
    method := selection.Method
    if method == null {
        throw new InvalidOperationException("A selected explicit generic call must carry a method handle.")
    }
    return method
}

test "explicit generic resolver closes a STATIC method over the written type arguments" {
    linqEnumerable := typeof(System.Linq.Enumerable)

    empty := ColumnarExplicitRuntimeGenericMethodResolver.Resolve(linqEnumerable, "Empty", GenericMethodTypes1(typeof(int)), 0, true)

    assert empty.IsSelected
    emptyMethod := ExplicitGenericRequiredMethod(empty)
    assert !emptyMethod.get_IsGenericMethodDefinition()
    assert emptyMethod.GetGenericArguments()[0] == typeof(int)
    assert empty.ParameterTypes.Length == 0
    assert empty.ExplicitArgumentCount == 0
    assert empty.ReturnType == typeof(IEnumerable<int>)
    assert empty.IsStatic
    assert !empty.UsesCallVirtual
}

// NOTHING IS INFERRED HERE: `Empty<string>()` and `Empty<int>()` differ only in what was written, and
// each closes over exactly that.
test "a different written argument closes a different instantiation of the same method" {
    linqEnumerable := typeof(System.Linq.Enumerable)

    ints := ColumnarExplicitRuntimeGenericMethodResolver.Resolve(linqEnumerable, "Empty", GenericMethodTypes1(typeof(int)), 0, true)
    texts := ColumnarExplicitRuntimeGenericMethodResolver.Resolve(linqEnumerable, "Empty", GenericMethodTypes1(typeof(string)), 0, true)

    assert ints.IsSelected
    assert texts.IsSelected
    assert ints.ReturnType != texts.ReturnType
    assert texts.ReturnType == typeof(IEnumerable<string>)
}

test "explicit generic resolver closes an INSTANCE method and reports the receiver's dispatch" {
    listOfInt := typeof(List<int>)

    convert := ColumnarExplicitRuntimeGenericMethodResolver.Resolve(listOfInt, "ConvertAll", GenericMethodTypes1(typeof(string)), 1, false)

    assert convert.IsSelected
    assert convert.ParameterTypes.Length == 1
    assert convert.ParameterTypes[0] == typeof(Converter<int, string>)
    assert convert.ReturnType == typeof(List<string>)
    assert !convert.IsStatic

    // A reference receiver dispatches virtually; a VALUE receiver takes an address and a plain call.
    assert convert.UsesCallVirtual
}

// A STATIC call is a plain `call` whatever the owner is, and the written arguments are the
// instantiation — `HashCode.Combine<byte, string>` takes exactly those two.
test "a static call reports a non-virtual dispatch and the substituted parameters" {
    hashOwner := typeof(HashCode)

    combine := ColumnarExplicitRuntimeGenericMethodResolver.Resolve(hashOwner, "Combine", GenericMethodTypes2(typeof(byte), typeof(string)), 2, true)

    assert combine.IsSelected
    assert !combine.UsesCallVirtual
    assert combine.IsStatic
    assert combine.ParameterTypes[0] == typeof(byte)
    assert combine.ParameterTypes[1] == typeof(string)
    assert combine.ReturnType == typeof(int)
}

// A TRAILING OPTIONAL whose metadata default is the null reference is filled, which is the whole
// reason `JsonSerializer.Deserialize<T>(json)` binds without writing `options`.
test "a trailing optional with a null default is filled, and the supplied count says how many were written" {
    serializer := typeof(System.Text.Json.JsonSerializer)

    // `Deserialize<TValue>` declares eight one-argument-plus-options overloads, so the source it reads
    // from is what picks one.
    deserialize := ColumnarExplicitRuntimeGenericMethodResolver.ResolveWithFacts(serializer, "Deserialize", GenericMethodTypes1(typeof(string)), GenericMethodTypes1(typeof(string)), ColumnarDirectCallArgumentFacts.Empty(1), true)

    assert deserialize.IsSelected
    assert deserialize.ParameterTypes.Length == 2
    assert deserialize.ExplicitArgumentCount == 1
    assert deserialize.ParameterTypes[0] == typeof(string)
    assert deserialize.ParameterTypes[1] == typeof(System.Text.Json.JsonSerializerOptions)
    assert deserialize.ReturnType == typeof(string)
}

// THE WRITTEN COUNT MUST MATCH THE DECLARATION'S ARITY. A candidate of another arity is not a
// candidate at all, so nothing is closed and the call site reports the ordinary arity diagnostic.
test "a written type-argument count the declaration does not have selects nothing" {
    linqEnumerable := typeof(System.Linq.Enumerable)

    assert !ColumnarExplicitRuntimeGenericMethodResolver.Resolve(linqEnumerable, "Empty", GenericMethodTypes2(typeof(int), typeof(string)), 0, true).IsSelected

    hashOwner := typeof(HashCode)
    assert !ColumnarExplicitRuntimeGenericMethodResolver.Resolve(hashOwner, "Combine", GenericMethodTypes1(typeof(byte)), 2, true).IsSelected
}

// `CloseOrNull` checks the declared constraints before closure; `MakeGenericMethod` is an additional
// runtime check, but it does not validate TypeBuilder-bound arguments. `Enum.Parse<TEnum>(string) where
// TEnum : struct, Enum` takes an enum and nothing else.
test "a written type argument the declared constraints refuse selects nothing" {
    enumOwner := typeof(Enum)

    // `Parse<TEnum>` declares a `string` and a `ReadOnlySpan<char>` overload at this arity, so the
    // argument type is what picks one.
    textArgument := GenericMethodTypes1(typeof(string))
    accepted := ColumnarExplicitRuntimeGenericMethodResolver.ResolveWithFacts(enumOwner, "Parse", GenericMethodTypes1(typeof(DayOfWeek)), textArgument, ColumnarDirectCallArgumentFacts.Empty(1), true)
    refused := ColumnarExplicitRuntimeGenericMethodResolver.ResolveWithFacts(enumOwner, "Parse", GenericMethodTypes1(typeof(string)), textArgument, ColumnarDirectCallArgumentFacts.Empty(1), true)

    assert accepted.IsSelected
    assert accepted.ReturnType == typeof(DayOfWeek)
    assert !refused.IsSelected
}

// A NAME AND ARITY THAT LEAVE MORE THAN ONE CANDIDATE are refused by the uniqueness tier, because the
// argument TYPES are exactly what would have chosen between them — and a site that reaches this tier
// (a lambda argument, an `out`) does not have them. The scored tier answers the same call once the
// types are known.
test "an ambiguity is refused by the uniqueness tier and resolved by the scored one" {
    linqEnumerable := typeof(System.Linq.Enumerable)

    // `Enumerable.Select<TSource, TResult>` declares two arity-2 overloads: over `Func<T, TResult>`
    // and over `Func<T, int, TResult>`.
    ambiguous := ColumnarExplicitRuntimeGenericMethodResolver.Resolve(linqEnumerable, "Select", GenericMethodTypes2(typeof(int), typeof(string)), 2, true)
    assert !ambiguous.IsSelected

    argumentTypes := GenericMethodTypes2(typeof(IEnumerable<int>), typeof(Func<int, string>))
    scored := ColumnarExplicitRuntimeGenericMethodResolver.ResolveWithFacts(linqEnumerable, "Select", GenericMethodTypes2(typeof(int), typeof(string)), argumentTypes, ColumnarDirectCallArgumentFacts.Empty(2), true)
    assert scored.IsSelected
    assert scored.ParameterTypes[1] == typeof(Func<int, string>)
    assert scored.ReturnType == typeof(IEnumerable<string>)
}

// The owner boundary the inference tier keeps, kept here for the same reason: an open definition has
// no reachable member table and a method of one could not be closed without the TYPE's arguments.
test "an open or builder-bound owner selects nothing" {
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()

    assert !ColumnarExplicitRuntimeGenericMethodResolver.Resolve(listDefinition, "ConvertAll", GenericMethodTypes1(typeof(string)), 1, false).IsSelected
}

// ── declared constraints are enforced over types this compilation is still writing ───────────────
//
// `MakeGenericMethod` validates constraints for runtime types only; over a TypeBuilder it accepts
// anything, so inference that reaches a source `struct` would close `where T : class` and emit
// unverifiable IL. `SatisfiesConstraints` is the arbiter, asked by every closure.
class ConstraintProbe {
    static func NeedsClass<T>(value: T): T where T: class {
        return value
    }

    static func NeedsStruct<T>(value: T): T where T: struct {
        return value
    }

    static func NeedsNew<T>(value: T): T where T: new() {
        return value
    }

    static func NeedsDisposable<T>(value: T): T where T: IDisposable {
        return value
    }

    static func NeedsMemoryStream<T>(value: T): T where T: MemoryStream {
        return value
    }
}

class ConstraintReferenceArgument<T> where T: class {
}

class ConstraintValueArgument<T> where T: struct {
}

class ConstraintEnumArgument<T> where T: Enum {
}

class ConstraintNewArgument<T> where T: new() {
}

class ConstraintDisposableArgument<T> where T: IDisposable {
}

class ConstraintMemoryStreamArgument<T> where T: MemoryStream {
}

class ConstraintUnboundedArgument<T> {
}

func ConstraintProbeMethod(name: string): MethodInfo {
    method := typeof(ConstraintProbe).GetMethod(name)
    if method == null {
        throw new InvalidOperationException("Constraint probe method not found: " + name)
    }
    return method
}

func ConstraintProbeClosable(name: string, argument: Type): bool {
    return ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod(name), GenericMethodTypes1(argument)) != null
}

// An uncreated source-shaped type: a class, or a struct when `isStruct`.
func ConstraintProbeSourceType(isStruct: bool, createRuntimeType: bool = false): Type {
    identity := "ConstraintProbeSource" + Guid.NewGuid().ToString("N")
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(identity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(identity)
    parent := isStruct ? typeof(ValueType) : typeof(object)
    attributes := TypeAttributes.Public
    if isStruct {
        attributes = attributes | TypeAttributes.Sealed | TypeAttributes.SequentialLayout
    }
    owner := module.DefineType("Shape", attributes, parent)
    if !isStruct {
        constructor := owner.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, Type.EmptyTypes)
        il := constructor.GetILGenerator()
        il.Emit(OpCodes.Ldarg_0)
        objectConstructor := typeof(object).GetConstructor(Type.EmptyTypes)
        if objectConstructor == null {
            throw new InvalidOperationException("Object constructor not found")
        }
        il.Emit(OpCodes.Call, objectConstructor)
        il.Emit(OpCodes.Ret)
    }
    if createRuntimeType {
        return owner.CreateType()
    }
    return owner
}

func ConstraintProbeSourceClassWithoutPublicParameterlessConstructor(): Type {
    identity := "ConstraintProbeNoNewSource" + Guid.NewGuid().ToString("N")
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(identity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(identity)
    owner := module.DefineType("Shape", TypeAttributes.Public, typeof(object))
    constructor := owner.DefineConstructor(MethodAttributes.Private, CallingConventions.Standard, Type.EmptyTypes)
    il := constructor.GetILGenerator()
    il.Emit(OpCodes.Ldarg_0)
    objectConstructor := typeof(object).GetConstructor(Type.EmptyTypes)
    if objectConstructor == null {
        throw new InvalidOperationException("Object constructor not found")
    }
    il.Emit(OpCodes.Call, objectConstructor)
    il.Emit(OpCodes.Ret)
    return owner.CreateType()
}

func ConstraintProbeSourceDefinition(identity: string, constructorAttributes: MethodAttributes): ColumnarStructDef {
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(identity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(identity)
    builder := module.DefineType(identity + ".Shape", TypeAttributes.Public, typeof(object))
    constructor := builder.DefineConstructor(constructorAttributes, CallingConventions.Standard, Type.EmptyTypes)
    constructorIl := constructor.GetILGenerator()
    objectConstructor := typeof(object).GetConstructor(Type.EmptyTypes)
    if objectConstructor == null {
        throw new InvalidOperationException("Object constructor not found")
    }
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Call, objectConstructor)
    constructorIl.Emit(OpCodes.Ret)
    definition := new ColumnarStructDef(builder, new string[](0), new Dictionary<string, FieldBuilder>(), true)
    definition.Constructors.Add(new ColumnarConstructorDef(constructor, new Type[](0), new int[](0), new string[](0)))
    return definition
}

func ConstraintProbeSourceMemoryStreamSubtype(): Type {
    identity := "ConstraintProbeMemoryStreamSource" + Guid.NewGuid().ToString("N")
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(identity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(identity)
    return module.DefineType("Shape", TypeAttributes.Public, typeof(MemoryStream))
}

test "a source struct does not close a class-constrained generic method" {
    sourceStruct := ConstraintProbeSourceType(true)
    sourceClass := ConstraintProbeSourceType(false)

    assert !ConstraintProbeClosable("NeedsClass", sourceStruct)
    assert ConstraintProbeClosable("NeedsClass", sourceClass)
    assert !ConstraintProbeClosable("NeedsClass", typeof(int))
    assert ConstraintProbeClosable("NeedsClass", typeof(string))
    assert ConstraintProbeClosable("NeedsClass", typeof(IDisposable))
}

test "a source class does not close a struct-constrained generic method" {
    assert ConstraintProbeClosable("NeedsStruct", ConstraintProbeSourceType(true))
    assert !ConstraintProbeClosable("NeedsStruct", ConstraintProbeSourceType(false))
    assert ConstraintProbeClosable("NeedsStruct", typeof(int))
    assert !ConstraintProbeClosable("NeedsStruct", typeof(int?))
    assert !ConstraintProbeClosable("NeedsStruct", typeof(string))
}

test "a new() constraint refuses a type with no public parameterless constructor" {
    assert ConstraintProbeClosable("NeedsNew", typeof(List<int>)), "List<T> has a public parameterless constructor"
    assert ConstraintProbeClosable("NeedsNew", typeof(int)), "value types satisfy new()"
    assert !ConstraintProbeClosable("NeedsNew", typeof(int?)), "nullable value types do not satisfy new()"
    assert !ConstraintProbeClosable("NeedsNew", ConstraintProbeSourceType(false)), "an uncreated source class cannot prove its public constructor before it is baked"
    assert ConstraintProbeClosable("NeedsNew", ConstraintProbeSourceType(false, true)), "a runtime class with a public parameterless constructor satisfies new()"
    assert !ConstraintProbeClosable("NeedsNew", ConstraintProbeSourceClassWithoutPublicParameterlessConstructor()), "a source class with only a private constructor does not satisfy new()"
    assert !ConstraintProbeClosable("NeedsNew", typeof(Stream)), "abstract classes do not satisfy new()"
    assert !ConstraintProbeClosable("NeedsNew", typeof(string)), "string has no public parameterless constructor"
}

test "a source public parameterless constructor proves an external new constraint" {
    publicDefinition := ConstraintProbeSourceDefinition("ConstraintProbePublicNew", MethodAttributes.Public)
    privateDefinition := ConstraintProbeSourceDefinition("ConstraintProbePrivateNew", MethodAttributes.Private)
    publicDefinitions := new List<ColumnarStructDef>()
    publicDefinitions.Add(publicDefinition)
    privateDefinitions := new List<ColumnarStructDef>()
    privateDefinitions.Add(privateDefinition)

    assert ColumnarRuntimeGenericMethodResolver.HasPublicParameterlessConstructorGuarantee(publicDefinition.Builder, publicDefinitions), "the public constructor fact must satisfy new() before TypeBuilder is baked"
    assert !ColumnarRuntimeGenericMethodResolver.HasPublicParameterlessConstructorGuarantee(privateDefinition.Builder, privateDefinitions), "a private constructor does not prove new()"

    method := ConstraintProbeMethod("NeedsNew")
    argumentTypes := GenericMethodTypes1(publicDefinition.Builder)
    argumentFacts := ColumnarDirectCallArgumentFacts.Empty(1)
    argumentFacts.SourceTypeDefinitions = publicDefinitions
    inferred := ColumnarRuntimeGenericMethodResolver.InferAndClose(method, argumentTypes, argumentFacts, false)
    assert inferred != null, "inferred generic closure must carry the source constructor facts"

    runtimeType := publicDefinition.Builder.CreateType()
    instance := Activator.CreateInstance(runtimeType)
    assert instance != null
    runtimeMethod := method.MakeGenericMethod(GenericMethodTypes1(runtimeType))
    runtimeArguments := new object?[](1)
    runtimeArguments[0] = instance
    runtimeValue := runtimeMethod.Invoke(null, runtimeArguments)
    if runtimeValue == null {
        throw new InvalidOperationException("The closed external method returned a null source instance.")
    }
    assert Object.ReferenceEquals(runtimeValue, instance), "the closed external method must return the same runtime source instance"
    assert runtimeValue.GetType() == runtimeType, "the runtime value must have the newly baked source type"
}

test "a type constraint refuses an argument that does not derive from or implement it" {
    assert ConstraintProbeClosable("NeedsDisposable", typeof(MemoryStream))
    assert !ConstraintProbeClosable("NeedsDisposable", typeof(string))
    assert !ConstraintProbeClosable("NeedsDisposable", ConstraintProbeSourceType(false))
    assert !ConstraintProbeClosable("NeedsDisposable", ConstraintProbeSourceType(true))
}

test "a source class satisfies a generic type constraint through its external base" {
    assert ConstraintProbeClosable("NeedsMemoryStream", ConstraintProbeSourceMemoryStreamSubtype())
}

test "open type arguments must prove the special and declared constraints" {
    reference := typeof(ConstraintReferenceArgument<object>).GetGenericTypeDefinition().GetGenericArguments()[0]
    value := typeof(ConstraintValueArgument<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
    enumeration := typeof(ConstraintEnumArgument<DayOfWeek>).GetGenericTypeDefinition().GetGenericArguments()[0]
    constructor := typeof(ConstraintNewArgument<List<int>>).GetGenericTypeDefinition().GetGenericArguments()[0]
    disposable := typeof(ConstraintDisposableArgument<MemoryStream>).GetGenericTypeDefinition().GetGenericArguments()[0]
    memoryStream := typeof(ConstraintMemoryStreamArgument<MemoryStream>).GetGenericTypeDefinition().GetGenericArguments()[0]
    unconstrained := typeof(ConstraintUnboundedArgument<object>).GetGenericTypeDefinition().GetGenericArguments()[0]

    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsClass"), GenericMethodTypes1(reference)) != null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsClass"), GenericMethodTypes1(value)) == null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsClass"), GenericMethodTypes1(enumeration)) == null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsClass"), GenericMethodTypes1(unconstrained)) == null

    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsStruct"), GenericMethodTypes1(value)) != null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsStruct"), GenericMethodTypes1(reference)) == null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsStruct"), GenericMethodTypes1(unconstrained)) == null

    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsNew"), GenericMethodTypes1(constructor)) != null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsNew"), GenericMethodTypes1(unconstrained)) == null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsDisposable"), GenericMethodTypes1(disposable)) != null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsDisposable"), GenericMethodTypes1(memoryStream)) != null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsClass"), GenericMethodTypes1(memoryStream)) != null
    assert ColumnarRuntimeGenericMethodResolver.CloseOrNull(ConstraintProbeMethod("NeedsDisposable"), GenericMethodTypes1(unconstrained)) == null
}

class ConstraintExtensionProbe {
    static func ReferenceOnly<T>(_receiver: T): int where T: class {
        return 1
    }
}

func ConstraintExtensionProbeCandidate(): ColumnarExtensionMethodCandidate {
    method := typeof(ConstraintExtensionProbe).GetMethod("ReferenceOnly")
    if method == null || method.DeclaringType == null {
        throw new InvalidOperationException("Constraint extension probe method not found")
    }

    parameterTypes := new Type[](1)
    parameterTypes[0] = method.GetParameters()[0].ParameterType
    return new ColumnarExtensionMethodCandidate(method, method.DeclaringType, parameterTypes, method.ReturnType)
}

test "extension inference declines a source struct for a class-constrained receiver" {
    sourceStruct := ConstraintProbeSourceType(true)
    sourceClass := ConstraintProbeSourceType(false)
    candidate := ConstraintExtensionProbeCandidate()
    noArguments := new Type[](0)
    noFacts := ColumnarDirectCallArgumentFacts.Empty(0)
    structTypeArguments := GenericMethodTypes1(sourceStruct)
    classTypeArguments := GenericMethodTypes1(sourceClass)

    assert ColumnarExtensionMethodResolver.ResolveCandidateShape(candidate, sourceStruct, noArguments, noFacts, 0) == null
    assert ColumnarExtensionMethodResolver.ResolveCandidateShape(candidate, sourceClass, noArguments, noFacts, 0) != null
    assert ColumnarExtensionMethodResolver.CloseExplicitOrNull(candidate, sourceStruct, structTypeArguments) == null
    assert ColumnarExtensionMethodResolver.CloseExplicitOrNull(candidate, sourceClass, classTypeArguments) != null
}

func NullExpandedExtensionProbeMethod(): MethodInfo {
    identity := "NullExpandedExtensionProbe" + Guid.NewGuid().ToString("N")
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(identity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(identity)
    owner := module.DefineType(identity, TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed)
    methodBuilder := owner.DefineMethod("Pack", MethodAttributes.Public | MethodAttributes.Static, CallingConventions.Standard)
    methodTypeParameter := methodBuilder.DefineGenericParameters(["T"])[0]
    receiverType := typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(GenericMethodTypes1(methodTypeParameter))
    methodBuilder.SetReturnType(typeof(int))
    methodBuilder.SetParameters(GenericMethodTypes2(receiverType, methodTypeParameter.MakeArrayType()))
    methodBuilder.DefineParameter(1, ParameterAttributes.None, "receiver")
    packedParameter := methodBuilder.DefineParameter(2, ParameterAttributes.None, "values")
    paramArrayConstructor := typeof(ParamArrayAttribute).GetConstructor(Type.EmptyTypes)
    if paramArrayConstructor == null {
        throw new InvalidOperationException("ParamArrayAttribute constructor not found")
    }
    packedParameter.SetCustomAttribute(new CustomAttributeBuilder(paramArrayConstructor, new object[](0)))
    il := methodBuilder.GetILGenerator()
    il.Emit(OpCodes.Ldc_I4_0)
    il.Emit(OpCodes.Ret)

    createdOwner := owner.CreateType()
    method := createdOwner.GetMethod("Pack")
    if method == null {
        throw new InvalidOperationException("Dynamic expanded-extension probe method not found")
    }
    return method
}

test "expanded extension inference skips a null literal after binding from the receiver" {
    method := NullExpandedExtensionProbeMethod()
    if method.DeclaringType == null {
        throw new InvalidOperationException("Null expansion probe method did not retain its declaring type")
    }

    parameters := method.GetParameters()
    assert method.IsGenericMethodDefinition, "the params probe must remain an open generic definition"
    assert parameters.Length == 2, "the extension shape has a receiver and a params slot"
    assert ColumnarExtensionMethodResolver.IsParamsParameter(parameters[1]), "the final slot must carry ParamArrayAttribute"
    parameterTypes := new Type[](parameters.Length)
    index := 0
    while index < parameters.Length {
        parameterTypes[index] = parameters[index].ParameterType
        index = index + 1
    }
    candidate := new ColumnarExtensionMethodCandidate(method, method.DeclaringType, parameterTypes, method.ReturnType)
    argumentTypes := new Type[](1)
    argumentTypes[0] = typeof(object)
    facts := ColumnarDirectCallArgumentFacts.Empty(1)
    facts.IsNullLiteral[0] = true

    callTypes := new Type[](2)
    callTypes[0] = typeof(List<int>)
    callTypes[1] = typeof(object)
    callFacts := ColumnarDirectCallArgumentFacts.Empty(2)
    callFacts.IsNullLiteral[1] = true
    sharedInference := ColumnarRuntimeGenericMethodResolver.InferAndClose(method, callTypes, callFacts, true, false)
    assert sharedInference != null, "the shared expanded inference loop must bind T from the receiver and skip the packed null literal"
    assert sharedInference.ParameterTypes[1] == typeof(int[]), "the shared closure must substitute T in the params array"

    expanded := ColumnarExtensionMethodResolver.ResolveExpandedShape(candidate, typeof(List<int>), argumentTypes, facts)
    assert expanded != null, "the receiver must bind T before the packed null literal is skipped"
    assert expanded.ParameterTypes[1] == typeof(int[]), "the closed params parameter must use the receiver's int type"
}

// These overload pairs isolate the cross-tier tie-break used after both resolvers have independently
// found an applicable candidate. List<string> converts by reference to both `IEnumerable<string>`
// and `object`; the first target is more specific. `Identical<T>(object)` closes to the same parameter
// list as the non-generic overload, where the non-generic member wins.
class CrossTierOverloadProbe {
    static func Choose<T>(_values: IEnumerable<T>): int {
        return 1
    }

    static func Choose(_values: object): int {
        return 2
    }

    static func Optional<T>(_values: IEnumerable<T>, _mode: string? = null): int {
        return 1
    }

    static func Optional(_values: object, _mode: string? = null): int {
        return 2
    }

    static func Identical<T>(_value: T): int {
        return 1
    }

    static func Identical(_value: object): int {
        return 2
    }
}

interface CrossTierLeftTarget {
}

interface CrossTierRightTarget {
}

class CrossTierBothTargets: CrossTierLeftTarget, CrossTierRightTarget {
}

class CrossTierOnlyLeftTarget: CrossTierLeftTarget {
}

class CrossTierIncomparableProbe {
    static func Choose<T>(_value: CrossTierLeftTarget, _witness: T): int {
        return 1
    }

    static func Choose(_value: CrossTierRightTarget, _witness: string): int {
        return 2
    }
}

class CrossTierDominatingCandidateProbe {
    static func Pick<T>(_value: CrossTierLeftTarget, _witness: T): int {
        return 1
    }

    static func Pick<T>(_value: CrossTierRightTarget, _witness: T): int {
        return 2
    }

    static func Pick(_value: CrossTierBothTargets, _witness: object): int {
        return 3
    }
}

class CrossTierOptionalArityProbe {
    static func Optional<T>(_value: T, _first: string? = null): int {
        return 1
    }

    static func Optional(_value: object, _first: string? = null, _second: string? = null): int {
        return 2
    }
}

class CrossTierOptionalIdenticalProbe {
    static func Optional<T>(_value: T, _mode: string? = null): int {
        return 1
    }

    static func Optional(_value: object, _mode: string? = null): int {
        return 2
    }
}

class CrossTierOptionalExactProbe {
    static func Pick<T>(_expected: T, _actual: T, _mode: string? = null): int {
        return 1
    }

    static func Pick(_expected: string, _actual: string): int {
        return 2
    }
}

func CrossTierExpandedArityProbeType(): Type {
    identity := "CrossTierExpandedArityProbe" + Guid.NewGuid().ToString("N")
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(identity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(identity)
    owner := module.DefineType(identity, TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed)
    paramArrayConstructor := typeof(ParamArrayAttribute).GetConstructor(Type.EmptyTypes)
    if paramArrayConstructor == null {
        throw new InvalidOperationException("ParamArrayAttribute constructor not found")
    }

    generic := owner.DefineMethod("Expanded", MethodAttributes.Public | MethodAttributes.Static, CallingConventions.Standard)
    methodTypeParameter := generic.DefineGenericParameters(["T"])[0]
    generic.SetReturnType(typeof(int))
    generic.SetParameters(GenericMethodTypes3(methodTypeParameter, methodTypeParameter, typeof(object[])))
    generic.DefineParameter(1, ParameterAttributes.None, "first")
    generic.DefineParameter(2, ParameterAttributes.None, "second")
    genericTail := generic.DefineParameter(3, ParameterAttributes.None, "rest")
    genericTail.SetCustomAttribute(new CustomAttributeBuilder(paramArrayConstructor, new object[](0)))
    genericIl := generic.GetILGenerator()
    genericIl.Emit(OpCodes.Ldc_I4_1)
    genericIl.Emit(OpCodes.Ret)

    nonGeneric := owner.DefineMethod("Expanded", MethodAttributes.Public | MethodAttributes.Static, CallingConventions.Standard)
    nonGeneric.SetReturnType(typeof(int))
    nonGeneric.SetParameters(GenericMethodTypes2(typeof(object), typeof(object[])))
    nonGeneric.DefineParameter(1, ParameterAttributes.None, "first")
    nonGenericTail := nonGeneric.DefineParameter(2, ParameterAttributes.None, "rest")
    nonGenericTail.SetCustomAttribute(new CustomAttributeBuilder(paramArrayConstructor, new object[](0)))
    nonGenericIl := nonGeneric.GetILGenerator()
    nonGenericIl.Emit(OpCodes.Ldc_I4_2)
    nonGenericIl.Emit(OpCodes.Ret)

    createdOwner := owner.CreateType()
    if createdOwner == null {
        throw new InvalidOperationException("Expanded cross-tier probe type was not created")
    }
    return createdOwner
}

class CrossTierGenericAmbiguityProbe {
    static func OptionalChoose<T>(_value: IComparable<T>, _witness: T, _mode: string? = null): int {
        return 1
    }

    static func OptionalChoose<T>(_value: IFormattable, _witness: T, _mode: string? = null): int {
        return 2
    }

    static func OptionalChoose(_value: object, _witness: int, _mode: string? = null): int {
        return 3
    }
}

class InferenceBoundsProbe {
    static func Invariant<T>(_left: List<T>, _right: List<T>): bool {
        return _left.Count == _right.Count
    }
}

class NullableInferenceProbe {
    static func Last<T>(_left: T, right: T): T {
        return right
    }
}

enum InferenceLevel {
    Low,
    High
}

func CrossTierMethodOrThrow(method: MethodInfo?): MethodInfo {
    if method == null {
        throw new InvalidOperationException("A selected cross-tier candidate did not carry a method")
    }
    return method
}

test "more-specific generic parameter types win normal and optional cross-tier comparisons" {
    owner := typeof(CrossTierOverloadProbe)
    argumentTypes := new Type[](1)
    argumentTypes[0] = typeof(List<string>)
    facts := ColumnarDirectCallArgumentFacts.Empty(1)

    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    normalGeneric := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(owner, "Choose", argumentTypes, facts, true)
    assert normalGeneric.IsSelected, "the generic interface overload should infer string from List<string>"
    normalBest := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Choose", argumentTypes, facts, true, candidates)
    assert CrossTierMethodOrThrow(normalBest.Method).IsGenericMethod, "the more-specific IEnumerable<string> parameter should win"
    runtimeArguments := new object?[](1)
    runtimeArguments[0] = new List<string>()
    runtimeValue := CrossTierMethodOrThrow(normalBest.Method).Invoke(null, runtimeArguments)
    assert Convert.ToInt32(runtimeValue) == 1, "the selected generic overload must produce its runtime marker"

    optionalNonGeneric := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFill(owner, "Optional", argumentTypes, facts, true)
    optionalGeneric := ColumnarRuntimeGenericMethodResolver.ResolveOptionalFill(owner, "Optional", argumentTypes, facts, true)
    assert optionalNonGeneric.IsSelected, "object optional overload should be viable"
    assert optionalGeneric.IsSelected, "generic interface optional overload should infer string"
    optionalBest := ColumnarRuntimeGenericMethodResolver.ResolveCombinedOptionalFillWithMethodCandidates(owner, "Optional", argumentTypes, facts, true, candidates)
    assert CrossTierMethodOrThrow(optionalBest.Method).IsGenericMethod, "the more-specific optional parameter should win"
    optionalRuntimeArguments := new object?[](2)
    optionalRuntimeArguments[0] = new List<string>()
    optionalRuntimeArguments[1] = null
    optionalRuntimeValue := CrossTierMethodOrThrow(optionalBest.Method).Invoke(null, optionalRuntimeArguments)
    assert Convert.ToInt32(optionalRuntimeValue) == 1, "the selected generic optional overload must produce its runtime marker"

    tieArguments := new Type[](1)
    tieArguments[0] = typeof(object)
    tieFacts := ColumnarDirectCallArgumentFacts.Empty(1)
    tieOwner := typeof(CrossTierOptionalIdenticalProbe)
    tiedCandidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(tieOwner)
    tiedBest := ColumnarRuntimeGenericMethodResolver.ResolveCombinedOptionalFillWithMethodCandidates(tieOwner, "Optional", tieArguments, tieFacts, true, tiedCandidates)
    tiedMethod := CrossTierMethodOrThrow(tiedBest.Method)
    assert !tiedMethod.IsGenericMethod, "identical optional parameter lists prefer the non-generic method"
    tiedRuntimeArguments := new object?[](2)
    tiedRuntimeArguments[0] = new object()
    tiedRuntimeArguments[1] = null
    tiedRuntimeValue := tiedMethod.Invoke(null, tiedRuntimeArguments)
    assert Convert.ToInt32(tiedRuntimeValue) == 2, "the non-generic optional tie-break must reach its runtime body"
}

test "optional cross-tier candidates with differing omitted-tail lengths are ambiguous" {
    owner := typeof(CrossTierOptionalArityProbe)
    argumentTypes := new Type[](1)
    argumentTypes[0] = typeof(object)
    facts := ColumnarDirectCallArgumentFacts.Empty(1)

    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    best := ColumnarRuntimeGenericMethodResolver.ResolveCombinedOptionalFillWithMethodCandidates(owner, "Optional", argumentTypes, facts, true, candidates)
    assert best.IsAmbiguous, "different optional parameter counts do not satisfy the non-generic tie-break"
}

test "expanded cross-tier ties apply the non-generic preference before declared parameter count" {
    owner := CrossTierExpandedArityProbeType()
    argumentTypes := new Type[](2)
    argumentTypes[0] = typeof(object)
    argumentTypes[1] = typeof(object)
    facts := ColumnarDirectCallArgumentFacts.Empty(2)

    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    nonGeneric := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveExpandedWithFacts(owner, "Expanded", argumentTypes, facts, true)
    generic := ColumnarRuntimeGenericMethodResolver.ResolveExpanded(owner, "Expanded", argumentTypes, facts, true)
    assert nonGeneric.IsSelected, "the non-generic params method should be selected by the expanded resolver"
    assert nonGeneric.IsExpanded, "the non-generic params method should apply in expanded form"
    assert generic.IsSelected, "the generic params method should be selected by the expanded resolver"
    assert generic.IsExpanded, "the generic params method should apply in expanded form"
    best := ColumnarRuntimeGenericMethodResolver.ResolveCombinedExpandedWithMethodCandidates(owner, "Expanded", argumentTypes, facts, true, candidates)
    method := CrossTierMethodOrThrow(best.Method)
    assert !method.IsGenericMethod, "with identical supplied parameter types and usage counts, C# prefers the non-generic member before declared parameter count"

    runtimeArguments := new object?[](2)
    runtimeArguments[0] = new object()
    runtimeArguments[1] = new object[](1)
    runtimeValue := method.Invoke(null, runtimeArguments)
    assert Convert.ToInt32(runtimeValue) == 2, "the non-generic overload must produce its runtime marker"
}

test "generic optional-family ambiguity remains ambiguous across the non-generic tier" {
    owner := typeof(CrossTierGenericAmbiguityProbe)
    argumentTypes := new Type[](2)
    argumentTypes[0] = typeof(int)
    argumentTypes[1] = typeof(int)
    facts := ColumnarDirectCallArgumentFacts.Empty(2)

    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    nonGeneric := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFill(owner, "OptionalChoose", argumentTypes, facts, true)
    generic := ColumnarRuntimeGenericMethodResolver.ResolveOptionalFill(owner, "OptionalChoose", argumentTypes, facts, true)
    assert nonGeneric.IsSelected, "the non-generic fallback should be viable"
    assert generic.IsAmbiguous, "the incomparable generic pair should retain its ambiguity state"
    best := ColumnarRuntimeGenericMethodResolver.ResolveCombinedOptionalFillWithMethodCandidates(owner, "OptionalChoose", argumentTypes, facts, true, candidates)
    assert best.IsAmbiguous, "an applicable non-generic candidate must not erase the generic-family ambiguity"
}

test "identical closed parameter lists prefer the non-generic candidate" {
    owner := typeof(CrossTierOverloadProbe)
    argumentTypes := new Type[](1)
    argumentTypes[0] = typeof(object)
    facts := ColumnarDirectCallArgumentFacts.Empty(1)

    nonGeneric := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(owner, "Identical", argumentTypes, facts, true)
    generic := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(owner, "Identical", argumentTypes, facts, true)
    assert nonGeneric.IsSelected, "the non-generic overload should be viable"
    assert generic.IsSelected, "the generic overload should be viable"
    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    best := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Identical", argumentTypes, facts, true, candidates)
    method := CrossTierMethodOrThrow(best.Method)
    assert !method.IsGenericMethod, "identical effective parameter lists prefer the non-generic member"
    runtimeArguments := new object?[](1)
    runtimeArguments[0] = new object()
    runtimeValue := method.Invoke(null, runtimeArguments)
    assert Convert.ToInt32(runtimeValue) == 2, "the selected non-generic method must produce its runtime marker"
}

test "incomparable generic and non-generic candidates remain ambiguous" {
    owner := typeof(CrossTierIncomparableProbe)
    argumentTypes := new Type[](2)
    argumentTypes[0] = typeof(CrossTierBothTargets)
    argumentTypes[1] = typeof(string)
    facts := ColumnarDirectCallArgumentFacts.Empty(2)

    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    nonGeneric := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(owner, "Choose", argumentTypes, facts, true)
    generic := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(owner, "Choose", argumentTypes, facts, true)
    assert generic.IsSelected
    best := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Choose", argumentTypes, facts, true, candidates)
    assert best.IsAmbiguous, "C# reports this cross-tier pair as ambiguous"
}

test "a better non-generic member removes an ambiguous generic subset" {
    owner := typeof(CrossTierDominatingCandidateProbe)
    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    argumentTypes := new Type[](2)
    argumentTypes[0] = typeof(CrossTierBothTargets)
    argumentTypes[1] = typeof(object)
    facts := ColumnarDirectCallArgumentFacts.Empty(2)

    genericOnly := ColumnarRuntimeGenericMethodResolver.ResolveWithMethodCandidates(owner, "Pick", argumentTypes, facts, true, candidates)
    assert genericOnly.IsAmbiguous, "the two interface overloads are incomparable when considered alone"
    genericCandidates := new List<MethodInfo>()
    for candidate in candidates {
        if candidate.IsGenericMethodDefinition {
            genericCandidates.Add(candidate)
        }
    }
    genericCombined := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Pick", argumentTypes, facts, true, genericCandidates.ToArray())
    assert genericCombined.IsAmbiguous, "without the concrete candidate, the combined applicable set remains ambiguous"

    combined := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Pick", argumentTypes, facts, true, candidates)
    assert combined.IsSelected, "the concrete overload is better than both generic candidates"
    selectedMethod := CrossTierMethodOrThrow(combined.Method)
    runtimeArguments := new object?[](2)
    runtimeArguments[0] = new CrossTierBothTargets()
    runtimeArguments[1] = new object()
    runtimeValue := selectedMethod.Invoke(null, runtimeArguments)
    assert Convert.ToInt32(runtimeValue) == 3, "the maximal non-generic candidate must reach its runtime body"

    // Remove the concrete target from the receiver shape. Only the left generic candidate then
    // applies, while a call with the original both-interface type and only the generic family is
    // still ambiguous. These controls prove that the combined set filters applicability before
    // reducing it.
    leftArgumentTypes := new Type[](2)
    leftArgumentTypes[0] = typeof(CrossTierOnlyLeftTarget)
    leftArgumentTypes[1] = typeof(object)
    leftOnly := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Pick", leftArgumentTypes, facts, true, candidates)
    assert leftOnly.IsSelected
    leftMethod := CrossTierMethodOrThrow(leftOnly.Method)
    leftRuntimeArguments := new object?[](2)
    leftRuntimeArguments[0] = new CrossTierOnlyLeftTarget()
    leftRuntimeArguments[1] = new object()
    leftValue := leftMethod.Invoke(null, leftRuntimeArguments)
    assert Convert.ToInt32(leftValue) == 1, "the remaining applicable generic overload must retain its runtime result"
}

test "combined Task.WhenAll candidates retain the typed array overload and runtime values" {
    owner := typeof(Task)
    argumentTypes := GenericMethodTypes1(typeof(Task<int>[]))
    facts := ColumnarDirectCallArgumentFacts.Empty(1)
    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    genericSelection := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(owner, "WhenAll", argumentTypes, facts, true)
    assert genericSelection.IsSelected, "the generic-only resolver should close Task.WhenAll for Task<int>[]"
    genericCandidates := new List<MethodInfo>()
    for candidate in candidates {
        if candidate.IsGenericMethodDefinition {
            genericCandidates.Add(candidate)
        }
    }
    genericCombined := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "WhenAll", argumentTypes, facts, true, genericCandidates.ToArray())
    assert genericCombined.IsSelected, "generic combined status: " + Convert.ToString(genericCombined.Status)
    selection := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "WhenAll", argumentTypes, facts, true, candidates)
    assert selection.IsSelected, "combined selection status: " + Convert.ToString(selection.Status)
    method := CrossTierMethodOrThrow(selection.Method)
    assert method.IsGenericMethod, "the typed Task<T>[] argument must prefer the generic method"
    runtimeArguments := new object?[](1)
    tasks: Task<int>[] = [Task.FromResult(4), Task.FromResult(5)]
    runtimeArguments[0] = tasks
    runtimeTask := method.Invoke(null, runtimeArguments) as Task<int[]>
    assert runtimeTask != null, "the selected overload returns Task<int[]>"
    assert runtimeTask.Result.Length == 2 && runtimeTask.Result[1] == 5, "the selected overload returns both typed results"

    controlTypes := GenericMethodTypes1(typeof(Task[]))
    control := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "WhenAll", controlTypes, facts, true, candidates)
    assert control.IsSelected && !CrossTierMethodOrThrow(control.Method).IsGenericMethod, "an untyped Task[] remains on the non-generic overload"
}

test "combined exact-arity member outranks optional generic member and keeps runtime value" {
    owner := typeof(CrossTierOptionalExactProbe)
    arguments := GenericMethodTypes2(typeof(string), typeof(string))
    facts := ColumnarDirectCallArgumentFacts.Empty(2)
    candidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    genericCandidates := new List<MethodInfo>()
    nonGenericCandidates := new List<MethodInfo>()
    for candidate in candidates {
        if candidate.Name == "Pick" {
            if candidate.IsGenericMethodDefinition {
                genericCandidates.Add(candidate)
            } else {
                nonGenericCandidates.Add(candidate)
            }
        }
    }

    genericOnly := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Pick", arguments, facts, true, genericCandidates.ToArray())
    assert genericOnly.IsSelected, "the generic optional overload remains applicable by itself"
    genericMethod := CrossTierMethodOrThrow(genericOnly.Method)
    assert genericMethod.IsGenericMethod
    genericRuntimeArguments := new object?[](3)
    genericRuntimeArguments[0] = "same"
    genericRuntimeArguments[1] = "same"
    genericRuntimeArguments[2] = null
    genericRuntimeValue := genericMethod.Invoke(null, genericRuntimeArguments)
    assert Convert.ToInt32(genericRuntimeValue) == 1, "the generic-only control reaches its runtime body"

    nonGenericOnly := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidatesWithFacts(owner, "Pick", arguments, facts, true, nonGenericCandidates.ToArray())
    assert nonGenericOnly.IsSelected, "the exact non-generic overload is applicable alone"
    nonGenericMethod := nonGenericOnly.Method
    assert nonGenericMethod != null && !nonGenericMethod.IsGenericMethod
    nonGenericRuntimeArguments := new object?[](2)
    nonGenericRuntimeArguments[0] = "same"
    nonGenericRuntimeArguments[1] = "same"
    nonGenericRuntimeValue := nonGenericMethod.Invoke(null, nonGenericRuntimeArguments)
    assert Convert.ToInt32(nonGenericRuntimeValue) == 2, "the non-generic-only control reaches its runtime body"

    combined := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Pick", arguments, facts, true, candidates)
    assert combined.IsSelected, "the exact-arity candidate removes the optional candidate before the non-generic tie-break"
    selectedMethod := CrossTierMethodOrThrow(combined.Method)
    assert !selectedMethod.IsGenericMethod && selectedMethod.GetParameters().Length == 2
    runtimeValue := selectedMethod.Invoke(null, nonGenericRuntimeArguments)
    assert Convert.ToInt32(runtimeValue) == 2, "the exact-arity winner reaches its runtime body"
}

test "combined normal and expanded candidates compare conversions before params form" {
    owner := typeof(string)
    factsOne := ColumnarDirectCallArgumentFacts.Empty(2)
    oneArgumentTypes := GenericMethodTypes2(typeof(string), typeof(string))
    oneSelection := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Join", oneArgumentTypes, factsOne, true, ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner))
    assert oneSelection.IsSelected, "the one-value Join candidates have an applicable member"
    oneMethod := CrossTierMethodOrThrow(oneSelection.Method)
    assert !oneMethod.IsGenericMethod && oneSelection.IsExpanded, "the identity conversion to the string params element beats the generic IEnumerable<char> conversion"
    oneRuntimeArguments := new object?[](2)
    oneRuntimeArguments[0] = "|"
    oneValues := new string[](1)
    oneValues[0] = "only"
    oneRuntimeArguments[1] = oneValues
    oneRuntimeValue := oneMethod.Invoke(null, oneRuntimeArguments)
    assert Convert.ToString(oneRuntimeValue) == "only", "the expanded string params overload returns the single string unchanged"

    packedTypes := new Type[](4)
    packedTypes[0] = typeof(string)
    packedTypes[1] = typeof(string)
    packedTypes[2] = typeof(string)
    packedTypes[3] = typeof(string)
    factsPacked := ColumnarDirectCallArgumentFacts.Empty(4)
    packedSelection := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Join", packedTypes, factsPacked, true, ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner))
    assert packedSelection.IsSelected && packedSelection.IsExpanded, "a multi-value call selects an expanded params candidate"
    packedMethod := CrossTierMethodOrThrow(packedSelection.Method)
    assert !packedMethod.IsGenericMethod && packedMethod.GetParameters()[1].ParameterType == typeof(string[]), "the packed overload keeps its declared string array"
    packedRuntimeArguments := new object?[](2)
    packedRuntimeArguments[0] = ","
    packedValues := new string[](3)
    packedValues[0] = "x"
    packedValues[1] = "y"
    packedValues[2] = "z"
    packedRuntimeArguments[1] = packedValues
    packedRuntimeValue := packedMethod.Invoke(null, packedRuntimeArguments)
    assert Convert.ToString(packedRuntimeValue) == "x,y,z", "the params array reaches the runtime method in order"

    builtArrayTypes := GenericMethodTypes2(typeof(string), typeof(string[]))
    builtArray := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Join", builtArrayTypes, ColumnarDirectCallArgumentFacts.Empty(2), true, ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner))
    assert builtArray.IsSelected && !builtArray.IsExpanded, "an existing array remains a normal-form argument"
    builtArrayMethod := CrossTierMethodOrThrow(builtArray.Method)
    builtArrayRuntimeArguments := new object?[](2)
    builtArrayRuntimeArguments[0] = "+"
    builtArrayValues := new string[](2)
    builtArrayValues[0] = "m"
    builtArrayValues[1] = "n"
    builtArrayRuntimeArguments[1] = builtArrayValues
    builtArrayRuntimeValue := builtArrayMethod.Invoke(null, builtArrayRuntimeArguments)
    assert Convert.ToString(builtArrayRuntimeValue) == "m+n", "the normal-form array control retains its runtime result"
}

test "repeated generic parameters accumulate lower bounds and preserve invariant conflicts" {
    enumerableObject := typeof(IEnumerable<object>)
    containsArguments := new Type[](2)
    containsArguments[0] = enumerableObject
    containsArguments[1] = typeof(string)
    facts := ColumnarDirectCallArgumentFacts.Empty(2)

    contains := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(typeof(Enumerable), "Contains", containsArguments, facts, true)
    assert contains.IsSelected, "string is a lower bound that converts to the object bound from IEnumerable<object>"
    containsMethod := CrossTierMethodOrThrow(contains.Method)
    runtimeArguments := new object?[](2)
    values := new List<object>()
    values.Add("found")
    runtimeArguments[0] = values
    runtimeArguments[1] = "found"
    runtimeValue := containsMethod.Invoke(null, runtimeArguments)
    assert Convert.ToBoolean(runtimeValue), "the fixed TSource=object call must find the string value"

    invariantArguments := new Type[](2)
    invariantArguments[0] = typeof(List<object>)
    invariantArguments[1] = typeof(List<string>)
    invariant := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(typeof(InferenceBoundsProbe), "Invariant", invariantArguments, facts, true)
    assert !invariant.IsSelected, "invariant List<T> positions cannot merge distinct exact type bounds"
}

test "nullable lifted bounds fix a repeated type parameter to the nullable type" {
    facts := ColumnarDirectCallArgumentFacts.Empty(2)
    plainFirstTypes := GenericMethodTypes2(typeof(int), typeof(int?))
    plainFirst := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(
        typeof(NullableInferenceProbe),
        "Last",
        plainFirstTypes,
        facts,
        true
    )
    assert plainFirst.IsSelected, "int and int? must fix T to int?"
    plainFirstMethod := CrossTierMethodOrThrow(plainFirst.Method)
    assert plainFirstMethod.GetGenericArguments()[0] == typeof(int?)
    plainFirstArguments := new object?[](2)
    plainFirstArguments[0] = 7
    plainFirstArguments[1] = null
    assert plainFirstMethod.Invoke(null, plainFirstArguments) == null, "the selected Nullable<int> method must carry a null value"

    liftedFirstTypes := GenericMethodTypes2(typeof(int?), typeof(int))
    liftedFirst := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(
        typeof(NullableInferenceProbe),
        "Last",
        liftedFirstTypes,
        facts,
        true
    )
    assert liftedFirst.IsSelected, "the reversed bound order must also fix T to int?"
    liftedFirstMethod := CrossTierMethodOrThrow(liftedFirst.Method)
    assert liftedFirstMethod.GetGenericArguments()[0] == typeof(int?)
    liftedFirstArguments := new object?[](2)
    liftedFirstArguments[0] = null
    liftedFirstArguments[1] = 9
    assert Convert.ToInt32(liftedFirstMethod.Invoke(null, liftedFirstArguments)) == 9

    enumTypes := GenericMethodTypes2(typeof(InferenceLevel), typeof(InferenceLevel?))
    enumSelection := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(
        typeof(NullableInferenceProbe),
        "Last",
        enumTypes,
        facts,
        true
    )
    assert enumSelection.IsSelected, "an enum and Nullable<enum> must fix T to Nullable<enum>"
    enumMethod := CrossTierMethodOrThrow(enumSelection.Method)
    assert enumMethod.GetGenericArguments()[0] == typeof(InferenceLevel?)
    enumArguments := new object?[](2)
    enumArguments[0] = InferenceLevel.High
    enumArguments[1] = null
    assert enumMethod.Invoke(null, enumArguments) == null

    sourceEnum := AdmissibilityEnumBuilder()
    sourceNullableEnum := typeof(Nullable<int>).GetGenericTypeDefinition().MakeGenericType(GenericMethodTypes1(sourceEnum))
    sourceTypes := GenericMethodTypes2(sourceEnum, sourceNullableEnum)
    sourceSelection := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(
        typeof(NullableInferenceProbe),
        "Last",
        sourceTypes,
        facts,
        true
    )
    assert sourceSelection.IsSelected, "a source enum and Nullable<source enum> must preserve the nullable-lift bound"
    sourceMethod := CrossTierMethodOrThrow(sourceSelection.Method)
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(
        sourceMethod.GetGenericArguments()[0],
        sourceNullableEnum
    )

    invalid := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(
        typeof(NullableInferenceProbe),
        "Last",
        GenericMethodTypes2(typeof(int), typeof(string)),
        facts,
        true
    )
    assert !invalid.IsSelected
}

test "generic Array overloads beat the broader non-generic overloads" {
    owner := typeof(Array)
    facts := ColumnarDirectCallArgumentFacts.Empty(1)
    sortArguments := new Type[](1)
    sortArguments[0] = typeof(int[])

    sortGeneric := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(owner, "Sort", sortArguments, facts, true)
    assert sortGeneric.IsSelected, "Array.Sort<T>(T[]) should be viable"
    sortCandidates := ColumnarOrdinaryRuntimeDirectCallResolver.CandidateMethods(owner)
    sortBest := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "Sort", sortArguments, facts, true, sortCandidates)
    assert CrossTierMethodOrThrow(sortBest.Method).IsGenericMethod, "int[] is more specific than Array"

    indexArguments := new Type[](2)
    indexArguments[0] = typeof(int[])
    indexArguments[1] = typeof(int)
    indexFacts := ColumnarDirectCallArgumentFacts.Empty(2)
    indexGeneric := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(owner, "IndexOf", indexArguments, indexFacts, true)
    assert indexGeneric.IsSelected, "Array.IndexOf<T>(T[], T) should be viable"
    indexBest := ColumnarRuntimeGenericMethodResolver.ResolveCombinedWithMethodCandidates(owner, "IndexOf", indexArguments, indexFacts, true, sortCandidates)
    assert CrossTierMethodOrThrow(indexBest.Method).IsGenericMethod, "int[] and int are more specific than Array and object"
}

class ProtectedGenericMethodProbe {
    protected func Hidden<T>(value: T): T {
        return value
    }
}

class ProtectedGenericDerivedMethodProbe: ProtectedGenericMethodProbe {
}

test "external generic lookup does not admit a protected method inherited from a base" {
    method := typeof(ProtectedGenericDerivedMethodProbe).GetMethod("Hidden", BindingFlags.Instance | BindingFlags.NonPublic)
    assert method != null
    assert !method.IsPublic
    assert method.DeclaringType == typeof(ProtectedGenericMethodProbe)

    selection := ColumnarExplicitRuntimeGenericMethodResolver.Resolve(
        typeof(ProtectedGenericDerivedMethodProbe),
        "Hidden",
        GenericMethodTypes1(typeof(int)),
        1,
        false
    )
    assert !selection.IsSelected
}
