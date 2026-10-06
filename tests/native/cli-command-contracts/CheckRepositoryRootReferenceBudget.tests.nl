namespace NSharpLang.CliCommandContracts.Tests

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Text.Json
import System.Xml.Linq

class CliRootCheckDependency {
    Kind: string
    Value: string
    Version: string?

    constructor(kind: string, value: string) {
        Kind = kind
        Value = value
        Version = null
    }
}

class CliRootCheckReferenceImageBudget {
    EmptyProjectReferenceImages: long
    ConfiguredReferenceImages: long
    Maximum: long

    constructor(emptyProjectImages: long, configuredImages: long, memberCount: int) {
        EmptyProjectReferenceImages = emptyProjectImages
        ConfiguredReferenceImages = configuredImages
        // A check can open a configured image once in each metadata context (analysis and emit),
        // plus once in the exact-identity runtime context. The empty-project probe measures the
        // common runtime surface in those same contexts, so only configured references need this
        // three-open allowance.
        Maximum = emptyProjectImages * (long)memberCount + configuredImages * 3L
    }
}

func CliRootCheckReferenceImageBudget(roots: List<string>): CliRootCheckReferenceImageBudget {
    emptyProjectImages := CliRootCheckEmptyProjectReferenceImages()
    configuredImages := 0L
    for root in roots {
        memberImages := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        visitedProjects := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        visitedPackages := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        CliRootCheckCollectMemberReferenceImages(root, memberImages, visitedProjects, visitedPackages)
        configuredImages = configuredImages + (long)memberImages.Count
    }

    return new CliRootCheckReferenceImageBudget(emptyProjectImages, configuredImages, roots.Count)
}

func CliRootCheckEmptyProjectReferenceImages(): long {
    directory := NewTempDirectory("nsharp-root-check-reference-probe")
    statsPath := Path.Combine(directory, "stats.json")
    try {
        File.WriteAllText(
            Path.Combine(directory, "project.yml"),
            "name: RootCheckReferenceProbe\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
        )
        File.WriteAllText(Path.Combine(directory, "Probe.nl"), "class Probe {}\n")

        run := Nlc("check --project \"" + directory + "\" --json --stats=\"" + statsPath + "\"")
        assert run.ExitCode == 0, "empty-project reference probe failed: " + run.Stdout + run.Stderr
        assert File.Exists(statsPath), "empty-project reference probe omitted its stats file"
        document := JsonDocument.Parse(File.ReadAllText(statsPath))
        counters := document.RootElement.GetProperty("counters")
        referenceImages := counters.GetProperty("referenceAssembliesLoaded").GetInt64()
        document.Dispose()
        return referenceImages
    } finally {
        Directory.Delete(directory, true)
    }
}

func CliRootCheckCollectMemberReferenceImages(
    projectRoot: string,
    images: HashSet<string>,
    visitedProjects: HashSet<string>,
    visitedPackages: HashSet<string>
): void {
    normalizedRoot := NormalizedFullPath(projectRoot)
    if !visitedProjects.Add(normalizedRoot) {
        return
    }

    targetFramework := CliRootCheckReadYamlValue(normalizedRoot, "targetFramework")
    if targetFramework.Length == 0 {
        targetFramework = "net10.0"
    }
    hasRestoredAssets := CliRootCheckCollectRestoredPackageImages(normalizedRoot, targetFramework, images)
    dependencies := CliRootCheckReadDependencies(normalizedRoot)
    for dependency in dependencies {
        if dependency.Kind == "nuget" {
            if !hasRestoredAssets {
                CliRootCheckCollectNuGetPackageImages(
                    dependency.Value,
                    dependency.Version,
                    targetFramework,
                    CliRootCheckNuGetPackagesRoot(),
                    images,
                    visitedPackages
                )
            }
            continue
        }

        if dependency.Kind == "project" {
            CliRootCheckCollectProjectReferenceImages(
                normalizedRoot,
                dependency.Value,
                images,
                visitedProjects,
                visitedPackages
            )
            continue
        }

        if dependency.Kind == "dll" {
            path := dependency.Value
            if !Path.IsPathRooted(path) {
                path = Path.Combine(normalizedRoot, path)
            }
            images.Add(CliRootCheckReferenceImageKey(path, "dll:" + NormalizedFullPath(path)))
            continue
        }

        if dependency.Kind == "framework" {
            CliRootCheckCollectSharedFrameworkImages(dependency.Value, images)
        }
    }

    sdk := CliRootCheckReadYamlValue(normalizedRoot, "sdk")
    if sdk.Contains("Web", StringComparison.OrdinalIgnoreCase) {
        CliRootCheckCollectSharedFrameworkImages("Microsoft.AspNetCore.App", images)
    }
}

