namespace NSharpLang.Build.Tasks

import System
import Microsoft.Build.Framework
import Microsoft.Build.Utilities
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
            return true
        } catch ex: Exception {
            emptyProjectFile: string? = null
            get_Log().LogErrorFromException(ex, true, false, emptyProjectFile)
            return false
        }
    }
}
