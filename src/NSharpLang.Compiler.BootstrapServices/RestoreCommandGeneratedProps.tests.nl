namespace NSharpLang.Cli.Commands

import System
import System.IO

// `nlc restore`'s GENERATED `obj/project.g.props`, END TO END OVER A REAL PROJECT TREE.
//
// These blocks replace ONE `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `RestoreCommand_DeduplicatesProjectReferencesInGeneratedProps` (54 declaration lines, 3
// `Assert.` rows). It writes two project.yml files to a temporary tree, calls
// `RestoreCommand.Restore`, and reads the generated props back.
//
// THE ROUTE IS THE ESTATE, MEASURED RATHER THAN ASSUMED. Slice 43's finisher sketch predicted this
// body "wants the native route" because it writes files to disk. It does not: `RestoreCommand` is
// N#-owned and in this assembly, and the whole path — `Directory.CreateDirectory`,
// `File.WriteAllText`, `File.ReadAllText`, `Path.Combine` — emits here. No process is spawned by
// `Restore`, so there is nothing a spawned `nlc` would prove that this does not.
//
// THE DELETED BODY CARRIED A PRIVATE `CountOccurrences` HELPER, a hand-rolled `IndexOf` loop, to
// count `<ProjectReference Include=` in the answer. Two-argument `IndexOf` declines on this emit
// path, so the count is done by splitting on the marker instead — which is the same measurement.

func CountOccurrences(text: string, value: string): int {
    return text.Split(value).Length - 1
}

func NewRestoreTree(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-restore-dedup-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(Path.Combine(root, "App"))
    Directory.CreateDirectory(Path.Combine(root, "Shared"))

    File.WriteAllText(Path.Combine(Path.Combine(root, "Shared"), "project.yml"),
        "name: Shared\n"
        + "outputType: library\n"
        + "targetFramework: net10.0\n")
    File.WriteAllText(Path.Combine(Path.Combine(root, "Shared"), "Shared.csproj"),
        "<Project Sdk=\"NSharpLang.Sdk\" />")
    File.WriteAllText(Path.Combine(Path.Combine(root, "App"), "project.yml"),
        "name: App\n"
        + "outputType: exe\n"
        + "targetFramework: net10.0\n"
        + "\n"
        + "dependencies:\n"
        + "  - nuget: Serilog\n"
        + "    version: 3.1.1\n"
        + "  - framework: Microsoft.AspNetCore.App\n"
        + "  - project: ../Shared/project.yml\n"
        + "  - project: ../Shared/Shared.csproj\n"
        + "  - project: ../Shared/project.yml\n")

    return root
}

test "three project references that resolve to ONE csproj are emitted once" {
    root := NewRestoreTree()
    try {
        appDirectory := Path.Combine(root, "App")

        assert RestoreCommand.Restore(appDirectory, true) == 0

        props := File.ReadAllText(Path.Combine(Path.Combine(appDirectory, "obj"), "project.g.props"))
        assert CountOccurrences(props, "<ProjectReference Include=") == 1
        assert props.Contains(Path.Combine(Path.Combine(root, "Shared"), "Shared.csproj"))
    } finally {
        Directory.Delete(root, true)
    }
}

test "the SAME generated props carries the project's own facts, which the deleted body never read" {
    // THREE CLAIMS THE DELETED BODY COULD NOT MAKE. It asserted the reference count and the
    // reference path and nothing else, so a restore that wrote the right reference into a props
    // file describing the WRONG project would have passed it. `outputType: exe` must become `Exe`,
    // the project name must be `App`, and the framework must be the one in the project.yml.
    root := NewRestoreTree()
    try {
        appDirectory := Path.Combine(root, "App")

        assert RestoreCommand.Restore(appDirectory, true) == 0

        props := File.ReadAllText(Path.Combine(Path.Combine(appDirectory, "obj"), "project.g.props"))
        assert props.Contains("<OutputType>Exe</OutputType>")
        assert props.Contains("<AssemblyName>App</AssemblyName>")
        assert props.Contains("<TargetFramework>net10.0</TargetFramework>")
    } finally {
        Directory.Delete(root, true)
    }
}

test "the NUGET and FRAMEWORK dependencies are NOT project references" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. Its fixture carried a `nuget:` and a `framework:`
    // entry beside the three project entries and asserted nothing about either, so a restore that
    // turned every dependency into a `<ProjectReference>` would have failed only on the count.
    root := NewRestoreTree()
    try {
        appDirectory := Path.Combine(root, "App")
        assert RestoreCommand.Restore(appDirectory, true) == 0

        props := File.ReadAllText(Path.Combine(Path.Combine(appDirectory, "obj"), "project.g.props"))
        assert !props.Contains("Serilog")
        assert !props.Contains("Microsoft.AspNetCore.App")
    } finally {
        Directory.Delete(root, true)
    }
}

test "restore RECURSES into the referenced project and generates its props too" {
    // A CLAIM THE DELETED BODY COULD NOT MAKE AT ALL. `RestoreRecursive` walks project references
    // and restores each one; the deleted body only ever looked in `App/obj`. The referenced
    // project is a LIBRARY, which is also the other side of the `outputType` rule above.
    root := NewRestoreTree()
    try {
        assert RestoreCommand.Restore(Path.Combine(root, "App"), true) == 0

        sharedProps := Path.Combine(Path.Combine(Path.Combine(root, "Shared"), "obj"), "project.g.props")
        assert File.Exists(sharedProps)
        assert File.ReadAllText(sharedProps).Contains("<OutputType>Library</OutputType>")
        assert File.ReadAllText(sharedProps).Contains("<AssemblyName>Shared</AssemblyName>")
    } finally {
        Directory.Delete(root, true)
    }
}

test "a directory with no project.yml fails quietly with exit 1" {
    // THE FAILURE ARM, WHICH THE DELETED BODY NEVER REACHED. `quiet` suppresses the sentence; the
    // exit code is the whole answer.
    root := Path.Combine(Path.GetTempPath(), "nsharp-restore-empty-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    try {
        assert RestoreCommand.Restore(root, true) == 1
        assert !Directory.Exists(Path.Combine(root, "obj"))
    } finally {
        Directory.Delete(root, true)
    }
}
