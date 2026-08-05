namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Runtime.CompilerServices


// The exact CLR member owner for range/index plans. Callers receive already-selected handles;
// no C# seed, reflection-order lookup, or overload scoring participates in planning.
class ColumnarRangeIndexHandles {
    IndexConstructor: ConstructorInfo
    IndexGetOffset: MethodInfo
    RangeConstructor: ConstructorInfo
    RangeGetOffsetAndLength: MethodInfo
    GetSubArrayDefinition: MethodInfo
    StringLengthGetter: MethodInfo
    StringCharsGetter: MethodInfo
    StringSubstring: MethodInfo
    TupleItem1: FieldInfo
    TupleItem2: FieldInfo

    constructor(indexConstructor: ConstructorInfo, indexGetOffset: MethodInfo, rangeConstructor: ConstructorInfo, rangeGetOffsetAndLength: MethodInfo, getSubArrayDefinition: MethodInfo, stringLengthGetter: MethodInfo, stringCharsGetter: MethodInfo, stringSubstring: MethodInfo, tupleItem1: FieldInfo, tupleItem2: FieldInfo) {
        if indexConstructor == null || indexGetOffset == null || rangeConstructor == null || rangeGetOffsetAndLength == null || getSubArrayDefinition == null || stringLengthGetter == null || stringCharsGetter == null || stringSubstring == null || tupleItem1 == null || tupleItem2 == null {
            throw new InvalidOperationException("Range/index CLR handles cannot be null.")
        }

        IndexConstructor = indexConstructor
        IndexGetOffset = indexGetOffset
        RangeConstructor = rangeConstructor
        RangeGetOffsetAndLength = rangeGetOffsetAndLength
        GetSubArrayDefinition = getSubArrayDefinition
        StringLengthGetter = stringLengthGetter
        StringCharsGetter = stringCharsGetter
        StringSubstring = stringSubstring
        TupleItem1 = tupleItem1
        TupleItem2 = tupleItem2
        ValidateGetSubArrayDefinition(GetSubArrayDefinition)
    }

    static func Resolve(): ColumnarRangeIndexHandles {
        intBool := new Type[](2)
        intBool[0] = typeof(int)
        intBool[1] = typeof(bool)
        indexConstructor := RequiredConstructor(typeof(Index), intBool, "System.Index(int,bool)")

        oneInt := new Type[](1)
        oneInt[0] = typeof(int)
        indexGetOffset := RequiredMethod(typeof(Index), "GetOffset", oneInt)

        twoIndices := new Type[](2)
        twoIndices[0] = typeof(Index)
        twoIndices[1] = typeof(Index)
        rangeConstructor := RequiredConstructor(typeof(Range), twoIndices, "System.Range(Index,Index)")
        rangeGetOffsetAndLength := RequiredMethod(typeof(Range), "GetOffsetAndLength", oneInt)

        noArguments := new Type[](0)
        stringLengthGetter := RequiredMethod(typeof(string), "get_Length", noArguments)
        stringCharsGetter := RequiredMethod(typeof(string), "get_Chars", oneInt)

        twoInts := new Type[](2)
        twoInts[0] = typeof(int)
        twoInts[1] = typeof(int)
        stringSubstring := RequiredMethod(typeof(string), "Substring", twoInts)

        tupleItem1 := RequiredField(typeof(ValueTuple<int, int>), "Item1")
        tupleItem2 := RequiredField(typeof(ValueTuple<int, int>), "Item2")

        getSubArrayDefinition := RequiredGetSubArrayDefinition()

        return new ColumnarRangeIndexHandles(indexConstructor, indexGetOffset, rangeConstructor, rangeGetOffsetAndLength, getSubArrayDefinition, stringLengthGetter, stringCharsGetter, stringSubstring, tupleItem1, tupleItem2)
    }

    func CloseGetSubArray(elementType: Type): MethodInfo {
        if elementType == null {
            throw new InvalidOperationException("GetSubArray element type cannot be null.")
        }
        ValidateGetSubArrayDefinition(GetSubArrayDefinition)
        typeArguments := new Type[](1)
        typeArguments[0] = elementType
        closed := GetSubArrayDefinition.MakeGenericMethod(typeArguments)
        ValidateClosedGetSubArray(closed, elementType)
        return closed
    }

