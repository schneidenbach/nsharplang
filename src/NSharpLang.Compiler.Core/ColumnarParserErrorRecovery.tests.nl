namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL PARSER-ERROR-RECOVERY CONTRACTS FOR `ColumnarParserRecovery.ParseFileAst`, IN N#.
//
// These replace `tests/ParserErrorTests.cs` — 1,914 C# lines, 91 test methods, 104 expanded xUnit
// cases, 419 `Assert.` statements — which task 020 slice 16 deletes terminally. Its subject is the
// N#-owned recovery parser: a malformed source goes in, a diagnostic list and a partial
// `CompilationUnit` come out. Source in, diagnostics out; nothing mocked, nothing stubbed.
//
// WHY THIS FILE AND NOT AN APPEND TO `ColumnarParserRecovery.tests.nl`. That file (6,016 lines) is
// the task-016 PARITY suite, and every one of its contracts calls `ParseFilePreamble` — the
// diagnostic-only entry point that returns POSITION-SORTED errors for the CLI-shaped oracle
// comparison. The deleted C# file called `ParseFileAst`, which returns errors in Parser.cs's
// RECORDING order and also hands back the recovered tree. Those are two different observable
// contracts of the same owner, and the difference is not cosmetic: see the
// "recording order is not position order" contract below, where one source's two diagnostics come
// back in OPPOSITE orders from the two entry points. Mixing the two conventions in one file would
// make every future reader guess which order a census is in.
//
// THE THREE KERNELS EVERY CONTRACT GOES THROUGH, AND WHY THEY ARE STRINGS.
//
// (1) `PeCensus` renders EVERY diagnostic's code and span, in order. It replaces
// `Assert.Single(result.Errors)`, `Assert.Contains(result.Errors, e => …)`,
// `Assert.DoesNotContain(…)`, `result.Errors.First(…)` and `Assert.True(result.Errors.Count >= 3)`
// all at once — a census states the cardinality, the order, and the absence of everything not in
// it, which no combination of those five can do.
//
// (2) `PeRow` renders one diagnostic WHOLE: code, span, message, source snippet, human explanation,
// contextual hint, the full suggestion list and the docs URL. The deleted file reached these with
// `Assert.Contains("dot", error.HumanExplanation, StringComparison.OrdinalIgnoreCase)` and
// `Assert.NotNull(error.Suggestions)`; a whole-text row cannot be satisfied by a reworded sentence
// or by a suggestion list that lost two of its three entries.
//
// (3) `PeDecls` / `PeStmts` / `PeMembers` render the RECOVERED TREE by runtime node type. The
// deleted file asked `Declarations.OfType<ClassDeclaration>().FirstOrDefault(c => c.Name ==
// "MyClass") != null`, which is true of a tree that also lost three other declarations or gained
// six `<error>` placeholders. A census sees both.
//
// The kernels are strings and not nullable node handles for a second reason: a `CompilerError?`
// helper would put NL905 rows in a `.tests.nl`, and the estate's live-tree contract requires zero.
//
// WHAT THE MIGRATION MEASURED THAT NOTHING HAD WRITTEN DOWN. Nine facts, each pinned below where it
// belongs: the top-level recovery synthesizes `<error>`-named CLASS declarations for stray tokens;
// `##` lexes as a PREPROCESSOR directive, so `@@ ## !! %%` reports two diagnostics and not four; an
// unclosed function brace turns the NEXT function into a LOCAL function of the first; a field with a
// malformed initializer SWALLOWS the field after it while a field with a missing TYPE does not; the
// `enum Status: decimal` diagnostic is the only one in the whole corpus with a null
// `HumanExplanation`, which routes it through the rust-style renderer instead of the Elm one; the
// tuple-deconstruction placeholder anchors at line 3 COLUMN 2; errors inside an interpolation hole
// are reported with a span INSIDE the hole; `ParseFileAst` order is recording order, not position
// order; and the reserved-keyword-after-dot hint contains a DOUBLE SPACE.
//
// THE ONE THING THE DELETED FILE STATED THAT THIS FILE DOES NOT, MEASURED AND NAMED.
// `Parser_MalformedTableDrivenTest_TerminatesWithErrors` wrapped the parse in
// `Task.Run(...)` + `Wait(TimeSpan.FromSeconds(10))`, so a lost no-progress guard failed FAST
// instead of hanging the host. `Task.Run` declines to emit in this estate (so does `Stopwatch`, and
// so does `Environment.TickCount64` — all three measured), so no wall-clock bound is expressible
// here. Two of that theory's three rows ALREADY have full-field contracts in
// `ColumnarParserRecovery.tests.nl` ("016 test-dsl: an untyped table header …"), written when those
// shapes were found to hang; the third row is added below with its whole census. The fail-fast
// property is the first concrete consumer of the "whole-run timeout" capability on task 020's own
// list.
func PeParse(source: string): FileParseAst {
    return ColumnarParserRecovery.ParseFileAst(source, "test.nl")
}

// Snippets can carry a bare CR (a CRLF source is split on '\n' only), and messages can carry
// backslashes. Escape both so a whole-row pin is one readable literal.
func PeEsc(value: string?): string {
    if value == null {
        return "<null>"
    }
    return value.Replace("\\", "\\\\").Replace("\r", "\\r").Replace("\n", "\\n")
}

func PeKind(node: object?): string {
    boxed := node
    if boxed == null {
        return "<null>"
    }
    return boxed.GetType().Name
}

func PeSuggestions(e: CompilerError): string {
    suggestions := e.Suggestions
    if suggestions == null {
        return "<null>"
    }
    builder := new StringBuilder()
    for suggestion in suggestions {
        builder.Append("{")
        builder.Append(PeEsc(suggestion))
        builder.Append("}")
    }
    return builder.ToString()
}

// Every diagnostic's code and span, in `ParseFileAst`'s recording order. Empty for a clean parse.
func PeCensus(source: string): string {
    parsed := PeParse(source)
    builder := new StringBuilder()
    index := 0
    while index < parsed.Errors.Count {
        e := parsed.Errors[index]
        builder.Append(e.DiagnosticId)
        builder.Append("@")
        builder.Append(e.Line.ToString())
        builder.Append(":")
        builder.Append(e.Column.ToString())
        builder.Append("+")
        builder.Append(e.Length.ToString())
        builder.Append(";")
        index = index + 1
    }
    return builder.ToString()
}

// The same census as the CLI-shaped, position-SORTED entry point returns.
func PeSortedCensus(source: string): string {
    errors := ColumnarParserRecovery.ParseFilePreamble(source, "test.nl")
    builder := new StringBuilder()
    index := 0
    while index < errors.Count {
        e := errors[index]
        builder.Append(e.DiagnosticId)
        builder.Append("@")
        builder.Append(e.Line.ToString())
        builder.Append(":")
        builder.Append(e.Column.ToString())
        builder.Append("+")
        builder.Append(e.Length.ToString())
        builder.Append(";")
        index = index + 1
    }
    return builder.ToString()
}

func PeSeverities(source: string): string {
    parsed := PeParse(source)
    builder := new StringBuilder()
    index := 0
    while index < parsed.Errors.Count {
        if parsed.Errors[index].Severity == ErrorSeverity.Error {
            builder.Append("error;")
        } else {
            builder.Append("other;")
        }
        index = index + 1
    }
    return builder.ToString()
}

// One diagnostic, whole: span, message, snippet, explanation, hint, every suggestion, docs URL.
func PeRow(source: string, index: int): string {
    parsed := PeParse(source)
    if index >= parsed.Errors.Count {
        return "<no-such-error>"
    }
    e := parsed.Errors[index]
    builder := new StringBuilder()
    builder.Append(e.DiagnosticId)
    builder.Append("@")
    builder.Append(e.Line.ToString())
    builder.Append(":")
    builder.Append(e.Column.ToString())
    builder.Append("+")
    builder.Append(e.Length.ToString())
    builder.Append("|")
    builder.Append(PeEsc(e.Message))
    builder.Append("|")
    builder.Append(PeEsc(e.SourceSnippet))
    builder.Append("|")
    builder.Append(PeEsc(e.HumanExplanation))
    builder.Append("|")
    builder.Append(PeEsc(e.ContextualHint))
    builder.Append("|")
    builder.Append(PeSuggestions(e))
    builder.Append("|")
    builder.Append(PeEsc(e.DocsUrl))
    return builder.ToString()
}

// The recovered top level, by runtime node type. Functions carry their body statement count (or
// `/nobody`); types carry their member count; enums carry their name.
func PeDecls(source: string): string {
    parsed := PeParse(source)
    unit := parsed.CompilationUnit
    if unit == null {
        return "<null-unit>"
    }
    builder := new StringBuilder()
    index := 0
    while index < unit.Declarations.Count {
        declaration := unit.Declarations[index]
        builder.Append(PeKind(declaration))
        builder.Append("[")
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            builder.Append(functionDeclaration.Name)
            body := functionDeclaration.Body
            if body != null {
                builder.Append("/s")
                builder.Append(body.Statements.Count.ToString())
            } else {
                builder.Append("/nobody")
            }
        }
        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            builder.Append(classDeclaration.Name)
            builder.Append("/m")
            builder.Append(classDeclaration.Members.Count.ToString())
        }
        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            builder.Append(structDeclaration.Name)
            builder.Append("/m")
            builder.Append(structDeclaration.Members.Count.ToString())
        }
        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            builder.Append(enumDeclaration.Name)
        }
        builder.Append("]")
        index = index + 1
    }
    return builder.ToString()
}

func PeStatementText(statement: Statement): string {
    builder := new StringBuilder()
    builder.Append(PeKind(statement))
    variableDeclaration := statement as VariableDeclarationStatement
    if variableDeclaration != null {
        builder.Append("(")
        builder.Append(variableDeclaration.Name)
        builder.Append(")")
    }
    foreachStatement := statement as ForeachStatement
    if foreachStatement != null {
        builder.Append("(")
        builder.Append(foreachStatement.VariableName)
        builder.Append("/")
        builder.Append(PeKind(foreachStatement.Body))
        builder.Append(")")
    }
    forStatement := statement as ForStatement
    if forStatement != null {
        builder.Append("(")
        builder.Append(PeKind(forStatement.Body))
        builder.Append(")")
    }
    whileStatement := statement as WhileStatement
    if whileStatement != null {
        builder.Append("(")
        builder.Append(PeKind(whileStatement.Body))
        builder.Append(")")
    }
    deconstruction := statement as TupleDeconstructionStatement
    if deconstruction != null {
        builder.Append("(")
        builder.Append(String.Join(",", deconstruction.Names))
        builder.Append("/")
        builder.Append(PeKind(deconstruction.Initializer))
        initializer := deconstruction.Initializer as IdentifierExpression
        if initializer != null {
            builder.Append("=")
            builder.Append(initializer.Name)
            builder.Append("@")
            builder.Append(initializer.Line.ToString())
            builder.Append(":")
            builder.Append(initializer.Column.ToString())
        }
        builder.Append(")")
    }
    return builder.ToString()
}

// Every statement of every recovered function body, in order.
func PeStmts(source: string): string {
    parsed := PeParse(source)
    unit := parsed.CompilationUnit
    if unit == null {
        return "<null-unit>"
    }
    builder := new StringBuilder()
    index := 0
    while index < unit.Declarations.Count {
        functionDeclaration := unit.Declarations[index] as FunctionDeclaration
        if functionDeclaration != null {
            body := functionDeclaration.Body
            if body != null {
                statementIndex := 0
                while statementIndex < body.Statements.Count {
                    builder.Append(PeStatementText(body.Statements[statementIndex]))
                    builder.Append(";")
                    statementIndex = statementIndex + 1
                }
            }
        }
        index = index + 1
    }
    return builder.ToString()
}

func PeMemberText(member: Declaration): string {
    builder := new StringBuilder()
    builder.Append(PeKind(member))
    field := member as FieldDeclaration
    if field != null {
        builder.Append("(")
        builder.Append(field.Name)
        builder.Append(")")
    }
    builder.Append(",")
    return builder.ToString()
}

// Every member of every recovered class/struct, by node type and name.
func PeMembers(source: string): string {
    parsed := PeParse(source)
    unit := parsed.CompilationUnit
    if unit == null {
        return "<null-unit>"
    }
    builder := new StringBuilder()
    index := 0
    while index < unit.Declarations.Count {
        declaration := unit.Declarations[index]
        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            builder.Append(classDeclaration.Name)
            builder.Append("{")
            memberIndex := 0
            while memberIndex < classDeclaration.Members.Count {
                builder.Append(PeMemberText(classDeclaration.Members[memberIndex]))
                memberIndex = memberIndex + 1
            }
            builder.Append("}")
        }
        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            builder.Append(structDeclaration.Name)
            builder.Append("{")
            memberIndex := 0
            while memberIndex < structDeclaration.Members.Count {
                builder.Append(PeMemberText(structDeclaration.Members[memberIndex]))
                memberIndex = memberIndex + 1
            }
            builder.Append("}")
        }
        index = index + 1
    }
    return builder.ToString()
}

// ══ RESERVED KEYWORD AS A NAME (NL109) ═══════════════════════════════════════════════════════
//
// Successors to the deleted file's `#region Reserved Keyword As Name (NL109)`. The regression it
// guarded is real and named in its own comment: a keyword-named field once flowed into the IL
// backend as an `<error>` placeholder and emitted unverifiable IL. The three refusals are three
// DIFFERENT sentences and two different hints, which the deleted file's
// `Assert.Contains("reserved keyword", …, OrdinalIgnoreCase)` could not tell apart.

// Successor to Parser_ReportsError_ReservedKeyword_AsFieldName. The deleted file asserted the
// code, `NL109`, the line, and that the explanation mentions 'reserved keyword' and 'base'. The
// whole row states the span (4 characters over `base`), both sentences and both suggestions, and
// the census states that this is the ONLY diagnostic — so a parser that also cascaded would fail.
// AND THE MEMBER CENSUS STATES THE THING THE DELETED FILE'S OWN COMMENT DESCRIBED BUT NEVER
// ASSERTED: the recovered field is named `<error>`, not `base`. That placeholder IS the artifact
// the regression was about — 'a keyword-named field flowed into the IL backend as an `<error>`
// placeholder and emitted unverifiable IL (InvalidProgramException)'. Pinning the member name is
// what makes the shape of the recovery observable instead of inferred from the diagnostic alone.
test "020 slice 16: a reserved keyword as a FIELD name is refused with the keyword-specific NL109" {
    assert !PeParse("\nclass Counter {\n    base: int\n}").Success
    assert PeCensus("\nclass Counter {\n    base: int\n}") == "NL109@3:5+4;", PeCensus("\nclass Counter {\n    base: int\n}")
    assert PeRow("\nclass Counter {\n    base: int\n}", 0) == "NL109@3:5+4|Expected field name. Got the reserved keyword 'base'|    base: int|'base' is a reserved keyword in N#, so it can't be used as a name here.|Choose a name that isn't a reserved keyword (for example 'baseValue' or '_base').|{Rename it to 'baseValue' or '_base'}{Pick any name that isn't a reserved N# keyword}|https://schneidenbach.github.io/nsharplang/docs/errors/NL109", PeRow("\nclass Counter {\n    base: int\n}", 0)
    assert PeDecls("\nclass Counter {\n    base: int\n}") == "ClassDeclaration[Counter/m1]", PeDecls("\nclass Counter {\n    base: int\n}")
    assert PeMembers("\nclass Counter {\n    base: int\n}") == "Counter{FieldDeclaration(<error>),}", PeMembers("\nclass Counter {\n    base: int\n}")
}

// Successor to Parser_ReportsError_ReservedKeyword_AsMemberNameAfterDot, which asserted only the
// code and that the explanation mentions 'reserved keyword' — satisfied by the field-position
// sentence. The member-position hint is a DIFFERENT sentence: it tells the developer to reach the
// member through an alias rather than to rename it, because the member is not theirs to rename.
// PINNED AS WRITTEN, DOUBLE SPACE INCLUDED ('to reach a  member'): the identical text is already
// pinned for the `class` keyword at ColumnarParserRecovery.tests.nl's package-segment contract, so
// the typo is knowingly recorded in two places rather than silently accepted in one.
test "020 slice 16: a reserved keyword AFTER A DOT gets its own hint, not the rename hint" {
    assert !PeParse("\nfunc test() {\n    x := obj.base\n}").Success
    assert PeCensus("\nfunc test() {\n    x := obj.base\n}") == "NL109@3:14+4;", PeCensus("\nfunc test() {\n    x := obj.base\n}")
    assert PeRow("\nfunc test() {\n    x := obj.base\n}", 0) == "NL109@3:14+4|Expected member name. Got the reserved keyword 'base'|    x := obj.base|'base' is a reserved keyword in N#, so it can't be used as a name here.|After a member access, the name must not be a reserved keyword. To reach a  member literally named 'base', access it through a differently-named alias.|{Rename it to 'baseValue' or '_base'}{Pick any name that isn't a reserved N# keyword}|https://schneidenbach.github.io/nsharplang/docs/errors/NL109", PeRow("\nfunc test() {\n    x := obj.base\n}", 0)
    assert PeStmts("\nfunc test() {\n    x := obj.base\n}") == "VariableDeclarationStatement(x);", PeStmts("\nfunc test() {\n    x := obj.base\n}")
}

// Successor to Parser_ReportsError_ReservedKeyword_AsFunctionParameterName, which asserted only
// `Assert.Contains(result.Errors, e => e.Code == ReservedKeywordAsName)` — true of a parse that
// reported it ten times. The census states it once.
test "020 slice 16: a reserved keyword as a PARAMETER name is refused and the function keeps no body" {
    assert !PeParse("func test(base: int) {}").Success
    assert PeCensus("func test(base: int) {}") == "NL109@1:11+4;", PeCensus("func test(base: int) {}")
    assert PeRow("func test(base: int) {}", 0) == "NL109@1:11+4|Expected parameter name. Got the reserved keyword 'base'|func test(base: int) {}|'base' is a reserved keyword in N#, so it can't be used as a name here.|Choose a name that isn't a reserved keyword (for example 'baseValue' or '_base').|{Rename it to 'baseValue' or '_base'}{Pick any name that isn't a reserved N# keyword}|https://schneidenbach.github.io/nsharplang/docs/errors/NL109", PeRow("func test(base: int) {}", 0)
    assert PeDecls("func test(base: int) {}") == "FunctionDeclaration[test/s0]", PeDecls("func test(base: int) {}")
}

