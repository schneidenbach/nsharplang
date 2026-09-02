namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT AN ASSIGNMENT MEANS.
//
// Every member behind these contracts was `private` in `Analyzer.cs`. This is their first DIRECT
// pinning, and it goes at the decisions that are invisible from the outside:
//
// (1) THE ARM TAKES TWO STEPS OF ONE KIND, AND EVERY BRACKET IS THE OWNER'S. The target step runs
// under FOUR ambient changes at once — the flow type suppressed, the error-tuple result use
// suppressed exactly when the operator is a plain `=`, bare event references allowed, and a capture
// table installed for a member or index chain — and all four are restored before any gate runs.
//
// (2) A REFUSED ASSIGNMENT STILL WALKS ITS VALUE. Six of the gates refuse, and every one of them
// hands out the value step anyway, because an error inside the value is the developer's problem
// whether or not the target was legal.
//
// (3) WHICH REFUSALS TARGET-TYPE THE VALUE AND WHICH DO NOT. The three target-SHAPE refusals — a row
// view, a table member, a built-in indexed mutation — walk the value under the target's type; the
// invalid-target and read-only-property refusals walk it under nothing. That is not a tidy-up: it is
// what the C# did, and the value's own diagnostics depend on it.
//
// (4) `??=` REPORTS AND CONTINUES. It is the only gate that does not end the walk.
//
// (5) THE ASSIGNABILITY GATE IS THE FRONT DOOR. `EmitValueCoercion` silently no-ops for closed
// generics over emitted user types, so this check is the only thing between a mismatched value and a
// type-confused read at run time. Both of its renderings are pinned.
//
// (6) THE NULL-STATE AND ERROR-TUPLE FACTS ARE LEFT BEHIND EVEN WHEN THE GATE REFUSED, because the
// store is still what the developer wrote.
//
// (7) NL322 IS DELIBERATELY UNDER-ENFORCING. An unresolvable hop stays silent, an ARRAY ELEMENT is a
// variable, and a FIELD hop passes the question to its own receiver.

class AssignmentValueProbe {
    Count: int => 0
    Mutable: int

    constructor() {
        Mutable = 0
    }
}

class AssignmentStep {
    Kind: int
    NodeName: string
    ExpectedType: string
    ErrorsBefore: int
    SuppressFlowType: bool
    SuppressErrorTuple: bool
    AllowEventReference: bool
    InWriteTarget: bool

    constructor(kind: int, nodeName: string, expectedType: string, errorsBefore: int, suppressFlowType: bool, suppressErrorTuple: bool, allowEventReference: bool, inWriteTarget: bool) {
        Kind = kind
        NodeName = nodeName
        ExpectedType = expectedType
        ErrorsBefore = errorsBefore
        SuppressFlowType = suppressFlowType
        SuppressErrorTuple = suppressErrorTuple
        AllowEventReference = allowEventReference
        InWriteTarget = inWriteTarget
    }
}

class AssignmentHarness {
    Arm: AnalyzerAssignment
    Errors: List<CompilerError>
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    NullFlow: AnalyzerNullFlow
    Identifiers: AnalyzerIdentifierResolution
    Context: AnalyzerDeclarationContext
    LastResult: string

    constructor(arm: AnalyzerAssignment, errors: List<CompilerError>, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, nullFlow: AnalyzerNullFlow, identifiers: AnalyzerIdentifierResolution, context: AnalyzerDeclarationContext) {
        Arm = arm
        Errors = errors
        Ambient = ambient
        Scopes = scopes
        NullFlow = nullFlow
        Identifiers = identifiers
        Context = context
        LastResult = ""
    }
}

func AssignmentPath(): string {
    return Path.GetFullPath("assignment-contract.nl")
}

