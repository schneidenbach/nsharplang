namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT MAY BE DONE TO A SoA COLUMN BY A CALL.
//
// Every member behind these was `private` in `Analyzer.cs`, reachable only by writing an
// `NSHARP_EXPERIMENTAL_SOA=1` program and reading a diagnostic, so this is their first DIRECT
// pinning. They go at the decisions a reader cannot recover from any one arm:
//
// (1) THE ALLOW-LISTS ARE PARAMETER TABLES, NOT METHOD TABLES. `Array.Copy`'s array parameters are 0
// and 1 in its three-argument form and 0 and 2 in its five-argument form, so the SAME method is
// silent at one position and refuses at another.
//
// (2) `Array.Sort`'s POSITIONS ARE A FUNCTION OF ITS ARITY: one array at 0 for the one- and
// three-argument forms, a keys/items PAIR at 0 and 1 for the two- and four-argument forms, and
// nothing at all for any other arity.
//
// (3) A METHOD WITH ITS OWN DIAGNOSTIC IS SKIPPED RATHER THAN REPORTED TWICE. `Sort`, `Reverse` and
// `Resize` are handled by gate 1 and by the write-target family, so gate 2 stays silent at their
// array parameters.
//
// (4) THE GATES ARE ORDERED AND THE FIRST ONE THAT FIRES WINS. `Array.Sort(points.x)` is a MUTATION
// report, never the "passed to Array method" one, even though both would match.
//
// (5) A METHOD GROUP IS AN INSTANCE REFERENCE ONLY IF EVERY CANDIDATE IS. One static overload in the
// group, or an empty group, answers no.
//
// (6) A NAME IN SCOPE SHADOWS THE TYPE. `Array` bound as a symbol is not `System.Array`, and that is
// what stops a local called `Array` from turning every call on it into an SoA diagnostic.
//
// (7) A `ref`/`out` ARGUMENT IS SKIPPED BY THE ESCAPE GATE, because a column IS addressable and the
// write-target family has already ruled on it.
class SoaCallHarness {
    Rule: AnalyzerSoaDirectColumnCalls
    Escape: AnalyzerSoaEscape
    Scopes: AnalyzerScopeStack
    Errors: List<CompilerError>

    constructor(rule: AnalyzerSoaDirectColumnCalls, escape: AnalyzerSoaEscape, scopes: AnalyzerScopeStack, errors: List<CompilerError>) {
        Rule = rule
        Escape = escape
        Scopes = scopes
        Errors = errors
    }
}

func SoaCallHarnessOf(): SoaCallHarness {
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
    sink.BeginAnalysis(Path.GetFullPath("soa-direct-column-call-contract.nl"), null)
    spans := new AnalyzerDiagnosticSpans(sink)
    usingAliases := new Dictionary<string, string>(StringComparer.Ordinal)
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal)
    namespaces := new List<string>()
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, usingAliases)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, usingAliases, importedSymbols, importedDeclarations, model, bindings)
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
    escape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, escape)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)
    identifierResolution := new AnalyzerIdentifierResolution(sink, scopes, resolver, discovery, probe, functionTypes, ambient, nullFlow, extensions, members, model, bindings)
    memberAccess := new AnalyzerMemberAccess(sink, spans, scopes, context, nullFlow, escape, ambient, provider, discovery, probe, substitution, identifierResolution, extensions, namespaces, usingAliases, importedSymbols, importedDeclarations, assemblies, members, clrConversion, extensionResolution, bindings)
    constantFacts := new AnalyzerConstantExpressionFacts(scopes, context)
    indexAccess := new AnalyzerIndexAccess(sink, spans, context, ambient, nullFlow, escape, memberAccess, constantFacts)
    writeTargets := new AnalyzerWriteTargets(sink, spans, scopes, context, substitution, clrConversion, ambient, escape, memberAccess, indexAccess)
    rule := new AnalyzerSoaDirectColumnCalls(sink, spans, scopes, context, clrConversion, escape, memberAccess, writeTargets)
    return new SoaCallHarness(rule, escape, scopes, errors)
}

