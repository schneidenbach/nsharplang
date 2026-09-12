namespace NSharpLang.Compiler

import System.Collections.Generic
import System.IO
import System.Text

// The SDK projection of project.yml. MSBuild tasks only copy these decided outputs.
class SdkProjectConfiguration {
    targetFrameworkValue: string
    outputTypeValue: string
    assemblyNameValue: string
    versionValue: string
    assemblyVersionValue: string
    fileVersionValue: string
    sdkValue: string
    testFrameworkValue: string
    packageIdValue: string
    packageAuthorsValue: string
    packageDescriptionValue: string
    packageTagsValue: string
    packageLicenseExpressionValue: string
    packageProjectUrlValue: string
    repositoryUrlValue: string
    packageReadmeFileValue: string
    packageReadmeSourceValue: string

    TargetFramework: string {
        get {
            return targetFrameworkValue
        }
        set {
            targetFrameworkValue = value
        }
    }

    OutputType: string {
        get {
            return outputTypeValue
        }
        set {
            outputTypeValue = value
        }
    }

    AssemblyName: string {
        get {
            return assemblyNameValue
        }
        set {
            assemblyNameValue = value
        }
    }

    Version: string {
        get {
            return versionValue
        }
        set {
            versionValue = value
        }
    }

    AssemblyVersion: string {
        get {
            return assemblyVersionValue
        }
        set {
            assemblyVersionValue = value
        }
    }

    FileVersion: string {
        get {
            return fileVersionValue
        }
        set {
            fileVersionValue = value
        }
    }

    Sdk: string {
        get {
            return sdkValue
        }
        set {
            sdkValue = value
        }
    }

    TestFramework: string {
        get {
            return testFrameworkValue
        }
        set {
            testFrameworkValue = value
        }
    }

    PackageId: string {
        get {
            return packageIdValue
        }
        set {
            packageIdValue = value
        }
    }

    PackageAuthors: string {
        get {
            return packageAuthorsValue
        }
        set {
            packageAuthorsValue = value
        }
    }

    PackageDescription: string {
        get {
            return packageDescriptionValue
        }
        set {
            packageDescriptionValue = value
        }
    }

    PackageTags: string {
        get {
            return packageTagsValue
        }
        set {
            packageTagsValue = value
        }
    }

    PackageLicenseExpression: string {
        get {
            return packageLicenseExpressionValue
        }
        set {
            packageLicenseExpressionValue = value
        }
    }

    PackageProjectUrl: string {
        get {
            return packageProjectUrlValue
        }
        set {
            packageProjectUrlValue = value
        }
    }

    RepositoryUrl: string {
        get {
            return repositoryUrlValue
        }
        set {
            repositoryUrlValue = value
        }
    }

    PackageReadmeFile: string {
        get {
            return packageReadmeFileValue
        }
        set {
            packageReadmeFileValue = value
        }
    }

    PackageReadmeSource: string {
        get {
            return packageReadmeSourceValue
        }
        set {
            packageReadmeSourceValue = value
        }
    }

    constructor() {
        targetFrameworkValue = ""
        outputTypeValue = ""
        assemblyNameValue = ""
        versionValue = ""
        assemblyVersionValue = ""
        fileVersionValue = ""
        sdkValue = ""
        testFrameworkValue = ""
        packageIdValue = ""
        packageAuthorsValue = ""
        packageDescriptionValue = ""
        packageTagsValue = ""
        packageLicenseExpressionValue = ""
        packageProjectUrlValue = ""
        repositoryUrlValue = ""
        packageReadmeFileValue = ""
        packageReadmeSourceValue = ""
    }

    static DefaultTestFramework: string => new ProjectConfig().TestFramework

    static func ProjectFilePath(projectDirectory: string): string {
        return Path.Combine(projectDirectory, "project.yml")
    }

    static func LoadingMessage(projectFile: string): string {
        return "Loading project configuration from " + projectFile
    }

    static func Load(projectDirectory: string): SdkProjectConfiguration {
        config := ProjectFileParser.Parse(ProjectFilePath(projectDirectory))
        result := new SdkProjectConfiguration()
        result.TargetFramework = config.TargetFramework
        result.OutputType = "Exe"
        if config.OutputType.ToLowerInvariant() == "library" {
            result.OutputType = "Library"
        }
        result.AssemblyName = config.Name ?? must Path.GetFileName(projectDirectory)
        result.Version = config.Version ?? ""
        if !string.IsNullOrWhiteSpace(result.Version) {
            result.AssemblyVersion = AssemblyVersionUtilities.GetAssemblyVersionOrDefault(result.Version).ToString()
            result.FileVersion = result.AssemblyVersion
        }
        result.Sdk = config.Sdk
        result.TestFramework = config.TestFramework
        if config.Package != null {
            result.PackageId = config.Package.Id ?? ""
            result.PackageAuthors = config.Package.Author ?? ""
            result.PackageDescription = config.Package.Description ?? ""
            result.PackageTags = PackageTagsValue(config.Package.Tags)
            result.PackageLicenseExpression = config.Package.License ?? ""
            result.PackageProjectUrl = config.Package.Repository ?? ""
            result.RepositoryUrl = config.Package.Repository ?? ""
            readmePath := config.Package.Readme ?? ""
            if !string.IsNullOrWhiteSpace(readmePath) {
                result.PackageReadmeFile = PackageReadmeFileName(readmePath)
                result.PackageReadmeSource = Path.GetFullPath(Path.Combine(projectDirectory, readmePath))
            }
        }

        return result
    }

    static func PackageTagsValue(tags: List<string>?): string {
        if tags == null || tags.Count == 0 {
            return ""
        }

        builder := new StringBuilder()
        index := 0
        while index < tags.Count {
            if index > 0 {
                builder.Append(";")
            }

            builder.Append(tags[index])
            index = index + 1
        }

        return builder.ToString()
    }

    static func PackageReadmeFileName(readmePath: string): string {
        fileName := Path.GetFileName(readmePath.Replace('\\', '/')) ?? ""
        if string.IsNullOrWhiteSpace(fileName) {
            return "README.md"
        }

        return fileName
    }
}
