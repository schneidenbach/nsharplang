namespace NSharpLang.Compiler.Columnar

import System.Reflection.Emit


// Owns the exact argument-slot opcode selection shared by constructor chaining and the remaining
// body emitter. Callers pass their live IL stream and already-resolved ordinal directly.
class ColumnarArgumentInstructionEmitter {
    static func EmitLoad(il: ILGenerator, index: int) {
        if index == 0 {
            il.Emit(OpCodes.Ldarg_0)
        } else if index == 1 {
            il.Emit(OpCodes.Ldarg_1)
        } else if index == 2 {
            il.Emit(OpCodes.Ldarg_2)
        } else if index == 3 {
            il.Emit(OpCodes.Ldarg_3)
        } else if index <= 255 {
            il.Emit(OpCodes.Ldarg_S, (byte)index)
        } else {
            il.Emit(OpCodes.Ldarg, index)
        }
    }

    static func EmitStore(il: ILGenerator, index: int) {
        if index <= 255 {
            il.Emit(OpCodes.Starg_S, (byte)index)
        } else {
            il.Emit(OpCodes.Starg, index)
        }
    }

    static func EmitLoadAddress(il: ILGenerator, index: int) {
        if index <= 255 {
            il.Emit(OpCodes.Ldarga_S, (byte)index)
        } else {
            il.Emit(OpCodes.Ldarga, index)
        }
    }
}
