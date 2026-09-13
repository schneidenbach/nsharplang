namespace NSharpLang.CensusDuplicateDeclarations.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Reflection
import System.Text.Json


// ONE NAMESPACE, TWO FILES, ONE TYPE NAME — THE SHAPE THAT USED TO COMPILE.
//
// A namespace's declaration scope is per FILE, so `class Widget` written in two files each declared
// into an empty table and neither saw the other. Both were then emitted: the census probe's assembly
// carried TWO `TypeDef` rows called `P2.Widget`, which is the metadata C# refuses as CS0101, and a
// reference to the name bound to whichever the loader reached first. Nothing reported it — `nlc
// check` said "no errors" and `nlc build` said "Build successful".
//
// These rows are the regression, and they are proven through the SHIPPED CLI on real projects on
// disk rather than in memory: the fact that broke was a whole-project fact, so a per-file harness
// could not have caught it. The negative rows matter as much as the positive one — a rule that fires
// on a different arity or a different namespace would make legal programs unbuildable — and the last
// row goes all the way to metadata, so the ACCEPTED shapes are proven to emit the type count they
// claim.
class DupRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

// Both pipes are drained before the wait, so a chatty child cannot deadlock against a full buffer,
// and the process is disposed so this project leaves no orphan `dotnet` behind.
func DupRunProcess(arguments: string, workingDirectory: string): DupRun {
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
    return new DupRun(exitCode, stdout, stderr)
}

func DupRepositoryRoot(): string {
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

func DupCliDll(): string {
    root := DupRepositoryRoot()
    cliDll := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0")
    cliDll = Path.Combine(cliDll, "Cli.dll")
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found beside the repository root.")
    }

    return cliDll
}

func DupNlcIn(workingDirectory: string, arguments: string): DupRun {
    return DupRunProcess("\"" + DupCliDll() + "\" " + arguments, workingDirectory)
}

