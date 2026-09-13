namespace NSharpLang.CensusImportUsage.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text.Json


// NL010 AND NL002, ANSWERED BY WHAT A FILE BOUND — PROVEN THROUGH THE SHIPPED COMPILER.
//
// Both rules used to answer from hand-written tables of BCL spellings: NL010 from a closed-world list
// of the names each of ten namespaces provides (112 for `System` alone), NL002 from a 25-name
// whitelist. The tables could not be finished, and the census found both failures in one name:
//
//   * `import System` beside `OperatingSystem.IsWindows()` was reported UNUSED, because the `System`
//     row had never heard of `OperatingSystem` — on an ERROR whose `nlc fix` DELETES the line.
//   * The same file WITHOUT the import was accepted in silence, because NL002's table had not heard
//     of the name either.
//
// A namespace with no row at all was reported USED no matter what, so a dead import of any name
// outside those ten rows — a project's own namespace included — was invisible.
//
// These rows are that regression, end to end: real projects on disk, the real `nlc`, and for every
// reported import a REMOVAL CONTROL that builds, so an NL010 is never asserted without proof that
// the import really is dead.
class IuRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

func IuRunProcess(arguments: string, workingDirectory: string): IuRun {
    startInfo := new ProcessStartInfo { FileName: "dotnet", Arguments: arguments }
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
    return new IuRun(exitCode, stdout, stderr)
}

func IuRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
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

func IuCliDll(): string {
    root := IuRepositoryRoot()
    binDirectory := Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug")
    cliDll := Path.Combine(Path.Combine(binDirectory, "net10.0"), "Cli.dll")
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found beside the repository root.")
    }

    return cliDll
}

func IuNlcIn(workingDirectory: string, arguments: string): IuRun {
    return IuRunProcess("\"" + IuCliDll() + "\" " + arguments, workingDirectory)
}

