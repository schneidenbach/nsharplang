namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast

// Native contracts for the diagnostic sink and the type-reference resolution walk.
//
// Every member behind these contracts was `private` in Analyzer.cs, so no test named any of them:
// their behaviour was pinned only indirectly, through end-to-end diagnostics. This is their first
// DIRECT pinning, and it goes at the decisions that read like plumbing and are not:
//
//   * the CHANNEL ORDER, which is what makes a local declaration shadow a project type and a project
//     type outrank a CLR type of the same name;
//   * the DEDUPE SET, which is shared across five report sites AND two shell sites outside the walk,
//     so the first report at a position silences every later one there;
//   * `line <= 0`, which means "no source position" and turns every report and every binding record
//     off while still resolving;
//   * the REPORT OPT-IN, which is off by default, on inside a declared-type position, and forced OFF
//     again for the open-generic head probe while the CALLER's opt-in still decides the three
//     generic reports;
//   * the SPANS and LENGTHS the reports carry, because an IDE underlines exactly those columns;
//   * the SEMANTIC-MODEL and BINDING-MAP writes, which are what hover and go-to-definition read.

func ResolverSinkOf(errors: List<CompilerError>): AnalyzerDiagnosticSink {
    return new AnalyzerDiagnosticSink(errors, new AnalyzerProjectSourceProvider())
}

func ResolverScopesOf(): AnalyzerScopeStack {
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    return scopes
}

// A resolver over an EMPTY project with no referenced assemblies: the built-in table, the scope stack
// and the unresolved fallback are the only live channels, which is exactly what most of these
// contracts are about.
func ResolverOf(
    scopes: AnalyzerScopeStack,
    sink: AnalyzerDiagnosticSink,
    model: SemanticModel,
    bindings: BindingMap): AnalyzerTypeResolver {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    return new AnalyzerTypeResolver(
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
}

// A class type shaped only where these contracts read it: its type-parameter list decides the head
// arity, and its nested types decide the dotted walk.
func ResolverClassOf(
    name: string,
    typeParameters: TypeParameter[],
    nestedTypes: NestedTypeInfo[]): ClassTypeInfo {
    return new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[0],
        typeParameters,
        new ParameterDeclarationInfo[0],
        new DeclaredMemberInfo[0],
        nestedTypes,
        true)
}

func ResolverCodes(errors: List<CompilerError>): string {
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

func ResolverTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    simple := candidate as SimpleTypeInfo
    if simple != null {
        return "simple:" + simple.Name
    }

    external := candidate as ExternalTypeInfo
    if external != null {
        return "external:" + external.Name
    }

    generic := candidate as GenericTypeInfo
    if generic != null {
        return "generic:" + generic.Name + "/" + generic.TypeArguments.Count.ToString()
    }

    array := candidate as ArrayTypeInfo
    if array != null {
        return "array(" + ResolverTypeName(array.ElementType) + ")"
    }

    nullable := candidate as NullableTypeInfo
    if nullable != null {
        return "nullable(" + ResolverTypeName(nullable.InnerType) + ")"
    }

    byRef := candidate as ByRefTypeInfo
    if byRef != null {
        return "byref(" + ResolverTypeName(byRef.InnerType) + ")"
    }

    anonymous := candidate as AnonymousUnionTypeInfo
    if anonymous != null {
        return "union/" + anonymous.Arms.Count.ToString()
    }

    tuple := candidate as TupleTypeInfo
    if tuple != null {
        return "tuple/" + tuple.Elements.Count.ToString()
    }

    functionType := candidate as FunctionTypeInfo
    if functionType != null {
        return "function/" + functionType.ParameterTypes.Count.ToString()
    }

    if BuiltInTypes.IsUnknown(candidate) {
        return "unknown"
    }

    return "<other>"
}

func ResolverArmNames(candidate: TypeInfo): string {
    anonymous := candidate as AnonymousUnionTypeInfo
    if anonymous == null {
        return "<not-a-union>"
    }

    text := ""
    index := 0
    while index < anonymous.Arms.Count {
        if index > 0 {
            text = text + "|"
        }
        text = text + ResolverTypeName(anonymous.Arms[index])
        index = index + 1
    }
    return text
}

