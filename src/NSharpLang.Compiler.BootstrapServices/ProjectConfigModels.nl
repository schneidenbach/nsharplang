namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

public class ProjectConfig {
    nameValue: string?
    versionValue: string?
    entryValue: string?
    backendValue: string = "il"
    outputTypeValue: string = "exe"
    targetFrameworkValue: string = "net10.0"
    sdkValue: string = "Microsoft.NET.Sdk"
    dependenciesValue: List<Reference> = new List<Reference>()
    testDependenciesValue: List<Reference> = new List<Reference>()
    excludeValue: List<string> = new List<string>()
    testFrameworkValue: string = "xunit"
    definesValue: List<string> = new List<string>()
    languageValue: LanguageConfig = new LanguageConfig()
    packageValue: PackageConfig?

    Name: string? {
        get {
            return nameValue
        }
        set {
            nameValue = value
        }
    }

    Version: string? {
        get {
            return versionValue
        }
        set {
            versionValue = value
        }
    }

    Entry: string? {
        get {
            return entryValue
        }
        set {
            entryValue = value
        }
    }

    Backend: string {
        get {
            return backendValue
        }
        set {
            backendValue = value
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

    TargetFramework: string {
        get {
            return targetFrameworkValue
        }
        set {
            targetFrameworkValue = value
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

    Dependencies: List<Reference> {
        get {
            return dependenciesValue
        }
        set {
            dependenciesValue = value
        }
    }

    TestDependencies: List<Reference> {
        get {
            return testDependenciesValue
        }
        set {
            testDependenciesValue = value
        }
    }

    Exclude: List<string> {
        get {
            return excludeValue
        }
        set {
            if value == null {
                excludeValue = new List<string>()
            } else {
                excludeValue = value
            }
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

    Defines: List<string> {
        get {
            return definesValue
        }
        set {
            if value == null {
                definesValue = new List<string>()
            } else {
                definesValue = value
            }
        }
    }

    Language: LanguageConfig {
        get {
            return languageValue
        }
        set {
            if value == null {
                languageValue = new LanguageConfig()
            } else {
                languageValue = value
            }
        }
    }

    Package: PackageConfig? {
        get {
            return packageValue
        }
        set {
            packageValue = value
        }
    }

    public EffectiveName: string => Name ?? Path.GetFileName(Environment.CurrentDirectory) ?? "Project"

    public func GetSourceFiles(projectRoot: string, includeTests: bool = false): string[] {
        allFiles := EnumerateSourceFileArray(projectRoot)
        return ProjectSourceFileFilter.Filter(allFiles, projectRoot, Exclude.ToArray(), includeTests)
    }

    public static func EnumerateSourceFiles(projectRoot: string): IEnumerable<string> {
        return EnumerateSourceFileArray(projectRoot)
    }

    static func EnumerateSourceFileArray(projectRoot: string): string[] {
        if !Directory.Exists(projectRoot) {
            return new string[](0)
        }

        files := new List<string>()
        EnumerateSourceFilesRecursive(Path.GetFullPath(projectRoot), files)
        return files.ToArray()
    }

    static func EnumerateSourceFilesRecursive(directory: string, files: List<string>) {
        directoryFiles := new string[](0)
        try {
            directoryFiles = Directory.GetFiles(directory, "*.nl", SearchOption.TopDirectoryOnly)
        } catch {
            return
        }

        i := 0
        while i < directoryFiles.Length {
            files.Add(directoryFiles[i])
            i = i + 1
        }

        subdirectories := new string[](0)
        try {
            subdirectories = Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
        } catch {
            return
        }

        j := 0
        while j < subdirectories.Length {
            subdirectory := subdirectories[j]
            directoryName := Path.GetFileName(subdirectory) ?? ""
            if !ShouldSkipSourceDirectory(directoryName) {
                EnumerateSourceFilesRecursive(subdirectory, files)
            }

            j = j + 1
        }
    }

    static func ShouldSkipSourceDirectory(name: string): bool {
        if String.Compare(name, ".context", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, ".git", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, ".github", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, ".hermes", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, ".vscode", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, ".vscode-test", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, ".worktrees", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, "bin", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, "node_modules", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, "nsharp", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, "obj", StringComparison.OrdinalIgnoreCase) == 0 { return true }
        if String.Compare(name, "out", StringComparison.OrdinalIgnoreCase) == 0 { return true }

        return false
    }
}

public class PackageConfig {
    authorValue: string?
    descriptionValue: string?
    tagsValue: List<string>?
    licenseValue: string?
    repositoryValue: string?
    iconValue: string?

    Author: string? {
        get {
            return authorValue
        }
        set {
            authorValue = value
        }
    }

    Description: string? {
        get {
            return descriptionValue
        }
        set {
            descriptionValue = value
        }
    }

    Tags: List<string>? {
        get {
            return tagsValue
        }
        set {
            tagsValue = value
        }
    }

    License: string? {
        get {
            return licenseValue
        }
        set {
            licenseValue = value
        }
    }

    Repository: string? {
        get {
            return repositoryValue
        }
        set {
            repositoryValue = value
        }
    }

    Icon: string? {
        get {
            return iconValue
        }
        set {
            iconValue = value
        }
    }
}

public class LanguageConfig {
    profileValue: string = "default"
    asyncDefaultTypeValue: string = "ValueTask"
    pooledAsyncValue: bool
    systemsValue: SystemsConfig = new SystemsConfig()

    Profile: string {
        get {
            return profileValue
        }
        set {
            profileValue = value
        }
    }

    AsyncDefaultType: string {
        get {
            return asyncDefaultTypeValue
        }
        set {
            asyncDefaultTypeValue = value
        }
    }

    PooledAsync: bool {
        get {
            return pooledAsyncValue
        }
        set {
            pooledAsyncValue = value
        }
    }

    Systems: SystemsConfig {
        get {
            return systemsValue
        }
        set {
            systemsValue = value
        }
    }
}

public class SystemsConfig {
    modeValue: string = "strict"
    unknownExternalCallsValue: string = "warn"
    aotTargetValue: string = "nativeaot"
    warmupValue: List<string> = new List<string>()
    stackBudgetBytesValue: int = 4096
    hotSummaryFilesValue: List<string> = new List<string>()
    allowHotSidecarsValue: bool

    Mode: string {
        get {
            return modeValue
        }
        set {
            modeValue = value
        }
    }

    UnknownExternalCalls: string {
        get {
            return unknownExternalCallsValue
        }
        set {
            unknownExternalCallsValue = value
        }
    }

    AotTarget: string {
        get {
            return aotTargetValue
        }
        set {
            aotTargetValue = value
        }
    }

    Warmup: List<string> {
        get {
            return warmupValue
        }
        set {
            warmupValue = value
        }
    }

    StackBudgetBytes: int {
        get {
            return stackBudgetBytesValue
        }
        set {
            stackBudgetBytesValue = value
        }
    }

    HotSummaryFiles: List<string> {
        get {
            return hotSummaryFilesValue
        }
        set {
            hotSummaryFilesValue = value
        }
    }

    AllowHotSidecars: bool {
        get {
            return allowHotSidecarsValue
        }
        set {
            allowHotSidecarsValue = value
        }
    }
}
