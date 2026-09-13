namespace NSharpLang.Compiler

import System
import System.Reflection


// THE RELATION ITSELF, stated as a table rather than through a compile.
//
// The whole point of this owner is that ONE relation answers for a source member and a reflected one
// alike, so these contracts exercise it from both ends: the levels a written modifier word produces,
// the levels a `MethodInfo`/`FieldInfo` produces, and the six answers the relation gives for the
// four facts a caller supplies.
// WHAT THIS FILE CAN AND CANNOT READ OFF REAL METADATA. The compiler's own source is compiled by the
// PINNED stage-0 SDK, which predates this slice: it refuses `protected internal` outright and emits a
// `protected` FIELD as public. So the metadata half pinned here is limited to the two words that seed
// already got right, and `tests/native/census-accessibility` — built by the tip CLI — owns the whole
// six-level metadata table.
class AccessibilityLevelProbe {
    private hidden: int = 2
    Open: int = 4

    private func Hide(): int {
        return hidden
    }

    func Touch(): int {
        return Hide() + Open
    }
}

func AccessibilityProbeFlags(): BindingFlags {
    return BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
}

test "a written accessibility word decides the level, and no word means public at this level" {
    assert MemberAccessibility.LevelOfDeclaredModifiers(1) == MemberAccessibility.Public
    assert MemberAccessibility.LevelOfDeclaredModifiers(2) == MemberAccessibility.Private
    assert MemberAccessibility.LevelOfDeclaredModifiers(4) == MemberAccessibility.Assembly
    assert MemberAccessibility.LevelOfDeclaredModifiers(8) == MemberAccessibility.Family
    assert MemberAccessibility.LevelOfDeclaredModifiers(12) == MemberAccessibility.FamilyOrAssembly
    assert MemberAccessibility.LevelOfDeclaredModifiers(10) == MemberAccessibility.PrivateProtected
    assert MemberAccessibility.LevelOfDeclaredModifiers(32768) == MemberAccessibility.Assembly

    // `public` wins a malformed combination, exactly as the emitted metadata word does.
    assert MemberAccessibility.LevelOfDeclaredModifiers(15) == MemberAccessibility.Public

    // NO WORD IS `Public` HERE, DELIBERATELY. A camelCase member is package-private, and that is the
    // OTHER rule with the other owner: folding casing in here would refuse `widget.count` inside the
    // package that declared it.
    assert MemberAccessibility.LevelOfDeclaredModifiers(0) == MemberAccessibility.Public
    assert MemberAccessibility.LevelOfDeclaredModifiers(16) == MemberAccessibility.Public
}

test "the word a refusal quotes is the word that was written" {
    assert MemberAccessibility.LevelWord(MemberAccessibility.Private) == "private"
    assert MemberAccessibility.LevelWord(MemberAccessibility.PrivateProtected) == "private protected"
    assert MemberAccessibility.LevelWord(MemberAccessibility.Assembly) == "internal"
    assert MemberAccessibility.LevelWord(MemberAccessibility.Family) == "protected"
    assert MemberAccessibility.LevelWord(MemberAccessibility.FamilyOrAssembly) == "protected internal"
    assert MemberAccessibility.LevelWord(MemberAccessibility.Public) == "public"
}

test "a reflected member reports the level its written word named" {
    probe := typeof(AccessibilityLevelProbe)
    assert MemberAccessibility.LevelOfField(probe.GetField("hidden", AccessibilityProbeFlags())) == MemberAccessibility.Private
    assert MemberAccessibility.LevelOfField(probe.GetField("Open", AccessibilityProbeFlags())) == MemberAccessibility.Public
    assert MemberAccessibility.LevelOfMethod(probe.GetMethod("Hide", AccessibilityProbeFlags())) == MemberAccessibility.Private
    assert MemberAccessibility.LevelOfMethod(probe.GetMethod("Touch", AccessibilityProbeFlags())) == MemberAccessibility.Public

    // A member the reflection lookup cannot produce is treated as the most restricted level rather
    // than as an accident: nothing is admitted on the strength of a null.
    assert MemberAccessibility.LevelOfField(null) == MemberAccessibility.Private
    assert MemberAccessibility.LevelOfMethod(null) == MemberAccessibility.Private
}