// ---- the diagnostic sink -----------------------------------------------------------------------

test "the sink appends to the caller's own list, so report order survives the boundary" {
    errors := new List<CompilerError>()
    sink := ResolverSinkOf(errors)

    // A shell report and an owner report land in ONE list in call order. That is the whole reason the
    // list is a constructor argument rather than owned state.
    errors.Add(AnalyzerDiagnostics.Create(
        ErrorCode.UnusedVariable, "shell first", "a.nl", 1, 1, null, null, 3, ErrorSeverity.Warning))
    sink.Report(ErrorCode.TypeNotFound, "owner second", 2, 2, null, 4)
    errors.Add(AnalyzerDiagnostics.Create(
        ErrorCode.InvalidSyntax, "shell third", "a.nl", 3, 3, null, null, 5, ErrorSeverity.Error))

    assert errors.Count == 3
    assert errors[0].Message == "shell first"
    assert errors[1].Message == "owner second"
    assert errors[2].Message == "shell third"
    assert ResolverCodes(errors) == "901,201,103"
}

test "the sink stamps the current file and severity, and a warning is not an error" {
    errors := new List<CompilerError>()
    sink := ResolverSinkOf(errors)
    sink.BeginAnalysis("/p/main.nl", "line one\nline two\nline three\n")

    sink.Report(ErrorCode.TypeNotFound, "boom", 2, 5, "fix it", 7)
    sink.Warn(ErrorCode.UnusedVariable, "meh", 3, 1, null, 2)

    assert errors[0].FileName == "/p/main.nl"
    assert errors[0].Severity == ErrorSeverity.Error
    assert errors[0].Line == 2
    assert errors[0].Column == 5
    assert errors[0].Length == 7
    assert errors[0].Suggestion == "fix it"
    // The snippet is the diagnostic's OWN line, taken from the analysed text.
    assert errors[0].SourceSnippet == "line two"

    assert errors[1].Severity == ErrorSeverity.Warning
    assert errors[1].SourceSnippet == "line three"
    // A null suggestion is filled in from the code's catalogue entry when it has one, and stays null
    // when it does not — the sink never invents advice.
    assert errors[1].Suggestion == null
}

test "no source text and line 0 both mean NO snippet, and a new analysis replaces the text" {
    errors := new List<CompilerError>()
    sink := ResolverSinkOf(errors)

    // Before any analysis there is neither a file nor text.
    assert sink.SourceSnippet(1) == null
    assert sink.CurrentFilePath == null

    sink.BeginAnalysis("/p/main.nl", "only line\n")
    assert sink.SourceSnippet(1) == "only line"
    // Line 0 is "no position", not "the first line".
    assert sink.SourceSnippet(0) == null
    assert sink.SourceSnippet(-3) == null
    // Past the end has no line, which is the same answer as no text: null rather than a throw.
    assert sink.SourceSnippet(99) == null

    // An EMPTY text is the same as no text.
    sink.BeginAnalysis("/p/other.nl", "")
    assert sink.SourceSnippet(1) == null
    assert sink.CurrentFilePath == "/p/other.nl"

    sink.BeginAnalysis("/p/third.nl", null)
    assert sink.SourceSnippet(1) == null
}

