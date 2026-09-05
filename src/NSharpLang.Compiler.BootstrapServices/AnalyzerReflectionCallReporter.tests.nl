namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for WHAT THE ANALYZER SAYS WHEN A REFLECTED CALL DOES NOT BIND, and for the
// callable-reference report on the other side of the same question.
//
// All six members behind these were `private` in Analyzer.cs — nothing in `src/`, `tests/` or
// `editors/` named any of them — so their only pinning was ever end-to-end diagnostic text. These go
// at the decisions a reader cannot recover from a single arm:
//
//   * the METHOD-GROUP arm and the ordinary arm are MUTUALLY EXCLUSIVE and the probe runs first, so
//     one unbound call is exactly one report;
//   * the probe answers on the FIRST identifier argument whose symbol is an N# method group, and a
//     lambda-shaped `FunctionTypeInfo` — one with no source identity — is not one;
//   * the candidate list is capped at eight DISTINCT signatures, distinctness FIRST;
//   * the argument types are rendered in ARGUMENT order;
//   * what the failed call is CALLED is what the user wrote, and only a callee with no written name
//     falls back to the first candidate's reflected name;
//   * the rich `ErrorMessageBuilder` shape and the detail-only shape are the SAME report in the SAME
//     position — the choice is made by what the sink can supply — and the method-group arm has no
//     rich shape at all;
//   * the NL411 guard consults the EXPECTED type and nothing else, and a lambda is never unbound;
//   * the NL411 dedupe is keyed on the ANCHOR plus the reported NAME, and its log OUTLIVES the
//     reporter that reads it — which is the whole reason it is a separate owner.
func ReporterErrors(): List<CompilerError> {
    return new List<CompilerError>()
}

func ReporterScopes(): AnalyzerScopeStack {
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    return scopes
}

func ReporterOwner(errors: List<CompilerError>, scopes: AnalyzerScopeStack): AnalyzerReflectionCallReporter {
    return ReporterOwnerWith(errors, scopes, null, new AnalyzerCallableReferenceReportLog())
}

// The SAME owner over a sink that has a file path and a line of source text, which is what makes the
// RICH `ErrorMessageBuilder` shape reachable, and over a caller-supplied dedupe log, which is what
// lets a contract prove the log outlives its reader.
func ReporterOwnerWith(
    errors: List<CompilerError>,
    scopes: AnalyzerScopeStack,
    sourceText: string?,
    log: AnalyzerCallableReferenceReportLog
): AnalyzerReflectionCallReporter {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    provider := new AnalyzerProjectSourceProvider()
    sink := new AnalyzerDiagnosticSink(errors, provider)
    facts := new AnalyzerAssignabilityFacts(context, null)
    spans := new AnalyzerDiagnosticSpans(sink)
    if sourceText != null {
        sink.BeginAnalysis("probe.nl", sourceText)
    }

    return new AnalyzerReflectionCallReporter(scopes, context, facts, spans, sink, log)
}

// ------------------------------------------------------------------ reflected candidate shapes

// Every public method of `owner` named `name`, in reflection's own order. Used instead of
// `GetMethod(name)` because the interesting shapes are the OVERLOADED ones, which `GetMethod`
// refuses to choose between.
func RMethods(owner: Type, name: string): List<MethodInfo> {
    found := new List<MethodInfo>()
    all := owner.GetMethods()
    index := 0
    while index < all.Length {
        candidate := all[index]
        index = index + 1
        if candidate.get_Name() == name {
            found.Add(candidate)
        }
    }

    return found
}

func RMethods0(): List<MethodInfo> {
    return new List<MethodInfo>()
}

// One reflected method, chosen so its name is unambiguous on its declaring type.
func ROneMethod(): List<MethodInfo> {
    return RMethods(typeof(object), "GetHashCode")
}

// The same method listed twice — the DUPLICATE-signature shape the distinct cap has to collapse.
func RDuplicatedMethod(): List<MethodInfo> {
    doubled := RMethods0()
    single := ROneMethod()
    doubled.Add(single[0])
    doubled.Add(single[0])
    return doubled
}

