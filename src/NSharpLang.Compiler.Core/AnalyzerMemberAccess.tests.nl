namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the member arm — what `a.b` MEANS.
//
// Every member behind these contracts was `private` in `Analyzer.cs`, so nothing named any of them:
// the six gates, the four codes and the receiver classification were pinned only indirectly, through
// end-to-end diagnostics on programs that happened to reach them. This is their first DIRECT pinning,
// and it goes at the decisions that read like plumbing and are not:
//
//   * the IMPORT-ALIAS form, which answers before any walk and whose miss is a THIRD shape of NL303
//     naming the alias rather than a type;
//   * the NULLABLE fork's asymmetry — `Value` on a nullable is warned about and the SAME access on a
//     narrowed origin is silent, which is the difference between a useful warning and a false one;
//   * the RECEIVER CLASSIFICATION, because whether a receiver names a TYPE decides whether static
//     members are in scope, and a local of that name vetoes it;
//   * the QUALIFIED-EXTERNAL-TYPE vetoes, whose ORDER is what stops an assembly type from shadowing
//     anything the developer wrote;
//   * the NULL-CONDITIONAL RESULT WRAP's four exceptions, none of which has a nullable form;
//   * the SHOULD-REPORT rule, which is a question about the RECEIVER and not about the name, and
//     which is what keeps `object` and an unreliable assembly silent;
//   * the WALK PROTOCOL itself: which forms take a step, which take none, and that the report step is
//     asked LAST so the answer the walk was holding cannot escape ahead of it.
class MemberAccessHarness {
    Arm: AnalyzerMemberAccess
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Model: SemanticModel
    Bindings: BindingMap
    Sink: AnalyzerDiagnosticSink
    Context: AnalyzerDeclarationContext
    ImportedSymbols: Dictionary<string, Dictionary<string, TypeInfo>>
    ImportedDeclarations: Dictionary<string, Dictionary<string, SymbolDeclaration>>
    Members: AnalyzerMemberResolution
    ExtensionResolution: AnalyzerExtensionMethodResolution

    constructor(
        arm: AnalyzerMemberAccess,
        errors: List<CompilerError>,
        scopes: AnalyzerScopeStack,
        model: SemanticModel,
        bindings: BindingMap,
        sink: AnalyzerDiagnosticSink,
        context: AnalyzerDeclarationContext,
        importedSymbols: Dictionary<string, Dictionary<string, TypeInfo>>,
        importedDeclarations: Dictionary<string, Dictionary<string, SymbolDeclaration>>,
        members: AnalyzerMemberResolution,
        extensionResolution: AnalyzerExtensionMethodResolution
    ) {
        Arm = arm
        Errors = errors
        Scopes = scopes
        Model = model
        Bindings = bindings
        Sink = sink
        Context = context
        ImportedSymbols = importedSymbols
        ImportedDeclarations = importedDeclarations
        Members = members
        ExtensionResolution = extensionResolution
    }
}

// The arm over an EMPTY project with no referenced assemblies and no metadata load context: the
// built-in keyword channel is dark, the assembly probe has nothing to find, and the CLR conversion
// funnel answers null for everything. That is deliberately the harshest configuration for the
// should-report rule, because it is the one an editor sees before the first assembly load.
func MemberArmOf(): MemberAccessHarness {
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
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    extensions := new List<FunctionDeclaration>()
    extensionResolution := new AnalyzerExtensionMethodResolution(resolver, assignability, context, functionTypes, clrConversion, extensions, namespaces, assemblies)
    members := new AnalyzerMemberResolution(functionTypes, context, substitution, resolver, clrConversion, extensionResolution, namespaces)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)
    identifierResolution := new AnalyzerIdentifierResolution(sink, scopes, resolver, discovery, probe, functionTypes, ambient, nullFlow, extensions, members, model, bindings)

    arm := new AnalyzerMemberAccess(sink, spans, scopes, context, nullFlow, soaEscape, ambient, provider, discovery, probe, substitution, identifierResolution, extensions, namespaces, usingAliases, importedSymbols, importedDeclarations, assemblies, members, clrConversion, extensionResolution, bindings)
    return new MemberAccessHarness(arm, errors, scopes, model, bindings, sink, context, importedSymbols, importedDeclarations, members, extensionResolution)
}

