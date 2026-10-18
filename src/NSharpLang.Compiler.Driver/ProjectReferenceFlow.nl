namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.Reflection
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

            // A project reference that cannot be read is reported by the reference loop in
            // `CompilationReferenceResolver` with its normal project-reference failure; this pass only
            // adds what a readable one carries.
            let referencedRoot: string = ""
            let referencedConfig: ProjectConfig? = null
            try {
                referencedRoot = ProjectReferenceResolver.ResolveNSharpProjectRoot(
                    CompilationReferenceResolverKernels.ResolveProjectReferencePath(projectRoot, projectPath)
                )
                referencedYml := CompilationReferenceResolverKernels.GetProjectYmlPath(referencedRoot)
                if !visited.Add(referencedRoot) || !File.Exists(referencedYml) {
                    continue
                }

                referencedConfig = ProjectFileParser.Parse(referencedYml)
            } catch unreadable: Exception {
                continue
            }

            if referencedConfig == null {
                continue
            }

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

    // THE DLL REFERENCES A PROJECT DECLARED ITSELF, taken before any reference flows in from a project
    // it references.
    static func SnapshotDllReferences(config: ProjectConfig): HashSet<string> {
        own := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for reference in config.Dependencies {
            if reference.Type == ReferenceType.Dll && reference.Dll != null {
                own.Add(Path.GetFullPath(reference.Dll ?? ""))
            }
        }

        return own
    }

    // ONE ASSEMBLY, ONE COMPILE REFERENCE. A compile reference that flows in from a referenced project
    // is added only if no reference to an assembly of the same name is there already: the project's
    // own reference wins (`own`); between two flowed ones the higher assembly version wins, as the
    // runtime side does (`ReferenceResolutionResult.SelectFlatRuntimeAssets`). Otherwise a project
    // referencing Newtonsoft.Json 12 itself and a project that uses 13 compiled against two files of
    // one assembly.
    static func AddFlowedCompileReference(config: ProjectConfig, own: HashSet<string>, assemblyPath: string) {
        if !File.Exists(assemblyPath) {
            return
        }

        fullPath := Path.GetFullPath(assemblyPath)
        fileName := Path.GetFileName(fullPath)
        for reference in config.Dependencies {
            if reference.Type != ReferenceType.Dll || reference.Dll == null {
                continue
            }

            existingPath := Path.GetFullPath(reference.Dll ?? "")
            if !string.Equals(Path.GetFileName(existingPath), fileName, StringComparison.OrdinalIgnoreCase) {
                continue
            }

            if string.Equals(existingPath, fullPath, StringComparison.OrdinalIgnoreCase) || own.Contains(existingPath) {
                return
            }

            if PreferredVersion(fullPath) > PreferredVersion(existingPath) {
                config.Dependencies.Remove(reference)
                config.Dependencies.Add(new Reference { Dll: fullPath })
            }

            return
        }

        config.Dependencies.Add(new Reference { Dll: fullPath })
    }

    private static func PreferredVersion(assemblyPath: string): Version {
        try {
            return AssemblyName.GetAssemblyName(assemblyPath).Version ?? new Version(0, 0, 0, 0)
        } catch unreadable: Exception {
            return new Version(0, 0, 0, 0)
        }
    }
}
