namespace NSharpLang.Compiler

import System

public class ErrorSuggestions {
    public static func GetSuggestion(
        code: ErrorCode,
        context: string? = null,
        additionalInfo: string? = null): string? {
        if code == ErrorCode.TypeNotFound {
            if context != null {
                if IsPossibleTypo(context) {
                    return "Did you mean '" + FindSimilarType(context) + "'?"
                }
            }

            return "Check that the type is defined and imported correctly"
        }

        if code == ErrorCode.MissingReturn {
            return "Add a return statement or change return type to void"
        }

        if code == ErrorCode.DefiniteAssignmentError {
            return "Initialize property in constructor or provide default value"
        }

        if code == ErrorCode.ShadowedDeclaration {
            if context != null {
                return "Rename this declaration (the outer '" + context + "' is still in scope), or remove it and reuse the existing '" + context + "'"
            }

            return "Rename this declaration, or remove it and reuse the variable from the enclosing scope"
        }

        if code == ErrorCode.UnverifiedErrorResult {
            return "Check the paired error first, or return/throw from the error branch before using the result"
        }

        if code == ErrorCode.DiscardedMustUseResult {
            return "Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`"
        }

        if code == ErrorCode.UndefinedVariable {
            if context != null {
                return "Variable '" + context + "' is not defined in current scope"
            }
        }

        if code == ErrorCode.UndefinedFunction {
            if context != null {
                return "Function '" + context + "' is not defined in current scope"
            }
        }

        if code == ErrorCode.TypeMismatch {
            return "Ensure types are compatible or add explicit cast"
        }

        if code == ErrorCode.CannotInferType {
            return "Add explicit type annotation: 'let x: Type = ...'"
        }

        if code == ErrorCode.NonExhaustiveMatch {
            if additionalInfo != null {
                return "Add missing cases: " + additionalInfo + ", or use wildcard '_' to match all remaining"
            }

            return "Ensure all cases are covered or add wildcard pattern '_'"
        }

        if code == ErrorCode.GuardNotBoolean {
            return "Guard expression must be boolean type"
        }

        if code == ErrorCode.WrongArgumentCount {
            return "Check the function signature for required parameters"
        }

        if code == ErrorCode.MethodGroupUsedAsValue {
            return "Call the method with parentheses, or pass it to a parameter with a delegate type"
        }

        if code == ErrorCode.FeatureNotImplemented {
            return "This language feature is parsed for forward compatibility, but it is not available in production builds yet"
        }

        if code == ErrorCode.ReadonlyAssignment {
            return "Readonly fields can only be assigned in constructor"
        }

        if code == ErrorCode.VisibilityConventionWarning {
            return "Use PascalCase for public members or camelCase for private members"
        }

        if code == ErrorCode.ImportCollision {
            return "Use 'import ... as Alias' to resolve naming conflicts"
        }

        if code == ErrorCode.CircularImport {
            return "Reorganize imports to avoid cycles. Move shared types to a separate file that both files can import"
        }

        if code == ErrorCode.DuckInterfaceMismatch {
            if additionalInfo != null {
                return "Implement missing method: " + additionalInfo
            }
        }

        if code == ErrorCode.InvalidOperatorOverload {
            return "Operators must be public static and have correct parameter types"
        }

        if code == ErrorCode.ComparisonOperatorPair {
            return "Define both operators in the pair (== with !=, < with >, <= with >=)"
        }

        if code == ErrorCode.UnreachableStatement {
            return "Remove unreachable code or restructure control flow"
        }

        if code == ErrorCode.InvalidExpressionStatement {
            return "Use the value by assigning it, printing it, passing it to a call, or remove the expression"
        }

        return null
    }

    static func IsPossibleTypo(name: string): bool {
        lowerName := name.ToLower()
        commonTypes := CommonTypes()
        i := 0
        while i < commonTypes.Length {
            if LevenshteinDistance(lowerName, commonTypes[i].ToLower()) <= 2 {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func FindSimilarType(name: string): string {
        lowerName := name.ToLower()
        commonTypes := CommonTypes()
        bestIndex := 0
        bestDistance := LevenshteinDistance(lowerName, commonTypes[0].ToLower())

        i := 1
        while i < commonTypes.Length {
            distance := LevenshteinDistance(lowerName, commonTypes[i].ToLower())
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }

            i = i + 1
        }

        return commonTypes[bestIndex]
    }

    static func CommonTypes(): string[] {
        types := new string[](10)
        types[0] = "string"
        types[1] = "int"
        types[2] = "bool"
        types[3] = "double"
        types[4] = "float"
        types[5] = "long"
        types[6] = "decimal"
        types[7] = "object"
        types[8] = "DateTime"
        types[9] = "Guid"
        return types
    }

    public static func LevenshteinDistance(s: string, t: string): int {
        n := s.Length
        m := t.Length

        if n == 0 {
            return m
        }

        if m == 0 {
            return n
        }

        width := m + 1
        distances := new int[]((n + 1) * width)

        i := 0
        while i <= n {
            distances[i * width] = i
            i = i + 1
        }

        j := 0
        while j <= m {
            distances[j] = j
            j = j + 1
        }

        i = 1
        while i <= n {
            j = 1
            while j <= m {
                cost := 1
                if t[j - 1] == s[i - 1] {
                    cost = 0
                }

                deletion := distances[(i - 1) * width + j] + 1
                insertion := distances[i * width + j - 1] + 1
                substitution := distances[(i - 1) * width + j - 1] + cost
                distances[i * width + j] = MinInt(MinInt(deletion, insertion), substitution)

                j = j + 1
            }

            i = i + 1
        }

        return distances[n * width + m]
    }

    static func MinInt(left: int, right: int): int {
        if left < right {
            return left
        }

        return right
    }
}
