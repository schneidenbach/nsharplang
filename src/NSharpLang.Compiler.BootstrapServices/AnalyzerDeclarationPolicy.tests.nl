namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT IT MEANS TO DECLARE SOMETHING.
//
// The thirteen members this replaces were all `private` in `Analyzer.cs` and nothing in `src/`,
// `tests/` or `editors/` named any of them, so their behaviour was pinned only through whichever
// end-to-end diagnostic a bad declaration happened to produce. This is their first DIRECT pinning,
// and it is written around the five things this family is easy to get wrong.
//
// (1) THE OVERLOAD MERGE IS THE ONLY LEGAL COLLISION, AND ITS DISTINCTNESS QUESTION IS ASKED AGAINST
// THE EXISTING FUNCTIONS ALONE. A list that also contained the incoming function would compare it
// with itself, match, and turn every overload in the language into a duplicate-declaration error.
// That is not a hypothetical: it is the exact mistake this port had to avoid, so it is pinned first
// and from both directions — a distinct signature MUST merge, an identical one MUST NOT.
//
// (2) THE MERGE HAS TWO SHAPES. The second declaration builds a GROUP from two functions; the third
// and later ones JOIN the existing group. Only the first shape replaces the scope entry.
//
// (3) SHADOWING IS AN ERROR, NOT A WARNING — and the walk that decides it stops dead at the first
// GLOBAL or type-level scope, so a local named after a global is not shadowing anything. The report
// also does NOT abandon the declaration: the name is still bound, which is what keeps one mistake to
// one diagnostic instead of a cascade of "undefined" reports behind it.
//
// (4) A TYPE IS RECORDED IN FOUR PLACES and an alias in a fifth, because four different consumers
// ask. A port that recorded in three would be silently wrong for whichever consumer it forgot.
//
// (5) THE DEFAULT-PARAMETER WALK REPORTS IN LIST ORDER, and its `params` check runs FIRST, whole,
// before any default-value report — the two families' reports interleave in exactly one order.
class DeclarationPolicyHarness {
    Owner: AnalyzerDeclarationPolicy
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Model: SemanticModel
    Bindings: BindingMap
    Context: AnalyzerDeclarationContext
    DeclarationFiles: Dictionary<string, string>
    Aliases: Dictionary<string, string>

    constructor(owner: AnalyzerDeclarationPolicy, errors: List<CompilerError>, scopes: AnalyzerScopeStack, model: SemanticModel, bindings: BindingMap, context: AnalyzerDeclarationContext, declarationFiles: Dictionary<string, string>, aliases: Dictionary<string, string>) {
        Owner = owner
        Errors = errors
        Scopes = scopes
        Model = model
        Bindings = bindings
        Context = context
        DeclarationFiles = declarationFiles
        Aliases = aliases
    }
}

func DeclarationPolicyPath(): string {
    return "declaration-policy-root/Program.nl"
}

func DeclarationPolicyHarnessNew(): DeclarationPolicyHarness {
    errors := new List<CompilerError>()
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset("declaration-policy-root", assemblies)
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    provider.BeginAnalysis("declaration-policy-root")
    namespaces := new List<string>()
    aliases := new Dictionary<string, string>(StringComparer.Ordinal)
    symbolsByAlias := new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal)
    declarationsByAlias := new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal)
    declarationFiles := new Dictionary<string, string>(StringComparer.Ordinal)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    sink := new AnalyzerDiagnosticSink(errors, provider)
    sink.BeginAnalysis(DeclarationPolicyPath(), null)
    spans := new AnalyzerDiagnosticSpans(sink)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, declarationFiles)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, aliases, symbolsByAlias, declarationsByAlias, model, bindings)
    parameters := new AnalyzerParameterDeclarations(sink)
    owner := new AnalyzerDeclarationPolicy(sink, spans, scopes, nullFlow, context, resolver, parameters, discovery, assemblies, aliases, symbolsByAlias, declarationsByAlias, declarationFiles)
    owner.BeginAnalysis(model, bindings, DeclarationPolicyPath(), null)
    return new DeclarationPolicyHarness(owner, errors, scopes, model, bindings, context, declarationFiles, aliases)
}

