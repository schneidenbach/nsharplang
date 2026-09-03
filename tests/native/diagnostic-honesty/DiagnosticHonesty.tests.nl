namespace NSharpLang.DiagnosticHonesty.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO


// WHAT THE COMPILER SAYS, MEASURED BY RUNNING IT.
//
// The estate proves the rules; this proves the PRODUCT. Every claim below is made against the bytes
// the shipped `nlc` writes for a program held here as a literal — no harness in the middle, no
// analyzer object constructed in-process, nothing that can be true of a code path a user never
// takes. It is the same instrument `tests/native/error-docs-contract` uses on the documentation
// pages, pointed at the sentences instead.
//
// THE ONE THING A CONTRACT LIKE THIS MUST PROVE ABOUT ITSELF IS THAT IT READS ANYTHING AT ALL. A
// sweep for an absent substring passes trivially when the reader is empty, and the error-docs slice
// found exactly that failure: `nlc check --text` writes its DIAGNOSTICS TO STDERR and only its
// summary to stdout, so a harness reading stdout alone saw nothing and approved everything. Both
// streams are read here, every sweep asserts the run produced diagnostics before it asserts what
// they do not say, and one control asserts the sweep CAN see the forbidden characters when they are
// legitimately present.
class DhProbe {
    static func RepositoryRoot(): string {
        current: string? = Path.GetFullPath(Environment.CurrentDirectory)
        while current != null {
            value := current ?? ""
            if File.Exists(Path.Combine(value, "AGENTS.md")) && Directory.Exists(Path.Combine(value, "src")) && Directory.Exists(Path.Combine(value, "tests")) {
                return value
            }

            parent := Path.GetDirectoryName(value)
            if parent == null || parent == "" || parent == value {
                current = null
            } else {
                current = parent
            }
        }

        throw new InvalidOperationException("Could not locate the repository root above this test tree.")
    }

    static func CliPath(): string {
        root := DhProbe.RepositoryRoot()
        cli := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0")
        return Path.Combine(cli, "Cli.dll")
    }

    static func WorkspaceRoot(): string {
        return Path.Combine(Path.GetTempPath(), "nsharp-diagnostic-honesty")
    }

