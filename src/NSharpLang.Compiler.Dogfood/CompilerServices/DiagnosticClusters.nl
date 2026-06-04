import System
import System.Text

func DiagnosticSeveritySummaryInto(severities: string[], count: int, resultCounts: int[]): int {
    if resultCounts.Length < 3 {
        return 0
    }

    if count > severities.Length {
        count = severities.Length
    }

    errors := 0
    warnings := 0
    info := 0
    i := 0

    while i < count {
        severity := severities[i]
        if severity == "error" {
            errors = errors + 1
        } else if severity == "warning" {
            warnings = warnings + 1
        } else if severity == "info" {
            info = info + 1
        }

        i = i + 1
    }

    resultCounts[0] = errors
    resultCounts[1] = warnings
    resultCounts[2] = info
    return count
}

func DiagnosticSeveritySummaryChecksumInto(severities: string[], count: int, resultCounts: int[]): int {
    count = DiagnosticSeveritySummaryInto(severities, count, resultCounts)
    if resultCounts.Length < 3 {
        return count
    }

    return count + resultCounts[0] * 31 + resultCounts[1] * 17 + resultCounts[2] * 13
}

func DiagnosticClusterTraitsInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[]): int {
    count := MinInt(codes.Length, messages.Length)
    count = MinInt(count, snippets.Length)
    count = MinInt(count, resultCategories.Length)
    count = MinInt(count, resultSourceConstructs.Length)

    i := 0
    while i < count {
        code := codes[i]
        message := messages[i]
        snippet := snippets[i]

        category := ClassifyDiagnosticCategory(code, message)
        sourceConstruct := 8

        if category == 2 {
            sourceConstruct = 4
        } else {
            sourceConstruct = InferDiagnosticSourceConstruct(snippet)
        }

        resultCategories[i] = category
        resultSourceConstructs[i] = sourceConstruct

        i = i + 1
    }

    return count
}

func DiagnosticClusterTraitChecksumInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[]): int {
    count := DiagnosticClusterTraitsInto(
        codes,
        messages,
        snippets,
        resultCategories,
        resultSourceConstructs)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultCategories[i] * 31 + resultSourceConstructs[i] * 17
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterTraitsAndPatternsInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[],
    resultPatterns: string[]): int {
    count := MinInt(codes.Length, messages.Length)
    count = MinInt(count, snippets.Length)
    count = MinInt(count, resultCategories.Length)
    count = MinInt(count, resultSourceConstructs.Length)
    count = MinInt(count, resultPatterns.Length)

    i := 0
    while i < count {
        code := codes[i]
        message := messages[i]
        snippet := snippets[i]

        category := ClassifyDiagnosticCategory(code, message)
        sourceConstruct := 8

        if category == 2 {
            sourceConstruct = 4
        } else {
            sourceConstruct = InferDiagnosticSourceConstruct(snippet)
        }

        resultCategories[i] = category
        resultSourceConstructs[i] = sourceConstruct
        resultPatterns[i] = NormalizeDiagnosticMessagePattern(message)

        i = i + 1
    }

    return count
}

func DiagnosticClusterTraitPatternChecksumInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[],
    resultPatterns: string[]): int {
    count := DiagnosticClusterTraitsAndPatternsInto(
        codes,
        messages,
        snippets,
        resultCategories,
        resultSourceConstructs,
        resultPatterns)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultCategories[i] * 31 + resultSourceConstructs[i] * 17 + resultPatterns[i].Length
        i = i + 1
    }

    return checksum
}

func ClassifyDiagnosticCategory(code: string, message: string): int {
    if code == "NL102" {
        if ContainsChar(message, ';') || ContainsIgnoreCase(message, "semicolon") {
            return 0
        }

        return 1
    }

    if code == "NL703" {
        return 2
    }

    if code == "NL301" || code == "NL412" {
        return 3
    }

    if code == "NL201" || code == "NL302" {
        return 4
    }

    if code == "NL202" {
        return 5
    }

    if code == "NL303" {
        return 6
    }

    if ContainsIgnoreCase(message, "expected token") || ContainsIgnoreCase(message, "missing") {
        if ContainsChar(message, ';') || ContainsIgnoreCase(message, "semicolon") {
            return 0
        }

        return 1
    }

    if ContainsIgnoreCase(message, "circular import") {
        return 2
    }

    if ContainsIgnoreCase(message, "undefined variable") || ContainsIgnoreCase(message, "undefined symbol") {
        return 3
    }

    if ContainsIgnoreCase(message, "type not found") || ContainsIgnoreCase(message, "undefined type") || ContainsIgnoreCase(message, "cannot resolve type") {
        return 4
    }

    if ContainsIgnoreCase(message, "type mismatch") {
        return 5
    }

    if ContainsIgnoreCase(message, "member") || ContainsIgnoreCase(message, "method") {
        return 6
    }

    return 7
}

