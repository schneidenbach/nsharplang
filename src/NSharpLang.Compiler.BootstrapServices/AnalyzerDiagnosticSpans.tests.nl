namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Native contracts for the diagnostic span resolver.
//
// Every member behind these was `private` in Analyzer.cs, so nothing named any of them: where a
// semantic diagnostic POINTS was pinned only indirectly, through end-to-end LSP squiggle tests. This
// is its first DIRECT pinning, and it goes at the decisions a reader would guess wrong:
//
//   * a literal's width comes from its LEXEME where the lexeme is faithful (an integer, `true`,
//     `null`) and from the SOURCE TEXT where it is not (an escaped string is shorter than what the
//     reader typed);
//   * a member access reports on the member NAME, located by searching the line — and the fallback
//     column steps 1 past `.` but 2 past `?.`;
//   * a stable dotted PATH widens the span to the whole path, and the search runs FORWARD from the
//     expression's start so a line mentioning `a.b` twice underlines the right one;
//   * `TryGetStableNullPath` is the gate for that widening, and a null-conditional hop or a parser
//     error placeholder closes it;
//   * a token scan stops at `,` `)` `]` `}` — but NOT at `(` or `[`;
//   * the same expression spans DIFFERENTLY in statement position, where the finding is about the
//     whole written statement rather than one token;
//   * a multi-line `SourceSpan` is REFUSED as a span, because one underlined run cannot render it.

func SpanSource(): string {
    return "package probe\n"
        + "func main() {\n"
        + "    total := customer.Account.Balance\n"
        + "    name := \"he said \\\"hi\\\" ok\"\n"
        + "    values := [1, 2, 3]\n"
        + "    Compute(alpha,beta) ok\n"
        + "    a.b = a.b\n"
        + "}\n"
}

func SpanResolver(): AnalyzerDiagnosticSpans {
    sink := new AnalyzerDiagnosticSink(new List<CompilerError>(), new AnalyzerProjectSourceProvider())
    sink.BeginAnalysis("/probe/main.nl", SpanSource())
    return new AnalyzerDiagnosticSpans(sink)
}

// A resolver with NO source text: every text-backed answer has to fall back rather than throw.
func SpanResolverWithoutText(): AnalyzerDiagnosticSpans {
    sink := new AnalyzerDiagnosticSink(new List<CompilerError>(), new AnalyzerProjectSourceProvider())
    sink.BeginAnalysis(null, null)
    return new AnalyzerDiagnosticSpans(sink)
}

func SpanText(span: DiagnosticSpan): string {
    return span.Line.ToString() + "|" + span.Column.ToString() + "|" + span.Length.ToString()
}

func SpanIdentifier(name: string, line: int, column: int): Expression {
    return new IdentifierExpression(name, line, column)
}

// `customer.Account.Balance` on line 3, with the parser's positions at the dots.
func SpanBalancePath(): MemberAccessExpression {
    receiver: Expression = SpanIdentifier("customer", 3, 14)
    account: Expression = new MemberAccessExpression(receiver, "Account", false, 3, 22)
    return new MemberAccessExpression(account, "Balance", false, 3, 30)
}

test "a literal's width comes from its lexeme where the lexeme is faithful" {
    spans := SpanResolver()

    assert SpanText(spans.GetExpressionDiagnosticSpan(new IntLiteralExpression("12345", 5, 16))) == "5|16|5"
    assert SpanText(spans.GetExpressionDiagnosticSpan(new FloatLiteralExpression("1.25", 5, 16))) == "5|16|4"
    assert SpanText(spans.GetExpressionDiagnosticSpan(new BoolLiteralExpression(true, 5, 16))) == "5|16|4"
    assert SpanText(spans.GetExpressionDiagnosticSpan(new BoolLiteralExpression(false, 5, 16))) == "5|16|5"
    assert SpanText(spans.GetExpressionDiagnosticSpan(new NullLiteralExpression(5, 16))) == "5|16|4"
    assert SpanText(spans.GetExpressionDiagnosticSpan(new ThisExpression(5, 16))) == "5|16|4"
}

