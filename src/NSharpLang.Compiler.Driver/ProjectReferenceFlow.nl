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

    // THE SIMPLE NAMES OF ASSEMBLIES A PROJECT DECLARED ITSELF, taken before any reference flows in
    // from a project it references.
    static func SnapshotDllReferences(config: ProjectConfig): HashSet<string> {
        own := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for reference in config.Dependencies {
            if reference.Type == ReferenceType.Dll && reference.Dll != null {
                simpleName := GetAssemblySimpleName(Path.GetFullPath(reference.Dll ?? ""))
                if simpleName.Length > 0 {
                    own.Add(simpleName)
                }
            }
        }

        return own
    }

    // ONE ASSEMBLY SIMPLE NAME, ONE COMPILE REFERENCE. Compare assembly metadata rather than file
    // names: NuGet packages normally make them match, but a DLL's file name is not its assembly
    // identity. The project's own reference wins (`own`); between two flowed references the higher
    // NuGet package version wins, as the runtime side does
    // (`ReferenceResolutionResult.SelectFlatRuntimeAssets`). A non-package DLL falls back to its assembly version.
    static func AddFlowedCompileReference(config: ProjectConfig, own: HashSet<string>, assemblyPath: string) {
        if !File.Exists(assemblyPath) {
            return
        }

        fullPath := Path.GetFullPath(assemblyPath)
        simpleName := GetAssemblySimpleName(fullPath)
        if simpleName.Length == 0 {
            config.Dependencies.Add(new Reference { Dll: fullPath })
            return
        }

        for reference in config.Dependencies {
            if reference.Type != ReferenceType.Dll || reference.Dll == null {
                continue
            }

            existingPath := Path.GetFullPath(reference.Dll ?? "")
            existingSimpleName := GetAssemblySimpleName(existingPath)
            if existingSimpleName.Length == 0 || !string.Equals(existingSimpleName, simpleName, StringComparison.OrdinalIgnoreCase) {
                continue
            }

            if string.Equals(existingPath, fullPath, StringComparison.OrdinalIgnoreCase) || own.Contains(simpleName) {
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

    private static func GetAssemblySimpleName(assemblyPath: string): string {
        try {
            return AssemblyName.GetAssemblyName(assemblyPath).Name ?? ""
        } catch unreadable: Exception {
            return ""
        }
    }

    private static func PreferredVersion(assemblyPath: string): Version {
        packageVersion := ReferenceResolutionResult.ExtractRuntimeAssetVersion(assemblyPath)
        if ReferenceResolutionResult.IsHigherVersion(packageVersion, new Version(0, 0, 0, 0)) {
            return packageVersion
        }

        try {
            return AssemblyName.GetAssemblyName(assemblyPath).Version ?? new Version(0, 0, 0, 0)
        } catch unreadable: Exception {
            return new Version(0, 0, 0, 0)
        }
    }
}
