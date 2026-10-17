namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

// WHAT A `project:` REFERENCE CARRIES INTO THE PROJECT THAT REFERENCES IT, beyond its own assembly.
//
// MSBuild flows a ProjectReference's PackageReferences and FrameworkReferences to the referencing
// project, compile time and run time (unless the reference marks them private). The package half is
// done where the packages are resolved (`CompilationReferenceResolver`, through
// `ReferenceResolutionResult.CompileReferences`); the framework half is here, because shared
// frameworks are decided before any package is taken: a library on `Microsoft.AspNetCore.App` makes
// the application that references it an ASP.NET Core application too.
class ProjectReferenceFlow {
    static func AddTransitiveFrameworkReferences(projectRoot: string, config: ProjectConfig) {
        visited := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        visited.Add(projectRoot)
        AddFrom(projectRoot, config, config, visited)
    }

    private static func AddFrom(projectRoot: string, owner: ProjectConfig, target: ProjectConfig, visited: HashSet<string>) {
        projectReferences := CompilationReferenceResolverKernels.FilterReferencesByType(owner.Dependencies, ReferenceType.Project)
        for projectReference in projectReferences {
            projectPath := projectReference.Project
            if projectPath == null {
                continue
            }

            referencedRoot := ProjectReferenceResolver.ResolveNSharpProjectRoot(
                CompilationReferenceResolverKernels.ResolveProjectReferencePath(projectRoot, projectPath)
            )
            referencedYml := CompilationReferenceResolverKernels.GetProjectYmlPath(referencedRoot)
            if !visited.Add(referencedRoot) || !File.Exists(referencedYml) {
                continue
            }

            referencedConfig := ProjectFileParser.Parse(referencedYml)
            referencedFrameworks := CompilationReferenceResolverKernels.GetFrameworkReferenceNames(
                referencedConfig.Sdk,
                referencedConfig.Dependencies
            )
            for frameworkName in referencedFrameworks {
                if !HasFramework(target, frameworkName) {
                    target.Dependencies.Add(new Reference { Framework: frameworkName })
                }
            }

            AddFrom(referencedRoot, referencedConfig, target, visited)
        }
    }

    private static func HasFramework(config: ProjectConfig, frameworkName: string): bool {
        names := CompilationReferenceResolverKernels.GetFrameworkReferenceNames(config.Sdk, config.Dependencies)
        for name in names {
            if string.Equals(name, frameworkName, StringComparison.OrdinalIgnoreCase) {
                return true
            }
        }

        return false
    }
}