func MemberCodes(errors: List<CompilerError>): string {
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

func MemberTypeName(candidate: TypeInfo?): string {
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

    nullable := candidate as NullableTypeInfo
    if nullable != null {
        return "nullable(" + MemberTypeName(nullable.InnerType) + ")"
    }

    classType := candidate as ClassTypeInfo
    if classType != null {
        return "class:" + classType.Name
    }

    return "<other>"
}

func MemberAccessOf(receiverName: string, memberName: string, isNullConditional: bool): MemberAccessExpression {
    return new MemberAccessExpression(new IdentifierExpression(receiverName, 4, 1), memberName, isNullConditional, 4, 1)
}

func MemberDeclare(harness: MemberAccessHarness, name: string, declaredType: TypeInfo) {
    harness.Scopes.Peek().Symbols[name] = declaredType
}

func MemberAliasSymbols(harness: MemberAccessHarness, alias: string): Dictionary<string, TypeInfo> {
    existing: Dictionary<string, TypeInfo>? = null
    if harness.ImportedSymbols.TryGetValue(alias, out existing) && existing != null {
        return existing
    }

    created := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    harness.ImportedSymbols[alias] = created
    return created
}

func MemberAliasDeclarations(harness: MemberAccessHarness, alias: string): Dictionary<string, SymbolDeclaration> {
    existing: Dictionary<string, SymbolDeclaration>? = null
    if harness.ImportedDeclarations.TryGetValue(alias, out existing) && existing != null {
        return existing
    }

    created := new Dictionary<string, SymbolDeclaration>(StringComparer.Ordinal)
    harness.ImportedDeclarations[alias] = created
    return created
}

// One full turn of the protocol with a receiver answer supplied for the walk step. The report is no
// longer a step, so it is observed where it now happens: THROUGH THE SINK. That is a stronger
// observation than the retired kind-2 count, because it proves the report was RENDERED and not merely
// requested.
func MemberDriveWith(harness: MemberAccessHarness, node: Expression, receiverAnswer: TypeInfo): MemberDriveTrace {
    trace := new MemberDriveTrace()
    before := harness.Errors.Count
    state := harness.Arm.Begin(node)
    step := harness.Arm.NextStep(state)
    while step != null {
        trace.Kinds = trace.Kinds + step.Kind.ToString()
        harness.Arm.Supply(state, receiverAnswer)
        step = harness.Arm.NextStep(state)
    }

    trace.Answer = MemberTypeName(harness.Arm.Result(state))
    trace.Reports = harness.Errors.Count - before
    if trace.Reports > 0 {
        reported := harness.Errors[harness.Errors.Count - 1]
        trace.ReportedMessage = reported.Message
    }

    return trace
}

class MemberDriveTrace {
    Kinds: string
    Reports: int
    Answer: string
    ReportedMessage: string

    constructor() {
        Kinds = ""
        Reports = 0
        Answer = ""
        ReportedMessage = ""
    }
}

func MemberSampleClass(name: string): ClassTypeInfo {
    return new ClassTypeInfo(name, 2, 1, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
}

// `List<argument>` as the analyzer builds it: a REFLECTED definition with whatever the program wrote
// in its type-argument position — including a type that has no CLR handle at all.
func MemberClosedListOf(argument: TypeInfo): GenericTypeInfo {
    typeArguments := new List<TypeInfo>()
    typeArguments.Add(argument)
    return new GenericTypeInfo("List", typeArguments, new ReflectionTypeInfo(typeof(List<int>).GetGenericTypeDefinition()))
}

// ---- the walk protocol ---------------------------------------------------------------------------

test "a node that is not a member access finishes at Begin and asks for nothing" {
    harness := MemberArmOf()

    state := harness.Arm.Begin(new IdentifierExpression("value", 4, 1))

    assert harness.Arm.NextStep(state) == null
    assert MemberTypeName(harness.Arm.Result(state)) == "unknown"
    assert harness.Errors.Count == 0
}

test "an ordinary member access asks for exactly ONE step, and it is the RECEIVER node" {
    harness := MemberArmOf()
    MemberDeclare(harness, "widget", BuiltInTypes.String)
    node := MemberAccessOf("widget", "Length", false)

    state := harness.Arm.Begin(node)
    step := harness.Arm.NextStep(state)

    assert step != null
    assert step.Kind == 1
    assert step.Node == node.Object
}

test "the receiver step's answer is what every later gate reasons about" {
    harness := MemberArmOf()
    MemberDeclare(harness, "box", BuiltInTypes.Int)
    trace := MemberDriveWith(harness, MemberAccessOf("box", "HasValue", false), new NullableTypeInfo(BuiltInTypes.Int))

    // `HasValue` is answered by the nullable fork, which only fires because the SUPPLIED answer was
    // nullable. The node itself says nothing about nullability.
    assert trace.Kinds == "1"
    assert trace.Answer == "simple:bool"
}

test "a null answer to the receiver step is `unknown`, not a missing one" {
    harness := MemberArmOf()
    MemberDeclare(harness, "box", BuiltInTypes.Int)

    state := harness.Arm.Begin(MemberAccessOf("box", "Length", false))
    harness.Arm.NextStep(state)
    harness.Arm.Supply(state, null)

    assert harness.Arm.NextStep(state) == null
    assert MemberTypeName(harness.Arm.Result(state)) == "unknown"
}

test "Supply outside an outstanding step changes nothing" {
    harness := MemberArmOf()
    state := harness.Arm.Begin(MemberAccessOf("widget", "Length", false))

    harness.Arm.Supply(state, BuiltInTypes.String)

    assert MemberTypeName(harness.Arm.Result(state)) == "unknown"
    assert harness.Errors.Count == 0
}

// ---- the import-alias form -----------------------------------------------------------------------

test "an aliased import's symbol answers WITHOUT a walk step" {
    harness := MemberArmOf()
    MemberAliasSymbols(harness, "text")["Trim"] = BuiltInTypes.String

    state := harness.Arm.Begin(MemberAccessOf("text", "Trim", false))

    // The alias table is not an expression, so the receiver is never analysed.
    assert harness.Arm.NextStep(state) == null
    assert MemberTypeName(harness.Arm.Result(state)) == "simple:string"
    assert harness.Errors.Count == 0
}

test "an aliased import's symbol RECORDS its binding when the alias carries a declaration" {
    harness := MemberArmOf()
    MemberAliasSymbols(harness, "text")["Trim"] = BuiltInTypes.String
    MemberAliasDeclarations(harness, "text")["Trim"] = new SymbolDeclaration("Trim", "/p/text.nl", 9, 3, "function")

    state := harness.Arm.Begin(MemberAccessOf("text", "Trim", false))
    harness.Arm.NextStep(state)

    assert harness.Bindings.GetBindingAt(harness.Sink.CurrentFilePath, 4, 2) != null
}

test "a MISS inside a known alias is its own NL303 shape and still takes no step" {
    harness := MemberArmOf()
    MemberAliasSymbols(harness, "text")["Trim"] = BuiltInTypes.String

    state := harness.Arm.Begin(MemberAccessOf("text", "Trimm", false))

    assert harness.Arm.NextStep(state) == null
    assert MemberTypeName(harness.Arm.Result(state)) == "unknown"
    assert MemberCodes(harness.Errors) == "303"
    assert harness.Errors[0].Message.Contains("import alias 'text'")
    assert harness.Errors[0].Suggestion == "Did you mean 'Trim'?"
}

test "the alias miss underlines the MEMBER name's length, never zero" {
    harness := MemberArmOf()
    MemberAliasSymbols(harness, "text")["Trim"] = BuiltInTypes.String

    harness.Arm.NextStep(harness.Arm.Begin(MemberAccessOf("text", "X", false)))

    assert harness.Errors[0].Length == 1
}

test "an EMPTY alias reports with no did-you-mean rather than crashing on an empty pool" {
    harness := MemberArmOf()
    MemberAliasSymbols(harness, "text")

    harness.Arm.NextStep(harness.Arm.Begin(MemberAccessOf("text", "Trim", false)))

    assert MemberCodes(harness.Errors) == "303"
    assert harness.Errors[0].Suggestion == null
}

test "a receiver that is not an alias at all falls through to the ordinary walk" {
    harness := MemberArmOf()
    MemberAliasSymbols(harness, "text")["Trim"] = BuiltInTypes.String

    state := harness.Arm.Begin(MemberAccessOf("other", "Trim", false))
    step := harness.Arm.NextStep(state)

    assert step != null
    assert step.Kind == 1
    assert harness.Errors.Count == 0
}

// ---- the nullable fork ---------------------------------------------------------------------------

test "`HasValue` on a nullable is bool, and it is answered without metadata" {
    harness := MemberArmOf()
    MemberDeclare(harness, "count", new NullableTypeInfo(BuiltInTypes.Int))
    trace := MemberDriveWith(harness, MemberAccessOf("count", "HasValue", false), new NullableTypeInfo(BuiltInTypes.Int))

    assert trace.Answer == "simple:bool"
    assert harness.Errors.Count == 0
}

test "`Value` on a nullable is the inner type AND is warned about" {
    harness := MemberArmOf()
    MemberDeclare(harness, "count", new NullableTypeInfo(BuiltInTypes.Int))
    trace := MemberDriveWith(harness, MemberAccessOf("count", "Value", false), new NullableTypeInfo(BuiltInTypes.Int))

    assert trace.Answer == "simple:int"
    assert MemberCodes(harness.Errors) == "907"
    assert harness.Errors[0].Message.Contains("can throw")
    // NL907 is ADVICE about a `.Value` that can throw, not a refusal to compile: the program it
    // describes is correct, and the risk is a runtime one the author may well have accepted.
    assert harness.Errors[0].Severity == ErrorSeverity.Warning
}

test "`Value` on a NARROWED nullable origin is the inner type and is SILENT" {
    harness := MemberArmOf()

    // The ENCLOSING scope holds the nullable declaration and the INNER one holds the narrowed type,
    // which is exactly the shape `AnalyzerFlowNarrowing` leaves behind inside an `if count != null`
    // branch. The arm must recognise the origin and NOT warn — the narrowing already proved the value
    // present, and warning here is the false positive that makes a nullability warning untrustworthy.
    // The origin lookup deliberately skips the INNERMOST scope, because that is the narrowed one.
    MemberDeclare(harness, "count", new NullableTypeInfo(BuiltInTypes.Int))
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 3, 1)
    MemberDeclare(harness, "count", BuiltInTypes.Int)
    trace := MemberDriveWith(harness, MemberAccessOf("count", "Value", false), BuiltInTypes.Int)

    assert trace.Answer == "simple:int"
    assert harness.Errors.Count == 0
}

test "the narrowed-origin silence ALSO finds a nullable in the INNERMOST scope" {
    harness := MemberArmOf()

    // One scope, holding the nullable declaration, and an answer of `int`. That is the GUARD-CLAUSE
    // shape — `if count == null { return }` installs its facts into the scope that also declares the
    // local, so there is no inner scope to skip — and it is the shape the converted CLI is written in.
    // The origin walk used to start one scope OUT, found nothing here, and reported NL303 for a
    // `.Value` the program had already proved safe.
    MemberDeclare(harness, "count", new NullableTypeInfo(BuiltInTypes.Int))
    trace := MemberDriveWith(harness, MemberAccessOf("count", "Value", false), BuiltInTypes.Int)

    assert trace.Answer == "simple:int"
    assert harness.Errors.Count == 0
}

test "a name that is NOT a nullable origin still falls through and reports" {
    harness := MemberArmOf()
    MemberDeclare(harness, "count", BuiltInTypes.Int)

    trace := MemberDriveWith(harness, MemberAccessOf("count", "Value", false), BuiltInTypes.Int)

    assert trace.Answer == "unknown"
    assert trace.Reports == 1
    assert MemberCodes(harness.Errors) == "303"
}

test "a NON-primitive receiver never reaches the narrowed-origin path" {
    harness := MemberArmOf()
    MemberDeclare(harness, "widget", new NullableTypeInfo(BuiltInTypes.Int))
    trace := MemberDriveWith(harness, MemberAccessOf("widget", "Value", false), MemberSampleClass("Widget"))

    // The origin lookup is gated on the receiver's answer being primitive-like, so a class-typed
    // answer falls through to ordinary resolution rather than silently unwrapping.
    assert trace.Answer == "unknown"
}

// CENSUS §FLOW5 — `Nullable<T>`'s SURFACE IS A VALUE-TYPE SURFACE.
//
// A reference `T?` is an ANNOTATION on one CLR type, not a `System.Nullable<T>`: `MarkupContent?` IS
// `MarkupContent`, and `.Value` there is whatever the CLASS declares. Answering it from the nullable
// fork typed `documentation.MarkupContent?.Value` as `MarkupContent` and warned NL907 about an
// unwrap the program never wrote — and then refused the `string?` the function actually returned.
test "`Value` on a reference nullable is NOT the unwrap and is not warned about" {
    harness := MemberArmOf()
    content := new NullableTypeInfo(MemberSampleClass("MarkupContent"))
    MemberDeclare(harness, "content", content)

    trace := MemberDriveWith(harness, MemberAccessOf("content", "Value", false), content)

    // The class declares no members in this harness, so ordinary resolution is what answers — and
    // what it answers is the point: the fork did not. The receiver is maybe-null and the access is
    // unguarded, so the ORDINARY dereference rule reports NL905 on it, which is the other half of
    // reading `.Value` as a member rather than as the unwrap.
    assert trace.Answer == "unknown"
    assert !MemberCodes(harness.Errors).Contains("907")
    assert MemberCodes(harness.Errors).Contains("905")
}

test "`HasValue` on a reference nullable is the class's own name, not the nullable's" {
    harness := MemberArmOf()
    content := new NullableTypeInfo(MemberSampleClass("MarkupContent"))
    MemberDeclare(harness, "content", content)

    trace := MemberDriveWith(harness, MemberAccessOf("content", "HasValue", false), content)

    assert trace.Answer != "simple:bool"
    assert trace.Answer == "unknown"
}

test "the same two names on a VALUE nullable still take the fork" {
    harness := MemberArmOf()
    MemberDeclare(harness, "count", new NullableTypeInfo(BuiltInTypes.Int))

    hasValue := MemberDriveWith(harness, MemberAccessOf("count", "HasValue", false), new NullableTypeInfo(BuiltInTypes.Int))
    assert hasValue.Answer == "simple:bool"

    value := MemberDriveWith(harness, MemberAccessOf("count", "Value", false), new NullableTypeInfo(BuiltInTypes.Int))
    assert value.Answer == "simple:int"
}

test "a THIRD name on a nullable falls through to ordinary resolution" {
    harness := MemberArmOf()
    MemberDeclare(harness, "count", new NullableTypeInfo(BuiltInTypes.Int))
    trace := MemberDriveWith(harness, MemberAccessOf("count", "Nonesuch", false), new NullableTypeInfo(BuiltInTypes.Int))

    assert trace.Answer == "unknown"
}

// ---- the receiver classification -----------------------------------------------------------------

test "a bare identifier with NO symbol of that name names a TYPE" {
    harness := MemberArmOf()

    assert harness.Arm.IsStaticMemberAccessTarget(new IdentifierExpression("Console", 4, 1))
}

test "a local of the same name VETOES the type reading" {
    harness := MemberArmOf()
    MemberDeclare(harness, "Console", BuiltInTypes.String)

    assert !harness.Arm.IsStaticMemberAccessTarget(new IdentifierExpression("Console", 4, 1))
}

test "parentheses are transparent to the type reading" {
    harness := MemberArmOf()
    MemberDeclare(harness, "value", BuiltInTypes.String)

    assert !harness.Arm.IsStaticMemberAccessTarget(new ParenthesizedExpression(new IdentifierExpression("value", 4, 1), 4, 1))
    assert harness.Arm.IsStaticMemberAccessTarget(new ParenthesizedExpression(new IdentifierExpression("Widget", 4, 1), 4, 1))
}

test "a scope TYPE answers the type-valued receiver probe" {
    harness := MemberArmOf()
    harness.Scopes.Peek().Types["Widget"] = MemberSampleClass("Widget")

    resolved: TypeInfo = BuiltInTypes.Unknown
    assert harness.Arm.TryResolveTypeValuedMemberAccess(new IdentifierExpression("Widget", 4, 1), out resolved)
    assert MemberTypeName(resolved) == "class:Widget"
}

test "a SYMBOL of that name vetoes the probe before any type table is read" {
    harness := MemberArmOf()
    harness.Scopes.Peek().Types["Widget"] = MemberSampleClass("Widget")
    MemberDeclare(harness, "Widget", BuiltInTypes.Int)

    resolved: TypeInfo = BuiltInTypes.Unknown
    assert !harness.Arm.TryResolveTypeValuedMemberAccess(new IdentifierExpression("Widget", 4, 1), out resolved)
    assert MemberTypeName(resolved) == "unknown"
}

test "an unknown bare name is not a type-valued receiver" {
    harness := MemberArmOf()

    resolved: TypeInfo = BuiltInTypes.Unknown
    assert !harness.Arm.TryResolveTypeValuedMemberAccess(new IdentifierExpression("Nonesuch", 4, 1), out resolved)
}

test "an expression that is neither an identifier, a member access nor parentheses is not a type" {
    harness := MemberArmOf()

    resolved: TypeInfo = BuiltInTypes.Unknown
    assert !harness.Arm.TryResolveTypeValuedMemberAccess(new IntLiteralExpression("1", 4, 1), out resolved)
}

// ---- the dotted-name reader ----------------------------------------------------------------------

test "a dotted chain spells its qualified name" {
    name := ""

    assert AnalyzerMemberAccess.TryGetQualifiedExpressionTreeName(new MemberAccessExpression(new MemberAccessExpression(new IdentifierExpression("System", 4, 1), "Text", false, 4, 1), "StringBuilder", false, 4, 1), out name)
    assert name == "System.Text.StringBuilder"
}

test "a NULL-CONDITIONAL link breaks the name — a type reference cannot be conditional" {
    name := ""

    assert !AnalyzerMemberAccess.TryGetQualifiedExpressionTreeName(new MemberAccessExpression(new IdentifierExpression("System", 4, 1), "Text", true, 4, 1), out name)
    assert name == ""
}

test "a link whose own root is unreadable breaks the whole name" {
    name := ""

    assert !AnalyzerMemberAccess.TryGetQualifiedExpressionTreeName(new MemberAccessExpression(new IntLiteralExpression("1", 4, 1), "Text", false, 4, 1), out name)
}

test "a bare identifier is its own qualified name" {
    name := ""

    assert AnalyzerMemberAccess.TryGetQualifiedExpressionTreeName(new IdentifierExpression("Console", 4, 1), out name)
    assert name == "Console"
}

// ---- the null-conditional result wrap ------------------------------------------------------------

test "`a?.b` wraps an ordinary member type in one layer of nullability" {
    harness := MemberArmOf()

    assert MemberTypeName(harness.Arm.MakeNullableResult(BuiltInTypes.String)) == "nullable(simple:string)"
}

test "the four shapes with no nullable form pass through UNWRAPPED" {
    harness := MemberArmOf()

    // `void` and `never` do not produce a value; `unknown` is already the absence of an answer; and a
    // nullable is not made more nullable by a second `?.`.
    assert MemberTypeName(harness.Arm.MakeNullableResult(BuiltInTypes.Void)) == "simple:void"
    assert MemberTypeName(harness.Arm.MakeNullableResult(BuiltInTypes.Never)) == "simple:never"
    assert MemberTypeName(harness.Arm.MakeNullableResult(BuiltInTypes.Unknown)) == "unknown"
    assert MemberTypeName(harness.Arm.MakeNullableResult(new NullableTypeInfo(BuiltInTypes.String))) == "nullable(simple:string)"
}

test "the wrap keeps the WRITTEN type inside, not the alias-resolved one" {
    harness := MemberArmOf()
    wrapped := harness.Arm.MakeNullableResult(BuiltInTypes.Int) as NullableTypeInfo

    // `BuiltInTypes.Int` constructs a fresh instance on every read, so identity is asserted through
    // `BuiltInTypes.Is` rather than by reference.
    assert wrapped != null
    assert BuiltInTypes.Is(wrapped.InnerType, BuiltInTypes.Int)
}

// ---- the should-report rule ----------------------------------------------------------------------

test "the parser's `<error>` placeholder is never reported as a missing member" {
    harness := MemberArmOf()

    assert !harness.Arm.ShouldReportUndefinedMember(MemberSampleClass("Widget"), "<error>", false)
}

test "a blank member name is never reported" {
    harness := MemberArmOf()

    assert !harness.Arm.ShouldReportUndefinedMember(MemberSampleClass("Widget"), "   ", false)
}

test "`object` NEVER reports — any name might be there through a cast" {
    harness := MemberArmOf()

    assert !harness.Arm.ShouldReportUndefinedMember(BuiltInTypes.Object, "Nonesuch", false)
}

test "every SOURCE-declared shape reports, because its member list is complete by construction" {
    harness := MemberArmOf()

    assert harness.Arm.ShouldReportUndefinedMember(MemberSampleClass("Widget"), "Nonesuch", false)
}

test "a nullable asks about its INNER type" {
    harness := MemberArmOf()

    assert harness.Arm.ShouldReportUndefinedMember(new NullableTypeInfo(MemberSampleClass("Widget")), "Nonesuch", false)
    assert !harness.Arm.ShouldReportUndefinedMember(new NullableTypeInfo(BuiltInTypes.Object), "Nonesuch", false)
}

test "`System.Object` reflected is the same silence as the built-in `object`" {
    harness := MemberArmOf()

    assert !harness.Arm.ShouldReportUndefinedMember(new ReflectionTypeInfo(typeof(object)), "Nonesuch", false)
}

test "a core-library reflected type has a reliable member set and DOES report" {
    harness := MemberArmOf()

    assert harness.Arm.ShouldReportUndefinedMember(new ReflectionTypeInfo(typeof(Version)), "Nonesuch", false)
}

// A BCL GENERIC CLOSED OVER A TYPE WITH NO CLR HANDLE reported NOTHING AT ALL: `List<PriceArgs>`
// cannot be constructed as a CLR type while `PriceArgs` is still a declaration, so the "reachable
// CLR type" question answered no and the miss first surfaced as an emitter decline naming a backend.
// The DEFINITION answers instead, and it is asked about the NAME — a type argument never adds a
// member, and a name the definition DOES have is the analyzer's own resolution gap rather than the
// reader's typo.
test "a BCL generic closed over a SOURCE type reports a name its DEFINITION does not have" {
    harness := MemberArmOf()
    overSource := MemberClosedListOf(MemberSampleClass("PriceArgs"))

    assert harness.Arm.ShouldReportUndefinedMember(overSource, "Nope", false)
    assert harness.Arm.ShouldReportUndefinedMember(overSource, "Nope", true)

    // A name the definition HAS is not reported, whether or not this analyzer could resolve it here.
    assert !harness.Arm.ShouldReportUndefinedMember(overSource, "Count", false)
    assert !harness.Arm.ShouldReportUndefinedMember(overSource, "Add", false)

    // And the same is true of a definition closed over an enclosing signature's type parameter, which
    // is the spelling every generic function writes.
    overTypeParameter := MemberClosedListOf(new SimpleTypeInfo("T"))
    assert harness.Arm.ShouldReportUndefinedMember(overTypeParameter, "Nope", false)
    assert !harness.Arm.ShouldReportUndefinedMember(overTypeParameter, "Add", false)
}

test "a primitive whose CLR type IS reachable reports, and the tables are not consulted at all" {
    harness := MemberArmOf()

    // The conversion funnel answers the RUNTIME primitive even with no metadata load context open, so
    // this arm concludes from reflection rather than from the name tables. The tables below are the
    // fallback for the one configuration where the funnel cannot answer.
    assert harness.Arm.ShouldReportUndefinedMember(BuiltInTypes.String, "Lenght", false)
    assert harness.Arm.ShouldReportUndefinedMember(BuiltInTypes.String, "Length", false)
    assert harness.Arm.ShouldReportUndefinedMember(new ArrayTypeInfo(BuiltInTypes.Int), "Lenght", false)
}

test "the OBJECT table is checked before the receiver's own, and it serves every receiver" {
    harness := MemberArmOf()

    // `ToString`, `Equals`, `GetHashCode` and `GetType` are on everything, so the receiver arm is
    // never reached for them.
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.String, "ToString", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(MemberSampleClass("Widget"), "GetType", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(new ArrayTypeInfo(BuiltInTypes.Int), "Equals", false)
}

test "the STRING table separates instance names from static ones" {
    harness := MemberArmOf()

    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.String, "Length", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.String, "Substring", false)
    assert !harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.String, "Lenght", false)

    // A static name is known ONLY when the receiver named the type, which is the same distinction the
    // receiver classification makes one level up.
    assert !harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.String, "IsNullOrEmpty", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.String, "IsNullOrEmpty", true)
}