test "the inaccessible report names the DECLARING namespace, and the global namespace is spelled out" {
    errors := new List<CompilerError>()
    provider := new AnalyzerProjectSourceProvider()
    root := Path.Combine(Path.GetTempPath(), "s10-sink-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(root)
    try {
        namespaced := Path.Combine(root, "lib.nl")
        File.WriteAllText(namespaced, "namespace Inner.Deep\n\nclass hidden {\n}\n")
        globalFile := Path.Combine(root, "glob.nl")
        File.WriteAllText(globalFile, "class hidden {\n}\n")

        sink := new AnalyzerDiagnosticSink(errors, provider)
        sink.BeginAnalysis("/p/main.nl", null)

        // The namespace comes from the DECLARING file read off disk, not from the current file.
        assert sink.ReportInaccessibleMember("hidden", namespaced, 4, 9)
        assert errors[0].Code == ErrorCode.InaccessibleMember
        assert errors[0].Message.Contains("'hidden' is not exported from package/namespace 'Inner.Deep'")
        assert errors[0].Message.Contains("use PascalCase for cross-package visibility")
        assert errors[0].Line == 4
        assert errors[0].Column == 9
        assert errors[0].Length == 6

        // A file with no namespace declaration is the GLOBAL namespace, and it is named.
        assert sink.ReportInaccessibleMember("hidden", globalFile, 1, 1)
        assert errors[1].Message.Contains("namespace '<global>'")

        // An absent declaration file is the global namespace too, and the length is at least one even
        // for an empty name.
        assert sink.ReportInaccessibleMember("", null, 1, 1)
        assert errors[2].Message.Contains("namespace '<global>'")
        assert errors[2].Length == 1
    } finally {
        Directory.Delete(root, true)
    }
}

// ---- the channel order -------------------------------------------------------------------------

test "the built-in table answers before the scope stack, and the scope stack before the fallback" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)

    // Channel 1: the built-in name table. It answers even for a name the scope stack also binds,
    // which is why declaring a type called `int` cannot shadow the keyword.
    scopes.DeclareNestedTypeIfAbsent("int", new SimpleTypeInfo("shadow"))
    assert ResolverTypeName(resolver.ResolveSimpleType("int", 3, 5)) == "simple:int"

    // Channel 2: the scope stack.
    scopes.DeclareNestedTypeIfAbsent("Customer", new SimpleTypeInfo("Customer"))
    assert ResolverTypeName(resolver.ResolveSimpleType("Customer", 3, 5)) == "simple:Customer"

    // Channel 8: nothing recognised the name, so it becomes a placeholder rather than an error type.
    assert ResolverTypeName(resolver.ResolveSimpleType("Nope", 3, 5)) == "external:Nope"

    // None of the three reported anything: the opt-in is OFF by default.
    assert errors.Count == 0
}

test "line 0 resolves but records no binding, while a positioned scope hit does record one" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)
    classScope := new Scope(ScopeKind.Class)
    classScope.RecordDeclarationLocation("Customer", "/p/lib.nl", 4, 7, "class")
    scopes.Push(new SemanticModel(), classScope, 2, 1)
    scopes.DeclareNestedTypeIfAbsent("Customer", new SimpleTypeInfo("Customer"))

    assert ResolverTypeName(resolver.ResolveSimpleType("Customer", 0, 0)) == "simple:Customer"
    assert bindings.GetBindingAt("/p/main.nl", 0, 0) == null

    assert ResolverTypeName(resolver.ResolveSimpleType("Customer", 7, 11)) == "simple:Customer"
    // A scope hit with a position records the binding go-to-definition reads, pointing at the
    // DECLARING file and position rather than at the reference.
    declaration := bindings.GetBindingAt("/p/main.nl", 7, 11)
    assert declaration != null
    assert declaration.File == "/p/lib.nl"
    assert declaration.Line == 4
    assert declaration.Column == 7

    // A scope hit whose scope carries no declaration location resolves but records nothing: the
    // binding walk needs a declaration to point at.
    scopes.DeclareNestedTypeIfAbsent("Anonymous", new SimpleTypeInfo("Anonymous"))
    assert ResolverTypeName(resolver.ResolveSimpleType("Anonymous", 8, 11)) == "simple:Anonymous"
    assert bindings.GetBindingAt("/p/main.nl", 8, 11) == null
}

// ---- the report opt-in and the dedupe set ------------------------------------------------------

