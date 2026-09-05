namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic


// THE ORDER OF EVERY ROW A SYSTEMS REPORT SHOWS A USER — the single owner of a decision that used
// to be spelled four times in two languages.
//
// A systems report has three arrays and one nested list, and every one of them is read positionally
// by a shipped command: `nlc check --systems-report` prints `functions[]`, `findings[]` and
// `trustedSites[]` in list order, `nlc query trusted` prints the same trusted sites as `results[]`,
// and `nlc query perf` echoes one function's `calls[]` whole. Nothing between the analyzer and the
// JSON re-sorts: the normalization kernels and the payload builders both walk their input and
// append. **So the order decided here is schema-visible, and it is a product decision, not an
// implementation detail.**
//
// THE FOUR ORDERS, AND WHY THEY ARE NOT THE SAME ORDER.
//
// `OrderedFiles` is the analyzer's WALK order, and it is the only one of the four that is not
// itself a report array. It decides which file's declarations register first, which decides which
// function the walk enters first, which decides the order the function rows come out in — and,
// because the finding order below is a STABLE sort, it is also the tie-break between two findings
// that land on the same file, line and column. It is case-INSENSITIVE because a project's files
// come off a case-insensitive filesystem on two of the three platforms N# ships on, and a report
// whose row order flipped when a user renamed `Parser.nl` to `parser.nl` would be reporting the
// filesystem rather than the program.
//
// `OrderedFindings` is file, then line, then column, and STABLE, so two findings at the same
// position are read in the order the walk met them. That stability is behaviour, not an accident of
// the sort: a `[hot]` function that allocates twice on one line must list its two findings in the
// order the walk found them.
//
// `OrderedTrustedSites` is the same three keys for the same reason — a trusted site is a position a
// human reviews, and a reviewer reads a file top to bottom. It is a SEPARATE entry point rather
// than a generic one because a trusted site is not a finding: it has no code, no severity and no
// call path, and the two lists must be allowed to disagree later without one silently dragging the
// other.
//
// `OrderedCalls` is neither. It is case-SENSITIVE ordinal, because a call list holds NAMES —
// `Alpha2`, `Beta` and `alpha` are three different functions and N# uses case to carry visibility,
// so folding it would be folding away the thing the reader is looking at. It also DE-DUPLICATES,
// because the list answers "what does this function call", not "how many times": a hot loop calling
// `zeta()` five times records `zeta` once. The two halves are one decision and live in one door, so
// no caller can take the ordering without the de-duplication.
//
// EVERY SORT IS AN INSERTION SORT, WRITTEN OUT rather than delegated, for the reason
// `AnalyzerReferenceLoadReport.SortedOrdinal` records: comparer-routed ordinal string orders are
// not on the columnar emit surface. Writing it out satisfies both gates, gives every one of these
// orders the same proven stability, and turns a user-visible report order into a rule the reader
// can see.
class SystemsReportOrder {

    // THE ANALYZER'S FILE WALK ORDER. The caller hands over the compilation unit keys in whatever
    // order the project's file discovery produced them; this decides the order they are analysed,
    // and therefore the order `systemsReport.functions[]` is read.
    //
    // The row order is NOT simply this order, and that is worth saying at the door: the walk is
    // re-entrant, so resolving a call analyses the callee mid-walk and emits it FIRST. This decides
    // the ROOTS of that traversal; the traversal decides the rest.
    static func OrderedFiles(files: IReadOnlyList<string>): string[] {
        sorted := new List<string>()
        outer := 0
        while outer < files.Count {
            candidate := files[outer]
            position := sorted.Count
            while position > 0 && CompareOrdinalIgnoreCase(sorted[position - 1], candidate) > 0 {
                position = position - 1
            }

            sorted.Insert(position, candidate)
            outer = outer + 1
        }

        return sorted.ToArray()
    }

    // THE REPORT ORDER FOR FINDINGS: file, then line, then column — and stable. Reached through
    // `SystemsFindingSink.Ordered()`, which owns the list; this owns the order.
    static func OrderedFindings(findings: IReadOnlyList<SystemsFinding>): SystemsFinding[] {
        sorted := new List<SystemsFinding>()
        outer := 0
        while outer < findings.Count {
            candidate := findings[outer]
            position := sorted.Count
            while position > 0 && CompareFindingPosition(sorted[position - 1], candidate) > 0 {
                position = position - 1
            }

            sorted.Insert(position, candidate)
            outer = outer + 1
        }

        return sorted.ToArray()
    }

