namespace NSharpLang.Cli

import System
import System.IO
import System.Text.RegularExpressions


// THE CANONICAL CONTRACTS FOR `DotnetRunner`, IN N#.
//
// These replace `tests/DotnetRunnerTests.cs`, the last canonical C# assertion layer over
// `DotnetRunner.nl`. The runner is how every `nlc` command that shells out reaches the .NET SDK:
// it starts a process, captures its two streams SEPARATELY, and answers the exit code.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT — AND WHY THE INHERITED INVENTORY WAS WRONG.
// The previous slice classified this cluster as the one `tests/native`-routable row, on the theory
// that its arguments are primitive. They are, but the SUBJECT lives here: `DotnetRunner.nl` is a
// file of THIS project, in namespace `NSharpLang.Cli`, reached by an `import`. So the estate can
// assert on it directly, its `DotnetRunResult` answers cross no assembly boundary, and no
// `tests/native` project is needed at all.
//
// BOTH OF THIS BATCH'S MEASURED WALLS MEET HERE. (1) Omitting a defaulted parameter declines at
// `emit.local.initializer` — on static methods, not only on free funcs — so `Run` and `RunProcess`
// are spelled at FULL ARITY. `DotnetRunner.Run("--version")` becomes `DotnetRunner.Run("--version",
// null, true, null)`: the same call with its three defaults written out, including the `TimeSpan?`
// that spells fine as a bare `null`. (2) A `TimeSpan` may be CONSTRUCTED and PASSED but not
// INTERROGATED — see the timeout contract below.
//
// THE REGEX ROW IS KEPT AND THEN DECODED. The deleted file asserted `Assert.Matches(@"\d+\.\d+",
// stdout)`. `System.Text.RegularExpressions` IS in the emitter's catalog — measured, not assumed —
// so that assertion survives verbatim; and because a regex is the one assertion here whose meaning
// is not readable at a glance, the same claim is ALSO made by a hand-written scan that answers
// "some digit, then a dot, then a digit". Two independent decodings of one row.
//
// THESE ROWS START REAL PROCESSES, DELIBERATELY. `dotnet --version` is the hermetic probe the
// deleted file chose — no external tool, no network, and the SDK is present by definition whenever
// this suite runs at all.
//
// THE THREE THINGS IT IS EASY TO GET WRONG:
//
// (1) THE STREAMS ARE SEPARATE. A successful command's diagnostics must not turn up in `Stdout`,
// and a merged-stream implementation passes every "stdout is not empty" assertion ever written.
//
// (2) CAPTURING IS A CHOICE, AND NOT CAPTURING STILL ANSWERS. With `captureOutput` false the
// process's output goes to the console and the result carries EMPTY strings — not `null`, which
// would fault every caller that trims or measures them.
//
// (3) THE EXIT CODE IS THE PROCESS'S, NOT THE RUNNER'S. A command that fails must answer non-zero
// with both streams still readable, because that is what the CLI reports to the user.

func DotnetRunnerContractHasDigitDotDigit(text: string): bool {
    index := 0
    while index + 2 < text.Length {
        if char.IsDigit(text[index]) && text[index + 1] == '.' && char.IsDigit(text[index + 2]) {
            return true
        }

        index = index + 1
    }

    return false
}

// ---- Capturing ------------------------------------------------------------------------------

// Successor to DotnetRunner_CapturesOutput.
test "dotnet runner captures stdout" {
    result := DotnetRunner.Run("--version", null, true, null)

    assert result.ExitCode == 0
    assert !string.IsNullOrWhiteSpace(result.Stdout), "Expected non-empty stdout from 'dotnet --version'"

    // The deleted file's regex row, kept verbatim — and then decoded by hand, so the claim is
    // legible without a regex engine.
    assert Regex.IsMatch(result.Stdout, "\\d+\\.\\d+")
    assert DotnetRunnerContractHasDigitDotDigit(result.Stdout)

    // NOT IN THE DELETED FILE: the captured text is a SINGLE line — the version and nothing else —
    // which is what every caller that parses it depends on.
    trimmed := result.Stdout.Trim()
    assert trimmed.Length > 0
    assert !trimmed.Contains("\n")
    assert char.IsDigit(trimmed[0])
}

