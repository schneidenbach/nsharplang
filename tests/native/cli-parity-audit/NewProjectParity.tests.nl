namespace NSharpLang.CliParityAudit.Tests

import System.IO
import NSharpLang.Cli

// `nlc new` — the scaffolding contract.
//
// Both of the deleted `[Theory]` blocks are UNROLLED here, one `test` per `[InlineData]` row
// (four template rows, then two systems-template rows), so a failure names the template that
// broke instead of reporting one composite row.
//
// Every row that used `Directory.SetCurrentDirectory(parentDir)` now simply hands `parentDir` to
// the child process as its working directory.
func AssertSystemsProjectShape(projectDirectory: string, projectName: string, sourceFile: string, testFile: string) {
    assert File.Exists(Path.Combine(projectDirectory, sourceFile))
    assert File.Exists(Path.Combine(projectDirectory, testFile))
    assert TopLevelProjectFileCount(projectDirectory, "*.csproj") == 0

    projectYaml := File.ReadAllText(Path.Combine(projectDirectory, "project.yml"))
    assert projectYaml.Contains("name: " + projectName)
    assert projectYaml.Contains("profile: systems")
    assert projectYaml.Contains("mode: strict")
    assert projectYaml.Contains("aotTarget: nativeaot")
    assert projectYaml.Contains("warmup:")
}

