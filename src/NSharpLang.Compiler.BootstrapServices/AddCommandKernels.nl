namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler
import System
import System.Collections.Generic

public class AddArgumentSummary {
    VersionOption: string?
    PathOption: string?
    PackageOperand: string?
    Framework: bool
    Prerelease: bool
    ShowHelp: bool

    constructor(versionOption: string?, pathOption: string?, packageOperand: string?, framework: bool, prerelease: bool, showHelp: bool) {
        VersionOption = versionOption
        PathOption = pathOption
        PackageOperand = packageOperand
        Framework = framework
        Prerelease = prerelease
        ShowHelp = showHelp
    }
}

public class AddPackageSpec {
    PackageName: string
    Version: string?

    constructor(packageName: string, version: string?) {
        PackageName = packageName
        Version = version
    }
}

public class AddCommandKernels {
    public static func GetArgumentSummary(args: string[]): AddArgumentSummary {
        versionOption: string? = null
        pathOption: string? = null
        packageOperand: string? = null
        framework := false
        prerelease := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            kind := ArgumentSummaryKind(arg)
            if kind == 1 {
                if versionOption == null && i + 1 < args.Length {
                    versionOption = args[i + 1]
                }
            } else if kind == 2 {
                if pathOption == null && i + 1 < args.Length {
                    pathOption = args[i + 1]
                }
            } else if kind == 3 {
                framework = true
            } else if kind == 4 {
                prerelease = true
            } else if kind == 5 {
                showHelp = true
            }

            i = i + 1
        }

        i = 0
        while i < args.Length {
            arg := args[i]
            kind := ArgumentSummaryKind(arg)
            if kind == 1 || kind == 2 {
                if i + 1 < args.Length {
                    i = i + 2
                } else {
                    i = i + 1
                }

                continue
            }

            if arg.Length == 0 || arg[0] != '-' {
                packageOperand = arg
                break
            }

            i = i + 1
        }

