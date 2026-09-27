namespace NSharpLang.Compiler.Columnar

import NSharpLang.Compiler


// THE INHERITED-EXTERNAL-BASE FORM OF THE RELATION, which both the analyzer's metadata arm and the
// emitter's candidate filter ask. A member of a REFERENCED assembly is never reachable by its
// `assembly` half, so the only thing `allowInheritedProtected` opens is the family surface.
test "an inherited external base offers its family surface and nothing else" {
    assert AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Public, false)
    assert AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Public, true)

    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Family, false)
    assert AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Family, true)

    assert AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.FamilyOrAssembly, true)
    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.FamilyOrAssembly, false)

    // `private protected` across an assembly boundary is unreachable however derived the reader is:
    // its `assembly` half can never be satisfied.
    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.PrivateProtected, true)

    // `internal` and `private` are never reachable from another assembly.
    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Assembly, true)
    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Private, true)

    // The emitter's copy of the question is the same relation, so the two cannot drift.
    assert ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.Family, true)
    assert !ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.Family, false)
    assert !ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.Assembly, true)
    assert ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.Public, false)
}