// A source function of the given parameter type spellings — `SourceParameterTypes` is what makes it
// an overload candidate at all.
func DeclarationPolicySourceFunction(parameterTypeNames: List<string>): FunctionTypeInfo {
    function := new FunctionTypeInfo()
    sourceParameters := new List<TypeReference>()
    index := 0
    while index < parameterTypeNames.Count {
        sourceParameters.Add(new SimpleTypeReference(parameterTypeNames[index], 0, 0))
        index = index + 1
    }

    function.SourceParameterTypes = sourceParameters
    function.SourceParameterCount = parameterTypeNames.Count
    return function
}

func DeclarationPolicyOneParam(typeName: string): FunctionTypeInfo {
    names := new List<string>()
    names.Add(typeName)
    return DeclarationPolicySourceFunction(names)
}

// A function with NO source signature: reflection-derived, and therefore not overloadable from source.
func DeclarationPolicyReflectionFunction(): FunctionTypeInfo {
    return new FunctionTypeInfo()
}

func DeclarationPolicyErrors(harness: DeclarationPolicyHarness, code: ErrorCode): List<CompilerError> {
    found := new List<CompilerError>()
    index := 0
    while index < harness.Errors.Count {
        candidate := harness.Errors[index]
        if candidate.Code == code {
            found.Add(candidate)
        }

        index = index + 1
    }

    return found
}

// The binding map exposes its declarations as a list; a contract that asks "was this spelling
// recorded" reads that list rather than reaching for a positional lookup meant for the IDE.
func DeclarationPolicyDeclarationAt(harness: DeclarationPolicyHarness, name: string, line: int, column: int): SymbolDeclaration? {
    all := harness.Bindings.AllDeclarations
    index := 0
    while index < all.Count {
        candidate := all[index]
        if candidate.Name == name && candidate.Line == line && candidate.Column == column {
            return candidate
        }

        index = index + 1
    }

    return null
}

func DeclarationPolicyGlobalSymbol(harness: DeclarationPolicyHarness, name: string): TypeInfo {
    scope := harness.Scopes.Peek()
    found: TypeInfo = BuiltInTypes.Unknown
    if scope.Symbols.TryGetValue(name, out found) {
        return found
    }

    return BuiltInTypes.Unknown
}

// ---- (1) the overload merge, from both directions ----------------------------------------------

test "two functions with DISTINCT source signatures merge into a method group and report nothing" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Render", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Render", DeclarationPolicyOneParam("string"), 2, 1, null, true)

    assert harness.Errors.Count == 0
    merged := DeclarationPolicyGlobalSymbol(harness, "Render") as NSharpMethodGroupInfo
    assert merged != null
    assert NSharpMethodGroupInfoFactory.GetFunctions(merged).Count == 2
}

test "two functions with the SAME source signature are a duplicate declaration" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Render", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Render", DeclarationPolicyOneParam("int"), 2, 1, null, true)

    duplicates := DeclarationPolicyErrors(harness, ErrorCode.DuplicateDeclaration)
    assert duplicates.Count == 1
    assert duplicates[0].Message == "'Render' is already declared in this scope — each name must be unique within the same scope"
    assert DeclarationPolicyGlobalSymbol(harness, "Render") is FunctionTypeInfo
}

test "overloads differing only in ARITY are distinct and merge" {
    harness := DeclarationPolicyHarnessNew()
    two := new List<string>()
    two.Add("int")
    two.Add("int")
    harness.Owner.DeclareSymbol("Sum", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Sum", DeclarationPolicySourceFunction(two), 2, 1, null, true)

    assert harness.Errors.Count == 0
    assert DeclarationPolicyGlobalSymbol(harness, "Sum") is NSharpMethodGroupInfo
}

test "a function may not overload a NON-function of the same name" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Value", BuiltInTypes.Int, 1, 1, null, true)
    harness.Owner.DeclareSymbol("Value", DeclarationPolicyOneParam("int"), 2, 1, null, true)

    assert DeclarationPolicyErrors(harness, ErrorCode.DuplicateDeclaration).Count == 1
}

