namespace NSharpLang.InstalledToolchainIntegration.Tests

import System.Collections.Generic
import System.IO

// ─── THE TWELVE ROWS OF THE DELETED `ToolchainTests.cs`, PLUS THE FIXTURE'S OWN ────────────────
//
// Every row below carries `[DockerFact]` and therefore the deleted attribute's gate: it runs when
// `NSHARP_RUN_DOCKER_INTEGRATION=1` or when a daemon answers, and is reported as `skipped` with a
// named reason otherwise. `.github/workflows/build.yml` and `publish.yml` set the variable, so CI
// cannot pass this project by skipping it.
//
// The order, the commands, the directories and the assertions are the deleted rows'. Where the C#
// looped over a table inside one `[Fact]`, the loop stays inside one `test` — collapsing a table into
// separate rows would change which failures are reported together.

// One case of the canonical-shape table: the `dotnet new` short name and the source file that
// template must scaffold.
class TemplateShapeCase {
    ShortName: string
    ExpectedFile: string

    constructor(shortName: string, expectedFile: string) {
        ShortName = shortName
        ExpectedFile = expectedFile
    }
}

// One case of the parity table: the `nlc new --template` kind, the `dotnet new` short name, and every
// source file the two must produce identically.
class TemplateParityCase {
    Template: string
    ShortName: string
    SourceFiles: List<string>

    constructor(template: string, shortName: string, sourceFiles: List<string>) {
        Template = template
        ShortName = shortName
        SourceFiles = sourceFiles
    }
}

func TemplateShapeCases(): List<TemplateShapeCase> {
    cases := new List<TemplateShapeCase>()
    cases.Add(new TemplateShapeCase("nsharp-console", "Program.nl"))
    cases.Add(new TemplateShapeCase("nsharp-library", "Calculator.nl"))
    cases.Add(new TemplateShapeCase("nsharp-test", "Calculator.tests.nl"))
    cases.Add(new TemplateShapeCase("nsharp-webapi", "Controllers/WeatherController.nl"))
    cases.Add(new TemplateShapeCase("nsharp-systems-cli", "Program.nl"))
    cases.Add(new TemplateShapeCase("nsharp-systems-lib", "PacketCore.nl"))
    return cases
}

func TemplateParityCaseFor(template: string, shortName: string, first: string, second: string): TemplateParityCase {
    sourceFiles := new List<string>()
    sourceFiles.Add(first)
    if second != "" {
        sourceFiles.Add(second)
    }

    return new TemplateParityCase(template, shortName, sourceFiles)
}

func TemplateParityCases(): List<TemplateParityCase> {
    cases := new List<TemplateParityCase>()
    cases.Add(TemplateParityCaseFor("console", "nsharp-console", "Program.nl", ""))
    cases.Add(TemplateParityCaseFor("library", "nsharp-library", "Calculator.nl", ""))
    cases.Add(TemplateParityCaseFor("test", "nsharp-test", "Calculator.nl", "Calculator.tests.nl"))
    cases.Add(TemplateParityCaseFor("webapi", "nsharp-webapi", "Program.nl", "Controllers/WeatherController.nl"))
    cases.Add(TemplateParityCaseFor("systems-cli", "nsharp-systems-cli", "Program.nl", "Systems.tests.nl"))
    cases.Add(TemplateParityCaseFor("systems-lib", "nsharp-systems-lib", "PacketCore.nl", "PacketCore.tests.nl"))
    return cases
}

// ─── THE FIXTURE HALF THAT NEEDS NO DAEMON ─────────────────────────────────────────────────────

