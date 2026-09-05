namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the `match` EXPRESSION arm — what a `match` produces, and who is told what.
//
// The statement form moved in slice 42 and the pattern family in slice 41; this is the EXPRESSION,
// and every member behind these contracts was `private` in `Analyzer.cs`. This is their first DIRECT
// pinning, and it goes at the decisions that read like plumbing and are not:
//
//   * the WALK PROTOCOL: five kinds, a scope PER ARM, and the exact step order
//     open / pattern / [guard] / value / close — a guard-less arm takes FOUR steps, not five;
//   * the TWO EXPRESSION KINDS, which are different on purpose: the match VALUE is a PLAIN walk under
//     a CLEARED expected-type slot the owner brackets itself, and every ARM is the TARGET-TYPED walk
//     the driver performs, because that form routes a lambda before any bracket opens;
//   * that the expected type is captured at `Begin` and therefore SURVIVES the clear;
//   * that every arm is target-typed against the MATCH's expected type, never against the arm
//     before it;
//   * the JOIN, which is NOT a common-type computation: the first arm wins and a later assignable arm
//     does NOT widen it;
//   * the reflected COMMON-TYPE search, which prefers a shared interface over a shared base and
//     refuses `object`;
//   * and that EXHAUSTIVENESS is asked LAST, once, on the POST-ESCAPE value type.

// TWO PROBES WITH A SHARED BASE AND NO SHARED INTERFACE, which is the only shape that reaches the
// base-class half of the common-type search: an interface match would answer first.
class MatchBaseProbe {
    Tag: int

    constructor() {
        Tag = 0
    }
}

class MatchDerivedProbe: MatchBaseProbe {
    constructor(): base() {
    }
}

class MatchStrangerProbe {
    Tag: int

    constructor() {
        Tag = 0
    }
}

class MatchArmHarness {
    Arm: AnalyzerMatchExpression
    Errors: List<CompilerError>
    Ambient: AnalyzerAmbientContext
    Sink: AnalyzerDiagnosticSink

    constructor(arm: AnalyzerMatchExpression, errors: List<CompilerError>, ambient: AnalyzerAmbientContext, sink: AnalyzerDiagnosticSink) {
        Arm = arm
        Errors = errors
        Ambient = ambient
        Sink = sink
    }
}

func MatchArmOf(): MatchArmHarness {
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
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal)
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
    conditions := new AnalyzerBooleanConditions(sink, spans, soaEscape)
    exhaustiveness := new AnalyzerMatchExhaustiveness(sink, substitution, assignability, resolver)

    arm := new AnalyzerMatchExpression(sink, spans, ambient, soaEscape, conditions, assignability, exhaustiveness)
    return new MatchArmHarness(arm, errors, ambient, sink)
}

