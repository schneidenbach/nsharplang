namespace NSharpLang.Cli

// THE `nlc build` / `nlc run` CONFIGURATION AND EXIT-CODE KERNELS.
//
// `BuildCommandKernels` had NO estate contract file before 021/6 — it is the largest of the build
// kernels and nothing in `.nl` pinned any of it. These blocks pin the two answers slice 6 moved out
// of `src/NSharpLang.Cli/Program.Backends.cs`, plus the predicate that is now defined from one of
// them, so the pair cannot drift back apart.

// ── the configuration names ───────────────────────────────────────────────────
test "the two build configurations are exactly Release and Debug" {
    assert BuildCommandKernels.GetConfigurationName(true) == "Release"
    assert BuildCommandKernels.GetConfigurationName(false) == "Debug"
    assert BuildCommandKernels.GetConfigurationName(true) != BuildCommandKernels.GetConfigurationName(false)
}

test "the DEBUG define is applied for every configuration EXCEPT the release one" {
    // The predicate used to restate `"Release"` in its own comparison while the CLI spelled the
    // ternary; it now reads the name owner, so the word that picks the output folder and the word
    // that suppresses the define are the same word.
    assert !BuildCommandKernels.ShouldApplyDebugDefine(BuildCommandKernels.GetConfigurationName(true))
    assert BuildCommandKernels.ShouldApplyDebugDefine(BuildCommandKernels.GetConfigurationName(false))
    // the comparison is case-INSENSITIVE and that is deliberate: a project.yml may say "release"
    assert !BuildCommandKernels.ShouldApplyDebugDefine("release")
    assert !BuildCommandKernels.ShouldApplyDebugDefine("RELEASE")
    // anything else is a debug build
    assert BuildCommandKernels.ShouldApplyDebugDefine("Profile")
}

test "the configuration name is what the output directory is built from" {
    releaseDir := BuildCommandKernels.GetOutputDirectory("/tmp/demo", BuildCommandKernels.GetConfigurationName(true), "net10.0", null)
    debugDir := BuildCommandKernels.GetOutputDirectory("/tmp/demo", BuildCommandKernels.GetConfigurationName(false), "net10.0", null)

    assert releaseDir.Contains("Release")
    assert debugDir.Contains("Debug")
    assert releaseDir != debugDir
}

// ── the build exit code ───────────────────────────────────────────────────────

test "a build that produced no output assembly exits 1, and one that did exits 0" {
    // This replaces two bare `return 1;`s in `Program.Backends.cs` that carried no sentence, so
    // nothing else in the pipeline classified them.
    assert BuildCommandKernels.GetExitCode(false) == 1
    assert BuildCommandKernels.GetExitCode(true) == 0
}
