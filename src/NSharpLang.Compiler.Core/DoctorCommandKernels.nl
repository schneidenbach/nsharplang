namespace NSharpLang.Cli.Commands

class DoctorOptionSummary {
    Json: bool
    RequireVscode: bool
    SkipVscode: bool
    ShowHelp: bool

    constructor(json: bool, requireVscode: bool, skipVscode: bool, showHelp: bool) {
        Json = json
        RequireVscode = requireVscode
        SkipVscode = skipVscode
        ShowHelp = showHelp
    }
}

class DoctorCommandKernels {
    static func GetOptionSummary(args: string[]): DoctorOptionSummary {
        json := false
        requireVscode := false
        skipVscode := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            if arg == "--json" {
                json = true
            } else if arg == "--require-vscode" {
                requireVscode = true
            } else if arg == "--skip-vscode" {
                skipVscode = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new DoctorOptionSummary(json, requireVscode, skipVscode, showHelp)
    }

    static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    static func GetHelpText(): string {
        return "N# Doctor\n" + "\n" + "Usage: nlc doctor [options]\n" + "\n" + "Verifies the public N# install path: dotnet, nlc, local N# packages, templates,\n" + "language server, and the VS Code extension when the VS Code 'code' CLI is available.\n" + "\n" + "Options:\n" + "  --json              Output as JSON envelope\n" + "  --require-vscode    Treat missing VS Code or missing N# extension as a failure\n" + "  --skip-vscode       Skip VS Code extension probing\n" + "  --help, -h          Show this help text\n" + "\n" + "Examples:\n" + "  nlc doctor\n" + "  nlc doctor --require-vscode\n" + "  nlc doctor --json --skip-vscode\n" + "\n" + "Exit codes:\n" + "  0  Required checks passed\n" + "  1  One or more required checks failed"
    }

    static func GetDotnetNotFoundMessage(): string {
        return "dotnet CLI was not found on PATH"
    }

    static func GetDotnetVersionFailedMessage(): string {
        return "dotnet --version failed"
    }

    static func GetNlcCommandMissingMessage(): string {
        return "nlc is running, but no nlc command was found on PATH; source ~/.nsharp/env or use your package manager shell integration"
    }

    static func GetPackageCacheMissingMessage(packageCache: string): string {
        return "N# package cache was not found at " + packageCache + "; rerun the N# installer"
    }

    static func GetTemplateInstalledMessage(): string {
        return "nsharp-console template is installed"
    }

    static func GetTemplatesMissingMessage(): string {
        return "nsharp-console template was not found; run the N# installer or dotnet new install NSharpLang.Templates"
    }

    static func GetLanguageServerMissingMessage(): string {
        return "nsharp-lsp was not found on PATH; source ~/.nsharp/env or reinstall N#"
    }

    static func GetVscodeSkippedMessage(): string {
        return "skipped by --skip-vscode"
    }

    static func GetVscodeRequiredMissingMessage(): string {
        return "VS Code 'code' CLI was not found on PATH"
    }

    static func GetVscodeOptionalMissingMessage(): string {
        return "VS Code 'code' CLI was not found; install VS Code or rerun with --require-vscode on developer machines"
    }

    static func GetVscodeExtensionMissingMessage(extensionId: string): string {
        return extensionId + " is not installed; run code --install-extension " + extensionId
    }

    static func GetTextHeader(): string {
        return "N# doctor"
    }

    static func GetStatusLine(ok: bool): string {
        if ok {
            return "status: ok"
        }

        return "status: problems found"
    }

    static func GetCheckMarker(status: string): string {
        if status == "pass" {
            return "✓"
        }

        if status == "warn" {
            return "!"
        }

        return "x"
    }

    static func GetCheckLine(marker: string, name: string, detail: string): string {
        return marker + " " + name + ": " + detail
    }
}
