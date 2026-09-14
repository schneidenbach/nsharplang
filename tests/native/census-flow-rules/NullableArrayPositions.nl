namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic


// `T?[]` AND `T[]?` IN EVERY TYPE POSITION, NOT ONLY IN A SIGNATURE.
//
// `tests/native/census-emit-shapes/NullableElementArrayLocal` pins the LOCAL position the census
// caught; these are the positions beside it — a field, a generic argument, the doubly-annotated
// `T?[]?`, and the element types all four reach on the CLR.
//
// The two spellings mean different things and both have to parse everywhere a type may be written.
// `string?[]` is an array whose ELEMENTS may be absent — the array itself is always there — and
// `string[]?` is an array reference that may be absent while its elements are not. The census caught
// the LOCAL position (`widened: string?[] = values` did not parse as a local annotation where the
// same spelling parsed as a parameter and as a return type); these sources pin the whole grid, so a
// type grammar that regresses one position fails here rather than in a converted file.
class Shelf {
    Labels: string?[]
    Rows: string[]?
    Counts: int?[]
    Both: string?[]?

    constructor(labels: string?[], rows: string[]?, counts: int?[], both: string?[]?) {
        Labels = labels
        Rows = rows
        Counts = counts
        Both = both
    }
}

func CountPresentLabels(values: string?[]): int {
    widened: string?[] = values
    total := 0
    for item in widened {
        if item != null {
            total = total + 1
        }
    }

    return total
}

func LengthOrZero(rows: string[]?): int {
    local: string[]? = rows
    if local == null {
        return 0
    }

    return local.Length
}

func SumPresentCounts(counts: int?[]): int {
    local: int?[] = counts
    total := 0
    for value in local {
        total = total + (value ?? 0)
    }

    return total
}

// THE SAME TWO SPELLINGS AS GENERIC ARGUMENTS, where a `?` also has to survive the angle brackets.
func CollectOptionalNames(values: string?[]): List<string?> {
    collected: List<string?> = new List<string?>()
    for item in values {
        collected.Add(item)
    }

    return collected
}

func IndexOptionalCounts(counts: int?[]): Dictionary<int, int?> {
    map: Dictionary<int, int?> = new Dictionary<int, int?>()
    index := 0
    while index < counts.Length {
        map[index] = counts[index]
        index = index + 1
    }

    return map
}

// A DOUBLY-ANNOTATED LOCAL: an array that may be absent whose elements may be absent too.
func PresentInBoth(values: string?[]?): int {
    local: string?[]? = values
    if local == null {
        return -1
    }

    return CountPresentLabels(local)
}

func MakeShelf(labels: string?[], rows: string[]?, counts: int?[], both: string?[]?): Shelf {
    return new Shelf(labels, rows, counts, both)
}