// ── the table every contract measures against ────────────────────────────────

func SoaCallColumns(): List<SoaColumnInfo> {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 0, 0), 1, 1))
    columns.Add(new SoaColumnInfo("y", new SimpleTypeReference("int", 0, 0), 2, 1))
    return columns
}

func SoaCallTableType(): TypeInfo {
    table: TypeInfo = new SoaRecordTypeInfo(new SoaRecordDeclarationInfo("Points", SoaCallColumns(), 1, 1))
    return table
}

func SoaCallDeclare(harness: SoaCallHarness, name: string, declaredType: TypeInfo) {
    harness.Scopes.Peek().Symbols[name] = declaredType
}

func SoaCallDeclareTable(harness: SoaCallHarness) {
    SoaCallDeclare(harness, "points", SoaCallTableType())
}

// ── AST builders ─────────────────────────────────────────────────────────────

func SoaCallName(name: string): Expression {
    expression: Expression = new IdentifierExpression(name, 4, 9)
    return expression
}

func SoaCallMember(receiver: Expression, memberName: string): Expression {
    expression: Expression = new MemberAccessExpression(receiver, memberName, false, 4, 9)
    return expression
}

// `points.x` — a column read the DECLARED fallback recognises once `points` is a table in scope.
func SoaCallColumn(): Expression {
    return SoaCallMember(SoaCallName("points"), "x")
}

func SoaCallArgs(values: List<Expression>): List<Argument> {
    args := new List<Argument>()
    index := 0
    while index < values.Count {
        args.Add(new Argument(null, values[index], ArgumentModifier.None))
        index = index + 1
    }

    return args
}

func SoaCallValues0(): List<Expression> {
    return new List<Expression>()
}

func SoaCallValues1(first: Expression): List<Expression> {
    values := new List<Expression>()
    values.Add(first)
    return values
}

func SoaCallValues2(first: Expression, second: Expression): List<Expression> {
    values := SoaCallValues1(first)
    values.Add(second)
    return values
}

func SoaCallValues3(first: Expression, second: Expression, third: Expression): List<Expression> {
    values := SoaCallValues2(first, second)
    values.Add(third)
    return values
}

func SoaCallValues5(first: Expression, second: Expression, third: Expression, fourth: Expression, fifth: Expression): List<Expression> {
    values := SoaCallValues3(first, second, third)
    values.Add(fourth)
    values.Add(fifth)
    return values
}

func SoaCallInt(text: string): Expression {
    literal: Expression = new IntLiteralExpression(text, 4, 20)
    return literal
}

// `Array.<method>(<args>)` — the receiver is the bare name `Array`, which is the static array target
// whenever nothing in scope claims that name.
func SoaCallArrayCall(methodName: string, values: List<Expression>): CallExpression {
    return new CallExpression(SoaCallMember(SoaCallName("Array"), methodName), SoaCallArgs(values), null, 4, 5)
}

func SoaCallNamedArrayCall(methodName: string, parameterName: string, value: Expression): CallExpression {
    args := new List<Argument>()
    args.Add(new Argument(parameterName, value, ArgumentModifier.None))
    return new CallExpression(SoaCallMember(SoaCallName("Array"), methodName), args, null, 4, 5)
}

func SoaCallMessages(harness: SoaCallHarness): string {
    text := ""
    index := 0
    while index < harness.Errors.Count {
        if index > 0 {
            text = text + " | "
        }

        text = text + harness.Errors[index].Message
        index = index + 1
    }

    return text
}

// A reflected method GROUP built from a real type's overloads, so the instance/static question is
// answered by metadata rather than by a stub.
func SoaCallMethods(owner: Type, name: string): MethodInfo[] {
    all := owner.GetMethods()
    matched := new List<MethodInfo>()
    index := 0
    while index < all.Length {
        if all[index].get_Name() == name {
            matched.Add(all[index])
        }

        index = index + 1
    }

    return matched.ToArray()
}

func SoaCallInstanceMethodType(): TypeInfo {
    methods := SoaCallMethods(typeof(int[]), "GetLength")
    reference: TypeInfo = new ReflectionMethodInfo(methods[0])
    return reference
}

