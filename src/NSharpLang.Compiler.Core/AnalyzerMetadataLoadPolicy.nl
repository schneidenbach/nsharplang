namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// EVERY DECISION THE ANALYZER'S METADATA-LOADING SURFACE MAKES, and none of the mechanics that
// perform them.
//
// The analyzer inspects referenced assemblies through a `MetadataLoadContext`. That context, its
// resolver and the `System.Reflection` objects they hand back are ECOSYSTEM MECHANICS: the CLR
// fixes their shape and there is no product choice in any of them. What is NOT mechanical is
// everything the surface has to DECIDE on the way — which assemblies to pre-load, where a package
// lives on disk, which of several extracted versions answers, which target-framework asset to read,
// when two loads are the same load, and what a project reference resolves to. Those decisions have
// user-visible consequences: they decide whether `import System.Text.Json` resolves at all, which
// version of a package's metadata a diagnostic is computed against, and whether a reference load
// failure becomes an `NL923`.
//
// This owner holds those decisions and nothing else. Every function here is pure: strings, paths and
// version spellings in, an answer out. The caller performs the IO and drives the load context.
//
// THREE OF THE ANSWERS HERE ARE DEFINED FROM OWNERS THAT ALREADY EXISTED rather than copied:
// `NuGetPackageCacheDirectory` is `CompilationReferenceResolverKernels.GetGlobalPackagesFolder` +
// `GetNuGetPackageDirectory`, which the CLI's reference resolver has answered since long before this
// file; and `CommonAssemblyNames` is `ExternalAssemblyScan.CommonAssemblyNames`, which the columnar
// back end's own scan has answered for as long. A second spelling of either is a drift waiting to
// happen, and both had already drifted once — see the two notes below.
class AnalyzerMetadataLoadPolicy {

    // ── WHICH ASSEMBLIES THE ANALYZER PRE-LOADS ──────────────────────────────────────────────────
    //
    // THE ONE TABLE, SHARED WITH THE COLUMNAR SCAN. The analyzer used to carry its own copy of this
    // list, and the copy had DRIFTED: it held twenty-six of the scan's twenty-seven names, in the
    // same order, missing only `System.Private.Xml.Linq`. Nothing decided that the analyzer should
    // see fewer assemblies than the back end; one list simply grew and the other did not. They are
    // one list now, and the name they disagreed on is the one that makes LINQ-to-XML types visible
    // to a metadata scan at all.
    static func CommonAssemblyNames(): string[] {
        return ExternalAssemblyScan.CommonAssemblyNames()
    }

    // THE CORE ASSEMBLY the metadata load context binds its primitives against. Every `int`, `string`
    // and `object` a referenced assembly names is resolved through this one identity, so it is the
    // single name the context cannot be built without.
    static func MetadataCoreAssemblyName(): string {
        return "System.Runtime"
    }

    // A WEB PROJECT NEEDS MORE THAN THE COMMON TABLE, and the trigger is the project's SDK spelling
    // containing `Web` — the same substring `Microsoft.NET.Sdk.Web` carries. This is a contains test
    // rather than an equality test on purpose: the SDK id a user writes is not a closed set.
    static func RequiresAspNetCoreAssemblies(sdk: string?): bool {
        if sdk == null {
            return false
        }

        return sdk.Contains("Web")
    }

    static func AspNetCoreAssemblyNames(): string[] {
        names := new string[](8)
        names[0] = "Microsoft.AspNetCore"
        names[1] = "Microsoft.AspNetCore.Http"
        names[2] = "Microsoft.AspNetCore.Http.Abstractions"
        names[3] = "Microsoft.AspNetCore.Mvc.Core"
        names[4] = "Microsoft.AspNetCore.Mvc.Abstractions"
        names[5] = "Microsoft.AspNetCore.Routing"
        names[6] = "Microsoft.Extensions.DependencyInjection"
        names[7] = "Microsoft.Extensions.DependencyInjection.Abstractions"
        return names
    }

    // ── THE SHARED-FRAMEWORK WALK ────────────────────────────────────────────────────────────────
    //
    // The runtime directory a host reports is `…/shared/Microsoft.NETCore.App/<version>`. The
    // framework assemblies the analyzer wants sit BESIDE it, under the same `shared` root, so the
    // walk climbs parents until it finds a directory literally named `shared`. It stops after five
    // levels: `shared` is two above the runtime directory on every layout .NET ships, and an
    // unbounded climb on an unexpected layout would walk to the filesystem root adding search
    // directories that cannot contain framework assemblies.
    static func MaximumSharedRootSearchDepth(): int {
        return 5
    }