test "nlc new onto an existing directory exits 1 and suggests a different name" {
    directory := NewTempDirectory()
    try {
        run := Nlc(["new", directory], HelpWorkingDirectory())

        assert run.ExitCode == 1
        assert run.Stderr.Contains("already exists")
        assert run.Stderr.Contains("different name")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc new --template console creates the canonical csproj-free shape with a Program.nl entry" {
    parent := NewTempDirectory()
    try {
        run := Nlc(["new", "Democonsole", "--template", "console"], parent)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        AssertCanonicalProjectShape(Path.Combine(parent, "Democonsole"), "Democonsole", true, false, false)
        assert run.Stdout.Contains("project.yml")
        assert run.Stdout.Contains("nlc build")
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new --template library creates the canonical csproj-free shape with no entry point" {
    parent := NewTempDirectory()
    try {
        run := Nlc(["new", "Demolibrary", "--template", "library"], parent)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        AssertCanonicalProjectShape(Path.Combine(parent, "Demolibrary"), "Demolibrary", false, false, false)
        assert run.Stdout.Contains("project.yml")
        assert run.Stdout.Contains("nlc build")
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new --template test creates the canonical csproj-free shape with a Calculator.tests.nl" {
    parent := NewTempDirectory()
    try {
        run := Nlc(["new", "Demotest", "--template", "test"], parent)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        AssertCanonicalProjectShape(Path.Combine(parent, "Demotest"), "Demotest", false, true, false)
        assert run.Stdout.Contains("project.yml")
        assert run.Stdout.Contains("nlc build")
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new --template webapi creates the canonical csproj-free shape with a controller" {
    parent := NewTempDirectory()
    try {
        run := Nlc(["new", "Demowebapi", "--template", "webapi"], parent)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        AssertCanonicalProjectShape(Path.Combine(parent, "Demowebapi"), "Demowebapi", true, false, true)
        assert run.Stdout.Contains("project.yml")
        assert run.Stdout.Contains("nlc build")
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new honours a custom install root and writes the install-root feed into NuGet.config" {
    parent := NewTempDirectory()
    try {
        installRoot := Path.Combine(parent, "custom install")

        run := NlcWithEnvironment(
            ["new", "CustomFeedApp"],
            parent,
            NSharpInstallRoot.InstallDirEnvironmentVariable,
            installRoot
        )

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)

        nugetConfig := File.ReadAllText(Path.Combine(Path.Combine(parent, "CustomFeedApp"), "NuGet.config"))
        assert nugetConfig.Contains(NSharpInstallRoot.InstallRootFeedValue)
        assert !nugetConfig.Contains(NSharpInstallRoot.DefaultFeedValue)
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new accepts the project name AFTER the --template option" {
    parent := NewTempDirectory()
    try {
        run := Nlc(["new", "--template", "library", "DemoOptionFirst"], parent)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        AssertCanonicalProjectShape(Path.Combine(parent, "DemoOptionFirst"), "DemoOptionFirst", false, false, false)
        assert run.Stdout.Contains("library")
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new normalizes the lib and web-api template aliases" {
    parent := NewTempDirectory()
    try {
        libraryRun := Nlc(["new", "lib", "DemoLibAlias"], parent)
        assert libraryRun.ExitCode == 0
        assert IsBlank(libraryRun.Stderr)
        AssertCanonicalProjectShape(Path.Combine(parent, "DemoLibAlias"), "DemoLibAlias", false, false, false)
        assert libraryRun.Stdout.Contains("library")

        webRun := Nlc(["new", "DemoWebAlias", "--template", "web-api"], parent)
        assert webRun.ExitCode == 0
        assert IsBlank(webRun.Stderr)
        AssertCanonicalProjectShape(Path.Combine(parent, "DemoWebAlias"), "DemoWebAlias", true, false, true)
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new --help states the csproj-free policy and lists every template and the systems flag" {
    run := Nlc(["new", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.ToLowerInvariant().Contains("csproj-free")
    assert run.Stdout.Contains("--template")
    assert run.Stdout.Contains("console")
    assert run.Stdout.Contains("library")
    assert run.Stdout.Contains("test")
    assert run.Stdout.Contains("webapi")
    assert run.Stdout.Contains("systems-cli")
    assert run.Stdout.Contains("systems-lib")
    assert run.Stdout.Contains("--systems")
}

test "nlc new with no arguments exits 1 and prints its usage line to stderr" {
    run := Nlc(["new"], HelpWorkingDirectory())

    assert run.ExitCode == 1
    assert IsBlank(run.Stdout)
    assert run.Stderr.Contains("Usage: nlc new <project-name> [--template <template>]")
}

test "nlc new with an unknown template exits 1 and lists the templates it does accept" {
    run := Nlc(["new", "MyApp", "--template", "unknown-template"], HelpWorkingDirectory())

    assert run.ExitCode == 1
    assert IsBlank(run.Stdout)
    assert run.Stderr.Contains("Invalid template. Expected one of: console, library, test, webapi, systems-cli, systems-lib.")
}

test "nlc new systems-cli creates the systems project shape with Program.nl and Systems.tests.nl" {
    parent := NewTempDirectory()
    try {
        run := Nlc(["new", "systems-cli", "Demosystemscli"], parent)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        AssertSystemsProjectShape(Path.Combine(parent, "Demosystemscli"), "Demosystemscli", "Program.nl", "Systems.tests.nl")
        assert run.Stdout.Contains("project.yml")
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new systems-lib creates the systems project shape with PacketCore.nl and PacketCore.tests.nl" {
    parent := NewTempDirectory()
    try {
        run := Nlc(["new", "systems-lib", "Demosystemslib"], parent)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        AssertSystemsProjectShape(Path.Combine(parent, "Demosystemslib"), "Demosystemslib", "PacketCore.nl", "PacketCore.tests.nl")
        assert run.Stdout.Contains("project.yml")
    } finally {
        DeleteTempDirectory(parent)
    }
}

test "nlc new library --systems produces a systems LIBRARY rather than a systems CLI" {
    parent := NewTempDirectory()
    try {
        run := Nlc(["new", "library", "PacketCore", "--systems"], parent)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        assert File.Exists(Path.Combine(Path.Combine(parent, "PacketCore"), "PacketCore.nl"))

        projectYaml := File.ReadAllText(Path.Combine(Path.Combine(parent, "PacketCore"), "project.yml"))
        assert projectYaml.Contains("profile: systems")
        assert projectYaml.Contains("outputType: library")
    } finally {
        DeleteTempDirectory(parent)
    }
}
