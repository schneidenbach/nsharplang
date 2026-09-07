namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
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

    constructor(packageReferences: SdkPackageReferenceProjection[], frameworkReferences: string[], projectReferences: string[]) {
        PackageReferences = packageReferences
        FrameworkReferences = frameworkReferences
        ProjectReferences = projectReferences
    }
}

// The complete reference projection that the SDK adds before MSBuild constructs its restore and
// build graphs. N# owns selection, metadata, path resolution, ordering, and deduplication; the
// MSBuild task only transports the resulting rows into item collections.
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

        frameworkDependencies := RestoreCommandKernels.FilterReferencesByType(dependencies, ReferenceType.Framework)
        frameworkReferences := new string[](frameworkDependencies.Count)
        i = 0
        while i < frameworkDependencies.Count {
            frameworkReferences[i] = frameworkDependencies[i].Framework ?? ""
            i = i + 1
        }

        projectReferences := ResolveProjects(projectFile, dependencies, existingProjectReferences)
        return new SdkReferenceProjection(packageReferences, frameworkReferences, projectReferences)
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
