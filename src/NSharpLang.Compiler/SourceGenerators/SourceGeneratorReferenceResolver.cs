using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Xml.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.SourceGenerators;

public static class SourceGeneratorReferenceResolver
{
    private static readonly StringComparer PathComparer = StringComparer.OrdinalIgnoreCase;

    // (path|fingerprint) -> single-flight build of the generator assembly path. Bounds
    // `dotnet build` to once per generator-project change within a process (H5) and coalesces
    // concurrent analysis/check threads so they don't race a build of the same project.
    private static readonly ConcurrentDictionary<string, Lazy<string>> GeneratorBuildCache = new(StringComparer.Ordinal);

    /// <summary>
    /// Discovers source-generator references for the project (package analyzers, framework
    /// generators, and Roslyn-component project references) and appends them to
    /// <paramref name="config"/>. Returns any diagnostics produced while preparing those
    /// references (e.g. a generator project that failed to build) so callers can surface them
    /// instead of crashing analysis/emit (H6).
    /// </summary>
    public static IReadOnlyList<CompilerError> PopulateDiscoveredReferences(
        ProjectConfig config,
        string projectRoot,
        IEnumerable<CompilationUnit>? compilationUnits = null,
        bool buildProjectReferences = false)
    {
        ArgumentNullException.ThrowIfNull(config);
        projectRoot = Path.GetFullPath(projectRoot);

        var diagnostics = new List<CompilerError>();

        foreach (var packageReference in config.Dependencies.Where(reference => reference.Type == ReferenceType.NuGet))
        {
            var packageDirectory = TryGetPackageDirectory(packageReference.Nuget!, packageReference.Version);
            if (packageDirectory != null)
            {
                AddPackageAnalyzers(config, packageReference.Nuget!, packageDirectory);
            }
        }

        foreach (var packageReference in config.TestDependencies.Where(reference => reference.Type == ReferenceType.NuGet))
        {
            var packageDirectory = TryGetPackageDirectory(packageReference.Nuget!, packageReference.Version);
            if (packageDirectory != null)
            {
                AddPackageAnalyzers(config, packageReference.Nuget!, packageDirectory);
            }
        }

        foreach (var projectReference in config.Dependencies.Where(reference => reference.Type == ReferenceType.Project).ToArray())
        {
            var projectPath = ResolveProjectReferencePath(projectRoot, projectReference.Project!);
            if (!projectPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (!buildProjectReferences)
            {
                continue;
            }

            // Only build project references that are actually Roslyn components (source
            // generators / analyzers). Ordinary library references are resolved as normal
            // compile references elsewhere and must NOT be built here — building every
            // `.csproj` on the interactive analysis path is the H5 stall (ILCompiler review).
            if (!IsRoslynComponentProject(projectPath))
            {
                continue;
            }

            try
            {
                var outputAssembly = BuildGeneratorProjectCached(projectPath);
                AddReferenceIfMissing(
                    config,
                    outputAssembly,
                    SourceGeneratorReferenceKind.Project,
                    projectReference.Project!);
            }
            catch (Exception ex)
            {
                diagnostics.Add(BuildGeneratorReferenceFailureDiagnostic(projectReference.Project!, projectPath, ex));
            }
        }

        var units = compilationUnits?.ToArray() ?? Array.Empty<CompilationUnit>();
        if (units.Length > 0 && HasAttribute(units, "JsonSerializable"))
        {
            AddFrameworkGeneratorByFileName(
                config,
                config.TargetFramework,
                "System.Text.Json.SourceGeneration.dll",
                "System.Text.Json");
        }

        return diagnostics;
    }

    /// <summary>
    /// True when the project declares <c>&lt;IsRoslynComponent&gt;true&lt;/IsRoslynComponent&gt;</c>,
    /// the standard MSBuild marker for source-generator / analyzer projects.
    /// </summary>
    public static bool IsRoslynComponentProject(string projectPath)
    {
        try
        {
            var document = XDocument.Load(projectPath);
            return document.Descendants()
                .Where(element => element.Name.LocalName == "IsRoslynComponent")
                .Any(element => string.Equals(element.Value.Trim(), "true", StringComparison.OrdinalIgnoreCase));
        }
        catch
        {
            return false;
        }
    }

    public static void AddProjectReference(ProjectConfig config, string assemblyPath, string origin)
    {
        AddReferenceIfMissing(
            config,
            assemblyPath,
            SourceGeneratorReferenceKind.Project,
            origin);
    }

    private static string BuildGeneratorProjectCached(string projectPath)
    {
        projectPath = Path.GetFullPath(projectPath);
        var key = projectPath + "|" + ComputeProjectFingerprint(projectPath);

        while (true)
        {
            // Single-flight: only one thread builds a given (project, fingerprint); others await
            // the same Lazy result instead of racing a concurrent `dotnet build` of the project.
            var lazy = GeneratorBuildCache.GetOrAdd(
                key,
                _ => new Lazy<string>(() => BuildGeneratorProject(projectPath), LazyThreadSafetyMode.ExecutionAndPublication));

            string built;
            try
            {
                built = lazy.Value;
            }
            catch
            {
                // Don't pin a failed build; let a later call retry.
                GeneratorBuildCache.TryRemove(new KeyValuePair<string, Lazy<string>>(key, lazy));
                throw;
            }

            if (File.Exists(built))
            {
                return built;
            }

            // The cached output was removed after the build; invalidate this entry and rebuild.
            GeneratorBuildCache.TryRemove(new KeyValuePair<string, Lazy<string>>(key, lazy));
        }
    }

    // Fingerprint covers every build input we can cheaply see: the count and newest write time of
    // all files under the project directory (excluding bin/obj), plus any ancestor
    // Directory.Build.props/.targets. Captures edits, adds, and deletes of project sources and
    // MSBuild props/targets so a stale generator assembly isn't reused. It does NOT capture
    // changes in referenced projects or NuGet restore inputs outside the project tree — rare for
    // a generator project, and `dotnet build` incrementality still applies when we do build.
    private static string ComputeProjectFingerprint(string projectPath)
    {
        try
        {
            var directory = Path.GetDirectoryName(projectPath) ?? Environment.CurrentDirectory;
            long newestTicks = 0;
            long fileCount = 0;
            foreach (var file in Directory.EnumerateFiles(directory, "*", SearchOption.AllDirectories))
            {
                if (PathHasSegment(file, "bin") || PathHasSegment(file, "obj"))
                {
                    continue;
                }

                fileCount++;
                var ticks = File.GetLastWriteTimeUtc(file).Ticks;
                if (ticks > newestTicks)
                {
                    newestTicks = ticks;
                }
            }

            foreach (var ticks in EnumerateAncestorBuildFileTicks(directory))
            {
                if (ticks > newestTicks)
                {
                    newestTicks = ticks;
                }
            }

            return string.Create(
                CultureInfo.InvariantCulture,
                $"{fileCount}|{newestTicks}");
        }
        catch
        {
            return string.Empty;
        }
    }

    private static IEnumerable<long> EnumerateAncestorBuildFileTicks(string startDirectory)
    {
        for (var current = new DirectoryInfo(startDirectory); current != null; current = current.Parent)
        {
            foreach (var name in new[] { "Directory.Build.props", "Directory.Build.targets" })
            {
                var path = Path.Combine(current.FullName, name);
                if (File.Exists(path))
                {
                    yield return File.GetLastWriteTimeUtc(path).Ticks;
                }
            }
        }
    }

    private static bool PathHasSegment(string path, string segment)
        => path.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Any(part => string.Equals(part, segment, StringComparison.OrdinalIgnoreCase));

    private static CompilerError BuildGeneratorReferenceFailureDiagnostic(string origin, string projectPath, Exception ex)
        => new CompilerError(
            ErrorCode.SourceGeneratorLoadFailure,
            $"Source generator project reference '{origin}' could not be prepared: {ex.Message}",
            0,
            0,
            ErrorSeverity.Error)
        {
            DiagnosticIdOverride = "NL920",
            HumanExplanation = "A referenced source-generator project failed to build, so its generators are unavailable.",
            ContextualHint = "Source-generator project references are built before generators run; a build failure there is reported as a diagnostic instead of crashing analysis.",
            Suggestion = "Build the referenced generator project manually to see the underlying error, fix it, or remove the reference.",
            RelatedInfo = new Dictionary<string, string>
            {
                ["origin"] = origin,
                ["path"] = projectPath,
                ["exception"] = ex.ToString()
            }
        };

    public static void AddPackageAnalyzers(ProjectConfig config, string packageName, string packageDirectory)
    {
        foreach (var analyzerAssembly in EnumerateAnalyzerAssemblies(packageDirectory))
        {
            AddReferenceIfMissing(
                config,
                analyzerAssembly,
                SourceGeneratorReferenceKind.Package,
                packageName);
        }
    }

    public static void AddDirectReference(ProjectConfig config, string assemblyPath, string origin)
    {
        AddReferenceIfMissing(
            config,
            assemblyPath,
            SourceGeneratorReferenceKind.Direct,
            origin);
    }

    public static IReadOnlyList<string> EnumerateAnalyzerAssemblies(string packageDirectory)
    {
        if (string.IsNullOrWhiteSpace(packageDirectory) || !Directory.Exists(packageDirectory))
        {
            return Array.Empty<string>();
        }

        var analyzerRoot = Path.Combine(packageDirectory, "analyzers", "dotnet");
        if (!Directory.Exists(analyzerRoot))
        {
            return Array.Empty<string>();
        }

        var candidates = new List<string>();
        foreach (var directory in EnumerateAnalyzerAssetDirectories(analyzerRoot))
        {
            candidates.AddRange(Directory.GetFiles(directory, "*.dll", SearchOption.TopDirectoryOnly));
        }

        return candidates
            .Where(IsUsableAnalyzerAssembly)
            .Select(Path.GetFullPath)
            .Distinct(PathComparer)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static IEnumerable<string> EnumerateAnalyzerAssetDirectories(string analyzerRoot)
    {
        var versionedBuckets = Directory.GetDirectories(analyzerRoot)
            .Select(directory => new
            {
                Directory = directory,
                Version = TryParseRoslynAnalyzerVersion(Path.GetFileName(directory))
            })
            .Where(candidate => candidate.Version != null)
            .Where(candidate => RoslynAnalyzerVersionIsCompatible(candidate.Version!))
            .OrderByDescending(candidate => candidate.Version)
            .ToArray();

        if (versionedBuckets.Length > 0)
        {
            foreach (var directory in EnumerateLanguageSpecificAnalyzerDirectories(versionedBuckets[0].Directory))
            {
                yield return directory;
            }

            yield break;
        }

        foreach (var directory in EnumerateLanguageSpecificAnalyzerDirectories(analyzerRoot))
        {
            yield return directory;
        }
    }

    private static IEnumerable<string> EnumerateLanguageSpecificAnalyzerDirectories(string analyzerRoot)
    {
        yield return analyzerRoot;

        var csDirectory = Path.Combine(analyzerRoot, "cs");
        if (Directory.Exists(csDirectory))
        {
            yield return csDirectory;
        }
    }

    private static Version? TryParseRoslynAnalyzerVersion(string? directoryName)
    {
        const string prefix = "roslyn";
        if (string.IsNullOrWhiteSpace(directoryName)
            || !directoryName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return TryParseVersion(directoryName[prefix.Length..]);
    }

    private static bool RoslynAnalyzerVersionIsCompatible(Version analyzerVersion)
    {
        var roslynVersion = typeof(Microsoft.CodeAnalysis.Compilation).Assembly.GetName().Version;
        if (roslynVersion == null)
        {
            return true;
        }

        return analyzerVersion.Major < roslynVersion.Major
            || analyzerVersion.Major == roslynVersion.Major && analyzerVersion.Minor <= roslynVersion.Minor;
    }

    private static bool IsUsableAnalyzerAssembly(string path)
    {
        var fileName = Path.GetFileName(path);
        return fileName.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)
            && !fileName.EndsWith(".resources.dll", StringComparison.OrdinalIgnoreCase);
    }

    private static void AddFrameworkGeneratorByFileName(
        ProjectConfig config,
        string targetFramework,
        string generatorFileName,
        string origin)
    {
        foreach (var path in EnumerateImplicitGeneratorCandidates(targetFramework, generatorFileName, origin)
                     .OrderByDescending(candidate => candidate.Priority)
                     .ThenByDescending(candidate => candidate.Version ?? new Version(0, 0))
                     .ThenBy(candidate => candidate.Path, StringComparer.OrdinalIgnoreCase)
                     .Select(candidate => candidate.Path))
        {
            AddReferenceIfMissing(
                config,
                path,
                SourceGeneratorReferenceKind.Framework,
                origin,
                isImplicitFramework: true);
            return;
        }
    }

    private static IEnumerable<ImplicitGeneratorCandidate> EnumerateImplicitGeneratorCandidates(
        string targetFramework,
        string generatorFileName,
        string origin)
    {
        foreach (var path in EnumeratePackageAnalyzerCandidates(origin, generatorFileName))
        {
            yield return new ImplicitGeneratorCandidate(path, TryGetPackageVersion(path, origin), Priority: 1);
        }

        foreach (var path in EnumerateFrameworkAnalyzerCandidates(targetFramework, generatorFileName))
        {
            yield return new ImplicitGeneratorCandidate(path, TryGetFrameworkAnalyzerPackVersion(path), Priority: 0);
        }
    }

    private static IEnumerable<string> EnumeratePackageAnalyzerCandidates(
        string packageName,
        string generatorFileName)
    {
        var packageRoot = Path.Combine(GetGlobalPackagesFolder(), packageName.ToLowerInvariant());
        if (!Directory.Exists(packageRoot))
        {
            yield break;
        }

        foreach (var packageDirectory in Directory.GetDirectories(packageRoot)
                     .Select(directory => new
                     {
                         Directory = directory,
                         Version = TryParseVersion(Path.GetFileName(directory)?.Split('-', 2)[0])
                     })
                     .OrderByDescending(candidate => candidate.Version)
                     .ThenByDescending(candidate => Path.GetFileName(candidate.Directory), StringComparer.OrdinalIgnoreCase))
        {
            foreach (var analyzerAssembly in EnumerateAnalyzerAssemblies(packageDirectory.Directory)
                         .Where(path => string.Equals(Path.GetFileName(path), generatorFileName, StringComparison.OrdinalIgnoreCase)))
            {
                yield return analyzerAssembly;
            }
        }
    }

    private static Version? TryGetFrameworkAnalyzerPackVersion(string analyzerPath)
    {
        var current = new DirectoryInfo(Path.GetDirectoryName(analyzerPath) ?? string.Empty);
        while (current.Parent != null)
        {
            if (string.Equals(current.Parent.Name, "Microsoft.NETCore.App.Ref", StringComparison.OrdinalIgnoreCase))
            {
                return TryParseVersion(current.Name);
            }

            current = current.Parent;
        }

        return null;
    }

    private static Version? TryGetPackageVersion(string analyzerPath, string packageName)
    {
        var normalizedPackageName = packageName.ToLowerInvariant();
        var current = new DirectoryInfo(Path.GetDirectoryName(analyzerPath) ?? string.Empty);
        while (current.Parent != null)
        {
            if (string.Equals(current.Parent.Name, normalizedPackageName, StringComparison.OrdinalIgnoreCase))
            {
                return TryParseVersion(current.Name.Split('-', 2)[0]);
            }

            current = current.Parent;
        }

        return null;
    }

    private static IEnumerable<string> EnumerateFrameworkAnalyzerCandidates(
        string targetFramework,
        string generatorFileName)
    {
        var yielded = new HashSet<string>(PathComparer);
        foreach (var packRoot in EnumerateDotnetPackRoots())
        {
            foreach (var candidate in EnumeratePackAnalyzerCandidates(
                         Path.Combine(packRoot, "Microsoft.NETCore.App.Ref"),
                         targetFramework,
                         generatorFileName))
            {
                if (yielded.Add(candidate))
                {
                    yield return candidate;
                }
            }
        }

        var packageRoot = Path.Combine(GetGlobalPackagesFolder(), "microsoft.netcore.app.ref");
        foreach (var candidate in EnumeratePackAnalyzerCandidates(packageRoot, targetFramework, generatorFileName))
        {
            if (yielded.Add(candidate))
            {
                yield return candidate;
            }
        }
    }

    private static IEnumerable<string> EnumeratePackAnalyzerCandidates(
        string refPackRoot,
        string targetFramework,
        string generatorFileName)
    {
        if (!Directory.Exists(refPackRoot))
        {
            yield break;
        }

        var targetVersion = ParseTargetFrameworkVersion(targetFramework);
        foreach (var versionDirectory in Directory.GetDirectories(refPackRoot)
                     .Select(directory => new
                     {
                         Directory = directory,
                         Version = TryParseVersion(Path.GetFileName(directory))
                     })
                     .Where(candidate => candidate.Version != null)
                     .Where(candidate => targetVersion == null || candidate.Version!.Major == targetVersion.Value.Major)
                     .OrderByDescending(candidate => candidate.Version))
        {
            var analyzerPath = Path.Combine(
                versionDirectory.Directory,
                "analyzers",
                "dotnet",
                "cs",
                generatorFileName);
            if (File.Exists(analyzerPath))
            {
                yield return Path.GetFullPath(analyzerPath);
            }
        }
    }

    private static IEnumerable<string> EnumerateDotnetPackRoots()
    {
        var yielded = new HashSet<string>(PathComparer);
        var runtimeDirectory = RuntimeEnvironment.GetRuntimeDirectory();
        for (var current = runtimeDirectory; !string.IsNullOrWhiteSpace(current); current = Path.GetDirectoryName(current))
        {
            var packs = Path.Combine(current, "packs");
            if (Directory.Exists(packs) && yielded.Add(packs))
            {
                yield return packs;
            }

            if (string.Equals(Path.GetFileName(current), "shared", StringComparison.OrdinalIgnoreCase))
            {
                var dotnetRoot = Path.GetDirectoryName(current);
                if (!string.IsNullOrWhiteSpace(dotnetRoot))
                {
                    packs = Path.Combine(dotnetRoot, "packs");
                    if (Directory.Exists(packs) && yielded.Add(packs))
                    {
                        yield return packs;
                    }
                }
            }
        }

        foreach (var root in new[]
                 {
                     "/usr/local/share/dotnet/packs",
                     "/opt/homebrew/share/dotnet/packs",
                     "/opt/homebrew/Cellar/dotnet",
                     "/usr/share/dotnet/packs"
                 })
        {
            if (Directory.Exists(root) && string.Equals(Path.GetFileName(root), "dotnet", StringComparison.OrdinalIgnoreCase))
            {
                foreach (var nested in Directory.GetDirectories(root, "packs", SearchOption.AllDirectories))
                {
                    if (yielded.Add(nested))
                    {
                        yield return nested;
                    }
                }
                continue;
            }

            if (Directory.Exists(root) && yielded.Add(root))
            {
                yield return root;
            }
        }
    }

    private static string? TryGetPackageDirectory(string packageName, string? version)
    {
        var packageRoot = Path.Combine(GetGlobalPackagesFolder(), packageName.ToLowerInvariant());
        if (!Directory.Exists(packageRoot))
        {
            return null;
        }

        if (!string.IsNullOrWhiteSpace(version))
        {
            var versionDirectory = Path.Combine(packageRoot, version.ToLowerInvariant());
            return Directory.Exists(versionDirectory) ? versionDirectory : null;
        }

        return Directory.GetDirectories(packageRoot)
            .Select(directory => new
            {
                Directory = directory,
                Version = TryParseVersion(Path.GetFileName(directory)?.Split('-', 2)[0])
            })
            .OrderByDescending(candidate => candidate.Version)
            .ThenByDescending(candidate => Path.GetFileName(candidate.Directory), StringComparer.OrdinalIgnoreCase)
            .Select(candidate => candidate.Directory)
            .FirstOrDefault();
    }

    private static string BuildGeneratorProject(string projectPath)
    {
        projectPath = Path.GetFullPath(projectPath);
        if (!File.Exists(projectPath))
        {
            throw new FileNotFoundException($"Source generator project reference not found: {projectPath}", projectPath);
        }

        var startInfo = new ProcessStartInfo("dotnet")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Path.GetDirectoryName(projectPath) ?? Environment.CurrentDirectory
        };
        startInfo.ArgumentList.Add("build");
        startInfo.ArgumentList.Add(projectPath);
        startInfo.ArgumentList.Add("-c");
        startInfo.ArgumentList.Add("Debug");
        startInfo.ArgumentList.Add("--nologo");
        startInfo.ArgumentList.Add("-v:q");
        startInfo.ArgumentList.Add("--disable-build-servers");

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Could not start dotnet build for source generator project '{projectPath}'.");
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"Source generator project '{projectPath}' failed to build. " +
                $"dotnet build exit code {process.ExitCode}.{Environment.NewLine}{stdout}{stderr}");
        }