// PACK-ONCE, AND THE STEP THAT HAS BROKEN CI ON ITS OWN. Six `dotnet` commands and
// `scripts/publish-toolset.sh` produce the build context the image is made from, and the deleted
// fixture ran them before any row — so a defect here took all twelve rows with it, which is exactly
// what CI run 35806417973 was: `dotnet pack` of `NSharpLang.Compiler` failed NU5026 for a `.pdb` the
// emitter never writes.
//
// This row asserts the CONTEXT, not the image, so it is the one Docker-gated row that a machine with
// no daemon can still be made to run: `NSHARP_RUN_DOCKER_INTEGRATION=1` forces it and nothing it
// touches is a container. It carries the gate anyway because a ~30-minute self-emitting pack is not
// something an inner loop should pay for by default.
[DockerFact]
test "the fixture packs this checkout and publishes the toolset into a Docker build context" {
    buildContextDirectory := ToolchainPrepareBuildContext()

    packagesDirectory := Path.Combine(buildContextDirectory, "packages")
    toolsetDirectory := Path.Combine(buildContextDirectory, "toolset")

    // The Dockerfile `COPY`s `toolset/` to `/root/.nsharp/` and `packages/` to `/packages/`, so both
    // must exist and neither may be empty: an empty feed produces an image whose every row fails to
    // restore, with no attribution to the pack that produced nothing.
    assert Directory.Exists(packagesDirectory), packagesDirectory
    assert Directory.Exists(toolsetDirectory), toolsetDirectory
    assert File.Exists(Path.Combine(buildContextDirectory, "Dockerfile.toolchain")), buildContextDirectory

    // The packages a generated project restores, plus the template package `dotnet new install`
    // reads from `/root/.nsharp/packages`.
    packageNames: string[] = [
        "NSharpLang.Runtime",
        "NSharpLang.Compiler.Model",
        "NSharpLang.Compiler.Syntax",
        "NSharpLang.Compiler.Core",
        "NSharpLang.Compiler",
        "NSharpLang.Sdk",
        "NSharpLang.Templates"
    ]
    for packageName in packageNames {
        assert Directory.GetFiles(packagesDirectory, packageName + ".*.nupkg").Length > 0, "no " + packageName + " package in " + packagesDirectory
    }

    // The two launchers `publish-toolset.sh` reports writing, and the packages it bundles beside
    // them: `Dockerfile.toolchain` puts `/root/.nsharp/bin` on PATH and installs the template package
    // from `/root/.nsharp/packages`, so both paths are part of the image's contract.
    assert File.Exists(Path.Combine(Path.Combine(toolsetDirectory, "bin"), "nlc")), toolsetDirectory
    assert File.Exists(Path.Combine(Path.Combine(toolsetDirectory, "bin"), "nsharp-lsp")), toolsetDirectory
    assert Directory.GetFiles(Path.Combine(toolsetDirectory, "packages"), "NSharpLang.Templates.*.nupkg").Length > 0, toolsetDirectory

    // PACK-ONCE IS THE CONTRACT, not an optimization: twelve rows sharing one container must also
    // share one pack, and the deleted `IClassFixture` is what guaranteed it.
    assert ToolchainPrepareBuildContext() == buildContextDirectory
}

// ─── THE TWELVE ─────────────────────────────────────────────────────────────────────────────────

// `dotnet new list nsharp` must name every template the package ships. The deleted row left its own
// `dotnet new install` unasserted; installing through the shared helper asserts it too, which can
// only turn a silent install failure into an attributed one.
[DockerFact]
test "dotnet new list names every shipped N# template" {
    ToolchainInstallTemplates()

    list := ToolchainBash("dotnet new list nsharp")
    ToolchainAssertSuccess(list, "dotnet new list")
    assert list.Stdout.Contains("nsharp-console"), list.Stdout
    assert list.Stdout.Contains("nsharp-library"), list.Stdout
    assert list.Stdout.Contains("nsharp-test"), list.Stdout
    assert list.Stdout.Contains("nsharp-webapi"), list.Stdout
    assert list.Stdout.Contains("nsharp-systems-cli"), list.Stdout
    assert list.Stdout.Contains("nsharp-systems-lib"), list.Stdout
}

// THE CANONICAL SHAPE IS CSPROJ-FREE. Every template must scaffold `project.yml`, `global.json`,
// `NuGet.config` and its own source file, and must scaffold NO `.csproj` — the shape AGENTS.md
// mandates and the only one `nlc build` reads directly.
[DockerFact]
test "every dotnet new template scaffolds the canonical csproj-free shape" {
    ToolchainInstallTemplates()

    for shapeCase in TemplateShapeCases() {
        directory := ToolchainUniqueDir(shapeCase.ShortName + "-shape")
        create := ToolchainBash("dotnet new " + shapeCase.ShortName + " -o " + directory)
        ToolchainAssertSuccess(create, "dotnet new " + shapeCase.ShortName)

        check := ToolchainBash(
            "test -f " + directory + "/project.yml && " + "test -f " + directory + "/global.json && " + "test -f " + directory + "/NuGet.config && " + "test -f " + directory + "/" + shapeCase.ExpectedFile + " && " + "test -z \"$(find " + directory + " -maxdepth 1 -name '*.csproj' -print -quit)\""
        )
        ToolchainAssertSuccess(check, "canonical shape for " + shapeCase.ShortName)
    }
}