func RIdentifier(name: string, line: int, column: int): Expression {
    return new IdentifierExpression(name, line, column)
}

func RPositional(value: Expression): Argument {
    return new Argument(null, value, ArgumentModifier.None)
}

func RArgs0(): List<Argument> {
    return new List<Argument>()
}

func RArgs1(first: Expression): List<Argument> {
    arguments := RArgs0()
    arguments.Add(RPositional(first))
    return arguments
}

func RArgs2(first: Expression, second: Expression): List<Argument> {
    arguments := RArgs1(first)
    arguments.Add(RPositional(second))
    return arguments
}

func RCall(name: string, arguments: List<Argument>): CallExpression {
    return new CallExpression(RIdentifier(name, 1, 1), arguments, null, 1, 1)
}

func RMemberCall(memberName: string, arguments: List<Argument>): CallExpression {
    receiver := RIdentifier("receiver", 1, 1)
    callee := new MemberAccessExpression(receiver, memberName, false, 1, 9)
    return new CallExpression(callee, arguments, null, 1, 1)
}

// A callee with no written name of its own: `g()(x)`. This is the only shape that reaches the
// first-candidate fallback.
func RUnnamedCalleeCall(arguments: List<Argument>): CallExpression {
    inner := new CallExpression(RIdentifier("g", 1, 1), RArgs0(), null, 1, 1)
    return new CallExpression(inner, arguments, null, 1, 1)
}

func RTypes0(): List<TypeInfo> {
    return new List<TypeInfo>()
}

func RTypes1(first: TypeInfo): List<TypeInfo> {
    types := RTypes0()
    types.Add(first)
    return types
}

func RTypes2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    types := RTypes1(first)
    types.Add(second)
    return types
}

// A `FunctionTypeInfo` that carries a DECLARATION's identity — the method-group half of the
// group-versus-lambda discriminator.
func RSourceFunction(sourceName: string): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SourceName = sourceName
    signature.SyntheticName = sourceName
    signature.ParameterTypes = RTypes0()
    signature.ReturnType = BuiltInTypes.Void
    return signature
}

// A `FunctionTypeInfo` with NO source identity — a lambda's type.
func RLambdaFunction(): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.ParameterTypes = RTypes0()
    signature.ReturnType = BuiltInTypes.Void
    return signature
}

func RMethodGroup(sourceName: string): NSharpMethodGroupInfo {
    functions := new List<FunctionTypeInfo>()
    functions.Add(RSourceFunction(sourceName))
    return NSharpMethodGroupInfoFactory.FromFunctions(functions)
}

func RDeclare(scopes: AnalyzerScopeStack, name: string, symbol: TypeInfo) {
    scopes.GlobalScope().Symbols[name] = symbol
}

func RTypeText(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    candidateObject := candidate as object
    rendered := candidateObject.ToString()
    if rendered == null {
        return "<null-text>"
    }

    return rendered
}

// How many candidate signatures the rich hint actually lists. `ErrorMessageBuilder` renders each
// one as its own `  - ` bullet, so counting bullets counts signatures.
func RBulletCount(hint: string): int {
    count := 0
    index := 0
    while index >= 0 {
        found := hint.IndexOf("  - ", index)
        if found < 0 {
            index = -1
        } else {
            count = count + 1
            index = found + 1
        }
    }

    return count
}

func RCodes(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + ","
        }
        text = text + errors[index].DiagnosticId
        index = index + 1
    }

    return text
}

// ------------------------------------------------------------------ the ordinary NL402 arm

test "an EMPTY candidate list says nothing at all, through either arm" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)

    owner.ReportNoMatchingOverload(RCall("f", RArgs0()), RMethods0(), RTypes0())
    assert errors.Count == 0

    owner.ReportNoMatchingMethodGroupOverload(RCall("f", RArgs0()), RMethods0(), "handler")
    assert errors.Count == 0

    // The driver still answers `unknown` — silence is not the same as a failure to answer.
    answer := owner.ReportUnboundCall(RCall("f", RArgs0()), RMethods0(), RTypes0())
    assert errors.Count == 0
    assert RTypeText(answer) == "unknown"
}

