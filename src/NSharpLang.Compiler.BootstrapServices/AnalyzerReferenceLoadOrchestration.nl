namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Text.Json


// ONE REQUEST THE ANALYZER'S LOAD SURFACE IS ASKED TO PERFORM.
//
// The plan exists so the three decisions below can be ASSERTED. Each of them is an ORDER or a KIND
// and none of them carries a literal, so no test could reach them while they lived inside a method
// that also touched the NuGet cache: the only observable was which assemblies happened to end up
// loaded on the machine running the test.
//
// `Identity` is the name a FAILURE is recorded under, and it is the reference's RAW spelling rather
// than the path the request resolved to — a user who wrote `nuget: Foo` must read "Foo", not a cache
// path they never typed.
class ReferenceLoadRequest {
    Kind: string
    Value: string
    Version: string?
    Identity: string
    RecordedPackageName: string?

    constructor(kind: string, value: string, version: string?, identity: string, recordedPackageName: string?) {
        Kind = kind
        Value = value
        Version = version
        Identity = identity
        RecordedPackageName = recordedPackageName
    }
}

// WHAT A PROJECT'S REFERENCES MEAN, IN THE ORDER THEY MEAN IT.
//
// `Analyzer.cs` walked a `ProjectConfig` and loaded as it walked. Three of the decisions it made on
// the way carry no literal at all, which is why task 021's audit could not move them and why nothing
// ever pinned them:
//
//   D1. NON-NUGET DEPENDENCIES LOAD BEFORE NUGET ONES. A `dll:` or `project:` reference is the
//       user's own build output; a `nuget:` reference is a cache entry that may exist at several
//       versions. Loading the user's own first means an identity they built wins the by-identity
//       dedupe over one the cache also happens to hold, rather than the other way round.
//   D2. A TEST DEPENDENCY CONTRIBUTES ITS PACKAGE NAME WHERE A NORMAL ONE CONTRIBUTES A PATH. A
//       normal `nuget:` dependency is resolved to a `lib/<tfm>/<name>.dll` and loaded BY PATH, so
//       the project's pinned version decides. A `testDependencies:` entry is loaded BY NAME and left
//       to the resolver, because a test framework's assembly is whatever the host already has —
//       resolving it to a cache path would bind a second copy of xunit beside the one running.
//   D3. (the resolver's own four-stage probe order) is `NSharpMetadataResolver`'s and moves with it.
//
// So the walk is split in two. `PlanRequests` is PURE — a config and a directory in, an ordered list
// of requests out, no IO — and it is what the contracts assert. `Load` performs the plan. A contract
// can now state D1 and D2 as what they are, without a NuGet cache, without a network, and without
// the machine's own package folder deciding whether the test passes.
//
// THE FAILURE NET IS PER REQUEST, NOT PER PROJECT. One reference that cannot be resolved must not end
// the analysis, so each performed request is bracketed and its failure recorded under the reference's
// raw identity for `AnalyzerReferenceLoadReport` to pair against unresolved-type errors. By-NAME
// requests are deliberately OUTSIDE that bracket: `LoadByName` already records its own failures, and
// wrapping it would record the same failure twice under two identities.
class AnalyzerReferenceLoadOrchestration {
    surface: AnalyzerMetadataLoadSurface

    // The analyzer's referenced-package set, held by reference: `AnalyzerImports` reads the same set
    // to decide whether an unresolved import names a package the project actually depends on.
    referencedPackageNames: HashSet<string>

    // One parse of `obj/project.assets.json` per project directory. The restore output does not
    // change under a running analysis, and the walk is asked once per dependency.
    restoredPackageVersionsByProject: Dictionary<string, Dictionary<string, string>>

