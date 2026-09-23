namespace NSharpLang.CensusInParameters.Tests

import System.Reflection


// THE EMITTED SHAPE, read out of the assembly this project just built.
//
// `in`, `ref` and `out` are ALL `&T` in a signature. The CLR tells them apart by two flags beside the
// signature, and so does every consumer: `ParameterAttributes.Out` for `out`, `ParameterAttributes.In`
// plus `[IsReadOnlyAttribute]` for `in`, and neither for `ref`. Writing only one of `in`'s two marks
// would leave C# and F# treating the parameter as a writable `ref` — which is why both are asserted,
// against a `ref` control that must carry neither.
class InParameterShapeFacts {

    static func FirstParameter(methodName: string): ParameterInfo {
        holder := typeof(InParameters)
        method := must holder.GetMethod(methodName)
        parameters := method.GetParameters()
        return parameters[0]
    }

    // `<typeName> isIn=<b> isOut=<b>` plus every custom attribute the parameter carries, in order.
    static func Describe(methodName: string): string {
        p := FirstParameter(methodName)
        text := p.ParameterType.ToString() + " isIn=" + p.IsIn.ToString() + " isOut=" + p.IsOut.ToString()
        attributes := p.GetCustomAttributesData()
        text = text + " attrs=" + attributes.Count.ToString()
        for attribute in attributes {
            text = text + ":" + attribute.AttributeType.Name
        }
        return text
    }

    static func ParameterCount(methodName: string): int {
        holder := typeof(InParameters)
        method := must holder.GetMethod(methodName)
        return method.GetParameters().Length
    }

    static func DescribeAt(methodName: string, index: int): string {
        holder := typeof(InParameters)
        method := must holder.GetMethod(methodName)
        p := method.GetParameters()[index]
        return p.ParameterType.ToString() + " isIn=" + p.IsIn.ToString() + " isOut=" + p.IsOut.ToString()
    }
}

test "an in parameter is `&T` carrying BOTH the In bit and [IsReadOnly]" {
    // `InAttribute` is how `ParameterAttributes.In` surfaces through `GetCustomAttributesData`, which is
    // also how it reads back on a C#-compiled `in` parameter.
    assert InParameterShapeFacts.Describe("SumIn") == "NSharpLang.CensusInParameters.Tests.Big& isIn=True isOut=False attrs=2:InAttribute:IsReadOnlyAttribute"
}

test "a BY-VALUE parameter is not by-reference and carries neither mark" {
    assert InParameterShapeFacts.Describe("SumByValue") == "NSharpLang.CensusInParameters.Tests.Big isIn=False isOut=False attrs=0"
}

test "THE CONTROL: a `ref` parameter is the same `&T` with NEITHER mark" {
    // This is the row that makes the first one mean something. Without it, `&T` alone would look like
    // proof of `in` — and it is not, because `ref` produces the identical signature.
    assert InParameterShapeFacts.DescribeAt("ReadTwiceAround", 1) == "NSharpLang.CensusInParameters.Tests.Big& isIn=False isOut=False"
    assert InParameterShapeFacts.Describe("ReadTwiceAround") == "NSharpLang.CensusInParameters.Tests.Big& isIn=True isOut=False attrs=2:InAttribute:IsReadOnlyAttribute"
}

test "in works in a non-first position and does not disturb its neighbours" {
    assert InParameterShapeFacts.ParameterCount("Mixed") == 3
    assert InParameterShapeFacts.DescribeAt("Mixed", 0) == "System.String isIn=False isOut=False"
    assert InParameterShapeFacts.DescribeAt("Mixed", 1) == "NSharpLang.CensusInParameters.Tests.Big& isIn=True isOut=False"
    assert InParameterShapeFacts.DescribeAt("Mixed", 2) == "System.Int64 isIn=False isOut=False"
}

test "an in parameter of a primitive type is `&` of that primitive, not a box" {
    assert InParameterShapeFacts.Describe("Doubled") == "System.Int64& isIn=True isOut=False attrs=2:InAttribute:IsReadOnlyAttribute"
}
