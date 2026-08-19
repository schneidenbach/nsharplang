namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.CodeIntelligence


// THE CANONICAL CONTRACTS FOR `FixApplicatorTextEditOrderer`, IN N#.
//
// Part of the replacement for `tests/FixApplicatorTests.cs`. The subject is the five-key comparator
// that decides the order edits are applied in — LAST position first, so that applying one edit never
// invalidates the coordinates of the ones still to come.
//
// THE MEASURED WALL THIS FILE IS WRITTEN AROUND, AND WHY THE ANSWER IS BETTER THAN THE QUESTION.
// The deleted file swept 200 `new Random(seed)` edit lists against a LINQ `OrderByDescending` /
// `ThenBy` chain. `System.Random` cannot be constructed in this estate — the parameterless
// constructor declines exactly as the seeded one does — so the sweep is re-spelled over the 32-bit
// linear congruential generator below.
//
// THAT IS A STRENGTHENING, NOT A WORKAROUND. `Random(seed)`'s sequence is explicitly NOT stable
// across .NET versions: the deleted file's 200 "seeds" named an input set that a framework upgrade
// could silently replace, so a shape it happened to cover this year might not be covered next year,
// and nobody would see the coverage move. The generator here is fixed forever, in this repository,
// in a language the compiler owns.
//
// AND THE ORACLE IS GENUINELY INDEPENDENT. The subject sorts INDICES into five parallel `int[]`
// columns with an insertion sort, comparing through `TextEditOrderIndexComesBefore`. The oracle
// below is a SELECTION sort over the `TextEdit` records themselves, comparing fields directly. Two
// different algorithms, two different data layouts, one answer — which is what makes agreement
// evidence rather than a tautology. Both are total orders (the input index is the final tiebreak and
// no two indices are equal), so a correct sort of either kind must produce the identical sequence.
//
// WHAT THE DELETED FILE COULD NOT SAY. It asserted only that the two sorts AGREE. Agreement is
// silent if both are wrong the same way — and they shared a comparator specification written twice
// from the same paragraph. This file also states, on every one of the 200 lists, that the answer is
// SORTED under the comparator and is a PERMUTATION of the input, which are properties an agreeing
// pair of broken sorts would still have to satisfy separately.

// ── The generator that replaces System.Random ─────────────────────────────────────────────────────

func FteoSeed(seed: int): int[] {
    state := new int[](1)
    state[0] = seed
    return state
}

// A 32-bit linear congruential generator (Numerical Recipes constants). Wrapping multiply-add is
// exactly what the algorithm wants; `& 2147483647` clears the sign bit so the modulus below cannot
// answer a negative index.
//
// THE `/ 65536` IS NOT DECORATION AND IT WAS MEASURED, NOT ASSUMED. An LCG's LOW-order bits have
// famously short periods — taking `value % span` straight off the state made `Next(0, 12)` answer
// ODD NUMBERS ONLY, so half of every count in the sweep below was unreachable and four whole
// categories of edit list would never have been generated. Dividing first uses the high bits
// instead. The size census at the end of the sweep is what holds this honest: it fails if the
// generator ever degenerates again.
func FteoNext(state: int[], lowInclusive: int, highExclusive: int): int {
    state[0] = state[0] * 1664525 + 1013904223
    value := (state[0] & 2147483647) / 65536
    span := highExclusive - lowInclusive
    if span <= 0 {
        return lowInclusive
    }

    return lowInclusive + (value % span)
}

// ── The independent ordering oracle ───────────────────────────────────────────────────────────────

// The five keys, spelled against the records rather than against parallel columns: start line
// DESCENDING, start column DESCENDING, end line ASCENDING, end column ASCENDING, input index
// DESCENDING.
func FteoOracleComesBefore(left: TextEdit, leftIndex: int, right: TextEdit, rightIndex: int): bool {
    if left.StartLine != right.StartLine {
        return left.StartLine > right.StartLine
    }

    if left.StartColumn != right.StartColumn {
        return left.StartColumn > right.StartColumn
    }

    if left.EndLine != right.EndLine {
        return left.EndLine < right.EndLine
    }

    if left.EndColumn != right.EndColumn {
        return left.EndColumn < right.EndColumn
    }

    return leftIndex > rightIndex
}

