namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text

public class DocQueryKernels {
    public static func DeduplicateStableStringsOrdinalIgnoreCase(values: IReadOnlyList<string>): string[] {
        items := new List<string>()
        foreach valueObject in values {
            items.Add((string)valueObject)
        }

        valueCount := items.Count
        if valueCount == 0 {
            return new string[](0)
        }

        scratch := new StableDistinctStringScratch()
        scratch.EnsureCapacity(valueCount)
        scratch.Reset()

        i := 0
        while i < valueCount {
            value := items[i]
            rank := 0
            if scratch.RanksByValue.ContainsKey(value) {
                rank = scratch.RanksByValue[value]
            } else {
                rank = scratch.UniqueRankCount + 1
                scratch.UniqueRankCount = rank
                scratch.RanksByValue.Add(value, rank)
            }

            scratch.Ranks[i] = rank
            i = i + 1
        }

        scratch.EnsureRankCapacity(scratch.UniqueRankCount)
        resultCount := StableDistinctRankIndices(
            scratch.Ranks,
            valueCount,
            scratch.UniqueRankCount,
            scratch.SeenRanks,
            scratch.ResultIndices)

        result := new string[](resultCount)
        i = 0
        while i < resultCount {
            sourceIndex := scratch.ResultIndices[i]
            result[i] = items[sourceIndex]
            i = i + 1
        }

        scratch.Reset()
        return result
    }

    public static func DeduplicateStableTypes(values: IReadOnlyList<Type>): Type[] {
        items := new List<Type>()
        foreach valueObject in values {
            items.Add((Type)valueObject)
        }

        valueCount := items.Count
        if valueCount == 0 {
            return new Type[](0)
        }

        scratch := new StableDistinctTypeScratch()
        scratch.EnsureCapacity(valueCount)
        scratch.Reset()

        i := 0
        while i < valueCount {
            value := items[i]
            rank := 0
            if scratch.RanksByValue.ContainsKey(value) {
                rank = scratch.RanksByValue[value]
            } else {
                rank = scratch.UniqueRankCount + 1
                scratch.UniqueRankCount = rank
                scratch.RanksByValue.Add(value, rank)
            }

            scratch.Ranks[i] = rank
            i = i + 1
        }

        scratch.EnsureRankCapacity(scratch.UniqueRankCount)
        resultCount := StableDistinctRankIndices(
            scratch.Ranks,
            valueCount,
            scratch.UniqueRankCount,
            scratch.SeenRanks,
            scratch.ResultIndices)

        result := new Type[](resultCount)
        i = 0
        while i < resultCount {
            sourceIndex := scratch.ResultIndices[i]
            result[i] = items[sourceIndex]
            i = i + 1
        }

        scratch.Reset()
        return result
    }

    public static func SelectBestDocType(
        query: string,
        candidates: Type[]): Type? {
        candidateCount := candidates.Length
        if candidateCount == 0 {
            return null
        }

        scratch := new DocQueryBestTypeScratch()
        scratch.EnsureCapacity(candidateCount)
        strippedQuery := StripGenericArity(query)

        i := 0
        while i < candidateCount {
            candidate := candidates[i]
            scratch.Scores[i] = ScoreDocTypeMatch(strippedQuery, candidate)
            scratch.NamespaceLengths[i] = DocQueryNamespaceLengthForType(candidate)
            scratch.FullNames[i] = candidate.FullName ?? ""
            i = i + 1
        }

        bestIndex := DocQueryBestTypeIndex(scratch.Scores, scratch.NamespaceLengths, scratch.FullNames, candidateCount)
        scratch.ClearFullNames(candidateCount)
        return candidates[bestIndex]
    }

    static func ScoreDocTypeMatch(strippedQuery: string, candidateType: Type): int {
        qualifiedName := DocQueryLookupTypeName(candidateType)
        simpleName := StripGenericArity(candidateType.Name)
        namespaceName := candidateType.Namespace ?? ""
        isNestedValue := 0
        if candidateType.IsNested {
            isNestedValue = 1
        }

        return ScoreTypeMatch(strippedQuery, qualifiedName, simpleName, namespaceName, isNestedValue)
    }

    static func DocQueryLookupTypeName(candidateType: Type): string {
        fullName := candidateType.FullName ?? candidateType.Name
        return StripGenericArity(fullName.Replace('+', '.'))
    }