    // THE REPORT ORDER FOR TRUSTED SITES: file, then line, then column — and stable, so two sites
    // that somehow share a position keep the order the walk met them in.
    static func OrderedTrustedSites(sites: IReadOnlyList<SystemsTrustedSite>): SystemsTrustedSite[] {
        sorted := new List<SystemsTrustedSite>()
        outer := 0
        while outer < sites.Count {
            candidate := sites[outer]
            position := sorted.Count
            while position > 0 && CompareTrustedSitePosition(sorted[position - 1], candidate) > 0 {
                position = position - 1
            }

            sorted.Insert(position, candidate)
            outer = outer + 1
        }

        return sorted.ToArray()
    }

    // ONE FUNCTION'S CALL LIST: de-duplicated by exact name, then ordered by exact name. The
    // de-duplication keeps the FIRST occurrence, which is what the walk met first; the sort then
    // makes the answer independent of the walk, so two programs that call the same set of functions
    // in different orders report the same list.
    static func OrderedCalls(calls: IReadOnlyList<string>): string[] {
        distinct := new List<string>()
        index := 0
        while index < calls.Count {
            candidate := calls[index]
            seen := false
            scan := 0
            while scan < distinct.Count {
                if CompareOrdinal(distinct[scan], candidate) == 0 {
                    seen = true
                    break
                }

                scan = scan + 1
            }

            if !seen {
                distinct.Add(candidate)
            }

            index = index + 1
        }

        sorted := new List<string>()
        outer := 0
        while outer < distinct.Count {
            candidate := distinct[outer]
            position := sorted.Count
            while position > 0 && CompareOrdinal(sorted[position - 1], candidate) > 0 {
                position = position - 1
            }

            sorted.Insert(position, candidate)
            outer = outer + 1
        }

        return sorted.ToArray()
    }

    static func CompareFindingPosition(left: SystemsFinding, right: SystemsFinding): int {
        fileOrder := CompareOrdinalIgnoreCase(left.File, right.File)
        if fileOrder != 0 {
            return fileOrder
        }

        if left.Line != right.Line {
            return CompareInt(left.Line, right.Line)
        }

        return CompareInt(left.Column, right.Column)
    }

    static func CompareTrustedSitePosition(left: SystemsTrustedSite, right: SystemsTrustedSite): int {
        fileOrder := CompareOrdinalIgnoreCase(left.File, right.File)
        if fileOrder != 0 {
            return fileOrder
        }

        if left.Line != right.Line {
            return CompareInt(left.Line, right.Line)
        }

        return CompareInt(left.Column, right.Column)
    }

    static func CompareInt(left: int, right: int): int {
        if left < right {
            return -1
        }

        if left > right {
            return 1
        }

        return 0
    }

    // CASE-SENSITIVE COMPARISON BY UTF-16 CODE UNIT — precisely what `StringComparer.Ordinal` does.
    // Shorter sorts before longer when one is a prefix of the other.
    static func CompareOrdinal(left: string, right: string): int {
        limit := left.Length
        if right.Length < limit {
            limit = right.Length
        }

        index := 0
        while index < limit {
            leftUnit := left[index]
            rightUnit := right[index]
            if leftUnit != rightUnit {
                if leftUnit < rightUnit {
                    return -1
                }

                return 1
            }

            index = index + 1
        }

        return CompareInt(left.Length, right.Length)
    }

    // CASE-INSENSITIVE ORDINAL COMPARISON, BY UTF-16 CODE UNIT AFTER INVARIANT UPPERCASING — which
    // is precisely what `StringComparer.OrdinalIgnoreCase` does. Uppercasing per code unit is the
    // exact semantics and not an approximation: a surrogate has no single-unit case mapping and
    // comes back unchanged, so a path outside the basic plane orders by its raw units either way.
    // Shorter sorts before longer when one is a prefix of the other.
    static func CompareOrdinalIgnoreCase(left: string, right: string): int {
        limit := left.Length
        if right.Length < limit {
            limit = right.Length
        }

        index := 0
        while index < limit {
            leftUnit := Char.ToUpperInvariant(left[index])
            rightUnit := Char.ToUpperInvariant(right[index])
            if leftUnit != rightUnit {
                if leftUnit < rightUnit {
                    return -1
                }

                return 1
            }

            index = index + 1
        }

        return CompareInt(left.Length, right.Length)
    }
}
