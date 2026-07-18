namespace NSharpLang.Compiler

import System.Collections.Generic

class LoopSequenceTypeFacts {
    static func GetGenericLoopSequenceElementType(genericType: GenericTypeInfo, requireAsync: bool): TypeInfo? {
        if genericType.GenericDefinition != null
            && genericType.GenericDefinition as ReflectionTypeInfo == null {
            return null
        }
        name := StripGenericArity(UnqualifiedTypeName(genericType.Name))

        if requireAsync {
            if name == "IAsyncEnumerable" && genericType.TypeArguments.Count == 1 {
                return genericType.TypeArguments[0]
            }

            return null
        }

        if IsDictionaryTypeName(name) && genericType.TypeArguments.Count == 2 {
            arguments := new List<TypeInfo>()
            arguments.Add(genericType.TypeArguments[0])
            arguments.Add(genericType.TypeArguments[1])
            definition := Type.GetType(
                "System.Collections.Generic.KeyValuePair`2")
            if definition == null {
                throw new InvalidOperationException(
                    "Required KeyValuePair generic definition was not found.")
            }
            definitionInfo := new ReflectionTypeInfo(definition)
            return new GenericTypeInfo(
                "KeyValuePair",
                arguments,
                definitionInfo)
        }

        if genericType.TypeArguments.Count != 1 {
            return null
        }

        if IsSpanTypeName(name) || IsCollectionTypeName(name) {
            return genericType.TypeArguments[0]
        }

        return null
    }

    static func IsDictionaryTypeName(name: string): bool {
        return name == "Dictionary"
            || name == "IDictionary"
            || name == "IReadOnlyDictionary"
            || name == "SortedDictionary"
            || name == "SortedList"
    }

    static func IsSpanTypeName(name: string): bool {
        return name == "Span" || name == "ReadOnlySpan"
    }

    static func IsCollectionTypeName(name: string): bool {
        return name == "List"
            || name == "HashSet"
            || name == "IList"
            || name == "ICollection"
            || name == "IEnumerable"
            || name == "IQueryable"
            || name == "ISet"
            || name == "Queue"
            || name == "Stack"
            || name == "LinkedList"
            || name == "Collection"
            || name == "ObservableCollection"
            || name == "SortedSet"
            || name == "IReadOnlyList"
            || name == "IReadOnlyCollection"
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