// Successor to Parser_AcceptsNonKeywordIdentifiers_ThatAreIlAsmReserved — the REMOVAL CONTROL for
// the three refusals above. It is the only source in this region that must produce nothing, and
// the member census proves both fields survived with their written names rather than the parse
// merely staying silent.
test "020 slice 16: `value` and `method` are ILAsm-reserved but NOT N# keywords and parse clean" {
    assert PeParse("\nclass Box {\n    value: int\n    method: int\n}").Success
    assert PeCensus("\nclass Box {\n    value: int\n    method: int\n}") == "", PeCensus("\nclass Box {\n    value: int\n    method: int\n}")
    assert PeDecls("\nclass Box {\n    value: int\n    method: int\n}") == "ClassDeclaration[Box/m2]", PeDecls("\nclass Box {\n    value: int\n    method: int\n}")
    assert PeMembers("\nclass Box {\n    value: int\n    method: int\n}") == "Box{FieldDeclaration(value),FieldDeclaration(method),}", PeMembers("\nclass Box {\n    value: int\n    method: int\n}")
}

// ══ THE MEMBER-ACCESS SPAN COVERS THE RECEIVER ═══════════════════════════════════════════════
//
// Four sources reach the same NL102 through four different receivers, and the span is the
// RECEIVER every time — `x` (1), `name` (4), `employees` (9). The deleted file asserted the span
// for exactly one of them and only the LINE for the others, so a span that had collapsed onto the
// dot would have passed three of the four.

// Successor to Parser_ReportsError_IncompleteMemberAccess_SingleLine, which asserted the code, the
// line, a non-null explanation containing 'dot', and a non-empty suggestion list. The whole row
// states the three suggestions BY TEXT — the third ('remove the trailing .') is the actionable one
// and no `NotEmpty` check can see whether it is still there.
test "020 slice 16: an incomplete member access on its own line underlines the one-character receiver" {
    assert !PeParse("\nfunc test() {\n    x.\n}").Success
    assert PeCensus("\nfunc test() {\n    x.\n}") == "NL102@3:5+1;", PeCensus("\nfunc test() {\n    x.\n}")
    assert PeRow("\nfunc test() {\n    x.\n}", 0) == "NL102@3:5+1|Expected member name. Got '}'|    x.|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test() {\n    x.\n}", 0)
    assert PeStmts("\nfunc test() {\n    x.\n}") == "ExpressionStatement;", PeStmts("\nfunc test() {\n    x.\n}")
}

// Successor to Parser_ReportsError_IncompleteMemberAccessBeforeSameLineToken_PointsAtReceiver.
test "020 slice 16: an incomplete member access before a same-line token underlines the whole receiver" {
    assert PeCensus("func test() { name. }") == "NL102@1:15+4;", PeCensus("func test() { name. }")
    assert PeRow("func test() { name. }", 0) == "NL102@1:15+4|Expected member name. Got '}'|func test() { name. }|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() { name. }", 0)
}

// Successor to Parser_ProvidesSuggestions_ForIncompleteMemberAccess, which asserted only that the
// suggestion list is non-empty and that every entry is non-empty. Three named suggestions, and the
// span scales with the receiver.
test "020 slice 16: a nine-character receiver gets a nine-character span" {
    assert PeCensus("func test() { employees. }") == "NL102@1:15+9;", PeCensus("func test() { employees. }")
    assert PeRow("func test() { employees. }", 0) == "NL102@1:15+9|Expected member name. Got '}'|func test() { employees. }|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() { employees. }", 0)
}

// Successor to Parser_ProvidesSourceSnippet (`Assert.Contains("x.", error.SourceSnippet)`) and to
// Parser_ProvidesHumanExplanation, whose only real claim was that the explanation does NOT contain
// the word 'null' — a claim the whole-text row subsumes and strengthens.
test "020 slice 16: the snippet is the offending SOURCE LINE, not the whole file" {
    assert PeCensus("func test() {\n    x.\n}") == "NL102@2:5+1;", PeCensus("func test() {\n    x.\n}")
    assert PeRow("func test() {\n    x.\n}", 0) == "NL102@2:5+1|Expected member name. Got '}'|    x.|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    x.\n}", 0)
}

// Successor to Parser_ProvidesSourceSnippet_PreservesCrLfSplitBehavior. The snippet is produced by
// splitting on '\n' alone, so a CRLF file's snippet keeps its trailing '\r'. This is the
// behaviour every consumer that measures snippet length inherits, and it is stated with the span
// unchanged from the LF sibling above — so the CR does not move the column.
test "020 slice 16: a CRLF source leaves the bare CR in the snippet" {
    assert PeCensus("func test() {\r\n    x.\r\n}") == "NL102@2:5+1;", PeCensus("func test() {\r\n    x.\r\n}")
    assert PeRow("func test() {\r\n    x.\r\n}", 0) == "NL102@2:5+1|Expected member name. Got '}'|    x.\\r|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\r\n    x.\r\n}", 0)
}

// Successor to Parser_ErrorFormat_IsReadable, which asserted that `Format(useColors: false)`
// contains the code, the file name and the line number. Those three `Contains` samples cannot see
// the gutter width, the caret column, the 'Hint:' label, the 'Did you mean one of these?' block or
// the 'Read more:' footer — all of which a developer reads on every failed build. The whole
// rendering is stated. The caret sits under the receiver at the span's column.
// NOTE: the renderer is chosen by `HumanExplanation` alone (CompilerError.tests.nl states that
// rule); this diagnostic has one, so it is Elm-style. The one corpus diagnostic that does NOT
// have one is `enum Status: decimal`, below.
test "020 slice 16: the parsed error renders WHOLE through the Elm-style terminal formatter" {
    error := PeParse("func test() { x. }").Errors[0]
    assert PeEsc(error.FileName) == "test.nl"
    assert PeEsc(error.Format(false)) == "-- ERROR --------------------------------------------------  test.nl\\n\\nI see a dot (.) operator but no member name after it.\\n\\n1|     func test() { x. }\\n                    ^\\n\\nHint: After dot (.), I need to see a property or method name.\\n\\nDid you mean one of these?\\n\\n    Check if you forgot to finish this line\\n    Common members: Length, Count, ToString(), GetHashCode()\\n    If this is end of statement, remove the trailing '.'\\n\\nRead more: https://schneidenbach.github.io/nsharplang/docs/errors/NL102\\n", PeEsc(error.Format(false))
    assert PeEsc(error.FormatForTooling(true, false)) == "NL102: Expected member name. Got '}'\\n\\nI see a dot (.) operator but no member name after it.\\n\\nfunc test() { x. }\\n              ^\\n\\nAfter dot (.), I need to see a property or method name.\\n\\ndid you mean:\\n- Check if you forgot to finish this line\\n- Common members: Length, Count, ToString(), GetHashCode()\\n- If this is end of statement, remove the trailing '.'\\n\\n\\ndocs: https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeEsc(error.FormatForTooling(true, false))
}

// Successor to Parser_ProvidesDocsUrl, which asserted the prefix and the `NL{code:D3}` anchor for
// ONE diagnostic. Every `PeRow` pin in this file ends with the whole URL, so the anchor is stated
// 101 times over; this contract states the composition rule itself.
// Also the successor to Parser_ReturnsCorrectErrorCode_ExpectedToken, whose whole body was
// `Assert.False(Success)` plus `Assert.Equal(ExpectedToken, result.Errors.FirstOrDefault().Code)`
// on this same source — carried by the census's `NL102` and the `codeValue == 102` pin.
test "020 slice 16: the docs URL is composed from the code, and every corpus row carries one" {
    error := PeParse("func test() { x. }").Errors[0]
    codeValue: int = (int)error.Code
    assert codeValue == 102
    assert PeEsc(error.DocsUrl) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL" + codeValue.ToString("D3")
    assert PeCensus("func test() { x. }") == "NL102@1:15+1;", PeCensus("func test() { x. }")
    assert PeRow("func test() { x. }", 0) == "NL102@1:15+1|Expected member name. Got '}'|func test() { x. }|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() { x. }", 0)
}

// ══ MISSING DECLARATION NAMES — ALL EIGHT KEYWORDS, ONE AT A TIME ════════════════════════════
//
// Successors to the eight `[InlineData]` rows of Parser_MissingDeclarationName_PointsAtDeclarationKeyword.
// The deleted theory asserted line 1, column 1, `keyword.Length` and `StartsWith(keyword)` on the
// snippet. Each row here additionally states the WHOLE message and the RECOVERED DECLARATION —
// and the recovered declarations are not uniform: `func`/`class`/`struct`/`enum` materialize an
// `<error>`-named node, while `record`/`interface`/`union`/`type` materialize a node with no name
// at all. Nothing had written that asymmetry down.

test "020 slice 16: a `func` declaration with no name underlines the `func` keyword" {
    assert PeCensus("func () {\n}") == "NL102@1:1+4;", PeCensus("func () {\n}")
    assert PeRow("func () {\n}", 0) == "NL102@1:1+4|Expected function name. Got '('|func () {|I was expecting an identifier here, but I found '(' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func () {\n}", 0)
    assert PeDecls("func () {\n}") == "FunctionDeclaration[<error>/s0]", PeDecls("func () {\n}")
}

test "020 slice 16: a `class` declaration with no name underlines the `class` keyword" {
    assert PeCensus("class {\n}") == "NL102@1:1+5;", PeCensus("class {\n}")
    assert PeRow("class {\n}", 0) == "NL102@1:1+5|Expected class name. Got '{'|class {|I was expecting an identifier here, but I found '{' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class {\n}", 0)
    assert PeDecls("class {\n}") == "ClassDeclaration[<error>/m0]", PeDecls("class {\n}")
}

test "020 slice 16: a `struct` declaration with no name underlines the `struct` keyword" {
    assert PeCensus("struct {\n}") == "NL102@1:1+6;", PeCensus("struct {\n}")
    assert PeRow("struct {\n}", 0) == "NL102@1:1+6|Expected struct name. Got '{'|struct {|I was expecting an identifier here, but I found '{' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("struct {\n}", 0)
    assert PeDecls("struct {\n}") == "StructDeclaration[<error>/m0]", PeDecls("struct {\n}")
}

test "020 slice 16: a `record` declaration with no name underlines the `record` keyword" {
    assert PeCensus("record {\n}") == "NL102@1:1+6;", PeCensus("record {\n}")
    assert PeRow("record {\n}", 0) == "NL102@1:1+6|Expected record name. Got '{'|record {|I was expecting an identifier here, but I found '{' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("record {\n}", 0)
    assert PeDecls("record {\n}") == "RecordDeclaration[]", PeDecls("record {\n}")
}

test "020 slice 16: a `interface` declaration with no name underlines the `interface` keyword" {
    assert PeCensus("interface {\n}") == "NL102@1:1+9;", PeCensus("interface {\n}")
    assert PeRow("interface {\n}", 0) == "NL102@1:1+9|Expected interface name. Got '{'|interface {|I was expecting an identifier here, but I found '{' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("interface {\n}", 0)
    assert PeDecls("interface {\n}") == "InterfaceDeclaration[]", PeDecls("interface {\n}")
}

test "020 slice 16: a `union` declaration with no name underlines the `union` keyword" {
    assert PeCensus("union {\n}") == "NL102@1:1+5;", PeCensus("union {\n}")
    assert PeRow("union {\n}", 0) == "NL102@1:1+5|Expected union name. Got '{'|union {|I was expecting an identifier here, but I found '{' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("union {\n}", 0)
    assert PeDecls("union {\n}") == "UnionDeclaration[]", PeDecls("union {\n}")
}

test "020 slice 16: a `enum` declaration with no name underlines the `enum` keyword" {
    assert PeCensus("enum {\n}") == "NL102@1:1+4;", PeCensus("enum {\n}")
    assert PeRow("enum {\n}", 0) == "NL102@1:1+4|Expected enum name. Got '{'|enum {|I was expecting an identifier here, but I found '{' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("enum {\n}", 0)
    assert PeDecls("enum {\n}") == "EnumDeclaration[<error>]", PeDecls("enum {\n}")
}

test "020 slice 16: a `type` declaration with no name underlines the `type` keyword" {
    assert PeCensus("type = int") == "NL102@1:1+4;", PeCensus("type = int")
    assert PeRow("type = int", 0) == "NL102@1:1+4|Expected type alias name. Got '='|type = int|I was expecting an identifier here, but I found '=' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("type = int", 0)
    assert PeDecls("type = int") == "TypeAliasDeclaration[]", PeDecls("type = int")
}

// ══ MALFORMED PARAMETER, TYPE-PARAMETER AND FIELD LISTS ══════════════════════════════════════
//
// Successors to nine deleted cases. Every one of them asserted line/column/length plus ONE
// `Message.Contains(...)` fragment. Three of the nine turn out to carry a DIFFERENT human
// explanation from the others — the trailing-comma case says "Parameter lists need another
// parameter after a comma", not the generic identifier sentence — so a builder that answered the
// generic sentence everywhere would have passed all nine.

// Successor to Parser_MissingParameterName_PointsAtTypeToken.
test "020 slice 16: a parameter list opening with `:` underlines the TYPE token, not the colon" {
    assert PeCensus("func main(: string) {\n}") == "NL102@1:13+6;", PeCensus("func main(: string) {\n}")
    assert PeRow("func main(: string) {\n}", 0) == "NL102@1:13+6|Expected parameter name. Got ':'|func main(: string) {|I was expecting an identifier here, but I found ':' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func main(: string) {\n}", 0)
    assert PeDecls("func main(: string) {\n}") == "FunctionDeclaration[main/s0]", PeDecls("func main(: string) {\n}")
}

// Successor to Parser_MissingParameterType_PointsAtParameterName. The explanation names the
// parameter ('Parameter 'name' needs a type after ':'), which the deleted file's
// `Message.Contains("Expected type name")` could not see.
test "020 slice 16: a parameter with a colon and no type underlines the parameter NAME" {
    assert PeCensus("func main(name:) {\n}") == "NL102@1:11+4;", PeCensus("func main(name:) {\n}")
    assert PeRow("func main(name:) {\n}", 0) == "NL102@1:11+4|Expected type name. Got ')'|func main(name:) {|Parameter 'name' needs a type after ':'.|Write this parameter as `name: Type`.|{Add a parameter type after ':'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func main(name:) {\n}", 0)
}

// Successor to Parser_TrailingParameterComma_PointsAtPreviousParameter. The 13-character span
// covers `name: string,` — comma included — and the explanation is the comma-specific one.
test "020 slice 16: a trailing parameter comma underlines the whole preceding parameter AND says so" {
    assert PeCensus("func main(name: string, ) {\n}") == "NL102@1:11+13;", PeCensus("func main(name: string, ) {\n}")
    assert PeRow("func main(name: string, ) {\n}", 0) == "NL102@1:11+13|Expected parameter name. Got ')'|func main(name: string, ) {|Parameter lists need another parameter after a comma.|Add the missing parameter after the comma, or remove the trailing comma.|{Add a parameter after the comma}{Remove the trailing comma}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func main(name: string, ) {\n}", 0)
}

// Successor to the first `[InlineData]` row of Parser_MissingTypeParameterName_PointsAtGenericParameterList.
test "020 slice 16: a trailing comma in a generic parameter list underlines `<T,>`" {
    assert PeCensus("func main<T,>() {\n}") == "NL102@1:10+4;", PeCensus("func main<T,>() {\n}")
    assert PeRow("func main<T,>() {\n}", 0) == "NL102@1:10+4|Expected type parameter name. Got '>'|func main<T,>() {|Generic parameter lists need a type parameter name after each comma.|Write generic parameters as `<T>` or `<T, U>`.|{Add a type parameter name}{Remove the trailing comma if the list is complete}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func main<T,>() {\n}", 0)
}

// Successor to the second `[InlineData]` row. Same message and explanation as the trailing-comma
// row, a two-character span, and `Box` still materializes with zero members.
test "020 slice 16: an empty generic parameter list underlines `<>` and the class survives" {
    assert PeCensus("class Box<> {\n}") == "NL102@1:10+2;", PeCensus("class Box<> {\n}")
    assert PeRow("class Box<> {\n}", 0) == "NL102@1:10+2|Expected type parameter name. Got '>'|class Box<> {|Generic parameter lists need a type parameter name after each comma.|Write generic parameters as `<T>` or `<T, U>`.|{Add a type parameter name}{Remove the trailing comma if the list is complete}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class Box<> {\n}", 0)
    assert PeDecls("class Box<> {\n}") == "ClassDeclaration[Box/m0]", PeDecls("class Box<> {\n}")
}

// Successor to Parser_MissingFieldType_PointsAtFieldName. The explanation is field-specific
// ('Field 'Name' needs a type after ':'), and the field still materializes as a member.
test "020 slice 16: a field with a colon and no type underlines the field NAME" {
    assert PeCensus("class User {\n    Name:\n}") == "NL102@2:5+4;", PeCensus("class User {\n    Name:\n}")
    assert PeRow("class User {\n    Name:\n}", 0) == "NL102@2:5+4|Expected type name. Got '}'|    Name:|Field 'Name' needs a type after ':'.|Write this field as `Name: Type`.|{Add a field type after ':'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class User {\n    Name:\n}", 0)
    assert PeDecls("class User {\n    Name:\n}") == "ClassDeclaration[User/m1]", PeDecls("class User {\n    Name:\n}")
}