    static func StableDistinctRankIndices(
        valueRanks: int[],
        valueCount: int,
        uniqueRankCount: int,
        seenRanks: int[],
        resultIndices: int[]): int {
        resultCount := 0
        i := 0
        while i < valueCount {
            rank := valueRanks[i]
            if rank > 0 && seenRanks[rank] == 0 {
                seenRanks[rank] = 1
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            i = i + 1
        }

        rankIndex := 1
        while rankIndex <= uniqueRankCount {
            seenRanks[rankIndex] = 0
            rankIndex = rankIndex + 1
        }

        return resultCount
    }

    static func DocQueryBestTypeIndex(scores: int[], namespaceLengths: int[], fullNames: string[], count: int): int {
        bestIndex := 0
        bestScore := scores[0]
        bestNamespaceLength := namespaceLengths[0]

        i := 1
        while i < count {
            score := scores[i]
            if score > bestScore {
                bestIndex = i
                bestScore = score
                bestNamespaceLength = namespaceLengths[i]
            } else if score == bestScore {
                namespaceLength := namespaceLengths[i]
                if namespaceLength < bestNamespaceLength {
                    bestIndex = i
                    bestNamespaceLength = namespaceLength
                } else if namespaceLength == bestNamespaceLength {
                    comparison := String.Compare(fullNames[i], fullNames[bestIndex], StringComparison.OrdinalIgnoreCase)
                    if comparison < 0 {
                        bestIndex = i
                    }
                }
            }

            i = i + 1
        }

        return bestIndex
    }

    static func DocQueryMemberOrderIndices(kindRanks: int[], nameRanks: int[], resultIndices: int[], count: int): int {
        i := 0
        while i < count {
            resultIndices[i] = i
            i = i + 1
        }

        i = 1
        while i < count {
            currentIndex := resultIndices[i]
            currentKindRank := kindRanks[currentIndex]
            currentNameRank := nameRanks[currentIndex]
            j := i - 1
            keepMoving := true
            while j >= 0 && keepMoving {
                if DocQueryMemberIndexComesAfter(resultIndices[j], currentKindRank, currentNameRank, kindRanks, nameRanks) {
                    resultIndices[j + 1] = resultIndices[j]
                    j = j - 1
                } else {
                    keepMoving = false
                }
            }

            resultIndices[j + 1] = currentIndex
            i = i + 1
        }

        return count
    }

    static func DocQueryMemberIndexComesAfter(
        leftIndex: int,
        rightKindRank: int,
        rightNameRank: int,
        kindRanks: int[],
        nameRanks: int[]): bool {
        leftKindRank := kindRanks[leftIndex]
        if leftKindRank != rightKindRank {
            return leftKindRank > rightKindRank
        }

        leftNameRank := nameRanks[leftIndex]
        return leftNameRank > rightNameRank
    }

    public static func OrderDocMembers(members: IReadOnlyList<DocMemberResult>): DocMemberResult[] {
        materialized := new List<DocMemberResult>()
        foreach memberObject in members {
            member := (DocMemberResult)memberObject
            materialized.Add(member)
        }

        memberCount := materialized.Count
        if memberCount == 0 {
            return materialized.ToArray()
        }

        scratch := new DocQueryMemberOrderScratch()
        scratch.EnsureCapacity(memberCount)
        scratch.ResetNames()

        i := 0
        while i < memberCount {
            scratch.AddName(materialized[i].Name)
            i = i + 1
        }

        scratch.BuildSortedNameRanks()

        i = 0
        while i < memberCount {
            member := materialized[i]
            kindRank := GetDocMemberKindRank(member.Kind)
            if kindRank == 0 {
                throw new InvalidOperationException("N# doc query member ordering kernel rejected a member kind.")
            }

            scratch.KindRanks[i] = kindRank
            scratch.NameRanks[i] = scratch.GetNameRank(member.Name)
            i = i + 1
        }

        orderedCount := DocQueryMemberOrderIndices(scratch.KindRanks, scratch.NameRanks, scratch.ResultIndices, memberCount)

        result := new List<DocMemberResult>()
        i = 0
        while i < orderedCount {
            sourceIndex := scratch.ResultIndices[i]
            result.Add(materialized[sourceIndex])
            i = i + 1
        }

        scratch.ResetNames()
        return result.ToArray()
    }

    public static func StripGenericArity(name: string): string {
        if name.IndexOf('`') < 0 {
            return name
        }

        builder := new StringBuilder(name.Length)
        i := 0
        while i < name.Length {
            if name[i] == '`' {
                i = i + 1
                while i < name.Length && DocQueryIsDigit(name[i]) {
                    i = i + 1
                }

                continue
            }

            builder.Append(name[i])
            i = i + 1
        }

        return builder.ToString()
    }

    public static func GetReflectionLookupTypeName(reflectionType: Type): string {
        fullName := reflectionType.FullName
        if fullName == null {
            fullName = reflectionType.Name
        } else {
            fullName = fullName.Replace('+', '.')
        }

        return StripGenericArity(fullName)
    }

    public static func ScoreTypeMatch(
        strippedQuery: string,
        qualifiedName: string,
        simpleName: string,
        namespaceName: string,
        isNested: int): int {
        score := 0

        if DocQueryEqualsIgnoreCase(qualifiedName, strippedQuery) {
            score = score + 1000
        }

        if DocQueryEndsWithSegmentIgnoreCase(qualifiedName, strippedQuery) {
            score = score + 400
        }

        lastSegmentStart := DocQueryLastSegmentStart(strippedQuery)
        if DocQueryEqualsSubstringIgnoreCase(simpleName, 0, simpleName.Length, strippedQuery, lastSegmentStart, strippedQuery.Length - lastSegmentStart) {
            score = score + 250
        }

        queryNamespaceLength := DocQueryQueryNamespaceLength(strippedQuery)
        if queryNamespaceLength > 0 && DocQueryEndsWithSubstringIgnoreCase(namespaceName, strippedQuery, 0, queryNamespaceLength) {
            score = score + 300
        }

        score = score + DocQueryNamespacePriority(namespaceName)

        if isNested == 0 {
            score = score + 10
        }

        return score
    }

    static func GetDocMemberKindRank(kind: string): int {
        if kind == "constructor" {
            return 1
        }

        if kind == "event" {
            return 2
        }

        if kind == "field" {
            return 3
        }

        if kind == "method" {
            return 4
        }

        if kind == "nested type" {
            return 5
        }

        if kind == "property" {
            return 6
        }

        return 0
    }

    static func DocQueryNamespaceLengthForType(candidateType: Type): int {
        namespaceName := candidateType.Namespace
        if namespaceName == null {
            return Int32.MaxValue
        }

        return namespaceName.Length
    }

    static func DocQueryNamespacePriority(ns: string): int {
        if ns.Length == 0 {
            return 0
        }

        if DocQueryEqualsIgnoreCase(ns, "System") {
            return 200
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Collections") {
            return 199
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Collections.Generic") {
            return 198
        }

        if DocQueryEqualsIgnoreCase(ns, "System.IO") {
            return 197
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Linq") {
            return 196
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Net") {
            return 195
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Net.Http") {
            return 194
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Text") {
            return 193
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Text.Json") {
            return 192
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Text.RegularExpressions") {
            return 191
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Threading") {
            return 190
        }

        if DocQueryEqualsIgnoreCase(ns, "System.Threading.Tasks") {
            return 189
        }

        if DocQueryStartsWithIgnoreCase(ns, "System.") {
            return 120
        }

        if DocQueryEqualsIgnoreCase(ns, "Microsoft") || DocQueryStartsWithIgnoreCase(ns, "Microsoft.") {
            return 60
        }

        return 10
    }

    static func DocQueryLastSegmentStart(text: string): int {
        i := text.Length - 1
        while i >= 0 {
            if text[i] == '.' {
                return i + 1
            }

            i = i - 1
        }

        return 0
    }

    static func DocQueryQueryNamespaceLength(text: string): int {
        i := text.Length - 1
        while i >= 0 {
            if text[i] == '.' {
                return i
            }

            i = i - 1
        }

        return 0
    }

    static func DocQueryEqualsIgnoreCase(left: string, right: string): bool {
        return left.Length == right.Length && String.Compare(left, right, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func DocQueryStartsWithIgnoreCase(text: string, prefix: string): bool {
        if prefix.Length > text.Length {
            return false
        }

        return String.Compare(text, 0, prefix, 0, prefix.Length, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func DocQueryEndsWithSegmentIgnoreCase(text: string, suffix: string): bool {
        if suffix.Length >= text.Length {
            return false
        }

        start := text.Length - suffix.Length
        if text[start - 1] != '.' {
            return false
        }

        return String.Compare(text, start, suffix, 0, suffix.Length, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func DocQueryEndsWithSubstringIgnoreCase(text: string, query: string, queryStart: int, queryLength: int): bool {
        if queryLength <= 0 || queryLength > text.Length {
            return false
        }

        textStart := text.Length - queryLength
        return String.Compare(text, textStart, query, queryStart, queryLength, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func DocQueryEqualsSubstringIgnoreCase(
        left: string,
        leftStart: int,
        leftLength: int,
        right: string,
        rightStart: int,
        rightLength: int): bool {
        if leftLength != rightLength {
            return false
        }

        return String.Compare(left, leftStart, right, rightStart, leftLength, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func DocQueryIsDigit(ch: char): bool {
        return ch >= '0' && ch <= '9'
    }
}
