using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Xml.Linq;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal sealed record ReferenceResolutionOptions(
    string Configuration = "Debug",
    bool IncludeTests = false,
    bool BuildProjectReferences = true,
    bool Quiet = false,
    bool AotMode = false);

internal sealed class ReferenceResolutionResult
{
    private readonly HashSet<string> _runtimeAssets = new(StringComparer.OrdinalIgnoreCase);

    public IReadOnlyList<string> RuntimeAssets => _runtimeAssets
        .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
        .ToArray();

    public void AddRuntimeAsset(string path)
    {
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
        {
            _runtimeAssets.Add(Path.GetFullPath(path));
        }
    }

    public void Add(ReferenceResolutionResult other)
    {
        foreach (var asset in other.RuntimeAssets)
        {
            AddRuntimeAsset(asset);
        }
    }

    public void CopyRuntimeAssets(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);

        foreach (var asset in RuntimeAssets)
        {
            var destination = Path.Combine(outputDirectory, Path.GetFileName(asset));
            if (string.Equals(Path.GetFullPath(asset), Path.GetFullPath(destination), StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            File.Copy(asset, destination, overwrite: true);
        }
    }
}

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
        => !string.IsNullOrWhiteSpace(config.Name)
            ? config.Name!
            : Path.GetFileName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(projectRoot))) ?? "Project";

    internal static string GetStableOutputDirectory(string projectRoot, ProjectConfig config, string configuration)
        => Path.Combine(projectRoot, "bin", configuration, config.TargetFramework);

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

        foreach (var packageReference in EnumerateNuGetReferences(config, options).ToArray())
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

            var resolvedProjectReferencePath = ResolveProjectReferencePath(projectRoot, projectReference.Project!);
            var referencedProjectRoot = ProjectReferenceResolver.ResolveNSharpProjectRoot(
                resolvedProjectReferencePath);
            var referencedProjectYml = Path.Combine(referencedProjectRoot, "project.yml");
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
        foreach (var candidate in GetImplicitNSharpRuntimeAssetCandidates())
        {
            if (File.Exists(candidate))
            {
                result.AddRuntimeAsset(candidate);
                return;
            }
        }
    }

    private static IEnumerable<string> GetImplicitNSharpRuntimeAssetCandidates()
    {
        yield return Path.Combine(AppContext.BaseDirectory, "NSharpLang.Runtime.dll");

        var compilerDirectory = Path.GetDirectoryName(typeof(ProjectConfig).Assembly.Location);
        if (!string.IsNullOrWhiteSpace(compilerDirectory))
        {
            yield return Path.Combine(compilerDirectory, "NSharpLang.Runtime.dll");
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
            var chain = string.Join(" -> ", context.ActiveProjectRoots.Append(projectRoot));
            throw new InvalidOperationException(
                $"Project reference cycle detected: {chain}. Break the cycle in project.yml dependencies.");
        }

        context.ActiveProjectRoots.Push(projectRoot);
        try
        {
            var references = ResolveProjectReferences(projectRoot, config, options with { IncludeTests = false }, context);
            var outputDirectory = GetStableOutputDirectory(projectRoot, config, options.Configuration);
            Directory.CreateDirectory(outputDirectory);

            var assemblyName = GetProjectAssemblyName(projectRoot, config);
            var outputPath = Path.Combine(outputDirectory, $"{assemblyName}.dll");
            var compiler = new MultiFileCompiler(projectRoot, config);
            compiler.AotMode = options.AotMode;
            var result = compiler.CompileToIlAssembly(assemblyName, outputPath);
            if (!result.Success || string.IsNullOrWhiteSpace(result.OutputAssemblyPath))
            {
                var diagnostics = !result.Errors.Any()
                    ? "No compiler diagnostics were produced."
                    : string.Join(Environment.NewLine, result.Errors.Select(error => error.Format()));
                throw new InvalidOperationException(
                    $"Project reference '{Path.Combine(projectRoot, "project.yml")}' failed to build:{Environment.NewLine}{diagnostics}");
            }

            if (string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase))
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

    private static IEnumerable<Reference> EnumerateNuGetReferences(ProjectConfig config, ReferenceResolutionOptions options)
    {
        foreach (var reference in CompilationReferenceResolverKernels.FilterReferencesByType(config.Dependencies, ReferenceType.NuGet))
        {
            yield return reference;
        }

        if (!options.IncludeTests)
        {
            yield break;
        }

        foreach (var reference in CompilationReferenceResolverKernels.FilterReferencesByType(config.TestDependencies, ReferenceType.NuGet))
        {
            yield return reference;
        }
    }

    private static void AddImplicitTestDependencies(string projectRoot, ProjectConfig config, ReferenceResolutionOptions options)
    {
        if (!options.IncludeTests)
        {
            return;
        }

        var hasTests = Directory.Exists(projectRoot)
            && Directory.GetFiles(projectRoot, "*.tests.nl", SearchOption.AllDirectories).Length > 0;
        if (!hasTests)
        {
            return;
        }

        if (string.Equals(config.TestFramework, "nunit", StringComparison.OrdinalIgnoreCase))
        {
            AddPackageReferenceIfMissing(config.TestDependencies, "NUnit", "4.3.2");
            return;
        }

        AddPackageReferenceIfMissing(config.TestDependencies, "xunit", "2.9.2");
    }

    private static void AddPackageReferenceIfMissing(List<Reference> references, string packageName, string version)
    {
        if (references.Any(reference =>
                reference.Type == ReferenceType.NuGet
                && string.Equals(reference.Nuget, packageName, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        references.Add(new Reference { Nuget = packageName, Version = version });
    }

    private static string ResolveProjectReferencePath(string projectRoot, string projectReference)
        => Path.IsPathRooted(projectReference)
            ? projectReference
            : Path.Combine(projectRoot, projectReference);

    private static IReadOnlyList<string> ResolveFrameworkReferenceDirectories(string projectRoot, ProjectConfig config)
    {
        var frameworkNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (config.Sdk.Contains("Web", StringComparison.OrdinalIgnoreCase))
        {
            frameworkNames.Add("Microsoft.AspNetCore.App");
        }

        foreach (var reference in CompilationReferenceResolverKernels.FilterReferencesByType(config.Dependencies, ReferenceType.Framework))
        {
            frameworkNames.Add(reference.Framework!);
        }

        var directories = new List<string>();
        foreach (var frameworkName in frameworkNames)
        {
            var directory = FindSharedFrameworkDirectory(frameworkName, config.TargetFramework);
            if (directory == null)
            {
                throw new InvalidOperationException(
                    $"Could not resolve framework reference '{frameworkName}' for project '{projectRoot}'. " +
                    $"Install the {frameworkName} runtime for {config.TargetFramework}, or remove the framework reference from project.yml.");
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
        var packageId = ReadPackageIdentity(versionDirectory).Id ?? packageName;
        var packageVersion = ReadPackageIdentity(versionDirectory).Version ?? Path.GetFileName(versionDirectory);
        var key = $"{packageId}@{packageVersion}";

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

        if (assets.CompileAssemblies.Count == 0)
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
        var packageDirectory = Path.Combine(packagesRoot, packageName.ToLowerInvariant());

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
        var versionDirectory = Path.Combine(packageDirectory, resolvedVersion.ToLowerInvariant());
        if (Directory.Exists(versionDirectory))
        {
            return versionDirectory;
        }

        DownloadPackage(packageName, resolvedVersion, versionDirectory);
        return versionDirectory;
    }

    private static string GetLatestPackageVersion(string packageName)
    {
        var packageId = packageName.ToLowerInvariant();
        var indexUrl = $"https://api.nuget.org/v3-flatcontainer/{packageId}/index.json";
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

        throw new InvalidOperationException($"Package '{packageName}' has no published versions on NuGet.org.");
    }

    private static void DownloadPackage(string packageName, string version, string versionDirectory)
    {
        var packageId = packageName.ToLowerInvariant();
        var normalizedVersion = version.ToLowerInvariant();
        var url = $"https://api.nuget.org/v3-flatcontainer/{packageId}/{normalizedVersion}/{packageId}.{normalizedVersion}.nupkg";
        var tempDirectory = Path.Combine(Path.GetTempPath(), $"nlc-nuget-{Guid.NewGuid():N}");
        var packagePath = Path.Combine(tempDirectory, $"{packageId}.{normalizedVersion}.nupkg");

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
                $"Could not restore NuGet package '{packageName}' version '{version}'. " +
                $"Check network access, NuGet.org availability, or pin a version already present in the local NuGet cache. Details: {ex.Message}",
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
            return new PackageIdentity(Path.GetFileName(Path.GetDirectoryName(versionDirectory)), Path.GetFileName(versionDirectory));
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
            var scores = new int[dependencyGroups.Length];
            for (var i = 0; i < dependencyGroups.Length; i++)
                scores[i] = CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore(
                    dependencyGroups[i].TargetFramework,
                    targetFramework);

            var bestGroupIndex = CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, scores.Length);
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

        var candidateDirectories = Directory.GetDirectories(assetRoot, "*", SearchOption.TopDirectoryOnly);
        var scores = new int[candidateDirectories.Length];
        for (var i = 0; i < candidateDirectories.Length; i++)
            scores[i] = CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore(
                Path.GetFileName(candidateDirectories[i]),
                targetFramework);

        var bestDirectoryIndex = CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, scores.Length);
        var bestDirectory = bestDirectoryIndex >= 0
            ? candidateDirectories[bestDirectoryIndex]
            : null;

        return bestDirectory == null
            ? Array.Empty<string>()
            : Directory.GetFiles(bestDirectory, "*.dll", SearchOption.TopDirectoryOnly)
                .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
                .ToArray();
    }

    private static void AddDllReference(ProjectConfig config, string assemblyPath)
    {
        if (!File.Exists(assemblyPath))
        {
            return;
        }

        var fullPath = Path.GetFullPath(assemblyPath);
        var alreadyPresent = config.Dependencies.Any(dependency =>
            dependency.Type == ReferenceType.Dll
            && string.Equals(Path.GetFullPath(dependency.Dll!), fullPath, StringComparison.OrdinalIgnoreCase));

        if (!alreadyPresent)
        {
            config.Dependencies.Add(new Reference { Dll = fullPath });
        }
    }

    private static string GetGlobalPackagesFolder()
    {
        var configured = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(configured);
        }

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".nuget",
            "packages");
    }

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

            var candidates = Directory.GetDirectories(frameworkRoot)
                .Select(directory => new
                {
                    Directory = directory,
                    Version = TryParseVersion(Path.GetFileName(directory))
                })
                .Where(candidate => candidate.Version != null)
                .Select(candidate => new FrameworkCandidate(candidate.Directory, candidate.Version!))
                .ToArray();

            if (candidates.Length == 0)
            {
                continue;
            }

            return SelectSharedFrameworkDirectory(candidates, targetVersion);
        }

        return null;
    }

    private static string SelectSharedFrameworkDirectory(
        FrameworkCandidate[] candidates,
        (bool Parsed, int Major, int Minor) targetVersion)
    {
        var versions = new Version[candidates.Length];
        for (var i = 0; i < candidates.Length; i++)
            versions[i] = candidates[i].Version;

        var targetMajor = targetVersion.Parsed ? targetVersion.Major : (int?)null;
        var dogfoodIndex = CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(
            versions,
            targetMajor);
        if (dogfoodIndex >= 0)
            return candidates[dogfoodIndex].Directory;

        throw new InvalidOperationException("N# reference resolver kernel did not select a shared-framework directory.");
    }

    private static IEnumerable<string> EnumerateDotnetSharedRoots()
    {
        var yielded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var runtimeDirectory = RuntimeEnvironment.GetRuntimeDirectory();
        var current = runtimeDirectory;
        while (!string.IsNullOrWhiteSpace(current))
        {
            if (string.Equals(Path.GetFileName(current), "shared", StringComparison.OrdinalIgnoreCase)
                && Directory.Exists(current)
                && yielded.Add(current))
            {
                yield return current;
            }

            current = Path.GetDirectoryName(current);
        }

        foreach (var root in new[]
                 {
                     "/usr/local/share/dotnet/shared",
                     "/opt/homebrew/share/dotnet/shared",
                     "/usr/share/dotnet/shared"
                 })
        {
            if (Directory.Exists(root) && yielded.Add(root))
            {
                yield return root;
            }
        }
    }

    private static Version? TryParseVersion(string? value)
        => Version.TryParse(value, out var version) ? version : null;

    private sealed class ResolutionContext
    {
        public Dictionary<string, NuGetPackageAssets> PackageAssets { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, ResolvedProjectReference> ProjectOutputs { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Stack<string> ActiveProjectRoots { get; } = new();
    }

    private sealed class NuGetPackageAssets
    {
        public HashSet<string> CompileAssemblies { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> RuntimeAssemblies { get; } = new(StringComparer.OrdinalIgnoreCase);

        public void Add(NuGetPackageAssets other)
        {
            foreach (var assembly in other.CompileAssemblies)
            {
                CompileAssemblies.Add(assembly);
            }

            foreach (var assembly in other.RuntimeAssemblies)
            {
                RuntimeAssemblies.Add(assembly);
            }
        }
    }

    private sealed record PackageIdentity(string? Id, string? Version);
    private sealed record PackageDependency(string Id, string? Version);
    private sealed record ResolvedProjectReference(string OutputAssemblyPath, ReferenceResolutionResult References);
    private sealed record FrameworkCandidate(string Directory, Version Version);

}