// Successor to Parser_MissingGenericTypeArgument_PointsAtGenericType. A six-character span over
// `List<>` and a generic-specific explanation that names `List`.
test "020 slice 16: an empty generic argument list underlines the whole `List<>`" {
    assert PeCensus("class User {\n    Items: List<>\n}") == "NL102@2:12+6;", PeCensus("class User {\n    Items: List<>\n}")
    assert PeRow("class User {\n    Items: List<>\n}", 0) == "NL102@2:12+6|Expected type name. Got '>'|    Items: List<>|Generic type 'List' needs a type argument between '<' and '>'.|Write this type as `List<T>` or remove the generic argument list.|{Add a type argument}{Remove the empty generic argument list}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class User {\n    Items: List<>\n}", 0)
    assert PeDecls("class User {\n    Items: List<>\n}") == "ClassDeclaration[User/m1]", PeDecls("class User {\n    Items: List<>\n}")
}

// Successor to Parser_MissingFieldTypeBeforeNextField_PointsAtFieldNameAndContinues, which
// asserted two `Assert.Contains` predicates over line/column/length. The census states that there
// are EXACTLY two diagnostics in exactly that order, and the member census states that both
// `Name` and `Items` survived with their written names — which is the actual claim behind
// 'AndContinues' and which no `Contains` pair can make.
// CONTRAST, and it is sharp: the class-member case with a malformed INITIALIZER (below) loses the
// field after it. A missing TYPE does not.
test "020 slice 16: two malformed fields in a row report TWICE and both members survive" {
    assert PeCensus("class User {\n    Name:\n    Items: List<>\n}") == "NL102@2:5+4;NL102@3:12+6;", PeCensus("class User {\n    Name:\n    Items: List<>\n}")
    assert PeRow("class User {\n    Name:\n    Items: List<>\n}", 0) == "NL102@2:5+4|Expected type name. Got 'Items'|    Name:|Field 'Name' needs a type after ':'.|Write this field as `Name: Type`.|{Add a field type after ':'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class User {\n    Name:\n    Items: List<>\n}", 0)
    assert PeRow("class User {\n    Name:\n    Items: List<>\n}", 1) == "NL102@3:12+6|Expected type name. Got '>'|    Items: List<>|Generic type 'List' needs a type argument between '<' and '>'.|Write this type as `List<T>` or remove the generic argument list.|{Add a type argument}{Remove the empty generic argument list}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class User {\n    Name:\n    Items: List<>\n}", 1)
    assert PeMembers("class User {\n    Name:\n    Items: List<>\n}") == "User{FieldDeclaration(Name),FieldDeclaration(Items),}", PeMembers("class User {\n    Name:\n    Items: List<>\n}")
}

// Successor to Parser_MissingObjectInitializerColon_PointsAtPropertyName. The message NAMES the
// member ('after object initializer member 'Name''), and both declarations of the two-declaration
// file survive.
test "020 slice 16: an object initializer member with no colon underlines the property name" {
    assert PeCensus("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}") == "NL102@5:24+4;", PeCensus("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}")
    assert PeRow("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}", 0) == "NL102@5:24+4|Expected ':' after object initializer member 'Name'|    user := new User { Name }|Object initializer member 'Name' needs ':' before its value.|Write 'Name: value'.|{Add ':' after 'Name'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}", 0)
    assert PeDecls("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}") == "ClassDeclaration[User/m1]FunctionDeclaration[main/s1]", PeDecls("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}")
    assert PeStmts("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}") == "VariableDeclarationStatement(user);", PeStmts("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}")
}

// Successor to Parser_NewMissingType_PointsAtNewKeyword. Two suggestions, and the second one
// ('Use `new()` for target-typed construction') is the language feature a developer would not
// guess — it was unstated.
test "020 slice 16: a bare `new` underlines the keyword and offers the target-typed route" {
    assert PeCensus("func main() {\n    value := new\n}") == "NL102@2:14+3;", PeCensus("func main() {\n    value := new\n}")
    assert PeRow("func main() {\n    value := new\n}", 0) == "NL102@2:14+3|Expected type name. Got '}'|    value := new|The `new` expression needs a type name, `()`, or an initializer after it.|Write `new TypeName(...)`, `new()`, or `new { Name: value }`.|{Add a type name after `new`}{Use `new()` for target-typed construction}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func main() {\n    value := new\n}", 0)
    assert PeStmts("func main() {\n    value := new\n}") == "VariableDeclarationStatement(value);", PeStmts("func main() {\n    value := new\n}")
}

// ══ COLON-POSITION MISTAKES: THE C#-SHAPED SOURCES A NEWCOMER WRITES ═════════════════════════
//
// Successors to the deleted file's `#region Error Code Verification`. These four are the sources
// a developer arriving from C#/Go actually types, and each one gets a hint that shows the N# form.
// The deleted file asserted `Contains` on the CONTEXTUAL HINT for three of them; the whole rows
// state the hint, the explanation and the suggestion list.

// Successor to Parser_MissingParameterColon_PointsAtParameterName.
test "020 slice 16: `func greet(name string)` points at the parameter name and shows `name: Type`" {
    assert !PeParse("func greet(name string): string { return name }").Success
    assert PeCensus("func greet(name string): string { return name }") == "NL102@1:12+4;", PeCensus("func greet(name string): string { return name }")
    assert PeRow("func greet(name string): string { return name }", 0) == "NL102@1:12+4|Expected ':' after parameter name. Got 'string'|func greet(name string): string { return name }|Parameter 'name' needs a ':' before its type.|Write this parameter as `name: Type`.|{Add ':' after 'name'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func greet(name string): string { return name }", 0)
    assert PeDecls("func greet(name string): string { return name }") == "FunctionDeclaration[greet/s1]", PeDecls("func greet(name string): string { return name }")
}

// Successor to Parser_MissingFieldColon_PointsAtFieldName. Two suggestions: add ':', or use ':='
// for an inferred initializer. The deleted file asserted one hint fragment and the snippet.
test "020 slice 16: `Name string` in a class body offers BOTH the `:` and the `:=` route" {
    assert !PeParse("class User {\n    Name string\n}").Success
    assert PeCensus("class User {\n    Name string\n}") == "NL102@2:5+4;", PeCensus("class User {\n    Name string\n}")
    assert PeRow("class User {\n    Name string\n}", 0) == "NL102@2:5+4|Expected ':' or ':=' after field name. Got 'string'|    Name string|Field 'Name' needs a ':' before its type, or ':=' before an inferred initializer.|Write this field as `Name: Type` or `Name := value`.|{Add ':' after 'Name'}{Use ':=' after 'Name' if the type should be inferred}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class User {\n    Name string\n}", 0)
}

// Successor to Parser_MissingFunctionReturnColon_PointsAtFunctionName. The span is the function
// name, six characters — not the return type the developer wrote in the wrong place.
test "020 slice 16: `func answer() int` points at the function NAME and shows the return-type form" {
    assert !PeParse("func answer() int { return 1 }").Success
    assert PeCensus("func answer() int { return 1 }") == "NL102@1:6+6;", PeCensus("func answer() int { return 1 }")
    assert PeRow("func answer() int { return 1 }", 0) == "NL102@1:6+6|Expected ':' before return type. Got 'int'|func answer() int { return 1 }|Function 'answer' needs a ':' before its return type.|Write the return type as `func name(...): Type { ... }`.|{Add ':' before 'int'}{Remove the return type if this function does not return a value}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func answer() int { return 1 }", 0)
    assert PeDecls("func answer() int { return 1 }") == "FunctionDeclaration[answer/s1]", PeDecls("func answer() int { return 1 }")
}

// Successor to Parser_DefaultDiagnosticSpan_CoversVisibleToken, which asserted the code, the
// message fragment, the span and the snippet. What it could not see is that this diagnostic
// carries NO `HumanExplanation`, NO `ContextualHint` and NO suggestions — it is built through the
// DEFAULT span resolver rather than through a purpose-built parser diagnostic. Because
// `HumanExplanation` alone selects the renderer, this is the one parser diagnostic in the whole
// corpus a developer sees in RUST style, not Elm style. That is a real user-visible inconsistency
// and it is now stated rather than latent.
test "020 slice 16: the enum-backing-type refusal is the ONLY corpus row with no human explanation" {
    assert !PeParse("enum Status: decimal { Open }").Success
    assert PeCensus("enum Status: decimal { Open }") == "NL101@1:14+7;", PeCensus("enum Status: decimal { Open }")
    assert PeRow("enum Status: decimal { Open }", 0) == "NL101@1:14+7|Unsupported enum backing type 'decimal'. Only 'int' and 'string' are supported.|enum Status: decimal { Open }|<null>|<null>|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("enum Status: decimal { Open }", 0)
    assert PeDecls("enum Status: decimal { Open }") == "EnumDeclaration[Status]", PeDecls("enum Status: decimal { Open }")
    assert PeParse("enum Status: decimal { Open }").Errors[0].HumanExplanation == null
    assert PeParse("enum Status: decimal { Open }").Errors[0].Suggestions == null
}

// Successor to Parser_ReturnsCorrectErrorCode_UnexpectedToken, whose whole claim was
// `Assert.All(result.Errors, e => Assert.True(e.Code != default(ErrorCode)))` — i.e. that the code
// is nonzero. The real answer is one NL102 naming the token, and a class that materializes with an
// `<error>`-named field. Both the nonzero-code claim and the severity are stated.
test "020 slice 16: a stray `]` in a class body is reported once and leaves an `<error>` field" {
    assert !PeParse("class Test { ] }").Success
    assert PeCensus("class Test { ] }") == "NL102@1:14+1;", PeCensus("class Test { ] }")
    assert PeRow("class Test { ] }", 0) == "NL102@1:14+1|Expected field name. Got ']'|class Test { ] }|I was expecting an identifier here, but I found ']' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("class Test { ] }", 0)
    assert PeSeverities("class Test { ] }") == "error;", PeSeverities("class Test { ] }")
    assert (int)PeParse("class Test { ] }").Errors[0].Code != 0
    assert PeMembers("class Test { ] }") == "Test{FieldDeclaration(<error>),}", PeMembers("class Test { ] }")
}

// ══ MULTI-ERROR REPORTING AND CASCADING SUPPRESSION ══════════════════════════════════════════
//
// Successors to `#region Multi-Line Errors`, `#region Complex Multi-Error Scenarios` and the
// count-bound cases. Every one of these asserted `Errors.Count >= N` plus a handful of
// `Contains(e => e.Line == L)` — a lower bound that a parser reporting fifty cascaded diagnostics
// passes. Each census states the EXACT list, which is simultaneously the lower bound, the upper
// bound, the order and the suppression claim.

// Successor to Parser_ReportsMultipleErrors_DifferentLines (`Count >= 3` + three line predicates).
test "020 slice 16: three dangling dots in three functions report exactly three diagnostics" {
    assert !PeParse("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}").Success
    assert PeCensus("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}") == "NL102@3:5+1;NL102@7:5+1;NL102@11:5+1;", PeCensus("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}")
    assert PeRow("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}", 0) == "NL102@3:5+1|Expected member name. Got '}'|    x.|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}", 0)
    assert PeRow("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}", 2) == "NL102@11:5+1|Expected member name. Got '}'|    z.|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}", 2)
    assert PeDecls("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}") == "FunctionDeclaration[test1/s1]FunctionDeclaration[test2/s1]FunctionDeclaration[test3/s1]", PeDecls("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    y.\n}\n\nfunc test3() {\n    z.\n}")
}

// Successor to Parser_ReportsMultipleErrors_SameFunction, which asserted `Count >= 3`, three line
// predicates and `Assert.All(… ExpectedToken)`. The three messages DIFFER — 'Got 'y'', 'Got 'z'',
// 'Got '}'' — because each dot reports what actually follows it. Stating the messages is what
// shows the parser is resynchronising per statement rather than repeating one canned diagnostic.
test "020 slice 16: three dangling dots in ONE function report three, each naming the NEXT token" {
    assert PeCensus("\nfunc test() {\n    x.\n    y.\n    z.\n}") == "NL102@3:5+1;NL102@4:5+1;NL102@5:5+1;", PeCensus("\nfunc test() {\n    x.\n    y.\n    z.\n}")
    assert PeRow("\nfunc test() {\n    x.\n    y.\n    z.\n}", 0) == "NL102@3:5+1|Expected member name. Got 'y'|    x.|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test() {\n    x.\n    y.\n    z.\n}", 0)
    assert PeRow("\nfunc test() {\n    x.\n    y.\n    z.\n}", 1) == "NL102@4:5+1|Expected member name. Got 'z'|    y.|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test() {\n    x.\n    y.\n    z.\n}", 1)
    assert PeRow("\nfunc test() {\n    x.\n    y.\n    z.\n}", 2) == "NL102@5:5+1|Expected member name. Got '}'|    z.|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test() {\n    x.\n    y.\n    z.\n}", 2)
    assert PeSeverities("\nfunc test() {\n    x.\n    y.\n    z.\n}") == "error;error;error;", PeSeverities("\nfunc test() {\n    x.\n    y.\n    z.\n}")
    assert PeDecls("\nfunc test() {\n    x.\n    y.\n    z.\n}") == "FunctionDeclaration[test/s3]", PeDecls("\nfunc test() {\n    x.\n    y.\n    z.\n}")
}

// Successor to Parser_ReportsMultipleErrors_FromSingleMalformedSource, which asserted `Count >= 2`
// and `>= 2` distinct lines. The real answer is NL103 (invalid pattern, with four pattern-form
// suggestions) then NL102 (expected property name) — two different diagnostic FAMILIES from one
// source, which is the actual point of the case.
test "020 slice 16: a bad match arm and a bad initializer member report two DIFFERENT codes" {
    assert !PeParse("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}").Success
    assert PeCensus("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}") == "NL103@4:9+1;NL102@9:9+1;", PeCensus("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}")
    assert PeRow("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}", 0) == "NL103@4:9+1|Invalid pattern. Got '@'|        @@ => 1,|I couldn't recognize this as a valid pattern for matching.|Patterns can be literals, identifiers, types, or destructuring patterns.|{Literal pattern: case 5 => ...}{Identifier pattern: case x => ...}{Type pattern: case int x => ...}{Object pattern: case { Name: \"John\" } => ...}|https://schneidenbach.github.io/nsharplang/docs/errors/NL103", PeRow("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}", 0)
    assert PeRow("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}", 1) == "NL102@9:9+1|Expected property name. Got '@'|        @@|I was expecting an identifier here, but I found '@' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}", 1)
    assert PeDecls("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}") == "FunctionDeclaration[test/s2]", PeDecls("\nfunc test() {\n    match value {\n        @@ => 1,\n        other => 2\n    }\n\n    new Person {\n        @@\n    }\n}")
}

// Successor to Parser_HandlesComplexMultiError_AcrossFile, which asserted `Count >= 3`, `>= 3`
// distinct lines, and for every error `Line > 0`, `Column > 0`, non-empty message. The census
// states all four spans; the rows state the two extremes. Note the second error is NL102
// 'Expected field name' — a `prop := 5 @@ 3` inside a CLASS body is a field, not a statement.
test "020 slice 16: four errors across a 24-line file land on four distinct lines with full metadata" {
    assert !PeParse("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}").Success
    assert PeCensus("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}") == "NL102@5:5+1;NL102@11:15+1;NL107@17:13+9;NL102@23:5+1;", PeCensus("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}")
    assert PeRow("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}", 1) == "NL102@11:15+1|Expected field name. Got '@'|    prop := 5 @@ 3  // Error on line 11 (invalid operator)|I was expecting an identifier here, but I found '@' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}", 1)
    assert PeRow("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}", 2) == "NL107@17:13+9|Missing closing ')'|    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)|I reached the next line while looking for the closing ')' that matches an earlier '('.|Every opening parenthesis '(' needs a matching closing parenthesis ')'.|{Add ')' before starting the next line}{Check the matching '(' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL107", PeRow("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}", 2)
    assert PeSeverities("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}") == "error;error;error;error;", PeSeverities("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}")
    assert PeDecls("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}") == "FunctionDeclaration[test1/s1]ClassDeclaration[Test/m2]FunctionDeclaration[test2/s1]FunctionDeclaration[test3/s1]", PeDecls("\n// Line 2\nfunc test1() {\n    // Line 4\n    x.   // Error on line 5\n}\n\n// Line 8\nclass Test {\n    // Line 10\n    prop := 5 @@ 3  // Error on line 11 (invalid operator)\n}\n\n// Line 14\nfunc test2() {\n    // Line 16\n    Console.WriteLine(\"test\"  // Error on line 17 (missing paren)\n}\n\n// Line 20\nfunc test3() {\n    // Line 22\n    y.   // Error on line 23\n}")
}

// Successor to Parser_ReportsError_InvalidTokenInExpression, whose only claim was
// `Assert.Contains(result.Errors, e => e.Line == 3)`. `@@` is two tokens and reports twice, at
// columns 11 and 12 — the per-character granularity of the unexpected-token arm, unstated anywhere.
test "020 slice 16: two `@` tokens in an expression report twice, one per character" {
    assert !PeParse("\nfunc test() {\n    x = 5 @@ 3\n}").Success
    assert PeCensus("\nfunc test() {\n    x = 5 @@ 3\n}") == "NL101@3:11+1;NL101@3:12+1;", PeCensus("\nfunc test() {\n    x = 5 @@ 3\n}")
    assert PeRow("\nfunc test() {\n    x = 5 @@ 3\n}", 0) == "NL101@3:11+1|Unexpected token '@' in expression|    x = 5 @@ 3|I was parsing an expression and found '@', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("\nfunc test() {\n    x = 5 @@ 3\n}", 0)
    assert PeDecls("\nfunc test() {\n    x = 5 @@ 3\n}") == "FunctionDeclaration[test/s4]", PeDecls("\nfunc test() {\n    x = 5 @@ 3\n}")
    assert PeStmts("\nfunc test() {\n    x = 5 @@ 3\n}") == "ExpressionStatement;ExpressionStatement;ExpressionStatement;ExpressionStatement;", PeStmts("\nfunc test() {\n    x = 5 @@ 3\n}")
}

