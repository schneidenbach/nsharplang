namespace NSharpLang.LanguageServerDiagnostics.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text.Json
import Microsoft.Extensions.Logging.Abstractions
import NSharpLang.Compiler
import NSharpLang.LanguageServer.Services

class LspReferenceParityProcessResult {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

func LspReferenceParityRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "examples")) {
            return directory
        }

        current = Path.GetDirectoryName(directory)
    }

    throw new InvalidOperationException("Could not locate the repository root above the Language Server diagnostics tests.")
}

func LspReferenceParityRunCliCheck(projectRoot: string): LspReferenceParityProcessResult {
    repositoryRoot := LspReferenceParityRepositoryRoot()
    cliDll := Path.Combine(
        Path.Combine(Path.Combine(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Cli"), "bin"), "Debug"),
        "net10.0/Cli.dll"
    )
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found: " + cliDll)
    }

    startInfo := new ProcessStartInfo { FileName: "dotnet" }
    startInfo.WorkingDirectory = projectRoot
    startInfo.ArgumentList.Add(cliDll)
    startInfo.ArgumentList.Add("check")
    startInfo.ArgumentList.Add("--json")
    startInfo.ArgumentList.Add("--project")
    startInfo.ArgumentList.Add(projectRoot)
    startInfo.EnvironmentVariables["NLC_NO_DAEMON"] = "1"
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(300000) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("nlc check did not finish for " + projectRoot)
    }

    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    result := new LspReferenceParityProcessResult(process.ExitCode, stdout, stderr)
    process.Dispose()
    return result
}

func LspReferenceParityRelativeFile(projectRoot: string, path: string?): string {
    if path == null || path.Length == 0 {
        return "unknown"
    }

    fullPath := path
    if !Path.IsPathRooted(fullPath) {
        fullPath = Path.Combine(projectRoot, fullPath)
    }

    return Path.GetRelativePath(projectRoot, Path.GetFullPath(fullPath)).Replace("\\", "/")
}

func LspReferenceParityKey(
    code: string,
    severity: string,
    file: string,
    line: int,
    column: int,
    length: int,
    message: string
): string {
    return code + "|" + severity + "|" + file + "|" + line.ToString() + "|" + column.ToString() + "|" + length.ToString() + "|" + message
}

func LspReferenceParityCliCensus(projectRoot: string, output: string): List<string> {
    document := JsonDocument.Parse(output)
    try {
        results := document.RootElement.GetProperty("results")
        census := new List<string>()
        enumerator := results.EnumerateArray()
        while enumerator.MoveNext() {
            row := enumerator.Current
            file := row.GetProperty("file").GetString() ?? "unknown"
            // `nlc check` includes tests; editor project snapshots intentionally cover product files.
            if file.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase) {
                continue
            }

            census.Add(LspReferenceParityKey(
                row.GetProperty("code").GetString() ?? "",
                row.GetProperty("severity").GetString() ?? "",
                LspReferenceParityRelativeFile(projectRoot, file),
                row.GetProperty("line").GetInt32(),
                row.GetProperty("column").GetInt32(),
                row.GetProperty("length").GetInt32(),
                row.GetProperty("message").GetString() ?? ""
            ))
        }

        census.Sort(StringComparer.Ordinal)
        return census
    } finally {
        document.Dispose()
    }
}

func LspReferenceParityCompilerSeverity(severity: ErrorSeverity): string {
    if severity == ErrorSeverity.Warning {
        return "warning"
    }

    return "error"
}

func LspReferenceParityLinterSeverity(severity: DiagnosticSeverity): string {
    if severity == DiagnosticSeverity.Error {
        return "error"
    }
    if severity == DiagnosticSeverity.Info {
        return "info"
    }

    return "warning"
}

