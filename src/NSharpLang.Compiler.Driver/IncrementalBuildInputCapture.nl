namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Linq
import System.Runtime.InteropServices
import NSharpLang.Compiler.Ast

// THE INPUT INVENTORY OF ONE MULTI-FILE COMPILATION: every file and directory the parse, the
// analysis, the strict lint and the emission consult, named in one place so the up-to-date check
// cannot be wrong by omission somewhere else. Each row below names the reader it stands for.
//
// Most of it is known BEFORE the compilation runs and is captured then, so that a file which changes
// while the compiler is reading it is recorded with its old value and the next build runs again. Two
// rows are only knowable AFTER: the files the parsed units import by path, and the metadata the
// analyzer's load context actually read (the resolver loads lazily). Those are captured from the
// finished compilation.
class IncrementalBuildInputCapture {
    private readonly entries: List<IncrementalInputEntry>
    private readonly seen: HashSet<string>
    private readonly installedRuntimeRoots: List<string>

    constructor() {
        entries = new List<IncrementalInputEntry>()
        seen = new HashSet<string>(StringComparer.Ordinal)
        installedRuntimeRoots = InstalledRuntimeRoots()
    }

    Entries: List<IncrementalInputEntry> => entries

    // ---- before the compilation -------------------------------------------------------------------

    func CaptureBeforeCompile(projectRoot: string, config: ProjectConfig, sourceFiles: IReadOnlyList<string>) {
        fullRoot := Path.GetFullPath(projectRoot)

        // The sources themselves (`MultiFileCompiler.ParseAllFiles`, the emitter's own parse).
        for sourceFile in sourceFiles {
            AddFile(Path.GetFullPath(sourceFile))
        }

        // The analyzer's project walk (`AnalyzerProjectSourceProvider.ProjectNamespaces`) reads every
        // `.nl` file under the root, whether or not this compilation compiles it, and the reference
        // orchestration asks whether any `*.tests.nl` exists (`HasTestSources`).
        Add(IncrementalInputEntry.ProjectSourceEnumeration, fullRoot)
        for enumerated in ProjectConfig.EnumerateSourceFileArray(fullRoot) {
            AddFile(Path.GetFullPath(enumerated))
        }
        Add(IncrementalInputEntry.TestSourcePresence, fullRoot)

        // The project file itself, byte for byte: the parsed configuration is in the key, and this
        // row makes ANY edit to `project.yml` invalidate, including one the parser ignores today.
        AddFile(Path.Combine(fullRoot, "project.yml"))

        // The strict linter's configuration (`LinterConfig.FromEditorConfig`): every `.editorconfig`
        // from each source directory up to the filesystem root. Absence is recorded too, so adding
        // one invalidates.
        directories := new HashSet<string>(StringComparer.Ordinal)
        for sourceFile in sourceFiles {
            directory := Path.GetDirectoryName(Path.GetFullPath(sourceFile))
            while directory != null && directories.Add(directory) {
                AddFile(Path.Combine(directory, ".editorconfig"))
                directory = Path.GetDirectoryName(directory)
            }
        }

        // The restore output the reference orchestration pins package versions from.
        AddFile(AnalyzerMetadataLoadPolicy.RestoredPackageAssetsPath(fullRoot))

        // Systems hot-summary sidecars (`HotSummaryCatalog.Load`).
        for sidecar in config.Language.Systems.HotSummaryFiles {
            sidecarPath := sidecar
            if !Path.IsPathRooted(sidecar) {
                sidecarPath = Path.Combine(fullRoot, sidecar)
            }
            AddFile(Path.GetFullPath(sidecarPath))
        }

        // Every referenced assembly the emitter and the analyzer are handed by path.
        for referencePath in ExternalAssemblyScan.ResolveReferencePaths(fullRoot, config.Dependencies) {
            AddAssembly(referencePath)
        }
        for runtimePath in ExternalAssemblyScan.ResolveRuntimeAssetPaths(fullRoot, config.Dependencies) {
            AddAssembly(runtimePath)
        }

        // Package and project references, as the reference orchestration resolves them: a locally
        // built copy in the project's own `bin/` outranks the cache, the cache directory's version
        // folders decide an unpinned version, and a referenced project's own `project.yml` names its
        // assembly.
        packagesRoot := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
        userProfile := Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        AddReferences(fullRoot, config, config.Dependencies, packagesRoot, userProfile)
        AddReferences(fullRoot, config, config.TestDependencies, packagesRoot, userProfile)

        // The N# runtime the compiler ships beside itself.
        AddFile(Path.Combine(AppContext.BaseDirectory, "NSharpLang.Runtime.dll"))
    }

