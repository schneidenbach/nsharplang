namespace NSharpLang.CliCommandContracts.Tests

import System.Collections.Generic
import System.Diagnostics
import System.IO

// THE NATIVE FRONT DOOR'S HAND-OFF, PROVEN AS PROCESSES.
//
// A per-platform toolset's `nlc` is a NativeAOT front door (`src/NSharpLang.Compiler.Driver/FrontDoor.nl`)
// that answers `--version`/`help` itself and `execve`s `dotnet <lib>/Cli.dll <args>` for everything
// else. `NSHARP_FRONT_DOOR=1` takes the SAME path inside a JIT process, so every row here runs a
// command twice — straight into the host, and through the front door — and requires the two runs to
// be indistinguishable to a caller: the same exit code, the same stdout, the same stderr. The
// NativeAOT build of the front door is exercised by `scripts/publish-toolset.sh --rid` (see
// `memory/components/cli-toolchain.md`); its decisions are pinned by
// `src/NSharpLang.Compiler.Driver/FrontDoorKernels.tests.nl`.
func NlcThroughFrontDoor(arguments: string, workingDirectory: string, forced: bool): CliRun {
    startInfo := new ProcessStartInfo { FileName: "dotnet", Arguments: "\"" + CliDll() + "\" " + arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    if forced {
        startInfo.Environment["NSHARP_FRONT_DOOR"] = "1"
    } else {
        startInfo.Environment.Remove("NSHARP_FRONT_DOOR")
    }

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderr := process.StandardError.ReadToEnd()
    process.WaitForExit()
    exitCode := process.ExitCode
    stdout := stdoutTask.Result
    process.Dispose()
    return new CliRun(exitCode, stdout, stderr)
}

// Elapsed-time figures are the only text two honest runs may disagree on.
func WithoutTimings(text: string): string {
    lines := text.Replace("\r\n", "\n").Split('\n')
    kept := new List<string>()
    for line in lines {
        if line.Contains("completed in ") || line.Contains("[") && line.Contains("s]") {
            continue
        }

        kept.Add(line)
    }

    return string.Join("\n", kept)
}

func AssertSameRun(direct: CliRun, front: CliRun) {
    assert front.ExitCode == direct.ExitCode, "exit " + front.ExitCode.ToString() + " through the front door, " + direct.ExitCode.ToString() + " direct"
    assert WithoutTimings(front.Stdout) == WithoutTimings(direct.Stdout), "stdout differs:\n--- front door ---\n" + front.Stdout + "\n--- direct ---\n" + direct.Stdout
    assert WithoutTimings(front.Stderr) == WithoutTimings(direct.Stderr), "stderr differs:\n--- front door ---\n" + front.Stderr + "\n--- direct ---\n" + direct.Stderr
}

func FrontDoorProject(programSource: string, testSource: string?): string {
    directory := NewTempDirectory("nlc-front-door")
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: FrontDoorProbe\nversion: 0.1.0\ntargetFramework: net10.0\noutputType: exe\nentry: Program.nl\n")
    File.WriteAllText(Path.Combine(directory, "Program.nl"), programSource)
    if testSource != null {
        File.WriteAllText(Path.Combine(directory, "Program.tests.nl"), testSource)
    }

    return directory
}

test "the front door prints the host's version and help text" {
    workingDirectory := Path.GetTempPath()
    for arguments in ["--version", "-V", "help", "--help", ""] {
        direct := NlcThroughFrontDoor(arguments, workingDirectory, false)
        front := NlcThroughFrontDoor(arguments, workingDirectory, true)

        assert direct.ExitCode == 0, arguments
        AssertSameRun(direct, front)
    }

    assert NlcThroughFrontDoor("--version", workingDirectory, true).Stdout.StartsWith("nlc ")
}

test "an unknown command reaches the host's dispatcher through the front door and fails the same way" {
    workingDirectory := Path.GetTempPath()
    direct := NlcThroughFrontDoor("no-such-command --flag", workingDirectory, false)
    front := NlcThroughFrontDoor("no-such-command --flag", workingDirectory, true)

    assert direct.ExitCode == 1
    assert direct.Stderr.Contains("Unknown command: no-such-command")
    AssertSameRun(direct, front)
}

test "check reports the same diagnostics and exit code through the front door" {
    directory := FrontDoorProject("namespace FrontDoorProbe\n\nfunc main() {\n    count: int = \"three\"\n    print count\n}\n", null)
    try {
        direct := NlcThroughFrontDoor("check", directory, false)
        front := NlcThroughFrontDoor("check", directory, true)

        assert direct.ExitCode != 0, direct.Stdout
        assert direct.Stdout.Contains("\"ok\": false"), direct.Stdout
        AssertSameRun(direct, front)
    } finally {
        Directory.Delete(directory, true)
    }
}

test "run forwards the program's streams and exit code through the front door, and the host never sees the force switch" {
    source := "namespace FrontDoorProbe\n\nimport System\n\nfunc main(): int {\n    Console.WriteLine(\"force=\" + (Environment.GetEnvironmentVariable(\"NSHARP_FRONT_DOOR\") ?? \"<unset>\"))\n    Console.WriteLine(\"root-set=\" + (Environment.GetEnvironmentVariable(\"DOTNET_ROOT\") != null).ToString())\n    Console.Error.WriteLine(\"to stderr\")\n    return 7\n}\n"
    directory := FrontDoorProject(source, null)
    try {
        // Build once so both runs below take the same incremental path.
        build := NlcThroughFrontDoor("build", directory, false)
        assert build.ExitCode == 0, build.Stdout + build.Stderr
        direct := NlcThroughFrontDoor("run", directory, false)
        front := NlcThroughFrontDoor("run", directory, true)

        assert front.ExitCode == 7, front.Stdout + front.Stderr
        assert front.Stdout.Contains("force=<unset>"), front.Stdout
        assert front.Stdout.Contains("root-set=True"), front.Stdout
        assert front.Stderr.Contains("to stderr"), front.Stderr
        // The front door exports DOTNET_ROOT for the host exactly as the launcher scripts did, so
        // only that one line may differ from a direct run whose caller never set it.
        AssertSameRun(new CliRun(direct.ExitCode, direct.Stdout.Replace("root-set=False", "root-set=True"), direct.Stderr), front)
    } finally {
        Directory.Delete(directory, true)
    }
}

test "test discovers, runs and fails the same tests through the front door" {
    tests := "namespace FrontDoorProbe\n\ntest \"one passes\" {\n    assert 1 + 1 == 2\n}\n\ntest \"one fails\" {\n    assert 1 + 1 == 3\n}\n"
    directory := FrontDoorProject("namespace FrontDoorProbe\n\nfunc main() {\n    print \"main\"\n}\n", tests)
    try {
        direct := NlcThroughFrontDoor("test --no-cache", directory, false)
        front := NlcThroughFrontDoor("test --no-cache", directory, true)

        assert direct.ExitCode != 0, direct.Stdout + direct.Stderr
        assert direct.Stdout.Contains("Passed: 1, Failed: 1"), direct.Stdout
        AssertSameRun(direct, front)
    } finally {
        Directory.Delete(directory, true)
    }
}