func SoaCallInstanceGroupType(): TypeInfo {
    reference: TypeInfo = new ReflectionMethodGroupInfo(SoaCallMethods(typeof(int[]), "GetValue"))
    return reference
}

func SoaCallEmptyGroupType(): TypeInfo {
    reference: TypeInfo = new ReflectionMethodGroupInfo(new MethodInfo[](0))
    return reference
}

func SoaCallStaticMethodType(): TypeInfo {
    methods := SoaCallMethods(typeof(string), "IsNullOrEmpty")
    reference: TypeInfo = new ReflectionMethodInfo(methods[0])
    return reference
}

func SoaCallWrapType(): TypeInfo {
    functionType := new FunctionTypeInfo()
    functionType.SyntheticName = "wrap"
    carrier: TypeInfo = functionType
    return carrier
}

// ------------------------------------------------------------------ contracts

test "Array.Sort on a column is refused as a table-member MUTATION, not as an unsupported method" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert harness.Rule.ReportDirectColumnCallIfNeeded(SoaCallArrayCall("Sort", SoaCallValues1(SoaCallColumn())), BuiltInTypes.Unknown)
    assert harness.Errors.Count == 1
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot be sorted directly"
}

test "Array.Reverse names its own action word" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert harness.Rule.ReportMutatingArrayCallIfNeeded(SoaCallArrayCall("Reverse", SoaCallValues1(SoaCallColumn())))
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot be reversed directly"
}

test "a NAMED keys argument reaches the mutation rule the positional one does" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert harness.Rule.ReportMutatingArrayCallIfNeeded(SoaCallNamedArrayCall("Sort", "keys", SoaCallColumn()))
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot be sorted directly"
}

test "a named argument that is NOT an array parameter of Sort is not the mutation rule's business" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert !harness.Rule.ReportMutatingArrayCallIfNeeded(SoaCallNamedArrayCall("Sort", "comparer", SoaCallColumn()))
    assert harness.Errors.Count == 0
}

test "Array.Sort's array POSITIONS are a function of its arity, and an unknown arity has none" {
    assert AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(1, 0)
    assert !AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(1, 1)
    assert AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(2, 0)
    assert AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(2, 1)
    assert AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(3, 0)
    assert !AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(3, 1)
    assert AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(4, 0)
    assert AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(4, 1)
    assert !AnalyzerSoaDirectColumnCalls.IsPositionalArraySortParameter(5, 0)
}

test "Array.Fill and Array.Clear take a column at position 0 in SILENCE" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert !harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(SoaCallArrayCall("Fill", SoaCallValues2(SoaCallColumn(), SoaCallInt("0"))))
    assert !harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(SoaCallArrayCall("Clear", SoaCallValues3(SoaCallColumn(), SoaCallInt("0"), SoaCallInt("1"))))
    assert harness.Errors.Count == 0
}

test "Array.Copy's array positions are 0 and 1 at arity three and 0 and 2 at arity five" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    // arity 3: (source, destination, length) — the column is the destination, which is an array slot
    assert !harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(
        SoaCallArrayCall("Copy", SoaCallValues3(SoaCallName("other"), SoaCallColumn(), SoaCallInt("3")))
    )

    // arity 5: (source, sourceIndex, destination, destinationIndex, length) — position 1 is an INDEX,
    // so a column there is not a handled array parameter and IS refused
    assert harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(
        SoaCallArrayCall("Copy", SoaCallValues5(SoaCallName("other"), SoaCallColumn(), SoaCallName("dest"), SoaCallInt("0"), SoaCallInt("3")))
    )
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot be passed to Array method 'Copy' directly"
}

test "an Array method on neither list refuses the column and names the METHOD" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(SoaCallArrayCall("IndexOf", SoaCallValues2(SoaCallColumn(), SoaCallInt("1"))))
    assert harness.Errors.Count == 1
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot be passed to Array method 'IndexOf' directly"
    assert harness.Errors[0].Length == 7
}

