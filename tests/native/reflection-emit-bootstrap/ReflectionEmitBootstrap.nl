namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System.Reflection.Emit

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
        return 1
    }
}