test "NL201 fires only at a declared-type position, only once per position, and never for a dotted name" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    sink := ResolverSinkOf(errors)
    sink.BeginAnalysis("/p/main.nl", null)
    resolver := ResolverOf(scopes, sink, model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    // Not a declared-type position: silent.
    resolver.ResolveType(new SimpleTypeReference("Nope", 3, 5))
    assert errors.Count == 0

    // A declared-type position: NL201, once.
    resolver.ResolveDeclaredType(new SimpleTypeReference("Nope", 3, 5))
    assert errors.Count == 1
    assert errors[0].Code == ErrorCode.TypeNotFound
    assert errors[0].Message == "Type 'Nope' not found"
    assert errors[0].Line == 3
    assert errors[0].Column == 5
    assert errors[0].Length == 4

    // The SAME position again is suppressed by the dedupe set.
    resolver.ResolveDeclaredType(new SimpleTypeReference("Nope", 3, 5))
    assert errors.Count == 1

    // A DIFFERENT position for the same name is a different diagnostic.
    resolver.ResolveDeclaredType(new SimpleTypeReference("Nope", 4, 5))
    assert errors.Count == 2

    // Line 0 has no position to report at.
    resolver.ResolveDeclaredType(new SimpleTypeReference("Nope", 0, 0))
    assert errors.Count == 2

    // A DOTTED name stays lenient: namespace-qualified externals resolve through other channels.
    resolver.ResolveDeclaredType(new SimpleTypeReference("Some.Where.Nope", 5, 5))
    assert errors.Count == 2

    // The opt-in is scoped to the declared-type call: it is off again afterwards.
    resolver.ResolveType(new SimpleTypeReference("Other", 6, 5))
    assert errors.Count == 2
}

test "the dedupe set is shared with the shell's own inaccessible reports, and a new analysis clears it" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    // The shell claims the position first — this is what the `new Union.Case` and identifier-binding
    // inaccessible probes do — and the walk's NL201 at that position stays silent.
    assert resolver.MarkUnresolvedTypeReported("Nope", 3, 5)
    assert !resolver.MarkUnresolvedTypeReported("Nope", 3, 5)
    resolver.ResolveDeclaredType(new SimpleTypeReference("Nope", 3, 5))
    assert errors.Count == 0

    // A new analysis starts a fresh set, and turns the opt-in off again.
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)
    assert resolver.MarkUnresolvedTypeReported("Nope", 3, 5)
    resolver.ResolveDeclaredType(new SimpleTypeReference("Other", 3, 5))
    assert errors.Count == 1
}

test "the did-you-mean suggestion is built from the names actually in scope" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)
    scopes.DeclareNestedTypeIfAbsent("Customer", new SimpleTypeInfo("Customer"))

    resolver.ResolveDeclaredType(new SimpleTypeReference("Custmer", 3, 5))
    assert errors[0].Suggestion.Contains("Did you mean 'Customer'?")

    // A name nothing is near falls back to the generic advice.
    resolver.ResolveDeclaredType(new SimpleTypeReference("Zqxwvut", 4, 5))
    assert errors[1].Suggestion.Contains("Check the spelling")
    assert !errors[1].Suggestion.Contains("Did you mean")
}

test "`var` is refused as a type at a position, and is silently unknown without one" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)

    // This report does NOT consult the opt-in: `var` is never a type, at any position.
    assert ResolverTypeName(resolver.ResolveSimpleType("var", 3, 5)) == "unknown"
    assert errors.Count == 1
    assert errors[0].Code == ErrorCode.InvalidSyntax
    assert errors[0].Message == "'var' is not a type; use ':=' for type inference"
    assert errors[0].Line == 3
    assert errors[0].Column == 5

    // Nor is it deduped — it is not an unresolved-type report.
    assert ResolverTypeName(resolver.ResolveSimpleType("var", 3, 5)) == "unknown"
    assert errors.Count == 2

    // Without a position the report is skipped AND so is the refusal: `var` is not in the built-in
    // table, so it falls through every channel to the unresolved placeholder. That asymmetry is the
    // behaviour, not a rounding of it.
    assert ResolverTypeName(resolver.ResolveSimpleType("var", 0, 0)) == "external:var"
    assert errors.Count == 2
}

// ---- the nine-arm dispatch and the semantic-model record --------------------------------------