func CliRootCheckCollectProjectReferenceImages(
    projectRoot: string,
    projectReference: string,
    images: HashSet<string>,
    visitedProjects: HashSet<string>,
    visitedPackages: HashSet<string>
): void {
    path := projectReference
    if !Path.IsPathRooted(path) {
        path = Path.Combine(projectRoot, path)
    }

    if path.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase) {
        images.Add("project:" + NormalizedFullPath(path))
        return
    }

    projectDirectory := path
    if path.EndsWith(".yml", StringComparison.OrdinalIgnoreCase) {
        projectDirectory = Path.GetDirectoryName(path) ?? path
    }
    projectDirectory = NormalizedFullPath(projectDirectory)

    assemblyName := CliRootCheckProjectAssemblyName(projectDirectory)
    targetFramework := CliRootCheckReadYamlValue(projectDirectory, "targetFramework")
    if targetFramework.Length == 0 {
        targetFramework = "net10.0"
    }
    outputPath := Path.Combine(
        Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), targetFramework),
        assemblyName + ".dll"
    )
    images.Add(CliRootCheckReferenceImageKey(outputPath, "project:" + NormalizedFullPath(outputPath)))
    if File.Exists(Path.Combine(projectDirectory, "project.yml")) {
        CliRootCheckCollectMemberReferenceImages(projectDirectory, images, visitedProjects, visitedPackages)
    }
}

func CliRootCheckProjectAssemblyName(projectRoot: string): string {
    configuredName := CliRootCheckReadYamlValue(projectRoot, "name")
    if configuredName.Length > 0 {
        return configuredName
    }
    return Path.GetFileName(Path.TrimEndingDirectorySeparator(projectRoot)) ?? "Project"
}

func CliRootCheckReadYamlValue(projectRoot: string, key: string): string {
    projectPath := Path.Combine(projectRoot, "project.yml")
    if !File.Exists(projectPath) {
        return ""
    }

    prefix := key + ":"
    for line in File.ReadAllLines(projectPath) {
        trimmed := line.Trim()
        if trimmed.StartsWith(prefix, StringComparison.Ordinal) {
            value := trimmed.Substring(prefix.Length).Trim()
            return CliRootCheckUnquoteYamlScalar(value)
        }
    }
    return ""
}

func CliRootCheckReadDependencies(projectRoot: string): List<CliRootCheckDependency> {
    dependencies := new List<CliRootCheckDependency>()
    projectPath := Path.Combine(projectRoot, "project.yml")
    if !File.Exists(projectPath) {
        return dependencies
    }

    inDependencyBlock := false
    lastDependency: CliRootCheckDependency? = null
    for line in File.ReadAllLines(projectPath) {
        trimmed := line.Trim()
        if trimmed.Length == 0 || trimmed.StartsWith("#") {
            continue
        }

        isIndented := line[0] == ' ' || line[0] == '\t'
        if !isIndented {
            inDependencyBlock = trimmed == "dependencies:" || trimmed == "testDependencies:"
            lastDependency = null
            continue
        }

        if !inDependencyBlock {
            continue
        }

        if trimmed.StartsWith("-") {
            item := trimmed.Substring(1).Trim()
            separator := item.IndexOf(":", StringComparison.Ordinal)
            if separator <= 0 {
                lastDependency = null
                continue
            }

            kind := item.Substring(0, separator).Trim()
            value := CliRootCheckUnquoteYamlScalar(item.Substring(separator + 1).Trim())
            dependency := new CliRootCheckDependency(kind, value)
            dependencies.Add(dependency)
            lastDependency = dependency
            continue
        }

        if lastDependency != null && lastDependency.Kind == "nuget" && trimmed.StartsWith("version:", StringComparison.Ordinal) {
            version := trimmed.Substring("version:".Length).Trim()
            lastDependency.Version = CliRootCheckUnquoteYamlScalar(version)
        }
    }
    return dependencies
}

func CliRootCheckUnquoteYamlScalar(value: string): string {
    if value.Length >= 2 {
        first := value[0]
        last := value[value.Length - 1]
        if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
            return value.Substring(1, value.Length - 2)
        }
    }
    return value
}