func AssignmentHarnessWith(sourceText: string?): AssignmentHarness {
    errors := new List<CompilerError>()
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    sink := new AnalyzerDiagnosticSink(errors, provider)
    sink.BeginAnalysis(AssignmentPath(), sourceText)
    spans := new AnalyzerDiagnosticSpans(sink)
    usingAliases := new Dictionary<string, string>(StringComparer.Ordinal)
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal)
    namespaces := new List<string>()
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, usingAliases)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, usingAliases, importedSymbols, importedDeclarations, model, bindings)
    resolver.BeginAnalysis(AssignmentPath(), null, model, bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    extensions := new List<FunctionDeclaration>()
    extensionResolution := new AnalyzerExtensionMethodResolution(resolver, assignability, context, functionTypes, clrConversion, extensions, namespaces, assemblies)
    members := new AnalyzerMemberResolution(functionTypes, context, substitution, resolver, clrConversion, extensionResolution, namespaces)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)
    identifiers := new AnalyzerIdentifierResolution(sink, scopes, resolver, discovery, probe, functionTypes, ambient, nullFlow, extensions, members, model, bindings)
    memberAccess := new AnalyzerMemberAccess(sink, spans, scopes, context, nullFlow, soaEscape, ambient, provider, discovery, probe, substitution, identifiers, extensions, namespaces, usingAliases, importedSymbols, importedDeclarations, assemblies, members, clrConversion, extensionResolution, bindings)
    constantFacts := new AnalyzerConstantExpressionFacts(scopes, context)
    indexAccess := new AnalyzerIndexAccess(sink, spans, context, ambient, nullFlow, soaEscape, memberAccess, constantFacts)
    writeTargets := new AnalyzerWriteTargets(sink, spans, scopes, context, substitution, clrConversion, ambient, soaEscape, memberAccess, indexAccess)
    narrowing := new AnalyzerFlowNarrowing(scopes, resolver, assignability)
    operators := new AnalyzerOperatorExpressions(sink, spans, scopes, context, substitution, assignability, clrConversion, probe, soaEscape, ambient, narrowing, writeTargets)
    arm := new AnalyzerAssignment(sink, spans, scopes, context, ambient, nullFlow, soaEscape, identifiers, assignability, facts, writeTargets, operators)
    return new AssignmentHarness(arm, errors, ambient, scopes, nullFlow, identifiers, context)
}

func AssignmentDefault(): AssignmentHarness {
    return AssignmentHarnessWith(null)
}

func AssignmentTypeText(candidate: TypeInfo?): string {
    if candidate == null {
        return "<none>"
    }

    boxed := candidate as object
    rendered := boxed.ToString()
    if rendered != null {
        return rendered
    }

    return "<blank>"
}

func AssignmentNodeName(node: Expression?): string {
    if node == null {
        return "<null>"
    }

    identifier := node as IdentifierExpression
    if identifier != null {
        return identifier.Name
    }

    member := node as MemberAccessExpression
    if member != null {
        return AssignmentNodeName(member.Object) + "." + member.MemberName
    }

    boxed := node as object
    return boxed.GetType().Name
}

// One full turn of the protocol, exactly as `DriveAssignment` writes it. Every step records the
// FOUR ambient facts that were in force at the instant it was handed out, which is the only way to
// observe brackets that open and close entirely inside the owner.
func AssignmentRun(harness: AssignmentHarness, node: Expression, answers: List<TypeInfo?>): List<AssignmentStep> {
    steps := new List<AssignmentStep>()
    state := harness.Arm.Begin(node)
    step := harness.Arm.NextStep(state)
    while step != null {
        index := steps.Count
        steps.Add(new AssignmentStep(step.Kind, AssignmentNodeName(step.Node), AssignmentTypeText(harness.Ambient.CurrentExpectedType), harness.Errors.Count, harness.NullFlow.SuppressFlowType, harness.Identifiers.SuppressErrorTupleResultUse, harness.Ambient.AllowEventReference, harness.Ambient.InWriteTarget))
        answer: TypeInfo? = null
        if index < answers.Count {
            answer = answers[index]
        }

        harness.Arm.Supply(state, answer)
        step = harness.Arm.NextStep(state)
    }

    harness.LastResult = AssignmentTypeText(harness.Arm.Result(state))
    return steps
}

func AssignmentAnswers(first: TypeInfo?, second: TypeInfo?): List<TypeInfo?> {
    answers := new List<TypeInfo?>()
    answers.Add(first)
    answers.Add(second)
    return answers
}

func AssignmentOne(answer: TypeInfo?): List<TypeInfo?> {
    answers := new List<TypeInfo?>()
    answers.Add(answer)
    return answers
}

