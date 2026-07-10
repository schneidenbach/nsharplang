namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Runtime.CompilerServices

// The exact CLR member owner for range/index plans. Callers receive already-selected handles;
// no C# seed, reflection-order lookup, or overload scoring participates in planning.
public class ColumnarRangeIndexHandles {
    public IndexConstructor: ConstructorInfo
    public IndexGetOffset: MethodInfo
    public RangeConstructor: ConstructorInfo
    public RangeGetOffsetAndLength: MethodInfo
    public GetSubArrayDefinition: MethodInfo
    public StringLengthGetter: MethodInfo
    public StringCharsGetter: MethodInfo
    public StringSubstring: MethodInfo
    public TupleItem1: FieldInfo
    public TupleItem2: FieldInfo

    constructor(
        indexConstructor: ConstructorInfo,
        indexGetOffset: MethodInfo,
        rangeConstructor: ConstructorInfo,
        rangeGetOffsetAndLength: MethodInfo,
        getSubArrayDefinition: MethodInfo,
        stringLengthGetter: MethodInfo,
        stringCharsGetter: MethodInfo,
        stringSubstring: MethodInfo,
        tupleItem1: FieldInfo,
        tupleItem2: FieldInfo) {
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
    }

    public static func Resolve(): ColumnarRangeIndexHandles {
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

        getSubArrayDefinition := typeof(RuntimeHelpers).GetMethod("GetSubArray")
        if getSubArrayDefinition == null {
            throw new InvalidOperationException(
                "Required CLR method RuntimeHelpers.GetSubArray<T>(T[],Range) was not found.")
        }

        // Closing the method proves that the selected name denotes the expected generic definition.
        probeTypeArguments := new Type[](1)
        probeTypeArguments[0] = typeof(int)
        getSubArrayDefinition.MakeGenericMethod(probeTypeArguments)

        return new ColumnarRangeIndexHandles(
            indexConstructor,
            indexGetOffset,
            rangeConstructor,
            rangeGetOffsetAndLength,
            getSubArrayDefinition,
            stringLengthGetter,
            stringCharsGetter,
            stringSubstring,
            tupleItem1,
            tupleItem2)
    }

    public func CloseGetSubArray(elementType: Type): MethodInfo {
        if elementType == null {
            throw new InvalidOperationException("GetSubArray element type cannot be null.")
        }
        typeArguments := new Type[](1)
        typeArguments[0] = elementType
        return GetSubArrayDefinition.MakeGenericMethod(typeArguments)
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
            throw new InvalidOperationException(
                "Required CLR method " + name + " was not found on its exact owner.")
        }
        return method
    }

    static func RequiredField(owner: Type, name: string): FieldInfo {
        field := owner.GetField(name)
        if field == null {
            throw new InvalidOperationException(
                "Required CLR field " + name + " was not found on its exact owner.")
        }
        return field
    }
}
