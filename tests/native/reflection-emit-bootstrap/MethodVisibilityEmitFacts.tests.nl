namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection

func MethodVisibilityRequiredMethod(name: string): MethodInfo {
    methods := typeof(MethodVisibilityEmitFacts).GetMethods((BindingFlags)60)
    for method in methods {
        if method.get_Name() == name {
            return method
        }
    }
    throw new InvalidOperationException("Required method was not found: " + name)
}

test "method declarations emit exact convention and explicit CLR accessibility" {
    publicByConvention := MethodVisibilityRequiredMethod("PascalByConvention")
    assert publicByConvention.get_IsPublic()
    assert Convert.ToInt32(publicByConvention.get_Attributes()) == 134

    assemblyByConvention := MethodVisibilityRequiredMethod("camelByConvention")
    assert assemblyByConvention.get_IsAssembly()
    assert Convert.ToInt32(assemblyByConvention.get_Attributes()) == 131

    forcedPublic := MethodVisibilityRequiredMethod("forcedPublic")
    assert forcedPublic.get_IsPublic()
    assert Convert.ToInt32(forcedPublic.get_Attributes()) == 134

    forcedPrivate := MethodVisibilityRequiredMethod("ForcedPrivate")
    assert forcedPrivate.get_IsPrivate()
    assert Convert.ToInt32(forcedPrivate.get_Attributes()) == 129

    internalInterop := MethodVisibilityRequiredMethod("InternalInterop")
    assert internalInterop.get_IsAssembly()
    assert Convert.ToInt32(internalInterop.get_Attributes()) == 131

    protectedInterop := MethodVisibilityRequiredMethod("ProtectedInterop")
    assert protectedInterop.get_IsFamily()
    assert Convert.ToInt32(protectedInterop.get_Attributes()) == 132

    privateStatic := MethodVisibilityRequiredMethod("PrivateStatic")
    assert privateStatic.get_IsPrivate()
    assert privateStatic.get_IsStatic()
    assert Convert.ToInt32(privateStatic.get_Attributes()) == 145
}
