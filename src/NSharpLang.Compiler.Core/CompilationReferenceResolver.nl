namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.IO.Compression
import System.Net.Http
import System.Runtime.InteropServices
import System.Text.Json
import System.Xml.Linq
import NSharpLang.Compiler

sealed class CompilationReferenceResolver {
    private static readonly HttpClient: HttpClient = CreateHttpClient()

    private constructor() {
    }

    private static func CreateHttpClient(): HttpClient {
        client := new HttpClient()
        client.Timeout = TimeSpan.FromMinutes(2)
        return client
    }

    static func AddResolvedDllReferences(
        projectDir: string,
        config: ProjectConfig,
        options: ReferenceResolutionOptions? = null
    ): ReferenceResolutionResult {
        resolvedOptions := options ?? new ReferenceResolutionOptions()
        context := new ResolutionContext()
        projectRoot := CompilationReferenceResolverKernels.GetProjectRoot(projectDir)
        return ResolveProjectReferences(projectRoot, config, resolvedOptions, context)
    }

    static func GetProjectAssemblyName(projectRoot: string, config: ProjectConfig): string {
        return CompilationReferenceResolverKernels.GetProjectAssemblyName(projectRoot, config.Name)
    }

    private static func GetStableOutputDirectory(
        projectRoot: string,
        config: ProjectConfig,
        configuration: string
    ): string {
        return CompilationReferenceResolverKernels.GetStableOutputDirectory(
            projectRoot,
            configuration,
            config.TargetFramework
        )
    }

    private static func ResolveProjectReferences(
        projectRoot: string,
        config: ProjectConfig,
        options: ReferenceResolutionOptions,
        context: ResolutionContext
    ): ReferenceResolutionResult {
        projectRoot = CompilationReferenceResolverKernels.GetProjectRoot(projectRoot)
        result := ReferenceResolutionResult.Create(projectRoot, config.Dependencies)

        AddImplicitTestDependencies(projectRoot, config, options)
        AddImplicitNSharpRuntimeAsset(result)

        frameworkDirectories := ResolveFrameworkReferenceDirectories(projectRoot, config)
        frameworkIndex := 0
        while frameworkIndex < frameworkDirectories.Count {
            frameworkDirectory := frameworkDirectories[frameworkIndex]
            assemblyPaths := Directory.GetFiles(frameworkDirectory, "*.dll", SearchOption.TopDirectoryOnly)
            assemblyIndex := 0
            while assemblyIndex < assemblyPaths.Length {
                AddDllReference(config, assemblyPaths[assemblyIndex])
                assemblyIndex = assemblyIndex + 1
            }
            frameworkIndex = frameworkIndex + 1
        }

        packageReferences := CompilationReferenceResolverKernels.GetNuGetReferences(
            config.Dependencies,
            config.TestDependencies,
            options.IncludeTests
        )
        packageIndex := 0
        while packageIndex < packageReferences.Count {
            packageReference := packageReferences[packageIndex]
            packageAssets := ResolveNuGetPackage(
                packageReference.Nuget,
                packageReference.Version,
                config.TargetFramework,
                context
            )

            for assemblyPath in packageAssets.CompileAssemblies {
                AddDllReference(config, assemblyPath)
            }

            for runtimeAsset in packageAssets.RuntimeAssemblies {
                AddDllReference(config, runtimeAsset)
                result.AddRuntimeAsset(runtimeAsset)
            }
            packageIndex = packageIndex + 1
        }

        projectReferences := CompilationReferenceResolverKernels.FilterReferencesByType(
            config.Dependencies,
            ReferenceType.Project
        )
        projectIndex := 0
        while projectIndex < projectReferences.Count {
            projectReference := projectReferences[projectIndex]
            if !options.BuildProjectReferences {
                projectIndex = projectIndex + 1
                continue
            }

            resolvedProjectReferencePath := CompilationReferenceResolverKernels.ResolveProjectReferencePath(
                projectRoot,
                projectReference.Project
            )
            referencedProjectRoot := ProjectReferenceResolver.ResolveNSharpProjectRoot(resolvedProjectReferencePath)
            referencedProjectYml := CompilationReferenceResolverKernels.GetProjectYmlPath(referencedProjectRoot)
            referencedConfig := ProjectFileParser.Parse(referencedProjectYml)
            referencedOutput := BuildProjectReference(
                referencedProjectRoot,
                referencedConfig,
                options,
                context
            )

            AddDllReference(config, referencedOutput.OutputAssemblyPath)
            result.AddRuntimeAsset(referencedOutput.OutputAssemblyPath)
            result.Add(referencedOutput.References)
            config.Dependencies.Remove(projectReference)
            projectIndex = projectIndex + 1
        }

        return result
    }

