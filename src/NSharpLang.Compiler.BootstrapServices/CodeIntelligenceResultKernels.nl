namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class CodeIntelligenceResultKernels {
    public static func SuppressLintShadowingDiagnostics(
        diagnostics: IReadOnlyList<DiagnosticResult>,
        shadowedFiles: IReadOnlyList<string>): ValueTuple<int[], int> {
        shadowed := new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        foreach fileValue in shadowedFiles {
            shadowedFile := (string)fileValue
            if !shadowed.ContainsKey(shadowedFile) {
                shadowed.Add(shadowedFile, 1)
            }
        }

        result := new List<int>()
        index := 0
        foreach diagnosticValue in diagnostics {
            diagnostic := (DiagnosticResult)diagnosticValue
            suppress := false
            if diagnostic.Code == "NL020" {
                suppress = shadowed.ContainsKey(diagnostic.File)
            }
            if !suppress {
                result.Add(index)
            }

            index = index + 1
        }

        values := result.ToArray()
        return new ValueTuple<int[], int>(values, values.Length)
    }

    public static func DeduplicateDiagnostics(
        diagnostics: IReadOnlyList<DiagnosticResult>): ValueTuple<int[], int> {
        items := DiagnosticList(diagnostics)
        result := UniqueDiagnosticIndices(items)
        values := result.ToArray()
        SortDiagnosticIndices(values, values.Length, items)
        return new ValueTuple<int[], int>(values, values.Length)
    }

    public static func DeduplicateDiagnosticsPreservingOrder(
        diagnostics: IReadOnlyList<DiagnosticResult>): ValueTuple<int[], int> {
        items := DiagnosticList(diagnostics)
        result := UniqueDiagnosticIndices(items)
        values := result.ToArray()
        return new ValueTuple<int[], int>(values, values.Length)
    }

    public static func DeduplicateReferences(
        references: IReadOnlyList<ReferenceResult>): ValueTuple<int[], int> {
        items := ReferenceList(references)
        result := UniqueReferenceIndices(items)
        values := result.ToArray()
        SortReferenceIndices(values, values.Length, items)
        return new ValueTuple<int[], int>(values, values.Length)
    }

    public static func MatchesFilePath(fullPath: string, queryPath: string): bool {
        if PathEqualsNormalizedIgnoreCase(fullPath, queryPath) {
            return true
        }

        if !PathEndsWithNormalizedIgnoreCase(fullPath, queryPath) {
            return false
        }

        charBeforeIndex := fullPath.Length - queryPath.Length - 1
        if charBeforeIndex < 0 {
            return false
        }

        return NormalizeSlash(fullPath[charBeforeIndex]) == '/'
    }

    static func DiagnosticList(diagnostics: IReadOnlyList<DiagnosticResult>): List<DiagnosticResult> {
        items := new List<DiagnosticResult>()
        foreach diagnosticValue in diagnostics {
            items.Add((DiagnosticResult)diagnosticValue)
        }

        return items
    }

    static func ReferenceList(references: IReadOnlyList<ReferenceResult>): List<ReferenceResult> {
        items := new List<ReferenceResult>()
        foreach referenceValue in references {
            items.Add((ReferenceResult)referenceValue)
        }

        return items
    }

    static func UniqueDiagnosticIndices(items: List<DiagnosticResult>): List<int> {
        seen := new Dictionary<string, int>(StringComparer.Ordinal)
        result := new List<int>()
        index := 0
        while index < items.Count {
            key := DiagnosticKey(items[index])
            if !seen.ContainsKey(key) {
                seen.Add(key, 1)
                result.Add(index)
            }

            index = index + 1
        }

        return result
    }

    static func UniqueReferenceIndices(items: List<ReferenceResult>): List<int> {
        seen := new Dictionary<string, int>(StringComparer.Ordinal)
        result := new List<int>()
        index := 0
        while index < items.Count {
            key := ReferenceKey(items[index])
            if !seen.ContainsKey(key) {
                seen.Add(key, 1)
                result.Add(index)
            }

            index = index + 1
        }

        return result
    }

    static func DiagnosticKey(diagnostic: DiagnosticResult): string {
        return KeyPart(diagnostic.Code)
            + "|" + KeyPart(diagnostic.File)
            + "|" + diagnostic.Line.ToString()
            + "|" + diagnostic.Column.ToString()
            + "|" + KeyPart(diagnostic.Message)
    }

    static func ReferenceKey(reference: ReferenceResult): string {
        return KeyPart(reference.File)
            + "|" + reference.Line.ToString()
            + "|" + reference.Column.ToString()
    }

    static func KeyPart(value: string): string {
        return value.Length.ToString() + ":" + value
    }

    static func SortDiagnosticIndices(indices: int[], count: int, diagnostics: List<DiagnosticResult>) {
        i := 1
        while i < count {
            current := indices[i]
            j := i - 1
            keepMoving := true
            while j >= 0 && keepMoving {
                if DiagnosticIndexComesAfter(diagnostics, indices[j], current) {
                    indices[j + 1] = indices[j]
                    j = j - 1
                } else {
                    keepMoving = false
                }
            }

            indices[j + 1] = current
            i = i + 1
        }
    }

    static func SortReferenceIndices(indices: int[], count: int, references: List<ReferenceResult>) {
        i := 1
        while i < count {
            current := indices[i]
            j := i - 1
            keepMoving := true
            while j >= 0 && keepMoving {
                if ReferenceIndexComesAfter(references, indices[j], current) {
                    indices[j + 1] = indices[j]
                    j = j - 1
                } else {
                    keepMoving = false
                }
            }

            indices[j + 1] = current
            i = i + 1
        }
    }

    static func DiagnosticIndexComesAfter(diagnostics: List<DiagnosticResult>, leftIndex: int, rightIndex: int): bool {
        left := diagnostics[leftIndex]
        right := diagnostics[rightIndex]
        fileCompare := String.Compare(left.File, right.File, StringComparison.Ordinal)
        if fileCompare != 0 {
            return fileCompare > 0
        }

        if left.Line != right.Line {
            return left.Line > right.Line
        }

        if left.Column != right.Column {
            return left.Column > right.Column
        }

        return leftIndex > rightIndex
    }

    static func ReferenceIndexComesAfter(references: List<ReferenceResult>, leftIndex: int, rightIndex: int): bool {
        left := references[leftIndex]
        right := references[rightIndex]
        fileCompare := String.Compare(left.File, right.File, StringComparison.Ordinal)
        if fileCompare != 0 {
            return fileCompare > 0
        }

        if left.Line != right.Line {
            return left.Line > right.Line
        }

        if left.Column != right.Column {
            return left.Column > right.Column
        }

        return leftIndex > rightIndex
    }

    static func PathEqualsNormalizedIgnoreCase(fullPath: string, queryPath: string): bool {
        if fullPath.Length != queryPath.Length {
            return false
        }

        i := 0
        while i < fullPath.Length {
            if !PathCharsEqualIgnoreCase(fullPath[i], queryPath[i]) {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func PathEndsWithNormalizedIgnoreCase(fullPath: string, queryPath: string): bool {
        if queryPath.Length > fullPath.Length {
            return false
        }

        fullStart := fullPath.Length - queryPath.Length
        i := 0
        while i < queryPath.Length {
            if !PathCharsEqualIgnoreCase(fullPath[fullStart + i], queryPath[i]) {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func PathCharsEqualIgnoreCase(left: char, right: char): bool {
        left = NormalizeSlash(left)
        right = NormalizeSlash(right)

        if left == right {
            return true
        }

        return Char.ToUpperInvariant(left) == Char.ToUpperInvariant(right)
    }

    static func NormalizeSlash(ch: char): char {
        if ch == '\\' {
            return '/'
        }

        return ch
    }
}
