namespace NSharpLang.Cli.Commands

import NSharpLang.Cli
import System
import System.Collections.Generic
import System.IO
import System.Text

public class DoctorCheck {
    Name: string
    Status: string
    Detail: string
    IsRequired: bool

    constructor(name: string, status: string, detail: string, isRequired: bool) {
        Name = name
        Status = status
        Detail = detail
        IsRequired = isRequired
    }
}

public class DoctorProcessResult {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

public class DoctorCommand {
    static VscodeExtensionId: string => "nsharp.nsharp"

    public static func Execute(args: string[]): int {
        options := DoctorCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print DoctorCommandKernels.GetHelpText()
            return 0
        }

        outputMode := DoctorCommandKernels.GetOutputMode(options.Json)
        requireVscode := options.RequireVscode
        skipVscode := options.SkipVscode
        checks := new List<DoctorCheck>()

        dotnet := FindOnPath("dotnet")
        if dotnet == null {
            checks.Add(Fail("dotnet", DoctorCommandKernels.GetDotnetNotFoundMessage(), true))
        } else {
            version := RunCapture("dotnet", "--version")
            if version.ExitCode == 0 {
                checks.Add(Pass("dotnet", version.Stdout.Trim()))
            } else {
                checks.Add(Fail(
                    "dotnet",
                    TrimOrDefault(version.Stderr, DoctorCommandKernels.GetDotnetVersionFailedMessage()),
                    true))
            }
        }

        checks.Add(Pass("nlc", "0.1.0"))

        nlc := FindOnPath("nlc")
        if nlc != null {
            checks.Add(Pass("nlc-command", nlc ?? ""))
        } else {
            checks.Add(Warn("nlc-command", DoctorCommandKernels.GetNlcCommandMissingMessage()))
        }

        packageCache := Path.Combine(
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nsharp"),
            "packages")
        if PackageCacheHasSdk(packageCache) {
            checks.Add(Pass("nsharp-packages", packageCache))
        } else {
            checks.Add(Fail(
                "nsharp-packages",
                DoctorCommandKernels.GetPackageCacheMissingMessage(packageCache),
                true))
        }

        templateList := Failed(DoctorCommandKernels.GetDotnetNotFoundMessage())
        if dotnet != null {
            templateList = RunCapture("dotnet", "new list nsharp")
        }

        if templateList.ExitCode == 0
            && templateList.Stdout.IndexOf("nsharp-console", StringComparison.OrdinalIgnoreCase) >= 0 {
            checks.Add(Pass("templates", DoctorCommandKernels.GetTemplateInstalledMessage()))
        } else {
            checks.Add(Fail("templates", DoctorCommandKernels.GetTemplatesMissingMessage(), true))
        }

        lsp := FindOnPath("nsharp-lsp")
        if lsp != null {
            checks.Add(Pass("language-server", lsp ?? ""))
        } else {
            checks.Add(Fail("language-server", DoctorCommandKernels.GetLanguageServerMissingMessage(), true))
        }

        if skipVscode {
            checks.Add(Warn("vscode-extension", DoctorCommandKernels.GetVscodeSkippedMessage()))
        } else {
            code := FindOnPath("code")
            if code == null {
                if requireVscode {
                    checks.Add(Fail(
                        "vscode-extension",
                        DoctorCommandKernels.GetVscodeRequiredMissingMessage(),
                        true))
                } else {
                    checks.Add(Warn(
                        "vscode-extension",
                        DoctorCommandKernels.GetVscodeOptionalMissingMessage()))
                }
            } else {
                extensions := RunCapture("code", "--list-extensions")
                if extensions.ExitCode == 0 && ContainsLine(extensions.Stdout, DoctorCommand.VscodeExtensionId) {
                    checks.Add(Pass("vscode-extension", DoctorCommand.VscodeExtensionId))
                } else {
                    checks.Add(Fail(
                        "vscode-extension",
                        DoctorCommandKernels.GetVscodeExtensionMissingMessage(DoctorCommand.VscodeExtensionId),
                        requireVscode))
                }
            }
        }

        ok := AllRequiredChecksPassed(checks)
        if outputMode == 1 {
            print BuildJson(ok, checks)
        } else {
            PrintText(ok, checks)
        }

        if ok {
            return 0
        }

        return 1
    }

    static func Pass(name: string, detail: string): DoctorCheck {
        return new DoctorCheck(name, "pass", detail, true)
    }

    static func Warn(name: string, detail: string): DoctorCheck {
        return new DoctorCheck(name, "warn", detail, false)
    }

    static func Fail(name: string, detail: string, isRequired: bool): DoctorCheck {
        status := "warn"
        if isRequired {
            status = "fail"
        }

        return new DoctorCheck(name, status, detail, isRequired)
    }

    static func Failed(stderr: string): DoctorProcessResult {
        return new DoctorProcessResult(1, "", stderr)
    }

