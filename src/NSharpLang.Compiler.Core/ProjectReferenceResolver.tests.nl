namespace NSharpLang.Compiler

import System
import System.IO

// THE PROJECT-REFERENCE RESOLUTION THAT TURNS A `project:` DEPENDENCY INTO SOMETHING MSBUILD CAN
// REFERENCE, AND INTO SOMETHING `nlc` CAN COMPILE.
//
// These blocks replace TWO `[Fact]`s deleted from `tests/IlSdkToolchainTests.cs`:
// `ProjectReferenceResolver_ResolvesProjectYmlToNamedCsproj` and
// `_ResolvesProjectYmlToNSharpProjectRoot` (24 and 23 declaration lines, ONE `Assert.` row each).
// Both wrote a `Shared/project.yml` — one of them also a `SharedLib.csproj` — and asserted a
// single resolved path.
//
// WHAT THE TWO DELETED ROWS COULD NOT SAY. `ResolveMsBuildProjectPath` has FOUR ways to answer and
// the deleted row exercised only the first: a csproj named for the project's `name:` field. The
// other three — a single `.csproj` of any name, a `.csproj` named for the DIRECTORY, and the
// failure — decide what happens to every project whose `name:` and file name disagree, which is
// the ordinary case after a rename. The ORDER between them is the rule, and it is stated here.
//
// A THIRD FILE IS NOT NEEDED TO CATCH A REGRESSION IN THE FIRST ARM: the named-csproj arm and the
// directory-named arm are only distinguishable when the two names DIFFER, so every block below
// keeps them different on purpose.
func NewProjectDirectory(): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-projectref-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func WriteSharedProject(directory: string, name: string): string {
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: " + name + "\noutputType: library\ntargetFramework: net10.0\n")
    return Path.Combine(directory, "project.yml")
}

func WriteCsproj(directory: string, fileName: string) {
    File.WriteAllText(Path.Combine(directory, fileName), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
}

// ── the two deleted rows, reproduced whole ────────────────────────────────────

test "a project.yml resolves to the csproj named for the project's own name field" {
    root := NewProjectDirectory()
    sharedDirectory := Path.Combine(root, "Shared")
    Directory.CreateDirectory(sharedDirectory)
    projectYml := WriteSharedProject(sharedDirectory, "SharedLib")
    WriteCsproj(sharedDirectory, "SharedLib.csproj")

    assert ProjectReferenceResolver.ResolveMsBuildProjectPath(projectYml) == Path.Combine(sharedDirectory, "SharedLib.csproj")

    Directory.Delete(root, true)
}

test "a project.yml with no csproj beside it resolves to its own DIRECTORY as an N# project root" {
    root := NewProjectDirectory()
    sharedDirectory := Path.Combine(root, "Shared")
    Directory.CreateDirectory(sharedDirectory)
    projectYml := WriteSharedProject(sharedDirectory, "SharedLib")

    assert ProjectReferenceResolver.ResolveNSharpProjectRoot(projectYml) == sharedDirectory

    Directory.Delete(root, true)
}

// ── the four MSBuild arms, in order ───────────────────────────────────────────

test "a .csproj path is returned unchanged, without the project.yml being read at all" {
    root := NewProjectDirectory()
    WriteCsproj(root, "Whatever.csproj")

    // NO project.yml EXISTS HERE. A resolver that parsed one first would throw.
    assert ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(root, "Whatever.csproj")) == Path.Combine(root, "Whatever.csproj")
    // and the suffix check ignores case
    assert ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(root, "Whatever.CSPROJ")) == Path.Combine(root, "Whatever.CSPROJ")

    Directory.Delete(root, true)
}

test "the NAMED csproj beats the DIRECTORY-named one when the two disagree" {
    // THE ONE ORDERING THAT IS OBSERVABLE, AND THE MUTATION PANEL IS WHY IT IS SPELLED THIS WAY.
    // The first draft of this block put `SharedLib.csproj` beside `Legacy.csproj` and claimed it
    // proved the NAMED arm beats the SINGLE-csproj arm. Mutation M4 swapped those two arms in the
    // resolver and NOTHING went red: with two csprojs present the single-csproj arm cannot answer
    // at all, so their order is unobservable — a fact now recorded rather than a claim asserted.
    //
    // The named arm and the DIRECTORY-named arm CAN both answer at once, and they disagree here:
    // `name:` says SharedLib, the folder says Renamed, and both csprojs exist.
    root := NewProjectDirectory()
    projectDirectory := Path.Combine(root, "Renamed")
    Directory.CreateDirectory(projectDirectory)
    WriteSharedProject(projectDirectory, "SharedLib")
    WriteCsproj(projectDirectory, "SharedLib.csproj")
    WriteCsproj(projectDirectory, "Renamed.csproj")

    assert ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(projectDirectory, "project.yml")) == Path.Combine(projectDirectory, "SharedLib.csproj")

    Directory.Delete(root, true)
}