test "the NUMERIC table serves every integral and floating width, and `char` shares it" {
    harness := MemberArmOf()

    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Int, "CompareTo", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Double, "CompareTo", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.ULong, "CompareTo", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Decimal, "CompareTo", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Char, "CompareTo", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Int, "MaxValue", true)
    assert !harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Int, "MaxValue", false)
}

test "`bool` has its OWN table, and it is not the numeric one" {
    harness := MemberArmOf()

    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Bool, "TrueString", true)
    assert !harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Bool, "MaxValue", true)
    assert !harness.Arm.IsKnownBuiltInMemberWithoutReflection(BuiltInTypes.Int, "TrueString", true)
}

test "the ARRAY table is the array's whole known surface" {
    harness := MemberArmOf()

    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(new ArrayTypeInfo(BuiltInTypes.Int), "Length", false)
    assert harness.Arm.IsKnownBuiltInMemberWithoutReflection(new ArrayTypeInfo(BuiltInTypes.Int), "CopyTo", false)
    assert !harness.Arm.IsKnownBuiltInMemberWithoutReflection(new ArrayTypeInfo(BuiltInTypes.Int), "Lenght", false)

    // A receiver that is neither a built-in primitive nor an array has no table of its own.
    assert !harness.Arm.IsKnownBuiltInMemberWithoutReflection(MemberSampleClass("Widget"), "Length", false)
}

