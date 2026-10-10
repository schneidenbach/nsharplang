namespace NSharpLang.IncrementalBuild.Tests

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler

// THE UP-TO-DATE CHECK ANSWERS ONLY WHEN NOTHING THE COMPILATION READ HAS CHANGED.
//
// Every row builds a fresh project twice to arm the stamp, changes exactly one input, and builds
// again. The rebuild must run (not be answered from the stamp), and what it produced must be what a
// build with the incremental machinery switched off produces from the same inputs — so a row fails
// both when an input is missed and when a hit would have handed back stale bytes.
func ArmedProject(label: string): string {
    scratch := IncrementalScratch(label)
    IncrementalWriteProject(scratch)
    first := IncrementalBuild(scratch)
    assert first.Success, first.Diagnostics
    assert !first.UpToDate
    second := IncrementalBuild(scratch)
    assert second.Success, second.Diagnostics
    assert second.UpToDate, "an unchanged project must be answered from its stamp"
    return scratch
}

// The rebuild after a change: it ran, and it matches a from-scratch compilation of the same inputs.
func AssertRebuiltLikeAFullBuild(scratch: string, configure: Action<ProjectConfig>?, prepare: Action<MultiFileCompiler>?) {
    rebuilt := IncrementalBuildWith(scratch, configure, prepare, true)
    assert !rebuilt.UpToDate, "a changed input must not be answered from the stamp"
    full := IncrementalBuildWith(scratch, configure, prepare, false)
    assert rebuilt.Success == full.Success
    assert rebuilt.Diagnostics == full.Diagnostics, rebuilt.Diagnostics + " | " + full.Diagnostics
    assert rebuilt.OutputHash == full.OutputHash
    again := IncrementalBuildWith(scratch, configure, prepare, true)
    if rebuilt.Success {
        assert again.UpToDate, "the rebuild must re-arm the stamp"
        assert again.Diagnostics == full.Diagnostics
        assert again.OutputHash == full.OutputHash
    }
}

func AssertRebuilt(scratch: string) {
    AssertRebuiltLikeAFullBuild(scratch, null, null)
}