test "an unbound reflected call reports NL402 naming what the user WROTE" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)

    owner.ReportNoMatchingOverload(
        RCall("hash", RArgs1(RIdentifier("a", 1, 6))),
        ROneMethod(),
        RTypes1(BuiltInTypes.String)
    )

    assert RCodes(errors) == "NL402"
    assert errors[0].Message.Contains("'hash'")
    assert errors[0].Message.Contains("1 argument(s)")
    assert errors[0].Line == 1
    assert errors[0].Column == 1
}

test "a MEMBER-ACCESS callee names the MEMBER, and the span moves to it" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)

    owner.ReportNoMatchingOverload(
        RMemberCall("Trim", RArgs0()),
        ROneMethod(),
        RTypes0()
    )

    assert RCodes(errors) == "NL402"
    assert errors[0].Message.Contains("'Trim'")
    // With no source text the member name's column is the member access's own column plus one,
    // and the span is the member NAME's width, not the whole callee's.
    assert errors[0].Column == 10
    assert errors[0].Length == 4
}

test "only a callee with NO written name falls back to the first candidate's reflected name" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)

    owner.ReportNoMatchingOverload(RUnnamedCalleeCall(RArgs0()), ROneMethod(), RTypes0())

    assert RCodes(errors) == "NL402"
    assert errors[0].Message.Contains("'GetHashCode'")
}

test "the argument types are rendered in ARGUMENT order" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    text := "let x = hash(a, b)\n"
    owner := ReporterOwnerWith(errors, scopes, text, new AnalyzerCallableReferenceReportLog())

    owner.ReportNoMatchingOverload(
        RCall("hash", RArgs2(RIdentifier("a", 1, 14), RIdentifier("b", 1, 17))),
        ROneMethod(),
        RTypes2(BuiltInTypes.String, BuiltInTypes.Int)
    )

    assert RCodes(errors) == "NL402"
    hint := errors[0].HumanExplanation ?? ""
    contextual := errors[0].ContextualHint ?? ""
    rendered := hint + "\n" + contextual + "\n" + errors[0].Message
    assert rendered.IndexOf("string") >= 0
    assert rendered.IndexOf("int") >= 0
    assert rendered.IndexOf("string") < rendered.IndexOf("int")
}

test "the candidate list is DISTINCT first and capped at eight second" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    text := "let x = IndexOf(a)\n"
    owner := ReporterOwnerWith(errors, scopes, text, new AnalyzerCallableReferenceReportLog())

    // `string.IndexOf` carries well over eight public overloads, so the cap is exercised.
    candidates := RMethods(typeof(string), "IndexOf")
    assert candidates.Count > 8

    owner.ReportNoMatchingOverload(
        RCall("IndexOf", RArgs1(RIdentifier("a", 1, 17))),
        candidates,
        RTypes1(BuiltInTypes.Bool)
    )

    assert RCodes(errors) == "NL402"
    // Each rendered signature is one `  - ` bullet, so the bullets ARE the list.
    assert RBulletCount(errors[0].ContextualHint ?? "") == 8
}

test "DUPLICATE signatures collapse to one before the cap counts them" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    text := "let x = hash()\n"
    owner := ReporterOwnerWith(errors, scopes, text, new AnalyzerCallableReferenceReportLog())

    owner.ReportNoMatchingOverload(RCall("hash", RArgs0()), RDuplicatedMethod(), RTypes0())

    assert RCodes(errors) == "NL402"
    // Two identical candidates render one bullet: distinctness is applied BEFORE the cap.
    assert RBulletCount(errors[0].ContextualHint ?? "") == 1
}