// TWO SCAFFOLDERS, ONE PROJECT. `nlc new` writes its files from the CLI's own kernels and
// `dotnet new` expands the template package: two different bodies of shipped text, and a user meets
// whichever their first command uses. Every source file, `global.json` and `NuGet.config` is compared
// with `diff -u`, so a difference is REPORTED rather than merely counted.
[DockerFact]
test "nlc new and dotnet new produce a compatible project shape for every template" {
    ToolchainInstallTemplates()
    ToolchainInstallCli()

    for parityCase in TemplateParityCases() {
        nlcParent := ToolchainUniqueDir("nlc-new-" + parityCase.Template + "-parent")
        nlcDirectory := nlcParent + "/Demo"
        dotnetDirectory := ToolchainUniqueDir("dotnet-new-" + parityCase.Template)
        templateArgument := ""
        if parityCase.Template != "console" {
            templateArgument = " --template " + parityCase.Template
        }

        nlcCreate := ToolchainBash("mkdir -p " + nlcParent + " && cd " + nlcParent + " && nlc new Demo" + templateArgument)
        ToolchainAssertSuccess(nlcCreate, "nlc new Demo (" + parityCase.Template + ")")

        dotnetCreate := ToolchainBash("dotnet new " + parityCase.ShortName + " -n Demo -o " + dotnetDirectory)
        ToolchainAssertSuccess(dotnetCreate, "dotnet new " + parityCase.ShortName)

        diffSources := ""
        fileIndex := 0
        while fileIndex < parityCase.SourceFiles.Count {
            if fileIndex > 0 {
                diffSources = diffSources + " && "
            }

            diffSources = diffSources + "diff -u " + nlcDirectory + "/" + parityCase.SourceFiles[fileIndex] + " " + dotnetDirectory + "/" + parityCase.SourceFiles[fileIndex]
            fileIndex = fileIndex + 1
        }

        parity := ToolchainBash(
            diffSources + " && " + "diff -u " + nlcDirectory + "/global.json " + dotnetDirectory + "/global.json && " + "diff -u " + nlcDirectory + "/NuGet.config " + dotnetDirectory + "/NuGet.config && " + "grep -q '^name: Demo$' " + nlcDirectory + "/project.yml && " + "grep -q '^name: Demo$' " + dotnetDirectory + "/project.yml && " + "test -z \"$(find " + nlcDirectory + " -maxdepth 1 -name '*.csproj' -print -quit)\" && " + "test -z \"$(find " + dotnetDirectory + " -maxdepth 1 -name '*.csproj' -print -quit)\""
        )
        ToolchainAssertSuccess(parity, "nlc new and dotnet new " + parityCase.Template + " parity")
    }
}

// The console template's own files, asserted on their own: no `.csproj`, because `nlc` builds
// directly from `project.yml`.
[DockerFact]
test "the console template scaffolds the files it claims" {
    directory := ToolchainUniqueDir("scaffold")
    ToolchainInstallTemplates()

    create := ToolchainBash("dotnet new nsharp-console -o " + directory)
    ToolchainAssertSuccess(create, "dotnet new nsharp-console")

    check := ToolchainBash("test -f " + directory + "/project.yml && " + "test -f " + directory + "/Program.nl")
    ToolchainAssertSuccess(check, "expected files exist")
}

[DockerFact]
test "the console template builds on a machine that has only the installed toolchain" {
    directory := ToolchainUniqueDir("console-build")
    ToolchainInstallTemplates()
    ToolchainInstallCli()
    ToolchainBash("dotnet new nsharp-console -o " + directory)

    build := ToolchainBash("cd " + directory + " && nlc build")
    ToolchainAssertSuccess(build, "nlc build (console)")
}