func DupNewProject(prefix: string): string {
    directory := Path.Combine(Path.GetTempPath(), prefix + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    File.WriteAllText(
        Path.Combine(directory, "project.yml"),
        "name: DuplicateProbe\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    return directory
}

func DupWrite(directory: string, fileName: string, text: string) {
    File.WriteAllText(Path.Combine(directory, fileName), text)
}

// A probe directory that another process still holds open is not a test failure; the temporary
// directory is the operating system's to reclaim.
func DupDelete(directory: string) {
    try {
        Directory.Delete(directory, true)
    // nlc:ignore NL011
    } catch {
    }
}

// Every `results` row of a `nlc check --json` run, as "<code>@<file>:<line>:<column>+<length>".
func DupCheckCensus(directory: string): List<string> {
    run := DupNlcIn(directory, "check --json")
    census := new List<string>()
    document := JsonDocument.Parse(run.Stdout)
    try {
        results := document.RootElement.GetProperty("results")
        enumerator := results.EnumerateArray()
        while enumerator.MoveNext() {
            row := enumerator.Current
            census.Add(
                (row.GetProperty("code").GetString() ?? "") + "@" + (row.GetProperty("file").GetString() ?? "") + ":" + row.GetProperty("line").GetInt32().ToString() + ":" + row.GetProperty("column").GetInt32().ToString() + "+" + row.GetProperty("length").GetInt32().ToString()
            )
        }
    } finally {
        document.Dispose()
    }

    return census
}

func DupSingleMessage(directory: string, code: string): string {
    run := DupNlcIn(directory, "check --json")
    found: string? = null
    matches := 0
    document := JsonDocument.Parse(run.Stdout)
    try {
        enumerator := document.RootElement.GetProperty("results").EnumerateArray()
        while enumerator.MoveNext() {
            row := enumerator.Current
            if (row.GetProperty("code").GetString() ?? "") == code {
                found = row.GetProperty("message").GetString() ?? ""
                matches = matches + 1
            }
        }
    } finally {
        document.Dispose()
    }

    if found == null || matches != 1 {
        throw new InvalidOperationException("Expected one " + code + " row, found " + matches.ToString() + ".")
    }

    return found ?? ""
}

func DupJoin(items: List<string>): string {
    text := ""
    index := 0
    while index < items.Count {
        if index > 0 {
            text = text + ";"
        }

        text = text + items[index]
        index = index + 1
    }

    return text
}

// ─── THE CENSUS SHAPE ─────────────────────────────────────────────────────────────────────────

test "one type name in two files of one namespace is NL339 at the second, naming the first" {
    directory := DupNewProject("nsharp-duplicate-across-files")
    try {
        DupWrite(directory, "First.nl", "namespace Catalog\n\nclass Widget {\n    Name: string => \"first\"\n}\n")
        DupWrite(directory, "Second.nl", "namespace Catalog\n\nclass Widget {\n    Label: string => \"second\"\n}\n")

        census := DupCheckCensus(directory)
        assert DupJoin(census) == "NL339@Second.nl:3:7+6", DupJoin(census)
        assert DupSingleMessage(directory, "NL339") == "A type named 'Widget' is already declared in this namespace, at First.nl:3 — one namespace cannot contain two types with the same name"
    } finally {
        DupDelete(directory)
    }
}

test "the collision blocks the build rather than emitting two types under one name" {
    directory := DupNewProject("nsharp-duplicate-blocks-build")
    try {
        DupWrite(directory, "First.nl", "namespace Catalog\n\nclass Widget {\n    Name: string => \"first\"\n}\n")
        DupWrite(directory, "Second.nl", "namespace Catalog\n\nclass Widget {\n    Label: string => \"second\"\n}\n")

        run := DupNlcIn(directory, "build")

        assert run.ExitCode != 0, run.Stdout + run.Stderr
        assert !File.Exists(Path.Combine(Path.Combine(Path.Combine(Path.Combine(directory, "bin"), "Debug"), "net10.0"), "DuplicateProbe.dll"))
    } finally {
        DupDelete(directory)
    }
}

test "three files that all claim the name report against the FIRST, once each" {
    directory := DupNewProject("nsharp-duplicate-three-files")
    try {
        DupWrite(directory, "A.nl", "namespace Catalog\n\nclass Widget { }\n")
        DupWrite(directory, "B.nl", "namespace Catalog\n\nclass Widget { }\n")
        DupWrite(directory, "C.nl", "namespace Catalog\n\nclass Widget { }\n")

        census := DupCheckCensus(directory)
        assert DupJoin(census) == "NL339@B.nl:3:7+6;NL339@C.nl:3:7+6", DupJoin(census)
    } finally {
        DupDelete(directory)
    }
}

test "every declaration form collides, not just `class`" {
    directory := DupNewProject("nsharp-duplicate-forms")
    try {
        DupWrite(directory, "A.nl", "namespace Catalog\n\nstruct Point { }\n\ninterface Shape { }\n\nenum Mode {\n    On\n}\n")
        DupWrite(directory, "B.nl", "namespace Catalog\n\nstruct Point { }\n\ninterface Shape { }\n\nenum Mode {\n    Off\n}\n")

        census := DupCheckCensus(directory)
        assert DupJoin(census) == "NL339@B.nl:3:8+5;NL339@B.nl:5:11+5;NL339@B.nl:7:6+4", DupJoin(census)
    } finally {
        DupDelete(directory)
    }
}

// ─── THE SHAPES THAT MUST STAY LEGAL ──────────────────────────────────────────────────────────

test "the same name in two DIFFERENT namespaces is two types and reports nothing" {
    directory := DupNewProject("nsharp-duplicate-two-namespaces")
    try {
        DupWrite(directory, "A.nl", "namespace Catalog\n\nclass Widget { }\n")
        DupWrite(directory, "B.nl", "namespace Catalog.Parts\n\nclass Widget { }\n")

        census := DupCheckCensus(directory)
        assert census.Count == 0, DupJoin(census)
    } finally {
        DupDelete(directory)
    }
}

test "a different generic arity is a different type, in one file or across two" {
    directory := DupNewProject("nsharp-duplicate-arity")
    try {
        DupWrite(directory, "A.nl", "namespace Catalog\n\nclass Widget { }\n")
        DupWrite(directory, "B.nl", "namespace Catalog\n\nclass Widget<T> {\n    Value: T?\n}\n")

        census := DupCheckCensus(directory)
        assert census.Count == 0, DupJoin(census)
    } finally {
        DupDelete(directory)
    }
}

test "the SAME arity in two files still collides, and the message writes the arity out" {
    directory := DupNewProject("nsharp-duplicate-same-arity")
    try {
        DupWrite(directory, "A.nl", "namespace Catalog\n\nclass Pair<T1, T2> {\n    First: T1?\n}\n")
        DupWrite(directory, "B.nl", "namespace Catalog\n\nclass Pair<T1, T2> {\n    Second: T2?\n}\n")

        assert DupSingleMessage(directory, "NL339") == "A type named 'Pair<T1, T2>' is already declared in this namespace, at A.nl:3 — one namespace cannot contain two types with the same name"
    } finally {
        DupDelete(directory)
    }
}

test "two declarations in ONE file are still NL306, and NL339 stays out of it" {
    directory := DupNewProject("nsharp-duplicate-one-file")
    try {
        DupWrite(directory, "A.nl", "namespace Catalog\n\nclass Widget { }\n\nclass Widget { }\n")

        census := DupCheckCensus(directory)
        assert DupJoin(census) == "NL306@A.nl:5:7+6", DupJoin(census)
    } finally {
        DupDelete(directory)
    }
}

// ─── WHAT THE ACCEPTED PROGRAM EMITS ──────────────────────────────────────────────────────────

test "a namespace spread over two files with distinct names emits one type each" {
    directory := DupNewProject("nsharp-duplicate-accepted-emit")
    try {
        DupWrite(directory, "A.nl", "namespace Catalog\n\nclass Widget {\n    Name: string => \"widget\"\n}\n")
        DupWrite(directory, "B.nl", "namespace Catalog\n\nclass Gadget {\n    Name: string => \"gadget\"\n}\n")

        run := DupNlcIn(directory, "build")
        assert run.ExitCode == 0, run.Stdout + run.Stderr

        output := Path.Combine(Path.Combine(Path.Combine(Path.Combine(directory, "bin"), "Debug"), "net10.0"), "DuplicateProbe.dll")
        assert File.Exists(output), run.Stdout

        names := new List<string>()
        assembly := Assembly.LoadFrom(output)
        types := assembly.GetTypes()
        index := 0
        while index < types.Length {
            fullName := types[index].FullName ?? ""
            if fullName.StartsWith("Catalog.", StringComparison.Ordinal) {
                names.Add(fullName)
            }

            index = index + 1
        }

        names.Sort()
        // `Catalog.Program` is the synthesised entry-point holder every emitted assembly carries; the
        // two DECLARED types are what this row is about, and each appears exactly once.
        assert DupJoin(names) == "Catalog.Gadget;Catalog.Program;Catalog.Widget", DupJoin(names)
    } finally {
        DupDelete(directory)
    }
}