test "the RICH shape appears only when the sink has BOTH a path and the line's text" {
    // Detail-only: no source text at all.
    plainErrors := ReporterErrors()
    plainScopes := ReporterScopes()
    plain := ReporterOwner(plainErrors, plainScopes)
    plain.ReportNoMatchingOverload(RCall("hash", RArgs0()), ROneMethod(), RTypes0())
    assert RCodes(plainErrors) == "NL402"
    assert plainErrors[0].DocsUrl == null
    assert plainErrors[0].Suggestion != null

    // Rich: a path AND the offending line.
    richErrors := ReporterErrors()
    richScopes := ReporterScopes()
    rich := ReporterOwnerWith(
        richErrors,
        richScopes,
        "let x = hash()\n",
        new AnalyzerCallableReferenceReportLog()
    )
    rich.ReportNoMatchingOverload(RCall("hash", RArgs0()), ROneMethod(), RTypes0())
    assert RCodes(richErrors) == "NL402"
    assert richErrors[0].DocsUrl != null
    assert richErrors[0].SourceSnippet != null
    assert richErrors[0].FileName == "probe.nl"
}

// ------------------------------------------------------------------ the method-group arm

test "the method-group arm names the GROUP and has no rich shape even with source text" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwnerWith(
        errors,
        scopes,
        "let x = each(handler)\n",
        new AnalyzerCallableReferenceReportLog()
    )

    owner.ReportNoMatchingMethodGroupOverload(
        RCall("each", RArgs1(RIdentifier("handler", 1, 14))),
        ROneMethod(),
        "handler"
    )

    assert RCodes(errors) == "NL402"
    assert errors[0].Message.Contains("method group 'handler'")
    assert errors[0].DocsUrl == null
}

test "an N# METHOD GROUP argument selects the method-group arm, and only that arm fires" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    RDeclare(scopes, "handler", RMethodGroup("handler"))
    owner := ReporterOwner(errors, scopes)

    answer := owner.ReportUnboundCall(
        RCall("each", RArgs1(RIdentifier("handler", 1, 14))),
        ROneMethod(),
        RTypes0()
    )

    assert errors.Count == 1
    assert errors[0].Message.Contains("method group 'handler'")
    assert RTypeText(answer) == "unknown"
}

test "a SOURCE FUNCTION argument counts as a method group; a LAMBDA-typed one does not" {
    groupErrors := ReporterErrors()
    groupScopes := ReporterScopes()
    RDeclare(groupScopes, "handler", RSourceFunction("handler"))
    group := ReporterOwner(groupErrors, groupScopes)
    group.ReportUnboundCall(
        RCall("each", RArgs1(RIdentifier("handler", 1, 14))),
        ROneMethod(),
        RTypes0()
    )
    assert groupErrors.Count == 1
    assert groupErrors[0].Message.Contains("method group 'handler'")

    lambdaErrors := ReporterErrors()
    lambdaScopes := ReporterScopes()
    RDeclare(lambdaScopes, "handler", RLambdaFunction())
    lambda := ReporterOwner(lambdaErrors, lambdaScopes)
    lambda.ReportUnboundCall(
        RCall("each", RArgs1(RIdentifier("handler", 1, 14))),
        ROneMethod(),
        RTypes0()
    )
    assert lambdaErrors.Count == 1
    assert !lambdaErrors[0].Message.Contains("method group")
    assert lambdaErrors[0].Message.Contains("argument(s) with these types")
}

test "an ordinary symbol, an UNDECLARED name and a non-identifier argument all take the ordinary arm" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    RDeclare(scopes, "count", BuiltInTypes.Int)
    owner := ReporterOwner(errors, scopes)

    owner.ReportUnboundCall(
        RCall("each", RArgs1(RIdentifier("count", 1, 14))),
        ROneMethod(),
        RTypes1(BuiltInTypes.Int)
    )
    assert errors.Count == 1
    assert !errors[0].Message.Contains("method group")

    errors.Clear()
    owner.ReportUnboundCall(
        RCall("each", RArgs1(RIdentifier("missing", 1, 14))),
        ROneMethod(),
        RTypes0()
    )
    assert errors.Count == 1
    assert !errors[0].Message.Contains("method group")

    // A call in argument position is a VALUE, never a group, however its name resolves.
    errors.Clear()
    RDeclare(scopes, "handler", RMethodGroup("handler"))
    nested := RArgs0()
    nested.Add(RPositional(new CallExpression(RIdentifier("handler", 1, 14), RArgs0(), null, 1, 14)))
    owner.ReportUnboundCall(RCall("each", nested), ROneMethod(), RTypes0())
    assert errors.Count == 1
    assert !errors[0].Message.Contains("method group")
}

