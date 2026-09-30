namespace NSharpLang.CensusAccessibility.Tests

import System
import System.Reflection


// A free function is emitted as a STATIC method on its namespace's free-function type, and a
// non-public method is invisible to `Type.GetMethod(name)` under default binding flags, so the
// search asks for both accessibilities explicitly.
func AccessibilityStaticMethodFlags(): BindingFlags {
    return BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic
}

func AccessibilityMethodNamed(name: string): MethodInfo {
    assembly := Assembly.GetExecutingAssembly()
    types := assembly.GetTypes()
    for candidateType in types {
        methods := candidateType.GetMethods(AccessibilityStaticMethodFlags())
        for method in methods {
            if method.Name == name {
                return method
            }
        }
    }

    throw new InvalidOperationException("The emitted assembly declares no static method named " + name + ".")
}

test "a written 'public' exports a camelCase free function to CLR metadata" {
    // The finding: a free function's modifier words never reached the emitted method attributes, so
    // `public func exportedByWord()` came out non-public and the word said nothing at all.
    method := AccessibilityMethodNamed("exportedByWord")
    assert method.IsPublic
    assert !method.IsAssembly
    assert !method.IsPrivate
    assert method.IsStatic

    // …and it really is callable, not merely marked.
    assert exportedByWord() == 3
}

test "a written 'internal' or 'private' keeps a PascalCase free function out of the public surface" {
    internalMethod := AccessibilityMethodNamed("InternalByWord")
    assert internalMethod.IsAssembly
    assert !internalMethod.IsPublic
    assert !internalMethod.IsPrivate

    // `private` at namespace scope is namespace privacy, not type privacy: it emits `Assembly` too.
    // `Private` would be a claim about a containing type that a free function does not have.
    privateMethod := AccessibilityMethodNamed("PrivateByWord")
    assert privateMethod.IsAssembly
    assert !privateMethod.IsPublic
    assert !privateMethod.IsPrivate
}

test "with no written word the casing still decides, exactly as before" {
    pascal := AccessibilityMethodNamed("VisibleByCasing")
    assert pascal.IsPublic
    assert !pascal.IsAssembly

    camel := AccessibilityMethodNamed("hiddenByCasing")
    assert camel.IsAssembly
    assert !camel.IsPublic
}

test "every spelling sits on one emitted free-function type, so accessibility is the only difference" {
    owner := AccessibilityMethodNamed("VisibleByCasing").DeclaringType
    assert owner != null
    assert AccessibilityMethodNamed("hiddenByCasing").DeclaringType == owner
    assert AccessibilityMethodNamed("exportedByWord").DeclaringType == owner
    assert AccessibilityMethodNamed("InternalByWord").DeclaringType == owner
    assert AccessibilityMethodNamed("PrivateByWord").DeclaringType == owner
}

test "a non-exported free function is callable from another CLR type of the same package" {
    // The runtime half of the `Assembly`-not-`Private` decision: a class, and a lambda's display
    // class, are each a different CLR type from the free-function type, and both call all three
    // non-exported spellings. Under `Private` these calls would not verify.
    caller := new PackageCaller()
    assert caller.SumOfHiddenFunctions() == 11
    assert SumOfHiddenFunctionsThroughLambda() == 11
}
