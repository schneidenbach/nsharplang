namespace NSharpLang.Cli

import NSharpLang.Compiler

// THE SDK'S IL-EMIT TASK — THE DECISIONS EVERY `dotnet build` OF AN N# PROJECT RUNS THROUGH.
//
// `src/NSharpLang.Build.Tasks/EmitIlAssembly.cs` had NO estate contract of any kind before 021/8,
// and it was the last file on the CLI/SDK product path that consulted no N# owner at all: a census
// of `\b\w+Kernels\.\w+` over its 341 lines returned ZERO rows. Seventeen decisions lived there,
// and nothing anywhere — `.nl` or `.cs` — asserted a single one of them. `System.Private.CoreLib`
// could have been renamed, the define separators cut to one, the diagnostic id reformatted or the
// definition-beats-forwarder precedence inverted, and every test in the repository would still have
// passed. These blocks are the first pins those answers have ever had.

// ── conditional compilation ───────────────────────────────────────────────────
//
// The task used to restate the `DEBUG` rule and re-implement the define splitter. Both now reach the
// owners `nlc` itself uses, so "resolves `#if` identically to `nlc`" is a shared owner rather than a
// hopeful comment.
test "an MSBuild build defines DEBUG for every configuration except the release one" {
    debugBuild := new ProjectConfig()
    SdkEmitTaskKernels.ApplyMsBuildDefines(debugBuild, "Debug", null)
    assert debugBuild.Defines.Count == 1
    assert debugBuild.Defines[0] == "DEBUG"

    releaseBuild := new ProjectConfig()
    SdkEmitTaskKernels.ApplyMsBuildDefines(releaseBuild, "Release", null)
    assert releaseBuild.Defines.Count == 0

    // case-insensitively, and the word is the one `BuildCommandKernels` owns
    lowerCase := new ProjectConfig()
    SdkEmitTaskKernels.ApplyMsBuildDefines(lowerCase, BuildCommandKernels.GetConfigurationName(true).ToLowerInvariant(), null)
    assert lowerCase.Defines.Count == 0

    // MSBuild passing nothing is not a release build
    unset := new ProjectConfig()
    SdkEmitTaskKernels.ApplyMsBuildDefines(unset, null, null)
    assert unset.Defines.Count == 1
    assert unset.Defines[0] == "DEBUG"
}

test "the MSBuild DefineConstants list is split by the same extractor --define uses" {
    // Two separators, both ends trimmed, empty segments dropped, no duplicates: the task used to own
    // a second copy of all four of those rules.
    config := new ProjectConfig()
    SdkEmitTaskKernels.ApplyMsBuildDefines(config, "Release", " ALPHA ; ; BRAVO ,ALPHA, ")
    assert config.Defines.Count == 2
    assert config.Defines[0] == "ALPHA"
    assert config.Defines[1] == "BRAVO"

    // and the same string through the CLI's own door answers the same list
    viaCli := new List<string>()
    DefineArgumentKernels.AddDefineSymbols(viaCli, " ALPHA ; ; BRAVO ,ALPHA, ", 0)
    assert viaCli.Count == config.Defines.Count
    assert viaCli[0] == config.Defines[0]
    assert viaCli[1] == config.Defines[1]
}

test "DEBUG and the MSBuild define list arrive together, and DEBUG is never duplicated" {
    config := new ProjectConfig()
    config.Defines.Add("DEBUG")
    SdkEmitTaskKernels.ApplyMsBuildDefines(config, "Debug", "DEBUG;EXTRA")
    assert config.Defines.Count == 2
    assert config.Defines[0] == "DEBUG"
    assert config.Defines[1] == "EXTRA"
}

// ── the emitted assembly's identity, its message and its validation default ────

test "project.yml's version wins and MSBuild's AssemblyVersion is only a fallback" {
    assert SdkEmitTaskKernels.ResolveProjectVersion("2.5.0", "9.9.9.9") == "2.5.0"
    assert SdkEmitTaskKernels.ResolveProjectVersion(null, "9.9.9.9") == "9.9.9.9"
    assert SdkEmitTaskKernels.ResolveProjectVersion("", "9.9.9.9") == "9.9.9.9"
    assert SdkEmitTaskKernels.ResolveProjectVersion("   ", "9.9.9.9") == "9.9.9.9"
    // with neither, the project file's own answer is left exactly as it was
    assert SdkEmitTaskKernels.ResolveProjectVersion(null, null) == null
    assert SdkEmitTaskKernels.ResolveProjectVersion("", null) == ""
}

test "a successful emit prints one sentence, and it names the assembly it wrote" {
    message := SdkEmitTaskKernels.GetEmittedAssemblyMessage("obj/Debug/net10.0/Demo.dll")
    assert message == "Emitted N# IL assembly to obj/Debug/net10.0/Demo.dll"
    assert message.EndsWith("obj/Debug/net10.0/Demo.dll")
}