    static func SharedRootFromRuntimeDirectory(runtimeDirectory: string?): string? {
        current := runtimeDirectory
        depth := 0
        while depth < MaximumSharedRootSearchDepth() {
            current = Path.GetDirectoryName(current ?? "")
            if current == null {
                return null
            }

            if Path.GetFileName(current) == "shared" {
                return current
            }

            depth = depth + 1
        }

        return null
    }

    // BOTH SHIPPED FRAMEWORKS, ASP.NET FIRST. The order decides which copy of a type that both
    // frameworks carry is registered first, and a first-loaded-wins registry makes that visible.
    static func SharedFrameworkDirectoryNames(): string[] {
        names := new string[](2)
        names[0] = "Microsoft.AspNetCore.App"
        names[1] = "Microsoft.NETCore.App"
        return names
    }

    // ── WHERE A PACKAGE LIVES ────────────────────────────────────────────────────────────────────
    //
    // DEFINED FROM THE CLI'S OWN RESOLVER. `nlc restore` and the analyzer have to agree about where
    // the package cache is or the analyzer reads metadata for a package the build never restored.
    // They are the same two functions now.
    static func NuGetPackageCacheDirectory(configuredRoot: string?, userProfileFolder: string, packageName: string): string {
        root := CompilationReferenceResolverKernels.GetGlobalPackagesFolder(configuredRoot, userProfileFolder)
        return CompilationReferenceResolverKernels.GetNuGetPackageDirectory(root, packageName)
    }

    static func NuGetPackagesRoot(configuredRoot: string?, userProfileFolder: string): string {
        return CompilationReferenceResolverKernels.GetGlobalPackagesFolder(configuredRoot, userProfileFolder)
    }