func MatchTypeName(candidate: TypeInfo?): string {
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

func MatchNameNode(name: string): Expression {
    identifier: Expression = new IdentifierExpression(name, 4, 1)
    return identifier
}

func MatchCaseOf(patternLine: int, patternColumn: int, guard: Expression?, armValue: Expression): MatchCase {
    pattern: Pattern = new IdentifierPattern("_", patternLine, patternColumn)
    return new MatchCase(pattern, guard, armValue)
}

// THE SAME ARM UNDER A PATTERN THAT IS NOT A CATCH-ALL. Every fixture here is about the ARM JOIN —
// what type two arms agree on — and the pattern each arm carried was incidental to that: both were
// spelled `_`, which made the SECOND arm unreachable. `NL502` now says so, correctly, so the first
// arm of a two-arm join is written with a DOTTED name, which is a union case rather than a binding
// and covers only itself. The node type, the step sequence and every assertion below are unchanged.
func MatchCaseNamed(patternName: string, patternLine: int, patternColumn: int, guard: Expression?, armValue: Expression): MatchCase {
    pattern: Pattern = new IdentifierPattern(patternName, patternLine, patternColumn)
    return new MatchCase(pattern, guard, armValue)
}

func MatchNodeOf(cases: List<MatchCase>): Expression {
    node: Expression = new MatchExpression(MatchNameNode("subject"), cases, 4, 1)
    return node
}

func MatchOneArm(guard: Expression?, armValue: Expression): Expression {
    cases := new List<MatchCase>()
    cases.Add(MatchCaseOf(7, 3, guard, armValue))
    return MatchNodeOf(cases)
}

func MatchTwoArms(firstValue: Expression, secondValue: Expression): Expression {
    cases := new List<MatchCase>()
    cases.Add(MatchCaseNamed("Shape.Circle", 7, 3, null, firstValue))
    cases.Add(MatchCaseOf(8, 3, null, secondValue))
    return MatchNodeOf(cases)
}

class MatchDriveTrace {
    Kinds: string
    ExpectedAtStep: string
    ScopeEvents: string
    Answer: string
    Reports: int
    Message: string

    constructor() {
        Kinds = ""
        ExpectedAtStep = ""
        ScopeEvents = ""
        Answer = ""
        Reports = 0
        Message = ""
    }
}

// One full turn of the protocol. Answers are taken from the supplied list in the order the walk asks
// for them; the non-answering kinds (scope open, pattern, scope close) consume nothing. The EXPECTED
// TYPE the ambient slot holds at each step is recorded, which is the only way to observe a bracket
// that opens and closes entirely inside the owner.
func MatchDrive(harness: MatchArmHarness, node: Expression, answers: List<TypeInfo>): MatchDriveTrace {
    trace := new MatchDriveTrace()
    before := harness.Errors.Count
    state := harness.Arm.Begin(node)
    answerIndex := 0
    stepIndex := 0
    step := harness.Arm.NextStep(state)
    while step != null {
        trace.Kinds = trace.Kinds + step.Kind.ToString()
        if stepIndex > 0 {
            trace.ExpectedAtStep = trace.ExpectedAtStep + ","
        }

        trace.ExpectedAtStep = trace.ExpectedAtStep + MatchTypeName(harness.Ambient.CurrentExpectedType)
        answer: TypeInfo? = null
        if step.Kind == 3 {
            trace.ScopeEvents = trace.ScopeEvents + "open(" + step.Line.ToString() + ":" + step.Column.ToString() + ")"
        }

        if step.Kind == 5 {
            trace.ScopeEvents = trace.ScopeEvents + "close"
        }

        if step.Kind == 1 || step.Kind == 2 {
            if answerIndex < answers.Count {
                answer = answers[answerIndex]
            }

            answerIndex = answerIndex + 1
        }

        harness.Arm.Supply(state, answer)
        stepIndex = stepIndex + 1
        step = harness.Arm.NextStep(state)
    }

    trace.Answer = MatchTypeName(harness.Arm.Result(state))
    trace.Reports = harness.Errors.Count - before
    if harness.Errors.Count > before {
        trace.Message = harness.Errors[before].Message
    }

    return trace
}

func MatchAnswers2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    list := new List<TypeInfo>()
    list.Add(first)
    list.Add(second)
    return list
}

func MatchAnswers3(first: TypeInfo, second: TypeInfo, third: TypeInfo): List<TypeInfo> {
    list := MatchAnswers2(first, second)
    list.Add(third)
    return list
}

// ---- the walk protocol -----------------------------------------------------------------------

test "a guard-less single arm takes FOUR steps: value, open, pattern, arm value, close" {
    harness := MatchArmOf()
    trace := MatchDrive(harness, MatchOneArm(null, MatchNameNode("one")), MatchAnswers2(BuiltInTypes.Int, BuiltInTypes.String))

    assert trace.Kinds == "13425"
    assert trace.Answer == "simple:string"
}

test "a GUARDED arm inserts the guard step between the pattern and the arm value" {
    harness := MatchArmOf()
    trace := MatchDrive(harness, MatchOneArm(MatchNameNode("ok"), MatchNameNode("one")), MatchAnswers3(BuiltInTypes.Int, BuiltInTypes.Bool, BuiltInTypes.String))

    assert trace.Kinds == "134225"
    assert trace.Answer == "simple:string"
}

test "the scope opens AT THE PATTERN'S POSITION and closes once per arm" {
    harness := MatchArmOf()
    trace := MatchDrive(harness, MatchTwoArms(MatchNameNode("a"), MatchNameNode("b")), MatchAnswers3(BuiltInTypes.Int, BuiltInTypes.String, BuiltInTypes.String))

    assert trace.ScopeEvents == "open(7:3)closeopen(8:3)close"
    assert trace.Kinds == "134253425"
}

