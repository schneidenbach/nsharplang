namespace NSharpLang.CensusExceptionFilters.Tests


// RUN-TIME BEHAVIOUR of `catch ... when ...`. Every row below executes real IL: something is thrown,
// a filter is asked, and the value returned says which clause ran and in what order the side effects
// happened. `FilterIlShape.tests.nl` reads the emitted metadata beside these; a green row here with a
// red row there would mean the behaviour is right for the wrong reason.
test "the filter runs BEFORE a finally nested inside the protected region" {
    // THE ROW THE FEATURE EXISTS FOR. A catch-and-rethrow lowering answers
    // "inner-finally,filter,handler"; a real CLR filter block answers this.
    assert ExceptionFilters.FilterRunsBeforeInnerFinally() == "filter,inner-finally,handler"
}

test "a filter that answers false leaves the region for an outer handler" {
    assert ExceptionFilters.FalseFilterLeavesTheRegion() == "outer:9"
}

test "a guard is never asked about an exception whose type the clause did not name" {
    assert ExceptionFilters.UnmatchedTypeNeverAsks() == "outer"
}

test "between two clauses of one type the first TRUE guard wins and the second is not asked" {
    assert ExceptionFilters.FirstTrueGuardWins(3) == "low:ask-low"
    assert ExceptionFilters.FirstTrueGuardWins(30) == "high:ask-low,ask-high"
}

test "a bare catch takes a filter" {
    assert ExceptionFilters.BareFilteredCatch() == "bare-filter,bare-handler"
}

test "the binding is filled before the guard runs, so a guard reads the caught instance" {
    assert ExceptionFilters.GuardReadsTheBinding(4) == "four"
    assert ExceptionFilters.GuardReadsTheBinding(8) == "other:8"
}

test "what the filter proves is available in the handler without a second test" {
    assert ExceptionFilters.FilterNarrowsForTheHandler(true) == "inner"
    assert ExceptionFilters.FilterNarrowsForTheHandler(false) == "none"
}

test "a filtered clause and an unfiltered one of the same type fall through in declaration order" {
    assert ExceptionFilters.FilteredThenUnfiltered(1) == "one"
    assert ExceptionFilters.FilteredThenUnfiltered(2) == "fallback:2"
}

test "a finally beside a filtered catch still runs, after the filter and the handler" {
    assert ExceptionFilters.FinallyStillRuns() == "filter,handler,finally"
}

test "a bare throw inside a filtered handler still rethrows the original instance" {
    assert ExceptionFilters.RethrowFromFilteredHandler() == "rethrowing,caught:5"
}

test "a second filtered pair behaves like the first — the lowering is not once-per-method" {
    assert ExceptionFilters.SecondFilteredPair(2) == "two"
    assert ExceptionFilters.SecondFilteredPair(5) == "other"
}

test "the unfiltered control still catches, so the filter rows are not measuring a broken try" {
    assert ExceptionFilters.UnfilteredControl(11) == "caught:11"
}

test "a clause that writes a type but no binding takes a filter" {
    assert ExceptionFilters.TypeOnlyClauseTakesAFilter() == "type-only-filter,type-only-handler"
}
