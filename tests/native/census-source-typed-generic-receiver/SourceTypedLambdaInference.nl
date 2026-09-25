namespace NSharpLang.CensusSourceTypedGenericReceiver.Tests

import System.Collections.Generic


// CENSUS — A GENERIC METHOD WHOSE TYPE ARGUMENTS ONLY A LAMBDA CAN DECIDE, CALLED ON AN EXTERNAL
// GENERIC CLOSED OVER A TYPE THIS COMPILATION IS WRITING.
//
// `List<Row>.ConvertAll<TOutput>(Converter<Row, TOutput>)` fixes `TOutput` from nothing but the
// lambda's body. `List<Row>` is a `TypeBuilderInstantiation` while `Row` is being emitted, so the
// contextual walk that infers `TOutput` could not ask it for `ConvertAll` at all: the call declined at
// emission after analysis had typed it, while the identical call over `List<string>` — and the
// non-generic `Exists(r => ...)` over `List<Row>` — emitted. The candidate is now read off the open
// definition `List<T>`, closed over `Row`, inferred from the lambda, and rebound onto `List<Row>`.
//
// Every spelling of the receiver reaches the same member: a local, the bare and `this.` forms inside
// a class that inherits `List<Row>`, and that class's instance from outside.
class RowLabels: List<Row> {

    func Bare(): List<string> {
        return ConvertAll(r => r.Label)
    }

    func ThroughThis(): List<string> {
        return this.ConvertAll(r => r.Label + "!")
    }
}

class SourceTypedLambdaInference {

    static func LocalLabels(): string {
        local := new List<Row>()
        local.Add(new Row("z"))
        local.Add(new Row("y"))
        labels := local.ConvertAll(r => r.Label)
        return labels[0] + labels[1]
    }

    // A value-type `TOutput`: the lambda's body decides the delegate's return, and the closed call
    // returns `List<int>`.
    static func LocalLengths(rows: List<Row>): int {
        return rows.ConvertAll(r => r.Label.Length)[0]
    }

    // `TOutput` is the source type itself, so the closed method is instantiated over the builder too.
    static func LocalRoundTrip(rows: List<Row>): string {
        return rows.ConvertAll(r => new Row(r.Label + r.Label))[0].Label
    }

    static func OutsideDerived(rows: RowLabels): string {
        return rows.ConvertAll(r => r.Label.ToUpper())[0]
    }

    // THE CONTROL. The same inference over a non-source argument always emitted.
    static func TextLengths(texts: List<string>): int {
        return texts.ConvertAll(t => t.Length)[0]
    }
}