    constructor(loadSurface: AnalyzerMetadataLoadSurface, packageNames: HashSet<string>) {
        surface = loadSurface
        referencedPackageNames = packageNames
        restoredPackageVersionsByProject = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal)
    }

    // ---------------------------------------------------------------------------------------------
    // THE PLAN. Pure: no file is opened and no assembly is loaded.
    // ---------------------------------------------------------------------------------------------

    static func RequestIdentity(reference: Reference): string {
        nuget := reference.Nuget
        if nuget != null {
            return nuget
        }

        project := reference.Project
        if project != null {
            return project
        }

        dll := reference.Dll
        if dll != null {
            return dll
        }

        return "<unknown reference>"
    }

    // A package NAME is recorded only when the entry actually spells one. A blank `nuget:` still
    // produces a REQUEST — the C# this replaces called through with it and let the load fail and be
    // recorded — but it contributes no name to the set the import diagnostics read.
    static func RecordedPackageName(reference: Reference): string? {
        nuget := reference.Nuget
        if nuget == null {
            return null
        }

        if string.IsNullOrWhiteSpace(nuget) {
            return null
        }

        return nuget
    }

    static func PlanRequests(config: ProjectConfig, projectDirectory: string): List<ReferenceLoadRequest> {
        requests := new List<ReferenceLoadRequest>()

        // D1, first half: everything that is NOT a NuGet package, in declaration order.
        dependencies := config.Dependencies
        index := 0
        while index < dependencies.Count {
            reference := dependencies[index]
            if reference.Type != ReferenceType.NuGet {
                request := PlanNonPackageRequest(reference, projectDirectory)
                if request != null {
                    requests.Add(request)
                }
            }

            index = index + 1
        }

        // D1, second half: the NuGet packages, each also contributing its name.
        index = 0
        while index < dependencies.Count {
            reference := dependencies[index]
            if reference.Type == ReferenceType.NuGet {
                requests.Add(new ReferenceLoadRequest(
                    "package",
                    reference.Nuget ?? "",
                    reference.Version,
                    RequestIdentity(reference),
                    RecordedPackageName(reference)
                ))
            }

            index = index + 1
        }

        // D2: a test dependency is loaded BY NAME, never resolved to a cache path.
        testDependencies := config.TestDependencies
        index = 0
        while index < testDependencies.Count {
            dependency := testDependencies[index]
            if dependency.Type == ReferenceType.NuGet {
                packageName := dependency.Nuget
                if packageName != null {
                    requests.Add(new ReferenceLoadRequest(
                        "name",
                        packageName,
                        null,
                        RequestIdentity(dependency),
                        RecordedPackageName(dependency)
                    ))
                }
            }

            index = index + 1
        }

        // A web project's framework assemblies are named, not referenced, so they arrive last and
        // by name — the same door a test dependency uses, for the same reason.
        if AnalyzerMetadataLoadPolicy.RequiresAspNetCoreAssemblies(config.Sdk) {
            aspNetNames := AnalyzerMetadataLoadPolicy.AspNetCoreAssemblyNames()
            nameIndex := 0
            while nameIndex < aspNetNames.Length {
                requests.Add(new ReferenceLoadRequest("name", aspNetNames[nameIndex], null, aspNetNames[nameIndex], null))
                nameIndex = nameIndex + 1
            }
        }

        return requests
    }

    // A `framework:` reference names something the host already has and produces NO request; the
    // other two resolve their path against the project directory before anything is opened.
    static func PlanNonPackageRequest(reference: Reference, projectDirectory: string): ReferenceLoadRequest? {
        if reference.Type == ReferenceType.Dll {
            return new ReferenceLoadRequest(
                "dll",
                AnalyzerMetadataLoadPolicy.ResolvedReferencePath(projectDirectory, reference.Dll ?? ""),
                null,
                RequestIdentity(reference),
                null
            )
        }

        if reference.Type == ReferenceType.Project {
            return new ReferenceLoadRequest(
                "project",
                AnalyzerMetadataLoadPolicy.ResolvedReferencePath(projectDirectory, reference.Project ?? ""),
                null,
                RequestIdentity(reference),
                null
            )
        }

        return null
    }

    // ---------------------------------------------------------------------------------------------
    // PERFORMING THE PLAN.
    // ---------------------------------------------------------------------------------------------

    func Load(config: ProjectConfig, projectDirectory: string) {
        // The versions the project RESTORED are pinned before anything is loaded, so a cache fallback
        // binds the version this project resolved rather than the highest one extracted on the box.
        for entry in GetRestoredPackageVersions(projectDirectory) {
            surface.PinPackageVersion(entry.Key, entry.Value)
        }

        requests := PlanRequests(config, projectDirectory)
        index := 0
        while index < requests.Count {
            Perform(requests[index], projectDirectory, config.TargetFramework)
            index = index + 1
        }
    }

    func Perform(request: ReferenceLoadRequest, projectDirectory: string, targetFramework: string) {
        recorded := request.RecordedPackageName
        if recorded != null {
            referencedPackageNames.Add(recorded)
        }

        kind := request.Kind
        if kind == "name" {
            surface.LoadByName(request.Value)
            return
        }

        try {
            if kind == "dll" {
                surface.LoadByPath(request.Value)
            } else if kind == "project" {
                LoadProjectReference(request.Value, targetFramework)
            } else if kind == "package" {
                LoadPackage(request.Value, request.Version, targetFramework, projectDirectory)
            }
        } catch error: Exception {
            surface.RecordExceptionFailure(request.Identity, error)
        }
    }

    // A LOCALLY BUILT COPY WINS OVER THE CACHE. A package the solution also builds is the one the
    // user is editing, and its `bin/` output is newer than anything restored.
    func LoadPackage(packageName: string, version: string?, targetFramework: string, projectDirectory: string) {
        binPath := AnalyzerMetadataLoadPolicy.LocallyBuiltPackageAssemblyPath(projectDirectory, targetFramework, packageName)
        if File.Exists(binPath) {
            surface.LoadByPath(binPath)
            return
        }

        effectiveVersion := version
        if effectiveVersion == null {
            effectiveVersion = TryGetRestoredPackageVersion(projectDirectory, packageName)
        }

        nugetCache := AnalyzerMetadataLoadPolicy.NuGetPackageCacheDirectory(
            Environment.GetEnvironmentVariable("NUGET_PACKAGES"),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            packageName
        )

        if !Directory.Exists(nugetCache) {
            surface.RecordFailure(packageName, AnalyzerReferenceLoadReport.PackageMissingDetail(nugetCache))
            return
        }

        versionDir := AnalyzerMetadataLoadPolicy.PackageVersionDirectory(nugetCache, effectiveVersion, Directory.GetDirectories(nugetCache))
        if versionDir == null {
            surface.RecordFailure(packageName, AnalyzerReferenceLoadReport.PackageVersionDeadEndDetail(effectiveVersion, nugetCache))
            return
        }

        if !Directory.Exists(versionDir) {
            surface.RecordFailure(packageName, AnalyzerReferenceLoadReport.PackageVersionDeadEndDetail(effectiveVersion, nugetCache))
            return
        }

        targetFrameworks := AnalyzerMetadataLoadPolicy.MetadataProbeTargetFrameworks(targetFramework)
        tfmIndex := 0
        while tfmIndex < targetFrameworks.Length {
            assetPath := AnalyzerMetadataLoadPolicy.PackageLibAssetPath(versionDir, targetFrameworks[tfmIndex], packageName)
            if File.Exists(assetPath) {
                surface.LoadByPath(assetPath)
                return
            }

            tfmIndex = tfmIndex + 1
        }

        surface.RecordFailure(
            packageName,
            AnalyzerReferenceLoadReport.PackageLibAssetMissingDetail(packageName, AnalyzerMetadataLoadPolicy.PackageLibRoot(versionDir))
        )
    }

    // A referenced project is reached through its BUILD OUTPUT, and which name that output carries is
    // a project-file question: a C# project's assembly name is its file name, an N# project's is
    // whatever `project.yml` declares. An unrecognised project file is a warning rather than a
    // failure, because the analysis can still say something useful without it.
    func LoadProjectReference(projectPath: string, targetFramework: string) {
        projectDirectory := Path.GetDirectoryName(projectPath) ?? ""

        if !AnalyzerMetadataLoadPolicy.IsRecognizedProjectReference(projectPath) {
            Console.Error.WriteLine(AnalyzerMetadataLoadPolicy.UnknownProjectReferenceWarning(projectPath))
            return
        }

        declaredName := ""
        if !AnalyzerMetadataLoadPolicy.IsCSharpProjectReference(projectPath) {
            declaredName = ProjectFileParser.Parse(projectPath).EffectiveName
        }

        assemblyName := AnalyzerMetadataLoadPolicy.ProjectReferenceAssemblyName(projectPath, declaredName)
        surface.LoadByPath(AnalyzerMetadataLoadPolicy.ProjectReferenceOutputPath(projectDirectory, targetFramework, assemblyName))
    }

    func TryGetRestoredPackageVersion(projectDirectory: string, packageName: string): string? {
        versions := GetRestoredPackageVersions(projectDirectory)
        if versions.ContainsKey(packageName) {
            return versions[packageName]
        }

        return null
    }

    // WHAT THE PROJECT ACTUALLY RESTORED, read from `obj/project.assets.json`. A project with no
    // restore output answers an empty map rather than failing: an unrestored project still analyses,
    // it just cannot pin versions. An unreadable or malformed assets file is the same answer for the
    // same reason.
    func GetRestoredPackageVersions(projectDirectory: string): Dictionary<string, string> {
        if restoredPackageVersionsByProject.ContainsKey(projectDirectory) {
            return restoredPackageVersionsByProject[projectDirectory]
        }

        versions := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        assetsPath := AnalyzerMetadataLoadPolicy.RestoredPackageAssetsPath(projectDirectory)
        if File.Exists(assetsPath) {
            try {
                document := JsonDocument.Parse(File.ReadAllText(assetsPath))
                root := document.RootElement
                libraries := new JsonElement()
                if root.TryGetProperty(AnalyzerMetadataLoadPolicy.RestoredLibrariesPropertyName(), out libraries) {
                    if libraries.ValueKind == JsonValueKind.Object {
                        entries := libraries.EnumerateObject()
                        while entries.MoveNext() {
                            entry := entries.Current
                            packageName := AnalyzerMetadataLoadPolicy.RestoredLibraryPackageName(entry.Name)
                            packageVersion := AnalyzerMetadataLoadPolicy.RestoredLibraryPackageVersion(entry.Name)
                            if packageName != null && packageVersion != null {
                                versions[packageName] = packageVersion
                            }
                        }
                    }
                }

                document.Dispose()
            } catch assetsError: Exception {
            }
        }

        restoredPackageVersionsByProject[projectDirectory] = versions
        return versions
    }
}
