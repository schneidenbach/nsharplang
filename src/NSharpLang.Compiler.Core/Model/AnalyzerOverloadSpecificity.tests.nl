namespace NSharpLang.Compiler

import System.Collections.Generic


// Native contracts for the "better function member" rule, pinned at the rule rather than at the two
// callers that fold into it.
//
// The owner deliberately takes BOOLEANS rather than types: the reflected world answers identity and
// convertibility over CLR `Type`s read from a MetadataLoadContext, the source world answers them over
// `TypeInfo`s, and the columnar emitter answers them over `TypeBuilder`s. Only the DECISION is shared,
// so only the decision is tested here — the three oracles are pinned beside their own owners.
func SpecificityVerdicts(values: int[]): List<int> {
    verdicts := new List<int>()
    index := 0
    while index < values.Length {
        verdicts.Add(values[index])
        index = index + 1
    }

    return verdicts
}

// A square verdict matrix built from its ROWS, because row-major is how `FindMaximalIndexes` reads it
// and a flat list of nine numbers is not a matrix a reader can check.
func SpecificityMatrix3(first: int[], second: int[], third: int[]): int[] {
    matrix := new int[9]
    index := 0
    while index < 3 {
        matrix[index] = first[index]
        matrix[3 + index] = second[index]
        matrix[6 + index] = third[index]
        index = index + 1
    }

    return matrix
}

// The maximal set rendered as a comma-joined string, which is the whole answer in one assertion.
func SpecificityMaximal(comparisons: int[], count: int): string {
    maximal := AnalyzerOverloadSpecificity.FindMaximalIndexes(comparisons, count)
    rendered := ""
    index := 0
    while index < maximal.Count {
        if index > 0 {
            rendered = rendered + ","
        }

        rendered = rendered + maximal[index].ToString()
        index = index + 1
    }

    return rendered
}

test "IDENTITY IS ASKED BEFORE SPECIFICITY, so a parameter the argument already has wins" {
    // `WriteLine(string)` against `WriteLine(object)` for a `string` argument: the left parameter IS
    // the argument's type. It wins even though the right one is reachable from it.
    assert AnalyzerOverloadSpecificity.CompareConversionTargets(true, false, true, false) == AnalyzerOverloadSpecificity.LeftIsBetter
    assert AnalyzerOverloadSpecificity.CompareConversionTargets(false, true, false, true) == AnalyzerOverloadSpecificity.RightIsBetter

    // BOTH identical is not a win for either — the two parameters denote the same type, and the
    // generic and params tie-breaks are what separate such a pair.
    assert AnalyzerOverloadSpecificity.CompareConversionTargets(true, true, true, true) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "THE MORE SPECIFIC TYPE WINS when neither parameter is the argument's own type" {
    // `IEnumerable<Task<int>>` over `IEnumerable<Task>` for a `List<Task<int>>`: the left converts to
    // the right and the right does not convert back.
    assert AnalyzerOverloadSpecificity.CompareConversionTargets(false, false, true, false) == AnalyzerOverloadSpecificity.LeftIsBetter
    assert AnalyzerOverloadSpecificity.CompareConversionTargets(false, false, false, true) == AnalyzerOverloadSpecificity.RightIsBetter

    // Two unrelated parameter types say nothing, and so do two mutually convertible ones.
    assert AnalyzerOverloadSpecificity.CompareConversionTargets(false, false, false, false) == AnalyzerOverloadSpecificity.NeitherIsBetter
    assert AnalyzerOverloadSpecificity.CompareConversionTargets(false, false, true, true) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "THE FOLD IS ALL-OR-NOTHING: winning one position and losing another is not winning" {
    left := SpecificityVerdicts([-1, 0, 0])
    assert AnalyzerOverloadSpecificity.FoldArgumentVerdicts(left) == AnalyzerOverloadSpecificity.LeftIsBetter

    right := SpecificityVerdicts([0, 1])
    assert AnalyzerOverloadSpecificity.FoldArgumentVerdicts(right) == AnalyzerOverloadSpecificity.RightIsBetter

    // `Pick(object, string)` against `Pick(string, object)` for `("a", "b")` — one position each. This
    // is the shape NL414 exists for.
    split := SpecificityVerdicts([1, -1])
    assert AnalyzerOverloadSpecificity.FoldArgumentVerdicts(split) == AnalyzerOverloadSpecificity.NeitherIsBetter

    // No positions at all — every argument was a lambda or a method group — says nothing either.
    assert AnalyzerOverloadSpecificity.FoldArgumentVerdicts(SpecificityVerdicts([])) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "THE GENERIC TIE-BREAK IS GATED ON THE PARAMETER TYPES BEING IDENTICAL" {
    // `string.Join(string, IEnumerable<string>)` over `Join<T>(string, IEnumerable<T>)` with
    // `T = string`: the substituted signatures are the same types, so the non-generic one wins.
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(true, false, true, false, false, 0, 0, 0) == AnalyzerOverloadSpecificity.LeftIsBetter
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(true, true, false, false, false, 0, 0, 0) == AnalyzerOverloadSpecificity.RightIsBetter

    // Signatures the conversions could NOT separate and that are not the same types are left alone:
    // "non-generic wins" is a tie-break, never a way to overturn a conversion that did not happen.
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, true, false, false, 0, 0, 0) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "NORMAL FORM BEATS AN EXPANDED PARAMS TAIL, AND FEWER DEFAULTS BEATS MORE, IN THAT ORDER" {
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, false, true, 0, 0, 0) == AnalyzerOverloadSpecificity.LeftIsBetter
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, true, false, 0, 0, 0) == AnalyzerOverloadSpecificity.RightIsBetter

    // The params key is read FIRST: a candidate that expands loses even though it fills fewer defaults.
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, true, false, 0, 3, 0) == AnalyzerOverloadSpecificity.RightIsBetter

    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, false, false, 0, 1, 0) == AnalyzerOverloadSpecificity.LeftIsBetter
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, false, false, 2, 1, 0) == AnalyzerOverloadSpecificity.RightIsBetter
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, false, false, 1, 1, 0) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "THE WRITTEN-SIGNATURE VERDICT IS THE LAST TIE-BREAK AND NEVER OVERTURNS AN EARLIER ONE" {
    // Nothing else separates the pair: the written signatures decide, and the verdict passes through.
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, false, false, 0, 0, AnalyzerOverloadSpecificity.LeftIsBetter) == AnalyzerOverloadSpecificity.LeftIsBetter
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, false, false, 0, 0, AnalyzerOverloadSpecificity.RightIsBetter) == AnalyzerOverloadSpecificity.RightIsBetter

    // An EARLIER key that answered wins: a candidate expanding a params tail loses even where its
    // written signature is the more specific one, and so does one that fills more defaults.
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, true, false, 0, 0, AnalyzerOverloadSpecificity.LeftIsBetter) == AnalyzerOverloadSpecificity.RightIsBetter
    assert AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, false, false, 2, 1, AnalyzerOverloadSpecificity.LeftIsBetter) == AnalyzerOverloadSpecificity.RightIsBetter
}

