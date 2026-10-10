namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

class ProjectConfig {
    nameValue: string?
    versionValue: string?
    entryValue: string?
    backendValue: string?
    outputTypeValue: string?
    targetFrameworkValue: string?
    excludeTestsValue: bool
    debugTypeValue: string?
    sdkValue: string?
    dependenciesValue: List<Reference>?
    testDependenciesValue: List<Reference>?
    excludeValue: List<string>?
    testFrameworkValue: string?
    definesValue: List<string>?
    internalsVisibleToValue: List<string>?
    languageValue: LanguageConfig?
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
            if backendValue == null {
                return "il"
            }

            return backendValue
        }
        set {
            backendValue = value
        }
    }

    OutputType: string {
        get {
            if outputTypeValue == null {
                return "exe"
            }

            return outputTypeValue
        }
        set {
            outputTypeValue = value
        }
    }

    TargetFramework: string {
        get {
            if targetFrameworkValue == null {
                return "net10.0"
            }

            return targetFrameworkValue
        }
        set {
            targetFrameworkValue = value
        }
    }

    ExcludeTests: bool {
        get {
            return excludeTestsValue
        }
        set {
            excludeTestsValue = value
        }
    }

    DebugType: string {
        get {
            if debugTypeValue == null {
                return "none"
            }

            return debugTypeValue
        }
        set {
            debugTypeValue = value
        }
    }

    Sdk: string {
        get {
            if sdkValue == null {
                return "Microsoft.NET.Sdk"
            }

            return sdkValue
        }
        set {
            sdkValue = value
        }
    }

    Dependencies: List<Reference> {
        get {
            if dependenciesValue == null {
                dependenciesValue = new List<Reference>()
            }

            return dependenciesValue
        }
        set {
            dependenciesValue = value
        }
    }

    TestDependencies: List<Reference> {
        get {
            if testDependenciesValue == null {
                testDependenciesValue = new List<Reference>()
            }

            return testDependenciesValue
        }
        set {
            testDependenciesValue = value
        }
    }

    Exclude: List<string> {
        get {
            if excludeValue == null {
                excludeValue = new List<string>()
            }

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
            if testFrameworkValue == null {
                return "xunit"
            }

            return testFrameworkValue
        }
        set {
            testFrameworkValue = value
        }
    }

    Defines: List<string> {
        get {
            if definesValue == null {
                definesValue = new List<string>()
            }

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

    // THE ASSEMBLIES THIS PROJECT MAKES ITS FRIENDS. Each entry is an assembly DISPLAY name, and
    // each one is emitted as an `[assembly: InternalsVisibleTo(...)]` row on the produced assembly,
    // which is the only way an N# library can let another assembly reach the members it emits as
    // CLR `internal`. It is the WRITING half of the rule `InternalsVisibleToGrants` reads: a
    // consumer compiled under one of these names sees this assembly's internals, and the CLR
    // re-checks the same rows when it loads the consumer.
    InternalsVisibleTo: List<string> {
        get {
            if internalsVisibleToValue == null {
                internalsVisibleToValue = new List<string>()
            }

            return internalsVisibleToValue
        }
        set {
            if value == null {
                internalsVisibleToValue = new List<string>()
            } else {
                internalsVisibleToValue = value
            }
        }
    }

    Language: LanguageConfig {
        get {
            if languageValue == null {
                languageValue = new LanguageConfig()
            }

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

    EffectiveName: string => Name ?? Path.GetFileName(Environment.CurrentDirectory) ?? "Project"

    func GetSourceFiles(projectRoot: string, includeTests: bool = false): string[] {
        allFiles := EnumerateSourceFileArray(projectRoot)
        return ProjectSourceFileFilter.Filter(allFiles, projectRoot, Exclude.ToArray(), includeTests)
    }

    // The distinct nested `project.yml` roots that own included source files. Keep this query on the
    // same filtered file set as the compiler so excluded files and test-file policy cannot invent a
    // project boundary. Each file is attributed to its nearest nested project root.
    func GetNestedProjectRoots(projectRoot: string, includeTests: bool = false): List<string> {
        fullRoot := Path.GetFullPath(projectRoot)
        rootBoundary := fullRoot
        if !rootBoundary.EndsWith(Path.DirectorySeparatorChar.ToString()) {
            rootBoundary = rootBoundary + Path.DirectorySeparatorChar.ToString()
        }

        nestedRoots := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for sourceFile in GetSourceFiles(projectRoot, includeTests) {
            directory := Path.GetDirectoryName(Path.GetFullPath(sourceFile))
            while directory != null && !string.Equals(directory, fullRoot, StringComparison.OrdinalIgnoreCase) {
                if !directory.StartsWith(rootBoundary, StringComparison.OrdinalIgnoreCase) {
                    break
                }
                if File.Exists(Path.Combine(directory, "project.yml")) {
                    if seen.Add(directory) {
                        nestedRoots.Add(directory)
                    }
                    break
                }

                directory = Path.GetDirectoryName(directory)
            }
        }

        return nestedRoots
    }

    static func EnumerateSourceFiles(projectRoot: string): IEnumerable<string> {
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

    // The CLI workspace front door checks every nested project.yml as its own program. This walk
    // shares the source walk's ignore rules, but discovers project boundaries directly so a
    // parent project's exclude patterns cannot hide a member project from the workspace.
    func DiscoverNestedProjectRoots(projectRoot: string): List<string> {
        roots := new List<string>()
        if !Directory.Exists(projectRoot) {
            return roots
        }

        DiscoverNestedProjectRootsRecursive(Path.GetFullPath(projectRoot), roots)
        roots.Sort(StringComparer.OrdinalIgnoreCase)
        return roots
    }

    private static func DiscoverNestedProjectRootsRecursive(directory: string, roots: List<string>): void {
        subdirectories := new string[](0)
        try {
            subdirectories = Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
        } catch {
            return
        }

        for subdirectory in subdirectories {
            directoryName := Path.GetFileName(subdirectory) ?? ""
            if ShouldSkipSourceDirectory(directoryName) || IsNestedGitWorktree(subdirectory) {
                continue
            }

            if File.Exists(Path.Combine(subdirectory, "project.yml")) {
                roots.Add(Path.GetFullPath(subdirectory))
            }

            DiscoverNestedProjectRootsRecursive(subdirectory, roots)
        }
    }

    private static func IsNestedGitWorktree(directory: string): bool {
        marker := Path.Combine(directory, ".git")
        return File.Exists(marker) || Directory.Exists(marker)
    }

    static func EnumerateSourceFilesRecursive(directory: string, files: List<string>) {
        directoryFiles := new string[](0)
        try {
            directoryFiles = Directory.GetFiles(directory, "*.nl", SearchOption.TopDirectoryOnly)
        } catch {
            return
        }

        for directoryFile in directoryFiles {
            files.Add(directoryFile)
        }

        subdirectories := new string[](0)
        try {
            subdirectories = Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
        } catch {
            return
        }

        for subdirectory in subdirectories {
            directoryName := Path.GetFileName(subdirectory) ?? ""
            if !ShouldSkipSourceDirectory(directoryName) && !IsNestedGitWorktree(subdirectory) {
                EnumerateSourceFilesRecursive(subdirectory, files)
            }
        }
    }

    static func ShouldSkipSourceDirectory(name: string): bool {
        if String.Compare(name, ".context", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, ".git", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, ".github", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, ".hermes", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, ".vscode", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, ".vscode-test", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, ".worktrees", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, "bin", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, "bootstrap", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, "node_modules", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, "nsharp", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, "obj", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }
        if String.Compare(name, "out", StringComparison.OrdinalIgnoreCase) == 0 {
            return true
        }

        return false
    }
}

class PackageConfig {
    idValue: string?
    authorValue: string?
    descriptionValue: string?
    tagsValue: List<string>?
    licenseValue: string?
    repositoryValue: string?
    iconValue: string?
    readmeValue: string?

    Id: string? {
        get {
            return idValue
        }
        set {
            idValue = value
        }
    }

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

    Readme: string? {
        get {
            return readmeValue
        }
        set {
            readmeValue = value
        }
    }
}

class LanguageConfig {
    profileValue: string?
    asyncDefaultTypeValue: string?
    pooledAsyncValue: bool
    systemsValue: SystemsConfig?

    Profile: string {
        get {
            if profileValue == null {
                return "default"
            }

            return profileValue
        }
        set {
            profileValue = value
        }
    }

    AsyncDefaultType: string {
        get {
            if asyncDefaultTypeValue == null {
                return "ValueTask"
            }

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
            if systemsValue == null {
                systemsValue = new SystemsConfig()
            }

            return systemsValue
        }
        set {
            systemsValue = value
        }
    }
}

class SystemsConfig {
    modeValue: string?
    unknownExternalCallsValue: string?
    aotTargetValue: string?
    warmupValue: List<string>?
    stackBudgetBytesValue: int
    stackBudgetBytesAssignedValue: bool
    hotSummaryFilesValue: List<string>?
    allowHotSidecarsValue: bool

    Mode: string {
        get {
            if modeValue == null {
                return "strict"
            }

            return modeValue
        }
        set {
            modeValue = value
        }
    }

    UnknownExternalCalls: string {
        get {
            if unknownExternalCallsValue == null {
                return "warn"
            }

            return unknownExternalCallsValue
        }
        set {
            unknownExternalCallsValue = value
        }
    }

    AotTarget: string {
        get {
            if aotTargetValue == null {
                return "nativeaot"
            }

            return aotTargetValue
        }
        set {
            aotTargetValue = value
        }
    }

    Warmup: List<string> {
        get {
            if warmupValue == null {
                warmupValue = new List<string>()
            }

            return warmupValue
        }
        set {
            warmupValue = value
        }
    }

    StackBudgetBytes: int {
        get {
            if !stackBudgetBytesAssignedValue {
                return 4096
            }

            return stackBudgetBytesValue
        }
        set {
            stackBudgetBytesValue = value
            stackBudgetBytesAssignedValue = true
        }
    }

    HotSummaryFiles: List<string> {
        get {
            if hotSummaryFilesValue == null {
                hotSummaryFilesValue = new List<string>()
            }

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
