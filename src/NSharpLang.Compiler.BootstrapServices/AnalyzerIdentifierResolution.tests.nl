namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the identifier arm — what a BARE NAME means.
//
// Both members behind these contracts were `private` in `Analyzer.cs`, so no test named either: the
// six-channel lookup and the four codes it raises were pinned only indirectly, through end-to-end
// diagnostics on programs that happened to reach them. This is their first DIRECT pinning, and it
// goes at the decisions that read like plumbing and are not:
//
//   * the CHANNEL ORDER, which is what makes a local shadow an enclosing type's member, a member
//     shadow an imported type name, and a project type outrank a CLR type of the same name;
//   * the `<error>` SILENCE, which is what stops a syntax error from also being told the name it
//     could not read is undefined;
//   * the TWO SHAPES of both miss reports, because a diagnostic with a snippet underlines columns
//     and one without cannot, and the fallback is the shape an editor sees on a buffer the analyzer
//     has no text for;
//   * the TWO SUGGESTION POOLS, because only a callee position may mean an extension method;
//   * the ERROR-TUPLE GUARD's suppression and its dedupe, which are the difference between telling a
//     developer once and telling them at every re-resolution of the same position;
//   * the PER-ANALYSIS RESET, because the dedupe set outliving an analysis would silence a real
//     second report in the next file;
//   * the SETTER discipline for the two rebuilt collaborators, because a factory rebuild would drop
//     that set mid-analysis.

class IdentifierHarness {
    Rule: AnalyzerIdentifierResolution
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Model: SemanticModel
    Bindings: BindingMap
    Extensions: List<FunctionDeclaration>
    Sink: AnalyzerDiagnosticSink
    Members: AnalyzerMemberResolution

    constructor(
        rule: AnalyzerIdentifierResolution,
        errors: List<CompilerError>,
        scopes: AnalyzerScopeStack,
        model: SemanticModel,
        bindings: BindingMap,
        extensions: List<FunctionDeclaration>,
        sink: AnalyzerDiagnosticSink,
        members: AnalyzerMemberResolution) {
        Rule = rule
        Errors = errors
        Scopes = scopes
        Model = model
        Bindings = bindings
        Extensions = extensions
        Sink = sink
        Members = members
    }
}

// The rule over an EMPTY project with no referenced assemblies: channels 1, 2 and 5 are live, channel
// 3 is dark because the well-known-type bag is null, channel 4 finds nothing and channel 6 has no
// assembly to probe. That is exactly the shape most of these contracts are about — the ones that need
// a live metadata channel say so.
func IdentifierRuleOf(): IdentifierHarness {
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
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        sink,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        model,
        bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    namespaces := new List<string>()
    extensions := new List<FunctionDeclaration>()
    extensionResolution := new AnalyzerExtensionMethodResolution(
        resolver,
        assignability,
        context,
        functionTypes,
        clrConversion,
        extensions,
        namespaces,
        new List<Assembly>())
    members := new AnalyzerMemberResolution(
        functionTypes,
        context,
        substitution,
        resolver,
        clrConversion,
        extensionResolution,
        namespaces)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)

    rule := new AnalyzerIdentifierResolution(
        sink,
        scopes,
        resolver,
        discovery,
        probe,
        functionTypes,
        ambient,
        nullFlow,
        extensions,
        members,
        model,
        bindings)
    return new IdentifierHarness(rule, errors, scopes, model, bindings, extensions, sink, members)
}