test "THE MAXIMAL SET IS WHAT NOTHING BEATS, and it does not depend on the candidate order" {
    // Three candidates, 0 beats 1 and 2. Read row-major: comparisons[row * count + column] is the
    // verdict of `row` against `column`.
    beaten := SpecificityMatrix3([0, -1, -1], [1, 0, 0], [1, 0, 0])
    assert SpecificityMaximal(beaten, 3) == "0"

    // The SAME relation with the winner declared last still answers one candidate, and it is the
    // winner — which is the property a reflected candidate list needs.
    beatenLast := SpecificityMatrix3([0, 0, 1], [0, 0, 1], [-1, -1, 0])
    assert SpecificityMaximal(beatenLast, 3) == "2"
}

test "TWO MAXIMAL CANDIDATES ARE THE AMBIGUITY, and a cycle is no answer at all" {
    // Nothing beats anything: both are maximal, which is NL414.
    tied := [0, 0, 0, 0]
    assert SpecificityMaximal(tied, 2) == "0,1"

    // 0 beats 1, 1 beats 2, 2 beats 0. Every candidate is beaten, so the set is EMPTY and the caller
    // must keep the order it already had rather than invent a winner.
    cycle := SpecificityMatrix3([0, -1, 1], [1, 0, -1], [-1, 1, 0])
    assert SpecificityMaximal(cycle, 3) == ""
}

test "a malformed matrix answers nothing rather than indexing out of itself" {
    assert SpecificityMaximal([0, 0, 0, 0], 0) == ""
    assert SpecificityMaximal([0, 0, 0], 2) == ""
    assert SpecificityMaximal([], 1) == ""
}

test "BOTH WORLDS SAY THE SAME SENTENCE ABOUT AN AMBIGUOUS CALL" {
    assert AnalyzerOverloadSpecificity.AmbiguousCallSummary("Select") == "The call to 'Select' is ambiguous"
    assert AnalyzerOverloadSpecificity.AmbiguousCallExplanation("Select") == "The call to `Select` is ambiguous — two overloads match it equally well:"

    hint := AnalyzerOverloadSpecificity.AmbiguousCallHint("Pick(a: object): int", "Pick(a: string): int")
    assert hint.Contains("  - Pick(a: object): int")
    assert hint.Contains("  - Pick(a: string): int")

    // The hint names the three disambiguating edits, because a diagnostic that only says "ambiguous"
    // leaves the reader with no next step.
    assert hint.Contains("cast an argument")
    assert hint.Contains("annotate a lambda's parameter types")
    assert hint.Contains("type arguments explicitly")
}
