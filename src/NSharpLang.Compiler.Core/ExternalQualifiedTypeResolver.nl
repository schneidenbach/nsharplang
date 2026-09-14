namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// Canonical exact-name resolver for CLR types. Qualified names use exact namespace/nested-type
// traversal; bare names use the same case-sensitive exported-type assembly scan as Analyzer.
class ExternalQualifiedTypeResolver {
    static func TryResolve(assemblies: IReadOnlyList<Assembly>, fullName: string, out runtimeType: Type): bool {
        return TryResolve(assemblies, fullName, null, out runtimeType)
    }

    // THE NAMEABLE SURFACE, NOT THE EXPORTED ONE. `Assembly.GetType` answers for internal types too,
    // so this resolver checked membership of `GetExportedTypes()` to reject what a program cannot
    // spell. A reference that named this compilation in an `InternalsVisibleTo` widens what it CAN
    // spell, so the test is `InternalsVisibleToGrants.IsNameableType` — the same rule the analyzer's
    // metadata probe applies — and the exported list is what an absent grants object falls back to.
    static func TryResolve(assemblies: IReadOnlyList<Assembly>, fullName: string, grants: InternalsVisibleToGrants?, out runtimeType: Type): bool {
        runtimeType = typeof(object)
        if assemblies == null || fullName == null || fullName.Length == 0 {
            return false
        }
        if !fullName.Contains(".") {
            return TryResolveBareName(assemblies, fullName, grants, out runtimeType)
        }

        candidate := fullName
        searchEnd := candidate.Length
        while searchEnd > 0 {
            index := 0
            while index < assemblies.Count {
                try {
                    resolved := assemblies[index].GetType(candidate)
                    if resolved != null && IsNameable(resolved, grants) {
                        runtimeType = resolved
                        return true
                    }
                } catch {
                }
                // A hostile metadata slot cannot replace an exact type from a later slot.

                index = index + 1
            }

            separator := -1
            index = searchEnd - 1
            while index >= 0 {
                if candidate[index] == '.' {
                    separator = index
                    index = -1
                } else {
                    index = index - 1
                }
            }
            if separator <= 0 {
                return false
            }
            candidate = candidate.Substring(0, separator) + "+" + candidate.Substring(separator + 1)
            searchEnd = separator
        }
        return false
    }

    static func TryResolveBareName(assemblies: IReadOnlyList<Assembly>, name: string, out runtimeType: Type): bool {
        return TryResolveBareName(assemblies, name, null, out runtimeType)
    }

    static func TryResolveBareName(assemblies: IReadOnlyList<Assembly>, name: string, grants: InternalsVisibleToGrants?, out runtimeType: Type): bool {
        runtimeType = typeof(object)
        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            try {
                scanned := NameableTypes(assemblies[assemblyIndex], grants)
                typeIndex := 0
                while typeIndex < scanned.Length {
                    candidate := scanned[typeIndex]
                    if (string.Equals(candidate.Name, name, StringComparison.Ordinal) || string.Equals(candidate.FullName, name, StringComparison.Ordinal)) && IsNameable(candidate, grants) {
                        runtimeType = candidate
                        return true
                    }
                    typeIndex = typeIndex + 1
                }
            } catch {
            }
            // A hostile metadata slot cannot replace an exact type from a later slot.

            assemblyIndex = assemblyIndex + 1
        }
        return false
    }

    // The surface to SCAN. The public one for an ordinary reference; the declared one for a reference
    // that made this compilation a friend, since only `GetTypes()` returns its internals.
    static func NameableTypes(assembly: Assembly, grants: InternalsVisibleToGrants?): Type[] {
        if grants != null && grants.GrantsAccess(assembly) {
            return assembly.GetTypes()
        }

        return assembly.GetExportedTypes()
    }

    static func IsNameable(candidate: Type, grants: InternalsVisibleToGrants?): bool {
        if grants == null {
            return candidate.get_IsVisible()
        }

        return grants.IsNameableType(candidate)
    }

    static func RootName(qualifiedName: string): string {
        separator := qualifiedName.IndexOf(".", StringComparison.Ordinal)
        if separator <= 0 {
            return qualifiedName
        }
        return qualifiedName.Substring(0, separator)
    }
}
