namespace NSharpLang.SdkReferenceIncrementality.Tests

import System
import System.IO

func IncrementalityOriginalBody(): string {
    return "        return \"hello \" + Name\n"
}

func IncrementalityChangedBody(): string {
    return "        return \"a completely different greeting for \" + Name + \"!\"\n"
}

func IncrementalityNoExtraMember(): string {
    return ""
}

func IncrementalityExtraMember(): string {
    return "\n    func Repeat(times: int): string {\n        return Name\n    }\n"
}

test "a dependent does not re-emit when only a referenced project's implementation changed" {
    repositoryRoot := IncrementalityRepositoryRoot()
    IncrementalityPrepareFeed(repositoryRoot)
    scratch := IncrementalityScratch("pair")
    try {
        IncrementalityWriteResolution(scratch)
        IncrementalityWritePair(scratch, IncrementalityOriginalBody(), IncrementalityNoExtraMember())

        cold := IncrementalityBuildConsumer(scratch)
        IncrementalityRequireSuccess(cold, "cold build of A")
        assert IncrementalityEmitted(cold, "B"), "cold/B " + cold.Stdout
        assert IncrementalityEmitted(cold, "A"), "cold/A " + cold.Stdout

        noop := IncrementalityBuildConsumer(scratch)
        IncrementalityRequireSuccess(noop, "no-op rebuild of A")
        assert !IncrementalityEmitted(noop, "B"), "noop/B " + noop.Stdout
        assert !IncrementalityEmitted(noop, "A"), "noop/A " + noop.Stdout

        // A METHOD BODY ONLY. B's implementation is different IL, a different string literal and a
        // different `B.dll`; its SURFACE is the same surface, so its reference assembly is the same
        // bytes, `refint/B.dll` is not rewritten, `ref/B.dll` keeps its timestamp, and A's emit
        // target — whose `Inputs` name `@(ReferencePathWithRefAssemblies)` — stays up to date.
        IncrementalityWriteLibrary(scratch, IncrementalityChangedBody(), IncrementalityNoExtraMember())
        bodyEdit := IncrementalityBuildConsumer(scratch)
        IncrementalityRequireSuccess(bodyEdit, "rebuild of A after a body-only edit in B")
        assert IncrementalityEmitted(bodyEdit, "B"), "body/B " + bodyEdit.Stdout
        assert !IncrementalityEmitted(bodyEdit, "A"), "body/A " + bodyEdit.Stdout

        referenceAssembly := Path.Combine(Path.Combine(scratch, "B"), Path.Combine("obj", Path.Combine("Debug", Path.Combine("net10.0", Path.Combine("ref", "B.dll")))))
        assert File.Exists(referenceAssembly)

        // A PUBLIC MEMBER. The surface moved, so the reference assembly moved, so A rebuilds.
        IncrementalityWriteLibrary(scratch, IncrementalityChangedBody(), IncrementalityExtraMember())
        surfaceEdit := IncrementalityBuildConsumer(scratch)
        IncrementalityRequireSuccess(surfaceEdit, "rebuild of A after a surface edit in B")
        assert IncrementalityEmitted(surfaceEdit, "B"), "surface/B " + surfaceEdit.Stdout
        assert IncrementalityEmitted(surfaceEdit, "A"), "surface/A " + surfaceEdit.Stdout
    } finally {
        Directory.Delete(scratch, true)
    }
}

// The mechanism, pinned where it is written rather than only where it is observed: a future edit
// that puts `@(ReferencePath)` back into `Inputs` would silently restore the old behaviour, because
// that item's identity for a project reference is the IMPLEMENTATION in `bin/` and
// `CopyFilesToOutputDirectory` rewrites it on every emit.
test "the emit target's up-to-date check reads the ref-substituted reference list" {
    repositoryRoot := IncrementalityRepositoryRoot()
    targets := File.ReadAllText(
        Path.Combine(
            Path.Combine(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Sdk"), "Sdk"),
            "Sdk.targets"
        )
    )
    emitTarget := targets.Substring(targets.IndexOf("<Target Name=\"EmitNSharpIlAssembly\"", StringComparison.Ordinal))
    header := emitTarget.Substring(0, emitTarget.IndexOf(">", StringComparison.Ordinal))
    assert header.Contains("DependsOnTargets=\"FindReferenceAssembliesForReferences\""), header
    assert header.Contains("Inputs=\""), header
    assert header.Contains("@(ReferencePathWithRefAssemblies)"), header
    assert !header.Contains("@(ReferencePath);"), header

    // The task itself still receives the implementations: the columnar back end binds against
    // runtime `Type` objects, and the CLR refuses to load an assembly carrying
    // `[ReferenceAssembly]` for execution.
    assert emitTarget.Contains("References=\"@(ReferencePath)\""), emitTarget
}
