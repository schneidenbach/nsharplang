namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection.Emit

class ExternalQualifiedVisibilityHost {
    private class Hidden {
    }
}

test "external type resolver owns bare exact and nested CLR names" {
    assemblies := ExternalAssemblyScan.Loaded()

    opcodeType := typeof(object)
    assert ExternalQualifiedTypeResolver.TryResolve(
        assemblies,
        "System.Reflection.Emit.OpCodes",
        out opcodeType
    )
    assert opcodeType == typeof(OpCodes)

    nestedType := typeof(object)
    assert ExternalQualifiedTypeResolver.TryResolve(
        assemblies,
        "System.Environment.SpecialFolder",
        out nestedType
    )
    assert nestedType == Type.GetType("System.Environment+SpecialFolder")

    bareType := typeof(object)
    assert ExternalQualifiedTypeResolver.TryResolve(
        assemblies,
        "DateTime",
        out bareType
    )
    assert bareType == typeof(DateTime)

    bareGenericType := typeof(object)
    assert ExternalQualifiedTypeResolver.TryResolve(
        assemblies,
        "Stack`1",
        out bareGenericType
    )
    assert bareGenericType == typeof(Stack<int>).GetGenericTypeDefinition()

    missingType := typeof(object)
    assert !ExternalQualifiedTypeResolver.TryResolve(
        assemblies,
        "Missing.Namespace.Type",
        out missingType
    )
    assert missingType == typeof(object)

    hiddenType := typeof(object)
    assert !ExternalQualifiedTypeResolver.TryResolve(
        assemblies,
        "NSharpLang.Compiler.ExternalQualifiedVisibilityHost.Hidden",
        out hiddenType
    )
    assert hiddenType == typeof(object)
    assert ExternalQualifiedTypeResolver.RootName(
        "System.Reflection.Emit.OpCodes"
    ) == "System"
}