// Successor to Parser_CascadingErrorsSuppressed, which asserted `Errors.Count <= 5`. Two is the
// answer, and stating it turns a loose bound into a contract.
// AND THE RECOVERY IS NOT WHAT THE CASE ASSUMED: with the first brace unclosed, `func other()`
// becomes a LOCAL FUNCTION inside `test` — the statement census says
// `VariableDeclarationStatement(x);LocalFunctionStatement;` and the declaration census says there
// is only ONE top-level function. Nothing had written that down.
test "020 slice 16: a dangling `+` before a new function is suppressed to exactly two diagnostics" {
    assert PeCensus("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}") == "NL102@3:13+3;NL106@2:6+4;", PeCensus("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}")
    assert PeRow("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}", 0) == "NL102@3:13+3|Expected expression after '+'|    let x = 5 +|The '+' operator needs an expression on its right side.|Finish the expression after the operator, or remove the operator if the expression is already complete.|{Add an expression after '+'}{Remove the trailing '+'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}", 0)
    assert PeRow("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}", 1) == "NL106@2:6+4|Missing closing '}'|func test() {|The block that started on line 2 is missing its closing brace. I reached the end of the file without finding it.|Add a '}' to close this block.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL106", PeRow("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}", 1)
    assert PeDecls("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}") == "FunctionDeclaration[test/s2]", PeDecls("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}")
    assert PeStmts("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}") == "VariableDeclarationStatement(x);LocalFunctionStatement;", PeStmts("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}")
}

// NOT IN THE DELETED FILE, AND NOT ANYWHERE ELSE. The cascading source's two diagnostics come back
// from `ParseFileAst` as NL102@3 then NL106@2, and from `ParseFilePreamble` as NL106@2 then
// NL102@3. Both are correct and the difference is by design (the AST entry preserves Parser.cs's
// `_errors` order so a routed consumer's reads are unchanged; the preamble entry sorts for the
// CLI-shaped oracle). Every consumer that prints `result.Errors` in order — the CLI, MSBuild, the
// language server — sees the unsorted one. This contract is why this file exists separately from
// `ColumnarParserRecovery.tests.nl`, all of whose contracts go through the sorted entry point.
test "020 slice 16: `ParseFileAst` returns RECORDING order, which is not position order" {
    assert PeCensus("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}") == "NL102@3:13+3;NL106@2:6+4;", PeCensus("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}")
    assert PeSortedCensus("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}") == "NL106@2:6+4;NL102@3:13+3;", PeSortedCensus("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}")
    assert PeCensus("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}") != PeSortedCensus("\nfunc test() {\n    let x = 5 +\n\nfunc other() {\n    let y = 10\n}")
    assert PeCensus("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}") == "NL102@3:5+1;NL101@7:18+1;NL101@7:19+1;NL107@11:13+9;", PeCensus("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}")
    assert PeSortedCensus("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}") == "NL102@3:5+1;NL101@7:18+1;NL101@7:19+1;NL107@11:13+9;", PeSortedCensus("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}")
}

// Successor to Parser_MultipleStatementsWithErrors_InSameBlock_AllReported (`Count >= 3`, `>= 3`
// distinct lines). Six is the answer — two per `@@` — and the statement census shows each bad
// `let` leaves BOTH its variable declaration and a trailing expression statement behind.
test "020 slice 16: three bad initializers in one block report six diagnostics, two per `@@`" {
    assert !PeParse("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}").Success
    assert PeCensus("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}") == "NL101@3:18+1;NL101@3:19+1;NL101@4:18+1;NL101@4:19+1;NL101@5:18+1;NL101@5:19+1;", PeCensus("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}")
    assert PeRow("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}", 0) == "NL101@3:18+1|Unexpected token '@' in expression|    let a: int = @@|I was parsing an expression and found '@', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}", 0)
    assert PeSeverities("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}") == "error;error;error;error;error;error;", PeSeverities("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}")
    assert PeDecls("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}") == "FunctionDeclaration[test/s6]", PeDecls("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}")
    assert PeStmts("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}") == "VariableDeclarationStatement(a);ExpressionStatement;VariableDeclarationStatement(b);ExpressionStatement;VariableDeclarationStatement(c);ExpressionStatement;", PeStmts("\nfunc test() {\n    let a: int = @@\n    let b: int = @@\n    let c: int = @@\n}")
}

// Successor to Parser_MixedErrorTypes_AllReported (`Count >= 3`, `>= 3` distinct lines). Four is
// the answer, across three codes — NL102, NL101 twice, NL107 — and all three functions survive.
test "020 slice 16: three different error KINDS in three functions report four diagnostics" {
    assert !PeParse("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}").Success
    assert PeCensus("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}") == "NL102@3:5+1;NL101@7:18+1;NL101@7:19+1;NL107@11:13+9;", PeCensus("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}")
    assert PeRow("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}", 3) == "NL107@11:13+9|Missing closing ')'|    Console.WriteLine(\"hi\"|I reached the next line while looking for the closing ')' that matches an earlier '('.|Every opening parenthesis '(' needs a matching closing parenthesis ')'.|{Add ')' before starting the next line}{Check the matching '(' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL107", PeRow("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}", 3)
    assert PeDecls("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}") == "FunctionDeclaration[test1/s1]FunctionDeclaration[test2/s2]FunctionDeclaration[test3/s1]", PeDecls("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}")
    assert PeStmts("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}") == "ExpressionStatement;VariableDeclarationStatement(a);ExpressionStatement;ExpressionStatement;", PeStmts("\nfunc test1() {\n    x.\n}\n\nfunc test2() {\n    let a: int = @@\n}\n\nfunc test3() {\n    Console.WriteLine(\"hi\"\n}")
}

// ══ EDGE CASES: EMPTY, GARBAGE, AND END OF FILE ══════════════════════════════════════════════
//
// Successors to `#region Edge Cases` and the two "no exception" cases. Every one of these
// asserted only `NotNull(result)` or `NotEmpty(result.Errors)`, and two of them turn out to have
// genuinely surprising answers.

// Successor to Parser_HandlesError_AtStartOfFile, which asserted `NotEmpty(Errors)` and
// `error.Line >= 1`. THE MEASURED ANSWER IS THAT TOP-LEVEL RECOVERY MANUFACTURES CLASSES: three
// stray tokens produce three `ClassDeclaration[<error>/m0]` nodes. Everything downstream that
// walks `Declarations` sees them, which is exactly why the `Name != "<error>"` filter appears in
// the deleted file's own recovery cases. Nothing stated where those nodes come from.
test "020 slice 16: stray tokens at the start of a file synthesize `<error>`-named CLASS declarations" {
    assert !PeParse("@@ invalid").Success
    assert PeCensus("@@ invalid") == "NL101@1:1+1;NL101@1:2+1;NL101@1:4+7;", PeCensus("@@ invalid")
    assert PeRow("@@ invalid", 2) == "NL101@1:4+7|Unexpected token 'invalid'|@@ invalid|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found 'invalid' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("@@ invalid", 2)
    assert PeDecls("@@ invalid") == "ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]", PeDecls("@@ invalid")
}

// Successor to Parser_EmptyMalformedFile_NoException, which asserted `NotEmpty(Errors)`. Four
// garbage pairs do NOT produce four diagnostics: `##` is consumed as a PreprocessorDeclaration and
// `!!`/`%%` are consumed with it, so only the two `@` characters report. The declaration census
// names the preprocessor node. This is the kind of fact a `NotEmpty` assertion is structurally
// incapable of noticing, and it is the difference between 'the parser survived' and 'the parser
// did what we think it did'.
test "020 slice 16: `@@ ## !! %%` reports TWO diagnostics, because `##` lexes as a preprocessor directive" {
    assert !PeParse("@@ ## !! %%").Success
    assert PeCensus("@@ ## !! %%") == "NL101@1:1+1;NL101@1:2+1;", PeCensus("@@ ## !! %%")
    assert PeRow("@@ ## !! %%", 0) == "NL101@1:1+1|Unexpected token '@'|@@ ## !! %%|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '@' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("@@ ## !! %%", 0)
    assert PeDecls("@@ ## !! %%") == "ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]PreprocessorDeclaration[]", PeDecls("@@ ## !! %%")
}

// Successor to Parser_HandlesError_AtEndOfFile (`NotEmpty(Errors)`). One NL106 anchored on the
// function NAME, with the end-of-file explanation rather than the next-declaration one.
test "020 slice 16: an unclosed function at end of file reports the brace error at the function name" {
    assert !PeParse("\nfunc test() {\n    x = 5\n").Success
    assert PeCensus("\nfunc test() {\n    x = 5\n") == "NL106@2:6+4;", PeCensus("\nfunc test() {\n    x = 5\n")
    assert PeRow("\nfunc test() {\n    x = 5\n", 0) == "NL106@2:6+4|Missing closing '}'|func test() {|The block that started on line 2 is missing its closing brace. I reached the end of the file without finding it.|Add a '}' to close this block.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL106", PeRow("\nfunc test() {\n    x = 5\n", 0)
    assert PeDecls("\nfunc test() {\n    x = 5\n") == "FunctionDeclaration[test/s1]", PeDecls("\nfunc test() {\n    x = 5\n")
}

// Successor to Parser_HandlesEmptyInput, which asserted `Assert.NotNull(result)` and explicitly
// declined to say which of the two possible answers is correct ('OR report an appropriate error if
// required'). The answer is stated here: success, zero diagnostics, zero declarations.
test "020 slice 16: empty input parses successfully into an empty compilation unit" {
    assert PeParse("").Success
    assert PeCensus("") == "", PeCensus("")
    assert PeDecls("") == "", PeDecls("")
    assert PeStmts("") == "", PeStmts("")
}

// Successor to Parser_NamedTuple_NonIdentifierBeforeColon_DoesNotCrash, which guarded a real
// InvalidCastException (`(1+2: value)` casting a BinaryExpression to an IdentifierExpression) and
// asserted only `NotNull(CompilationUnit)`. The stronger claim is that the parse is CLEAN — zero
// diagnostics — which is what distinguishes 'did not crash' from 'silently reported something'.
test "020 slice 16: a parenthesized binary expression is not a named tuple and does not crash" {
    assert PeParse("\nfunc test() {\n    x := (1+2)\n}").Success
    assert PeCensus("\nfunc test() {\n    x := (1+2)\n}") == "", PeCensus("\nfunc test() {\n    x := (1+2)\n}")
    assert PeDecls("\nfunc test() {\n    x := (1+2)\n}") == "FunctionDeclaration[test/s1]", PeDecls("\nfunc test() {\n    x := (1+2)\n}")
    assert PeStmts("\nfunc test() {\n    x := (1+2)\n}") == "VariableDeclarationStatement(x);", PeStmts("\nfunc test() {\n    x := (1+2)\n}")
}

// Successor to Parser_InterpolatedString_ErrorsArePropagated — and the deleted test did not test
// its own name. Its body was `Assert.NotNull(result.CompilationUnit)` and its comment said 'Should
// have at least one error from the malformed expression inside {1 +}'; it never asserted one. A
// parser that silently swallowed every diagnostic inside every interpolation hole would have
// passed. The real answer is NL102 'Expected expression after '+'' at column 19 — INSIDE the hole,
// three characters over `1 +`.
test "020 slice 16: an error inside an interpolation hole IS reported, with a span inside the hole" {
    assert !PeParse("\nfunc test() {\n    x := $\"hello {1 +}\"\n}").Success
    assert PeCensus("\nfunc test() {\n    x := $\"hello {1 +}\"\n}") == "NL102@3:19+3;", PeCensus("\nfunc test() {\n    x := $\"hello {1 +}\"\n}")
    assert PeRow("\nfunc test() {\n    x := $\"hello {1 +}\"\n}", 0) == "NL102@3:19+3|Expected expression after '+'|    x := $\"hello {1 +}\"|The '+' operator needs an expression on its right side.|Finish the expression after the operator, or remove the operator if the expression is already complete.|{Add an expression after '+'}{Remove the trailing '+'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test() {\n    x := $\"hello {1 +}\"\n}", 0)
    assert PeStmts("\nfunc test() {\n    x := $\"hello {1 +}\"\n}") == "VariableDeclarationStatement(x);", PeStmts("\nfunc test() {\n    x := $\"hello {1 +}\"\n}")
}

// ══ RECOVERY ACROSS DECLARATION BOUNDARIES ═══════════════════════════════════════════════════
//
// Successors to `#region Error Recovery Tests`. The deleted cases asked "is the good declaration
// still there?" with `OfType<T>().FirstOrDefault(x => x.Name == "…") != null`. Each census here
// states the whole recovered top level, so a recovery that kept the named declaration AND lost or
// manufactured others fails.

// Successor to Parser_ThreeErrorsInThreeFunctions_AllReported, which asserted `Count >= 3` and
// that exactly 3 non-`<error>` functions are present. The census states six diagnostics; the
// declaration census states three functions AND that none of them is an `<error>` placeholder,
// which is the same claim without needing the filter.
test "020 slice 16: three functions with bad initializers all survive, and report six diagnostics" {
    assert !PeParse("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}").Success
    assert PeCensus("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}") == "NL101@3:18+1;NL101@3:19+1;NL101@7:18+1;NL101@7:19+1;NL101@11:18+1;NL101@11:19+1;", PeCensus("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}")
    assert PeRow("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}", 0) == "NL101@3:18+1|Unexpected token '@' in expression|    let x: int = @@|I was parsing an expression and found '@', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}", 0)
    assert PeDecls("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}") == "FunctionDeclaration[test1/s2]FunctionDeclaration[test2/s2]FunctionDeclaration[test3/s2]", PeDecls("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}")
    assert PeStmts("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}") == "VariableDeclarationStatement(x);ExpressionStatement;VariableDeclarationStatement(y);ExpressionStatement;VariableDeclarationStatement(z);ExpressionStatement;", PeStmts("\nfunc test1() {\n    let x: int = @@\n}\n\nfunc test2() {\n    let y: int = @@\n}\n\nfunc test3() {\n    let z: int = @@\n}")
}

// Successor to Parser_ErrorInFirstFunction_SecondFunctionStillParsed, which asserted that
// `valid`'s body has some statements. The statement census states WHICH: the broken function keeps
// its declaration plus a stray expression statement, and `valid` keeps exactly `y`.
test "020 slice 16: an error in the first function leaves the second function's body intact" {
    assert PeCensus("\nfunc broken() {\n    let x: int = @@\n}\n\nfunc valid() {\n    let y = 42\n}") == "NL101@3:18+1;NL101@3:19+1;", PeCensus("\nfunc broken() {\n    let x: int = @@\n}\n\nfunc valid() {\n    let y = 42\n}")
    assert PeDecls("\nfunc broken() {\n    let x: int = @@\n}\n\nfunc valid() {\n    let y = 42\n}") == "FunctionDeclaration[broken/s2]FunctionDeclaration[valid/s1]", PeDecls("\nfunc broken() {\n    let x: int = @@\n}\n\nfunc valid() {\n    let y = 42\n}")
    assert PeStmts("\nfunc broken() {\n    let x: int = @@\n}\n\nfunc valid() {\n    let y = 42\n}") == "VariableDeclarationStatement(x);ExpressionStatement;VariableDeclarationStatement(y);", PeStmts("\nfunc broken() {\n    let x: int = @@\n}\n\nfunc valid() {\n    let y = 42\n}")
}

// Successor to Parser_MissingClosingBrace_NextDeclarationStillParsed. The explanation is the
// declaration-aware one — 'I found 'class' on line 5, which looks like a new declaration' — and
// its hint says 'Add a '}' before this declaration', not the end-of-file wording. The deleted file
// asserted only the CODE, so the two variants were indistinguishable.
test "020 slice 16: an unclosed brace before a class reports the NEXT-DECLARATION variant of NL106" {
    assert !PeParse("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}").Success
    assert PeCensus("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}") == "NL106@2:6+6;", PeCensus("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}")
    assert PeRow("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}", 0) == "NL106@2:6+6|Missing closing '}'|func broken() {|The block that started on line 2 appears to be missing its closing brace. I found 'class' on line 5, which looks like a new declaration.|Add a '}' before this declaration to close the previous block.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL106", PeRow("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}", 0)
    assert PeDecls("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}") == "FunctionDeclaration[broken/s1]ClassDeclaration[MyClass/m1]", PeDecls("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}")
    assert PeStmts("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}") == "VariableDeclarationStatement(x);", PeStmts("\nfunc broken() {\n    let x = 5\n\nclass MyClass {\n    name: string\n}")
}

// Successor to Parser_MissingBrace_ErrorPositionAccurate, which asserted the code and line 2. The
// sibling of the class case above: the same arm names whichever keyword it found, and `Point`
// survives with both of its fields.
test "020 slice 16: an unclosed brace before a struct names the struct in the explanation" {
    assert !PeParse("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}").Success
    assert PeCensus("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}") == "NL106@2:6+4;", PeCensus("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}")
    assert PeRow("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}", 0) == "NL106@2:6+4|Missing closing '}'|func test() {|The block that started on line 2 appears to be missing its closing brace. I found 'struct' on line 5, which looks like a new declaration.|Add a '}' before this declaration to close the previous block.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL106", PeRow("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}", 0)
    assert PeDecls("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}") == "FunctionDeclaration[test/s1]StructDeclaration[Point/m2]", PeDecls("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}")
    assert PeMembers("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}") == "Point{FieldDeclaration(x),FieldDeclaration(y),}", PeMembers("\nfunc test() {\n    let x = 5\n\nstruct Point {\n    x: int\n    y: int\n}")
}