test "a method with its OWN diagnostic is skipped by this gate rather than reported twice" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert !harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(SoaCallArrayCall("Resize", SoaCallValues2(SoaCallColumn(), SoaCallInt("4"))))
    assert !harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(SoaCallArrayCall("Sort", SoaCallValues1(SoaCallColumn())))
    assert !harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(SoaCallArrayCall("Reverse", SoaCallValues1(SoaCallColumn())))
    assert harness.Errors.Count == 0
}

test "a call with no arguments never reaches either static-array gate" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert !harness.Rule.ReportMutatingArrayCallIfNeeded(SoaCallArrayCall("Sort", SoaCallValues0()))
    assert !harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(SoaCallArrayCall("IndexOf", SoaCallValues0()))
    assert harness.Errors.Count == 0
}

test "an instance array method CALLED on a column and TAKEN as a value differ by two words" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)
    call := new CallExpression(SoaCallMember(SoaCallColumn(), "GetLength"), SoaCallArgs(SoaCallValues1(SoaCallInt("0"))), null, 4, 5)

    assert harness.Rule.ReportUnsupportedArrayInstanceCallIfNeeded(call, SoaCallInstanceMethodType())
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot call array method 'GetLength' directly"

    valueHarness := SoaCallHarnessOf()
    SoaCallDeclareTable(valueHarness)
    assert valueHarness.Rule.ReportUnsupportedArrayInstanceMethodReferenceIfNeeded(SoaCallMember(SoaCallColumn(), "GetLength"), SoaCallInstanceMethodType(), false)
    assert SoaCallMessages(valueHarness) == "SoA table member 'x' cannot use array method 'GetLength' as a value"
}

test "a method GROUP of instance overloads is an instance reference" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert harness.Rule.IsRuntimeArrayInstanceMethodReference(SoaCallInstanceGroupType())
    assert harness.Rule.ReportUnsupportedArrayInstanceMethodReferenceIfNeeded(SoaCallMember(SoaCallColumn(), "GetValue"), SoaCallInstanceGroupType(), true)
}

test "an EMPTY group and a STATIC method are not instance references" {
    harness := SoaCallHarnessOf()

    assert !harness.Rule.IsRuntimeArrayInstanceMethodReference(SoaCallEmptyGroupType())
    assert !harness.Rule.IsRuntimeArrayInstanceMethodReference(SoaCallStaticMethodType())
    assert !harness.Rule.IsRuntimeArrayInstanceMethodReference(BuiltInTypes.Int)
}

test "a column used as an ordinary RECEIVER is named before any argument is looked at" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)
    call := new CallExpression(SoaCallMember(SoaCallColumn(), "Where"), SoaCallArgs(SoaCallValues1(SoaCallColumn())), null, 4, 5)

    assert harness.Rule.ReportUnsupportedCallArgumentIfNeeded(call, BuiltInTypes.Int)
    assert harness.Errors.Count == 1
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot be used as the receiver for 'Where' directly"
}

test "an UNKNOWN callee type suppresses the receiver arm and leaves the arguments to answer" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)
    call := new CallExpression(SoaCallMember(SoaCallColumn(), "Where"), SoaCallArgs(SoaCallValues1(SoaCallColumn())), null, 4, 5)

    assert harness.Rule.ReportUnsupportedCallArgumentIfNeeded(call, BuiltInTypes.Unknown)
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot be passed as an argument directly"
}

test "a ref or out argument is skipped, because a column IS addressable" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)
    args := new List<Argument>()
    args.Add(new Argument(null, SoaCallColumn(), ArgumentModifier.Ref))
    args.Add(new Argument(null, SoaCallColumn(), ArgumentModifier.Out))
    call := new CallExpression(SoaCallName("take"), args, null, 4, 5)

    assert !harness.Rule.ReportUnsupportedCallArgumentIfNeeded(call, BuiltInTypes.Int)
    assert harness.Errors.Count == 0
}

