namespace NSharpLang.CensusConversions.Tests

import System.Reflection
import System.Xml.Linq

// CENSUS §CONV2/3 AND §CONV2/4 — WHAT AN ARGUMENT MAY BE CONVERTED BY, AND WHAT AN ARRAY LITERAL
// WRITTEN AS ONE IS WORTH BEFORE A CANDIDATE IS CHOSEN.
//
// §CONV2/3. `result.Attribute("outcome")` reported "No overload of 'Attribute' accepts 1 argument
// with these types" over a signature that takes exactly one `XName` — because applicability was
// decided by the STANDARD conversions alone. C# admits a candidate when every argument has an
// implicit conversion to its parameter, and an operator a type declares about itself is one of
// those: `XName` declares `implicit operator XName(string)`, and the call is an ordinary one that
// emits `call XName::op_Implicit(string)` in front of the argument. The explicit direction is the
// same rule with a cast written: `XAttribute` declares `explicit operator string?(XAttribute)`.
//
// §CONV2/4. `method.Invoke(null, [args])` reported "No overload of 'Invoke' accepts 2 arguments"
// because the literal had to be given a type before any parameter named its element type, and the
// type it was given — `string[][]`, inferred from its single element — matched neither overload. A
// collection expression is applicable to a candidate whose parameter is an array its elements
// convert to, element by element; the chosen candidate then target-types the literal for real.
//
// Everything below is EXECUTED by the tests beside it, because a conversion emitted in the wrong
// place and an overload chosen wrongly both still compile.

// ── a user-defined implicit conversion in argument position ─────────────
func BuildResult(outcome: string): XElement {
    element := new XElement(XName.Get("result"))

    // `SetAttributeValue(XName, object?)`: the name reaches `XName` through the operator, and the
    // value boxes into `object?` the ordinary way.
    element.SetAttributeValue("outcome", outcome)
    return element
}

func AttributeByString(element: XElement): XAttribute? {
    return element.Attribute("outcome")
}

func AttributeByName(element: XElement): XAttribute? {
    return element.Attribute(XName.Get("outcome"))
}

// The EXPLICIT direction, written as a cast: `XAttribute` declares `explicit operator
// string?(XAttribute)`, and a missing attribute converts to `null` rather than throwing.
func OutcomeOf(element: XElement): string? {
    return (string?)element.Attribute("outcome")
}

func MissingOf(element: XElement): string? {
    return (string?)element.Attribute("absent")
}

// ── an array literal scored against an overload set ─────────────────────

// The overload set lives on a type because free-function overloads are not emitted yet; what is
// under test is the SCORING of a collection expression against several candidates, which is the same
// question either way.
class Sink {
    static func Accept(values: int[]): string {
        return "int[] " + values.Length.ToString()
    }

    static func Accept(values: object[]): string {
        return "object[] " + values.Length.ToString()
    }

    static func AcceptParams(params values: object[]): string {
        return "params " + values.Length.ToString()
    }

    // One candidate, so the literal's only job is to take the target's element type.
    static func AcceptOnly(values: object[]): string {
        return "only " + values.Length.ToString()
    }
}

// The literal's ELEMENTS decide which overload it fits: an exact element type keeps the top of the
// ladder, and one that converts is ranked below it.
func PickInts(): string {
    return Sink.Accept([1, 2, 3])
}

// `string[]` reaches `object[]` by array covariance and reaches `int[]` not at all, so the object
// overload is the only applicable one.
func PickObjectsFromStrings(): string {
    return Sink.Accept(["a", "b"])
}

func PickParamsLiteral(): string {
    return Sink.AcceptParams(["a", "b"])
}

func PickParamsExpanded(): string {
    return Sink.AcceptParams("a", "b")
}

// Elements with no common type at all: this is an ordinary `object[]`, and inferring it from the
// first element used to report "all elements in an array must be the same type".
func PickMixed(): string {
    return Sink.AcceptOnly([1, "b", null])
}

// ── the same question over a REFLECTED overload set ─────────────────────

// `MethodInfo.Invoke(object?, object?[]?)` against `Invoke(object?, BindingFlags, Binder?,
// object?[]?, CultureInfo?)` — the census probe's own call, with the literal written in place.
func InvokeWith(method: MethodInfo, values: string[]): object? {
    return method.Invoke(null, [values])
}

func InvokeWithMixed(method: MethodInfo, first: int, second: string): object? {
    return method.Invoke(null, [first, second])
}

// The target of those invocations. Public and static so reflection finds it the ordinary way.
func JoinValues(values: string[]): string {
    return string.Join("|", values)
}

func DescribePair(first: int, second: string): string {
    return first.ToString() + ":" + second
}
