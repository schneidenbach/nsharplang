namespace NSharpLang.CensusParseShapes.Tests

import System
import System.Collections.Generic
import System.Linq
import System.Reflection
import System.Runtime.CompilerServices


// AN ELEMENT NAME IS NEVER LOST BY MOVING THE VALUE.
//
// Element names have no CLR identity: `(Item: string, Ranges: List<int>)` IS
// `ValueTuple<string, List<int>>`, and the names live in a `TupleElementNamesAttribute` on whichever
// POSITION declared them. A body can therefore only learn a name by walking back to the written type
// the value came out of -- and that walk used to stop at three ordinary links, so the SAME chain
// written in one expression compiled while the version broken over two statements did not:
//
//   1. A LOCAL BINDING. `vals := groups.Values` binds a `ValueCollection<...>`, a shape no annotation
//      ever named, and the walk had nothing left to follow. Storing a value in a local is not a place
//      a name can be lost, so a local whose own type declares nothing now remembers where its value
//      came from and the walk continues through it.
//   2. A FIELD OR PROPERTY OF THIS COMPILATION'S OWN TYPES. `holder.Pairs["k"].Ranges` was claimed by
//      the instance-member planner, which could only start a chain at a bare identifier, so the name
//      failed to resolve and the whole expression declined -- while `pairs["k"].Ranges` compiled.
//   3. A GENERIC FUNCTION'S INFERRED RETURN. `Echo(row)` declared as `func Echo<T>(value: T): T`
//      answers the tuple `row` is, names and all, because a tuple type INCLUDES its element names and
//      inference gives `T` the argument's own type. The written return canonical is `T`, which names
//      nothing, and that empty answer used to win over the argument's.
//
// A TUPLE IS ALSO AN ARRAY'S ELEMENT TYPE. The tuple syntax was admitted at every declared position
// except that one, so `rows: (Item: string, Count: int)[]` declined at emit -- and the labelled walk
// already knew how to read an array's element names, which nothing could reach.
//
// Every row below executes real emitted IL.

// ---------------------------------------------------------------- the shapes
class GroupHolder {
    Pairs: Dictionary<string, (Item: string, Ranges: List<int>)>
    Rows: (Item: string, Count: int)[]
    Bounds: (Min: int, Max: int)[] => [(1, 2), (3, 4)]

    constructor() {
        Pairs = new Dictionary<string, (Item: string, Ranges: List<int>)>()
        Rows = [("a", 1), ("b", 2)]
    }
}

func NewHolder(): GroupHolder {
    holder := new GroupHolder()
    ranges := new List<int>()
    ranges.Add(7)
    ranges.Add(9)
    holder.Pairs["k"] = ("value", ranges)
    return holder
}

// 1. A LOCAL BINDING IS WALKED THROUGH.
func RangeCountThroughLocals(groups: Dictionary<string, (Item: string, Ranges: List<int>)>): int {
    vals := groups.Values
    first := vals.First()
    return first.Ranges.Count
}

// The same broken chain, finished by a foreach over the intermediate local.
func TotalThroughLocalForeach(groups: Dictionary<string, (Item: string, Ranges: List<int>)>): int {
    vals := groups.Values
    total := 0
    for group in vals {
        total = total + group.Ranges.Count
    }

    return total
}

// A local that copies another local keeps the names it was copied from.
func ItemThroughCopiedLocal(groups: Dictionary<string, (Item: string, Ranges: List<int>)>): string {
    first := groups["k"]
    copied := first
    return copied.Item
}

// 2. A FIELD IS A LINK IN THE CHAIN, NOT A DEAD END.
func RangeCountThroughField(holder: GroupHolder): int {
    return holder.Pairs["k"].Ranges.Count
}

// The chain rooted at the field, broken over the two statements a converter writes.
func RangeCountThroughFieldAndLocal(holder: GroupHolder): int {
    vals := holder.Pairs.Values
    first := vals.First()
    return first.Ranges.Count
}

// 3. A GENERIC FUNCTION'S INFERRED RETURN IS THE ARGUMENT IT CAME FROM.
func Echo<T>(value: T): T {
    return value
}

// Two parameter positions declared with the SAME type parameter cannot say which argument the result
// came from, so the call says nothing and the read stays positional.
func Either<T>(left: T, _right: T): T {
    return left
}