test "a shape with no member list at all stays silent" {
    harness := MemberArmOf()

    assert !harness.Arm.ShouldReportUndefinedMember(new FunctionTypeInfo(), "Nonesuch", false)
}

// ---- the report step -----------------------------------------------------------------------------

test "a resolution MISS RENDERS the report itself, and the walk takes only its one step" {
    harness := MemberArmOf()
    MemberDeclare(harness, "widget", MemberSampleClass("Widget"))
    trace := MemberDriveWith(harness, MemberAccessOf("widget", "Nonesuch", false), MemberSampleClass("Widget"))

    // ONE kind, not two: the report used to be kind 2 and is now rendered where it is decided.
    assert trace.Kinds == "1"
    assert trace.Reports == 1
    assert trace.ReportedMessage.Contains("Nonesuch")
    assert trace.ReportedMessage.Contains("Widget")
    assert MemberCodes(harness.Errors) == "303"
}

test "the report lands BEFORE the walk's answer is observable" {
    harness := MemberArmOf()
    MemberDeclare(harness, "widget", MemberSampleClass("Widget"))
    state := harness.Arm.Begin(MemberAccessOf("widget", "Nonesuch", false))
    harness.Arm.NextStep(state)
    assert harness.Errors.Count == 0

    // Supplying the receiver finishes the walk: the report is rendered inside that same call, ahead of
    // the answer being settled, which is the ordering the retired report step existed to guarantee.
    harness.Arm.Supply(state, MemberSampleClass("Widget"))
    assert harness.Errors.Count == 1
    assert harness.Arm.NextStep(state) == null
    assert MemberTypeName(harness.Arm.Result(state)) == "unknown"
}

