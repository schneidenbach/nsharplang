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

// ============================================================================
// Task-016 parser-front-end arc, Stage 3: the MALFORMED-LITERAL diagnostic family
// (NL105 InvalidLiteral).
//
// Carries the malformed-literal diagnostics — unterminated string, unterminated interpolated
// (single-line) string, unterminated char, empty char, unterminated triple-quoted string,
// unterminated interpolated raw string — through the SAME shared-panic recovery model. Every
// malformed-literal diagnostic is REPORTED in Parser.cs ParsePrimaryExpression
// (ReportMalformedCharLiteralIfNeeded / ReportMalformedStringLiteralIfNeeded /
// ReportMalformedRawStringLiteralIfNeeded), routing through the shared-panic ReportError; the
// already-N# Lexer only CLASSIFIES (Token.IsTerminated + the token value), and the malformed
// DECISION reuses the live shared owner ParserLiteralFacts.IsCompleteStringLiteral /
// IsCompleteCharLiteral (Parser.cs delegates to the identical calls). So the family belongs to
// the parser model, not a separate lexer lane, and is carried in full here.
//
// The literal is reached via the shallowest byte-exact expression context — the expression-bodied
// function `func f() => <literal>` (oracle-verified to emit exactly ONE NL105 per shape). Every
// expected value is the GOLDEN output of the production Parser.cs path, captured out-of-band from
// the freshly built Release CLI (`nlc check --json`) on the same malformed source, filtered to the
// parser diagnostic codes NL101-NL109.
//
// The corpus covers, per literal shape, the single-malformed case, plus the panic-model interactions:
//   * across a sync (declaration) boundary → the next declaration's literal error fires
//     (mirrors Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements);
//   * an in-region cascade → a following malformed literal in the SAME expression is suppressed by
//     shared panic (mirrors Parser_CascadingErrorsSuppressed).
// ============================================================================

// ---- one malformed-literal diagnostic per shape (expression-bodied function) ----

test "016 literal: an unterminated string in an expression body reports NL105 anchored on the literal" {
    errors := RunPreamble("func f() => \"abc")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Unterminated string literal"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 4
    assert e.SourceSnippet == "func f() => \"abc"
    assert e.HumanExplanation == "This string starts with a quote but reaches the end of the line before a closing quote."
    assert e.ContextualHint == "Add the closing quote on this line, or use a triple-quoted string for multi-line text."
    assert e.Suggestion == "Add a closing quote"
}

test "016 literal: an unterminated character literal reports NL105" {
    errors := RunPreamble("func f() => 'a")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Unterminated character literal"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 2
    assert e.SourceSnippet == "func f() => 'a"
    assert e.HumanExplanation == "This character literal starts with a quote but does not have a closing quote."
    assert e.ContextualHint == "Write a single character like `'a'`, or use a string literal like \"a\" when you need text."
    assert e.Suggestion == "Add the closing quote"
}

test "016 literal: an empty character literal reports the empty-char NL105 variant" {
    errors := RunPreamble("func f() => ''")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Empty character literal"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 2
    assert e.SourceSnippet == "func f() => ''"
    assert e.HumanExplanation == "A character literal needs exactly one character between the quotes."
    assert e.ContextualHint == "Write a single character like `'a'`, or use a string literal like \"a\" when you need text."
    assert e.Suggestion == "Add the closing quote"
}

test "016 literal: an unterminated triple-quoted string reports the raw-string NL105 (marker length 3)" {
    errors := RunPreamble("func f() => \"\"\"abc")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Unterminated triple-quoted string literal"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 3
    assert e.SourceSnippet == "func f() => \"\"\"abc"
    assert e.HumanExplanation == "This triple-quoted string starts with `\"\"\"` but reaches the end of the file before the closing triple quote."
    assert e.ContextualHint == "Add the closing triple quote `\"\"\"` before the end of the file."
    assert e.Suggestion == "Add the closing triple quote"
}

test "016 literal: an unterminated interpolated (single-line) string reports the interpolated NL105 variant" {
    errors := RunPreamble("func f() => $\"abc")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Unterminated interpolated string literal"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 5
    assert e.SourceSnippet == "func f() => $\"abc"
    assert e.HumanExplanation == "This interpolated string starts with `$\"` but reaches the end of the line before a closing quote."
    assert e.ContextualHint == "Add the closing quote on this line, or use a triple-quoted string for multi-line text."
    assert e.Suggestion == "Add a closing quote"
}

test "016 literal: an unterminated interpolated raw string reports the raw-string NL105 (marker length 4)" {
    errors := RunPreamble("func f() => $\"\"\"abc")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Unterminated interpolated raw string literal"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 4
    assert e.SourceSnippet == "func f() => $\"\"\"abc"
    assert e.HumanExplanation == "This interpolated raw string starts with `$\"\"\"` but reaches the end of the file before the closing triple quote."
    assert e.ContextualHint == "Add the closing triple quote `\"\"\"` before the end of the file."
    assert e.Suggestion == "Add the closing triple quote"
}

// ---- across a sync (declaration) boundary → the next literal error fires ----

test "016 literal: two malformed-char expression bodies each report at their own declaration boundary" {
    // The declaration boundary resets panic, so BOTH funcs' character literals report.
    errors := RunPreamble("func f() => 'a\nfunc g() => 'b")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.InvalidLiteral
    assert e0.Message == "Unterminated character literal"
    assert e0.Line == 1
    assert e0.Column == 13
    assert e0.Length == 2
    assert e0.SourceSnippet == "func f() => 'a"

    e1 := errors[1]
    assert e1.Code == ErrorCode.InvalidLiteral
    assert e1.Message == "Unterminated character literal"
    assert e1.Line == 2
    assert e1.Column == 13
    assert e1.Length == 2
    assert e1.SourceSnippet == "func g() => 'b"
}

test "016 literal: two malformed-string expression bodies each report at their own declaration boundary" {
    errors := RunPreamble("func f() => \"aa\nfunc g() => \"bb")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.InvalidLiteral
    assert e0.Message == "Unterminated string literal"
    assert e0.Line == 1
    assert e0.Column == 13
    assert e0.Length == 3
    assert e0.SourceSnippet == "func f() => \"aa"

    e1 := errors[1]
    assert e1.Code == ErrorCode.InvalidLiteral
    assert e1.Message == "Unterminated string literal"
    assert e1.Line == 2
    assert e1.Column == 13
    assert e1.Length == 3
    assert e1.SourceSnippet == "func g() => \"bb"
}

test "016 literal: a malformed literal then a stray top-level token both fire across the boundary reset" {
    // func f() => 'a\n5 : the char literal reports and sets panic; the declaration boundary
    // resets panic so the stray '5' reports its own unexpected-token diagnostic.
    errors := RunPreamble("func f() => 'a\n5")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.InvalidLiteral
    assert e0.Message == "Unterminated character literal"
    assert e0.Line == 1
    assert e0.Column == 13
    assert e0.Length == 2
    assert e0.SourceSnippet == "func f() => 'a"

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 2
    assert e1.Column == 1
    assert e1.Length == 1
    assert e1.SourceSnippet == "5"
}

// ---- in-region cascade → a following malformed literal is suppressed by shared panic ----

test "016 literal: a second malformed character literal in the same expression is suppressed by shared panic" {
    // func f() => 'a + 'b : the malformed check runs on BOTH char literals, but the first sets
    // panic, so Report suppresses the second — exactly one diagnostic, mirroring cascading suppression.
    errors := RunPreamble("func f() => 'a + 'b")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Unterminated character literal"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 2
    assert e.SourceSnippet == "func f() => 'a + 'b"
}

test "016 literal: an empty-char error suppresses a following malformed literal in the same expression" {
    errors := RunPreamble("func f() => '' + 'b")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Empty character literal"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 2
    assert e.SourceSnippet == "func f() => '' + 'b"
}

test "016 literal: a malformed literal inside a parenthesized group anchors on the literal and suppresses the missing paren" {
    // func f() => ('a : the '(' shifts the char literal to column 14; the char error reports and the
    // (would-be) missing-')' recovery is suppressed by shared panic — exactly one diagnostic.
    errors := RunPreamble("func f() => ('a")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Unterminated character literal"
    assert e.Line == 1
    assert e.Column == 14
    assert e.Length == 2
    assert e.SourceSnippet == "func f() => ('a"
}

// ---- negatives: a well-formed literal reports nothing (no over-reporting) ----

test "016 literal: a well-formed string literal in an expression body reports no parser diagnostic" {
    errors := RunPreamble("func f() => \"abc\"")
    assert errors.Count == 0
}

test "016 literal: a well-formed function followed by a malformed one reports only the malformed literal" {
    // func f() => "abc"\nfunc g() => 'x : the complete string reports nothing; only g's char fires.
    errors := RunPreamble("func f() => \"abc\"\nfunc g() => 'x")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidLiteral
    assert e.Message == "Unterminated character literal"
    assert e.Line == 2
    assert e.Column == 13
    assert e.Length == 2
    assert e.SourceSnippet == "func g() => 'x"
}

// ============================================================================
// Task-016 parser-front-end arc, Stage 4: the MEMBER / PARAMETER / FIELD declaration
// diagnostic family (the `:`/`:=` colon and type-annotation errors, NL102 ExpectedToken /
// NL109 ReservedKeywordAsName).
//
// Carries, through the SAME shared-panic recovery model: the PARAMETER family via
// `func f(<params>)` (ConsumeIdentifier + GetMissingParameterNameDiagnosticSpan,
// ConsumeParameterColon, ParseParameterTypeReference); the FIELD family via `class C { … }` /
// `struct S { … }` (ConsumeIdentifier "Expected field name", ConsumeFieldColon,
// ParseFieldTypeReference with LooksLikeNextFieldAfterMissingType); the MEMBER-BOUNDARY panic
// reset (ParseMemberList, Parser.cs :1365); and the Stage-2-deferred braced-kind found-other
// name for the `{`-offender variant (`class {` / `struct {`), now reachable through the
// member-list parse. Every expected value is the GOLDEN output of the production Parser.cs path,
// captured out-of-band from the freshly built Release CLI (`nlc check --json`) on the same
// malformed source, filtered to the parser diagnostic codes NL101-NL109.
// ============================================================================

// ---- parameter family (func f(<params>)) ----

