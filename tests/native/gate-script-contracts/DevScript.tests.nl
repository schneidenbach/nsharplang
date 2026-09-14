namespace NSharpLang.GateScriptContracts.Tests

import System
import System.IO

// ─── THE DEVELOPMENT ESTATE EVIDENCE GUARD ────────────────────────────────────────────────────
//
// `scripts/dev.sh --estate` used to trust `dotnet test`'s exit code alone. A filtered run can
// report success without executing a test, so every row below installs a disposable fake `dotnet`
// ahead of PATH and invokes the script with `--no-build`. The fake restore is silent and succeeds;
// only its test output varies, so no real build, restore, or cache is touched.
func FakeDotnetScript(testOutput: string, testExitCode: int): string {
    return "#!/usr/bin/env bash\n" + "if [ \"${1:-}\" = \"test\" ]; then\n" + "  cat <<'TEST_OUTPUT'\n" + testOutput + "TEST_OUTPUT\n" + "  exit " + testExitCode.ToString() + "\n" + "fi\n" + "exit 0\n"
}

func MakeFakeDotnet(directory: string, testOutput: string, testExitCode: int): string {
    bin := Path.Combine(directory, "bin")
    Directory.CreateDirectory(bin)
    dotnet := Path.Combine(bin, "dotnet")
    File.WriteAllText(dotnet, FakeDotnetScript(testOutput, testExitCode))

    chmod := new ProcessLaunch("chmod", RepositoryRoot(), 60000)
    chmod.Arguments.Add("+x")
    chmod.Arguments.Add(dotnet)
    chmodRun := Run(chmod)
    if chmodRun.ExitCode != 0 {
        throw new InvalidOperationException("Could not make synthetic dotnet executable: " + chmodRun.Report())
    }

    return bin
}

func RunDevEstateWithFakeDotnet(testOutput: string, testExitCode: int): ProcessRun {
    temporaryRoot := NewTempDirectory("nsharp-dev-estate-evidence")
    try {
        bin := MakeFakeDotnet(temporaryRoot, testOutput, testExitCode)
        launch := new ProcessLaunch("bash", RepositoryRoot(), 60000)
        launch.Arguments.Add("scripts/dev.sh")
        launch.Arguments.Add("--no-build")
        launch.Arguments.Add("--estate")
        launch.Arguments.Add("DeliberatelyMissing")
        launch.WithEnvironment("PATH", bin + ":" + (Environment.GetEnvironmentVariable("PATH") ?? ""))
        return Run(launch)
    } finally {
        DeleteTempDirectory(temporaryRoot)
    }
}

func RequireMissingEstateEvidence(run: ProcessRun) {
    assert run.ExitCode != 0, "dev.sh accepted output that did not prove a test run: " + run.Report()
    assert run.Stdout.Contains("Estate rows did not produce a nonempty successful test summary"), run.Report()
    assert run.Stdout.Contains("Expected one VSTest or N# native summary line with Passed: > 0, Failed: 0, and Total: > 0."), run.Report()
    assert !run.Stdout.Contains("Estate rows passed"), run.Report()
}

test "dev estate rejects an exit-zero test command with no output" {
    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet("", 0))
}

test "dev estate rejects no-matching-test output that exits zero" {
    run := RunDevEstateWithFakeDotnet("No test matches the given testcase filter.\n", 0)

    RequireMissingEstateEvidence(run)
    assert run.Stdout.Contains("No test matches the given testcase filter."), run.Report()
}

test "dev estate rejects a zero-total summary that exits zero" {
    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet("Passed: 0, Failed: 0, Skipped: 0, Total: 0\n", 0))
}

test "dev estate rejects a skipped-only summary that exits zero" {
    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet("Passed: 0, Failed: 0, Skipped: 2, Total: 2\n", 0))
}

test "dev estate rejects a failed summary even when the test process exits zero" {
    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet("Passed: 2, Failed: 1, Skipped: 0, Total: 3\n", 0))
}

test "dev estate rejects mixed failed and passing summaries" {
    output := "Failed!  - Failed: 1, Passed: 2, Skipped: 0, Total: 3, Duration: 18 ms\n" + "Passed!  - Failed: 0, Passed: 2, Skipped: 0, Total: 2, Duration: 18 ms\n"

    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet(output, 0))
}

test "dev estate rejects counters split across separate lines" {
    output := "Passed: 2\nFailed: 0\nSkipped: 0\nTotal: 2\n"

    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet(output, 0))
}

test "dev estate accepts a positive VSTest summary" {
    run := RunDevEstateWithFakeDotnet("Passed!  - Failed: 0, Passed: 2, Skipped: 0, Total: 2, Duration: 18 ms\n", 0)

    assert run.ExitCode == 0, run.Report()
    assert run.Stdout.Contains("Estate rows passed"), run.Report()
}

test "dev estate accepts the N# native test summary format" {
    run := RunDevEstateWithFakeDotnet("Passed: 2, Failed: 0, Skipped: 0, Total: 2\n", 0)

    assert run.ExitCode == 0, run.Report()
    assert run.Stdout.Contains("Estate rows passed"), run.Report()
}

test "dev estate preserves a nonzero test process exit" {
    run := RunDevEstateWithFakeDotnet("Passed: 2, Failed: 0, Skipped: 0, Total: 2\n", 23)

    assert run.ExitCode == 23, run.Report()
    assert run.Stdout.Contains("Estate rows failed"), run.Report()
    assert !run.Stdout.Contains("Estate rows passed"), run.Report()
}