test "AN ESCAPED STRING IS MEASURED FROM THE SOURCE, NOT FROM ITS VALUE" {
    // `"he said \"hi\" ok"` occupies 19 characters on line 4 from column 13, while the decoded
    // value is 15. Using the lexeme would underline four characters too few and stop mid-token.
    spans := SpanResolver()
    literal := new StringLiteralExpression("he said \"hi\" ok", 4, 13)

    assert literal.Value.Length == 15
    assert SpanText(spans.GetExpressionDiagnosticSpan(literal)) == "4|13|19"
}

test "a member access reports on the member name, located in the line" {
    spans := SpanResolver()
    account: Expression = new MemberAccessExpression(SpanIdentifier("customer", 3, 14), "Account", false, 3, 22)

    // The node's own column is the dot at 22; `Account` starts at 23.
    assert spans.GetMemberNameColumn(account as MemberAccessExpression) == 23
}

test "THE MEMBER-COLUMN FALLBACK STEPS ONE PAST `.` AND TWO PAST `?.`" {
    // Without source text there is nothing to search, so the operator width IS the answer, and the
    // two operators are not the same width.
    spans := SpanResolverWithoutText()
    plain := new MemberAccessExpression(SpanIdentifier("obj", 9, 5), "Member", false, 9, 8)
    conditional := new MemberAccessExpression(SpanIdentifier("obj", 9, 5), "Member", true, 9, 8)

    assert spans.GetMemberNameColumn(plain) == 9
    assert spans.GetMemberNameColumn(conditional) == 10
}

test "A STABLE DOTTED PATH WIDENS THE SPAN TO THE WHOLE PATH" {
    // `customer.Account.Balance` is 24 characters from column 14. Reporting on `Balance` alone
    // would underline 7 characters at column 31 and lose the receiver the finding is about.
    spans := SpanResolver()

    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(SpanBalancePath()) == "customer.Account.Balance"
    assert SpanText(spans.GetExpressionDiagnosticSpan(SpanBalancePath())) == "3|14|24"
}

test "a null-conditional hop or an error placeholder closes the stable path" {
    conditional := new MemberAccessExpression(SpanIdentifier("customer", 3, 14), "Account", true, 3, 22)
    errorReceiver := new MemberAccessExpression(SpanIdentifier("<error>", 3, 14), "Account", false, 3, 22)
    overCall: Expression = new CallExpression(SpanIdentifier("f", 3, 14), new List<Argument>(), null, 3, 14)

    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(conditional) == null
    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(errorReceiver) == null
    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(
        new MemberAccessExpression(overCall, "X", false, 3, 20)) == null
    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(new ThisExpression(3, 14)) == "this"
    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(
        new ParenthesizedExpression(new ThisExpression(3, 15), 3, 14)) == "this"
}

test "A PATH WRITTEN TWICE ON ONE LINE UNDERLINES THE OCCURRENCE THIS EXPRESSION IS" {
    // Line 7 is `    a.b = a.b`. The SECOND `a.b` starts at column 11; searching from the start of
    // the line would report the first one for both.
    spans := SpanResolver()
    second: Expression = new MemberAccessExpression(SpanIdentifier("a", 7, 11), "b", false, 7, 12)

    assert SpanText(spans.GetStablePathDiagnosticSpan(second, "a.b", 7, 12)) == "7|11|3"
    assert SpanText(spans.GetStablePathDiagnosticSpan(
        new MemberAccessExpression(SpanIdentifier("a", 7, 5), "b", false, 7, 6), "a.b", 7, 6)) == "7|5|3"
}

test "a path the line does not contain still reports, at the expression's start" {
    spans := SpanResolver()

    assert SpanText(spans.GetStablePathDiagnosticSpan(SpanIdentifier("zzz", 7, 5), "zzz.qqq", 7, 5)) == "7|5|7"
}

