namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

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

test "017 generics: a nested generic closed by a split >> then '?' reports nothing" {
    // Regression: while a split `>` is owed, Check must answer false for every non-`>` request — the
    // owed `>` is the effective current token. Before the fix, Check(Question) matched the real `?`
    // after the split `>>`, the paired Advance consumed the owed `>` instead, the inner type was
    // nullable-wrapped twice, and the outer close reported a spurious "Expected '>'".
    errors := RunPreamble("func f(m: Dictionary<string, List<int>>?) {\n}\n")
    assert errors.Count == 0
}

test "017 generics: a >>? nested generic in return-type position reports nothing" {
    errors := RunPreamble("func f(): List<Dictionary<string, object>>? {\n    return null\n}\n")
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

// ============================================================================
// Stage 11: the remaining keyword-led primaries (alloc / stackalloc / lambda; map item [1]) and the
// `is` / `as` TYPE sub-grammar (map item [2]), carried through the SAME shared-panic model. Every expected
// value below is the golden output of the freshly built Release CLI oracle (`nlc check --json`, NL101-NL109,
// excluding the columnar-backend emit-decline NL103 anchored at Main.nl:1:1). The interpolated-string `$"…"`
// hole grammar is DEFERRED to Stage 12 (fresh sub-Lexer + sub-Parser + per-hole position adjustment); the
// malformed-`$"…"` NL105 is already owned (Stage 3).
// ============================================================================

// ---- the `is` / `as` relational TYPE sub-grammar (Parser.cs ParseRelationalExpression :4132) ----

test "016 is: a well-formed `is` type test reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := x is int\n}\n")
    assert errors.Count == 0
}

test "016 is: an `is` type test with a pattern variable name reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := x is string s\n}\n")
    assert errors.Count == 0
}

test "017 is: the pattern variable does not greedily continue onto the next line" {
    // Regression: statements are newline-terminated, so an identifier that OPENS the next line starts a
    // new statement. Before the same-line gate, `flag := x is string` swallowed the next line's `other`
    // as the pattern variable and reported "Unexpected token ':='" on the orphaned assignment.
    errors := RunPreamble("func f(x: object) {\n    flag := x is string\n    other := 42\n}\n")
    assert errors.Count == 0
}

test "016 as: a well-formed `as` safe cast reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := x as Foo\n}\n")
    assert errors.Count == 0
}

test "016 is: an `is` test against a generic type reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := x is List<int>\n}\n")
    assert errors.Count == 0
}

test "016 is: a missing type after `is` reports the NL102 expected-type-name via the type-reference recovery" {
    errors := RunPreamble("func f() {\n    y := x is\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '}'"
    assert e.Line == 3
    assert e.Column == 1
    assert e.Length == 1
    assert e.SourceSnippet == "}"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '}' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e.Suggestion == null
}

test "016 as: a missing type after `as` reports the NL102 expected-type-name" {
    errors := RunPreamble("func f() {\n    y := x as\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '}'"
    assert e.Line == 3
    assert e.Column == 1
    assert e.Length == 1
    assert e.SourceSnippet == "}"
}

test "016 is: a missing type after `is` in a call argument anchors the NL102 on the closing paren" {
    errors := RunPreamble("func f() {\n    print(x is)\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got ')'"
    assert e.Line == 2
    assert e.Column == 15
    assert e.Length == 1
    assert e.SourceSnippet == "    print(x is)"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found ')' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
}

test "016 is: an empty generic argument list after `is` reports the NL102 missing-type-argument" {
    errors := RunPreamble("func f() {\n    y := x is List<>\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '>'"
    assert e.Line == 2
    assert e.Column == 15
    assert e.Length == 6
    assert e.SourceSnippet == "    y := x is List<>"
    assert e.HumanExplanation == "Generic type 'List' needs a type argument between '<' and '>'."
    assert e.ContextualHint == "Write this type as `List<T>` or remove the generic argument list."
    assert e.Suggestion == "Add a type argument"
}

test "016 is: a trailing dot in the `is` qualified type name reports the NL102 dot-access variant" {
    errors := RunPreamble("func f() {\n    y := x is A.\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected identifier after '.'. Got '}'"
    assert e.Line == 3
    assert e.Column == 1
    assert e.Length == 1
    assert e.SourceSnippet == "}"
    assert e.HumanExplanation == "I see a dot (.) operator but no member name after it. I found '}' instead."
    assert e.ContextualHint == "After a dot, I need to see a property or method name."
    assert e.Suggestion == "Check if you forgot to finish this line"
}

test "016 as: an unclosed generic type after `as` reports the NL102 expected-greater via ConsumeGreater" {
    errors := RunPreamble("func f() {\n    y := x as List<int\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '>'. Got '}'"
    assert e.Line == 3
    assert e.Column == 1
    assert e.Length == 1
    assert e.SourceSnippet == "}"
    assert e.HumanExplanation == "I was parsing generic type parameters and expected to see a closing '>' here."
    assert e.ContextualHint == null
    assert e.Suggestion == "Check if you have matching '<' and '>' in your generic type declaration"
}

test "016 is: a reserved keyword as the `is` type name reports the NL109 reserved-keyword variant" {
    errors := RunPreamble("func f() {\n    y := x is return\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ReservedKeywordAsName
    assert e.Message == "Expected type name. Got the reserved keyword 'return'"
    assert e.Line == 2
    assert e.Column == 15
    assert e.Length == 6
    assert e.SourceSnippet == "    y := x is return"
    assert e.HumanExplanation == "'return' is a reserved keyword in N#, so it can't be used as a name here."
    assert e.ContextualHint == "Choose a name that isn't a reserved keyword (for example 'returnValue' or '_return')."
    assert e.Suggestion == "Rename it to 'returnValue' or '_return'"
}

test "016 is: two `is` type tests across a statement boundary - the first swallows the following name, the boundary resets panic" {
    // `y := x is\n z := w is`: after the first `is`, the type-reference consumes the next identifier `z`,
    // leaving `:=` as an unexpected token (NL101); the statement boundary resets panic, so `w is` then
    // reports its own missing-type NL102 against the closing brace.
    errors := RunPreamble("func f() {\n    y := x is\n    z := w is\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.UnexpectedToken
    assert e0.Message == "Unexpected token ':=' in expression"
    assert e0.Line == 3
    assert e0.Column == 7
    assert e0.Length == 2
    assert e0.SourceSnippet == "    z := w is"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected type name. Got '}'"
    assert e1.Line == 4
    assert e1.Column == 1
    assert e1.Length == 1
    assert e1.SourceSnippet == "}"
}

// ---- the keyword-led primary `alloc` (Parser.cs ParseAllocExpression :5178) ----

test "016 alloc: `alloc new Foo()` reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := alloc new Foo()\n}\n")
    assert errors.Count == 0
}

test "016 alloc: `alloc [ ... ]` array literal reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := alloc [1, 2, 3]\n}\n")
    assert errors.Count == 0
}

test "016 alloc: `alloc new Foo()` in a call argument reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    print(alloc new Foo())\n}\n")
    assert errors.Count == 0
}

test "016 alloc: a bare `alloc` with no operand routes to the NL101 unexpected-token terminal on the operand" {
    errors := RunPreamble("func f() {\n    y := alloc\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedToken
    assert e.Message == "Unexpected token '}' in expression"
    assert e.Line == 3
    assert e.Column == 1
    assert e.Length == 1
    assert e.SourceSnippet == "}"
    assert e.HumanExplanation == "I was parsing an expression and found '}', which I don't know how to handle here."
    assert e.ContextualHint == "Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax."
    assert e.Suggestion == null
}

test "016 alloc: `alloc new` with no type routes to the NL102 expected-type-name on `new`" {
    errors := RunPreamble("func f() {\n    y := alloc new\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '}'"
    assert e.Line == 2
    assert e.Column == 16
    assert e.Length == 3
    assert e.SourceSnippet == "    y := alloc new"
    assert e.HumanExplanation == "The `new` expression needs a type name, `()`, or an initializer after it."
    assert e.ContextualHint == "Write `new TypeName(...)`, `new()`, or `new { Name: value }`."
    assert e.Suggestion == "Add a type name after `new`"
}

// ---- the keyword-led primary `stackalloc` (Parser.cs ParseStackAllocExpression :5197) ----

test "016 stackalloc: a well-formed `stackalloc int[4]` reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := stackalloc int[4]\n}\n")
    assert errors.Count == 0
}

test "016 stackalloc: a well-formed `stackalloc` over a generic element type reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    y := stackalloc List<int>[4]\n}\n")
    assert errors.Count == 0
}

test "016 stackalloc: a missing '[' after the element type reports the distinct NL102 expected-bracket message" {
    errors := RunPreamble("func f() {\n    y := stackalloc int 4\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '[' after stackalloc element type. Expected '[', got '4'"
    assert e.Line == 2
    assert e.Column == 25
    assert e.Length == 1
    assert e.SourceSnippet == "    y := stackalloc int 4"
    assert e.HumanExplanation == "I was expecting [ here, but I found '4' instead."
    assert e.ContextualHint == null
    assert e.Suggestion == null
}

test "016 stackalloc: a missing type reports the NL102 expected-type-name via the type-reference recovery" {
    errors := RunPreamble("func f() {\n    y := stackalloc [4]\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '['"
    assert e.Line == 2
    assert e.Column == 21
    assert e.Length == 1
    assert e.SourceSnippet == "    y := stackalloc [4]"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '[' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
}

test "016 stackalloc: an unclosed ']' before the next line reports NL108 via the Stage-9 closing-delimiter recovery" {
    errors := RunPreamble("func f() {\n    y := stackalloc int[4\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBracket
    assert e.Message == "Missing closing ']'"
    assert e.Line == 2
    assert e.Column == 21
    assert e.Length == 3
    assert e.SourceSnippet == "    y := stackalloc int[4"
    assert e.HumanExplanation == "I reached the next line while looking for the closing ']' that matches an earlier '['."
    assert e.ContextualHint == "Every opening bracket '[' needs a matching closing bracket ']'."
    assert e.Suggestion == "Add ']' before starting the next line"
}

test "016 stackalloc: a mid-line offender where ']' is required declines recovery (NL102) then the stray ']' reports NL101" {
    // The mid-line `5` is not a same-line closing-delimiter boundary, so ConsumeToken declines the recovery
    // and reports the distinct "Expected ']' after stackalloc length" NL102 WITHOUT advancing; the statement
    // boundary resets panic, `5` parses as its own statement, and the leftover `]` hits the NL101 terminal.
    errors := RunPreamble("func f() {\n    y := stackalloc int[4 5]\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected ']' after stackalloc length. Expected ']', got '5'"
    assert e0.Line == 2
    assert e0.Column == 27
    assert e0.Length == 1
    assert e0.SourceSnippet == "    y := stackalloc int[4 5]"
    assert e0.ContextualHint == "Every opening bracket '[' needs a matching closing bracket ']'."

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token ']' in expression"
    assert e1.Line == 2
    assert e1.Column == 28
    assert e1.Length == 1
    assert e1.SourceSnippet == "    y := stackalloc int[4 5]"
}

// ---- the lambda family (Parser.cs ParseLambdaOrAssignmentExpression :3641) ----

test "016 lambda: a well-formed single-parameter lambda reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    g := x => x\n}\n")
    assert errors.Count == 0
}

test "016 lambda: a well-formed multi-parameter lambda reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    g := (x, y) => x\n}\n")
    assert errors.Count == 0
}

test "016 lambda: a well-formed empty-parameter lambda reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    g := () => 1\n}\n")
    assert errors.Count == 0
}

test "016 lambda: a well-formed block-body lambda reports no parser diagnostic" {
    errors := RunPreamble("func f() {\n    g := x => { }\n}\n")
    assert errors.Count == 0
}