func FteoOracleOrder(edits: List<TextEdit>): List<TextEdit> {
    count := edits.Count
    order := new int[](count)
    i := 0
    while i < count {
        order[i] = i
        i = i + 1
    }

    outer := 0
    while outer < count {
        best := outer
        inner := outer + 1
        while inner < count {
            if FteoOracleComesBefore(edits[order[inner]], order[inner], edits[order[best]], order[best]) {
                best = inner
            }

            inner = inner + 1
        }

        swap := order[outer]
        order[outer] = order[best]
        order[best] = swap
        outer = outer + 1
    }

    result := new List<TextEdit>()
    k := 0
    while k < count {
        result.Add(edits[order[k]])
        k = k + 1
    }

    return result
}

// ── Shared helpers ────────────────────────────────────────────────────────────────────────────────

func FteoJoin(edits: List<TextEdit>): string {
    text := ""
    for edit in edits {
        text = text + edit.StartLine.ToString() + "," + edit.StartColumn.ToString() + ".." + edit.EndLine.ToString() + "," + edit.EndColumn.ToString() + "=" + edit.NewText + ";"
    }

    return text
}

// Is `ordered` sorted under the comparator, judged WITHOUT consulting either sort? The index key is
// re-derived from the original list by identity of the replacement text, which the sweep keeps
// unique per list.
func FteoIndexOf(edits: List<TextEdit>, newText: string): int {
    i := 0
    while i < edits.Count {
        if edits[i].NewText == newText {
            return i
        }

        i = i + 1
    }

    return -1
}

func FteoIsSorted(original: List<TextEdit>, ordered: List<TextEdit>): bool {
    i := 1
    while i < ordered.Count {
        previous := ordered[i - 1]
        current := ordered[i]
        previousIndex := FteoIndexOf(original, previous.NewText)
        currentIndex := FteoIndexOf(original, current.NewText)

        // Every adjacent pair must be in strict comparator order, and never the other way round.
        if !FteoOracleComesBefore(previous, previousIndex, current, currentIndex) {
            return false
        }

        if FteoOracleComesBefore(current, currentIndex, previous, previousIndex) {
            return false
        }

        i = i + 1
    }

    return true
}

// Is `ordered` a permutation of `original`? Counted by replacement text, which the sweep keeps unique.
func FteoIsPermutation(original: List<TextEdit>, ordered: List<TextEdit>): bool {
    if original.Count != ordered.Count {
        return false
    }

    for edit in original {
        seen := 0
        for candidate in ordered {
            if candidate.NewText == edit.NewText {
                seen = seen + 1
            }
        }

        if seen != 1 {
            return false
        }
    }

    return true
}

func FteoList(): List<TextEdit> {
    return new List<TextEdit>()
}

// ── Contracts ─────────────────────────────────────────────────────────────────────────────────────

// Successor to DogfoodTextEditOrdering_IsActuallyExercisedInTests.
test "ordering a single edit answers that edit, from an array as well as a list" {
    // The deleted file passed a C# ARRAY, which crosses into the `IReadOnlyCollection<TextEdit>`
    // parameter. That crossing is kept rather than quietly swapped for a list, because it is the
    // shape the language server's own edit arrays take.
    array := new TextEdit[](1)
    array[0] = new TextEdit(1, 0, 1, 1, "x")

    orderedFromArray := FixApplicatorTextEditOrderer.OrderTextEdits(array)
    assert orderedFromArray.Count == 1
    assert orderedFromArray[0].Equals(array[0])

    list := FteoList()
    list.Add(new TextEdit(1, 0, 1, 1, "x"))
    orderedFromList := FixApplicatorTextEditOrderer.OrderTextEdits(list)
    assert orderedFromList.Count == 1
    assert orderedFromList[0].Equals(list[0])

    // NOT IN THE DELETED FILE: an EMPTY collection answers an empty list rather than throwing on the
    // `count - 1` loop bound, and the answer is a NEW list either way — the orderer never hands back
    // the collection it was given.
    assert FixApplicatorTextEditOrderer.OrderTextEdits(FteoList()).Count == 0
}