// Successor to Parser_InvalidExpressionInsideFunction_FunctionBoundaryRecovered.
test "020 slice 16: an invalid operator inside a function does not consume the next function" {
    assert PeCensus("\nfunc broken() {\n    let x = 5 @@ 3\n}\n\nfunc valid() {\n    let y = 10\n}") == "NL101@3:15+1;NL101@3:16+1;", PeCensus("\nfunc broken() {\n    let x = 5 @@ 3\n}\n\nfunc valid() {\n    let y = 10\n}")
    assert PeDecls("\nfunc broken() {\n    let x = 5 @@ 3\n}\n\nfunc valid() {\n    let y = 10\n}") == "FunctionDeclaration[broken/s4]FunctionDeclaration[valid/s1]", PeDecls("\nfunc broken() {\n    let x = 5 @@ 3\n}\n\nfunc valid() {\n    let y = 10\n}")
    assert PeStmts("\nfunc broken() {\n    let x = 5 @@ 3\n}\n\nfunc valid() {\n    let y = 10\n}") == "VariableDeclarationStatement(x);ExpressionStatement;ExpressionStatement;ExpressionStatement;VariableDeclarationStatement(y);", PeStmts("\nfunc broken() {\n    let x = 5 @@ 3\n}\n\nfunc valid() {\n    let y = 10\n}")
}

// Successor to Parser_MissingFunctionClosingBrace_PointsAtFunctionName.
test "020 slice 16: an unclosed function brace at end of file anchors NL106 on the function name" {
    assert PeCensus("func main() {\n    print \"hi\"") == "NL106@1:6+4;", PeCensus("func main() {\n    print \"hi\"")
    assert PeRow("func main() {\n    print \"hi\"", 0) == "NL106@1:6+4|Missing closing '}'|func main() {|The block that started on line 1 is missing its closing brace. I reached the end of the file without finding it.|Add a '}' to close this block.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL106", PeRow("func main() {\n    print \"hi\"", 0)
    assert PeDecls("func main() {\n    print \"hi\"") == "FunctionDeclaration[main/s1]", PeDecls("func main() {\n    print \"hi\"")
    assert PeStmts("func main() {\n    print \"hi\"") == "PrintStatement;", PeStmts("func main() {\n    print \"hi\"")
}

// Successor to Parser_MissingTypeClosingBrace_PointsAtTypeName. A third NL106 variant: 'The type
// body that started on line 1' with the hint 'Add a '}' to close this type declaration'. Three
// variants of one code, all three now separated by their whole text.
test "020 slice 16: an unclosed TYPE brace says 'type body', not 'block'" {
    assert PeCensus("class User {\n    Name: string") == "NL106@1:7+4;", PeCensus("class User {\n    Name: string")
    assert PeRow("class User {\n    Name: string", 0) == "NL106@1:7+4|Missing closing '}'|class User {|The type body that started on line 1 is missing its closing brace. I reached the end of the file without finding it.|Add a '}' to close this type declaration.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL106", PeRow("class User {\n    Name: string", 0)
    assert PeDecls("class User {\n    Name: string") == "ClassDeclaration[User/m1]", PeDecls("class User {\n    Name: string")
    assert PeMembers("class User {\n    Name: string") == "User{FieldDeclaration(Name),}", PeMembers("class User {\n    Name: string")
}

// Successor to Parser_MultipleDeclarationTypes_AllRecovered, which asserted three `Contains`
// predicates over the declaration list. The census states the whole list IN ORDER, including the
// broken function that precedes them.
test "020 slice 16: an enum, a class and a function after a broken function all recover" {
    assert PeCensus("\nfunc broken() {\n    let x = @@\n}\n\nenum Color {\n    Red,\n    Green,\n    Blue\n}\n\nclass Person {\n    name: string\n    age: int\n}\n\nfunc alsoValid() {\n    let y = 42\n}") == "NL101@3:13+1;NL101@3:14+1;", PeCensus("\nfunc broken() {\n    let x = @@\n}\n\nenum Color {\n    Red,\n    Green,\n    Blue\n}\n\nclass Person {\n    name: string\n    age: int\n}\n\nfunc alsoValid() {\n    let y = 42\n}")
    assert PeDecls("\nfunc broken() {\n    let x = @@\n}\n\nenum Color {\n    Red,\n    Green,\n    Blue\n}\n\nclass Person {\n    name: string\n    age: int\n}\n\nfunc alsoValid() {\n    let y = 42\n}") == "FunctionDeclaration[broken/s2]EnumDeclaration[Color]ClassDeclaration[Person/m2]FunctionDeclaration[alsoValid/s1]", PeDecls("\nfunc broken() {\n    let x = @@\n}\n\nenum Color {\n    Red,\n    Green,\n    Blue\n}\n\nclass Person {\n    name: string\n    age: int\n}\n\nfunc alsoValid() {\n    let y = 42\n}")
    assert PeStmts("\nfunc broken() {\n    let x = @@\n}\n\nenum Color {\n    Red,\n    Green,\n    Blue\n}\n\nclass Person {\n    name: string\n    age: int\n}\n\nfunc alsoValid() {\n    let y = 42\n}") == "VariableDeclarationStatement(x);ExpressionStatement;VariableDeclarationStatement(y);", PeStmts("\nfunc broken() {\n    let x = @@\n}\n\nenum Color {\n    Red,\n    Green,\n    Blue\n}\n\nclass Person {\n    name: string\n    age: int\n}\n\nfunc alsoValid() {\n    let y = 42\n}")
}

// Successor to Parser_MultipleErrors_RecoveryBetweenDeclarations, which asserted `Count > 0` and
// that at least one non-`<error>` class is recovered. The measured answer: `@@@@` is four tokens,
// reports four NL101s, and leaves FOUR `<error>` classes between `Person` and `Employee`. A
// downstream walk over `Declarations` therefore sees six classes for a two-class file.
test "020 slice 16: garbage between two class declarations manufactures FOUR `<error>` classes" {
    assert PeCensus("\nclass Person\n    Name: string\n@@@@\nclass Employee\n    Id: int\n") == "NL101@4:1+1;NL101@4:2+1;NL101@4:3+1;NL101@4:4+1;", PeCensus("\nclass Person\n    Name: string\n@@@@\nclass Employee\n    Id: int\n")
    assert PeRow("\nclass Person\n    Name: string\n@@@@\nclass Employee\n    Id: int\n", 0) == "NL101@4:1+1|Unexpected token '@'|@@@@|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '@' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("\nclass Person\n    Name: string\n@@@@\nclass Employee\n    Id: int\n", 0)
    assert PeDecls("\nclass Person\n    Name: string\n@@@@\nclass Employee\n    Id: int\n") == "ClassDeclaration[Person/m1]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[Employee/m1]", PeDecls("\nclass Person\n    Name: string\n@@@@\nclass Employee\n    Id: int\n")
}

// Successor to Parser_MissingClosingParen_RecoverToNextFunction, which asserted `Count > 0` and
// that exactly one function named `Bar` is present. The measured answer is TWO diagnostics — the
// first about `Foo`'s parameter, the second about `Bar`'s return-type colon — and NEITHER function
// gets a body. The deleted assertion could not see that `Bar` was recovered as a bodiless shell.
test "020 slice 16: a missing `)` in a parameter list recovers to the next function, which keeps no body" {
    assert PeCensus("\nfunc Foo(x int\nfunc Bar() int => 42\n") == "NL102@2:10+1;NL102@3:6+3;", PeCensus("\nfunc Foo(x int\nfunc Bar() int => 42\n")
    assert PeRow("\nfunc Foo(x int\nfunc Bar() int => 42\n", 0) == "NL102@2:10+1|Expected ':' after parameter name. Got 'int'|func Foo(x int|Parameter 'x' needs a ':' before its type.|Write this parameter as `x: Type`.|{Add ':' after 'x'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc Foo(x int\nfunc Bar() int => 42\n", 0)
    assert PeRow("\nfunc Foo(x int\nfunc Bar() int => 42\n", 1) == "NL102@3:6+3|Expected ':' before return type. Got 'int'|func Bar() int => 42|Function 'Bar' needs a ':' before its return type.|Write the return type as `func name(...): Type { ... }`.|{Add ':' before 'int'}{Remove the return type if this function does not return a value}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc Foo(x int\nfunc Bar() int => 42\n", 1)
    assert PeDecls("\nfunc Foo(x int\nfunc Bar() int => 42\n") == "FunctionDeclaration[Foo/nobody]FunctionDeclaration[Bar/nobody]", PeDecls("\nfunc Foo(x int\nfunc Bar() int => 42\n")
}

// Successor to Parser_ErrorInClassMember_NextMemberStillParsed, which asserted that the class
// `Foo` is still present. IT IS — but `Age` IS NOT. The members are `Name` and `<error>`: the
// recovery consumed the following field. This is the exact opposite of the missing-TYPE case
// above, where both fields survive, and it is a genuine recovery limitation that a
// 'the class is still parsed' assertion is structurally unable to report.
test "020 slice 16: a malformed field INITIALIZER swallows the field after it" {
    assert !PeParse("\nclass Foo {\n    Name: string = @@\n    Age: int\n}").Success
    assert PeCensus("\nclass Foo {\n    Name: string = @@\n    Age: int\n}") == "NL101@3:20+1;NL102@3:21+1;", PeCensus("\nclass Foo {\n    Name: string = @@\n    Age: int\n}")
    assert PeRow("\nclass Foo {\n    Name: string = @@\n    Age: int\n}", 0) == "NL101@3:20+1|Unexpected token '@' in expression|    Name: string = @@|I was parsing an expression and found '@', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("\nclass Foo {\n    Name: string = @@\n    Age: int\n}", 0)
    assert PeRow("\nclass Foo {\n    Name: string = @@\n    Age: int\n}", 1) == "NL102@3:21+1|Expected field name. Got '@'|    Name: string = @@|I was expecting an identifier here, but I found '@' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nclass Foo {\n    Name: string = @@\n    Age: int\n}", 1)
    assert PeDecls("\nclass Foo {\n    Name: string = @@\n    Age: int\n}") == "ClassDeclaration[Foo/m2]", PeDecls("\nclass Foo {\n    Name: string = @@\n    Age: int\n}")
    assert PeMembers("\nclass Foo {\n    Name: string = @@\n    Age: int\n}") == "Foo{FieldDeclaration(Name),FieldDeclaration(<error>),}", PeMembers("\nclass Foo {\n    Name: string = @@\n    Age: int\n}")
}

// Successor to Parser_ErrorsInMultipleClassMembers_AllReported, which asserted `Count >= 2` and
// `classes.Count >= 2`. The measured answer is exactly two diagnostics for TWO bad members — the
// first bad initializer swallows the second one whole, so the second `= @@` never reports at all —
// and `Bar` keeps its field. The lower bound hid the swallow.
test "020 slice 16: two malformed members report only twice, and the second class is untouched" {
    assert PeCensus("\nclass Foo {\n    Name: string = @@\n    Age: int = @@\n}\n\nclass Bar {\n    Value: int\n}") == "NL101@3:20+1;NL102@3:21+1;", PeCensus("\nclass Foo {\n    Name: string = @@\n    Age: int = @@\n}\n\nclass Bar {\n    Value: int\n}")
    assert PeRow("\nclass Foo {\n    Name: string = @@\n    Age: int = @@\n}\n\nclass Bar {\n    Value: int\n}", 1) == "NL102@3:21+1|Expected field name. Got '@'|    Name: string = @@|I was expecting an identifier here, but I found '@' instead.|An identifier is a name for a variable, function, or type.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nclass Foo {\n    Name: string = @@\n    Age: int = @@\n}\n\nclass Bar {\n    Value: int\n}", 1)
    assert PeDecls("\nclass Foo {\n    Name: string = @@\n    Age: int = @@\n}\n\nclass Bar {\n    Value: int\n}") == "ClassDeclaration[Foo/m2]ClassDeclaration[Bar/m1]", PeDecls("\nclass Foo {\n    Name: string = @@\n    Age: int = @@\n}\n\nclass Bar {\n    Value: int\n}")
    assert PeMembers("\nclass Foo {\n    Name: string = @@\n    Age: int = @@\n}\n\nclass Bar {\n    Value: int\n}") == "Foo{FieldDeclaration(Name),FieldDeclaration(<error>),}Bar{FieldDeclaration(Value),}", PeMembers("\nclass Foo {\n    Name: string = @@\n    Age: int = @@\n}\n\nclass Bar {\n    Value: int\n}")
}

// ══ THE "DOES NOT SWALLOW THE FOLLOWING STATEMENT" FAMILY ════════════════════════════════════
//
// Successors to the deleted file's largest family. Each case pairs one incomplete construct with
// a following statement that must survive, and each asserted
// `Assert.DoesNotContain(result.Errors, e => e.Code == UnexpectedToken)` — a NEGATIVE claim over
// one code. Every census below states the whole list, which answers that negative claim for ALL
// codes at once, and every statement census states which statements survived.

// Successor to Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements, which asserted the
// single NL102, its span and snippet, and that the three variable names are `first`/`second`/`third`.
// The census adds the two NL101s from the `@@` on line 5 — which the deleted `Assert.Single` with a
// predicate did not have to account for — so the whole list is now stated, not one row of it.
test "020 slice 16: a dangling `+` reports once and all three following declarations survive" {
    assert PeCensus("\nfunc test() {\n    first := 1 +\n    second := missingValue\n    third := @@\n}") == "NL102@3:14+3;NL101@5:14+1;NL101@5:15+1;", PeCensus("\nfunc test() {\n    first := 1 +\n    second := missingValue\n    third := @@\n}")
    assert PeRow("\nfunc test() {\n    first := 1 +\n    second := missingValue\n    third := @@\n}", 0) == "NL102@3:14+3|Expected expression after '+'|    first := 1 +|The '+' operator needs an expression on its right side.|Finish the expression after the operator, or remove the operator if the expression is already complete.|{Add an expression after '+'}{Remove the trailing '+'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("\nfunc test() {\n    first := 1 +\n    second := missingValue\n    third := @@\n}", 0)
    assert PeDecls("\nfunc test() {\n    first := 1 +\n    second := missingValue\n    third := @@\n}") == "FunctionDeclaration[test/s4]", PeDecls("\nfunc test() {\n    first := 1 +\n    second := missingValue\n    third := @@\n}")
    assert PeStmts("\nfunc test() {\n    first := 1 +\n    second := missingValue\n    third := @@\n}") == "VariableDeclarationStatement(first);VariableDeclarationStatement(second);VariableDeclarationStatement(third);ExpressionStatement;", PeStmts("\nfunc test() {\n    first := 1 +\n    second := missingValue\n    third := @@\n}")
}

// Successor to Parser_MissingInitializer_DoesNotSwallowFollowingStatement.
test "020 slice 16: a `:=` with no initializer keeps the next statement AND the one after it" {
    assert PeCensus("func test() {\n    name :=\n        greeting := \"hi\"\n    print greeting\n}") == "NL102@2:5+4;", PeCensus("func test() {\n    name :=\n        greeting := \"hi\"\n    print greeting\n}")
    assert PeRow("func test() {\n    name :=\n        greeting := \"hi\"\n    print greeting\n}", 0) == "NL102@2:5+4|Expected an initializer expression after ':='|    name :=|This shorthand variable declaration needs an initializer expression after ':='.|Finish the expression before starting the next statement.|{Add an initializer expression after ':='}{Remove ':=' until the expression is ready}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    name :=\n        greeting := \"hi\"\n    print greeting\n}", 0)
    assert PeDecls("func test() {\n    name :=\n        greeting := \"hi\"\n    print greeting\n}") == "FunctionDeclaration[test/s3]", PeDecls("func test() {\n    name :=\n        greeting := \"hi\"\n    print greeting\n}")
    assert PeStmts("func test() {\n    name :=\n        greeting := \"hi\"\n    print greeting\n}") == "VariableDeclarationStatement(name);VariableDeclarationStatement(greeting);PrintStatement;", PeStmts("func test() {\n    name :=\n        greeting := \"hi\"\n    print greeting\n}")
}

// Successor to Parser_MissingAssignmentValue_UsesTargetSpanAndContinues. The span is `value`, the
// assignment target, five characters — not the `=`.
test "020 slice 16: an `=` with no value uses the TARGET's span and keeps the following print" {
    assert PeCensus("func test() {\n    value := 1\n    value =\n    print value\n}") == "NL102@3:5+5;", PeCensus("func test() {\n    value := 1\n    value =\n    print value\n}")
    assert PeRow("func test() {\n    value := 1\n    value =\n    print value\n}", 0) == "NL102@3:5+5|Expected expression after '='|    value =|The '=' operator needs an expression on its right side.|Finish the expression after the operator, or remove the operator if the expression is already complete.|{Add an expression after '='}{Remove the trailing '='}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    value := 1\n    value =\n    print value\n}", 0)
    assert PeDecls("func test() {\n    value := 1\n    value =\n    print value\n}") == "FunctionDeclaration[test/s3]", PeDecls("func test() {\n    value := 1\n    value =\n    print value\n}")
    assert PeStmts("func test() {\n    value := 1\n    value =\n    print value\n}") == "VariableDeclarationStatement(value);ExpressionStatement;PrintStatement;", PeStmts("func test() {\n    value := 1\n    value =\n    print value\n}")
}

// Successor to Parser_PrintMissingExpression_DoesNotSwallowFollowingStatement. The PrintStatement
// survives with a placeholder value, so the census shows `PrintStatement;` BEFORE the recovered
// declaration — the parser keeps the broken statement rather than dropping it.
test "020 slice 16: a bare `print` reports once and the next statement still parses" {
    assert PeCensus("func test() {\n    print\n        greeting := \"hi\"\n}") == "NL102@2:5+5;", PeCensus("func test() {\n    print\n        greeting := \"hi\"\n}")
    assert PeRow("func test() {\n    print\n        greeting := \"hi\"\n}", 0) == "NL102@2:5+5|Expected an expression to print after 'print'|    print|This print statement needs an expression to print after 'print'.|Finish the expression before starting the next statement.|{Add an expression to print after 'print'}{Remove 'print' until the expression is ready}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    print\n        greeting := \"hi\"\n}", 0)
    assert PeDecls("func test() {\n    print\n        greeting := \"hi\"\n}") == "FunctionDeclaration[test/s2]", PeDecls("func test() {\n    print\n        greeting := \"hi\"\n}")
    assert PeStmts("func test() {\n    print\n        greeting := \"hi\"\n}") == "PrintStatement;VariableDeclarationStatement(greeting);", PeStmts("func test() {\n    print\n        greeting := \"hi\"\n}")
}