test "016 lambda: a single-parameter lambda missing its body reports NL102 spanning the parameter through '=>'" {
    errors := RunPreamble("func f() {\n    g := x =>\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a lambda body expression after '=>'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    g := x =>"
    assert e.HumanExplanation == "This lambda expression needs a lambda body expression after '=>'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add a lambda body expression after '=>'"
}

test "016 lambda: a multi-parameter lambda missing its body reports NL102 spanning '(' through '=>'" {
    errors := RunPreamble("func f() {\n    g := (x, y) =>\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a lambda body expression after '=>'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 9
    assert e.SourceSnippet == "    g := (x, y) =>"
    assert e.HumanExplanation == "This lambda expression needs a lambda body expression after '=>'."
    assert e.Suggestion == "Add a lambda body expression after '=>'"
}

test "016 lambda: a missing lambda body does not swallow the following statement" {
    // `a := x =>` reaches the recovery boundary at the next line's `b :=` statement start, so it reports
    // its missing body ONCE and the well-formed `b := 1` statement parses cleanly.
    errors := RunPreamble("func f() {\n    a := x =>\n    b := 1\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a lambda body expression after '=>'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 4
    assert e.SourceSnippet == "    a := x =>"
}

test "016 lambda: two functions each with a body-less lambda each report - the declaration boundary resets panic" {
    errors := RunPreamble("func g() {\n    a := x =>\n}\nfunc h() {\n    b := y =>\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected a lambda body expression after '=>'"
    assert e0.Line == 2
    assert e0.Column == 10
    assert e0.Length == 4
    assert e0.SourceSnippet == "    a := x =>"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected a lambda body expression after '=>'"
    assert e1.Line == 5
    assert e1.Column == 10
    assert e1.Length == 4
    assert e1.SourceSnippet == "    b := y =>"
}

// ---- the interpolated-string `$"…"` HOLE family (Parser.cs ParseInterpolatedString :4932) ----
// Reached through the Stage-6 block-body statement vehicle `func f() { print $"…" }`, so the string
// primary descends the full expression ladder into ParsePrimaryExprValue's string-literal arm, which
// routes a `$"`-prefixed StringLiteral / InterpolatedRawStringLiteral into ParseInterpolatedString. Each
// hole opens a FRESH sub-Lexer + sub-Parser with its OWN panic universe; the hole errors are the owned
// expression grammar's, and the lone explicit report is the NL101 hole-tail. Golden values are the
// production Parser.cs path captured from the freshly built CLI (`nlc check --json`, NL101-NL109).

test "016 interpolation: a hole-free interpolated string reports no parser diagnostic" {
    errors := RunPreamble("func f() { print $\"hello\" }\n")
    assert errors.Count == 0
}

test "016 interpolation: a well-formed single hole reports no parser diagnostic" {
    errors := RunPreamble("func f() { print $\"hello {x}\" }\n")
    assert errors.Count == 0
}

test "016 interpolation: two well-formed holes report no parser diagnostic" {
    errors := RunPreamble("func f() { print $\"{x} and {y}\" }\n")
    assert errors.Count == 0
}

test "016 interpolation: a format-clause hole {x:D3} strips the format and reports no parser diagnostic" {
    errors := RunPreamble("func f() { print $\"{x:D3}\" }\n")
    assert errors.Count == 0
}

test "016 interpolation: escaped braces {{ }} are literal text and report no parser diagnostic" {
    errors := RunPreamble("func f() { print $\"a{{b}}c\" }\n")
    assert errors.Count == 0
}

test "016 interpolation: a well-formed nested interpolated string inside a hole reports no parser diagnostic" {
    errors := RunPreamble("func f() { print $\"{g($\"{y}\")}\" }\n")
    assert errors.Count == 0
}

test "016 interpolation: a well-formed raw interpolated string reports no parser diagnostic" {
    errors := RunPreamble("func f() { print $\"\"\"val {x}\"\"\" }\n")
    assert errors.Count == 0
}

test "016 interpolation: a dangling operator inside a hole reports the hole-expression NL102" {
    // The hole expression `a +` is sub-parsed with its position adjusted into the enclosing file, so the
    // dangling-operator span anchors on the hole's `a` (col 25) through `+`, exactly as the outer ladder.
    errors := RunPreamble("func f() { print $\"val {a +}\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '+'"
    assert e.Line == 1
    assert e.Column == 25
    assert e.Length == 3
    assert e.SourceSnippet == "func f() { print $\"val {a +}\" }"
    assert e.HumanExplanation == "The '+' operator needs an expression on its right side."
    assert e.ContextualHint == "Finish the expression after the operator, or remove the operator if the expression is already complete."
    assert e.Suggestion == "Add an expression after '+'"
}

test "016 interpolation: extra syntax after the hole expression reports the NL101 hole-tail" {
    errors := RunPreamble("func f() { print $\"val {a b}\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedToken
    assert e.Message == "Unexpected token 'b' after interpolated string expression"
    assert e.Line == 1
    assert e.Column == 27
    assert e.Length == 1
    assert e.SourceSnippet == "func f() { print $\"val {a b}\" }"
    assert e.HumanExplanation == "I parsed a valid expression at the start of this interpolation hole, but there was extra syntax after it."
    assert e.ContextualHint == "Keep exactly one expression inside each interpolation hole, or split additional text outside the braces."
    assert e.Suggestion == null
}

test "016 interpolation: the hole-tail fires on the FIRST trailing token only" {
    // `a b c` — the sub-parser parses `a`, then the hole-tail fires on `b`; `c` is never re-examined
    // (the sub-panic is set by the tail report), so exactly one diagnostic is produced.
    errors := RunPreamble("func f() { print $\"{a b c}\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedToken
    assert e.Message == "Unexpected token 'b' after interpolated string expression"
    assert e.Line == 1
    assert e.Column == 23
    assert e.Length == 1
    assert e.SourceSnippet == "func f() { print $\"{a b c}\" }"
}

test "016 interpolation: PANIC INDEPENDENCE - two bad holes in one string EACH report (fresh sub-parser per hole)" {
    // Each hole is parsed by a fresh sub-parser with its own panic, so the second bad hole is NOT suppressed
    // by the first — both dangling-operator diagnostics are produced.
    errors := RunPreamble("func f() { print $\"{a +} {b +}\" }\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected expression after '+'"
    assert e0.Line == 1
    assert e0.Column == 21
    assert e0.Length == 3
    assert e0.SourceSnippet == "func f() { print $\"{a +} {b +}\" }"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected expression after '+'"
    assert e1.Line == 1
    assert e1.Column == 27
    assert e1.Length == 3
}

test "016 interpolation: PANIC INDEPENDENCE - two bad-tail holes EACH report their hole-tail" {
    errors := RunPreamble("func f() { print $\"{a b} {c d}\" }\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.UnexpectedToken
    assert e0.Message == "Unexpected token 'b' after interpolated string expression"
    assert e0.Line == 1
    assert e0.Column == 23
    assert e0.Length == 1

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token 'd' after interpolated string expression"
    assert e1.Line == 1
    assert e1.Column == 29
    assert e1.Length == 1
}

test "016 interpolation: a bad first hole followed by a good hole reports only the first" {
    errors := RunPreamble("func f() { print $\"{a +} {b}\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '+'"
    assert e.Line == 1
    assert e.Column == 21
    assert e.Length == 3
}

test "016 interpolation: a good first hole followed by a bad hole reports only the second (independence)" {
    errors := RunPreamble("func f() { print $\"{a} {b +}\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '+'"
    assert e.Line == 1
    assert e.Column == 25
    assert e.Length == 3
}

test "016 interpolation: two holes with DIFFERENT error kinds each report independently" {
    errors := RunPreamble("func f() { print $\"{a +} and {c d}\" }\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected expression after '+'"
    assert e0.Line == 1
    assert e0.Column == 21
    assert e0.Length == 3

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token 'd' after interpolated string expression"
    assert e1.Line == 1
    assert e1.Column == 33
    assert e1.Length == 1
}

test "016 interpolation: a hole-expression error SUPPRESSES the hole-tail (sub-panic gates the tail)" {
    // `+ a b` — the prefix-`+` reports NL103 and sets the SUB-parser panic; the trailing `b` would be the
    // hole-tail, but the sub-parser is in panic, so the tail is suppressed. Exactly one diagnostic.
    errors := RunPreamble("func f() { print $\"{+ a b}\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Prefix '+' is not supported"
    assert e.Line == 1
    assert e.Column == 21
    assert e.Length == 3
    assert e.SourceSnippet == "func f() { print $\"{+ a b}\" }"
    assert e.HumanExplanation == "A leading '+' does not change the value in N#, so it is not part of the expression grammar."
    assert e.ContextualHint == "Remove the leading '+'. Numeric literals and variables are already positive unless you subtract or negate them."
    assert e.Suggestion == "Remove the leading '+'"
}

test "016 interpolation: a format-clause hole {a +:D3} strips the format then reports the hole-expression error" {
    // FindFormatSpecifierColon splits `:D3` off before the sub-parse, so the dangling `+` is the only error.
    errors := RunPreamble("func f() { print $\"{a +:D3}\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '+'"
    assert e.Line == 1
    assert e.Column == 21
    assert e.Length == 3
}

test "016 interpolation: a bad NESTED hole reports through the recursive sub-parse with composed positions" {
    // The outer hole's expression `g($"{y +}")` is itself sub-parsed; its interpolated-string argument recurses
    // into ParseInterpolatedString, and the inner hole's dangling `+` anchors at the composed file position.
    errors := RunPreamble("func f() { print $\"{g($\"{y +}\")}\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '+'"
    assert e.Line == 1
    assert e.Column == 26
    assert e.Length == 3
}

test "016 interpolation: a bad hole inside a RAW interpolated string reports the hole-expression error" {
    errors := RunPreamble("func f() { print $\"\"\"val {a +}\"\"\" }\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected expression after '+'"
    assert e.Line == 1
    assert e.Column == 27
    assert e.Length == 3
}

test "016 interpolation: INTERLEAVING - an outer prefix-plus AND a hole error BOTH report (outer panic does not suppress the hole)" {
    // The outer `+` reports NL103 and sets the OUTER panic BEFORE parsing its operand `$"{b +}"`; the hole's
    // fresh sub-parser records the dangling `+` regardless (mirroring Parser.cs's `_errors.AddRange` bypass).
    errors := RunPreamble("func g() { print + $\"{b +}\" }\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.InvalidSyntax
    assert e0.Message == "Prefix '+' is not supported"
    assert e0.Line == 1
    assert e0.Column == 18
    assert e0.Length == 10
    assert e0.SourceSnippet == "func g() { print + $\"{b +}\" }"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected expression after '+'"
    assert e1.Line == 1
    assert e1.Column == 23
    assert e1.Length == 3
}

test "016 interpolation: INTERLEAVING - a hole error recorded first but positioned after an outer dangling operator sorts correctly" {
    // `print $"{a +}" +` — the hole dangling (col 21) is RECORDED before the outer dangling `+` (span col 18),
    // but the diagnostics are presented position-sorted, so the outer error comes first (matching the oracle).
    errors := RunPreamble("func g() { print $\"{a +}\" + }\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected expression after '+'"
    assert e0.Line == 1
    assert e0.Column == 18
    assert e0.Length == 10
    assert e0.SourceSnippet == "func g() { print $\"{a +}\" + }"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected expression after '+'"
    assert e1.Line == 1
    assert e1.Column == 21
    assert e1.Length == 3
}

// ============================================================================
// Task-016 parser-front-end arc, Stage 13: parity contracts for the REMAINING statement kinds
// (residual map item [1]) — yield / break / continue / throw / try-catch-finally / using / lock /
// switch / allow / alloc-block / unsafe / assert / preprocessor / local-function / await-foreach /
// off / on, plus the C-style for(init;cond;incr) / tuple deconstruction / typed `name: T = value`
// declarations. Reached through the Stage-6 block-body vehicle `func f() { <statement> }`. Every
// expected value is the GOLDEN output of the production Parser.cs path, captured out-of-band from the
// freshly built Release CLI (`nlc check --json`) on the same malformed source, filtered to the parser
// diagnostic codes NL101-NL109 (excluding the line-0 columnar-backend decline NL103, and the SEMANTIC
// diagnostics — loop-context for break/continue/yield, generator-return, undefined name — which are
// analyzer diagnostics, not parser ones).
// ============================================================================

// ---- yield ----

test "016 stmt: yield with no value reports the missing-value NL102 anchored on 'yield'" {
    errors := RunPreamble("func f() {\n    yield\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a value to yield after 'yield'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 5
    assert e.SourceSnippet == "    yield"
    assert e.HumanExplanation == "This yield statement needs a value to yield after 'yield'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add a value to yield after 'yield'"
}

test "016 stmt: yield break (no value) parses clean" {
    errors := RunPreamble("func f() {\n    yield break\n}\n")
    assert errors.Count == 0
}

test "016 stmt: yield with a value parses clean (the generator-context check is semantic, not parser)" {
    errors := RunPreamble("func f() {\n    yield 1\n}\n")
    assert errors.Count == 0
}

// ---- break / continue ----

test "016 stmt: break and continue inside a loop parse clean (the loop-context check is semantic)" {
    errors := RunPreamble("func f() {\n    for x in items {\n        break\n        continue\n    }\n}\n")
    assert errors.Count == 0
}

// ---- throw ----

test "016 stmt: throw with no operand reports the missing-exception NL102 anchored on 'throw'" {
    errors := RunPreamble("func f() {\n    throw\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an exception expression after 'throw'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 5
    assert e.SourceSnippet == "    throw"
    assert e.HumanExplanation == "This throw statement needs an exception expression after 'throw'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add an exception expression after 'throw'"
}

test "016 stmt: throw of an expression parses clean" {
    errors := RunPreamble("func f() {\n    throw ex\n}\n")
    assert errors.Count == 0
}

// ---- try / catch / finally ----

test "016 stmt: a full try / catch / finally parses clean" {
    errors := RunPreamble("func f() {\n    try {\n        x := 1\n    } catch (Exception e) {\n        y := 2\n    } finally {\n        z := 3\n    }\n}\n")
    assert errors.Count == 0
}

test "016 stmt: a catch with a typed variable `(e: Exception)` parses clean" {
    errors := RunPreamble("func f() {\n    try {\n        x := 1\n    } catch (e: Exception) {\n        y := 2\n    }\n}\n")
    assert errors.Count == 0
}

test "016 stmt: an unclosed catch parameter list reports the NL107 via the closing-delimiter recovery" {
    errors := RunPreamble("func f() {\n    try {\n        x := 1\n    } catch (Exception e {\n        y := 2\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 4
    assert e.Column == 26
    assert e.Length == 1
    assert e.SourceSnippet == "    } catch (Exception e {"
    assert e.HumanExplanation == "I found '{' while looking for the closing ')' that matches an earlier '('."
    assert e.ContextualHint == "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
    assert e.Suggestion == "Add ')' before '{'"
}

// ---- lock ----

test "016 stmt: lock with no object expression reports the missing-object NL102 anchored on 'lock'" {
    errors := RunPreamble("func f() {\n    lock {\n        x := 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an object expression after 'lock'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 4
    assert e.SourceSnippet == "    lock {"
    assert e.HumanExplanation == "This lock statement needs an object expression after 'lock'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add an object expression after 'lock'"
}

test "016 stmt: lock obj { } and lock (obj) { } both parse clean" {
    errors := RunPreamble("func f() {\n    lock obj {\n        x := 1\n    }\n}\n")
    assert errors.Count == 0
    errors2 := RunPreamble("func f() {\n    lock (obj) {\n        x := 1\n    }\n}\n")
    assert errors2.Count == 0
}

// ---- unsafe / alloc block ----

test "016 stmt: an unsafe block parses clean" {
    errors := RunPreamble("func f() {\n    unsafe {\n        x := 1\n    }\n}\n")
    assert errors.Count == 0
}

test "016 stmt: an alloc block parses clean" {
    errors := RunPreamble("func f() {\n    alloc {\n        x := 1\n    }\n}\n")
    assert errors.Count == 0
}

// ---- assert ----

test "016 stmt: assert with no condition reports the missing-condition NL102 anchored on 'assert'" {
    errors := RunPreamble("func f() {\n    assert\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected a condition expression after 'assert'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 6
    assert e.SourceSnippet == "    assert"
    assert e.HumanExplanation == "This assert statement needs a condition expression after 'assert'."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add a condition expression after 'assert'"
}

test "016 stmt: assert with a condition, an optional message, and the throws form all parse clean" {
    errors := RunPreamble("func f() {\n    assert x\n}\n")
    assert errors.Count == 0
    errors2 := RunPreamble("func f() {\n    assert x, \"boom\"\n}\n")
    assert errors2.Count == 0
    errors3 := RunPreamble("func f() {\n    assert throws Foo {\n        x := 1\n    }\n}\n")
    assert errors3.Count == 0
}

// ---- preprocessor ----

test "016 stmt: preprocessor directives parse clean" {
    errors := RunPreamble("func f() {\n    #region Foo\n    x := 1\n    #endregion\n}\n")
    assert errors.Count == 0
}

// ---- switch ----

test "016 stmt: switch missing its opening brace reports NL102 at the offending 'case', and the func's own missing-} is panic-suppressed" {
    errors := RunPreamble("func f() {\n    switch x\n        case 1 => print 1\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '{'. Expected '{', got 'case'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 4
    assert e.SourceSnippet == "        case 1 => print 1"
    assert e.HumanExplanation == "I was expecting { here, but I found 'case' instead."
}

test "016 stmt: a switch branch that is neither case nor default reports the expected-case-or-default NL102" {
    errors := RunPreamble("func f() {\n    switch x {\n        1 => print 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected 'case' or 'default'. Got '1'"
    assert e.Line == 3
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "        1 => print 1"
    assert e.HumanExplanation == "Switch statements must contain 'case' patterns or a 'default' case."
    assert e.ContextualHint == "Each branch in a switch must start with 'case pattern =>' or 'default =>'"
    assert e.Suggestion == "Add a case: case 1 => { ... }"
}

test "016 stmt: a switch case missing its arrow reports NL102 with the 'arrow' expected token" {
    errors := RunPreamble("func f() {\n    switch x {\n        case 1 print 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '=>'. Expected 'arrow', got 'print'"
    assert e.Line == 3
    assert e.Column == 16
    assert e.Length == 5
    assert e.SourceSnippet == "        case 1 print 1"
    assert e.HumanExplanation == "I was expecting arrow here, but I found 'print' instead."
}

test "016 stmt: an unclosed switch body at EOF reports the switch-specific missing-} NL106" {
    errors := RunPreamble("func f() {\n    switch x {\n        case 1 => print 1\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBrace
    assert e.Message == "Missing closing '}'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 6
    assert e.SourceSnippet == "    switch x {"
    assert e.HumanExplanation == "The switch body that started on line 2 is missing its closing brace. I reached the end of the file without finding it."
    assert e.ContextualHint == "Add a '}' to close this switch statement."
}

test "016 stmt: two switches each with a bad branch both report (statement-boundary panic reset)" {
    errors := RunPreamble("func f() {\n    switch x {\n        1 => print 1\n    }\n    switch y {\n        2 => print 2\n    }\n}\n")
    assert errors.Count == 2
    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected 'case' or 'default'. Got '1'"
    assert e0.Line == 3
    assert e0.Column == 9
    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected 'case' or 'default'. Got '2'"
    assert e1.Line == 6
    assert e1.Column == 9
}

test "016 stmt: a switch with case and default branches parses clean" {
    errors := RunPreamble("func f() {\n    switch x {\n        case 1 => print 1\n        default => print 2\n    }\n}\n")
    assert errors.Count == 0
}

// ---- allow ----

test "016 stmt: allow missing its opening paren reports NL102 at the offending effect" {
    errors := RunPreamble("func f() {\n    allow alloc {\n        x := 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '(' after 'allow'. Expected '(', got 'alloc'"
    assert e.Line == 2
    assert e.Column == 11
    assert e.Length == 5
    assert e.SourceSnippet == "    allow alloc {"
    assert e.HumanExplanation == "I was expecting ( here, but I found 'alloc' instead."
}

test "016 stmt: allow with a non-effect token reports the systems-identifier NL102 then force-advances" {
    errors := RunPreamble("func f() {\n    allow(5) {\n        x := 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected allow effect or named argument. Got '5'"
    assert e.Line == 2
    assert e.Column == 11
    assert e.Length == 1
    assert e.SourceSnippet == "    allow(5) {"
    assert e.HumanExplanation == "Systems policy lists use effect names such as alloc, trap, dispatch, delegate, closure, or a named argument such as reason."
    assert e.ContextualHint == "Write allow(alloc, reason: \"...\") { ... } or remove this allow block."
}

test "016 stmt: allow(effect) and allow(effect, reason: ...) parse clean" {
    errors := RunPreamble("func f() {\n    allow(alloc) {\n        x := 1\n    }\n}\n")
    assert errors.Count == 0
    errors2 := RunPreamble("func f() {\n    allow(alloc, reason: \"why\") {\n        x := 1\n    }\n}\n")
    assert errors2.Count == 0
}

// ---- local function ----

test "016 stmt: a local function with no body reports the missing-body NL102 at the offending token" {
    errors := RunPreamble("func f() {\n    func inner(): int\n    print 1\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected function body or '=>' for expression-bodied function. Got 'print'"
    assert e.Line == 3
    assert e.Column == 5
    assert e.Length == 5
    assert e.SourceSnippet == "    print 1"
    assert e.HumanExplanation == "A function needs a body - either a block with braces { } or an expression after '=>'."
    assert e.ContextualHint == "Use '{ ... }' for a block body or '=> expression' for a single expression."
    assert e.Suggestion == "Add a block: { return value; }"
}

test "016 stmt: a local function missing the ':' before its return type reports NL102 anchored on the name" {
    errors := RunPreamble("func f() {\n    func inner() int {\n        return 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' before return type. Got 'int'"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 5
    assert e.SourceSnippet == "    func inner() int {"
    assert e.HumanExplanation == "Function 'inner' needs a ':' before its return type."
    assert e.ContextualHint == "Write the return type as `func name(...): Type { ... }`."
    assert e.Suggestion == "Add ':' before 'int'"
}

test "016 stmt: block-body / expression-body / static local functions all parse clean" {
    errors := RunPreamble("func f() {\n    func inner(): int {\n        return 1\n    }\n    print inner()\n}\n")
    assert errors.Count == 0
    errors2 := RunPreamble("func f() {\n    func inner(x: int): int => x\n    print inner(1)\n}\n")
    assert errors2.Count == 0
    errors3 := RunPreamble("func f() {\n    static func inner(): int {\n        return 1\n    }\n    print inner()\n}\n")
    assert errors3.Count == 0
}

test "016 stmt: two functions each with a body-less local function both report (declaration-boundary reset)" {
    errors := RunPreamble("func f() {\n    func a(): int\n}\nfunc g() {\n    func b(): int\n}\n")
    assert errors.Count == 2
    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected function body or '=>' for expression-bodied function. Got '}'"
    assert e0.Line == 3
    assert e0.Column == 1
    assert e0.Length == 1
    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected function body or '=>' for expression-bodied function. Got '}'"
    assert e1.Line == 6
    assert e1.Column == 1
}

// ---- await foreach ----

test "016 stmt: await foreach missing 'in' reports the missing-in NL102 anchored on 'foreach'" {
    errors := RunPreamble("func f() {\n    await foreach x items {\n        print x\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected 'in' between the loop variable and collection"
    assert e.Line == 2
    assert e.Column == 11
    assert e.Length == 7
    assert e.SourceSnippet == "    await foreach x items {"
    assert e.HumanExplanation == "This await foreach statement needs the 'in' keyword between the loop variable and the collection."
    assert e.ContextualHint == "Write `foreach x in ...`."
    assert e.Suggestion == "Add 'in' after 'x'"
}

test "016 stmt: a well-formed await foreach parses clean" {
    errors := RunPreamble("func f() {\n    await foreach x in items {\n        print x\n    }\n}\n")
    assert errors.Count == 0
}

// ---- C-style for ----

test "016 stmt: a C-style for missing its first ';' reports NL102 with the ';' hint" {
    errors := RunPreamble("func f() {\n    for (let i := 0 i < 10; i = i + 1) {\n        print i\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ';'. Expected ';', got 'i'"
    assert e.Line == 2
    assert e.Column == 21
    assert e.Length == 1
    assert e.SourceSnippet == "    for (let i := 0 i < 10; i = i + 1) {"
    assert e.HumanExplanation == "I was expecting ; here, but I found 'i' instead."
    assert e.ContextualHint == "Statements can end with a semicolon, though it's optional in N#."
}

test "016 stmt: a C-style for missing its closing ')' reports the NL107 via the closing-delimiter recovery" {
    errors := RunPreamble("func f() {\n    for (let i := 0; i < 10; i = i + 1 {\n        print i\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 2
    assert e.Column == 40
    assert e.Length == 1
    assert e.SourceSnippet == "    for (let i := 0; i < 10; i = i + 1 {"
    assert e.Suggestion == "Add ')' before '{'"
}

test "016 stmt: C-style for loops (parenthesized and bare) parse clean" {
    errors := RunPreamble("func f() {\n    for (let i := 0; i < 10; i = i + 1) {\n        print i\n    }\n}\n")
    assert errors.Count == 0
    errors2 := RunPreamble("func f() {\n    for let i := 0; i < 10; i = i + 1 {\n        print i\n    }\n}\n")
    assert errors2.Count == 0
}

// ---- tuple deconstruction ----

test "016 stmt: a paren tuple deconstruction missing ':=' reports NL102 at the offending token" {
    errors := RunPreamble("func f() {\n    let (a, b) 5\n    print a\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Tuple deconstruction requires ':=' or '='. Got '5'"
    assert e.Line == 2
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "    let (a, b) 5"
    assert e.HumanExplanation == "To unpack a tuple into multiple variables, you need to use ':=' or '=' after the variable list."
    assert e.ContextualHint == "Tuple deconstruction syntax: (x, y) := getTuple() or (x, y) = getTuple()"
    assert e.Suggestion == "Add ':=' for new variables: (x, y) := (1, 2)"
}

test "016 stmt: paren and no-paren tuple deconstructions parse clean" {
    errors := RunPreamble("func f() {\n    let (a, b) := getPair()\n    print a\n}\n")
    assert errors.Count == 0
    errors2 := RunPreamble("func f() {\n    a, b := getPair()\n    print a\n}\n")
    assert errors2.Count == 0
}

// ---- typed declaration ----

test "016 stmt: a typed declaration `name: T =` with no initializer reports NL102 anchored on the name" {
    errors := RunPreamble("func f() {\n    name: string =\n    print 1\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected an initializer expression after '='"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 4
    assert e.SourceSnippet == "    name: string ="
    assert e.HumanExplanation == "This typed variable declaration needs an initializer expression after '='."
    assert e.ContextualHint == "Finish the expression before starting the next statement."
    assert e.Suggestion == "Add an initializer expression after '='"
}

test "016 stmt: a well-formed typed declaration parses clean" {
    errors := RunPreamble("func f() {\n    name: string = \"x\"\n    print name\n}\n")
    assert errors.Count == 0
}

// ---- using ----

test "016 stmt: a using declaration missing ':=' reports NL102 with the 'colonassign' expected token" {
    errors := RunPreamble("func f() {\n    using r open() {\n        print 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':='. Expected 'colonassign', got 'open'"
    assert e.Line == 2
    assert e.Column == 13
    assert e.Length == 4
    assert e.SourceSnippet == "    using r open() {"
    assert e.HumanExplanation == "I was expecting colonassign here, but I found 'open' instead."
}

test "016 stmt: a using-let with tuple deconstruction reports the InvalidSyntax NL103 on the pattern span" {
    errors := RunPreamble("func f() {\n    using let (a, b) := open() {\n        print 1\n    }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Using statement requires a variable declaration, not tuple deconstruction"
    assert e.Line == 2
    assert e.Column == 15
    assert e.Length == 6
    assert e.SourceSnippet == "    using let (a, b) := open() {"
    assert e.HumanExplanation == "The 'using' statement can only work with single variable declarations, not tuple deconstruction."
    assert e.ContextualHint == "Use a single variable: using let resource := getResource() { ... }"
    assert e.Suggestion == "Change from tuple deconstruction to single variable"
}

test "016 stmt: using-let and using-ident resource declarations parse clean" {
    errors := RunPreamble("func f() {\n    using let r := open() {\n        print r\n    }\n}\n")
    assert errors.Count == 0
    errors2 := RunPreamble("func f() {\n    using r := open() {\n        print r\n    }\n}\n")
    assert errors2.Count == 0
}

// ---- off / on ----

test "016 stmt: an off unsubscription statement parses clean" {
    errors := RunPreamble("func f() {\n    off h\n}\n")
    assert errors.Count == 0
}

test "016 stmt: an on subscription whose handler is not a lambda reports the InvalidSyntax NL103 at the handler" {
    errors := RunPreamble("func f() {\n    on widget.Clicked foo\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected an event handler lambda after the event"
    assert e.Line == 2
    assert e.Column == 23
    assert e.Length == 1
    assert e.SourceSnippet == "    on widget.Clicked foo"
    assert e.HumanExplanation == "`on` subscribes a handler to a .NET event, so it needs a lambda to run when the event fires."
    assert e.ContextualHint == "Write the handler inline, e.g. `on widget.Clicked (sender, args) => { ... }`."
}

test "016 stmt: an on subscription whose event target ends with a bare dot reports the member-after-dot NL102, panic-suppressing the non-lambda report" {
    errors := RunPreamble("func f() {\n    on w. => 1\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected event or member name after '.'. Got '=>'"
    assert e.Line == 2
    assert e.Column == 11
    assert e.Length == 2
    assert e.SourceSnippet == "    on w. => 1"
    assert e.HumanExplanation == "I see a dot (.) operator but no member name after it. I found '=>' instead."
    assert e.ContextualHint == "After a dot, I need to see a property or method name."
    assert e.Suggestion == "Check if you forgot to finish this line"
}

test "016 stmt: on subscriptions with single-param and multi-param lambda handlers parse clean" {
    errors := RunPreamble("func f() {\n    on w.Clicked x => 1\n}\n")
    assert errors.Count == 0
    errors2 := RunPreamble("func f() {\n    on w.Clicked (s, a) => 1\n}\n")
    assert errors2.Count == 0
}

// ============================================================================
// Task-016 parser-front-end arc, Stage 14: parity contracts for the MEMBER grammars + the remaining
// type BODIES (residual map item [2]), carried through the SAME shared-panic model. Reached through the
// type-declaration vehicle `class C { <member> }` (and the record / interface / union / enum / soa
// declarations). Every golden below is the byte-exact output of the production Parser.cs path, captured
// out-of-band from the freshly built Release CLI (`nlc check --json`, filtered to the parser codes
// NL101-NL109 — excluding the SEMANTIC diagnostics [not-all-paths-return NL305, undefined-name, etc.]
// which are analyzer, not parser, diagnostics).
// ============================================================================

// ---- methods (missing return-type marker; reached as a MEMBER and as an INTERFACE member) ----

test "016 member: an interface method missing its ':' return-type marker reports NL102 anchored on the method name" {
    errors := RunPreamble("interface I {\n  func Foo() int\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' before return type. Got 'int'"
    assert e.Line == 2
    assert e.Column == 8
    assert e.Length == 3
    assert e.SourceSnippet == "  func Foo() int"
    assert e.HumanExplanation == "Function 'Foo' needs a ':' before its return type."
    assert e.ContextualHint == "Write the return type as `func name(...): Type { ... }`."
    assert e.Suggestion == "Add ':' before 'int'"
}

test "016 member: two class methods each missing the ':' marker each report at their own member boundary" {
    errors := RunPreamble("class C {\n  func A() int {\n  }\n  func B() int {\n  }\n}\n")
    assert errors.Count == 2
    a := errors[0]
    assert a.Code == ErrorCode.ExpectedToken
    assert a.Message == "Expected ':' before return type. Got 'int'"
    assert a.Line == 2
    assert a.Column == 8
    assert a.Length == 1
    assert a.HumanExplanation == "Function 'A' needs a ':' before its return type."
    b := errors[1]
    assert b.Code == ErrorCode.ExpectedToken
    assert b.Message == "Expected ':' before return type. Got 'int'"
    assert b.Line == 4
    assert b.Column == 8
    assert b.Length == 1
    assert b.HumanExplanation == "Function 'B' needs a ':' before its return type."
}

test "016 member: a body-less method missing its ':' marker panic-suppresses the type-body missing-'}' at EOF" {
    errors := RunPreamble("class C {\n  func A() int\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' before return type. Got 'int'"
    assert e.Line == 2
    assert e.Column == 8
    assert e.Length == 1
}

// ---- constructors ----

test "016 member: a constructor initializer target that is neither 'this' nor 'base' reports NL102 then cascades to the EOF missing-'}'" {
    errors := RunPreamble("class C {\n  constructor() : foo() {\n  }\n}\n")
    assert errors.Count == 2
    brace := errors[0]
    assert brace.Code == ErrorCode.MissingClosingBrace
    assert brace.Message == "Missing closing '}'"
    assert brace.Line == 1
    assert brace.Column == 7
    assert brace.Length == 1
    assert brace.HumanExplanation == "The type body that started on line 1 is missing its closing brace. I reached the end of the file without finding it."
    target := errors[1]
    assert target.Code == ErrorCode.ExpectedToken
    assert target.Message == "Expected 'this' or 'base' after ':'. Got 'foo'"
    assert target.Line == 2
    assert target.Column == 19
    assert target.Length == 3
    assert target.HumanExplanation == "In constructor initialization, the colon ':' must be followed by either 'this' (to call another constructor) or 'base' (to call parent constructor)."
    assert target.ContextualHint == "Constructor chaining syntax: 'constructor(params) : this(args) { }' or 'constructor(params) : base(args) { }'"
    assert target.Suggestion == "Use 'this' to call another constructor in the same class"
}

test "016 member: a constructor 'this' initializer missing its '(' reports the ConsumeToken NL102" {
    errors := RunPreamble("class C {\n  constructor() : this {\n  }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '(' after 'this'. Expected '(', got '{'"
    assert e.Line == 2
    assert e.Column == 24
    assert e.Length == 1
}

// ---- properties (get/set accessor block) ----

test "016 member: a non-identifier where a property accessor is required reports the 'Got' NL102 anchored on the offender" {
    errors := RunPreamble("class C {\n  X: int {\n    5\n  }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected 'get' or 'set' accessor. Got '5'"
    assert e.Line == 3
    assert e.Column == 5
    assert e.Length == 1
    assert e.SourceSnippet == "    5"
    assert e.HumanExplanation == "Inside property declaration braces, I need to see either 'get' or 'set' accessors."
    assert e.ContextualHint == "Properties define how to get and/or set their values using accessor blocks."
    assert e.Suggestion == "Add a 'get' accessor to make the property readable"
}

test "016 member: an invalid identifier accessor reports the ', got' NL102 (anchored on the token after the accessor) then the trailing '}' is unexpected" {
    errors := RunPreamble("class C {\n  X: int {\n    getter { }\n  }\n}\n")
    assert errors.Count == 2
    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected 'get' or 'set' accessor, got 'getter'"
    assert e0.Line == 3
    assert e0.Column == 12
    assert e0.Length == 6
    assert e0.HumanExplanation == "Property accessors must be either 'get' (for reading) or 'set' (for writing)."
    assert e0.ContextualHint == "Use 'get' to define how to retrieve the property value, or 'set' to define how to assign a new value."
    assert e0.Suggestion == "Example: get { return _value; }"
    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '}'"
    assert e1.Line == 5
    assert e1.Column == 1
    assert e1.Length == 1
}

test "016 member: two properties each with a bad accessor each report at their own member boundary" {
    errors := RunPreamble("class C {\n  X: int {\n    5\n  }\n  Y: int {\n    6\n  }\n}\n")
    assert errors.Count == 2
    assert errors[0].Message == "Expected 'get' or 'set' accessor. Got '5'"
    assert errors[0].Line == 3
    assert errors[0].Column == 5
    assert errors[1].Message == "Expected 'get' or 'set' accessor. Got '6'"
    assert errors[1].Line == 6
    assert errors[1].Column == 5
}

// ---- indexers ----

test "016 member: an invalid indexer accessor reports the ', got' NL102 then the trailing '}' is unexpected" {
    errors := RunPreamble("class C {\n  func this[i: int]: int {\n    xyz { }\n  }\n}\n")
    assert errors.Count == 2
    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected 'get' or 'set' accessor, got 'xyz'"
    assert e0.Line == 3
    assert e0.Column == 9
    assert e0.Length == 3
    assert e0.HumanExplanation == "Indexer accessors must be either 'get' (for reading) or 'set' (for writing)."
    assert e0.ContextualHint == "Use 'get' to define how to retrieve a value, or 'set' to define how to assign a value."
    assert e0.Suggestion == "Example: get { return items[i]; }"
    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '}'"
    assert e1.Line == 5
    assert e1.Column == 1
}

// ---- record / class positional (primary-ctor) parameter lists ----

test "016 member: a record positional parameter missing its ':' reports the shared parameter-colon NL102" {
    errors := RunPreamble("record R(x int) {\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' after parameter name. Got 'int'"
    assert e.Line == 1
    assert e.Column == 10
    assert e.Length == 1
    assert e.HumanExplanation == "Parameter 'x' needs a ':' before its type."
    assert e.ContextualHint == "Write this parameter as `x: Type`."
    assert e.Suggestion == "Add ':' after 'x'"
}

// ---- union type body ----

test "016 type-body: a non-identifier union case name reports the plain 'Expected union case name' NL102" {
    errors := RunPreamble("union U {\n  5\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected union case name. Got '5'"
    assert e.Line == 2
    assert e.Column == 3
    assert e.Length == 1
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
}

test "016 type-body: an unclosed union body reports the union-specific missing-'}' NL106 anchored on the union name" {
    errors := RunPreamble("union U {\n  A\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBrace
    assert e.Message == "Missing closing '}'"
    assert e.Line == 1
    assert e.Column == 7
    assert e.Length == 1
    assert e.HumanExplanation == "The union body that started on line 1 is missing its closing brace. I reached the end of the file without finding it."
    assert e.ContextualHint == "Add a '}' to close this union declaration."
}

test "016 type-body: a union-case payload property missing its ':' reports the ConsumeToken NL102" {
    errors := RunPreamble("union U {\n  A { x int }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':'. Expected ':', got 'int'"
    assert e.Line == 2
    assert e.Column == 9
    assert e.Length == 3
}

// ---- enum type body ----

test "016 type-body: a non-identifier enum member name reports NL102, then the break leaves the offender + '}' as unexpected top-level tokens" {
    errors := RunPreamble("enum E {\n  5\n}\n")
    assert errors.Count == 3
    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected enum member name. Got '5'"
    assert e0.Line == 2
    assert e0.Column == 3
    assert e0.Length == 1
    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 2
    assert e1.Column == 3
    e2 := errors[2]
    assert e2.Code == ErrorCode.UnexpectedToken
    assert e2.Message == "Unexpected token '}'"
    assert e2.Line == 3
    assert e2.Column == 1
}

test "016 type-body: an unsupported enum backing type reports the UnexpectedToken NL101 anchored on the type name" {
    errors := RunPreamble("enum E: float {\n  A\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedToken
    assert e.Message == "Unsupported enum backing type 'float'. Only 'int' and 'string' are supported."
    assert e.Line == 1
    assert e.Column == 9
    assert e.Length == 5
}

test "016 type-body: an unclosed enum body reports the enum-specific missing-'}' NL106 anchored on the enum name" {
    errors := RunPreamble("enum E {\n  A\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBrace
    assert e.Message == "Missing closing '}'"
    assert e.Line == 1
    assert e.Column == 6
    assert e.Length == 1
    assert e.HumanExplanation == "The enum body that started on line 1 is missing its closing brace. I reached the end of the file without finding it."
    assert e.ContextualHint == "Add a '}' to close this enum declaration."
}

// ---- soa record type body ----

test "016 type-body: a soa column missing its ':' reports the ConsumeToken NL102" {
    errors := RunPreamble("soa record S {\n  x int\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':'. Expected ':', got 'int'"
    assert e.Line == 2
    assert e.Column == 5
    assert e.Length == 3
}

test "016 type-body: a generic soa record reports the InvalidSyntax NL103 anchored on the '<'" {
    errors := RunPreamble("soa record S<T> {\n  x: int\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "soa record type parameters are not supported yet"
    assert e.Line == 1
    assert e.Column == 13
    assert e.Length == 1
    assert e.HumanExplanation == "This parser slice only accepts non-generic soa records. Generic soa tables need an explicit ABI design before they can be accepted."
    assert e.ContextualHint == "Remove the type parameter list for now."
}

test "016 type-body: an unclosed soa record body reports the soa-specific missing-'}' NL106 anchored on the soa name" {
    errors := RunPreamble("soa record S {\n  x: int\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBrace
    assert e.Message == "Missing closing '}'"
    assert e.Line == 1
    assert e.Column == 12
    assert e.Length == 1
    assert e.HumanExplanation == "The soa record body that started on line 1 is missing its closing brace. I reached the end of the file without finding it."
    assert e.ContextualHint == "Add a '}' to close this soa record declaration."
}

// ---- nested type bodies + cross-boundary panic ----

test "016 type-body: an unclosed nested enum reports its OWN missing-'}' and panic-suppresses the outer class body's" {
    errors := RunPreamble("class C {\n  enum E {\n    A\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBrace
    assert e.Message == "Missing closing '}'"
    assert e.Line == 2
    assert e.Column == 8
    assert e.Length == 1
    assert e.HumanExplanation == "The enum body that started on line 2 is missing its closing brace. I reached the end of the file without finding it."
    assert e.ContextualHint == "Add a '}' to close this enum declaration."
}

// ---- negatives: well-formed member / body shapes report NO parser diagnostic ----

test "016 member: a well-formed block-bodied method reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  func Foo(): int {\n    return 1\n  }\n}\n")
    assert errors.Count == 0
}

test "016 member: a generator func* method reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  func* Gen(): int {\n    yield 1\n  }\n}\n")
    assert errors.Count == 0
}

test "016 member: an async method reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  async func Go(): int {\n    return 1\n  }\n}\n")
    assert errors.Count == 0
}

test "016 member: an expression-bodied method reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  func Add(a: int, b: int): int => a + b\n}\n")
    assert errors.Count == 0
}

test "016 member: a func operator overload reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  func operator +(a: C, b: C): C => a\n}\n")
    assert errors.Count == 0
}

test "016 member: an implicit conversion operator (return type before params) reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  implicit operator int(c: C) => 0\n}\n")
    assert errors.Count == 0
}

test "016 member: a constructor chaining to this() reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  constructor() {\n  }\n  constructor(x: int) : this() {\n  }\n}\n")
    assert errors.Count == 0
}

test "016 member: a property with get/set accessor blocks reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  Name: string {\n    get { return _n }\n    set { _n = value }\n  }\n}\n")
    assert errors.Count == 0
}

test "016 member: an expression-bodied property reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  Total: int => 42\n}\n")
    assert errors.Count == 0
}

test "016 type-body: a nested enum with members reports no parser diagnostic" {
    errors := RunPreamble("class C {\n  enum Color {\n    Red,\n    Blue\n  }\n}\n")
    assert errors.Count == 0
}

test "016 type-body: a union with a payload case and a bare case reports no parser diagnostic" {
    errors := RunPreamble("union Shape {\n  Circle { radius: int }\n  Square\n}\n")
    assert errors.Count == 0
}

test "016 type-body: an interface with a method and a property member reports no parser diagnostic" {
    errors := RunPreamble("interface I {\n  func Foo(): int\n  Name: string\n}\n")
    assert errors.Count == 0
}

test "016 type-body: a record with positional parameters reports no parser diagnostic" {
    errors := RunPreamble("record Point(x: int, y: int) {\n}\n")
    assert errors.Count == 0
}

// ---- retirement of the stage-2 deferred non-'{' braced found-other cases for record / union / enum ----
// A '{' where the type name is required now reports the keyword-anchored found-other name NL102 (Stage 2)
// AND flows into the body parse (Stage 14), exactly like class/struct since Stage 4 — proven byte-exact
// against the oracle with the Stage-12 position-sort in place.

test "016 type-body: a record whose name is a '{' reports the found-other name NL102 then parses the body (a field colon error)" {
    errors := RunPreamble("record {\n  A\n}\n")
    assert errors.Count == 2
    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected record name. Got '{'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 6
    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected ':' or ':=' after field name. Got '}'"
    assert e1.Line == 2
    assert e1.Column == 3
    assert e1.Length == 1
    assert e1.Suggestion == "Add ':' after 'A'"
}

test "016 type-body: a union whose name is a '{' reports the found-other name NL102 then parses the (clean) body" {
    errors := RunPreamble("union {\n  A\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected union name. Got '{'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 5
}

test "016 type-body: an enum whose name is a '{' reports the found-other name NL102 then parses the (clean) body" {
    errors := RunPreamble("enum {\n  A\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected enum name. Got '{'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 4
}

// ============================================================================
// Stage 15: the richer TYPE-REFERENCE forms (residual map item [3]) — the UNION / POSTFIX
// (array / nullable) / byref / tuple / Func<> layers of the full Parser.cs type grammar
// (ParseTypeReference :1774 → ParseUnionTypeReference / ParsePostfixTypeReference /
// ParseBaseTypeReference / ParseParenthesizedOrTupleTypeReference / ParseFunctionTypeReference),
// carried through the SAME shared owner. Because the whole grammar is the SHARED
// ParseTypeReferenceRecovery entry, these contracts prove the forms fire identically at every
// consumption site (return type / field / type-alias / catch / is-expr / generic-arg /
// tuple-element / Func-param / base-list). Golden values captured from the freshly built Release
// CLI oracle (`nlc check --json`, filtered to parser codes NL101-NL109).
// ============================================================================

// ---- UNION missing-arm (NL103) across representative shared consumers ----

test "016 type-ref union: a trailing '|' in a return type reports the anonymous-union NL103 at the terminator" {
    errors := RunPreamble("func f(): A |")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 1
    assert e.Column == 14
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): A |"
    assert e.HumanExplanation == "Anonymous union types use the form `A | B`, so every `|` must be followed by another type."
    assert e.ContextualHint == "Add the missing type arm, or remove the trailing `|`."
    assert e.Suggestion == null
}

test "016 type-ref union: a trailing '|' in a field type reports the NL103 at the closing-brace terminator" {
    errors := RunPreamble("struct S {\n  x: A |\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 3
    assert e.Column == 1
    assert e.Length == 1
    assert e.SourceSnippet == "}"
    assert e.HumanExplanation == "Anonymous union types use the form `A | B`, so every `|` must be followed by another type."
    assert e.ContextualHint == "Add the missing type arm, or remove the trailing `|`."
}

test "016 type-ref union: a trailing '|' in a typed declaration reports the NL103 at the '=' terminator" {
    // The `name: T = value` typed declaration (no `let`) routes its type through the shared grammar too.
    errors := RunPreamble("func f() {\n  x: A | = y\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 2
    assert e.Column == 10
    assert e.Length == 1
    assert e.SourceSnippet == "  x: A | = y"
}

test "016 type-ref union: a trailing '|' in a catch type reports the NL103 at the ')' terminator" {
    errors := RunPreamble("func f() {\n  try {\n  } catch (e: A |) {\n  }\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 3
    assert e.Column == 18
    assert e.Length == 1
    assert e.SourceSnippet == "  } catch (e: A |) {"
}

test "016 type-ref union: a trailing '|' in an is-expression type reports the NL103 (is/as share the grammar)" {
    errors := RunPreamble("func f(x: object) {\n  y := x is A |\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 3
    assert e.Column == 1
    assert e.Length == 1
    assert e.SourceSnippet == "}"
}

// ---- POSTFIX / byref forms are CONSUMED, so a following union '|' anchors past them ----

test "016 type-ref postfix: an array type A[] is consumed, so a trailing '|' reports the union NL103 after it" {
    errors := RunPreamble("func f(): A[] |")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 1
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): A[] |"
}

test "016 type-ref postfix: a nullable type A? is consumed, so a trailing '|' reports the union NL103 after it" {
    errors := RunPreamble("func f(): A? |")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 1
    assert e.Column == 15
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): A? |"
}

test "016 type-ref byref: a byref type &A is consumed, so a trailing '|' reports the union NL103 after it" {
    errors := RunPreamble("func f(): &A |")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 1
    assert e.Column == 15
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): &A |"
}

test "016 type-ref byref: a byref '&' with no inner type at end of file reports the ConsumeIdentifier NL104" {
    errors := RunPreamble("func f(): &")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected type name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): &"
    assert e.HumanExplanation == "I was expecting an identifier here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 type-ref byref: a parameter type '&' with no inner type reaches the ConsumeIdentifier NL102 on the ')'" {
    // Proves the PARAMETER-type consumer now routes through the full grammar (Parser.cs threads params
    // through ParseTypeReference): the byref inner type reports on the ')' that follows the '&'.
    errors := RunPreamble("func f(x: &)")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got ')'"
    assert e.Line == 1
    assert e.Column == 12
    assert e.Length == 1
    assert e.SourceSnippet == "func f(x: &)"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found ')' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
}

// ---- TUPLE forms ----

test "016 type-ref tuple: an unclosed tuple type crossing onto the next line reports the NL107 on the '('" {
    errors := RunPreamble("func f(): (int, string")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): (int, string"
    assert e.HumanExplanation == "I reached the next line while looking for the closing ')' that matches an earlier '('."
    assert e.ContextualHint == "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
    assert e.Suggestion == "Add ')' before starting the next line"
}

test "016 type-ref tuple: an empty tuple type () reports the ConsumeIdentifier NL102 on the ')'" {
    errors := RunPreamble("func f(): ()")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got ')'"
    assert e.Line == 1
    assert e.Column == 12
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): ()"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found ')' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e.Suggestion == null
}

test "016 type-ref tuple: a named element with a missing type reaches the ConsumeIdentifier NL102 on the ')'" {
    errors := RunPreamble("func f(): (a: int, b: )")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got ')'"
    assert e.Line == 1
    assert e.Column == 23
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): (a: int, b: )"
}

test "016 type-ref tuple: a tuple type is consumed, so a trailing '|' reports the union NL103 after it" {
    errors := RunPreamble("func f(): (int, string) |")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 1
    assert e.Column == 26
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): (int, string) |"
}

// ---- Func<> forms (the Func dispatch does NOT report ReportMissingGenericTypeArgument) ----

test "016 type-ref Func: a bare 'Func' with no '<' at end of file reports the Consume(Less) NL104" {
    errors := RunPreamble("func f(): Func")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected 'less' but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 11
    assert e.Length == 4
    assert e.SourceSnippet == "func f(): Func"
    assert e.HumanExplanation == "I was expecting 'less' here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 type-ref Func: an unclosed Func<int reports the ConsumeGreater NL102 at the offender" {
    errors := RunPreamble("func f(): Func<int {\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '>'. Got '{'"
    assert e.Line == 1
    assert e.Column == 20
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): Func<int {"
    assert e.HumanExplanation == "I was parsing generic type parameters and expected to see a closing '>' here."
    assert e.ContextualHint == null
    assert e.Suggestion == "Check if you have matching '<' and '>' in your generic type declaration"
}

test "016 type-ref Func: an empty Func<> reaches the ConsumeIdentifier NL102 on the '>' (not the generic-arg report)" {
    errors := RunPreamble("func f(): Func<>")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '>'"
    assert e.Line == 1
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): Func<>"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '>' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e.Suggestion == null
}

test "016 type-ref Func: a trailing comma Func<int,> reaches the ConsumeIdentifier NL102 on the '>'" {
    errors := RunPreamble("func f(): Func<int,>")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '>'"
    assert e.Line == 1
    assert e.Column == 20
    assert e.Length == 1
    assert e.SourceSnippet == "func f(): Func<int,>"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '>' instead."
}

// ---- consumption parity: the union arm greedily consumes across the '|'-suppressed newline ----

test "016 type-ref union: the arm after '|' greedily consumes the next line's field name, so its ':' reports one NL102" {
    // `x: A |` <newline-suppressed-after-'|'> `y` — the union arm consumes `y` as the second type name,
    // then the field member sees the following ':' with no name (byte-exact with Parser.cs's greedy
    // ParsePostfixTypeReference across the suppressed newline). A single diagnostic, not two.
    errors := RunPreamble("struct S {\n  x: A |\n  y: B |\n}")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected field name. Got ':'"
    assert e.Line == 3
    assert e.Column == 4
    assert e.Length == 1
    assert e.SourceSnippet == "  y: B |"
}

// ---- NEGATIVES: every valid richer form parses clean (zero parser diagnostics) ----

test "016 type-ref negative: a valid union return type A | B reports nothing" {
    assert RunPreamble("func f(): A | B").Count == 0
}

test "016 type-ref negative: a valid array return type A[] reports nothing" {
    assert RunPreamble("func f(): A[]").Count == 0
}

test "016 type-ref negative: a valid nullable return type A? reports nothing" {
    assert RunPreamble("func f(): A?").Count == 0
}

test "016 type-ref negative: a valid nullable-array return type A?[] reports nothing" {
    assert RunPreamble("func f(): A?[]").Count == 0
}

test "016 type-ref negative: a valid byref parameter type &int reports nothing" {
    assert RunPreamble("func f(x: &int)").Count == 0
}

test "016 type-ref negative: a valid tuple return type (int, string) reports nothing" {
    assert RunPreamble("func f(): (int, string)").Count == 0
}

test "016 type-ref negative: a valid named tuple type (a: int, b: string) reports nothing" {
    assert RunPreamble("func f(): (a: int, b: string)").Count == 0
}

test "016 type-ref negative: a valid single-element parenthesized type (int) reports nothing" {
    assert RunPreamble("func f(): (int)").Count == 0
}

test "016 type-ref negative: a valid Func<int, string> return type reports nothing" {
    assert RunPreamble("func f(): Func<int, string>").Count == 0
}

test "016 type-ref negative: a valid multi-parameter Func<int, string, bool> reports nothing" {
    assert RunPreamble("func f(): Func<int, string, bool>").Count == 0
}

test "016 type-ref negative: a union nested inside a generic argument List<A | B> reports nothing" {
    assert RunPreamble("func f(): List<A | B>").Count == 0
}

test "016 type-ref negative: a nested Func<Func<int, string>, bool> closes both angles via the >> split" {
    assert RunPreamble("func f(): Func<Func<int, string>, bool>").Count == 0
}

test "016 type-ref negative: a valid is-expression union type A | B is consumed with no diagnostic" {
    assert RunPreamble("func f(x: object) {\n  y := x is A | B\n}").Count == 0
}

test "016 type-ref negative: a valid base-list union A | B routes through the full grammar with no diagnostic" {
    assert RunPreamble("class C : A | B {\n}").Count == 0
}

// ---------------------------------------------------------------------------
// Task-016 parser-front-end arc, Stage 16: the TEST DSL + ATTRIBUTES family.
// Every golden below is the byte-exact output of the freshly built Release CLI oracle
// (`nlc check --json`, parser codes NL101-NL109, excluding the columnar-backend emit-decline
// NL103 — for the test-DSL declarations the oracle also emits a line-0/1 emit decline that is a
// backend diagnostic, not a parser one). The test-DSL declarations (`test`/`setup`/`teardown`)
// are dispatched from ParseTopLevelDeclaration BEFORE attributes/modifiers, so each is its own
// declaration and resets panic at the Run() declaration boundary; attributes (`[Name(args)]`)
// precede modifiers on top-level declarations, members, and parameters.
//
// NOT corpus-pinnable (recorded, with reason): the malformed table-driven ROW shapes reached
// via a following `{ }` body (`test "d" with (a) 9 { }`, `test "d" with (a) [ 9 ] { }`) HANG the
// production parser — the row loop `while (!Check(RightParen) && !IsAtEnd()) ParseExpression()`
// does NOT force-advance, and ParseExpression neither consumes nor skips a `}` / `]` in the
// row-expression position (ShouldSkipUnexpectedExpressionToken returns false for an expression
// terminator), so it spins. The model reproduces this loop faithfully, so pinning such a shape
// would hang the suite. The malformed table sites are instead pinned at EOF (below), where the
// loop terminates and the leading Consume error is the single unsuppressed diagnostic.

test "016 test-dsl: a non-string test description reports the ExpectedToken direct diagnostic and skips the offender" {
    errors := RunPreamble("test 5 {\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected string literal for test description. Got '5'"
    assert e.Line == 1
    assert e.Column == 6
    assert e.Length == 1
    assert e.SourceSnippet == "test 5 {"
    assert e.HumanExplanation == "Test declarations require a string literal describing what the test does."
    assert e.ContextualHint == "A test should start with the 'test' keyword followed by a string in quotes."
    assert e.Suggestion == "Example: test \"should calculate sum correctly\" { ... }"
    assert e.Suggestions.Count == 2
    assert e.Suggestions[1] == "Example: test \"validates user input\" { ... }"
}

test "016 test-dsl: two malformed test declarations BOTH report — the declaration-boundary panic reset" {
    errors := RunPreamble("test 5 {\n}\ntest 6 {\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected string literal for test description. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 6

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected string literal for test description. Got '6'"
    assert e1.Line == 3
    assert e1.Column == 6
}

test "016 test-dsl: a malformed test followed by a valid declaration reports only the test error" {
    errors := RunPreamble("test 5 {\n}\nfunc f() {\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected string literal for test description. Got '5'"
    assert e.Line == 1
    assert e.Column == 6
}

test "016 test-dsl: a non-string skip reason reports the skip ExpectedToken diagnostic" {
    errors := RunPreamble("test \"adds\" skip {\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected string literal for skip reason. Got '{'"
    assert e.Line == 1
    assert e.Column == 18
    assert e.Length == 1
    assert e.SourceSnippet == "test \"adds\" skip {"
    assert e.HumanExplanation == "The 'skip' modifier requires a string explaining why the test is skipped."
    assert e.ContextualHint == "Add a reason string after 'skip'."
    assert e.Suggestion == "Example: test \"my test\" skip \"needs network\" { ... }"
}

test "016 test-dsl: a non-string skip reason before a body cascades the skip error and the block missing-'}' (position-sorted)" {
    errors := RunPreamble("test \"adds\" skip 9 {\n}\n")
    assert errors.Count == 2

    // The block resets panic per statement, so the missing-'}' NL106 (anchored on the 'test'
    // keyword at col 1) is recorded after the skip error but position-sorts before it.
    e0 := errors[0]
    assert e0.Code == ErrorCode.MissingClosingBrace
    assert e0.Message == "Missing closing '}'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 4
    assert e0.SourceSnippet == "test \"adds\" skip 9 {"
    assert e0.HumanExplanation == "The block that started on line 1 is missing its closing brace. I reached the end of the file without finding it."

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected string literal for skip reason. Got '9'"
    assert e1.Line == 1
    assert e1.Column == 18
}

test "016 test-dsl: a missing '[' before the test cases reports the table ExpectedToken diagnostic" {
    errors := RunPreamble("test \"adds\" with (a: int) 9")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '[' to start test cases. Expected '[', got '9'"
    assert e.Line == 1
    assert e.Column == 27
    assert e.Length == 1
    assert e.SourceSnippet == "test \"adds\" with (a: int) 9"
    assert e.HumanExplanation == "I was expecting [ here, but I found '9' instead."
    assert e.ContextualHint == null
}

test "016 test-dsl: a non-'(' where a test case row starts reports the row ExpectedToken diagnostic" {
    errors := RunPreamble("test \"adds\" with (a: int) [ 9")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '(' to start test case row. Expected '(', got '9'"
    assert e.Line == 1
    assert e.Column == 29
    assert e.Length == 1
    assert e.HumanExplanation == "I was expecting ( here, but I found '9' instead."
}

test "016 test-dsl: an unclosed test-cases ']' routes through the Stage-9 closing-delimiter recovery (NL108)" {
    errors := RunPreamble("test \"adds\" with (a: int) [ (1)")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBracket
    assert e.Message == "Missing closing ']'"
    assert e.Line == 1
    assert e.Column == 27
    assert e.Length == 1
    assert e.HumanExplanation == "I reached the next line while looking for the closing ']' that matches an earlier '['."
    assert e.ContextualHint == "Every opening bracket '[' needs a matching closing bracket ']'."
    assert e.Suggestion == "Add ']' before starting the next line"
}

// Parity for the table-case no-progress guard (Parser.cs 170244a5f). Before the guard, a token that cannot start
// an expression sitting in row position (the body '{', or the ']' that closes an unparenthesised row) spun the
// row-item loop forever — ParseExpression returns without advancing and Match(Comma)/ConsumeToken do not advance
// on mismatch either — and the outer row loop spun for the same reason once the item loop consumed nothing. All
// four shapes below HUNG; they now terminate with exactly the diagnostics the live Parser.cs reports (golden
// values from the freshly built Release CLI `nlc check --json`, filtered to the parser codes NL101-NL109).
// The earlier EOF-pinned row contracts above are unaffected — the loops there end on IsAtEnd(), not the guard.

test "016 test-dsl: an untyped table header before a bare row value terminates on the parameter-':' NL102" {
    errors := RunPreamble("test \"d\" with (a) 9 { }")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' after parameter name. Got ')'"
    assert e.Line == 1
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "test \"d\" with (a) 9 { }"
    assert e.HumanExplanation == "Parameter 'a' needs a ':' before its type."
    assert e.ContextualHint == "Write this parameter as `a: Type`."
    assert e.Suggestion == "Add ':' after 'a'"
}

test "016 test-dsl: an untyped table header before a bracketed row value terminates on the parameter-':' NL102" {
    errors := RunPreamble("test \"d\" with (a) [ 9 ] { }")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected ':' after parameter name. Got ')'"
    assert e.Line == 1
    assert e.Column == 16
    assert e.Length == 1
    assert e.SourceSnippet == "test \"d\" with (a) [ 9 ] { }"
    assert e.HumanExplanation == "Parameter 'a' needs a ':' before its type."
    assert e.ContextualHint == "Write this parameter as `a: Type`."
    assert e.Suggestion == "Add ':' after 'a'"
}

test "016 test-dsl: a bare row value after a typed table header terminates on the table '[' NL102" {
    errors := RunPreamble("test \"d\" with (a: int) 9 { }")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '[' to start test cases. Expected '[', got '9'"
    assert e.Line == 1
    assert e.Column == 24
    assert e.Length == 1
    assert e.SourceSnippet == "test \"d\" with (a: int) 9 { }"
    assert e.HumanExplanation == "I was expecting [ here, but I found '9' instead."
    assert e.ContextualHint == null
}

test "016 test-dsl: a non-'(' row between the brackets terminates on the row '(' NL102" {
    errors := RunPreamble("test \"d\" with (a: int) [ 9 ] { }")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '(' to start test case row. Expected '(', got '9'"
    assert e.Line == 1
    assert e.Column == 26
    assert e.Length == 1
    assert e.SourceSnippet == "test \"d\" with (a: int) [ 9 ] { }"
    assert e.HumanExplanation == "I was expecting ( here, but I found '9' instead."
    assert e.ContextualHint == null
}

test "016 test-dsl negative: a valid empty test reports nothing" {
    assert RunPreamble("test \"adds\" {\n}\n").Count == 0
}

test "016 test-dsl negative: a valid test with an assert body reports nothing" {
    assert RunPreamble("test \"adds\" {\n  assert 1 == 1\n}\n").Count == 0
}

test "016 test-dsl negative: a valid skip reason reports nothing" {
    assert RunPreamble("test \"adds\" skip \"flaky\" {\n}\n").Count == 0
}

test "016 test-dsl negative: a valid table-driven test with rows reports nothing" {
    assert RunPreamble("test \"adds\" with (a: int, b: int) [\n  (1, 2),\n  (3, 4)\n] {\n}\n").Count == 0
}

test "016 test-dsl negative: a valid setup block reports nothing" {
    assert RunPreamble("setup {\n  x := 1\n}\n").Count == 0
}

test "016 test-dsl negative: a valid teardown block reports nothing" {
    assert RunPreamble("teardown {\n  y := 2\n}\n").Count == 0
}

test "016 attributes: a non-identifier attribute name reports the ConsumeIdentifier NL102 then the ']' unexpected-token at the boundary" {
    errors := RunPreamble("[123]\nfunc g() {\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected attribute name. Got '123'"
    assert e0.Line == 1
    assert e0.Column == 2
    assert e0.Length == 3
    assert e0.SourceSnippet == "[123]"
    assert e0.HumanExplanation == "I was expecting an identifier here, but I found '123' instead."
    assert e0.ContextualHint == "An identifier is a name for a variable, function, or type."
    assert e0.Suggestion == null

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token ']'"
    assert e1.Line == 1
    assert e1.Column == 5
    assert e1.Length == 1
    assert e1.HumanExplanation == "I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found ']' instead."
    assert e1.ContextualHint == "Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases."
}

test "016 attributes: a missing identifier after '.' in a qualified attribute name uses the dot-access ConsumeIdentifier variant" {
    errors := RunPreamble("[System.]\nfunc g() {\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected identifier after '.'. Got ']'"
    assert e.Line == 1
    assert e.Column == 9
    assert e.Length == 1
    assert e.SourceSnippet == "[System.]"
    assert e.HumanExplanation == "I see a dot (.) operator but no member name after it. I found ']' instead."
    assert e.ContextualHint == "After a dot, I need to see a property or method name."
    assert e.Suggestion == "Check if you forgot to finish this line"
}

test "016 attributes: an unclosed attribute ']' routes through the Stage-9 closing-delimiter recovery (NL108)" {
    errors := RunPreamble("[Foo\nfunc g() {\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingBracket
    assert e.Message == "Missing closing ']'"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 1
    assert e.SourceSnippet == "[Foo"
    assert e.HumanExplanation == "I reached the next line while looking for the closing ']' that matches an earlier '['."
    assert e.ContextualHint == "Every opening bracket '[' needs a matching closing bracket ']'."
    assert e.Suggestion == "Add ']' before starting the next line"
}

test "016 attributes: an unclosed attribute argument ')' routes through the Stage-9/Stage-10 argument grammar (NL107)" {
    errors := RunPreamble("[Foo(1\nfunc g() {\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.MissingClosingParen
    assert e.Message == "Missing closing ')'"
    assert e.Line == 1
    assert e.Column == 2
    assert e.Length == 3
    assert e.SourceSnippet == "[Foo(1"
    assert e.HumanExplanation == "I reached the next line while looking for the closing ')' that matches an earlier '('."
    assert e.ContextualHint == "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
    assert e.Suggestion == "Add ')' before starting the next line"
}

test "016 attributes: a non-identifier member attribute name cascades the attr-name and the field-name NL102 across the member-boundary reset" {
    errors := RunPreamble("class C {\n  [123]\n  func m() {\n  }\n}\n")
    assert errors.Count == 2

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected attribute name. Got '123'"
    assert e0.Line == 2
    assert e0.Column == 4
    assert e0.Length == 3
    assert e0.SourceSnippet == "  [123]"

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected field name. Got '123'"
    assert e1.Line == 2
    assert e1.Column == 4
    assert e1.Length == 3
}

test "016 attributes negative: a valid attribute on a top-level function reports nothing" {
    assert RunPreamble("[Foo]\nfunc g() {\n}\n").Count == 0
}

test "016 attributes negative: a valid attribute with arguments reports nothing" {
    assert RunPreamble("[Foo(1, 2)]\nfunc g() {\n}\n").Count == 0
}

test "016 attributes negative: a valid qualified attribute name reports nothing" {
    assert RunPreamble("[System.Foo]\nfunc g() {\n}\n").Count == 0
}

test "016 attributes negative: two stacked attributes on one declaration report nothing" {
    assert RunPreamble("[Foo]\n[Bar]\nfunc g() {\n}\n").Count == 0
}

test "016 attributes negative: a valid attribute on a class member reports nothing" {
    assert RunPreamble("class C {\n  [Foo]\n  func m() {\n  }\n}\n").Count == 0
}

test "016 attributes negative: a valid attribute on a parameter reports nothing" {
    assert RunPreamble("func f([Foo] x: int) {\n}\n").Count == 0
}

// ============================================================================
// Task-016 parser-front-end arc, Stage 17: residual map item [5] — the LAST capability family.
// (a) the GARBAGE-TYPE cascade shapes deferred since stages 4/9 — the non-'{' braced found-other
//     for class/struct (`class 5` / `struct 5`), the non-identifier parameter name (`func f(5)`),
//     and the named-tuple bad-name (`(x: 1, 5: 2)`); the Stage-12 position-sort orders their
//     emitted diagnostics to the CLI's display order. (b) the TYPE-ALIAS underlying-type consumer
//     (`type T = A | B` — the `= <type>` body via the Stage-15 full type grammar) + its error shapes.
// Every expected value is GOLDEN Parser.cs output captured from the freshly built Release CLI
// (`nlc check --json`, parser codes NL101-NL109, excluding the line-0 columnar-backend emit-decline).
// ============================================================================

// ---- garbage-type cascade: the non-'{' braced found-other for class / struct (stage-2 probe shape) ----

test "016 garbage: a non-'{' class name (`class 5`) cascades the name error, the type-body missing-'}', and the in-body field-name error" {
    // Parser.cs ALWAYS parses the class body (Consume '{' + ParseMemberList, :970). A '<error>'-named
    // class whose offender is a non-'{' token leaves the offender for ParseMemberList: the class-name
    // NL102 and the type-body missing-'}' NL106 both anchor at the class keyword (col 1), and the
    // in-body field-name NL102 anchors at the offender (col 7). The position-sort orders them
    // (class NL102, then NL106 at the same column by emission order, then the field NL102).
    errors := RunPreamble("class 5\n")
    assert errors.Count == 3

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected class name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 5
    assert e0.SourceSnippet == "class 5"
    assert e0.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e0.ContextualHint == "An identifier is a name for a variable, function, or type."

    e1 := errors[1]
    assert e1.Code == ErrorCode.MissingClosingBrace
    assert e1.Message == "Missing closing '}'"
    assert e1.Line == 1
    assert e1.Column == 1
    assert e1.Length == 5
    assert e1.SourceSnippet == "class 5"
    assert e1.HumanExplanation == "The type body that started on line 1 is missing its closing brace. I reached the end of the file without finding it."
    assert e1.ContextualHint == "Add a '}' to close this type declaration."

    e2 := errors[2]
    assert e2.Code == ErrorCode.ExpectedToken
    assert e2.Message == "Expected field name. Got '5'"
    assert e2.Line == 1
    assert e2.Column == 7
    assert e2.Length == 1
    assert e2.SourceSnippet == "class 5"
    assert e2.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e2.ContextualHint == "An identifier is a name for a variable, function, or type."
}

test "016 garbage: a non-'{' struct name (`struct 5`) cascades identically with the struct-keyword anchor" {
    errors := RunPreamble("struct 5\n")
    assert errors.Count == 3

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected struct name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 6
    assert e0.SourceSnippet == "struct 5"

    e1 := errors[1]
    assert e1.Code == ErrorCode.MissingClosingBrace
    assert e1.Message == "Missing closing '}'"
    assert e1.Line == 1
    assert e1.Column == 1
    assert e1.Length == 6
    assert e1.SourceSnippet == "struct 5"

    e2 := errors[2]
    assert e2.Code == ErrorCode.ExpectedToken
    assert e2.Message == "Expected field name. Got '5'"
    assert e2.Line == 1
    assert e2.Column == 8
    assert e2.Length == 1
    assert e2.SourceSnippet == "struct 5"
}

test "016 garbage: a non-'{' class name WITH a braced body (`class 5 { }`) closes the body so the field-name errors report but no missing-'}' fires" {
    // With an explicit `{ }`, ParseMemberList consumes past the offending `5` (field-name NL102 @ 7),
    // then reaches `{` inside the body (field-name NL102 @ 9), then the `}` closes the body — no NL106.
    errors := RunPreamble("class 5 { }\n")
    assert errors.Count == 3

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected class name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 1
    assert e0.Length == 5

    e1 := errors[1]
    assert e1.Code == ErrorCode.ExpectedToken
    assert e1.Message == "Expected field name. Got '5'"
    assert e1.Line == 1
    assert e1.Column == 7
    assert e1.Length == 1

    e2 := errors[2]
    assert e2.Code == ErrorCode.ExpectedToken
    assert e2.Message == "Expected field name. Got '{'"
    assert e2.Line == 1
    assert e2.Column == 9
    assert e2.Length == 1
    assert e2.SourceSnippet == "class 5 { }"
}

// ---- garbage-type cascade: the non-identifier parameter name (`func f(5)`) ----

test "016 garbage: a non-identifier parameter name (`func f(5)`) reports the param-name error then the leftover tokens cascade through the top-level unexpected-token arm" {
    // The parameter-name ConsumeIdentifier reports NL102 @ the offender; ParseParameterTypeReference
    // routes the garbage through ParseTypeReference (which does not consume it), the ')' Consume is
    // suppressed under panic, and the function returns without a body — so `5 ) { }` each surface as
    // a top-level "Unexpected token" NL101 after the per-declaration panic reset.
    errors := RunPreamble("func f(5) { }\n")
    assert errors.Count == 5

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected parameter name. Got '5'"
    assert e0.Line == 1
    assert e0.Column == 8
    assert e0.Length == 1
    assert e0.SourceSnippet == "func f(5) { }"
    assert e0.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e0.ContextualHint == "An identifier is a name for a variable, function, or type."

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token '5'"
    assert e1.Line == 1
    assert e1.Column == 8
    assert e1.Length == 1
    assert e1.HumanExplanation == "I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '5' instead."

    e2 := errors[2]
    assert e2.Code == ErrorCode.UnexpectedToken
    assert e2.Message == "Unexpected token ')'"
    assert e2.Line == 1
    assert e2.Column == 9
    assert e2.Length == 1

    e3 := errors[3]
    assert e3.Code == ErrorCode.UnexpectedToken
    assert e3.Message == "Unexpected token '{'"
    assert e3.Line == 1
    assert e3.Column == 11
    assert e3.Length == 1

    e4 := errors[4]
    assert e4.Code == ErrorCode.UnexpectedToken
    assert e4.Message == "Unexpected token '}'"
    assert e4.Line == 1
    assert e4.Column == 13
    assert e4.Length == 1
}

// ---- garbage-type cascade: the named-tuple bad-name (`(x: 1, 5: 2)`) ----

test "016 garbage: a named-tuple bad-name (`(x: 1, 5: 2)`) reports the element-name error then the leftover ':' and ')' cascade through the expression-terminal arm" {
    // The named-element loop's ConsumeIdentifier reports NL102 @ the offender; the value ParseExpression
    // consumes the offending `5`, the ')' Consume is suppressed under panic, and the leftover `:` and `)`
    // surface as "Unexpected token '…' in expression" NL101 through the per-statement panic reset.
    errors := RunPreamble("func f() {\n    y := (x: 1, 5: 2)\n}\n")
    assert errors.Count == 3

    e0 := errors[0]
    assert e0.Code == ErrorCode.ExpectedToken
    assert e0.Message == "Expected identifier. Got '5'"
    assert e0.Line == 2
    assert e0.Column == 17
    assert e0.Length == 1
    assert e0.SourceSnippet == "    y := (x: 1, 5: 2)"
    assert e0.HumanExplanation == "I was expecting an identifier here, but I found '5' instead."
    assert e0.ContextualHint == "An identifier is a name for a variable, function, or type."

    e1 := errors[1]
    assert e1.Code == ErrorCode.UnexpectedToken
    assert e1.Message == "Unexpected token ':' in expression"
    assert e1.Line == 2
    assert e1.Column == 18
    assert e1.Length == 1
    assert e1.HumanExplanation == "I was parsing an expression and found ':', which I don't know how to handle here."
    assert e1.ContextualHint == "Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax."

    e2 := errors[2]
    assert e2.Code == ErrorCode.UnexpectedToken
    assert e2.Message == "Unexpected token ')' in expression"
    assert e2.Line == 2
    assert e2.Column == 21
    assert e2.Length == 1
}

// ---- the type-alias underlying-type consumer (`type T = <type>`, Parser.cs :1338-1350) ----

test "016 type-alias: a missing '=' after the alias name at end of file reports the ExpectedEndOfFile NL104" {
    errors := RunPreamble("type T")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected 'assign' but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 6
    assert e.Length == 1
    assert e.SourceSnippet == "type T"
    assert e.HumanExplanation == "I was expecting 'assign' here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 type-alias: a missing underlying type after '=' at end of file reports the ExpectedEndOfFile NL104" {
    errors := RunPreamble("type T =")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected type name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 1
    assert e.SourceSnippet == "type T ="
    assert e.HumanExplanation == "I was expecting an identifier here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 type-alias: a mid-line missing '=' (`type T int`) reports the ExpectedToken NL102 anchored on the offender" {
    errors := RunPreamble("type T int\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected '='. Expected 'assign', got 'int'"
    assert e.Line == 1
    assert e.Column == 8
    assert e.Length == 3
    assert e.SourceSnippet == "type T int"
    assert e.HumanExplanation == "I was expecting assign here, but I found 'int' instead."
    assert e.ContextualHint == null
}

test "016 type-alias: the underlying type routes through the full type grammar so a malformed generic (`type T = List<>`) reports ReportMissingGenericTypeArgument" {
    errors := RunPreamble("type T = List<>\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type name. Got '>'"
    assert e.Line == 1
    assert e.Column == 10
    assert e.Length == 6
    assert e.SourceSnippet == "type T = List<>"
    assert e.HumanExplanation == "Generic type 'List' needs a type argument between '<' and '>'."
    assert e.ContextualHint == "Write this type as `List<T>` or remove the generic argument list."
    assert e.Suggestion == "Add a type argument"
}

test "016 type-alias: a missing alias name (`type = int`) reports ONLY the name error — the '=' and underlying type are then consumed cleanly" {
    errors := RunPreamble("type = int\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected type alias name. Got '='"
    assert e.Line == 1
    assert e.Column == 1
    assert e.Length == 4
    assert e.SourceSnippet == "type = int"
    assert e.HumanExplanation == "I was expecting an identifier here, but I found '=' instead."
    assert e.ContextualHint == "An identifier is a name for a variable, function, or type."
}

test "016 type-alias: the newtype variant routes its underlying type through the same grammar (`type T = newtype` at EOF reports the missing-type NL104)" {
    errors := RunPreamble("type T = newtype")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.UnexpectedEndOfFile
    assert e.Message == "Expected type name, but reached the end of the file"
    assert e.Line == 1
    assert e.Column == 10
    assert e.Length == 7
    assert e.SourceSnippet == "type T = newtype"
    assert e.HumanExplanation == "I was expecting an identifier here, but the file ended first."
    assert e.ContextualHint == "Finish this construct before the end of the file."
}

test "016 type-alias: a trailing '|' in a union underlying type (`type T = A |`) reports the anonymous-union missing-arm NL103" {
    errors := RunPreamble("type T = A |\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Expected a type after '|' in anonymous union type"
    assert e.Line == 2
    assert e.Column == 1
    assert e.Length == 1
    assert e.HumanExplanation == "Anonymous union types use the form `A | B`, so every `|` must be followed by another type."
    assert e.ContextualHint == "Add the missing type arm, or remove the trailing `|`."
}

// ---- type-alias negatives: valid underlying types across the full Stage-15 grammar report nothing ----

test "016 type-alias negative: a valid union underlying type (`type T = A | B`) reports no parser diagnostic" {
    assert RunPreamble("type T = A | B\n").Count == 0
}

test "016 type-alias negative: a simple underlying type (`type T = int`) reports no parser diagnostic" {
    assert RunPreamble("type T = int\n").Count == 0
}

test "016 type-alias negative: the newtype variant (`type T = newtype int`) reports no parser diagnostic" {
    assert RunPreamble("type T = newtype int\n").Count == 0
}

test "016 type-alias negative: a tuple underlying type (`type T = (int, string)`) reports no parser diagnostic" {
    assert RunPreamble("type T = (int, string)\n").Count == 0
}

test "016 type-alias negative: a Func underlying type (`type Callback = Func<int, bool>`) reports no parser diagnostic" {
    assert RunPreamble("type Callback = Func<int, bool>\n").Count == 0
}

test "016 type-alias negative: a postfix array underlying type (`type T = int[]`) reports no parser diagnostic" {
    assert RunPreamble("type T = int[]\n").Count == 0
}

test "016 type-alias negative: a nullable underlying type (`type T = A?`) reports no parser diagnostic" {
    assert RunPreamble("type T = A?\n").Count == 0
}

// ---- deferral-ledger closeout: the NOW-PINNABLE corpus-light shapes previously left un-pinned ----

test "016 operator: an invalid operator-overload symbol (`func operator @`) reports the InvalidSyntax NL103 (Stage-14 corpus-light shape, now pinned)" {
    errors := RunPreamble("class C {\n  func operator @(a: C): C => a\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.InvalidSyntax
    assert e.Message == "Invalid operator symbol '@' for operator overloading"
    assert e.Line == 2
    assert e.Column == 17
    assert e.Length == 1
    assert e.SourceSnippet == "  func operator @(a: C): C => a"
    assert e.HumanExplanation == "This operator cannot be overloaded, or is not a valid operator symbol."
    assert e.ContextualHint == "Only certain operators can be overloaded in operator declarations."
    assert e.Suggestion == "Arithmetic: +, -, *, /, %"
}

test "016 returns-lifetime: a missing lifetime label after 'returns' on a LOCAL function reports the ExpectedToken NL102 (Stage-13 corpus-light shape, now pinned via the local-function vehicle that wires ParseReturnLifetimeAnnotation)" {
    // Stage 13 wired ParseReturnLifetimeAnnotation into ParseLocalFunction (not the top-level
    // ParseFunctionHeadAndBody), so the `returns` grammar is reached through a local function `g`.
    errors := RunPreamble("func f() {\n  func g(): int returns {\n    return 1\n  }\n}\n")
    assert errors.Count == 1
    e := errors[0]
    assert e.Code == ErrorCode.ExpectedToken
    assert e.Message == "Expected lifetime label after 'returns'. Got '{'"
    assert e.Line == 2
    assert e.Column == 25
    assert e.Length == 1
    assert e.SourceSnippet == "  func g(): int returns {"
    assert e.HumanExplanation == "Systems lifetime annotations use `returns 'a`, `returns param(name)`, or `returns heap(owner)` to describe a ref-like return."
    assert e.ContextualHint == "Write a lifetime such as `returns 'a`, `returns heap(owner)`, or remove the `returns` annotation."
}

test "016 raw-string negative: a well-formed multi-line interpolated raw string in the block vehicle reports nothing (Stage-12 corpus-light raw edge, now pinned)" {
    assert RunPreamble("func f() {\n  print $\"\"\"\n{x}\n\"\"\"\n}\n").Count == 0
}

// Task-016 parser-front-end arc, Stage N+1 (the AST/facts BRIDGE, first increment): parity
// contracts for the PRODUCTION Ast node instances the recovery owner now constructs for the file
// preamble (Namespace / Imports / Package), alongside the owned diagnostics. Each expected node
// field is the value Parser.cs's ParseCompilationUnit hangs on ParseResult.CompilationUnit for the
// same source — NamespaceDeclaration(name, keywordLine, keywordColumn) (Parser.cs :127),
// PackageDeclaration(name, keywordLine, keywordColumn) (:136), and, for a NAMESPACE import,
// ImportDirective(namespace, alias, importKeywordLine, importKeywordColumn) (:71). The owner and
// Parser.cs construct the identical NSharpLang.Compiler.Ast types (both N#, owned in this assembly),
// through the identical preamble grammar, so matching these fields proves the bridge builds the same
// preamble subtree as the production parser. The corpus pins WELL-FORMED preambles: node identity on
// the recovery path is out of scope for this first increment (the diagnostics are pinned by the
// Stage-1 corpus above). FileImports / the CompilationUnit container / Declarations are downstream C#
// and are the recorded N+1 block — not built here.

func RunPreambleAst(source: string): PreambleAst {
    return ColumnarParserRecovery.ParseFilePreambleAst(source, "a.nl")
}

test "016 bridge: a lone file-scoped namespace materializes NamespaceDeclaration anchored on the keyword" {
    ast := RunPreambleAst("namespace Foo.Bar")
    assert ast.Errors.Count == 0
    assert ast.Namespace != null
    assert ast.Namespace.Name == "Foo.Bar"
    assert ast.Namespace.Line == 1
    assert ast.Namespace.Column == 1
    assert ast.Imports.Count == 0
    assert ast.Package == null
}

test "016 bridge: a package declaration materializes PackageDeclaration anchored on the keyword" {
    ast := RunPreambleAst("package Acme.Widgets")
    assert ast.Errors.Count == 0
    assert ast.Package != null
    assert ast.Package.Name == "Acme.Widgets"
    assert ast.Package.Line == 1
    assert ast.Package.Column == 1
    assert ast.Namespace == null
    assert ast.Imports.Count == 0
}

test "016 bridge: a valid package name carries per-segment spans" {
    ast := RunPreambleAst("package Acme.Widgets")
    assert ast.Package != null
    segments := ast.Package.Segments
    assert segments != null
    assert segments.Count == 2
    assert segments[0].Text == "Acme"
    assert segments[0].Line == 1
    assert segments[0].Column == 9
    assert segments[0].Length == 4
    assert segments[1].Text == "Widgets"
    assert segments[1].Column == 14
    assert segments[1].Length == 7
}

// ---- recovery preserves what the developer wrote (the `package good.9bad` family) ----
// A malformed segment written ATTACHED to the name is consumed as one word-like run and carried
// with its span, producing NO parser diagnostic — the whole-pipeline report for it is the
// analyzer's NL103, which names and underlines the written text (the analyzer half is pinned in
// AnalyzerDeclarationPolicy.tests.nl "with parser segments..."). Before this, `package good.9bad`
// reported "Expected identifier after '.'" here, left `9`/`bad` for the top-level loop's
// unexpected-token + `<error>`-class cascade, and the analyzer named the placeholder at 1:1.

test "016 bridge: a malformed attached segment is carried as written, with its span, and no parser diagnostic" {
    ast := RunPreambleAst("package good.9bad\n\nfunc Foo(): int {\n    return 1\n}\n")
    assert ast.Errors.Count == 0
    assert ast.Package != null
    assert ast.Package.Name == "good.9bad"
    segments := ast.Package.Segments
    assert segments != null
    assert segments.Count == 2
    assert segments[0].Text == "good"
    assert segments[0].Line == 1
    assert segments[0].Column == 9
    assert segments[0].Length == 4
    assert segments[1].Text == "9bad"
    assert segments[1].Line == 1
    assert segments[1].Column == 14
    assert segments[1].Length == 4
}

test "016 bridge: a malformed segment run stops at a dot, so the segments around it stay intact" {
    ast := RunPreambleAst("package good.9bad.more")
    assert ast.Errors.Count == 0
    assert ast.Package != null
    assert ast.Package.Name == "good.9bad.more"
    segments := ast.Package.Segments
    assert segments != null
    assert segments.Count == 3
    assert segments[1].Text == "9bad"
    assert segments[2].Text == "more"
}

test "016 bridge: a malformed segment run consumes only ADJACENT text — a detached token stays genuinely unexpected" {
    ast := RunPreambleAst("package good.9 bad\n")
    assert ast.Package != null
    assert ast.Package.Name == "good.9"
    segments := ast.Package.Segments
    assert segments != null
    assert segments.Count == 2
    assert segments[1].Text == "9"
    assert segments[1].Column == 14
    assert segments[1].Length == 1
    assert ast.Errors.Count == 1
    assert ast.Errors[0].Code == ErrorCode.UnexpectedToken
    assert ast.Errors[0].Message == "Unexpected token 'bad'"
}

test "016 bridge: a package trailing dot at end of file keeps the parser's one report and records the placeholder segment" {
    // With nothing written after the dot there is no text to carry: the parser's end-of-file
    // diagnostic is THE report, and the `<error>` placeholder segment tells the analyzer to stay
    // silent instead of naming the placeholder (pinned in AnalyzerDeclarationPolicy.tests.nl).
    ast := RunPreambleAst("package good.")
    assert ast.Errors.Count == 1
    assert ast.Errors[0].Code == ErrorCode.UnexpectedEndOfFile
    assert ast.Package != null
    assert ast.Package.Name == "good.<error>"
    segments := ast.Package.Segments
    assert segments != null
    assert segments.Count == 2
    assert segments[0].Text == "good"
    assert segments[1].Text == "<error>"
}

test "016 bridge: a reserved keyword as a package segment keeps its keyword-specific diagnostic and the placeholder" {
    ast := RunPreambleAst("package good.class\n")
    assert ast.Errors.Count == 1
    assert ast.Errors[0].Code == ErrorCode.ReservedKeywordAsName
    assert ast.Package != null
    assert ast.Package.Name == "good.<error>"
}

test "016 bridge: a bare namespace import materializes one ImportDirective with a null alias" {
    ast := RunPreambleAst("import System")
    assert ast.Errors.Count == 0
    assert ast.Imports.Count == 1
    imp := ast.Imports[0]
    assert imp.Namespace == "System"
    assert imp.Alias == null
    assert imp.Line == 1
    assert imp.Column == 1
    assert ast.Namespace == null
    assert ast.Package == null
}

test "016 bridge: a qualified aliased import carries the joined name and the alias" {
    ast := RunPreambleAst("import System.Collections.Generic as Gen")
    assert ast.Errors.Count == 0
    assert ast.Imports.Count == 1
    imp := ast.Imports[0]
    assert imp.Namespace == "System.Collections.Generic"
    assert imp.Alias == "Gen"
    assert imp.Line == 1
    assert imp.Column == 1
}

test "016 bridge: a full multi-line preamble materializes namespace + package + both imports with per-line anchoring" {
    ast := RunPreambleAst("namespace App\npackage app.core\nimport A\nimport B.C as BC")
    assert ast.Errors.Count == 0

    assert ast.Namespace != null
    assert ast.Namespace.Name == "App"
    assert ast.Namespace.Line == 1
    assert ast.Namespace.Column == 1

    assert ast.Package != null
    assert ast.Package.Name == "app.core"
    assert ast.Package.Line == 2
    assert ast.Package.Column == 1

    assert ast.Imports.Count == 2
    first := ast.Imports[0]
    assert first.Namespace == "A"
    assert first.Alias == null
    assert first.Line == 3
    assert first.Column == 1
    second := ast.Imports[1]
    assert second.Namespace == "B.C"
    assert second.Alias == "BC"
    assert second.Line == 4
    assert second.Column == 1
}

test "016 bridge: a file import builds no ImportDirective (downstream FileImport is not part of the bridge)" {
    ast := RunPreambleAst("import \"./helpers.nl\"\nimport RealNamespace")
    assert ast.Errors.Count == 0
    // Only the namespace import becomes an ImportDirective; the file import is parsed for
    // diagnostics but routed (in Parser.cs) to the downstream FileImports list, not built here.
    assert ast.Imports.Count == 1
    assert ast.Imports[0].Namespace == "RealNamespace"
    assert ast.Imports[0].Line == 2
}

test "016 bridge: empty source yields an all-absent preamble with no diagnostics" {
    ast := RunPreambleAst("")
    assert ast.Errors.Count == 0
    assert ast.Namespace == null
    assert ast.Package == null
    assert ast.Imports.Count == 0
}

test "016 bridge: the AST entry preserves the owned diagnostics byte-for-byte with the diagnostic-only entry" {
    // Same malformed source as the Stage-1 "import of a non-identifier" contract: the AST entry runs
    // the identical Run() grammar, so its Errors must match ParseFilePreamble's exactly (Count 2, the
    // found-other NL102 then the boundary-reset NL101), proving node construction is a pure side-effect
    // that does not perturb the shared-panic diagnostic stream.
    ast := RunPreambleAst("import 5\n")
    diagnosticsOnly := RunPreamble("import 5\n")
    assert ast.Errors.Count == diagnosticsOnly.Count
    assert ast.Errors.Count == 2
    assert ast.Errors[0].Code == ErrorCode.ExpectedToken
    assert ast.Errors[0].Message == "Expected identifier. Got '5'"
    assert ast.Errors[1].Code == ErrorCode.UnexpectedToken
    assert ast.Errors[1].Message == "Unexpected token '5'"
}

// ── the total-parse guarantee ─────────────────────────────────────────────────────────────────
//
// Successor to `Parser_AlwaysProducesCompilationUnit_EvenWithErrors`, deleted from
// `tests/ErrorRecoveryPipelineTests.cs` (21 declaration lines, ONE `Assert.` row inside a loop over
// five malformed sources). The row asserted `result.CompilationUnit` was not null for each. That is
// the contract every downstream consumer depends on — the LSP, `nlc check` and the formatter all
// call `ParseFileAst` and then walk the unit — and a null would be a crash, not a diagnostic.
//
// THE DELETED ROW COULD NOT SAY THE OTHER HALF, AND IT IS THE HALF THAT MATTERS. A parser that
// returned an EMPTY compilation unit for every input would have satisfied it five times over. Each
// source below therefore also states what the recovery actually SALVAGED and that the failure was
// REPORTED, so "not null" is not the whole claim.

test "a malformed body still yields a unit, with the declaration recovered and the error reported" {
    result := ColumnarParserRecovery.ParseFileAst("func test() { @@ }", "test.nl")

    assert result.CompilationUnit != null
    assert result.CompilationUnit.Declarations.Count == 1
    assert result.Errors.Count > 0
}

test "a malformed initializer still yields a unit and keeps the enclosing function" {
    result := ColumnarParserRecovery.ParseFileAst("func test() { let x: int = @@ }", "test.nl")

    assert result.CompilationUnit != null
    assert result.CompilationUnit.Declarations.Count == 1
    assert result.Errors.Count > 0
}

test "a dangling member access still yields a unit and keeps the enclosing function" {
    result := ColumnarParserRecovery.ParseFileAst("func test() { x. }", "test.nl")

    assert result.CompilationUnit != null
    assert result.CompilationUnit.Declarations.Count == 1
    assert result.Errors.Count > 0
}

test "an unclosed function recovers at the next top-level declaration rather than swallowing it" {
    // THE SHARPEST OF THE FIVE. `func test()` is never closed, and `class Foo` follows. A recovery
    // that resynchronised badly would lose the class; the deleted row could not tell the two apart
    // because BOTH produce a non-null unit.
    result := ColumnarParserRecovery.ParseFileAst("func test() {\n    let x = 5\n\nclass Foo { name: string }", "test.nl")

    assert result.CompilationUnit != null
    assert result.CompilationUnit.Declarations.Count == 2
    assert result.Errors.Count > 0
}

test "a file of pure punctuation still yields a unit, and recovery INVENTS declarations for it" {
    // THE FIFTH SOURCE, AND THE ONE THAT TURNED OVER A DEFECT. The deleted row asserted only that
    // this file's unit was not null. It is not null — and it carries THREE declarations that no
    // syntax in the file asked for, while reporting only TWO of the file's SIX errors.
    result := ColumnarParserRecovery.ParseFileAst("@@ ## !! %%", "test.nl")

    assert result.CompilationUnit != null
    assert result.CompilationUnit.Declarations.Count == 3
    assert result.Errors.Count == 2
    assert result.Errors[0].Message == "Unexpected token '@'"
    assert result.Errors[1].Message == "Unexpected token '@'"
}

test "each punctuation run ALONE reports two errors — except ## which reports NONE" {
    // MEASURED, RECORDED, NOT FIXED. `##` at the top level parses as a PREPROCESSOR declaration and
    // is accepted in silence: a user who types it gets a clean file. The other three runs are
    // rejected two tokens at a time.
    assert ColumnarParserRecovery.ParseFileAst("@@", "test.nl").Errors.Count == 2
    assert ColumnarParserRecovery.ParseFileAst("!!", "test.nl").Errors.Count == 2
    assert ColumnarParserRecovery.ParseFileAst("%%", "test.nl").Errors.Count == 2
    assert ColumnarParserRecovery.ParseFileAst("##", "test.nl").Errors.Count == 0
}

test "the preprocessor declaration SWALLOWS every diagnostic after it in the same file" {
    // THE DEFECT, ISOLATED. `!!` reports two errors on its own and `%%` reports two on its own, so
    // the four-run file should report six. It reports the TWO from `@@` and stops — the four that
    // follow the `##` are lost. The deleted row could not see this: it asked only whether the unit
    // was null, and a unit that reports nothing at all is just as non-null as a correct one.
    //
    // The pair below is the proof, not the claim: the SAME two runs, before and after a `##`.
    assert ColumnarParserRecovery.ParseFileAst("!! %%", "test.nl").Errors.Count == 4
    assert ColumnarParserRecovery.ParseFileAst("## !! %%", "test.nl").Errors.Count == 0
}
