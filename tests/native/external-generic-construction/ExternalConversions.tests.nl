namespace NSharpLang.ExternalGenericConstruction.Tests

import System
import System.Xml.Linq

// USER-DEFINED CONVERSIONS DECLARED BY A REFERENCED ASSEMBLY'S TYPE, EXECUTED.
//
// A conversion operator is metadata like any other member, and the language honours the ones an
// external type declares in exactly the positions it honours a source-declared one: an annotated
// local, an argument, a return, and a written cast. Every row below runs the emitted IL and reads a
// value back, so an operator that was selected but not CALLED would fail the assertion rather than
// pass a type check.
//
// THE THREE TYPES ARE CHOSEN FOR WHAT THEY PROVE, not for convenience. `XName` declares
// `implicit operator XName(string)` and is a reference type; `DateTimeOffset` declares
// `implicit operator DateTimeOffset(DateTime)` and is a struct, so the conversion has to reach a
// value-type result; and `decimal` declares its numeric conversions BOTH ways, which is how the
// explicit-only half is told apart from the implicit one.
func XNameLocalPart(name: XName): string {
    return name.LocalName
}

func XNameFromText(): XName {
    return "returned"
}

func OffsetOf(moment: DateTime): DateTimeOffset {
    return moment
}

func UtcMoment(): DateTime {
    return new DateTime(2020, 1, 2, 3, 4, 5, DateTimeKind.Utc)
}

test "an external type's implicit conversion reaches an ANNOTATED LOCAL" {
    tag: XName = "tag"
    assert tag.LocalName == "tag"

    moment := UtcMoment()
    offset: DateTimeOffset = moment
    assert offset.ToString("yyyy-MM-dd HH:mm:ss") == "2020-01-02 03:04:05"
}

test "an external type's implicit conversion reaches an ARGUMENT position" {
    assert XNameLocalPart("passed") == "passed"

    converted := OffsetOf(UtcMoment())
    assert converted.ToString("yyyy-MM-dd") == "2020-01-02"
}

test "an external type's implicit conversion reaches a RETURN position" {
    returned := XNameFromText()
    assert returned.LocalName == "returned"

    offset := OffsetOf(UtcMoment())
    assert offset.ToString("HH:mm:ss") == "03:04:05"
}

test "a written CAST reaches the same implicit conversion" {
    cast := (XName)"cast"
    assert cast.LocalName == "cast"
}

test "an EXPLICIT-only conversion needs the cast and gets it" {
    // `decimal` declares `explicit operator decimal(double)` and no implicit one, so the annotated
    // form is a type error and the cast is the whole difference.
    value := 5.75
    narrowed := (decimal)value
    assert narrowed.ToString() == "5.75"

    // The other direction is explicit too, and rounds toward zero exactly as the operator does.
    amount := 5.75
    truncated := (int)amount
    assert truncated == 5
}

test "an implicit conversion is still available under a cast that merely says what was implied" {
    named := (XName)"explicitly"
    assert named.LocalName == "explicitly"

    offset := (DateTimeOffset)UtcMoment()
    assert offset.ToString("yyyy") == "2020"
}