func CliRootCheckCollectRestoredPackageImages(projectRoot: string, targetFramework: string, images: HashSet<string>): bool {
    assetsPath := Path.Combine(Path.Combine(projectRoot, "obj"), "project.assets.json")
    if !File.Exists(assetsPath) {
        return false
    }

    document := JsonDocument.Parse(File.ReadAllText(assetsPath))
    root := document.RootElement
    libraries := root.GetProperty("libraries")
    targets := root.GetProperty("targets")
    packageFolders := root.GetProperty("packageFolders")
    selectedTargetName := CliRootCheckSelectAssetsTarget(targets, targetFramework)
    if selectedTargetName.Length == 0 {
        document.Dispose()
        return false
    }
    for target in targets.EnumerateObject() {
        if target.Name != selectedTargetName {
            continue
        }
        for library in target.Value.EnumerateObject() {
            metadata := new JsonElement()
            if !libraries.TryGetProperty(library.Name, out metadata) {
                continue
            }
            if metadata.GetProperty("type").GetString() != "package" {
                continue
            }
            libraryPath := metadata.GetProperty("path").GetString() ?? ""

            for assetKind in ["compile", "runtime"] {
                assetList := new JsonElement()
                if !library.Value.TryGetProperty(assetKind, out assetList) || assetList.ValueKind != JsonValueKind.Object {
                    continue
                }
                for asset in assetList.EnumerateObject() {
                    if asset.Name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) && !asset.Name.EndsWith("_._", StringComparison.Ordinal) {
                        assemblyName := Path.GetFileNameWithoutExtension(asset.Name) ?? ""
                        if assemblyName.Length > 0 {
                            fallbackKey := "package:" + library.Name.ToLowerInvariant() + ":" + assemblyName.ToLowerInvariant()
                            imageKey := fallbackKey
                            for packageFolder in packageFolders.EnumerateObject() {
                                assetPath := Path.Combine(Path.Combine(packageFolder.Name, libraryPath), asset.Name)
                                if File.Exists(assetPath) {
                                    imageKey = CliRootCheckReferenceImageKey(assetPath, fallbackKey)
                                    break
                                }
                            }
                            images.Add(imageKey)
                        }
                    }
                }
            }
        }
    }

    document.Dispose()
    return true
}

func CliRootCheckSelectAssetsTarget(targets: JsonElement, targetFramework: string): string {
    firstTarget := ""
    targetCount := 0
    for target in targets.EnumerateObject() {
        if targetCount == 0 {
            firstTarget = target.Name
        }
        targetCount = targetCount + 1
        frameworkEnd := target.Name.IndexOf("/", StringComparison.Ordinal)
        framework := target.Name
        if frameworkEnd >= 0 {
            framework = framework.Substring(0, frameworkEnd)
        }
        if string.Equals(framework, targetFramework, StringComparison.OrdinalIgnoreCase) {
            return target.Name
        }
    }
    if targetCount == 1 {
        return firstTarget
    }
    return ""
}

func CliRootCheckCollectNuGetPackageImages(
    packageName: string,
    requestedVersion: string?,
    targetFramework: string,
    packagesRoot: string,
    images: HashSet<string>,
    visitedPackages: HashSet<string>
): void {
    requestKey := packageName.ToLowerInvariant() + "@" + (requestedVersion ?? "")
    if !visitedPackages.Add(requestKey) {
        return
    }

    packageRoot := Path.Combine(packagesRoot, packageName.ToLowerInvariant())
    if !Directory.Exists(packageRoot) {
        images.Add("package:" + requestKey)
        return
    }

    versionDirectories := new List<string>()
    versionHint := CliRootCheckNuGetVersionHint(requestedVersion)
    exactVersionDirectory := Path.Combine(packageRoot, versionHint)
    if versionHint.Length > 0 && Directory.Exists(exactVersionDirectory) {
        versionDirectories.Add(exactVersionDirectory)
    } else {
        candidates := Directory.GetDirectories(packageRoot)
        if candidates.Length > 0 {
            Array.Sort(candidates, StringComparer.OrdinalIgnoreCase)
            if versionHint.Length == 0 {
                versionDirectories.Add(candidates[candidates.Length - 1])
            } else {
                versionDirectories.Add(Path.Combine(packageRoot, versionHint))
                if !Directory.Exists(versionDirectories[0]) {
                    versionDirectories.Clear()
                    versionDirectories.Add(candidates[candidates.Length - 1])
                }
            }
        }
    }

    if versionDirectories.Count == 0 {
        images.Add("package:" + requestKey)
        return
    }

    for versionDirectory in versionDirectories {
        actualVersion := Path.GetFileName(versionDirectory) ?? ""
        packageIdentity := packageName.ToLowerInvariant() + "@" + actualVersion.ToLowerInvariant()
        compileAssemblies := CliRootCheckSelectPackageAssetAssemblies(versionDirectory, "ref", targetFramework)
        runtimeAssemblies := CliRootCheckSelectPackageAssetAssemblies(versionDirectory, "lib", targetFramework)
        assetAssemblies := compileAssemblies
        if compileAssemblies.Count == 0 {
            assetAssemblies = runtimeAssemblies
        }
        for assetPath in assetAssemblies {
            assemblyName := Path.GetFileNameWithoutExtension(assetPath) ?? ""
            if assemblyName.Length > 0 {
                images.Add(CliRootCheckReferenceImageKey(assetPath, "package:" + packageIdentity + ":" + assemblyName.ToLowerInvariant()))
            }
        }

        for nuspecPath in Directory.GetFiles(versionDirectory, "*.nuspec", SearchOption.TopDirectoryOnly) {
            CliRootCheckCollectNuGetDependenciesFromNuspec(
                nuspecPath,
                targetFramework,
                packagesRoot,
                images,
                visitedPackages
            )
        }
    }
}

