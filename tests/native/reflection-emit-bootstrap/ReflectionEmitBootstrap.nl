namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Globalization
import System.Reflection
import System.Reflection.Emit
import System.Runtime.CompilerServices

enum ReflectionEmitProbeEnum {
    Value
}

public class ReflectionEmitBootstrapProbe {
    public static func EmitVoidBody(il: ILGenerator) {
        done := il.DefineLabel()
        value := il.DeclareLocal(typeof(int), false)

        il.Emit(OpCodes.Ldc_I4, 1)
        il.Emit(OpCodes.Stloc, value)
        il.Emit(OpCodes.Br, done)
        il.MarkLabel(done)
        il.Emit(OpCodes.Ldloc, value)
        il.Emit(OpCodes.Pop)
        il.Emit(OpCodes.Ret)
    }

    public static func ContractVersion(): int {
        return 14
    }

    public static func HasReferenceIdentitySurface(): bool {
        noTypes := new Type[](0)
        method := typeof(string).GetMethod("ToString", noTypes)
        differentMethod := typeof(object).GetMethod("ToString", noTypes)
        if method == null || differentMethod == null {
            return false
        }

        sameMethod: MethodInfo = method
        return Object.ReferenceEquals(method, sameMethod)
            && System.Object.ReferenceEquals(method, sameMethod)
            && !Object.ReferenceEquals(method, differentMethod)
            && !System.Object.ReferenceEquals(method, differentMethod)
    }

    public static func ParseInt32(text: string): int {
        return Int32.Parse(text)
    }

    public static func TryParseInt32(text: string, out value: int): bool {
        return Int32.TryParse(text, out value)
    }

    public static func ParseDoubleInvariant(text: string): double {
        return Double.Parse(text, CultureInfo.InvariantCulture)
    }

    public static func TryParseDoubleInvariant(text: string, out value: double): bool {
        return Double.TryParse(text, CultureInfo.InvariantCulture, out value)
    }

