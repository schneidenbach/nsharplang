namespace NSharpLang.EmitDeterminism.Tests

import System.IO
import NSharpLang.Compiler

func DeterminismSource(body: string): string {
    return "namespace Det\n" + "\n" + "class Counter {\n" + "    Total: int\n" + "\n" + "    constructor() {\n" + "        Total = 0\n" + "    }\n" + "\n" + "    func Add(value: int): int {\n" + body + "    }\n" + "}\n"
}

func DeterminismOriginalBody(): string {
    return "        Total = Total + value\n        return Total\n"
}

func DeterminismChangedBody(): string {
    return "        Total = Total + value + 1\n        return Total - 1\n"
}

test "two clean builds of the same source produce byte-identical implementation and reference assemblies" {
    scratch := DeterminismScratch("clean")
    try {
        projectDirectory := Path.Combine(scratch, "project")
        DeterminismWriteProject(projectDirectory, DeterminismSource(DeterminismOriginalBody()))

        first := DeterminismCompile(projectDirectory, Path.Combine(scratch, "out1"))
        second := DeterminismCompile(projectDirectory, Path.Combine(scratch, "out2"))

        assert DeterminismBytesEqual(File.ReadAllBytes(first.ImplementationPath), File.ReadAllBytes(second.ImplementationPath))
        assert DeterminismBytesEqual(File.ReadAllBytes(first.ReferencePath), File.ReadAllBytes(second.ReferencePath))
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "the module version id is derived from the emitted content and the timestamp says it is not a date" {
    scratch := DeterminismScratch("mvid")
    try {
        projectDirectory := Path.Combine(scratch, "project")
        DeterminismWriteProject(projectDirectory, DeterminismSource(DeterminismOriginalBody()))
        original := DeterminismCompile(projectDirectory, Path.Combine(scratch, "out1"))
        originalMvid := DeterminismModuleVersionId(original.ImplementationPath)
        originalTimestamp := DeterminismTimestamp(original.ImplementationPath)

        assert DeterminismGuidIsVersionFour(originalMvid), originalMvid
        assert DeterminismTimestampHighBitSet(original.ImplementationPath)

        // A changed body is a changed image, so it is a changed identity.
        DeterminismWriteProject(projectDirectory, DeterminismSource(DeterminismChangedBody()))
        changed := DeterminismCompile(projectDirectory, Path.Combine(scratch, "out2"))
        assert DeterminismModuleVersionId(changed.ImplementationPath) != originalMvid
        assert DeterminismTimestamp(changed.ImplementationPath) != originalTimestamp

        // Restoring the source restores the identity: it is a function of the content and of
        // nothing else — not the clock, not the output path, not the order of the builds.
        DeterminismWriteProject(projectDirectory, DeterminismSource(DeterminismOriginalBody()))
        restored := DeterminismCompile(projectDirectory, Path.Combine(scratch, "out3"))
        assert DeterminismModuleVersionId(restored.ImplementationPath) == originalMvid
        assert DeterminismTimestamp(restored.ImplementationPath) == originalTimestamp
        assert DeterminismBytesEqual(File.ReadAllBytes(original.ImplementationPath), File.ReadAllBytes(restored.ImplementationPath))
    } finally {
        Directory.Delete(scratch, true)
    }
}

// THE SURFACE AND THE IMPLEMENTATION CARRY DIFFERENT IDENTITIES, AND THAT IS THE POINT: the
// reference assembly's id is a hash of the SURFACE, so a body-only edit moves the implementation's
// and leaves the surface's alone. `CopyRefAssembly` compares module version ids for exactly this
// reason; it cannot read one out of anything but Roslyn's own output (see
// `tests/native/sdk-reference-incrementality`), so the SDK compares the bytes instead — but the
// identity itself is what makes the bytes comparable at all.
test "the reference assembly's module version id is the surface's, not the implementation's" {
    scratch := DeterminismScratch("surface")
    try {
        projectDirectory := Path.Combine(scratch, "project")
        DeterminismWriteProject(projectDirectory, DeterminismSource(DeterminismOriginalBody()))
        original := DeterminismCompile(projectDirectory, Path.Combine(scratch, "out1"))
        implementationMvid := DeterminismModuleVersionId(original.ImplementationPath)
        referenceMvid := DeterminismModuleVersionId(original.ReferencePath)
        assert implementationMvid != referenceMvid
        assert DeterminismGuidIsVersionFour(referenceMvid), referenceMvid

        DeterminismWriteProject(projectDirectory, DeterminismSource(DeterminismChangedBody()))
        changed := DeterminismCompile(projectDirectory, Path.Combine(scratch, "out2"))
        assert DeterminismModuleVersionId(changed.ImplementationPath) != implementationMvid
        assert DeterminismModuleVersionId(changed.ReferencePath) == referenceMvid
    } finally {
        Directory.Delete(scratch, true)
    }
}

// THE CONSEQUENCE DETERMINISM HAD ON REFERENCE RESOLUTION, PINNED WHERE THE RULE LIVES.
//
// Once two builds of one unchanged source carry the same module version id, the seed's
// `tools/NSharpLang.Compiler.Core.dll` and the copy on a project's reference path are the same
// bytes, and `ExternalAssemblyScan`'s "same module version id, keep what the host already has"
// shortcut starts answering a project's reference path with the HOST's build of the compiler. Under
// MSBuild that build is the TASK's, in MSBuild's plugin context, while the rest of the project's
// closure lands in the owned context: `NSharpLang.TestHost`, `LanguageServer` and
// `NSharpLang.Playground` all declined calls into the compiler they reference, and only a
// republished seed could see it. Every other identity the host carries is the same FILE the project
// resolves, and for those the shortcut is what keeps one identity out of two contexts.
test "the host's own build of the compiler may not stand in for a project's reference path" {
    assert !ExternalAssemblyScan.IsCompilerProductAssembly(null)
    assert ExternalAssemblyScan.IsCompilerProductAssembly(typeof(ExternalAssemblyScan).get_Assembly())
    assert ExternalAssemblyScan.IsCompilerProductAssembly(typeof(MultiFileCompiler).get_Assembly())
    assert !ExternalAssemblyScan.IsCompilerProductAssembly(typeof(DeterminismBuild).get_Assembly())
    assert !ExternalAssemblyScan.IsCompilerProductAssembly(typeof(string).get_Assembly())
}
