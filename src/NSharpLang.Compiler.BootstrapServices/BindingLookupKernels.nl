namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler

class BindingLookupKernels {
    static func TryGetBindingCandidateColumns(column: int, span: ValueTuple<int, int>?, out candidateColumns: int[]): bool {
        spanStart := -1
        spanEnd := -1

        if span.HasValue {
            spanValue := span.Value
            spanStart = spanValue.Item1
            spanEnd = spanValue.Item2
        }

        maxDistance := CandidateColumnMaxDistance(column, spanStart, spanEnd)
        results := new List<int>()

        if maxDistance > 64 {
            AppendCompactCandidateColumns(column, spanStart, spanEnd, results)
        } else {
            distance := 0
            while distance <= maxDistance {
                left := column - distance
                if CandidateColumnInSet(left, column, spanStart, spanEnd) {
                    results.Add(left)
                }

                if distance > 0 {
                    right := column + distance
                    if CandidateColumnInSet(right, column, spanStart, spanEnd) {
                        results.Add(right)
                    }
                }

                distance = distance + 1
            }
        }

        candidateColumns = results.ToArray()
        return true
    }

    static func TryResolveBindingDeclaration(bindingMap: BindingMap, filePathValue: string, line: int, candidateColumns: int[], out declaration: SymbolDeclaration?): bool {
        declaration = null

        if candidateColumns.Length == 0 {
            return true
        }

        i := 0
        while i < candidateColumns.Length {
            candidateColumn := candidateColumns[i]
            found := FindDeclarationAt(bindingMap, filePathValue, line, candidateColumn)
            if found != null {
                declaration = found
                return true
            }

            found = FindBindingDeclarationAt(bindingMap, filePathValue, line, candidateColumn)
            if found != null {
                declaration = found
                return true
            }

            i = i + 1
        }

        return true
    }

    static func FindDeclarationAt(bindingMap: BindingMap, filePathValue: string?, line: int, column: int): SymbolDeclaration? {
        values := bindingMap.DeclarationEntries.Values
        i := 0
        while i < values.Count {
            declaration := values[i]
            if declaration.Line == line && declaration.Column == column && FilesEqualExact(declaration.File, filePathValue) {
                return declaration
            }

            i = i + 1
        }

        return null
    }

    static func FindBindingDeclarationAt(bindingMap: BindingMap, filePathValue: string?, line: int, column: int): SymbolDeclaration? {
        entries := bindingMap.BindingEntries
        enumerator := entries.GetEnumerator()
        while enumerator.MoveNext() {
            entry := enumerator.Current
            usage := entry.Key
            if usage.Line == line && usage.Col == column && FilesEqualExact(usage.File, filePathValue) {
                return entry.Value
            }
        }

        return null
    }

    static func FilesEqualExact(left: string?, right: string?): bool {
        if left == null {
            return right == null
        }

        if right == null {
            return false
        }

        return left == right
    }

    static func CandidateColumnMaxDistance(column: int, spanStart: int, spanEnd: int): int {
        maxDistance := 1

        if column > 1 {
            leftDistance := AbsInt((column - 1) - column)
            if leftDistance > maxDistance {
                maxDistance = leftDistance
            }
        }

        rightDistance := AbsInt((column + 1) - column)
        if rightDistance > maxDistance {
            maxDistance = rightDistance
        }

        if spanStart > 0 && spanEnd >= spanStart {
            startDistance := AbsInt(spanStart - column)
            if startDistance > maxDistance {
                maxDistance = startDistance
            }

            endDistance := AbsInt(spanEnd - column)
            if endDistance > maxDistance {
                maxDistance = endDistance
            }
        }

        return maxDistance
    }

    static func CandidateColumnInSet(candidate: int, column: int, spanStart: int, spanEnd: int): bool {
        if column > 0 && candidate == column {
            return true
        }

        if column > 1 && candidate == column - 1 {
            return true
        }

        if candidate == column + 1 {
            return true
        }

        return spanStart > 0 && spanEnd >= spanStart && candidate >= spanStart && candidate <= spanEnd
    }

    static func AppendCompactCandidateColumns(column: int, spanStart: int, spanEnd: int, results: List<int>) {
        if column > 0 {
            AppendDistinct(results, column)
        }

        if column > 1 {
            AppendDistinct(results, column - 1)
        }

        AppendDistinct(results, column + 1)

        if spanStart > 0 && spanEnd >= spanStart {
            candidate := spanStart
            while candidate <= spanEnd {
                AppendDistinct(results, candidate)
                candidate = candidate + 1
            }
        }

        SortCandidatesByDistance(results, column)
    }

    static func AppendDistinct(results: List<int>, candidate: int) {
        i := 0
        while i < results.Count {
            if results[i] == candidate {
                return
            }

            i = i + 1
        }

        results.Add(candidate)
    }

    static func SortCandidatesByDistance(results: List<int>, column: int) {
        i := 1
        while i < results.Count {
            value := results[i]
            distance := CandidateColumnDistance(value, column)
            j := i - 1
            while j >= 0 && CandidateColumnDistance(results[j], column) > distance {
                results[j + 1] = results[j]
                j = j - 1
            }

            results[j + 1] = value
            i = i + 1
        }
    }

    static func CandidateColumnDistance(candidate: int, column: int): int {
        if candidate >= column {
            return candidate - column
        }

        return column - candidate
    }

    static func AbsInt(value: int): int {
        if value < 0 {
            return 0 - value
        }

        return value
    }
}