test "016 param: a missing ':' after a parameter name anchors NL102 on the parameter name" {
    errors := RunPreamble("func f(x)")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' after parameter name. Got ')'"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 1
    assert e.SourceSnippet == "func f(x)"
    assert e.HumanExplanation == "Parameter 'x' needs a ':' before its type."
    assert e.ContextualHint == "Write this parameter as `x: Type`."
    assert e.Suggestion == "Add ':' after 'x'"
}

test "016 param: a missing type after the parameter ':' anchors the type NL102 on the parameter name" {
    errors := RunPreamble("func f(x:)")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got ')'"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 1
    assert e.SourceSnippet == "func f(x:)"
    assert e.HumanExplanation == "Parameter 'x' needs a type after ':'."
    assert e.ContextualHint == "Write this parameter as `x: Type`."
    assert e.Suggestion == "Add a parameter type after ':'"
}

test "016 param: a ':' where the parameter name is required anchors the found NL102 on the type token" {
    // GetMissingParameterNameDiagnosticSpan: the `:` is followed by a type start `int`, so the
    // "Expected parameter name" diagnostic underlines `int` (column 9, length 3), not the `:`.
    errors := RunPreamble("func f(:int)")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected parameter name. Got ':'"
    assert e.Line == 1
    assert e.Column == 9
    assert e.Length == 3
    assert e.SourceSnippet == "func f(:int)"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found ':' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e.Suggestion == null
}

test "016 param: a reserved keyword where a parameter name is required reports the keyword-specific NL109" {
    errors := RunPreamble("func f(class: int)")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected parameter name. Got the reserved keyword 'class'"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 5
    assert e.SourceSnippet == "func f(class: int)"
    assert e.HumanExplanation == "'class' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'classValue' or '_class')."
    assert e.Suggestion == "Rename it to 'classValue' or '_class'"
}

test "016 param: a valid first parameter then a second missing its ':' reports the second parameter's NL102" {
    // The first parameter `a: int` parses cleanly; the second `b` reports the missing-':' NL102
    // anchored on `b` (column 16). Exercises a simple type consume plus the comma continuation.
    errors := RunPreamble("func f(a: int, b)")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' after parameter name. Got ')'"
    assert e.Line == 1
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "func f(a: int, b)"
    assert e.HumanExplanation == "Parameter 'b' needs a ':' before its type."
    assert e.ContextualHint == "Write this parameter as `b: Type`."
    assert e.Suggestion == "Add ':' after 'b'"
}

test "016 param: a fully well-formed parameter list reports no parser diagnostic" {
    errors := RunPreamble("func f(x: int)")
    assert errors.Count == 0
}

test "016 param: two functions each with a missing parameter ':' report at their own declaration boundary" {
    // The declaration-boundary panic reset lets BOTH functions' parameter errors fire.
    errors := RunPreamble("func f(x)\nfunc g(y)")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected ':' after parameter name. Got ')'"
    assert e0.Line == 1
    assert e0.Column == 8
    assert e0.Length == 1
    assert e0.SourceSnippet == "func f(x)"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected ':' after parameter name. Got ')'"
    assert e1.Line == 2
    assert e1.Column == 8
    assert e1.Length == 1
    assert e1.SourceSnippet == "func g(y)"
}

// ---- field family (class C { … } / struct S { … }) ----

test "016 field: a missing ':'/':=' after a field name anchors NL102 on the field name" {
    errors := RunPreamble("class C { x }")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' or ':=' after field name. Got '}'"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 1
    assert e.SourceSnippet == "class C { x }"
    assert e.HumanExplanation == "Field 'x' needs a ':' before its type, or ':=' before an inferred initializer."
    assert e.ContextualHint == "Write this field as `x: Type` or `x := value`."
    assert e.Suggestion == "Add ':' after 'x'"
}

test "016 field: a missing type after the field ':' anchors the type NL102 on the field name" {
    errors := RunPreamble("class C { x: }")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '}'"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 1
    assert e.SourceSnippet == "class C { x: }"
    assert e.HumanExplanation == "Field 'x' needs a type after ':'."
    assert e.ContextualHint == "Write this field as `x: Type`."
    assert e.Suggestion == "Add a field type after ':'"
}

test "016 field: the member-boundary panic reset lets two malformed fields each report their type error" {
    // class C { x: \n y: } : the LooksLikeNextFieldAfterMissingType heuristic stops field x's type
    // parse from swallowing field y; field x sets panic, the member boundary resets it, and field
    // y reports too. Proves the Parser.cs :1365 per-member sync point.
    errors := RunPreamble("class C {\nx:\ny:\n}")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected type name. Got 'y'"
    assert e0.Line == 2
    assert e0.Column == 1
    assert e0.Length == 1
    assert e0.SourceSnippet == "x:"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected type name. Got '}'"
    assert e1.Line == 3
    assert e1.Column == 1
    assert e1.Length == 1
    assert e1.SourceSnippet == "y:"
}

test "016 field: a reserved keyword where a field name is required reports the keyword-specific NL109" {
    errors := RunPreamble("class C { return }")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected field name. Got the reserved keyword 'return'"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 6
    assert e.SourceSnippet == "class C { return }"
    assert e.HumanExplanation == "'return' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'returnValue' or '_return')."
    assert e.Suggestion == "Rename it to 'returnValue' or '_return'"
}

test "016 field: a struct field missing its ':'/':=' reports the same NL102 (struct body parity)" {
    errors := RunPreamble("struct S { a }")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' or ':=' after field name. Got '}'"
    assert e.Line == 1
    assert e.Column == 12
    assert e.Length == 1
    assert e.SourceSnippet == "struct S { a }"
    assert e.HumanExplanation == "Field 'a' needs a ':' before its type, or ':=' before an inferred initializer."
    assert e.ContextualHint == "Write this field as `a: Type` or `a := value`."
    assert e.Suggestion == "Add ':' after 'a'"
}

test "016 field: a malformed field in each of two classes reports at each class's declaration boundary" {
    errors := RunPreamble("class C {\nx\n}\nclass D {\ny\n}")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected ':' or ':=' after field name. Got '}'"
    assert e0.Line == 2
    assert e0.Column == 1
    assert e0.Length == 1
    assert e0.SourceSnippet == "x"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected ':' or ':=' after field name. Got '}'"
    assert e1.Line == 5
    assert e1.Column == 1
    assert e1.Length == 1
    assert e1.SourceSnippet == "y"
}

test "016 field: a well-formed explicitly-typed field reports no parser diagnostic" {
    errors := RunPreamble("class C { x: int }")
    assert errors.Count == 0
}

test "016 field: an empty class body reports no parser diagnostic" {
    errors := RunPreamble("class C {}")
    assert errors.Count == 0
}

// ---- braced-kind found-other name (Stage-2-deferred `{`-offender variant, now reachable) ----

