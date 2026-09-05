namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection
import System.Reflection.Emit

// 015-B2 STAGE 1 — THE WIDENED MODELED `OpCodes` ALLOWLIST, EXERCISED END TO END.
//
// `Ldarg_0`, `Ldarg_1`, `Ldarg_2`, `Ldarg_3` and `Unbox_Any` were admitted to the emitter's modeled
// `OpCodes` surface (`ColumnarExternalBindingPlans.IsSupportedOpCodeMemberName`) in this tree. The
// compiler-service estate is compiled by the PACKAGED SDK, which still carries the pre-widening
// allowlist, so the estate cannot spell the new names at all — it can only ask the surface whether it
// admits them. THIS project is compiled by the CLI built from THIS tree, which makes it the only place
// in the repository where the new names can be written.
//
// Spelling them is half a proof. Each new name is emitted into a real method body here, and every body
// is INVOKED, so a name that binds but emits the wrong instruction fails on the answer rather than on
// the compile. The bodies are deliberately PARAMETER-SHAPED: `ldarg.N` is only meaningful in a method
// that has an argument N, which is exactly what B1's parameterless entry-point wrapper could not offer.
class OpcodeAllowlistWideningProbe {
    static func RequiredConstructor(owner: Type, parameterTypes: Type[]): ConstructorInfo {
        constructorInfo := owner.GetConstructor(parameterTypes)
        if constructorInfo == null {
            throw new InvalidOperationException("Required constructor was not found.")
        }

        return constructorInfo
    }

    static func SetObject(values: object?[], index: int, value: object?) {
        values[index] = value
    }

    static func DynamicMethodOf(name: string, returnType: Type, parameterTypes: Type[]): DynamicMethod {
        constructorTypes := new Type[](3)
        constructorTypes[0] = typeof(string)
        constructorTypes[1] = typeof(Type)
        constructorTypes[2] = typeof(Type[])
        constructorInfo := RequiredConstructor(typeof(DynamicMethod), constructorTypes)
        constructorArguments := new object?[](3)
        SetObject(constructorArguments, 0, name)
        SetObject(constructorArguments, 1, returnType)
        SetObject(constructorArguments, 2, parameterTypes)
        return (DynamicMethod)constructorInfo.Invoke(constructorArguments)
    }

    static func FourInt32Parameters(): Type[] {
        parameterTypes := new Type[](4)
        parameterTypes[0] = typeof(int)
        parameterTypes[1] = typeof(int)
        parameterTypes[2] = typeof(int)
        parameterTypes[3] = typeof(int)
        return parameterTypes
    }

    static func OneObjectParameter(): Type[] {
        parameterTypes := new Type[](1)
        parameterTypes[0] = typeof(object)
        return parameterTypes
    }

    // ONE short-form load per body, so each of the four opcodes is proved on its own rather than as a
    // member of a sum that a wrong ordinal might still balance.
    static func LoadArgumentByShortForm(
        ordinal: int,
        first: int,
        second: int,
        third: int,
        fourth: int
    ): int {
        method := DynamicMethodOf("NSharpB2LoadArgumentShortForm", typeof(int), FourInt32Parameters())
        il := method.GetILGenerator()
        if ordinal == 0 {
            il.Emit(OpCodes.Ldarg_0)
        } else if ordinal == 1 {
            il.Emit(OpCodes.Ldarg_1)
        } else if ordinal == 2 {
            il.Emit(OpCodes.Ldarg_2)
        } else if ordinal == 3 {
            il.Emit(OpCodes.Ldarg_3)
        } else {
            throw new ArgumentOutOfRangeException("ordinal")
        }

        il.Emit(OpCodes.Ret)

        arguments := new object?[](4)
        SetObject(arguments, 0, first)
        SetObject(arguments, 1, second)
        SetObject(arguments, 2, third)
        SetObject(arguments, 3, fourth)
        return Convert.ToInt32(method.Invoke(null, arguments))
    }

    // All four short forms in ONE body. Weighted so that a repeated or omitted ordinal moves the answer.
    static func SumViaShortFormArgumentLoads(
        first: int,
        second: int,
        third: int,
        fourth: int
    ): int {
        method := DynamicMethodOf("NSharpB2SumShortFormArguments", typeof(int), FourInt32Parameters())
        il := method.GetILGenerator()
        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Ldarg_1)
        il.Emit(OpCodes.Add)
        il.Emit(OpCodes.Ldarg_2)
        il.Emit(OpCodes.Add)
        il.Emit(OpCodes.Ldarg_3)
        il.Emit(OpCodes.Add)
        il.Emit(OpCodes.Ret)

        arguments := new object?[](4)
        SetObject(arguments, 0, first)
        SetObject(arguments, 1, second)
        SetObject(arguments, 2, third)
        SetObject(arguments, 3, fourth)
        return Convert.ToInt32(method.Invoke(null, arguments))
    }

    // `unbox.any` over a VALUE type — the arm PASS 0e needs, where a record STRUCT's `Equals` must turn
    // its boxed `object` argument into the typed value before the typed store. `castclass` cannot
    // express this, so a body that runs and answers is proof the emitted instruction is the right one.
    static func UnboxAnyToInt32(boxed: object): int {
        method := DynamicMethodOf("NSharpB2UnboxAnyValue", typeof(int), OneObjectParameter())
        il := method.GetILGenerator()
        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Unbox_Any, typeof(int))
        il.Emit(OpCodes.Ret)

        arguments := new object?[](1)
        SetObject(arguments, 0, boxed)
        return Convert.ToInt32(method.Invoke(null, arguments))
    }

    // `unbox.any` over a REFERENCE type — the same opcode's castclass-shaped arm, which a record CLASS
    // would take. Proving both arms keeps the row from being pinned to the value case alone.
    static func UnboxAnyToText(boxed: object): string {
        method := DynamicMethodOf("NSharpB2UnboxAnyReference", typeof(string), OneObjectParameter())
        il := method.GetILGenerator()
        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Unbox_Any, typeof(string))
        il.Emit(OpCodes.Ret)

        arguments := new object?[](1)
        SetObject(arguments, 0, boxed)
        result := method.Invoke(null, arguments)
        if result == null {
            return ""
        }

        return result.ToString() ?? ""
    }
}
