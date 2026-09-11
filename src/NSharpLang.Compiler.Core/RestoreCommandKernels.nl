namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler

class RestoreOptionSummary {
    showHelpValue: bool

    ShowHelp: bool => showHelpValue

    constructor(showHelp: bool) {
        showHelpValue = showHelp
    }
}

class RestoreCommandKernels {
    static func GetOptionSummary(args: string[]): RestoreOptionSummary {
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if arg == "--help" {
                showHelp = true
            } else if arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new RestoreOptionSummary(showHelp)
    }

    static func DeduplicateProjectReferences(projectReferences: IEnumerable<string>): string[] {
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        results := new List<string>()

        for reference in projectReferences {
            if seen.Add(reference) {
                results.Add(reference)
            }
        }

        return results.ToArray()
    }

    static func FilterReferencesByType(references: IEnumerable<Reference>, targetType: ReferenceType): List<Reference> {
        targetTypeId := Convert.ToInt32(targetType)
        if targetTypeId < 0 || targetTypeId > Convert.ToInt32(ReferenceType.Framework) {
            throw new InvalidOperationException("N# restore reference filter kernel received an unsupported reference type.")
        }

        filteredReferences := new List<Reference>()
        for reference in references {
            if reference.Type == targetType {
                filteredReferences.Add(reference)
            }
        }

        return filteredReferences
    }

    static func GetHelpText(): string {
        return "N# Restore\n" + "\n" + "Usage: nlc restore\n" + "\n" + "Generates build configuration (obj/project.g.props) from project.yml.\n" + "This must be run before 'dotnet build' can work directly against a minimal\n" + "NSharpLang.Sdk .csproj. Native 'nlc build' reads project.yml directly.\n" + "\n" + "Options:\n" + "  -h, --help    Show this help message"
    }

    static func GetMissingProjectFileMessage(): string {
        return "No project.yml found. Run 'nlc new <name>' to create a project."
    }

    static func GetGeneratedPropsMessage(): string {
        return "Generated obj/project.g.props from project.yml"
    }

    static func GetFailedMessage(message: string): string {
        return "Failed to restore project configuration: " + message
    }

    static func GetGeneratedPropsText(targetFramework: string, outputType: string, projectName: string, backend: string, testFramework: string, baseSdk: string, projectReferences: string[]): string {
        builder := new StringBuilder()
        builder.Append("<Project xmlns=")
        builder.Append('"')
        builder.Append("http://schemas.microsoft.com/developer/msbuild/2003")
        builder.Append('"')
        AppendLine(builder, ">")
        AppendLine(builder, "  <PropertyGroup>")
        builder.Append("    <TargetFramework>")
        builder.Append(targetFramework)
        AppendLine(builder, "</TargetFramework>")
        builder.Append("    <OutputType>")
        builder.Append(outputType)
        AppendLine(builder, "</OutputType>")
        builder.Append("    <_NSharpOriginalOutputType>")
        builder.Append(outputType)
        AppendLine(builder, "</_NSharpOriginalOutputType>")
        builder.Append("    <AssemblyName>")
        builder.Append(projectName)
        AppendLine(builder, "</AssemblyName>")
        builder.Append("    <NSharpCompilationBackend>")
        builder.Append(backend)
        AppendLine(builder, "</NSharpCompilationBackend>")
        builder.Append("    <NSharpTestFramework>")
        builder.Append(testFramework)
        AppendLine(builder, "</NSharpTestFramework>")
        builder.Append("    <_NSharpBaseSdk>")
        builder.Append(baseSdk)
        AppendLine(builder, "</_NSharpBaseSdk>")
        AppendLine(builder, "  </PropertyGroup>")

        if projectReferences.Length > 0 {
            AppendLine(builder, "  <ItemGroup>")

            i := 0
            while i < projectReferences.Length {
                builder.Append("    <ProjectReference Include=")
                builder.Append('"')
                builder.Append(XmlAttributeEscape(projectReferences[i]))
                builder.Append('"')
                AppendLine(builder, " />")
                i = i + 1
            }

            AppendLine(builder, "  </ItemGroup>")
        }

        AppendLine(builder, "</Project>")
        return builder.ToString()
    }

    static func AppendLine(builder: StringBuilder, text: string) {
        builder.Append(text)
        builder.Append((char)10)
    }

    static func XmlAttributeEscape(value: string): string {
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
}
