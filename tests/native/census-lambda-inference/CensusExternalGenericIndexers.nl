namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic
import System.Linq
import System.Numerics


// A LAMBDA WHOSE BODY READS A CONSTRUCTED EXTERNAL GENERIC'S INDEXER.
//
// `names.Select(n => v[n.Length])` over a `Vector<int>` reported NL402 ("No overload of 'Select'
// accepts 1 argument with these types"). The index arm named the element of an array, a string and
// the collections it recognises by NAME — `List`, `Dictionary`, `Collection` — and answered `unknown`
// for every other generic, so the lambda had no return type to fix `TResult` with. The same read
// outside a lambda compiled only because `unknown` is assignable everywhere. The element now comes
// from the definition's own indexer, with the receiver's spelled arguments substituted.
record Tag {
    Name: string
}

func LaneValues(v: Vector<int>, names: List<string>): List<int> {
    return names.Select(n => v[n.Length]).ToList()
}

func FirstLane(v: Vector<int>, names: List<string>): int {
    return names.Select(n => v[n.Length]).First()
}

// A SOURCE-typed argument has only a surrogate CLR type while it is being emitted; the element must
// still be `Tag`, or `.Name` would not resolve.
func TagNames(segment: ArraySegment<Tag>, positions: List<int>): List<string> {
    return positions.Select(p => segment[p].Name).ToList()
}