test "a receiver the rule keeps silent about reports NOTHING" {
    harness := MemberArmOf()
    MemberDeclare(harness, "anything", BuiltInTypes.Object)
    trace := MemberDriveWith(harness, MemberAccessOf("anything", "Nonesuch", false), BuiltInTypes.Object)

    assert trace.Kinds == "1"
    assert trace.Reports == 0
    assert trace.Answer == "unknown"
}

test "a TYPE receiver's report draws its did-you-mean names from the STATIC pool" {
    harness := MemberArmOf()
    harness.Scopes.Peek().Types["Widget"] = MemberSampleClass("Widget")
    trace := MemberDriveWith(harness, MemberAccessOf("Widget", "Nonesuch", false), MemberSampleClass("Widget"))

    assert trace.Reports == 1

    // The static and instance pools are different walks over the same receiver, and the report gets
    // whichever the receiver classification chose.
    staticNames := harness.Arm.GetAvailableMemberNames(MemberSampleClass("Widget"), true)
    instanceNames := harness.Arm.GetAvailableMemberNames(MemberSampleClass("Widget"), false)
    assert staticNames.Count != instanceNames.Count
}

test "a null-conditional MISS still answers unknown rather than nullable-unknown" {
    harness := MemberArmOf()
    MemberDeclare(harness, "widget", MemberSampleClass("Widget"))
    trace := MemberDriveWith(harness, MemberAccessOf("widget", "Nonesuch", true), MemberSampleClass("Widget"))

    assert trace.Reports == 1
    assert trace.Answer == "unknown"
}