test "legacy analysis gates emission unless a project opts out" {
    assert SdkEmitTaskKernels.ValidatesWithLegacyAnalysisByDefault()
}

// ── the reference-assembly scope rewrite ──────────────────────────────────────
//
// This is the half that decides whether a C# project can consume an N# library at all. Without the
// rewrite `csc` reports `CS0012: The type 'Object' is defined in an assembly that is not
// referenced … 'System.Private.CoreLib, Version=10.0.0.0, Culture=neutral,
// PublicKeyToken=7cec85d7bea7798e'`, measured rather than assumed.

test "the implementation core library is named, and it is the only scope that gets rewritten" {
    assert SdkEmitTaskKernels.ImplementationCoreLibraryName() == "System.Private.CoreLib"
    assert SdkEmitTaskKernels.IsImplementationCoreLibrary("System.Private.CoreLib")

    // every reference-pack assembly is left alone — these are the exact scopes a real emit produces
    assert !SdkEmitTaskKernels.IsImplementationCoreLibrary("System.Runtime")
    assert !SdkEmitTaskKernels.IsImplementationCoreLibrary("System.Collections")
    assert !SdkEmitTaskKernels.IsImplementationCoreLibrary("System.Console")
    assert !SdkEmitTaskKernels.IsImplementationCoreLibrary("mscorlib")
    assert !SdkEmitTaskKernels.IsImplementationCoreLibrary("netstandard")
    // the comparison is ORDINAL, so case is identity
    assert !SdkEmitTaskKernels.IsImplementationCoreLibrary("system.private.corelib")
    // a type reference whose scope is not an assembly reference at all reaches here as null
    assert !SdkEmitTaskKernels.IsImplementationCoreLibrary(null)
}

test "a type reference moves only when it is corelib-scoped AND a reference owns the type" {
    assert SdkEmitTaskKernels.ShouldRescopeTypeReference("System.Private.CoreLib", true)
    // nothing owns it: leaving it alone beats pointing it at nothing
    assert !SdkEmitTaskKernels.ShouldRescopeTypeReference("System.Private.CoreLib", false)
    // already scoped correctly — this is the live `System.Console` case
    assert !SdkEmitTaskKernels.ShouldRescopeTypeReference("System.Console", true)
    assert !SdkEmitTaskKernels.ShouldRescopeTypeReference("System.Runtime", true)
    assert !SdkEmitTaskKernels.ShouldRescopeTypeReference(null, true)
}

test "a defining assembly outranks a forwarding facade whatever order they arrive in" {
    // `System.Object` is DEFINED by System.Runtime and FORWARDED by mscorlib and netstandard. If
    // precedence went the other way, the emitted TypeRef would name a facade and depend on how the
    // reference list happened to be ordered.
    forwarderFirst := new ReferenceTypeOwners()
    forwarderFirst.RecordForwarder("System.Object", "mscorlib")
    forwarderFirst.RecordDefinition("System.Object", "System.Runtime")
    assert forwarderFirst.Resolve("System.Object") == "System.Runtime"

    definitionFirst := new ReferenceTypeOwners()
    definitionFirst.RecordDefinition("System.Object", "System.Runtime")
    definitionFirst.RecordForwarder("System.Object", "mscorlib")
    assert definitionFirst.Resolve("System.Object") == "System.Runtime"

    // among two of a kind, the first seen keeps the type
    twoForwarders := new ReferenceTypeOwners()
    twoForwarders.RecordForwarder("System.Object", "mscorlib")
    twoForwarders.RecordForwarder("System.Object", "netstandard")
    assert twoForwarders.Resolve("System.Object") == "mscorlib"

    twoDefinitions := new ReferenceTypeOwners()
    twoDefinitions.RecordDefinition("System.Object", "System.Runtime")
    twoDefinitions.RecordDefinition("System.Object", "System.Private.CoreLib")
    assert twoDefinitions.Resolve("System.Object") == "System.Runtime"
}

test "a forwarded type with no definition anywhere still resolves to its facade" {
    owners := new ReferenceTypeOwners()
    owners.RecordForwarder("System.Xml.Linq.XDocument", "System.Xml.Linq")
    assert owners.Resolve("System.Xml.Linq.XDocument") == "System.Xml.Linq"
    assert owners.Owns("System.Xml.Linq.XDocument")
    assert owners.Resolve("System.Never.Heard.Of.It") == null
    assert !owners.Owns("System.Never.Heard.Of.It")
}

test "nested types are owned too, under the slash-separated name the metadata carries" {
    // The scan walks NestedTypes recursively; a top-level-only walk would leave every nested type
    // pointing at the implementation core library and break exactly the consumers it is there for.
    owners := new ReferenceTypeOwners()
    owners.RecordDefinition("System.Collections.Generic.List`1/Enumerator", "System.Collections")
    assert owners.Resolve("System.Collections.Generic.List`1/Enumerator") == "System.Collections"
}

