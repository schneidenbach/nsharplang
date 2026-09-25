namespace NSharpLang.CensusExceptionFilters.Tests

import System.Reflection


// THE EMITTED SHAPE, read out of the assembly this project just built.
//
// The behaviour rows beside this file prove what a filtered catch DOES. These prove what it IS: the
// CLR's own exception-handling table, which records one clause per protected region and a flags word
// saying whether that clause is a typed catch, a filter, a finally or a fault. `Filter` is a bit the
// metadata either carries or does not, and a catch-and-rethrow lowering can never make it appear —
// which is exactly why this is the shape assertion worth making. Nothing here re-decodes IL bytes:
// `MethodBody.ExceptionHandlingClauses` is the runtime's own reading of the table.
class FilterIlShapeFacts {

    // The clause-flag words of one method's protected regions, joined in table order. `Clause` is 0,
    // `Filter` is 1, `Finally` is 2 and `Fault` is 4 (ECMA-335 II.25.4.6, surfaced as
    // `ExceptionHandlingClauseOptions`).
    static func ClauseFlags(methodName: string): string {
        holder := typeof(ExceptionFilters)
        method := must holder.GetMethod(methodName)
        body := must method.GetMethodBody()
        clauses := body.ExceptionHandlingClauses
        joined := ""
        index := 0
        while index < clauses.Count {
            if index > 0 {
                joined = joined + ","
            }
            joined = joined + clauses[index].Flags.ToString()
            index = index + 1
        }
        return joined
    }

    static func ClauseCount(methodName: string): int {
        holder := typeof(ExceptionFilters)
        method := must holder.GetMethod(methodName)
        body := must method.GetMethodBody()
        clauses := body.ExceptionHandlingClauses
        return clauses.Count
    }

    // Whether any clause of this method is a FILTER.
    static func HasFilterClause(methodName: string): bool {
        holder := typeof(ExceptionFilters)
        method := must holder.GetMethod(methodName)
        body := must method.GetMethodBody()
        clauses := body.ExceptionHandlingClauses
        index := 0
        while index < clauses.Count {
            if clauses[index].Flags == ExceptionHandlingClauseOptions.Filter {
                return true
            }
            index = index + 1
        }
        return false
    }
}

test "a filtered catch emits a CLR filter clause, not a typed catch clause" {
    // `GuardReadsTheBinding` writes one filtered clause and one unfiltered clause of the same type.
    // The table must therefore carry a Filter row AND a Clause row, in that written order.
    assert FilterIlShapeFacts.ClauseFlags("GuardReadsTheBinding") == "Filter,Clause"
}

test "an unfiltered catch still emits a plain typed clause" {
    assert FilterIlShapeFacts.ClauseFlags("FilteredThenUnfiltered") == "Filter,Clause"
    // The control: the same statement shape with no `when` carries no filter bit at all, so the bit
    // the rows above read is the filter's and not the try statement's.
    assert FilterIlShapeFacts.ClauseFlags("UnfilteredControl") == "Clause"
    assert !FilterIlShapeFacts.HasFilterClause("UnfilteredControl")
}

test "a bare filtered catch is a filter clause too — the missing type does not make it a catch-all row" {
    assert FilterIlShapeFacts.ClauseFlags("BareFilteredCatch") == "Filter"
}

test "two filtered clauses of one type emit two filter rows" {
    assert FilterIlShapeFacts.ClauseFlags("FirstTrueGuardWins") == "Filter,Filter"
    assert FilterIlShapeFacts.ClauseCount("FirstTrueGuardWins") == 2
}

test "a filtered catch beside a finally emits both rows, the filter first" {
    assert FilterIlShapeFacts.ClauseFlags("FinallyStillRuns") == "Filter,Finally,Clause"
}

test "the filter bit is what distinguishes the lowering — a rethrow shape would carry none" {
    assert FilterIlShapeFacts.HasFilterClause("FilterRunsBeforeInnerFinally")
    assert FilterIlShapeFacts.HasFilterClause("UnmatchedTypeNeverAsks")
    assert FilterIlShapeFacts.HasFilterClause("SecondFilteredPair")
    assert FilterIlShapeFacts.HasFilterClause("TypeOnlyClauseTakesAFilter")
}