    public static func HasRangeHandleSurface(): bool {
        indexCtorArgs := new Type[](2)
        indexCtorArgs[0] = typeof(int)
        indexCtorArgs[1] = typeof(bool)
        indexCtor := typeof(Index).GetConstructor(indexCtorArgs)
        if indexCtor == null {
            return false
        }

        indexOffsetArgs := new Type[](1)
        indexOffsetArgs[0] = typeof(int)
        indexOffset := typeof(Index).GetMethod("GetOffset", indexOffsetArgs)
        if indexOffset == null {
            return false
        }

        rangeCtorArgs := new Type[](2)
        rangeCtorArgs[0] = typeof(Index)
        rangeCtorArgs[1] = typeof(Index)
        rangeCtor := typeof(Range).GetConstructor(rangeCtorArgs)
        if rangeCtor == null {
            return false
        }

        rangeOffsetArgs := new Type[](1)
        rangeOffsetArgs[0] = typeof(int)
        rangeOffset := typeof(Range).GetMethod("GetOffsetAndLength", rangeOffsetArgs)
        if rangeOffset == null {
            return false
        }

        noTypes := new Type[](0)
        abstractMethod := typeof(MethodInfo).GetMethod("GetBaseDefinition", noTypes)
        if abstractMethod == null {
            return false
        }
        stringLength := typeof(string).GetMethod("get_Length", noTypes)
        stringChars := typeof(string).GetMethod("get_Chars", indexOffsetArgs)
        substringArgs := new Type[](2)
        substringArgs[0] = typeof(int)
        substringArgs[1] = typeof(int)
        stringSubstring := typeof(string).GetMethod("Substring", substringArgs)
        if stringLength == null || stringChars == null || stringSubstring == null {
            return false
        }

        tupleItem1 := typeof(ValueTuple<int, int>).GetField("Item1")
        tupleItem2 := typeof(ValueTuple<int, int>).GetField("Item2")
        if tupleItem1 == null || tupleItem2 == null {
            return false
        }

        getSubArray := typeof(RuntimeHelpers).GetMethod("GetSubArray")
        if getSubArray == null {
            return false
        }
        genericArgs := new Type[](1)
        genericArgs[0] = typeof(int)
        closedGetSubArray := getSubArray.MakeGenericMethod(genericArgs)
        if closedGetSubArray == null {
            return false
        }

        indexParameters := indexCtor.GetParameters()
        offsetParameters := indexOffset.GetParameters()
        rangeParameters := rangeCtor.GetParameters()
        openSubArrayParameters := getSubArray.GetParameters()
        subArrayParameters := closedGetSubArray.GetParameters()
        if openSubArrayParameters.Length != 2 {
            return false
        }
        openArrayElementType := openSubArrayParameters[0].get_ParameterType().GetElementType()
        if openArrayElementType == null {
            return false
        }
        otherGenericDefinition := typeof(System.Array).GetMethod("Empty")
        if otherGenericDefinition == null {
            return false
        }
        otherGenericParameter := otherGenericDefinition.get_ReturnType().GetElementType()
        if otherGenericParameter == null {
            return false
        }
        openTypeArgs := new Type[](1)
        openTypeArgs[0] = otherGenericParameter
        openConstructedGetSubArray := getSubArray.MakeGenericMethod(openTypeArgs)
        if openConstructedGetSubArray == null {
            return false
        }
        genericTupleDefinition := typeof(ValueTuple<int, int>).GetGenericTypeDefinition()
        tupleTypeArguments := new Type[](2)
        tupleTypeArguments[0] = typeof(string)
        tupleTypeArguments[1] = typeof(int)
        constructedTuple := genericTupleDefinition.MakeGenericType(tupleTypeArguments)
        constructedTupleArguments := constructedTuple.GetGenericArguments()
        closedGenericArguments := closedGetSubArray.GetGenericArguments()
        openConstructedGenericArguments := openConstructedGetSubArray.GetGenericArguments()
        roundTripDefinition := openConstructedGetSubArray.GetGenericMethodDefinition()
        roundTripGenericArguments := roundTripDefinition.GetGenericArguments()
        openConstructedArrayElement := openConstructedGetSubArray
            .GetParameters()[0].get_ParameterType().GetElementType()
        if openConstructedArrayElement == null {
            return false
        }
        // System.Reflection.CallingConventions.VarArgs has the stable CLR metadata value 2.
        varArgsFlag := 2
        return typeof(int[]).get_IsSZArray()
            && typeof(int).get_IsValueType()
            && typeof(ReflectionEmitProbeEnum).get_IsEnum()
            && typeof(ReflectionEmitProbeEnum).GetEnumUnderlyingType() == typeof(int)
            && !typeof(int).get_IsGenericParameter()
            && openArrayElementType.get_IsGenericParameter()
            && otherGenericParameter.get_IsGenericParameter()
            && typeof(ValueTuple<int, int>).get_IsGenericType()
            && genericTupleDefinition.get_IsGenericTypeDefinition()
            && !typeof(ValueTuple<int, int>).get_IsGenericTypeDefinition()
            && !openArrayElementType.get_IsGenericTypeDefinition()
            && constructedTuple == typeof(ValueTuple<string, int>)
            && constructedTupleArguments.Length == 2
            && constructedTupleArguments[0] == typeof(string)
            && constructedTupleArguments[1] == typeof(int)
            && typeof(MethodInfo).get_IsAbstract()
            && !typeof(Index).get_IsAbstract()
            && getSubArray.get_IsGenericMethod()
            && getSubArray.get_IsGenericMethodDefinition()
            && !getSubArray.get_IsAbstract()
            && abstractMethod.get_IsAbstract()
            && (((int)getSubArray.get_CallingConvention()) & varArgsFlag) == 0
            && (((int)indexCtor.get_CallingConvention()) & varArgsFlag) == 0
            && !openConstructedGetSubArray.get_IsGenericMethodDefinition()
            && !closedGetSubArray.get_IsGenericMethodDefinition()
            && openConstructedGetSubArray.get_IsGenericMethod()
            && roundTripDefinition.get_IsGenericMethodDefinition()
            && roundTripGenericArguments.Length == 1
            && roundTripGenericArguments[0].get_IsGenericParameter()
            && closedGenericArguments.Length == 1
            && closedGenericArguments[0] == typeof(int)
            && openConstructedGenericArguments.Length == 1
            && openConstructedGenericArguments[0] == otherGenericParameter
            && otherGenericParameter.get_GenericParameterPosition()
                == openConstructedArrayElement.get_GenericParameterPosition()
            && otherGenericParameter.get_DeclaringMethod() != null
            && openConstructedArrayElement.get_DeclaringMethod() != null
            && typeof(object).IsAssignableFrom(typeof(string))
            && indexCtor.get_DeclaringType() == typeof(Index)
            && !indexCtor.get_IsStatic()
            && indexParameters.Length == 2
            && indexParameters[0].get_ParameterType() == typeof(int)
            && !indexParameters[0].get_ParameterType().get_IsByRef()
            && indexParameters[1].get_ParameterType() == typeof(bool)
            && indexOffset.get_DeclaringType() == typeof(Index)
            && !indexOffset.get_IsStatic()
            && indexOffset.get_ReturnType() == typeof(int)
            && offsetParameters.Length == 1
            && offsetParameters[0].get_ParameterType() == typeof(int)
            && rangeCtor.get_DeclaringType() == typeof(Range)
            && !rangeCtor.get_IsStatic()
            && rangeParameters.Length == 2
            && rangeParameters[0].get_ParameterType() == typeof(Index)
            && rangeParameters[1].get_ParameterType() == typeof(Index)
            && tupleItem1.get_DeclaringType() == typeof(ValueTuple<int, int>)
            && !tupleItem1.get_IsStatic()
            && tupleItem1.get_FieldType() == typeof(int)
            && tupleItem2.get_FieldType() == typeof(int)
            && closedGetSubArray.get_IsStatic()
            && closedGetSubArray.get_ReturnType() == typeof(int[])
            && subArrayParameters.Length == 2
            && subArrayParameters[0].get_ParameterType() == typeof(int[])
            && subArrayParameters[1].get_ParameterType() == typeof(Range)
    }

