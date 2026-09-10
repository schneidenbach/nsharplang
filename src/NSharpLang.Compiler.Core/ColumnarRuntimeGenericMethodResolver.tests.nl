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