func AssignmentName(name: string): Expression {
    expression: Expression = new IdentifierExpression(name, 3, 5)
    return expression
}

func AssignmentMember(receiver: Expression, memberName: string, nullConditional: bool): Expression {
    expression: Expression = new MemberAccessExpression(receiver, memberName, nullConditional, 3, 5)
    return expression
}

func AssignmentOf(op: AssignmentOperator, target: Expression, value: Expression): Expression {
    expression: Expression = new AssignmentExpression(target, op, value, 3, 5)
    return expression
}

func AssignmentSimple(op: AssignmentOperator): Expression {
    return AssignmentOf(op, AssignmentName("total"), AssignmentName("source"))
}

func AssignmentCodes(errors: List<CompilerError>): string {
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

func AssignmentCall(calleeName: string): Expression {
    expression: Expression = new CallExpression(AssignmentName(calleeName), new List<Argument>(), null, 3, 5)
    return expression
}

func AssignmentPlainStruct(name: string): StructTypeInfo {
    return new StructTypeInfo(name, 1, 1, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
}

func AssignmentDeclare(harness: AssignmentHarness, name: string, declaredType: TypeInfo) {
    harness.Scopes.Peek().Symbols[name] = declaredType
}

// ---- the walk protocol -----------------------------------------------------------------------------

test "the arm takes TWO steps of ONE kind, the target then the value" {
    harness := AssignmentDefault()
    steps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    assert steps.Count == 2
    assert steps[0].Kind == 1
    assert steps[0].NodeName == "total"
    assert steps[1].Kind == 1
    assert steps[1].NodeName == "source"
    assert harness.LastResult == "int"
    assert harness.Errors.Count == 0
}

test "a node that is not an assignment finishes at Begin and asks for nothing" {
    harness := AssignmentDefault()
    steps := AssignmentRun(harness, AssignmentName("total"), AssignmentOne(BuiltInTypes.Int))

    assert steps.Count == 0
    assert harness.LastResult == "unknown"
}

test "a DISCARD never walks its target at all, and answers the VALUE'S type" {
    harness := AssignmentDefault()
    steps := AssignmentRun(harness, AssignmentOf(AssignmentOperator.Assign, AssignmentName("_"), AssignmentName("source")), AssignmentOne(BuiltInTypes.String))

    assert steps.Count == 1
    assert steps[0].NodeName == "source"
    assert harness.LastResult == "string"
    assert harness.Errors.Count == 0
}

test "a COMPOUND discard is refused and still walks its value" {
    harness := AssignmentDefault()
    steps := AssignmentRun(harness, AssignmentOf(AssignmentOperator.AddAssign, AssignmentName("_"), AssignmentName("source")), AssignmentOne(BuiltInTypes.Int))

    assert steps.Count == 1
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "The discard `_` can only be used with a plain `=` assignment"
    assert AssignmentCodes(harness.Errors) == "103"
    assert harness.LastResult == "int"
}

test "a NULL-CONDITIONAL target is refused before it is walked, and the value is walked anyway" {
    harness := AssignmentDefault()
    target := AssignmentMember(AssignmentName("box"), "count", true)
    steps := AssignmentRun(harness, AssignmentOf(AssignmentOperator.Assign, target, AssignmentName("source")), AssignmentOne(BuiltInTypes.Int))

    assert steps.Count == 1
    assert steps[0].NodeName == "source"
    assert harness.Errors[0].Message == "Null-conditional member access can't be assigned with '='"
    assert harness.LastResult == "unknown"
}

// ---- the four-part target bracket -------------------------------------------------------------------

test "the TARGET step runs under all four ambient changes and the VALUE step under none of them" {
    harness := AssignmentDefault()
    steps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    assert steps[0].SuppressFlowType
    assert steps[0].SuppressErrorTuple
    assert steps[0].AllowEventReference
    assert !steps[0].InWriteTarget

    assert !steps[1].SuppressFlowType
    assert !steps[1].SuppressErrorTuple
    assert !steps[1].AllowEventReference
    assert !steps[1].InWriteTarget

    // And the walk leaves every one of them exactly as it found them.
    assert !harness.NullFlow.SuppressFlowType
    assert !harness.Identifiers.SuppressErrorTupleResultUse
    assert !harness.Ambient.AllowEventReference
    assert !harness.Ambient.InWriteTarget
}

test "the ERROR-TUPLE suppression is conditional on a PLAIN '=' and nothing else is" {
    harness := AssignmentDefault()
    plainSteps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))
    assert plainSteps[0].SuppressErrorTuple

    // A compound operator READS the target first, so a `must`-typed read there is a real use.
    compoundSteps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.AddAssign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))
    assert !compoundSteps[0].SuppressErrorTuple
    assert compoundSteps[0].SuppressFlowType
    assert compoundSteps[0].AllowEventReference
}

