namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

public class TargetFrameworkVersionParseResult {
    public Parsed: bool
    public Major: int
    public Minor: int

    constructor(Parsed: bool, Major: int, Minor: int) {
        this.Parsed = Parsed
        this.Major = Major
        this.Minor = Minor
    }

}

public class CompilationReferenceResolverKernels {
    public static func GetImplicitNSharpRuntimeAssetCandidates(
        baseDirectory: string,
        compilerDirectory: string?): string[] {
        candidates := new List<string>()
        candidates.Add(Path.Combine(baseDirectory, "NSharpLang.Runtime.dll"))

        if !string.IsNullOrWhiteSpace(compilerDirectory ?? "") {
            candidates.Add(Path.Combine(compilerDirectory, "NSharpLang.Runtime.dll"))
        }

        return candidates.ToArray()
    }

    public static func GetGlobalPackagesFolder(configuredPackagesFolder: string?, userProfileFolder: string): string {
        if !string.IsNullOrWhiteSpace(configuredPackagesFolder ?? "") {
            return Path.GetFullPath(configuredPackagesFolder)
        }

        return Path.Combine(Path.Combine(userProfileFolder, ".nuget"), "packages")
    }

    public static func NormalizeNuGetPackageId(packageName: string): string {
        return packageName.ToLowerInvariant()
    }

    public static func NormalizeNuGetPackageVersion(version: string): string {
        return version.ToLowerInvariant()
    }

    public static func GetNuGetPackageDirectory(packagesRoot: string, packageName: string): string {
        return Path.Combine(packagesRoot, NormalizeNuGetPackageId(packageName))
    }

    public static func GetNuGetPackageVersionDirectory(packageDirectory: string, version: string): string {
        return Path.Combine(packageDirectory, NormalizeNuGetPackageVersion(version))
    }

    public static func GetNuGetIndexUrl(packageName: string): string {
        packageId := NormalizeNuGetPackageId(packageName)
        return "https://api.nuget.org/v3-flatcontainer/" + packageId + "/index.json"
    }

    public static func GetNuGetPackageDownloadUrl(packageName: string, version: string): string {
        packageId := NormalizeNuGetPackageId(packageName)
        normalizedVersion := NormalizeNuGetPackageVersion(version)
        return "https://api.nuget.org/v3-flatcontainer/"
            + packageId
            + "/"
            + normalizedVersion
            + "/"
            + packageId
            + "."
            + normalizedVersion
            + ".nupkg"
    }

    public static func GetNuGetPackageFileName(packageName: string, version: string): string {
        return NormalizeNuGetPackageId(packageName)
            + "."
            + NormalizeNuGetPackageVersion(version)
            + ".nupkg"
    }