    // Compile-time proof for every Reflection.Emit field/overload consumed by schema-v2 execution.
    // The executor's persisted tests call the same surface with validated operation streams.
    public static func EmitRangePlanSurface(
        il: ILGenerator,
        method: MethodInfo,
        constructor: ConstructorInfo,
        field: FieldInfo,
        elementType: Type,
        ambientLocal: LocalBuilder) {
        label := il.DefineLabel()
        temporary := il.DeclareLocal(elementType)
        ambientType := ambientLocal.get_LocalType()
        ambientCopy := il.DeclareLocal(ambientType)

        il.Emit(OpCodes.Ldc_I4_M1)
        il.Emit(OpCodes.Ldc_I4_0)
        il.Emit(OpCodes.Ldc_I4_1)
        il.Emit(OpCodes.Ldc_I4_2)
        il.Emit(OpCodes.Ldc_I4_3)
        il.Emit(OpCodes.Ldc_I4_4)
        il.Emit(OpCodes.Ldc_I4_5)
        il.Emit(OpCodes.Ldc_I4_6)
        il.Emit(OpCodes.Ldc_I4_7)
        il.Emit(OpCodes.Ldc_I4_8)
        il.Emit(OpCodes.Ldc_I4, 9)
        il.Emit(OpCodes.Stloc, temporary)
        il.Emit(OpCodes.Ldloc, ambientCopy)
        il.Emit(OpCodes.Pop)
        il.Emit(OpCodes.Ldloc, ambientLocal)
        il.Emit(OpCodes.Ldloca, temporary)
        il.Emit(OpCodes.Ldarg, (short)0)
        il.Emit(OpCodes.Brfalse, label)
        il.Emit(OpCodes.Br, label)
        il.Emit(OpCodes.Call, method)
        il.Emit(OpCodes.Callvirt, method)
        il.Emit(OpCodes.Newobj, constructor)
        il.Emit(OpCodes.Conv_I4)
        il.Emit(OpCodes.Ldfld, field)
        il.Emit(OpCodes.Ldlen)
        il.Emit(OpCodes.Ldelem_U1)
        il.Emit(OpCodes.Ldelem_U2)
        il.Emit(OpCodes.Ldelem_I4)
        il.Emit(OpCodes.Ldelem_U4)
        il.Emit(OpCodes.Ldelem_I8)
        il.Emit(OpCodes.Ldelem_R4)
        il.Emit(OpCodes.Ldelem_R8)
        il.Emit(OpCodes.Ldelem_Ref)
        il.Emit(OpCodes.Ldelem, elementType)
        il.MarkLabel(label)
    }

    // Compile-time proof for every scalar-constant overload consumed by schema-v3 execution.
    public static func EmitScalarConstantSurface(il: ILGenerator) {
        il.Emit(OpCodes.Ldc_I8, (long)-1)
        il.Emit(OpCodes.Ldc_R4, (float)1.25)
        il.Emit(OpCodes.Ldc_R8, 2.5)
        il.Emit(OpCodes.Ldstr, "scalar")
        il.Emit(OpCodes.Neg)
        il.Emit(OpCodes.Not)
        il.Emit(OpCodes.Ceq)
    }

    // Compile-time proof for the field load and reflection fact consumed by static-member plans.
    public static func EmitExternalStaticMemberPlanSurface(
        il: ILGenerator,
        field: FieldInfo,
        property: PropertyInfo): Type {
        il.Emit(OpCodes.Ldsfld, field)
        return property.get_PropertyType()
    }
}