test "the CAPTURE TABLE is opened for a member chain and NOT for a bare name" {
    harness := AssignmentDefault()
    nameSteps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))
    assert !nameSteps[0].InWriteTarget

    target := AssignmentMember(AssignmentName("box"), "count", false)
    memberSteps := AssignmentRun(harness, AssignmentOf(AssignmentOperator.Assign, target, AssignmentName("source")), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))
    assert memberSteps[0].InWriteTarget
    assert !memberSteps[1].InWriteTarget
    assert !harness.Ambient.InWriteTarget
}

// ---- which refusals target-type the value -----------------------------------------------------------

test "the ORDINARY value step runs under the TARGET'S type" {
    harness := AssignmentDefault()
    steps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(BuiltInTypes.Byte, BuiltInTypes.Byte))

    assert steps[0].ExpectedType == "<none>"
    assert steps[1].ExpectedType == "byte"
    assert AssignmentTypeText(harness.Ambient.CurrentExpectedType) == "<none>"
}

test "a SoA ROW-VIEW target is refused, target-types its value anyway, and answers unknown" {
    harness := AssignmentDefault()
    columns := new List<SoaColumnInfo>()
    row: TypeInfo = new SoaRowTypeInfo(new SoaRecordDeclarationInfo("Points", columns, 1, 1))

    steps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(row, BuiltInTypes.Int))

    assert steps.Count == 2
    assert steps[1].ExpectedType == "Points.Row"
    assert harness.LastResult == "unknown"
    assert harness.Errors.Count == 1
}

test "an INVALID target and a READ-ONLY PROPERTY target walk the value under NOTHING" {
    harness := AssignmentDefault()
    literal: Expression = new IntLiteralExpression("1", 3, 5)
    steps := AssignmentRun(harness, AssignmentOf(AssignmentOperator.Assign, literal, AssignmentName("source")), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    assert steps.Count == 2
    assert steps[1].ExpectedType == "<none>"
    assert harness.Errors[0].Message == "The '=' assignment needs an assignable target"
    assert harness.LastResult == "unknown"
}

// ---- the event gate -----------------------------------------------------------------------------------

test "the three event operators get three different sentences and the value is still walked" {
    harness := AssignmentDefault()
    eventType: TypeInfo = new ReflectionEventInfo("Changed", null, null, null, null, "Changed")
    target := AssignmentMember(AssignmentName("widget"), "Changed", false)

    assignSteps := AssignmentRun(harness, AssignmentOf(AssignmentOperator.Assign, target, AssignmentName("handler")), AssignmentAnswers(eventType, BuiltInTypes.Int))
    assert assignSteps.Count == 2
    assert harness.Errors[0].Message == "'Changed' is a .NET event — it can't be assigned with '='"
    assert harness.Errors[0].Suggestion == "Subscribe with `on widget.Changed (sender, args) => { ... }` and unsubscribe with `off`."
    assert harness.LastResult == "unknown"

    AssignmentRun(harness, AssignmentOf(AssignmentOperator.AddAssign, target, AssignmentName("handler")), AssignmentAnswers(eventType, BuiltInTypes.Int))
    assert harness.Errors[1].Message == "'Changed' is a .NET event — it can't be subscribed to with '+='"

    AssignmentRun(harness, AssignmentOf(AssignmentOperator.SubtractAssign, target, AssignmentName("handler")), AssignmentAnswers(eventType, BuiltInTypes.Int))
    assert harness.Errors[2].Message == "'Changed' is a .NET event — it can't be unsubscribed with '-='"
    assert AssignmentCodes(harness.Errors) == "317,317,317"
}

test "the event target is rendered from the AST, through every transparent wrapper" {
    inner := AssignmentMember(AssignmentName("a"), "b", false)
    assert AnalyzerAssignment.RenderEventTarget(inner) == "a.b"

    parenthesized: Expression = new ParenthesizedExpression(inner, 3, 4)
    assert AnalyzerAssignment.RenderEventTarget(parenthesized) == "a.b"

    thisExpression: Expression = new ThisExpression(3, 4)
    assert AnalyzerAssignment.RenderEventTarget(AssignmentMember(thisExpression, "b", false)) == "this.b"

    literal: Expression = new IntLiteralExpression("1", 3, 4)
    assert AnalyzerAssignment.RenderEventTarget(literal) == "<event>"
}

// ---- the assignability front door ----------------------------------------------------------------------

test "THE FRONT DOOR: a value that is not assignable to the target is refused by NAME" {
    harness := AssignmentDefault()
    steps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.String))

    assert steps.Count == 2
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Type mismatch in assignment — expected 'int' but got 'string'"
    assert AssignmentCodes(harness.Errors) == "202"
    // The BARE rendering carries neither the snippet nor the two type names.
    assert harness.Errors[0].SourceSnippet == null

    // The store still answers the TARGET'S type: a refused assignment is still an assignment, and the
    // expression it sits inside should not cascade a second complaint.
    assert harness.LastResult == "int"
}