    private func AddReferences(projectRoot: string, config: ProjectConfig, references: List<Reference>, packagesRoot: string?, userProfile: string) {
        for reference in references {
            if reference == null {
                continue
            }

            nuget := reference.Nuget
            if nuget != null {
                AddFile(AnalyzerMetadataLoadPolicy.LocallyBuiltPackageAssemblyPath(projectRoot, config.TargetFramework, nuget))
                Add(IncrementalInputEntry.DirectoryListing, AnalyzerMetadataLoadPolicy.NuGetPackageCacheDirectory(packagesRoot, userProfile, nuget))
            }

            project := reference.Project
            if project != null {
                projectPath := project
                if !Path.IsPathRooted(projectPath) {
                    projectPath = Path.Combine(projectRoot, projectPath)
                }
                AddFile(Path.GetFullPath(projectPath))
            }
        }
    }

    // ---- after the compilation --------------------------------------------------------------------

    // Files the units import by path (`AnalyzerImports`, `LinterFileImportUsage`): each spelling a
    // resolver tries, so a file appearing at an earlier candidate is seen.
    func CaptureFileImports(projectRoot: string, units: IReadOnlyDictionary<string, CompilationUnit>) {
        for pair in units {
            sourceFile := Path.GetFullPath(pair.Key)
            unit := pair.Value
            if unit == null {
                continue
            }

            resolver := new FileResolver(projectRoot, sourceFile)
            directory := Path.GetDirectoryName(sourceFile) ?? projectRoot
            for fileImport in unit.FileImports.OfType<FileImport>() {
                importPath := fileImport.Path
                AddFile(Path.GetFullPath(resolver.ResolveFilePath(importPath)))
                AddFile(Path.GetFullPath(Path.Combine(directory, importPath)))
                AddFile(Path.GetFullPath(Path.Combine(directory, importPath + ".nl")))
            }
        }
    }

    // The metadata the analyzer's load context read, including assemblies its resolver loaded lazily,
    // and the directories that resolver probes (a sibling assembly appearing in one can change what a
    // later resolution finds).
    func CaptureMetadataInputs(assemblyPaths: List<string>, searchDirectories: List<string>) {
        for assemblyPath in assemblyPaths {
            AddAssembly(assemblyPath)
        }

        for directory in searchDirectories {
            fullDirectory := Path.GetFullPath(directory)
            Add(IncrementalInputEntry.DirectoryListing, fullDirectory)
            // A framework version directory was chosen from its parent's listing (the version ladder).
            if IsInstalledRuntimePath(fullDirectory) {
                parent := Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(fullDirectory))
                if parent != null {
                    Add(IncrementalInputEntry.DirectoryListing, parent)
                }
            }
        }
    }

    // ---- rows -------------------------------------------------------------------------------------

    private func AddAssembly(path: string) {
        fullPath := Path.GetFullPath(path)
        if IsInstalledRuntimePath(fullPath) {
            Add(IncrementalInputEntry.InstalledRuntimeFile, fullPath)
            return
        }

        AddFile(fullPath)
    }

    private func AddFile(path: string) {
        Add(IncrementalInputEntry.FileContent, path)
    }

    private func Add(kind: int, path: string) {
        identity := kind.ToString(System.Globalization.CultureInfo.InvariantCulture) + "|" + path
        if !seen.Add(identity) {
            return
        }

        entries.Add(IncrementalInputEntry.Capture(kind, path))
    }

    // THE IMMUTABLE STORES: the running .NET installation's `shared/` and `packs/` trees. Their
    // directories are named by exact version and an installer never rewrites a file in place; the
    // key already carries the runtime's version and directory.
    private func IsInstalledRuntimePath(fullPath: string): bool {
        for root in installedRuntimeRoots {
            if fullPath.StartsWith(root, StringComparison.Ordinal) {
                return true
            }
        }

        return false
    }

    private static func InstalledRuntimeRoots(): List<string> {
        roots := new List<string>()
        sharedRoot := AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory(RuntimeEnvironment.GetRuntimeDirectory())
        if sharedRoot == null {
            return roots
        }

        dotnetRoot := Path.GetDirectoryName(sharedRoot)
        roots.Add(Path.GetFullPath(sharedRoot) + Path.DirectorySeparatorChar.ToString())
        if dotnetRoot != null {
            roots.Add(Path.GetFullPath(Path.Combine(dotnetRoot, "packs")) + Path.DirectorySeparatorChar.ToString())
        }

        return roots
    }
}