func CliRootCheckNuGetVersionHint(version: string?): string {
    text := (version ?? "").Trim()
    if text.Length == 0 || (text[0] != '[' && text[0] != '(') {
        return text
    }

    comma := text.IndexOf(",", StringComparison.Ordinal)
    if comma >= 0 {
        return text.Substring(1, comma - 1).Trim()
    }
    if text.Length > 1 {
        return text.Substring(1, text.Length - 2).Trim()
    }
    return ""
}

func CliRootCheckSelectPackageAssetAssemblies(versionDirectory: string, assetKind: string, targetFramework: string): List<string> {
    result := new List<string>()
    assetRoot := Path.Combine(versionDirectory, assetKind)
    if !Directory.Exists(assetRoot) {
        return result
    }

    bestDirectory := ""
    bestScore := -1
    for directory in Directory.GetDirectories(assetRoot, "*", SearchOption.TopDirectoryOnly) {
        score := CliRootCheckFrameworkCompatibilityScore(Path.GetFileName(directory) ?? "", targetFramework)
        if score > bestScore {
            bestScore = score
            bestDirectory = directory
        }
    }
    if bestDirectory.Length > 0 {
        for assetPath in Directory.GetFiles(bestDirectory, "*.dll", SearchOption.TopDirectoryOnly) {
            result.Add(assetPath)
        }
    }
    return result
}

func CliRootCheckFrameworkCompatibilityScore(assetFramework: string, targetFramework: string): int {
    if assetFramework.Trim().Length == 0 {
        return 1
    }
    if string.Equals(assetFramework, targetFramework, StringComparison.OrdinalIgnoreCase) {
        return 10000
    }
    asset := CliRootCheckFrameworkVersion(assetFramework.ToLowerInvariant())
    target := CliRootCheckFrameworkVersion(targetFramework.ToLowerInvariant())
    if asset < 0 || target < 0 {
        return -1
    }
    assetName := assetFramework.ToLowerInvariant()
    if assetName.StartsWith(".", StringComparison.Ordinal) {
        assetName = assetName.Substring(1)
    }
    if assetName.StartsWith("netstandard", StringComparison.Ordinal) {
        return 4000 + asset
    }
    if assetName.StartsWith("netcoreapp", StringComparison.Ordinal) && asset <= target {
        return 7000 + asset
    }
    if assetName.StartsWith("net", StringComparison.Ordinal) && asset >= 500 && asset <= target {
        return 8000 + asset
    }
    return -1
}

func CliRootCheckFrameworkVersion(framework: string): int {
    start := 0
    while start < framework.Length && !char.IsDigit(framework[start]) {
        start = start + 1
    }
    if start == framework.Length {
        return -1
    }
    major := 0
    index := start
    while index < framework.Length && char.IsDigit(framework[index]) {
        major = major * 10 + (int)framework[index] - (int)'0'
        index = index + 1
    }
    minor := 0
    if index < framework.Length && framework[index] == '.' {
        index = index + 1
        while index < framework.Length && char.IsDigit(framework[index]) {
            minor = minor * 10 + (int)framework[index] - (int)'0'
            index = index + 1
        }
    }
    return major * 100 + minor
}

