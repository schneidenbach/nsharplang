namespace NSharpLang.Cli

import System.IO
import System.Text

public class PublishArgumentSummary {
    validationErrorValue: string?
    projectOptionValue: string?
    backendOptionValue: string?
    configurationValue: string
    outputValue: string?
    runtimeValue: string?
    selfContainedValue: bool
    aotValue: bool
    showHelpValue: bool

    ValidationError: string? => validationErrorValue
    ProjectOption: string? => projectOptionValue
    BackendOption: string? => backendOptionValue
    Configuration: string => configurationValue
    Output: string? => outputValue
    Runtime: string? => runtimeValue
    SelfContained: bool => selfContainedValue
    Aot: bool => aotValue
    ShowHelp: bool => showHelpValue

    constructor(
        validationError: string?,
        projectOption: string?,
        backendOption: string?,
        configuration: string,
        output: string?,
        runtime: string?,
        selfContained: bool,
        aot: bool,
        showHelp: bool) {
        validationErrorValue = validationError
        projectOptionValue = projectOption
        backendOptionValue = backendOption
        configurationValue = configuration
        outputValue = output
        runtimeValue = runtime
        selfContainedValue = selfContained
        aotValue = aot
        showHelpValue = showHelp
    }
}

public class PublishCommandKernels {
    public static func GetArgumentSummary(args: string[]): PublishArgumentSummary {
        showHelp := HasHelp(args)
        projectOption: string? = null
        backendOption: string? = null
        configurationLong: string? = null
        configurationShort: string? = null
        outputLong: string? = null
        outputShort: string? = null
        runtimeLong: string? = null
        runtimeShort: string? = null
        selfContained := false
        aot := false
        validationError: string? = null

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                i = i + 1
                continue
            }

            kind := ArgumentKind(arg)
            if kind >= 1 && kind <= 8 {
                valueIndex := i + 1
                if valueIndex >= args.Length {
                    validationError = GetValidationErrorMessage(1, arg)
                    break
                }

                value := args[valueIndex]
                valueLooksLikeOption := false
                if value.Length > 0 {
                    if value[0] == '-' {
                        valueLooksLikeOption = true
                    }
                }

                if valueLooksLikeOption {
                    validationError = GetValidationErrorMessage(1, arg)
                    break
                }

                if kind == 1 {
                    if projectOption == null {
                        projectOption = value
                    }
                } else if kind == 2 {
                    if backendOption == null {
                        backendOption = value
                    }
                } else if kind == 3 {
                    if configurationLong == null {
                        configurationLong = value
                    }
                } else if kind == 4 {
                    if configurationShort == null {
                        configurationShort = value
                    }
                } else if kind == 5 {
                    if outputLong == null {
                        outputLong = value
                    }
                } else if kind == 6 {
                    if outputShort == null {
                        outputShort = value
                    }
                } else if kind == 7 {
                    if runtimeLong == null {
                        runtimeLong = value
                    }
                } else if kind == 8 {
                    if runtimeShort == null {
                        runtimeShort = value
                    }
                }

                i = i + 2
                continue
            }

            if kind == 9 {
                selfContained = true
                i = i + 1
                continue
            }

            if kind == 10 {
                aot = true
                i = i + 1
                continue
            }

            if kind == 11 {
                validationError = GetValidationErrorMessage(2, arg)
                break
            }

            if kind == 12 {
                i = i + 1
                continue
            }

            if arg.Length > 0 {
                if arg[0] == '-' {
                    validationError = GetValidationErrorMessage(3, arg)
                    break
                }
            }

