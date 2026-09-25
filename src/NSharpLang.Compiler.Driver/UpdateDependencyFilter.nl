namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import NSharpLang.Compiler

class UpdateDependencyFilter {
    static func FilterAllNuGetDependencies(dependencies: List<Reference>): List<Reference> {
        filteredDependencies := new List<Reference>()

        for dependency in dependencies {
            if dependency.Nuget != null {
                filteredDependencies.Add(dependency)
            }
        }

        return filteredDependencies
    }

    static func FilterAllNuGetDependencies(dependencies: Reference[]): List<Reference> {
        filteredDependencies := new List<Reference>()

        for dependency in dependencies {
            if dependency.Nuget != null {
                filteredDependencies.Add(dependency)
            }
        }

        return filteredDependencies
    }

    static func FilterTargetNuGetDependencies(dependencies: List<Reference>, targetPackage: string): List<Reference> {
        filteredDependencies := new List<Reference>()

        for dependency in dependencies {
            packageName := dependency.Nuget
            if packageName != null && string.Equals(packageName, targetPackage, StringComparison.OrdinalIgnoreCase) {
                filteredDependencies.Add(dependency)
            }
        }

        return filteredDependencies
    }

    static func FilterTargetNuGetDependencies(dependencies: Reference[], targetPackage: string): List<Reference> {
        filteredDependencies := new List<Reference>()

        for dependency in dependencies {
            packageName := dependency.Nuget
            if packageName != null && string.Equals(packageName, targetPackage, StringComparison.OrdinalIgnoreCase) {
                filteredDependencies.Add(dependency)
            }
        }

        return filteredDependencies
    }
}