test "a NON-function may not overload an existing function" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Value", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Value", BuiltInTypes.Int, 2, 1, null, true)

    assert DeclarationPolicyErrors(harness, ErrorCode.DuplicateDeclaration).Count == 1
}

test "a function with no SOURCE signature cannot overload, in either position" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Probe", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Probe", DeclarationPolicyReflectionFunction(), 2, 1, null, true)
    assert DeclarationPolicyErrors(harness, ErrorCode.DuplicateDeclaration).Count == 1

    other := DeclarationPolicyHarnessNew()
    other.Owner.DeclareSymbol("Probe", DeclarationPolicyReflectionFunction(), 1, 1, null, true)
    other.Owner.DeclareSymbol("Probe", DeclarationPolicyOneParam("int"), 2, 1, null, true)
    assert DeclarationPolicyErrors(other, ErrorCode.DuplicateDeclaration).Count == 1
}

// ---- (2) the merge's two shapes ------------------------------------------------------------------

test "a THIRD distinct overload joins the existing group rather than building a new one" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Pick", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Pick", DeclarationPolicyOneParam("string"), 2, 1, null, true)
    group := DeclarationPolicyGlobalSymbol(harness, "Pick") as NSharpMethodGroupInfo
    assert group != null

    harness.Owner.DeclareSymbol("Pick", DeclarationPolicyOneParam("bool"), 3, 1, null, true)
    assert harness.Errors.Count == 0

    after := DeclarationPolicyGlobalSymbol(harness, "Pick") as NSharpMethodGroupInfo
    assert after != null
    assert NSharpMethodGroupInfoFactory.GetFunctions(after).Count == 3
    // The SAME group instance was extended, not replaced.
    assert NSharpMethodGroupInfoFactory.GetFunctions(group).Count == 3
}

test "a fourth declaration matching an EXISTING group member is a duplicate" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Pick", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Pick", DeclarationPolicyOneParam("string"), 2, 1, null, true)
    harness.Owner.DeclareSymbol("Pick", DeclarationPolicyOneParam("int"), 3, 1, null, true)

    assert DeclarationPolicyErrors(harness, ErrorCode.DuplicateDeclaration).Count == 1
    group := DeclarationPolicyGlobalSymbol(harness, "Pick") as NSharpMethodGroupInfo
    assert group != null
    assert NSharpMethodGroupInfoFactory.GetFunctions(group).Count == 2
}

test "a merged overload still records a binding declaration for its own spelling" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Render", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Render", DeclarationPolicyOneParam("string"), 7, 1, null, true)
    assert DeclarationPolicyDeclarationAt(harness, "Render", 7, 1) != null
}

test "a merged overload records NOTHING when the caller asks for no binding" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("Render", DeclarationPolicyOneParam("int"), 1, 1, null, true)
    harness.Owner.DeclareSymbol("Render", DeclarationPolicyOneParam("string"), 7, 1, null, false)
    assert DeclarationPolicyDeclarationAt(harness, "Render", 7, 1) == null
    assert DeclarationPolicyGlobalSymbol(harness, "Render") is NSharpMethodGroupInfo
}

// ---- (3) plain declaration, and shadowing ------------------------------------------------------

test "a fresh name binds, takes a default null state, and records a declaration" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 4, 5, null, true)

    assert harness.Errors.Count == 0
    scope := harness.Scopes.Peek()
    assert scope.Symbols.ContainsKey("total")
    assert scope.NullStates.ContainsKey("total")
    assert DeclarationPolicyDeclarationAt(harness, "total", 4, 5) != null
}