    private static func AddImplicitNSharpRuntimeAsset(result: ReferenceResolutionResult): void {
        compilerDirectory := CompilationReferenceResolverKernels.GetCompilerAssemblyDirectory(
            typeof(ProjectConfig).get_Assembly().get_Location()
        )
        candidates := CompilationReferenceResolverKernels.GetImplicitNSharpRuntimeAssetCandidates(
            AppContext.BaseDirectory,
            compilerDirectory
        )
        candidateIndex := 0
        while candidateIndex < candidates.Length {
            candidate := candidates[candidateIndex]
            if File.Exists(candidate) {
                result.AddRuntimeAsset(candidate)
                return
            }
            candidateIndex = candidateIndex + 1
        }
    }

    private static func BuildProjectReference(
        projectRoot: string,
        config: ProjectConfig,
        options: ReferenceResolutionOptions,
        context: ResolutionContext
    ): ResolvedProjectReference {
        projectRoot = CompilationReferenceResolverKernels.GetProjectRoot(projectRoot)
        let cachedOutput: ResolvedProjectReference? = null
        if context.ProjectOutputs.TryGetValue(projectRoot, out cachedOutput) {
            return cachedOutput
        }

        if context.ActiveProjectRoots.Contains(projectRoot) {
            activeRoots := context.ActiveProjectRoots
            chainRoots := new string[](activeRoots.Count + 1)
            chainIndex := 0
            for activeRoot in activeRoots {
                chainRoots[chainIndex] = activeRoot
                chainIndex = chainIndex + 1
            }
            chainRoots[chainIndex] = projectRoot
            throw new InvalidOperationException(
                CompilationReferenceResolverKernels.GetProjectReferenceCycleMessage(chainRoots)
            )
        }

        context.ActiveProjectRoots.Push(projectRoot)
        let resolvedOutput: ResolvedProjectReference = null
        try {
            references := ResolveProjectReferences(
                projectRoot,
                config,
                CompilationReferenceResolverKernels.GetProjectReferenceResolutionOptions(options),
                context
            )
            outputDirectory := GetStableOutputDirectory(projectRoot, config, options.Configuration)
            Directory.CreateDirectory(outputDirectory)

            assemblyName := GetProjectAssemblyName(projectRoot, config)
            outputPath := CompilationReferenceResolverKernels.GetProjectOutputAssemblyPath(
                outputDirectory,
                assemblyName
            )
            compiler := new MultiFileCompiler(projectRoot, config)
            compiler.AotMode = options.AotMode
            compilationResult := compiler.CompileToIlAssembly(
                assemblyName,
                outputPath,
                false,
                true
            )
            if CompilationReferenceResolverKernels.ShouldTreatProjectReferenceBuildAsFailed(
                compilationResult.Success,
                compilationResult.OutputAssemblyPath
            ) {
                failedProjectYml := CompilationReferenceResolverKernels.GetProjectYmlPath(projectRoot)
                formattedDiagnostics := FormatCompilerDiagnostics(compilationResult.Errors)
                throw new InvalidOperationException(
                    CompilationReferenceResolverKernels.GetProjectReferenceBuildFailedMessage(
                        failedProjectYml,
                        CompilationReferenceResolverKernels.GetCompilerDiagnosticsText(
                            formattedDiagnostics
                        )
                    )
                )
            }

            if CompilationReferenceResolverKernels.IsExecutableOutputType(config.OutputType) {
                CompilationArtifacts.WriteRuntimeConfig(config, compilationResult.OutputAssemblyPath)
            }

            references.CopyRuntimeAssets(outputDirectory)
            resolvedOutput = new ResolvedProjectReference(
                compilationResult.OutputAssemblyPath,
                references
            )
            context.ProjectOutputs[projectRoot] = resolvedOutput
        } finally {
            context.ActiveProjectRoots.Pop()
        }
        return resolvedOutput
    }