        var outputAssembly = FindBuiltProjectAssembly(projectPath);
        if (outputAssembly == null)
        {
            throw new InvalidOperationException(
                $"Source generator project '{projectPath}' built successfully, but no output assembly could be found under bin/Debug.");
        }

        return outputAssembly;
    }

    private static string? FindBuiltProjectAssembly(string projectPath)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath) ?? Environment.CurrentDirectory;
        var assemblyName = ReadProjectAssemblyName(projectPath) ?? Path.GetFileNameWithoutExtension(projectPath);
        var binDirectory = Path.Combine(projectDirectory, "bin", "Debug");
        if (!Directory.Exists(binDirectory))
        {
            return null;
        }

        return Directory.GetFiles(binDirectory, $"{assemblyName}.dll", SearchOption.AllDirectories)
            .Where(path => !path.Split(Path.DirectorySeparatorChar).Any(part => string.Equals(part, "ref", StringComparison.OrdinalIgnoreCase)))
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .FirstOrDefault();
    }

    private static string? ReadProjectAssemblyName(string projectPath)
    {
        try
        {
            var document = XDocument.Load(projectPath);
            return document.Descendants()
                .FirstOrDefault(element => element.Name.LocalName == "AssemblyName")
                ?.Value;
        }
        catch
        {
            return null;
        }
    }

    private static string ResolveProjectReferencePath(string projectRoot, string projectReference)
        => Path.GetFullPath(Path.IsPathRooted(projectReference)
            ? projectReference
            : Path.Combine(projectRoot, projectReference));

    private static void AddReferenceIfMissing(
        ProjectConfig config,
        string assemblyPath,
        SourceGeneratorReferenceKind kind,
        string origin,
        bool isImplicitFramework = false)
    {
        if (string.IsNullOrWhiteSpace(assemblyPath) || !File.Exists(assemblyPath))
        {
            return;
        }

        var fullPath = Path.GetFullPath(assemblyPath);
        if (config.SourceGenerators.Any(reference =>
                string.Equals(Path.GetFullPath(reference.Path), fullPath, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        config.SourceGenerators.Add(new SourceGeneratorReference(fullPath, kind, origin, isImplicitFramework));
    }

    private static bool HasAttribute(IEnumerable<CompilationUnit> units, string shortName)
        => units.SelectMany(unit => unit.Declarations).Any(declaration => HasAttribute(declaration, shortName));

    private static bool HasAttribute(Declaration declaration, string shortName)
    {
        if (GetAttributes(declaration).Any(attribute => AttributeNameMatches(attribute.Name, shortName)))
        {
            return true;
        }

        return GetMembers(declaration).Any(member => HasAttribute(member, shortName));
    }

    private static IEnumerable<AttributeNode> GetAttributes(Declaration declaration) => declaration switch
    {
        ClassDeclaration classDeclaration => classDeclaration.Attributes,
        StructDeclaration structDeclaration => structDeclaration.Attributes,
        RecordDeclaration recordDeclaration => recordDeclaration.Attributes,
        SoaRecordDeclaration soaRecordDeclaration => soaRecordDeclaration.Attributes,
        InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Attributes,
        EnumDeclaration enumDeclaration => enumDeclaration.Attributes,
        UnionDeclaration unionDeclaration => unionDeclaration.Attributes,
        FieldDeclaration fieldDeclaration => fieldDeclaration.Attributes,
        PropertyDeclaration propertyDeclaration => propertyDeclaration.Attributes,
        ConstructorDeclaration constructorDeclaration => constructorDeclaration.Attributes,
        IndexerDeclaration indexerDeclaration => indexerDeclaration.Attributes,
        FunctionDeclaration functionDeclaration => functionDeclaration.Attributes,
        _ => Array.Empty<AttributeNode>()
    };

    private static IEnumerable<Declaration> GetMembers(Declaration declaration) => declaration switch
    {
        ClassDeclaration classDeclaration => classDeclaration.Members,
        StructDeclaration structDeclaration => structDeclaration.Members,
        RecordDeclaration recordDeclaration => recordDeclaration.Members,
        InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Members,
        _ => Array.Empty<Declaration>()
    };

    private static bool AttributeNameMatches(string name, string shortName)
    {
        var lastDot = name.LastIndexOf('.');
        if (lastDot >= 0)
        {
            name = name[(lastDot + 1)..];
        }

        if (name.EndsWith("Attribute", StringComparison.Ordinal))
        {
            name = name[..^"Attribute".Length];
        }

        return string.Equals(name, shortName, StringComparison.Ordinal);
    }

    private static string GetGlobalPackagesFolder()
    {
        var configured = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        return !string.IsNullOrWhiteSpace(configured)
            ? Path.GetFullPath(configured)
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");
    }

    private static (int Major, int Minor)? ParseTargetFrameworkVersion(string targetFramework)
    {
        if (SourceGeneratorReferenceResolverKernels.TryParseTargetFrameworkVersion(
                targetFramework,
                out var parsed,
                out var major,
                out var minor))
        {
            return parsed ? (major, minor) : null;
        }

        throw new InvalidOperationException("N# source-generator reference resolver kernel rejected target-framework version parsing.");
    }

    private static Version? TryParseVersion(string? value)
        => Version.TryParse(value, out var version) ? version : null;

    private sealed record ImplicitGeneratorCandidate(string Path, Version? Version, int Priority);
}