func IdentifierCodes(errors: List<CompilerError>): string {
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

// The DID-YOU-MEAN names live in `Suggestions`, a nullable list, while `Suggestion` is the single
// prose line. Reading the list through one door keeps the narrowing in one place.
func IdentifierSuggestions(error: CompilerError): string {
    if error.Suggestions == null {
        return ""
    }

    text := ""
    index := 0
    while index < error.Suggestions.Count {
        text = text + error.Suggestions[index] + "|"
        index = index + 1
    }

    return text
}

func IdentifierSuggestion(error: CompilerError): string {
    if error.Suggestion == null {
        return ""
    }

    return error.Suggestion
}

// A name declared into the innermost LEXICAL scope, which is the table channel 1 reads.
// `RecordVariable` writes the semantic model's scoped table instead, and that is a different table.
func IdentifierDeclare(harness: IdentifierHarness, name: string, declaredType: TypeInfo) {
    harness.Scopes.Peek().Symbols[name] = declaredType
}

func IdentifierExtensionMethod(name: string): FunctionDeclaration {
    return new FunctionDeclaration(name, new List<Parameter>(), null, null, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 1, 1)
}

func IdentifierTypeName(candidate: TypeInfo?): string {
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
        return "nullable(" + IdentifierTypeName(nullable.InnerType) + ")"
    }

    functionType := candidate as FunctionTypeInfo
    if functionType != null {
        return "function/" + functionType.ParameterTypes.Count.ToString()
    }

    return "<other>"
}

// ---- the `<error>` placeholder -------------------------------------------------------------------

test "the parser's `<error>` placeholder answers unknown and reports NOTHING" {
    harness := IdentifierRuleOf()

    // The syntax diagnostic has already been raised at this position. A second report saying the name
    // the parser could not read is undefined would be noise stacked on top of it, and it would be
    // stacked on EVERY malformed expression in a file being typed.
    answer := harness.Rule.Resolve("<error>", 3, 5, false)

    assert IdentifierTypeName(answer) == "unknown"
    assert harness.Errors.Count == 0
}

test "the `<error>` silence holds in callee position too" {
    harness := IdentifierRuleOf()

    answer := harness.Rule.Resolve("<error>", 3, 5, true)

    assert IdentifierTypeName(answer) == "unknown"
    assert harness.Errors.Count == 0
}

// ---- channel 1: the scope stack ------------------------------------------------------------------

test "channel 1 answers a scope SYMBOL, and the answer is the declared type" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "count", BuiltInTypes.Int)

    assert IdentifierTypeName(harness.Rule.Resolve("count", 4, 9, false)) == "simple:int"
    assert harness.Errors.Count == 0
}

test "channel 1 answers a scope TYPE when no symbol has the name — symbols FIRST" {
    harness := IdentifierRuleOf()
    scope := harness.Scopes.Peek()
    scope.Types["Widget"] = BuiltInTypes.String
    scope.Symbols["Widget"] = BuiltInTypes.Int

    // Both tables carry the name. The SYMBOL wins, which is what makes `let string = 1` mean the
    // local and not the type for the rest of the block.
    assert IdentifierTypeName(harness.Rule.Resolve("Widget", 4, 9, false)) == "simple:int"
}

test "a scope type with no symbol of that name is still an answer" {
    harness := IdentifierRuleOf()
    harness.Scopes.Peek().Types["Widget"] = BuiltInTypes.String

    assert IdentifierTypeName(harness.Rule.Resolve("Widget", 4, 9, false)) == "simple:string"
}

test "an inner scope shadows an outer binding of the same name" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 2, 1)
    IdentifierDeclare(harness, "value", BuiltInTypes.String)

    assert IdentifierTypeName(harness.Rule.Resolve("value", 4, 9, false)) == "simple:string"

    harness.Scopes.Pop(harness.Model)
    assert IdentifierTypeName(harness.Rule.Resolve("value", 5, 9, false)) == "simple:int"
}