    // `library` so a probe never has to invent a `main` it would then have to explain. `companions`
    // is zero or more further files, each introduced by its own `// FILE <name>.nl` header line —
    // the same shape the error-docs contract uses, so a multi-file rule can be stated here too.
    static func Run(name: string, command: string, source: string, companions: string): string {
        directory := Path.Combine(DhProbe.WorkspaceRoot(), name)
        if Directory.Exists(directory) {
            Directory.Delete(directory, true)
        }

        Directory.CreateDirectory(directory)
        File.WriteAllText(Path.Combine(directory, "project.yml"), "name: DiagnosticHonestyProbe\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(Path.Combine(directory, "Program.nl"), source)
        DhWriteCompanions(directory, companions)

        arguments := "\"" + DhProbe.CliPath() + "\" " + command + " --project \"" + directory + "\" --text"
        startInfo := new ProcessStartInfo("dotnet", arguments)
        startInfo.RedirectStandardOutput = true
        startInfo.RedirectStandardError = true
        startInfo.UseShellExecute = false
        process := new Process { StartInfo: startInfo }
        process.Start()

        // BOTH STREAMS. Diagnostics go to stderr and the summary to stdout; a reader that takes one
        // of them is a contract that reads nothing.
        errorText := process.StandardError.ReadToEnd()
        standardText := process.StandardOutput.ReadToEnd()
        process.WaitForExit()
        process.Dispose()
        Directory.Delete(directory, true)
        return errorText + "\n" + standardText
    }

    static func Check(name: string, source: string): string {
        return DhProbe.Run(name, "check", source, "")
    }
}

func DhWriteCompanions(directory: string, companions: string) {
    if companions.Length == 0 {
        return
    }

    header := "// FILE "
    lines := companions.Split('\n')
    currentName := ""
    currentText := ""
    index := 0
    while index < lines.Length {
        line := lines[index]
        if line.StartsWith(header, StringComparison.Ordinal) {
            if currentName.Length > 0 {
                File.WriteAllText(Path.Combine(directory, currentName), currentText)
            }

            currentName = line.Substring(header.Length).Trim()
            currentText = line + "\n"
        } else if currentName.Length > 0 {
            currentText = currentText + line + "\n"
        }

        index = index + 1
    }

    if currentName.Length > 0 {
        File.WriteAllText(Path.Combine(directory, currentName), currentText)
    }
}

// How many diagnostic headers the run printed. The header is matched by CONTENT — a bracketed code,
// a severity word and the file position — rather than by the box-drawing rule it is padded with, so
// the match does not depend on how the child process's bytes survive the pipe.
func DhDiagnosticCount(output: string): int {
    count := 0
    lines := output.Split('\n')
    index := 0
    while index < lines.Length {
        line := lines[index].Replace("\r", "")
        bracket := line.IndexOf("[", StringComparison.Ordinal)
        if bracket >= 0 && line.IndexOf("] ", StringComparison.Ordinal) > bracket && line.IndexOf("Program.nl:", StringComparison.Ordinal) > bracket {
            count = count + 1
        }

        index = index + 1
    }

    return count
}

func DhCodeCount(output: string, code: string): int {
    count := 0
    lines := output.Split('\n')
    marker := "[" + code + "]"
    index := 0
    while index < lines.Length {
        if lines[index].IndexOf(marker, StringComparison.Ordinal) >= 0 {
            count = count + 1
        }

        index = index + 1
    }

    return count
}

func DhCarriesPlaceholder(output: string): bool {
    return output.IndexOf("<error>", StringComparison.Ordinal) >= 0
}

// ═══ THE PLACEHOLDER SWEEP ════════════════════════════════════════════════════════════════════
//
// Each row is `name|source`, and every source is a shape that makes the recovery parser mint its
// `<error>` placeholder — a name it could not read in a parameter list, a field, a declaration head,
// an enum body, a type position. NONE of them contains the characters `<error>` in its own text, so
// any occurrence in the output came from the compiler and not from the echo of a source line.
//
// Before this guard these five printed twenty-three sentences quoting the placeholder between them:
// `Identifier '<error>' starts with a non-letter character`, `A type named '<error>' already
// exists`, `Type '<error>' not found` and `Parameter '<error>' in 'main' is never read`.
func DhPlaceholderPrograms(): List<string> {
    programs := new List<string>()
    programs.Add("parameter|func Add(a: int, 5: int): int {\n    return a\n}\n")
    programs.Add("field|class Box {\n    5: int\n}\n")
    programs.Add("declaration-head|func () {\n}\n")
    programs.Add("class-head|class {\n}\n")
    programs.Add("enum-newlines|enum Color {\n    Red\n    Green\n}\n\nfunc Pick(): Color {\n    return Color.Red\n}\n")
    programs.Add("field-without-type|class User {\n    Name:\n}\n\nfunc Read(user: User): string {\n    return user.Name\n}\n")
    return programs
}

func DhPlaceholderLeaks(): string {
    leaks := ""
    programs := DhPlaceholderPrograms()
    index := 0
    while index < programs.Count {
        row := programs[index]
        separator := row.IndexOf("|", StringComparison.Ordinal)
        name := row.Substring(0, separator)
        source := row.Substring(separator + 1)
        output := DhProbe.Check("placeholder-" + name, source)
        if DhDiagnosticCount(output) == 0 {
            leaks = leaks + name + ":REPORTED-NOTHING-so-this-row-proves-nothing;"
        }

        if DhCarriesPlaceholder(output) {
            leaks = leaks + name + ":PRINTED-THE-PLACEHOLDER;"
        }

        index = index + 1
    }

    return leaks
}

test "the built CLI these contracts run their programs through is present" {
    assert File.Exists(DhProbe.CliPath()), DhProbe.CliPath()
}

test "NO shape that makes the parser mint its `<error>` placeholder can print it — six programs, each of which DOES report" {
    assert DhPlaceholderLeaks() == "", DhPlaceholderLeaks()
}

test "the sweep is not vacuous: it SEES the characters when the source itself carries them, because the echoed snippet is deliberately not guarded" {
    source := "func Run() {\n    message := \"<error>\"\n}\n"
    output := DhProbe.Check("placeholder-liveness", source)
    assert DhDiagnosticCount(output) > 0, output
    // The unused-local report survives — its own MESSAGE names `message`, not the placeholder — and
    // its snippet echoes the user's line back verbatim, characters and all. That is what proves the
    // reader above can see these bytes at all.
    assert DhCodeCount(output, "NL001") == 1, output
    assert DhCarriesPlaceholder(output), output
}

test "the suppressed cascade takes NOTHING true with it — the one report that names what the user wrote survives" {
    // `func Add(a: int, 5: int)`: the parser says what it found, at the character it found it.
    parameter := DhProbe.Check("survivor-parameter", "func Add(a: int, 5: int): int {\n    return a\n}\n")
    assert DhCodeCount(parameter, "NL102") == 1, parameter
    assert !DhCarriesPlaceholder(parameter), parameter

    // `class Box { 5: int }`: before the guard this printed three diagnostics, two of them about a
    // type and an identifier named `<error>`. One is left and it is the true one.
    field := DhProbe.Check("survivor-field", "class Box {\n    5: int\n}\n")
    assert DhDiagnosticCount(field) == 1, field
    assert DhCodeCount(field, "NL102") == 1, field

    // A field with no type still reports the genuine consequence — the member does not exist — and
    // no longer reports `Type '<error>' not found` beside it.
    consequence := DhProbe.Check("survivor-consequence", "class User {\n    Name:\n}\n\nfunc Read(user: User): string {\n    return user.Name\n}\n")
    assert DhCodeCount(consequence, "NL102") == 1, consequence
    assert DhCodeCount(consequence, "NL303") == 1, consequence
    assert DhCodeCount(consequence, "NL201") == 0, consequence
    assert !DhCarriesPlaceholder(consequence), consequence
}

test "a well-formed program is untouched by the guard: it reports nothing at all" {
    output := DhProbe.Check("clean", "func Total(prices: int[]): int {\n    sum := 0\n    for price in prices {\n        sum = sum + price\n    }\n\n    return sum\n}\n")
    assert DhDiagnosticCount(output) == 0, output
}
