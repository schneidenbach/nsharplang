namespace NSharpLang.CliCommandContracts.Tests

import System
import System.IO


// Run the installed boundary in a separate process so both streams and the real process status
// are observed. The fixture references the built product assemblies; no fault-injection switch
// or synthetic exception lives in production code.
func InternalBoundaryProbe(source: string): CliRun {
    directory := NewTempDirectory("nlc-internal-boundary")
    result := new CliRun(99, "", "")
    try {
        cliDirectory := Path.GetDirectoryName(CliDll()) ?? ""
        project := "name: InternalBoundaryProbe\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - dll: " + CliDll() + "\n  - dll: " + Path.Combine(cliDirectory, "NSharpLang.Compiler.BootstrapServices.dll") + "\n  - dll: " + Path.Combine(cliDirectory, "Compiler.dll") + "\n"
        File.WriteAllText(Path.Combine(directory, "project.yml"), project)
        File.WriteAllText(Path.Combine(directory, "Program.nl"), source)
        build := Nlc("build --project \"" + directory + "\"")
        assert build.ExitCode == 0, build.Stdout + build.Stderr
        assembly := Path.Combine(directory, "bin/Debug/net10.0/InternalBoundaryProbe.dll")
        result = RunProcess("dotnet", "\"" + assembly + "\"", directory)
    } finally {
        Directory.Delete(directory, true)
    }

    return result
}

func InternalDocumentedOutput(): string {
    page := File.ReadAllText(Path.Combine(CliRepositoryRoot(), "website/docs/errors/NL924.md")).Replace("\r\n", "\n")
    fence := "```text title=\"NL924 boundary output\"\n"
    start := page.IndexOf(fence, StringComparison.Ordinal)
    assert start >= 0, "NL924 must retain its contracted output example."
    remaining := page.Substring(start + fence.Length)
    end := remaining.IndexOf("```", StringComparison.Ordinal)
    assert end >= 0, "NL924's output example must close its fence."
    return remaining.Substring(0, end)
}

test "NL924 process boundary renders synthetic invariant failure exactly as its documentation" {
    source := "import System\nimport NSharpLang.Cli\nfunc main(): int {\n    action: Func<int> = () => FailInvariant()\n    return InternalErrorBoundary.Execute(action)\n}\nfunc FailInvariant(): int {\n    throw new InvalidOperationException(\"AnalyzerScopeStack requires a non-empty scope stack before Peek.\")\n}\n"
    run := InternalBoundaryProbe(source)
    expected := "error NL924: Internal compiler error.\nThis is a bug in N#, not in your code.\nAnalyzerScopeStack requires a non-empty scope stack before Peek.\nException: System.InvalidOperationException\nReport this failure: https://schneidenbach.github.io/nsharplang/docs/errors/NL924" + Environment.NewLine
    assert run.ExitCode == 2
    assert run.Stdout == "", run.Stdout
    assert run.Stderr == expected, run.Stderr
    assert InternalDocumentedOutput() == expected.Replace("\r\n", "\n")
}

test "the real CLI Main routes an escaping exception through NL924" {
    // Reflection supplies null arguments that the operating system cannot supply. This exercises
    // the real private entry point without a production fault switch. Before the seam existed,
    // reflection rethrew TargetInvocationException and the child aborted with a stack trace.
    source := "import System\nimport System.Reflection\nfunc main(): int {\n    owner := Type.GetType(\"NSharpLang.Cli.Program, Cli\")\n    if owner == null { return 98 }\n    entry := owner.GetMethod(\"Main\", BindingFlags.NonPublic | BindingFlags.Static)\n    if entry == null { return 99 }\n    arguments := new object?[](1)\n    returned := entry.Invoke(null, arguments)\n    return Convert.ToInt32(returned)\n}\n"
    run := InternalBoundaryProbe(source)
    expected := "error NL924: Internal compiler error.\nThis is a bug in N#, not in your code.\nObject reference not set to an instance of an object.\nException: System.NullReferenceException\nReport this failure: https://schneidenbach.github.io/nsharplang/docs/errors/NL924" + Environment.NewLine
    assert run.ExitCode == 2
    assert run.Stdout == "", run.Stdout
    assert run.Stderr == expected, run.Stderr
}

test "NL924 leaves existing stdout bytes intact and emits no invented JSON envelope" {
    source := "import System\nimport NSharpLang.Cli\nfunc main(): int {\n    action: Func<int> = () => WriteThenFail()\n    return InternalErrorBoundary.Execute(action)\n}\nfunc WriteThenFail(): int {\n    Console.WriteLine(\"{\\\"schemaVersion\\\":1}\")\n    throw new InvalidOperationException(\"SyntheticCommand requires its output operation to complete.\")\n}\n"
    run := InternalBoundaryProbe(source)
    assert run.ExitCode == 2
    assert run.Stdout == "{\"schemaVersion\":1}" + Environment.NewLine, run.Stdout
    assert run.Stderr == "error NL924: Internal compiler error.\nThis is a bug in N#, not in your code.\nSyntheticCommand requires its output operation to complete.\nException: System.InvalidOperationException\nReport this failure: https://schneidenbach.github.io/nsharplang/docs/errors/NL924" + Environment.NewLine, run.Stderr
}

test "the process boundary preserves ordinary return codes and keeps stderr empty" {
    source := "import NSharpLang.Cli\nfunc main(): int {\n    action: Func<int> = () => 17\n    return InternalErrorBoundary.Execute(action)\n}\n"
    run := InternalBoundaryProbe(source)
    assert run.ExitCode == 17
    assert run.Stdout == "", run.Stdout
    assert run.Stderr == "", run.Stderr
}

test "nlc run preserves a user program's exit 2 without reporting NL924" {
    directory := NewTempDirectory("nlc-child-exit-two")
    try {
        File.WriteAllText(Path.Combine(directory, "project.yml"), "name: ChildExitTwo\noutputType: exe\ntargetFramework: net10.0\n")
        sourcePath := Path.Combine(directory, "Program.nl")
        File.WriteAllText(sourcePath, "func main(): int {\n    return 2\n}\n")
        run := Nlc("run \"" + sourcePath + "\"")
        assert run.ExitCode == 2
        assert run.Stderr == "", run.Stderr
        assert !run.Stdout.Contains("NL924"), run.Stdout
    } finally {
        Directory.Delete(directory, true)
    }
}
