// Compact severity/message-index scan for Formatter.FormatSafe reparse-error filtering.
//
// FormatSafe reparses formatted output and rejects the formatting if any reparse
// diagnostic has Error severity, collecting the error messages for a warning string.
// The host owns the public string materialization (string.Join over messages); this
// kernel only scans a compact severity int[] (0 = Warning, 1 = Error), reports whether
// any error exists, and writes the matching error-severity indices into a caller-owned
// int[], returning the count. No strings cross the boundary.

func FormatterSafetyHasError(severities: int[]): bool {
    i := 0
    count := severities.Length
    while i < count {
        if severities[i] == 1 {
            return true
        }

        i = i + 1
    }

    return false
}

func FormatterSafetyErrorIndicesInto(
    severities: int[],
    resultIndices: int[]): int {
    count := severities.Length
    maxResults := resultIndices.Length
    if count == 0 || maxResults == 0 {
        return 0
    }

    resultCount := 0
    i := 0
    while i < count {
        if severities[i] == 1 {
            if resultCount < maxResults {
                resultIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}