test "two locals of one name in one scope are a duplicate, and the squiggle is the name's length" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 1, 5, null, true)
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 2, 5, null, true)

    duplicates := DeclarationPolicyErrors(harness, ErrorCode.DuplicateDeclaration)
    assert duplicates.Count == 1
    assert duplicates[0].Length == 5
}

test "a declaration that shadows an enclosing FUNCTION-scope binding is an ERROR" {
    harness := DeclarationPolicyHarnessNew()
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), 1, 1)
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 2, 5, null, true)
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 3, 1)
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 4, 9, null, true)

    shadowed := DeclarationPolicyErrors(harness, ErrorCode.ShadowedDeclaration)
    assert shadowed.Count == 1
    assert shadowed[0].Severity == ErrorSeverity.Error
    assert shadowed[0].Message == "'total' shadows an existing 'total' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs"
}

// PRODUCTION BEHAVIOUR, PINNED BECAUSE IT IS NOT WHAT THE RULE'S NAME SUGGESTS: the shadowing report
// does NOT abandon the declaration. The name is still bound in the inner scope, so everything after
// it type-checks against the value the developer actually wrote rather than collapsing into a second
// wave of "undefined" errors about the same mistake.
test "a shadowed declaration is still BOUND, so one mistake stays one diagnostic" {
    harness := DeclarationPolicyHarnessNew()
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), 1, 1)
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 2, 5, null, true)
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 3, 1)
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 4, 9, null, true)

    assert DeclarationPolicyErrors(harness, ErrorCode.ShadowedDeclaration).Count == 1
    assert harness.Scopes.Peek().Symbols.ContainsKey("total")
}

// The walk stops dead at the first GLOBAL or type-level scope, so a global of the same name is not
// something an inner local shadows.
test "a local does not shadow a GLOBAL of the same name" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 1, 5, null, true)
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 2, 1)
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 3, 9, null, true)

    assert DeclarationPolicyErrors(harness, ErrorCode.ShadowedDeclaration).Count == 0
}

test "a shadowing report carries the shadowing suggestion" {
    harness := DeclarationPolicyHarnessNew()
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), 1, 1)
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 2, 5, null, true)
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 3, 1)
    harness.Owner.DeclareSymbol("total", BuiltInTypes.Int, 4, 9, null, true)

    shadowed := DeclarationPolicyErrors(harness, ErrorCode.ShadowedDeclaration)
    assert shadowed.Count == 1
    assert shadowed[0].Suggestion != null
}

test "a name declared in a SIBLING block does not shadow" {
    harness := DeclarationPolicyHarnessNew()
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 1, 1)
    harness.Owner.DeclareSymbol("local", BuiltInTypes.Int, 2, 5, null, true)
    harness.Scopes.Pop(harness.Model)
    harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), 3, 1)
    harness.Owner.DeclareSymbol("local", BuiltInTypes.Int, 4, 5, null, true)

    assert harness.Errors.Count == 0
}

test "a declaration kind supplied by the caller overrides the one derived from the type" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareSymbol("thing", BuiltInTypes.Int, 2, 3, "parameter", true)
    declaration := DeclarationPolicyDeclarationAt(harness, "thing", 2, 3)
    assert declaration != null
    assert declaration.Kind == "parameter"
}

// ---- (4) a type, and its four records --------------------------------------------------------------

test "a declared type lands in the scope, the semantic model, the file map and the binding map" {
    harness := DeclarationPolicyHarnessNew()
    widget := BuiltInTypes.Int
    harness.Owner.DeclareType("Widget", widget, 3, 7)

    assert harness.Errors.Count == 0
    assert harness.Scopes.Peek().Types.ContainsKey("Widget")
    assert harness.Model.Types.ContainsKey("Widget")
    assert harness.DeclarationFiles.ContainsKey("Widget")
    assert DeclarationPolicyDeclarationAt(harness, "Widget", 3, 7) != null
}

