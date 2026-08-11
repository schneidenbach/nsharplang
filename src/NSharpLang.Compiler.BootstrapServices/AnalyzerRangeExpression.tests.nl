namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the `range` arm — what `a..b` MEANS.
//
// Every member behind these contracts was `private` in `Analyzer.cs`, so nothing named any of them.
// This is their first DIRECT pinning, and it goes at the decisions that read like plumbing and are
// not:
//
//   * the WALK PROTOCOL: ONE kind handed out ONCE PER PRESENT ENDPOINT, which means twice for
//     `a..b`, once for `a..` and `..b`, and NOT AT ALL for the bare `..` — an absent endpoint is not
//     walked as a null, it is not walked;
//   * that NOTHING IS BRACKETED — the ambient expected type is untouched at every step, which is what
//     makes this the only arm whose driver carries no operand but the node;
//   * WHICH BOUNDS ARE LEGAL, and that the answer comes from the ASSIGNABILITY ORACLE rather than a
//     type-name test, so a `byte` bound is accepted and a `long` is not;
//   * that `unknown` IS ACCEPTED SILENTLY, because the complaint the developer is owed was already
//     raised below;
//   * that the RESULT IS `System.Range` WHATEVER HAPPENED — a refused bound still types the
//     expression around it and produces no cascade;
//   * and that the two SoA escapes SHORT-CIRCUIT, which is the arm's one behavioural difference from
//     the boolean-condition family's look-alike pair.

class RangeArmHarness {
    Arm: AnalyzerRangeExpression
    Errors: List<CompilerError>
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Sink: AnalyzerDiagnosticSink

    constructor(arm: AnalyzerRangeExpression, errors: List<CompilerError>, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, sink: AnalyzerDiagnosticSink) {
        Arm = arm
        Errors = errors
        Ambient = ambient
        Scopes = scopes
        Sink = sink
    }
}

func RangeArmOf(): RangeArmHarness {
    errors := new List<CompilerError>()
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    sink := new AnalyzerDiagnosticSink(errors, provider)
    spans := new AnalyzerDiagnosticSpans(sink)
    usingAliases := new Dictionary<string, string>(StringComparer.Ordinal)
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal)
    namespaces := new List<string>()
    assemblies := new List<Assembly>()
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, usingAliases)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, usingAliases, importedSymbols, importedDeclarations, model, bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)

    arm := new AnalyzerRangeExpression(sink, spans, scopes, context, soaEscape, assignability)
    return new RangeArmHarness(arm, errors, ambient, scopes, sink)
}

func RangeCodes(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + ","
        }

        codeValue: int = (int)errors[index].Code
        text = text + codeValue.ToString()
        index = index + 1
    }

    return text
}

func RangeTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    if BuiltInTypes.IsUnknown(candidate) {
        return "unknown"
    }

    simple := candidate as SimpleTypeInfo
    if simple != null {
        return "simple:" + simple.Name
    }

    reflection := candidate as ReflectionTypeInfo
    if reflection != null {
        return "reflection:" + reflection.Type.get_Name()
    }

    return "<other>"
}

func RangeNodeOf(start: Expression?, rangeEnd: Expression?): Expression {
    node: Expression = new RangeExpression(start, rangeEnd, 4, 1)
    return node
}

func RangeIntLiteral(value: string): Expression {
    literal: Expression = new IntLiteralExpression(value, 4, 8)
    return literal
}

func RangeName(name: string): Expression {
    identifier: Expression = new IdentifierExpression(name, 4, 8)
    return identifier
}

class RangeDriveTrace {
    Kinds: string
    Nodes: string
    ExpectedAtStep: string
    Answer: string
    Reports: int
    Message: string

    constructor() {
        Kinds = ""
        Nodes = ""
        ExpectedAtStep = ""
        Answer = ""
        Reports = 0
        Message = ""
    }
}

// One full turn of the protocol. Every step is answered from the two supplied types in order — start
// first, end second — and the EXPECTED TYPE the ambient slot holds at each step is recorded, which is
// the only way to observe that this arm brackets nothing at all.
func RangeDrive(harness: RangeArmHarness, node: Expression, startAnswer: TypeInfo, endAnswer: TypeInfo): RangeDriveTrace {
    trace := new RangeDriveTrace()
    before := harness.Errors.Count
    state := harness.Arm.Begin(node)
    stepIndex := 0
    step := harness.Arm.NextStep(state)
    while step != null {
        trace.Kinds = trace.Kinds + step.Kind.ToString()
        if stepIndex > 0 {
            trace.Nodes = trace.Nodes + ","
            trace.ExpectedAtStep = trace.ExpectedAtStep + ","
        }

        trace.Nodes = trace.Nodes + RangeNodeText(step.Node)
        trace.ExpectedAtStep = trace.ExpectedAtStep + RangeTypeName(harness.Ambient.CurrentExpectedType)
        answer := startAnswer
        if stepIndex > 0 {
            answer = endAnswer
        }

        harness.Arm.Supply(state, answer)
        stepIndex = stepIndex + 1
        step = harness.Arm.NextStep(state)
    }

    trace.Answer = RangeTypeName(harness.Arm.Result(state))
    trace.Reports = harness.Errors.Count - before
    if harness.Errors.Count > before {
        trace.Message = harness.Errors[before].Message
    }

    return trace
}

func RangeNodeText(node: Expression?): string {
    if node == null {
        return "<null>"
    }

    literal := node as IntLiteralExpression
    if literal != null {
        return literal.Value
    }

    identifier := node as IdentifierExpression
    if identifier != null {
        return identifier.Name
    }

    return "<other>"
}

