namespace NSharpLang.SystemsVectorizationFacts.Tests

import System
import System.Diagnostics
import System.IO


// THE DOCUMENTED OPT-OUT IS DEAD, AND THIS FILE IS THE PROOF.
//
// THE FINDING. `website/docs/systems.md` used to tell users that `NSHARP_VECTORIZE_REDUCTIONS=0` disables the
// SIMD rewrites. It does not, and has not since 2026-06-23. `grep -rn VECTORIZE src/` finds NOTHING: the
// environment variable was read only by the legacy C# IL compiler, and `git log -S NSHARP_VECTORIZE_REDUCTIONS
// -- src/` shows exactly two commits touching it — b1326cb89, which introduced it with the first
// auto-vectorized reduction, and 1cef0d16e ("Delete legacy C# IL compiler fallback", 2026-06-23), which
// removed the only reader along with the rest of that compiler. The columnar emitter that replaced it calls
// `TryEmitVectorizedReduction{While,For}` and its three siblings UNCONDITIONALLY from the generic while/for
// emission; there is no flag, no project.yml switch and no environment variable in front of them.
//
// WHAT THIS CONTRACT PINS. Not "the opt-out works" and not "the opt-out is absent" as an opinion, but the
// observable consequence: THREE builds of the same fixture — with the variable unset, set to 0, and set to 1
// — produce an assembly that still references `SimdReductions.SumInt32`, and still prints the same checksum.
// The name is checked in the emitted METADATA rather than through reflection because the `SumInt32` string
// only exists in an assembly's `#Strings` heap if the emitter wrote a MemberRef to that method, which it does
// only when the vectorizer fired.
//
// WHAT THE 015 OWNER MUST DO. Task 015 deletes `ColumnarIlEmitter.cs` and gives the vectorizer an N# owner.
// That owner has two honest options, and this file is the switch between them:
//   * RESTORE AN OPT-OUT. Then the `=0` build stops referencing the helper, this contract's `=0` assertions
//     must be FLIPPED to assert absence, and the docs paragraph can be restored.
//   * KEEP NO OPT-OUT. Then this contract stands as written and the docs stay corrected (the corrected
//     paragraph in `website/docs/systems.md` already points at this project).
// What the owner may NOT do is leave the documentation and the compiler disagreeing again.
//
// THE FIXTURE LIVES OUTSIDE THIS PROJECT, at `tests/fixtures/systems-vectorization/opt-out-probe`, because a
// `.nl` file inside `tests/native/systems-vectorization-facts` would be compiled INTO this test assembly.
// `tests/fixtures/` is already part of the gate's UNIT input set, so no gate-script change is needed for the
// cache to notice edits to it.
//
// Maps: no deleted test. The deleted suite never covered the opt-out; this contract exists because reading
// the emitter to write the other four files turned up a documented switch that no longer exists.

class ProcessResult {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

class OptOutProbe {
    // Start a child process, drain both pipes before waiting (so a chatty child cannot deadlock on a full
    // pipe buffer), and dispose it, so this project leaves no orphan `dotnet` behind.
    //
    // The child's environment is set on THIS process rather than on the ProcessStartInfo: both
    // `startInfo.Environment.Add` and `startInfo.EnvironmentVariables.Add` decline on this emit path
    // (NL103, emit.expression-statement.call), while `Environment.SetEnvironmentVariable` is modelled, and a
    // child process inherits its parent's environment. `BuildWith` below sets the variable, builds, and
    // restores whatever was there before, so the setting never leaks past one build.
    static func RunProcess(fileName: string, arguments: string, workingDirectory: string): ProcessResult {
        startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
        startInfo.WorkingDirectory = workingDirectory
        startInfo.RedirectStandardOutput = true
        startInfo.RedirectStandardError = true
        startInfo.UseShellExecute = false

        process := new Process { StartInfo: startInfo }
        process.Start()
        stdout := process.StandardOutput.ReadToEnd()
        stderr := process.StandardError.ReadToEnd()
        process.WaitForExit()
        exitCode := process.ExitCode
        process.Dispose()
        return new ProcessResult(exitCode, stdout, stderr)
    }

    // The repository root, found by walking up from the directory this test assembly was loaded into (which
    // is the CLI's own directory, because `nlc test` hosts the emitted tests in its process).
    static func RepositoryRoot(): string {
        current: string? = AppContext.BaseDirectory
        while current != null {
            directory := current ?? ""
            if File.Exists(Path.Combine(directory, "NSharpLang.sln"))
                && Directory.Exists(Path.Combine(directory, "src"))
                && Directory.Exists(Path.Combine(directory, "tests")) {
                return directory
            }

            parent := Path.GetDirectoryName(directory)
            if parent == null || parent == "" || parent == directory {
                current = null
            } else {
                current = parent
            }
        }

        throw new InvalidOperationException("Could not locate the repository root above this test tree.")
    }

    static func CliDll(): string {
        root := RepositoryRoot()
        binDirectory := Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug")
        cliDll := Path.Combine(Path.Combine(binDirectory, "net10.0"), "Cli.dll")
        if !File.Exists(cliDll) {
            throw new InvalidOperationException("The built N# CLI was not found beside the repository root.")
        }

        return cliDll
    }

