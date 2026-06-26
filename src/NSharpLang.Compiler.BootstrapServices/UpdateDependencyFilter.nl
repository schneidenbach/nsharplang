namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import NSharpLang.Compiler

public class UpdateDependencyFilter {
    public static func FilterAllNuGetDependencies(dependencies: List<Reference>): List<Reference> {
        filteredDependencies := new List<Reference>()

        i := 0
        while i < dependencies.Count {
            dependency := dependencies[i]
            if dependency.Nuget != null {
                filteredDependencies.Add(dependency)
            }

            i = i + 1
        }

        return filteredDependencies
    }

    public static func FilterAllNuGetDependencies(dependencies: Reference[]): List<Reference> {
        filteredDependencies := new List<Reference>()

        i := 0
        while i < dependencies.Length {
            dependency := dependencies[i]
            if dependency.Nuget != null {
                filteredDependencies.Add(dependency)
            }

            i = i + 1
        }

        return filteredDependencies
    }

    public static func FilterTargetNuGetDependencies(
        dependencies: List<Reference>,
        targetPackage: string): List<Reference> {
        filteredDependencies := new List<Reference>()

        i := 0
        while i < dependencies.Count {
            dependency := dependencies[i]
            packageName := dependency.Nuget
            if packageName != null
                && string.Equals(packageName, targetPackage, StringComparison.OrdinalIgnoreCase) {
                filteredDependencies.Add(dependency)
            }

            i = i + 1
        }

        return filteredDependencies
    }

    public static func FilterTargetNuGetDependencies(
        dependencies: Reference[],
        targetPackage: string): List<Reference> {
        filteredDependencies := new List<Reference>()

        i := 0
        while i < dependencies.Length {
            dependency := dependencies[i]
            packageName := dependency.Nuget
            if packageName != null
                && string.Equals(packageName, targetPackage, StringComparison.OrdinalIgnoreCase) {
                filteredDependencies.Add(dependency)
            }

            i = i + 1
        }

        return filteredDependencies
    }
}