test "a match with NO arms asks only for the value and answers unknown" {
    harness := MatchArmOf()
    empty := new List<MatchCase>()
    answers := new List<TypeInfo>()
    answers.Add(BuiltInTypes.Int)
    trace := MatchDrive(harness, MatchNodeOf(empty), answers)

    assert trace.Kinds == "1"
    assert trace.Answer == "unknown"
}

test "a node that is not a match finishes at Begin and asks for nothing" {
    harness := MatchArmOf()
    state := harness.Arm.Begin(MatchNameNode("subject"))

    assert harness.Arm.NextStep(state) == null
    assert MatchTypeName(harness.Arm.Result(state)) == "unknown"
}

// ---- the two expression kinds and the brackets -------------------------------------------------

test "THE VALUE WALK RUNS UNDER A CLEARED SLOT, and the bracket CLOSES before the arms" {
    harness := MatchArmOf()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.String)
    trace := MatchDrive(harness, MatchOneArm(null, MatchNameNode("one")), MatchAnswers2(BuiltInTypes.Int, BuiltInTypes.String))
    restoredAfterWalk := MatchTypeName(harness.Ambient.CurrentExpectedType)
    harness.Ambient.ExitExpectedType(saved)

    // step 0 is the value, under the CLEAR; every later step sees the restored slot.
    assert trace.ExpectedAtStep == "<null>,simple:string,simple:string,simple:string,simple:string"
    assert restoredAfterWalk == "simple:string"
}

test "the EXPECTED TYPE IS CAPTURED AT Begin and survives the clear — the arm is target-typed with it" {
    harness := MatchArmOf()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.String)
    node := MatchOneArm(null, MatchNameNode("one"))
    state := harness.Arm.Begin(node)
    valueStep := harness.Arm.NextStep(state)
    harness.Arm.Supply(state, BuiltInTypes.Int)
    openStep := harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)
    patternStep := harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)
    armStep := harness.Arm.NextStep(state)
    harness.Ambient.ExitExpectedType(saved)

    assert valueStep != null && valueStep.Kind == 1
    assert valueStep.ExpectedType == null
    assert openStep != null && openStep.Kind == 3
    assert patternStep != null && patternStep.Kind == 4
    assert armStep != null && armStep.Kind == 2
    assert MatchTypeName(armStep.ExpectedType) == "simple:string"
}

test "a GUARD is target-typed to bool, never to the match's own expected type" {
    harness := MatchArmOf()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.String)
    node := MatchOneArm(MatchNameNode("ok"), MatchNameNode("one"))
    state := harness.Arm.Begin(node)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, BuiltInTypes.Int)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)
    guardStep := harness.Arm.NextStep(state)
    harness.Ambient.ExitExpectedType(saved)

    assert guardStep != null && guardStep.Kind == 2
    assert MatchTypeName(guardStep.ExpectedType) == "simple:bool"
}

test "the PATTERN step carries the POST-ESCAPE value type as its operand" {
    harness := MatchArmOf()
    node := MatchOneArm(null, MatchNameNode("one"))
    state := harness.Arm.Begin(node)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, BuiltInTypes.Int)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)
    patternStep := harness.Arm.NextStep(state)

    assert patternStep != null && patternStep.Kind == 4
    assert patternStep.PatternNode != null
    assert MatchTypeName(patternStep.CarriedType) == "simple:int"
}

// ---- the arm join ------------------------------------------------------------------------------

test "the FIRST arm's type wins, and a later ASSIGNABLE arm does NOT widen it" {
    harness := MatchArmOf()
    trace := MatchDrive(harness, MatchTwoArms(MatchNameNode("a"), MatchNameNode("b")), MatchAnswers3(BuiltInTypes.Int, BuiltInTypes.Int, BuiltInTypes.Object))

    assert trace.Reports == 0
    assert trace.Answer == "simple:int"
}