    static func FixtureDirectory(): string {
        root := RepositoryRoot()
        fixtures := Path.Combine(Path.Combine(Path.Combine(root, "tests"), "fixtures"), "systems-vectorization")
        directory := Path.Combine(fixtures, "opt-out-probe")
        if !Directory.Exists(directory) {
            throw new InvalidOperationException("The opt-out probe fixture was not on disk.")
        }

        return directory
    }

    static func FixtureOutputDirectory(): string {
        return Path.Combine(Path.Combine(Path.Combine(FixtureDirectory(), "bin"), "Debug"), "net10.0")
    }

    static func FixtureAssembly(): string {
        return Path.Combine(FixtureOutputDirectory(), "NSharpLang.VectorizationOptOutProbe.dll")
    }

    // Build the fixture with `NSHARP_VECTORIZE_REDUCTIONS` set to `setting` ("" meaning unset), restore the
    // ambient value afterwards, and report the CLI's exit code.
    static func BuildExitCode(setting: string): int {
        variable := "NSHARP_VECTORIZE_REDUCTIONS"
        previous := Environment.GetEnvironmentVariable(variable)
        if setting == "" {
            Environment.SetEnvironmentVariable(variable, null)
        } else {
            Environment.SetEnvironmentVariable(variable, setting)
        }

        run := RunProcess("dotnet", "\"" + CliDll() + "\" build --project \"" + FixtureDirectory() + "\"", Path.GetTempPath())
        Environment.SetEnvironmentVariable(variable, previous)
        if run.ExitCode != 0 {
            Console.Error.WriteLine(run.Stdout + run.Stderr)
        }

        return run.ExitCode
    }

    // Whether the freshly built assembly's metadata still names the SIMD helper. The `#Strings` heap holds
    // that name only if the emitter wrote a MemberRef to `SimdReductions.SumInt32`, which happens only when
    // the reduction was lowered.
    static func BuiltAssemblyNamesHelper(): bool {
        return ContainsAscii(File.ReadAllBytes(FixtureAssembly()), "SumInt32")
    }

    // Whether the freshly built assembly names a helper that does not exist, which it must not.
    static func BuiltAssemblyNamesMissingHelper(): bool {
        return ContainsAscii(File.ReadAllBytes(FixtureAssembly()), "SumInt24")
    }

    // The checksum the freshly built assembly prints, trimmed of its trailing newline.
    static func BuiltAssemblyChecksum(): string {
        outputDirectory := FixtureOutputDirectory()
        run := RunProcess("dotnet", "\"" + FixtureAssembly() + "\"", outputDirectory)
        if run.ExitCode != 0 {
            return "exit " + run.ExitCode.ToString() + ": " + run.Stderr
        }

        return run.Stdout.Trim()
    }

    // An ordinal search for `text`'s ASCII bytes inside `bytes`.
    static func ContainsAscii(bytes: byte[], text: string): bool {
        limit := bytes.Length - text.Length
        for start := 0; start <= limit; start++ {
            matched := true
            for k := 0; k < text.Length; k++ {
                if (int)bytes[start + k] != (int)text[k] {
                    matched = false
                    break
                }
            }

            if matched {
                return true
            }
        }
        return false
    }
}

// The fixture's `Main` sums `k * 3 - 7` over 1000 elements: 3 * 499500 - 7000.
func ExpectedChecksum(): string {
    return "1491500"
}

func AsciiBytes(text: string): byte[] {
    bytes := new byte[text.Length]
    for k := 0; k < text.Length; k++ {
        bytes[k] = (byte)text[k]
    }
    return bytes
}

test "the ascii scan finds a name that is present and rejects one that is not" {
    // Pins the metadata probe itself before it is used as evidence.
    assert OptOutProbe.ContainsAscii(AsciiBytes("xxSumInt32yy"), "SumInt32")
    assert !OptOutProbe.ContainsAscii(AsciiBytes("xxSumInt24yy"), "SumInt32")
    assert !OptOutProbe.ContainsAscii(AsciiBytes("SumInt3"), "SumInt32")
    assert OptOutProbe.BuildExitCode("") == 0
    assert !OptOutProbe.BuiltAssemblyNamesMissingHelper()
}

test "building the probe with the vectorization opt-out unset emits the SIMD helper reference" {
    assert OptOutProbe.BuildExitCode("") == 0
    assert OptOutProbe.BuiltAssemblyNamesHelper()
    assert OptOutProbe.BuiltAssemblyChecksum() == ExpectedChecksum()
}

test "the documented NSHARP_VECTORIZE_REDUCTIONS=0 opt-out has no effect on the emitted assembly" {
    assert OptOutProbe.BuildExitCode("0") == 0
    assert OptOutProbe.BuiltAssemblyNamesHelper()
    assert OptOutProbe.BuiltAssemblyChecksum() == ExpectedChecksum()
}

test "setting NSHARP_VECTORIZE_REDUCTIONS=1 changes nothing either, because nothing reads it" {
    assert OptOutProbe.BuildExitCode("1") == 0
    assert OptOutProbe.BuiltAssemblyNamesHelper()
    assert OptOutProbe.BuiltAssemblyChecksum() == ExpectedChecksum()
}
