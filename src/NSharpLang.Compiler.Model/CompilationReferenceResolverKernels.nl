namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.Security.Cryptography
import NSharpLang.Compiler

class TargetFrameworkVersionParseResult {
    Parsed: bool
    Major: int
    Minor: int

    constructor(Parsed: bool, Major: int, Minor: int) {
        this.Parsed = Parsed
        this.Major = Major
        this.Minor = Minor
    }
}

class CompilationReferenceResolverKernels {
    static func GetImplicitNSharpRuntimeAssetCandidates(baseDirectory: string, compilerDirectory: string?): string[] {
        candidates := new List<string>()
        candidates.Add(Path.Combine(baseDirectory, "NSharpLang.Runtime.dll"))

        if compilerDirectory != null && !string.IsNullOrWhiteSpace(compilerDirectory) {
            candidates.Add(Path.Combine(compilerDirectory, "NSharpLang.Runtime.dll"))
        }

        return candidates.ToArray()
    }

    static func GetProjectRoot(projectDir: string): string {
        return Path.GetFullPath(projectDir)
    }

    static func GetCompilerAssemblyDirectory(assemblyLocation: string): string? {
        return Path.GetDirectoryName(assemblyLocation)
    }

    static func GetGlobalPackagesFolder(configuredPackagesFolder: string?, userProfileFolder: string): string {
        if configuredPackagesFolder != null && !string.IsNullOrWhiteSpace(configuredPackagesFolder) {
            return Path.GetFullPath(configuredPackagesFolder)
        }

        return Path.Combine(Path.Combine(userProfileFolder, ".nuget"), "packages")
    }

    static func NormalizeNuGetPackageId(packageName: string): string {
        return packageName.ToLowerInvariant()
    }

    static func NormalizeNuGetPackageVersion(version: string): string {
        return version.ToLowerInvariant()
    }

    static func GetNuGetPackageDirectory(packagesRoot: string, packageName: string): string {
        return Path.Combine(packagesRoot, NormalizeNuGetPackageId(packageName))
    }

    static func GetNuGetPackageVersionDirectory(packageDirectory: string, version: string): string {
        return Path.Combine(packageDirectory, NormalizeNuGetPackageVersion(version))
    }

    static func GetNuGetPackageParentDirectory(versionDirectory: string): string? {
        return Path.GetDirectoryName(versionDirectory)
    }

    static func GetNuGetIndexUrl(packageName: string): string {
        packageId := NormalizeNuGetPackageId(packageName)
        return "https://api.nuget.org/v3-flatcontainer/" + packageId + "/index.json"
    }

    static func GetNuGetPackageDownloadUrl(packageName: string, version: string): string {
        packageId := NormalizeNuGetPackageId(packageName)
        normalizedVersion := NormalizeNuGetPackageVersion(version)
        return "https://api.nuget.org/v3-flatcontainer/" + packageId + "/" + normalizedVersion + "/" + packageId + "." + normalizedVersion + ".nupkg"
    }

    static func GetNuGetPackageFileName(packageName: string, version: string): string {
        return NormalizeNuGetPackageId(packageName) + "." + NormalizeNuGetPackageVersion(version) + ".nupkg"
    }

    static func GetNuGetPackagePath(tempDirectory: string, packageName: string, version: string): string {
        return Path.Combine(tempDirectory, GetNuGetPackageFileName(packageName, version))
    }

    // ── NUGET'S INSTALL MARKERS ───────────────────────────────────────────────────────────────
    //
    // Unzipping a package into `<packages>/<id>/<version>/` does NOT install it. NuGet decides
    // whether a version directory holds a package by looking for the install markers beside the
    // content — the `.nupkg` itself and its `<id>.<version>.nupkg.sha512` — and a directory that
    // carries only the extracted files is invisible to `dotnet restore`, which then reports NU1101
    // for a package that is sitting right there. `nlc build` and `dotnet build` share ONE global
    // packages folder, so an install only one of them can see is a lie about that cache.
    //
    // The `.sha512` file is the base64 SHA-512 of the `.nupkg` bytes, with no trailing newline.
    // `.nupkg.metadata` is deliberately NOT written here: its `contentHash` is the SIGNED content
    // hash for a signed package, which is not the hash of the file, and writing a value this side
    // cannot compute would be a false claim about the cache. NuGet writes that file itself on the
    // first restore that finds these two (measured against the 10.0.105 SDK: restore succeeds
    // offline with no sources and leaves a correct `.nupkg.metadata` behind).
    static func GetNuGetPackageHashFileName(packageName: string, version: string): string {
        return GetNuGetPackageFileName(packageName, version) + ".sha512"
    }

    static func GetInstalledNuGetPackagePath(installDirectory: string, packageName: string, version: string): string {
        return Path.Combine(installDirectory, GetNuGetPackageFileName(packageName, version))
    }

    static func GetInstalledNuGetPackageHashPath(installDirectory: string, packageName: string, version: string): string {
        return Path.Combine(installDirectory, GetNuGetPackageHashFileName(packageName, version))
    }

    static func GetNuGetPackageContentHash(packageBytes: byte[]): string {
        algorithm := SHA512.Create()
        try {
            hashBytes := algorithm.ComputeHash(packageBytes)
            encoded := Convert.ToBase64String(hashBytes)
            return encoded
        } finally {
            algorithm.Dispose()
        }
    }

    static func GetInstalledNuGetPackageVersion(versionDirectory: string): string {
        return Path.GetFileName(versionDirectory) ?? ""
    }

    // ── DIRECT WINS, THEN HIGHEST APPLICABLE COUSIN VERSION ──────────────────────────────────
    //
    // A `nuget:` list is a set of ROOTS, not an ordered search path. This comparison helper is used
    // only after the graph walk has applied nearest-wins within each root subgraph. Across cousin
    // subgraphs, NuGet's lowest-applicable rule chooses the lowest version satisfying all lower
    // bounds, which is the highest requested minimum. A project-level direct reference overrides
    // any transitive occurrence, including a downgrade, and NuGet reports that as NU1605:
    //
    //   | graph | `dotnet restore` resolves |
    //   | Swashbuckle 7.2.0 (-> 1.6.22 at depth 3) + AspNetCore.OpenApi 9.0.0 (-> 1.6.17 at depth 2) | 1.6.22 |
    //   | the same, plus a DIRECT `Microsoft.OpenApi 1.6.17` | 1.6.17, with NU1605 |
    //
    // The resolver recomputes the closure after choosing these candidates. The chosen version's
    // dependencies replace the losing version's edges before the next cousin set is considered.
    //
    // `NormalizeNuGetDependencyVersion` collapses a declared range to its minimum, so an EXACT
    // range (`[1.0.0]`) is indistinguishable here from a lower bound. NuGet would report that
    // conflict; this cannot, and a package pinned that way is the one shape this rule can still
    // resolve higher than its author allowed.
    static func ShouldSelectNuGetPackageCandidate(
        hasSelection: bool,
        selectedVersion: string,
        selectedIsDirect: bool,
        candidateVersion: string,
        candidateIsDirect: bool
    ): bool {
        if !hasSelection {
            return true
        }

        if candidateIsDirect && !selectedIsDirect {
            return true
        }

        if selectedIsDirect && !candidateIsDirect {
            return false
        }

        compareScratch := new int[](9)
        return BestNuGetVersionCompare(candidateVersion, selectedVersion, compareScratch) > 0
    }

    static func GetNuGetTempDirectory(tempRoot: string, uniqueName: string): string {
        return Path.Combine(tempRoot, "nlc-nuget-" + uniqueName)
    }

    static func GetNuGetExtractDirectory(versionDirectory: string, uniqueName: string): string {
        return versionDirectory + "." + uniqueName + ".tmp"
    }

    static func GetNuGetAssetRoot(versionDirectory: string, assetKind: string): string {
        return Path.Combine(versionDirectory, assetKind)
    }

    static func GetFallbackNuGetPackageIdentity(versionDirectory: string): PackageIdentity {
        packageId := Path.GetFileName(Path.GetDirectoryName(versionDirectory)) ?? ""
        packageVersion := Path.GetFileName(versionDirectory) ?? ""
        return new PackageIdentity(packageId, packageVersion)
    }