test "THE FRONT DOOR CLOSES ON A CLOSED-GENERIC MISMATCH, which the emitter cannot catch" {
    harness := AssignmentDefault()
    // A construction is bound to a TYPED local before it is widened into a `List<TypeInfo>`: the
    // columnar surface does not widen a derived construction inside a call's argument list.
    pointElement: TypeInfo = AssignmentPlainStruct("Pt")
    pointArguments := new List<TypeInfo>()
    pointArguments.Add(pointElement)
    pointList: TypeInfo = new GenericTypeInfo("List", pointArguments)
    rectangleElement: TypeInfo = AssignmentPlainStruct("Rs")
    rectangleArguments := new List<TypeInfo>()
    rectangleArguments.Add(rectangleElement)
    rectangleList: TypeInfo = new GenericTypeInfo("List", rectangleArguments)

    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(pointList, rectangleList))

    assert harness.Errors.Count == 1
    assert AssignmentCodes(harness.Errors) == "202"

    // The same instantiation on both sides is silent.
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(pointList, pointList))
    assert harness.Errors.Count == 1
}

test "the RICH rendering is used when a source snippet and a file path both exist" {
    harness := AssignmentHarnessWith("func main() {\n    total := 1\n    total = \"text\"\n}\n")
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.String))

    assert harness.Errors.Count == 1
    assert AssignmentCodes(harness.Errors) == "202"

    // The rich builder is the one that carries the SOURCE SNIPPET and the two TYPE NAMES a developer
    // reads; the bare report carries none of them, which is the whole difference between the two
    // renderings.
    assert harness.Errors[0].SourceSnippet != null
    assert harness.Errors[0].ActualType == "string"
    assert harness.Errors[0].ExpectedType == "int"

    // AND THE SENTENCE IS NOT PART OF THE DIFFERENCE. The route production actually calls used to
    // trade this sentence away for the snippet; it now carries both.
    assert harness.Errors[0].Message == "Type mismatch in assignment — expected 'int' but got 'string'"
}

// ---- the compound form -----------------------------------------------------------------------------------

// THE COMPOUND RULE RUNS ONLY WHEN THE VALUE IS ALREADY ASSIGNABLE, which is why the shape that
// reaches it is `byte += byte` and not `byte += int`: the latter never gets past the front door, and a
// contract written on it would be testing the front door instead of the operator question.
test "a COMPOUND assignment asks the operator family what the binary form is worth" {
    harness := AssignmentDefault()
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.AddAssign), AssignmentAnswers(BuiltInTypes.Byte, BuiltInTypes.Byte))

    // `byte + byte` is an `int` — binary numeric promotion — which cannot be stored back into a `byte`.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "The '+=' assignment produces 'int', which can't be stored in 'byte'"
    assert AssignmentCodes(harness.Errors) == "202"
    assert harness.LastResult == "unknown"

    // `byte += int` never reaches the rule at all: the front door refuses it first, and says so.
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.AddAssign), AssignmentAnswers(BuiltInTypes.Byte, BuiltInTypes.Int))
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "Type mismatch in assignment — expected 'byte' but got 'int'"
}

