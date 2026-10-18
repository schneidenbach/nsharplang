namespace NSharpLang.NullableConversions.Tests

import System

record Stamped {
    When: DateTime?
}

// `??` over two nullable operands is itself nullable (C#: the right operand's type is `T?`, so the
// result is `T?`, not the unwrapped `T`).
func CoalesceLocal(a: double?, b: double?): double? {
    c: double? = a ?? b
    return c
}

func CoalesceReturn(a: double?, b: double?): double? {
    return a ?? b
}

func CoalesceChain(a: int?, b: int?, c: int?): int? => a ?? b ?? c

func CoalesceBody(a: DateTime?, b: DateTime?): DateTime? => a ?? b

func CoalesceToValue(a: double?, b: double?): double {
    return (a ?? b) ?? -1.0
}

// The control: a non-nullable right operand still unwraps.
func CoalesceUnwrapped(a: double?): double => a ?? 0.5

// `int` widens to `long` and then lifts: C# "implicit nullable conversion".
func WidenLocal(n: int): long? {
    len: long? = n
    return len
}

func WidenReturn(n: int): long? {
    return n
}

func WidenNullable(n: int?): long? {
    return n
}

func WidenField(n: int): long? {
    box := new Widened { Value: n }
    return box.Value
}

class Widened {
    Value: long?
}

// A conditional whose other arm is `null` takes the nullable member type.
func MakeStamped(flag: bool, utc: DateTime): Stamped {
    return new Stamped { When: flag ? utc : null }
}

func MakeStampedInverted(flag: bool, utc: DateTime): Stamped {
    return new Stamped { When: flag ? null : utc }
}

func StampedByAssignment(flag: bool, utc: DateTime): Stamped {
    s := new Stamped { When: null }
    s.When = flag ? utc : null
    return s
}

// An implicit tuple conversion converts element by element.
func LiftedTuple(): (string?, int?) {
    t: (string, int) = ("a", 1)
    return t
}

func LiftedTupleLocal(name: string, count: int): (string?, int?) {
    pair: (string?, int?) = (name, count)
    return pair
}

// `with` replacements are written like object-initializer members.
record Airport {
    Latitude: double?
    Name: string?
    Opened: DateTime?
}

func ClearName(source: Airport): Airport {
    return source with { Name: null }
}

func FillLatitude(a: Airport, b: Airport): Airport {
    return a with { Latitude: a.Latitude ?? b.Latitude }
}

func SetOpened(source: Airport, flag: bool, utc: DateTime): Airport {
    return source with { Opened: flag ? utc : null }
}

func SetLatitude(source: Airport, value: double): Airport {
    return source with { Latitude: value }
}

func WidenLatitude(source: Airport, whole: int): Airport {
    return source with { Latitude: whole }
}

// ---- `??` typing: null, widening and reference conversions ----
func CoalesceNullValue(a: int?): int? => a ?? null

func CoalesceNullReference(s: string?): string? => s ?? null

func CoalesceWidenToRight(a: int?, b: long): long => a ?? b

func CoalesceWidenToNullableRight(a: int?, b: long?): long? => a ?? b

func CoalesceRightWidens(a: long?, b: int): long => a ?? b

func CoalesceDoubleRight(a: double?, b: int): double => a ?? b

class Animal {
    Name: string = "animal"
}

class Dog: Animal {
}

func CoalesceBaseDerived(a: Animal?, b: Dog): Animal => a ?? b

func CoalesceDerivedBase(a: Dog?, b: Animal): Animal => a ?? b

// ---- the lifted matrix: widening under the nullable wrap ----
func LiftChar(c: char): int? {
    r: int? = c
    return r
}

func LiftInt(n: int): double? {
    r: double? = n
    return r
}

func LiftShort(n: short): float? {
    r: float? = n
    return r
}

func LiftLong(n: long): double? {
    r: double? = n
    return r
}

func LiftNullableInt(n: int?): double? {
    r: double? = n
    return r
}

// ---- tuples ----
func TupleNullElement(): (string?, int?) {
    t: (string?, int) = (null, 1)
    return t
}

func TupleWidening(): (long?, string) {
    t: (int, string) = (7, "x")
    return t
}

func TupleNested(): ((int, string?), int?) {
    t: ((int, string), int) = ((1, "n"), 2)
    return t
}
