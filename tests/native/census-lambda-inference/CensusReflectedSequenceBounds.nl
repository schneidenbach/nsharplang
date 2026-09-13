namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic
import System.Collections.ObjectModel
import System.Linq


// A LAMBDA WHOSE RESULT IS READ OFF A REFLECTED MEMBER.
//
// The converter census wrote `safeActions.SelectMany(f => f.Edits)` nine times, where `Edits` is a
// member of a type from a referenced assembly. It reported NL402: the lambda's result carries no N#
// generic SPELLING — a member read off a reflected type is the CLR type whole — so the walk that
// folds the lambda's result into `Func<TSource, IEnumerable<TResult>>` had no type arguments to
// descend into and fixed nothing. The same member declared in SOURCE bound, which is what made the
// hole look like a LINQ problem rather than a reading problem.
//
// The reflected type is a complete shape in its own right, so the ordinary parameter-match walk now
// reads it through its interfaces and its base chain — the same reading every other argument gets.
class Bundle {
    Edits: IReadOnlyList<string>

    constructor(Edits: IReadOnlyList<string>) {
        this.Edits = Edits
    }
}

func SourceBundle(edits: List<string>): Bundle {
    return new Bundle(new ReadOnlyCollection<string>(edits))
}

// `ReadOnlyCollection<string>` is REFLECTED end to end, and it names no type parameter of the
// `IEnumerable<TResult>` parameter it has to satisfy — it reaches it through its interface list.
func ReflectedBundles(first: List<string>, second: List<string>): List<ReadOnlyCollection<string>> {
    bundles := new List<ReadOnlyCollection<string>>()
    bundles.Add(new ReadOnlyCollection<string>(first))
    bundles.Add(new ReadOnlyCollection<string>(second))
    return bundles
}

func WordsOf(rows: List<ReadOnlyCollection<string>>): List<string> {
    return rows.SelectMany(row => row).ToList()
}

func EditsOf(bundles: List<Bundle>): List<string> {
    return bundles.SelectMany(bundle => bundle.Edits).ToList()
}

// A REFLECTED member whose own type is a nested reflected collection: `Dictionary<K, V>.Keys` is a
// `KeyCollection`, which is an `IEnumerable<K>` only through its interface list.
func KeysOf(tables: List<Dictionary<string, int>>): List<string> {
    return tables.SelectMany(table => table.Keys).ToList()
}

func LengthsOf(bundles: List<Bundle>): List<int> {
    return bundles.Select(bundle => bundle.Edits.Count).ToList()
}

func BundlesOf(edits: List<string>): List<Bundle> {
    bundles := new List<Bundle>()
    bundles.Add(SourceBundle(edits))
    return bundles
}
