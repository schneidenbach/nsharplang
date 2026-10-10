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

        for arg in args {
            if arg == "--help" {
                showHelp = true
            } else if arg == "-h" {
                showHelp = true
            }
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
        return GetGeneratedPropsTextWithPackageMetadata(targetFramework, outputType, projectName, backend, testFramework, baseSdk, null, null, null, null, null, null, null, null, projectReferences)
    }

    static func GetGeneratedPropsTextWithPackageMetadata(targetFramework: string, outputType: string, projectName: string, backend: string, testFramework: string, baseSdk: string, packageId: string?, packageReadme: string?, packageAuthors: string?, packageDescription: string?, packageTags: string?, packageLicenseExpression: string?, packageProjectUrl: string?, repositoryUrl: string?, projectReferences: string[]): string {
        builder := new StringBuilder()
        builder.Append("<Project xmlns=")
        builder.Append('"')
        builder.Append("http://schemas.microsoft.com/developer/msbuild/2003")
        builder.Append('"')
        CommandOutputKernels.AppendLine(builder, ">")
        CommandOutputKernels.AppendLine(builder, "  <PropertyGroup>")
        builder.Append("    <TargetFramework>")
        builder.Append(targetFramework)
        CommandOutputKernels.AppendLine(builder, "</TargetFramework>")
        builder.Append("    <OutputType>")
        builder.Append(outputType)
        CommandOutputKernels.AppendLine(builder, "</OutputType>")
        builder.Append("    <_NSharpOriginalOutputType>")
        builder.Append(outputType)
        CommandOutputKernels.AppendLine(builder, "</_NSharpOriginalOutputType>")
        builder.Append("    <AssemblyName>")
        builder.Append(projectName)
        CommandOutputKernels.AppendLine(builder, "</AssemblyName>")
        if packageId != null && packageId.Trim().Length > 0 {
            builder.Append("    <PackageId>")
            builder.Append(XmlElementEscape(packageId))
            CommandOutputKernels.AppendLine(builder, "</PackageId>")
        }
        if packageReadme != null && packageReadme.Trim().Length > 0 {
            builder.Append("    <PackageReadmeFile>")
            builder.Append(XmlElementEscape(packageReadme))
            CommandOutputKernels.AppendLine(builder, "</PackageReadmeFile>")
        }
        if packageAuthors != null && packageAuthors.Trim().Length > 0 {
            builder.Append("    <Authors>")
            builder.Append(XmlElementEscape(packageAuthors))
            CommandOutputKernels.AppendLine(builder, "</Authors>")
        }
        if packageDescription != null && packageDescription.Trim().Length > 0 {
            builder.Append("    <Description>")
            builder.Append(XmlElementEscape(packageDescription))
            CommandOutputKernels.AppendLine(builder, "</Description>")
        }
        if packageTags != null && packageTags.Trim().Length > 0 {
            builder.Append("    <PackageTags>")
            builder.Append(XmlElementEscape(packageTags))
            CommandOutputKernels.AppendLine(builder, "</PackageTags>")
        }
        if packageLicenseExpression != null && packageLicenseExpression.Trim().Length > 0 {
            builder.Append("    <PackageLicenseExpression>")
            builder.Append(XmlElementEscape(packageLicenseExpression))
            CommandOutputKernels.AppendLine(builder, "</PackageLicenseExpression>")
        }
        if packageProjectUrl != null && packageProjectUrl.Trim().Length > 0 {
            builder.Append("    <PackageProjectUrl>")
            builder.Append(XmlElementEscape(packageProjectUrl))
            CommandOutputKernels.AppendLine(builder, "</PackageProjectUrl>")
        }
        if repositoryUrl != null && repositoryUrl.Trim().Length > 0 {
            builder.Append("    <RepositoryUrl>")
            builder.Append(XmlElementEscape(repositoryUrl))
            CommandOutputKernels.AppendLine(builder, "</RepositoryUrl>")
        }
        builder.Append("    <NSharpCompilationBackend>")
        builder.Append(backend)
        CommandOutputKernels.AppendLine(builder, "</NSharpCompilationBackend>")
        builder.Append("    <NSharpTestFramework>")
        builder.Append(testFramework)
        CommandOutputKernels.AppendLine(builder, "</NSharpTestFramework>")
        builder.Append("    <_NSharpBaseSdk>")
        builder.Append(baseSdk)
        CommandOutputKernels.AppendLine(builder, "</_NSharpBaseSdk>")
        CommandOutputKernels.AppendLine(builder, "  </PropertyGroup>")

        if projectReferences.Length > 0 {
            CommandOutputKernels.AppendLine(builder, "  <ItemGroup>")

            for projectReference in projectReferences {
                builder.Append("    <ProjectReference Include=")
                builder.Append('"')
                builder.Append(CommandOutputKernels.XmlEscape(projectReference))
                builder.Append('"')
                CommandOutputKernels.AppendLine(builder, " />")
            }

            CommandOutputKernels.AppendLine(builder, "  </ItemGroup>")
        }

        CommandOutputKernels.AppendLine(builder, "</Project>")
        return builder.ToString()
    }

    static func XmlElementEscape(value: string): string {
        return CommandOutputKernels.XmlEscape(value)
    }
}
