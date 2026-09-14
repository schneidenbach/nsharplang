namespace NSharpLang.CompilationBackend.Tests

import System.IO
import System.IO.Compression
import System.Reflection
import System.Runtime.InteropServices
import System.Text.Json

// The twenty-one rows of the deleted `tests/CompilationBackendTests.cs`, one for one, against the
// shipped binary. Each row keeps its original claim set; where the C# asserted "stderr is blank"
// the claim is kept AND is non-vacuous here, because a child process's stderr is a real stream
// that the neighbouring failure rows in this same file demonstrably reach.
func ProjectYml(name: string, backend: string, outputType: string): string {
    text := "name: " + name + "\n"
    if backend != "" {
        text = text + "backend: " + backend + "\n"
    }

    return text + "outputType: " + outputType + "\ntargetFramework: net10.0\n"
}

// ═══ check ════════════════════════════════════════════════════════════════════════════════════

test "nlc check on a project that configures the il backend verifies and reports ok" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("CheckIl", "il", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"checked\"\n}\n")

        run := Nlc("check --project " + Quote(directory), directory)

        assert run.ExitCode == 0

        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("command").GetString() == "check"
        assert document.RootElement.GetProperty("ok").GetBoolean()
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ build ════════════════════════════════════════════════════════════════════════════════════