test "THE TOKEN SCAN STOPS AT `,` `)` `]` `}` BUT NOT AT `(` OR `[`" {
    // Line 6 is `    Compute(alpha,beta) ok`. From `Compute` the scan runs THROUGH the `(` — the
    // callee and its open paren are one token for this purpose (13 characters) — while `alpha`
    // stops at the comma, and a scan STARTING on `)` collapses to one.
    spans := SpanResolver()

    assert spans.GetTokenLength(6, 5) == 13
    assert spans.GetTokenLength(6, 13) == 5
    assert spans.GetTokenLength(6, 23) == 1
}

test "a quoted token is measured whole, honouring escapes, and an interpolation keeps its `$`" {
    assert AnalyzerDiagnosticSpanFacts.ScanQuotedTokenLength("\"abc\"", 0, '"') == 5
    assert AnalyzerDiagnosticSpanFacts.ScanQuotedTokenLength("\"esc\\\"aped\"", 0, '"') == 11
    // An UNTERMINATED quote runs to the end of the line rather than collapsing to one character.
    assert AnalyzerDiagnosticSpanFacts.ScanQuotedTokenLength("\"unterminated", 0, '"') == 13
    assert AnalyzerDiagnosticSpanFacts.ScanQuotedTokenLength("", 0, '"') == 1
}

test "without source text every text-backed length falls back to one" {
    spans := SpanResolverWithoutText()

    assert spans.GetTokenLength(3, 5) == 1
    assert spans.GetExpressionLength(3, 5) == 1
    assert spans.GetDelimitedPatternLength(5, 15, '[', ']') == 1
    // An out-of-range position is the same answer as no text at all.
    assert spans.GetTokenLength(0, 5) == 1
}

test "THE SAME EXPRESSION SPANS DIFFERENTLY IN STATEMENT POSITION" {
    // In value position an unnamed form measures ONE token; in statement position the finding is
    // "this statement has no effect", so it runs to the end of the written line.
    spans := SpanResolver()
    literal: Expression = new IntLiteralExpression("1", 6, 5)

    assert SpanText(spans.GetExpressionDiagnosticSpan(literal)) == "6|5|1"
    assert SpanText(spans.GetExpressionStatementDiagnosticSpan(
        new BinaryExpression(literal, BinaryOperator.Add, literal, 6, 5))) == "6|5|22"
}

test "a statement reports through its own shape" {
    spans := SpanResolver()

    assert SpanText(spans.GetStatementDiagnosticSpan(
        new ExpressionStatement(SpanIdentifier("total", 3, 5), 3, 5))) == "3|5|5"
    assert SpanText(spans.GetStatementDiagnosticSpan(
        new VariableDeclarationStatement("total", null, null, VariableKind.Let, 3, 5))) == "3|5|5"
    assert SpanText(AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(
        new VariableDeclarationStatement("", null, null, VariableKind.Let, 3, 5))) == "3|5|1"
}

test "a wrong binary operand reports on that operand; both wrong reports on the operator" {
    spans := SpanResolver()
    left: Expression = SpanIdentifier("alpha", 6, 13)
    right: Expression = SpanIdentifier("beta", 6, 19)
    binary := new BinaryExpression(left, BinaryOperator.Add, right, 6, 17)

    assert SpanText(spans.GetBinaryOperandDiagnosticSpan(binary, true, false)) == "6|13|5"
    assert SpanText(spans.GetBinaryOperandDiagnosticSpan(binary, false, true)) == "6|19|4"
    assert SpanText(spans.GetBinaryOperandDiagnosticSpan(binary, true, true)) == "6|17|1"
    assert SpanText(spans.GetBinaryOperandDiagnosticSpan(binary, false, false)) == "6|17|1"
    assert SpanText(AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(binary)) == "6|17|1"
}

test "A MULTI-LINE SOURCE SPAN IS REFUSED, AND THE CALLER'S FALLBACK LENGTH STANDS" {
    // One underlined run cannot render a span that crosses lines, so the anchor falls back — and
    // the fallback LENGTH is the caller's, because only the caller knows what the finding is about.
    oneLine := new SourceSpan(2, 5, 2, 11)
    crossing := new SourceSpan(2, 5, 3, 11)

    assert SpanText(AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(oneLine, 8, 3, 6)) == "2|5|6"
    assert SpanText(AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(crossing, 8, 3, 6)) == "8|3|6"
    assert SpanText(AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(SourceSpan.None, 8, 3, 0)) == "8|3|1"
}