test "channel 1 is where NARROWING pays off: the arm reads whatever the scope now holds" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "text", new NullableTypeInfo(BuiltInTypes.String))

    assert IdentifierTypeName(harness.Rule.Resolve("text", 4, 9, false)) == "nullable(simple:string)"

    // This is exactly what `AnalyzerFlowNarrowing` does inside an `if text != null` branch: it writes
    // the narrowed type into the scope's own symbol table. The arm names narrowing nowhere and still
    // answers the narrowed type, which is why the identifier arm needed no narrowing collaborator.
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 5, 1)
    IdentifierDeclare(harness, "text", BuiltInTypes.String)

    assert IdentifierTypeName(harness.Rule.Resolve("text", 6, 9, false)) == "simple:string"
}

// ---- channel 3: the built-in keyword table -------------------------------------------------------

test "channel 3 is DARK while the well-known-type bag is null" {
    harness := IdentifierRuleOf()

    // Without a metadata load context there is no `System.Int32` to name, so `int` in expression
    // position is a miss rather than a receiver. That is not a degraded mode to be worked around: the
    // analyzer reports through exactly this path before it has loaded any assembly.
    assert IdentifierTypeName(harness.Rule.Resolve("int", 4, 9, false)) == "unknown"
    assert IdentifierCodes(harness.Errors) == "301"
}

test "a scope symbol shadows the built-in keyword table" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "double", BuiltInTypes.Int)

    assert IdentifierTypeName(harness.Rule.Resolve("double", 4, 9, false)) == "simple:int"
    assert harness.Errors.Count == 0
}

// ---- channel 5: project-wide function discovery --------------------------------------------------

test "the published project-function probe answers false over an empty project" {
    harness := IdentifierRuleOf()
    functionType: TypeInfo = BuiltInTypes.Unknown
    declaration: SymbolDeclaration? = null

    // The probe is PUBLISHED because a second host member — the qualified-external-type walk — asks
    // the same question of a dotted name's root. Both consumers must get the same answer, which is
    // the whole reason it is not private to the rule.
    assert !harness.Rule.TryResolveVisibleProjectFunction("Anything", out functionType, out declaration)
    assert IdentifierTypeName(functionType) == "unknown"
    assert declaration == null
    assert harness.Errors.Count == 0
}

// ---- NL301, the undefined variable ---------------------------------------------------------------

test "a miss with NO source text takes the BARE NL301 shape" {
    harness := IdentifierRuleOf()

    answer := harness.Rule.Resolve("missing", 4, 9, false)

    assert IdentifierTypeName(answer) == "unknown"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedVariable
    assert harness.Errors[0].Message == "I can't find 'missing' — it hasn't been declared in this scope"
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 9
    // The BARE shape is asked for length 0 and floors at 1, so it underlines a single caret. The
    // rich shape below carries the name's own length, and an IDE underlines exactly those columns.
    assert harness.Errors[0].Length == 1
}

test "a miss WITH source text takes the RICH NL301 shape and underlines the name" {
    harness := IdentifierRuleOf()
    harness.Sink.BeginAnalysis("a.nl", "func Main() {\n    print missing\n}\n")

    answer := harness.Rule.Resolve("missing", 2, 11, false)

    assert IdentifierTypeName(answer) == "unknown"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedVariable
    assert harness.Errors[0].Message == "Variable 'missing' not found"
    assert harness.Errors[0].Length == 7
    assert harness.Errors[0].FileName == "a.nl"
}