    public static func GetDotnetSharedRootCandidates(runtimeDirectory: string?): string[] {
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

    public static func GetProjectAssemblyName(projectRoot: string, configuredName: string?): string {
        if !string.IsNullOrWhiteSpace(configuredName ?? "") {
            return configuredName ?? ""
        }

        projectName := Path.GetFileName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(projectRoot)))
        return projectName ?? "Project"
    }

    public static func IsExecutableOutputType(outputType: string?): bool {
        return string.Equals(outputType ?? "", "exe", StringComparison.OrdinalIgnoreCase)
    }

    public static func GetProjectYmlPath(projectRoot: string): string {
        return Path.Combine(projectRoot, "project.yml")
    }

    public static func GetStableOutputDirectory(projectRoot: string, configuration: string, targetFramework: string): string {
        return Path.Combine(Path.Combine(Path.Combine(projectRoot, "bin"), configuration), targetFramework)
    }

    public static func ResolveProjectReferencePath(projectRoot: string, projectReference: string): string {
        if Path.IsPathRooted(projectReference) {
            return projectReference
        }

        return Path.Combine(projectRoot, projectReference)
    }

    public static func GetFrameworkReferenceNames(sdk: string, references: IEnumerable<Reference>): string[] {
        names := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)

        if sdk.Contains("Web", StringComparison.OrdinalIgnoreCase) {
            AddUniqueText(names, seen, "Microsoft.AspNetCore.App")
        }

        foreach reference in references {
            if reference.Type == ReferenceType.Framework {
                AddUniqueText(names, seen, reference.Framework ?? "")
            }
        }

        return names.ToArray()
    }

    public static func ShouldAddDllReference(references: IEnumerable<Reference>, fullPath: string): bool {
        foreach reference in references {
            if reference.Type == ReferenceType.Dll {
                referencePath := reference.Dll
                if !string.IsNullOrWhiteSpace(referencePath ?? "") {
                    if string.Equals(Path.GetFullPath(referencePath), fullPath, StringComparison.OrdinalIgnoreCase) {
                        return false
                    }
                }
            }
        }

        return true
    }

    public static func GetNuGetReferences(
        dependencies: IEnumerable<Reference>,
        testDependencies: IEnumerable<Reference>,
        includeTests: bool): List<Reference> {
        references := new List<Reference>()
        foreach reference in dependencies {
            if reference.Type == ReferenceType.NuGet {
                references.Add(reference)
            }
        }

        if includeTests {
            foreach reference in testDependencies {
                if reference.Type == ReferenceType.NuGet {
                    references.Add(reference)
                }
            }
        }

        return references
    }

    public static func GetProjectReferenceResolutionOptions(options: ReferenceResolutionOptions): ReferenceResolutionOptions {
        return new ReferenceResolutionOptions(
            options.Configuration,
            false,
            options.BuildProjectReferences,
            options.Quiet,
            options.AotMode)
    }

    public static func ShouldUseRuntimeAssembliesForCompile(compileAssemblyCount: int): bool {
        return compileAssemblyCount == 0
    }

    public static func GetProjectReferenceCycleMessage(chainRoots: string[]): string {
        return "Project reference cycle detected: "
            + string.Join(" -> ", chainRoots)
            + ". Break the cycle in project.yml dependencies."
    }

    public static func GetCompilerDiagnosticsText(formattedDiagnostics: string[]): string {
        if formattedDiagnostics.Length == 0 {
            return "No compiler diagnostics were produced."
        }

        return string.Join(Environment.NewLine, formattedDiagnostics)
    }

    public static func GetProjectReferenceBuildFailedMessage(projectYmlPath: string, diagnostics: string): string {
        return "Project reference '"
            + projectYmlPath
            + "' failed to build:"
            + Environment.NewLine
            + diagnostics
    }

    public static func GetFrameworkReferenceNotResolvedMessage(
        frameworkName: string,
        projectRoot: string,
        targetFramework: string): string {
        return "Could not resolve framework reference '"
            + frameworkName
            + "' for project '"
            + projectRoot
            + "'. Install the "
            + frameworkName
            + " runtime for "
            + targetFramework
            + ", or remove the framework reference from project.yml."
    }

    public static func GetNuGetNoPublishedVersionsMessage(packageName: string): string {
        return "Package '" + packageName + "' has no published versions on NuGet.org."
    }

    public static func GetNuGetRestoreFailedMessage(packageName: string, version: string, detail: string): string {
        return "Could not restore NuGet package '"
            + packageName
            + "' version '"
            + version
            + "'. Check network access, NuGet.org availability, or pin a version already present in the local NuGet cache. Details: "
            + detail
    }

    public static func GetImplicitTestDependencyPlan(
        includeTests: bool,
        hasTests: bool,
        testFramework: string?,
        existingPackageIds: string[]): ImplicitTestDependencyPlan {
        if !includeTests || !hasTests {
            return new ImplicitTestDependencyPlan(false, "", "")
        }

        packageName := "xunit"
        version := "2.9.2"
        if string.Equals(testFramework ?? "", "nunit", StringComparison.OrdinalIgnoreCase) {
            packageName = "NUnit"
            version = "4.3.2"
        }

        if ContainsPackageId(existingPackageIds, packageName) {
            return new ImplicitTestDependencyPlan(false, "", "")
        }

        return new ImplicitTestDependencyPlan(true, packageName, version)
    }

    public static func FilterReferencesByType(
        references: IEnumerable<Reference>,
        targetType: ReferenceType): List<Reference> {
        targetTypeId := Convert.ToInt32(targetType)
        if targetTypeId < 0 || targetTypeId > Convert.ToInt32(ReferenceType.Framework) {
            throw new ArgumentOutOfRangeException("targetType", "Reference type is not supported.")
        }

        filteredReferences := new List<Reference>()
        foreach reference in references {
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

    public static func SelectBestScoreIndex(scores: int[], count: int): int {
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

    public static func ParseTargetFrameworkVersion(targetFramework: string): TargetFrameworkVersionParseResult {
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

    public static func GetFrameworkCompatibilityScore(assetFramework: string?, targetFramework: string): int {
        result := new int[](5)
        code := FrameworkCompatibilityScoreInto(assetFramework ?? "", targetFramework, result)
        if code != 1 {
            throw new InvalidOperationException("N# reference resolver framework compatibility kernel returned an invalid code.")
        }

        return result[0]
    }

    public static func SelectBestAssetDirectoryIndex(candidateFrameworks: string[], targetFramework: string): int {
        scores := new int[](candidateFrameworks.Length)
        index := 0
        while index < candidateFrameworks.Length {
            scores[index] = GetFrameworkCompatibilityScore(candidateFrameworks[index], targetFramework)
            index = index + 1
        }

        return SelectBestScoreIndex(scores, scores.Length)
    }

    public static func SelectBestDependencyGroupIndex(groupTargetFrameworks: string?[], targetFramework: string): int {
        scores := new int[](groupTargetFrameworks.Length)
        index := 0
        while index < groupTargetFrameworks.Length {
            scores[index] = GetFrameworkCompatibilityScore(groupTargetFrameworks[index], targetFramework)
            index = index + 1
        }

        return SelectBestScoreIndex(scores, scores.Length)
    }

    public static func SortPathsIgnoreCase(paths: string[]): string[] {
        sorted := new string[](paths.Length)
        index := 0
        while index < paths.Length {
            sorted[index] = paths[index]
            index = index + 1
        }

        Array.Sort(sorted, 0, sorted.Length, StringComparer.OrdinalIgnoreCase)
        return sorted
    }

    public static func NormalizeNuGetDependencyVersion(version: string?): string? {
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

    public static func SelectSharedFrameworkCandidateIndex(
        versions: Version[],
        targetMajor: int?): int {
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

    public static func SelectSharedFrameworkDirectoryIndex(
        versionNames: string[],
        targetVersion: TargetFrameworkVersionParseResult): int {
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

    public static func SelectLatestNuGetVersionIndex(versions: string[]): int {
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

    public static func SelectBestNuGetVersionIndex(versions: string[]): int {
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

    public static func PathHasSegmentIgnoreCase(path: string, separator: char, segment: string): bool {
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

    static func TryParseVersionIntSegment(
        text: string,
        start: int,
        end: int,
        result: int[],
        resultIndex: int): bool {
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
        index := 0
        while index < version.Length {
            if version[index] == '-' {
                return true
            }

            index = index + 1
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

    static func NuGetVersionTryParseIntSegment(
        text: string,
        start: int,
        end: int,
        result: int[],
        resultIndex: int): bool {
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

    static func TryParseIntSegment(
        text: string,
        start: int,
        end: int,
        result: int[],
        resultIndex: int): bool {
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

    static func FrameworkNormalizedEquals(
        left: string,
        leftStart: int,
        leftEnd: int,
        right: string,
        rightStart: int,
        rightEnd: int): bool {
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

    static func FrameworkTryParseNormalizedIntSegment(
        text: string,
        start: int,
        end: int,
        segmentStart: int,
        segmentEnd: int,
        result: int[],
        resultIndex: int): bool {
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
        index := 0
        while index < packageIds.Length {
            if string.Equals(packageIds[index], packageName, StringComparison.OrdinalIgnoreCase) {
                return true
            }

            index = index + 1
        }

        return false
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
