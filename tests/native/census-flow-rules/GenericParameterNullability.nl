namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Collections.Generic
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
// without it. (The LINQ half of that rule — `FirstOrDefault`/`LastOrDefault`, whose `?` is written
// as a `NullableContextAttribute(2)` on the METHOD rather than on the position — is pinned in the
// estate instead: the columnar backend does not yet emit those calls, so there is no runtime to
// assert against here.)
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