    static func RequiredGetSubArrayDefinition(): MethodInfo {
        definition := typeof(RuntimeHelpers).GetMethod("GetSubArray")
        if definition == null {
            throw new InvalidOperationException("Required CLR method RuntimeHelpers.GetSubArray<T>(T[],Range) was not found uniquely.")
        }
        ValidateGetSubArrayDefinition(definition)
        return definition
    }

    static func ValidateGetSubArrayDefinition(definition: MethodInfo) {
        if definition.get_DeclaringType() != typeof(RuntimeHelpers) {
            throw new InvalidOperationException("GetSubArray definition must be declared by RuntimeHelpers.")
        }
        if !definition.get_IsStatic() {
            throw new InvalidOperationException("GetSubArray definition must be static.")
        }
        if !definition.get_IsGenericMethodDefinition() {
            throw new InvalidOperationException("GetSubArray handle must be a generic method definition.")
        }

        returnType := definition.get_ReturnType()
        parameters := definition.GetParameters()
        if !returnType.get_IsSZArray() {
            throw new InvalidOperationException("GetSubArray definition must return an SZ array.")
        }
        if parameters.Length != 2 {
            throw new InvalidOperationException("GetSubArray definition must have exactly two parameters.")
        }
        if !parameters[0].get_ParameterType().get_IsSZArray() {
            throw new InvalidOperationException("GetSubArray first parameter must be an SZ array.")
        }
        if parameters[1].get_ParameterType() != typeof(Range) {
            throw new InvalidOperationException("GetSubArray second parameter must be System.Range.")
        }

        returnElement := returnType.GetElementType()
        parameterElement := parameters[0].get_ParameterType().GetElementType()
        if returnElement == null || parameterElement == null {
            throw new InvalidOperationException("GetSubArray array element metadata is missing.")
        }
        if !returnElement.get_IsGenericParameter() {
            throw new InvalidOperationException("GetSubArray return element must be a generic parameter.")
        }
        if parameterElement != returnElement {
            throw new InvalidOperationException("RuntimeHelpers.GetSubArray definition does not preserve its generic array element.")
        }
    }

    static func ValidateClosedGetSubArray(method: MethodInfo, elementType: Type) {
        returnType := method.get_ReturnType()
        parameters := method.GetParameters()
        genericArguments := method.GetGenericArguments()
        if method.get_DeclaringType() != typeof(RuntimeHelpers) {
            throw new InvalidOperationException("Constructed GetSubArray owner changed.")
        }
        if !method.get_IsStatic() || method.get_IsGenericMethodDefinition() {
            throw new InvalidOperationException("Constructed GetSubArray method state is invalid.")
        }
        if genericArguments.Length != 1 || genericArguments[0] != elementType {
            throw new InvalidOperationException("Constructed GetSubArray generic argument is invalid.")
        }
        returnElement := returnType.GetElementType()
        if !returnType.get_IsSZArray() || returnElement == null || (elementType.get_IsGenericParameter() ? !returnElement.get_IsGenericParameter() : returnElement != elementType) {
            throw new InvalidOperationException("Constructed GetSubArray return type is invalid.")
        }
        if parameters.Length != 2 {
            throw new InvalidOperationException("Constructed GetSubArray parameter count is invalid.")
        }
        arrayParameterType := parameters[0].get_ParameterType()
        parameterElement := arrayParameterType.GetElementType()
        if !arrayParameterType.get_IsSZArray() || parameterElement == null || (elementType.get_IsGenericParameter() ? !parameterElement.get_IsGenericParameter() : parameterElement != elementType) {
            throw new InvalidOperationException("Constructed GetSubArray array parameter is invalid.")
        }
        if parameters[1].get_ParameterType() != typeof(Range) {
            throw new InvalidOperationException("Constructed GetSubArray range parameter is invalid.")
        }
    }

    static func RequiredConstructor(owner: Type, parameters: Type[], display: string): ConstructorInfo {
        constructor := owner.GetConstructor(parameters)
        if constructor == null {
            throw new InvalidOperationException("Required CLR constructor " + display + " was not found.")
        }
        return constructor
    }

    static func RequiredMethod(owner: Type, name: string, parameters: Type[]): MethodInfo {
        method := owner.GetMethod(name, parameters)
        if method == null {
            throw new InvalidOperationException("Required CLR method " + name + " was not found on its exact owner.")
        }
        return method
    }

    static func RequiredField(owner: Type, name: string): FieldInfo {
        field := owner.GetField(name)
        if field == null {
            throw new InvalidOperationException("Required CLR field " + name + " was not found on its exact owner.")
        }
        return field
    }
}
