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

// ============================================================================
// Task-016 parser-front-end arc, Stage 2: the declaration-NAME diagnostic family.
//
// Carries the "Expected <kind> name" diagnostics for func / class / struct / record /
// soa record / interface / union / enum / type-alias declarations through the SAME
// shared-panic recovery model, with the DiagnosticSpanFromToken keyword-anchoring
// discipline: a missing/invalid name underlines the DECLARATION KEYWORD (not the
// offending token) in all three ConsumeIdentifier variants (end-of-file / reserved-keyword
// / found-other). Every expected value is the GOLDEN output of the production Parser.cs
// path, captured out-of-band from the freshly built CLI (`nlc check --json`) on the same
// malformed source, filtered to the parser diagnostic codes NL101-NL109.
//
// The corpus covers, per kind: the absent-name (end-of-file) case, the reserved-keyword-as-
// name case, and — for the kinds whose failing body does not consume trailing tokens
// (func / enum / type) — the found-other case, which also demonstrates the panic model:
//   * a bad declaration name sets panic and the rest of that declaration's region is
//     suppressed; then at the NEXT declaration boundary panic RESETS and the following
//     error fires (mirrors Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements).
// ============================================================================

// ---- absent name (end-of-file), keyword-anchored, one diagnostic per kind ----

test "016 decl-name: func at end of file anchors the expected-name diagnostic on the 'func' keyword" {
    errors := RunPreamble("func")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected function name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 4
    assert e.SourceSnippet == "func"
    assert e.HumanExplanation == "I was expecting an identifier here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
    assert e.Suggestion == null
}

