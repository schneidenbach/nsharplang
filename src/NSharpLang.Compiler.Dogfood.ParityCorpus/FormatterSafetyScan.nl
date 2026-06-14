// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/FormatterSafetyScan.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

// Compact severity/message-index scan for Formatter.FormatSafe reparse-error filtering.
//
// FormatSafe reparses formatted output and rejects the formatting if any reparse
// diagnostic has Error severity, collecting the error messages for a warning string.
// The host owns the public string materialization (string.Join over messages); this
// kernel only scans a compact severity int[] (0 = Warning, 1 = Error), reports whether
// any error exists, and writes the matching error-severity indices into a caller-owned
// int[], returning the count. No strings cross the boundary.

struct FormatterSafetySeverityTable {
    Severities: int[]
}

struct FormatterSafetyResultIndexTable {
    Indices: int[]
}

func FormatterSafetyHasError(severities: int[]): bool {
    diagnostics := new FormatterSafetySeverityTable { Severities: severities }
    return FormatterSafetyHasErrorCore(ref diagnostics)
}

func FormatterSafetyHasErrorCore(diagnostics: &FormatterSafetySeverityTable): bool {
    i := 0
    count := diagnostics.Severities.Length
    while i < count {
        if diagnostics.Severities[i] == 1 {
            return true
        }

        i = i + 1
    }

    return false
}

func FormatterSafetyErrorIndicesInto(
    severities: int[],
    resultIndices: int[]): int {
    diagnostics := new FormatterSafetySeverityTable { Severities: severities }
    result := new FormatterSafetyResultIndexTable { Indices: resultIndices }
    return FormatterSafetyErrorIndicesCore(ref diagnostics, ref result)
}

func FormatterSafetyErrorIndicesCore(
    diagnostics: &FormatterSafetySeverityTable,
    result: &FormatterSafetyResultIndexTable): int {
    count := diagnostics.Severities.Length
    maxResults := result.Indices.Length
    if count == 0 || maxResults == 0 {
        return 0
    }

    resultCount := 0
    i := 0
    while i < count {
        if diagnostics.Severities[i] == 1 {
            if resultCount < maxResults {
                result.Indices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func FormatterSafetyErrorIndicesChecksumInto(
    severities: int[],
    resultIndices: int[]): int {
    resultCount := FormatterSafetyErrorIndicesInto(severities, resultIndices)

    checksum := resultCount
    i := 0
    while i < resultCount && i < resultIndices.Length {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31 + (i + 1) * 13
        i = i + 1
    }

    return checksum
}