// Successor to DotnetRunner_StderrIsCapturedSeparately.
test "dotnet runner captures stderr separately" {
    result := DotnetRunner.Run("--version", null, true, null)

    assert result.ExitCode == 0
    assert string.IsNullOrWhiteSpace(result.Stderr)

    // NOT IN THE DELETED FILE: separate means BOTH ways — the version text is on stdout and is not
    // also on stderr.
    assert !string.IsNullOrWhiteSpace(result.Stdout)
    reported := result.Stdout.Trim()
    assert !result.Stderr.Contains(reported)
}

// Successor to DotnetRunner_ReturnsNonZeroExitCode.
test "dotnet runner reports a non zero exit code" {
    result := DotnetRunner.Run("not-a-real-command-nlc-test-xyz", null, true, null)

    assert result.ExitCode != 0

    // NOT IN THE DELETED FILE: a FAILING command still answers both streams rather than leaving
    // them null, which is what the CLI prints when it reports the failure.
    assert result.Stdout != null
    assert result.Stderr != null
}

// Successor to DotnetRunner_RunProcess_CapturesOutput.
test "dotnet runner runs a named process" {
    result := DotnetRunner.RunProcess("dotnet", "--version", null, null)

    assert result.ExitCode == 0
    assert !string.IsNullOrWhiteSpace(result.Stdout)

    // NOT IN THE DELETED FILE: naming the process explicitly answers exactly what the `dotnet`
    // shorthand does, so the two entry points cannot drift apart.
    shorthand := DotnetRunner.Run("--version", null, true, null)
    named := result.Stdout.Trim()
    assert named == shorthand.Stdout.Trim()
}

// Successor to DotnetRunner_WorkingDirectory_IsRespected.
test "dotnet runner respects an explicit working directory" {
    temporaryDirectory := Path.GetTempPath()

    result := DotnetRunner.Run("--version", temporaryDirectory, true, null)

    assert result.ExitCode == 0
    assert !string.IsNullOrWhiteSpace(result.Stdout)

    // NOT IN THE DELETED FILE: the same directory is accepted by the named-process entry point too,
    // which is the one that builds the start info for BOTH.
    named := DotnetRunner.RunProcess("dotnet", "--version", temporaryDirectory, null)
    assert named.ExitCode == 0
    assert !string.IsNullOrWhiteSpace(named.Stdout)
}

// ---- Not capturing, arguments and timeouts ---------------------------------------------------

// NOT IN THE DELETED FILE. The non-capturing arm: the exit code is still answered and the two
// streams are EMPTY STRINGS rather than null, so a caller may trim and measure them unconditionally.
test "dotnet runner answers empty output when it is not capturing" {
    result := DotnetRunner.Run("--version", null, false, null)

    assert result.ExitCode == 0
    assert result.Stdout == ""
    assert result.Stderr == ""
}

// NOT IN THE DELETED FILE. The ARGUMENTS reach the process: two different argument strings produce
// two different captures, which "stdout is not empty" cannot show.
test "dotnet runner passes its arguments to the process" {
    version := DotnetRunner.Run("--version", null, true, null)
    info := DotnetRunner.Run("--info", null, true, null)

    assert version.ExitCode == 0
    assert info.ExitCode == 0
    assert info.Stdout.Length > version.Stdout.Length
}

// NOT IN THE DELETED FILE. An EXPLICIT timeout is honoured — the arm that decides how long a hung
// `dotnet` may hold the CLI, and the only one of the four parameters the deleted file never passed.
//
// THE VALUE OF `DefaultTimeout` IS NOT ASSERTED HERE, AND THAT IS A MEASURED WALL RATHER THAN A
// CHOICE: reading ANY member off a `TimeSpan` — `TotalMinutes`, `Minutes`, `Hours` — declines at
// `emit.statement.block-child`, both as a `double` comparison and as an integer one. A `TimeSpan`
// may be CONSTRUCTED and PASSED here; it may not be interrogated.
test "dotnet runner honours an explicit timeout" {
    oneMinute := TimeSpan.FromMinutes(1)

    result := DotnetRunner.Run("--version", null, true, oneMinute)

    assert result.ExitCode == 0
    assert !string.IsNullOrWhiteSpace(result.Stdout)
}

// NOT IN THE DELETED FILE, AND IT STARTS NO PROCESS AT ALL. The result carries its three values in
// their own members — a constructor that transposed two of them would still pass every row above,
// because a successful `dotnet --version` has an exit code of 0 and an empty stderr.
test "dotnet runner result carries its three members" {
    result := new DotnetRunResult(3, "the output", "the error")

    assert result.ExitCode == 3
    assert result.Stdout == "the output"
    assert result.Stderr == "the error"
}
