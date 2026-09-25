namespace NSharpLang.Build.Tasks

import System
import Microsoft.Build.Framework
import NSharpLang.Compiler

/// <summary>
/// MSBuild task that projects the N# project configuration into MSBuild properties.
/// </summary>
class LoadProjectConfig: Microsoft.Build.Utilities.Task {
    private projectDirectoryValue: string

    [Microsoft.Build.Framework.Required]
    ProjectDirectory: string {
        get {
            return projectDirectoryValue
        }
        set {
            projectDirectoryValue = value
        }
    }

    private targetFrameworkValue: string

    [Microsoft.Build.Framework.Output]
    TargetFramework: string {
        get {
            return targetFrameworkValue
        }
        set {
            targetFrameworkValue = value
        }
    }

    private outputTypeValue: string

    [Microsoft.Build.Framework.Output]
    OutputType: string {
        get {
            return outputTypeValue
        }
        set {
            outputTypeValue = value
        }
    }

    private assemblyNameValue: string

    [Microsoft.Build.Framework.Output]
    AssemblyName: string {
        get {
            return assemblyNameValue
        }
        set {
            assemblyNameValue = value
        }
    }

    private versionValue: string

    [Microsoft.Build.Framework.Output]
    Version: string {
        get {
            return versionValue
        }
        set {
            versionValue = value
        }
    }

    private assemblyVersionValue: string

    [Microsoft.Build.Framework.Output]
    AssemblyVersion: string {
        get {
            return assemblyVersionValue
        }
        set {
            assemblyVersionValue = value
        }
    }

    private fileVersionValue: string

    [Microsoft.Build.Framework.Output]
    FileVersion: string {
        get {
            return fileVersionValue
        }
        set {
            fileVersionValue = value
        }
    }

    private sdkValue: string

    [Microsoft.Build.Framework.Output]
    Sdk: string {
        get {
            return sdkValue
        }
        set {
            sdkValue = value
        }
    }

    private testFrameworkValue: string

    [Microsoft.Build.Framework.Output]
    TestFramework: string {
        get {
            return testFrameworkValue
        }
        set {
            testFrameworkValue = value
        }
    }

    private packageIdValue: string

    [Microsoft.Build.Framework.Output]
    PackageId: string {
        get {
            return packageIdValue
        }
        set {
            packageIdValue = value
        }
    }

    private packageAuthorsValue: string

    [Microsoft.Build.Framework.Output]
    PackageAuthors: string {
        get {
            return packageAuthorsValue
        }
        set {
            packageAuthorsValue = value
        }
    }

    private packageDescriptionValue: string

    [Microsoft.Build.Framework.Output]
    PackageDescription: string {
        get {
            return packageDescriptionValue
        }
        set {
            packageDescriptionValue = value
        }
    }

    private packageTagsValue: string

    [Microsoft.Build.Framework.Output]
    PackageTags: string {
        get {
            return packageTagsValue
        }
        set {
            packageTagsValue = value
        }
    }

    private packageLicenseExpressionValue: string

    [Microsoft.Build.Framework.Output]
    PackageLicenseExpression: string {
        get {
            return packageLicenseExpressionValue
        }
        set {
            packageLicenseExpressionValue = value
        }
    }

    private packageProjectUrlValue: string

    [Microsoft.Build.Framework.Output]
    PackageProjectUrl: string {
        get {
            return packageProjectUrlValue
        }
        set {
            packageProjectUrlValue = value
        }
    }

    private repositoryUrlValue: string

    [Microsoft.Build.Framework.Output]
    RepositoryUrl: string {
        get {
            return repositoryUrlValue
        }
        set {
            repositoryUrlValue = value
        }
    }

    private packageReadmeFileValue: string

    [Microsoft.Build.Framework.Output]
    PackageReadmeFile: string {
        get {
            return packageReadmeFileValue
        }
        set {
            packageReadmeFileValue = value
        }
    }

    private packageReadmeSourceValue: string

    [Microsoft.Build.Framework.Output]
    PackageReadmeSource: string {
        get {
            return packageReadmeSourceValue
        }
        set {
            packageReadmeSourceValue = value
        }
    }

    constructor() {
        projectDirectoryValue = ""
        targetFrameworkValue = ""
        outputTypeValue = ""
        assemblyNameValue = ""
        versionValue = ""
        assemblyVersionValue = ""
        fileVersionValue = ""
        sdkValue = ""
        testFrameworkValue = SdkProjectConfiguration.DefaultTestFramework
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

    override func Execute(): bool {
        try {
            projectFile := SdkProjectConfiguration.ProjectFilePath(ProjectDirectory)
            logger: Microsoft.Build.Utilities.TaskLoggingHelper = get_Log()
            importance: MessageImportance = MessageImportance.Low
            loadingMessage: string = SdkProjectConfiguration.LoadingMessage(projectFile)
            messageArguments: object[] = Array.Empty<object>()
            logger.LogMessage(importance, loadingMessage, messageArguments)

            config := SdkProjectConfiguration.Load(ProjectDirectory)
            TargetFramework = config.TargetFramework
            OutputType = config.OutputType
            AssemblyName = config.AssemblyName
            Version = config.Version
            AssemblyVersion = config.AssemblyVersion
            FileVersion = config.FileVersion
            Sdk = config.Sdk
            TestFramework = config.TestFramework
            PackageId = config.PackageId
            PackageAuthors = config.PackageAuthors
            PackageDescription = config.PackageDescription
            PackageTags = config.PackageTags
            PackageLicenseExpression = config.PackageLicenseExpression
            PackageProjectUrl = config.PackageProjectUrl
            RepositoryUrl = config.RepositoryUrl
            PackageReadmeFile = config.PackageReadmeFile
            PackageReadmeSource = config.PackageReadmeSource
            return true
        } catch ex: Exception {
            emptyProjectFile: string? = null
            get_Log().LogErrorFromException(ex, true, false, emptyProjectFile)
            return false
        }
    }
}