test "the SINGLE-csproj arm and the NAMED arm never disagree, so their order is not a contract" {
    // MEASURED AND RECORDED. The two arms overlap only when there is exactly ONE csproj AND it is
    // named for the project — in which case they return the same path. Any other configuration
    // leaves exactly one of them applicable.
    both := NewProjectDirectory()
    WriteSharedProject(both, "SharedLib")
    WriteCsproj(both, "SharedLib.csproj")
    assert ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(both, "project.yml")) == Path.Combine(both, "SharedLib.csproj")

    onlySingle := NewProjectDirectory()
    WriteSharedProject(onlySingle, "SharedLib")
    WriteCsproj(onlySingle, "Legacy.csproj")
    assert ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(onlySingle, "project.yml")) == Path.Combine(onlySingle, "Legacy.csproj")

    Directory.Delete(both, true)
    Directory.Delete(onlySingle, true)
}

test "a SINGLE csproj of any name answers when no csproj carries the project's name" {
    root := NewProjectDirectory()
    WriteSharedProject(root, "SharedLib")
    WriteCsproj(root, "CompletelyDifferent.csproj")

    assert ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(root, "project.yml")) == Path.Combine(root, "CompletelyDifferent.csproj")

    Directory.Delete(root, true)
}

test "with TWO wrongly-named csprojs the DIRECTORY name decides, and neither of the two wins" {
    // This is the arm that rescues a renamed project: `name:` says one thing, the folder says
    // another, and there is no single candidate to fall back on.
    root := NewProjectDirectory()
    projectDirectory := Path.Combine(root, "Renamed")
    Directory.CreateDirectory(projectDirectory)
    WriteSharedProject(projectDirectory, "SharedLib")
    WriteCsproj(projectDirectory, "Renamed.csproj")
    WriteCsproj(projectDirectory, "Legacy.csproj")

    assert ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(projectDirectory, "project.yml")) == Path.Combine(projectDirectory, "Renamed.csproj")

    Directory.Delete(root, true)
}

test "two wrongly-named csprojs and no directory-named one is a FAILURE, not an arbitrary pick" {
    // THE DELETED BODIES NEVER REACHED A FAILURE. Picking either candidate would build the wrong
    // project silently, so the resolver refuses.
    root := NewProjectDirectory()
    projectDirectory := Path.Combine(root, "Renamed")
    Directory.CreateDirectory(projectDirectory)
    WriteSharedProject(projectDirectory, "SharedLib")
    WriteCsproj(projectDirectory, "AlphaLegacy.csproj")
    WriteCsproj(projectDirectory, "BetaLegacy.csproj")

    threw := false
    try {
        ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(projectDirectory, "project.yml"))
    } catch {
        threw = true
    }

    assert threw

    Directory.Delete(root, true)
}

test "a path that is neither a csproj nor a yaml project is rejected" {
    root := NewProjectDirectory()
    File.WriteAllText(Path.Combine(root, "Program.nl"), "func Main() {\n}\n")

    threw := false
    try {
        ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(root, "Program.nl"))
    } catch {
        threw = true
    }

    assert threw

    Directory.Delete(root, true)
}

// ── the N# project-root arms ──────────────────────────────────────────────────

test "a DIRECTORY containing project.yml resolves to itself" {
    root := NewProjectDirectory()
    WriteSharedProject(root, "SharedLib")

    assert ProjectReferenceResolver.ResolveNSharpProjectRoot(root) == Path.GetFullPath(root)

    Directory.Delete(root, true)
}

test "a directory WITHOUT a project.yml is a failure, not an empty answer" {
    root := NewProjectDirectory()

    threw := false
    try {
        ProjectReferenceResolver.ResolveNSharpProjectRoot(root)
    } catch {
        threw = true
    }

    assert threw

    Directory.Delete(root, true)
}

test "a path that does not exist at all is a failure" {
    missing := Path.Combine(Path.GetTempPath(), "nsharp-projectref-missing-" + Guid.NewGuid().ToString("N"))

    threw := false
    try {
        ProjectReferenceResolver.ResolveNSharpProjectRoot(Path.Combine(missing, "project.yml"))
    } catch {
        threw = true
    }

    assert threw
}

test "a blank reference path is rejected by both entry points before any disk access" {
    resolverThrew := false
    try {
        ProjectReferenceResolver.ResolveNSharpProjectRoot("   ")
    } catch {
        resolverThrew = true
    }

    msbuildThrew := false
    try {
        ProjectReferenceResolver.ResolveMsBuildProjectPath("   ")
    } catch {
        msbuildThrew = true
    }

    assert resolverThrew
    assert msbuildThrew
}

// ── the suffix predicate the two entry points share ───────────────────────────

test "both yaml suffixes count as a project path, in either case, and nothing else does" {
    assert ProjectReferenceResolver.IsYamlProjectPath("project.yml")
    assert ProjectReferenceResolver.IsYamlProjectPath("project.yaml")
    assert ProjectReferenceResolver.IsYamlProjectPath("PROJECT.YML")
    assert ProjectReferenceResolver.IsYamlProjectPath("Project.YAML")

    assert (ProjectReferenceResolver.IsYamlProjectPath("project.json")) == false
    assert (ProjectReferenceResolver.IsYamlProjectPath("Shared.csproj")) == false
    assert (ProjectReferenceResolver.IsYamlProjectPath("project")) == false
}

test "a .yaml project resolves the same way a .yml one does" {
    root := NewProjectDirectory()
    File.WriteAllText(Path.Combine(root, "project.yaml"), "name: SharedLib\noutputType: library\ntargetFramework: net10.0\n")

    assert ProjectReferenceResolver.ResolveNSharpProjectRoot(Path.Combine(root, "project.yaml")) == Path.GetFullPath(root)

    Directory.Delete(root, true)
}