test "a call reports on its callee's written name, or on the display name when it has none" {
    spans := SpanResolver()
    named := new CallExpression(SpanIdentifier("Compute", 6, 5), new List<Argument>(), null, 6, 5)
    through := new CallExpression(new IntLiteralExpression("7", 6, 5), new List<Argument>(), null, 6, 5)

    assert SpanText(spans.GetCallDiagnosticSpan(named, "ignored")) == "6|5|7"
    assert SpanText(spans.GetCallDiagnosticSpan(through, "Compute")) == "6|5|7"
    assert SpanText(spans.GetCallDiagnosticSpan(through, "")) == "6|5|1"
}

test "A LIST PATTERN UNDERLINES THE WHOLE BRACKETED GROUP" {
    // Line 5 is `    values := [1, 2, 3]` — the group is 9 characters from column 15. Measuring a
    // token would stop at the `[`.
    spans := SpanResolver()

    assert SpanText(spans.GetListPatternDiagnosticSpan(new ListPattern(new List<Pattern>(), 5, 15))) == "5|15|9"
    // A position that is NOT the opening delimiter falls back to a token measure.
    assert spans.GetDelimitedPatternLength(5, 5, '[', ']') == 6
}

test "a pattern reports on the name it introduces or matches" {
    spans := SpanResolver()

    assert SpanText(spans.GetPatternNameDiagnosticSpan(new IdentifierPattern("alpha", 6, 13))) == "6|13|5"
    assert SpanText(spans.GetPatternNameDiagnosticSpan(new UnionCasePattern("Some", null, 6, 13))) == "6|13|4"
    assert SpanText(spans.GetPatternNameDiagnosticSpan(
        new TypePattern(new SimpleTypeReference("string", 6, 13), null, 6, 13))) == "6|13|6"
    assert spans.GetTypePatternNameLength(
        new TypePattern(new GenericTypeReference("List", new List<TypeReference>(), 6, 13), null, 6, 13)) == 4
}

test "A PROPERTY PATTERN WITH NO POSITION IS ANCHORED ON ITS ENCLOSING PATTERN" {
    spans := SpanResolver()

    assert SpanText(spans.GetPropertyPatternNameDiagnosticSpan(
        new PropertyPattern("Name", null, null, 6, 13), 9, 7)) == "6|13|4"
    assert SpanText(spans.GetPropertyPatternNameDiagnosticSpan(
        new PropertyPattern("Name", null, null, 0, 0), 9, 7)) == "9|7|4"
    // The parser's error placeholder measures the TOKEN, not the placeholder's own seven characters.
    assert SpanText(spans.GetPropertyPatternNameDiagnosticSpan(
        new PropertyPattern("<error>", null, null, 6, 5), 9, 7)) == "6|5|13"
}

test "AN `is` EXPRESSION UNDERLINES THE KEYWORD THROUGH THE TESTED TYPE NAME" {
    // Line 3 is `    total := customer.Account.Balance`. Anchored at column 5, the scan skips
    // `to`, then whitespace is absent so the type run is `tal` — the point is that the span is
    // keyword-through-type, not the two-character keyword.
    resolver := SpanResolver()
    typed := new IsExpression(SpanIdentifier("v", 6, 5), new SimpleTypeReference("string", 6, 5), null, 6, 5)

    // `Compute(alpha,beta)` from column 5: `Co` is the keyword slot, `mpute(alpha` scans as a type
    // run because `(` is not a type-name character — the run stops there.
    assert SpanText(resolver.GetIsExpressionDiagnosticSpan(typed)) == "6|5|7"
    // Without text, and past the end of the line, the keyword alone stands.
    assert SpanText(SpanResolverWithoutText().GetIsExpressionDiagnosticSpan(typed)) == "6|5|2"
    assert SpanText(resolver.GetIsExpressionDiagnosticSpan(
        new IsExpression(SpanIdentifier("v", 6, 400), new SimpleTypeReference("string", 6, 400), null, 6, 400))) == "6|400|2"
}