test "the FIRST method-group argument names the report, whatever follows it" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    RDeclare(scopes, "first", RMethodGroup("first"))
    RDeclare(scopes, "second", RMethodGroup("second"))
    owner := ReporterOwner(errors, scopes)

    owner.ReportUnboundCall(
        RCall("each", RArgs2(RIdentifier("first", 1, 14), RIdentifier("second", 1, 22))),
        ROneMethod(),
        RTypes0()
    )

    assert errors.Count == 1
    assert errors[0].Message.Contains("method group 'first'")
}

test "a method group in a LATER position still selects the arm" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    RDeclare(scopes, "count", BuiltInTypes.Int)
    RDeclare(scopes, "second", RMethodGroup("second"))
    owner := ReporterOwner(errors, scopes)

    owner.ReportUnboundCall(
        RCall("each", RArgs2(RIdentifier("count", 1, 14), RIdentifier("second", 1, 22))),
        ROneMethod(),
        RTypes1(BuiltInTypes.Int)
    )

    assert errors.Count == 1
    assert errors[0].Message.Contains("method group 'second'")
}

// ------------------------------------------------------------------ the NL411 guard

test "a LAMBDA is never an unbound callable reference, whatever its type says" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)
    lambda := new LambdaExpression(new List<Parameter>(), null, null, 1, 1)

    assert !owner.IsUnboundCallableReference(lambda, RMethodGroup("f"), null)
    assert !owner.IsUnboundCallableReference(lambda, RMethodGroup("f"), BuiltInTypes.Int)
}

test "an EXPECTED type that can take a delegate suppresses the guard; one that cannot does not" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)
    reference := RIdentifier("f", 1, 1)
    group := RMethodGroup("f")

    assert owner.IsUnboundCallableReference(reference, group, null)
    assert owner.IsUnboundCallableReference(reference, group, BuiltInTypes.Int)

    delegateShape := new FunctionTypeInfo()
    delegateShape.ParameterTypes = RTypes0()
    delegateShape.ReturnType = BuiltInTypes.Void
    assert !owner.IsUnboundCallableReference(reference, group, delegateShape)

    funcShape := new GenericTypeInfo("Func", RTypes1(BuiltInTypes.Int))
    assert !owner.IsUnboundCallableReference(reference, group, funcShape)
}

test "an ordinary value type is not a callable reference, and a lambda-typed value is not either" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)
    reference := RIdentifier("f", 1, 1)

    assert !owner.IsUnboundCallableReference(reference, BuiltInTypes.Int, null)
    assert !owner.IsUnboundCallableReference(reference, RLambdaFunction(), null)
    assert owner.IsUnboundCallableReference(reference, RSourceFunction("f"), null)
}

// ------------------------------------------------------------------ the NL411 report

test "NL411 names the identifier, and renders both report shapes" {
    plainErrors := ReporterErrors()
    plainScopes := ReporterScopes()
    plain := ReporterOwner(plainErrors, plainScopes)
    plain.ReportMethodGroupUsedAsValue(RIdentifier("handler", 3, 5), RMethodGroup("handler"))
    assert RCodes(plainErrors) == "NL411"
    assert plainErrors[0].Message.Contains("Method 'handler'")
    assert plainErrors[0].Line == 3
    assert plainErrors[0].Column == 5
    assert plainErrors[0].Length == 7
    assert plainErrors[0].DocsUrl == null

    richErrors := ReporterErrors()
    richScopes := ReporterScopes()
    rich := ReporterOwnerWith(
        richErrors,
        richScopes,
        "let x = handler\n",
        new AnalyzerCallableReferenceReportLog()
    )
    rich.ReportMethodGroupUsedAsValue(RIdentifier("handler", 1, 9), RMethodGroup("handler"))
    assert RCodes(richErrors) == "NL411"
    assert richErrors[0].DocsUrl != null
    assert richErrors[0].SourceSnippet != null
}

