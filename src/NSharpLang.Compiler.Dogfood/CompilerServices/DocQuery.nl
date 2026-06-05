func DocQueryBestTypeIndex(scores: int[], namespaceLengths: int[], fullNames: string[], count: int): int {
    if count <= 0 {
        return -1
    }

    if scores.Length < count || namespaceLengths.Length < count || fullNames.Length < count {
        return -1
    }

    bestIndex := 0
    bestScore := scores[0]
    bestNamespaceLength := namespaceLengths[0]
    i := 1
    unrolledLimit := count - 8

    while i <= unrolledLimit {
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
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[i], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = i
                }
            }
        }

        candidateIndex := i + 1
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 2
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 3
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 4
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 5
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 6
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 7
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        i = i + 8
    }

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
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[i], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = i
                }
            }
        }

        i = i + 1
    }

    return bestIndex
}

func DocQueryBestTypeChecksumInto(scores: int[], namespaceLengths: int[], fullNames: string[], count: int): int {
    bestIndex := DocQueryBestTypeIndex(scores, namespaceLengths, fullNames, count)
    if bestIndex < 0 {
        return bestIndex
    }

    return (bestIndex + 1) * 97 + scores[bestIndex] * 31 + namespaceLengths[bestIndex] * 17
}

func DocQueryCompareOrdinalIgnoreCase(left: string, right: string): int {
    length := DocQueryMinInt(left.Length, right.Length)
    i := 0

    while i < length {
        leftChar := Char.ToLowerInvariant(left[i])
        rightChar := Char.ToLowerInvariant(right[i])

        if leftChar < rightChar {
            return -1
        }

        if leftChar > rightChar {
            return 1
        }

        i = i + 1
    }

    if left.Length < right.Length {
        return -1
    }

    if left.Length > right.Length {
        return 1
    }

    return 0
}

func DocQueryMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}
