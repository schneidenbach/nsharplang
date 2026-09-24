namespace NSharpLang.Compiler

class GeneratorSequenceTypeFacts {
    static func IsSequenceReturnType(typeInfo: TypeInfo, isAsyncGenerator: bool): bool {
        generic := typeInfo as GenericTypeInfo
        if generic == null {
            return false
        }

        return IsGeneratorSequenceTypeName(generic.Name, generic.TypeArguments.Count, isAsyncGenerator)
    }

    static func IsGeneratorSequenceTypeName(name: string, arity: int, isAsyncGenerator: bool): bool {
        if arity != 1 {
            return false
        }

        unqualifiedName := StripGenericArity(UnqualifiedTypeName(name))

        if isAsyncGenerator {
            return unqualifiedName == "IAsyncEnumerable"
        }

        return unqualifiedName == "List" || unqualifiedName == "IEnumerable" || unqualifiedName == "ICollection" || unqualifiedName == "IList" || unqualifiedName == "IReadOnlyCollection" || unqualifiedName == "IReadOnlyList"
    }

    static func ExpectedSequenceKind(isAsyncGenerator: bool): string {
        if isAsyncGenerator {
            return "an async enumerable sequence type"
        }

        return "a synchronous enumerable sequence type"
    }

    static func ReturnTypeSuggestion(isAsyncGenerator: bool): string {
        if isAsyncGenerator {
            return "Use `IAsyncEnumerable<T>` for `async func*`."
        }

        return "Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`."
    }

    static func UnqualifiedTypeName(value: string): string {
        lastDot := -1
        index := 0
        while index < value.Length {
            if value[index] == '.' {
                lastDot = index
            }

            index = index + 1
        }

        if lastDot >= 0 && lastDot + 1 < value.Length {
            return value.Substring(lastDot + 1)
        }

        return value
    }

    static func StripGenericArity(value: string): string {
        index := 0
        while index < value.Length {
            if value[index] == '`' {
                return value.Substring(0, index)
            }

            index = index + 1
        }

        return value
    }
}
