namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic
import System.Linq


// AN EXTERNAL GENERIC CLOSED OVER A TYPE THIS COMPILATION IS WRITING.
//
// `Lazy<Feed>` for a source class `Feed` converts to no CLR type at all while `Feed` is still a
// builder, so three things the census wrote declined for the same reason:
//
//   * `static readonly packed: Lazy<Feed> = new Lazy<Feed>(build)` reported NL411 "must be called or
//     passed to a delegate", because the constructor position had no expected delegate type to hand
//     the method group;
//   * `new Lazy<Query>(MakeQuery)` reported the same for a free function;
//   * `.Value` on either declined at emit, because a member of such a receiver could not be reached.
//
// The DEFINITION answers all three: `Lazy<T>`'s constructors and its `Value` getter are complete
// reflected shapes spelled in `T`, and the instantiation supplies `T`.
class Feed {
    Path: string = "feed"
}

class Query {
    Text: string = "q"

    func Lookup(text: string): string {
        return text + Text
    }
}

// A STATIC FIELD INITIALIZER naming a static method of its OWN class, declared LATER in the file.
class Holder {
    static readonly packed: Lazy<Feed> = new Lazy<Feed>(build)

    static Current: Feed => packed.Value

    static func build(): Feed {
        return new Feed()
    }
}

func LazyFromGroup(): Lazy<Query> {
    return new Lazy<Query>(MakeQuery)
}

func LazyFromLambda(): Lazy<Query> {
    return new Lazy<Query>(() => new Query())
}

func MakeQuery(): Query {
    return new Query()
}

func MakeInt(): int {
    return 7
}

func LazyOfInt(): Lazy<int> {
    return new Lazy<int>(MakeInt)
}

// A METHOD GROUP NAMING A METHOD OF THE ENCLOSING TYPE. The census site is
// `g.TypeArguments.Select(formatTypeRef)` inside the class that declares `formatTypeRef`, and its
// parameter is NULLABLE while the sequence's element is not — a conversion the delegate signature
// admits, and the one the overload scorer used to refuse.
class Symbols {
    Prefix: string = "<"

    static func formatTypeRef(name: string?): string? {
        if name == null {
            return null
        }

        return "<" + name + ">"
    }

    static func FormatAll(names: List<string>): List<string?> {
        return names.Select(formatTypeRef).ToList()
    }

    func Decorate(name: string): string {
        return Prefix + name
    }

    func DecorateAll(names: List<string>): List<string> {
        return names.Select(Decorate).ToList()
    }

    // TWO OVERLOADS OF ONE NAME: which one the delegate selects is the delegate's own signature.
    // Exactly one of them is applicable to each delegate below, which is C#'s own rule for when a
    // method group is convertible at all.
    static func Widen(value: int): string {
        return value.ToString()
    }

    static func Widen(value: string): string {
        return value
    }

    static func WidenFromInt(): Func<int, string> {
        widening: Func<int, string> = Widen
        return widening
    }

    static func WidenFromText(): Func<string, string> {
        widening: Func<string, string> = Widen
        return widening
    }

    // The CALLED method's own overload set is the other half of the question: `Select` declares both
    // `(TSource) -> TResult` and `(TSource, int) -> TResult`, and a one-parameter group picks the
    // first without ambiguity.
    static func IndexedAll(values: List<string>): List<string> {
        return values.Select(WithIndex).ToList()
    }

    static func WithIndex(value: string, index: int): string {
        return index.ToString() + value
    }
}

// THE LINQ SURFACE WITH NESTED-SEQUENCE RESULTS, which analyses and now emits end to end.
class Fix {
    Edits: List<string> = new List<string>()
}

func FlattenEdits(fixes: List<Fix>): List<string> {
    return fixes.SelectMany(fix => fix.Edits).ToList()
}

func GroupedByLength(values: List<string>): List<string> {
    return values.GroupBy(value => value.Length, (key, items) => key.ToString() + ":" + items.Count().ToString()).ToList()
}

func Zipped(left: List<int>, right: List<int>): List<int> {
    return left.Zip(right, (first, second) => first * second).ToList()
}

func AggregatedFrom(seed: int, values: List<int>): int {
    return values.Aggregate(seed, (running, value) => running + value)
}

// A TYPE PARAMETER CONSTRAINED TO AN INTERFACE IS THAT INTERFACE, INCLUDING FOR A LAMBDA ARGUMENT.
// `T` has no members of its own and no reflectable interface list, so the receiver was matched
// against nothing and the call's callee was never resolved to a signature: all three of these
// reported NL203 "I can't figure out the type of lambda parameter 'i'" while the no-argument form
// (`items.Count()`) resolved. The `where` clause is what types them.
func WidestOf<T>(items: T): int where T: IEnumerable<string> {
    return items.Max(item => item.Length)
}

func LongCountOf<T>(items: T): int where T: IEnumerable<string> {
    return items.Count(item => item.Length > 2)
}

func UpperJoined<T>(items: T): string where T: IEnumerable<string> {
    return string.Join(",", items.Select(item => item.ToUpperInvariant()))
}

func CountOfConstrained<T>(items: T): int where T: IEnumerable<string> {
    return items.Count()
}

func WordArray(): string[] {
    return ["alpha", "be", "gamma"]
}
