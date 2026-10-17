namespace NSharpLang.CliCommandContracts.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json

// WHICH INSTALL `nlc doctor` JUDGES, PROVEN THROUGH THE SHIPPED CLI.
//
// `scripts/install.sh --install-dir DIR` (or `NSHARP_INSTALL_DIR=DIR`) installs the toolset's
// packages into `DIR/packages` and exports `NSHARP_INSTALL_DIR` from `DIR/env`. Doctor used to
// check a hard-coded `~/.nsharp/packages` instead, so a scratch install passed or failed on the
// user's unrelated real install. The arms of the resolution are pinned in
// `src/NSharpLang.Compiler.Driver/NSharpInstallRoot.tests.nl`; these rows prove the shipped
// command reads the environment variable at all.
//
// THE PAIR IS WHAT MAKES THE CLAIM HOLD ON EVERY MACHINE. On a machine with no `~/.nsharp`, only
// the populated row can tell the override from the default; on a developer machine with a real
// install, only the empty row can. Neither row asserts the overall exit code of the populated run,
// because templates and `nsharp-lsp` on PATH are facts about the machine, not about this check.

func NlcWithInstallDir(arguments: string, installDir: string): CliRun {
    startInfo := new ProcessStartInfo { FileName: "dotnet", Arguments: "\"" + CliDll() + "\" " + arguments }
    startInfo.WorkingDirectory = Path.GetTempPath()
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    startInfo.Environment["NSHARP_INSTALL_DIR"] = installDir

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

func DoctorCheckNamed(stdout: string, name: string): JsonElement {
    document := JsonDocument.Parse(stdout)
    enumerator := document.RootElement.GetProperty("checks").EnumerateArray()
    while enumerator.MoveNext() {
        check := enumerator.Current
        if TextOf(check.GetProperty("name")) == name {
            return check.Clone()
        }
    }

    throw new InvalidOperationException("nlc doctor --json reported no '" + name + "' check.")
}

test "nlc doctor checks the package cache under NSHARP_INSTALL_DIR and passes when the SDK package is there" {
    installDir := NewTempDirectory("nsharp-doctor-install")
    packages := Path.Combine(installDir, "packages")
    Directory.CreateDirectory(packages)
    File.WriteAllText(Path.Combine(packages, "NSharpLang.Sdk.0.0.0-doctor.nupkg"), "")
    try {
        run := NlcWithInstallDir("doctor --json --skip-vscode", installDir)

        check := DoctorCheckNamed(run.Stdout, "nsharp-packages")
        assert TextOf(check.GetProperty("status")) == "pass", run.Stdout
        assert TextOf(check.GetProperty("detail")) == packages, run.Stdout
    } finally {
        Directory.Delete(installDir, true)
    }
}

test "nlc doctor fails the package check by naming the NSHARP_INSTALL_DIR cache when it is empty" {
    installDir := NewTempDirectory("nsharp-doctor-install")
    packages := Path.Combine(installDir, "packages")
    try {
        run := NlcWithInstallDir("doctor --json --skip-vscode", installDir)

        assert run.ExitCode == 1, run.Stdout
        check := DoctorCheckNamed(run.Stdout, "nsharp-packages")
        assert TextOf(check.GetProperty("status")) == "fail", run.Stdout
        assert TextOf(check.GetProperty("detail")) == "N# package cache was not found at " + packages + "; rerun the N# installer", run.Stdout
    } finally {
        Directory.Delete(installDir, true)
    }
}
