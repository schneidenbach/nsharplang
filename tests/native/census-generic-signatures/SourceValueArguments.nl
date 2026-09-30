namespace NSharpLang.CensusGenericSignatures

import System
import System.Collections.Generic

// A SOURCE VALUE DECLARATION IS AN ORDINARY GENERIC ARGUMENT, AND AN ORDINARY KEY.
//
// `Loc` is a plain struct and `Span` a readonly record struct. Both are written as the element of a
// `HashSet`/`IReadOnlySet` and as the key of a `Dictionary` — positions whose admission used to be
// reserved for reference declarations and for record structs registered in the live source registry.
// Equality is what a key surface is about, and the two declarations answer it differently on
// purpose: `Loc` gets `System.ValueType`'s field-wise equality, `Span` the equality a record struct
// synthesizes. The assertions read both.
struct Loc {
    Line: int
    Column: int

    constructor(line: int, column: int) {
        Line = line
        Column = column
    }
}

readonly record struct Span(Start: int, Length: int) {
}

class LocationIndex {
    readonly seen: HashSet<Loc> = new HashSet<Loc>()
    readonly spans: HashSet<Span> = new HashSet<Span>()
    readonly labels: Dictionary<Loc, string> = new Dictionary<Loc, string>()
    readonly optional: List<Loc?> = new List<Loc?>()

    func Observe(value: Loc): bool {
        return seen.Add(value)
    }

    func ObserveSpan(value: Span): bool {
        return spans.Add(value)
    }

    func Label(value: Loc, text: string) {
        labels[value] = text
    }

    func LabelOf(value: Loc): string {
        found := ""
        if labels.TryGetValue(value, out found) {
            return found
        }
        return "<none>"
    }

    func Remember(value: Loc?) {
        optional.Add(value)
    }

    func RememberedLine(index: int): int {
        entry := optional[index]
        if entry == null {
            return -1
        }
        return entry.Line
    }

    func Distinct(): int {
        return seen.Count
    }

    func DistinctSpans(): int {
        return spans.Count
    }

    // A parameter whose type closes an unmodelled read-only set head over a source value type.
    func CountAll(values: IReadOnlySet<Loc>): int {
        return values.Count
    }

    func SeenSet(): IReadOnlySet<Loc> {
        return seen
    }

    // With no target delegate on the left, the annotation itself supplies the lambda's signature.
    func NextLine(value: Loc): int {
        next := (line: int) => line + 1
        return next(value.Line)
    }

    func SumSix(): int {
        sum := (a: int, b: int, c: int, d: int, e: int, f: int) => a + b + c + d + e + f
        return sum(1, 2, 3, 4, 5, 6)
    }

    static func WrittenParameterKind(_value: object): int => 1
    static func WrittenParameterKind(_value: string): int => 2

    func CompatibleWrittenParameter(): int {
        classify: Func<string, int> = (value: object) => LocationIndex.WrittenParameterKind(value)
        return classify("text")
    }
}

class LambdaOwner<T> {
    func Echo(value: T): T {
        identity := (item: T) => item
        return identity(value)
    }
}

// A DELEGATE OVER TWO SOURCE DECLARATIONS — one a value type, one a reference type — declared as a
// field's type rather than inferred at a call site.
class Projector {
    readonly project: Func<Loc, Marker>

    constructor(project: Func<Loc, Marker>) {
        this.project = project
    }

    func Apply(value: Loc): Marker {
        return project(value)
    }
}

sealed record Marker(Text: string) {
}
