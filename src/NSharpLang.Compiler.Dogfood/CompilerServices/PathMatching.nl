func CodeIntelligencePathMatches(fullPath: string, queryPath: string): int {
    if CodeIntelligencePathEqualsNormalizedIgnoreCase(fullPath, queryPath) {
        return 1
    }

    if !CodeIntelligencePathEndsWithNormalizedIgnoreCase(fullPath, queryPath) {
        return 0
    }

    charBeforeIndex := fullPath.Length - queryPath.Length - 1
    if charBeforeIndex < 0 {
        return 0
    }

    if CodeIntelligencePathNormalizeSlash(fullPath[charBeforeIndex]) == '/' {
        return 1
    }

    return 0
}

func CodeIntelligencePathMatchFlagsInto(
    fullPaths: string[],
    queryPaths: string[],
    resultFlags: int[]): int {
    count := CodeIntelligencePathMatchMinInt(fullPaths.Length, queryPaths.Length)
    count = CodeIntelligencePathMatchMinInt(count, resultFlags.Length)

    i := 0
    while i < count {
        resultFlags[i] = CodeIntelligencePathMatches(fullPaths[i], queryPaths[i])
        i = i + 1
    }

    return count
}

func CodeIntelligencePathEqualsNormalizedIgnoreCase(fullPath: string, queryPath: string): bool {
    if fullPath.Length != queryPath.Length {
        return false
    }

    i := 0
    while i < fullPath.Length {
        if !CodeIntelligencePathCharsEqualIgnoreCase(fullPath[i], queryPath[i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func CodeIntelligencePathEndsWithNormalizedIgnoreCase(fullPath: string, queryPath: string): bool {
    if queryPath.Length > fullPath.Length {
        return false
    }

    fullStart := fullPath.Length - queryPath.Length
    i := 0
    while i < queryPath.Length {
        if !CodeIntelligencePathCharsEqualIgnoreCase(fullPath[fullStart + i], queryPath[i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func CodeIntelligencePathCharsEqualIgnoreCase(left: char, right: char): bool {
    left = CodeIntelligencePathNormalizeSlash(left)
    right = CodeIntelligencePathNormalizeSlash(right)

    if left == right {
        return true
    }

    if left >= 'A' && left <= 'Z' && right >= 'a' && right <= 'z' {
        return left - 'A' == right - 'a'
    }

    if left >= 'a' && left <= 'z' && right >= 'A' && right <= 'Z' {
        return left - 'a' == right - 'A'
    }

    return Char.ToUpperInvariant(left) == Char.ToUpperInvariant(right)
}

func CodeIntelligencePathNormalizeSlash(ch: char): char {
    if ch == '\\' {
        return '/'
    }

    return ch
}

func CodeIntelligencePathMatchMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}
