using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Xml.Linq;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal static class CompilationReferenceResolver
{
    private static readonly HttpClient HttpClient = new()
    {
        Timeout = TimeSpan.FromMinutes(2)
    };

    internal static ReferenceResolutionResult AddResolvedDllReferences(
        string projectDir,
        ProjectConfig config,
        ReferenceResolutionOptions? options = null)
    {
        options ??= new ReferenceResolutionOptions();
        var context = new ResolutionContext();
        return ResolveProjectReferences(Path.GetFullPath(projectDir), config, options, context);
    }

    internal static string GetProjectAssemblyName(string projectRoot, ProjectConfig config)
        => CompilationReferenceResolverKernels.GetProjectAssemblyName(projectRoot, config.Name);

    internal static string GetStableOutputDirectory(string projectRoot, ProjectConfig config, string configuration)
        => CompilationReferenceResolverKernels.GetStableOutputDirectory(projectRoot, configuration, config.TargetFramework);

    private static ReferenceResolutionResult ResolveProjectReferences(
        string projectRoot,
        ProjectConfig config,
        ReferenceResolutionOptions options,
        ResolutionContext context)
    {
        projectRoot = Path.GetFullPath(projectRoot);
        var result = new ReferenceResolutionResult();

        AddImplicitTestDependencies(projectRoot, config, options);
        AddImplicitNSharpRuntimeAsset(result);

        foreach (var frameworkDirectory in ResolveFrameworkReferenceDirectories(projectRoot, config))
        {
            foreach (var assemblyPath in Directory.GetFiles(frameworkDirectory, "*.dll", SearchOption.TopDirectoryOnly))
            {
                AddDllReference(config, assemblyPath);
            }
        }

        foreach (var packageReference in CompilationReferenceResolverKernels.GetNuGetReferences(
                     config.Dependencies,
                     config.TestDependencies,
                     options.IncludeTests))
        {
            var packageAssets = ResolveNuGetPackage(
                packageReference.Nuget!,
                packageReference.Version,
                config.TargetFramework,
                context);

            foreach (var assemblyPath in packageAssets.CompileAssemblies)
            {
                AddDllReference(config, assemblyPath);
            }

            foreach (var runtimeAsset in packageAssets.RuntimeAssemblies)
            {
                AddDllReference(config, runtimeAsset);
                result.AddRuntimeAsset(runtimeAsset);
            }
        }

        foreach (var projectReference in CompilationReferenceResolverKernels.FilterReferencesByType(config.Dependencies, ReferenceType.Project))
        {
            if (!options.BuildProjectReferences)
            {
                continue;
            }

            var resolvedProjectReferencePath = CompilationReferenceResolverKernels.ResolveProjectReferencePath(projectRoot, projectReference.Project!);
            var referencedProjectRoot = ProjectReferenceResolver.ResolveNSharpProjectRoot(
                resolvedProjectReferencePath);
            var referencedProjectYml = CompilationReferenceResolverKernels.GetProjectYmlPath(referencedProjectRoot);
            var referencedConfig = ProjectFileParser.Parse(referencedProjectYml);

            var referencedOutput = BuildProjectReference(
                referencedProjectRoot,
                referencedConfig,
                options,
                context);

            AddDllReference(config, referencedOutput.OutputAssemblyPath);
            result.AddRuntimeAsset(referencedOutput.OutputAssemblyPath);
            result.Add(referencedOutput.References);
            config.Dependencies.Remove(projectReference);
        }

        return result;
    }

    private static void AddImplicitNSharpRuntimeAsset(ReferenceResolutionResult result)
    {
        var compilerDirectory = Path.GetDirectoryName(typeof(ProjectConfig).Assembly.Location);
        foreach (var candidate in CompilationReferenceResolverKernels.GetImplicitNSharpRuntimeAssetCandidates(
                     AppContext.BaseDirectory,
                     compilerDirectory))
        {
            if (File.Exists(candidate))
            {
                result.AddRuntimeAsset(candidate);
                return;
            }
        }
    }

    private static ResolvedProjectReference BuildProjectReference(
        string projectRoot,
        ProjectConfig config,
        ReferenceResolutionOptions options,
        ResolutionContext context)
    {
        projectRoot = Path.GetFullPath(projectRoot);
        if (context.ProjectOutputs.TryGetValue(projectRoot, out var cachedOutput))
        {
            return cachedOutput;
        }

        if (context.ActiveProjectRoots.Contains(projectRoot))
        {
            throw new InvalidOperationException(
                CompilationReferenceResolverKernels.GetProjectReferenceCycleMessage(context.ActiveProjectRoots.Append(projectRoot).ToArray()));
        }

        context.ActiveProjectRoots.Push(projectRoot);
        try
        {
            var references = ResolveProjectReferences(
                projectRoot,
                config,
                CompilationReferenceResolverKernels.GetProjectReferenceResolutionOptions(options),
                context);
            var outputDirectory = GetStableOutputDirectory(projectRoot, config, options.Configuration);
            Directory.CreateDirectory(outputDirectory);

            var assemblyName = GetProjectAssemblyName(projectRoot, config);
            var outputPath = Path.Combine(outputDirectory, $"{assemblyName}.dll");
            var compiler = new MultiFileCompiler(projectRoot, config);
            compiler.AotMode = options.AotMode;
            var result = compiler.CompileToIlAssembly(assemblyName, outputPath);
            if (!result.Success || string.IsNullOrWhiteSpace(result.OutputAssemblyPath))
            {
                throw new InvalidOperationException(
                    CompilationReferenceResolverKernels.GetProjectReferenceBuildFailedMessage(
                        CompilationReferenceResolverKernels.GetProjectYmlPath(projectRoot),
                        CompilationReferenceResolverKernels.GetCompilerDiagnosticsText(
                            result.Errors.Select(error => error.Format()).ToArray())));
            }

            if (CompilationReferenceResolverKernels.IsExecutableOutputType(config.OutputType))
            {
                CompilationArtifacts.WriteRuntimeConfig(config, result.OutputAssemblyPath);
            }

            references.CopyRuntimeAssets(outputDirectory);

            var resolved = new ResolvedProjectReference(result.OutputAssemblyPath, references);
            context.ProjectOutputs[projectRoot] = resolved;
            return resolved;
        }
        finally
        {
            _ = context.ActiveProjectRoots.Pop();
        }
    }

    private static void AddImplicitTestDependencies(string projectRoot, ProjectConfig config, ReferenceResolutionOptions options)
    {
        // MECHANICAL-GLUE: filesystem scan and project mutation only; package policy lives in CompilationReferenceResolverKernels.nl.
        var hasTests = Directory.Exists(projectRoot)
            && Directory.GetFiles(projectRoot, "*.tests.nl", SearchOption.AllDirectories).Length > 0;
        var existingPackageIds = CompilationReferenceResolverKernels
            .FilterReferencesByType(config.TestDependencies, ReferenceType.NuGet)
            .Select(reference => reference.Nuget ?? string.Empty)
            .ToArray();
        var plan = CompilationReferenceResolverKernels.GetImplicitTestDependencyPlan(
            options.IncludeTests,
            hasTests,
            config.TestFramework,
            existingPackageIds);
        if (!plan.ShouldAdd)
        {
            return;
        }

        config.TestDependencies.Add(new Reference { Nuget = plan.PackageName, Version = plan.Version });
    }

    private static IReadOnlyList<string> ResolveFrameworkReferenceDirectories(string projectRoot, ProjectConfig config)
    {
        var directories = new List<string>();
        foreach (var frameworkName in CompilationReferenceResolverKernels.GetFrameworkReferenceNames(config.Sdk, config.Dependencies))
        {
            var directory = FindSharedFrameworkDirectory(frameworkName, config.TargetFramework);
            if (directory == null)
            {
                throw new InvalidOperationException(
                    CompilationReferenceResolverKernels.GetFrameworkReferenceNotResolvedMessage(
                        frameworkName,
                        projectRoot,
                        config.TargetFramework));
            }

            directories.Add(directory);
        }

        return directories;
    }

    private static NuGetPackageAssets ResolveNuGetPackage(
        string packageName,
        string? version,
        string targetFramework,
        ResolutionContext context)
    {
        var versionDirectory = EnsurePackageAvailable(packageName, version);
        var declaredIdentity = ReadPackageIdentity(versionDirectory);
        var packageIdentity = CompilationReferenceResolverKernels.ResolveNuGetPackageIdentity(
            versionDirectory,
            packageName,
            declaredIdentity.Id,
            declaredIdentity.Version);
        var key = CompilationReferenceResolverKernels.GetNuGetPackageAssetsCacheKey(
            packageIdentity.Id,
            packageIdentity.Version);

        if (context.PackageAssets.TryGetValue(key, out var cached))
        {
            return cached;
        }

        var assets = new NuGetPackageAssets();
        context.PackageAssets[key] = assets;

        foreach (var dependency in ReadPackageDependencies(versionDirectory, targetFramework))
        {
            var dependencyAssets = ResolveNuGetPackage(
                dependency.Id,
                dependency.Version,
                targetFramework,
                context);
            assets.Add(dependencyAssets);
        }

        foreach (var compileAssembly in SelectBestAssetAssemblies(versionDirectory, "ref", targetFramework)
                     .DefaultIfEmpty()
                     .Where(path => path != null)
                     .Cast<string>())
        {
            assets.CompileAssemblies.Add(compileAssembly);
        }

        var runtimeAssemblies = SelectBestAssetAssemblies(versionDirectory, "lib", targetFramework);
        foreach (var runtimeAssembly in runtimeAssemblies)
        {
            assets.RuntimeAssemblies.Add(runtimeAssembly);
        }

        if (CompilationReferenceResolverKernels.ShouldUseRuntimeAssembliesForCompile(assets.CompileAssemblies.Count))
        {
            foreach (var runtimeAssembly in runtimeAssemblies)
            {
                assets.CompileAssemblies.Add(runtimeAssembly);
            }
        }

        return assets;
    }

    private static string EnsurePackageAvailable(string packageName, string? version)
    {
        var packagesRoot = GetGlobalPackagesFolder();
        var packageDirectory = CompilationReferenceResolverKernels.GetNuGetPackageDirectory(packagesRoot, packageName);

        if (version == null && Directory.Exists(packageDirectory))
        {
            var installedVersions = Directory.GetDirectories(packageDirectory)
                .Select(Path.GetFileName)
                .Where(name => !string.IsNullOrWhiteSpace(name))
                .Cast<string>()
                .ToArray();

            var bestVersionIndex = CompilationReferenceResolverKernels.SelectBestNuGetVersionIndex(installedVersions);
            if (bestVersionIndex >= 0)
            {
                return Path.Combine(packageDirectory, installedVersions[bestVersionIndex]);
            }
        }

        var resolvedVersion = version ?? GetLatestPackageVersion(packageName);
        var versionDirectory = CompilationReferenceResolverKernels.GetNuGetPackageVersionDirectory(packageDirectory, resolvedVersion);
        if (Directory.Exists(versionDirectory))
        {
            return versionDirectory;
        }

        DownloadPackage(packageName, resolvedVersion, versionDirectory);
        return versionDirectory;
    }

    private static string GetLatestPackageVersion(string packageName)
    {
        var indexUrl = CompilationReferenceResolverKernels.GetNuGetIndexUrl(packageName);
        using var document = JsonDocument.Parse(HttpClient.GetStringAsync(indexUrl).GetAwaiter().GetResult());
        var versions = document.RootElement.GetProperty("versions")
            .EnumerateArray()
            .Select(element => element.GetString())
            .Where(version => !string.IsNullOrWhiteSpace(version))
            .Cast<string>()
            .ToArray();

        var latestVersionIndex = CompilationReferenceResolverKernels.SelectLatestNuGetVersionIndex(versions);
        if (latestVersionIndex >= 0)
            return versions[latestVersionIndex];

        throw new InvalidOperationException(CompilationReferenceResolverKernels.GetNuGetNoPublishedVersionsMessage(packageName));
    }

    private static void DownloadPackage(string packageName, string version, string versionDirectory)
    {
        var url = CompilationReferenceResolverKernels.GetNuGetPackageDownloadUrl(packageName, version);
        var tempDirectory = Path.Combine(Path.GetTempPath(), $"nlc-nuget-{Guid.NewGuid():N}");
        var packagePath = Path.Combine(tempDirectory, CompilationReferenceResolverKernels.GetNuGetPackageFileName(packageName, version));

        try
        {
            Directory.CreateDirectory(tempDirectory);
            var bytes = HttpClient.GetByteArrayAsync(url).GetAwaiter().GetResult();
            File.WriteAllBytes(packagePath, bytes);

            Directory.CreateDirectory(Path.GetDirectoryName(versionDirectory)!);
            var extractDirectory = versionDirectory + $".{Guid.NewGuid():N}.tmp";
            ZipFile.ExtractToDirectory(packagePath, extractDirectory);

            if (Directory.Exists(versionDirectory))
            {
                Directory.Delete(extractDirectory, recursive: true);
            }
            else
            {
                Directory.Move(extractDirectory, versionDirectory);
            }
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                CompilationReferenceResolverKernels.GetNuGetRestoreFailedMessage(packageName, version, ex.Message),
                ex);
        }
        finally
        {
            try { Directory.Delete(tempDirectory, recursive: true); } catch { }
        }
    }

    private static PackageIdentity ReadPackageIdentity(string versionDirectory)
    {
        var nuspecPath = Directory.GetFiles(versionDirectory, "*.nuspec", SearchOption.TopDirectoryOnly)
            .FirstOrDefault();
        if (nuspecPath == null)
        {
            return CompilationReferenceResolverKernels.GetFallbackNuGetPackageIdentity(versionDirectory);
        }

        var document = XDocument.Load(nuspecPath);
        var metadata = document.Descendants().FirstOrDefault(element => element.Name.LocalName == "metadata");
        return new PackageIdentity(
            metadata?.Elements().FirstOrDefault(element => element.Name.LocalName == "id")?.Value,
            metadata?.Elements().FirstOrDefault(element => element.Name.LocalName == "version")?.Value);
    }

    private static IReadOnlyList<PackageDependency> ReadPackageDependencies(string versionDirectory, string targetFramework)
    {
        var nuspecPath = Directory.GetFiles(versionDirectory, "*.nuspec", SearchOption.TopDirectoryOnly)
            .FirstOrDefault();
        if (nuspecPath == null)
        {
            return Array.Empty<PackageDependency>();
        }

        var document = XDocument.Load(nuspecPath);
        var dependencyGroups = document.Descendants()
            .Where(element => element.Name.LocalName == "group")
            .Select(group => new
            {
                TargetFramework = (string?)group.Attribute("targetFramework"),
                Dependencies = group.Elements().Where(element => element.Name.LocalName == "dependency").ToArray()
            })
            .ToArray();

        IEnumerable<XElement> dependencies;
        if (dependencyGroups.Length == 0)
        {
            dependencies = document.Descendants().Where(element => element.Name.LocalName == "dependency");
        }
        else
        {
            // MECHANICAL-GLUE: XDocument flatten only; group compatibility lives in CompilationReferenceResolverKernels.nl.
            var groupTargetFrameworks = dependencyGroups
                .Select(group => group.TargetFramework)
                .ToArray();
            var bestGroupIndex = CompilationReferenceResolverKernels.SelectBestDependencyGroupIndex(
                groupTargetFrameworks,
                targetFramework);
            dependencies = bestGroupIndex >= 0
                ? dependencyGroups[bestGroupIndex].Dependencies
                : Array.Empty<XElement>();
        }

        return dependencies
            .Select(element => new PackageDependency(
                (string?)element.Attribute("id") ?? string.Empty,
                CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion(
                    (string?)element.Attribute("version"))))
            .Where(dependency => !string.IsNullOrWhiteSpace(dependency.Id))
            .ToArray();
    }

    private static IReadOnlyList<string> SelectBestAssetAssemblies(
        string versionDirectory,
        string assetKind,
        string targetFramework)
    {
        var assetRoot = Path.Combine(versionDirectory, assetKind);
        if (!Directory.Exists(assetRoot))
        {
            return Array.Empty<string>();
        }

        // MECHANICAL-GLUE: directory and file enumeration only; compatibility and ordering live in CompilationReferenceResolverKernels.nl.
        var candidateDirectories = Directory.GetDirectories(assetRoot, "*", SearchOption.TopDirectoryOnly);
        var candidateFrameworks = candidateDirectories
            .Select(directory => Path.GetFileName(directory) ?? string.Empty)
            .ToArray();
        var bestDirectoryIndex = CompilationReferenceResolverKernels.SelectBestAssetDirectoryIndex(
            candidateFrameworks,
            targetFramework);
        var bestDirectory = bestDirectoryIndex >= 0
            ? candidateDirectories[bestDirectoryIndex]
            : null;

        return bestDirectory == null
            ? Array.Empty<string>()
            : CompilationReferenceResolverKernels.SortPathsIgnoreCase(
                Directory.GetFiles(bestDirectory, "*.dll", SearchOption.TopDirectoryOnly));
    }

    private static void AddDllReference(ProjectConfig config, string assemblyPath)
    {
        if (!File.Exists(assemblyPath))
        {
            return;
        }

        var fullPath = Path.GetFullPath(assemblyPath);
        if (CompilationReferenceResolverKernels.ShouldAddDllReference(config.Dependencies, fullPath))
        {
            config.Dependencies.Add(new Reference { Dll = fullPath });
        }
    }

    private static string GetGlobalPackagesFolder()
        => CompilationReferenceResolverKernels.GetGlobalPackagesFolder(
            Environment.GetEnvironmentVariable("NUGET_PACKAGES"),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));

    private static string? FindSharedFrameworkDirectory(string frameworkName, string targetFramework)
    {
        var targetVersion = CompilationReferenceResolverKernels.ParseTargetFrameworkVersion(targetFramework);
        foreach (var sharedRoot in EnumerateDotnetSharedRoots())
        {
            var frameworkRoot = Path.Combine(sharedRoot, frameworkName);
            if (!Directory.Exists(frameworkRoot))
            {
                continue;
            }

            // MECHANICAL-GLUE: directory enumeration only; version parsing and selection live in CompilationReferenceResolverKernels.nl.
            var candidateDirectories = Directory.GetDirectories(frameworkRoot);
            var candidateVersions = candidateDirectories
                .Select(directory => Path.GetFileName(directory) ?? string.Empty)
                .ToArray();
            var selectedIndex = CompilationReferenceResolverKernels.SelectSharedFrameworkDirectoryIndex(
                candidateVersions,
                targetVersion);
            if (selectedIndex >= 0)
            {
                return candidateDirectories[selectedIndex];
            }
        }

        return null;
    }

    private static IEnumerable<string> EnumerateDotnetSharedRoots()
    {
        // MECHANICAL-GLUE: runtime probing and existence filter only; ordering and dedupe live in CompilationReferenceResolverKernels.nl.
        foreach (var root in CompilationReferenceResolverKernels.GetDotnetSharedRootCandidates(RuntimeEnvironment.GetRuntimeDirectory()))
        {
            if (Directory.Exists(root))
            {
                yield return root;
            }
        }
    }

}
