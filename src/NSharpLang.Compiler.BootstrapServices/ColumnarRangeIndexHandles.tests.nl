namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection

func RangeHandleGenericParameter(): Type {
    definition := typeof(System.Array).GetMethod("Empty")
    if definition == null {
        throw new InvalidOperationException("Required generic-parameter probe was not found.")
    }
    parameterType := definition.get_ReturnType().GetElementType()
    if parameterType == null {
        throw new InvalidOperationException("Required generic parameter type was not found.")
    }
    return parameterType
}

test "range handle owner selects exact CLR members" {
    handles := ColumnarRangeIndexHandles.Resolve()
    assert handles.IndexConstructor.get_DeclaringType() == typeof(Index)
    assert handles.IndexGetOffset.get_DeclaringType() == typeof(Index)
    assert handles.RangeConstructor.get_DeclaringType() == typeof(Range)
    assert handles.RangeGetOffsetAndLength.get_DeclaringType() == typeof(Range)
    assert handles.StringLengthGetter.get_DeclaringType() == typeof(string)
    assert handles.StringCharsGetter.get_DeclaringType() == typeof(string)
    assert handles.StringSubstring.get_DeclaringType() == typeof(string)
    assert handles.TupleItem1.get_DeclaringType() == typeof(ValueTuple<int, int>)
    assert handles.TupleItem2.get_DeclaringType() == typeof(ValueTuple<int, int>)
    assert handles.GetSubArrayDefinition.get_IsGenericMethodDefinition()
}

test "range handle owner validates each closed GetSubArray element identity" {
    handles := ColumnarRangeIndexHandles.Resolve()

    stringMethod := handles.CloseGetSubArray(typeof(string))
    stringParameters := stringMethod.GetParameters()
    assert !stringMethod.get_IsGenericMethodDefinition()
    assert stringMethod.get_ReturnType() == typeof(string[])
    assert stringParameters.Length == 2
    assert stringParameters[0].get_ParameterType() == typeof(string[])
    assert stringParameters[1].get_ParameterType() == typeof(Range)

    genericParameter := RangeHandleGenericParameter()
    genericMethod := handles.CloseGetSubArray(genericParameter)
    genericArray := genericParameter.MakeArrayType()
    genericParameters := genericMethod.GetParameters()
    assert genericParameter.get_IsGenericParameter()
    assert !genericMethod.get_IsGenericMethodDefinition()
    assert genericMethod.get_ReturnType() == genericArray
    assert genericParameters[0].get_ParameterType() == genericArray
    assert genericParameters[1].get_ParameterType() == typeof(Range)
}

test "range handle owner rejects foreign generic definitions and null elements" {
    handles := ColumnarRangeIndexHandles.Resolve()
    foreignDefinition := typeof(System.Array).GetMethod("Empty")
    if foreignDefinition == null {
        throw new InvalidOperationException("Required foreign generic definition was not found.")
    }

    assert throws InvalidOperationException {
        _rejected := new ColumnarRangeIndexHandles(
            handles.IndexConstructor,
            handles.IndexGetOffset,
            handles.RangeConstructor,
            handles.RangeGetOffsetAndLength,
            foreignDefinition,
            handles.StringLengthGetter,
            handles.StringCharsGetter,
            handles.StringSubstring,
            handles.TupleItem1,
            handles.TupleItem2)
    }
    assert throws InvalidOperationException { handles.CloseGetSubArray(null) }
}
