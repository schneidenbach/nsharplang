namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// WHEN A FAILED REFERENCE LOAD IS WORTH TELLING THE USER ABOUT.
//
// Loading reference assemblies is best-effort: the analyzer probes a lot of paths and some of them
// legitimately miss. Reporting every miss would bury a healthy build in noise. Reporting none of them
// would leave the single most confusing failure in the compiler undiagnosable — a reference that did
// not load produces "type not found" on types that plainly exist, and the user has no way to connect
// the two.
//
// THE RULE IS THE PAIRING, AND IT IS THE WHOLE POLICY: surface NL923 for every recorded load failure
// IF AND ONLY IF this analysis ALSO produced at least one unresolved-type error. A healthy
// compilation stays completely quiet even when a probe failed along the way; a broken one names every
// assembly that might be the cause. The two halves of the question are asked in the cheap order — the
// failure tables are checked first, because they are usually empty, and the diagnostic list is only
// scanned when there is something to say.
//
// TWO FAILURE TABLES, AND WHICH ONE WINS IS A RULE. The analyzer records failures itself, and the
// metadata resolver records its own; an identity can appear in both with different detail text. The
// ANALYZER's detail wins, because it describes the failure at the point the compiler actually needed
// the assembly, while the resolver's describes a probe. That is why the merge adds the resolver's
// entries with a try-add rather than an overwrite.
//
// THE REPORT ORDER IS ORDINAL BY ASSEMBLY IDENTITY, not the order the failures happened in. Load
// order depends on which type was mentioned first in the file, so a stable alphabetical list is the
// only order a user can predict — and it is what the C# original's `SortedDictionary` produced.
//
// Every report lands at line 1, column 1: the failure belongs to the compilation, not to any line of
// it, and pinning it to the first line is what puts it at the top of the list.
//
// This owner is NOT rebuilt with the metadata-load-context SCC. It holds the analyzer's own failure
// table BY REFERENCE, because the assembly-loading surface (task 021's) writes into that same table
// throughout the analysis; a snapshot would be empty. The RESOLVER's table arrives as an argument
// instead, because the resolver itself is replaced when the load context is rebuilt.
class AnalyzerReferenceLoadReport {
    diagnostics: AnalyzerDiagnosticSink

    // The analyzer's LIVE failure table, held by reference and never resnapshotted.
    referenceLoadFailures: Dictionary<string, string>

    constructor(diagnosticSink: AnalyzerDiagnosticSink, failures: Dictionary<string, string>) {
        diagnostics = diagnosticSink
        referenceLoadFailures = failures
    }

    // One call per analysis, at the very end. `resolverFailures` is the metadata resolver's own table,
    // or null when no resolver was built for this analysis.
    func Report(resolverFailures: Dictionary<string, string>?) {
        resolverCount := 0
        if resolverFailures != null {
            resolverCount = resolverFailures.Count
        }

        if referenceLoadFailures.Count == 0 && resolverCount == 0 {
            return
        }

        if !diagnostics.HasUnresolvedTypeError() {
            return
        }

        merged := new Dictionary<string, string>(StringComparer.Ordinal)
        for entry in referenceLoadFailures {
            merged[entry.Key] = entry.Value
        }

        if resolverFailures != null {
            for entry in resolverFailures {
                if !merged.ContainsKey(entry.Key) {
                    merged[entry.Key] = entry.Value
                }
            }
        }

        collected := new List<string>()
        for entry in merged {
            collected.Add(entry.Key)
        }

        identities := SortedOrdinal(collected)

        position := 0
        while position < identities.Count {
            identity := identities[position]
            detail := merged[identity]
            diagnostics.Warn(ErrorCode.ReferenceLoadFailure, "Reference assembly '" + identity + "' could not be loaded or fully inspected (" + detail + "); types from it may be reported as not found.", 1, 1, null, 0)
            position = position + 1
        }
    }

    // ORDINAL ASCENDING, WRITTEN OUT RATHER THAN DELEGATED.
    //
    // An insertion sort, which is the right shape for this list: it is empty on every healthy
    // compilation and holds a handful of entries on a broken one, and it is STABLE, so two identities
    // that compare equal keep the order the merge gave them.
    //
    // It is written here rather than handed to a comparer for a reason worth recording: FOUR routes
    // to an ordinal string order were measured against the pinned toolset and three of them decline.
    // `Array.Sort(T[], int, int, IComparer<T>)` emits but trips NL402 on `nlc check` (the analyzer's
    // overload table does not carry it — the same finding stands today on `BatchQueryKernels.nl`);
    // `Array.Sort(T[], IComparer<T>)`, `string.CompareOrdinal` and `StringComparer.Ordinal.Compare`
    // are not on the columnar emit surface at all. Writing the order out satisfies both gates, and
    // turns a user-visible report order into a rule the reader can see rather than one inherited.
    func SortedOrdinal(names: List<string>): List<string> {
        sorted := new List<string>()
        outer := 0
        while outer < names.Count {
            candidate := names[outer]
            position := sorted.Count
            while position > 0 && CompareOrdinal(sorted[position - 1], candidate) > 0 {
                position = position - 1
            }

            sorted.Insert(position, candidate)
            outer = outer + 1
        }

        return sorted
    }

    // ORDINAL COMPARISON, BY UTF-16 CODE UNIT — which is precisely what `StringComparer.Ordinal`
    // does. Shorter sorts before longer when one is a prefix of the other.
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

        if left.Length < right.Length {
            return -1
        }

        if left.Length > right.Length {
            return 1
        }

        return 0
    }
}
