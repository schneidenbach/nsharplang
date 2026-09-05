namespace NSharpLang.AsBoxing.Tests

// `value as Target` and `value is Target` lower to `isinst <Target>`, which reads the top of the
// evaluation stack as an OBJECT REFERENCE. Over a VALUE-typed operand that is invalid: the emitter
// used to hand `isinst` the raw value, so `(enumValue as object)` answered null and the wider value
// shapes faulted outright. A value-typed operand now BOXES first, which is the conversion C# performs
// at the same point (`5 as object` IS a box). These contracts pin all three halves of that rule:
// the boxed answer for a value operand, the legitimate NULL answers that must survive it, and the
// reference-operand `x as object` idiom the .nl estate already depends on, which must not move.
enum AsBoxColors {
    Red = 1,
    Green = 2,
    Blue = 4
}

interface AsBoxNamed {
    func Label(): string
}

interface AsBoxUnimplemented {
    func Ping(): string
}

struct AsBoxPoint: AsBoxNamed {
    X: int
    Y: int

    func Label(): string {
        return "point"
    }
}

class AsBoxCarrier: AsBoxNamed {
    Tag: string = "carrier"

    func Label(): string {
        return "carrier"
    }
}

class AsBoxUnrelated {
    Slot: int = 0
}

// `object.ToString()` is typed `string?`, so the rendering goes through one place that names both
// null answers rather than being spelled at every assertion.
func AsBoxRender(value: object?): string {
    if value == null {
        return "<null>"
    }
    rendered := value.ToString()
    if rendered == null {
        return "<null-string>"
    }
    return rendered
}

func AsBoxLabelOf(value: AsBoxNamed?): string {
    if value == null {
        return "<null>"
    }
    return value.Label()
}

// A type PARAMETER is not statically a value type, so it takes the box too — correct for every
// instantiation, because `box` over a reference type yields the reference unchanged.
func AsBoxWiden<T>(value: T): string {
    boxed := value as object
    return AsBoxRender(boxed)
}

test "an enum operand boxes through `as object` rather than answering null" {
    value := AsBoxColors.Green
    boxed := value as object

    assert boxed != null
    assert AsBoxRender(boxed) == "Green"
}

test "an int operand boxes through `as object`" {
    number := 42
    boxed := number as object

    assert boxed != null
    assert AsBoxRender(boxed) == "42"
}

test "a bool operand boxes through `as object`" {
    flag := true
    boxed := flag as object

    assert boxed != null
    assert AsBoxRender(boxed) == "True"
}

test "a double operand boxes through `as object`" {
    scaled := 4.0
    boxed := scaled as object

    assert boxed != null
    assert AsBoxRender(boxed) == "4"
}

test "a struct operand boxes through `as object`" {
    point := new AsBoxPoint { X: 1, Y: 2 }
    boxed := point as object

    assert boxed != null
    assert AsBoxRender(boxed).EndsWith("AsBoxPoint")
}

test "a struct operand boxes through `as` to an implemented interface and still dispatches" {
    point := new AsBoxPoint { X: 1, Y: 2 }
    named := point as AsBoxNamed

    assert named != null
    assert AsBoxLabelOf(named) == "point"
}

test "a value operand answers null for an interface its type does not implement" {
    point := new AsBoxPoint { X: 1, Y: 2 }
    unimplemented := point as AsBoxUnimplemented

    assert unimplemented == null
}

test "a Nullable operand boxes the value it carries" {
    present: int? = 5
    boxed := present as object

    assert boxed != null
    assert AsBoxRender(boxed) == "5"
}

test "an empty Nullable operand still answers null" {
    absent: int? = null
    boxed := absent as object

    assert boxed == null
}

test "`is` over a value operand tests the boxed reference" {
    point := new AsBoxPoint { X: 1, Y: 2 }
    isNamed := point is AsBoxNamed

    assert isNamed
}

test "`is object` over an enum operand is true rather than a fault" {
    value := AsBoxColors.Blue

    if value is object {
        assert true
    } else {
        assert false
    }
}

test "a reference operand keeps the established `as object` idiom" {
    carrier := new AsBoxCarrier()
    boxed := carrier as object

    assert boxed != null
    assert AsBoxRender(boxed).EndsWith("AsBoxCarrier")
}

test "a reference operand still answers null for an unrelated target" {
    carrier := new AsBoxCarrier()
    boxed := carrier as object
    unrelated := boxed as AsBoxUnrelated

    assert unrelated == null
}

test "a reference operand still converts to an implemented interface" {
    carrier := new AsBoxCarrier()
    named := carrier as AsBoxNamed

    assert named != null
    assert AsBoxLabelOf(named) == "carrier"
}

test "a type-parameter operand boxes under a value-type instantiation" {
    rendered := AsBoxWiden<int>(7)

    assert rendered == "7"
}

test "a type-parameter operand carries a reference instantiation through unchanged" {
    rendered := AsBoxWiden<string>("carried")

    assert rendered == "carried"
}