    // A LOCALLY BUILT COPY OUTRANKS THE CACHE. When the project's own output directory already holds
    // an assembly with the package's name, that is the copy the build will bind against, so it is
    // the copy the analyzer must read metadata from — otherwise a developer editing a sibling
    // project sees diagnostics computed against the published package instead of their own build.
    static func LocallyBuiltPackageAssemblyPath(projectDirectory: string, targetFramework: string, packageName: string): string {
        return Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), targetFramework), AssemblyFileName(packageName))
    }

    // AN ASSEMBLY'S SIMPLE NAME IS ITS FILE NAME. Every probe in the loading surface — the search
    // directories, the package `lib` folders, the project outputs — looks for exactly this, and the
    // convention is spelled once so a probe cannot look for a file the emitter would not have
    // written.
    static func AssemblyFileName(simpleName: string): string {
        return simpleName + ".dll"
    }

    // THE RESTORED VERSION PINS THE DIRECTORY; failing that, the highest extracted version answers.
    // A stale extraction next to the restored one is the shape this guards against: without the pin,
    // a cache holding `2.0.0` alongside the restored `1.4.0` would answer with metadata the build
    // never references.
    static func PackageVersionDirectory(cacheDirectory: string, version: string?, extractedVersionDirectories: string[]): string? {
        if version != null {
            return Path.Combine(cacheDirectory, version)
        }

        return PickHighestVersionDirectory(extractedVersionDirectories)
    }

    static func PackageLibRoot(versionDirectory: string): string {
        return Path.Combine(versionDirectory, "lib")
    }

    static func PackageLibAssetPath(versionDirectory: string, targetFramework: string, packageName: string): string {
        return Path.Combine(Path.Combine(PackageLibRoot(versionDirectory), targetFramework), AssemblyFileName(packageName))
    }

    static func SearchDirectoryAssemblyPath(searchDirectory: string, simpleName: string): string {
        return Path.Combine(searchDirectory, AssemblyFileName(simpleName))
    }

    // ── WHICH TARGET-FRAMEWORK ASSET ANSWERS ─────────────────────────────────────────────────────
    //
    // ONE ORDER, TWO VIEWS, AND THIS TOO HAD DRIFTED. The analyzer probed a package's `lib` folder
    // through two different lists in the same file: the direct load tried the project's own target
    // framework and then five fallbacks, while the load context's resolver tried seven and never the
    // project's. A package publishing only `lib/net6.0` was therefore invisible to a `nuget:`
    // dependency the user wrote down and visible to the same package arriving as a transitive
    // resolve — which reads as the compiler finding a type only sometimes. The fallback ladder is
    // one list now; the direct view simply puts the project's own framework in front of it, which is
    // the only thing that ever distinguished the two.
    static func FallbackTargetFrameworks(): string[] {
        names := new string[](7)
        names[0] = "net10.0"
        names[1] = "net9.0"
        names[2] = "net8.0"
        names[3] = "net7.0"
        names[4] = "net6.0"
        names[5] = "netstandard2.1"
        names[6] = "netstandard2.0"
        return names
    }

    static func MetadataProbeTargetFrameworks(projectTargetFramework: string?): string[] {
        fallbacks := FallbackTargetFrameworks()
        if string.IsNullOrWhiteSpace(projectTargetFramework ?? "") {
            return fallbacks
        }

        ordered := new List<string>()
        ordered.Add(projectTargetFramework ?? "")
        index := 0
        while index < fallbacks.Length {
            if fallbacks[index] != (projectTargetFramework ?? "") {
                ordered.Add(fallbacks[index])
            }

            index = index + 1
        }

        return ordered.ToArray()
    }

    // ── SEMVER PRECEDENCE OVER EXTRACTED VERSION FOLDER NAMES ────────────────────────────────────
    //
    // THIS IS NOT ORDINAL STRING ORDER AND THE DIFFERENCE IS VISIBLE. Ordinal order ranks
    // `0.1.0-beta` above `0.1.0` and `0.10.0` below `0.9.0`, so a cache holding a prerelease beside
    // its release would answer with the prerelease. The rules, in the order they apply:
    //
    //   * `+build.metadata` is not part of precedence and is discarded before anything else;
    //   * up to four dot-separated numeric parts compare NUMERICALLY, missing parts being zero;
    //   * a release outranks every prerelease of the same numbers;
    //   * prerelease identifiers compare dot-part by dot-part: numeric parts numerically, numeric
    //     below alphanumeric, otherwise ordinally, and a shorter run of identifiers loses to a longer
    //     one that matched it so far;
    //   * a spelling that does not parse at all sorts BELOW every one that does, and two of them
    //     fall back to ordinal order so the answer is still total and still deterministic.
    static func CompareVersionSpellings(x: string?, y: string?): int {
        if x == null && y == null {
            return 0
        }

        if x == null {
            return -1
        }

        if y == null {
            return 1
        }

        leftNumbers := new long[](4)
        rightNumbers := new long[](4)
        leftPrerelease := ""
        rightPrerelease := ""

        parsedLeft := TryParseVersionSpelling(x, leftNumbers, out leftPrerelease)
        parsedRight := TryParseVersionSpelling(y, rightNumbers, out rightPrerelease)

        if !parsedLeft || !parsedRight {
            if parsedLeft == parsedRight {
                return CompareOrdinalText(x, y)
            }

            if parsedLeft {
                return 1
            }

            return -1
        }

        index := 0
        while index < leftNumbers.Length {
            if leftNumbers[index] < rightNumbers[index] {
                return -1
            }

            if leftNumbers[index] > rightNumbers[index] {
                return 1
            }

            index = index + 1
        }

        if leftPrerelease.Length == 0 {
            if rightPrerelease.Length == 0 {
                return 0
            }

            return 1
        }

        if rightPrerelease.Length == 0 {
            return -1
        }

        return ComparePrereleaseIdentifiers(leftPrerelease, rightPrerelease)
    }

    static func TryParseVersionSpelling(version: string, numbers: long[], out prerelease: string): bool {
        prerelease = ""
        index := 0
        while index < numbers.Length {
            numbers[index] = 0L
            index = index + 1
        }

        text := version
        metadataStart := text.IndexOf('+')
        if metadataStart >= 0 {
            text = text.Substring(0, metadataStart)
        }

        prereleaseStart := text.IndexOf('-')
        if prereleaseStart >= 0 {
            prerelease = text.Substring(prereleaseStart + 1, text.Length - prereleaseStart - 1)
            text = text.Substring(0, prereleaseStart)
        }

        parts := text.Split('.')
        if parts.Length < 1 || parts.Length > 4 {
            prerelease = ""
            return false
        }

        part := 0
        while part < parts.Length {
            value := 0L
            if !TryParseUnsignedNumber(parts[part], out value) {
                prerelease = ""
                return false
            }

            numbers[part] = value
            part = part + 1
        }

        return true
    }

    // THE NUMERIC PARSE IS DELIBERATELY STRICT — `NumberStyles.None`. No sign, no thousands
    // separator, no surrounding whitespace: a folder named ` 1` or `-1` or `1 000` is not a version
    // part, and admitting one would let a directory that is not a package version outrank one that
    // is. An empty segment (`1..0`) is not a number either.
    static func TryParseUnsignedNumber(text: string, out value: long): bool {
        value = 0L
        if text == null || text.Length == 0 {
            return false
        }

        accumulated := 0L
        index := 0
        while index < text.Length {
            digit := text[index]
            if digit < '0' || digit > '9' {
                return false
            }

            step := (long)digit - (long)'0'
            // OVERFLOW IS A PARSE FAILURE, not a wrap. A folder name whose numeric part will not fit
            // is not a version part, and a silent wrap would let an absurd spelling outrank a real
            // version instead of sorting below every parseable one.
            if accumulated > (long.MaxValue - step) / 10L {
                return false
            }

            accumulated = accumulated * 10L + step
            index = index + 1
        }

        value = accumulated
        return true
    }

    static func ComparePrereleaseIdentifiers(x: string, y: string): int {
        leftIdentifiers := x.Split('.')
        rightIdentifiers := y.Split('.')
        limit := leftIdentifiers.Length
        if rightIdentifiers.Length > limit {
            limit = rightIdentifiers.Length
        }

        index := 0
        while index < limit {
            if index >= leftIdentifiers.Length {
                return -1
            }

            if index >= rightIdentifiers.Length {
                return 1
            }

            leftValue := 0L
            rightValue := 0L
            leftNumeric := TryParseUnsignedNumber(leftIdentifiers[index], out leftValue)
            rightNumeric := TryParseUnsignedNumber(rightIdentifiers[index], out rightValue)

            if leftNumeric && rightNumeric {
                if leftValue < rightValue {
                    return -1
                }

                if leftValue > rightValue {
                    return 1
                }
            } else if leftNumeric != rightNumeric {
                if leftNumeric {
                    return -1
                }

                return 1
            } else {
                byText := CompareOrdinalText(leftIdentifiers[index], rightIdentifiers[index])
                if byText != 0 {
                    return byText
                }
            }

            index = index + 1
        }

        return 0
    }

    // ORDINAL COMPARISON BY CODE UNIT, spelled out rather than delegated. The pinned bootstrap
    // toolset does not model `string.CompareOrdinal` or `StringComparer.Ordinal.Compare` on this
    // emit path (the same wall `AnalyzerReferenceLoadReport` records for the two-argument
    // `Array.Sort`), and the SIGN is the whole of what an ordering consumes.
    static func CompareOrdinalText(x: string, y: string): int {
        limit := x.Length
        if y.Length < limit {
            limit = y.Length
        }

        index := 0
        while index < limit {
            left := (int)x[index]
            right := (int)y[index]
            if left != right {
                if left < right {
                    return -1
                }

                return 1
            }

            index = index + 1
        }

        if x.Length < y.Length {
            return -1
        }

        if x.Length > y.Length {
            return 1
        }

        return 0
    }

    // THE HIGHEST EXTRACTED VERSION, chosen by the precedence above over the directories' LEAF
    // NAMES. Ties keep the first directory the caller listed, so the answer does not depend on how
    // the filesystem happened to enumerate.
    static func PickHighestVersionDirectory(versionDirectories: string[]): string? {
        if versionDirectories == null || versionDirectories.Length == 0 {
            return null
        }

        bestIndex := 0
        index := 1
        while index < versionDirectories.Length {
            candidate := Path.GetFileName(versionDirectories[index])
            best := Path.GetFileName(versionDirectories[bestIndex])
            if CompareVersionSpellings(candidate, best) > 0 {
                bestIndex = index
            }

            index = index + 1
        }

        return versionDirectories[bestIndex]
    }

    // THE WHOLE SET IN DESCENDING PRECEDENCE, which is what a search-directory list needs: every
    // installed framework version is reachable and the newest is reached first.
    static func OrderVersionDirectoriesDescending(versionDirectories: string[]): string[] {
        if versionDirectories == null || versionDirectories.Length == 0 {
            return new string[](0)
        }

        ordered := new string[](versionDirectories.Length)
        index := 0
        while index < versionDirectories.Length {
            ordered[index] = versionDirectories[index]
            index = index + 1
        }

        // A stable insertion sort: equal spellings keep the caller's order, which `OrderByDescending`
        // also guarantees and a comparison sort would not.
        position := 1
        while position < ordered.Length {
            moving := ordered[position]
            movingName := Path.GetFileName(moving)
            target := position
            scan := position - 1
            while scan >= 0 {
                if CompareVersionSpellings(Path.GetFileName(ordered[scan]), movingName) < 0 {
                    ordered[scan + 1] = ordered[scan]
                    target = scan
                    scan = scan - 1
                } else {
                    scan = -1
                }
            }

            ordered[target] = moving
            position = position + 1
        }

        return ordered
    }

    // ── WHAT THE PROJECT RESTORED ────────────────────────────────────────────────────────────────
    //
    // `obj/project.assets.json` is the restore's own record, and its `libraries` object is keyed
    // `<package>/<version>`. The split is at the FIRST `/` and both halves must be non-empty: a key
    // with no separator, a leading separator or a trailing one names no package version and is
    // dropped rather than guessed at.
    static func RestoredPackageAssetsPath(projectDirectory: string): string {
        return Path.Combine(Path.Combine(projectDirectory, "obj"), "project.assets.json")
    }

    // The map lives under `libraries`, not under `targets` or `projectFileDependencyGroups`, both of
    // which also carry `<package>/<version>` keys — `targets`' keys are per-framework and include
    // project references, so reading them would pin versions for things that are not packages.
    static func RestoredLibrariesPropertyName(): string {
        return "libraries"
    }

    static func RestoredLibrarySeparatorIndex(libraryKey: string): int {
        if libraryKey == null {
            return -1
        }

        separator := libraryKey.IndexOf('/')
        if separator > 0 && separator < libraryKey.Length - 1 {
            return separator
        }

        return -1
    }

    static func RestoredLibraryPackageName(libraryKey: string): string? {
        separator := RestoredLibrarySeparatorIndex(libraryKey)
        if separator < 0 {
            return null
        }

        return libraryKey.Substring(0, separator)
    }

    static func RestoredLibraryPackageVersion(libraryKey: string): string? {
        separator := RestoredLibrarySeparatorIndex(libraryKey)
        if separator < 0 {
            return null
        }

        return libraryKey.Substring(separator + 1, libraryKey.Length - separator - 1)
    }

    // ── WHAT A PROJECT REFERENCE RESOLVES TO ─────────────────────────────────────────────────────
    //
    // Two project spellings are recognised and they name their assembly differently: a `.csproj`'s
    // assembly is its own file name, and a `project.yml`'s is whatever `ProjectFileParser` says its
    // effective name is — which `name:` can override, so the file name is not a safe guess there.
    // Anything else is not a project the analyzer knows how to read, and it says so rather than
    // silently resolving nothing.
    static func IsCSharpProjectReference(projectPath: string): bool {
        return projectPath != null && projectPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase)
    }

    static func IsNSharpProjectReference(projectPath: string): bool {
        return projectPath != null && projectPath.EndsWith(".yml", StringComparison.OrdinalIgnoreCase)
    }

    static func IsRecognizedProjectReference(projectPath: string): bool {
        return IsCSharpProjectReference(projectPath) || IsNSharpProjectReference(projectPath)
    }

    static func UnknownProjectReferenceWarning(projectPath: string): string {
        return "Warning: Unknown project reference type: " + (projectPath ?? "")
    }

    static func ProjectReferenceAssemblyName(projectPath: string, effectiveNSharpName: string): string {
        if IsCSharpProjectReference(projectPath) {
            // `GetFileNameWithoutExtension` is nullable-returning on its contract and only for a null
            // input, which `IsCSharpProjectReference` has already excluded — the coalesce is the total
            // spelling of that, not a behaviour choice.
            return Path.GetFileNameWithoutExtension(projectPath) ?? ""
        }

        return effectiveNSharpName
    }

    static func ProjectReferenceOutputPath(projectDirectory: string, targetFramework: string, assemblyName: string): string {
        return Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), targetFramework), AssemblyFileName(assemblyName))
    }

    // A REFERENCE PATH IS TAKEN AS WRITTEN WHEN IT IS ROOTED and resolved against the project
    // directory when it is not. `dll:` and `project:` dependencies ask the same question and get the
    // same answer; they differ in what is at the end of the path, not in how the path is found.
    static func ResolvedReferencePath(projectDirectory: string, referencePath: string): string {
        if Path.IsPathRooted(referencePath) {
            return referencePath
        }

        return Path.Combine(projectDirectory, referencePath)
    }

    // ── WHEN TWO LOADS ARE THE SAME LOAD ─────────────────────────────────────────────────────────
    //
    // Three separate questions, and the analyzer asks all three because it is handed three different
    // spellings of "this assembly": a file path, an `AssemblyName`, and a bare simple name.
    //
    // PATHS AND SIMPLE NAMES COMPARE CASE-INSENSITIVELY. A reference written `Newtonsoft.Json.dll`
    // and one written `newtonsoft.json.dll` are the same file on the platforms N# ships on, and
    // loading a second copy of one identity into a metadata context throws rather than shadowing.
    static func IsSameAssemblyPath(loadedFullPath: string?, requestedFullPath: string): bool {
        if loadedFullPath == null || requestedFullPath == null {
            return false
        }

        return string.Equals(loadedFullPath, requestedFullPath, StringComparison.OrdinalIgnoreCase)
    }

    static func IsSameSimpleName(loadedSimpleName: string?, requestedSimpleName: string?): bool {
        if loadedSimpleName == null || requestedSimpleName == null {
            return false
        }

        return string.Equals(loadedSimpleName, requestedSimpleName, StringComparison.OrdinalIgnoreCase)
    }

    // A SEARCH DIRECTORY IS ADDED ONLY ONCE, and only when it names something. The existence check is
    // the caller's — this owner decides admission, not IO. The duplicate test is ORDINAL, unlike the
    // assembly comparisons above, because the list is a probe ORDER and a directory spelled two ways
    // is two probe positions, not one identity.
    static func ShouldAddSearchDirectory(directory: string?, directoryExists: bool, existingDirectories: List<string>): bool {
        if string.IsNullOrEmpty(directory ?? "") {
            return false
        }

        if !directoryExists {
            return false
        }

        index := 0
        while index < existingDirectories.Count {
            if existingDirectories[index] == directory {
                return false
            }

            index = index + 1
        }

        return true
    }

    // THE FIRST FAILURE PER IDENTITY IS THE ONE REPORTED. A reference that fails is usually retried
    // through a different route, and the later failures describe the fallback rather than the cause,
    // so keeping the first keeps the sentence `NL923` prints pointing at what actually went wrong.
    static func ShouldRecordLoadFailure(identityAlreadyRecorded: bool): bool {
        return !identityAlreadyRecorded
    }

    // ── THE RESOLVER'S OWN PROBE ─────────────────────────────────────────────────────────────────
    //
    // When the load context cannot satisfy a reference from what it already holds or from a search
    // directory, it falls back to the package cache twice: once at the directory the package name
    // spells exactly, and then across every cache directory whose name STARTS WITH that spelling.
    // The prefix sweep is what finds `system.text.json` for a reference to `System.Text.Json` after a
    // rename, and it is deliberately not a contains test — a substring sweep over a full package
    // cache would bind an unrelated package whose name happens to embed the requested one.
    static func NuGetPackageDirectoryMatchesPrefix(directoryName: string?, simpleName: string): bool {
        if directoryName == null || simpleName == null {
            return false
        }

        return directoryName.StartsWith(CompilationReferenceResolverKernels.NormalizeNuGetPackageId(simpleName), StringComparison.OrdinalIgnoreCase)
    }

    // A PINNED VERSION OUTRANKS THE HIGHEST EXTRACTED ONE, and this is the same rule
    // `PackageVersionDirectory` applies to a directly declared reference, reached from the other
    // side: there the version arrives with the reference, here it arrives from the restore record.
    static func PinnedPackageVersionDirectory(packageDirectory: string, pinnedVersion: string?): string? {
        if string.IsNullOrEmpty(pinnedVersion ?? "") {
            return null
        }

        return Path.Combine(packageDirectory, pinnedVersion ?? "")
    }
}