func CountThroughInferredReturn(): int {
    let row: (Item: string, Count: int) = ("a", 4)
    echoed := Echo(row)
    return echoed.Count
}

func CountThroughAmbiguousInference(): int {
    let row: (Item: string, Count: int) = ("a", 4)
    let other: (Item: string, Count: int) = ("b", 5)
    picked := Either(row, other)
    return picked.Item2
}

// 4. A TUPLE IS AN ARRAY'S ELEMENT TYPE.
func RowsLocal(): int {
    let rows: (Item: string, Count: int)[] = [("a", 1), ("b", 5)]
    rows[1] = ("cd", 7)
    return rows[1].Count + rows[1].Item.Length
}

func RowItemOfField(holder: GroupHolder): string {
    return holder.Rows[1].Item
}

func BoundsMaxOfProperty(holder: GroupHolder): int {
    return holder.Bounds[1].Max
}

// A foreach over an array of tuples reads the element names the array's written type gave.
func TotalOfRows(rows: (Item: string, Count: int)[]): int {
    total := 0
    for row in rows {
        total = total + row.Count
    }

    return total
}

// ---------------------------------------------------------------- by-ref positions

// A NAMED tuple and a positional one are ONE type in an `out` position: names are an annotation the
// CLR never sees, so `out` accepts a local whose names differ from the dictionary's value type -- and
// the local keeps ITS OWN names for reading, because those are what its annotation wrote.
func OutWithDifferentNames(groups: Dictionary<string, (Item: string, Ranges: List<int>)>): int {
    let found: (Label: string, Lines: List<int>) = default
    if !groups.TryGetValue("k", out found) {
        return -1
    }

    return found.Lines.Count
}

// The `ValueTuple<...>` spelling of the same position is the same type again.
func OutWithValueTupleSpelling(groups: Dictionary<string, (Item: string, Ranges: List<int>)>): int {
    found: ValueTuple<string, List<int>> = default
    if !groups.TryGetValue("k", out found) {
        return -1
    }

    return found.Item2.Count
}

// And the mirror: a NAMED local against a dictionary whose value type was written positionally.
func OutIntoNamedLocal(groups: Dictionary<string, ValueTuple<string, int>>): int {
    let found: (Item: string, Count: int) = default
    if !groups.TryGetValue("k", out found) {
        return -1
    }

    return found.Count
}

// A SOURCE SIGNATURE MAY BE WRITTEN IN EITHER SPELLING. A parameter and a return resolve through the
// substitution rebuild rather than the plain walk, and that rebuild used to hand back a SECOND
// representation of `ValueTuple`N` -- so a `ValueTuple<...>`-written signature disagreed with the
// tuple spelling at every call site, while the same annotation on a LOCAL agreed.
func TakeValueTupleRows(rows: List<ValueTuple<string, int>>): int {
    return rows.Count
}

func TakeValueTupleRow(row: ValueTuple<string, int>): int {
    return row.Item2
}

func TakeValueTupleGroups(groups: Dictionary<string, ValueTuple<string, int>>): int {
    return groups.Count
}

func ReturnValueTupleRow(): ValueTuple<string, int> {
    let row: (Item: string, Count: int) = ("a", 9)
    return row
}

func Bump(ref row: (Item: string, Count: int)) {
    row = (row.Item, row.Count + 1)
}

func RefWithDifferentNames(): int {
    let row: (Left: string, Right: int) = ("a", 1)
    Bump(ref row)
    return row.Right
}

// A generic ARGUMENT matches on the CLR type, so two spellings of one tuple are interchangeable.
func GenericArgumentIdentity(): int {
    rows := new List<(Left: string, Right: int)>()
    rows.Add(("a", 6))
    renamed: List<(Item: string, Count: int)> = rows
    return renamed[0].Count
}

// A named tuple in an ARGUMENT position accepts a differently-named value.
func TakeRow(row: (Item: string, Count: int)): int {
    return row.Count
}

func ArgumentIdentity(): int {
    let row: (Left: string, Right: int) = ("a", 8)
    return TakeRow(row)
}

// ---------------------------------------------------------------- reading the metadata back

func HolderFieldType(name: string): Type {
    found := typeof(GroupHolder).GetField(name)
    if found == null {
        throw new InvalidOperationException("'" + name + "' was not found.")
    }

    return found.FieldType
}

