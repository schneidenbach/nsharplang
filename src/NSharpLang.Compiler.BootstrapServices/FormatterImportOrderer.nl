namespace NSharpLang.Compiler

import System
import System.Collections.Generic

public class FormatterImportOrderer {
    public static func OrderBySystemThenNamespace<T>(imports: IReadOnlyList<T>): List<T> {
        count := imports.Count
        namespaces := new string[](count)
        resultIndices := new int[](count)

        i := 0
        while i < count {
            namespaces[i] = FormatterImportNamespace(imports[i])
            resultIndices[i] = i
            i = i + 1
        }

        i = 1
        while i < count {
            currentIndex := resultIndices[i]
            j := i

            while j > 0 {
                previousIndex := resultIndices[j - 1]
                if !FormatterImportNamespaceComesAfter(namespaces[previousIndex], namespaces[currentIndex]) {
                    break
                }

                resultIndices[j] = previousIndex
                j = j - 1
            }

            resultIndices[j] = currentIndex
            i = i + 1
        }

        result := new List<T>()
        i = 0
        while i < count {
            result.Add(imports[resultIndices[i]])
            i = i + 1
        }

        return result
    }

    static func FormatterImportNamespace(value: object): string {
        property := value.GetType().GetProperty("Namespace")
        if property != null {
            name := FormatterImportNamespaceValue(property.GetValue(value))
            if name.Length > 0 {
                return name
            }
        }

        field := value.GetType().GetField("Namespace")
        if field == null {
            return ""
        }

        return FormatterImportNamespaceValue(field.GetValue(value))
    }

    static func FormatterImportNamespaceValue(rawName: object): string {
        if rawName == null {
            return ""
        }

        name := rawName as string
        if name == null {
            return ""
        }

        return name
    }

    static func FormatterImportNamespaceComesAfter(left: string, right: string): bool {
        leftIsSystem := FormatterImportNamespaceStartsWithSystem(left)
        rightIsSystem := FormatterImportNamespaceStartsWithSystem(right)

        if leftIsSystem != rightIsSystem {
            return !leftIsSystem && rightIsSystem
        }

        return String.Compare(left, right, StringComparison.CurrentCulture) > 0
    }

    static func FormatterImportNamespaceStartsWithSystem(namespaceName: string): bool {
        if namespaceName.Length < 6 {
            return false
        }

        return String.Compare(namespaceName, 0, "System", 0, 6, StringComparison.CurrentCulture) == 0
    }
}
