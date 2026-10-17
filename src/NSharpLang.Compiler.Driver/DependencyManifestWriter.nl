namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Reflection
import System.Text.Json
import NSharpLang.Compiler

// THE `<assembly>.deps.json` NEXT TO A BUILT ASSEMBLY, as `dotnet build` writes it.
//
// The .NET host builds its trusted-assembly list from this file whenever it exists, and resolves
// RID-specific assets from it: a package's `runtimes/<rid>/native/*` library is found only through a
// `runtimeTargets` row, which is why `Microsoft.Data.Sqlite` threw `DllNotFoundException` for
// `e_sqlite3` when the build copied the managed files and nothing else. `WebApplicationFactory`
// reads the application's file too. The manifest lists exactly what the build copied
// (`ReferenceResolutionResult.SelectFlatRuntimeAssets` / `SelectRuntimeTargetFiles` are the one
// selection both the copy and this file read), so the file can never name a file that is not there
// or omit one that is.
//
// A restored package is a `package` library keyed `id/version`; every other assembly (a referenced
// project's output, `NSharpLang.Runtime`, a `dll:` reference) is a `reference` library. Each managed
// row carries the assembly and file versions the host uses to prefer the higher of two copies of one
// assembly -- the same rule `dotnet build` output follows.
class DependencyManifestWriter {
    static func Write(config: ProjectConfig, references: ReferenceResolutionResult, assemblyPath: string) {
        manifestPath := Path.ChangeExtension(assemblyPath, ".deps.json")
        text := Build(config, references, assemblyPath)
        if File.Exists(manifestPath) && File.ReadAllText(manifestPath) == text {
            return
        }

        File.WriteAllText(manifestPath, text)
    }

    static func Build(config: ProjectConfig, references: ReferenceResolutionResult, assemblyPath: string): string {
        targetName := CompilationReferenceResolverKernels.GetDependencyManifestTargetName(config.TargetFramework)
        assemblyName := Path.GetFileNameWithoutExtension(assemblyPath)
        applicationKey := assemblyName + "/" + (config.Version ?? "1.0.0")

        targets := new SortedDictionary<string, object>(StringComparer.Ordinal)
        libraries := new SortedDictionary<string, object>(StringComparer.Ordinal)

        applicationRuntime := new SortedDictionary<string, object>(StringComparer.Ordinal)
        applicationRuntime[Path.GetFileName(assemblyPath)] = new SortedDictionary<string, object>(StringComparer.Ordinal)
        applicationEntry := new SortedDictionary<string, object>(StringComparer.Ordinal)
        applicationEntry["runtime"] = applicationRuntime
        targets[applicationKey] = applicationEntry
        libraries[applicationKey] = CreateLibrary("project", false, "")

        packageFilesByPath := new Dictionary<string, PackageRuntimeFile>(StringComparer.OrdinalIgnoreCase)
        for packageFile in references.PackageFiles {
            if packageFile.Rid == null {
                packageFilesByPath[Path.GetFullPath(packageFile.SourcePath)] = packageFile
            }
        }

        fullAssemblyPath := Path.GetFullPath(assemblyPath)
        flatAssets := references.SelectFlatRuntimeAssets()
        for flatEntry in flatAssets {
            assetPath := flatEntry.Value
            if !flatEntry.Key.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) {
                continue
            }

            if string.Equals(Path.GetFullPath(assetPath), fullAssemblyPath, StringComparison.OrdinalIgnoreCase) {
                continue
            }

            let owner: PackageRuntimeFile? = null
            if packageFilesByPath.TryGetValue(Path.GetFullPath(assetPath), out owner) && owner != null {
                packageEntry := EnsurePackage(targets, libraries, owner)
                GetSection(packageEntry, "runtime")[owner.RelativePath] = ManagedVersions(assetPath)
                continue
            }

            versions := ManagedVersions(assetPath)
            referenceVersion := "0.0.0.0"
            let assemblyVersion: object? = null
            if versions.TryGetValue("assemblyVersion", out assemblyVersion) && assemblyVersion != null {
                referenceVersion = assemblyVersion.ToString() ?? referenceVersion
            }

            referenceKey := Path.GetFileNameWithoutExtension(flatEntry.Key) + "/" + referenceVersion
            referenceRuntime := new SortedDictionary<string, object>(StringComparer.Ordinal)
            referenceRuntime[flatEntry.Key] = versions
            referenceEntry := new SortedDictionary<string, object>(StringComparer.Ordinal)
            referenceEntry["runtime"] = referenceRuntime
            targets[referenceKey] = referenceEntry
            libraries[referenceKey] = CreateLibrary("reference", false, "")
        }