test "line 0 has no snippet, so a miss there falls back to the bare shape even with text" {
    harness := IdentifierRuleOf()
    harness.Sink.BeginAnalysis("a.nl", "func Main() {\n    print missing\n}\n")

    harness.Rule.Resolve("missing", 0, 0, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "I can't find 'missing' — it hasn't been declared in this scope"
}

test "a near-miss local is suggested, and the suggestion pool is the SCOPE" {
    harness := IdentifierRuleOf()
    harness.Sink.BeginAnalysis("a.nl", "func Main() {\n    print countre\n}\n")
    IdentifierDeclare(harness, "counter", BuiltInTypes.Int)

    harness.Rule.Resolve("countre", 2, 11, false)

    assert harness.Errors.Count == 1
    assert IdentifierSuggestions(harness.Errors[0]).Contains("counter")
}

// ---- NL412, the undefined function ---------------------------------------------------------------

test "a callee-position miss is an undefined FUNCTION, not an undefined variable" {
    harness := IdentifierRuleOf()

    answer := harness.Rule.Resolve("Nonesuch", 4, 9, true)

    assert IdentifierTypeName(answer) == "unknown"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedFunction
    assert harness.Errors[0].Message == "Function 'Nonesuch' not found"
    // Unlike the bare NL301, the bare NL412 DOES carry the name's length.
    assert harness.Errors[0].Length == 8
}

test "the RICH NL412 shape is selected by the same snippet test" {
    harness := IdentifierRuleOf()
    harness.Sink.BeginAnalysis("a.nl", "func Main() {\n    print Nonesuch()\n}\n")

    harness.Rule.Resolve("Nonesuch", 2, 11, true)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedFunction
    assert harness.Errors[0].Length == 8
    assert harness.Errors[0].FileName == "a.nl"
}

test "the CALLABLE pool is a different pool: a non-callable local is not suggested for a callee" {
    harness := IdentifierRuleOf()
    harness.Sink.BeginAnalysis("a.nl", "func Main() {\n    print countre()\n}\n")
    IdentifierDeclare(harness, "counter", BuiltInTypes.Int)

    harness.Rule.Resolve("countre", 2, 11, true)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedFunction
    // `counter` is an `int`, so it is not a callable and the callee position must not offer it.
    assert !IdentifierSuggestions(harness.Errors[0]).Contains("counter")
}

test "an EXTENSION METHOD name is in the callable pool and in no other" {
    harness := IdentifierRuleOf()
    harness.Sink.BeginAnalysis("a.nl", "func Main() {\n    print Shou()\n}\n")
    harness.Extensions.Add(IdentifierExtensionMethod("Shout"))

    harness.Rule.Resolve("Shou", 2, 11, true)

    assert harness.Errors.Count == 1
    assert IdentifierSuggestions(harness.Errors[0]).Contains("Shout")

    // The SAME name in a non-callee position must not be offered: extension methods are not values.
    harness.Errors.Clear()
    harness.Rule.Resolve("Shou", 2, 11, false)
    assert harness.Errors.Count == 1
    assert !IdentifierSuggestions(harness.Errors[0]).Contains("Shout")
}

test "the extension list is LIVE: a method registered after construction is still offered" {
    harness := IdentifierRuleOf()
    harness.Sink.BeginAnalysis("a.nl", "func Main() {\n    print Shou()\n}\n")

    harness.Rule.Resolve("Shou", 2, 11, true)
    assert harness.Errors.Count == 1
    assert !IdentifierSuggestions(harness.Errors[0]).Contains("Shout")

    // The declaration walk registers extension methods as it meets them, long after the rule was
    // built. Holding the LIST rather than a copy is what keeps the suggestion pool current.
    harness.Extensions.Add(IdentifierExtensionMethod("Shout"))
    harness.Errors.Clear()

    harness.Rule.Resolve("Shou", 2, 11, true)
    assert harness.Errors.Count == 1
    assert IdentifierSuggestions(harness.Errors[0]).Contains("Shout")
}

// ---- NL314, the error-tuple result guard ---------------------------------------------------------

test "a result read before its error is checked is refused, and the report names BOTH names" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    answer := harness.Rule.Resolve("value", 3, 11, false)

    // The NAME still resolves — this is a use rule, not a resolution rule, so the answer is the
    // declared type and the walk around it carries on with a real type rather than `unknown`.
    assert IdentifierTypeName(answer) == "simple:int"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UnverifiedErrorResult
    assert harness.Errors[0].Message == "Result 'value' may be unavailable because 'err' can be non-null"
    assert harness.Errors[0].Line == 3
    assert harness.Errors[0].Column == 11
    assert harness.Errors[0].Length == 5
    assert IdentifierSuggestion(harness.Errors[0]).Contains("if err == null")
}