test "every reference family resolves through the dispatch, composing inner resolutions" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    assert ResolverTypeName(resolver.ResolveType(new SimpleTypeReference("int", 3, 5))) == "simple:int"
    assert ResolverTypeName(resolver.ResolveType(
        new ArrayTypeReference(new SimpleTypeReference("int", 3, 5)))) == "array(simple:int)"
    assert ResolverTypeName(resolver.ResolveType(
        new ArrayTypeReference(new ArrayTypeReference(new SimpleTypeReference("int", 3, 5)))))
        == "array(array(simple:int))"
    assert ResolverTypeName(resolver.ResolveType(
        new NullableTypeReference(new SimpleTypeReference("int", 3, 5)))) == "nullable(simple:int)"
    assert ResolverTypeName(resolver.ResolveType(
        new ByRefTypeReference(new SimpleTypeReference("int", 3, 5)))) == "byref(simple:int)"

    elements := new List<TupleTypeElement>()
    elements.Add(new TupleTypeElement(new SimpleTypeReference("int", 3, 5), "first"))
    elements.Add(new TupleTypeElement(new SimpleTypeReference("string", 3, 12), null))
    tuple := resolver.ResolveType(new TupleTypeReference(elements))
    assert ResolverTypeName(tuple) == "tuple/2"
    tupleInfo := tuple as TupleTypeInfo
    assert tupleInfo.Elements[0].Name == "first"
    assert ResolverTypeName(tupleInfo.Elements[0].Type) == "simple:int"
    // An unnamed element keeps its null name rather than being given a positional one.
    assert tupleInfo.Elements[1].Name == null

    parameterTypes := new List<TypeReference>()
    parameterTypes.Add(new SimpleTypeReference("int", 3, 5))
    functionType := resolver.ResolveType(
        new FunctionTypeReference(parameterTypes, new SimpleTypeReference("bool", 3, 14)))
    assert ResolverTypeName(functionType) == "function/1"
    assert ResolverTypeName((functionType as FunctionTypeInfo).ReturnType) == "simple:bool"

    // The unmodelled arm answers unknown rather than throwing.
    assert ResolverTypeName(resolver.ResolveType(new TypeReference())) == "unknown"
}

test "every resolved reference is recorded at its OWN start span, and a span-less one is skipped" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    // An array reference records BOTH itself and its element — at the same span, because an array's
    // start span IS its element's.
    resolver.ResolveType(new ArrayTypeReference(new SimpleTypeReference("int", 7, 11)))
    assert ResolverTypeName(model.LookupTypeReferenceAtPosition(7, 11)) == "array(simple:int)"

    // A nested reference at its own position gets its own record.
    resolver.ResolveType(new NullableTypeReference(new SimpleTypeReference("string", 9, 3)))
    assert ResolverTypeName(model.LookupTypeReferenceAtPosition(9, 3)) == "nullable(simple:string)"

    // A reference with no valid position is not recorded at all.
    before := model.TypeReferenceTypes.Count
    resolver.ResolveType(new SimpleTypeReference("int", 0, 0))
    assert model.TypeReferenceTypes.Count == before
}

// ---- the generic head and the two NL207 shapes -------------------------------------------------

test "a locally-declared generic at the wrong arity is NL207, with the count in the message" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    scopes.DeclareNestedTypeIfAbsent("Box", ResolverClassOf("Box", [new TypeParameter("T")], []))

    twoArguments := new List<TypeReference>()
    twoArguments.Add(new SimpleTypeReference("int", 3, 9))
    twoArguments.Add(new SimpleTypeReference("string", 3, 14))
    resolver.ResolveDeclaredType(new GenericTypeReference("Box", twoArguments, 3, 5))

    assert errors.Count == 1
    assert errors[0].Code == ErrorCode.InvalidTypeArgument
    assert errors[0].Message == "Generic type 'Box' takes 1 type argument(s), but 2 were provided"
    assert errors[0].Suggestion == "Match the declaration's type parameter count for 'Box'"
    // The report underlines the NAME, not the whole reference.
    assert errors[0].Line == 3
    assert errors[0].Column == 5
    assert errors[0].Length == 3

    // The right arity is silent, and the resolved generic carries the declaration as its definition.
    oneArgument := new List<TypeReference>()
    oneArgument.Add(new SimpleTypeReference("int", 4, 9))
    resolved := resolver.ResolveDeclaredType(new GenericTypeReference("Box", oneArgument, 4, 5))
    assert errors.Count == 1
    assert ResolverTypeName(resolved) == "generic:Box/1"
    assert (resolved as GenericTypeInfo).GenericDefinition != null
}