test "two types of one name are a duplicate, and the first one stays" {
    harness := DeclarationPolicyHarnessNew()
    first := BuiltInTypes.Int
    second := BuiltInTypes.String
    harness.Owner.DeclareType("Widget", first, 1, 1)
    harness.Owner.DeclareType("Widget", second, 2, 1)

    duplicates := DeclarationPolicyErrors(harness, ErrorCode.DuplicateDeclaration)
    assert duplicates.Count == 1
    assert duplicates[0].Message == "A type named 'Widget' already exists — each type name must be unique"
}

test "a type and a SYMBOL of one name do not collide, because they are different tables" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.DeclareType("Thing", BuiltInTypes.Int, 1, 1)
    harness.Owner.DeclareSymbol("Thing", DeclarationPolicyOneParam("int"), 2, 1, null, true)

    assert harness.Errors.Count == 0
}

test "an alias registers as an alias and is NOT canonicalised away" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.SetDeclarationContextFilePath(DeclarationPolicyPath())
    alias := new AliasTypeInfo(new SimpleTypeReference("int", 0, 0))
    harness.Owner.DeclareType("Count", alias, 1, 1)

    assert harness.Errors.Count == 0
    assert harness.Scopes.Peek().Types["Count"] is AliasTypeInfo
}

test "with no declaration-context path set, the declared type is used as written" {
    harness := DeclarationPolicyHarnessNew()
    widget := BuiltInTypes.Int
    harness.Owner.DeclareType("Widget", widget, 1, 1)
    assert harness.Scopes.Peek().Types.ContainsKey("Widget")
}

// ---- (5) the package name --------------------------------------------------------------------------

test "a valid dotted package name reports nothing" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.ValidatePackageName(new PackageDeclaration("good.name.here", 1, 1))
    assert harness.Errors.Count == 0
}

test "a segment starting with a digit is reported, naming the SEGMENT" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.ValidatePackageName(new PackageDeclaration("good.9bad", 1, 1))
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Package name '9bad' is not a valid identifier — package names must start with a letter and contain only letters, digits, and underscores"
}

test "two bad segments are two reports, because one mistake must not hide the other" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.ValidatePackageName(new PackageDeclaration("1bad.2worse", 1, 1))
    assert harness.Errors.Count == 2
}

test "an empty segment — a doubled or trailing dot — is reported" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.ValidatePackageName(new PackageDeclaration("a..b", 1, 1))
    assert harness.Errors.Count == 1
}

test "underscores are valid, leading and within" {
    harness := DeclarationPolicyHarnessNew()
    harness.Owner.ValidatePackageName(new PackageDeclaration("_ok._also_ok", 1, 1))
    assert harness.Errors.Count == 0
}

test "the identifier rule itself answers each shape" {
    assert AnalyzerDeclarationPolicy.IsValidIdentifier("Name")
    assert AnalyzerDeclarationPolicy.IsValidIdentifier("_name")
    assert AnalyzerDeclarationPolicy.IsValidIdentifier("n1")
    assert !AnalyzerDeclarationPolicy.IsValidIdentifier("1n")
    assert !AnalyzerDeclarationPolicy.IsValidIdentifier("")
    assert !AnalyzerDeclarationPolicy.IsValidIdentifier("has-dash")
    assert !AnalyzerDeclarationPolicy.IsValidIdentifier("has space")
}

// When the parser supplies segments (the production path), the report names the segment AS WRITTEN
// and anchors on ITS span — not on the declaration keyword.

test "with parser segments, the report names the written segment and underlines its span" {
    harness := DeclarationPolicyHarnessNew()
    declaration := new PackageDeclaration("good.9bad", 1, 1)
    segments := new List<PackageNameSegment>()
    segments.Add(new PackageNameSegment("good", 1, 9, 4))
    segments.Add(new PackageNameSegment("9bad", 1, 14, 4))
    declaration.Segments = segments
    harness.Owner.ValidatePackageName(declaration)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Package name '9bad' is not a valid identifier — package names must start with a letter and contain only letters, digits, and underscores"
    assert harness.Errors[0].Line == 1
    assert harness.Errors[0].Column == 14
    assert harness.Errors[0].Length == 4
}