// Successor to Parser_ForeachMissingIn_UnderlinesForeachKeywordAndContinues. The recovered node is
// a ForeachStatement over `item` with a real BlockStatement body.
test "020 slice 16: `foreach item items` underlines `foreach` and keeps the loop with its variable" {
    assert PeCensus("func test() {\n    foreach item items {\n        print item\n    }\n}") == "NL102@2:5+7;", PeCensus("func test() {\n    foreach item items {\n        print item\n    }\n}")
    assert PeRow("func test() {\n    foreach item items {\n        print item\n    }\n}", 0) == "NL102@2:5+7|Expected 'in' between the loop variable and collection|    foreach item items {|This foreach statement needs the 'in' keyword between the loop variable and the collection.|Write `foreach item in ...`.|{Add 'in' after 'item'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    foreach item items {\n        print item\n    }\n}", 0)
    assert PeDecls("func test() {\n    foreach item items {\n        print item\n    }\n}") == "FunctionDeclaration[test/s1]", PeDecls("func test() {\n    foreach item items {\n        print item\n    }\n}")
    assert PeStmts("func test() {\n    foreach item items {\n        print item\n    }\n}") == "ForeachStatement(item/BlockStatement);", PeStmts("func test() {\n    foreach item items {\n        print item\n    }\n}")
}

// Successor to Parser_ForInMissingIn_UnderlinesForKeywordAndContinues, which asserted
// `IsType<ForeachStatement>(forStatement.Body)`. The explanation differs from the `foreach` arm's
// ('This for-in statement …' versus 'This foreach statement …') — two sentences the deleted
// `Message.Contains` shared.
test "020 slice 16: `for item items` underlines `for` and recovers a ForStatement wrapping a foreach" {
    assert PeCensus("func test() {\n    for item items {\n        print item\n    }\n}") == "NL102@2:5+3;", PeCensus("func test() {\n    for item items {\n        print item\n    }\n}")
    assert PeRow("func test() {\n    for item items {\n        print item\n    }\n}", 0) == "NL102@2:5+3|Expected 'in' between the loop variable and collection|    for item items {|This for-in statement needs the 'in' keyword between the loop variable and the collection.|Write `for item in ...`.|{Add 'in' after 'item'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    for item items {\n        print item\n    }\n}", 0)
    assert PeDecls("func test() {\n    for item items {\n        print item\n    }\n}") == "FunctionDeclaration[test/s1]", PeDecls("func test() {\n    for item items {\n        print item\n    }\n}")
    assert PeStmts("func test() {\n    for item items {\n        print item\n    }\n}") == "ForStatement(ForeachStatement);", PeStmts("func test() {\n    for item items {\n        print item\n    }\n}")
}

// Successor to Parser_WhileMissingCondition_UnderlinesWhileKeywordAndContinues.
test "020 slice 16: a `while` with no condition underlines `while` and keeps its block body" {
    assert PeCensus("func test() {\n    while {\n        print \"hi\"\n    }\n}") == "NL102@2:5+5;", PeCensus("func test() {\n    while {\n        print \"hi\"\n    }\n}")
    assert PeRow("func test() {\n    while {\n        print \"hi\"\n    }\n}", 0) == "NL102@2:5+5|Expected a condition expression after 'while'|    while {|This while statement needs a condition expression after 'while'.|Finish the expression before starting the next statement.|{Add a condition expression after 'while'}{Remove 'while' until the expression is ready}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    while {\n        print \"hi\"\n    }\n}", 0)
    assert PeDecls("func test() {\n    while {\n        print \"hi\"\n    }\n}") == "FunctionDeclaration[test/s1]", PeDecls("func test() {\n    while {\n        print \"hi\"\n    }\n}")
    assert PeStmts("func test() {\n    while {\n        print \"hi\"\n    }\n}") == "WhileStatement(BlockStatement);", PeStmts("func test() {\n    while {\n        print \"hi\"\n    }\n}")
}

// Successor to Parser_ObjectInitializerMissingValue_UsesPropertyNameSpanAndContinues. The message
// NAMES the member and differs from the missing-COLON sibling above — 'Expected a value for object
// initializer member' versus 'Expected ':' after object initializer member'.
test "020 slice 16: an object initializer member with no value uses the member's span and continues" {
    assert PeCensus("func test() {\n    user := new User { Name: }\n    print \"after\"\n}") == "NL102@2:24+4;", PeCensus("func test() {\n    user := new User { Name: }\n    print \"after\"\n}")
    assert PeRow("func test() {\n    user := new User { Name: }\n    print \"after\"\n}", 0) == "NL102@2:24+4|Expected a value for object initializer member 'Name'|    user := new User { Name: }|Object initializer member 'Name' needs a value after ':'.|Write 'Name: value'.|{Add a value after 'Name:'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    user := new User { Name: }\n    print \"after\"\n}", 0)
    assert PeDecls("func test() {\n    user := new User { Name: }\n    print \"after\"\n}") == "FunctionDeclaration[test/s2]", PeDecls("func test() {\n    user := new User { Name: }\n    print \"after\"\n}")
    assert PeStmts("func test() {\n    user := new User { Name: }\n    print \"after\"\n}") == "VariableDeclarationStatement(user);PrintStatement;", PeStmts("func test() {\n    user := new User { Name: }\n    print \"after\"\n}")
}

// Successors to the three `[InlineData]` rows of Parser_MissingStatementBody_UnderlinesControlFlowKeyword,
// which asserted line/column/`keyword.Length` and the shared message fragment. The three share ONE
// message and ONE explanation but recover THREE different bodies: `if` yields an IfStatement, `for`
// yields a ForStatement wrapping a foreach, and `while` yields a WhileStatement over an
// EmptyStatement. Nothing had stated what the parser substitutes for a missing body.
test "020 slice 16: `if`, `for` and `while` with no body all underline their keyword \u2014 with three different recovered bodies" {
    assert PeCensus("func test() {\n    if true\n}") == "NL102@2:5+2;", PeCensus("func test() {\n    if true\n}")
    assert PeRow("func test() {\n    if true\n}", 0) == "NL102@2:5+2|Expected statement body. Got '}'|    if true|This control-flow keyword needs a statement or block after its condition.|Add a block like `{ ... }`, or add a single statement after the keyword.|{Add a block body}{Add a statement body}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    if true\n}", 0)
    assert PeStmts("func test() {\n    if true\n}") == "IfStatement;", PeStmts("func test() {\n    if true\n}")
    assert PeCensus("func test() {\n    for item in items\n}") == "NL102@2:5+3;", PeCensus("func test() {\n    for item in items\n}")
    assert PeRow("func test() {\n    for item in items\n}", 0) == "NL102@2:5+3|Expected statement body. Got '}'|    for item in items|This control-flow keyword needs a statement or block after its condition.|Add a block like `{ ... }`, or add a single statement after the keyword.|{Add a block body}{Add a statement body}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    for item in items\n}", 0)
    assert PeStmts("func test() {\n    for item in items\n}") == "ForStatement(ForeachStatement);", PeStmts("func test() {\n    for item in items\n}")
    assert PeCensus("func test() {\n    while true\n}") == "NL102@2:5+5;", PeCensus("func test() {\n    while true\n}")
    assert PeRow("func test() {\n    while true\n}", 0) == "NL102@2:5+5|Expected statement body. Got '}'|    while true|This control-flow keyword needs a statement or block after its condition.|Add a block like `{ ... }`, or add a single statement after the keyword.|{Add a block body}{Add a statement body}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    while true\n}", 0)
    assert PeStmts("func test() {\n    while true\n}") == "WhileStatement(EmptyStatement);", PeStmts("func test() {\n    while true\n}")
}

// Successor to Parser_InvalidPrefixPlus_UnderlinesVisibleExpressionSegment. NL103, not NL101: the
// explanation says a leading '+' does not change the value in N#, so it is deliberately outside the
// expression grammar. That design decision was reachable only through this diagnostic's text.
test "020 slice 16: a prefix `+` is refused by DESIGN, with the reason stated" {
    assert PeCensus("func test() {\n    + 1\n}") == "NL103@2:5+3;", PeCensus("func test() {\n    + 1\n}")
    assert PeRow("func test() {\n    + 1\n}", 0) == "NL103@2:5+3|Prefix '+' is not supported|    + 1|A leading '+' does not change the value in N#, so it is not part of the expression grammar.|Remove the leading '+'. Numeric literals and variables are already positive unless you subtract or negate them.|{Remove the leading '+'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL103", PeRow("func test() {\n    + 1\n}", 0)
    assert PeStmts("func test() {\n    + 1\n}") == "ExpressionStatement;", PeStmts("func test() {\n    + 1\n}")
}

// Successor to Parser_LeadingMemberAccess_UnderlinesVisibleMemberAccess.
test "020 slice 16: a leading `.Name` underlines the whole member access" {
    assert PeCensus("func test() {\n    .Name\n}") == "NL102@2:5+5;", PeCensus("func test() {\n    .Name\n}")
    assert PeRow("func test() {\n    .Name\n}", 0) == "NL102@2:5+5|Expected expression before '.'|    .Name|I see a dot (.) operator, but there is no receiver expression before it.|Put an expression before '.', or remove the member access.|{Add a receiver before '.'}{Remove the member access until the receiver is known}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    .Name\n}", 0)
    assert PeStmts("func test() {\n    .Name\n}") == "ExpressionStatement;", PeStmts("func test() {\n    .Name\n}")
}

// Successor to the first `[InlineData]` row of Parser_MissingUnaryKeywordOperand_UnderlinesKeyword.
test "020 slice 16: a bare `await` underlines the keyword" {
    assert PeCensus("func test() {\n    value := await\n}") == "NL102@2:14+5;", PeCensus("func test() {\n    value := await\n}")
    assert PeRow("func test() {\n    value := await\n}", 0) == "NL102@2:14+5|Expected an expression to await after 'await'|    value := await|This await expression needs an expression to await after 'await'.|Add an expression to await after 'await', or remove 'await'.|{Add an expression to await after 'await'}{Remove 'await' until the expression is ready}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    value := await\n}", 0)
    assert PeStmts("func test() {\n    value := await\n}") == "VariableDeclarationStatement(value);", PeStmts("func test() {\n    value := await\n}")
}

// Successor to the second `[InlineData]` row. The two keywords get two DIFFERENT sentences and two
// different suggestion pairs, which the shared theory could not distinguish.
test "020 slice 16: a bare `must` underlines the keyword and names the nullable-unwrap contract" {
    assert PeCensus("func test() {\n    value := must\n}") == "NL102@2:14+4;", PeCensus("func test() {\n    value := must\n}")
    assert PeRow("func test() {\n    value := must\n}", 0) == "NL102@2:14+4|Expected a nullable expression to unwrap after 'must'|    value := must|This must expression needs a nullable expression to unwrap after 'must'.|Add a nullable expression to unwrap after 'must', or remove 'must'.|{Add a nullable expression to unwrap after 'must'}{Remove 'must' until the expression is ready}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    value := must\n}", 0)
    assert PeStmts("func test() {\n    value := must\n}") == "VariableDeclarationStatement(value);", PeStmts("func test() {\n    value := must\n}")
}

// Successor to Parser_MissingLambdaBody_UnderlinesLambdaHeader.
test "020 slice 16: a lambda with no body underlines the lambda HEADER, `x =>`" {
    assert PeCensus("func test() {\n    f := x =>\n}") == "NL102@2:10+4;", PeCensus("func test() {\n    f := x =>\n}")
    assert PeRow("func test() {\n    f := x =>\n}", 0) == "NL102@2:10+4|Expected a lambda body expression after '=>'|    f := x =>|This lambda expression needs a lambda body expression after '=>'.|Finish the expression before starting the next statement.|{Add a lambda body expression after '=>'}{Remove '=>' until the expression is ready}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    f := x =>\n}", 0)
    assert PeStmts("func test() {\n    f := x =>\n}") == "VariableDeclarationStatement(f);", PeStmts("func test() {\n    f := x =>\n}")
}

// Successor to Parser_MissingTernaryElse_UnderlinesTernaryExpression. Fifteen characters, covering
// `condition ? 1 :` — the visible expression, not the trailing colon.
test "020 slice 16: a ternary with no else underlines the whole ternary so far" {
    assert PeCensus("func test() {\n    value := condition ? 1 :\n}") == "NL102@2:14+15;", PeCensus("func test() {\n    value := condition ? 1 :\n}")
    assert PeRow("func test() {\n    value := condition ? 1 :\n}", 0) == "NL102@2:14+15|Expected an else expression after ':'|    value := condition ? 1 :|This ternary expression needs an else expression after ':'.|Finish the expression before starting the next statement.|{Add an else expression after ':'}{Remove ':' until the expression is ready}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    value := condition ? 1 :\n}", 0)
    assert PeStmts("func test() {\n    value := condition ? 1 :\n}") == "VariableDeclarationStatement(value);", PeStmts("func test() {\n    value := condition ? 1 :\n}")
}

// ══ UNTERMINATED LITERALS — FOUR DELIMITERS, FOUR SENTENCES ══════════════════════════════════
//
// Successors to the five unterminated-literal cases. Each asserted the code, a message fragment,
// the span, the snippet and `Contains("closing quote", …, OrdinalIgnoreCase)`. The four
// delimiters produce four distinct explanations and four distinct hint sentences, and the
// escaped-quote case proves the scanner does not treat `\"` as a terminator.

// Successor to Parser_UnterminatedStringLiteral_ReportsInvalidLiteralAtOpeningQuote. The following
// `print name` statement still parses — the scanner stops at the line end, not at the file end.
test "020 slice 16: an unterminated string underlines the opening quote and the text after it" {
    assert PeCensus("func test() {\n    name := \"Ada\n    print name\n}") == "NL105@2:13+4;", PeCensus("func test() {\n    name := \"Ada\n    print name\n}")
    assert PeRow("func test() {\n    name := \"Ada\n    print name\n}", 0) == "NL105@2:13+4|Unterminated string literal|    name := \"Ada|This string starts with a quote but reaches the end of the line before a closing quote.|Add the closing quote on this line, or use a triple-quoted string for multi-line text.|{Add a closing quote}{Use triple quotes for multi-line strings}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow("func test() {\n    name := \"Ada\n    print name\n}", 0)
    assert PeStmts("func test() {\n    name := \"Ada\n    print name\n}") == "VariableDeclarationStatement(name);PrintStatement;", PeStmts("func test() {\n    name := \"Ada\n    print name\n}")
}

// Successor to Parser_UnterminatedStringLiteral_WithEscapedQuote_ReportsInvalidLiteralAtOpeningQuote.
// Six characters where the plain case has four: the `\"` is consumed as escaped content. If the
// scanner ever treated it as a terminator this source would parse silently.
test "020 slice 16: an escaped quote does NOT terminate the string, and the span grows by two" {
    assert PeCensus("func test() {\n    name := \"Ada\\\"\n}") == "NL105@2:13+6;", PeCensus("func test() {\n    name := \"Ada\\\"\n}")
    assert PeRow("func test() {\n    name := \"Ada\\\"\n}", 0) == "NL105@2:13+6|Unterminated string literal|    name := \"Ada\\\\\"|This string starts with a quote but reaches the end of the line before a closing quote.|Add the closing quote on this line, or use a triple-quoted string for multi-line text.|{Add a closing quote}{Use triple quotes for multi-line strings}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow("func test() {\n    name := \"Ada\\\"\n}", 0)
    assert PeStmts("func test() {\n    name := \"Ada\\\"\n}") == "VariableDeclarationStatement(name);", PeStmts("func test() {\n    name := \"Ada\\\"\n}")
}

