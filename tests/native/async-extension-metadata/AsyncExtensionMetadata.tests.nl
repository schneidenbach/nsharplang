namespace NSharpLang.AsyncExtensionMetadata.Tests

import System.Reflection
import System.Runtime.CompilerServices
import NSharpLang.AsyncAwaitablePatternFixtures

test "a referenced N# generic extension is emitted with discoverable CLR metadata" {
    fixtureAssembly := typeof(ReflectedGenericExtensionBox<int>).Assembly
    extensionHost := fixtureAssembly.GetType("NSharpLang.AsyncAwaitablePatternFixtures.Program")
    assert extensionHost != null, "the top-level extension holder is missing"
    assert extensionHost.IsAbstract && extensionHost.IsSealed, "the extension holder must be a static CLR type"
    assert extensionHost.IsDefined(typeof(ExtensionAttribute), false), "the extension holder must carry ExtensionAttribute"

    method: MethodInfo? = null
    for candidate in extensionHost.GetMethods(BindingFlags.Public | BindingFlags.Static) {
        if candidate.Name == "GetAwaiter" && candidate.IsGenericMethodDefinition {
            method = candidate
            break
        }
    }
    assert method != null && method.IsGenericMethodDefinition, "the generic extension definition is missing"
    assert method.IsDefined(typeof(ExtensionAttribute), false), "the extension method must carry ExtensionAttribute"
}