test "with parser segments, two bad segments are still two reports, each on its own span" {
    harness := DeclarationPolicyHarnessNew()
    declaration := new PackageDeclaration("1bad.2worse", 1, 1)
    segments := new List<PackageNameSegment>()
    segments.Add(new PackageNameSegment("1bad", 1, 9, 4))
    segments.Add(new PackageNameSegment("2worse", 1, 14, 6))
    declaration.Segments = segments
    harness.Owner.ValidatePackageName(declaration)
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Column == 9
    assert harness.Errors[1].Column == 14
}

test "an `<error>` placeholder segment is the parser's report, not repeated here" {
    // Recovery records `<error>` only when it had no written text to carry (end of file, reserved
    // keyword, detached offender) — and in each of those paths the parser has already reported at
    // that exact site. Naming the placeholder again would be the noise this family used to emit.
    harness := DeclarationPolicyHarnessNew()
    declaration := new PackageDeclaration("good.<error>", 1, 1)
    segments := new List<PackageNameSegment>()
    segments.Add(new PackageNameSegment("good", 1, 9, 4))
    segments.Add(new PackageNameSegment("<error>", 1, 13, 0))
    declaration.Segments = segments
    harness.Owner.ValidatePackageName(declaration)
    assert harness.Errors.Count == 0
}

// ---- (6) the default-parameter walk ------------------------------------------------------------------

// The driver exactly as `Analyzer.cs` writes it, minus the expression analysis the shell owns: the
// steps are COLLECTED rather than performed, which is what makes the protocol itself observable.
func DeclarationPolicyDrive(harness: DeclarationPolicyHarness, state: ParameterWalkState): List<ParameterWalkRequest> {
    seen := new List<ParameterWalkRequest>()
    step := harness.Owner.NextStep(state)
    while step != null {
        seen.Add(step)
        harness.Owner.Supply(state)
        step = harness.Owner.NextStep(state)
    }

    return seen
}

func DeclarationPolicyParam(name: string, typeName: string, defaultValue: Expression?): Parameter {
    return new Parameter(name, new SimpleTypeReference(typeName, 0, 0), defaultValue, false, ParameterModifier.None, null, 1, 1, false, null)
}

func DeclarationPolicyParamList(parameters: List<Parameter>): List<Parameter> {
    return parameters
}

func DeclarationPolicyValidate(harness: DeclarationPolicyHarness, parameters: List<Parameter>): List<ParameterWalkRequest> {
    state := harness.Owner.BeginParameterDeclarations(parameters, 5, 3)
    return DeclarationPolicyDrive(harness, state)
}

test "a required parameter after an optional one is reported" {
    harness := DeclarationPolicyHarnessNew()
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", new IntLiteralExpression("1", 1, 1)))
    parameters.Add(DeclarationPolicyParam("b", "int", null))
    DeclarationPolicyValidate(harness, parameters)

    reports := DeclarationPolicyErrors(harness, ErrorCode.RequiredParameterAfterOptional)
    assert reports.Count == 1
    assert reports[0].Message == "Required parameter 'b' can't come after optional parameters — move it before the optional ones, or give it a default value too"
}

test "TWO required parameters after an optional one are reported twice, in list order" {
    harness := DeclarationPolicyHarnessNew()
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", new IntLiteralExpression("1", 1, 1)))
    parameters.Add(DeclarationPolicyParam("b", "int", null))
    parameters.Add(DeclarationPolicyParam("c", "int", null))
    DeclarationPolicyValidate(harness, parameters)

    reports := DeclarationPolicyErrors(harness, ErrorCode.RequiredParameterAfterOptional)
    assert reports.Count == 2
    assert reports[0].Message.Contains("'b'")
    assert reports[1].Message.Contains("'c'")
}

