namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

// Canonical exact-name resolver for CLR types. Qualified names use exact namespace/nested-type
// traversal; bare names use the same case-sensitive exported-type assembly scan as Analyzer.
public class ExternalQualifiedTypeResolver {
    public static func TryResolve(
        assemblies: IReadOnlyList<Assembly>,
        fullName: string,
        out runtimeType: Type): bool {
        runtimeType = typeof(object)
        if assemblies == null || fullName == null || fullName.Length == 0 {
            return false
        }
        if !fullName.Contains(".") {
            return TryResolveBareName(assemblies, fullName, out runtimeType)
        }

        candidate := fullName
        searchEnd := candidate.Length
        while searchEnd > 0 {
            index := 0
            while index < assemblies.Count {
                try {
                    resolved := assemblies[index].GetType(candidate)
                    if resolved != null {
                        exportedTypes := assemblies[index].GetExportedTypes()
                        typeIndex := 0
                        while typeIndex < exportedTypes.Length {
                            if exportedTypes[typeIndex] == resolved {
                                runtimeType = resolved
                                return true
                            }
                            typeIndex = typeIndex + 1
                        }
                    }
                } catch {
                    // A hostile metadata slot cannot replace an exact type from a later slot.
                }
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
            candidate = candidate.Substring(0, separator)
                + "+" + candidate.Substring(separator + 1)
            searchEnd = separator
        }
        return false
    }

    static func TryResolveBareName(
        assemblies: IReadOnlyList<Assembly>,
        name: string,
        out runtimeType: Type): bool {
        runtimeType = typeof(object)
        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            try {
                exportedTypes := assemblies[assemblyIndex].GetExportedTypes()
                typeIndex := 0
                while typeIndex < exportedTypes.Length {
                    candidate := exportedTypes[typeIndex]
                    if string.Equals(candidate.Name, name, StringComparison.Ordinal)
                        || string.Equals(candidate.FullName, name, StringComparison.Ordinal) {
                        runtimeType = candidate
                        return true
                    }
                    typeIndex = typeIndex + 1
                }
            } catch {
                // A hostile metadata slot cannot replace an exact type from a later slot.
            }
            assemblyIndex = assemblyIndex + 1
        }
        return false
    }

    public static func RootName(qualifiedName: string): string {
        separator := qualifiedName.IndexOf(".", StringComparison.Ordinal)
        if separator <= 0 {
            return qualifiedName
        }
        return qualifiedName.Substring(0, separator)
    }
}