// THE FIRST COMMAND A USER RUNS, AND ITS OUTPUT. A build that succeeds and an app that prints
// nothing are not the same thing, so the row reads stdout.
[DockerFact]
test "the console template runs and prints what the template says it prints" {
    directory := ToolchainUniqueDir("console-run")
    ToolchainInstallTemplates()
    ToolchainInstallCli()
    ToolchainBash("dotnet new nsharp-console -o " + directory)

    run := ToolchainBash("cd " + directory + " && nlc run")
    ToolchainAssertSuccess(run, "nlc run (console)")
    assert run.Stdout.Contains("Hello, N#!"), run.Stdout
}

[DockerFact]
test "the library template builds on a machine that has only the installed toolchain" {
    directory := ToolchainUniqueDir("library-build")
    ToolchainInstallTemplates()
    ToolchainInstallCli()
    ToolchainBash("dotnet new nsharp-library -o " + directory)

    build := ToolchainBash("cd " + directory + " && nlc build")
    ToolchainAssertSuccess(build, "nlc build (library)")
}

// `nlc test` inside the container, which is the whole test host — emit, load context and runner —
// reached through the installed launcher rather than the repository's build output.
[DockerFact]
test "the test template's own tests pass through the installed nlc test" {
    directory := ToolchainUniqueDir("test-run")
    ToolchainInstallTemplates()
    ToolchainInstallCli()
    ToolchainBash("dotnet new nsharp-test -o " + directory)

    test := ToolchainBash("cd " + directory + " && nlc test")
    ToolchainAssertSuccess(test, "nlc test (test template)")
}

// The only template with `nuget:` dependencies and a framework reference, so the only one whose build
// exercises package resolution against the staged feed at all.
[DockerFact]
test "the web API template builds on a machine that has only the installed toolchain" {
    directory := ToolchainUniqueDir("webapi-build")
    ToolchainInstallTemplates()
    ToolchainInstallCli()
    ToolchainBash("dotnet new nsharp-webapi -o " + directory)

    build := ToolchainBash("cd " + directory + " && nlc build")
    ToolchainAssertSuccess(build, "nlc build (webapi)")
}

// EVERY DOCUMENTED QUICKSTART, REPLAYED. `templates/README.md` is what a reader follows before
// anything else; each of its six `bash` fences is executed command by command in the container, with
// the working directory tracked across commands the way a reader's shell would track it.
[DockerFact]
test "every quickstart in templates README replays successfully" {
    ToolchainInstallTemplates()
    ToolchainInstallCli()

    quickstarts := ReadTemplateQuickstartsFromDocs()

    // THE SET IS PART OF THE CLAIM. A row that replayed whatever it found would go green by finding
    // nothing, and a quickstart deleted from the document would take its coverage with it silently.
    assert string.Join(",", TemplateQuickstartNamesSorted(quickstarts)) == "console,library,systems-console,systems-library,test,webapi", string.Join(",", TemplateQuickstartNamesSorted(quickstarts))

    for quickstart in quickstarts {
        workingDirectory := "/workspace"
        projectDirectory := ToolchainUniqueDir("docs-" + quickstart.Name)
        commands := RewriteProjectName(quickstart.Commands, projectDirectory)

        // A fence with no commands would replay nothing and pass; one with more than four is a
        // document this row has not been read against.
        assert commands.Count >= 1 && commands.Count <= 4, quickstart.Name + " has " + commands.Count.ToString() + " commands"

        commandIndex := 0
        while commandIndex < commands.Count {
            command := commands[commandIndex]
            result := ToolchainBash("cd " + workingDirectory + " && " + ReplayCommand(command))
            ToolchainAssertSuccess(result, "templates/README.md quickstart '" + quickstart.Name + "' command: " + command)
            workingDirectory = ApplyCd(workingDirectory, command)
            commandIndex = commandIndex + 1
        }
    }
}

// The launcher `publish-toolset.sh` wrote, reached through PATH rather than through a path: this is
// the command a reader's very first line runs.
[DockerFact]
test "the installed nlc launcher reports its version" {
    version := ToolchainBash("nlc --version")
    ToolchainAssertSuccess(version, "nlc --version")
}

// The language server's launcher must be BOTH on PATH and executable at the install root. An editor
// that cannot start the server is an editor with no N# support, and nothing else in the estate looks
// at the installed launcher's mode bits.
[DockerFact]
test "the installed language server launcher is on PATH and executable" {
    command := ToolchainBash("command -v nsharp-lsp && test -x /root/.nsharp/bin/nsharp-lsp")
    ToolchainAssertSuccess(command, "nsharp-lsp launcher")
}