// Successor to Parser_UnterminatedCharacterLiteral_ReportsInvalidLiteralAtOpeningQuote. A different
// explanation and a different hint from the string arm, and a two-character span.
test "020 slice 16: an unterminated character literal offers the double-quote route" {
    assert PeCensus("func test() {\n    letter := 'a\n}") == "NL105@2:15+2;", PeCensus("func test() {\n    letter := 'a\n}")
    assert PeRow("func test() {\n    letter := 'a\n}", 0) == "NL105@2:15+2|Unterminated character literal|    letter := 'a|This character literal starts with a quote but does not have a closing quote.|Write a single character like `'a'`, or use a string literal like \"a\" when you need text.|{Add the closing quote}{Use double quotes for a string}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow("func test() {\n    letter := 'a\n}", 0)
    assert PeStmts("func test() {\n    letter := 'a\n}") == "VariableDeclarationStatement(letter);", PeStmts("func test() {\n    letter := 'a\n}")
}

// Successor to Parser_UnterminatedTripleQuoteStringLiteral_ReportsInvalidLiteralAtOpeningDelimiter.
// Its explanation says 'reaches the end of the FILE', not the end of the line — the multi-line
// delimiter changes the failure mode as well as the message.
test "020 slice 16: an unterminated triple-quoted string spans the three-character delimiter" {
    assert PeCensus("func test() {\n    text := \"\"\"hello\nworld\n}\n") == "NL105@2:13+3;", PeCensus("func test() {\n    text := \"\"\"hello\nworld\n}\n")
    assert PeRow("func test() {\n    text := \"\"\"hello\nworld\n}\n", 0) == "NL105@2:13+3|Unterminated triple-quoted string literal|    text := \"\"\"hello|This triple-quoted string starts with `\"\"\"` but reaches the end of the file before the closing triple quote.|Add the closing triple quote `\"\"\"` before the end of the file.|{Add the closing triple quote}{Check where the raw string should end}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow("func test() {\n    text := \"\"\"hello\nworld\n}\n", 0)
    assert PeStmts("func test() {\n    text := \"\"\"hello\nworld\n}\n") == "VariableDeclarationStatement(text);", PeStmts("func test() {\n    text := \"\"\"hello\nworld\n}\n")
}

// Successor to Parser_UnterminatedInterpolatedRawStringLiteral_ReportsInvalidLiteralAtOpeningDelimiter.
// Four characters, and the snippet keeps the interpolation hole verbatim.
test "020 slice 16: an unterminated interpolated raw string spans the four-character `$\"\"\"` delimiter" {
    assert PeCensus("func test() {\n    text := $\"\"\"hello {name}\n}\n") == "NL105@2:13+4;", PeCensus("func test() {\n    text := $\"\"\"hello {name}\n}\n")
    assert PeRow("func test() {\n    text := $\"\"\"hello {name}\n}\n", 0) == "NL105@2:13+4|Unterminated interpolated raw string literal|    text := $\"\"\"hello {name}|This interpolated raw string starts with `$\"\"\"` but reaches the end of the file before the closing triple quote.|Add the closing triple quote `\"\"\"` before the end of the file.|{Add the closing triple quote}{Check where the raw string should end}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow("func test() {\n    text := $\"\"\"hello {name}\n}\n", 0)
    assert PeStmts("func test() {\n    text := $\"\"\"hello {name}\n}\n") == "VariableDeclarationStatement(text);", PeStmts("func test() {\n    text := $\"\"\"hello {name}\n}\n")
}

// ══ UNBALANCED DELIMITERS — WHO OWNS THE SQUIGGLE ════════════════════════════════════════════
//
// Successors to the five missing-paren/bracket cases. The rule these state is that the span
// anchors on the OWNER of the delimiter — the callee, the function name, the assigned variable,
// the indexed receiver — never on the delimiter itself, so the squiggle lands on something the
// developer can read.

// Successor to Parser_MissingClosingParen_PointsAtCallOwner.
test "020 slice 16: a missing `)` underlines the CALLEE" {
    assert PeCensus("func test() {\n    print(\"hello\"\n}") == "NL107@2:5+5;", PeCensus("func test() {\n    print(\"hello\"\n}")
    assert PeRow("func test() {\n    print(\"hello\"\n}", 0) == "NL107@2:5+5|Missing closing ')'|    print(\"hello\"|I reached the next line while looking for the closing ')' that matches an earlier '('.|Every opening parenthesis '(' needs a matching closing parenthesis ')'.|{Add ')' before starting the next line}{Check the matching '(' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL107", PeRow("func test() {\n    print(\"hello\"\n}", 0)
    assert PeStmts("func test() {\n    print(\"hello\"\n}") == "PrintStatement;", PeStmts("func test() {\n    print(\"hello\"\n}")
}

// Successor to Parser_UnclosedEmptyCallArgumentList_ReportsMissingParenAtCallOwner. The snippet is
// just `    print(` — there is no argument text to underline — and the span is still the five
// characters of `print`.
test "020 slice 16: an unclosed EMPTY argument list still anchors on the callee, and the next line parses" {
    assert PeCensus("func test() {\n    print(\n    greeting.CompareTo(\"ter\")\n}") == "NL107@2:5+5;", PeCensus("func test() {\n    print(\n    greeting.CompareTo(\"ter\")\n}")
    assert PeRow("func test() {\n    print(\n    greeting.CompareTo(\"ter\")\n}", 0) == "NL107@2:5+5|Missing closing ')'|    print(|I reached the next line while looking for the closing ')' that matches an earlier '('.|Every opening parenthesis '(' needs a matching closing parenthesis ')'.|{Add ')' before starting the next line}{Check the matching '(' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL107", PeRow("func test() {\n    print(\n    greeting.CompareTo(\"ter\")\n}", 0)
    assert PeStmts("func test() {\n    print(\n    greeting.CompareTo(\"ter\")\n}") == "PrintStatement;ExpressionStatement;", PeStmts("func test() {\n    print(\n    greeting.CompareTo(\"ter\")\n}")
}

// Successor to Parser_UnclosedEmptyFunctionParameterList_ReportsMissingParenAtFunctionName. The
// function is recovered without a body, which the deleted file did not state.
test "020 slice 16: an unclosed parameter list anchors on the FUNCTION NAME" {
    assert PeCensus("func test(\n") == "NL107@1:6+4;", PeCensus("func test(\n")
    assert PeRow("func test(\n", 0) == "NL107@1:6+4|Missing closing ')'|func test(|I reached the next line while looking for the closing ')' that matches an earlier '('.|Every opening parenthesis '(' needs a matching closing parenthesis ')'.|{Add ')' before starting the next line}{Check the matching '(' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL107", PeRow("func test(\n", 0)
    assert PeStmts("func test(\n") == "", PeStmts("func test(\n")
}

// Successor to Parser_MissingClosingBracket_ArrayLiteralPointsAtAssignedVariable.
test "020 slice 16: an unclosed array literal underlines the ASSIGNED VARIABLE" {
    assert PeCensus("func test() {\n    nums := [1, 2\n    print nums\n}") == "NL108@2:5+4;", PeCensus("func test() {\n    nums := [1, 2\n    print nums\n}")
    assert PeRow("func test() {\n    nums := [1, 2\n    print nums\n}", 0) == "NL108@2:5+4|Missing closing ']'|    nums := [1, 2|I reached the next line while looking for the closing ']' that matches an earlier '['.|Every opening bracket '[' needs a matching closing bracket ']'.|{Add ']' before starting the next line}{Check the matching '[' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL108", PeRow("func test() {\n    nums := [1, 2\n    print nums\n}", 0)
    assert PeStmts("func test() {\n    nums := [1, 2\n    print nums\n}") == "VariableDeclarationStatement(nums);PrintStatement;", PeStmts("func test() {\n    nums := [1, 2\n    print nums\n}")
}

// Successor to Parser_MissingClosingBracket_IndexAccessPointsAtReceiver. Same code and same
// explanation as the array-literal arm, a different owner — the distinction the deleted file's two
// cases made only through their line numbers.
test "020 slice 16: an unclosed index access underlines the INDEXED RECEIVER" {
    assert PeCensus("func test() {\n    nums := [1, 2, 3]\n    print nums[0\n}") == "NL108@3:11+4;", PeCensus("func test() {\n    nums := [1, 2, 3]\n    print nums[0\n}")
    assert PeRow("func test() {\n    nums := [1, 2, 3]\n    print nums[0\n}", 0) == "NL108@3:11+4|Missing closing ']'|    print nums[0|I reached the next line while looking for the closing ']' that matches an earlier '['.|Every opening bracket '[' needs a matching closing bracket ']'.|{Add ']' before starting the next line}{Check the matching '[' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL108", PeRow("func test() {\n    nums := [1, 2, 3]\n    print nums[0\n}", 0)
    assert PeStmts("func test() {\n    nums := [1, 2, 3]\n    print nums[0\n}") == "VariableDeclarationStatement(nums);PrintStatement;", PeStmts("func test() {\n    nums := [1, 2, 3]\n    print nums[0\n}")
}

// Successor to Parser_ReportsError_MissingClosingParen_SingleLine, which asserted the code, the
// line and a non-null explanation. The nine-character span covers the dotted callee, not just its
// last segment.
test "020 slice 16: a missing `)` on a qualified call underlines the whole `Console.WriteLine`" {
    assert PeCensus("\nfunc test() {\n    Console.WriteLine(\"hello\"\n}") == "NL107@3:13+9;", PeCensus("\nfunc test() {\n    Console.WriteLine(\"hello\"\n}")
    assert PeRow("\nfunc test() {\n    Console.WriteLine(\"hello\"\n}", 0) == "NL107@3:13+9|Missing closing ')'|    Console.WriteLine(\"hello\"|I reached the next line while looking for the closing ')' that matches an earlier '('.|Every opening parenthesis '(' needs a matching closing parenthesis ')'.|{Add ')' before starting the next line}{Check the matching '(' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL107", PeRow("\nfunc test() {\n    Console.WriteLine(\"hello\"\n}", 0)
    assert PeStmts("\nfunc test() {\n    Console.WriteLine(\"hello\"\n}") == "ExpressionStatement;", PeStmts("\nfunc test() {\n    Console.WriteLine(\"hello\"\n}")
}

// ══ TUPLE DECONSTRUCTION AND `using` ═════════════════════════════════════════════════════════

// Successor to Parser_UsingTupleDeconstruction_PointsAtTuplePattern. Thirteen characters over
// `(left, right)`, three suggestions including a worked `File.Open` example, and the
// disposal-semantics note that is the actual reason for the restriction.
test "020 slice 16: `using` with a tuple pattern is refused, and the pattern is what gets underlined" {
    assert PeCensus("func test() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}") == "NL103@2:15+13;", PeCensus("func test() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}")
    assert PeRow("func test() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}", 0) == "NL103@2:15+13|Using statement requires a variable declaration, not tuple deconstruction|    using let (left, right) := getPair() {|The 'using' statement can only work with single variable declarations, not tuple deconstruction.|Use a single variable: using let resource := getResource() { ... }|{Change from tuple deconstruction to single variable}{Example: using let file := File.Open(path) { ... }}{Note: The variable will be automatically disposed when the block ends}|https://schneidenbach.github.io/nsharplang/docs/errors/NL103", PeRow("func test() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}", 0)
    assert PeDecls("func test() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}") == "FunctionDeclaration[test/s1]", PeDecls("func test() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}")
    assert PeStmts("func test() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}") == "UsingStatement;", PeStmts("func test() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}")
}

// Successor to Parser_TupleDeconstruction_MalformedSeparator_ReportsSensibleDiagnostic. The message
// names the token it found ('Got 'err''), the names `x`/`y` survive, and the initializer is the
// real CallExpression — so the recovery skipped exactly one token.
test "020 slice 16: a stray token where `:=` belongs reports once and the deconstruction still lands" {
    assert PeCensus("func test() {\n    let (x, y) err := getTuple()\n}") == "NL102@2:16+3;", PeCensus("func test() {\n    let (x, y) err := getTuple()\n}")
    assert PeRow("func test() {\n    let (x, y) err := getTuple()\n}", 0) == "NL102@2:16+3|Tuple deconstruction requires ':=' or '='. Got 'err'|    let (x, y) err := getTuple()|To unpack a tuple into multiple variables, you need to use ':=' or '=' after the variable list.|Tuple deconstruction syntax: (x, y) := getTuple() or (x, y) = getTuple()|{Add ':=' for new variables: (x, y) := (1, 2)}{Add '=' for existing variables: (x, y) = tuple}{Example: (name, age) := getPerson()}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    let (x, y) err := getTuple()\n}", 0)
    assert PeDecls("func test() {\n    let (x, y) err := getTuple()\n}") == "FunctionDeclaration[test/s1]", PeDecls("func test() {\n    let (x, y) err := getTuple()\n}")
    assert PeStmts("func test() {\n    let (x, y) err := getTuple()\n}") == "TupleDeconstructionStatement(x,y/CallExpression);", PeStmts("func test() {\n    let (x, y) err := getTuple()\n}")
}

// Successor to Parser_TupleDeconstruction_DoubleSeparatorFailure_AnchorsInitializerPlaceholderAtCurrentToken,
// a named regression test for an error-recovery anchoring bug. The deleted file asserted the
// placeholder's line (3) and its name (`<error>`). The statement census states its COLUMN as well
// — 2, the `}` on line 3 — which is the position the bug got wrong in the other direction, and
// which no assertion in the deleted file could see. It also states that panic mode suppressed the
// follow-on 'expected an initializer' diagnostic: the census is exactly one row.
test "020 slice 16: the double-failure placeholder anchors at the CURRENT token, line 3 column 2" {
    assert PeCensus("func test() {\n    let (x, y) err\n}") == "NL102@2:16+3;", PeCensus("func test() {\n    let (x, y) err\n}")
    assert PeRow("func test() {\n    let (x, y) err\n}", 0) == "NL102@2:16+3|Tuple deconstruction requires ':=' or '='. Got 'err'|    let (x, y) err|To unpack a tuple into multiple variables, you need to use ':=' or '=' after the variable list.|Tuple deconstruction syntax: (x, y) := getTuple() or (x, y) = getTuple()|{Add ':=' for new variables: (x, y) := (1, 2)}{Add '=' for existing variables: (x, y) = tuple}{Example: (name, age) := getPerson()}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("func test() {\n    let (x, y) err\n}", 0)
    assert PeDecls("func test() {\n    let (x, y) err\n}") == "FunctionDeclaration[test/s1]", PeDecls("func test() {\n    let (x, y) err\n}")
    assert PeStmts("func test() {\n    let (x, y) err\n}") == "TupleDeconstructionStatement(x,y/IdentifierExpression=<error>@3:2);", PeStmts("func test() {\n    let (x, y) err\n}")
}

// ══ THE NL101-NL108 SPAN TABLE ═══════════════════════════════════════════════════════════════
//
// Successors to the deleted file's `#region Syntax Diagnostic Spans (NL101-NL108)` — eight cases
// that went through a shared `AssertSpan` helper. That helper asserted two things: the 1-based
// compiler span plus the UNDERLINED TEXT, and the 0-based end-exclusive LSP range derived from it
// by `LspDiagnosticConverter`. The compiler half is here, with the whole row rather than the span
// alone. THE LSP HALF IS NOT LOST: `LspDiagnosticConverter.FromCompilerError` is an `internal`
// class in `NSharpLang.LanguageServer`, which sits ABOVE this assembly, and
// `tests/LanguageServerDiagnosticsTests.cs` — whose subject it is, and which this slice does not
// touch — owns `AssertLspRange` and calls it at more than twenty sites, including theory rows over
// the same malformed-parameter sources asserting the same line/column/length AND the derived range.
//
// `PeUnderlined` reproduces the helper's text check: the span's characters, cut out of the snippet.

func PeUnderlined(source: string, index: int): string {
    parsed := PeParse(source)
    if index >= parsed.Errors.Count {
        return "<no-such-error>"
    }
    e := parsed.Errors[index]
    snippet := e.SourceSnippet
    if snippet == null {
        return "<null-snippet>"
    }
    if e.Column - 1 + e.Length > snippet.Length {
        return "<over-long-span>"
    }
    return snippet.Substring(e.Column - 1, e.Length)
}

// Successor to Span_NL101_UnexpectedToken_UnderlinesOffendingToken.
test "020 slice 16: NL101 underlines the offending token" {
    assert PeCensus("package T\n\nfunc Main() {\n    let x = @\n}\n") == "NL101@4:13+1;", PeCensus("package T\n\nfunc Main() {\n    let x = @\n}\n")
    assert PeRow("package T\n\nfunc Main() {\n    let x = @\n}\n", 0) == "NL101@4:13+1|Unexpected token '@' in expression|    let x = @|I was parsing an expression and found '@', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL101", PeRow("package T\n\nfunc Main() {\n    let x = @\n}\n", 0)
    assert PeUnderlined("package T\n\nfunc Main() {\n    let x = @\n}\n", 0) == "@", PeUnderlined("package T\n\nfunc Main() {\n    let x = @\n}\n", 0)
    assert PeUnderlined("package T\n\nfunc Main() {\n    let x = @\n}\n", 0).Trim() != ""
}

// Successor to Span_NL102_ExpectedToken_UnderlinesParameterName.
test "020 slice 16: NL102 underlines the parameter name" {
    assert PeCensus("package T\n\nfunc greet(name string) {\n    return name\n}\n") == "NL102@3:12+4;", PeCensus("package T\n\nfunc greet(name string) {\n    return name\n}\n")
    assert PeRow("package T\n\nfunc greet(name string) {\n    return name\n}\n", 0) == "NL102@3:12+4|Expected ':' after parameter name. Got 'string'|func greet(name string) {|Parameter 'name' needs a ':' before its type.|Write this parameter as `name: Type`.|{Add ':' after 'name'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("package T\n\nfunc greet(name string) {\n    return name\n}\n", 0)
    assert PeUnderlined("package T\n\nfunc greet(name string) {\n    return name\n}\n", 0) == "name", PeUnderlined("package T\n\nfunc greet(name string) {\n    return name\n}\n", 0)
    assert PeUnderlined("package T\n\nfunc greet(name string) {\n    return name\n}\n", 0).Trim() != ""
}

// Successor to Span_NL104_UnexpectedEndOfFile_UnderlinesLastVisibleOwner, which also asserted that
// the message does NOT contain `''` (an empty quoted token) and DOES contain 'end of the file'.
// The whole-message pin answers both, and it is stronger: it fixes which construct was expected
// ('Expected '{'').
test "020 slice 16: NL104 underlines the last VISIBLE owner, never the empty EOF position" {
    assert PeCensus("package T\n\nclass Foo") == "NL104@3:7+3;", PeCensus("package T\n\nclass Foo")
    assert PeRow("package T\n\nclass Foo", 0) == "NL104@3:7+3|Expected '{' but reached the end of the file|class Foo|I was expecting '{' here, but the file ended first.|Finish this construct before the end of the file.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL104", PeRow("package T\n\nclass Foo", 0)
    assert PeUnderlined("package T\n\nclass Foo", 0) == "Foo", PeUnderlined("package T\n\nclass Foo", 0)
    assert PeUnderlined("package T\n\nclass Foo", 0).Trim() != ""
}

// Successor to Span_NL104_UnexpectedEndOfFile_MissingIdentifier_UnderlinesKeyword. Same code, a
// different message, and the recovered declaration is an `<error>`-named bodiless function.
test "020 slice 16: NL104 after a bare `func` underlines the keyword" {
    assert PeCensus("package T\n\nfunc") == "NL104@3:1+4;", PeCensus("package T\n\nfunc")
    assert PeRow("package T\n\nfunc", 0) == "NL104@3:1+4|Expected function name, but reached the end of the file|func|I was expecting an identifier here, but the file ended first.|Finish this construct before the end of the file.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL104", PeRow("package T\n\nfunc", 0)
    assert PeUnderlined("package T\n\nfunc", 0) == "func", PeUnderlined("package T\n\nfunc", 0)
    assert PeUnderlined("package T\n\nfunc", 0).Trim() != ""
}