    private static func FormatCompilerDiagnostics(errors: IEnumerable<CompilerError>): string[] {
        formattedDiagnostics := new List<string>()
        errorEnumerator := errors.GetEnumerator()
        let errorEnumeratorObject: object = errorEnumerator
        movement := errorEnumeratorObject as System.Collections.IEnumerator
        try {
            while movement.MoveNext() {
                error := errorEnumerator.get_Current()
                formattedDiagnostics.Add(error.Format(false))
            }
        } finally {
            disposable := errorEnumeratorObject as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return formattedDiagnostics.ToArray()
    }

    private static func AddImplicitTestDependencies(
        projectRoot: string,
        config: ProjectConfig,
        options: ReferenceResolutionOptions
    ): void {
        hasTests := false
        if Directory.Exists(projectRoot) {
            hasTests = Directory.GetFiles(
                projectRoot,
                "*.tests.nl",
                SearchOption.AllDirectories
            ).Length > 0
        }

        packageReferences := CompilationReferenceResolverKernels.FilterReferencesByType(
            config.TestDependencies,
            ReferenceType.NuGet
        )
        existingPackageIds := new string[](packageReferences.Count)
        packageIndex := 0
        while packageIndex < packageReferences.Count {
            packageId := packageReferences[packageIndex].Nuget
            let resolvedPackageId: string = ""
            if packageId != null {
                resolvedPackageId = packageId
            }
            existingPackageIds[packageIndex] = resolvedPackageId
            packageIndex = packageIndex + 1
        }

        plan := CompilationReferenceResolverKernels.GetImplicitTestDependencyPlan(
            options.IncludeTests,
            hasTests,
            config.TestFramework,
            existingPackageIds
        )
        if !plan.ShouldAdd {
            return
        }

        config.TestDependencies.Add(new Reference { Nuget: plan.PackageName, Version: plan.Version })
    }

    private static func ResolveFrameworkReferenceDirectories(
        projectRoot: string,
        config: ProjectConfig
    ): IReadOnlyList<string> {
        directories := new List<string>()
        frameworkNames := CompilationReferenceResolverKernels.GetFrameworkReferenceNames(
            config.Sdk,
            config.Dependencies
        )
        frameworkIndex := 0
        while frameworkIndex < frameworkNames.Length {
            frameworkName := frameworkNames[frameworkIndex]
            directory := FindSharedFrameworkDirectory(frameworkName, config.TargetFramework)
            if directory == null {
                throw new InvalidOperationException(
                    CompilationReferenceResolverKernels.GetFrameworkReferenceNotResolvedMessage(
                        frameworkName,
                        projectRoot,
                        config.TargetFramework
                    )
                )
            }
            directories.Add(directory)
            frameworkIndex = frameworkIndex + 1
        }
        return directories
    }

    private static func ResolveNuGetPackage(
        packageName: string,
        version: string?,
        targetFramework: string,
        context: ResolutionContext
    ): NuGetPackageAssets {
        versionDirectory := EnsurePackageAvailable(packageName, version)
        declaredIdentity := ReadPackageIdentity(versionDirectory)
        packageIdentity := CompilationReferenceResolverKernels.ResolveNuGetPackageIdentity(
            versionDirectory,
            packageName,
            declaredIdentity.Id,
            declaredIdentity.Version
        )
        key := CompilationReferenceResolverKernels.GetNuGetPackageAssetsCacheKey(
            packageIdentity.Id,
            packageIdentity.Version
        )

        let cached: NuGetPackageAssets? = null
        if context.PackageAssets.TryGetValue(key, out cached) {
            return cached
        }

        assets := new NuGetPackageAssets()
        context.PackageAssets[key] = assets

        dependencies := ReadPackageDependencies(versionDirectory, targetFramework)
        dependencyIndex := 0
        while dependencyIndex < dependencies.Count {
            dependency := dependencies[dependencyIndex]
            dependencyAssets := ResolveNuGetPackage(
                dependency.Id,
                dependency.Version,
                targetFramework,
                context
            )
            assets.Add(dependencyAssets)
            dependencyIndex = dependencyIndex + 1
        }

        compileAssemblies := SelectBestAssetAssemblies(versionDirectory, "ref", targetFramework)
        compileIndex := 0
        while compileIndex < compileAssemblies.Count {
            assets.CompileAssemblies.Add(compileAssemblies[compileIndex])
            compileIndex = compileIndex + 1
        }

        runtimeAssemblies := SelectBestAssetAssemblies(versionDirectory, "lib", targetFramework)
        runtimeIndex := 0
        while runtimeIndex < runtimeAssemblies.Count {
            assets.RuntimeAssemblies.Add(runtimeAssemblies[runtimeIndex])
            runtimeIndex = runtimeIndex + 1
        }

        if CompilationReferenceResolverKernels.ShouldUseRuntimeAssembliesForCompile(
            assets.CompileAssemblies.Count
        ) {
            runtimeIndex = 0
            while runtimeIndex < runtimeAssemblies.Count {
                assets.CompileAssemblies.Add(runtimeAssemblies[runtimeIndex])
                runtimeIndex = runtimeIndex + 1
            }
        }

        return assets
    }

    private static func EnsurePackageAvailable(packageName: string, version: string?): string {
        packagesRoot := GetGlobalPackagesFolder()
        packageDirectory := CompilationReferenceResolverKernels.GetNuGetPackageDirectory(
            packagesRoot,
            packageName
        )
        packageDirectoryExists := Directory.Exists(packageDirectory)
        if CompilationReferenceResolverKernels.ShouldProbeInstalledNuGetVersions(
            version,
            packageDirectoryExists
        ) {
            installedDirectories := Directory.GetDirectories(packageDirectory)
            bestInstalledVersionDirectory := CompilationReferenceResolverKernels.SelectBestInstalledNuGetVersionDirectory(installedDirectories)
            if bestInstalledVersionDirectory != null {
                return bestInstalledVersionDirectory
            }
        }

        resolvedVersion := version
        if resolvedVersion == null {
            resolvedVersion = GetLatestPackageVersion(packageName)
        }
        versionDirectory := CompilationReferenceResolverKernels.GetNuGetPackageVersionDirectory(
            packageDirectory,
            resolvedVersion
        )
        if Directory.Exists(versionDirectory) {
            return versionDirectory
        }

        DownloadPackage(packageName, resolvedVersion, versionDirectory)
        return versionDirectory
    }

    private static func GetLatestPackageVersion(packageName: string): string {
        indexUrl := CompilationReferenceResolverKernels.GetNuGetIndexUrl(packageName)
        client := CompilationReferenceResolver.HttpClient
        responseTask := client.GetStringAsync(indexUrl)
        responseText := await responseTask
        document := JsonDocument.Parse(responseText)
        let latestVersion: string = null
        try {
            versionsElement := document.RootElement.GetProperty("versions")
            versions := new List<string?>()
            ReadNuGetVersionStrings(versionsElement, versions)
            latestVersion = CompilationReferenceResolverKernels.GetLatestNuGetVersionOrThrow(
                packageName,
                versions.ToArray()
            )
        } finally {
            document.Dispose()
        }
        return latestVersion
    }

    private static func ReadNuGetVersionStrings(
        versionsElement: JsonElement,
        versionsList: List<string?>
    ): void {
        versions := versionsElement.EnumerateArray()
        try {
            while versions.MoveNext() {
                versionsList.Add(versions.Current.GetString())
            }
        } finally {
            versions.Dispose()
        }
    }

    private static func DownloadPackage(
        packageName: string,
        version: string,
        versionDirectory: string
    ): void {
        url := CompilationReferenceResolverKernels.GetNuGetPackageDownloadUrl(packageName, version)
        tempDirectory := CompilationReferenceResolverKernels.GetNuGetTempDirectory(
            Path.GetTempPath(),
            Guid.NewGuid().ToString("N")
        )
        packagePath := CompilationReferenceResolverKernels.GetNuGetPackagePath(
            tempDirectory,
            packageName,
            version
        )

        try {
            Directory.CreateDirectory(tempDirectory)
            client := CompilationReferenceResolver.HttpClient
            bytesTask := client.GetByteArrayAsync(url)
            bytes := await bytesTask
            File.WriteAllBytes(packagePath, bytes)

            parentDirectory := CompilationReferenceResolverKernels.GetNuGetPackageParentDirectory(
                versionDirectory
            )
            Directory.CreateDirectory(parentDirectory)
            extractDirectory := CompilationReferenceResolverKernels.GetNuGetExtractDirectory(
                versionDirectory,
                Guid.NewGuid().ToString("N")
            )
            ZipFile.ExtractToDirectory(packagePath, extractDirectory)

            if Directory.Exists(versionDirectory) {
                Directory.Delete(extractDirectory, true)
            } else {
                Directory.Move(extractDirectory, versionDirectory)
            }
        } catch ex: Exception {
            throw new InvalidOperationException(
                CompilationReferenceResolverKernels.GetNuGetRestoreFailedMessage(
                    packageName,
                    version,
                    ex.Message
                ),
                ex
            )
        } finally {
            TryDeleteDirectoryRecursively(tempDirectory)
        }
    }

    private static func TryDeleteDirectoryRecursively(directory: string): void {
        try {
            Directory.Delete(directory, true)
        } catch {
            return
        }
    }

    private static func ReadPackageIdentity(versionDirectory: string): PackageIdentity {
        nuspecPaths := Directory.GetFiles(
            versionDirectory,
            "*.nuspec",
            SearchOption.TopDirectoryOnly
        )
        if nuspecPaths.Length == 0 {
            return CompilationReferenceResolverKernels.GetFallbackNuGetPackageIdentity(
                versionDirectory
            )
        }

        document := XDocument.Load(nuspecPaths[0])
        let descendants: System.Collections.IEnumerable = document.Descendants()
        metadata := FindFirstElementByLocalName(descendants, "metadata")

        let id: string? = null
        let packageVersion: string? = null
        if metadata != null {
            let idElements: System.Collections.IEnumerable = metadata.Elements()
            idElement := FindFirstElementByLocalName(idElements, "id")
            if idElement != null {
                id = idElement.Value
            }

            let versionElements: System.Collections.IEnumerable = metadata.Elements()
            versionElement := FindFirstElementByLocalName(versionElements, "version")
            if versionElement != null {
                packageVersion = versionElement.Value
            }
        }

        return new PackageIdentity(id, packageVersion)
    }

    private static func FindFirstElementByLocalName(
        elements: System.Collections.IEnumerable,
        localName: string
    ): XElement? {
        let result: XElement? = null
        enumerator := elements.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                element := enumerator.get_Current() as XElement
                elementName := element.Name
                elementLocalName := elementName.LocalName
                if elementLocalName == localName {
                    result = element
                    break
                }
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return result
    }

    private static func CollectElementsByLocalName(
        elements: System.Collections.IEnumerable,
        localName: string,
        output: List<XElement>
    ): void {
        enumerator := elements.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                element := enumerator.get_Current() as XElement
                elementName := element.Name
                elementLocalName := elementName.LocalName
                if elementLocalName == localName {
                    output.Add(element)
                }
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
    }

    private static func ReadPackageDependencies(
        versionDirectory: string,
        targetFramework: string
    ): IReadOnlyList<PackageDependency> {
        nuspecPaths := Directory.GetFiles(
            versionDirectory,
            "*.nuspec",
            SearchOption.TopDirectoryOnly
        )
        if nuspecPaths.Length == 0 {
            return Array.Empty<PackageDependency>()
        }

        document := XDocument.Load(nuspecPaths[0])
        groupTargetFrameworksList := new List<string?>()
        groupDependenciesList := new List<XElement[]>()
        let groupSequence: System.Collections.IEnumerable = document.Descendants()
        groupElements := groupSequence.GetEnumerator()
        try {
            while groupElements.MoveNext() {
                group := groupElements.get_Current() as XElement
                groupName := group.Name
                groupLocalName := groupName.LocalName
                if groupLocalName == "group" {
                    let groupTargetFramework: string? = null
                    targetFrameworkName := XName.Get("targetFramework")
                    targetFrameworkAttribute := group.Attribute(targetFrameworkName)
                    if targetFrameworkAttribute != null {
                        groupTargetFramework = targetFrameworkAttribute.Value
                    }
                    groupTargetFrameworksList.Add(groupTargetFramework)

                    directDependencies := new List<XElement>()
                    let directElements: System.Collections.IEnumerable = group.Elements()
                    CollectElementsByLocalName(directElements, "dependency", directDependencies)
                    groupDependenciesList.Add(directDependencies.ToArray())
                }
            }
        } finally {
            groupDisposable := groupElements as IDisposable
            if groupDisposable != null {
                groupDisposable.Dispose()
            }
        }
        groupTargetFrameworks := groupTargetFrameworksList.ToArray()
        groupDependencies := groupDependenciesList.ToArray()

        let dependencyElements: XElement[] = null
        if groupTargetFrameworks.Length == 0 {
            allDependencies := new List<XElement>()
            let allElements: System.Collections.IEnumerable = document.Descendants()
            CollectElementsByLocalName(allElements, "dependency", allDependencies)
            dependencyElements = allDependencies.ToArray()
        } else {
            bestGroupIndex := CompilationReferenceResolverKernels.SelectBestDependencyGroupIndex(
                groupTargetFrameworks,
                targetFramework
            )
            if bestGroupIndex >= 0 {
                dependencyElements = groupDependencies[bestGroupIndex]
            } else {
                dependencyElements = new XElement[](0)
            }
        }

        rawIds := new string?[](dependencyElements.Length)
        dependencyIndex := 0
        while dependencyIndex < dependencyElements.Length {
            idName := XName.Get("id")
            idAttribute := dependencyElements[dependencyIndex].Attribute(idName)
            if idAttribute != null {
                rawIds[dependencyIndex] = idAttribute.Value
            }
            dependencyIndex = dependencyIndex + 1
        }

        rawVersions := new string?[](dependencyElements.Length)
        dependencyIndex = 0
        while dependencyIndex < dependencyElements.Length {
            versionName := XName.Get("version")
            versionAttribute := dependencyElements[dependencyIndex].Attribute(versionName)
            if versionAttribute != null {
                rawVersions[dependencyIndex] = versionAttribute.Value
            }
            dependencyIndex = dependencyIndex + 1
        }

        return CompilationReferenceResolverKernels.GetPackageDependencies(rawIds, rawVersions)
    }

    private static func SelectBestAssetAssemblies(
        versionDirectory: string,
        assetKind: string,
        targetFramework: string
    ): IReadOnlyList<string> {
        assetRoot := CompilationReferenceResolverKernels.GetNuGetAssetRoot(
            versionDirectory,
            assetKind
        )
        if !Directory.Exists(assetRoot) {
            return Array.Empty<string>()
        }

        candidateDirectories := Directory.GetDirectories(
            assetRoot,
            "*",
            SearchOption.TopDirectoryOnly
        )
        bestDirectory := CompilationReferenceResolverKernels.SelectBestAssetDirectory(
            candidateDirectories,
            targetFramework
        )
        if bestDirectory == null {
            return Array.Empty<string>()
        }
        return CompilationReferenceResolverKernels.SortPathsIgnoreCase(
            Directory.GetFiles(bestDirectory, "*.dll", SearchOption.TopDirectoryOnly)
        )
    }

    private static func AddDllReference(config: ProjectConfig, assemblyPath: string): void {
        if !File.Exists(assemblyPath) {
            return
        }

        fullPath := CompilationReferenceResolverKernels.GetDllReferencePath(assemblyPath)
        if CompilationReferenceResolverKernels.ShouldAddDllReference(config.Dependencies, fullPath) {
            config.Dependencies.Add(new Reference { Dll: fullPath })
        }
    }

    private static func GetGlobalPackagesFolder(): string {
        configuredPackagesFolder := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
        userProfileFolder := Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        return CompilationReferenceResolverKernels.GetGlobalPackagesFolder(
            configuredPackagesFolder,
            userProfileFolder
        )
    }

    private static func FindSharedFrameworkDirectory(
        frameworkName: string,
        targetFramework: string
    ): string? {
        candidates := CompilationReferenceResolverKernels.GetDotnetSharedRootCandidates(
            RuntimeEnvironment.GetRuntimeDirectory()
        )
        candidateIndex := 0
        while candidateIndex < candidates.Length {
            sharedRoot := candidates[candidateIndex]
            if !Directory.Exists(sharedRoot) {
                candidateIndex = candidateIndex + 1
                continue
            }
            frameworkRoot := CompilationReferenceResolverKernels.GetSharedFrameworkRoot(
                sharedRoot,
                frameworkName
            )
            if !Directory.Exists(frameworkRoot) {
                candidateIndex = candidateIndex + 1
                continue
            }

            selectedDirectory := CompilationReferenceResolverKernels.SelectSharedFrameworkDirectory(
                Directory.GetDirectories(frameworkRoot),
                targetFramework
            )
            if selectedDirectory != null {
                return selectedDirectory
            }
            candidateIndex = candidateIndex + 1
        }
        return null
    }
}
