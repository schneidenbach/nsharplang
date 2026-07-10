namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection
import System.Reflection.Emit
import System.Runtime.CompilerServices

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
        return 2
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
        return closedGetSubArray != null
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
}
