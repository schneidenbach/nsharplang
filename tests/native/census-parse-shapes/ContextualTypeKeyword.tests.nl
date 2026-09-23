namespace NSharpLang.CensusParseShapes.Tests

import System.Collections.Generic
import System.Reflection


// `type` IS A CONTEXTUAL KEYWORD, AND THESE ROWS ARE THE PROOF THAT IT COMPILES AND RUNS.
//
// It was a HARD keyword, which meant no N# type could expose a member named `type` — the name
// `nlc query type` wanted, and the name a converted `QueryCommand` needed. It now opens exactly one
// production, a top-level type-alias declaration head (`type Name = Underlying` and its branded
// `type Name = newtype Underlying` form), and is an ordinary identifier everywhere else.
//
// The distinction is a LANGUAGE fact, so the rows below are written as running code rather than as
// parser goldens: a field, a property, a parameter, a local, a loop variable, a member access and a
// declaration NAME, each used for its value, plus the two alias productions that keep the word.
type RowKind = int
type RowLabel = newtype string

// A TYPE WHOSE OWN NAME IS THE WORD. It is camelCase, so it is package-private in metadata, which is
// the ordinary reading of the casing rule and not a consequence of the name.
class type {
    label: string

    constructor(label: string) {
        this.label = label
    }

    Label: string => label
}

class Row {

    // A FIELD named `type`, and a PROPERTY whose body reads it.
    type: string = "row"

    Kind: string => type

    // A PARAMETER named `type`, read for its value and combined with the field of the same name.
    func Describe(type: string): string => type + "/" + Kind

    // A LOCAL named `type`, declared, reassigned and read.
    func CountKinds(): int {
        type := 1
        type = type + 2
        return type
    }

    // A LOOP VARIABLE named `type`, over a collection whose elements it names.
    func Join(kinds: IEnumerable<string>): string {
        joined := ""
        for type in kinds {
            if joined.Length > 0 {
                joined = joined + ","
            }

            joined = joined + type
        }

        return joined
    }
}

func RowType(row: Row): string {
    // A MEMBER ACCESS whose member is the word.
    return row.type
}

test "a field, a property and a parameter may all be named `type`" {
    row := new Row()
    assert row.type == "row"
    assert row.Kind == "row"
    assert row.Describe("kind") == "kind/row"
    assert RowType(row) == "row"
}

test "a local and a loop variable may be named `type`" {
    row := new Row()
    assert row.CountKinds() == 3

    kinds: string[] = ["a", "b", "c"]
    assert row.Join(kinds) == "a,b,c"
}

test "a declared type may be named `type`" {
    value := new type("branded")
    assert value.Label == "branded"
    assert value.GetType().Name == "type"
}

test "the two productions that keep the word still declare their types" {
    // A TRANSPARENT alias is interchangeable with its underlying type.
    kind: RowKind = 7
    assert kind == 7

    // A BRANDED newtype is not, so it is constructed and read back.
    label := new RowLabel("orders")
    assert label.Value == "orders"
}

test "the member named `type` is what the emitted assembly carries" {
    // READ BACK FROM METADATA, because "it compiled" is not the claim: the CLR member really is
    // named `type`, so a consumer — including `nlc query` — can find it under that name.
    rowType := typeof(Row)
    field := rowType.GetField("type", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
    assert field != null
    assert field.Name == "type"

    describe := rowType.GetMethod("Describe", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
    assert describe != null
    parameters := describe.GetParameters()
    assert parameters.Length == 1
    assert parameters[0].Name == "type"
}
