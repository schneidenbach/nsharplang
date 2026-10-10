namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic


// CENSUS §3 — THE JOIN AFTER AN `if` WHOSE BRANCH DOES NOT LEAVE.
//
// A guard clause deletes one of the two paths, so the surviving flow inherits the other one and the
// analyzer has always been able to say what follows it. An `if` whose branch FALLS THROUGH has two
// live paths and what follows is their JOIN — and that was the half the analyzer was missing. It
// forgot the branch's exit state when the branch's scope closed, and it never installed the
// condition's FALSE facts anywhere, so the TryGetValue-or-create idiom the converted language
// server writes in every index it builds
//
//     if !locations.TryGetValue(name, out list) {
//         list = new List<int>()
//     }
//     list.Add(line)
//
// squiggled on the line below with NL905. BOTH paths reach it holding a list: the then-branch just
// assigned one, and the implicit else path is the path on which `TryGetValue` returned TRUE, which
// is exactly what `[MaybeNullWhen(false)]` says leaves the `out` target non-null.
//
// The sources below are the converted idiom verbatim, its mirrors, and the negatives that must keep
// their answer — a branch that re-assigns a MAYBE-null value, and a branch that assigns on only one
// of the two paths. All of them RUN, because a join that compiles and then dereferences null is not
// a fix.

// THE CENSUS PROBE, VERBATIM: out/languageserver/Services/DocumentManager.nl:603–608.
func AddLine(locations: Dictionary<string, List<int>>, name: string, line: int) {
    list: List<int>? = default
    if !locations.TryGetValue(name, out list) {
        list = new List<int>()
        locations[name] = list
    }

    list.Add(line)
}

// THE MIRROR: the un-negated condition with an EMPTY then-branch and the creation in the `else`.
// The then-branch proves nothing of its own — what it ends with is what the condition proved when
// it was TRUE — and the else-branch ends with the list it just made.
func AddLineFromElse(locations: Dictionary<string, List<int>>, name: string, line: int) {
    list: List<int>? = default
    if locations.TryGetValue(name, out list) {
    } else {
        list = new List<int>()
        locations[name] = list
    }

    list.Add(line)
}

// THE NULL-CHECK SPELLING OF THE SAME IDIOM, over a local rather than an `out` target.
func CountOrEmpty(input: List<int>?): int {
    values := input
    if values == null {
        values = new List<int>()
    }

    return values.Count
}

// BOTH BRANCHES ASSIGN: the join of two not-null paths is not-null, whatever the condition proved.
func ChooseList(useFirst: bool, first: List<int>, second: List<int>): int {
    chosen: List<int>? = default
    if useFirst {
        chosen = first
    } else {
        chosen = second
    }

    return chosen.Count
}

// AN `else if` CHAIN JOINS TOO. The inner `if` is a statement in the else slot and runs inside the
// else branch's own scope, so what IT concludes is the else branch's exit state and is joined with
// the then-branch's rather than escaping the outer statement.
func ChooseFromChain(which: int, first: List<int>, second: List<int>, third: List<int>): int {
    chosen: List<int>? = default
    if which == 0 {
        chosen = first
    } else if which == 1 {
        chosen = second
    } else {
        chosen = third
    }

    return chosen.Count
}

// A GUARD CLAUSE STILL WINS OUTRIGHT — one path is deleted, so there is nothing to join with and the
// surviving flow takes the other branch whole.
func FirstOrZero(input: List<int>?): int {
    if input == null {
        return 0
    }

    return input.Count
}

// A `while` EXIT CARRIES THE CONDITION'S FALSE FACTS. A loop is left through the bottom only when
// its condition failed.
func FillUntilPresent(source: List<int>?, fallback: List<int>): int {
    values := source
    while values == null {
        values = fallback
    }

    return values.Count
}

// AND SO DOES A `for` EXIT, for the same reason.
func FillWithCounter(source: List<int>?, fallback: List<int>): int {
    values := source
    for attempt := 0; values == null; attempt++ {
        values = fallback
    }

    return values.Count
}

// THE PROPERTY PATH: FLOW6's stable member paths join exactly as a local does.
class LineIndex {
    Lines: List<int>?
}

func RecordLine(index: LineIndex, line: int): int {
    if index.Lines == null {
        index.Lines = new List<int>()
    }

    index.Lines.Add(line)
    return index.Lines.Count
}

// THE NEGATIVES, AS RUNNING CODE. A branch that assigns a MAYBE-null value leaves the join
// maybe-null, so the dereference has to be written defensively — and it still has to produce the
// right answer at runtime.
func CountOrFallback(input: List<int>?, fallback: List<int>): int {
    values: List<int>? = default
    if !CanUse(input) {
        values = input
    } else {
        values = fallback
    }

    if values == null {
        return -1
    }

    return values.Count
}

func CanUse(input: List<int>?): bool {
    return input != null
}