    static func ResolveNuGetPackageIdentity(versionDirectory: string, requestedPackageName: string, declaredId: string?, declaredVersion: string?): PackageIdentity {
        packageId := declaredId ?? requestedPackageName
        packageVersion := declaredVersion ?? (Path.GetFileName(versionDirectory) ?? "")
        return new PackageIdentity(packageId, packageVersion)
    }

    static func GetNuGetPackageAssetsCacheKey(packageId: string?, packageVersion: string?): string {
        return (packageId ?? "") + "@" + (packageVersion ?? "")
    }

    // A shared workspace cache must distinguish target-framework asset selection and the complete
    // nearest-wins package-version map. The same package can have different transitive assets when
    // two member projects resolve different dependency closures.
    static func GetNuGetPackageAssetsCacheKey(
        packageId: string?,
        packageVersion: string?,
        targetFramework: string,
        selectedVersionsKey: string
    ): string {
        return GetNuGetPackageAssetsCacheKey(packageId, packageVersion) + "|" + targetFramework.ToLowerInvariant() + "|" + selectedVersionsKey
    }

    static func ShouldProbeInstalledNuGetVersions(requestedVersion: string?, packageDirectoryExists: bool): bool {
        return requestedVersion == null && packageDirectoryExists
    }

    static func SelectBestInstalledNuGetVersionDirectory(installedVersionDirectories: string[]): string? {
        installedVersions := new List<string>()
        candidateDirectories := new List<string>()
        for installedVersionDirectory in installedVersionDirectories {
            version := Path.GetFileName(installedVersionDirectory) ?? ""
            if !string.IsNullOrWhiteSpace(version) {
                installedVersions.Add(version)
                candidateDirectories.Add(installedVersionDirectory)
            }
        }

        bestVersionIndex := SelectBestNuGetVersionIndex(installedVersions.ToArray())
        if bestVersionIndex >= 0 {
            return candidateDirectories[bestVersionIndex]
        }

        return null
    }

    static func GetLatestNuGetVersionOrThrow(packageName: string, rawVersions: string?[]): string {
        versionsList := new List<string>()
        for rawVersion in rawVersions {
            version := rawVersion ?? ""
            if !string.IsNullOrWhiteSpace(version) {
                versionsList.Add(version)
            }
        }

        versions := versionsList.ToArray()
        latestVersionIndex := SelectLatestNuGetVersionIndex(versions)
        if latestVersionIndex >= 0 {
            return versions[latestVersionIndex]
        }

        throw new InvalidOperationException(GetNuGetNoPublishedVersionsMessage(packageName))
    }

    static func GetDotnetSharedRootCandidates(runtimeDirectory: string?): string[] {
        candidates := new List<string>()
        yielded := new HashSet<string>(StringComparer.OrdinalIgnoreCase)

        current := runtimeDirectory ?? ""
        while !string.IsNullOrWhiteSpace(current) {
            if string.Equals(Path.GetFileName(current), "shared", StringComparison.OrdinalIgnoreCase) {
                AddSharedRootCandidate(candidates, yielded, current)
            }

            current = Path.GetDirectoryName(current) ?? ""
        }

        AddSharedRootCandidate(candidates, yielded, "/usr/local/share/dotnet/shared")
        AddSharedRootCandidate(candidates, yielded, "/opt/homebrew/share/dotnet/shared")
        AddSharedRootCandidate(candidates, yielded, "/usr/share/dotnet/shared")
        return candidates.ToArray()
    }

