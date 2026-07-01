import System

// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// the former src/NSharpLang.Compiler.Dogfood/CompilerServices/ErrorSuggestions.nl product probe.
// These functions exist solely as parity-test surfaces (tests + benchmarks bind them by NAME).
// They are NOT part of the shipped dogfood assembly.

struct TypoSuggestionInputTable {
    Typos: string[]
    Candidates: string[]
}

struct TypoSuggestionDistanceTable {
    Previous: int[]
    Current: int[]
}

struct TypoSuggestionDistanceRowTable {
    Values: int[]
}

struct TypoSuggestionResultTable {
    Starts: int[]
    Counts: int[]
    Indices: int[]
}

func TypoSuggestionIndicesInto(
    typos: string[],
    candidates: string[],
    maxSuggestions: int,
    previousDistances: int[],
    currentDistances: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    inputs := new TypoSuggestionInputTable { Typos: typos, Candidates: candidates }
    distances := new TypoSuggestionDistanceTable { Previous: previousDistances, Current: currentDistances }
    result := new TypoSuggestionResultTable { Starts: resultStarts, Counts: resultCounts, Indices: resultIndices }
    return TypoSuggestionIndicesCore(ref inputs, maxSuggestions, ref distances, ref result)
}

func TypoSuggestionIndicesCore(
    inputs: &TypoSuggestionInputTable,
    maxSuggestions: int,
    distances: &TypoSuggestionDistanceTable,
    result: &TypoSuggestionResultTable): int {
    queryCount := TypoSuggestionMinInt(inputs.Typos.Length, result.Starts.Length)
    queryCount = TypoSuggestionMinInt(queryCount, result.Counts.Length)

    suggestionLimit := maxSuggestions
    if suggestionLimit > 3 {
        suggestionLimit = 3
    }

    writeIndex := 0
    queryIndex := 0
    while queryIndex < queryCount {
        result.Starts[queryIndex] = writeIndex

        if suggestionLimit <= 0 {
            result.Counts[queryIndex] = 0
            queryIndex = queryIndex + 1
            continue
        }

        typo := inputs.Typos[queryIndex]
        top0Index := -1
        top1Index := -1
        top2Index := -1
        top0Numerator := 0
        top1Numerator := 0
        top2Numerator := 0
        top0Denominator := 1
        top1Denominator := 1
        top2Denominator := 1
        topCount := 0

        candidateIndex := 0
        while candidateIndex < inputs.Candidates.Length {
            candidate := inputs.Candidates[candidateIndex]
            maxLength := TypoSuggestionMaxInt(typo.Length, candidate.Length)
            minLength := TypoSuggestionMinInt(typo.Length, candidate.Length)
            if maxLength > 0 && minLength > 0 {
                distance := TypoSuggestionLevenshteinDistanceCore(typo, candidate, ref distances)
                prefixLength := TypoSuggestionCommonPrefixLength(typo, candidate)
                numerator := TypoSuggestionScoreNumerator(maxLength, minLength, distance, prefixLength)
                denominator := 10 * maxLength * minLength

                if numerator * 2 > denominator {
                    if topCount == 0 || TypoSuggestionScoreGreater(
                        numerator,
                        denominator,
                        top0Numerator,
                        top0Denominator) {
                        top2Index = top1Index
                        top2Numerator = top1Numerator
                        top2Denominator = top1Denominator
                        top1Index = top0Index
                        top1Numerator = top0Numerator
                        top1Denominator = top0Denominator
                        top0Index = candidateIndex
                        top0Numerator = numerator
                        top0Denominator = denominator
                        if topCount < 3 {
                            topCount = topCount + 1
                        }
                    } else if suggestionLimit > 1 && (topCount < 2 || TypoSuggestionScoreGreater(
                        numerator,
                        denominator,
                        top1Numerator,
                        top1Denominator)) {
                        top2Index = top1Index
                        top2Numerator = top1Numerator
                        top2Denominator = top1Denominator
                        top1Index = candidateIndex
                        top1Numerator = numerator
                        top1Denominator = denominator
                        if topCount < 3 {
                            topCount = topCount + 1
                        }
                    } else if suggestionLimit > 2 && (topCount < 3 || TypoSuggestionScoreGreater(
                        numerator,
                        denominator,
                        top2Numerator,
                        top2Denominator)) {
                        top2Index = candidateIndex
                        top2Numerator = numerator
                        top2Denominator = denominator
                        if topCount < 3 {
                            topCount = topCount + 1
                        }
                    }
                }
            }

            candidateIndex = candidateIndex + 1
        }

        emitCount := TypoSuggestionMinInt(topCount, suggestionLimit)
        if emitCount > 0 && writeIndex < result.Indices.Length {
            result.Indices[writeIndex] = top0Index
            writeIndex = writeIndex + 1
        }

        if emitCount > 1 && writeIndex < result.Indices.Length {
            result.Indices[writeIndex] = top1Index
            writeIndex = writeIndex + 1
        }

        if emitCount > 2 && writeIndex < result.Indices.Length {
            result.Indices[writeIndex] = top2Index
            writeIndex = writeIndex + 1
        }

        result.Counts[queryIndex] = writeIndex - result.Starts[queryIndex]
        queryIndex = queryIndex + 1
    }

    return writeIndex
}