func BindingNameAt(declared: TupleElementNamesAttribute, index: int): string {
    transformed := declared.get_TransformNames()
    try {
        value := transformed[index]
        if value == null {
            return "-"
        }

        return value
    } catch e: ArgumentOutOfRangeException {
        return "<end>"
    }
}

func BindingNameRowOf(attributes: object[]): string {
    if attributes.Length != 1 {
        return "<none>"
    }

    declared := attributes[0] as TupleElementNamesAttribute
    if declared == null {
        return "<none>"
    }

    row := ""
    index := 0
    while index < 32 {
        element := BindingNameAt(declared, index)
        if element == "<end>" {
            return row
        }

        if index > 0 {
            row = row + "/"
        }

        row = row + element
        index = index + 1
    }

    return row
}

func HolderFieldNameRow(name: string): string {
    found := typeof(GroupHolder).GetField(name)
    if found == null {
        throw new InvalidOperationException("'" + name + "' was not found.")
    }

    return BindingNameRowOf(found.GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

func HolderPropertyNameRow(name: string): string {
    found := typeof(GroupHolder).GetProperty(name)
    if found == null {
        throw new InvalidOperationException("'" + name + "' was not found.")
    }

    return BindingNameRowOf(found.GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

// ---------------------------------------------------------------- the contracts

test "an element name survives an intermediate local" {
    holder := NewHolder()
    assert RangeCountThroughLocals(holder.Pairs) == 2
    assert TotalThroughLocalForeach(holder.Pairs) == 2
    assert ItemThroughCopiedLocal(holder.Pairs) == "value"
}

test "an element name survives a field hop" {
    holder := NewHolder()
    assert RangeCountThroughField(holder) == 2
    assert RangeCountThroughFieldAndLocal(holder) == 2
}

test "a generic function's inferred return keeps the argument's element names" {
    assert CountThroughInferredReturn() == 4

    // An inference with two candidate positions says nothing, and the positional spelling still reads.
    assert CountThroughAmbiguousInference() == 4
}

test "a tuple may be an array's element type" {
    assert RowsLocal() == 9

    holder := NewHolder()
    assert RowItemOfField(holder) == "b"
    assert holder.Rows[0].Count == 1
    assert BoundsMaxOfProperty(holder) == 4

    let rows: (Item: string, Count: int)[] = [("a", 2), ("b", 3)]
    assert TotalOfRows(rows) == 5

    // The array IS an array of the bare `ValueTuple`, which is why the names need an attribute at all.
    assert HolderFieldType("Rows") == typeof(ValueTuple<string, int>[])
    assert HolderFieldNameRow("Rows") == "Item/Count"
    assert HolderPropertyNameRow("Bounds") == "Min/Max"
}

test "tuple identity ignores element names in every position" {
    holder := NewHolder()

    // `out`, in both spellings and in both directions.
    assert OutWithDifferentNames(holder.Pairs) == 2
    assert OutWithValueTupleSpelling(holder.Pairs) == 2

    positional := new Dictionary<string, ValueTuple<string, int>>()
    positional["k"] = ("a", 3)
    assert OutIntoNamedLocal(positional) == 3

    // `ref`, a generic argument, and an ordinary argument.
    assert RefWithDifferentNames() == 2
    assert GenericArgumentIdentity() == 6
    assert ArgumentIdentity() == 8
}

test "a signature written with ValueTuple is the tuple it spells" {
    // The tuple spelling flows into a `ValueTuple<...>`-written parameter, bare and nested inside a
    // generic argument alike.
    let row: (Item: string, Count: int) = ("a", 7)
    assert TakeValueTupleRow(row) == 7

    rows := new List<(Item: string, Count: int)>()
    rows.Add(("a", 1))
    rows.Add(("b", 2))
    assert TakeValueTupleRows(rows) == 2

    groups := new Dictionary<string, (Item: string, Count: int)>()
    groups["k"] = ("a", 1)
    assert TakeValueTupleGroups(groups) == 1

    // And back out of a `ValueTuple<...>`-written return into the tuple spelling.
    let returned: (Item: string, Count: int) = ReturnValueTupleRow()
    assert returned.Count == 9

    // The CLR agrees, which is the whole reason the analyzer must.
    assert typeof(ValueTuple<string, int>) == typeof((string, int))
}
