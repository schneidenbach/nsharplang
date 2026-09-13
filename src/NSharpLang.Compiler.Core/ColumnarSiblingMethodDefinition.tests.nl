namespace NSharpLang.Compiler.Columnar

import System


// The pinned compiler cannot spell Array.Empty<string>() directly at this source level. Reflection
// still reaches the BCL singleton, which lets the control state identity rather than merely length.
func GenericExtensionReceiverBclEmptyStringArray(): object {
    emptyDefinition := typeof(Array).GetMethod("Empty")
    if emptyDefinition == null || !emptyDefinition.get_IsGenericMethodDefinition() {
        throw new InvalidOperationException("System.Array.Empty<T>() was not found.")
    }
    typeArguments := new Type[](1)
    typeArguments[0] = typeof(string)
    closedEmpty := emptyDefinition.MakeGenericMethod(typeArguments)
    value := TypeOfRequiredInvocation(closedEmpty, null, new object[](0))
    if value == null {
        throw new InvalidOperationException("System.Array.Empty<string>() returned null.")
    }
    return value
}

test "generic extension receiver chains accept only dotted plain names" {
    assert ColumnarGenericExtensionReceiverChain.IsSimpleIdentifierText(((char)916).ToString() + "9_")
    assert !ColumnarGenericExtensionReceiverChain.IsSimpleIdentifierText("9bad")
    assert !ColumnarGenericExtensionReceiverChain.IsSimpleIdentifierText("has-dash")

    names := new string[](1)
    names[0] = "sentinel"
    assert ColumnarGenericExtensionReceiverChain.IsSupportedText(
        "root.Next_2." + ((char)916).ToString(),
        out names
    )
    assert names.Length == 3
    assert names[0] == "root"
    assert names[1] == "Next_2"
    assert names[2] == ((char)916).ToString()

    names = new string[](1)
    names[0] = "sentinel"
    assert !ColumnarGenericExtensionReceiverChain.IsSupportedText(
        "root..next",
        out names
    )
    // The split has already occurred when a segment fails validation. Callers that inspect the
    // failure out slot therefore retain the three exact source segments.
    assert names.Length == 3
    assert names[0] == "root"
    assert names[1] == ""
    assert names[2] == "next"

    names = new string[](1)
    names[0] = "sentinel"
    assert !ColumnarGenericExtensionReceiverChain.IsSupportedText(
        "root(call)",
        out names
    )
    assert names.Length == 0
    assert Object.ReferenceEquals(names, GenericExtensionReceiverBclEmptyStringArray())
}
