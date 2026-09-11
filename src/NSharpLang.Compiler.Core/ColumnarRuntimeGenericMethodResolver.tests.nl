namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Numerics
import System.Reflection
import System.Reflection.Emit

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

// CONSTRAINTS ARE ENFORCED BY `MakeGenericMethod`, so a violated one drops the candidate here rather
// than throwing at emit. `Enum.Parse<TEnum>(string) where TEnum : struct, Enum` takes an enum and
// nothing else.
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
