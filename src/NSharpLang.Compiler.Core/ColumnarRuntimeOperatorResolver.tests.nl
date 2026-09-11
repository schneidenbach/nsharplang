namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Numerics
import System.Reflection
import System.Reflection.Emit

// The runtime operator resolver's selection contract. `System.Numerics.Vector<T>` is the witness for
// constructed external generics precisely because nothing in the resolver names it; `DateTime`,
// `TimeSpan` and `decimal` witness the same lookup on non-generic external types.
func RuntimeOperatorRequiredMethod(selection: ColumnarRuntimeOperatorSelection): MethodInfo {
    method := selection.Method
    if method == null {
        throw new InvalidOperationException("A selected runtime operator must carry a method handle.")
    }
    return method
}

test "runtime operator resolver selects binary operators on a constructed external generic type" {
    vector := typeof(Vector<int>)
    addition := ColumnarRuntimeOperatorResolver.ResolveBinary("+", vector, vector)
    assert addition.IsSelected
    additionMethod := RuntimeOperatorRequiredMethod(addition)
    assert additionMethod.get_Name() == "op_Addition"
    assert additionMethod.get_DeclaringType() == vector
    assert addition.ParameterTypes.Length == 2
    assert addition.ParameterTypes[0] == vector
    assert addition.ParameterTypes[1] == vector
    assert addition.ReturnType == vector

    subtraction := ColumnarRuntimeOperatorResolver.ResolveBinary("-", vector, vector)
    assert RuntimeOperatorRequiredMethod(subtraction).get_Name() == "op_Subtraction"

    bitwiseAnd := ColumnarRuntimeOperatorResolver.ResolveBinary("&", vector, vector)
    assert RuntimeOperatorRequiredMethod(bitwiseAnd).get_Name() == "op_BitwiseAnd"
    assert bitwiseAnd.ReturnType == vector

    bitwiseOr := ColumnarRuntimeOperatorResolver.ResolveBinary("|", vector, vector)
    assert RuntimeOperatorRequiredMethod(bitwiseOr).get_Name() == "op_BitwiseOr"

    exclusiveOr := ColumnarRuntimeOperatorResolver.ResolveBinary("^", vector, vector)
    assert RuntimeOperatorRequiredMethod(exclusiveOr).get_Name() == "op_ExclusiveOr"

    equality := ColumnarRuntimeOperatorResolver.ResolveBinary("==", vector, vector)
    assert RuntimeOperatorRequiredMethod(equality).get_Name() == "op_Equality"
    assert equality.ReturnType == typeof(bool)

    inequality := ColumnarRuntimeOperatorResolver.ResolveBinary("!=", vector, vector)
    assert RuntimeOperatorRequiredMethod(inequality).get_Name() == "op_Inequality"
    assert inequality.ReturnType == typeof(bool)
}

test "runtime operator resolver selects unary operators on a constructed external generic type" {
    vector := typeof(Vector<int>)
    complement := ColumnarRuntimeOperatorResolver.ResolveUnary("~", vector)
    assert complement.IsSelected
    complementMethod := RuntimeOperatorRequiredMethod(complement)
    assert complementMethod.get_Name() == "op_OnesComplement"
    assert complement.ParameterTypes.Length == 1
    assert complement.ParameterTypes[0] == vector
    assert complement.ReturnType == vector

    negation := ColumnarRuntimeOperatorResolver.ResolveUnary("-", vector)
    assert RuntimeOperatorRequiredMethod(negation).get_Name() == "op_UnaryNegation"
    assert negation.ReturnType == vector
}

test "runtime operator resolver selects operators on non-generic external types" {
    difference := ColumnarRuntimeOperatorResolver.ResolveBinary("-", typeof(DateTime), typeof(DateTime))
    assert difference.IsSelected
    assert RuntimeOperatorRequiredMethod(difference).get_Name() == "op_Subtraction"
    assert difference.ReturnType == typeof(TimeSpan)

    // The two operand types contribute one candidate set between them: `DateTime - TimeSpan` is
    // declared on DateTime alone and is still found with a TimeSpan on the right.
    shifted := ColumnarRuntimeOperatorResolver.ResolveBinary("-", typeof(DateTime), typeof(TimeSpan))
    assert shifted.IsSelected
    assert shifted.ReturnType == typeof(DateTime)
    assert shifted.ParameterTypes[1] == typeof(TimeSpan)

    money := ColumnarRuntimeOperatorResolver.ResolveBinary("*", typeof(decimal), typeof(decimal))
    assert money.IsSelected
    assert money.ReturnType == typeof(decimal)
}

test "runtime operator resolver refuses operators the operand types do not declare" {
    vector := typeof(Vector<int>)

    // Vector<T> declares no division by another vector shape it cannot accept, and no shift by a vector.
    assert !ColumnarRuntimeOperatorResolver.ResolveBinary("+", vector, typeof(string)).IsSelected
    assert !ColumnarRuntimeOperatorResolver.ResolveBinary("+", vector, typeof(Vector<long>)).IsSelected
    assert !ColumnarRuntimeOperatorResolver.ResolveBinary("<", vector, vector).IsSelected
    assert !ColumnarRuntimeOperatorResolver.ResolveUnary("!", vector).IsSelected

    // A type with no user-defined operators at all.
    assert !ColumnarRuntimeOperatorResolver.ResolveBinary("+", typeof(object), typeof(object)).HasCandidates
    assert !ColumnarRuntimeOperatorResolver.ResolveBinary("+", typeof(List<int>), typeof(List<int>)).HasCandidates

    // A symbol that is not an operator name at all.
    assert !ColumnarRuntimeOperatorResolver.ResolveBinary("&&", vector, vector).HasCandidates
}

test "runtime operator resolver leaves the predefined IL primitive surface alone" {
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(int))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(long))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(ulong))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(uint))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(double))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(float))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(char))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(byte))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(bool))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(string))
    assert ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(ColumnarRuntimeOperatorStatus))

    assert !ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(decimal))
    assert !ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(DateTime))
    assert !ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(Vector<int>))
    assert !ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(typeof(object))
}

// THE OPERAND MAY BE A TYPE THAT IS STILL BEING EMITTED. `a == b` for a user-declared
// `Tagged<int>` reaches this question with a `TypeBuilderInstantiation`, and that shape answers
// `IsEnum` — which routes through `IsSubclassOf` — with `NotSupportedException` rather than `false`.
// A predicate that throws mid-emit is not a decline, it is a crash that takes the whole run down, so
// the enum question is asked through the guarded owner. It is the only reflection read here: every
// other arm is reference equality against a `typeof`.
test "runtime operator resolver answers the primitive question for a type that is still being emitted" {
    openDefinition: Type = TypeOfCreateBuilder("RuntimeOperatorPrimitiveProbe`1", "ColumnarRuntimeOperatorTests.PrimitiveProbe", 1)
    arguments := new Type[](1)
    arguments[0] = typeof(int)
    constructed := openDefinition.MakeGenericType(arguments)

    assert !ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(constructed)
    assert !ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(openDefinition)
}
