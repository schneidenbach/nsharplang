namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.Text
import System.Text.Json

public class PackOptionSummary {
    projectOptionValue: string?
    outputDirValue: string?
    versionOverrideValue: string?
    configurationValue: string
    includeSymbolsValue: bool
    jsonOutputValue: bool
    showHelpValue: bool

    ProjectOption: string? => projectOptionValue
    OutputDir: string? => outputDirValue
    VersionOverride: string? => versionOverrideValue
    Configuration: string => configurationValue
    IncludeSymbols: bool => includeSymbolsValue
    JsonOutput: bool => jsonOutputValue
    ShowHelp: bool => showHelpValue

    constructor(
        projectOption: string?,
        outputDir: string?,
        versionOverride: string?,
        configuration: string,
        includeSymbols: bool,
        jsonOutput: bool,
        showHelp: bool) {
        projectOptionValue = projectOption
        outputDirValue = outputDir
        versionOverrideValue = versionOverride
        configurationValue = configuration
        includeSymbolsValue = includeSymbols
        jsonOutputValue = jsonOutput
        showHelpValue = showHelp
    }
}

public class PackCommandKernels {
    public static func GetOptionSummary(args: string[]): PackOptionSummary {
        projectOption: string? = null
        versionOverride: string? = null
        outputLong: string? = null
        outputShort: string? = null
        configurationLong: string? = null
        configurationShort: string? = null
        includeSymbols := false
        jsonOutput := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            valueIndex := i + 1
            hasValue := valueIndex < args.Length

            if arg == "--project" {
                if projectOption == null && hasValue {
                    projectOption = args[valueIndex]
                }
            } else if arg == "--output" {
                if outputLong == null && hasValue {
                    outputLong = args[valueIndex]
                }
            } else if arg == "-o" {
                if outputShort == null && hasValue {
                    outputShort = args[valueIndex]
                }
            } else if arg == "--version" {
                if versionOverride == null && hasValue {
                    versionOverride = args[valueIndex]
                }
            } else if arg == "--configuration" {
                if configurationLong == null && hasValue {
                    configurationLong = args[valueIndex]
                }
            } else if arg == "-c" {
                if configurationShort == null && hasValue {
                    configurationShort = args[valueIndex]
                }
            } else if arg == "--include-symbols" {
                includeSymbols = true
            } else if arg == "--json" {
                jsonOutput = true
            } else if arg == "--help" {
                showHelp = true
            } else if arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        outputDir := outputShort
        if outputLong != null {
            outputDir = outputLong
        }

        configuration := configurationShort
        if configurationLong != null {
            configuration = configurationLong
        }

        return new PackOptionSummary(
            projectOption,
            outputDir,
            versionOverride,
            configuration ?? "Release",
            includeSymbols,
            jsonOutput,
            showHelp)
    }

    public static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    public static func GetEffectiveVersionSource(versionOverride: string?, projectVersion: string?): int {
        if versionOverride != null {
            if (versionOverride ?? "").Trim().Length == 0 {
                return 0
            }

            return 1
        }

        if (projectVersion ?? "").Trim().Length == 0 {
            return 0
        }

        return 2
    }

    public static func GetHelpText(): string {
        builder := new StringBuilder()
        AppendLine(builder, "N# Pack")
        AppendLine(builder, "")
        AppendLine(builder, "Usage: nlc pack [options]")
        AppendLine(builder, "")
        AppendLine(builder, "Generate a NuGet package from the current N# project.")
        AppendLine(builder, "")
        AppendLine(builder, "Reads package metadata from the 'package' section of project.yml and packs")
        AppendLine(builder, "the native nlc IL build output. The package section is optional but")
        AppendLine(builder, "recommended for library projects intended for distribution.")
        AppendLine(builder, "")
        AppendLine(builder, "project.yml example:")
        AppendLine(builder, "  name: MyLibrary")
        AppendLine(builder, "  version: 1.2.0")
        AppendLine(builder, "  outputType: library")
        AppendLine(builder, "  package:")
        AppendLine(builder, "    author: Your Name")
        AppendLine(builder, "    description: A concise description of your library")
        AppendLine(builder, "    license: MIT")
        AppendLine(builder, "    repository: https://github.com/you/MyLibrary")
        AppendLine(builder, "    tags:")
        AppendLine(builder, "      - dotnet")
        AppendLine(builder, "      - nsharp")
        AppendLine(builder, "")
        AppendLine(builder, "Options:")
        AppendLine(builder, "  --output <dir>          Output directory for the .nupkg file")
        AppendLine(builder, "  --version <ver>         Override the version from project.yml")
        AppendLine(builder, "  --configuration <cfg>   Build configuration (default: Release)")
        AppendLine(builder, "  --include-symbols       Also produce a .snupkg symbols package")
        AppendLine(builder, "  --project <dir>         Project root directory (default: current directory)")
        AppendLine(builder, "  --json                  Output structured JSON (schemaVersion 1 envelope)")
        AppendLine(builder, "  --help, -h              Show this help text")
        AppendLine(builder, "")
        AppendLine(builder, "Examples:")
        AppendLine(builder, "  nlc pack")
        AppendLine(builder, "  nlc pack --output ./artifacts")
        AppendLine(builder, "  nlc pack --version 2.0.0-beta.1")
        AppendLine(builder, "  nlc pack --include-symbols")
        AppendLine(builder, "  nlc pack --json")
        AppendLine(builder, "")
        AppendLine(builder, "Exit codes:")
        AppendLine(builder, "  0  Pack succeeded")
        builder.Append("  1  Pack failed")
        return builder.ToString()
    }

    public static func GetMissingProjectFileJsonMessage(): string {
        return "No project.yml found. Run 'nlc new <name>' to create a project."
    }

