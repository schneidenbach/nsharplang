namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Cli.Commands

// The project-reference rows that the SDK must add before MSBuild constructs its build graph.
// Filtering and deduplication reuse the same N# policy as `nlc restore`; the MSBuild task only
// wraps these decided paths as ITaskItem values.
class SdkProjectReferenceProjection {
    static func Resolve(projectFile: string, dependencies: IEnumerable<Reference>, existingProjectReferences: string[]): string[] {
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