// ---- the cross-package rule ----------------------------------------------------------------------

test "a declaration in the SAME file is never cross-package" {
    harness := MemberArmOf()
    harness.Sink.BeginAnalysis(Path.GetFullPath("member-access-contract.nl"), null)

    assert !harness.Arm.IsCrossPackageFile(Path.GetFullPath("member-access-contract.nl"))
}

test "a missing path on either side is never cross-package" {
    harness := MemberArmOf()
    harness.Sink.BeginAnalysis(Path.GetFullPath("member-access-contract.nl"), null)

    assert !harness.Arm.IsCrossPackageFile(null)
    assert !harness.Arm.IsCrossPackageFile("   ")

    harness.Sink.BeginAnalysis(null, null)
    assert !harness.Arm.IsCrossPackageFile(Path.GetFullPath("other.nl"))
}

// ---- the per-analysis and rebuild discipline -----------------------------------------------------

test "BeginAnalysis takes the REPLACED binding map, so bindings land in the live one" {
    harness := MemberArmOf()
    replacement := new BindingMap()
    harness.Arm.BeginAnalysis(null, replacement)
    MemberAliasSymbols(harness, "text")["Trim"] = BuiltInTypes.String
    MemberAliasDeclarations(harness, "text")["Trim"] = new SymbolDeclaration("Trim", "/p/text.nl", 9, 3, "function")

    harness.Arm.NextStep(harness.Arm.Begin(MemberAccessOf("text", "Trim", false)))

    // The map handed to the constructor is REPLACED once per analysis. A binding written into the
    // stale one is invisible to go-to-definition.
    assert replacement.GetBindingAt(harness.Sink.CurrentFilePath, 4, 2) != null
    assert harness.Bindings.GetBindingAt(harness.Sink.CurrentFilePath, 4, 2) == null
}

