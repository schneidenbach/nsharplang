namespace NSharpLang.CensusVisibility.Tests

import System
import System.Collections.Generic
import System.Reflection


// A THIRD FILE OF THE SAME NAMESPACE, which is itself part of the claim: these blocks call
// `formatTypeRef` directly, and a test file is an ordinary file of the project.
func VisibilityNames(): List<string> {
    names := new List<string>()
    names.Add("int")
    names.Add("string")
    return names
}

func VisibilityJoin(values: List<string>): string {
    text := ""
    index := 0
    while index < values.Count {
        if index > 0 {
            text = text + ","
        }
        text = text + values[index]
        index = index + 1
    }
    return text
}

// ─── THE CLR METADATA HALF ────────────────────────────────────────────────────────────────────
//
// The LANGUAGE rule changed; the CLR contract did not, and that is worth saying out loud. A
// camelCase free function was already emitted with ASSEMBLY accessibility
// (`ColumnarDeclarationPlan.MethodVisibilityAttributes` answers `Assembly` for a lower-cased name),
// so the same assembly could always call it and nothing outside ever could. Making it visible to
// the whole namespace in the language did not widen or narrow one metadata bit.
//
// A free function is emitted onto the `Program` type, and a NON-PUBLIC method is invisible to
// `Type.GetMethod(name)` with default binding flags, so the search asks for both accessibilities
// explicitly.
func VisibilityStaticMethodFlags(): BindingFlags {
    return BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic
}

func VisibilityMethodNamed(name: string): object {
    assembly := Assembly.GetExecutingAssembly()
    types := assembly.GetTypes()
    for candidateType in types {
        methods := candidateType.GetMethods(VisibilityStaticMethodFlags())
        for method in methods {
            if method.Name == name {
                return method
            }
        }
    }

    throw new InvalidOperationException("The emitted assembly declares no static method named " + name + ".")
}

func VisibilityMethodFlag(name: string, flagName: string): bool {
    method := VisibilityMethodNamed(name)
    property := method.GetType().GetProperty(flagName)
    if property == null {
        throw new InvalidOperationException("MethodInfo exposes no " + flagName + " member.")
    }

    value := property.GetValue(method)
    if value == null {
        throw new InvalidOperationException("MethodInfo answered nothing for " + flagName + ".")
    }

    return Convert.ToBoolean(value)
}

func VisibilityMethodDeclaringTypeName(name: string): string {
    method := VisibilityMethodNamed(name)
    property := method.GetType().GetProperty("DeclaringType")
    if property == null {
        throw new InvalidOperationException("MethodInfo exposes no DeclaringType member.")
    }

    owner := property.GetValue(method) as Type
    if owner == null {
        throw new InvalidOperationException("The emitted method declares no owning type.")
    }

    return owner.Name
}

test "a camelCase function of this namespace is callable from another file of it" {
    // `DescribeAcrossFiles` lives in NamespacePrivateUse.nl and calls `formatTypeRef`, declared in
    // NamespacePrivateHelpers.nl. This block is a THIRD file naming the same function directly.
    assert DescribeAcrossFiles("int") == "<int>"
    assert formatTypeRef("string") == "<string>"
    assert shoutTypeRef("string") == "STRING"

    // The exported twin behaves identically in the language; only its metadata differs.
    assert FormatExported("int") == "[int]"
}

test "a camelCase function of this namespace converts to a delegate from another file of it" {
    // The method-group shape, which reported NL402 "No overload of 'Select' accepts 1 argument
    // with these types" before the rule was implemented at the function channel.
    assert VisibilityJoin(DescribeAllAcrossFiles(VisibilityNames())) == "<int>,<string>"

    // TWO candidates of the same shape exist, so the delegate that comes back is the one the
    // written NAME selects rather than the only one available.
    assert VisibilityJoin(ShoutAllAcrossFiles(VisibilityNames())) == "INT,STRING"

    // The same name bound to a delegate-typed local first.
    assert DescribeViaDelegate("bool") == "<bool>"
}

test "a camelCase TYPE of this namespace is constructible from another file of it" {
    // The half of the rule that already held, pinned beside the half that did not so the two
    // cannot drift apart again.
    assert BoxAcrossFiles("int") == "<int>"

    box := new helperBox("string")
    assert box.Value == "string"
    assert box.Describe() == "<string>"
}

test "namespace-private is a LANGUAGE rule: the emitted method is still assembly-accessible" {
    // camelCase emits `Assembly` accessibility — internal, so the whole assembly (every file of
    // every namespace in it) can call it and nothing outside the assembly can. That is UNCHANGED by
    // the ruling: `X.formatTypeRef` is invisible to namespace `Y` in the LANGUAGE while both are
    // compiled into one assembly, exactly as a C# `private` member is invisible to another class in
    // the same file.
    assert VisibilityMethodFlag("formatTypeRef", "IsAssembly")
    assert !VisibilityMethodFlag("formatTypeRef", "IsPublic")
    assert !VisibilityMethodFlag("formatTypeRef", "IsPrivate")
    assert VisibilityMethodFlag("formatTypeRef", "IsStatic")

    // PascalCase emits `Public`, which is the difference the casing actually makes in metadata.
    assert VisibilityMethodFlag("FormatExported", "IsPublic")
    assert !VisibilityMethodFlag("FormatExported", "IsAssembly")
    assert VisibilityMethodFlag("FormatExported", "IsStatic")

    // Both sit on the same emitted free-function type, so the accessibility difference is the only
    // difference between them.
    assert VisibilityMethodDeclaringTypeName("formatTypeRef") == VisibilityMethodDeclaringTypeName("FormatExported")
}