test "the module pseudo-type owns nothing, and it is the only name excluded" {
    assert SdkEmitTaskKernels.ModuleTypeName() == "<Module>"
    assert !SdkEmitTaskKernels.ShouldRecordTypeOwner(SdkEmitTaskKernels.ModuleTypeName())
    assert SdkEmitTaskKernels.ShouldRecordTypeOwner("System.Object")
    assert SdkEmitTaskKernels.ShouldRecordTypeOwner("Module")

    owners := new ReferenceTypeOwners()
    owners.RecordDefinition("<Module>", "System.Runtime")
    owners.RecordForwarder("<Module>", "mscorlib")
    assert owners.IsEmpty
    assert owners.Resolve("<Module>") == null
}

test "with no known owners the reference assembly is the implementation assembly verbatim" {
    empty := new ReferenceTypeOwners()
    assert empty.IsEmpty
    assert empty.KnownTypeCount == 0
    assert SdkEmitTaskKernels.ShouldCopyImplementationVerbatim(empty)

    populated := new ReferenceTypeOwners()
    populated.RecordDefinition("System.Object", "System.Runtime")
    assert !populated.IsEmpty
    assert populated.KnownTypeCount == 1
    assert !SdkEmitTaskKernels.ShouldCopyImplementationVerbatim(populated)

    // a forwarder alone is enough to stop the verbatim copy
    forwardedOnly := new ReferenceTypeOwners()
    forwardedOnly.RecordForwarder("System.Object", "mscorlib")
    assert !SdkEmitTaskKernels.ShouldCopyImplementationVerbatim(forwardedOnly)
}

test "there is a reference assembly to synchronize only when MSBuild asked for one and emission produced one" {
    assert SdkEmitTaskKernels.ShouldSynchronizeReferenceAssembly("obj/Debug/net10.0/refint/Demo.dll", true)
    assert !SdkEmitTaskKernels.ShouldSynchronizeReferenceAssembly("obj/Debug/net10.0/refint/Demo.dll", false)
    assert !SdkEmitTaskKernels.ShouldSynchronizeReferenceAssembly(null, true)
    assert !SdkEmitTaskKernels.ShouldSynchronizeReferenceAssembly("", true)
    assert !SdkEmitTaskKernels.ShouldSynchronizeReferenceAssembly("   ", true)
}

test "two build outputs are the same output case-insensitively" {
    assert SdkEmitTaskKernels.IsSameOutputPath("/tmp/demo/Demo.dll", "/tmp/demo/Demo.dll")
    assert SdkEmitTaskKernels.IsSameOutputPath("/tmp/demo/Demo.dll", "/tmp/demo/demo.DLL")
    assert !SdkEmitTaskKernels.IsSameOutputPath("/tmp/demo/Demo.dll", "/tmp/demo/refint/Demo.dll")
}

test "a reference is scanned for owners only when it exists and is not one of the task's own outputs" {
    assert SdkEmitTaskKernels.ShouldScanReferenceForOwners("/tmp/packs/System.Runtime.dll", true, false)
    // a library must never be told that it owns its own types
    assert !SdkEmitTaskKernels.ShouldScanReferenceForOwners("/tmp/demo/Demo.dll", true, true)
    assert !SdkEmitTaskKernels.ShouldScanReferenceForOwners("/tmp/packs/Missing.dll", false, false)
    assert !SdkEmitTaskKernels.ShouldScanReferenceForOwners(null, true, false)
    assert !SdkEmitTaskKernels.ShouldScanReferenceForOwners("", true, false)
    assert !SdkEmitTaskKernels.ShouldScanReferenceForOwners("   ", true, false)
}

test "an assembly reference is reused only when BOTH its name and its version match" {
    assert SdkEmitTaskKernels.AssemblyReferenceMatches("System.Runtime", "10.0.0.0", "System.Runtime", "10.0.0.0")
    // a version-only difference is a DIFFERENT assembly, so a second reference row is added
    assert !SdkEmitTaskKernels.AssemblyReferenceMatches("System.Runtime", "9.0.0.0", "System.Runtime", "10.0.0.0")
    assert !SdkEmitTaskKernels.AssemblyReferenceMatches("System.Console", "10.0.0.0", "System.Runtime", "10.0.0.0")
    // name comparison is ordinal
    assert !SdkEmitTaskKernels.AssemblyReferenceMatches("system.runtime", "10.0.0.0", "System.Runtime", "10.0.0.0")
    // a version-less reference matches only another version-less one
    assert SdkEmitTaskKernels.AssemblyReferenceMatches("Demo", "", "Demo", "")
    assert !SdkEmitTaskKernels.AssemblyReferenceMatches("Demo", "", "Demo", "1.0.0.0")
}

test "the implementation core library reference is dropped once nothing scopes to it" {
    assert SdkEmitTaskKernels.ShouldRemoveCoreLibraryReference(false)
    assert !SdkEmitTaskKernels.ShouldRemoveCoreLibraryReference(true)
}