    public static func GetMissingProjectFileTextMessage(): string {
        return "No project.yml found in current directory." + ((char)10).ToString()
            + "Run 'nlc new <name>' to create a project."
    }

    public static func GetParseFailedJsonMessage(message: string): string {
        return "Failed to parse project.yml: " + message
    }

    public static func GetParseFailedTextMessage(message: string): string {
        return "Failed to parse project.yml: " + message
    }

    public static func GetStartMessage(name: string, version: string?): string {
        versionText := "(no version)"
        if version != null {
            versionText = version ?? ""
        }

        return "Packing " + name + " " + versionText + "..."
    }

    public static func GetMissingVersionJsonMessage(): string {
        return "Package version is required. Set version in project.yml or pass --version."
    }

    public static func GetMissingVersionTextMessage(): string {
        return "Package version is required. Set version in project.yml or pass --version."
    }

    public static func GetBuildFailedJsonMessage(): string {
        return "Pack build failed."
    }

    public static func GetBuildFailedTextMessage(): string {
        return "Pack build failed."
    }

    public static func GetSuccessMessage(): string {
        return "Pack successful!"
    }

    public static func GetPackagePathLine(packagePath: string): string {
        return "  Package: " + packagePath
    }

    public static func GetFailedJsonMessage(message: string): string {
        return "Pack failed: " + message
    }

    public static func GetFailedTextMessage(message: string): string {
        return "Pack failed: " + message
    }

    public static func SuccessJson(projectRoot: string, projectName: string, version: string, packagePath: string): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "pack"
        envelope["ok"] = true
        envelope["projectRoot"] = projectRoot
        envelope["name"] = projectName
        envelope["version"] = version
        envelope["packagePath"] = packagePath
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    public static func ErrorJson(message: string): string {
        error := new Dictionary<string, object>()
        error["message"] = message

        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "pack"
        envelope["ok"] = false
        envelope["error"] = error
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    public static func GetNuspecText(
        projectName: string,
        version: string,
        packageAuthor: string,
        packageDescription: string,
        packageTags: string,
        packageTagsCount: int,
        packageLicense: string,
        packageRepository: string,
        packageIcon: string): string {
        authors := "NSharp"
        if HasText(packageAuthor) {
            authors = packageAuthor
        }

        description := projectName + " N# package"
        if HasText(packageDescription) {
            description = packageDescription
        }

        builder := new StringBuilder()
        AppendXmlDeclaration(builder)
        AppendPackageOpen(builder)
        AppendLine(builder, "  <metadata>")
        AppendElement(builder, "id", projectName)
        AppendElement(builder, "version", version)
        AppendElement(builder, "authors", authors)
        AppendElement(builder, "description", description)

        if packageTagsCount > 0 {
            AppendElement(builder, "tags", packageTags)
        }

        if HasText(packageLicense) {
            builder.Append("    <license type=")
            AppendQuoted(builder, "expression")
            builder.Append(">")
            builder.Append(XmlEscape(packageLicense))
            AppendLine(builder, "</license>")
        }

        if HasText(packageRepository) {
            builder.Append("    <repository type=")
            AppendQuoted(builder, "git")
            builder.Append(" url=")
            AppendQuoted(builder, XmlEscape(packageRepository))
            AppendLine(builder, " />")
        }

        if HasText(packageIcon) {
            AppendElement(builder, "icon", packageIcon)
        }

        AppendLine(builder, "  </metadata>")
        AppendLine(builder, "</package>")
        return builder.ToString()
    }

    public static func GetSymbolsNuspecText(projectName: string, version: string): string {
        builder := new StringBuilder()
        AppendXmlDeclaration(builder)
        AppendPackageOpen(builder)
        AppendLine(builder, "  <metadata>")
        AppendElement(builder, "id", projectName)
        AppendElement(builder, "version", version)
        AppendElement(builder, "authors", "NSharp")
        AppendElement(builder, "description", "Symbols for " + projectName + ".")
        AppendLine(builder, "  </metadata>")
        AppendLine(builder, "</package>")
        return builder.ToString()
    }

    static func AppendXmlDeclaration(builder: StringBuilder) {
        builder.Append("<?xml version=")
        AppendQuoted(builder, "1.0")
        builder.Append(" encoding=")
        AppendQuoted(builder, "utf-8")
        AppendLine(builder, "?>")
    }

    static func AppendPackageOpen(builder: StringBuilder) {
        builder.Append("<package xmlns=")
        AppendQuoted(builder, "http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd")
        AppendLine(builder, ">")
    }

    static func AppendElement(builder: StringBuilder, name: string, value: string) {
        builder.Append("    <")
        builder.Append(name)
        builder.Append(">")
        builder.Append(XmlEscape(value))
        builder.Append("</")
        builder.Append(name)
        AppendLine(builder, ">")
    }

    static func AppendQuoted(builder: StringBuilder, value: string) {
        builder.Append('"')
        builder.Append(value)
        builder.Append('"')
    }

    static func AppendLine(builder: StringBuilder, text: string) {
        builder.Append(text)
        builder.Append((char)10)
    }

    static func CreateWriteIndentedOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions { WriteIndented: true }
    }

    static func XmlEscape(value: string): string {
        result := ""
        index := 0
        while index < value.Length {
            ch := value[index]
            if ch == '&' {
                result = result + "&amp;"
            } else if ch == '"' {
                result = result + "&quot;"
            } else if ch == '<' {
                result = result + "&lt;"
            } else if ch == '>' {
                result = result + "&gt;"
            } else {
                result = result + value.Substring(index, 1)
            }

            index = index + 1
        }

        return result
    }

    static func HasText(value: string): bool {
        return value.Trim().Length > 0
    }
}
