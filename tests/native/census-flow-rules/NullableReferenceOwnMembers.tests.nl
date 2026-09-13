namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Reflection

func MarkupDocumentation(text: string): StringOrMarkupContent {
    return new StringOrMarkupContent(new MarkupContent(text), null)
}

func StringDocumentation(text: string): StringOrMarkupContent {
    return new StringOrMarkupContent(null, text)
}

test "`.Value` on a nullable REFERENCE is the class's own member, lifted by the chain" {
    assert GetDocumentationText(MarkupDocumentation("# Title")) == "# Title"
    assert GetDocumentationText(StringDocumentation("plain")) == "plain"
    assert GetDocumentationText(null) == null

    // The `?.` guard is what makes the absent case null rather than a throw.
    assert GetDocumentationText(new StringOrMarkupContent(null, null)) == null
}

test "the same member behind an ordinary null check reads the class's value" {
    assert MarkupTextOrNone(MarkupDocumentation("body")) == "body"
    assert MarkupTextOrNone(StringDocumentation("plain")) == "none"
}

test "`must` on a reference nullable stays the null assertion" {
    assert MarkupTextOrThrow(MarkupDocumentation("body")) == "body"

    threw := false
    try {
        MarkupTextOrThrow(StringDocumentation("plain"))
    } catch ex: Exception {
        threw = true
    }

    assert threw
}

test "the reference-nullable reader really produces the CLASS's member type" {
    // `MarkupContent?.Value` used to answer `MarkupContent`; the RUNTIME type of what it produces is
    // what says which member bound.
    text := GetDocumentationText(MarkupDocumentation("typed"))
    assert text != null
    assert (must text).GetType() == typeof(string)

    field := typeof(MarkupContent).GetField("Value")
    assert field != null
    assert (must field).FieldType == typeof(string)
}

test "a class that declares HasValue and GetValueOrDefault owns both names" {
    assert SlotIsFilled(new Slot(true, "filled"))
    assert !SlotIsFilled(new Slot(false, "empty"))
    assert !SlotIsFilled(null)

    assert SlotText(new Slot(true, "filled")) == "filled"
    assert SlotText(new Slot(false, "empty")) == "<empty>"
    assert SlotText(null) == "none"

    // `Nullable<T>.GetValueOrDefault` returns `T`; the class's returns `string`, so the return type
    // is what proves whose member bound.
    method := typeof(Slot).GetMethod("GetValueOrDefault")
    assert method != null
    assert (must method).ReturnType == typeof(string)

    field := typeof(Slot).GetField("HasValue")
    assert field != null
    assert (must field).FieldType == typeof(bool)
}

test "the VALUE-type nullable surface is untouched" {
    assert CountHasValue(3)
    assert !CountHasValue(null)
    assert CountOrDefault(3) == 3
    assert CountOrDefault(null) == 0
    assert CountText(3) == "3"
    assert CountText(null) == "none"
}