test "a metadata-context CLOSE hands the arm a null well-known bag without rebuilding it" {
    harness := MemberArmOf()
    replacement := new BindingMap()
    harness.Arm.BeginAnalysis(null, replacement)

    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    conversion := new AnalyzerClrTypeConversion(context, null)
    harness.Arm.SetMetadataCollaborators(harness.Members, conversion, harness.ExtensionResolution, null)

    // The setter replaces four collaborators and touches nothing else — the per-analysis binding map
    // survives, which is the whole reason this owner is told rather than rebuilt.
    MemberAliasSymbols(harness, "text")["Trim"] = BuiltInTypes.String
    MemberAliasDeclarations(harness, "text")["Trim"] = new SymbolDeclaration("Trim", "/p/text.nl", 9, 3, "function")
    harness.Arm.NextStep(harness.Arm.Begin(MemberAccessOf("text", "Trim", false)))

    assert replacement.GetBindingAt(harness.Sink.CurrentFilePath, 4, 2) != null
}

// ---- one nullable surface, whatever the element is -----------------------------------------------

func MemberSampleStruct(name: string): StructTypeInfo {
    return new StructTypeInfo(name, 2, 1, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
}

test "whether `T?` has `Nullable<T>`'s surface is decided by whether T is a VALUE type" {
    harness := MemberArmOf()

    // The CLR answers for a type it has a handle for.
    assert harness.Arm.IsLiftedValueReceiver(BuiltInTypes.Int)
    assert !harness.Arm.IsLiftedValueReceiver(BuiltInTypes.String)

    // A type THIS COMPILATION declares has no handle yet, so the declaration answers. A class is
    // not a value, and `unknown` is not one either — reading it as one would give a surface to a
    // receiver whose type nobody knows.
    assert harness.Arm.IsLiftedValueReceiver(MemberSampleStruct("Money"))
    assert !harness.Arm.IsLiftedValueReceiver(MemberSampleClass("Markup"))
    assert !harness.Arm.IsLiftedValueReceiver(BuiltInTypes.Unknown)
}

test "`Nullable<T>`'s own members are read off the DEFINITION when T has no CLR handle" {
    harness := MemberArmOf()
    money := MemberSampleStruct("Money")

    // `GetValueOrDefault` is `Nullable<T>`'s, not `Money`'s, and `Money` is a type this compilation
    // is emitting — so there is no closed `Nullable<Money>` to read it off. Before the definition
    // arm, the name fell through to the UNWRAPPED receiver and reported NL303 "Member
    // 'GetValueOrDefault' not found on type 'Money'".
    resolved: TypeInfo = BuiltInTypes.Unknown
    assert harness.Arm.TryResolveOpenNullableDefinitionMember(money, "GetValueOrDefault", out resolved)

    group := resolved as NSharpMethodGroupInfo
    assert group != null
    functions := NSharpMethodGroupInfoFactory.GetFunctions(group)

    // BOTH overloads come back, because the definition declares both — no name list decided that.
    assert functions.Count == 2
    zeroArity := 0
    oneArity := 0
    index := 0
    while index < functions.Count {
        signature := functions[index]
        index = index + 1
        parameterTypes := signature.ParameterTypes
        assert parameterTypes != null

        // EVERY POSITION IS SUBSTITUTED: the return is a `Money`, and so is the one-argument
        // overload's fallback.
        assert MemberTypeName(signature.ReturnType) == "<other>"
        returnStruct := signature.ReturnType as StructTypeInfo
        assert returnStruct != null && returnStruct.Name == "Money"

        if parameterTypes.Count == 0 {
            zeroArity = zeroArity + 1
        } else {
            oneArity = oneArity + 1
            fallbackStruct := parameterTypes[0] as StructTypeInfo
            assert fallbackStruct != null && fallbackStruct.Name == "Money"
        }
    }

    assert zeroArity == 1
    assert oneArity == 1

    // A PROPERTY THE DEFINITION DECLARES ANSWERS TOO, and a name it does not declare answers not
    // at all rather than guessing.
    hasValue: TypeInfo = BuiltInTypes.Unknown
    assert harness.Arm.TryResolveOpenNullableDefinitionMember(money, "HasValue", out hasValue)
    assert MemberTypeName(hasValue) == "simple:bool"

    missing: TypeInfo = BuiltInTypes.Unknown
    assert !harness.Arm.TryResolveOpenNullableDefinitionMember(money, "Nonesuch", out missing)
}
