namespace NSharpLang.CliParityAudit.Tests

import System
import System.IO
import System.Text.Json

// `nlc remove`, `nlc pack`, `nlc build`/`nlc publish` help precedence, `nlc init`, and
// `nlc restore` — the project-lifecycle half of the deleted audit.

// ─── nlc remove ───────────────────────────────────────────────────────────────────────────────
func RemoveDemoProjectYaml(): string {
    return "name: RemoveDemo\nversion: 1.0.0\nbackend: il\ntargetFramework: net10.0\n\ndependencies:\n  - nuget: Newtonsoft.Json\n    version: 13.0.3\n  - framework: Microsoft.AspNetCore.App\n  - nuget: YamlDotNet\n    version: 16.3.0\n"
}

test "nlc remove deletes only the named mapping dependency block and re-projects obj/project.g.props" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", RemoveDemoProjectYaml())

        run := Nlc(["remove", "Newtonsoft.Json"], directory)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        assert run.Stdout.Contains("Removed Newtonsoft.Json from project.yml")

        projectYaml := File.ReadAllText(Path.Combine(directory, "project.yml"))
        assert !projectYaml.Contains("Newtonsoft.Json")
        assert !projectYaml.Contains("13.0.3")
        assert projectYaml.Contains("Microsoft.AspNetCore.App")
        assert projectYaml.Contains("YamlDotNet")
        assert projectYaml.Contains("16.3.0")
        assert File.Exists(Path.Combine(Path.Combine(directory, "obj"), "project.g.props"))
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ─── nlc pack ─────────────────────────────────────────────────────────────────────────────────

test "nlc pack --help exits 0 and documents project.yml, --output, --version, and --include-symbols" {
    run := Nlc(["pack", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Contains("project.yml")
    assert run.Stdout.Contains("--output")
    assert run.Stdout.Contains("--version")
    assert run.Stdout.Contains("--include-symbols")
}

// The expected stderr is a LITERAL, exactly as the deleted body had it. It used to be a live call
// to `ProgramCommandKernels.GetErrorLine(PackCommandKernels.GetMissingProjectFileTextMessage())`,
// so both sides were computed by the same two N#-owned kernels and agreed by construction:
// neither said what the sentence IS, and a kernel and a command wrong in the same way passed. The
// kernels' own text is pinned independently in
// `src/NSharpLang.Compiler.Core/PackCommandKernels.tests.nl`. The line break INSIDE the message is
// a literal `\n` the kernel embeds; only the trailing break is the console's `Environment.NewLine`.
test "nlc pack without a project.yml exits 1 and writes exactly the missing-project sentence to stderr" {
    directory := NewTempDirectory()
    try {
        run := Nlc(["pack", "--project", directory], directory)

        assert run.ExitCode == 1
        assert IsBlank(run.Stdout)
        assert run.Stderr == "Error: No project.yml found in current directory.\nRun 'nlc new <name>' to create a project." + Environment.NewLine
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc pack --json without a project.yml exits 1 with the pack error envelope" {
    directory := NewTempDirectory()
    try {
        run := Nlc(["pack", "--project", directory, "--json"], directory)

        assert run.ExitCode == 1
        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("schemaVersion").GetInt32() == 1
        assert (root.GetProperty("command").GetString() ?? "") == "pack"
        assert !root.GetProperty("ok").GetBoolean()
        message := root.GetProperty("error").GetProperty("message").GetString() ?? ""
        assert message.Contains("project.yml")
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ─── help precedence on nlc build and nlc publish ─────────────────────────────────────────────

test "nlc build --define --help prints help instead of consuming --help as the define value" {
    run := Nlc(["build", "--define", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Contains("Usage: nlc build")
}

test "nlc publish --help names both the supported and the unsupported target shapes" {
    run := Nlc(["publish", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Contains("Current host runtime only")
    assert run.Stdout.Contains("Portable framework-dependent")
    assert run.Stdout.Contains("Cross-runtime publishing")
    assert run.Stdout.Contains("Self-contained apphost/runtime bundles")
}

test "nlc publish --project --help prints help instead of validating the missing project argument" {
    run := Nlc(["publish", "--project", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Contains("Usage: nlc publish")
}

// ─── nlc init ─────────────────────────────────────────────────────────────────────────────────

test "nlc init --help exits 0 and documents its usage and the --force flag" {
    run := Nlc(["init", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Contains("N# Init")
    assert run.Stdout.Contains("Usage: nlc init [options]")
    assert run.Stdout.Contains("--force")
}

test "nlc init with an invalid --type exits 1, writes nothing, and names the two valid types" {
    directory := NewTempDirectory()
    try {
        run := Nlc(["init", "--type", "service"], directory)

        assert run.ExitCode == 1
        assert IsBlank(run.Stdout)
        assert run.Stderr.Contains("Invalid type 'service'. Expected 'exe' or 'library'.")
        assert !File.Exists(Path.Combine(directory, "project.yml"))
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc init writes a minimal project.yml and a one-line SDK-only csproj and no Program.nl" {
    directory := NewTempDirectory()
    try {
        run := Nlc(["init", "--name", "DemoLib", "--type", "library"], directory)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        assert run.Stdout.Contains("Created: project.yml")
        assert run.Stdout.Contains("Created: DemoLib.csproj")
        assert run.Stdout.Contains("N# project initialized. Run 'nlc build' to compile.")

        projectYaml := File.ReadAllText(Path.Combine(directory, "project.yml"))
        assert projectYaml.Contains("name: DemoLib")
        assert projectYaml.Contains("outputType: library")
        assert !projectYaml.Contains("entry:")
        assert File.ReadAllText(Path.Combine(directory, "DemoLib.csproj")) == "<Project Sdk=\"NSharpLang.Sdk\" />\n"
        assert !File.Exists(Path.Combine(directory, "Program.nl"))
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ─── nlc restore ──────────────────────────────────────────────────────────────────────────────

test "nlc restore --help exits 0 and names the obj/project.g.props projection it generates" {
    run := Nlc(["restore", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Contains("N# Restore")
    assert run.Stdout.Contains("Usage: nlc restore")
    assert run.Stdout.Contains("obj/project.g.props")
}

test "nlc restore without a project.yml exits 1 and points at nlc new on stderr" {
    directory := NewTempDirectory()
    try {
        run := Nlc(["restore"], directory)

        assert run.ExitCode == 1
        assert IsBlank(run.Stdout)
        assert run.Stderr.Contains("No project.yml found. Run 'nlc new <name>' to create a project.")
    } finally {
        DeleteTempDirectory(directory)
    }
}