func InferDiagnosticSourceConstruct(snippet: string): int {
    start := TrimStartIndex(snippet)

    if StartsWithIgnoreCase(snippet, start, "let ") || ContainsOrdinal(snippet, ":=") {
        return 0
    }

    declarationStart := StripLeadingDeclarationModifiers(snippet, start)
    if StartsWithIgnoreCase(snippet, declarationStart, "func ") || StartsWithIgnoreCase(snippet, declarationStart, "func* ") {
        return 1
    }

    if StartsWithIgnoreCase(snippet, start, "class ") {
        return 2
    }

    if StartsWithIgnoreCase(snippet, start, "interface ") {
        return 3
    }

    if StartsWithIgnoreCase(snippet, start, "import ") || StartsWithIgnoreCase(snippet, start, "using ") {
        return 4
    }

    if StartsWithIgnoreCase(snippet, start, "return ") {
        return 5
    }

    if StartsWithIgnoreCase(snippet, start, "if ") || StartsWithIgnoreCase(snippet, start, "for ") || StartsWithIgnoreCase(snippet, start, "while ") || StartsWithIgnoreCase(snippet, start, "match ") {
        return 6
    }

    if ContainsCharFrom(snippet, '(', start) && ContainsCharFrom(snippet, ')', start) {
        return 7
    }

    return 8
}

func StripLeadingDeclarationModifiers(snippet: string, start: int): int {
    current := start

    while true {
        current = TrimStartIndexFrom(snippet, current)

        if StartsWithIgnoreCase(snippet, current, "async ") {
            current = current + 6
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "static ") {
            current = current + 7
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "override ") {
            current = current + 9
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "public ") {
            current = current + 7
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "private ") {
            current = current + 8
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "protected ") {
            current = current + 10
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "internal ") {
            current = current + 9
            continue
        }

        return current
    }

    return current
}

func NormalizeDiagnosticMessagePattern(message: string): string {
    if IsBlank(message) {
        return "unknown-message"
    }

    builder := new StringBuilder(message.Length)
    inQuoted := false
    i := 0

    while i < message.Length {
        ch := message[i]
        if ch == '\'' || ch == '"' {
            inQuoted = !inQuoted
            if inQuoted {
                builder.Append("{value}")
            }

            i = i + 1
            continue
        }

        if !inQuoted {
            if ch >= '0' && ch <= '9' {
                builder.Append('#')
            } else {
                builder.Append(ch)
            }
        }

        i = i + 1
    }

    return builder.ToString().Trim()
}

func ContainsIgnoreCase(text: string, needle: string): bool {
    return text.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0
}

func StartsWithIgnoreCase(text: string, start: int, needle: string): bool {
    if start < 0 || start + needle.Length > text.Length {
        return false
    }

    return String.Compare(text, start, needle, 0, needle.Length, StringComparison.OrdinalIgnoreCase) == 0
}

func ContainsOrdinal(text: string, needle: string): bool {
    return text.IndexOf(needle, StringComparison.Ordinal) >= 0
}

func ContainsChar(text: string, ch: char): bool {
    return ContainsCharFrom(text, ch, 0)
}

func ContainsCharFrom(text: string, ch: char, start: int): bool {
    i := start
    if i < 0 {
        i = 0
    }

    while i < text.Length {
        if text[i] == ch {
            return true
        }

        i = i + 1
    }

    return false
}

func TrimStartIndex(text: string): int {
    return TrimStartIndexFrom(text, 0)
}

func TrimStartIndexFrom(text: string, start: int): int {
    i := start
    if i < 0 {
        i = 0
    }

    while i < text.Length && IsWhitespace(text[i]) {
        i = i + 1
    }

    return i
}

func IsBlank(text: string): bool {
    i := 0
    while i < text.Length {
        if !IsWhitespace(text[i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func IsWhitespace(ch: char): bool {
    return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'
}

func MinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}