// NOT IN THE DELETED FILE: each of the five keys, isolated so that exactly one of them decides.
test "each of the five ordering keys decides on its own" {
    // Key 1 — START LINE, descending. Everything else equal.
    startLine := FteoList()
    startLine.Add(new TextEdit(1, 0, 1, 0, "low"))
    startLine.Add(new TextEdit(9, 0, 9, 0, "high"))
    assert FteoJoin(FixApplicatorTextEditOrderer.OrderTextEdits(startLine)) == "9,0..9,0=high;1,0..1,0=low;"

    // Key 2 — START COLUMN, descending. Same line, so key 1 cannot decide.
    startColumn := FteoList()
    startColumn.Add(new TextEdit(1, 0, 1, 0, "left"))
    startColumn.Add(new TextEdit(1, 7, 1, 7, "right"))
    assert FteoJoin(FixApplicatorTextEditOrderer.OrderTextEdits(startColumn)) == "1,7..1,7=right;1,0..1,0=left;"

    // Key 3 — END LINE, ASCENDING. The direction FLIPS here, and the flip is the whole reason a
    // nested edit sorts inside its container rather than after it.
    endLine := FteoList()
    endLine.Add(new TextEdit(1, 0, 5, 0, "wide"))
    endLine.Add(new TextEdit(1, 0, 2, 0, "narrow"))
    assert FteoJoin(FixApplicatorTextEditOrderer.OrderTextEdits(endLine)) == "1,0..2,0=narrow;1,0..5,0=wide;"

    // Key 4 — END COLUMN, ascending. Same start and same end line.
    endColumn := FteoList()
    endColumn.Add(new TextEdit(1, 0, 1, 9, "wide"))
    endColumn.Add(new TextEdit(1, 0, 1, 3, "narrow"))
    assert FteoJoin(FixApplicatorTextEditOrderer.OrderTextEdits(endColumn)) == "1,0..1,3=narrow;1,0..1,9=wide;"

    // Key 5 — INPUT INDEX, descending. Every coordinate identical, so only the arrival order is
    // left. This is the key that makes two insertions at one point come out in input order in the
    // TEXT: they are applied last-first, so the later one is spliced first and ends up on the right.
    index := FteoList()
    index.Add(new TextEdit(2, 1, 2, 1, "first"))
    index.Add(new TextEdit(2, 1, 2, 1, "second"))
    index.Add(new TextEdit(2, 1, 2, 1, "third"))
    assert FteoJoin(FixApplicatorTextEditOrderer.OrderTextEdits(index)) == "2,1..2,1=third;2,1..2,1=second;2,1..2,1=first;"
}

// NOT IN THE DELETED FILE: the keys are consulted in order, proved by a pair that disagrees on two
// keys at once.
test "an earlier key wins over a later one" {
    // Start line says "b before a"; end line, if it were consulted first, would say the opposite.
    lineOverEnd := FteoList()
    lineOverEnd.Add(new TextEdit(1, 0, 1, 0, "a"))
    lineOverEnd.Add(new TextEdit(2, 0, 9, 0, "b"))
    assert FteoJoin(FixApplicatorTextEditOrderer.OrderTextEdits(lineOverEnd)) == "2,0..9,0=b;1,0..1,0=a;"

    // Start column says "b before a"; end column would say the opposite.
    columnOverEnd := FteoList()
    columnOverEnd.Add(new TextEdit(1, 0, 1, 1, "a"))
    columnOverEnd.Add(new TextEdit(1, 4, 1, 9, "b"))
    assert FteoJoin(FixApplicatorTextEditOrderer.OrderTextEdits(columnOverEnd)) == "1,4..1,9=b;1,0..1,1=a;"

    // End line says "a before b"; the index key would say the opposite.
    endOverIndex := FteoList()
    endOverIndex.Add(new TextEdit(1, 0, 2, 0, "a"))
    endOverIndex.Add(new TextEdit(1, 0, 8, 0, "b"))
    assert FteoJoin(FixApplicatorTextEditOrderer.OrderTextEdits(endOverIndex)) == "1,0..2,0=a;1,0..8,0=b;"
}

