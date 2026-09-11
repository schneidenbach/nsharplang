namespace NSharpLang.Cli.Commands

import System


// CONTRACTS FOR THE DOC-MISS MESSAGE. The first line is load-bearing text that scripts and
// humans both read; it must be byte-identical with and without an explanation, and the
// explanation — when the doc-query owners have one — rides on its own line underneath.
test "a doc miss without an explanation reads exactly as it always has" {
    assert QueryCommandKernels.GetNoDocumentationMessage("Consoel", null) == "No documentation found for 'Consoel'."
}

test "a doc miss with an explanation keeps the first line and appends the note on its own line" {
    message := QueryCommandKernels.GetNoDocumentationMessage("HttpLoggingOptions", "The note.")
    assert message == "No documentation found for 'HttpLoggingOptions'.\nThe note."
}