test "nlc build with the il backend writes a runnable assembly and generates no csproj" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("BuildIl", "il", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"built with il\"\n}\n")

        outputDirectory := Path.Combine(directory, "dist")
        run := Nlc("build -o " + Quote(outputDirectory), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Build successful!")
        assert run.Stderr.Trim().Length == 0

        assemblyPath := Path.Combine(outputDirectory, "BuildIl.dll")
        assert File.Exists(assemblyPath)
        assert File.Exists(Path.Combine(outputDirectory, "BuildIl.runtimeconfig.json"))
        assert GeneratedProjectFileCount(directory) == 0

        executed := DotnetApp(assemblyPath, directory)
        assert executed.ExitCode == 0
        assert executed.Stdout.Contains("built with il")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "finalizer refusal follows the selected runtime slot and overload" {
    directory := NewTempDirectory()
    try {
        fixture := Path.Combine(directory, "Fixture")
        consumer := Path.Combine(directory, "Consumer")
        Directory.CreateDirectory(fixture)
        Directory.CreateDirectory(consumer)
        WriteFile(fixture, "project.yml", ProjectYml("FinalizerFixture", "il", "library"))
        WriteFile(
            fixture,
            "Fixture.nl",
            "namespace FinalizerFixture\n\nclass OrdinaryBase {\n    public virtual func Finalize() {\n    }\n}\n\nclass OrdinaryDerived: OrdinaryBase {\n    public override func Finalize() {\n    }\n}\n\nclass FinalizeOverload {\n    public func Finalize(value: int): int {\n        return value\n    }\n}\n"
        )
        fixtureBuild := Nlc("build", fixture)
        assert fixtureBuild.ExitCode == 0, fixtureBuild.Stdout + fixtureBuild.Stderr

        fixtureAssembly := Path.Combine(fixture, "bin/Debug/net10.0/FinalizerFixture.dll")
        loaded := Assembly.LoadFile(fixtureAssembly)
        derivedType := loaded.GetType("FinalizerFixture.OrdinaryDerived")
        assert derivedType != null
        ordinaryFinalize := derivedType.GetMethod("Finalize", BindingFlags.Public | BindingFlags.Instance)
        assert ordinaryFinalize != null
        baseDefinition := ordinaryFinalize.GetBaseDefinition()
        baseOwner := baseDefinition.get_DeclaringType()
        assert baseOwner != null
        assert baseOwner.get_FullName() == "FinalizerFixture.OrdinaryBase"

        WriteFile(consumer, "project.yml", ProjectYml("FinalizerConsumer", "il", "library") + "dependencies:\n  - dll: " + fixtureAssembly + "\n")
        WriteFile(
            consumer,
            "Probe.nl",
            "namespace FinalizerConsumer\n\nimport FinalizerFixture\n\nfunc CallOrdinary(value: OrdinaryDerived) {\n    value.Finalize()\n}\n\nclass OverloadConsumer: FinalizeOverload {\n    func Invoke(): int {\n        return this.Finalize(42)\n    }\n}\n"
        )
        accepted := Nlc("check --project " + Quote(consumer) + " --text", consumer)
        assert accepted.ExitCode == 0, accepted.Stdout + accepted.Stderr

        WriteFile(consumer, "Direct.nl", "namespace FinalizerConsumer\n\nclass RuntimeOwned {\n    func Reject() {\n        this.Finalize()\n    }\n}\n")
        refused := Nlc("check --project " + Quote(consumer) + " --text", consumer)
        assert refused.ExitCode == 1
        said := SaidByCheck(refused)
        assert said.Contains("NL341")
        assert said.Contains("the runtime's finalizer")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc build accepts a single source file after the options and builds it with the il backend" {
    directory := NewTempDirectory()
    try {
        sourcePath := Path.Combine(directory, "Program.nl")
        File.WriteAllText(sourcePath, "func main(): int {\n    return 0\n}\n")

        outputDirectory := Path.Combine(directory, "dist")
        run := Nlc("build --backend il --output " + Quote(outputDirectory) + " " + Quote(sourcePath), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Build successful!")
        assert run.Stderr.Trim().Length == 0
        assert File.Exists(Path.Combine(outputDirectory, "Program.dll"))
        assert File.Exists(Path.Combine(outputDirectory, "Program.runtimeconfig.json"))
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc build of a single file fails when columnar emission declines the shape" {
    directory := NewTempDirectory()
    try {
        sourcePath := Path.Combine(directory, "Program.nl")
        File.WriteAllText(sourcePath, DecliningSource())

        outputDirectory := Path.Combine(directory, "dist")
        run := Nlc("build --backend il --output " + Quote(outputDirectory) + " " + Quote(sourcePath), directory)

        assert run.ExitCode == 1
        assert run.Stdout.Contains("Building")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc build accepts a whitespace and separator laden --define list and still succeeds" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("CliDefineBuild", "", "exe"))
        WriteFile(
            directory,
            "Program.nl",
            "func main() {\n    #if FEATURE_X\n    print \"feature-on\"\n    #else\n    print \"feature-off\"\n    #endif\n\n    #if SECOND\n    print \"second-on\"\n    #endif\n}\n"
        )

        outputDirectory := Path.Combine(directory, "dist")
        run := Nlc("build --define \" FEATURE_X , SECOND ; FEATURE_X \" --backend il -o " + Quote(outputDirectory), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Build successful!")
        assert run.Stderr.Trim().Length == 0
        assert File.Exists(Path.Combine(outputDirectory, "CliDefineBuild.dll"))
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "a strict lint error blocks the il build and reports failure" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("StrictLintBuild", "il", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    unused := 42\n}\n")

        outputDirectory := Path.Combine(directory, "dist")
        run := Nlc("build -o " + Quote(outputDirectory), directory)

        assert run.ExitCode == 1
        assert run.Stdout.Contains("Build failed")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc build --release reports the release configuration and uses the release output layout" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("ReleaseLayout", "il", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"release layout\"\n}\n")

        run := Nlc("build --release", directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Build successful! (il, release)")
        assert NormalizePath(run.Stdout).Contains(NormalizePath(Path.Combine(Path.Combine("bin", "Release"), Path.Combine("net10.0", "ReleaseLayout.dll"))))
        assert run.Stderr.Trim().Length == 0

        releaseDirectory := Path.Combine(Path.Combine(Path.Combine(directory, "bin"), "Release"), "net10.0")
        assert File.Exists(Path.Combine(releaseDirectory, "ReleaseLayout.dll"))
        assert File.Exists(Path.Combine(releaseDirectory, "ReleaseLayout.runtimeconfig.json"))
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "a project that names no backend defaults to il and emits no C# on the way" {
    directory := NewTempDirectory()
    try {
        WriteSdkResolutionFiles(directory)
        WriteFile(directory, "project.yml", ProjectYml("BuildDefaultIl", "", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"default backend is il\"\n}\n")

        outputDirectory := Path.Combine(directory, "dist")
        run := Nlc("build -o " + Quote(outputDirectory), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Build successful!")
        assert run.Stderr.Trim().Length == 0
        assert GeneratedProjectFileCount(directory) == 0
        assert GeneratedCSharpFileCount(directory) == 0

        assemblyPath := Path.Combine(outputDirectory, "BuildDefaultIl.dll")
        assert File.Exists(assemblyPath)
        assert File.Exists(Path.Combine(outputDirectory, "BuildDefaultIl.runtimeconfig.json"))

        executed := DotnetApp(assemblyPath, directory)
        assert executed.ExitCode == 0
        assert executed.Stdout.Contains("default backend is il")
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ run ══════════════════════════════════════════════════════════════════════════════════════

test "nlc run builds with the il backend and executes the project" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("RunIl", "il", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"ran with il\"\n}\n")

        run := Nlc("run", directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Running...")
        assert run.Stdout.Contains("ran with il")
        assert GeneratedProjectFileCount(directory) == 0
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc run of a single file fails when columnar emission declines the shape" {
    directory := NewTempDirectory()
    try {
        sourcePath := Path.Combine(directory, "Program.nl")
        File.WriteAllText(sourcePath, DecliningSource())

        run := Nlc("run --backend il " + Quote(sourcePath), directory)

        assert run.ExitCode == 1
        assert run.Stdout.Contains("Running")
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ test ═════════════════════════════════════════════════════════════════════════════════════

test "nlc test runs an executable project's tests through the il backend" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("TestIl", "il", "exe"))
        WriteSdkResolutionFiles(directory)
        WriteFile(directory, "Program.nl", "func main() {\n    print \"testing\"\n}\n\nfunc Add(a: int, b: int): int {\n    return a + b\n}\n")
        WriteFile(directory, "Program.tests.nl", "test \"addition works\" {\n    assert Add(2, 3) == 5\n}\n")

        run := Nlc("test --project " + Quote(directory) + " --json", directory)

        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("command").GetString() == "test"
        assert document.RootElement.GetProperty("ok").GetBoolean()
        assert document.RootElement.GetProperty("summary").GetProperty("passed").GetInt32() == 1
        document.Dispose()
        assert GeneratedProjectFileCount(directory) == 0
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc test --coverage reports the unsupported error before any discovery runs" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("CoverageUnavailable", "il", "library"))

        run := Nlc("test --project " + Quote(directory) + " --coverage --json", directory)

        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("command").GetString() == "test"
        assert !document.RootElement.GetProperty("ok").GetBoolean()
        assert (document.RootElement.GetProperty("error").GetString() ?? "").Contains("Coverage collection is not available in nlc test yet")
        assert document.RootElement.GetProperty("summary").GetProperty("total").GetInt32() == 0
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc test honours a --backend il override and runs the tests through the sdk project" {
    directory := NewTempDirectory()
    try {
        WriteSdkResolutionFiles(directory)
        WriteFile(directory, "project.yml", ProjectYml("OverrideIlTests", "", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"override\"\n}\n\nfunc Add(a: int, b: int): int {\n    return a + b\n}\n")
        WriteFile(directory, "Program.tests.nl", "test \"override il tests\" {\n    assert Add(4, 5) == 9\n}\n")

        run := Nlc("test --project " + Quote(directory) + " --backend il --json", directory)

        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("command").GetString() == "test"
        assert document.RootElement.GetProperty("ok").GetBoolean()
        assert document.RootElement.GetProperty("summary").GetProperty("passed").GetInt32() == 1
        document.Dispose()
        assert GeneratedProjectFileCount(directory) == 0
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ pack ═════════════════════════════════════════════════════════════════════════════════════

func PackageHoldsEntry(packagePath: string, entryName: string): bool {
    archive := ZipFile.OpenRead(packagePath)
    try {
        for entry in archive.Entries {
            if entry.FullName == entryName {
                return true
            }
        }

        return false
    } finally {
        archive.Dispose()
    }
}

test "nlc pack builds with the il backend and lays the assembly into lib/net10.0" {
    directory := NewTempDirectory()
    try {
        WriteSdkResolutionFiles(directory)
        WriteFile(
            directory,
            "project.yml",
            "name: PackIl\nbackend: il\noutputType: exe\ntargetFramework: net10.0\nversion: 1.2.3\npackage:\n  description: IL-backed package\n  author: NSharp\n"
        )
        WriteFile(directory, "Program.nl", "func main(): int {\n    return 0\n}\n")

        outputDirectory := Path.Combine(directory, "artifacts")
        run := Nlc("pack --project " + Quote(directory) + " --output " + Quote(outputDirectory) + " --json", directory)

        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("command").GetString() == "pack"
        assert document.RootElement.GetProperty("ok").GetBoolean()

        packagePath := document.RootElement.GetProperty("packagePath").GetString() ?? ""
        document.Dispose()
        assert packagePath.Trim().Length > 0
        assert File.Exists(packagePath)
        assert PackageHoldsEntry(packagePath, "lib/net10.0/PackIl.dll")
        assert GeneratedProjectFileCount(directory) == 0
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ SDK PROJECT REFERENCES ═══════════════════════════════════════════════════════════════════

// The fixture the three project-reference rows share: a referenced N# library, a NuGet dependency
// on top of it, and the SDK resolution files that make both restorable from the packed feed.
func CreateProjectReferenceFixture(projectRoot: string) {
    WriteSdkResolutionFiles(projectRoot)

    sharedDirectory := Path.Combine(projectRoot, "Shared")
    Directory.CreateDirectory(sharedDirectory)
    WriteVersionedSdkProject(sharedDirectory, "SharedLib")

    WriteFile(sharedDirectory, "project.yml", ProjectYml("SharedLib", "", "library"))
    WriteFile(sharedDirectory, "Shared.nl", "func Greeting(): string {\n    return \"hello from shared\"\n}\n")

    WriteFile(
        projectRoot,
        "project.yml",
        "name: App\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - project: Shared/project.yml\n  - nuget: Newtonsoft.Json\n    version: 13.0.3\n"
    )
    WriteFile(projectRoot, "Program.nl", "import Newtonsoft.Json\n\nfunc main() {\n    print JsonConvert.SerializeObject(Greeting())\n}\n")
}

test "a --backend il build resolves sdk project references and their runtime assets" {
    directory := NewTempDirectory()
    try {
        CreateProjectReferenceFixture(directory)
        outputDirectory := Path.Combine(directory, "dist")

        run := Nlc("build --backend il -o " + Quote(outputDirectory), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Build successful!")
        assert run.Stderr.Trim().Length == 0
        assert File.Exists(Path.Combine(outputDirectory, "App.dll"))
        assert File.Exists(Path.Combine(outputDirectory, "App.runtimeconfig.json"))
        assert GeneratedProjectFileCount(directory) == 0
        assert GeneratedProjectFileCount(Path.Combine(directory, "Shared")) == 0
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "an aot build over a project reference fails when the referenced library declines columnar emission" {
    directory := NewTempDirectory()
    try {
        WriteSdkResolutionFiles(directory)

        sharedDirectory := Path.Combine(directory, "Shared")
        Directory.CreateDirectory(sharedDirectory)
        WriteVersionedSdkProject(sharedDirectory, "SharedLib")
        WriteFile(sharedDirectory, "project.yml", ProjectYml("SharedLib", "", "library"))
        WriteFile(sharedDirectory, "Shared.nl", "import System\nimport System.Collections.Generic\nimport System.Threading.Tasks\nfunc* Relay(): IEnumerable<Func<Task<int>>> {\n    yield async () => 42\n}\n\n")

        WriteFile(directory, "project.yml", "name: App\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - project: Shared/project.yml\n")
        WriteFile(directory, "Program.nl", "func main() {\n    print \"root\"\n}\n")

        outputDirectory := Path.Combine(directory, "dist")
        run := Nlc("build --backend il --aot -o " + Quote(outputDirectory), directory)

        assert run.ExitCode == 1
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ publish ══════════════════════════════════════════════════════════════════════════════════

test "a --backend il publish resolves sdk project references and their runtime assets" {
    directory := NewTempDirectory()
    try {
        CreateProjectReferenceFixture(directory)
        publishDirectory := Path.Combine(directory, "publish")

        run := Nlc("publish --backend il --output " + Quote(publishDirectory), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Publish successful!")
        assert run.Stderr.Trim().Length == 0
        assert File.Exists(Path.Combine(publishDirectory, "App.dll"))
        assert File.Exists(Path.Combine(publishDirectory, "App.runtimeconfig.json"))
        assert GeneratedProjectFileCount(directory) == 0
        assert GeneratedProjectFileCount(Path.Combine(directory, "Shared")) == 0
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "a --runtime publish for the host runtime produces a launcher that runs" {
    directory := NewTempDirectory()
    try {
        runtimeIdentifier := RuntimeInformation.RuntimeIdentifier
        WriteSdkResolutionFiles(directory)
        WriteFile(directory, "project.yml", ProjectYml("RuntimeSpecificIlPublish", "il", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"runtime-specific il publish\"\n}\n")

        publishDirectory := Path.Combine(directory, "publish-runtime")
        run := Nlc("publish --backend il --runtime " + runtimeIdentifier + " --output " + Quote(publishDirectory), directory)

        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0
        assert run.Stdout.Contains("Publish successful!")

        publishedApp := PublishedAppPath(publishDirectory, "RuntimeSpecificIlPublish")
        assert File.Exists(publishedApp)
        assert File.Exists(Path.Combine(publishDirectory, "RuntimeSpecificIlPublish.dll"))
        assert GeneratedProjectFileCount(directory) == 0

        executed := RunProcess(publishedApp, "", publishDirectory, 180000)
        assert executed.ExitCode == 0
        assert executed.Stdout.Contains("runtime-specific il publish")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "a --self-contained publish is refused with a message that names the framework-dependent alternative" {
    directory := NewTempDirectory()
    try {
        runtimeIdentifier := RuntimeInformation.RuntimeIdentifier
        WriteSdkResolutionFiles(directory)
        WriteFile(directory, "project.yml", ProjectYml("SelfContainedIlPublish", "il", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"self-contained il publish\"\n}\n")

        publishDirectory := Path.Combine(directory, "publish-self-contained")
        run := Nlc("publish --backend il --runtime " + runtimeIdentifier + " --self-contained --output " + Quote(publishDirectory), directory)

        assert run.ExitCode == 1
        assert run.Stdout.Contains("Publishing project in")
        assert run.Stderr.Contains("Self-contained publish is not available in nlc publish yet")
        assert run.Stderr.Contains("framework-dependent artifacts")
        assert !Directory.Exists(publishDirectory)
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "a cross-runtime publish is refused with a message that names both runtimes" {
    directory := NewTempDirectory()
    try {
        requestedRuntime := DifferentRuntimeIdentifier()
        WriteSdkResolutionFiles(directory)
        WriteFile(directory, "project.yml", ProjectYml("CrossRuntimeIlPublish", "il", "exe"))
        WriteFile(directory, "Program.nl", "func main() {\n    print \"cross runtime il publish\"\n}\n")

        publishDirectory := Path.Combine(directory, "publish-cross-runtime")
        run := Nlc("publish --backend il --runtime " + requestedRuntime + " --output " + Quote(publishDirectory), directory)

        assert run.ExitCode == 1
        assert run.Stdout.Contains("Publishing project in")
        assert run.Stderr.Contains("Cross-runtime publish is not available in nlc publish yet")
        assert run.Stderr.Contains("Requested runtime '" + requestedRuntime + "'")
        assert run.Stderr.Contains(RuntimeInformation.RuntimeIdentifier)
        assert !Directory.Exists(publishDirectory)
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc publish without a project.yml says how to create one" {
    directory := NewTempDirectory()
    try {
        run := Nlc("publish --backend il", directory)

        assert run.ExitCode == 1
        assert run.Stdout.Contains("Publishing project in")
        assert run.Stderr.Contains("No project.yml found in current directory. Run 'nlc new <name>' to create a project.")
    } finally {
        DeleteTempDirectory(directory)
    }
}
