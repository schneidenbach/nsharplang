namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
import System.Text

class DocQueryLookupSplitPlan {
    typeCandidateValue: string
    remainderPartsValue: string[]
    containingTypePartsValue: string[]
    firstRemainderValue: string
    lastRemainderValue: string

    TypeCandidate: string => typeCandidateValue
    RemainderParts: string[] => remainderPartsValue
    ContainingTypeParts: string[] => containingTypePartsValue
    FirstRemainder: string => firstRemainderValue
    LastRemainder: string => lastRemainderValue
    HasContainingType: bool => containingTypePartsValue.Length > 0

    constructor(typeCandidate: string, remainderParts: string[], containingTypeParts: string[], firstRemainder: string, lastRemainder: string) {
        typeCandidateValue = typeCandidate
        remainderPartsValue = remainderParts
        containingTypePartsValue = containingTypeParts
        firstRemainderValue = firstRemainder
        lastRemainderValue = lastRemainder
    }
}

class DocQueryKernels {
    static func DeduplicateStableStringsOrdinalIgnoreCase(values: IReadOnlyList<string>): string[] {
        items := new List<string>()
        for valueObject in values {
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
        resultCount := StableDistinctRankIndices(scratch.Ranks, valueCount, scratch.UniqueRankCount, scratch.SeenRanks, scratch.ResultIndices)

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

    static func DeduplicateStableTypes(values: IReadOnlyList<Type>): Type[] {
        items := new List<Type>()
        for valueObject in values {
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
        resultCount := StableDistinctRankIndices(scratch.Ranks, valueCount, scratch.UniqueRankCount, scratch.SeenRanks, scratch.ResultIndices)

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

    static func SelectBestDocType(query: string, candidates: Type[]): Type? {
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

    static func StableDistinctRankIndices(valueRanks: int[], valueCount: int, uniqueRankCount: int, seenRanks: int[], resultIndices: int[]): int {
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

    static func DocQueryMemberIndexComesAfter(leftIndex: int, rightKindRank: int, rightNameRank: int, kindRanks: int[], nameRanks: int[]): bool {
        leftKindRank := kindRanks[leftIndex]
        if leftKindRank != rightKindRank {
            return leftKindRank > rightKindRank
        }

        leftNameRank := nameRanks[leftIndex]
        return leftNameRank > rightNameRank
    }

    static func OrderDocMembers(members: IReadOnlyList<DocMemberResult>): DocMemberResult[] {
        materialized := new List<DocMemberResult>()
        for memberObject in members {
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

    static func StripGenericArity(name: string): string {
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

    static func GetReflectionLookupTypeName(reflectionType: Type): string {
        fullName := reflectionType.FullName
        if fullName == null {
            fullName = reflectionType.Name
        } else {
            fullName = fullName.Replace('+', '.')
        }

        return StripGenericArity(fullName)
    }

    static func GetReflectionTypeDocId(reflectionType: Type): string {
        fullName := reflectionType.FullName
        if fullName == null {
            return "T:"
        }

        return "T:" + fullName.Replace('+', '.')
    }

    static func ShouldSearchQualifiedSuffix(strippedName: string): bool {
        return strippedName.IndexOf('.') >= 0
    }

    static func GetResolveTypeShortName(strippedName: string): string {
        return StripGenericArity(GetLastDocQuerySegment(strippedName))
    }

    static func IsQualifiedTypeSuffixMatch(qualifiedName: string, strippedName: string): bool {
        suffix := "." + strippedName
        return DocQueryEndsWithSubstringIgnoreCase(qualifiedName, suffix, 0, suffix.Length)
    }

    static func GetDocMemberDocId(prefix: string, declaringTypeFullName: string?, memberName: string): string {
        ownerName := declaringTypeFullName ?? ""
        return prefix + ownerName.Replace('+', '.') + "." + memberName
    }

    static func GetMethodDocMemberName(methodName: string, isConstructor: bool): string {
        if isConstructor {
            return "#ctor"
        }

        return methodName
    }

    static func GetMethodDocId(declaringTypeFullName: string?, memberName: string, parameterTypeDocIds: string[]): string {
        ownerName := declaringTypeFullName ?? ""
        builder := new StringBuilder()
        builder.Append("M:")
        builder.Append(ownerName.Replace('+', '.'))
        builder.Append(".")
        builder.Append(memberName)

        if parameterTypeDocIds.Length > 0 {
            builder.Append("(")
            i := 0
            while i < parameterTypeDocIds.Length {
                if i > 0 {
                    builder.Append(",")
                }

                builder.Append(parameterTypeDocIds[i])
                i = i + 1
            }

            builder.Append(")")
        }

        return builder.ToString()
    }

    static func FormatBuiltinTypeName(fullName: string?): string? {
        if fullName == "System.Void" {
            return "void"
        }

        if fullName == "System.Int32" {
            return "int"
        }

        if fullName == "System.Int64" {
            return "long"
        }

        if fullName == "System.Single" {
            return "float"
        }

        if fullName == "System.Double" {
            return "double"
        }

        if fullName == "System.Boolean" {
            return "bool"
        }

        if fullName == "System.String" {
            return "string"
        }

        if fullName == "System.Char" {
            return "char"
        }

        if fullName == "System.Byte" {
            return "byte"
        }

        if fullName == "System.Object" {
            return "object"
        }

        return null
    }

    static func FormatGenericTypeName(rawName: string, formattedArgs: string[]): string {
        return StripGenericArity(rawName) + "<" + string.Join(", ", formattedArgs) + ">"
    }

    static func FormatArrayTypeName(elementTypeName: string): string {
        return elementTypeName + "[]"
    }

    static func GetMethodSignatureName(methodName: string, declaringTypeName: string?, isConstructor: bool): string {
        if isConstructor && declaringTypeName != null {
            return StripGenericArity(declaringTypeName)
        }

        return methodName
    }

    static func FormatMethodSignature(methodName: string, parameterNames: string[], parameterTypeNames: string[]): string {
        builder := new StringBuilder()
        builder.Append(methodName)
        builder.Append("(")
        i := 0
        while i < parameterTypeNames.Length {
            if i > 0 {
                builder.Append(", ")
            }

            builder.Append(parameterTypeNames[i])
            builder.Append(" ")
            builder.Append(parameterNames[i])
            i = i + 1
        }

        builder.Append(")")
        return builder.ToString()
    }

    static func FormatParameterList(parameterNames: string[], parameterTypeNames: string[]): string {
        builder := new StringBuilder()
        builder.Append("(")
        i := 0
        while i < parameterTypeNames.Length {
            if i > 0 {
                builder.Append(", ")
            }

            builder.Append(parameterNames[i])
            builder.Append(": ")
            builder.Append(parameterTypeNames[i])
            i = i + 1
        }

        builder.Append(")")
        return builder.ToString()
    }

    static func FormatNestedQualifiedTypeName(declaringTypeName: string, nestedTypeName: string): string {
        return declaringTypeName + "." + nestedTypeName
    }

    static func FormatQualifiedTypeName(namespaceName: string?, typeName: string): string {
        if string.IsNullOrWhiteSpace(namespaceName) {
            return typeName
        }

        return (namespaceName ?? "") + "." + typeName
    }

    static func FormatByRefTypeDocId(elementTypeDocId: string): string {
        return elementTypeDocId + "@"
    }

    static func FormatPointerTypeDocId(elementTypeDocId: string): string {
        return elementTypeDocId + "*"
    }

    static func FormatArrayTypeDocId(elementTypeDocId: string, rank: int): string {
        if rank == 1 {
            return elementTypeDocId + "[]"
        }

        builder := new StringBuilder()
        builder.Append(elementTypeDocId)
        builder.Append("[")
        i := 0
        while i < rank {
            if i > 0 {
                builder.Append(",")
            }

            builder.Append("0:")
            i = i + 1
        }

        builder.Append("]")
        return builder.ToString()
    }

    static func FormatGenericParameterDocId(isMethodGenericParameter: bool, position: int): string {
        if isMethodGenericParameter {
            return "``" + position.ToString()
        }

        return "`" + position.ToString()
    }

    static func FormatGenericTypeDocId(genericTypeFullName: string?, parameterTypeDocIds: string[]): string {
        ownerName := genericTypeFullName ?? ""
        return ownerName.Replace('+', '.') + "{" + string.Join(",", parameterTypeDocIds) + "}"
    }

    static func FormatNamedTypeDocId(fullName: string?, fallbackName: string): string {
        if fullName == null {
            return fallbackName
        }

        return fullName.Replace('+', '.')
    }

    static func GetReflectionTypeKind(isEnum: bool, isInterface: bool, isValueType: bool, isAbstract: bool, isSealed: bool): string {
        if isEnum {
            return "enum"
        }

        if isInterface {
            return "interface"
        }

        if isValueType {
            return "struct"
        }

        if isAbstract && isSealed {
            return "static class"
        }

        if isAbstract {
            return "abstract class"
        }

        return "class"
    }

    static func FormatBaseTypeList(baseTypeFullName: string?, baseTypeDisplayName: string?, interfaceDisplayNames: string[]): string[] {
        result := new List<string>()
        if baseTypeFullName != null && baseTypeDisplayName != null && ShouldIncludeBaseType(baseTypeFullName) {
            result.Add(baseTypeDisplayName)
        }

        i := 0
        while i < interfaceDisplayNames.Length {
            result.Add(interfaceDisplayNames[i])
            i = i + 1
        }

        return result.ToArray()
    }

    static func IsDocMemberNameMatch(candidateName: string, requestedName: string): bool {
        return DocQueryEqualsIgnoreCase(StripGenericArity(candidateName), requestedName)
    }

    static func IsConstructorMemberMatch(requestedName: string, containingTypeName: string): bool {
        if DocQueryEqualsIgnoreCase(requestedName, "#ctor") {
            return true
        }

        if DocQueryEqualsIgnoreCase(requestedName, "ctor") {
            return true
        }

        return DocQueryEqualsIgnoreCase(StripGenericArity(containingTypeName), requestedName)
    }

    static func IsMethodMemberMatch(methodName: string, requestedName: string, isSpecialName: bool): bool {
        return !isSpecialName && DocQueryEqualsIgnoreCase(methodName, requestedName)
    }

    static func GetOverloadKindText(kind: string, overloadCount: int): string {
        if overloadCount == 1 {
            return kind
        }

        return kind + " (" + overloadCount.ToString() + " overloads)"
    }

    static func FormatMemberFullName(containingTypeName: string, memberName: string): string {
        return containingTypeName + "." + memberName
    }

    static func ShouldIncludePublicType(isPublic: bool, isNestedPublic: bool): bool {
        return isPublic || isNestedPublic
    }

    static func GetQualifiedTypeIndexName(fullName: string?): string? {
        if string.IsNullOrWhiteSpace(fullName) {
            return null
        }

        return (fullName ?? "").Replace('+', '.')
    }

    static func ShouldIncludeBaseType(fullName: string): bool {
        return fullName != "System.Object" && fullName != "System.ValueType"
    }

    static func SortPathsByFileNameDescending(paths: string[]): string[] {
        sorted := new string[](paths.Length)
        i := 0
        while i < paths.Length {
            sorted[i] = paths[i]
            i = i + 1
        }

        i = 1
        while i < sorted.Length {
            current := sorted[i]
            currentName := Path.GetFileName(current) ?? current
            j := i - 1
            while j >= 0 && String.Compare(Path.GetFileName(sorted[j]) ?? sorted[j], currentName, StringComparison.CurrentCulture) < 0 {
                sorted[j + 1] = sorted[j]
                j = j - 1
            }

            sorted[j + 1] = current
            i = i + 1
        }

        return sorted
    }

    static func GetXmlDocPath(assemblyLocation: string?, assemblyNameFromMetadata: string?, referencePackDirectories: string[]): string {
        location := assemblyLocation ?? ""
        assemblyName := assemblyNameFromMetadata ?? ""
        if string.IsNullOrWhiteSpace(assemblyName) {
            assemblyName = GetPathFileNameWithoutExtension(location)
        }

        if !string.IsNullOrWhiteSpace(location) {
            adjacentXml := ChangePathExtensionToXml(location)
            if File.Exists(adjacentXml) {
                return adjacentXml
            }

            assemblyDir := Path.GetDirectoryName(location)
            if !string.IsNullOrWhiteSpace(assemblyDir) {
                refXml := Path.Combine(Path.Combine(assemblyDir ?? "", "ref"), assemblyName + ".xml")
                if File.Exists(refXml) {
                    return refXml
                }
            }
        }

        i := 0
        while i < referencePackDirectories.Length {
            candidate := Path.Combine(referencePackDirectories[i], assemblyName + ".xml")
            if File.Exists(candidate) {
                return candidate
            }

            i = i + 1
        }

        return ""
    }

    static func DiscoverReferencePackAssemblyNames(referencePackDirectories: string[]): string[] {
        names := new List<string>()
        i := 0
        while i < referencePackDirectories.Length {
            dllFiles := Directory.GetFiles(referencePackDirectories[i], "*.dll", SearchOption.TopDirectoryOnly)
            fileIndex := 0
            while fileIndex < dllFiles.Length {
                name := GetPathFileNameWithoutExtension(dllFiles[fileIndex])
                if !string.IsNullOrWhiteSpace(name) {
                    names.Add(name)
                }

                fileIndex = fileIndex + 1
            }

            i = i + 1
        }

        return DeduplicateStableStringsOrdinalIgnoreCase(names)
    }

    static func GetReferencePackDirectories(assemblyLocations: string[], dotnetRoot: string?): string[] {
        roots := new List<string>()
        seenRoots := new HashSet<string>(StringComparer.OrdinalIgnoreCase)

        i := 0
        stopAfterFirstAssemblyLocation := false
        while i < assemblyLocations.Length && !stopAfterFirstAssemblyLocation {
            location := assemblyLocations[i]
            if !string.IsNullOrWhiteSpace(location) {
                candidate := FindDotNetRootCandidate(location)
                if candidate != null {
                    AddUniqueString(roots, seenRoots, candidate)
                }

                stopAfterFirstAssemblyLocation = true
            }

            i = i + 1
        }

        if !string.IsNullOrWhiteSpace(dotnetRoot) {
            AddUniqueString(roots, seenRoots, dotnetRoot ?? "")
        }

        directories := new List<string>()
        rootIndex := 0
        while rootIndex < roots.Count {
            packsDir := Path.Combine(roots[rootIndex], "packs")
            if Directory.Exists(packsDir) {
                packDirs := Directory.GetDirectories(packsDir, "*.Ref", SearchOption.TopDirectoryOnly)
                packIndex := 0
                while packIndex < packDirs.Length {
                    versionDirs := SortPathsByFileNameDescending(Directory.GetDirectories(packDirs[packIndex], "*", SearchOption.TopDirectoryOnly))
                    versionIndex := 0
                    while versionIndex < versionDirs.Length {
                        refRoot := Path.Combine(versionDirs[versionIndex], "ref")
                        if Directory.Exists(refRoot) {
                            tfmDirs := SortPathsByFileNameDescending(Directory.GetDirectories(refRoot, "*", SearchOption.TopDirectoryOnly))
                            tfmIndex := 0
                            while tfmIndex < tfmDirs.Length {
                                directories.Add(tfmDirs[tfmIndex])
                                tfmIndex = tfmIndex + 1
                            }
                        }

                        versionIndex = versionIndex + 1
                    }

                    packIndex = packIndex + 1
                }
            }

            rootIndex = rootIndex + 1
        }

        return DeduplicateStableStringsOrdinalIgnoreCase(directories)
    }

    static func GetLookupSplitPlans(query: string): DocQueryLookupSplitPlan[] {
        parts := query.Split('.')
        if parts.Length < 2 {
            return new DocQueryLookupSplitPlan[](0)
        }

        planCount := parts.Length - 1
        plans := new DocQueryLookupSplitPlan[](planCount)
        planIndex := 0
        i := parts.Length - 1
        while i >= 1 {
            remainderCount := parts.Length - i
            remainderParts := new string[](remainderCount)
            r := 0
            while r < remainderCount {
                remainderParts[r] = parts[i + r]
                r = r + 1
            }

            containingCount := remainderCount - 1
            containingTypeParts := new string[](containingCount)
            r = 0
            while r < containingCount {
                containingTypeParts[r] = remainderParts[r]
                r = r + 1
            }

            plans[planIndex] = new DocQueryLookupSplitPlan(JoinDocQueryParts(parts, 0, i), remainderParts, containingTypeParts, remainderParts[0], remainderParts[remainderCount - 1])

            planIndex = planIndex + 1
            i = i - 1
        }

        return plans
    }

    static func FormatSeeElementText(elementValue: string?, langword: string?, href: string?, cref: string?): string {
        if !string.IsNullOrWhiteSpace(elementValue) {
            return elementValue
        }

        if !string.IsNullOrWhiteSpace(langword) {
            return langword
        }

        if !string.IsNullOrWhiteSpace(href) {
            return href
        }

        if string.IsNullOrWhiteSpace(cref) {
            return ""
        }

        value := cref
        prefixIndex := value.IndexOf(':')
        if prefixIndex >= 0 {
            value = value.Substring(prefixIndex + 1)
        }

        value = value.Replace('+', '.')

        parameterIndex := value.IndexOf('(')
        if parameterIndex >= 0 {
            value = value.Substring(0, parameterIndex)
        }

        return StripGenericArity(GetLastDocQuerySegment(value))
    }

    static func FormatDocTextRaw(raw: string): string? {
        if string.IsNullOrWhiteSpace(raw) {
            return null
        }

        builder := new StringBuilder()
        pendingSpace := false
        wroteText := false
        i := 0
        while i < raw.Length {
            ch := raw[i]
            if char.IsWhiteSpace(ch) {
                if wroteText {
                    pendingSpace = true
                }
            } else {
                if pendingSpace && builder.Length > 0 {
                    builder.Append(" ")
                }

                builder.Append(ch)
                wroteText = true
                pendingSpace = false
            }

            i = i + 1
        }

        return builder.ToString()
    }

    static func FormatDocElementNodeText(localName: string, elementValue: string?, childText: string, nameAttribute: string?, langword: string?, href: string?, cref: string?): string {
        if localName == "see" || localName == "seealso" {
            return FormatSeeElementText(elementValue, langword, href, cref)
        }

        if localName == "paramref" || localName == "typeparamref" {
            return nameAttribute ?? ""
        }

        if localName == "c" || localName == "code" {
            return elementValue ?? ""
        }

        if localName == "para" {
            return childText + " "
        }

        return childText
    }

    static func CreateDocMemberResult(name: string, kind: string, typeName: string?, summary: string?, parameters: string?): DocMemberResult {
        return new DocMemberResult(name, kind, typeName, summary, parameters)
    }

    static func CreateDocParameterResult(parameterName: string?, typeName: string, summary: string?): DocParameterResult {
        return new DocParameterResult(parameterName ?? "?", typeName, summary)
    }

    static func CreateTypeDocResult(name: string, fullName: string, kind: string, summary: string?, namespaceName: string?, members: DocMemberResult[]?, baseTypes: string[]?): DocResult {
        return new DocResult(name, fullName, kind, summary, namespaceName, members, null, null, null, baseTypes)
    }

    static func CreateCallableDocResult(name: string, fullName: string, kind: string, summary: string?, namespaceName: string?, overloads: DocMemberResult[]?, parameters: DocParameterResult[]?, returnType: string?, returnDoc: string?): DocResult {
        return new DocResult(name, fullName, kind, summary, namespaceName, overloads, parameters, returnType, returnDoc, null)
    }

    static func CreateValueDocResult(name: string, fullName: string, kind: string, summary: string?, namespaceName: string?, returnType: string?): DocResult {
        return new DocResult(name, fullName, kind, summary, namespaceName, null, null, returnType, null, null)
    }

    static func ScoreTypeMatch(strippedQuery: string, qualifiedName: string, simpleName: string, namespaceName: string, isNested: int): int {
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

    static func DocQueryEqualsSubstringIgnoreCase(left: string, leftStart: int, leftLength: int, right: string, rightStart: int, rightLength: int): bool {
        if leftLength != rightLength {
            return false
        }

        return String.Compare(left, leftStart, right, rightStart, leftLength, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func DocQueryIsDigit(ch: char): bool {
        return ch >= '0' && ch <= '9'
    }

    static func AddUniqueString(values: List<string>, seen: HashSet<string>, value: string) {
        if seen.Add(value) {
            values.Add(value)
        }
    }

    static func FindDotNetRootCandidate(assemblyLocation: string): string? {
        current := Path.GetDirectoryName(assemblyLocation) ?? ""
        while !string.IsNullOrWhiteSpace(current) {
            if Directory.Exists(Path.Combine(current, "packs")) && Directory.Exists(Path.Combine(current, "shared")) {
                return current
            }

            parent := Path.GetDirectoryName(current) ?? ""
            if parent == current {
                return null
            }

            current = parent
        }

        return null
    }

    static func GetPathFileNameWithoutExtension(path: string): string {
        fileName := Path.GetFileName(path) ?? path
        dotIndex := -1
        i := fileName.Length - 1
        while i >= 0 {
            if fileName[i] == '.' {
                dotIndex = i
                i = -1
            } else {
                i = i - 1
            }
        }

        if dotIndex > 0 {
            return fileName.Substring(0, dotIndex)
        }

        return fileName
    }

    static func ChangePathExtensionToXml(path: string): string {
        lastSeparatorIndex := -1
        lastDotIndex := -1
        i := path.Length - 1
        while i >= 0 {
            ch := path[i]
            if lastSeparatorIndex < 0 && (ch == '/' || ch == '\\') {
                lastSeparatorIndex = i
            }

            if lastDotIndex < 0 && ch == '.' {
                lastDotIndex = i
            }

            i = i - 1
        }

        if lastDotIndex > lastSeparatorIndex {
            return path.Substring(0, lastDotIndex) + ".xml"
        }

        return path + ".xml"
    }

    static func JoinDocQueryParts(parts: string[], start: int, count: int): string {
        builder := new StringBuilder()
        i := 0
        while i < count {
            if i > 0 {
                builder.Append(".")
            }

            builder.Append(parts[start + i])
            i = i + 1
        }

        return builder.ToString()
    }

    static func GetLastDocQuerySegment(value: string): string {
        i := value.Length - 1
        while i >= 0 {
            if value[i] == '.' {
                if i + 1 >= value.Length {
                    return value
                }

                return value.Substring(i + 1)
            }

            i = i - 1
        }

        return value
    }
}