func IuNewProject(prefix: string): string {
    directory := Path.Combine(Path.GetTempPath(), prefix + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    File.WriteAllText(
        Path.Combine(directory, "project.yml"),
        "name: ImportProbe\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    return directory
}

func IuWrite(directory: string, fileName: string, text: string) {
    File.WriteAllText(Path.Combine(directory, fileName), text)
}

func IuDelete(directory: string) {
    try {
        Directory.Delete(directory, true)
    // nlc:ignore NL011
    } catch {
    }
}

// Every `results` row of a `nlc check --json` run, as "<code>@<file>:<line>:<column>+<length>".
func IuCheckCensus(directory: string): string {
    run := IuNlcIn(directory, "check --json")
    census := ""
    document := JsonDocument.Parse(run.Stdout)
    try {
        enumerator := document.RootElement.GetProperty("results").EnumerateArray()
        while enumerator.MoveNext() {
            row := enumerator.Current
            census = census + (row.GetProperty("code").GetString() ?? "") + "@" + (row.GetProperty("file").GetString() ?? "") + ":" + row.GetProperty("line").GetInt32().ToString() + ":" + row.GetProperty("column").GetInt32().ToString() + "+" + row.GetProperty("length").GetInt32().ToString() + ";"
        }
    } finally {
        document.Dispose()
    }

    return census
}

func IuSuggestion(directory: string, code: string): string {
    run := IuNlcIn(directory, "check --json")
    found := ""
    document := JsonDocument.Parse(run.Stdout)
    try {
        enumerator := document.RootElement.GetProperty("results").EnumerateArray()
        while enumerator.MoveNext() {
            row := enumerator.Current
            if (row.GetProperty("code").GetString() ?? "") == code && found.Length == 0 {
                found = row.GetProperty("suggestion").GetString() ?? ""
            }
        }
    } finally {
        document.Dispose()
    }

    return found
}

// A project with one source file, checked, then the census.
func IuCensusOf(prefix: string, source: string): string {
    directory := IuNewProject(prefix)
    try {
        IuWrite(directory, "Program.nl", source)
        return IuCheckCensus(directory)
    } finally {
        IuDelete(directory)
    }
}

// ─── NL010: THE FALSE POSITIVE THE TABLE SHIPPED ──────────────────────────────────────────────

test "an import whose only use is a name no table carried is USED" {
    // THE CENSUS FINDING. `OperatingSystem` was not in the 112-name `System` row, so `import System`
    // beside it was reported unused — an ERROR, with a `nlc fix` that deletes the line the build
    // needs.
    assert IuCensusOf("nsharp-import-operating-system", "namespace Probe\n\nimport System\n\nclass Widget {\n    func Check(): bool {\n        return OperatingSystem.IsWindows()\n    }\n}\n") == ""
}

test "and the import really is load-bearing, which is what makes the silence above a fact" {
    // REMOVAL CONTROL, IN THE OTHER DIRECTION: with the import gone the name still resolves — the
    // bare-name scan finds it — and NL002 says the import that provides it is missing. So the two
    // rules are answering about the same name from the same measurement.
    census := IuCensusOf("nsharp-import-operating-system-missing", "namespace Probe\n\nclass Widget {\n    func Check(): bool {\n        return OperatingSystem.IsWindows()\n    }\n}\n")
    assert census == "NL002@Program.nl:5:16+15;", census
}

test "the suggestion names the namespace the analysis said supplied the name" {
    directory := IuNewProject("nsharp-import-suggestion")
    try {
        IuWrite(directory, "Program.nl", "namespace Probe\n\nclass Widget {\n    func Check(): bool {\n        return OperatingSystem.IsWindows()\n    }\n}\n")
        assert IuSuggestion(directory, "NL002") == "Add 'import System' at the top of the file"
    } finally {
        IuDelete(directory)
    }
}

// ─── NL010: THE FALSE NEGATIVE THE TABLE SHIPPED ──────────────────────────────────────────────

test "a dead import of a namespace no table ever named is reported" {
    // `System.Runtime.CompilerServices` had no row, so it was reported USED no matter what — and so
    // was every dead import of a project's own namespace.
    census := IuCensusOf("nsharp-import-unlisted-dead", "namespace Probe\n\nimport System.Runtime.CompilerServices\n\nclass Widget {\n    Name: string => \"w\"\n}\n")
    assert census == "NL010@Program.nl:3:8+36;", census
}

test "a dead import of the PROJECT'S OWN namespace is reported too" {
    directory := IuNewProject("nsharp-import-project-namespace")
    try {
        IuWrite(directory, "Parts.nl", "namespace Probe.Parts\n\nclass Gadget {\n    Name: string => \"g\"\n}\n")
        IuWrite(directory, "Program.nl", "namespace Probe\n\nimport Probe.Parts\n\nclass Widget {\n    Name: string => \"w\"\n}\n")
        assert IuCheckCensus(directory) == "NL010@Program.nl:3:8+11;"

        // REMOVAL CONTROL: use the namespace's type and the same import is silent.
        IuWrite(directory, "Program.nl", "namespace Probe\n\nimport Probe.Parts\n\nclass Widget {\n    func Make(): Gadget {\n        return new Gadget()\n    }\n}\n")
        assert IuCheckCensus(directory) == ""
    } finally {
        IuDelete(directory)
    }
}

// ─── THE CENSUS'S TWO `import System` FINDINGS, RESOLVED ──────────────────────────────────────

test "A FULLY QUALIFIED SPELLING USES NO IMPORT, so `import System` beside `System.Type` is dead" {
    // Both of the census's remaining `import System` findings in the converted language server are
    // this shape, and both are TRUE positives: `System.Type` and `System.Enum.GetValues<T>()` name
    // their types from the root, so the import supplies nothing. Proven by the control below, which
    // builds without it.
    census := IuCensusOf("nsharp-import-fully-qualified", "namespace Probe\n\nimport System\n\nclass Widget {\n    func Describe(value: System.Type): string {\n        return value.Name\n    }\n}\n")
    assert census == "NL010@Program.nl:3:8+6;", census
}

test "and the same file with the import deleted still builds, which is the proof" {
    directory := IuNewProject("nsharp-import-fully-qualified-control")
    try {
        IuWrite(directory, "Program.nl", "namespace Probe\n\nclass Widget {\n    func Describe(value: System.Type): string {\n        return value.Name\n    }\n}\n")
        assert IuCheckCensus(directory) == ""
        run := IuNlcIn(directory, "build")
        assert run.ExitCode == 0, run.Stdout + run.Stderr
    } finally {
        IuDelete(directory)
    }
}

// ─── EVERY CHANNEL A NAME CAN REACH AN IMPORT THROUGH ─────────────────────────────────────────
//
// Each row below is a file whose ONLY mention of its import is one kind of position. A channel the
// analyzer forgets to credit turns into a false NL010 on that shape — the failure mode that deletes
// working code — so every one of them is stated, and each is paired with a removal control that
// reports the same import once the use is taken out.

test "an EXTENSION METHOD call keeps its import alive, with no type of that namespace ever named" {
    // `import System.Linq` used only as `.Where(...)`: the file writes no LINQ type at all.
    assert IuCensusOf("nsharp-import-extension", "namespace Probe\n\nimport System.Collections.Generic\nimport System.Linq\n\nclass Widget {\n    func Evens(values: List<int>): List<int> {\n        return Enumerable.ToList(Enumerable.Where(values, v => v % 2 == 0))\n    }\n}\n") == ""

    census := IuCensusOf("nsharp-import-extension-control", "namespace Probe\n\nimport System.Collections.Generic\nimport System.Linq\n\nclass Widget {\n    func All(values: List<int>): List<int> {\n        return values\n    }\n}\n")
    assert census == "NL010@Program.nl:4:8+11;", census
}

test "a STATIC RECEIVER keeps its import alive, with no annotation anywhere in the file" {
    assert IuCensusOf("nsharp-import-static-receiver", "namespace Probe\n\nimport System\n\nclass Widget {\n    func Root(value: double): double {\n        return Math.Sqrt(value)\n    }\n}\n") == ""
}

test "an ATTRIBUTE keeps its import alive, and it is a type position no type reference reaches" {
    // `[NotNullWhen(true)]` is the only mention of `System.Diagnostics.CodeAnalysis` in the file.
    assert IuCensusOf("nsharp-import-attribute", "namespace Probe\n\nimport System.Diagnostics.CodeAnalysis\n\nclass Widget {\n    func TryName([NotNullWhen(true)] out name: string?): bool {\n        name = \"widget\"\n        return true\n    }\n}\n") == ""

    census := IuCensusOf("nsharp-import-attribute-control", "namespace Probe\n\nimport System.Diagnostics.CodeAnalysis\n\nclass Widget {\n    func TryName(out name: string?): bool {\n        name = \"widget\"\n        return true\n    }\n}\n")
    assert census == "NL010@Program.nl:3:8+35;", census
}

test "a DECLARED MEMBER TYPE keeps its import alive, resolved by the declaration context alone" {
    assert IuCensusOf("nsharp-import-field-type", "namespace Probe\n\nimport System.Text\n\nclass Widget {\n    builder: StringBuilder?\n}\n") == ""
}

test "a TYPE ARGUMENT keeps its import alive, which the base name alone would have missed" {
    assert IuCensusOf("nsharp-import-type-argument", "namespace Probe\n\nimport System.Collections.Generic\nimport System.Text\n\nclass Widget {\n    func Make(): List<StringBuilder> {\n        return new List<StringBuilder>()\n    }\n}\n") == ""
}

test "an ALIASED import is used by the namespace's OWN bare name, not only by the alias" {
    // An N# aliased import does both things at once: it binds `Txt` AND brings `StringBuilder` into
    // scope unqualified. Asking only the alias question reported an import the build needs as dead.
    assert IuCensusOf("nsharp-import-alias-bare", "namespace Probe\n\nimport System.Text as Txt\n\nclass Widget {\n    func Make(): StringBuilder {\n        return new StringBuilder()\n    }\n}\n") == ""

    // The alias-qualified spelling is the same import and the same answer.
    assert IuCensusOf("nsharp-import-alias-qualified", "namespace Probe\n\nimport System.Text as Txt\n\nclass Widget {\n    func Make(): Txt.StringBuilder {\n        return new Txt.StringBuilder()\n    }\n}\n") == ""

    census := IuCensusOf("nsharp-import-alias-control", "namespace Probe\n\nimport System.Text as Txt\n\nclass Widget {\n    Name: string => \"w\"\n}\n")
    assert census == "NL010@Program.nl:3:8+11;", census
}

test "a name a namespace DECLARED BUT DID NOT EXPORT is still a use of the import that offered it" {
    // Two diagnostics for one mistake is one too many: the file asked `X` for a name, `X` had it and
    // refused it, and telling the author their import is also dead is wrong.
    directory := IuNewProject("nsharp-import-inaccessible")
    try {
        IuWrite(directory, "Parts.nl", "namespace Probe.Parts\n\nfunc formatTag(value: string): string {\n    return \"<\" + value + \">\"\n}\n")
        IuWrite(directory, "Program.nl", "namespace Probe\n\nimport Probe.Parts\n\nfunc UseIt(value: string): string {\n    return formatTag(value)\n}\n")
        assert IuCheckCensus(directory) == "NL308@Program.nl:6:12+10;"
    } finally {
        IuDelete(directory)
    }
}

// ─── NL002: THE OTHER READING OF THE SAME FACT ────────────────────────────────────────────────

test "NL002 fires for any name whose supplying namespace is not imported" {
    // The old table carried 25 names. None of these three was one of them.
    census := IuCensusOf("nsharp-missing-import-unlisted", "namespace Probe\n\nclass Widget {\n    func Check(): bool {\n        return OperatingSystem.IsWindows()\n    }\n\n    func Root(value: double): double {\n        return Math.Sqrt(value)\n    }\n}\n")
    assert census == "NL002@Program.nl:5:16+15;NL002@Program.nl:9:16+4;", census
}

test "the import silences it, and the two rules never disagree about the same name" {
    // With the import present NL002 is silent AND NL010 is silent: one measurement, two readings.
    assert IuCensusOf("nsharp-missing-import-silenced", "namespace Probe\n\nimport System\n\nclass Widget {\n    func Root(value: double): double {\n        return Math.Sqrt(value)\n    }\n}\n") == ""
}

test "a SOURCE type from another namespace of the same project needs no import, so NL002 stays quiet" {
    // Project-wide discovery resolves it with no import at all — that is the language's rule — so
    // demanding one would make working programs unbuildable.
    directory := IuNewProject("nsharp-missing-import-source-type")
    try {
        IuWrite(directory, "Parts.nl", "namespace Probe.Parts\n\nclass Gadget {\n    Name: string => \"g\"\n}\n")
        IuWrite(directory, "Program.nl", "namespace Probe\n\nclass Widget {\n    func Make(): Gadget {\n        return new Gadget()\n    }\n}\n")
        assert IuCheckCensus(directory) == ""
    } finally {
        IuDelete(directory)
    }
}

test "a name the PROJECT ITSELF declares is never a missing import, whatever a reference calls its types" {
    // A receiver position resolves through the external probe before it consults a SIBLING FILE's
    // declarations, so a source `class Guard` beside a metadata `Guard` answered with the metadata
    // one — and NL002 would have told the author to import a namespace their program does not use.
    directory := IuNewProject("nsharp-missing-import-own-name")
    try {
        IuWrite(directory, "Parts.nl", "namespace Probe\n\nclass Math {\n    static func Twice(value: int): int {\n        return value * 2\n    }\n}\n")
        IuWrite(directory, "Program.nl", "namespace Probe\n\nclass Widget {\n    func Use(value: int): int {\n        return Math.Twice(value)\n    }\n}\n")
        assert IuCheckCensus(directory) == ""
    } finally {
        IuDelete(directory)
    }
}