            validationError = GetValidationErrorMessage(4, arg)
            break
        }

        if validationError != null {
            return new PublishArgumentSummary(
                validationError,
                null,
                null,
                "Release",
                null,
                null,
                false,
                false,
                showHelp)
        }

        configuration := configurationShort
        if configurationLong != null {
            configuration = configurationLong
        }

        output := outputShort
        if outputLong != null {
            output = outputLong
        }

        runtime := runtimeShort
        if runtimeLong != null {
            runtime = runtimeLong
        }

        return new PublishArgumentSummary(
            null,
            projectOption,
            backendOption,
            configuration ?? "Release",
            output,
            runtime,
            selfContained,
            aot,
            showHelp)
    }

    public static func GetAotAnalysisOnlyNotice(): string {
        return "nlc publish --aot is analysis-only in this release: it verifies your project is Native AOT-safe "
            + "(failing on any AOT blocker) and stamps [RequiresUnreferencedCode]/[RequiresDynamicCode] on public APIs, "
            + "but it does NOT produce a native image yet. The output is the usual framework-dependent assembly."
    }

    public static func GetHelpText(): string {
        builder := new StringBuilder()
        AppendLine(builder, "N# Publish")
        AppendLine(builder, "")
        AppendLine(builder, "Usage: nlc publish [options]")
        AppendLine(builder, "")
        AppendLine(builder, "Package the project for distribution.")
        AppendLine(builder, "")
        AppendLine(builder, "Options:")
        AppendLine(builder, "  --project <dir>         Project root directory (default: current directory)")
        AppendLine(builder, "  --backend <mode>        Compilation backend: il")
        AppendLine(builder, "  --configuration <cfg>   Build configuration (default: Release)")
        AppendLine(builder, "  --output <dir>          Output directory for published files")
        AppendLine(builder, "  --runtime <rid>         Current host runtime only; adds a framework-dependent launcher")
        AppendLine(builder, "  --self-contained        Planned; currently exits with guidance")
        AppendLine(builder, "  --aot                   Analysis-only: verify Native AOT safety and annotate public APIs")
        AppendLine(builder, "  --help, -h              Show this help text")
        AppendLine(builder, "")
        AppendLine(builder, "Supported publish shapes:")
        AppendLine(builder, "  - Portable framework-dependent: nlc publish --output ./dist")
        AppendLine(builder, "  - Current-runtime launcher: nlc publish --runtime <current-rid>")
        AppendLine(builder, "")
        AppendLine(builder, "Native AOT (--aot):")
        AppendLine(builder, "  Analysis-only this release. Fails the publish on any AOT blocker (reflection,")
        AppendLine(builder, "  dynamic code, runtime generics, expression trees) and stamps public APIs with")
        AppendLine(builder, "  [RequiresUnreferencedCode]/[RequiresDynamicCode]. It does NOT emit a native image yet.")
        AppendLine(builder, "")
        AppendLine(builder, "Unsupported today:")
        AppendLine(builder, "  - Cross-runtime publishing, e.g. publishing linux-x64 from osx-arm64")
        AppendLine(builder, "  - Self-contained apphost/runtime bundles")
        AppendLine(builder, "  - Native AOT image generation")
        AppendLine(builder, "")
        AppendLine(builder, "Examples:")
        AppendLine(builder, "  nlc publish")
        AppendLine(builder, "  nlc publish --backend il --output ./dist")
        AppendLine(builder, "  nlc publish --configuration Release")
        AppendLine(builder, "  nlc publish --runtime <current-rid> --output ./dist")
        AppendLine(builder, "  nlc publish --aot")
        AppendLine(builder, "  nlc publish --output ./dist")
        AppendLine(builder, "")
        AppendLine(builder, "Exit codes:")
        AppendLine(builder, "  0  Publish succeeded")
        builder.Append("  1  Publish failed")
        return builder.ToString()
    }

    public static func GetSelfContainedUnsupportedMessage(): string {
        return "Self-contained publish is not available in nlc publish yet. "
            + "Today nlc publish produces framework-dependent artifacts. "
            + "Omit --self-contained, or use dotnet publish with an MSBuild compatibility project when you need a true apphost/self-contained bundle."
    }

    public static func GetCrossRuntimeUnsupportedMessage(requestedRuntime: string, currentRuntime: string): string {
        return "Cross-runtime publish is not available in nlc publish yet. Requested runtime '"
            + requestedRuntime
            + "', but this machine is '"
            + currentRuntime
            + "'. Today --runtime only supports the current host runtime to add a framework-dependent launcher. "
            + "Omit --runtime for portable 'dotnet <app>.dll' output, or run nlc publish on the target runtime."
    }

    public static func GetBuildFailureMessage(aotMode: bool): string {
        if aotMode {
            return "Publish failed: Native AOT blockers were found (see the diagnostics above). Fix them, then publish again."
        }

        return "Publish failed"
    }

    public static func GetExceptionFailureMessage(exceptionMessage: string): string {
        return "Publish failed: " + exceptionMessage
    }

    public static func GetStartMessage(projectRoot: string): string {
        return "Publishing project in " + projectRoot + "..."
    }

    public static func GetMissingProjectFileMessage(): string {
        return "No project.yml found in current directory. Run 'nlc new <name>' to create a project."
    }

    public static func GetSuccessMessage(): string {
        return "Publish successful!"
    }

    public static func RuntimeMatchesRequestedRuntime(requestedRuntime: string?, currentRuntime: string): bool {
        if string.IsNullOrWhiteSpace(requestedRuntime ?? "") {
            return true
        }

        return string.Equals(requestedRuntime ?? "", currentRuntime, StringComparison.OrdinalIgnoreCase)
    }

    public static func ShouldWriteRuntimeLauncher(requestedRuntime: string?): bool {
        return !string.IsNullOrWhiteSpace(requestedRuntime ?? "")
    }

    public static func GetPublishDirectory(
        projectRoot: string,
        configuration: string,
        targetFramework: string,
        output: string?): string {
        if output != null {
            return Path.GetFullPath(output)
        }

        return Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectRoot, "bin"), configuration), targetFramework), "publish")
    }

    public static func GetWindowsLauncherPath(outputDirectory: string, assemblyName: string): string {
        return Path.Combine(outputDirectory, assemblyName + ".cmd")
    }

    public static func GetUnixLauncherPath(outputDirectory: string, assemblyName: string): string {
        return Path.Combine(outputDirectory, assemblyName)
    }

    public static func GetWindowsLauncherText(assemblyName: string): string {
        return "@echo off\r\ndotnet \"%~dp0" + assemblyName + ".dll\" %*\r\n"
    }

    public static func GetUnixLauncherText(assemblyName: string): string {
        return "#!/usr/bin/env sh\n"
            + "set -eu\n"
            + "DIR=\"$(CDPATH= cd -- \"$(dirname -- \"$0\")\" && pwd)\"\n"
            + "exec dotnet \"$DIR/" + assemblyName + ".dll\" \"$@\"\n"
    }

    static func HasHelp(args: string[]): bool {
        i := 0
        while i < args.Length {
            arg := args[i]
            if arg == "--help" {
                return true
            }

            if arg == "-h" {
                return true
            }

            if i == 0 && arg == "help" {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func ArgumentKind(arg: string): int {
        if arg == "--project" {
            return 1
        }

        if arg == "--backend" {
            return 2
        }

        if arg == "--configuration" {
            return 3
        }

        if arg == "-c" {
            return 4
        }

        if arg == "--output" {
            return 5
        }

        if arg == "-o" {
            return 6
        }

        if arg == "--runtime" {
            return 7
        }

        if arg == "-r" {
            return 8
        }

        if arg == "--self-contained" {
            return 9
        }

        if arg == "--aot" {
            return 10
        }

        if arg == "--target" {
            return 11
        }

        if arg == "--target-platform" {
            return 11
        }

        if arg == "--help" {
            return 12
        }

        if arg == "-h" {
            return 12
        }

        return 0
    }

    static func GetValidationErrorMessage(code: int, arg: string): string {
        if code == 1 {
            return "Option '" + arg + "' requires a value."
        }

        if code == 2 {
            return "Target-platform publishing is expressed as --runtime <rid>, and nlc publish does not support cross-runtime publishing yet."
        }

        if code == 3 {
            return "Unknown publish option '" + arg + "'. Run 'nlc publish --help' for supported options."
        }

        if code == 4 {
            return "Unexpected publish argument '" + arg + "'. Run 'nlc publish --help' for usage."
        }

        return ""
    }

    static func AppendLine(builder: StringBuilder, text: string) {
        builder.Append(text)
        builder.Append((char)10)
    }
}