    static func GetProjectAssemblyName(projectRoot: string, configuredName: string?): string {
        if !string.IsNullOrWhiteSpace(configuredName ?? "") {
            return configuredName ?? ""
        }

        projectName := Path.GetFileName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(projectRoot)))
        return projectName ?? "Project"
    }

    static func IsExecutableOutputType(outputType: string?): bool {
        return string.Equals(outputType ?? "", "exe", StringComparison.OrdinalIgnoreCase)
    }

    static func GetProjectYmlPath(projectRoot: string): string {
        return Path.Combine(projectRoot, "project.yml")
    }

    static func GetStableOutputDirectory(projectRoot: string, configuration: string, targetFramework: string): string {
        return Path.Combine(Path.Combine(Path.Combine(projectRoot, "bin"), configuration), targetFramework)
    }

    static func GetProjectOutputAssemblyPath(outputDirectory: string, assemblyName: string): string {
        return Path.Combine(outputDirectory, assemblyName + ".dll")
    }

    static func GetDllReferencePath(assemblyPath: string): string {
        return Path.GetFullPath(assemblyPath)
    }

    static func ShouldTreatProjectReferenceBuildAsFailed(success: bool, outputAssemblyPath: string?): bool {
        return !success || string.IsNullOrWhiteSpace(outputAssemblyPath ?? "")
    }

    static func ResolveProjectReferencePath(projectRoot: string, projectReference: string): string {
        if Path.IsPathRooted(projectReference) {
            return projectReference
        }

        return Path.Combine(projectRoot, projectReference)
    }

    // THE SHARED FRAMEWORKS WHOSE EVERY ASSEMBLY BECOMES A COMPILE REFERENCE: the ones the project's
    // SDK implies under MSBuild (`IsMsBuildImplicitFramework`), then each `framework:` entry, once.
    // `Microsoft.NETCore.App` is never one of them. Every project compiles against it -- MSBuild
    // references it in every .NETCoreApp project -- and its assemblies reach the compiler on demand,
    // per namespace a file names (`FrameworkNamespaceIndex`), instead of as 160-odd references every
    // compilation would sweep. So an explicit `framework: Microsoft.NETCore.App` is legal and adds
    // nothing.
    static func GetFrameworkReferenceNames(sdk: string, references: IEnumerable<Reference>): string[] {
        names := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        seen.Add(BaseSharedFrameworkName())

        if IsMsBuildImplicitFramework(sdk, "Microsoft.AspNetCore.App") {
            AddUniqueText(names, seen, "Microsoft.AspNetCore.App")
        }

        for reference in references {
            if reference.Type == ReferenceType.Framework {
                AddUniqueText(names, seen, reference.Framework ?? "")
            }
        }

        return names.ToArray()
    }

    static func BaseSharedFrameworkName(): string {
        return "Microsoft.NETCore.App"
    }

    // THE SHARED FRAMEWORKS MSBUILD REFERENCES WITHOUT BEING ASKED, measured against the .NET 10 SDK
    // rather than inferred from SDK names. `Microsoft.NET.Sdk` adds `Microsoft.NETCore.App` to every
    // .NETCoreApp project, and `Microsoft.NET.Sdk.Web` alone adds `Microsoft.AspNetCore.App`
    // (`Sdks/Microsoft.NET.Sdk.Web/Targets/Sdk.Server.props`). Other SDKs whose ids contain `Web`
    // -- `Microsoft.NET.Sdk.BlazorWebAssembly`, `Microsoft.NET.Sdk.WebAssembly` -- add no framework,
    // so this is an exact, case-insensitive id match; `nlc` decides what it references by this same
    // rule (`GetFrameworkReferenceNames`). An explicit `FrameworkReference` to one of these draws NETSDK1086,
    // which is why the SDK projection leaves them out.
    static func IsMsBuildImplicitFramework(sdk: string, frameworkName: string): bool {
        if string.Equals(frameworkName, "Microsoft.NETCore.App", StringComparison.OrdinalIgnoreCase) {
            return true
        }

        return string.Equals(frameworkName, "Microsoft.AspNetCore.App", StringComparison.OrdinalIgnoreCase) && string.Equals(sdk, "Microsoft.NET.Sdk.Web", StringComparison.OrdinalIgnoreCase)
    }

    static func GetSharedFrameworkRoot(sharedRoot: string, frameworkName: string): string {
        return Path.Combine(sharedRoot, frameworkName)
    }

    static func ShouldAddDllReference(references: IEnumerable<Reference>, fullPath: string): bool {
        for reference in references {
            if reference.Type == ReferenceType.Dll {
                referencePath := reference.Dll
                if referencePath != null && !string.IsNullOrWhiteSpace(referencePath) {
                    if string.Equals(Path.GetFullPath(referencePath), fullPath, StringComparison.OrdinalIgnoreCase) {
                        return false
                    }
                }
            }
        }

        return true
    }

    static func GetNuGetReferences(dependencies: IEnumerable<Reference>, testDependencies: IEnumerable<Reference>, includeTests: bool): List<Reference> {
        references := new List<Reference>()
        for reference in dependencies {
            if reference.Type == ReferenceType.NuGet {
                references.Add(reference)
            }
        }

        if includeTests {
            for reference in testDependencies {
                if reference.Type == ReferenceType.NuGet {
                    references.Add(reference)
                }
            }
        }

        return references
    }

    static func GetProjectReferenceResolutionOptions(options: ReferenceResolutionOptions): ReferenceResolutionOptions {
        projectReferenceOptions := new ReferenceResolutionOptions(options.Configuration, false, options.BuildProjectReferences, options.Quiet, options.AotMode)
        projectReferenceOptions.PackagesFolder = options.PackagesFolder
        projectReferenceOptions.UseBuiltProjectReferences = options.UseBuiltProjectReferences
        return projectReferenceOptions
    }

    // THE FIRST PRODUCT SOURCE OF A PROJECT THAT IS NEWER THAN ITS BUILT ASSEMBLY, or null when the
    // assembly is at least as new as every one. A product source is `project.yml` and every `.nl` file
    // outside `bin/` and `obj/` that is not a `.tests.nl`: a reference is always the PRODUCT build, so
    // an edited row does not make it stale. Sorted ordinally, so the file a message names is stable.
    static func FindProductSourceNewerThan(projectRoot: string, assemblyPath: string): string? {
        builtAt := File.GetLastWriteTimeUtc(assemblyPath)
        candidates := new List<string>()
        projectYml := GetProjectYmlPath(projectRoot)
        if File.Exists(projectYml) {
            candidates.Add(projectYml)
        }

        for candidate in Directory.GetFiles(projectRoot, "*.nl", SearchOption.AllDirectories) {
            relative := Path.GetRelativePath(projectRoot, candidate).Replace('\\', '/')
            if IsProductSourcePath(relative) {
                candidates.Add(candidate)
            }
        }

        candidates.Sort(StringComparer.Ordinal)
        for candidate in candidates {
            if File.GetLastWriteTimeUtc(candidate) > builtAt {
                return candidate
            }
        }

        return null
    }

    // A project-relative, `/`-separated `.nl` path the product build compiles.
    static func IsProductSourcePath(relativePath: string): bool {
        if relativePath.StartsWith("bin/", StringComparison.Ordinal) || relativePath.StartsWith("obj/", StringComparison.Ordinal) {
            return false
        }

        return relativePath.EndsWith(".nl", StringComparison.Ordinal) && !relativePath.EndsWith(".tests.nl", StringComparison.Ordinal)
    }

    static func GetProjectReferenceNotBuiltMessage(projectYmlPath: string, assemblyPath: string): string {
        return "Project reference '" + projectYmlPath + "' has no built assembly at '" + assemblyPath + "'. Build it first (nlc build or dotnet build in its directory), or check without --use-built-references to compile it from source."
    }

    static func GetProjectReferenceStaleMessage(projectYmlPath: string, assemblyPath: string, newerSource: string): string {
        return "Project reference '" + projectYmlPath + "' is out of date: '" + newerSource + "' is newer than its built assembly '" + assemblyPath + "'. Build it again, or check without --use-built-references to compile it from source."
    }

    static func ShouldUseRuntimeAssembliesForCompile(compileAssemblyCount: int): bool {
        return compileAssemblyCount == 0
    }

    static func GetPackageDependencies(rawIds: string?[], rawVersions: string?[]): PackageDependency[] {
        if rawIds.Length != rawVersions.Length {
            throw new ArgumentException("Package dependency id and version arrays must have the same length.")
        }

        dependencies := new List<PackageDependency>()
        index := 0
        while index < rawIds.Length {
            id := rawIds[index] ?? ""
            if !string.IsNullOrWhiteSpace(id) {
                dependencies.Add(new PackageDependency(id, NormalizeNuGetDependencyVersion(rawVersions[index])))
            }

            index = index + 1
        }

        return dependencies.ToArray()
    }

    static func GetProjectReferenceCycleMessage(chainRoots: string[]): string {
        return "Project reference cycle detected: " + string.Join(" -> ", chainRoots) + ". Break the cycle in project.yml dependencies."
    }

    static func GetCompilerDiagnosticsText(formattedDiagnostics: string[]): string {
        if formattedDiagnostics.Length == 0 {
            return "No compiler diagnostics were produced."
        }

        return string.Join(Environment.NewLine, formattedDiagnostics)
    }

    static func GetProjectReferenceBuildFailedMessage(projectYmlPath: string, diagnostics: string): string {
        return "Project reference '" + projectYmlPath + "' failed to build:" + Environment.NewLine + diagnostics
    }

    static func GetFrameworkReferenceNotResolvedMessage(frameworkName: string, projectRoot: string, targetFramework: string): string {
        return "Could not resolve framework reference '" + frameworkName + "' for project '" + projectRoot + "'. Install the " + frameworkName + " runtime for " + targetFramework + ", or remove the framework reference from project.yml."
    }

    static func GetNuGetNoPublishedVersionsMessage(packageName: string): string {
        return "Package '" + packageName + "' has no published versions on NuGet.org."
    }

    static func GetNuGetRestoreFailedMessage(packageName: string, version: string, detail: string): string {
        return "Could not restore NuGet package '" + packageName + "' version '" + version + "'. Check network access, NuGet.org availability, or pin a version already present in the local NuGet cache. Details: " + detail
    }

    static func GetImplicitTestDependencyPlan(includeTests: bool, hasTests: bool, testFramework: string?, existingPackageIds: string[]): ImplicitTestDependencyPlan {
        if !includeTests || !hasTests {
            return new ImplicitTestDependencyPlan(false, "", "")
        }

        packageName := TestFrameworkReferenceSet.FrameworkPackageId(testFramework)
        version := TestFrameworkReferenceSet.FrameworkPackageVersion(testFramework)

        if ContainsPackageId(existingPackageIds, packageName) {
            return new ImplicitTestDependencyPlan(false, "", "")
        }

        return new ImplicitTestDependencyPlan(true, packageName, version)
    }

    static func FilterReferencesByType(references: IEnumerable<Reference>, targetType: ReferenceType): List<Reference> {
        targetTypeId := Convert.ToInt32(targetType)
        if targetTypeId < 0 || targetTypeId > Convert.ToInt32(ReferenceType.Framework) {
            throw new ArgumentOutOfRangeException("targetType", "Reference type is not supported.")
        }

        filteredReferences := new List<Reference>()
        for reference in references {
            typeId := Convert.ToInt32(reference.Type)
            if typeId < 0 || typeId > Convert.ToInt32(ReferenceType.Framework) {
                throw new InvalidOperationException("N# reference resolver type filter received an unsupported reference type.")
            }

            if reference.Type == targetType {
                filteredReferences.Add(reference)
            }
        }

        return filteredReferences
    }

    static func SelectBestScoreIndex(scores: int[], count: int): int {
        if count < 0 || count > scores.Length {
            throw new ArgumentOutOfRangeException("count", "Score count must fit within the score array.")
        }

        if count == 0 {
            return -1
        }

        bestIndex := -1
        bestScore := -1
        i := 0
        while i < count {
            score := scores[i]
            if score >= 0 {
                if score > bestScore {
                    bestScore = score
                    bestIndex = i
                }
            }

            i = i + 1
        }

        return bestIndex
    }

    static func ParseTargetFrameworkVersion(targetFramework: string): TargetFrameworkVersionParseResult {
        result := new int[](2)
        code := TargetFrameworkVersionInto(targetFramework, result)
        if code != 0 {
            if code != 1 {
                throw new InvalidOperationException("N# reference resolver target-framework parser returned an invalid code.")
            }
        }

        if code == 1 {
            return new TargetFrameworkVersionParseResult(true, result[0], result[1])
        }

        return new TargetFrameworkVersionParseResult(false, 0, 0)
    }

    static func GetFrameworkCompatibilityScore(assetFramework: string?, targetFramework: string): int {
        result := new int[](5)
        code := FrameworkCompatibilityScoreInto(assetFramework ?? "", targetFramework, result)
        if code != 1 {
            throw new InvalidOperationException("N# reference resolver framework compatibility kernel returned an invalid code.")
        }

        return result[0]
    }

    static func SelectBestAssetDirectoryIndex(candidateFrameworks: string[], targetFramework: string): int {
        scores := new int[](candidateFrameworks.Length)
        index := 0
        while index < candidateFrameworks.Length {
            scores[index] = GetFrameworkCompatibilityScore(candidateFrameworks[index], targetFramework)
            index = index + 1
        }

        return SelectBestScoreIndex(scores, scores.Length)
    }

    static func SelectBestAssetDirectory(candidateDirectories: string[], targetFramework: string): string? {
        candidateFrameworks := new string[](candidateDirectories.Length)
        index := 0
        while index < candidateDirectories.Length {
            candidateFrameworks[index] = Path.GetFileName(candidateDirectories[index]) ?? ""
            index = index + 1
        }

        bestIndex := SelectBestAssetDirectoryIndex(candidateFrameworks, targetFramework)
        if bestIndex >= 0 {
            return candidateDirectories[bestIndex]
        }

        return null
    }

    static func SelectBestDependencyGroupIndex(groupTargetFrameworks: string?[], targetFramework: string): int {
        scores := new int[](groupTargetFrameworks.Length)
        index := 0
        while index < groupTargetFrameworks.Length {
            scores[index] = GetFrameworkCompatibilityScore(groupTargetFrameworks[index], targetFramework)
            index = index + 1
        }

        return SelectBestScoreIndex(scores, scores.Length)
    }

    static func SortPathsIgnoreCase(paths: string[]): string[] {
        sorted := new string[](paths.Length)
        index := 0
        while index < paths.Length {
            sorted[index] = paths[index]
            index = index + 1
        }

        Array.Sort(sorted, 0, sorted.Length, StringComparer.OrdinalIgnoreCase)
        return sorted
    }

    static func NormalizeNuGetDependencyVersion(version: string?): string? {
        source := version ?? ""
        result := new int[](2)
        code := NuGetDependencyVersionRangeInto(source, result)
        if code == 0 {
            return null
        }

        if code != 1 {
            throw new InvalidOperationException("N# reference resolver dependency-version kernel returned an invalid code.")
        }

        start := result[0]
        length := result[1]
        if start < 0 || length <= 0 || start > source.Length {
            throw new InvalidOperationException("N# reference resolver dependency-version kernel returned an invalid range.")
        }

        if start + length > source.Length {
            throw new InvalidOperationException("N# reference resolver dependency-version kernel returned an invalid range.")
        }

        return source.Substring(start, length)
    }

    static func SelectSharedFrameworkCandidateIndex(versions: Version[], targetMajor: int?): int {
        count := versions.Length
        if count <= 0 {
            return -1
        }

        bestOverallIndex := 0
        bestMatchingIndex := -1
        index := 0
        while index < count {
            if SharedFrameworkCandidateCompare(versions[index], versions[bestOverallIndex]) > 0 {
                bestOverallIndex = index
            }

            matchesTarget := false
            if !targetMajor.HasValue {
                matchesTarget = true
            } else if versions[index].Major == targetMajor.Value {
                matchesTarget = true
            }

            if matchesTarget {
                if bestMatchingIndex < 0 {
                    bestMatchingIndex = index
                } else if SharedFrameworkCandidateCompare(versions[index], versions[bestMatchingIndex]) > 0 {
                    bestMatchingIndex = index
                }
            }

            index = index + 1
        }

        if bestMatchingIndex >= 0 {
            return bestMatchingIndex
        }

        return bestOverallIndex
    }

    static func SelectSharedFrameworkDirectoryIndex(versionNames: string[], targetVersion: TargetFrameworkVersionParseResult): int {
        current := new int[](4)
        bestOverall := new int[](4)
        bestMatching := new int[](4)
        bestOverallIndex := -1
        bestMatchingIndex := -1

        index := 0
        while index < versionNames.Length {
            if TryParseSharedFrameworkVersionInto(versionNames[index], current) {
                if bestOverallIndex < 0 || CompareVersionParts(current, bestOverall) > 0 {
                    CopyVersionParts(current, bestOverall)
                    bestOverallIndex = index
                }

                matchesTarget := false
                if !targetVersion.Parsed {
                    matchesTarget = true
                } else if current[0] == targetVersion.Major {
                    matchesTarget = true
                }

                if matchesTarget {
                    if bestMatchingIndex < 0 || CompareVersionParts(current, bestMatching) > 0 {
                        CopyVersionParts(current, bestMatching)
                        bestMatchingIndex = index
                    }
                }
            }

            index = index + 1
        }

        if bestMatchingIndex >= 0 {
            return bestMatchingIndex
        }

        return bestOverallIndex
    }

    static func SelectSharedFrameworkDirectory(candidateDirectories: string[], targetFramework: string): string? {
        targetVersion := ParseTargetFrameworkVersion(targetFramework)
        candidateVersions := new string[](candidateDirectories.Length)
        index := 0
        while index < candidateDirectories.Length {
            candidateVersions[index] = Path.GetFileName(candidateDirectories[index]) ?? ""
            index = index + 1
        }

        selectedIndex := SelectSharedFrameworkDirectoryIndex(candidateVersions, targetVersion)
        if selectedIndex >= 0 {
            return candidateDirectories[selectedIndex]
        }

        return null
    }

    static func SelectLatestNuGetVersionIndex(versions: string[]): int {
        if versions.Length == 0 {
            return -1
        }

        latestStableIndex := -1
        index := 0
        while index < versions.Length {
            if !NuGetVersionHasPrereleaseSuffix(versions[index]) {
                latestStableIndex = index
            }

            index = index + 1
        }

        if latestStableIndex >= 0 {
            return latestStableIndex
        }

        return versions.Length - 1
    }

    static func SelectBestNuGetVersionIndex(versions: string[]): int {
        if versions.Length == 0 {
            return -1
        }

        compareScratch := new int[](9)
        bestIndex := 0
        index := 1
        while index < versions.Length {
            compare := BestNuGetVersionCompare(versions[index], versions[bestIndex], compareScratch)
            if compare > 0 {
                bestIndex = index
            }

            index = index + 1
        }

        return bestIndex
    }

    static func PathHasSegmentIgnoreCase(path: string, separator: char, segment: string): bool {
        segmentStart := 0
        index := 0
        while index <= path.Length {
            if index == path.Length {
                if PathSegmentEqualsIgnoreCase(path, segmentStart, index, segment) {
                    return true
                }
            } else if path[index] == separator {
                if PathSegmentEqualsIgnoreCase(path, segmentStart, index, segment) {
                    return true
                }

                segmentStart = index + 1
            }

            index = index + 1
        }

        return false
    }

    static func SharedFrameworkCandidateCompare(left: Version, right: Version): int {
        compare := CompareInt(left.Major, right.Major)
        if compare != 0 {
            return compare
        }

        compare = CompareInt(left.Minor, right.Minor)
        if compare != 0 {
            return compare
        }

        compare = CompareInt(left.Build, right.Build)
        if compare != 0 {
            return compare
        }

        return CompareInt(left.Revision, right.Revision)
    }

    static func TryParseSharedFrameworkVersionInto(value: string?, result: int[]): bool {
        if result.Length < 4 {
            return false
        }

        result[0] = -1
        result[1] = -1
        result[2] = -1
        result[3] = -1

        text := value ?? ""
        start := 0
        while start < text.Length {
            if !char.IsWhiteSpace(text[start]) {
                break
            }

            start = start + 1
        }

        end := text.Length
        while end > start {
            if !char.IsWhiteSpace(text[end - 1]) {
                break
            }

            end = end - 1
        }

        if start >= end {
            return false
        }

        segmentStart := start
        segmentCount := 0
        while segmentStart < end {
            if segmentCount >= 4 {
                return false
            }

            segmentEnd := segmentStart
            while segmentEnd < end {
                if text[segmentEnd] == '.' {
                    break
                }

                segmentEnd = segmentEnd + 1
            }

            if !TryParseVersionIntSegment(text, segmentStart, segmentEnd, result, segmentCount) {
                return false
            }

            segmentCount = segmentCount + 1
            if segmentEnd >= end {
                break
            }

            segmentStart = segmentEnd + 1
            if segmentStart >= end {
                return false
            }
        }

        return segmentCount > 0
    }

    static func TryParseVersionIntSegment(text: string, start: int, end: int, result: int[], resultIndex: int): bool {
        if start >= end {
            return false
        }

        value := 0
        index := start
        while index < end {
            ch := text[index]
            if ch < '0' || ch > '9' {
                return false
            }

            digit := ch - '0'
            if value > 214748364 {
                return false
            }

            if value == 214748364 {
                if digit > 7 {
                    return false
                }
            }

            value = value * 10 + digit
            index = index + 1
        }

        result[resultIndex] = value
        return true
    }

    static func CompareVersionParts(left: int[], right: int[]): int {
        index := 0
        while index < 4 {
            compare := CompareInt(left[index], right[index])
            if compare != 0 {
                return compare
            }

            index = index + 1
        }

        return 0
    }

    static func CopyVersionParts(source: int[], destination: int[]) {
        index := 0
        while index < 4 {
            destination[index] = source[index]
            index = index + 1
        }
    }

    static func CompareInt(left: int, right: int): int {
        if left < right {
            return -1
        }

        if left > right {
            return 1
        }

        return 0
    }

    static func NuGetDependencyVersionRangeInto(version: string, result: int[]): int {
        if result.Length < 2 {
            return -1
        }

        result[0] = -1
        result[1] = 0

        start := 0
        end := version.Length
        while start < end {
            if !char.IsWhiteSpace(version[start]) {
                break
            }

            start = start + 1
        }

        while end > start {
            if !char.IsWhiteSpace(version[end - 1]) {
                break
            }

            end = end - 1
        }

        if start >= end {
            return 0
        }

        while start < end {
            if !NuGetDependencyVersionIsBracket(version[start]) {
                break
            }

            start = start + 1
        }

        while end > start {
            if !NuGetDependencyVersionIsBracket(version[end - 1]) {
                break
            }

            end = end - 1
        }

        segmentStart := start
        while segmentStart < end {
            segmentEnd := segmentStart
            while segmentEnd < end {
                if version[segmentEnd] == ',' {
                    break
                }

                segmentEnd = segmentEnd + 1
            }

            trimStart := segmentStart
            while trimStart < segmentEnd {
                if !char.IsWhiteSpace(version[trimStart]) {
                    break
                }

                trimStart = trimStart + 1
            }

            trimEnd := segmentEnd
            while trimEnd > trimStart {
                if !char.IsWhiteSpace(version[trimEnd - 1]) {
                    break
                }

                trimEnd = trimEnd - 1
            }

            if trimStart < trimEnd {
                result[0] = trimStart
                result[1] = trimEnd - trimStart
                return 1
            }

            if segmentEnd >= end {
                break
            }

            segmentStart = segmentEnd + 1
        }

        return 0
    }

    static func NuGetDependencyVersionIsBracket(ch: char): bool {
        return ch == '[' || ch == ']' || ch == '(' || ch == ')'
    }

    static func NuGetVersionHasPrereleaseSuffix(version: string): bool {
        for versionItem in version {
            if versionItem == '-' {
                return true
            }
        }

        return false
    }

    static func BestNuGetVersionCompare(left: string, right: string, compareScratch: int[]): int {
        code := NuGetVersionCompareInto(left, right, compareScratch)
        if code == 1 {
            compare := compareScratch[0]
            if compare != 0 {
                return compare
            }
        }

        return String.Compare(left, right, StringComparison.OrdinalIgnoreCase)
    }

    static func NuGetVersionCompareInto(x: string, y: string, result: int[]): int {
        if result.Length < 9 {
            return -1
        }

        result[0] = 0
        if !NuGetVersionParseCoreInto(x, result, 1) {
            return 0
        }

        if !NuGetVersionParseCoreInto(y, result, 5) {
            result[0] = 0
            return 0
        }

        result[0] = NuGetVersionCompareParsedComponents(result, 1, 5)
        return 1
    }

    static func NuGetVersionParseCoreInto(value: string, result: int[], resultOffset: int): bool {
        result[resultOffset] = 0
        result[resultOffset + 1] = 0
        result[resultOffset + 2] = 0
        result[resultOffset + 3] = -1

        end := 0
        while end < value.Length {
            if value[end] == '-' {
                break
            }

            end = end + 1
        }

        if end <= 0 {
            return false
        }

        segmentStart := 0
        segmentCount := 0
        while segmentStart < end {
            if segmentCount >= 4 {
                return false
            }

            segmentEnd := segmentStart
            while segmentEnd < end {
                if value[segmentEnd] == '.' {
                    break
                }

                segmentEnd = segmentEnd + 1
            }

            if !NuGetVersionTryParseIntSegment(value, segmentStart, segmentEnd, result, resultOffset + segmentCount) {
                return false
            }

            segmentCount = segmentCount + 1
            if segmentEnd >= end {
                break
            }

            segmentStart = segmentEnd + 1
            if segmentStart >= end {
                return false
            }
        }

        return segmentCount > 0
    }

    static func NuGetVersionCompareParsedComponents(components: int[], leftOffset: int, rightOffset: int): int {
        index := 0
        while index < 4 {
            left := components[leftOffset + index]
            right := components[rightOffset + index]
            compare := CompareInt(left, right)
            if compare != 0 {
                return compare
            }

            index = index + 1
        }

        return 0
    }

    static func NuGetVersionTryParseIntSegment(text: string, start: int, end: int, result: int[], resultIndex: int): bool {
        if start >= end {
            return false
        }

        value := 0
        index := start
        while index < end {
            ch := text[index]
            if ch < '0' || ch > '9' {
                return false
            }

            digit := ch - '0'
            if value > 214748364 {
                return false
            }

            if value == 214748364 {
                if digit > 7 {
                    return false
                }
            }

            value = value * 10 + digit
            index = index + 1
        }

        result[resultIndex] = value
        return true
    }

    static func TargetFrameworkVersionInto(targetFramework: string, result: int[]): int {
        if result.Length < 2 {
            return -1
        }

        result[0] = 0
        result[1] = 0

        start := 0
        while start < targetFramework.Length {
            if TargetFrameworkIsDigit(targetFramework[start]) {
                break
            }

            start = start + 1
        }

        if start >= targetFramework.Length {
            return 0
        }

        end := start
        while end < targetFramework.Length {
            ch := targetFramework[end]
            if !TargetFrameworkIsDigit(ch) && ch != '.' {
                break
            }

            end = end + 1
        }

        majorEnd := start
        while majorEnd < end {
            if targetFramework[majorEnd] == '.' {
                break
            }

            majorEnd = majorEnd + 1
        }

        if !TryParseIntSegment(targetFramework, start, majorEnd, result, 0) {
            result[0] = 0
            result[1] = 0
            return 0
        }

        minorStart := majorEnd
        while minorStart < end {
            if targetFramework[minorStart] != '.' {
                break
            }

            minorStart = minorStart + 1
        }

        if minorStart >= end {
            result[1] = 0
            return 1
        }

        minorEnd := minorStart
        while minorEnd < end {
            if targetFramework[minorEnd] == '.' {
                break
            }

            minorEnd = minorEnd + 1
        }

        if !TryParseIntSegment(targetFramework, minorStart, minorEnd, result, 1) {
            result[1] = 0
        }

        return 1
    }

    static func TryParseIntSegment(text: string, start: int, end: int, result: int[], resultIndex: int): bool {
        if start >= end {
            return false
        }

        value := 0
        index := start
        while index < end {
            ch := text[index]
            if !TargetFrameworkIsDigit(ch) {
                return false
            }

            digit := ch - '0'
            if value > 214748364 {
                return false
            }

            if value == 214748364 {
                if digit > 7 {
                    return false
                }
            }

            value = value * 10 + digit
            index = index + 1
        }

        result[resultIndex] = value
        return true
    }

    static func TargetFrameworkIsDigit(ch: char): bool {
        return ch >= '0' && ch <= '9'
    }

    static func FrameworkCompatibilityScoreInto(assetFramework: string, targetFramework: string, result: int[]): int {
        if result.Length < 5 {
            return -1
        }

        result[0] = -1
        result[1] = 0
        result[2] = 0
        result[3] = 0
        result[4] = 0

        assetStart := FrameworkTrimStart(assetFramework)
        assetEnd := FrameworkTrimEnd(assetFramework, assetStart)
        if assetStart >= assetEnd {
            result[0] = 1
            return 1
        }

        targetStart := FrameworkTrimStart(targetFramework)
        targetEnd := FrameworkTrimEnd(targetFramework, targetStart)
        if FrameworkNormalizedEquals(assetFramework, assetStart, assetEnd, targetFramework, targetStart, targetEnd) {
            result[0] = 10000
            return 1
        }

        // A PLATFORM-QUALIFIED FRAMEWORK (`net8.0-android34.0`) IS COMPATIBLE ONLY WITH A TARGET THAT
        // NAMES THE SAME PLATFORM. NuGet's FrameworkReducer never reduces `net10.0` to
        // `net8.0-android`: scored as plain `net8.0`, the Android group of
        // Microsoft.EntityFrameworkCore.Sqlite's closure won over the portable one and the app
        // shipped `SQLitePCLRaw.lib.e_sqlite3.android`.
        assetPlatformDash := FrameworkPlatformDash(assetFramework, assetStart, assetEnd)
        if assetPlatformDash >= 0 {
            targetPlatformDash := FrameworkPlatformDash(targetFramework, targetStart, targetEnd)
            if targetPlatformDash < 0 || !FrameworkPlatformNamesEqual(assetFramework, assetPlatformDash, assetEnd, targetFramework, targetPlatformDash, targetEnd) {
                result[0] = -1
                return 1
            }

            // The asset's platform version must not exceed the target's: `android35.0` code cannot run
            // on `android34.0`. A target that names no version is `windows7.0` for Windows (the SDK's
            // default) and 0.0 for every other platform, as NuGet normalises it.
            if FrameworkPlatformVersion(assetFramework, assetPlatformDash, assetEnd) > FrameworkTargetPlatformVersion(targetFramework, targetPlatformDash, targetEnd) {
                result[0] = -1
                return 1
            }
        }

        if !FrameworkParseVersionInto(assetFramework, assetStart, assetEnd, result, 1) {
            result[0] = -1
            return 1
        }

        if !FrameworkParseVersionInto(targetFramework, targetStart, targetEnd, result, 3) {
            result[0] = -1
            return 1
        }

        assetMajor := result[1]
        assetMinor := result[2]
        targetMajor := result[3]

        if FrameworkNormalizedStartsWith(assetFramework, assetStart, assetEnd, "netstandard") {
            // .NET Standard ends at 2.1; a higher version is not a framework.
            if (assetMajor * 100) + assetMinor > 201 {
                result[0] = -1
                return 1
            }

            result[0] = 4000 + (assetMajor * 100) + assetMinor
            return 1
        }

        if FrameworkNormalizedStartsWith(assetFramework, assetStart, assetEnd, "netcoreapp") {
            if assetMajor <= targetMajor {
                result[0] = 7000 + (assetMajor * 100) + assetMinor
            } else {
                result[0] = -1
            }

            return 1
        }

        if FrameworkNormalizedStartsWith(assetFramework, assetStart, assetEnd, "net") {
            if assetMajor >= 5 {
                if targetMajor >= 5 {
                    if assetMajor <= targetMajor {
                        result[0] = 8000 + (assetMajor * 100) + assetMinor
                        // The same platform beats the portable folder of the same version, never a newer one.
                        if assetPlatformDash >= 0 {
                            result[0] = result[0] + 50
                        }
                    } else {
                        result[0] = -1
                    }

                    return 1
                }
            }
        }

        result[0] = -1
        return 1
    }

    // The index of the `-` that starts a framework's platform (`net8.0-android34.0`), or -1.
    static func FrameworkPlatformDash(text: string, start: int, end: int): int {
        index := start
        while index < end {
            if text[index] == '-' {
                return index
            }

            index = index + 1
        }

        return -1
    }

    // The platform NAME after the dash, ignoring its version: `android34.0` and `android` are one.
    static func FrameworkPlatformNameEnd(text: string, dash: int, end: int): int {
        index := dash + 1
        while index < end {
            if TargetFrameworkIsDigit(text[index]) || text[index] == '.' {
                break
            }

            index = index + 1
        }

        return index
    }

    // The platform version after the name as major * 100 + minor (`android34.0` -> 3400), 0 for none.
    static func FrameworkPlatformVersion(text: string, dash: int, end: int): int {
        index := FrameworkPlatformNameEnd(text, dash, end)
        major := 0
        while index < end && TargetFrameworkIsDigit(text[index]) {
            major = major * 10 + (text[index] - '0')
            index = index + 1
        }

        minor := 0
        if index < end && text[index] == '.' {
            index = index + 1
            while index < end && TargetFrameworkIsDigit(text[index]) {
                minor = minor * 10 + (text[index] - '0')
                index = index + 1
            }
        }

        return major * 100 + minor
    }

    static func FrameworkTargetPlatformVersion(text: string, dash: int, end: int): int {
        version := FrameworkPlatformVersion(text, dash, end)
        if version == 0 && string.Equals(text.Substring(dash + 1, FrameworkPlatformNameEnd(text, dash, end) - dash - 1), "windows", StringComparison.OrdinalIgnoreCase) {
            return 700
        }

        return version
    }

    static func FrameworkPlatformNamesEqual(left: string, leftDash: int, leftEnd: int, right: string, rightDash: int, rightEnd: int): bool {
        leftNameEnd := FrameworkPlatformNameEnd(left, leftDash, leftEnd)
        rightNameEnd := FrameworkPlatformNameEnd(right, rightDash, rightEnd)
        if leftNameEnd - leftDash != rightNameEnd - rightDash {
            return false
        }

        offset := 1
        while leftDash + offset < leftNameEnd {
            if FrameworkAsciiLower(left[leftDash + offset]) != FrameworkAsciiLower(right[rightDash + offset]) {
                return false
            }

            offset = offset + 1
        }

        return true
    }

    static func FrameworkTrimStart(text: string): int {
        index := 0
        while index < text.Length {
            if !char.IsWhiteSpace(text[index]) {
                break
            }

            index = index + 1
        }

        return index
    }

    static func FrameworkTrimEnd(text: string, start: int): int {
        end := text.Length
        while end > start {
            if !char.IsWhiteSpace(text[end - 1]) {
                break
            }

            end = end - 1
        }

        return end
    }

    static func FrameworkNormalizedEquals(left: string, leftStart: int, leftEnd: int, right: string, rightStart: int, rightEnd: int): bool {
        leftLength := FrameworkNormalizedLength(left, leftStart, leftEnd)
        if leftLength != FrameworkNormalizedLength(right, rightStart, rightEnd) {
            return false
        }

        index := 0
        while index < leftLength {
            leftCh := FrameworkNormalizedCharAt(left, leftStart, leftEnd, index)
            rightCh := FrameworkNormalizedCharAt(right, rightStart, rightEnd, index)
            if leftCh != rightCh {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func FrameworkNormalizedStartsWith(text: string, start: int, end: int, prefix: string): bool {
        if FrameworkNormalizedLength(text, start, end) < prefix.Length {
            return false
        }

        index := 0
        while index < prefix.Length {
            if FrameworkNormalizedCharAt(text, start, end, index) != FrameworkAsciiLower(prefix[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func FrameworkNormalizedLength(text: string, start: int, end: int): int {
        kind := FrameworkNormalizedKind(text, start, end)
        if kind == 0 {
            return end - start
        }

        suffixStart := FrameworkNormalizedSuffixStart(text, start, end, kind)
        prefixLength := FrameworkNormalizedPrefixLength(kind)
        if kind != 3 {
            return prefixLength + end - suffixStart
        }

        suffixLength := 0
        index := suffixStart
        while index < end {
            if text[index] != '.' {
                suffixLength = suffixLength + 1
            }

            index = index + 1
        }

        return prefixLength + suffixLength
    }

    static func FrameworkNormalizedCharAt(text: string, start: int, end: int, index: int): char {
        kind := FrameworkNormalizedKind(text, start, end)
        if kind == 0 {
            return FrameworkAsciiLower(text[start + index])
        }

        prefixLength := FrameworkNormalizedPrefixLength(kind)
        if index < prefixLength {
            return FrameworkNormalizedPrefixChar(kind, index)
        }

        suffixStart := FrameworkNormalizedSuffixStart(text, start, end, kind)
        suffixIndex := index - prefixLength
        if kind != 3 {
            return FrameworkAsciiLower(text[suffixStart + suffixIndex])
        }

        seen := 0
        position := suffixStart
        while position < end {
            ch := text[position]
            if ch != '.' {
                if seen == suffixIndex {
                    return FrameworkAsciiLower(ch)
                }

                seen = seen + 1
            }

            position = position + 1
        }

        return '?'
    }

    static func FrameworkNormalizedKind(text: string, start: int, end: int): int {
        if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETCoreApp,Version=v") {
            return 1
        }

        if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETCoreApp") {
            return 1
        }

        if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETStandard,Version=v") {
            return 2
        }

        if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETStandard") {
            return 2
        }

        if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETFramework,Version=v") {
            return 3
        }

        if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETFramework") {
            return 3
        }

        return 0
    }

    static func FrameworkNormalizedSuffixStart(text: string, start: int, end: int, kind: int): int {
        if kind == 1 {
            if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETCoreApp,Version=v") {
                return start + 21
            }

            return start + 11
        }

        if kind == 2 {
            if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETStandard,Version=v") {
                return start + 22
            }

            return start + 12
        }

        if kind == 3 {
            if FrameworkRawStartsWithIgnoreCase(text, start, end, ".NETFramework,Version=v") {
                return start + 23
            }

            return start + 13
        }

        return start
    }

    static func FrameworkNormalizedPrefixLength(kind: int): int {
        if kind == 1 {
            return 10
        }

        if kind == 2 {
            return 11
        }

        if kind == 3 {
            return 3
        }

        return 0
    }

    static func FrameworkNormalizedPrefixChar(kind: int, index: int): char {
        if kind == 1 {
            return "netcoreapp"[index]
        }

        if kind == 2 {
            return "netstandard"[index]
        }

        return "net"[index]
    }

    static func FrameworkRawStartsWithIgnoreCase(text: string, start: int, end: int, prefix: string): bool {
        if start + prefix.Length > end {
            return false
        }

        index := 0
        while index < prefix.Length {
            if FrameworkAsciiLower(text[start + index]) != FrameworkAsciiLower(prefix[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func FrameworkParseVersionInto(text: string, start: int, end: int, result: int[], resultOffset: int): bool {
        result[resultOffset] = 0
        result[resultOffset + 1] = 0

        length := FrameworkNormalizedLength(text, start, end)
        digitStart := 0
        while digitStart < length {
            if TargetFrameworkIsDigit(FrameworkNormalizedCharAt(text, start, end, digitStart)) {
                break
            }

            digitStart = digitStart + 1
        }

        if digitStart >= length {
            return false
        }

        digitsEnd := digitStart
        while digitsEnd < length {
            ch := FrameworkNormalizedCharAt(text, start, end, digitsEnd)
            if !TargetFrameworkIsDigit(ch) && ch != '.' {
                break
            }

            digitsEnd = digitsEnd + 1
        }

        majorEnd := digitStart
        while majorEnd < digitsEnd {
            if FrameworkNormalizedCharAt(text, start, end, majorEnd) == '.' {
                break
            }

            majorEnd = majorEnd + 1
        }

        if !FrameworkTryParseNormalizedIntSegment(text, start, end, digitStart, majorEnd, result, resultOffset) {
            result[resultOffset] = 0
            result[resultOffset + 1] = 0
            return false
        }

        minorStart := majorEnd
        while minorStart < digitsEnd {
            if FrameworkNormalizedCharAt(text, start, end, minorStart) != '.' {
                break
            }

            minorStart = minorStart + 1
        }

        if minorStart >= digitsEnd {
            result[resultOffset + 1] = 0
            return true
        }

        minorEnd := minorStart
        while minorEnd < digitsEnd {
            if FrameworkNormalizedCharAt(text, start, end, minorEnd) == '.' {
                break
            }

            minorEnd = minorEnd + 1
        }

        if !FrameworkTryParseNormalizedIntSegment(text, start, end, minorStart, minorEnd, result, resultOffset + 1) {
            result[resultOffset + 1] = 0
        }

        return true
    }

    static func FrameworkTryParseNormalizedIntSegment(text: string, start: int, end: int, segmentStart: int, segmentEnd: int, result: int[], resultIndex: int): bool {
        if segmentStart >= segmentEnd {
            return false
        }

        value := 0
        index := segmentStart
        while index < segmentEnd {
            ch := FrameworkNormalizedCharAt(text, start, end, index)
            if !TargetFrameworkIsDigit(ch) {
                return false
            }

            digit := ch - '0'
            if value > 214748364 {
                return false
            }

            if value == 214748364 {
                if digit > 7 {
                    return false
                }
            }

            value = value * 10 + digit
            index = index + 1
        }

        result[resultIndex] = value
        return true
    }

    static func FrameworkAsciiLower(ch: char): char {
        return Char.ToLowerInvariant(ch)
    }

    static func PathSegmentEqualsIgnoreCase(path: string, start: int, end: int, segment: string): bool {
        length := end - start
        if length != segment.Length {
            return false
        }

        index := 0
        while index < segment.Length {
            if !PathCharsEqualIgnoreCase(path[start + index], segment[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func PathCharsEqualIgnoreCase(left: char, right: char): bool {
        return Char.ToLowerInvariant(left) == Char.ToLowerInvariant(right)
    }

    static func ContainsPackageId(packageIds: string[], packageName: string): bool {
        for packageId in packageIds {
            if string.Equals(packageId, packageName, StringComparison.OrdinalIgnoreCase) {
                return true
            }
        }

        return false
    }

    // A project whose package closure includes Microsoft.AspNetCore.Mvc.Testing hosts an application
    // in-process, and `WebApplicationFactory` requires that application's `deps.json` beside the test
    // assembly. The package's own MSBuild targets copy the file; the closure is the signal here.
    static func FlowsReferencedDependencyManifest(selectedVersions: Dictionary<string, string>): bool {
        return selectedVersions.ContainsKey(NormalizeNuGetPackageId("Microsoft.AspNetCore.Mvc.Testing"))
    }

    // ── RUNTIME IDENTIFIERS AND PACKAGE RUNTIME FILES ───────────────────────────

    // THE RID GRAPH FALLBACK, MOST SPECIFIC FIRST. A package ships `runtimes/<rid>/native/*` for a
    // handful of portable RIDs (`osx`, `linux-x64`, `win-arm64`) and the host's own RID is far more
    // specific (`osx.14-arm64`, `ubuntu.22.04-x64`, `linux-musl-arm64`). Walking this list and taking
    // the first RID a package ships is the runtime-identifier graph's rule, flattened: the exact RID,
    // its versionless form, the operating system on this architecture, the bare operating system, its
    // family (a distribution is `linux`, Alpine is `linux-musl` then `linux`), `unix` for everything
    // that is not Windows, and finally `any`.
    static func GetRuntimeIdentifierFallbacks(runtimeIdentifier: string): string[] {
        result := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        AddUniqueText(result, seen, runtimeIdentifier)

        architecture := ""
        operatingSystem := runtimeIdentifier
        dash := runtimeIdentifier.LastIndexOf('-')
        if dash > 0 && dash < runtimeIdentifier.Length - 1 {
            candidate := runtimeIdentifier.Substring(dash + 1)
            if IsKnownArchitecture(candidate) {
                architecture = candidate
                operatingSystem = runtimeIdentifier.Substring(0, dash)
            }
        }

        AddUniqueText(result, seen, operatingSystem)

        baseSystem := operatingSystem
        dot := operatingSystem.IndexOf('.')
        if dot > 0 {
            baseSystem = operatingSystem.Substring(0, dot)
        }

        if baseSystem.StartsWith("win", StringComparison.OrdinalIgnoreCase) {
            baseSystem = "win"
        }

        family := new List<string>()
        if string.Equals(baseSystem, "win", StringComparison.OrdinalIgnoreCase) {
            // win11 -> win10 -> win81 -> win8 -> win7 -> win: each older Windows is a fallback.
            versionName := operatingSystem
            while versionName.Length > 0 {
                family.Add(versionName)
                versionName = GetWindowsRuntimeIdentifierParent(versionName)
            }

            family.Add("win")
        } else {
            current := baseSystem
            guard := 0
            while current.Length > 0 && guard < 8 {
                family.Add(current)
                current = GetLinuxRuntimeIdentifierParent(current)
                guard = guard + 1
            }
        }

        for osName in family {
            rhelVersion := ""
            if string.Equals(osName, baseSystem, StringComparison.OrdinalIgnoreCase) && !string.Equals(baseSystem, "rhel", StringComparison.OrdinalIgnoreCase) {
                rhelVersion = GetRedHatRuntimeIdentifierVersion(baseSystem, operatingSystem)
            }

            if architecture.Length > 0 {
                AddUniqueText(result, seen, osName + "-" + architecture)
            }

            // Rocky, CentOS, and Oracle Linux RIDs import the same-version RHEL RID after their
            // architecture-specific RID and before their generic RID (e.g. rocky.9-x64 imports
            // rocky.9, rocky-x64, rhel.9-x64, rocky, rhel.9, rhel-x64, rhel).
            if rhelVersion.Length > 0 && architecture.Length > 0 {
                AddUniqueText(result, seen, "rhel." + rhelVersion + "-" + architecture)
            }

            AddUniqueText(result, seen, osName)

            if rhelVersion.Length > 0 {
                AddUniqueText(result, seen, "rhel." + rhelVersion)
            }
        }

        if !string.Equals(baseSystem, "win", StringComparison.OrdinalIgnoreCase) {
            if architecture.Length > 0 {
                AddUniqueText(result, seen, "unix-" + architecture)
            }

            AddUniqueText(result, seen, "unix")
        }

        AddUniqueText(result, seen, "any")
        return result.ToArray()
    }

    private static func GetRedHatRuntimeIdentifierVersion(baseSystem: string, operatingSystem: string): string {
        if !string.Equals(baseSystem, "rocky", StringComparison.OrdinalIgnoreCase) && !string.Equals(baseSystem, "centos", StringComparison.OrdinalIgnoreCase) && !string.Equals(baseSystem, "ol", StringComparison.OrdinalIgnoreCase) {
            return ""
        }

        dot := operatingSystem.IndexOf('.')
        if dot < 0 || dot + 1 >= operatingSystem.Length {
            return ""
        }

        return operatingSystem.Substring(dot + 1)
    }

    static func IsKnownArchitecture(candidate: string): bool {
        known := ["x64", "x86", "arm", "arm64", "armel", "armv6", "s390x", "ppc64le", "loongarch64", "riscv64", "mips64", "wasm"]
        for architecture in known {
            if string.Equals(candidate, architecture, StringComparison.OrdinalIgnoreCase) {
                return true
            }
        }

        return false
    }

    // The parent a Linux RID falls back to in the runtime identifier graph: a derivative names its
    // base distribution, every distribution names `linux`, and Alpine names `linux-musl`. Empty for
    // a RID with no parent (`osx`, `freebsd`, `linux`).
    static func GetLinuxRuntimeIdentifierParent(systemName: string): string {
        derived := ["linuxmint:ubuntu", "pop:ubuntu", "elementary:ubuntu", "kali:debian", "raspbian:debian", "ubuntu:debian", "debian:linux", "centos:rhel", "ol:rhel", "rocky:rhel", "rhel:linux", "fedora:linux", "sles:linux", "opensuse:linux", "arch:linux", "gentoo:linux", "tizen:linux", "alpine:linux-musl", "linux-musl:linux"]
        for entry in derived {
            separator := entry.IndexOf(':')
            if string.Equals(entry.Substring(0, separator), systemName, StringComparison.OrdinalIgnoreCase) {
                return entry.Substring(separator + 1)
            }
        }

        return ""
    }

    static func GetWindowsRuntimeIdentifierParent(systemName: string): string {
        if string.Equals(systemName, "win11", StringComparison.OrdinalIgnoreCase) {
            return "win10"
        }

        if string.Equals(systemName, "win10", StringComparison.OrdinalIgnoreCase) {
            return "win81"
        }

        if string.Equals(systemName, "win81", StringComparison.OrdinalIgnoreCase) {
            return "win8"
        }

        if string.Equals(systemName, "win8", StringComparison.OrdinalIgnoreCase) {
            return "win7"
        }

        return ""
    }

    // A package file's path from its version directory, with `/` separators on every platform: the
    // form a `deps.json` row and the copied `runtimes/<rid>/...` layout both use.
    static func GetPackageRelativePath(versionDirectory: string, filePath: string): string {
        return Path.GetRelativePath(versionDirectory, filePath).Replace('\\', '/')
    }

    // NuGet writes `_._` into a folder that must exist but must not contribute a file.
    static func IsPackagePlaceholderFile(filePath: string): bool {
        return string.Equals(Path.GetFileName(filePath), "_._", StringComparison.Ordinal)
    }

    // A runtime deps manifest belongs to a .NET 5+ application target, e.g.
    // `net10.0` -> `.NETCoreApp,Version=v10.0`. Libraries targeting .NET Standard, .NET Framework,
    // or pre-.NET 5 .NET Core do not have an application runtime target to write here.
    static func SupportsDependencyManifestTarget(targetFramework: string): bool {
        if string.IsNullOrWhiteSpace(targetFramework) {
            return false
        }

        moniker := targetFramework
        platformDash := moniker.IndexOf('-')
        if platformDash >= 0 {
            moniker = moniker.Substring(0, platformDash)
        }

        if !moniker.StartsWith("net", StringComparison.OrdinalIgnoreCase) || moniker.StartsWith("netstandard", StringComparison.OrdinalIgnoreCase) || moniker.StartsWith("netcoreapp", StringComparison.OrdinalIgnoreCase) {
            return false
        }

        version := moniker.Substring(3)
        if version.Length == 0 {
            return false
        }

        // Compact `net48` is .NET Framework 4.8; `net10` is modern shorthand for .NET 10.
        if version.IndexOf('.') < 0 && version.Length >= 2 && version[0] >= '1' && version[0] <= '4' && version != "10" {
            return false
        }

        majorEnd := version.IndexOf('.')
        if majorEnd < 0 {
            majorEnd = version.Length
        }

        major := 0
        if !int.TryParse(version.Substring(0, majorEnd), out major) {
            return false
        }

        return major >= 5
    }

    static func GetDependencyManifestTargetName(targetFramework: string): string {
        ArgumentException.ThrowIfNullOrWhiteSpace(targetFramework)
        if !SupportsDependencyManifestTarget(targetFramework) {
            throw new ArgumentException("Dependency manifests require a .NET 5.0 or later target framework.")
        }

        moniker := targetFramework
        platformDash := moniker.IndexOf('-')
        if platformDash >= 0 {
            moniker = moniker.Substring(0, platformDash)
        }

        version := moniker
        version = moniker.Substring(3)

        if version.IndexOf('.') < 0 {
            version = version + ".0"
        }

        return ".NETCoreApp,Version=v" + version
    }

    // The file names an unmanaged library name can mean on one operating system, in the order the
    // runtime itself tries them: the name as written, then with the platform's prefix and suffix.
    static func GetNativeLibraryFileNames(libraryName: string, isWindows: bool, isMacOS: bool): string[] {
        names := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)
        suffix := ".so"
        prefix := "lib"
        if isWindows {
            suffix = ".dll"
            prefix = ""
        } else if isMacOS {
            suffix = ".dylib"
        }

        AddUniqueText(names, seen, libraryName)
        if !libraryName.EndsWith(suffix, StringComparison.OrdinalIgnoreCase) {
            AddUniqueText(names, seen, libraryName + suffix)
            AddUniqueText(names, seen, prefix + libraryName + suffix)
            AddUniqueText(names, seen, prefix + libraryName)
        }

        return names.ToArray()
    }

    static func AddSharedRootCandidate(candidates: List<string>, yielded: HashSet<string>, candidate: string) {
        if !string.IsNullOrWhiteSpace(candidate) && yielded.Add(candidate) {
            candidates.Add(candidate)
        }
    }

    static func AddUniqueText(values: List<string>, seen: HashSet<string>, value: string) {
        if !string.IsNullOrWhiteSpace(value) && seen.Add(value) {
            values.Add(value)
        }
    }
}