func CliRootCheckCollectNuGetDependenciesFromNuspec(
    nuspecPath: string,
    targetFramework: string,
    packagesRoot: string,
    images: HashSet<string>,
    visitedPackages: HashSet<string>
): void {
    document := XDocument.Load(nuspecPath)
    dependenciesElement: XElement? = null
    let descendants: System.Collections.IEnumerable = document.Descendants()
    descendantEnumerator := descendants.GetEnumerator()
    try {
        while descendantEnumerator.MoveNext() {
            candidate := descendantEnumerator.get_Current() as XElement
            if candidate != null && candidate.Name.LocalName == "dependencies" {
                dependenciesElement = candidate
                break
            }
        }
    } finally {
        disposable := descendantEnumerator as IDisposable
        if disposable != null {
            disposable.Dispose()
        }
    }
    if dependenciesElement == null {
        return
    }

    groups := new List<XElement>()
    let children: System.Collections.IEnumerable = dependenciesElement.Elements()
    childEnumerator := children.GetEnumerator()
    try {
        while childEnumerator.MoveNext() {
            child := childEnumerator.get_Current() as XElement
            if child != null && child.Name.LocalName == "group" {
                groups.Add(child)
            }
        }
    } finally {
        disposable := childEnumerator as IDisposable
        if disposable != null {
            disposable.Dispose()
        }
    }

    selectedGroup: XElement? = null
    if groups.Count == 0 {
        selectedGroup = dependenciesElement
    } else {
        bestScore := -1
        for group in groups {
            frameworkAttribute := group.Attribute(XName.Get("targetFramework"))
            groupFramework := ""
            if frameworkAttribute != null {
                groupFramework = frameworkAttribute.Value
            }
            score := CliRootCheckFrameworkCompatibilityScore(groupFramework, targetFramework)
            if score > bestScore {
                bestScore = score
                selectedGroup = group
            }
        }
        if bestScore < 0 {
            return
        }
    }

    if selectedGroup == null {
        return
    }
    let selectedChildren: System.Collections.IEnumerable = selectedGroup.Elements()
    dependencyEnumerator := selectedChildren.GetEnumerator()
    try {
        while dependencyEnumerator.MoveNext() {
            element := dependencyEnumerator.get_Current() as XElement
            if element == null || element.Name.LocalName != "dependency" {
                continue
            }
            idAttribute := element.Attribute(XName.Get("id"))
            if idAttribute == null || idAttribute.Value.Length == 0 {
                continue
            }
            versionAttribute := element.Attribute(XName.Get("version"))
            version: string? = null
            if versionAttribute != null {
                version = versionAttribute.Value
            }
            CliRootCheckCollectNuGetPackageImages(
                idAttribute.Value,
                version,
                targetFramework,
                packagesRoot,
                images,
                visitedPackages
            )
        }
    } finally {
        disposable := dependencyEnumerator as IDisposable
        if disposable != null {
            disposable.Dispose()
        }
    }
}

func CliRootCheckNuGetPackagesRoot(): string {
    configuredRoot := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
    if !string.IsNullOrWhiteSpace(configuredRoot ?? "") {
        return Path.GetFullPath(configuredRoot ?? "")
    }

    profile := Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
    return Path.Combine(Path.Combine(Path.Combine(profile, ".nuget"), "packages"), "")
}

func CliRootCheckReferenceImageKey(path: string, fallback: string): string {
    try {
        identity := AssemblyName.GetAssemblyName(path)
        fullName := identity.FullName
        if !string.IsNullOrWhiteSpace(fullName ?? "") {
            return "identity:" + (fullName ?? "")
        }
        return fallback
    } catch {
        return fallback
    }
}

func CliRootCheckCollectSharedFrameworkImages(frameworkName: string, images: HashSet<string>): void {
    runtimeDirectory := Path.GetDirectoryName(typeof(object).Assembly.Location) ?? ""
    frameworkVersionDirectory := Path.GetDirectoryName(runtimeDirectory) ?? ""
    sharedRoot := Path.GetDirectoryName(frameworkVersionDirectory) ?? ""
    frameworkRoot := Path.Combine(sharedRoot, frameworkName)
    if !Directory.Exists(frameworkRoot) {
        return
    }

    for versionDirectory in Directory.GetDirectories(frameworkRoot) {
        for assemblyPath in Directory.GetFiles(versionDirectory, "*.dll", SearchOption.TopDirectoryOnly) {
            assemblyName := Path.GetFileNameWithoutExtension(assemblyPath) ?? ""
            if assemblyName.Length > 0 {
                images.Add(CliRootCheckReferenceImageKey(assemblyPath, "framework:" + frameworkName.ToLowerInvariant() + ":" + assemblyName.ToLowerInvariant()))
            }
        }
    }
}
