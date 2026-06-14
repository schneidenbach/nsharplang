// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/PathMatching.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

struct CodeIntelligencePathMatchInputTable {
    FullPaths: string[]
    QueryPaths: string[]
}

struct CodeIntelligencePathMatchResultTable {
    Flags: int[]
}

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
    paths := new CodeIntelligencePathMatchInputTable { FullPaths: fullPaths, QueryPaths: queryPaths }
    result := new CodeIntelligencePathMatchResultTable { Flags: resultFlags }
    return CodeIntelligencePathMatchFlagsCore(ref paths, ref result)
}

func CodeIntelligencePathMatchFlagsCore(
    paths: &CodeIntelligencePathMatchInputTable,
    result: &CodeIntelligencePathMatchResultTable): int {
    count := CodeIntelligencePathMatchMinInt(paths.FullPaths.Length, paths.QueryPaths.Length)
    count = CodeIntelligencePathMatchMinInt(count, result.Flags.Length)

    i := 0
    while i < count {
        result.Flags[i] = CodeIntelligencePathMatches(paths.FullPaths[i], paths.QueryPaths[i])
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

func CodeIntelligencePathMatchChecksumInto(
    fullPaths: string[],
    queryPaths: string[],
    resultFlags: int[]): int {
    count := CodeIntelligencePathMatchFlagsInto(fullPaths, queryPaths, resultFlags)
    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultFlags[i] * (i + 1) * 31
        i = i + 1
    }

    return checksum
}
