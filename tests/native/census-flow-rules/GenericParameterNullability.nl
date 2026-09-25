namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Collections.Generic
import System.Linq
import System.Threading.Tasks


// THE SOURCE SHAPES A SUBSTITUTED TYPE PARAMETER MAKES LEGAL, compiled and RUN by the tip compiler.
//
// Every function here dereferences the result of an EXTERNAL member whose declared type is a bare
// type parameter, substituted by a non-nullable reference argument. Each one reported NL905
// "Possible null dereference" before the substitution rule landed — `Lazy<T>.Value` was the
// converted CLI's ten sites and `Predicate<T>`'s parameter the one that made every
// `xs.Find(s => s.Length > 0)` lambda parameter maybe-null — so the fact that this file COMPILES is
// the contract, and the assertions in the sibling `.tests.nl` are what proves the answers are also
// right at run time.
//
// The other half is below: a position the member annotated `T?` stays maybe-null after the
// substitution, so it has to be guarded. `FindOrEmpty` does the guarding, and would not compile
// without it.
//
// AND THE THIRD HALF, at the bottom of this file: `T?` ON AN UNCONSTRAINED PARAMETER IS A REFERENCE
// ANNOTATION, so a VALUE argument erases it. `List<DateTime>.Find` answers a `DateTime`, not a
// `DateTime?`, and needs no guard at all — while `List<string>.Find` still does.
func LazyValueLength(box: Lazy<string>): int {
    return box.Value.Length
}

func TaskResultLength(pending: Task<string>): int {
    return pending.Result.Length
}

func TupleItemLength(pair: Tuple<string, int>): int {
    return pair.Item1.Length
}

func StackPeekLength(items: Stack<string>): int {
    return items.Peek().Length
}

func DictionaryIndexerLength(lookup: Dictionary<string, string>): int {
    return lookup["key"].Length
}

func ListIndexerLength(items: List<string>): int {
    return items[0].Length
}

// A `Predicate<T>` lambda's PARAMETER is a bare type parameter too, and `s` read as maybe-null.
func CountNonEmpty(items: List<string>): int {
    matches := items.FindAll(s => s.Length > 0)
    return matches.Count
}

// A VALUE argument substitutes without acquiring a nullable shell of its own.
func LazyIntValue(box: Lazy<int>): int {
    return box.Value
}

// ── the other direction: `T?` survives the substitution ────────────────────────────────────────

// `List<T>.Find` returns `T?` — an annotation on the position itself (`NullableAttribute(2)`).
func FindOrEmpty(items: List<string>): string {
    found := items.Find(s => s.Length > 2)
    if found == null {
        return ""
    }

    return found
}

// ── the fixtures, built here because a test body is a smaller source surface ────────────────────

func NullabilityLazyText(): Lazy<string> {
    factory: Func<string> = () => "abcd"
    return new Lazy<string>(factory)
}

func NullabilityLazyNumber(): Lazy<int> {
    factory: Func<int> = () => 7
    return new Lazy<int>(factory)
}

func NullabilityCompletedText(text: string): Task<string> {
    return Task.FromResult(text)
}

func NullabilityPair(text: string, value: int): Tuple<string, int> {
    return new Tuple<string, int>(text, value)
}

// ── `T?` ON AN UNCONSTRAINED PARAMETER ERASES FOR A VALUE ARGUMENT ──────────────────────────────
//
// C#'s `T?` on an unconstrained type parameter says "may be the default" and has no runtime form:
// for `T = string` it is a maybe-null `string`, and for `T = DateTime` it is a plain `DateTime`
// whose absent value is `default`. `Enumerable.FirstOrDefault` writes that `?` as a
// `NullableContextAttribute(2)` on the METHOD, `List<T>.Find` as a `NullableAttribute(2)` on the
// return position, and `Dictionary<K, V>.TryGetValue` as a `[MaybeNullWhen(false)]` postcondition;
// all three erase the same way.
//
// The census site was `times.OrderBy(kvp => kvp.Value).FirstOrDefault()` over a
// `Dictionary<string, DateTime>`: the result read as `KeyValuePair<string, DateTime>?`, so
// `.Value` bound as the NULLABLE UNWRAP instead of as the pair's own `Value` property, and the
// function reported NL202 "should return DateTime but returns KeyValuePair<string, DateTime>" plus
// NL907. Every function below would need a guard it should not need if the erasure were missing,
// so compiling is half the contract and the answers are the other half.

func EarliestEntryYear(times: Dictionary<string, DateTime>): int {
    ordered := times.OrderBy(kvp => kvp.Value).FirstOrDefault()
    return ordered.Value.Year
}

func FirstMomentYear(moments: List<DateTime>): int {
    return moments.FirstOrDefault().Year
}

func LastMomentYear(moments: List<DateTime>): int {
    return moments.LastOrDefault().Year
}

func OnlyMomentYear(moments: List<DateTime>): int {
    return moments.SingleOrDefault().Year
}

func FoundMomentYear(moments: List<DateTime>): int {
    return moments.Find(moment => moment.Year > 2000).Year
}

// `CollectionExtensions.GetValueOrDefault` and `Dictionary<K, V>.TryGetValue`'s `out` write the same
// `?` two other ways — a `NullableAttribute(2)` on the return, and a `[MaybeNullWhen(false)]`
// postcondition — and both erase for a value element, INCLUDING a struct this compilation declares.
//
// (`tallies.Find(t => t.Count > 1)` over a `List<Tally>` says the same thing and now emits too —
// an external generic closed over a SOURCE type, called with a lambda, reads its candidates off the
// open definition. `GenericLiftedReturns` pins that half.)
struct Tally {
    Count: int
}
func LookupYear(times: Dictionary<string, DateTime>, key: string): int {
    return times.GetValueOrDefault(key).Year
}

func LookupTallyCount(tallies: Dictionary<string, Tally>, key: string): int {
    found := new Tally { Count: 0 }
    if tallies.TryGetValue(key, out found) {
        return found.Count
    }

    return -1
}

// A REFERENCE argument keeps the annotation, which is what makes this the same rule rather than
// "value types are never maybe-null".
func FirstWordOrEmpty(words: List<string>): string {
    found := words.FirstOrDefault()
    if found == null {
        return ""
    }

    return found
}

// A SOURCE GENERIC WRITES THE SAME `T?` AND MEANS THE SAME THING.
func FirstOrDefaultOf<T>(items: T[]): T? {
    if items.Length > 0 {
        return items[0]
    }

    return default
}

// A `struct` CONSTRAINT SPELLS A REAL `Nullable<T>`, and the CLR writes that one as `Nullable<T>`
// in metadata — it is not the same type as the annotation above and does not erase. That half is
// pinned beside this one, in `GenericLiftedReturns`: the declaration's own metadata, and the calls
// that read the lifted result at every position.

func FirstNumber(values: int[]): int {
    return FirstOrDefaultOf(values)
}

func FirstWord(words: string[]): string {
    found := FirstOrDefaultOf(words)
    if found == null {
        return "<none>"
    }

    return found
}
