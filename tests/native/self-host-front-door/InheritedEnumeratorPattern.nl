namespace NSharpLang.SelfHostFrontDoor

import System.Collections.Generic
import System.Collections.ObjectModel

// THE SHAPE THAT STOPPED THE COMPILER FROM COMPILING ITSELF.
//
// `for row in rows` over a collection whose `GetEnumerator` is INHERITED asks the code generator to
// rebind that method onto a closed owner built over a type this very assembly is still emitting.
// Reflection answers the inherited method with its declaring type CONSTRUCTED OVER GENERIC
// PARAMETERS -- `Collection<T>` reached from `ObservableCollection<T>`, not the `Collection<>`
// definition -- and `TypeBuilder.GetMethod` accepts ONLY a method declared on the definition. The
// compiler used to hand it the constructed one and DIE with "The specified method cannot be dynamic
// or global and must be declared on a generic type definition", with no member named and no source
// span, inside 412K lines of its own source.
//
// `Row` is declared HERE on purpose: a source type is a `TypeBuilder` while this assembly is being
// emitted, which is the only thing that puts the loop on the builder-bound rebinding path at all. A
// `foreach` over `ObservableCollection<int>` never reaches it.
class Row {
    Value: int
    Label: string

    constructor(value: int, label: string) {
        Value = value
        Label = label
    }
}

class InheritedEnumeratorPattern {
    static func Rows(): ObservableCollection<Row> {
        // The collection is filled through its CONSTRUCTOR rather than `Add`, because
        // `ObservableCollection<T>.Add` is inherited from `Collection<T>` too and the instance-call
        // planner does not yet resolve an inherited member on a construction over a source type --
        // the same family as the loop below, one door further along. Recorded here rather than
        // worked around silently.
        seed := new List<Row>()
        seed.Add(new Row(2, "two"))
        seed.Add(new Row(3, "three"))
        seed.Add(new Row(7, "seven"))
        return new ObservableCollection<Row>(seed)
    }

    static func RowsOf(values: List<Row>): ObservableCollection<Row> {
        return new ObservableCollection<Row>(values)
    }

    static func SumValues(rows: ObservableCollection<Row>): int {
        total := 0
        for row in rows {
            total += row.Value
        }
        return total
    }

    static func JoinLabels(rows: ObservableCollection<Row>): string {
        joined := ""
        for row in rows {
            if joined.Length > 0 {
                joined += ","
            }
            joined += row.Label
        }
        return joined
    }

    // The same rebind through a READ-ONLY view, whose `GetEnumerator` is inherited from
    // `ReadOnlyCollection<T>` rather than `Collection<T>` -- a second base, one rule.
    static func SumReadOnly(rows: ObservableCollection<Row>): int {
        total := 0
        view := new ReadOnlyObservableCollection<Row>(rows)
        for row in view {
            total += row.Value
        }
        return total
    }
}