test "a function reports on its name, and a nameless one measures its token" {
    spans := SpanResolver()

    assert SpanText(spans.GetFunctionNameDiagnosticSpan(SpanFunction("Compute", 6, 3))) == "6|5|7"
    assert SpanText(spans.GetFunctionNameDiagnosticSpan(SpanFunction("<error>", 6, 5))) == "6|5|13"
    assert SpanText(spans.GetFunctionNameDiagnosticSpan(SpanFunction("", 6, 5))) == "6|5|13"
}

func SpanFunction(name: string, line: int, column: int): FunctionDeclaration {
    return new FunctionDeclaration(
        name,
        new List<Parameter>(),
        null,
        null,
        null,
        null,
        null,
        Modifiers.None,
        new List<AttributeNode>(),
        false,
        null,
        false,
        false,
        line,
        column)
}

test "AN ASSIGNMENT TARGET NEVER WIDENS TO A STABLE PATH" {
    // The general expression span widens `a.b` to the whole path; an assignment diagnostic is about
    // the member being WRITTEN, so it stays on the member name. Same node, two different answers.
    spans := SpanResolver()
    target: Expression = new MemberAccessExpression(SpanIdentifier("a", 7, 5), "b", false, 7, 6)

    assert SpanText(spans.GetExpressionDiagnosticSpan(target)) == "7|5|3"
    assert SpanText(spans.GetAssignmentTargetNameDiagnosticSpan(target, 7, 5)) == "7|7|1"
    assert SpanText(spans.GetAssignmentTargetNameDiagnosticSpan(
        new ParenthesizedExpression(target, 7, 4), 7, 5)) == "7|7|1"
    assert SpanText(spans.GetAssignmentTargetNameDiagnosticSpan(
        new IntLiteralExpression("1", 7, 5), 6, 5)) == "6|5|13"
}

test "a null receiver quotes its path, but the `this value` describer is not searchable text" {
    spans := SpanResolver()
    receiver: Expression = new MemberAccessExpression(SpanIdentifier("a", 7, 5), "b", false, 7, 6)

    assert SpanText(spans.GetNullReceiverDiagnosticSpan(receiver, "a.b", 7, 6)) == "7|5|3"
    assert SpanText(spans.GetNullReceiverDiagnosticSpan(receiver, "this value", 7, 6)) == "7|5|3"
    assert SpanText(spans.GetNullReceiverDiagnosticSpan(
        new ThisExpression(7, 5), "this value", 7, 5)) == "7|5|4"
}

test "the expression START is the leftmost written character, not the node's operator position" {
    line := 0
    column := 0
    AnalyzerDiagnosticSpanFacts.GetExpressionStartPosition(SpanBalancePath(), 11, 13, out line, out column)
    assert line == 3
    assert column == 14

    AnalyzerDiagnosticSpanFacts.GetExpressionStartPosition(
        new IndexAccessExpression(SpanIdentifier("values", 5, 5), new IntLiteralExpression("0", 5, 12), false, 5, 11),
        11, 13, out line, out column)
    assert line == 5
    assert column == 5

    // A node with no usable position of its own takes the caller's anchor.
    AnalyzerDiagnosticSpanFacts.GetExpressionStartPosition(SpanIdentifier("x", 0, 0), 11, 13, out line, out column)
    assert line == 11
    assert column == 13
}

test "the identifier-column probe returns the caller's fallback when there is no text" {
    assert AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(null, "alpha", 2, 4) == 4
    assert AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn("alpha beta\n", "alpha", 1, 4) == 1
    assert AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn("alpha beta\n", "zzz", 1, 4) == 4
    assert SpanResolver().GetDeclarationNameColumn("   ", 3, 7) == 7
}

