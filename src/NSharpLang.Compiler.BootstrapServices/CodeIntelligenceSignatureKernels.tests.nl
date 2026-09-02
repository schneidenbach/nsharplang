namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler


// CONTRACTS FOR THE HOVER SIGNATURE — IDE DEFECT D2.
//
// These run against the LIVE type universe: every receiver below resolves through
// `CompletionReflectionFacts.KnownReceiverType`, which answers with a `typeof`. The OTHER universe —
// the `MetadataLoadContext` the CLI loads external assemblies into — is pinned by
// `tests/native/query-integration`, which asks the same questions through a real project on disk.
// Both are needed and neither substitutes for the other: `NullabilityInfoContext.Create` is the
// documented hazard, it behaves differently on an MLC member than on a live one, and a hover that
// throws is a broken editor.
//
// The bar these assert is the one the May 2026 headless report recorded and the June deletion took
// away: the C# signature with parameter and return types, plus the declaring type.
func SkHandle(receiver: TypeInfo, memberName: string): ReflectedMemberHandle? {
    return CodeIntelligenceTypeResolution.ReflectedMemberOfType(receiver, memberName)
}

func SkLine(receiver: TypeInfo, memberName: string): string {
    handle := SkHandle(receiver, memberName)
    if handle == null {
        return "<no member>"
    }

    line := CodeIntelligenceSignatureKernels.GetReflectedMemberLineText(handle)
    if line == null {
        return "<no signature>"
    }

    return line ?? ""
}

func SkStringList(): GenericTypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(new SimpleTypeInfo("int"))
    return new GenericTypeInfo("List", arguments)
}

test "a reflected method renders its return type and its parameters, which is what D2 was missing" {
    // `AddDays` has exactly one overload, so its whole line is pinned.
    assert SkLine(new SimpleTypeInfo("DateTime"), "AddDays") == "method AddDays: DateTime AddDays(double value)"

    // `ToUpper` has two, and `GetMethods` order is deterministic per runtime but NOT specified, so
    // what is pinned here is the shape rather than which overload metadata happens to list first.
    upperLine := SkLine(new SimpleTypeInfo("string"), "ToUpper")
    assert upperLine.StartsWith("method ToUpper: string ToUpper(", StringComparison.Ordinal)
    assert upperLine.EndsWith(" (+1 overload)", StringComparison.Ordinal)
}

test "a reflected property renders its type and its accessors, not the analyzer's placeholder" {
    assert SkLine(new SimpleTypeInfo("DateTime"), "Now") == "property Now: DateTime { get; }"
}

test "an array member is answered from System.Array, which the completion resolver deliberately does not do" {
    assert SkLine(new ArrayTypeInfo(new SimpleTypeInfo("string")), "Length") == "property Length: int { get; }"
}

test "a member of a constructed generic is read off the definition and the type argument is mapped back" {
    // Closing `List<>` over the argument and reading the member off the CLOSED type reports
    // `object[]` for anything the CLR cannot spell. The override is what makes this `int[]`.
    assert SkLine(SkStringList(), "ToArray") == "method ToArray: int[] ToArray()"
}

test "the declaring type is carried, and a generic definition is spelled readably rather than as metadata" {
    stringHandle := SkHandle(new SimpleTypeInfo("string"), "ToUpper")
    assert stringHandle != null
    if stringHandle != null {
        assert stringHandle.DeclaringType == "System.String"
    }

    listHandle := SkHandle(SkStringList(), "ToArray")
    assert listHandle != null
    if listHandle != null {
        assert listHandle.DeclaringType == "System.Collections.Generic.List<T>"
    }

    arrayHandle := SkHandle(new ArrayTypeInfo(new SimpleTypeInfo("int")), "Length")
    assert arrayHandle != null
    if arrayHandle != null {
        assert arrayHandle.DeclaringType == "System.Array"
    }
}

test "one overload is shown and the rest are counted, and the count reads as English" {
    assert CodeIntelligenceSignatureKernels.GetOverloadSuffixText(1) == ""
    assert CodeIntelligenceSignatureKernels.GetOverloadSuffixText(2) == " (+1 overload)"
    assert CodeIntelligenceSignatureKernels.GetOverloadSuffixText(4) == " (+3 overloads)"
}

test "the accessor filter is a consequence of the probe order, so an accessor is never a method" {
    // `get_Length` exists on `string` as a special-name method. The property arm answers `Length`
    // first, and the method loop skips every `IsSpecialName` member, so neither route offers it.
    assert SkLine(new SimpleTypeInfo("string"), "Length") == "property Length: int { get; }"
    assert SkHandle(new SimpleTypeInfo("string"), "get_Length") == null
}

test "a receiver metadata cannot explain, and a member it does not have, both DECLINE" {
    // A project-declared receiver has no CLR type, which is what keeps this route from ever
    // shadowing a source symbol.
    assert SkHandle(new SimpleTypeInfo("SomeProjectRecord"), "Field") == null
    assert SkHandle(new SimpleTypeInfo("string"), "NoSuchMemberAnywhere") == null
}

test "the bare fallback is still there and is still a function of text alone" {
    assert CodeIntelligenceSignatureKernels.GetFallbackSignatureText("field", "Count", "int") == "field Count: int"
    assert CodeIntelligenceSignatureKernels.GetFallbackSignatureText("class", "Widget", null) == "class Widget"
}
