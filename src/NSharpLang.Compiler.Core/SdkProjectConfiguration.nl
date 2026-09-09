namespace NSharpLang.Compiler

import System.IO

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

    constructor() {
        targetFrameworkValue = ""
        outputTypeValue = ""
        assemblyNameValue = ""
        versionValue = ""
        assemblyVersionValue = ""
        fileVersionValue = ""
        sdkValue = ""
        testFrameworkValue = ""
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
        return result
    }
}