test "once the error is checked the same read is silent" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)
    harness.Scopes.MarkErrorTupleResultsAvailableForError("err")

    harness.Rule.Resolve("value", 3, 11, false)

    assert harness.Errors.Count == 0
}

test "the SAME position is reported once and no more — the dedupe is (line, column, name)" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    // One position can be resolved more than once: an assignment target is resolved again by the
    // write-target classifiers that follow it. The developer must see the report once.
    harness.Rule.Resolve("value", 3, 11, false)
    harness.Rule.Resolve("value", 3, 11, false)
    harness.Rule.Resolve("value", 3, 11, false)

    assert harness.Errors.Count == 1
}

test "a DIFFERENT position of the same name is a different report" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    harness.Rule.Resolve("value", 3, 11, false)
    harness.Rule.Resolve("value", 4, 11, false)

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Line == 3
    assert harness.Errors[1].Line == 4
}

test "the SUPPRESSION turns the guard off for a write target and restores it" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    // Writing INTO a result name is not a use of it. The assignment arm saves the flag, sets it for a
    // plain `=` only, and restores it — exactly as it already does for the null-flow suppression.
    assert !harness.Rule.SuppressErrorTupleResultUse
    harness.Rule.SetSuppressErrorTupleResultUse(true)
    assert harness.Rule.SuppressErrorTupleResultUse

    harness.Rule.Resolve("value", 3, 5, false)
    assert harness.Errors.Count == 0

    harness.Rule.SetSuppressErrorTupleResultUse(false)
    harness.Rule.Resolve("value", 4, 5, false)
    assert harness.Errors.Count == 1
}

test "a suppressed read does NOT consume its dedupe slot" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    // The suppression returns BEFORE the dedupe set is touched. If it did not, a plain assignment
    // would silence the report a later read at the same position must still raise.
    harness.Rule.SetSuppressErrorTupleResultUse(true)
    harness.Rule.Resolve("value", 3, 5, false)
    harness.Rule.SetSuppressErrorTupleResultUse(false)
    harness.Rule.Resolve("value", 3, 5, false)

    assert harness.Errors.Count == 1
}

test "the guard never fires for a name that is not a registered result" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    IdentifierDeclare(harness, "err", BuiltInTypes.String)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    harness.Rule.Resolve("err", 3, 11, false)

    assert harness.Errors.Count == 0
}

test "the guard fires on a MISS-free path only: an unresolved name never reaches it" {
    harness := IdentifierRuleOf()
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    // `value` was registered as a guarded result but never declared, so channel 1 misses and the
    // whole lookup falls through to the undefined report. The guard is reached only from the
    // RESOLVED branch, so there is exactly one diagnostic here and it is NL301.
    harness.Rule.Resolve("value", 3, 11, false)

    assert IdentifierCodes(harness.Errors) == "301"
}

// ---- the per-analysis reset ----------------------------------------------------------------------

test "`BeginAnalysis` clears the dedupe set, so the next file reports at the same position again" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    harness.Rule.Resolve("value", 3, 11, false)
    assert harness.Errors.Count == 1

    harness.Rule.BeginAnalysis(null, new SemanticModel(), new BindingMap())
    harness.Rule.Resolve("value", 3, 11, false)

    assert harness.Errors.Count == 2
}

test "`BeginAnalysis` also clears the suppression, so a file never inherits the previous one's" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    harness.Rule.SetSuppressErrorTupleResultUse(true)
    harness.Rule.BeginAnalysis(null, new SemanticModel(), new BindingMap())

    assert !harness.Rule.SuppressErrorTupleResultUse
    harness.Rule.Resolve("value", 3, 11, false)
    assert harness.Errors.Count == 1
}