test "the CLR flag reading agrees with the ordering, narrowest combined word first" {
    assert MemberAccessibility.LevelOfClrFlags(true, false, false, false, false) == MemberAccessibility.Public
    assert MemberAccessibility.LevelOfClrFlags(false, true, false, false, false) == MemberAccessibility.FamilyOrAssembly
    assert MemberAccessibility.LevelOfClrFlags(false, false, true, false, false) == MemberAccessibility.PrivateProtected
    assert MemberAccessibility.LevelOfClrFlags(false, false, false, true, false) == MemberAccessibility.Family
    assert MemberAccessibility.LevelOfClrFlags(false, false, false, false, true) == MemberAccessibility.Assembly
    assert MemberAccessibility.LevelOfClrFlags(false, false, false, false, false) == MemberAccessibility.Private
}

test "public is reachable from everywhere and private only from the declaring type" {
    assert MemberAccessibility.IsAccessible(MemberAccessibility.Public, false, false, false, false)
    assert MemberAccessibility.IsAccessible(MemberAccessibility.Private, true, true, true, true)
    assert !MemberAccessibility.IsAccessible(MemberAccessibility.Private, false, true, true, true)
}

test "internal is an assembly question and nothing else" {
    assert MemberAccessibility.IsAccessible(MemberAccessibility.Assembly, false, false, false, true)
    assert !MemberAccessibility.IsAccessible(MemberAccessibility.Assembly, false, true, true, false)

    // A reflected `internal` member of a referenced assembly is out of reach even from a type that
    // derives from its owner, because N# models no `InternalsVisibleTo`.
    assert !MemberAccessibility.IsAccessible(MemberAccessibility.Assembly, false, true, true, false)
}

test "protected needs BOTH halves: a derived accessing type and a compatible receiver" {
    // Inside the declaring type, the receiver question does not arise.
    assert MemberAccessibility.IsAccessible(MemberAccessibility.Family, true, true, false, true)

    // Derived, with a receiver of the deriving type.
    assert MemberAccessibility.IsAccessible(MemberAccessibility.Family, false, true, true, true)

    // Derived, through a receiver typed as the base: refused.
    assert !MemberAccessibility.IsAccessible(MemberAccessibility.Family, false, true, false, true)

    // Not derived at all: refused, receiver or no receiver.
    assert !MemberAccessibility.IsAccessible(MemberAccessibility.Family, false, false, true, true)

    // Protected crosses an assembly boundary, which is the difference from `private protected`.
    assert MemberAccessibility.IsAccessible(MemberAccessibility.Family, false, true, true, false)
}

test "private protected is protected AND the assembly, and protected internal is either" {
    assert MemberAccessibility.IsAccessible(MemberAccessibility.PrivateProtected, false, true, true, true)
    assert !MemberAccessibility.IsAccessible(MemberAccessibility.PrivateProtected, false, true, true, false)
    assert !MemberAccessibility.IsAccessible(MemberAccessibility.PrivateProtected, false, false, true, true)

    assert MemberAccessibility.IsAccessible(MemberAccessibility.FamilyOrAssembly, false, false, false, true)
    assert MemberAccessibility.IsAccessible(MemberAccessibility.FamilyOrAssembly, false, true, true, false)
    assert !MemberAccessibility.IsAccessible(MemberAccessibility.FamilyOrAssembly, false, false, true, false)
}

test "the refusal phrase names the declaring type and what would have been allowed" {
    assert MemberAccessibility.AllowedFromPhrase(MemberAccessibility.Private, "Vault") == "only code inside 'Vault' can reach it"
    assert MemberAccessibility.AllowedFromPhrase(MemberAccessibility.Family, "Seeded") == "only 'Seeded' and the types that derive from it can reach it, through a receiver of the deriving type"
    assert MemberAccessibility.AllowedFromPhrase(MemberAccessibility.Assembly, "Seeded") == "only code compiled into the same assembly as 'Seeded' can reach it"
}

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