test "a NON-generic name given type arguments gets the other NL207 wording" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)
    scopes.DeclareNestedTypeIfAbsent("Plain", new SimpleTypeInfo("Plain"))

    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("int", 3, 11))
    resolver.ResolveDeclaredType(new GenericTypeReference("Plain", arguments, 3, 5))

    assert errors.Count == 1
    assert errors[0].Message == "'Plain' is not generic, but 1 type argument(s) were provided"
    assert errors[0].Suggestion == "Remove the type arguments: 'Plain'"
}

test "the generic head probe suppresses ITS unresolved report while the CALLER's opt-in still decides" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("int", 3, 9))

    // Off a declared-type position: silent, even though `Lst` resolves through no channel.
    resolver.ResolveType(new GenericTypeReference("Lst", arguments, 3, 5))
    assert errors.Count == 0

    // At a declared-type position: ONE NL201 for the generic NAME. The head probe's own resolution
    // ran with reporting forced off, so the name is not reported twice.
    resolver.ResolveDeclaredType(new GenericTypeReference("Lst", arguments, 4, 5))
    assert errors.Count == 1
    assert errors[0].Code == ErrorCode.TypeNotFound
    assert errors[0].Message == "Type 'Lst' not found"
    assert errors[0].Length == 3

    // A DOTTED generic name stays lenient, exactly as a dotted simple name does.
    resolver.ResolveDeclaredType(new GenericTypeReference("Some.Lst", arguments, 5, 5))
    assert errors.Count == 1
}

test "a generic reference with no position resolves its arguments and reports nothing" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)
    scopes.DeclareNestedTypeIfAbsent("Plain", new SimpleTypeInfo("Plain"))

    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("int", 0, 0))
    resolved := resolver.ResolveDeclaredType(new GenericTypeReference("Plain", arguments, 0, 0))

    // The whole head block — the name probe, the arity table and all three reports — is gated on a
    // real position, so there is no definition and no diagnostic.
    assert ResolverTypeName(resolved) == "generic:Plain/1"
    assert (resolved as GenericTypeInfo).GenericDefinition == null
    assert errors.Count == 0
}

// ---- anonymous unions ---------------------------------------------------------------------------

test "a nested anonymous union is FLATTENED into its parent rather than nested" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    inner := new List<TypeReference>()
    inner.Add(new SimpleTypeReference("int", 3, 5))
    inner.Add(new SimpleTypeReference("string", 3, 11))
    outer := new List<TypeReference>()
    outer.Add(new UnionTypeReference(inner))

    // Two arms, not one arm that is itself a union.
    assert ResolverArmNames(resolver.ResolveType(new UnionTypeReference(outer))) == "simple:int|simple:string"
    assert errors.Count == 0
}