    static func RunCapture(fileName: string, arguments: string): DoctorProcessResult {
        try {
            result := DotnetRunner.RunProcess(fileName, arguments, null, null)
            return new DoctorProcessResult(result.ExitCode, result.Stdout, result.Stderr)
        } catch ex: Exception {
            return Failed(ex.Message)
        }
    }

    static func FindOnPath(command: string): string? {
        path := Environment.GetEnvironmentVariable("PATH") ?? ""
        separator := ':'
        osMarker := Environment.GetEnvironmentVariable("OS") ?? ""
        if String.Compare(osMarker, "Windows_NT", StringComparison.OrdinalIgnoreCase) == 0 {
            separator = ';'
        }

        start := 0

        while start <= path.Length {
            end := start
            while end < path.Length {
                if path[end] == separator {
                    break
                }

                end = end + 1
            }

            if end > start {
                dir := path.Substring(start, end - start)
                candidate := FindCandidateInDirectory(dir, command)
                if candidate != null {
                    return candidate
                }
            }

            if end >= path.Length {
                break
            }

            start = end + 1
        }

        return null
    }

    static func FindCandidateInDirectory(dir: string, command: string): string? {
        candidate := Path.Combine(dir, command)
        if File.Exists(candidate) {
            return candidate
        }

        candidate = Path.Combine(dir, command + ".exe")
        if File.Exists(candidate) {
            return candidate
        }

        candidate = Path.Combine(dir, command + ".cmd")
        if File.Exists(candidate) {
            return candidate
        }

        candidate = Path.Combine(dir, command + ".bat")
        if File.Exists(candidate) {
            return candidate
        }

        return null
    }

    static func PackageCacheHasSdk(packageCache: string): bool {
        if !Directory.Exists(packageCache) {
            return false
        }

        files := Directory.GetFiles(packageCache, "NSharpLang.Sdk.*.nupkg", SearchOption.TopDirectoryOnly)
        return files.Length > 0
    }

    static func ContainsLine(text: string, expected: string): bool {
        start := 0
        while start <= text.Length {
            end := start
            while end < text.Length {
                if text[end] == '\n' || text[end] == '\r' {
                    break
                }

                end = end + 1
            }

            if end > start {
                line := text.Substring(start, end - start).Trim()
                if String.Compare(line, expected, StringComparison.OrdinalIgnoreCase) == 0 {
                    return true
                }
            }

            if end >= text.Length {
                break
            }

            start = end + 1
        }

        return false
    }

    static func TrimOrDefault(value: string, fallback: string): string {
        trimmed := value.Trim()
        if string.IsNullOrWhiteSpace(trimmed) {
            return fallback
        }

        return trimmed
    }

    static func AllRequiredChecksPassed(checks: List<DoctorCheck>): bool {
        i := 0
        while i < checks.Count {
            if checks[i].Status == "fail" {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func PrintText(ok: bool, checks: List<DoctorCheck>) {
        print DoctorCommandKernels.GetTextHeader()
        print DoctorCommandKernels.GetStatusLine(ok)
        print ""

        i := 0
        while i < checks.Count {
            check := checks[i]
            marker := DoctorCommandKernels.GetCheckMarker(check.Status)
            print DoctorCommandKernels.GetCheckLine(marker, check.Name, check.Detail)
            i = i + 1
        }
    }

    static func BuildJson(ok: bool, checks: List<DoctorCheck>): string {
        builder := new StringBuilder()
        builder.Append("{\"schemaVersion\":1,\"command\":\"doctor\",\"ok\":")
        if ok {
            builder.Append("true")
        } else {
            builder.Append("false")
        }

        builder.Append(",\"checks\":[")
        i := 0
        while i < checks.Count {
            check := checks[i]
            if i > 0 {
                builder.Append(",")
            }

            builder.Append("{\"name\":")
            AppendJsonString(builder, check.Name)
            builder.Append(",\"status\":")
            AppendJsonString(builder, check.Status)
            builder.Append(",\"detail\":")
            AppendJsonString(builder, check.Detail)
            builder.Append(",\"required\":")
            if check.IsRequired {
                builder.Append("true")
            } else {
                builder.Append("false")
            }

            builder.Append("}")
            i = i + 1
        }

        builder.Append("]}")
        return builder.ToString()
    }

    static func AppendJsonString(builder: StringBuilder, value: string) {
        builder.Append('"')
        index := 0
        while index < value.Length {
            ch := value[index]
            if ch == '"' {
                builder.Append("\\\"")
            } else if ch == '\\' {
                builder.Append("\\\\")
            } else if ch == '\n' {
                builder.Append("\\n")
            } else if ch == '\r' {
                builder.Append("\\r")
            } else if ch == '\t' {
                builder.Append("\\t")
            } else {
                builder.Append(value.Substring(index, 1))
            }

            index = index + 1
        }

        builder.Append('"')
    }
}