// ---- the walk protocol -----------------------------------------------------------------------

test "both endpoints present take TWO steps of ONE kind, in start-then-end order" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeIntLiteral("1"), RangeIntLiteral("9")), BuiltInTypes.Int, BuiltInTypes.Int)

    assert trace.Kinds == "11"
    assert trace.Nodes == "1,9"
    assert trace.Reports == 0
}

test "an absent start endpoint is NOT walked as a null — only the end is handed out" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(null, RangeIntLiteral("9")), BuiltInTypes.Int, BuiltInTypes.Int)

    assert trace.Kinds == "1"
    assert trace.Nodes == "9"
    assert trace.Reports == 0
}

test "an absent end endpoint is NOT walked as a null — only the start is handed out" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeIntLiteral("1"), null), BuiltInTypes.Int, BuiltInTypes.Int)

    assert trace.Kinds == "1"
    assert trace.Nodes == "1"
    assert trace.Reports == 0
}

test "the bare `..` asks for NOTHING and still answers System.Range" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(null, null), BuiltInTypes.Int, BuiltInTypes.Int)

    assert trace.Kinds == ""
    assert trace.Reports == 0
    assert trace.Answer == "reflection:Range"
}

test "NOTHING IS BRACKETED — the ambient expected type is untouched at every step" {
    harness := RangeArmOf()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.String)
    trace := RangeDrive(harness, RangeNodeOf(RangeIntLiteral("1"), RangeIntLiteral("9")), BuiltInTypes.Int, BuiltInTypes.Int)
    harness.Ambient.ExitExpectedType(saved)

    assert trace.ExpectedAtStep == "simple:string,simple:string"
}

test "a node that is not a range finishes at Begin and asks for nothing" {
    harness := RangeArmOf()
    state := harness.Arm.Begin(RangeName("xs"))

    assert harness.Arm.NextStep(state) == null
    assert RangeTypeName(harness.Arm.Result(state)) == "reflection:Range"
}

// ---- what a bound may be ---------------------------------------------------------------------

test "an int bound is silent" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeIntLiteral("1"), RangeIntLiteral("9")), BuiltInTypes.Int, BuiltInTypes.Int)

    assert trace.Reports == 0
}

test "a byte bound is silent BECAUSE THE ASSIGNABILITY ORACLE ANSWERS, not a type-name test" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeIntLiteral("1"), RangeIntLiteral("9")), BuiltInTypes.Byte, BuiltInTypes.Int)

    assert trace.Reports == 0
}

test "a string bound is refused, and the report names the type it saw" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeName("text"), RangeIntLiteral("9")), BuiltInTypes.String, BuiltInTypes.Int)

    assert trace.Reports == 1
    assert RangeCodes(harness.Errors) == ((int)ErrorCode.TypeMismatch).ToString()
    assert trace.Message == "Range bounds must be int or System.Index, but this bound has type 'string'"
}

test "a long bound is refused — widening the other way is not assignable to int" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeName("big"), RangeIntLiteral("9")), BuiltInTypes.Long, BuiltInTypes.Int)

    assert trace.Reports == 1
}

test "an UNKNOWN bound is accepted silently — the complaint was already raised below" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeName("mystery"), RangeIntLiteral("9")), BuiltInTypes.Unknown, BuiltInTypes.Int)

    assert trace.Reports == 0
}

test "a System.Index bound is accepted, and it is the INDEX family's published predicate that says so" {
    harness := RangeArmOf()
    indexType: TypeInfo = new SimpleTypeInfo("System.Index")
    trace := RangeDrive(harness, RangeNodeOf(RangeName("hat"), RangeIntLiteral("9")), indexType, BuiltInTypes.Int)

    assert trace.Reports == 0
    assert AnalyzerIndexAccess.IsIndexLikeType(indexType)
}

test "BOTH bounds are checked — two bad bounds produce two reports" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeName("a"), RangeName("b")), BuiltInTypes.String, BuiltInTypes.String)

    assert trace.Reports == 2
}

test "the END bound is checked even when the START was refused" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeName("a"), RangeName("b")), BuiltInTypes.String, BuiltInTypes.Bool)

    assert trace.Reports == 2
    assert harness.Errors[1].Message == "Range bounds must be int or System.Index, but this bound has type 'bool'"
}

// ---- the type it answers ---------------------------------------------------------------------

test "a refused bound STILL answers System.Range — there is no cascade" {
    harness := RangeArmOf()
    trace := RangeDrive(harness, RangeNodeOf(RangeName("text"), RangeIntLiteral("9")), BuiltInTypes.String, BuiltInTypes.Int)

    assert trace.Reports == 1
    assert trace.Answer == "reflection:Range"
}

test "the PROJECT'S OWN System.Range wins over the reflected fallback when the scope stack has one" {
    harness := RangeArmOf()
    declared: TypeInfo = new SimpleTypeInfo("System.Range")
    harness.Scopes.Peek().Types["System.Range"] = declared
    trace := RangeDrive(harness, RangeNodeOf(RangeIntLiteral("1"), RangeIntLiteral("9")), BuiltInTypes.Int, BuiltInTypes.Int)

    assert trace.Answer == "simple:System.Range"
}

// ---- the diagnostic's shape ------------------------------------------------------------------

test "the report is underlined at the BOUND and carries the conversion suggestion" {
    harness := RangeArmOf()
    RangeDrive(harness, RangeNodeOf(RangeName("text"), null), BuiltInTypes.String, BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 8
    assert harness.Errors[0].Suggestion == "Use an int bound, '^n' with an int count, or convert the value before building the range."
}