test "a repeated arm is NL306 and is DROPPED, and more than two distinct arms is NL207" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    duplicate := new List<TypeReference>()
    duplicate.Add(new SimpleTypeReference("int", 3, 5))
    duplicate.Add(new SimpleTypeReference("int", 3, 11))
    resolved := resolver.ResolveType(new UnionTypeReference(duplicate))

    // The duplicate is removed, so the union is single-armed and NOT also over-wide.
    assert ResolverArmNames(resolved) == "simple:int"
    assert errors.Count == 1
    assert errors[0].Code == ErrorCode.DuplicateDeclaration
    assert errors[0].Message == "Anonymous union type repeats arm 'int'. Each arm must be unique."
    // The report is anchored at the union's start span, which is its FIRST arm.
    assert errors[0].Line == 3
    assert errors[0].Column == 5
    // With no span of its own the length falls back to one column.
    assert errors[0].Length == 1

    threeArms := new List<TypeReference>()
    threeArms.Add(new SimpleTypeReference("int", 5, 5))
    threeArms.Add(new SimpleTypeReference("string", 5, 11))
    threeArms.Add(new SimpleTypeReference("bool", 5, 20))
    assert ResolverArmNames(resolver.ResolveType(new UnionTypeReference(threeArms)))
        == "simple:int|simple:string|simple:bool"
    assert errors.Count == 2
    assert errors[1].Code == ErrorCode.InvalidTypeArgument
    assert errors[1].Message == "Anonymous union types support exactly two arms in v1; this union has 3 arms."
    assert errors[1].Suggestion == "Declare a named `union` for larger variants."
}

test "a union that HAS a span underlines the whole union, and an empty union is silent" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    arms := new List<TypeReference>()
    arms.Add(new SimpleTypeReference("int", 6, 9))
    arms.Add(new SimpleTypeReference("string", 6, 15))
    arms.Add(new SimpleTypeReference("bool", 6, 24))
    spanned := new UnionTypeReference(arms)
    spanned.Span = new SourceSpan(6, 9, 6, 29)
    resolver.ResolveType(spanned)

    assert errors.Count == 1
    // A valid span makes the report point at the span's own start and cover its width.
    assert errors[0].Line == 6
    assert errors[0].Column == 9
    assert errors[0].Length == 20

    // No arms at all: an empty union, no reports.
    assert ResolverArmNames(resolver.ResolveType(new UnionTypeReference(new List<TypeReference>()))) == ""
    assert errors.Count == 1
}

// ---- dotted nested types ------------------------------------------------------------------------

test "a dotted name walks nested members from a root IN SCOPE, and refuses everything else" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)

    scopes.DeclareNestedTypeIfAbsent("Outer", ResolverClassOf(
        "Outer", [], [new NestedTypeInfo("Inner", new SimpleTypeInfo("Outer.Inner"))]))

    resolved: TypeInfo = BuiltInTypes.Unknown
    assert resolver.TryResolveDottedNestedType("Outer.Inner", out resolved)
    assert ResolverTypeName(resolved) == "simple:Outer.Inner"

    // A single segment is not a dotted name at all.
    assert !resolver.TryResolveDottedNestedType("Outer", out resolved)
    assert ResolverTypeName(resolved) == "unknown"

    // Empty segments are dropped, so `Outer..Inner` is the same two-segment walk.
    assert resolver.TryResolveDottedNestedType("Outer..Inner", out resolved)
    assert ResolverTypeName(resolved) == "simple:Outer.Inner"

    // Nothing but separators is no segments, and a root that is not in scope is a miss rather than a
    // report: the caller's later channels still get their turn.
    assert !resolver.TryResolveDottedNestedType(".", out resolved)
    assert !resolver.TryResolveDottedNestedType("..", out resolved)
    assert !resolver.TryResolveDottedNestedType("Absent.Inner", out resolved)
    assert !resolver.TryResolveDottedNestedType("Outer.Absent", out resolved)
    assert ResolverTypeName(resolved) == "unknown"
    assert errors.Count == 0
}

// ---- the SoA row report -------------------------------------------------------------------------