        return new AddArgumentSummary(versionOption, pathOption, packageOperand, framework, prerelease, showHelp)
    }

    public static func GetPackageSpec(raw: string, explicitVersion: string?): AddPackageSpec {
        separator := InlineVersionSeparatorIndex(raw)
        if separator > 0 {
            return new AddPackageSpec(raw.Substring(0, separator), raw.Substring(separator + 1, raw.Length - separator - 1))
        }

        return new AddPackageSpec(raw, explicitVersion)
    }

    public static func PackageOrFrameworkDependencyExists(
        dependencies: IReadOnlyList<Reference>,
        packageName: string): bool {
        index := 0
        while index < dependencies.Count {
            dependency := dependencies[index]
            nuget := dependency.Nuget
            if nuget != null && StringEqualsAsciiIgnoreCase(nuget, packageName) {
                return true
            }

            framework := dependency.Framework
            if framework != null && StringEqualsAsciiIgnoreCase(framework, packageName) {
                return true
            }

            index = index + 1
        }

        return false
    }

    public static func ProjectDependencyExists(
        dependencies: IReadOnlyList<Reference>,
        localPath: string): bool {
        index := 0
        while index < dependencies.Count {
            project := dependencies[index].Project
            if project != null && StringEqualsAsciiIgnoreCase(project, localPath) {
                return true
            }

            index = index + 1
        }

        return false
    }

    public static func GetDependencyInsertIndex(lines: string[]): int {
        depIndex := -1
        index := 0
        while index < lines.Length {
            if IsDependencySectionLine(lines[index]) {
                depIndex = index
                break
            }

            index = index + 1
        }

        if depIndex < 0 {
            return -1
        }

        insertAt := depIndex + 1
        while insertAt < lines.Length {
            if DependencyBlockStopsAtLine(lines[insertAt]) {
                return insertAt
            }

            insertAt = insertAt + 1
        }

        return insertAt
    }

    public static func GetHelpText(): string {
        return "N# Add Dependency\n"
            + "\n"
            + "Usage: nlc add <package> [options]\n"
            + "       nlc add <package>@<version>\n"
            + "       nlc add --path <local-project>\n"
            + "\n"
            + "Add a NuGet package, framework reference, or local project reference to project.yml.\n"
            + "If no version is specified, the latest version is resolved from NuGet.\n"
            + "\n"
            + "Options:\n"
            + "  --version <ver>   Package version (alternative to @version syntax)\n"
            + "  --prerelease      Allow prerelease versions when resolving latest\n"
            + "  --framework       Add as a framework reference instead of NuGet package\n"
            + "  --path <path>     Add a local project reference (project.yml or directory)\n"
            + "  --help, -h        Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc add Newtonsoft.Json\n"
            + "  nlc add Serilog@3.1.0\n"
            + "  nlc add Serilog --version 3.1.0\n"
            + "  nlc add System.Text.Json --prerelease\n"
            + "  nlc add Microsoft.AspNetCore.App --framework\n"
            + "  nlc add --path ../MyLibrary\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Dependency added successfully\n"
            + "  1  Failed to add dependency"
    }

    public static func GetUsageMessage(): string {
        return "Usage: nlc add <package> [--version <ver>]\n       nlc add <package>@<version>"
    }

    public static func GetMissingProjectFileMessage(): string {
        return "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project."
    }

    public static func GetResolvingLatestVersionMessage(packageName: string): string {
        return "Resolving latest version for " + packageName + "..."
    }

    public static func GetPackageNotFoundMessage(packageName: string): string {
        return "Could not find package '" + packageName + "' on NuGet. Check the package name and try again."
    }

    public static func GetDuplicatePackageMessage(packageName: string): string {
        return "'" + packageName + "' is already in dependencies. Use 'nlc update' to change the version."
    }

    public static func GetDuplicateProjectReferenceMessage(localPath: string): string {
        return "Project reference '" + localPath + "' is already in dependencies."
    }

    public static func GetFrameworkAddedMessage(packageName: string): string {
        return "Added framework reference '" + packageName + "' to project.yml"
    }

    public static func GetPackageAddedMessage(packageName: string, version: string): string {
        return "Added " + packageName + "@" + version + " to project.yml"
    }

    public static func GetProjectReferenceAddedMessage(localPath: string): string {
        return "Added project reference '" + localPath + "' to project.yml"
    }

    static func ArgumentSummaryKind(arg: string): int {
        if arg == "--version" {
            return 1
        }

        if arg == "--path" {
            return 2
        }

        if arg == "--framework" {
            return 3
        }

        if arg == "--prerelease" {
            return 4
        }

        if arg == "--help" || arg == "-h" {
            return 5
        }

        return 0
    }

    static func InlineVersionSeparatorIndex(raw: string): int {
        index := 0
        while index < raw.Length {
            if raw[index] == '@' {
                if index > 0 {
                    return index
                }

                return -1
            }

            index = index + 1
        }

        return -1
    }

    static func IsDependencySectionLine(line: string): bool {
        start := TrimStartIndex(line)
        return SubstringStartsWith(line, start, line.Length, "dependencies:")
    }

    static func DependencyBlockStopsAtLine(line: string): bool {
        if line.Length == 0 {
            return true
        }

        return line[0] != ' ' && line[0] != '\t'
    }

    static func TrimStartIndex(text: string): int {
        index := 0
        while index < text.Length && char.IsWhiteSpace(text[index]) {
            index = index + 1
        }

        return index
    }

    static func SubstringStartsWith(text: string, start: int, end: int, prefix: string): bool {
        if end - start < prefix.Length {
            return false
        }

        index := 0
        while index < prefix.Length {
            if text[start + index] != prefix[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func StringEqualsAsciiIgnoreCase(left: string, right: string): bool {
        if left.Length != right.Length {
            return false
        }

        index := 0
        while index < left.Length {
            if !CharsEqualAsciiIgnoreCase(left[index], right[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func CharsEqualAsciiIgnoreCase(left: char, right: char): bool {
        leftCode := (int)left
        rightCode := (int)right

        if left >= 'A' && left <= 'Z' {
            leftCode = leftCode + 32
        }

        if right >= 'A' && right <= 'Z' {
            rightCode = rightCode + 32
        }

        return leftCode == rightCode
    }
}