test "a later arm assignable IN THE OTHER DIRECTION is also silent and also does not change the result" {
    harness := MatchArmOf()
    trace := MatchDrive(harness, MatchTwoArms(MatchNameNode("a"), MatchNameNode("b")), MatchAnswers3(BuiltInTypes.Int, BuiltInTypes.Object, BuiltInTypes.Int))

    assert trace.Reports == 0
    assert trace.Answer == "simple:object"
}

test "two arms that disagree in BOTH directions are reported, naming both types" {
    harness := MatchArmOf()
    trace := MatchDrive(harness, MatchTwoArms(MatchNameNode("a"), MatchNameNode("b")), MatchAnswers3(BuiltInTypes.Int, BuiltInTypes.String, BuiltInTypes.Bool))

    assert trace.Reports == 1
    assert trace.Message == "All match arms must return the same type — the first arm returns 'string', but this arm returns 'bool'"
}

test "the disagreement is underlined at the DISAGREEING ARM, not at the match" {
    harness := MatchArmOf()
    MatchDrive(harness, MatchTwoArms(MatchNameNode("a"), MatchNameNode("b")), MatchAnswers3(BuiltInTypes.Int, BuiltInTypes.String, BuiltInTypes.Bool))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 1
    codeValue: int = (int)harness.Errors[0].Code
    assert codeValue == (int)ErrorCode.TypeMismatch
}

test "an UNKNOWN arm never disagrees with anything" {
    harness := MatchArmOf()
    trace := MatchDrive(harness, MatchTwoArms(MatchNameNode("a"), MatchNameNode("b")), MatchAnswers3(BuiltInTypes.Int, BuiltInTypes.String, BuiltInTypes.Unknown))

    assert trace.Reports == 0
    assert trace.Answer == "simple:string"
}

// ---- the reflected common-type search ------------------------------------------------------------

test "a SHARED INTERFACE joins two reflected arms that are otherwise unrelated" {
    listType: TypeInfo = new ReflectionTypeInfo(typeof(List<int>))
    arrayType: TypeInfo = new ReflectionTypeInfo(typeof(int[]))
    common := AnalyzerMatchExpression.FindCommonBaseType(listType, arrayType)

    assert common != null
    assert (common as ReflectionTypeInfo) != null
}

test "two reflected arms with NOTHING in common answer null rather than object" {
    // `int` and `string` would NOT do here: they share `IComparable` and `IConvertible`, so the
    // interface half answers. Two probes that implement nothing and derive from nothing are the only
    // shape that reaches the fall-through — and it must NOT join them at `object`.
    first: TypeInfo = new ReflectionTypeInfo(typeof(MatchBaseProbe))
    second: TypeInfo = new ReflectionTypeInfo(typeof(MatchStrangerProbe))

    assert AnalyzerMatchExpression.FindCommonBaseType(first, second) == null
}

test "the common-type search is REFLECTED-ONLY — two source types answer null" {
    first: TypeInfo = new SimpleTypeInfo("Dog")
    second: TypeInfo = new SimpleTypeInfo("Cat")

    assert AnalyzerMatchExpression.FindCommonBaseType(first, second) == null
}

test "a SHARED BASE CLASS joins two reflected arms when no interface does" {
    derived: TypeInfo = new ReflectionTypeInfo(typeof(MatchDerivedProbe))
    ancestor: TypeInfo = new ReflectionTypeInfo(typeof(MatchBaseProbe))
    common := AnalyzerMatchExpression.FindCommonBaseType(derived, ancestor)

    assert common != null
    reflected := common as ReflectionTypeInfo
    assert reflected != null
    assert reflected.Type.get_Name() == "MatchBaseProbe"
}

// ---- exhaustiveness ------------------------------------------------------------------------------

test "EXHAUSTIVENESS IS ASKED LAST — nothing is reported before the final arm has closed" {
    harness := MatchArmOf()
    node := MatchOneArm(null, MatchNameNode("one"))
    state := harness.Arm.Begin(node)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, BuiltInTypes.Int)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, BuiltInTypes.String)
    beforeClose := harness.Errors.Count
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)
    harness.Arm.NextStep(state)

    // A wildcard arm is exhaustive, so the count does not move — what is pinned is that the walk
    // reaches the check only after the close step has been supplied.
    assert harness.Errors.Count == beforeClose
    assert harness.Arm.NextStep(state) == null
}