test "a `.Row` reference is refused only when the feature is on AND the prefix names a table" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("kind", new SimpleTypeReference("int", 2, 11), 2, 5))
    scopes.DeclareNestedTypeIfAbsent("NodeTable", new SoaRecordTypeInfo(
        new SoaRecordDeclarationInfo("NodeTable", columns, 1, 1)))
    scopes.DeclareNestedTypeIfAbsent("Plain", new SimpleTypeInfo("Plain"))

    previous := Environment.GetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA")
    try {
        Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", null)
        // With the feature OFF the row suffix is just a dotted name.
        assert !resolver.ReportSoaRowTypeReferenceIfNeeded("NodeTable.Row", 5, 11)
        assert errors.Count == 0

        Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", "1")
        assert resolver.ReportSoaRowTypeReferenceIfNeeded("NodeTable.Row", 5, 11)
        assert errors.Count == 1
        assert errors[0].Code == ErrorCode.InvalidSyntax
        assert errors[0].Message == "SoA row type 'NodeTable.Row' is not part of this lowering"
        assert errors[0].Suggestion.Contains("Pass the 'NodeTable' table and an int row index instead")
        assert errors[0].Length == 13

        // The answer stays TRUE at the same position — the reference is still refused — but its own
        // dedupe set silences the second report.
        assert resolver.ReportSoaRowTypeReferenceIfNeeded("NodeTable.Row", 5, 11)
        assert errors.Count == 1
        // A different position reports again.
        assert resolver.ReportSoaRowTypeReferenceIfNeeded("NodeTable.Row", 6, 11)
        assert errors.Count == 2

        // Not a table, no position, no suffix, and an empty prefix are all "not a row reference".
        assert !resolver.ReportSoaRowTypeReferenceIfNeeded("Plain.Row", 5, 11)
        assert !resolver.ReportSoaRowTypeReferenceIfNeeded("NodeTable.Row", 0, 0)
        assert !resolver.ReportSoaRowTypeReferenceIfNeeded("NodeTable", 5, 11)
        assert !resolver.ReportSoaRowTypeReferenceIfNeeded(".Row", 5, 11)
        assert errors.Count == 2

        // Through the reference walk the row reference SHORT-CIRCUITS to unknown rather than
        // resolving through the remaining channels.
        assert ResolverTypeName(resolver.ResolveType(new SimpleTypeReference("NodeTable.Row", 8, 11)))
            == "unknown"

        // And the SoA set is cleared by a new analysis, exactly like the unresolved set.
        resolver.BeginAnalysis("/p/main.nl", null, model, bindings)
        errorsBefore := errors.Count
        assert resolver.ReportSoaRowTypeReferenceIfNeeded("NodeTable.Row", 5, 11)
        assert errors.Count == errorsBefore + 1
    } finally {
        Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", previous)
    }
}

// ---- the bulk helpers ---------------------------------------------------------------------------

test "the bulk helpers resolve every reference they are given, and tolerate absence" {
    errors := new List<CompilerError>()
    scopes := ResolverScopesOf()
    model := new SemanticModel()
    bindings := new BindingMap()
    resolver := ResolverOf(scopes, ResolverSinkOf(errors), model, bindings)
    resolver.BeginAnalysis("/p/main.nl", null, model, bindings)

    // A null reference is a no-op, not a throw: a class with no base clause is the common case.
    resolver.ResolveTypeIfPresent(null)
    assert model.TypeReferenceTypes.Count == 0

    resolver.ResolveTypeIfPresent(new SimpleTypeReference("int", 3, 5))
    assert model.TypeReferenceTypes.Count == 1

    references := new List<TypeReference>()
    references.Add(new SimpleTypeReference("string", 4, 5))
    references.Add(new SimpleTypeReference("bool", 5, 5))
    resolver.ResolveTypeReferences(references)
    assert model.TypeReferenceTypes.Count == 3
    assert ResolverTypeName(model.LookupTypeReferenceAtPosition(5, 5)) == "simple:bool"

    // Absent constraints are a no-op; present ones resolve every constraint of every parameter.
    resolver.ResolveGenericConstraintTypes(null)
    assert model.TypeReferenceTypes.Count == 3

    constraintTypes := new List<TypeReference>()
    constraintTypes.Add(new SimpleTypeReference("object", 6, 5))
    constraints := new List<GenericConstraint>()
    constraints.Add(new GenericConstraint("T", constraintTypes, SpecialConstraintKind.None))
    resolver.ResolveGenericConstraintTypes(constraints)
    assert model.TypeReferenceTypes.Count == 4
    assert ResolverTypeName(model.LookupTypeReferenceAtPosition(6, 5)) == "simple:object"
}
