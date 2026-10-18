namespace NSharpLang.Cli

import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

// WHAT A RESTORED PACKAGE PUTS BESIDE THE APPLICATION BEYOND ITS PORTABLE `lib/<tfm>` ASSEMBLIES.
//
// NuGet lays a package out in three places that matter at run time: `lib/<tfm>/*.dll` (the portable
// managed assemblies, chosen by the nearest-framework rule), `runtimes/<rid>/native/*` (native
// libraries for one operating system and architecture) and `runtimes/<rid>/lib/<tfm>/*.dll`
// (managed assemblies that replace or extend the portable ones on one RID). `dotnet build` copies
// all three and writes a `deps.json` whose `runtimeTargets` rows let the host pick the file for the
// RID it runs on. This selector reads the same layout so the nlc output is the same shape: every
// RID's files are carried (the application stays portable across machines), and the host -- not the
// build -- decides which one loads.
class NuGetRuntimeAssetSelector {

    // `managedAssemblies` are the portable `lib/<tfm>` files the resolver already picked; they are
    // recorded as package files so the dependency manifest can name the package that owns each one.
    static func Select(
        packageId: string,
        packageVersion: string,
        versionDirectory: string,
        targetFramework: string,
        managedAssemblies: IReadOnlyList<string>
    ): List<PackageRuntimeFile> {
        files := new List<PackageRuntimeFile>()
        for managedAssembly in managedAssemblies {
            files.Add(
                new PackageRuntimeFile(
                    packageId,
                    packageVersion,
                    versionDirectory,
                    managedAssembly,
                    CompilationReferenceResolverKernels.GetPackageRelativePath(versionDirectory, managedAssembly),
                    null,
                    "runtime"
                )
            )
        }

        runtimesRoot := Path.Combine(versionDirectory, "runtimes")
        if !Directory.Exists(runtimesRoot) {
            return files
        }

        ridDirectories := CompilationReferenceResolverKernels.SortPathsIgnoreCase(
            Directory.GetDirectories(runtimesRoot, "*", SearchOption.TopDirectoryOnly)
        )
        for ridDirectory in ridDirectories {
            rid := Path.GetFileName(ridDirectory) ?? ""
            if rid.Length == 0 {
                continue
            }

            nativeDirectory := Path.Combine(ridDirectory, "native")
            if Directory.Exists(nativeDirectory) {
                AddNativeFiles(files, packageId, packageVersion, versionDirectory, nativeDirectory, rid)
            }

            // `runtimes/<rid>/nativeassets/<tfm>/*` (UWP): the nearest framework folder, as for `lib`.
            nativeAssetsRoot := Path.Combine(ridDirectory, "nativeassets")
            if Directory.Exists(nativeAssetsRoot) {
                nativeAssetsDirectory := CompilationReferenceResolverKernels.SelectBestAssetDirectory(
                    Directory.GetDirectories(nativeAssetsRoot, "*", SearchOption.TopDirectoryOnly),
                    targetFramework
                )
                if nativeAssetsDirectory != null {
                    AddNativeFiles(files, packageId, packageVersion, versionDirectory, nativeAssetsDirectory, rid)
                }
            }

            ridLibraryRoot := Path.Combine(ridDirectory, "lib")
            if Directory.Exists(ridLibraryRoot) {
                bestDirectory := CompilationReferenceResolverKernels.SelectBestAssetDirectory(
                    Directory.GetDirectories(ridLibraryRoot, "*", SearchOption.TopDirectoryOnly),
                    targetFramework
                )
                if bestDirectory != null {
                    ridAssemblies := CompilationReferenceResolverKernels.SortPathsIgnoreCase(
                        Directory.GetFiles(bestDirectory, "*.dll", SearchOption.TopDirectoryOnly)
                    )
                    for ridAssembly in ridAssemblies {
                        files.Add(
                            new PackageRuntimeFile(
                                packageId,
                                packageVersion,
                                versionDirectory,
                                ridAssembly,
                                CompilationReferenceResolverKernels.GetPackageRelativePath(versionDirectory, ridAssembly),
                                rid,
                                "runtime"
                            )
                        )
                    }
                }
            }
        }

        return files
    }

    // Every file under a native folder, nested folders included: a package may group libraries in
    // subfolders and the host resolves each by its `runtimeTargets` path.
    private static func AddNativeFiles(
        files: List<PackageRuntimeFile>,
        packageId: string,
        packageVersion: string,
        versionDirectory: string,
        nativeDirectory: string,
        rid: string
    ) {
        nativeFiles := CompilationReferenceResolverKernels.SortPathsIgnoreCase(
            Directory.GetFiles(nativeDirectory, "*", SearchOption.AllDirectories)
        )
        for nativeFile in nativeFiles {
            if CompilationReferenceResolverKernels.IsPackagePlaceholderFile(nativeFile) {
                continue
            }

            files.Add(
                new PackageRuntimeFile(
                    packageId,
                    packageVersion,
                    versionDirectory,
                    nativeFile,
                    CompilationReferenceResolverKernels.GetPackageRelativePath(versionDirectory, nativeFile),
                    rid,
                    "native"
                )
            )
        }
    }
}