        for runtimeTarget in references.SelectRuntimeTargetFiles() {
            packageEntry := EnsurePackage(targets, libraries, runtimeTarget)
            row := new SortedDictionary<string, object>(StringComparer.Ordinal)
            row["rid"] = runtimeTarget.Rid ?? ""
            row["assetType"] = runtimeTarget.AssetType
            if runtimeTarget.AssetType == "runtime" {
                versions := ManagedVersions(runtimeTarget.SourcePath)
                for version in versions {
                    row[version.Key] = version.Value
                }
            } else {
                row["fileVersion"] = "0.0.0.0"
            }

            GetSection(packageEntry, "runtimeTargets")[runtimeTarget.RelativePath] = row
        }

        runtimeTarget := new SortedDictionary<string, object>(StringComparer.Ordinal)
        runtimeTarget["name"] = targetName
        runtimeTarget["signature"] = ""
        targetGroups := new SortedDictionary<string, object>(StringComparer.Ordinal)
        targetGroups[targetName] = targets

        payload := new SortedDictionary<string, object>(StringComparer.Ordinal)
        payload["compilationOptions"] = new SortedDictionary<string, object>(StringComparer.Ordinal)
        payload["libraries"] = libraries
        payload["runtimeTarget"] = runtimeTarget
        payload["targets"] = targetGroups
        return JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented: true }) + Environment.NewLine
    }

    private static func CreateLibrary(kind: string, serviceable: bool, hash: string): SortedDictionary<string, object> {
        library := new SortedDictionary<string, object>(StringComparer.Ordinal)
        library["serviceable"] = serviceable
        library["sha512"] = hash
        library["type"] = kind
        return library
    }

    // The target row and the library row of the package that owns `file`, created on first use.
    private static func EnsurePackage(
        targets: SortedDictionary<string, object>,
        libraries: SortedDictionary<string, object>,
        file: PackageRuntimeFile
    ): SortedDictionary<string, object> {
        key := file.PackageId + "/" + file.PackageVersion
        let existing: object? = null
        if targets.TryGetValue(key, out existing) {
            existingEntry := existing as SortedDictionary<string, object>
            if existingEntry != null {
                return existingEntry
            }
        }

        entry := new SortedDictionary<string, object>(StringComparer.Ordinal)
        targets[key] = entry

        library := CreateLibrary("package", true, "")
        hashFiles := Directory.GetFiles(file.PackageDirectory, "*.nupkg.sha512", SearchOption.TopDirectoryOnly)
        if hashFiles.Length > 0 {
            library["sha512"] = "sha512-" + File.ReadAllText(hashFiles[0]).Trim()
            library["hashPath"] = Path.GetFileName(hashFiles[0])
        }

        packageParent := Path.GetDirectoryName(file.PackageDirectory.TrimEnd(Path.DirectorySeparatorChar)) ?? ""
        library["path"] = Path.GetFileName(packageParent) + "/" + Path.GetFileName(file.PackageDirectory.TrimEnd(Path.DirectorySeparatorChar))
        libraries[key] = library
        return entry
    }

    private static func GetSection(entry: SortedDictionary<string, object>, name: string): SortedDictionary<string, object> {
        let existing: object? = null
        if entry.TryGetValue(name, out existing) {
            existingSection := existing as SortedDictionary<string, object>
            if existingSection != null {
                return existingSection
            }
        }

        section := new SortedDictionary<string, object>(StringComparer.Ordinal)
        entry[name] = section
        return section
    }

    // `assemblyVersion` and `fileVersion` of a managed file; an unreadable file yields none, which
    // the host reads as the lowest version.
    private static func ManagedVersions(path: string): SortedDictionary<string, object> {
        versions := new SortedDictionary<string, object>(StringComparer.Ordinal)
        try {
            versions["assemblyVersion"] = AssemblyName.GetAssemblyName(path).Version.ToString()
        } catch badImage: BadImageFormatException {
            return versions
        }

        info := FileVersionInfo.GetVersionInfo(path)
        versions["fileVersion"] = new Version(info.FileMajorPart, info.FileMinorPart, info.FileBuildPart, info.FilePrivatePart).ToString()
        return versions
    }
}