// Successor to Span_NL105_InvalidLiteral_UnderlinesUnterminatedString.
test "020 slice 16: NL105 underlines the opening quote and its text" {
    assert PeCensus("package T\n\nfunc Main() {\n    name := \"Ada\n}\n") == "NL105@4:13+4;", PeCensus("package T\n\nfunc Main() {\n    name := \"Ada\n}\n")
    assert PeRow("package T\n\nfunc Main() {\n    name := \"Ada\n}\n", 0) == "NL105@4:13+4|Unterminated string literal|    name := \"Ada|This string starts with a quote but reaches the end of the line before a closing quote.|Add the closing quote on this line, or use a triple-quoted string for multi-line text.|{Add a closing quote}{Use triple quotes for multi-line strings}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow("package T\n\nfunc Main() {\n    name := \"Ada\n}\n", 0)
    assert PeUnderlined("package T\n\nfunc Main() {\n    name := \"Ada\n}\n", 0) == "\"Ada", PeUnderlined("package T\n\nfunc Main() {\n    name := \"Ada\n}\n", 0)
    assert PeUnderlined("package T\n\nfunc Main() {\n    name := \"Ada\n}\n", 0).Trim() != ""
}

// Successor to Span_NL106_MissingClosingBrace_UnderlinesFunctionName.
test "020 slice 16: NL106 underlines the function name" {
    assert PeCensus("func Main() {\n    print \"hi\"\n") == "NL106@1:6+4;", PeCensus("func Main() {\n    print \"hi\"\n")
    assert PeRow("func Main() {\n    print \"hi\"\n", 0) == "NL106@1:6+4|Missing closing '}'|func Main() {|The block that started on line 1 is missing its closing brace. I reached the end of the file without finding it.|Add a '}' to close this block.|<null>|https://schneidenbach.github.io/nsharplang/docs/errors/NL106", PeRow("func Main() {\n    print \"hi\"\n", 0)
    assert PeUnderlined("func Main() {\n    print \"hi\"\n", 0) == "Main", PeUnderlined("func Main() {\n    print \"hi\"\n", 0)
    assert PeUnderlined("func Main() {\n    print \"hi\"\n", 0).Trim() != ""
}

// Successor to Span_NL107_MissingClosingParen_UnderlinesCallOwner.
test "020 slice 16: NL107 underlines the call owner" {
    assert PeCensus("func Main() {\n    print(\"hello\"\n}\n") == "NL107@2:5+5;", PeCensus("func Main() {\n    print(\"hello\"\n}\n")
    assert PeRow("func Main() {\n    print(\"hello\"\n}\n", 0) == "NL107@2:5+5|Missing closing ')'|    print(\"hello\"|I reached the next line while looking for the closing ')' that matches an earlier '('.|Every opening parenthesis '(' needs a matching closing parenthesis ')'.|{Add ')' before starting the next line}{Check the matching '(' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL107", PeRow("func Main() {\n    print(\"hello\"\n}\n", 0)
    assert PeUnderlined("func Main() {\n    print(\"hello\"\n}\n", 0) == "print", PeUnderlined("func Main() {\n    print(\"hello\"\n}\n", 0)
    assert PeUnderlined("func Main() {\n    print(\"hello\"\n}\n", 0).Trim() != ""
}

// Successor to Span_NL108_MissingClosingBracket_UnderlinesAssignedVariable.
test "020 slice 16: NL108 underlines the assigned variable" {
    assert PeCensus("func Main() {\n    nums := [1, 2\n    print nums\n}\n") == "NL108@2:5+4;", PeCensus("func Main() {\n    nums := [1, 2\n    print nums\n}\n")
    assert PeRow("func Main() {\n    nums := [1, 2\n    print nums\n}\n", 0) == "NL108@2:5+4|Missing closing ']'|    nums := [1, 2|I reached the next line while looking for the closing ']' that matches an earlier '['.|Every opening bracket '[' needs a matching closing bracket ']'.|{Add ']' before starting the next line}{Check the matching '[' in this expression}|https://schneidenbach.github.io/nsharplang/docs/errors/NL108", PeRow("func Main() {\n    nums := [1, 2\n    print nums\n}\n", 0)
    assert PeUnderlined("func Main() {\n    nums := [1, 2\n    print nums\n}\n", 0) == "nums", PeUnderlined("func Main() {\n    nums := [1, 2\n    print nums\n}\n", 0)
    assert PeUnderlined("func Main() {\n    nums := [1, 2\n    print nums\n}\n", 0).Trim() != ""
}

// The shared helper's last claim, applied to the whole NL101-NL108 table at once rather than to
// one code at a time: `Assert.False(string.IsNullOrWhiteSpace(underlined))`. Eight codes, eight
// sources, and none of them may point at whitespace or past the end of its line — an over-long
// span would render as `<over-long-span>` here.
test "020 slice 16: every corpus span underlines a visible, non-whitespace token" {
    sources := new List<string>()
    sources.Add("package T\n\nfunc Main() {\n    let x = @\n}\n")
    sources.Add("package T\n\nfunc greet(name string) {\n    return name\n}\n")
    sources.Add("package T\n\nclass Foo")
    sources.Add("package T\n\nfunc")
    sources.Add("package T\n\nfunc Main() {\n    name := \"Ada\n}\n")
    sources.Add("func Main() {\n    print \"hi\"\n")
    sources.Add("func Main() {\n    print(\"hello\"\n}\n")
    sources.Add("func Main() {\n    nums := [1, 2\n    print nums\n}\n")
    assert sources.Count == 8
    index := 0
    while index < sources.Count {
        underlined := PeUnderlined(sources[index], 0)
        assert underlined != "<over-long-span>", underlined
        assert underlined != "<null-snippet>", underlined
        assert underlined.Trim() == underlined, underlined
        assert underlined.Length > 0, underlined
        index = index + 1
    }
}

// ══ THE MALFORMED TABLE-DRIVEN ROWS ══════════════════════════════════════════════════════════
//
// Successors to the three `[InlineData]` rows of Parser_MalformedTableDrivenTest_TerminatesWithErrors,
// a named regression guard for a no-progress bug that HUNG the parser. Two of the three already
// have full-field contracts in `ColumnarParserRecovery.tests.nl` ("016 test-dsl: an untyped table
// header before a bare / bracketed row value terminates on the parameter-':' NL102"), written when
// those shapes were found to hang; they are restated here through `ParseFileAst` with their
// recovered trees, because the sorted entry point cannot show that `TestDeclaration` survives. The
// THIRD row had no estate contract at all.

// The tree is what the sorted-entry sibling cannot state: a `TestDeclaration` survives the
// guard, so the parser bailed out of the row loop rather than out of the declaration.
test "020 slice 16: an untyped table header before a bare row value terminates with one NL102" {
    assert !PeParse("test \"d\" with (a) 9 { }").Success
    assert PeCensus("test \"d\" with (a) 9 { }") == "NL102@1:16+1;", PeCensus("test \"d\" with (a) 9 { }")
    assert PeRow("test \"d\" with (a) 9 { }", 0) == "NL102@1:16+1|Expected ':' after parameter name. Got ')'|test \"d\" with (a) 9 { }|Parameter 'a' needs a ':' before its type.|Write this parameter as `a: Type`.|{Add ':' after 'a'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("test \"d\" with (a) 9 { }", 0)
    assert PeDecls("test \"d\" with (a) 9 { }") == "TestDeclaration[]", PeDecls("test \"d\" with (a) 9 { }")
}

test "020 slice 16: an untyped table header before a bracketed row value terminates with one NL102" {
    assert !PeParse("test \"d\" with (a) [ 9 ] { }").Success
    assert PeCensus("test \"d\" with (a) [ 9 ] { }") == "NL102@1:16+1;", PeCensus("test \"d\" with (a) [ 9 ] { }")
    assert PeRow("test \"d\" with (a) [ 9 ] { }", 0) == "NL102@1:16+1|Expected ':' after parameter name. Got ')'|test \"d\" with (a) [ 9 ] { }|Parameter 'a' needs a ':' before its type.|Write this parameter as `a: Type`.|{Add ':' after 'a'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("test \"d\" with (a) [ 9 ] { }", 0)
    assert PeDecls("test \"d\" with (a) [ 9 ] { }") == "TestDeclaration[]", PeDecls("test \"d\" with (a) [ 9 ] { }")
}

// THE ROW WITH NO ESTATE CONTRACT ANYWHERE. Four diagnostics — the parameter-':' NL102 plus three
// top-level NL101s for `]`, `{` and `}` — and three `<error>` classes beside the surviving
// `TestDeclaration`. The deleted C# asserted `Assert.False(Success)` and `Assert.NotEmpty(Errors)`.
// WHAT IS NOT REPRODUCED HERE, AND IT IS MEASURED, NOT ASSUMED: the deleted theory wrapped the
// parse in `Task.Run` and failed after a ten-second `Wait`, so a lost no-progress guard failed
// fast. `Task.Run`, `Stopwatch` and `Environment.TickCount64` all decline to emit in this estate,
// so no wall-clock bound is expressible; a regression here would hang the run instead of failing
// it. This is the first concrete consumer of the whole-run-timeout capability on task 020's list.
test "020 slice 16: a mismatched brace inside a bracketed row reports four diagnostics and terminates" {
    assert !PeParse("test \"d\" with (a) [ (9 } ] { }").Success
    assert PeCensus("test \"d\" with (a) [ (9 } ] { }") == "NL102@1:16+1;NL101@1:26+1;NL101@1:28+1;NL101@1:30+1;", PeCensus("test \"d\" with (a) [ (9 } ] { }")
    assert PeRow("test \"d\" with (a) [ (9 } ] { }", 0) == "NL102@1:16+1|Expected ':' after parameter name. Got ')'|test \"d\" with (a) [ (9 } ] { }|Parameter 'a' needs a ':' before its type.|Write this parameter as `a: Type`.|{Add ':' after 'a'}|https://schneidenbach.github.io/nsharplang/docs/errors/NL102", PeRow("test \"d\" with (a) [ (9 } ] { }", 0)
    assert PeDecls("test \"d\" with (a) [ (9 } ] { }") == "TestDeclaration[]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]", PeDecls("test \"d\" with (a) [ (9 } ] { }")
}

// A control for the order contract above: where a source's diagnostics are already in position
// order, the two entry points must agree exactly. Two of the three rows have a single diagnostic
// and the third has four that happen to be in position order, so all three agree — which is what
// makes the cascading source's DISAGREEMENT above a real finding and not an artifact of the kernel.
test "020 slice 16: the three malformed table rows agree with the sorted entry point" {
    assert PeSortedCensus("test \"d\" with (a) [ (9 } ] { }") == "NL102@1:16+1;NL101@1:26+1;NL101@1:28+1;NL101@1:30+1;", PeSortedCensus("test \"d\" with (a) [ (9 } ] { }")
    assert PeCensus("test \"d\" with (a) [ (9 } ] { }") == PeSortedCensus("test \"d\" with (a) [ (9 } ] { }")
    assert PeCensus("test \"d\" with (a) 9 { }") == PeSortedCensus("test \"d\" with (a) 9 { }")
    assert PeCensus("test \"d\" with (a) [ 9 ] { }") == PeSortedCensus("test \"d\" with (a) [ 9 ] { }")
}

// ── NL105: a backslash that starts no escape ────────────────────────────────────────────────────
//
// THE DEFECT THIS CLOSES: an unrecognised escape was passed through as literal text, silently, so
// `"\x1b[1;31m"` was ten characters of garbage that every gate accepted — and it shipped, on every
// coloured diagnostic line the compiler wrote. `\x`, `\u`, `\U` and `\e` are escapes now; a
// backslash that still starts none of them is refused HERE, at the backslash, rather than
// reinterpreted.
//
// The marker is TWO characters — the backslash and what follows it — because those are the two the
// author has to change. `PeUnderlined` proves that against the snippet rather than trusting the
// arithmetic.

test "NL105 refuses an unrecognised escape at the backslash, not at the literal" {
    source := "func test() {\n    name := \"a\\qb\"\n}\n"
    assert PeCensus(source) == "NL105@2:15+2;", PeCensus(source)
    assert PeUnderlined(source, 0) == "\\q", PeUnderlined(source, 0)
    assert PeRow(source, 0) == "NL105@2:15+2|Unrecognised escape sequence `\\\\q`|    name := \"a\\\\qb\"|`\\\\q` is not an escape sequence in N#, so I cannot tell what character you meant here.|N# knows `\\\\0 \\\\a \\\\b \\\\e \\\\f \\\\n \\\\r \\\\t \\\\v \\\\' \\\\\" \\\\\\\\`, plus `\\\\xH..HHHH`, `\\\\uHHHH` and `\\\\UHHHHHHHH`.|{Write `\\\\\\\\q` for a literal backslash followed by `q`}{Use a triple-quoted `\"\"\"...\"\"\"` string, where no backslash is an escape}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow(source, 0)
}

test "NL105 names the WIDTH for a hex escape, because a short run is a different mistake" {
    // `\u041` is three digits where four are required. Telling this author "N# has no `\u`" would
    // be a lie, so the hint is about the width and the neighbouring escapes that take fewer digits.
    shortU := "func test() {\n    name := \"\\u041\"\n}\n"
    assert PeCensus(shortU) == "NL105@2:14+2;", PeCensus(shortU)
    assert PeRow(shortU, 0) == "NL105@2:14+2|Unrecognised escape sequence `\\\\u`|    name := \"\\\\u041\"|`\\\\u` is not an escape sequence in N#, so I cannot tell what character you meant here.|`\\\\u` needs EXACTLY four hex digits, as in `\\\\u001b`.|{Write `\\\\uHHHH` with exactly four hex digits}{Use `\\\\xH` to `\\\\xHHHH` when you have fewer digits}{Use `\\\\UHHHHHHHH` for a code point above U+FFFF}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow(shortU, 0)

    bareX := "func test() {\n    name := \"\\x\"\n}\n"
    assert PeCensus(bareX) == "NL105@2:14+2;", PeCensus(bareX)
    assert PeRow(bareX, 0) == "NL105@2:14+2|Unrecognised escape sequence `\\\\x`|    name := \"\\\\x\"|`\\\\x` is not an escape sequence in N#, so I cannot tell what character you meant here.|`\\\\x` needs one to four HEX digits after it, as in `\\\\x1b`.|{Write `\\\\xH` to `\\\\xHHHH` with one to four hex digits}{Use `\\\\e` when you mean the escape character}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow(bareX, 0)

    // `\U` past the last plane is a real code-point refusal, not a width one.
    bigU := "func test() {\n    name := \"\\U00110000\"\n}\n"
    assert PeCensus(bigU) == "NL105@2:14+2;", PeCensus(bigU)
    assert PeRow(bigU, 0) == "NL105@2:14+2|Unrecognised escape sequence `\\\\U`|    name := \"\\\\U00110000\"|`\\\\U` is not an escape sequence in N#, so I cannot tell what character you meant here.|`\\\\U` needs EXACTLY eight hex digits and a real code point, as in `\\\\U0001F600` — a lone surrogate and anything above U+10FFFF are refused.|{Write `\\\\UHHHHHHHH` with exactly eight hex digits}{Use `\\\\uHHHH` for a code point in the basic plane}|https://schneidenbach.github.io/nsharplang/docs/errors/NL105", PeRow(bigU, 0)
}

test "NL105 reports ONCE per literal, however many bad escapes it holds" {
    // A Windows path written with single backslashes would otherwise bury the file in identical
    // sentences, and the fix for the first is the fix for all of them.
    //
    // THE COLUMN IS THE FINDING. `C:\temp` reports at the `\q`, column 21, NOT at the `\t` in
    // column 16 — because `\t` IS a valid escape and that path has already silently become
    // `C:<tab>emp`. The diagnostic cannot save this author from the tab; it can only refuse the
    // escape that does not exist. That is the argument for the doubled backslash in the hint.
    source := "func test() {\n    name := \"C:\\temp\\qux\\zap\"\n}\n"
    assert PeCensus(source) == "NL105@2:21+2;", PeCensus(source)
}

test "every escape the table owns passes NL105 in one literal, and a raw literal is exempt" {
    // The whole family in a single string: nothing is reported.
    all := "func test() {\n    name := \"\\0\\a\\b\\e\\f\\n\\r\\t\\v\\'\\\"\\\\\\x1b\\x4\\u0041\\U0001F600\"\n}\n"
    assert PeCensus(all) == "", PeCensus(all)

    // A raw literal has no escapes at all, so a lone backslash in one is ordinary text. The check
    // keys on the TOKEN TYPE: the lexer does not keep the `\"\"\"` delimiters, so a value-shape test
    // would answer false for every raw literal and report on all of them.
    raw := "func test() {\n    name := \"\"\"a \\q b\"\"\"\n}\n"
    assert PeCensus(raw) == "", PeCensus(raw)
}

test "NL105 reaches a CHAR literal too, which is the other caller of the escape table" {
    source := "func test() {\n    c := '\\q'\n}\n"
    assert PeCensus(source) == "NL105@2:11+2;", PeCensus(source)
    assert PeUnderlined(source, 0) == "\\q", PeUnderlined(source, 0)
}

test "an unterminated literal still reports its OWN diagnostic first, not an escape one" {
    // `ReportMalformedStringLiteralIfNeeded` runs first and the escape check must not displace it:
    // the author's problem is the missing quote, not the backslash.
    source := "func test() {\n    name := \"Ada\\q\n}\n"
    assert PeCensus(source).StartsWith("NL105@2:13"), PeCensus(source)
}
