namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler

// Task-016 parser-front-end arc, Stage 1: parity contracts for the N# shared-panic
// recovery model carrying the import / namespace / package diagnostic family.
//
// Every expected value below is the GOLDEN output of the production Parser.cs path,
// captured out-of-band from the freshly built CLI (`nlc check --json`) on the same
// malformed source, filtered to the parser diagnostic codes NL101-NL109. Because both
// Parser.cs and ColumnarParserRecovery construct their diagnostics through the identical
// live owner ParserErrorDiagnostics.Create, matching these fields proves byte-exact
// message / span / order parity with the production parser. (BootstrapServices cannot
// reference Parser.cs directly — Compiler depends on BootstrapServices, not the reverse —
// so the golden values stand in for the C# oracle.)
//
// The corpus deliberately includes the two model shapes the committed C# tests pin:
//   * cascading suppression (Parser_CascadingErrorsSuppressed): the triple-package case
//     proves the third duplicate is suppressed by shared panic with no intervening reset.
//   * does-not-swallow-following (Parser_DanglingBinaryOperator_...): the package-then-bad
//     case proves the declaration-boundary panic reset lets the following bad token report
//     its own diagnostic instead of being swallowed.

func RunPreamble(source: string): List<CompilerError> {
    return ColumnarParserRecovery.ParseFilePreamble(source, "a.nl")
}

test "016 recovery: import at end of file reports the plain end-of-file expected-identifier diagnostic" {
    errors := RunPreamble("import")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected identifier, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 6
    assert e.SourceSnippet == "import"
    assert e.HumanExplanation == "I was expecting an identifier here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 recovery: import with trailing dot at end of file uses the dot-access end-of-file variant" {
    errors := RunPreamble("import System.")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected identifier after '.', but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 14
    assert e.Length == 1
    assert e.SourceSnippet == "import System."
    assert e.HumanExplanation == "I see a dot (.) operator but no member name after it; the file ended first."
    assert e.ContextualHint == "After a dot, I need to see a property or method name."
}

test "016 recovery: import of a non-identifier reports the found diagnostic then resumes past the declaration boundary" {
    errors := RunPreamble("import 5\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected identifier. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 8
    assert e0.Length == 1
    assert e0.SourceSnippet == "import 5"
    assert e0.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e0.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e0.Suggestion == null

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 8
    assert e1.Length == 1
    assert e1.SourceSnippet == "import 5"
    assert e1.HumanExplanation == "I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '5' instead."
    assert e1.ContextualHint == "Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases."
}

test "016 recovery: namespace at end of file reports the plain end-of-file expected-identifier diagnostic" {
    errors := RunPreamble("namespace")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected identifier, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 9
    assert e.SourceSnippet == "namespace"
    assert e.HumanExplanation == "I was expecting an identifier here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 recovery: missing import alias after 'as' anchors the end-of-file span on the 'as' keyword" {
    errors := RunPreamble("import System as")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected alias name after 'as', but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 15
    assert e.Length == 2
    assert e.SourceSnippet == "import System as"
    assert e.HumanExplanation == "I was expecting an identifier here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 recovery: a second package declaration reports the duplicate-package diagnostic" {
    errors := RunPreamble("package Foo\npackage Bar\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Only one package declaration is allowed"
    assert e.Line == 2
    assert e.Column == 1
    assert e.Length == 7
    assert e.SourceSnippet == "package Bar"
    assert e.HumanExplanation == "A source file can belong to a single package."
    assert e.ContextualHint == "Remove the extra package declaration."
}

test "016 recovery: cascading suppression - a third package declaration is suppressed with no intervening reset" {
    // Mirrors Parser_CascadingErrorsSuppressed: the shared-panic flag stays set across the
    // whole package/import loop (no sync point inside it), so only the SECOND package
    // reports; the third is swallowed. A per-directive reset would (wrongly) report twice.
    errors := RunPreamble("package Foo\npackage Bar\npackage Baz\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Only one package declaration is allowed"
    assert e.Line == 2
    assert e.Column == 1
    assert e.Length == 7
    assert e.SourceSnippet == "package Bar"
}

test "016 recovery: the declaration boundary resets panic so a following bad token is not swallowed" {
    // Mirrors Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements: after the
    // duplicate-package diagnostic sets panic, the declaration boundary reset (Parser.cs :83)
    // lets the stray token report its own diagnostic. A missing reset would swallow it.
    errors := RunPreamble("package Foo\npackage Bar\n5\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.InvalidSyntax
    assert e0.Message == "Only one package declaration is allowed"
    assert e0.Line == 2
    assert e0.Column == 1
    assert e0.Length == 7
    assert e0.SourceSnippet == "package Bar"

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 3
    assert e1.Column == 1
    assert e1.Length == 1
    assert e1.SourceSnippet == "5"
}

test "016 recovery: a reserved keyword where an import identifier is required reports the keyword-specific diagnostic" {
    errors := RunPreamble("import class")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected identifier. Got the reserved keyword 'class'"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 5
    assert e.SourceSnippet == "import class"
    assert e.HumanExplanation == "'class' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'classValue' or '_class')."
    assert e.Suggestion == "Rename it to 'classValue' or '_class'"
}

test "016 recovery: namespace with a non-identifier after a dot uses the dot-access found variant then resumes" {
    errors := RunPreamble("namespace Foo.5")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected identifier after '.'. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 15
    assert e0.Length == 1
    assert e0.SourceSnippet == "namespace Foo.5"
    assert e0.HumanExplanation == "I see a dot (.) operator but no member name after it. I found '5' instead."
    assert e0.ContextualHint == "After a dot, I need to see a property or method name."
    assert e0.Suggestion == "Check if you forgot to finish this line"

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 15
    assert e1.Length == 1
    assert e1.SourceSnippet == "namespace Foo.5"
}

test "016 recovery: import with a non-identifier after a dot matches the namespace dot-access shape" {
    errors := RunPreamble("import System.5")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected identifier after '.'. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 15
    assert e0.Length == 1
    assert e0.SourceSnippet == "import System.5"
    assert e0.HumanExplanation == "I see a dot (.) operator but no member name after it. I found '5' instead."
    assert e0.ContextualHint == "After a dot, I need to see a property or method name."

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 15
    assert e1.Length == 1
    assert e1.SourceSnippet == "import System.5"
}
