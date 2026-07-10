namespace NSharpLang.Compiler

import System
import System.Reflection.Emit

class ExternalQualifiedVisibilityHost {
    private class Hidden {
    }
}

test "qualified external type resolver owns exact and nested CLR names" {
    assemblies := ExternalAssemblyScan.Loaded()

    opcodeType := typeof(object)
    assert ExternalQualifiedTypeResolver.TryResolve(
        assemblies, "System.Reflection.Emit.OpCodes", out opcodeType)
    assert opcodeType == typeof(OpCodes)

    nestedType := typeof(object)
    assert ExternalQualifiedTypeResolver.TryResolve(
        assemblies, "System.Environment.SpecialFolder", out nestedType)
    assert nestedType == Type.GetType("System.Environment+SpecialFolder")

    missingType := typeof(object)
    assert !ExternalQualifiedTypeResolver.TryResolve(
        assemblies, "Missing.Namespace.Type", out missingType)
    assert missingType == typeof(object)

    hiddenType := typeof(object)
    assert !ExternalQualifiedTypeResolver.TryResolve(
        assemblies,
        "NSharpLang.Compiler.ExternalQualifiedVisibilityHost.Hidden",
        out hiddenType)
    assert hiddenType == typeof(object)
    assert ExternalQualifiedTypeResolver.RootName(
        "System.Reflection.Emit.OpCodes") == "System"
}
