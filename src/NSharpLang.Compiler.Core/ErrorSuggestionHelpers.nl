namespace NSharpLang.Compiler

import System
import System.Collections.Generic

class SmartSuggester {
    candidatesValue: List<string>

    constructor(candidates: List<string>) {
        candidatesValue = candidates
    }

    func SuggestSimilarNames(typo: string, maxSuggestions: int = 3): List<string> {
        result := new List<string>()
        if maxSuggestions <= 0 {
            return result
        }

        names := new List<string>()
        scores := new List<double>()

        i := 0
        while i < candidatesValue.Count {
            candidate := candidatesValue[i]
            score := ScoreSimilarity(typo, candidate)
            if score > 0.5 {
                InsertSuggestion(names, scores, candidate, score)
            }

            i = i + 1
        }

        limit := maxSuggestions
        if limit > names.Count {
            limit = names.Count
        }

        i = 0
        while i < limit {
            result.Add(names[i])
            i = i + 1
        }

        return result
    }

    static func InsertSuggestion(names: List<string>, scores: List<double>, name: string, score: double) {
        names.Add(name)
        scores.Add(score)

        index := names.Count - 1
        while index > 0 {
            previousScore := scores[index - 1]
            if previousScore >= score {
                break
            }

            names[index] = names[index - 1]
            scores[index] = previousScore
            index = index - 1
        }

        names[index] = name
        scores[index] = score
    }

    static func ScoreSimilarity(a: string, b: string): double {
        maxLen := MaxInt(a.Length, b.Length)
        minLen := MinInt(a.Length, b.Length)
        if maxLen == 0 || minLen == 0 {
            return 0.0
        }

        // Invariant, and for the reason the very next member already knew: `CommonPrefixLength`
        // below folds with `Char.ToLowerInvariant`, so a culture-sensitive fold here made the two
        // halves of ONE score disagree about what case-insensitive means.
        distance := ErrorSuggestions.LevenshteinDistance(a.ToLowerInvariant(), b.ToLowerInvariant())
        distanceScore := 1.0 - ((double)distance / (double)maxLen)
        prefixScore := (double)CommonPrefixLength(a, b) / (double)minLen

        return (distanceScore * 0.7) + (prefixScore * 0.3)
    }

    static func CommonPrefixLength(a: string, b: string): int {
        count := 0
        minLen := MinInt(a.Length, b.Length)
        i := 0
        while i < minLen {
            if Char.ToLowerInvariant(a[i]) == Char.ToLowerInvariant(b[i]) {
                count = count + 1
            } else {
                break
            }

            i = i + 1
        }

        return count
    }

    static func MaxInt(left: int, right: int): int {
        if left > right {
            return left
        }

        return right
    }

    static func MinInt(left: int, right: int): int {
        if left < right {
            return left
        }

        return right
    }
}

class TypeConversionSuggester {
    static func SuggestConversion(fromType: string, toType: string): string? {
        if fromType == "string" && toType == "int" {
            return "Strings and integers are different types. To convert a string to an int,\n" + "you can use int.Parse(yourString) or int.TryParse(yourString, out result)."
        }

        if fromType == "int" && toType == "string" {
            return "You can convert an integer to a string using .ToString() or string\n" + "interpolation: " + InterpolatedStringExample("yourNumber")
        }

        if fromType == "int" && toType == "double" {
            return "Implicit conversion from int to double works automatically."
        }

        if fromType == "double" && toType == "int" {
            return "Cannot implicitly convert 'double' to 'int'. Use an explicit cast: (int)value\n" + "Warning: This truncates decimals (e.g. 3.7 becomes 3) and may lose data if the value exceeds the target type's range."
        }

        if fromType == "string" && toType == "double" {
            return "Use double.Parse(yourString) or double.TryParse(yourString, out result)."
        }

        if fromType == "double" && toType == "string" {
            return "Use value.ToString() or " + InterpolatedStringExample("value")
        }

        if fromType == "int" && toType == "long" {
            return "Implicit conversion from int to long works automatically."
        }

        if fromType == "long" && toType == "int" {
            return "Cannot implicitly convert 'long' to 'int'. Use an explicit cast: (int)value\n" + "Warning: This conversion may lose data if the value exceeds the target type's range."
        }

        if toType == fromType + "?" {
            return "This conversion is implicit. Non-nullable values can be assigned to nullable types."
        }

        if fromType == toType + "?" {
            return "You're trying to use a nullable value where a non-nullable is expected.\n" + "You need to handle the null case, perhaps with 'if (x != null)' or the\n" + "null-coalescing operator 'x ?? defaultValue'."
        }

        if fromType.EndsWith("[]") && toType.StartsWith("List<") {
            return "Use .ToList() to convert an array to a List, or use 'new List<T>(array)'."
        }

        if fromType.StartsWith("List<") && toType.EndsWith("[]") {
            return "Use .ToArray() to convert a List to an array."
        }

        if IsNumericType(fromType) && IsNumericType(toType) {
            return "Cannot implicitly convert '" + fromType + "' to '" + toType + "'. Use an explicit cast: (" + toType + ")value\n" + "Warning: This conversion may lose data if the value exceeds the target type's range."
        }

        return null
    }

    static func InterpolatedStringExample(name: string): string {
        quote := ((char)34).ToString()
        return "$" + quote + "{" + name + "}" + quote
    }

    static func IsNumericType(typeName: string): bool {
        if typeName == "int" {
            return true
        }

        if typeName == "long" {
            return true
        }

        if typeName == "short" {
            return true
        }

        if typeName == "byte" {
            return true
        }

        if typeName == "sbyte" {
            return true
        }

        if typeName == "ushort" {
            return true
        }

        if typeName == "uint" {
            return true
        }

        if typeName == "ulong" {
            return true
        }

        if typeName == "float" {
            return true
        }

        if typeName == "double" {
            return true
        }

        if typeName == "decimal" {
            return true
        }

        if typeName == "char" {
            return true
        }

        return false
    }
}
