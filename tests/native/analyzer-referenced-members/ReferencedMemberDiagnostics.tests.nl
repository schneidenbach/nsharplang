namespace NSharpLang.AnalyzerReferencedMembers.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json

class RmdRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

func RmdRepositoryRoot(): string {
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

func RmdRunCli(arguments: string, workingDirectory: string): RmdRun {
    root := RmdRepositoryRoot()
    cliDll := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0")
    cliDll = Path.Combine(cliDll, "Cli.dll")
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found beside the repository root.")
    }

    startInfo := new ProcessStartInfo { FileName: "dotnet", Arguments: "\"" + cliDll + "\" " + arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    startInfo.EnvironmentVariables["NLC_NO_DAEMON"] = "1"
    process := new Process { StartInfo: startInfo }
    process.Start()
    stdout := process.StandardOutput.ReadToEnd()
    stderr := process.StandardError.ReadToEnd()
    process.WaitForExit()
    result := new RmdRun(process.ExitCode, stdout, stderr)
    process.Dispose()
    return result
}

func RmdDiagnosticCount(output: string, code: string): int {
    document := JsonDocument.Parse(output)
    try {
        root := document.RootElement
        count := 0
        results: JsonElement = root
        if root.TryGetProperty("results", out results) {
            count = count + RmdCountInResults(results, code)
        }

        projects: JsonElement = root
        if root.TryGetProperty("projects", out projects) {
            projectEnumerator := projects.EnumerateArray()
            while projectEnumerator.MoveNext() {
                nestedResults: JsonElement = projectEnumerator.Current
                if projectEnumerator.Current.TryGetProperty("results", out nestedResults) {
                    count = count + RmdCountInResults(nestedResults, code)
                }
            }
        }

        return count
    } finally {
        document.Dispose()
    }
}

func RmdCountInResults(results: JsonElement, code: string): int {
    count := 0
    enumerator := results.EnumerateArray()
    while enumerator.MoveNext() {
        diagnosticCode := enumerator.Current.GetProperty("code").GetString() ?? ""
        if diagnosticCode == code {
            count = count + 1
        }
    }

    return count
}

func RmdResultsHaveFieldText(results: JsonElement, fieldName: string, text: string): bool {
    enumerator := results.EnumerateArray()
    while enumerator.MoveNext() {
        field: JsonElement = enumerator.Current
        if enumerator.Current.TryGetProperty(fieldName, out field) {
            value := field.GetString() ?? ""
            if value.Contains(text, StringComparison.Ordinal) {
                return true
            }
        }
    }

    return false
}

func RmdDiagnosticHasFieldText(output: string, fieldName: string, text: string): bool {
    document := JsonDocument.Parse(output)
    try {
        root := document.RootElement
        results: JsonElement = root
        if root.TryGetProperty("results", out results) && RmdResultsHaveFieldText(results, fieldName, text) {
            return true
        }

        projects: JsonElement = root
        if root.TryGetProperty("projects", out projects) {
            projectEnumerator := projects.EnumerateArray()
            while projectEnumerator.MoveNext() {
                nestedResults: JsonElement = projectEnumerator.Current
                if projectEnumerator.Current.TryGetProperty("results", out nestedResults) && RmdResultsHaveFieldText(nestedResults, fieldName, text) {
                    return true
                }
            }
        }

        return false
    } finally {
        document.Dispose()
    }
}

func RmdCheckReferencedMembers(): RmdRun {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-referenced-members-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    try {
        project := "name: ReferencedMembersProbe\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n"
        source := "namespace ReferencedMembers\n\nimport System\nimport System.Collections.Generic\nimport System.Linq\nimport System.Text.Json\nimport YamlDotNet.Serialization\n\nclass Probe {\n    static func Check(builder: DeserializerBuilder, values: IList<int>, options: JsonSerializerOptions, element: JsonElement): int {\n        _missingField := Guid.Emptty\n        _missingProperty := options.DefaultIgnoreConditon\n        builder.Buildd()\n        builder.Build(1)\n        _missingEvent := AppDomain.CurrentDomain.ProcessExitt\n        _missingNestedType := JsonElement.ArrayEnumeartor\n        _missingStatic := DeserializerBuilder.NoSuchStatic\n        _missingInstance := builder.NoSuchInstance\n        _missingGeneric := values.NoSuchGeneric\n        values.Firts()\n\n        subscription := on AppDomain.CurrentDomain.ProcessExit (sender, args) => {\n            Console.Out.Flush()\n        }\n        off subscription\n        _serializer := builder.Build()\n        _policy := options.PropertyNamingPolicy\n        _first := values.First()\n        enumerator := element.EnumerateArray()\n        _current := enumerator.Current\n        return values.Count\n    }\n}\n"
        File.WriteAllText(Path.Combine(directory, "project.yml"), project)
        File.WriteAllText(Path.Combine(directory, "Program.nl"), source)
        return RmdRunCli("check --json --project \"" + directory + "\"", directory)
    } finally {
        Directory.Delete(directory, true)
    }
}

test "referenced .NET and NuGet member misses are NL303 while overloads and valid surfaces keep their own answers" {
    run := RmdCheckReferencedMembers()
    assert run.ExitCode == 1, run.Stdout + run.Stderr
    assert run.Stderr == "", run.Stderr

    // Field, property, method, event, nested type, static/instance, generic receiver, and extension
    // receiver misses all arrive at analysis time. The method typo also gets the member suggester.
    assert RmdDiagnosticCount(run.Stdout, "NL303") == 9, run.Stdout
    assert RmdDiagnosticHasFieldText(run.Stdout, "message", "Buildd' not found"), run.Stdout
    assert RmdDiagnosticHasFieldText(run.Stdout, "suggestion", "Build"), run.Stdout

    // A real member with the wrong argument count stays an overload error. A valid package method,
    // inherited BCL interface member, nested type surface, and LINQ extension still analyze cleanly.
    assert RmdDiagnosticCount(run.Stdout, "NL402") >= 1, run.Stdout
    assert RmdDiagnosticCount(run.Stdout, "NL103") == 0, run.Stdout
}