test "`BeginAnalysis` takes the REPLACED semantic model and binding map, not the ones held before" {
    harness := IdentifierRuleOf()
    replacementModel := new SemanticModel()
    replacementBindings := new BindingMap()
    harness.Rule.BeginAnalysis(null, replacementModel, replacementBindings)
    IdentifierDeclare(harness, "handler", BuiltInTypes.Int)

    // The call-target form writes the IDE records. They must land in the model this analysis owns —
    // both are REPLACED per analysis rather than cleared, so holding them from construction would
    // write every file's hover types into the first file's model.
    harness.Rule.CallTarget(new IdentifierExpression("handler", 7, 3))

    assert replacementModel.ExpressionTypes.ContainsKey((Line: 7, Column: 3))
    assert !harness.Model.ExpressionTypes.ContainsKey((Line: 7, Column: 3))
}

// ---- the setter discipline for the two rebuilt collaborators -------------------------------------

test "`SetMetadataCollaborators` replaces the pair WITHOUT dropping the dedupe set" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "value", BuiltInTypes.Int)
    harness.Scopes.RegisterErrorTupleResult("value", "err", 2, 5)

    harness.Rule.Resolve("value", 3, 11, false)
    assert harness.Errors.Count == 1

    // This is the whole reason the rule is TOLD about the rebuilt pair instead of being rebuilt with
    // it: the metadata load context opens and closes around an analysis, and a rebuild here would
    // forget what had already been reported and say it a second time.
    harness.Rule.SetMetadataCollaborators(harness.Members, null)
    harness.Rule.Resolve("value", 3, 11, false)

    assert harness.Errors.Count == 1
}

// ---- the callee-position form --------------------------------------------------------------------

test "`CallTarget` resolves as a FUNCTION and records both IDE facts" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "handler", BuiltInTypes.Int)

    answer := harness.Rule.CallTarget(new IdentifierExpression("handler", 7, 3))

    assert IdentifierTypeName(answer) == "simple:int"
    assert IdentifierTypeName(harness.Model.ExpressionTypes[(Line: 7, Column: 3)]) == "simple:int"
    assert harness.Model.ExpressionNullStates.ContainsKey((Line: 7, Column: 3))
}

test "`CallTarget` on a miss reports NL412 rather than NL301" {
    harness := IdentifierRuleOf()

    answer := harness.Rule.CallTarget(new IdentifierExpression("Nonesuch", 7, 3))

    assert IdentifierTypeName(answer) == "unknown"
    assert IdentifierCodes(harness.Errors) == "412"
}

test "`CallTarget` applies the nullability FLOW type, which is what the plain rule does not do" {
    harness := IdentifierRuleOf()
    IdentifierDeclare(harness, "handler", new NullableTypeInfo(BuiltInTypes.Int))

    // The plain rule answers the DECLARED type; the callee form answers the FLOW type. The call arm
    // reaches its callee without going through the dispatch host, so if this form did not apply the
    // flow type the callee would be the only expression position in the language that did not.
    plain := harness.Rule.Resolve("handler", 7, 3, true)
    flowed := harness.Rule.CallTarget(new IdentifierExpression("handler", 7, 3))

    assert IdentifierTypeName(plain) == "nullable(simple:int)"
    assert IdentifierTypeName(flowed) == "nullable(simple:int)"
    assert harness.Model.ExpressionNullStates.ContainsKey((Line: 7, Column: 3))
}

test "both consumers share ONE resolution, so a miss is reported once per position per consumer" {
    harness := IdentifierRuleOf()
    harness.Sink.BeginAnalysis("a.nl", "func Main() {\n    print Nonesuch()\n}\n")

    // The dispatch arm and the call arm ask the SAME rule. Neither wraps the other and neither
    // re-implements it, which is what stops a callee from being resolved twice with two reports.
    harness.Rule.CallTarget(new IdentifierExpression("Nonesuch", 2, 11))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedFunction
}
