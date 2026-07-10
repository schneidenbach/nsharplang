namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

// Canonical exact-name resolver for namespace-qualified CLR type receivers. Analyzer routes a
// complete dotted receiver here instead of treating each namespace segment as a value expression.
public class ExternalQualifiedTypeResolver {
    public static func TryResolve(
        assemblies: IReadOnlyList<Assembly>,
        fullName: string,
        out runtimeType: Type): bool {
        runtimeType = typeof(object)
        if assemblies == null || fullName == null || fullName.Length == 0
            || !fullName.Contains(".") {
            return false
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

    public static func RootName(qualifiedName: string): string {
        separator := qualifiedName.IndexOf(".", StringComparison.Ordinal)
        if separator <= 0 {
            return qualifiedName
        }
        return qualifiedName.Substring(0, separator)
    }
}