test "a compound form whose result FITS is silent, and a plain '=' never asks at all" {
    harness := AssignmentDefault()
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.AddAssign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))
    assert harness.Errors.Count == 0

    // The SAME operand pair under a plain `=` is silent, which is the proof that the compound
    // question is asked by the OPERATOR and not by the assignment.
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.Assign), AssignmentAnswers(BuiltInTypes.Byte, BuiltInTypes.Byte))
    assert harness.Errors.Count == 0
}

test "an UNKNOWN on either side declines the compound rule rather than guessing" {
    harness := AssignmentDefault()
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.AddAssign), AssignmentAnswers(BuiltInTypes.Unknown, BuiltInTypes.Int))
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.AddAssign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Unknown))
    assert harness.Errors.Count == 0
}

test "'+=' ON A DELEGATE-LIKE TARGET SKIPS THE RULE, because combination is not arithmetic" {
    harness := AssignmentDefault()
    parameterTypes := new List<TypeInfo>()
    action: TypeInfo = new GenericTypeInfo("Action", parameterTypes)

    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.AddAssign), AssignmentAnswers(action, action))
    assert harness.Errors.Count == 0

    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.SubtractAssign), AssignmentAnswers(action, action))
    assert harness.Errors.Count == 0

    // A MULTIPLY on the same target is not a combination and is still asked.
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.MultiplyAssign), AssignmentAnswers(action, action))
    assert harness.Errors.Count == 1
}

// ---- '??=' ---------------------------------------------------------------------------------------------

test "'??=' on a target that can never be null REPORTS AND CONTINUES" {
    harness := AssignmentDefault()
    steps := AssignmentRun(harness, AssignmentSimple(AssignmentOperator.NullCoalesceAssign), AssignmentAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    // Two steps: it is the only gate that does not end the walk.
    assert steps.Count == 2
    assert harness.Errors[0].Message == "The left side of '??=' has type 'int', which can't be null"
    assert AssignmentCodes(harness.Errors) == "202"
    assert harness.LastResult == "int"
}

test "a nullable, a reference type, a generic parameter and unknown all pass the '??=' rule" {
    harness := AssignmentDefault()
    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.NullCoalesceAssign), AssignmentAnswers(nullable, BuiltInTypes.Int))
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.NullCoalesceAssign), AssignmentAnswers(BuiltInTypes.String, BuiltInTypes.String))
    AssignmentRun(harness, AssignmentSimple(AssignmentOperator.NullCoalesceAssign), AssignmentAnswers(BuiltInTypes.Unknown, BuiltInTypes.Int))

    assert harness.Errors.Count == 0
}

// ---- NL322 ----------------------------------------------------------------------------------------------

// NL322 END TO END, THROUGH THE WALK. The capture table is open exactly at the target step, so this
// is where a driver would have recorded the chain's types — and the report fires when the target has
// answered, not before.
test "NL322 names WHICH temporary the receiver chain bottomed out in" {
    harness := AssignmentDefault()
    probeType: TypeInfo = new ReflectionTypeInfo(typeof(AssignmentValueProbe))
    structType: TypeInfo = AssignmentPlainStruct("Pt")

    box := AssignmentName("box")
    AssignmentDeclare(harness, "box", probeType)
    propertyHop := AssignmentMember(box, "Count", false)
    target := AssignmentMember(propertyHop, "x", false)

    state := harness.Arm.Begin(AssignmentOf(AssignmentOperator.Assign, target, AssignmentName("source")))
    targetStep := harness.Arm.NextStep(state)

    assert targetStep != null
    assert harness.Ambient.InWriteTarget

    table := harness.Ambient.WriteTargetExpressionTypes
    assert table != null
    table[box] = probeType
    table[propertyHop] = structType
    table[target] = BuiltInTypes.Int
    harness.Arm.Supply(state, BuiltInTypes.Int)

    valueStep := harness.Arm.NextStep(state)
    assert valueStep != null
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Cannot assign to 'x' because its receiver is a temporary copy of 'Pt', not a variable"
    assert AssignmentCodes(harness.Errors) == "322"

    harness.Arm.Supply(state, BuiltInTypes.Int)
    assert AssignmentTypeText(harness.Arm.Result(state)) == "int"
}