test "an unchanged project is answered from its stamp with the same output and warnings" {
    scratch := IncrementalScratch("unchanged")
    try {
        IncrementalWriteProject(scratch)
        full := IncrementalBuildConfigured(scratch, null, false)
        assert full.Success, full.Diagnostics
        assert full.Diagnostics.Contains("NL907"), "the fixture is meant to carry a warning: " + full.Diagnostics
        assert !File.Exists(IncrementalStampPath(scratch)), "a compilation that did not ask for a stamp writes none"
        first := IncrementalBuild(scratch)
        assert !first.UpToDate
        assert File.Exists(IncrementalStampPath(scratch))
        second := IncrementalBuild(scratch)
        assert second.UpToDate
        assert second.Success
        assert second.Diagnostics == full.Diagnostics, second.Diagnostics
        assert second.OutputHash == full.OutputHash
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "rewriting a source with identical bytes and a new timestamp stays up to date" {
    scratch := ArmedProject("touch")
    try {
        path := Path.Combine(scratch, "Math.nl")
        File.WriteAllText(path, File.ReadAllText(path))
        File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddHours(1))
        outcome := IncrementalBuild(scratch)
        assert outcome.UpToDate, "content, not time, decides"
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "a one-character body edit invalidates" {
    scratch := ArmedProject("body")
    try {
        path := Path.Combine(scratch, "Math.nl")
        File.WriteAllText(path, File.ReadAllText(path).Replace("value * 2", "value * 3"))
        AssertRebuilt(scratch)
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "an edit that introduces an error is reported, and fixing it builds again" {
    scratch := ArmedProject("error")
    try {
        path := Path.Combine(scratch, "Report.nl")
        original := File.ReadAllText(path)
        File.WriteAllText(path, original.Replace("Twice(", "Thrice("))
        AssertRebuilt(scratch)
        failing := IncrementalBuild(scratch)
        assert !failing.Success
        assert !failing.UpToDate, "a failed compilation writes no stamp"

        // Back to the sources the stamp describes: the output on disk IS their output (the failed
        // compilations never wrote one), so the stamp answers, and what it answers is exactly what a
        // full build of these sources produces.
        File.WriteAllText(path, original)
        restored := IncrementalBuild(scratch)
        assert restored.UpToDate
        full := IncrementalBuildConfigured(scratch, null, false)
        assert restored.Diagnostics == full.Diagnostics
        assert restored.OutputHash == full.OutputHash
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "adding, deleting and renaming a source file each invalidate" {
    scratch := ArmedProject("files")
    try {
        added := Path.Combine(scratch, "Extra.nl")
        File.WriteAllText(added, "namespace Lib\n\nfunc Extra(): int {\n    return 7\n}\n")
        AssertRebuilt(scratch)

        renamed := Path.Combine(scratch, "Zextra.nl")
        File.Move(added, renamed)
        AssertRebuilt(scratch)

        File.Delete(renamed)
        AssertRebuilt(scratch)
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "a test file the build does not compile still invalidates, because the analyzer reads it" {
    scratch := ArmedProject("tests-file")
    try {
        File.WriteAllText(Path.Combine(scratch, "Math.tests.nl"), "namespace Lib\n\ntest \"twice\" {\n    assert Twice(2) == 4\n}\n")
        AssertRebuilt(scratch)
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "any edit to project.yml invalidates, even a comment" {
    scratch := ArmedProject("project-yml")
    try {
        File.WriteAllText(Path.Combine(scratch, "project.yml"), IncrementalProjectYml() + "# a comment\n")
        AssertRebuilt(scratch)
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "a define, a configuration value and a compile option each invalidate" {
    scratch := ArmedProject("options")
    try {
        AssertRebuiltLikeAFullBuild(scratch, config => config.Defines.Add("FEATURE_X"), null)
        AssertRebuiltLikeAFullBuild(scratch, config => config.InternalsVisibleTo.Add("Friend"), null)
        AssertRebuiltLikeAFullBuild(scratch, null, EnableReferenceAssembly)
        AssertRebuiltLikeAFullBuild(scratch, null, EnableAotMode)
    } finally {
        IncrementalCleanup(scratch)
    }
}

func EnableReferenceAssembly(compiler: MultiFileCompiler) {
    compiler.EmitReferenceAssembly = true
}

func EnableAotMode(compiler: MultiFileCompiler) {
    compiler.AotMode = true
}

test "an editorconfig appearing beside the sources invalidates" {
    scratch := ArmedProject("editorconfig")
    try {
        File.WriteAllText(Path.Combine(scratch, ".editorconfig"), "root = true\n\n[*.nl]\nindent_size = 4\n")
        AssertRebuilt(scratch)
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "a deleted or modified output invalidates" {
    scratch := ArmedProject("output")
    try {
        output := IncrementalOutputPath(scratch)
        File.Delete(output)
        AssertRebuilt(scratch)

        bytes := File.ReadAllBytes(output)
        bytes[bytes.Length - 1] = (byte)(bytes[bytes.Length - 1] ^ 255)
        File.WriteAllBytes(output, bytes)
        AssertRebuilt(scratch)
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "a corrupt, truncated or foreign stamp is ignored and rewritten" {
    scratch := ArmedProject("stamp")
    try {
        stampPath := IncrementalStampPath(scratch)
        bytes := File.ReadAllBytes(stampPath)
        bytes[bytes.Length / 2] = (byte)(bytes[bytes.Length / 2] ^ 1)
        File.WriteAllBytes(stampPath, bytes)
        AssertRebuilt(scratch)

        whole := File.ReadAllBytes(stampPath)
        truncated := new byte[whole.Length - 7]
        Array.Copy(whole, truncated, truncated.Length)
        File.WriteAllBytes(stampPath, truncated)
        AssertRebuilt(scratch)

        File.WriteAllText(stampPath, "not a stamp")
        AssertRebuilt(scratch)
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "a referenced assembly's content invalidates its consumer" {
    scratch := IncrementalScratch("dll")
    try {
        dependencyDirectory := Path.Combine(scratch, "dep")
        Directory.CreateDirectory(dependencyDirectory)
        File.WriteAllText(Path.Combine(dependencyDirectory, "project.yml"), "name: Dep\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(Path.Combine(dependencyDirectory, "Dep.nl"), "namespace Dep\n\nfunc Base(): int {\n    return 1\n}\n")
        dependencyOutput := Path.Combine(dependencyDirectory, "out", "Dep.dll")
        BuildDependency(dependencyDirectory, dependencyOutput)

        consumer := Path.Combine(scratch, "app")
        IncrementalWriteProject(consumer)
        File.WriteAllText(Path.Combine(consumer, "project.yml"), IncrementalProjectYml() + "dependencies:\n  - dll: " + dependencyOutput + "\n")
        first := IncrementalBuild(consumer)
        assert first.Success, first.Diagnostics
        second := IncrementalBuild(consumer)
        assert second.UpToDate

        File.WriteAllText(Path.Combine(dependencyDirectory, "Dep.nl"), "namespace Dep\n\nfunc Base(): int {\n    return 2\n}\n\nfunc More(): int {\n    return 3\n}\n")
        BuildDependency(dependencyDirectory, dependencyOutput)
        AssertRebuilt(consumer)
    } finally {
        IncrementalCleanup(scratch)
    }
}

func BuildDependency(projectDirectory: string, outputPath: string) {
    config := ProjectFileParser.Parse(Path.Combine(projectDirectory, "project.yml"))
    compiler := new MultiFileCompiler(config.GetSourceFiles(projectDirectory, false), projectDirectory, config)
    Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? projectDirectory)
    result := compiler.CompileToIlAssembly("Dep", outputPath, false)
    assert result.Success
}

// The record's positional parameters are members too; the stamp writes them through the constructor.
test "the stamp carries every settable member of CompilerError" {
    expected := new List<string>(IncrementalBuildStamp.SerializedErrorMembers())
    expected.AddRange(IncrementalBuildStamp.ConstructorErrorMembers())
    expected.Sort(StringComparer.Ordinal)
    actual := new List<string>()
    for property in typeof(CompilerError).GetProperties(BindingFlags.Public | BindingFlags.Instance) {
        if property.CanWrite {
            actual.Add(property.Name)
        }
    }
    for field in typeof(CompilerError).GetFields(BindingFlags.Public | BindingFlags.Instance) {
        actual.Add(field.Name)
    }
    actual.Sort(StringComparer.Ordinal)
    assert string.Join(",", actual) == string.Join(",", expected), string.Join(",", actual)
}

test "an output outside the project writes no stamp and leaves the source tree untouched" {
    scratch := IncrementalScratch("outside")
    elsewhere := IncrementalScratch("outside-output")
    try {
        IncrementalWriteProject(scratch)
        config := ProjectFileParser.Parse(Path.Combine(scratch, "project.yml"))
        outputPath := Path.Combine(elsewhere, "Lib.dll")
        first := new MultiFileCompiler(config.GetSourceFiles(scratch, false), scratch, config)
        first.IncrementalBuild = true
        assert first.CompileToIlAssembly("Lib", outputPath, true).Success
        assert !Directory.Exists(Path.Combine(scratch, "obj"))
        second := new MultiFileCompiler(config.GetSourceFiles(scratch, false), scratch, config)
        second.IncrementalBuild = true
        assert second.CompileToIlAssembly("Lib", outputPath, true).Success
        assert !second.WasUpToDate
    } finally {
        IncrementalCleanup(scratch)
        IncrementalCleanup(elsewhere)
    }
}
