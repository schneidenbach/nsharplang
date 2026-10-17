namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Cli
import NSharpLang.Cli.Commands

class SdkPackageReferenceProjection {
    Identity: string
    Metadata: Dictionary<string, string>

    constructor(identity: string, version: string?) {
        Identity = identity
        Metadata = new Dictionary<string, string>(StringComparer.Ordinal)
        versionValue := version ?? ""
        if versionValue.Length > 0 {
            Metadata.Add("Version", versionValue)
        }
    }
}

class SdkReferenceProjection {
    PackageReferences: SdkPackageReferenceProjection[]
    FrameworkReferences: string[]
    ProjectReferences: string[]
    DllReferences: string[]

    constructor(packageReferences: SdkPackageReferenceProjection[], frameworkReferences: string[], projectReferences: string[], dllReferences: string[]) {
        PackageReferences = packageReferences
        FrameworkReferences = frameworkReferences
        ProjectReferences = projectReferences
        DllReferences = dllReferences
    }
}

// The complete reference projection that the SDK adds before MSBuild constructs its restore and
// build graphs: packages, frameworks, projects and prebuilt DLLs. N# owns selection, metadata, path
// resolution, ordering, and deduplication; the MSBuild task only transports the resulting rows into
// item collections.
class SdkProjectReferenceProjection {
    static func Resolve(projectFile: string, existingProjectReferences: string[]): SdkReferenceProjection {
        config := ProjectFileParser.Parse(projectFile)
        dependencies := config.Dependencies

        packageDependencies := RestoreCommandKernels.FilterReferencesByType(dependencies, ReferenceType.NuGet)
        packageReferences := new SdkPackageReferenceProjection[](packageDependencies.Count)
        i := 0
        while i < packageDependencies.Count {
            dependency := packageDependencies[i]
            packageReferences[i] = new SdkPackageReferenceProjection(dependency.Nuget ?? "", dependency.Version)
            i = i + 1
        }

        frameworkReferences := ResolveFrameworks(config.Sdk, dependencies)
        projectReferences := ResolveProjects(projectFile, dependencies, existingProjectReferences)
        dllReferences := ResolveDlls(projectFile, dependencies)
        return new SdkReferenceProjection(packageReferences, frameworkReferences, projectReferences, dllReferences)
    }

    // A FRAMEWORK MSBUILD ALREADY REFERENCES IS NOT PROJECTED AGAIN. The base SDK always references
    // `Microsoft.NETCore.App` and `Microsoft.NET.Sdk.Web` also references `Microsoft.AspNetCore.App`
    // (`CompilationReferenceResolverKernels.IsMsBuildImplicitFramework`); an explicit
    // `FrameworkReference` to either draws NETSDK1086 on every `dotnet build`. `nlc` has no implicit
    // framework of its own, so the project.yml entry still matters there and is dropped from the
    // MSBuild projection only.
    static func ResolveFrameworks(sdk: string, dependencies: IEnumerable<Reference>): string[] {
        frameworkDependencies := RestoreCommandKernels.FilterReferencesByType(dependencies, ReferenceType.Framework)
        frameworks := new List<string>()
        for dependency in frameworkDependencies {
            name := dependency.Framework ?? ""
            if !CompilationReferenceResolverKernels.IsMsBuildImplicitFramework(sdk, name) {
                frameworks.Add(name)
            }
        }

        return frameworks.ToArray()
    }

    // A `dll:` ENTRY IS AN MSBUILD `Reference` TOO. The compiler reads the entry straight from
    // project.yml, so `dotnet build` compiled against it without this row -- but MSBuild never heard
    // of the assembly, so it was neither copied beside the output nor written into `.deps.json`, and
    // the built program failed at its first use with "Could not load file or assembly". As a
    // `Reference` item MSBuild resolves it the way `nlc build` does: copied to the output directory and
    // recorded as a runtime dependency. Paths resolve against the project directory, as `nlc` resolves
    // them, and the rows keep source order with exact duplicates removed.
    static func ResolveDlls(projectFile: string, dependencies: IEnumerable<Reference>): string[] {
        projectDirectory := Path.GetDirectoryName(Path.GetFullPath(projectFile)) ?? ""
        dllDependencies := RestoreCommandKernels.FilterReferencesByType(dependencies, ReferenceType.Dll)
        resolved := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for dependency in dllDependencies {
            fullPath := Path.GetFullPath(AnalyzerMetadataLoadPolicy.ResolvedReferencePath(projectDirectory, dependency.Dll ?? ""))
            if seen.Add(fullPath) {
                resolved.Add(fullPath)
            }
        }

        return resolved.ToArray()
    }

    static func ResolveProjects(projectFile: string, dependencies: IEnumerable<Reference>, existingProjectReferences: string[]): string[] {
        projectDirectory := Path.GetDirectoryName(Path.GetFullPath(projectFile))
        if string.IsNullOrWhiteSpace(projectDirectory) {
            throw new InvalidOperationException("Could not determine the project directory for '" + projectFile + "'.")
        }

        projectDependencies := RestoreCommandKernels.FilterReferencesByType(dependencies, ReferenceType.Project)
        resolved := new List<string>()
        for dependency in projectDependencies {
            writtenPath := dependency.Project ?? ""
            candidatePath := writtenPath
            if !Path.IsPathRooted(writtenPath) {
                candidatePath = Path.Combine(projectDirectory ?? "", writtenPath)
            }

            resolved.Add(ProjectReferenceResolver.ResolveMsBuildProjectPath(candidatePath))
        }

        existingUnique := RestoreCommandKernels.DeduplicateProjectReferences(existingProjectReferences)
        combined := new List<string>()
        for existing in existingUnique {
            combined.Add(existing)
        }
        for candidate in resolved {
            combined.Add(candidate)
        }

        allUnique := RestoreCommandKernels.DeduplicateProjectReferences(combined)
        additions := new string[](allUnique.Length - existingUnique.Length)
        index := existingUnique.Length
        while index < allUnique.Length {
            additions[index - existingUnique.Length] = allUnique[index]
            index = index + 1
        }

        return additions
    }
}