test "an optional parameter LAST reports nothing" {
    harness := DeclarationPolicyHarnessNew()
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", null))
    parameters.Add(DeclarationPolicyParam("b", "int", new IntLiteralExpression("2", 1, 1)))
    DeclarationPolicyValidate(harness, parameters)
    assert harness.Errors.Count == 0
}

test "every literal shape is a valid default and reports nothing" {
    harness := DeclarationPolicyHarnessNew()
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", new IntLiteralExpression("1", 1, 1)))
    parameters.Add(DeclarationPolicyParam("b", "float", new FloatLiteralExpression("1.5", 1, 1)))
    parameters.Add(DeclarationPolicyParam("c", "bool", new BoolLiteralExpression(true, 1, 1)))
    parameters.Add(DeclarationPolicyParam("d", "string", new StringLiteralExpression("s", 1, 1)))
    parameters.Add(DeclarationPolicyParam("e", "string", new NullLiteralExpression(1, 1)))
    DeclarationPolicyValidate(harness, parameters)
    assert harness.Errors.Count == 0
}

test "a NEGATED literal is a valid default, and so is an arithmetic combination" {
    harness := DeclarationPolicyHarnessNew()
    negated := new UnaryExpression(UnaryOperator.Negate, new IntLiteralExpression("1", 1, 1), 1, 1)
    sum := new BinaryExpression(new IntLiteralExpression("2", 1, 1), BinaryOperator.Add, new IntLiteralExpression("3", 1, 1), 1, 1)
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", negated))
    parameters.Add(DeclarationPolicyParam("b", "int", sum))
    DeclarationPolicyValidate(harness, parameters)
    assert harness.Errors.Count == 0
}

test "a binary default is invalid when EITHER side is" {
    harness := DeclarationPolicyHarnessNew()
    mixed := new BinaryExpression(new IntLiteralExpression("2", 1, 1), BinaryOperator.Add, new IdentifierExpression("other", 1, 1), 1, 1)
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", mixed))
    DeclarationPolicyValidate(harness, parameters)
    assert DeclarationPolicyErrors(harness, ErrorCode.InvalidDefaultParameterValue).Count == 1
}

test "an identifier is not a default the compiler can evaluate" {
    harness := DeclarationPolicyHarnessNew()
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", new IdentifierExpression("someName", 1, 1)))
    DeclarationPolicyValidate(harness, parameters)

    reports := DeclarationPolicyErrors(harness, ErrorCode.InvalidDefaultParameterValue)
    assert reports.Count == 1
    assert reports[0].Message == "The default value for 'a' must be something the compiler can evaluate — use a literal, null, or a simple constant"
}

test "a `this` parameter and a `params` parameter are skipped by BOTH rules" {
    harness := DeclarationPolicyHarnessNew()
    receiver := new Parameter("self", new SimpleTypeReference("Widget", 0, 0), null, true, ParameterModifier.None, null, 1, 1, false, null)
    rest := new Parameter("rest", new SimpleTypeReference("int", 0, 0), null, false, ParameterModifier.Params, null, 1, 1, false, null)
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", new IntLiteralExpression("1", 1, 1)))
    parameters.Add(receiver)
    parameters.Add(rest)
    DeclarationPolicyValidate(harness, parameters)

    assert DeclarationPolicyErrors(harness, ErrorCode.RequiredParameterAfterOptional).Count == 0
}

test "an empty parameter list walks to completion and asks for nothing" {
    harness := DeclarationPolicyHarnessNew()
    steps := DeclarationPolicyValidate(harness, new List<Parameter>())
    assert steps.Count == 0
    assert harness.Errors.Count == 0
}

test "a walk over ordinary parameters never suspends" {
    harness := DeclarationPolicyHarnessNew()
    parameters := new List<Parameter>()
    parameters.Add(DeclarationPolicyParam("a", "int", new IntLiteralExpression("1", 1, 1)))
    parameters.Add(DeclarationPolicyParam("b", "string", new StringLiteralExpression("s", 1, 1)))
    steps := DeclarationPolicyValidate(harness, parameters)
    assert steps.Count == 0
}