func LspReferenceParityLspCensus(projectRoot: string, config: ProjectConfig): List<string> {
    sourceFiles := config.GetSourceFiles(projectRoot, false)
    if sourceFiles.Length == 0 {
        throw new InvalidOperationException("Example project has no product source files: " + projectRoot)
    }

    manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
    openUris := new List<string>()
    for sourceFile in sourceFiles {
        uri := LsdFileUri(sourceFile)
        openUris.Add(uri)
        manager.MarkEditorOpen(uri)
        manager.UpdateDocument(uri, File.ReadAllText(sourceFile), 1)
    }

    publications := manager.GetDiagnosticsToPublish(openUris[0])
    census := new List<string>()
    for publication in publications {
        for error in publication.CompilerDiagnostics {
            census.Add(LspReferenceParityKey(
                error.DiagnosticId,
                LspReferenceParityCompilerSeverity(error.Severity),
                LspReferenceParityRelativeFile(projectRoot, error.FileName),
                error.Line,
                error.Column,
                error.Length,
                error.Message
            ))
        }

        publicationFile := LspReferenceParityRelativeFile(projectRoot, new Uri(publication.Uri).LocalPath)
        for diagnostic in publication.LinterDiagnostics {
            census.Add(LspReferenceParityKey(
                diagnostic.Code,
                LspReferenceParityLinterSeverity(diagnostic.Severity),
                publicationFile,
                diagnostic.Location.Line,
                diagnostic.Location.Column,
                diagnostic.Length,
                diagnostic.Message
            ))
        }
    }

    census.Sort(StringComparer.Ordinal)
    return census
}

func LspReferenceParityText(items: IReadOnlyList<string>): string {
    return string.Join("\n", items)
}

test "issue tracker ASP.NET Core extension diagnostics match nlc check" {
    projectRoot := Path.Combine(LspReferenceParityRepositoryRoot(), "examples/17-issue-tracker/backend")
    config := ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"))
    cli := LspReferenceParityRunCliCheck(projectRoot)
    assert cli.ExitCode == 0, "nlc check failed for the issue tracker: " + cli.Stdout + cli.Stderr

    cliCensus := LspReferenceParityCliCensus(projectRoot, cli.Stdout)
    lspCensus := LspReferenceParityLspCensus(projectRoot, config)
    assert cliCensus.Count == 0, "Issue tracker CLI diagnostics: " + LspReferenceParityText(cliCensus)
    assert LspReferenceParityText(lspCensus) == LspReferenceParityText(cliCensus), "Issue tracker Language Server diagnostics diverged from nlc check." + "\nLSP:\n" + LspReferenceParityText(lspCensus) + "\nCLI:\n" + LspReferenceParityText(cliCensus)
}

test "Language Server diagnostics match nlc check for every example project" {
    examplesRoot := Path.Combine(LspReferenceParityRepositoryRoot(), "examples")
    projectFiles := Directory.GetFiles(examplesRoot, "project.yml", SearchOption.AllDirectories)
    Array.Sort(projectFiles, StringComparer.Ordinal)
    assert projectFiles.Length > 0

    issueTrackerRoot := Path.Combine(examplesRoot, "17-issue-tracker/backend")
    issueTrackerSeen := false
    for projectFile in projectFiles {
        projectRoot := Path.GetDirectoryName(projectFile) ?? ""
        config := ProjectFileParser.Parse(projectFile)
        cli := LspReferenceParityRunCliCheck(projectRoot)
        assert cli.ExitCode == 0 || cli.ExitCode == 1, "nlc check failed to produce a check result for " + projectRoot + ": " + cli.Stderr

        cliCensus := LspReferenceParityCliCensus(projectRoot, cli.Stdout)
        lspCensus := LspReferenceParityLspCensus(projectRoot, config)
        assert LspReferenceParityText(lspCensus) == LspReferenceParityText(cliCensus), "Language Server diagnostics diverged from nlc check for " + projectRoot + "\nLSP:\n" + LspReferenceParityText(lspCensus) + "\nCLI:\n" + LspReferenceParityText(cliCensus) + "\nCLI stderr:\n" + cli.Stderr

        if string.Equals(projectRoot, issueTrackerRoot, StringComparison.Ordinal) {
            issueTrackerSeen = true
            assert cliCensus.Count == 0, "Issue tracker CLI diagnostics: " + LspReferenceParityText(cliCensus)
        }
    }

    assert issueTrackerSeen, "The examples corpus did not include examples/17-issue-tracker/backend/project.yml"
}
