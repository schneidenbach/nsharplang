namespace NSharpLang.ColumnarEmitFacts.Tests

import System


// READING A PROPERTY OFF A CAUGHT EXCEPTION.
//
// `ex.Message` worked because `Message` was named, once, in the runtime instance-member resolver.
// Nothing else was: `ex.ParamName` — the property that says WHICH argument was null, and the whole
// reason `ArgumentNullException` carries a name — declined at emit, as did `StackTrace`, `Source`,
// and every property a NuGet package's own exception type adds. There is no rule that separates
// `Message` from the rest; it was simply the one that had been needed.
//
// The resolver now asks the RECEIVER's own type for any readable instance property, through the same
// admitted-property lookup that already served `DateTime` and the SDK task types. These tests read
// the properties and assert their VALUES, so a member that resolved to the wrong getter, or to a
// base's getter where a derived one shadows it, would still fail.
func ExceptionMemberThrowNullArgument(parameterName: string) {
    throw new ArgumentNullException(parameterName)
}

test "the parameter name of a caught ArgumentNullException is readable" {
    caught := ""
    try {
        ExceptionMemberThrowNullArgument("handler")
    } catch ex: ArgumentNullException {
        caught = ex.ParamName ?? ""
    }
    assert caught == "handler"
}

test "a second parameter name is not the first one" {
    // A property read that resolved to a constant, or to the wrong getter, would pass the test above
    // and fail this one.
    first := ""
    second := ""
    try {
        ExceptionMemberThrowNullArgument("remove")
    } catch ex: ArgumentNullException {
        first = ex.ParamName ?? ""
    }
    try {
        ExceptionMemberThrowNullArgument("handler")
    } catch ex: ArgumentNullException {
        second = ex.ParamName ?? ""
    }
    assert first == "remove"
    assert second == "handler"
    assert first != second
}

test "Message still resolves, and now beside the rest rather than instead of them" {
    message := ""
    parameterName := ""
    try {
        ExceptionMemberThrowNullArgument("value")
    } catch ex: ArgumentNullException {
        message = ex.Message
        parameterName = ex.ParamName ?? ""
    }
    // `ArgumentNullException` composes the parameter name into its message, so the two agree without
    // either being derived from the other here.
    assert message.Contains("value")
    assert parameterName == "value"
}

test "Source and StackTrace resolve on a caught exception" {
    hasStack := false
    source := ""
    try {
        ExceptionMemberThrowNullArgument("x")
    } catch ex: ArgumentNullException {
        trace := ex.StackTrace ?? ""
        hasStack = trace.Length > 0
        source = ex.Source ?? ""
    }
    assert hasStack
    assert source.Length > 0
}

test "a property declared by a DERIVED exception type resolves, not only Exception's" {
    // `FileNotFoundException.FileName` is declared by the derived type. A lookup that asked
    // `Exception` for the member — which is what the `Message` special case did — would never find it.
    fileName := ""
    message := ""
    try {
        throw new FileNotFoundException("not found", "/tmp/missing.txt")
    } catch ex: FileNotFoundException {
        fileName = ex.FileName ?? ""
        message = ex.Message
    }
    assert fileName == "/tmp/missing.txt"
    assert message == "not found"
}

test "the base type's properties still resolve through a derived receiver" {
    message := ""
    try {
        throw new InvalidOperationException("bad state")
    } catch ex: InvalidOperationException {
        message = ex.Message
    }
    assert message == "bad state"
}