test "position-only span facts need no source text at all" {
    attribute := new AttributeNode("Test", new List<Argument>(), 4, 9)

    assert SpanText(AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)) == "4|9|4"
    // A fallback attribute span anchors at the top of the file rather than dropping the finding.
    assert SpanText(AnalyzerDiagnosticSpanFacts.GetAttributeFallbackDiagnosticSpan(attribute)) == "1|1|4"

    parameter := new Parameter("value", new SimpleTypeReference("int", 3, 14), null, false)
    assert SpanText(AnalyzerDiagnosticSpanFacts.GetParameterDiagnosticSpan(parameter, 6, 2)) == "6|2|5"
}

test "AN SoA COLUMN WITH NO POSITION IS ANCHORED ON ITS DECLARING RECORD" {
    positioned := new SoaColumnDeclaration("Balance", new SimpleTypeReference("int", 3, 14), 3, 14)
    floating := new SoaColumnDeclaration("Balance", new SimpleTypeReference("int", 0, 0), 0, 0)
    columns := new List<SoaColumnDeclaration>()
    columns.Add(positioned)
    soaRecord := new SoaRecordDeclaration("Rec", columns, Modifiers.None, new List<AttributeNode>(), 2, 6)

    assert SpanText(AnalyzerDiagnosticSpanFacts.GetSoaColumnNameDiagnosticSpan(positioned, soaRecord)) == "3|14|7"
    assert SpanText(AnalyzerDiagnosticSpanFacts.GetSoaColumnNameDiagnosticSpan(floating, soaRecord)) == "2|6|7"
    // The TYPE span falls back to the column's own position, underlining the NAME's width.
    assert SpanText(AnalyzerDiagnosticSpanFacts.GetSoaColumnTypeDiagnosticSpan(floating)) == "0|0|7"
}

test "AN ATTRIBUTE ARGUMENT REPORTS ON THE NAME ONLY WHEN THE ARGUMENT IS UNNAMED SYNTAX" {
    // `[Test(Skip = "x")]` parses as an unnamed argument whose VALUE is an assignment; the finding
    // is about `Skip`, so the span is the assignment's target. Once the argument carries a real
    // name, the same value shape reports on the value instead.
    spans := SpanResolver()
    assignment: Expression = new AssignmentExpression(
        SpanIdentifier("Skip", 4, 9), AssignmentOperator.Assign, new StringLiteralExpression("x", 4, 16), 4, 14)

    assert SpanText(spans.GetAttributeArgumentDiagnosticSpan(
        new Argument(null, assignment), assignment)) == "4|9|4"
    assert SpanText(spans.GetAttributeArgumentDiagnosticSpan(
        new Argument("Skip", assignment), assignment)) == "4|14|2"
    assert SpanText(spans.GetAttributeArgumentDiagnosticSpan(
        new Argument(null, SpanIdentifier("total", 3, 5)), SpanIdentifier("total", 3, 5))) == "3|5|5"
}

test "a wrapper form spans as the expression it wraps" {
    spans := SpanResolver()
    inner: Expression = SpanIdentifier("total", 3, 5)

    assert SpanText(spans.GetExpressionDiagnosticSpan(new ParenthesizedExpression(inner, 3, 4))) == "3|5|5"
    assert SpanText(spans.GetExpressionDiagnosticSpan(new CheckedExpression(inner, 3, 1))) == "3|5|5"
    assert SpanText(spans.GetExpressionDiagnosticSpan(new UncheckedExpression(inner, 3, 1))) == "3|5|5"
    assert SpanText(spans.GetExpressionDiagnosticSpan(new AllocExpression(inner, 3, 1))) == "3|5|5"
}

test "THE SPAN VALUE DECONSTRUCTS, WHICH IS WHY THE REPORTING SITES DID NOT CHANGE SHAPE" {
    line := 0
    column := 0
    length := 0
    new DiagnosticSpan(7, 13, 4).Deconstruct(out line, out column, out length)

    assert line == 7
    assert column == 13
    assert length == 4
}
