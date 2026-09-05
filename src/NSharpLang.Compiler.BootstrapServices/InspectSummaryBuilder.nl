namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

class InspectSummaryBuilder {
    static func Build(result: InspectResult): InspectSummaryResult {
        referenceSample := BuildReferenceSample(result.References.Results)

        return new InspectSummaryResult(BuildSymbol(result), BuildType(result), BuildDefinition(result), new InspectSummaryReferencesResult(result.References.Count, result.References.DefinitionCount, BuildReferenceFiles(result.References.Results), referenceSample), new InspectSummaryCompletionsResult(CompletionContextText(result.Completions.Context), result.Completions.Receiver, result.Completions.ReceiverType, CompletionTotalCount(result.Completions.Completions), BuildGroupCounts(result.Completions.Completions), BuildCompletionGroups(result.Completions.Completions)))
    }

    static func BuildSymbol(result: InspectResult): InspectSummarySymbolResult? {
        if result.Symbol == null {
            return null
        }

        symbol := (InspectSymbolResult)result.Symbol
        return new InspectSummarySymbolResult(symbol.Name, symbol.Kind)
    }

    static func BuildType(result: InspectResult): InspectSummaryTypeResult? {
        if result.Type == null {
            return null
        }

        typeResult := (TypeResult)result.Type
        return new InspectSummaryTypeResult(typeResult.Name, typeResult.ResolvedType, typeResult.Kind, typeResult.Nullability)
    }

    static func BuildDefinition(result: InspectResult): LocationResult? {
        if result.Definition != null {
            definition := (DefinitionResult)result.Definition
            return new LocationResult(definition.File, definition.Line, definition.Column)
        }

        if result.Symbol != null {
            symbol := (InspectSymbolResult)result.Symbol
            return symbol.Definition
        }

        return null
    }

    static func BuildReferenceSample(references: ReferenceResult[]): InspectReferenceSummaryResult[] {
        count := references.Length
        if count > 5 {
            count = 5
        }

        sample := new InspectReferenceSummaryResult[](count)
        i := 0
        while i < count {
            reference := references[i]
            sample[i] = new InspectReferenceSummaryResult(reference.File, reference.Line, reference.Column, reference.IsDefinition)
            i = i + 1
        }

        return sample
    }

    static func BuildReferenceFiles(references: ReferenceResult[]): string[] {
        uniqueFiles := new List<string>()
        i := 0
        while i < references.Length {
            pathText := references[i].File.Replace('\\', '/')
            if !ContainsReferenceFile(uniqueFiles, pathText) {
                uniqueFiles.Add(pathText)
            }

            i = i + 1
        }

        SortReferenceFiles(uniqueFiles)
        result := new string[](uniqueFiles.Count)
        i = 0
        while i < uniqueFiles.Count {
            result[i] = uniqueFiles[i]
            i = i + 1
        }

        return result
    }

    static func ContainsReferenceFile(files: List<string>, pathText: string): bool {
        i := 0
        while i < files.Count {
            if String.Compare(files[i], pathText, StringComparison.Ordinal) == 0 {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func SortReferenceFiles(files: List<string>) {
        i := 1
        while i < files.Count {
            current := files[i]
            j := i
            while j > 0 {
                previous := files[j - 1]
                if String.Compare(previous, current, StringComparison.Ordinal) <= 0 {
                    break
                }

                files[j] = previous
                j = j - 1
            }

            files[j] = current
            i = i + 1
        }
    }

    static func CompletionTotalCount(completions: Dictionary<string, List<CompletionItem>>): int {
        total := 0
        for entry in completions {
            total = total + entry.Value.Count
        }

        return total
    }

    static func BuildGroupCounts(completions: Dictionary<string, List<CompletionItem>>): Dictionary<string, int> {
        keys := CompletionGroupKeys(completions)
        result := new Dictionary<string, int>(StringComparer.Ordinal)
        i := 0
        while i < keys.Length {
            key := keys[i]
            result[key] = completions[key].Count
            i = i + 1
        }

        return result
    }

    static func BuildCompletionGroups(completions: Dictionary<string, List<CompletionItem>>): Dictionary<string, string[]> {
        keys := CompletionGroupKeys(completions)
        result := new Dictionary<string, string[]>(StringComparer.Ordinal)
        i := 0
        while i < keys.Length {
            key := keys[i]
            result[key] = SampleCompletionNames(completions[key])
            i = i + 1
        }

        return result
    }

    static func CompletionGroupKeys(completions: Dictionary<string, List<CompletionItem>>): string[] {
        keys := new string[](completions.Count)
        index := 0
        for entry in completions {
            keys[index] = entry.Key
            index = index + 1
        }

        Array.Sort(keys, 0, keys.Length, StringComparer.Ordinal)
        return keys
    }

    static func SampleCompletionNames(items: List<CompletionItem>): string[] {
        names := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)
        i := 0
        while i < items.Count && names.Count < 8 {
            name := items[i].Name
            if seen.Add(name) {
                names.Add(name)
            }

            i = i + 1
        }

        return names.ToArray()
    }

    static func CompletionContextText(context: CompletionContext): string {
        if context == CompletionContext.MemberAccess {
            return "memberaccess"
        }

        if context == CompletionContext.Identifier {
            return "identifier"
        }

        if context == CompletionContext.Namespace {
            return "namespace"
        }

        return "unknown"
    }
}