test "016 decl-name: a class whose name is the opening brace anchors the found NL102 on 'class'" {
    // `class {` : the offending `{` is consumed as the (empty) body brace, so the member-list
    // parse makes this Stage-2-deferred found-other reachable as exactly ONE diagnostic.
    errors := RunPreamble("class {\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected class name. Got '{'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 5
    assert e.SourceSnippet == "class {"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '{' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e.Suggestion == null
}

test "016 decl-name: a struct whose name is the opening brace anchors the found NL102 on 'struct'" {
    errors := RunPreamble("struct {\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected struct name. Got '{'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 6
    assert e.SourceSnippet == "struct {"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '{' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e.Suggestion == null
}

// ============================================================================
// Task-016 parser-front-end arc, Stage 5: the GENERICS / CONSTRAINTS diagnostic family.
//
// Carries, through the SAME shared-panic recovery model: the TYPE PARAMETER name errors via `<…>`
// (ReportMissingTypeParameterName, Parser.cs :6439, + the reserved-keyword variant :743); the
// GENERIC TYPE ARGUMENT errors via a generic return type `Name<…>` (ReportMissingGenericTypeArgument,
// :6457); the ConsumeGreater split-`>>` discipline (:2101 — the split mechanism, proven by the
// well-formed nested-generic NEGATIVE, plus the "Expected '>'. Got 'X'" ExpectedToken error); and the
// `where`-clause constraint errors (ParseGenericConstraints :851 — the "Expected type parameter" name
// error, the missing-`:` Consume error, and the class/struct mutual-exclusion + struct/new() redundancy
// InvalidSyntax validations). Every expected value is the GOLDEN output of the production Parser.cs path,
// captured out-of-band from the freshly built Release CLI (`nlc check --json`) on the same malformed
// source, filtered to the parser diagnostic codes NL101-NL109 (excluding the columnar-backend decline
// NL103, which is not a parser diagnostic). DEFERRED with reasons: the EOF-anchored ConsumeGreater
// (the check pipeline clamps its JSON length 0→1, unmatchable at the CompilerError level); the `new(`
// missing-`)` (NL107, needs the closing-delimiter TryReportMissingClosingDelimiter stage); classes do
// NOT take `where` clauses (verified: `class C<T> where …` cascades), so the constraint family is
// function-only.
// ============================================================================

// ---- type parameter name family (ReportMissingTypeParameterName + reserved-keyword variant) ----

test "016 generics: an empty type parameter list <> reports the missing-name NL102 spanning the '<>'" {
    errors := RunPreamble("func f<>()")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type parameter name. Got '>'"
    assert e.Line == 1
    assert e.Column == 7
    assert e.Length == 2
    assert e.SourceSnippet == "func f<>()"
    assert e.HumanExplanation == "Generic parameter lists need a type parameter name after each comma."
    assert e.ContextualHint == "Write generic parameters as `<T>` or `<T, U>`."
    assert e.Suggestion == "Add a type parameter name"
}

test "016 generics: a trailing comma in a type parameter list <T,> reports the missing-name NL102" {
    errors := RunPreamble("func f<T,>()")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type parameter name. Got '>'"
    assert e.Line == 1
    assert e.Column == 7
    assert e.Length == 4
    assert e.SourceSnippet == "func f<T,>()"
    assert e.HumanExplanation == "Generic parameter lists need a type parameter name after each comma."
    assert e.ContextualHint == "Write generic parameters as `<T>` or `<T, U>`."
    assert e.Suggestion == "Add a type parameter name"
}

test "016 generics: an empty type parameter list on a class reports the same missing-name NL102" {
    // Proves the type-parameter family fires from the class declaration head, not only the function head.
    errors := RunPreamble("class C<> {\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type parameter name. Got '>'"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 2
    assert e.SourceSnippet == "class C<> {"
    assert e.HumanExplanation == "Generic parameter lists need a type parameter name after each comma."
    assert e.ContextualHint == "Write generic parameters as `<T>` or `<T, U>`."
    assert e.Suggestion == "Add a type parameter name"
}

test "016 generics: a reserved keyword as a type parameter name reports the keyword-specific NL109" {
    errors := RunPreamble("func f<return>()")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected type parameter name. Got the reserved keyword 'return'"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 6
    assert e.SourceSnippet == "func f<return>()"
    assert e.HumanExplanation == "'return' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'returnValue' or '_return')."
    assert e.Suggestion == "Rename it to 'returnValue' or '_return'"
}

// ---- generic type argument family (ReportMissingGenericTypeArgument via the return type) ----

test "016 generics: an empty generic argument list Name<> reports the missing-argument NL102" {
    errors := RunPreamble("func f(): List<>")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '>'"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 6
    assert e.SourceSnippet == "func f(): List<>"
    assert e.HumanExplanation == "Generic type 'List' needs a type argument between '<' and '>'."
    assert e.ContextualHint == "Write this type as `List<T>` or remove the generic argument list."
    assert e.Suggestion == "Add a type argument"
}

test "016 generics: a trailing comma in a generic argument list Name<T,> reports the missing-argument NL102" {
    errors := RunPreamble("func f(): List<int,>")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '>'"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 10
    assert e.SourceSnippet == "func f(): List<int,>"
    assert e.HumanExplanation == "Generic type 'List' needs a type argument between '<' and '>'."
    assert e.ContextualHint == "Write this type as `List<T>` or remove the generic argument list."
    assert e.Suggestion == "Add a type argument"
}

test "016 generics: the missing-argument message and span name the offending generic type" {
    // A different type name (Dictionary) proves the message/hint interpolate the type name and the
    // span runs from the type name to the '>'.
    errors := RunPreamble("func f(): Dictionary<int,>")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '>'"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 16
    assert e.SourceSnippet == "func f(): Dictionary<int,>"
    assert e.HumanExplanation == "Generic type 'Dictionary' needs a type argument between '<' and '>'."
    assert e.ContextualHint == "Write this type as `Dictionary<T>` or remove the generic argument list."
    assert e.Suggestion == "Add a type argument"
}

// ---- ConsumeGreater unclosed type-argument list ----

test "016 generics: an unclosed generic argument list reports the ConsumeGreater NL102 at the offender" {
    // `List<int =>` : after `int` the argument list is not closed by '>' or '>>', so ConsumeGreater
    // reports at the '=>' token; the function then continues into its expression body (panic-suppressed).
    errors := RunPreamble("func f(): List<int => 5")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '>'. Got '=>'"
    assert e.Line == 1
    assert e.Column == 20
    assert e.Length == 2
    assert e.SourceSnippet == "func f(): List<int => 5"
    assert e.HumanExplanation == "I was parsing generic type parameters and expected to see a closing '>' here."
    assert e.ContextualHint == null
    assert e.Suggestion == "Check if you have matching '<' and '>' in your generic type declaration"
}

// ---- ConsumeGreater split >> discipline (NEGATIVE: a well-formed nested generic reports nothing) ----

test "016 generics: a well-formed nested generic List<List<int>> reports nothing (the >> split closes both)" {
    // Proves the split-`>>` discipline: the lexer emits one `>>` token for the two closing angles; without
    // the split, ConsumeGreater would (wrongly) report "Expected '>'. Got '>>'". Zero diagnostics is the proof.
    errors := RunPreamble("func f(): List<List<int>> => 5")
    assert errors.Count == 0
}

// ---- where-clause constraint validations (InvalidSyntax) ----

test "016 constraints: combining 'class' and 'struct' reports the mutual-exclusion NL103 anchored on 'struct'" {
    errors := RunPreamble("func f<T>() where T: class, struct")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Cannot have both 'class' and 'struct' constraints on the same type parameter — they are mutually exclusive"
    assert e.Line == 1
    assert e.Column == 29
    assert e.Length == 6
    assert e.SourceSnippet == "func f<T>() where T: class, struct"
    assert e.HumanExplanation == "A type parameter cannot be both a reference type (class) and a value type (struct) at the same time."
    assert e.ContextualHint == null
    assert e.Suggestion == null
}

test "016 constraints: combining 'struct' and 'new()' reports the redundancy NL103 spanning 'new()'" {
    errors := RunPreamble("func f<T>() where T: struct, new()")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Cannot combine 'struct' and 'new()' constraints — 'struct' already implies a parameterless constructor"
    assert e.Line == 1
    assert e.Column == 30
    assert e.Length == 5
    assert e.SourceSnippet == "func f<T>() where T: struct, new()"
    assert e.HumanExplanation == "The 'struct' constraint already requires a parameterless constructor, so 'new()' is redundant and not permitted in ."
    assert e.ContextualHint == null
    assert e.Suggestion == null
}

// ---- where-clause name / colon errors ----

test "016 constraints: a missing type parameter name after 'where' reports the found NL102 on the ':'" {
    errors := RunPreamble("func f<T>() where : class")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type parameter. Got ':'"
    assert e.Line == 1
    assert e.Column == 19
    assert e.Length == 1
    assert e.SourceSnippet == "func f<T>() where : class"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found ':' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e.Suggestion == null
}

test "016 constraints: a reserved keyword after 'where' reports the keyword-specific NL109" {
    errors := RunPreamble("func f<T>() where return: class")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected type parameter. Got the reserved keyword 'return'"
    assert e.Line == 1
    assert e.Column == 19
    assert e.Length == 6
    assert e.SourceSnippet == "func f<T>() where return: class"
    assert e.HumanExplanation == "'return' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'returnValue' or '_return')."
    assert e.Suggestion == "Rename it to 'returnValue' or '_return'"
}

test "016 constraints: a missing ':' after the constraint type parameter reports the Consume NL102" {
    errors := RunPreamble("func f<T>() where T class")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':'. Expected ':', got 'class'"
    assert e.Line == 1
    assert e.Column == 21
    assert e.Length == 5
    assert e.SourceSnippet == "func f<T>() where T class"
    assert e.HumanExplanation == "I was expecting : here, but I found 'class' instead."
    assert e.ContextualHint == null
    assert e.Suggestion == null
}

test "016 constraints: a non-type constraint reports the type-name NL102 then a boundary-reset NL101" {
    // `where T: 5` : the constraint type parse reports "Expected type name. Got '5'" (panic set) without
    // consuming `5`; the function head ends, the declaration boundary resets panic, and `5` reports its
    // own unexpected-token NL101. Proves the constraint type routes through ParseTypeReference and the
    // shared-panic boundary reset carries into the generics stage.
    errors := RunPreamble("func f<T>() where T: 5")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected type name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 22
    assert e0.Length == 1
    assert e0.SourceSnippet == "func f<T>() where T: 5"
    assert e0.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e0.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e0.Suggestion == null

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 22
    assert e1.Length == 1
    assert e1.SourceSnippet == "func f<T>() where T: 5"
    assert e1.HumanExplanation == "I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '5' instead."
    assert e1.ContextualHint == "Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases."
}

// ---- panic-model boundary interaction: two generic errors both report at their own boundary ----

test "016 generics: two functions with empty type parameter lists each report at their declaration boundary" {
    errors := RunPreamble("func f<>()\nfunc g<>()")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected type parameter name. Got '>'"
    assert e0.Line == 1
    assert e0.Column == 7
    assert e0.Length == 2
    assert e0.SourceSnippet == "func f<>()"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected type parameter name. Got '>'"
    assert e1.Line == 2
    assert e1.Column == 7
    assert e1.Length == 2
    assert e1.SourceSnippet == "func g<>()"
}

test "016 generics: two functions with empty generic return types each report at their declaration boundary" {
    errors := RunPreamble("func f(): List<>\nfunc g(): List<>")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected type name. Got '>'"
    assert e0.Line == 1
    assert e0.Column == 11
    assert e0.Length == 6
    assert e0.SourceSnippet == "func f(): List<>"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected type name. Got '>'"
    assert e1.Line == 2
    assert e1.Column == 11
    assert e1.Length == 6
    assert e1.SourceSnippet == "func g(): List<>"
}

// ---- negatives: well-formed generics / constraints report nothing (no over-reporting) ----

test "016 generics: a well-formed single type parameter reports no parser diagnostic" {
    errors := RunPreamble("func f<T>()")
    assert errors.Count == 0
}

test "016 generics: a well-formed multi type parameter list reports no parser diagnostic" {
    errors := RunPreamble("func f<T, U>()")
    assert errors.Count == 0
}

test "016 generics: a well-formed generic return type List<int> reports no parser diagnostic" {
    errors := RunPreamble("func f(): List<int>")
    assert errors.Count == 0
}

test "016 constraints: a well-formed single-type constraint reports no parser diagnostic" {
    errors := RunPreamble("func f<T>() where T: SomeBase")
    assert errors.Count == 0
}

test "016 generics: a well-formed generic class declaration reports no parser diagnostic" {
    errors := RunPreamble("class C<T> {\n}")
    assert errors.Count == 0
}

// ============================================================================
// Task-016 parser-front-end arc, Stage 6: the STATEMENT diagnostic family.
//
// Extends the function head with a real block-body grammar (the `func f() { <statements> }`
// vehicle Stages 3-5 deliberately left unparsed) and carries, through the SAME shared-panic
// recovery model: the dangling binary/assignment operator (ParseRightOperandOrMissing,
// "Expected expression after 'X'", the through-token span); the missing-initializer `:=`/`=`
// forms and the missing if/while condition (ParseRequiredExpressionAfter); the missing
// for/foreach `in` (ReportMissingInKeywordAndRecover); the missing statement body
// (ReportMissingStatementBody); and the SynchronizeToNextStatement sync point + per-statement
// panic reset + _currentRecoveryBoundaryColumn tracking (Parser.cs ParseBlock :2172 /
// SynchronizeToNextStatement :7084). Every expected value is the GOLDEN output of the production
// Parser.cs path, captured out-of-band from the freshly built Release CLI (`nlc check --json`) on
// the same malformed source, filtered to the parser diagnostic codes NL101-NL109 (excluding the
// line-0 columnar-backend decline NL103, which is not a parser diagnostic).
//
// The corpus keeps every function body closed and free of nested type declarations, so the block's
// own missing-'}' (NL106) report and the IsBlockClosingDeclarationStart break are not exercised —
// the broader closing-delimiter family (missing `)`/`]`/`}`) remains a later arc stage.
// ============================================================================

// ---- dangling binary / assignment operator (through-token span) ----

test "016 stmt: a dangling binary '+' reports NL102 spanning the left operand through the operator" {
    // `first := 1 +` then a new statement on the next line at the same column: the recovery-boundary
    // column makes the '+' right operand missing (does not swallow `second := 2`). Exactly one diag.
    errors := RunPreamble("func test() {\n    first := 1 +\n    second := 2\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '+'"
    assert e.Line == 2
    assert e.Column == 14
    assert e.Length == 3
    assert e.SourceSnippet == "    first := 1 +"
    assert e.HumanExplanation == "The '+' operator needs an expression on its right side."
    assert e.ContextualHint == "Finish the expression after the operator, or remove the operator if the expression is already complete."
    assert e.Suggestion == "Add an expression after '+'"
}

test "016 stmt: a dangling assignment '=' reports NL102 anchored on the assignment target" {
    // `value =` with `print value` on the next line: the '=' right operand is missing; the span is
    // the target `value` (DiagnosticSpanFromExpression), column 5, length 5.
    errors := RunPreamble("func test() {\n    value := 1\n    value =\n    print value\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '='"
    assert e.Line == 3
    assert e.Column == 5
    assert e.Length == 5
    assert e.SourceSnippet == "    value ="
    assert e.HumanExplanation == "The '=' operator needs an expression on its right side."
    assert e.ContextualHint == "Finish the expression after the operator, or remove the operator if the expression is already complete."
    assert e.Suggestion == "Add an expression after '='"
}

// ---- missing initializer (`:=`) ----

test "016 stmt: a shorthand `:=` with no initializer anchors NL102 on the declaration target" {
    errors := RunPreamble("func test() {\n    name :=\n    greeting := 2\n    print greeting\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an initializer expression after ':='"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 4
    assert e.SourceSnippet == "    name :="
    assert e.HumanExplanation == "This shorthand variable declaration needs an initializer expression after ':='."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add an initializer expression after ':='"
}

test "016 stmt: a `let` declaration with no initializer anchors NL102 on the variable name" {
    errors := RunPreamble("func test() {\n    let x :=\n    print 1\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an initializer expression after ':='"
    assert e.Line == 2
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "    let x :="
    assert e.HumanExplanation == "This variable declaration needs an initializer expression after ':='."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add an initializer expression after ':='"
}

test "016 stmt: a `const` declaration with no initializer anchors NL102 on the variable name" {
    errors := RunPreamble("func test() {\n    const y :=\n    print 1\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an initializer expression after ':='"
    assert e.Line == 2
    assert e.Column == 11
    assert e.Length == 1
    assert e.SourceSnippet == "    const y :="
    assert e.HumanExplanation == "This variable declaration needs an initializer expression after ':='."
}

// ---- print missing expression ----

test "016 stmt: a `print` with no expression anchors NL102 on the 'print' keyword" {
    errors := RunPreamble("func test() {\n    print\n    greeting := 2\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an expression to print after 'print'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 5
    assert e.SourceSnippet == "    print"
    assert e.HumanExplanation == "This print statement needs an expression to print after 'print'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add an expression to print after 'print'"
}

// ---- missing condition (if / while) ----

test "016 stmt: a `while` with no condition anchors NL102 on the 'while' keyword" {
    errors := RunPreamble("func test() {\n    while {\n        print 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a condition expression after 'while'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 5
    assert e.SourceSnippet == "    while {"
    assert e.HumanExplanation == "This while statement needs a condition expression after 'while'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add a condition expression after 'while'"
}

test "016 stmt: an `if` with no condition anchors NL102 on the 'if' keyword" {
    errors := RunPreamble("func test() {\n    if {\n        print 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a condition expression after 'if'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 2
    assert e.SourceSnippet == "    if {"
    assert e.HumanExplanation == "This if statement needs a condition expression after 'if'."
    assert e.Suggestion == "Add a condition expression after 'if'"
}

// ---- missing `in` (for / foreach) ----

test "016 stmt: a `foreach` with a missing 'in' anchors NL102 on the 'foreach' keyword" {
    errors := RunPreamble("func test() {\n    foreach item items {\n        print item\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected 'in' between the loop variable and collection"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 7
    assert e.SourceSnippet == "    foreach item items {"
    assert e.HumanExplanation == "This foreach statement needs the 'in' keyword between the loop variable and the collection."
    assert e.ContextualHint == "Write `foreach item in ...`."
    assert e.Suggestion == "Add 'in' after 'item'"
}

test "016 stmt: a `for` with a missing 'in' anchors NL102 on the 'for' keyword" {
    errors := RunPreamble("func test() {\n    for item items {\n        print item\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected 'in' between the loop variable and collection"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 3
    assert e.SourceSnippet == "    for item items {"
    assert e.HumanExplanation == "This for-in statement needs the 'in' keyword between the loop variable and the collection."
    assert e.ContextualHint == "Write `for item in ...`."
    assert e.Suggestion == "Add 'in' after 'item'"
}

// ---- missing statement body (if / while / for) ----

test "016 stmt: an `if` with a condition but no body anchors the missing-body NL102 on 'if'" {
    errors := RunPreamble("func test() {\n    if true\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected statement body. Got '}'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 2
    assert e.SourceSnippet == "    if true"
    assert e.HumanExplanation == "This control-flow keyword needs a statement or block after its condition."
    assert e.ContextualHint == "Add a block like `{ ... }`, or add a single statement after the keyword."
    assert e.Suggestion == "Add a block body"
}

test "016 stmt: a `while` with a condition but no body anchors the missing-body NL102 on 'while'" {
    errors := RunPreamble("func test() {\n    while true\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected statement body. Got '}'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 5
    assert e.SourceSnippet == "    while true"
}

test "016 stmt: a `for item in items` with no body anchors the missing-body NL102 on 'for'" {
    errors := RunPreamble("func test() {\n    for item in items\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected statement body. Got '}'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 3
    assert e.SourceSnippet == "    for item in items"
}

// ---- panic-model interactions at statement granularity ----

test "016 stmt: two malformed statements each report at their own statement boundary (does not swallow)" {
    // The per-statement panic reset (Parser.cs :2172) lets BOTH `:=` errors fire — the statement-level
    // analogue of Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements.
    errors := RunPreamble("func test() {\n    a :=\n    b :=\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected an initializer expression after ':='"
    assert e0.Line == 2
    assert e0.Column == 5
    assert e0.Length == 1
    assert e0.SourceSnippet == "    a :="

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected an initializer expression after ':='"
    assert e1.Line == 3
    assert e1.Column == 5
    assert e1.Length == 1
    assert e1.SourceSnippet == "    b :="
}

test "016 stmt: a within-statement cascade is suppressed by shared panic (while: no condition, no body)" {
    // `while` with neither a condition nor a body: the missing-condition error sets panic, so the
    // missing-body report in the SAME statement is suppressed — exactly one diagnostic.
    errors := RunPreamble("func test() {\n    while\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a condition expression after 'while'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 5
    assert e.SourceSnippet == "    while"
}

test "016 stmt: a valid statement between two malformed ones does not suppress either" {
    errors := RunPreamble("func test() {\n    a :=\n    print 1\n    b :=\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected an initializer expression after ':='"
    assert e0.Line == 2
    assert e0.Column == 5

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected an initializer expression after ':='"
    assert e1.Line == 4
    assert e1.Column == 5
}

test "016 stmt: a dangling operator in one function and a missing initializer in the next each fire" {
    // The declaration-boundary reset (Parser.cs SynchronizeToNextDeclaration) carries across functions:
    // f's dangling '+' and g's missing `:=` both report.
    errors := RunPreamble("func f() {\n    x := 1 +\n}\nfunc g() {\n    y :=\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected expression after '+'"
    assert e0.Line == 2
    assert e0.Column == 10
    assert e0.Length == 3
    assert e0.SourceSnippet == "    x := 1 +"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected an initializer expression after ':='"
    assert e1.Line == 5
    assert e1.Column == 5
    assert e1.Length == 1
    assert e1.SourceSnippet == "    y :="
}

test "016 stmt: nested block statements reset panic at each inner statement boundary" {
    // Two malformed `:=` inside a well-formed `while true { … }` body: both report (the inner block's
    // per-statement reset), and the outer while condition/body are well-formed.
    errors := RunPreamble("func test() {\n    while true {\n        a :=\n        b :=\n    }\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected an initializer expression after ':='"
    assert e0.Line == 3
    assert e0.Column == 9

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected an initializer expression after ':='"
    assert e1.Line == 4
    assert e1.Column == 9
}

// ---- negatives: a well-formed statement body reports no parser diagnostic ----

test "016 stmt: a well-formed shorthand declaration and print report no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := 1\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 stmt: a well-formed binary initializer reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := 1 + 2\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 stmt: a well-formed assignment reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := 1\n    x = 2\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 stmt: a well-formed `while true { … }` with a bool condition reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    while true {\n        print 1\n    }\n}\n")
    assert errors.Count == 0
}

test "016 stmt: a well-formed `foreach item in items { … }` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    foreach item in items {\n        print item\n    }\n}\n")
    assert errors.Count == 0
}

test "016 stmt: a bare `return` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    return\n}\n")
    assert errors.Count == 0
}

test "016 stmt: an empty function body reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n}\n")
    assert errors.Count == 0
}

// ============================================================================
// Task-016 parser-front-end arc, Stage 7: parity contracts for the EXPRESSIONS / PATTERNS diagnostic
// family — the fuller precedence ladder plus the expression ERROR families Stages 3/6 kept panic-
// suppressed (unexpected-token-in-expression, prefix `+`, leading `.`, ternary errors, dangling binary
// operators across every ladder tier, await/must/throw missing-operand, and member-name-after-dot).
// Every expected value below is the GOLDEN output of the freshly built Release CLI oracle
// (`nlc check --json`, NL101-NL109, excluding the columnar-backend emit-decline NL103 — not a parser
// diagnostic). The statement expression is reached through the SAME `func test() { x := <expr> }`
// shorthand-declaration vehicle Stage 6 uses (the `:=` initializer routes into ParseExpression).
// ============================================================================

// ---- unexpected token in expression (Parser.cs ParsePrimaryExpression terminal arm :4813) ----

test "016 expr: an operator where an expression is required reports the unexpected-token NL101" {
    errors := RunPreamble("func test() {\n    x := * 3\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedToken
    assert e.Message == "Unexpected token '*' in expression"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 1
    assert e.SourceSnippet == "    x := * 3"
    assert e.HumanExplanation == "I was parsing an expression and found '*', which I don't know how to handle here."
    assert e.ContextualHint == "Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax."
    assert e.Suggestion == null
}

// ---- prefix `+` (Parser.cs ParseInvalidPrefixPlusExpression :3816, NL103 InvalidSyntax) ----

test "016 expr: a leading '+' reports the prefix-plus NL103 spanning the operand" {
    errors := RunPreamble("func test() {\n    x := + 3\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Prefix '+' is not supported"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 3
    assert e.SourceSnippet == "    x := + 3"
    assert e.HumanExplanation == "A leading '+' does not change the value in N#, so it is not part of the expression grammar."
    assert e.ContextualHint == "Remove the leading '+'. Numeric literals and variables are already positive unless you subtract or negate them."
    assert e.Suggestion == "Remove the leading '+'"
}

// ---- leading `.` (Parser.cs ParseLeadingMemberAccessWithoutReceiver :6407) ----

test "016 expr: a leading '.' with no receiver reports NL102 spanning the dot through the member" {
    errors := RunPreamble("func test() {\n    x := .Foo\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression before '.'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    x := .Foo"
    assert e.HumanExplanation == "I see a dot (.) operator, but there is no receiver expression before it."
    assert e.ContextualHint == "Put an expression before '.', or remove the member access."
    assert e.Suggestion == "Add a receiver before '.'"
}

// ---- member name after dot (Parser.cs ReportMissingMemberNameAfterDot :6385 + reserved-keyword :4433) ----

test "016 expr: a trailing '.' with no member name anchors NL102 on the receiver" {
    errors := RunPreamble("func test() {\n    x := a.\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected member name. Got '}'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 1
    assert e.SourceSnippet == "    x := a."
    assert e.HumanExplanation == "I see a dot (.) operator but no member name after it."
    assert e.ContextualHint == "After dot (.), I need to see a property or method name."
    assert e.Suggestion == "Check if you forgot to finish this line"
}

test "016 expr: a reserved keyword as a member name reports NL109 anchored on the keyword" {
    errors := RunPreamble("func test() {\n    x := a.class\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected member name. Got the reserved keyword 'class'"
    assert e.Line == 2
    assert e.Column == 12
    assert e.Length == 5
    assert e.SourceSnippet == "    x := a.class"
    assert e.HumanExplanation == "'class' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "After a member access, the name must not be a reserved keyword. To reach a  member literally named 'class', access it through a differently-named alias."
    assert e.Suggestion == "Rename it to 'classValue' or '_class'"
}

// ---- ternary errors (Parser.cs ParseTernaryExpression :4009) ----

test "016 expr: a ternary with a missing then-expression anchors NL102 through the '?'" {
    errors := RunPreamble("func test() {\n    x := a ?\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a then expression after '?'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 3
    assert e.SourceSnippet == "    x := a ?"
    assert e.HumanExplanation == "This ternary expression needs a then expression after '?'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add a then expression after '?'"
}

test "016 expr: a ternary with a missing ':' reports the generic Consume NL102 on the offender" {
    errors := RunPreamble("func test() {\n    x := a ? b c\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' in ternary expression. Expected ':', got 'c'"
    assert e.Line == 2
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "    x := a ? b c"
    assert e.HumanExplanation == "I was expecting : here, but I found 'c' instead."
    assert e.ContextualHint == null
    assert e.Suggestion == null
}

test "016 expr: a ternary with a missing else-expression anchors NL102 through the ':'" {
    errors := RunPreamble("func test() {\n    x := a ? b :\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an else expression after ':'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 7
    assert e.SourceSnippet == "    x := a ? b :"
    assert e.HumanExplanation == "This ternary expression needs an else expression after ':'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add an else expression after ':'"
}

// ---- dangling binary operator across every new ladder tier (Parser.cs ParseBinaryRightOperandOrMissing
//      :3778) — one per precedence tier the fuller ladder adds over Stage 6's additive/multiplicative ----

test "016 expr: a dangling '??' (null-coalescing tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a ??\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '??'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    x := a ??"
    assert e.HumanExplanation == "The '??' operator needs an expression on its right side."
    assert e.ContextualHint == "Finish the expression after the operator, or remove the operator if the expression is already complete."
    assert e.Suggestion == "Add an expression after '??'"
}

test "016 expr: a dangling '||' (logical-or tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a ||\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Message == "Expected expression after '||'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    x := a ||"
}

test "016 expr: a dangling '&&' (logical-and tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a &&\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Message == "Expected expression after '&&'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    x := a &&"
}

test "016 expr: a dangling '|' (bitwise-or tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a |\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Message == "Expected expression after '|'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 3
    assert e.SourceSnippet == "    x := a |"
}

test "016 expr: a dangling '^' (bitwise-xor tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a ^\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Message == "Expected expression after '^'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 3
    assert e.SourceSnippet == "    x := a ^"
}

test "016 expr: a dangling '&' (bitwise-and tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a &\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Message == "Expected expression after '&'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 3
    assert e.SourceSnippet == "    x := a &"
}

test "016 expr: a dangling '==' (equality tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a ==\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Message == "Expected expression after '=='"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    x := a =="
}

test "016 expr: a dangling '<' (relational tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a <\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Message == "Expected expression after '<'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 3
    assert e.SourceSnippet == "    x := a <"
}

test "016 expr: a dangling '<<' (shift tier) reports the through-token NL102" {
    errors := RunPreamble("func test() {\n    x := a <<\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Message == "Expected expression after '<<'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    x := a <<"
}

// ---- await / must / throw missing operand (Parser.cs ParseUnaryOperandOrMissing :3789) ----

test "016 expr: an `await` with no operand anchors NL102 on the 'await' keyword" {
    errors := RunPreamble("func test() {\n    x := await\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an expression to await after 'await'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 5
    assert e.SourceSnippet == "    x := await"
    assert e.HumanExplanation == "This await expression needs an expression to await after 'await'."
    assert e.ContextualHint == "Add an expression to await after 'await', or remove 'await'."
    assert e.Suggestion == "Add an expression to await after 'await'"
}

test "016 expr: a `must` with no operand anchors NL102 on the 'must' keyword" {
    errors := RunPreamble("func test() {\n    x := must\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a nullable expression to unwrap after 'must'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    x := must"
    assert e.HumanExplanation == "This must expression needs a nullable expression to unwrap after 'must'."
    assert e.ContextualHint == "Add a nullable expression to unwrap after 'must', or remove 'must'."
    assert e.Suggestion == "Add a nullable expression to unwrap after 'must'"
}

test "016 expr: a `throw` with no operand anchors NL102 on the 'throw' keyword" {
    errors := RunPreamble("func test() {\n    x := throw\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an exception expression to throw after 'throw'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 5
    assert e.SourceSnippet == "    x := throw"
    assert e.HumanExplanation == "This throw expression needs an exception expression to throw after 'throw'."
    assert e.ContextualHint == "Add an exception expression to throw after 'throw', or remove 'throw'."
    assert e.Suggestion == "Add an exception expression to throw after 'throw'"
}

// ---- panic-model interactions within expressions and at statement boundaries ----

test "016 expr: an initializer terminator triggers the missing-init NL102 then the unexpected-token NL101 at the reset boundary" {
    // `)` is an expression terminator, so the `:=` initializer boundary fires first (panic set); the
    // per-statement reset then lets the stray `)` report its own unexpected-token diagnostic.
    errors := RunPreamble("func test() {\n    x := )\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected an initializer expression after ':='"
    assert e0.Line == 2
    assert e0.Column == 5
    assert e0.Length == 1
    assert e0.SourceSnippet == "    x := )"

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token ')' in expression"
    assert e1.Line == 2
    assert e1.Column == 10
    assert e1.Length == 1
    assert e1.SourceSnippet == "    x := )"
}

test "016 expr: two dangling operators in different statements each report (per-statement reset)" {
    errors := RunPreamble("func test() {\n    x := a ||\n    y := b &&\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Message == "Expected expression after '||'"
    assert e0.Line == 2
    assert e0.Column == 10

    e1 := errors[1]
    assert e1.Message == "Expected expression after '&&'"
    assert e1.Line == 3
    assert e1.Column == 10
}

test "016 expr: an unexpected token is skipped so the following statement still parses" {
    // The unexpected `*` is skipped (ShouldSkipUnexpectedExpressionToken), and the following valid
    // `print 1` reports nothing — exactly one diagnostic.
    errors := RunPreamble("func test() {\n    x := *\n    print 1\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedToken
    assert e.Message == "Unexpected token '*' in expression"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 1
    assert e.SourceSnippet == "    x := *"
}

test "016 expr: a within-expression prefix-plus cascade is suppressed by shared panic" {
    // The first `+` reports the prefix-plus error and sets panic; the recursive unary operand is a
    // second `+` whose own prefix-plus report is suppressed — exactly one diagnostic.
    errors := RunPreamble("func test() {\n    x := + + 3\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Prefix '+' is not supported"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 3
    assert e.SourceSnippet == "    x := + + 3"
}

test "016 expr: a leading-dot error in one function and a dangling operator in the next each fire" {
    // The declaration-boundary reset carries across functions: f's leading `.` and g's dangling `==`
    // both report.
    errors := RunPreamble("func f() {\n    x := .Foo\n}\nfunc g() {\n    y := b ==\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected expression before '.'"
    assert e0.Line == 2
    assert e0.Column == 10
    assert e0.Length == 4
    assert e0.SourceSnippet == "    x := .Foo"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected expression after '=='"
    assert e1.Line == 5
    assert e1.Column == 10
    assert e1.Length == 4
    assert e1.SourceSnippet == "    y := b =="
}

// ---- negatives: well-formed expressions across the fuller ladder report no parser diagnostic ----

test "016 expr: a well-formed logical chain `a || b && c` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := a || b && c\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed comparison `a < b` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := a < b\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed unary `!a` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := !a\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed member-access chain `a.b.c` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := a.b.c\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed null-conditional member access `a?.b` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := a?.b\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed ternary `a ? b : c` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := a ? b : c\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed parenthesized multiplicative `(a + b) * c` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := (a + b) * c\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed range `a..b` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := a..b\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed postfix increment `a++` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := a++\n    print x\n}\n")
    assert errors.Count == 0
}

test "016 expr: a well-formed shift `a << b` reports no parser diagnostic" {
    errors := RunPreamble("func test() {\n    x := a << b\n    print x\n}\n")
    assert errors.Count == 0
}

// ============================================================================
// Task-016 parser-front-end arc, Stage 8: parity contracts for the MATCH / PATTERN diagnostic family
// (Stage-7's recorded cut B). The `match` keyword-led primary (the MINIMAL vehicle Stage 7 deferred) is
// reached through the Stage-6 block-body statement grammar (`func f() { match … }`); the match value,
// each `when` guard, and each case body descend the full Stage-7 ladder. Every expected value below is
// the GOLDEN output of the freshly built Release CLI oracle (`nlc check --json`, NL101-NL109). The match
// case loop makes progress via EnsureProgress but does NOT reset panic per case (Parser.cs :5399, unlike
// the union per-case reset :1216), so a pattern / arrow / comma error cascade-suppresses the rest of the
// match; the statement boundary between two match statements DOES reset it (proven below).
// ============================================================================

// ---- the pattern terminal "Invalid pattern. Got 'X'" (Parser.cs ParsePrimaryPattern :3440, NL103) ----

test "016 match: a non-pattern token reports the NL103 invalid-pattern terminal anchored on the offender" {
    errors := RunPreamble("func f() {\n    match x {\n        + => 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Invalid pattern. Got '+'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "        + => 1"
    assert e.HumanExplanation == "I couldn't recognize this as a valid pattern for matching."
    assert e.ContextualHint == "Patterns can be literals, identifiers, types, or destructuring patterns."
    assert e.Suggestion == "Literal pattern: case 5 => ..."
}

test "016 match: a different non-pattern operator reaches the same NL103 invalid-pattern terminal" {
    errors := RunPreamble("func f() {\n    match x {\n        * => 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Invalid pattern. Got '*'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "        * => 1"
}

test "016 match: a reserved keyword where a pattern is required hits the invalid-pattern terminal spanning the keyword" {
    // `return` is a reserved keyword, not an identifier, so ParsePrimaryPattern's identifier branch is
    // not taken and it falls to the terminal; the span is the keyword's own length (Current.Value.Length).
    errors := RunPreamble("func f() {\n    match x {\n        return => 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Invalid pattern. Got 'return'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 6
    assert e.SourceSnippet == "        return => 1"
}

test "016 match: the guard keyword `when` in pattern position hits the invalid-pattern terminal" {
    errors := RunPreamble("func f() {\n    match x {\n        when => 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Invalid pattern. Got 'when'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 4
    assert e.SourceSnippet == "        when => 1"
}

// ---- the match Consume sites (Parser.cs ParseMatchExpression :5368) ----

test "016 match: a missing '{' after the match value reports the NL102 expected-brace diagnostic" {
    errors := RunPreamble("func f() {\n    match x\n        1 => 10\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '{'. Expected '{', got '1'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "        1 => 10"
    assert e.HumanExplanation == "I was expecting { here, but I found '1' instead."
    assert e.ContextualHint == null
    assert e.Suggestion == null
}

test "016 match: a missing '=>' after the pattern reports the NL102 expected-arrow diagnostic" {
    // TokenTypeToString(Arrow) has no explicit case, so it renders as "arrow" (Parser.cs :6341).
    errors := RunPreamble("func f() {\n    match x {\n        1 2\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '=>'. Expected 'arrow', got '2'"
    assert e.Line == 3
    assert e.Column == 11
    assert e.Length == 1
    assert e.SourceSnippet == "        1 2"
    assert e.HumanExplanation == "I was expecting arrow here, but I found '2' instead."
    assert e.ContextualHint == null
}

test "016 match: a missing ',' between cases reports the NL102 expected-comma diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        1 => 10\n        2 => 20\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ',' between match cases. Expected ',', got '2'"
    assert e.Line == 4
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "        2 => 20"
    assert e.HumanExplanation == "I was expecting , here, but I found '2' instead."
    assert e.ContextualHint == null
}

test "016 match: an unterminated match at end of file reports the NL104 unexpected-end-of-file diagnostic" {
    // After the last case body the loop needs a ',' before the (absent) '}', and the file ends first,
    // so the comma Consume reports the end-of-file variant anchored on the last visible token ('10').
    errors := RunPreamble("func f() {\n    match x {\n        1 => 10\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected ',' but reached the end of the file"
    assert e.Line == 3
    assert e.Column == 14
    assert e.Length == 2
    assert e.SourceSnippet == "        1 => 10"
    assert e.HumanExplanation == "I was expecting ',' here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

// ---- the property-pattern sites (Parser.cs ParsePropertyPatterns :3459) ----

test "016 match: a non-identifier property name reports the NL102 expected-property-name diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        { 5: y } => 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected property name. Got '5'"
    assert e.Line == 3
    assert e.Column == 11
    assert e.Length == 1
    assert e.SourceSnippet == "        { 5: y } => 1"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e.Suggestion == null
}

test "016 match: a reserved keyword as a property name reports the NL109 reserved-keyword diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        { class: y } => 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected property name. Got the reserved keyword 'class'"
    assert e.Line == 3
    assert e.Column == 11
    assert e.Length == 5
    assert e.SourceSnippet == "        { class: y } => 1"
    assert e.HumanExplanation == "'class' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'classValue' or '_class')."
    assert e.Suggestion == "Rename it to 'classValue' or '_class'"
}

test "016 match: an object pattern with no closing '}' re-enters the loop and reports the next property name" {
    // The missing '}' is not the closing-delimiter family here: the property loop sees `=>` (not '}'),
    // tries to read another property name, and reports NL102 on '=>' before the pattern's own '}' close.
    errors := RunPreamble("func f() {\n    match x {\n        { Name: y => 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected property name. Got '=>'"
    assert e.Line == 3
    assert e.Column == 19
    assert e.Length == 2
    assert e.SourceSnippet == "        { Name: y => 1"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '=>' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
}

// ---- the qualified-name pattern site (Parser.cs ParsePrimaryPattern :3417) ----

test "016 match: a qualified pattern name with a trailing dot reports the NL102 dot-access diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        Result. => 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected identifier after '.'. Got '=>'"
    assert e.Line == 3
    assert e.Column == 17
    assert e.Length == 2
    assert e.SourceSnippet == "        Result. => 1"
    assert e.HumanExplanation == "I see a dot (.) operator but no member name after it. I found '=>' instead."
    assert e.ContextualHint == "After a dot, I need to see a property or method name."
    assert e.Suggestion == "Check if you forgot to finish this line"
}

// ---- the shared-panic model across match cases and match statements ----

test "016 match: two bad patterns in one match report ONCE - the case loop does not reset panic" {
    // Parser.cs :5399 uses EnsureProgress with no `_panicMode = false`, so the second pattern error is
    // suppressed by the panic the first set (the cascading-suppression shape, no intervening reset).
    errors := RunPreamble("func f() {\n    match x {\n        + => 1,\n        / => 2\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Invalid pattern. Got '+'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "        + => 1,"
}

test "016 match: two separate match statements each report their first pattern error - the statement boundary resets panic" {
    // The block-body statement boundary (Parser.cs ParseBlock :2172) resets panic between the two match
    // statements, so the second match's first bad pattern reports its own diagnostic.
    errors := RunPreamble("func f() {\n    match a {\n        + => 1\n    }\n    match b {\n        / => 2\n    }\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.InvalidSyntax
    assert e0.Message == "Invalid pattern. Got '+'"
    assert e0.Line == 3
    assert e0.Column == 9
    assert e0.Length == 1
    assert e0.SourceSnippet == "        + => 1"

    e1 := errors[1]
    assert e1.Code == ErrorCode.InvalidSyntax
    assert e1.Message == "Invalid pattern. Got '/'"
    assert e1.Line == 6
    assert e1.Column == 9
    assert e1.Length == 1
    assert e1.SourceSnippet == "        / => 2"
}

// ---- negatives: well-formed matches / patterns report NO parser diagnostic ----

test "016 match: well-formed literal, identifier, and type patterns report no parser diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        1 => 10,\n        y => 20,\n        int z => 30\n    }\n}\n")
    assert errors.Count == 0
}

test "016 match: well-formed relational, or, and, and not patterns report no parser diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        < 5 => 1,\n        1 or 2 => 2,\n        > 0 and < 9 => 3,\n        not 4 => 4\n    }\n}\n")
    assert errors.Count == 0
}

test "016 match: well-formed list, positional, object, union-case, and guarded patterns report no parser diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        [1, 2, 3] => 1,\n        (a, b) => 2,\n        { Name: n } => 3,\n        Result.Ok { value: v } => 4,\n        n when n > 5 => 5\n    }\n}\n")
    assert errors.Count == 0
}

test "016 match: well-formed list slice patterns report no parser diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        [1, .., 3] => 1,\n        [.. rest] => 2\n    }\n}\n")
    assert errors.Count == 0
}

// ============================================================================
// Stage 9: the CLOSING-DELIMITER recovery family (Parser.cs TryReportMissingClosingDelimiter :6103 +
// the block / type-body missing-'}' reports + the parameter trailing-comma recovery). Every golden
// below is the production Parser.cs output captured from the freshly built Release CLI (`nlc check
// --json`), filtered to NL101-NL109 (excluding the columnar-backend emit-decline NL103, a backend
// diagnostic anchored at Main.nl:1:1 — not a parser diagnostic). Both paths construct through the
// identical live ParserErrorDiagnostics.Create, so matching these fields proves byte-exact parity.
// ============================================================================

// ---- the same-line-boundary trigger (found != null): the offender stands in for the close ----

test "016 close: an unclosed positional pattern before a same-line '=>' reports NL107 anchored on the arrow" {
    // The '=>' is a same-line boundary for ')' (IsSameLineMissingClosingDelimiterBoundary), so the
    // recovery anchors on the arrow and synthesizes ')' so `=> 10` parses — one diagnostic only.
    errors := RunPreamble("func f() {\n    match x {\n        (1, 2 => 10\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 3
    assert e.Column == 15
    assert e.Length == 2
    assert e.SourceSnippet == "        (1, 2 => 10"
    assert e.HumanExplanation == "I found '=>' while looking for the closing ')' that matches an earlier '('."
    assert e.ContextualHint == "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
    assert e.Suggestion == "Add ')' before '=>'"
}

// ---- the next-line trigger (found == null): anchored on the unmatched opening delimiter ----

test "016 close: an unclosed list pattern that crosses onto the next line reports NL108 anchored on the '['" {
    // The next line begins before the ']' is found, so the recovery anchors on the unmatched '[' (no
    // visible owner sits on its line — the match '{' is on the line above) and reads "reached the next line".
    errors := RunPreamble("func f() {\n    match x {\n        [1, 2\n        => 10\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBracket
    assert e.Message == "Missing closing ']'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "        [1, 2"
    assert e.HumanExplanation == "I reached the next line while looking for the closing ']' that matches an earlier '['."
    assert e.ContextualHint == "Every opening bracket '[' needs a matching closing bracket ']'."
    assert e.Suggestion == "Add ']' before starting the next line"
}

test "016 close: a 'new(' constraint left unclosed at end of file reports NL107 anchored on the '('" {
    // where T: new( — the constraint's Consume(RightParen) routes through the closing-delimiter recovery.
    // 'new' is not a visible delimiter owner, so the diagnostic falls to the opening '(' itself.
    errors := RunPreamble("func f<T>() where T: new(\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 1
    assert e.Column == 25
    assert e.Length == 1
    assert e.SourceSnippet == "func f<T>() where T: new("
    assert e.HumanExplanation == "I reached the next line while looking for the closing ')' that matches an earlier '('."
    assert e.ContextualHint == "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
    assert e.Suggestion == "Add ')' before starting the next line"
}

// ---- the decline branch: a mid-line offender takes the standard ExpectedToken path (NL102) ----

test "016 close: a 'new(' immediately followed by a same-line comma declines recovery and reports the plain NL102" {
    // The ',' sits on the same line and is not a boundary token, so the recovery declines (returns false)
    // and the standard Consume ExpectedToken path fires — proving the boundary gate is byte-exact.
    errors := RunPreamble("func g<T>() where T: new(, IFoo\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ')' after 'new('. Expected ')', got ','"
    assert e.Line == 1
    assert e.Column == 26
    assert e.Length == 1
    assert e.SourceSnippet == "func g<T>() where T: new(, IFoo"
    assert e.HumanExplanation == "I was expecting ) here, but I found ',' instead."
    assert e.ContextualHint == "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
    assert e.Suggestion == null
}

// ---- the parameter trailing-comma recovery (Parser.cs :761) ----

test "016 close: a trailing comma in a parameter list reports NL102 spanning the last parameter through the comma" {
    errors := RunPreamble("func f(a: int,)\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected parameter name. Got ')'"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 7
    assert e.SourceSnippet == "func f(a: int,)"
    assert e.HumanExplanation == "Parameter lists need another parameter after a comma."
    assert e.ContextualHint == "Add the missing parameter after the comma, or remove the trailing comma."
    assert e.Suggestion == "Add a parameter after the comma"
}

// ---- the block's own missing-'}' (NL106) — end-of-file and found-declaration variants ----

test "016 close: a block left open at end of file reports the NL106 missing-brace anchored on the function name" {
    errors := RunPreamble("func f() {\n    x := 1\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBrace
    assert e.Message == "Missing closing '}'"
    assert e.Line == 1
    assert e.Column == 6
    assert e.Length == 1
    assert e.SourceSnippet == "func f() {"
    assert e.HumanExplanation == "The block that started on line 1 is missing its closing brace. I reached the end of the file without finding it."
    assert e.ContextualHint == "Add a '}' to close this block."
}

test "016 close: a type declaration mid-block signals the missing '}' with the found-declaration NL106" {
    // 'class' cannot appear as a statement (IsBlockClosingDeclarationStart), so the block is presumed
    // unclosed and the class is left for the outer declaration loop (which parses it cleanly).
    errors := RunPreamble("func f() {\n    x := 1\nclass C {\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBrace
    assert e.Message == "Missing closing '}'"
    assert e.Line == 1
    assert e.Column == 6
    assert e.Length == 1
    assert e.SourceSnippet == "func f() {"
    assert e.HumanExplanation == "The block that started on line 1 appears to be missing its closing brace. I found 'class' on line 3, which looks like a new declaration."
    assert e.ContextualHint == "Add a '}' before this declaration to close the previous block."
}

// ---- panic-model interactions ----

test "016 close: two unclosed positional patterns in one match report ONCE - the case loop does not reset panic" {
    // The first NL107 sets shared panic; the per-case EnsureProgress boundary does NOT reset it, so the
    // second case's own unclosed-')' (and the intervening missing comma) are suppressed.
    errors := RunPreamble("func f() {\n    match x {\n        (1, 2\n        => 10\n        (3, 4\n        => 20\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 1
}

test "016 close: two functions each with an unclosed 'new(' each report - the declaration boundary resets panic" {
    errors := RunPreamble("func f<T>() where T: new(\nfunc g<T>() where T: new(\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.MissingClosingParen
    assert e0.Message == "Missing closing ')'"
    assert e0.Line == 1
    assert e0.Column == 25
    assert e0.Length == 1

    e1 := errors[1]
    assert e1.Code == ErrorCode.MissingClosingParen
    assert e1.Message == "Missing closing ')'"
    assert e1.Line == 2
    assert e1.Column == 25
    assert e1.Length == 1
}

test "016 close: a found-declaration break then an unclosed type body report two NL106 (block then type-body)" {
    // The mid-block 'class' fires the block found-declaration NL106; the declaration boundary resets panic;
    // then the class body reaches end-of-file unclosed and reports the type-body NL106 anchored on the name.
    errors := RunPreamble("func f() {\n    x := 1\nclass C {\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.MissingClosingBrace
    assert e0.Message == "Missing closing '}'"
    assert e0.Line == 1
    assert e0.Column == 6
    assert e0.Length == 1
    assert e0.HumanExplanation == "The block that started on line 1 appears to be missing its closing brace. I found 'class' on line 3, which looks like a new declaration."

    e1 := errors[1]
    assert e1.Code == ErrorCode.MissingClosingBrace
    assert e1.Message == "Missing closing '}'"
    assert e1.Line == 3
    assert e1.Column == 7
    assert e1.Length == 1
    assert e1.HumanExplanation == "The type body that started on line 3 is missing its closing brace. I reached the end of the file without finding it."
}

// ---- negatives: closed delimiters report NO parser diagnostic ----

test "016 close: a closed 'new()' constraint reports no parser diagnostic" {
    // The oracle emits only the columnar-backend emit-decline NL103 (a backend diagnostic, not a parser
    // one); the recovery owner produces no parser diagnostic here.
    errors := RunPreamble("func f<T>() where T: new()\n")
    assert errors.Count == 0
}

test "016 close: a type declaration AFTER a properly closed block reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    x := 1\n}\nclass C {\n}\n")
    assert errors.Count == 0
}

test "016 close: well-formed closed positional and list patterns report no parser diagnostic" {
    errors := RunPreamble("func f() {\n    match x {\n        (1, 2) => 1,\n        [3, 4] => 2\n    }\n}\n")
    assert errors.Count == 0
}

// ============================================================================
// Stage 10: the POSTFIX CALL / INDEX / generic-call / `with {…}` + call-argument family (map item [1]) and
// the first KEYWORD-LED-PRIMARY tranche — new / cast / tuple / typeof (+ nameof / sizeof / checked /
// unchecked) / array (map item [2]). Golden values captured from the freshly built Release CLI oracle
// (`nlc check --json`, NL101-NL109, excluding the backend emit-decline NL103@Main.nl:1:1). Reached through
// the Stage-6 block-body statement vehicle `func f() { <expr> }`.
// ============================================================================

// ---- the CALL-ARGUMENT family (Parser.cs ParseArgumentList :4533) ----

test "016 call: an inline out declaration reports the NL103 anchored across both identifiers" {
    errors := RunPreamble("func f() {\n    g(out x y)\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Inline out declarations are not supported"
    assert e.Line == 2
    assert e.Column == 11
    assert e.Length == 3
    assert e.SourceSnippet == "    g(out x y)"
    assert e.HumanExplanation == "N# out arguments must refer to a variable that already exists."
    assert e.ContextualHint == "Declare 'y' before the call, then pass 'out y'."
    assert e.Suggestion == null
}

test "016 call: an unclosed argument list that crosses onto the next line reports NL107 anchored on the callee" {
    errors := RunPreamble("func f() {\n    g(1, 2\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 1
    assert e.SourceSnippet == "    g(1, 2"
    assert e.HumanExplanation == "I reached the next line while looking for the closing ')' that matches an earlier '('."
    assert e.ContextualHint == "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
    assert e.Suggestion == "Add ')' before starting the next line"
}

test "016 call: named arguments report no parser diagnostic" {
    errors := RunPreamble("func f() {\n    g(a: 1, b: 2)\n}\n")
    assert errors.Count == 0
}

test "016 call: a spread argument reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    g(...items)\n}\n")
    assert errors.Count == 0
}

test "016 call: a bare alloc-family keyword argument reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    g(alloc, 1)\n}\n")
    assert errors.Count == 0
}

// ---- postfix INDEX (Parser.cs :4444) ----

test "016 index: a well-formed index access reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := a[0]\n}\n")
    assert errors.Count == 0
}

test "016 index: an unclosed index that crosses onto the next line reports NL108 anchored on the object" {
    errors := RunPreamble("func f() {\n    y := a[0\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBracket
    assert e.Message == "Missing closing ']'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 1
    assert e.SourceSnippet == "    y := a[0"
    assert e.HumanExplanation == "I reached the next line while looking for the closing ']' that matches an earlier '['."
    assert e.ContextualHint == "Every opening bracket '[' needs a matching closing bracket ']'."
    assert e.Suggestion == "Add ']' before starting the next line"
}

// ---- postfix generic-call (Parser.cs :4452) ----

test "016 gencall: a well-formed generic method call reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := M<int>()\n}\n")
    assert errors.Count == 0
}

test "016 gencall: a well-formed generic call with arguments and nested generics reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := M<List<int>>(1, 2)\n}\n")
    assert errors.Count == 0
}

test "016 gencall: an unclosed generic-call argument list reports NL107 anchored on the callee" {
    errors := RunPreamble("func f() {\n    y := M<int>(1, 2\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 2
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "    y := M<int>(1, 2"
    assert e.HumanExplanation == "I reached the next line while looking for the closing ')' that matches an earlier '('."
    assert e.Suggestion == "Add ')' before starting the next line"
}

// ---- postfix WITH (Parser.cs :4500) ----

test "016 with: a well-formed with-expression reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := a with { X: 1 }\n}\n")
    assert errors.Count == 0
}

test "016 with: a missing '{' after 'with' reports the NL102 expected-brace via the standard Consume path" {
    errors := RunPreamble("func f() {\n    y := a with X\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '{'. Expected '{', got 'X'"
    assert e.Line == 2
    assert e.Column == 17
    assert e.Length == 1
    assert e.SourceSnippet == "    y := a with X"
    assert e.HumanExplanation == "I was expecting { here, but I found 'X' instead."
    assert e.ContextualHint == null
    assert e.Suggestion == null
}

test "016 with: a missing ':' after a with-property name reports the NL102 expected-colon" {
    errors := RunPreamble("func f() {\n    y := a with { X 1 }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':'. Expected ':', got '1'"
    assert e.Line == 2
    assert e.Column == 21
    assert e.Length == 1
    assert e.SourceSnippet == "    y := a with { X 1 }"
    assert e.HumanExplanation == "I was expecting : here, but I found '1' instead."
    assert e.ContextualHint == null
}

test "016 with: a non-identifier with-property name reports the NL102 expected-property-name" {
    errors := RunPreamble("func f() {\n    y := a with { 5: 1 }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected property name. Got '5'"
    assert e.Line == 2
    assert e.Column == 19
    assert e.Length == 1
    assert e.SourceSnippet == "    y := a with { 5: 1 }"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
}

test "016 with: two bad with-properties report ONCE - the with loop's EnsureProgress does not reset panic" {
    // `{ X 1 Y 2 }`: the first missing-colon sets panic; the with loop makes natural progress but (unlike the
    // new-object / match-case reset) does NOT reset panic, so the second property error is suppressed.
    errors := RunPreamble("func f() {\n    y := a with { X 1 Y 2 }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':'. Expected ':', got '1'"
    assert e.Line == 2
    assert e.Column == 21
    assert e.Length == 1
}

// ---- the keyword-led primary `new` (Parser.cs ParseNewExpression :5209) ----

test "016 new: target-typed new() reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := new()\n}\n")
    assert errors.Count == 0
}

test "016 new: a typed constructor call reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := new Foo()\n}\n")
    assert errors.Count == 0
}

test "016 new: a target-typed object initializer reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := new { X: 1 }\n}\n")
    assert errors.Count == 0
}

test "016 new: a typed object initializer reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := new Foo { X: 1 }\n}\n")
    assert errors.Count == 0
}

test "016 new: a sized array with a collection initializer reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := new Foo[2] { a, b }\n}\n")
    assert errors.Count == 0
}

test "016 new: a `new` with no type before a terminator reports the NL102 expected-type-name on 'new'" {
    errors := RunPreamble("func f() {\n    y := new\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '}'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 3
    assert e.SourceSnippet == "    y := new"
    assert e.HumanExplanation == "The `new` expression needs a type name, `()`, or an initializer after it."
    assert e.ContextualHint == "Write `new TypeName(...)`, `new()`, or `new { Name: value }`."
    assert e.Suggestion == "Add a type name after `new`"
}

test "016 new: a missing ':' in an object initializer reports NL102, and the panic reset lets the next member's name error fire" {
    // The object-initializer loop resets panic on natural progress (Parser.cs :5334), so BOTH the missing-colon
    // and the following bad property name report — the DISTINCT reset discipline from the with / match loops.
    errors := RunPreamble("func f() {\n    y := new Foo { X 1 }\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected ':' after object initializer member 'X'"
    assert e0.Line == 2
    assert e0.Column == 20
    assert e0.Length == 1
    assert e0.HumanExplanation == "Object initializer member 'X' needs ':' before its value."
    assert e0.ContextualHint == "Write 'X: value'."
    assert e0.Suggestion == "Add ':' after 'X'"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected property name. Got '1'"
    assert e1.Line == 2
    assert e1.Column == 22
    assert e1.Length == 1
}

test "016 new: a non-identifier object-initializer member name reports the NL102 property-name error once" {
    errors := RunPreamble("func f() {\n    y := new Foo { 5: 1 }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected property name. Got '5'"
    assert e.Line == 2
    assert e.Column == 20
    assert e.Length == 1
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
}

test "016 new: an unclosed constructor argument list reports NL107 anchored on the type name" {
    errors := RunPreamble("func f() {\n    y := new Foo(1, 2\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 2
    assert e.Column == 14
    assert e.Length == 3
    assert e.SourceSnippet == "    y := new Foo(1, 2"
    assert e.Suggestion == "Add ')' before starting the next line"
}

test "016 new: an unclosed sized-array length reports NL108 anchored on the type name" {
    errors := RunPreamble("func f() {\n    y := new Foo[3\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBracket
    assert e.Message == "Missing closing ']'"
    assert e.Line == 2
    assert e.Column == 14
    assert e.Length == 3
    assert e.SourceSnippet == "    y := new Foo[3"
    assert e.Suggestion == "Add ']' before starting the next line"
}

// ---- the keyword-led primary CAST (Parser.cs :4783, disambiguated from tuple/paren by IsCastExpression) ----

test "016 cast: a hard cast reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := (int)x\n}\n")
    assert errors.Count == 0
}

test "016 cast: a cast whose operand is a unary expression reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := (int)-x\n}\n")
    assert errors.Count == 0
}

// ---- the keyword-led primary TUPLE / parenthesized (Parser.cs ParseTupleOrParenthesizedExpression :5428) ----

test "016 tuple: an unnamed tuple reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := (a, b)\n}\n")
    assert errors.Count == 0
}

test "016 tuple: a named tuple reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := (x: 1, z: 2)\n}\n")
    assert errors.Count == 0
}

test "016 tuple: an empty tuple reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := ()\n}\n")
    assert errors.Count == 0
}

test "016 tuple: a missing ':' after a named-tuple element name reports the NL102 expected-colon" {
    errors := RunPreamble("func f() {\n    y := (x: 1, z 2)\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':'. Expected ':', got '2'"
    assert e.Line == 2
    assert e.Column == 19
    assert e.Length == 1
    assert e.SourceSnippet == "    y := (x: 1, z 2)"
    assert e.HumanExplanation == "I was expecting : here, but I found '2' instead."
    assert e.ContextualHint == null
}

// ---- the keyword-led primaries typeof / nameof / sizeof (the shared `( … )` shape, Parser.cs :4700) ----

test "016 typeof: a well-formed typeof reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := typeof(int)\n}\n")
    assert errors.Count == 0
}

test "016 typeof: a missing '(' after typeof reports the NL102 expected-paren via the standard Consume path" {
    errors := RunPreamble("func f() {\n    y := typeof int)\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '('. Expected '(', got 'int'"
    assert e.Line == 2
    assert e.Column == 17
    assert e.Length == 3
    assert e.SourceSnippet == "    y := typeof int)"
    assert e.HumanExplanation == "I was expecting ( here, but I found 'int' instead."
    assert e.ContextualHint == null
}

test "016 typeof: an unclosed typeof argument reports NL107 anchored on the opening paren" {
    errors := RunPreamble("func f() {\n    y := typeof(int\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 2
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "    y := typeof(int"
    assert e.Suggestion == "Add ')' before starting the next line"
}

test "016 nameof: a well-formed nameof reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := nameof(x)\n}\n")
    assert errors.Count == 0
}

test "016 sizeof: a well-formed sizeof reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := sizeof(int)\n}\n")
    assert errors.Count == 0
}

// ---- the keyword-led primary ARRAY literal (Parser.cs ParseArrayLiteral :5407) ----

test "016 array: a well-formed array literal reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := [1, 2, 3]\n}\n")
    assert errors.Count == 0
}

test "016 array: an unclosed array literal reports NL108 anchored on the assignment target" {
    // No visible delimiter owner sits before '['; the recovery falls to the assignment anchor 'y'.
    errors := RunPreamble("func f() {\n    y := [1, 2\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBracket
    assert e.Message == "Missing closing ']'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 1
    assert e.SourceSnippet == "    y := [1, 2"
    assert e.Suggestion == "Add ']' before starting the next line"
}

// ---- postfix chaining negatives + a cross-declaration panic-reset interaction ----

test "016 postfix: a mixed member / call / index chain reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := a.b().c(1)[0]\n}\n")
    assert errors.Count == 0
}

test "016 postfix: two functions each with an unclosed call each report - the declaration boundary resets panic" {
    errors := RunPreamble("func f() {\n    g(1, 2\n}\nfunc h() {\n    k(3, 4\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.MissingClosingParen
    assert e0.Message == "Missing closing ')'"
    assert e0.Line == 2
    assert e0.Column == 5
    assert e0.Length == 1

    e1 := errors[1]
    assert e1.Code == ErrorCode.MissingClosingParen
    assert e1.Message == "Missing closing ')'"
    assert e1.Line == 5
    assert e1.Column == 5
    assert e1.Length == 1
    assert e1.SourceSnippet == "    k(3, 4"
}