// THE FOUR RECEIVER SHAPES GET FOUR DIFFERENT WORDS, because the fix is different in each case.
test "the offending receiver is described by WHAT IT IS" {
    harness := AssignmentDefault()
    structType: TypeInfo = AssignmentPlainStruct("Pt")

    callReceiver := AssignmentCall("make")
    callTypes := new Dictionary<object, TypeInfo>()
    callTypes[callReceiver] = structType
    harness.Arm.CheckMemberWriteReceiverIsVariable(new MemberAccessExpression(callReceiver, "x", false, 3, 5), callTypes)
    assert harness.Errors[0].Message == "Cannot assign to 'x' because its receiver is a temporary copy of 'Pt', not a variable"
    assert harness.Errors[0].Suggestion == "Copy the value into a local first, modify the local, then store the whole value back"
}

test "an ARRAY ELEMENT is a variable and a CALL RESULT is not" {
    harness := AssignmentDefault()
    elementType: TypeInfo = AssignmentPlainStruct("Pt")
    arrayType: TypeInfo = new ArrayTypeInfo(elementType)
    structType: TypeInfo = AssignmentPlainStruct("Pt")

    elementReceiver: Expression = new IndexAccessExpression(AssignmentName("xs"), new IntLiteralExpression("0", 3, 9), false, 3, 5)
    target := AssignmentMember(elementReceiver, "x", false)
    types := new Dictionary<object, TypeInfo>()
    types[elementReceiver] = structType
    types[AssignmentName("xs")] = arrayType

    // The array receiver has to be the SAME node instance the chain names.
    arrayName := AssignmentName("xs")
    elementOfNamed: Expression = new IndexAccessExpression(arrayName, new IntLiteralExpression("0", 3, 9), false, 3, 5)
    namedTypes := new Dictionary<object, TypeInfo>()
    namedTypes[elementOfNamed] = structType
    namedTypes[arrayName] = arrayType
    assert harness.Arm.FindValueCopyReceiver(elementOfNamed, namedTypes) == null

    callReceiver: Expression = AssignmentCall("make")
    callTypes := new Dictionary<object, TypeInfo>()
    callTypes[callReceiver] = structType
    offender := harness.Arm.FindValueCopyReceiver(callReceiver, callTypes)
    assert offender != null
}

test "an UNRESOLVABLE hop and a REFERENCE-typed receiver both stay silent" {
    harness := AssignmentDefault()
    unknownReceiver := AssignmentName("mystery")
    assert harness.Arm.FindValueCopyReceiver(unknownReceiver, new Dictionary<object, TypeInfo>()) == null

    referenceTypes := new Dictionary<object, TypeInfo>()
    referenceCall: Expression = AssignmentCall("make")
    referenceTypes[referenceCall] = BuiltInTypes.String
    assert harness.Arm.FindValueCopyReceiver(referenceCall, referenceTypes) == null
}

// ---- the arm's own shape rules --------------------------------------------------------------------------

test "a discard is only a bare '_', and a parenthesised name is an assignable target" {
    assert AnalyzerAssignment.IsDiscardTarget(AssignmentName("_"))
    assert !AnalyzerAssignment.IsDiscardTarget(AssignmentName("total"))

    parenthesized: Expression = new ParenthesizedExpression(AssignmentName("total"), 3, 4)
    assert AnalyzerAssignment.IsAssignmentTarget(parenthesized)
    assert AnalyzerAssignment.IsAssignmentTarget(AssignmentMember(AssignmentName("box"), "count", false))

    literal: Expression = new IntLiteralExpression("1", 3, 5)
    assert !AnalyzerAssignment.IsAssignmentTarget(literal)

    call: Expression = AssignmentCall("make")
    assert !AnalyzerAssignment.IsAssignmentTarget(call)
}