test "NL411 names the MEMBER of a member access, and the TYPE when the node has no name" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)

    member := new MemberAccessExpression(RIdentifier("receiver", 1, 1), "Handle", false, 1, 10)
    owner.ReportMethodGroupUsedAsValue(member, RMethodGroup("handler"))
    assert errors[0].Message.Contains("Method 'Handle'")

    errors.Clear()
    unnamed := new CallExpression(RIdentifier("g", 2, 1), RArgs0(), null, 2, 1)
    owner.ReportMethodGroupUsedAsValue(unnamed, RMethodGroup("handler"))
    assert errors[0].Message.Contains("Method 'handler'")
}

test "NL411 reports ONCE per anchor and name, and again when either differs" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    owner := ReporterOwner(errors, scopes)
    group := RMethodGroup("handler")

    owner.ReportMethodGroupUsedAsValue(RIdentifier("handler", 3, 5), group)
    owner.ReportMethodGroupUsedAsValue(RIdentifier("handler", 3, 5), group)
    owner.ReportMethodGroupUsedAsValue(RIdentifier("handler", 3, 5), group)
    assert errors.Count == 1

    // A different COLUMN is a different occurrence.
    owner.ReportMethodGroupUsedAsValue(RIdentifier("handler", 3, 9), group)
    assert errors.Count == 2

    // A different LINE is a different occurrence.
    owner.ReportMethodGroupUsedAsValue(RIdentifier("handler", 4, 5), group)
    assert errors.Count == 3

    // The same anchor under a different NAME is a different report.
    owner.ReportMethodGroupUsedAsValue(RIdentifier("other", 3, 5), RMethodGroup("other"))
    assert errors.Count == 4
}

test "the dedupe log OUTLIVES the reporter that reads it" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    log := new AnalyzerCallableReferenceReportLog()

    first := ReporterOwnerWith(errors, scopes, null, log)
    first.ReportMethodGroupUsedAsValue(RIdentifier("handler", 3, 5), RMethodGroup("handler"))
    assert errors.Count == 1

    // The toolset rebuild replaces the reporter but MUST NOT replace the log.
    rebuilt := ReporterOwnerWith(errors, scopes, null, log)
    rebuilt.ReportMethodGroupUsedAsValue(RIdentifier("handler", 3, 5), RMethodGroup("handler"))
    assert errors.Count == 1

    // A reporter over a FRESH log has forgotten, which is exactly the failure the shape prevents.
    forgetful := ReporterOwnerWith(errors, scopes, null, new AnalyzerCallableReferenceReportLog())
    forgetful.ReportMethodGroupUsedAsValue(RIdentifier("handler", 3, 5), RMethodGroup("handler"))
    assert errors.Count == 2
}

test "the dedupe key is injective across the anchor and the name" {
    log := new AnalyzerCallableReferenceReportLog()

    assert log.TryBeginReport(1, 23, "x")
    // `1:23:x` versus `12:3:x` — the same characters, a different anchor.
    assert log.TryBeginReport(12, 3, "x")
    // A name that itself contains the separator cannot impersonate another anchor.
    assert log.TryBeginReport(1, 2, "3:x")
    assert !log.TryBeginReport(1, 23, "x")
    assert !log.TryBeginReport(12, 3, "x")
    assert !log.TryBeginReport(1, 2, "3:x")
}

test "every report this owner makes reaches the SAME list in list order" {
    errors := ReporterErrors()
    scopes := ReporterScopes()
    RDeclare(scopes, "handler", RMethodGroup("handler"))
    owner := ReporterOwnerWith(
        errors,
        scopes,
        "let x = each(handler)\n",
        new AnalyzerCallableReferenceReportLog()
    )

    owner.ReportMethodGroupUsedAsValue(RIdentifier("handler", 1, 14), RMethodGroup("handler"))
    owner.ReportUnboundCall(
        RCall("each", RArgs1(RIdentifier("handler", 1, 14))),
        ROneMethod(),
        RTypes0()
    )
    owner.ReportNoMatchingOverload(RCall("hash", RArgs0()), ROneMethod(), RTypes0())

    assert RCodes(errors) == "NL411,NL402,NL402"
}