func TypoSuggestionLevenshteinDistanceCore(
    left: string,
    right: string,
    distances: &TypoSuggestionDistanceTable): int {
    leftLength := left.Length
    rightLength := right.Length

    if leftLength == 0 {
        return rightLength
    }

    if rightLength == 0 {
        return leftLength
    }

    if distances.Previous.Length <= rightLength || distances.Current.Length <= rightLength {
        return leftLength + rightLength
    }

    previous := new TypoSuggestionDistanceRowTable { Values: distances.Previous }
    current := new TypoSuggestionDistanceRowTable { Values: distances.Current }

    column := 0
    while column <= rightLength {
        previous.Values[column] = column
        column = column + 1
    }

    row := 1
    while row <= leftLength {
        current.Values[0] = row

        column = 1
        while column <= rightLength {
            cost := 1
            if TypoSuggestionCharsEqualIgnoreCase(left[row - 1], right[column - 1]) {
                cost = 0
            }

            deletion := previous.Values[column] + 1
            insertion := current.Values[column - 1] + 1
            substitution := previous.Values[column - 1] + cost
            current.Values[column] = TypoSuggestionMinInt(TypoSuggestionMinInt(deletion, insertion), substitution)
            column = column + 1
        }

        temp := previous
        previous = current
        current = temp
        row = row + 1
    }

    return previous.Values[rightLength]
}

func TypoSuggestionCommonPrefixLength(left: string, right: string): int {
    length := TypoSuggestionMinInt(left.Length, right.Length)
    count := 0
    while count < length {
        if !TypoSuggestionCharsEqualIgnoreCase(left[count], right[count]) {
            return count
        }

        count = count + 1
    }

    return count
}

func TypoSuggestionScoreNumerator(
    maxLength: int,
    minLength: int,
    distance: int,
    prefixLength: int): int {
    distancePart := 7 * (maxLength - distance) * minLength
    prefixPart := 3 * prefixLength * maxLength
    return distancePart + prefixPart
}

func TypoSuggestionScoreGreater(
    leftNumerator: int,
    leftDenominator: int,
    rightNumerator: int,
    rightDenominator: int): bool {
    return leftNumerator * rightDenominator > rightNumerator * leftDenominator
}

func TypoSuggestionCharsEqualIgnoreCase(left: char, right: char): bool {
    if left == right {
        return true
    }

    if left >= 'A' && left <= 'Z' && right >= 'a' && right <= 'z' {
        return left - 'A' == right - 'a'
    }

    if left >= 'a' && left <= 'z' && right >= 'A' && right <= 'Z' {
        return left - 'a' == right - 'A'
    }

    return Char.ToLowerInvariant(left) == Char.ToLowerInvariant(right)
}

func TypoSuggestionMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

func TypoSuggestionMaxInt(left: int, right: int): int {
    if left > right {
        return left
    }

    return right
}

func TypoSuggestionChecksumInto(
    typos: string[],
    candidates: string[],
    maxSuggestions: int,
    previousDistances: int[],
    currentDistances: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    queryCount := TypoSuggestionMinInt(typos.Length, resultStarts.Length)
    queryCount = TypoSuggestionMinInt(queryCount, resultCounts.Length)
    total := TypoSuggestionIndicesInto(
        typos,
        candidates,
        maxSuggestions,
        previousDistances,
        currentDistances,
        resultStarts,
        resultCounts,
        resultIndices)

    checksum := total
    i := 0
    while i < queryCount {
        start := resultStarts[i]
        count := resultCounts[i]
        checksum = checksum + start * 7 + count * 97

        j := 0
        while j < count {
            index := start + j
            if index >= 0 && index < resultIndices.Length {
                checksum = checksum + resultIndices[index] * 31 + (j + 1) * 17
            }

            j = j + 1
        }

        i = i + 1
    }

    return checksum
}