// Successor to DogfoodTextEditOrdering_MatchesBaseline_AcrossRandomizedEdits.
test "the orderer agrees with an independent oracle across 200 generated edit lists" {
    lists := 0
    listsWithDuplicates := 0
    emptyLists := 0
    totalEdits := 0
    largest := 0
    sameLineEdits := 0
    multiLineEdits := 0
    sizesSeen := new bool[](15)

    seed := 0
    while seed < 200 {
        rng := FteoSeed(seed)
        edits := FteoList()

        count := FteoNext(rng, 0, 12)
        i := 0
        while i < count {
            startLine := FteoNext(rng, 1, 4)
            startColumn := FteoNext(rng, 0, 4)
            endLine := startLine + FteoNext(rng, 0, 2)
            endColumn := 0
            if endLine == startLine {
                endColumn = startColumn + FteoNext(rng, 0, 3)
                sameLineEdits = sameLineEdits + 1
            } else {
                endColumn = FteoNext(rng, 0, 4)
                multiLineEdits = multiLineEdits + 1
            }

            edits.Add(new TextEdit(startLine, startColumn, endLine, endColumn, "e" + i.ToString()))
            i = i + 1
        }

        // Force some same-position zero-width inserts, so the index tiebreak is exercised rather
        // than merely present. This is the deleted file's own construction, kept.
        duplicates := FteoNext(rng, 0, 4)
        k := 0
        while k < duplicates {
            edits.Add(new TextEdit(2, 1, 2, 1, "ins" + k.ToString()))
            k = k + 1
        }

        expected := FteoOracleOrder(edits)
        actual := FixApplicatorTextEditOrderer.OrderTextEdits(edits)

        // (a) The two independent sorts agree — the deleted file's whole claim.
        assert FteoJoin(actual) == FteoJoin(expected)

        // (b) NOT IN THE DELETED FILE: the answer is genuinely SORTED under the comparator, judged
        // without consulting either sort. Two sorts that agreed by sharing a defect would still have
        // to pass this.
        assert FteoIsSorted(edits, actual)

        // (c) NOT IN THE DELETED FILE: nothing was dropped, duplicated or invented.
        assert FteoIsPermutation(edits, actual)

        lists = lists + 1
        totalEdits = totalEdits + edits.Count
        sizesSeen[edits.Count] = true
        if duplicates > 0 {
            listsWithDuplicates = listsWithDuplicates + 1
        }

        if edits.Count == 0 {
            emptyLists = emptyLists + 1
        }

        if edits.Count > largest {
            largest = edits.Count
        }

        seed = seed + 1
    }

    // THE SWEEP'S OWN COVERAGE IS PINNED, so a generator that silently emptied or narrowed it cannot
    // pass. The deleted file asserted NOTHING about its own inputs: a `Random` that answered zero
    // every time would have swept 200 EMPTY lists and reported success, and a low-bit degeneracy
    // that halved the reachable list sizes — which is exactly what the first generator here did —
    // would have gone unnoticed forever.
    assert lists == 200
    assert totalEdits == 1412
    assert listsWithDuplicates == 153
    assert emptyLists == 4
    assert largest == 14

    // Every list size from 0 to 14 is actually generated. This is the census that caught the
    // low-bit degeneracy: under the naive generator only the ODD sizes were ever reached.
    size := 0
    while size <= 14 {
        assert sizesSeen[size]
        size = size + 1
    }

    // And both edit SHAPES are swept in quantity — a single-line replacement and one that spans a
    // line boundary take different arms of both the comparator's end-line key and the engine's
    // application path.
    assert sameLineEdits == 533
    assert multiLineEdits == 573

    // The remainder is the forced co-located inserts, and there are 306 of them — the tiebreak key
    // is swept in bulk rather than by the handful of hand-written cases above.
    assert totalEdits - sameLineEdits - multiLineEdits == 306
}