test "016 decl-name: class at end of file anchors the expected-name diagnostic on the 'class' keyword" {
    errors := RunPreamble("class")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected class name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 5
    assert e.SourceSnippet == "class"
    assert e.HumanExplanation == "I was expecting an identifier here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 decl-name: struct at end of file anchors the expected-name diagnostic on the 'struct' keyword" {
    errors := RunPreamble("struct")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected struct name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 6
    assert e.SourceSnippet == "struct"
}

test "016 decl-name: record at end of file anchors the expected-name diagnostic on the 'record' keyword" {
    errors := RunPreamble("record")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected record name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 6
    assert e.SourceSnippet == "record"
}

test "016 decl-name: soa record at end of file anchors the diagnostic on the 'record' keyword (column 5)" {
    errors := RunPreamble("soa record")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected soa record name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 5
    assert e.Length == 6
    assert e.SourceSnippet == "soa record"
}

test "016 decl-name: interface at end of file anchors the expected-name diagnostic on the 'interface' keyword" {
    errors := RunPreamble("interface")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected interface name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 9
    assert e.SourceSnippet == "interface"
}

test "016 decl-name: union at end of file anchors the expected-name diagnostic on the 'union' keyword" {
    errors := RunPreamble("union")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected union name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 5
    assert e.SourceSnippet == "union"
}

test "016 decl-name: enum at end of file anchors the expected-name diagnostic on the 'enum' keyword" {
    errors := RunPreamble("enum")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected enum name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 4
    assert e.SourceSnippet == "enum"
}

test "016 decl-name: type alias at end of file anchors the expected-name diagnostic on the 'type' keyword" {
    errors := RunPreamble("type")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected type alias name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 4
    assert e.SourceSnippet == "type"
}

test "016 decl-name: record struct at end of file anchors the diagnostic on the 'record' keyword" {
    errors := RunPreamble("record struct")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected record name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 6
    assert e.SourceSnippet == "record struct"
}

test "016 decl-name: duck interface at end of file anchors the diagnostic on the 'interface' keyword (column 6)" {
    errors := RunPreamble("duck interface")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected interface name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 6
    assert e.Length == 9
    assert e.SourceSnippet == "duck interface"
}

// ---- reserved keyword as a declaration name, keyword-anchored (NL109), per kind ----

test "016 decl-name: a reserved keyword as a function name reports the keyword-specific diagnostic anchored on 'func'" {
    errors := RunPreamble("func class")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected function name. Got the reserved keyword 'class'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 4
    assert e.SourceSnippet == "func class"
    assert e.HumanExplanation == "'class' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'classValue' or '_class')."
    assert e.Suggestion == "Rename it to 'classValue' or '_class'"
}

test "016 decl-name: a reserved keyword as a class name is anchored on 'class'" {
    errors := RunPreamble("class return")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected class name. Got the reserved keyword 'return'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 5
    assert e.SourceSnippet == "class return"
    assert e.HumanExplanation == "'return' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'returnValue' or '_return')."
    assert e.Suggestion == "Rename it to 'returnValue' or '_return'"
}

test "016 decl-name: a reserved keyword as a struct name is anchored on 'struct'" {
    errors := RunPreamble("struct return")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected struct name. Got the reserved keyword 'return'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 6
    assert e.SourceSnippet == "struct return"
}

test "016 decl-name: a reserved keyword as a record name is anchored on 'record'" {
    errors := RunPreamble("record if")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected record name. Got the reserved keyword 'if'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 6
    assert e.SourceSnippet == "record if"
}

test "016 decl-name: a reserved keyword as an interface name is anchored on 'interface'" {
    errors := RunPreamble("interface for")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected interface name. Got the reserved keyword 'for'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 9
    assert e.SourceSnippet == "interface for"
}

test "016 decl-name: a reserved keyword as a union name is anchored on 'union'" {
    errors := RunPreamble("union while")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected union name. Got the reserved keyword 'while'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 5
    assert e.SourceSnippet == "union while"
}

test "016 decl-name: a reserved keyword as an enum name is anchored on 'enum'" {
    errors := RunPreamble("enum if")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected enum name. Got the reserved keyword 'if'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 4
    assert e.SourceSnippet == "enum if"
}

test "016 decl-name: a reserved keyword as a type alias name is anchored on 'type'" {
    errors := RunPreamble("type class")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected type alias name. Got the reserved keyword 'class'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 4
    assert e.SourceSnippet == "type class"
    assert e.Suggestion == "Rename it to 'classValue' or '_class'"
}

// ---- found-other name + panic reset at the boundary (func / enum / type) ----
// A non-identifier, non-keyword name reports the found-variant (anchored on the keyword) and
// sets panic; the failing declaration body consumes nothing, so at the NEXT declaration
// boundary panic RESETS and the stray token fires its own unexpected-token diagnostic.

test "016 decl-name: a numeric function name reports the found diagnostic then the stray token fires after the boundary reset" {
    errors := RunPreamble("func 5")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected function name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 4
    assert e0.SourceSnippet == "func 5"
    assert e0.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e0.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e0.Suggestion == null

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 6
    assert e1.Length == 1
    assert e1.SourceSnippet == "func 5"
    assert e1.HumanExplanation == "I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '5' instead."
    assert e1.ContextualHint == "Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases."
}

test "016 decl-name: a numeric enum name reports the found diagnostic then the stray token fires after the boundary reset" {
    errors := RunPreamble("enum 5")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected enum name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 4
    assert e0.SourceSnippet == "enum 5"

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 6
    assert e1.Length == 1
    assert e1.SourceSnippet == "enum 5"
}

test "016 decl-name: a numeric type alias name reports the found diagnostic then the stray token fires after the boundary reset" {
    errors := RunPreamble("type 5")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected type alias name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 4
    assert e0.SourceSnippet == "type 5"

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 6
    assert e1.Length == 1
    assert e1.SourceSnippet == "type 5"
}

// ---- panic-model interactions across declaration boundaries ----

test "016 decl-name: a bad name, its stray token, and a following declaration's name error each fire across boundaries" {
    // func 5\nenum : three diagnostics at three boundaries — the func-name found error, the
    // stray '5' after the boundary reset, and the following enum's end-of-file name error.
    errors := RunPreamble("func 5\nenum")
    assert errors.Count == 3

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected function name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 4
    assert e0.SourceSnippet == "func 5"

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 6
    assert e1.Length == 1
    assert e1.SourceSnippet == "func 5"

    e2 := errors[2]
    assert e2.Code == ErrorCode.UnexpectedEndOfFile
    assert e2.Message == "Expected enum name, but reached the end of the file"
    assert e2.Line == 2
    assert e2.Column == 1
    assert e2.Length == 4
    assert e2.SourceSnippet == "enum"
}

test "016 decl-name: two reserved-keyword names on separate declarations each report at their own boundary" {
    // class struct\nfunc class : the reserved-keyword recovery consumes the offender within each
    // declaration (no cascade in that region), and each declaration boundary resets panic so
    // BOTH name errors fire — anchored on 'class' (line 1) and 'func' (line 2).
    errors := RunPreamble("class struct\nfunc class")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ReservedKeywordAsName
    assert e0.Message == "Expected class name. Got the reserved keyword 'struct'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 5
    assert e0.SourceSnippet == "class struct"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ReservedKeywordAsName
    assert e1.Message == "Expected function name. Got the reserved keyword 'class'"
    assert e1.Line == 2
    assert e1.Column == 1
    assert e1.Length == 4
    assert e1.SourceSnippet == "func class"
}