test "the synthesised wrap constructor may always take a column" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)
    call := new CallExpression(SoaCallName("wrap"), SoaCallArgs(SoaCallValues1(SoaCallColumn())), null, 4, 5)

    assert harness.Rule.IsAllowedCall(call, SoaCallWrapType())
    assert !harness.Rule.ReportUnsupportedCallArgumentIfNeeded(call, SoaCallWrapType())
    assert harness.Errors.Count == 0
}

test "a static Array call that reached gate 4 is allowed rather than refused a second time" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    assert harness.Rule.IsAllowedCall(SoaCallArrayCall("Fill", SoaCallValues2(SoaCallColumn(), SoaCallInt("0"))), BuiltInTypes.Int)
    assert !harness.Rule.ReportUnsupportedCallArgumentIfNeeded(SoaCallArrayCall("Fill", SoaCallValues2(SoaCallColumn(), SoaCallInt("0"))), BuiltInTypes.Int)
    assert harness.Errors.Count == 0
}

test "the bare name Array is the static array target, and a SYMBOL of that name vetoes it" {
    harness := SoaCallHarnessOf()

    assert harness.Rule.IsStaticArrayTarget(SoaCallName("Array"))
    assert harness.Rule.IsStaticArrayTarget(new ParenthesizedExpression(SoaCallName("Array"), 4, 9))
    assert !harness.Rule.IsStaticArrayTarget(SoaCallName("Widget"))

    SoaCallDeclare(harness, "Array", BuiltInTypes.Int)
    assert !harness.Rule.IsStaticArrayTarget(SoaCallName("Array"))
}

test "the spelled-out System.Array is the static array target, and its qualifier shadows too" {
    harness := SoaCallHarnessOf()

    assert harness.Rule.IsStaticArrayTarget(SoaCallMember(SoaCallName("System"), "Array"))
    assert !harness.Rule.IsStaticArrayTarget(SoaCallMember(SoaCallName("System"), "Collections"))

    SoaCallDeclare(harness, "System", BuiltInTypes.Int)
    assert !harness.Rule.IsStaticArrayTarget(SoaCallMember(SoaCallName("System"), "Array"))
}

test "a shadowed Array receiver takes the whole mutating gate with it" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)
    SoaCallDeclare(harness, "Array", BuiltInTypes.Int)

    assert !harness.Rule.ReportMutatingArrayCallIfNeeded(SoaCallArrayCall("Sort", SoaCallValues1(SoaCallColumn())))
    assert !harness.Rule.ReportUnsupportedStaticArrayCallIfNeeded(SoaCallArrayCall("IndexOf", SoaCallValues2(SoaCallColumn(), SoaCallInt("1"))))
    assert harness.Errors.Count == 0
}

test "an EXTERNAL type named Array answers the System.Array question without any metadata" {
    harness := SoaCallHarnessOf()
    shortName: TypeInfo = new ExternalTypeInfo("Array")
    longName: TypeInfo = new ExternalTypeInfo("System.Array")
    other: TypeInfo = new ExternalTypeInfo("Arrays")

    assert harness.Rule.IsSystemArrayTypeInfo(shortName)
    assert harness.Rule.IsSystemArrayTypeInfo(longName)
    assert !harness.Rule.IsSystemArrayTypeInfo(other)
}

test "a call on a table that touches no column at all is silent through every gate" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)
    call := SoaCallArrayCall("IndexOf", SoaCallValues2(SoaCallName("other"), SoaCallInt("1")))

    assert !harness.Rule.ReportDirectColumnCallIfNeeded(call, BuiltInTypes.Int)
    assert harness.Errors.Count == 0
}

test "the four gates run in order and the first that fires ends the question" {
    harness := SoaCallHarnessOf()
    SoaCallDeclareTable(harness)

    // `Array.Sort(points.x)` matches gate 1 AND would match gate 4's argument arm; gate 1 wins and
    // exactly ONE report is written.
    assert harness.Rule.ReportDirectColumnCallIfNeeded(SoaCallArrayCall("Sort", SoaCallValues1(SoaCallColumn())), BuiltInTypes.Int)
    assert harness.Errors.Count == 1
    assert SoaCallMessages(harness) == "SoA table member 'x' cannot be sorted directly"
}
