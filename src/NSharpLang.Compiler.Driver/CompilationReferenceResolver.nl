namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.IO.Compression
import System.Net.Http
import System.Reflection
import System.Runtime.InteropServices
import System.Text
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
        context := resolvedOptions.WorkspaceContext ?? new ResolutionContext(resolvedOptions.PackagesFolder)
        projectRoot := CompilationReferenceResolverKernels.GetProjectRoot(projectDir)
        context.ResolutionGate.Wait()
        try {
            return ResolveProjectReferences(projectRoot, config, resolvedOptions, context)
        } finally {
            context.ResolutionGate.Release()
        }
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
        if options.BuildProjectReferences {
            ProjectReferenceFlow.AddTransitiveFrameworkReferences(projectRoot, config)
        }

        frameworkDirectories := ResolveFrameworkReferenceDirectories(projectRoot, config)
        for frameworkDirectory in frameworkDirectories {
            assemblyPaths := Directory.GetFiles(frameworkDirectory, "*.dll", SearchOption.TopDirectoryOnly)
            assemblyIndex := 0
            while assemblyIndex < assemblyPaths.Length {
                AddDllReference(config, assemblyPaths[assemblyIndex])
                assemblyIndex = assemblyIndex + 1
            }
        }

        packageReferences := CompilationReferenceResolverKernels.GetNuGetReferences(
            config.Dependencies,
            config.TestDependencies,
            options.IncludeTests
        )
        // THE VERSION OF EVERY PACKAGE IN THE CLOSURE IS DECIDED BEFORE ANY ASSET IS TAKEN.
        // Project-level direct references win first. Each root subgraph then applies nearest-wins;
        // cousin requests are unified by their highest minimum version. The selection repeats from
        // the roots until stable, so losing package versions cannot leave their dependencies in the
        // map consumed by the asset walk below.
        selectedVersions := SelectNuGetPackageVersions(packageReferences, config.TargetFramework, context.PackagesRoot)
        selectedVersionsKey := SelectedNuGetVersionsCacheKey(selectedVersions)

        for packageReference in packageReferences {
            // A NuGet reference always names its package (`Reference.Type` answers NuGet only for a
            // named one); the version selection above skips an unnamed one the same way.
            packageName := packageReference.Nuget
            if packageName == null {
                continue
            }

            packageAssets := ResolveNuGetPackage(
                packageName,
                packageReference.Version,
                config.TargetFramework,
                context,
                selectedVersions,
                selectedVersionsKey
            )

            for assemblyPath in packageAssets.CompileAssemblies {
                AddDllReference(config, assemblyPath)
                result.AddCompileReference(assemblyPath)
            }

            for runtimeAsset in packageAssets.RuntimeAssemblies {
                AddDllReference(config, runtimeAsset)
                result.AddCompileReference(runtimeAsset)
                result.AddRuntimeAsset(runtimeAsset)
            }

            for packageFile in packageAssets.RuntimeFiles {
                result.AddPackageFile(packageFile)
            }
        }

        projectReferences := CompilationReferenceResolverKernels.FilterReferencesByType(
            config.Dependencies,
            ReferenceType.Project
        )
        ownDllReferences := ProjectReferenceFlow.SnapshotDllReferences(config)
        projectIndex := 0
        while projectIndex < projectReferences.Count {
            projectReference := projectReferences[projectIndex]
            projectPath := projectReference.Project
            if !options.BuildProjectReferences || projectPath == null {
                projectIndex = projectIndex + 1
                continue
            }

            resolvedProjectReferencePath := CompilationReferenceResolverKernels.ResolveProjectReferencePath(
                projectRoot,
                projectPath
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
            result.AddProjectOutput(referencedOutput.OutputAssemblyPath)
            // A PROJECT REFERENCE'S OWN PROJECT REFERENCES ARE THIS PROJECT'S REFERENCES TOO, as they
            // are to MSBuild's transitive `ProjectReference`: A -> B -> C lets A name C's types, and
            // `dotnet build` compiles A that way. Before this they reached A only as runtime assets
            // copied beside its output, so `nlc check`/`nlc build` refused a program `dotnet build`
            // compiled -- NL201/NL301 at every C name -- and Compiler.Core's own front door reported
            // 36,701 diagnostics the day Core reached Compiler.Model only through Compiler.Syntax.
            for transitiveOutput in referencedOutput.References.ProjectOutputAssemblies {
                AddDllReference(config, transitiveOutput)
                result.AddProjectOutput(transitiveOutput)
            }
            // THE SAME HOLDS FOR ITS PACKAGES: `PackageReference` flows through a `ProjectReference`
            // at compile time and at run time. A type the referenced project exposes from a package
            // only IT declares (`HtmlDocument` from HtmlAgilityPack) must bind in this project's
            // compilation, and the package's files are copied beside this project's output
            // (`result.Add` below carries them).
            for transitiveCompileReference in referencedOutput.References.CompileReferences {
                ProjectReferenceFlow.AddFlowedCompileReference(config, ownDllReferences, transitiveCompileReference)
            }
            result.AddRuntimeAsset(referencedOutput.OutputAssemblyPath)
            // `WebApplicationFactory<TEntryPoint>` reads the application's own `<app>.deps.json` from the
            // TEST output directory; Microsoft.AspNetCore.Mvc.Testing's MSBuild targets copy it there
            // and so does this.
            if CompilationReferenceResolverKernels.FlowsReferencedDependencyManifest(selectedVersions) {
                result.AddRuntimeAsset(Path.ChangeExtension(referencedOutput.OutputAssemblyPath, ".deps.json"))
                // ...and it finds the application's content root (its views, `wwwroot`, settings) through
                // `MvcTestingAppManifest.json`: the application's assembly name -> its project directory.
                result.AddContentRoot(
                    AssemblyName.GetAssemblyName(referencedOutput.OutputAssemblyPath).FullName,
                    referencedProjectRoot
                )
            }
            result.Add(referencedOutput.References)
            config.Dependencies.Remove(projectReference)
            projectIndex = projectIndex + 1
        }

        return result
    }

    private static func AddImplicitNSharpRuntimeAsset(result: ReferenceResolutionResult): void {
        compilerDirectory := CompilationReferenceResolverKernels.GetCompilerAssemblyDirectory(
            typeof(ProjectConfig).Assembly.Location
        )
        candidates := CompilationReferenceResolverKernels.GetImplicitNSharpRuntimeAssetCandidates(
            AppContext.BaseDirectory,
            compilerDirectory
        )
        for candidate in candidates {
            if File.Exists(candidate) {
                result.AddRuntimeAsset(candidate)
                return
            }
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

        if context.CacheProjectFailures {
            let cachedFailure: string? = null
            if context.ProjectFailures.TryGetValue(projectRoot, out cachedFailure) && cachedFailure != null {
                throw new InvalidOperationException(cachedFailure)
            }
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

        if options.UseBuiltProjectReferences {
            return LocateBuiltProjectReference(projectRoot, config, options, context)
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
            compiler.EmitReferenceAssembly = options.EmitReferenceAssembly
            if context.CompilesConcurrently {
                compiler.Workers = 1
            }
            // A referenced project's output lives in its own stable directory, so an unchanged
            // reference is answered from its up-to-date stamp instead of being rebuilt.
            compiler.IncrementalBuild = true
            compilationResult := compiler.CompileToIlAssembly(
                assemblyName,
                outputPath,
                false,
                true
            )
            builtAssemblyPath := compilationResult.OutputAssemblyPath
            if builtAssemblyPath == null || CompilationReferenceResolverKernels.ShouldTreatProjectReferenceBuildAsFailed(
                compilationResult.Success,
                builtAssemblyPath
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
                CompilationArtifacts.WriteRuntimeConfig(config, builtAssemblyPath)
            }

            references.CopyRuntimeAssets(outputDirectory)
            DependencyManifestWriter.Write(config, references, builtAssemblyPath)
            resolvedOutput = new ResolvedProjectReference(
                builtAssemblyPath,
                references
            )
            context.ProjectOutputs[projectRoot] = resolvedOutput
        } catch ex: Exception {
            // Workspace members can share a failing transitive project reference. Remember the
            // failure for this resolution context so every dependent receives the same result
            // without rebuilding the same project graph (and producing the same diagnostics) again.
            if context.CacheProjectFailures {
                context.ProjectFailures[projectRoot] = ex.Message
            }
            throw
        } finally {
            context.ActiveProjectRoots.Pop()
        }
        return resolvedOutput
    }

    // THE REFERENCE AS ITS OWN BUILD LEFT IT (`ReferenceResolutionOptions.UseBuiltProjectReferences`).
    // Nothing is compiled and nothing is written: the assembly is read where that project's build put
    // it, its own `project:` references are located the same way, and its package references resolve
    // as they always do, so the consumer sees the same transitive closure a source build would give
    // it. Missing and out-of-date assemblies are refused by name.
    private static func LocateBuiltProjectReference(
        projectRoot: string,
        config: ProjectConfig,
        options: ReferenceResolutionOptions,
        context: ResolutionContext
    ): ResolvedProjectReference {
        context.ActiveProjectRoots.Push(projectRoot)
        let resolvedOutput: ResolvedProjectReference = null
        try {
            projectYml := CompilationReferenceResolverKernels.GetProjectYmlPath(projectRoot)
            assemblyPath := CompilationReferenceResolverKernels.GetProjectOutputAssemblyPath(
                GetStableOutputDirectory(projectRoot, config, options.Configuration),
                GetProjectAssemblyName(projectRoot, config)
            )
            if !File.Exists(assemblyPath) {
                throw new InvalidOperationException(
                    CompilationReferenceResolverKernels.GetProjectReferenceNotBuiltMessage(projectYml, assemblyPath)
                )
            }

            newerSource := CompilationReferenceResolverKernels.FindProductSourceNewerThan(projectRoot, assemblyPath)
            if newerSource != null {
                throw new InvalidOperationException(
                    CompilationReferenceResolverKernels.GetProjectReferenceStaleMessage(projectYml, assemblyPath, newerSource)
                )
            }

            references := ResolveProjectReferences(
                projectRoot,
                config,
                CompilationReferenceResolverKernels.GetProjectReferenceResolutionOptions(options),
                context
            )
            resolvedOutput = new ResolvedProjectReference(assemblyPath, references)
            context.ProjectOutputs[projectRoot] = resolvedOutput
        } finally {
            context.ActiveProjectRoots.Pop()
        }
        return resolvedOutput
    }

    private static func FormatCompilerDiagnostics(errors: IEnumerable<CompilerError>): string[] {
        formattedDiagnostics := new List<string>()
        errorEnumerator := errors.GetEnumerator()
        // `MoveNext` is declared on the non-generic interface every `IEnumerator<T>` extends, so the
        // enumerator is read through that one: an upcast, which cannot fail.
        movement := errorEnumerator as System.Collections.IEnumerator
        try {
            while movement.MoveNext() {
                error := errorEnumerator.get_Current()
                formattedDiagnostics.Add(error.Format(false))
            }
        } finally {
            disposable := errorEnumerator as IDisposable
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
        if options.TestSourcesPresent != null {
            hasTests = options.TestSourcesPresent ?? false
        } else if options.IncludeTests && Directory.Exists(projectRoot) {
            for sourceFile in config.GetSourceFiles(projectRoot, true) {
                if sourceFile.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase) {
                    hasTests = true
                    break
                }
            }
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

    // The shared-framework directory each `framework:` reference (and a Web SDK's implicit one)
    // names, selected by the project's TFM. Compilation references every assembly in these
    // directories; `nlc test` probes the SAME directories when the test assembly it runs in-process
    // asks for a framework assembly, so a test executes against exactly what it was compiled against.
    static func ResolveFrameworkReferenceDirectories(
        projectRoot: string,
        config: ProjectConfig
    ): IReadOnlyList<string> {
        directories := new List<string>()
        frameworkNames := CompilationReferenceResolverKernels.GetFrameworkReferenceNames(
            config.Sdk,
            config.Dependencies
        )
        for frameworkName in frameworkNames {
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
        }
        return directories
    }

    // ── PACKAGE GRAPH SELECTION ─────────────────────────────────────────────────────────────────
    //
    // NuGet resolves direct project references first, nearest occurrences inside each root
    // subgraph next, then cousin requests across subgraphs to the lowest version satisfying their
    // lower bounds (the highest requested lower bound here). Each pass walks only the edges of the
    // selected package versions. Repeating from the roots matters: when a cousin winner replaces a
    // package, dependencies declared only by its losing version must disappear before the next
    // package's cousin set is computed.
    private static func SelectNuGetPackageVersions(
        packageReferences: List<Reference>,
        targetFramework: string,
        packagesRoot: string
    ): Dictionary<string, string> {
        directVersions := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        for rootReference in packageReferences {
            rootName := rootReference.Nuget
            if rootName == null {
                continue
            }

            normalizedId := CompilationReferenceResolverKernels.NormalizeNuGetPackageId(rootName ?? "")
            versionDirectory := EnsurePackageAvailable(packagesRoot, rootName ?? "", rootReference.Version)
            candidateVersion := CompilationReferenceResolverKernels.GetInstalledNuGetPackageVersion(versionDirectory)
            let selectedVersion: string = ""
            hasSelection := directVersions.TryGetValue(normalizedId, out selectedVersion)
            if CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(
                hasSelection,
                selectedVersion,
                hasSelection,
                candidateVersion,
                true
            ) {
                directVersions[normalizedId] = candidateVersion
            }
        }

        selectedVersions := new Dictionary<string, string>(directVersions, StringComparer.OrdinalIgnoreCase)
        seenClosures := new HashSet<string>(StringComparer.Ordinal)
        closureKey := SelectedNuGetVersionsCacheKey(selectedVersions)
        seenClosures.Add(closureKey)
        while true {
            nextVersions := new Dictionary<string, string>(directVersions, StringComparer.OrdinalIgnoreCase)
            for rootReference in packageReferences {
                rootName := rootReference.Nuget
                if rootName == null {
                    continue
                }

                branchVersions := SelectNuGetPackageBranch(
                    rootName ?? "",
                    rootReference.Version,
                    targetFramework,
                    packagesRoot,
                    selectedVersions,
                    directVersions
                )
                for branchEntry in branchVersions {
                    if directVersions.ContainsKey(branchEntry.Key) {
                        continue
                    }

                    let selectedVersion: string = ""
                    hasSelection := nextVersions.TryGetValue(branchEntry.Key, out selectedVersion)
                    if CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(
                        hasSelection,
                        selectedVersion,
                        false,
                        branchEntry.Value,
                        false
                    ) {
                        nextVersions[branchEntry.Key] = branchEntry.Value
                    }
                }
            }

            nextKey := SelectedNuGetVersionsCacheKey(nextVersions)
            if nextKey == closureKey {
                return nextVersions
            }
            if !seenClosures.Add(nextKey) {
                throw new InvalidOperationException("NuGet package dependency selection did not converge after recomputing the winning package closure.")
            }

            selectedVersions = nextVersions
            closureKey = nextKey
        }
    }

    private static func SelectNuGetPackageBranch(
        rootPackageName: string,
        rootVersion: string?,
        targetFramework: string,
        packagesRoot: string,
        selectedVersions: Dictionary<string, string>,
        directVersions: Dictionary<string, string>
    ): Dictionary<string, string> {
        branchVersions := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        pending := new List<PackageResolutionNode>()
        pending.Add(new PackageResolutionNode(rootPackageName, rootVersion, 0))
        cursor := 0

        while cursor < pending.Count {
            depth := pending[cursor].Depth
            layerEnd := cursor
            while layerEnd < pending.Count && pending[layerEnd].Depth == depth {
                layerEnd = layerEnd + 1
            }

            layerNodes := new Dictionary<string, PackageResolutionNode>(StringComparer.OrdinalIgnoreCase)
            layerVersions := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            nodeIndex := cursor
            while nodeIndex < layerEnd {
                node := pending[nodeIndex]
                nodeIndex = nodeIndex + 1
                normalizedId := CompilationReferenceResolverKernels.NormalizeNuGetPackageId(node.Id)
                if branchVersions.ContainsKey(normalizedId) {
                    continue
                }

                candidateDirectory := EnsurePackageAvailable(packagesRoot, node.Id, node.Version)
                candidateVersion := CompilationReferenceResolverKernels.GetInstalledNuGetPackageVersion(candidateDirectory)
                let selectedLayerVersion: string = ""
                if layerVersions.TryGetValue(normalizedId, out selectedLayerVersion) {
                    if CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(
                        true,
                        selectedLayerVersion,
                        false,
                        candidateVersion,
                        false
                    ) {
                        layerVersions[normalizedId] = candidateVersion
                        layerNodes[normalizedId] = node
                    }
                } else {
                    layerVersions[normalizedId] = candidateVersion
                    layerNodes[normalizedId] = node
                }
            }

            nextLayer := new List<PackageResolutionNode>()
            for layerEntry in layerNodes {
                normalizedId := layerEntry.Key
                branchVersions[normalizedId] = layerVersions[normalizedId]

                expansionVersion := layerVersions[normalizedId]
                let directVersion: string = ""
                if directVersions.TryGetValue(normalizedId, out directVersion) {
                    expansionVersion = directVersion
                } else {
                    let selectedVersion: string = ""
                    if selectedVersions.TryGetValue(normalizedId, out selectedVersion) && !CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(
                        true,
                        selectedVersion,
                        false,
                        expansionVersion,
                        false
                    ) {
                        expansionVersion = selectedVersion
                    }
                }

                versionDirectory := EnsurePackageAvailable(packagesRoot, layerEntry.Value.Id, expansionVersion)
                dependencies := ReadPackageDependencies(versionDirectory, targetFramework)
                for dependency in dependencies {
                    nextLayer.Add(new PackageResolutionNode(dependency.Id, dependency.Version, depth + 1))
                }
            }

            pending.AddRange(nextLayer)
            cursor = layerEnd
        }

        return branchVersions
    }

    private static func ResolveNuGetPackage(
        packageName: string,
        version: string?,
        targetFramework: string,
        context: ResolutionContext,
        selectedVersions: Dictionary<string, string>,
        selectedVersionsKey: string
    ): NuGetPackageAssets {
        resolvedVersion := version
        let selectedVersion: string = ""
        if selectedVersions.TryGetValue(
            CompilationReferenceResolverKernels.NormalizeNuGetPackageId(packageName),
            out selectedVersion
        ) {
            resolvedVersion = selectedVersion
        }

        versionDirectory := EnsurePackageAvailable(context.PackagesRoot, packageName, resolvedVersion)
        declaredIdentity := ReadPackageIdentity(versionDirectory)
        packageIdentity := CompilationReferenceResolverKernels.ResolveNuGetPackageIdentity(
            versionDirectory,
            packageName,
            declaredIdentity.Id,
            declaredIdentity.Version
        )
        key := CompilationReferenceResolverKernels.GetNuGetPackageAssetsCacheKey(
            packageIdentity.Id,
            packageIdentity.Version,
            targetFramework,
            selectedVersionsKey
        )

        let cached: NuGetPackageAssets? = null
        if context.PackageAssets.TryGetValue(key, out cached) {
            return cached
        }

        assets := new NuGetPackageAssets()
        context.PackageAssets[key] = assets

        dependencies := ReadPackageDependencies(versionDirectory, targetFramework)
        for dependency in dependencies {
            dependencyAssets := ResolveNuGetPackage(
                dependency.Id,
                dependency.Version,
                targetFramework,
                context,
                selectedVersions,
                selectedVersionsKey
            )
            assets.Add(dependencyAssets)
        }

        compileAssemblies := SelectBestAssetAssemblies(versionDirectory, "ref", targetFramework)
        for compileAssembly in compileAssemblies {
            assets.CompileAssemblies.Add(compileAssembly)
        }

        runtimeAssemblies := SelectBestAssetAssemblies(versionDirectory, "lib", targetFramework)
        runtimeIndex := 0
        while runtimeIndex < runtimeAssemblies.Count {
            assets.RuntimeAssemblies.Add(runtimeAssemblies[runtimeIndex])
            runtimeIndex = runtimeIndex + 1
        }

        runtimeFiles := NuGetRuntimeAssetSelector.Select(
            packageIdentity.Id ?? packageName,
            packageIdentity.Version ?? Path.GetFileName(versionDirectory),
            versionDirectory,
            targetFramework,
            runtimeAssemblies
        )
        for runtimeFile in runtimeFiles {
            assets.AddRuntimeFile(runtimeFile)
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

    private static func SelectedNuGetVersionsCacheKey(selectedVersions: Dictionary<string, string>): string {
        names := new string[selectedVersions.Count]
        index := 0
        for entry in selectedVersions {
            names[index] = entry.Key
            index = index + 1
        }
        Array.Sort(names, 0, names.Length, StringComparer.OrdinalIgnoreCase)

        builder := new StringBuilder()
        for name in names {
            let selectedVersion: string = ""
            if selectedVersions.TryGetValue(name, out selectedVersion) {
                builder.Append(name.ToLowerInvariant())
                builder.Append('@')
                builder.Append(selectedVersion)
                builder.Append(';')
            }
        }
        return builder.ToString()
    }

    private static func EnsurePackageAvailable(packagesRoot: string, packageName: string, version: string?): string {
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
        request := new HttpRequestMessage(HttpMethod.Get, indexUrl)
        response := client.Send(request)
        let responseText: string = ""
        try {
            response.EnsureSuccessStatusCode()
            reader := new StreamReader(response.Content.ReadAsStream())
            try {
                responseText = reader.ReadToEnd()
            } finally {
                reader.Dispose()
            }
        } finally {
            response.Dispose()
            request.Dispose()
        }
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
            request := new HttpRequestMessage(HttpMethod.Get, url)
            response := client.Send(request)
            let bytes: byte[] = new byte[](0)
            try {
                response.EnsureSuccessStatusCode()
                contentStream := response.Content.ReadAsStream()
                memory := new MemoryStream()
                try {
                    contentStream.CopyTo(memory)
                    bytes = memory.ToArray()
                } finally {
                    memory.Dispose()
                    contentStream.Dispose()
                }
            } finally {
                response.Dispose()
                request.Dispose()
            }
            File.WriteAllBytes(packagePath, bytes)

            parentDirectory := CompilationReferenceResolverKernels.GetNuGetPackageParentDirectory(
                versionDirectory
            )
            if parentDirectory == null {
                throw new InvalidOperationException("The NuGet package version directory has no parent directory.")
            }

            Directory.CreateDirectory(parentDirectory)
            extractDirectory := CompilationReferenceResolverKernels.GetNuGetExtractDirectory(
                versionDirectory,
                Guid.NewGuid().ToString("N")
            )
            ZipFile.ExtractToDirectory(packagePath, extractDirectory)

            // NUGET'S INSTALL MARKERS, WRITTEN BEFORE THE DIRECTORY IS PUBLISHED. The extracted
            // content alone is not an install: `dotnet restore` decides a version directory holds
            // a package by the `.nupkg` and its `.sha512` beside the content, and answers NU1101
            // for a directory that carries neither. Both doors share this folder, so writing them
            // here is what makes that cache mean the same thing to both. They go into the staging
            // directory so the move that publishes the version directory publishes a COMPLETE
            // install, never a half-marked one another process could read.
            File.WriteAllBytes(
                CompilationReferenceResolverKernels.GetInstalledNuGetPackagePath(
                    extractDirectory,
                    packageName,
                    version
                ),
                bytes
            )
            File.WriteAllText(
                CompilationReferenceResolverKernels.GetInstalledNuGetPackageHashPath(
                    extractDirectory,
                    packageName,
                    version
                ),
                CompilationReferenceResolverKernels.GetNuGetPackageContentHash(bytes)
            )

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
                if element == null {
                    continue
                }
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
                if element == null {
                    continue
                }
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
                if group == null {
                    continue
                }
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
