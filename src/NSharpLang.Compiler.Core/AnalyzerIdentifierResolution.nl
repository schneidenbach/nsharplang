namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHAT A BARE NAME MEANS: the whole of the expression walk's identifier arm, as a RULE rather than a
// walk.
//
// Every other expression family that has moved is a suspendable walk, because every other family has
// operands and an operand is an expression the analyzer must analyse. An identifier has none. It is
// a pure lookup — six ordered channels over the scope stack, the enclosing type's members, the
// built-in metadata name table, project-wide type discovery, project-wide function discovery and the
// referenced-assembly probe — so there is no request type, no state type, no phase and no driver
// loop here. The two consumers call a method and get a `TypeInfo` back.
//
// THE SIX CHANNELS, IN ORDER, ARE THE WHOLE OF `TryResolveBindingTarget`, AND THE ORDER IS
// BEHAVIOUR:
//   1  the SCOPE STACK — locals, parameters and locally declared types, symbols before types. This
//      is also where NARROWING pays off: `AnalyzerFlowNarrowing` writes the narrowed type into the
//      scope's own symbol table, so `text` inside `if text != null { … }` answers `string` here
//      without this rule naming narrowing at all.
//   2  the ENCLOSING TYPE's members, static ones included, so a field or property used bare inside
//      its own type resolves without `this.`.
//   3  the BUILT-IN TYPE KEYWORDS, so `int.Parse`, `string.IsNullOrEmpty` and `int.TryParse` have a
//      receiver.
//   4  project-wide TYPE discovery, which also RECORDS the binding and the semantic-model type.
//   5  project-wide FUNCTION discovery — the function half of auto-discovery.
//   6  the referenced-assembly PROBE, so `Console` resolves. It is deliberately LAST, after the
//      enclosing type's members, so an instance member wins over an imported type of the same name.
// Channel 2 before channel 6 and channel 1 before channel 2 are the two orderings a developer feels
// most directly, and swapping either one silently changes which declaration a name refers to.
//
// THE FOUR CODES IT OWNS: NL301 for a name that is not a variable, NL412 for a name that is not a
// callable, NL308 for a project declaration that IS visible but is not exported, and NL314 for an
// error-tuple result read before its error was checked. NL301 and NL412 each have TWO shapes — the
// RICH `ErrorMessageBuilder` form with a snippet, an underline and did-you-mean suggestions, and a
// bare fallback for a diagnostic that has no source line to point at (a synthesised node, or a
// position the analysed text does not cover).
//
// WHAT IT DOES NOT OWN: the method-group, event and synthetic-SoA-operation reports. Those fire in
// the dispatch host's common tail, AFTER this rule has answered, and they apply to every expression
// form rather than to a name — so an identifier that resolves to a method group is answered here and
// judged there.
//
// CONSTRUCTED ONCE, NEVER REBUILT. Two of its collaborators — member resolution and the well-known
// type bag — ARE replaced when the analyzer opens or closes its metadata load context, so it is TOLD
// about the replacements rather than being rebuilt with them. Rebuilding would drop the
// unverified-result dedupe set mid-analysis, which is the same reason `AnalyzerTypeResolver` takes
// its well-known types through a setter.
class AnalyzerIdentifierResolution {
    diagnosticsValue: AnalyzerDiagnosticSink
    scopesValue: AnalyzerScopeStack
    typeResolverValue: AnalyzerTypeResolver
    projectDiscoveryValue: AnalyzerProjectTypeDiscovery
    externalTypeProbeValue: AnalyzerExternalTypeProbe
    functionTypeFactoryValue: AnalyzerFunctionTypeFactory
    ambientValue: AnalyzerAmbientContext
    nullFlowValue: AnalyzerNullFlow
    extensionMethodsValue: List<FunctionDeclaration>
    memberResolutionValue: AnalyzerMemberResolution
    wellKnownTypesValue: AnalyzerWellKnownTypes?
    semanticModelValue: SemanticModel
    bindingsValue: BindingMap
    compilationUnitValue: CompilationUnit?
    suppressErrorTupleResultUseValue: bool
    reportedUnverifiedResultsValue: Dictionary<(Line: int, Column: int, Name: string), bool>

    // THE ERROR-TUPLE SUPPRESSION, saved and restored by the assignment arm exactly as
    // `AnalyzerNullFlow.SuppressFlowType` is: writing INTO a result name is not a use of it, so a
    // plain `result = …` must not be told the error was never checked. A compound assignment reads
    // the target first, so it is NOT suppressed.
    SuppressErrorTupleResultUse: bool => suppressErrorTupleResultUseValue

    constructor(diagnostics: AnalyzerDiagnosticSink, scopes: AnalyzerScopeStack, typeResolver: AnalyzerTypeResolver, projectDiscovery: AnalyzerProjectTypeDiscovery, externalTypeProbe: AnalyzerExternalTypeProbe, functionTypeFactory: AnalyzerFunctionTypeFactory, ambient: AnalyzerAmbientContext, nullFlow: AnalyzerNullFlow, extensionMethods: List<FunctionDeclaration>, memberResolution: AnalyzerMemberResolution, semanticModel: SemanticModel, bindings: BindingMap) {
        diagnosticsValue = diagnostics
        scopesValue = scopes
        typeResolverValue = typeResolver
        projectDiscoveryValue = projectDiscovery
        externalTypeProbeValue = externalTypeProbe
        functionTypeFactoryValue = functionTypeFactory
        ambientValue = ambient
        nullFlowValue = nullFlow
        extensionMethodsValue = extensionMethods
        memberResolutionValue = memberResolution
        wellKnownTypesValue = null
        semanticModelValue = semanticModel
        bindingsValue = bindings
        compilationUnitValue = null
        suppressErrorTupleResultUseValue = false
        reportedUnverifiedResultsValue = new Dictionary<(Line: int, Column: int, Name: string), bool>()
    }

    // One call per analysis, from the analyzer's own reset block. The semantic model and the binding
    // map are REPLACED per analysis rather than cleared, so they arrive here instead of being held
    // from construction — the same door `AnalyzerTypeResolver` takes them through.
    func BeginAnalysis(unit: CompilationUnit?, semanticModel: SemanticModel, bindings: BindingMap) {
        compilationUnitValue = unit
        semanticModelValue = semanticModel
        bindingsValue = bindings
        suppressErrorTupleResultUseValue = false
        reportedUnverifiedResultsValue.Clear()
    }

    // Member resolution and the well-known-type bag are both REBUILT when the metadata load context
    // opens and again when it closes. This rule is told about the new pair rather than being rebuilt
    // itself: it holds the unverified-result dedupe set, and rebuilding would drop it mid-analysis.
    func SetMetadataCollaborators(memberResolution: AnalyzerMemberResolution, wellKnownTypes: AnalyzerWellKnownTypes?) {
        memberResolutionValue = memberResolution
        wellKnownTypesValue = wellKnownTypes
    }

    func SetSuppressErrorTupleResultUse(value: bool) {
        suppressErrorTupleResultUseValue = value
    }

    // THE RULE. `reportMissingAsFunction` selects which of the two report families a miss belongs to
    // — a callee position wants NL412 and callable suggestions, every other position wants NL301 and
    // variable suggestions — and it also opens the inaccessible-FUNCTION probe, which only a callee
    // position asks.
    //
    // `<error>` is the parser's placeholder for a name it could not read. It answers unknown in
    // silence: the syntax diagnostic has already been reported at that position, and a second
    // "I can't find `<error>`" on top of it is noise.
    func Resolve(name: string, line: int, column: int, reportMissingAsFunction: bool): TypeInfo {
        if name == "<error>" {
            return BuiltInTypes.Unknown
        }

        resolved: TypeInfo = BuiltInTypes.Unknown
        if TryResolveBindingTarget(name, line, column, out resolved) {
            ReportUnverifiedErrorTupleResultUseIfNeeded(name, line, column)
            return resolved
        }

        if reportMissingAsFunction && line > 0 {
            inaccessibleFunctionFile: string? = null
            if projectDiscoveryValue.TryFindInaccessibleVisibleFunction(name, UnitNamespace(), out inaccessibleFunctionFile) {
                diagnosticsValue.ReportInaccessibleMember(name, inaccessibleFunctionFile, line, column)
                return BuiltInTypes.Unknown
            }
        }

        ReportUndefined(name, line, column, reportMissingAsFunction)
        return BuiltInTypes.Unknown
    }

    // THE CALLEE-POSITION FORM of the same rule, and the reason it lives here rather than in the call
    // arm: it is the identifier answer plus the three things every identifier answer needs and the
    // dispatch host does for its own arm — the null state, the flow type that state implies, and the
    // two semantic-model records the IDE's hover reads. The call arm reaches its callee WITHOUT going
    // through the dispatch host, so without this door it would have to repeat all four.
    func CallTarget(identifier: IdentifierExpression): TypeInfo {
        resolved := Resolve(identifier.Name, identifier.Line, identifier.Column, true)
        nullState := nullFlowValue.GetExpressionNullState(identifier, resolved)
        flowType := nullFlowValue.ApplyNullabilityFlowType(resolved, nullState)

        semanticModelValue.RecordExpressionType(identifier.Line, identifier.Column, flowType)
        semanticModelValue.RecordExpressionNullState(identifier.Line, identifier.Column, nullState)

        return flowType
    }

    // The function half of project auto-discovery: exported (PascalCase) top-level functions are
    // visible project-wide within visible namespaces without a file import, mirroring the type half
    // in `AnalyzerProjectTypeDiscovery`. Non-exported top-level functions stay file-private, so they
    // intentionally fall through to the undefined/inaccessible diagnostics.
    //
    // PUBLISHED rather than private because the qualified-external-type probe asks the same question
    // of a dotted name's ROOT before it will accept a CLR type of that name — a project function
    // named `Log` must not be shadowed by `Log.Write` resolving to an assembly type.
    func TryResolveVisibleProjectFunction(name: string, out resolvedType: TypeInfo, out declaration: SymbolDeclaration?): bool {
        declarationFile: string? = null
        functionDeclaration: FunctionDeclaration? = null
        functionSymbol: SymbolDeclaration? = null
        if projectDiscoveryValue.TryResolveVisibleProjectFunction(name, UnitNamespace(), out declarationFile, out functionDeclaration, out functionSymbol) {
            // Both nested guards are TOTAL on this path — discovery only answers `true` after it has
            // matched an exported `FunctionDeclaration` in a named file — but the factory wants
            // non-nullables, and a nested `if` is the only narrowing that holds.
            if functionDeclaration != null && declarationFile != null {
                resolvedType = functionTypeFactoryValue.CreateFromDeclarationInFile(functionDeclaration, declarationFile)
                declaration = functionSymbol
                return true
            }
        }

        resolvedType = BuiltInTypes.Unknown
        declaration = null
        return false
    }

    // THE SIX CHANNELS. A miss answers `false` with `unknown`, which is what separates "this name is
    // nothing" from "this name is something whose type we could not work out" — only the first
    // reports.
    func TryResolveBindingTarget(name: string, line: int, column: int, out resolvedType: TypeInfo): bool {
        // 1. Local symbols first, then local types.
        scopeBinding := scopesValue.ResolveBindingTarget(bindingsValue, diagnosticsValue.CurrentFilePath, name, line, column)
        if scopeBinding != null {
            resolvedType = scopeBinding
            return true
        }

        // 2. The enclosing type's members, static ones included.
        currentType := scopesValue.CurrentTypeScope()
        if currentType != null {
            memberType := memberResolutionValue.ResolveMember(currentType, name, true, ambientValue.CurrentTypeName)
            if !BuiltInTypes.IsUnknown(memberType) {
                resolvedType = memberType
                return true
            }
        }

        // 3. Built-in type keywords (`int`, `string`, `bool`, …) for static member access.
        builtInClrType := AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(wellKnownTypesValue, name)
        if builtInClrType != null {
            resolvedType = new ReflectionTypeInfo(builtInClrType)
            return true
        }

        // 4. Project-wide type discovery. `line > 0` is the synthesised-node test: a node the parser
        // never read has no position, so the inaccessible probe — which exists only to produce a
        // diagnostic — is not worth running for it.
        projectType: TypeInfo = BuiltInTypes.Unknown
        projectDeclaration: SymbolDeclaration? = null
        inaccessibleProjectFile: string? = null
        if projectDiscoveryValue.ResolveVisibleProjectType(name, UnitNamespace(), line > 0, out projectType, out projectDeclaration, out inaccessibleProjectFile) {
            resolvedType = projectType
            // TOTAL on this path: discovery materialises the symbol before it answers `true`.
            if projectDeclaration != null {
                bindingsValue.RecordBinding(diagnosticsValue.CurrentFilePath, line, column, name.Length, projectDeclaration)
            }

            semanticModelValue.RecordType(name, projectType)
            return true
        }

        // A project type that EXISTS but is not exported is reported here and marked, so the type
        // resolver's own NL201 does not report the same position a second time.
        if inaccessibleProjectFile != null {
            diagnosticsValue.ReportInaccessibleMember(name, inaccessibleProjectFile, line, column)
            typeResolverValue.MarkUnresolvedTypeReported(name, line, column)
        }

        // 5. Project-wide function discovery.
        projectFunctionType: TypeInfo = BuiltInTypes.Unknown
        projectFunctionDeclaration: SymbolDeclaration? = null
        if TryResolveVisibleProjectFunction(name, out projectFunctionType, out projectFunctionDeclaration) {
            resolvedType = projectFunctionType
            // TOTAL on this path, for the same reason.
            if projectFunctionDeclaration != null {
                bindingsValue.RecordBinding(diagnosticsValue.CurrentFilePath, line, column, name.Length, projectFunctionDeclaration)
            }

            return true
        }

        // 6. An external type (static class access like `Console`). Deliberately after the
        // enclosing-type member lookup so instance members win over imported type names.
        externalType := externalTypeProbeValue.ResolveExternalType(name)
        if externalType != null {
            resolvedType = externalType
            return true
        }

        resolvedType = BuiltInTypes.Unknown
        return false
    }

    // NL314. An error-tuple result name is only available once its error half has been checked; a
    // read before that is told which guard to write. Deduped by (line, column, name) because one
    // position can be resolved more than once — a write target is resolved again by the classifiers
    // that follow it — and the developer must see the report once.
    func ReportUnverifiedErrorTupleResultUseIfNeeded(name: string, line: int, column: int) {
        if suppressErrorTupleResultUseValue {
            return
        }

        guard := scopesValue.FindErrorTupleResultGuard(name)
        if guard == null {
            return
        }

        if scopesValue.IsErrorTupleResultAvailable(name) {
            return
        }

        key := (Line: line, Column: column, Name: name)
        if reportedUnverifiedResultsValue.ContainsKey(key) {
            return
        }

        reportedUnverifiedResultsValue[key] = true
        diagnosticsValue.Report(ErrorCode.UnverifiedErrorResult, "Result '" + name + "' may be unavailable because '" + guard.ErrorName + "' can be non-null", line, column, "Use '" + name + "' only after `if " + guard.ErrorName + " == null`, or return/throw from an `if " + guard.ErrorName + " != null` error branch before the result is used.", Math.Max(1, name.Length))
    }

    // NL301 / NL412, in the RICH shape when there is a source line to underline and a file to name it
    // in, and in the bare shape otherwise. The suggestion list is drawn from a different pool for
    // each: a callee position may mean an extension method, and no other position may.
    func ReportUndefined(name: string, line: int, column: int, reportMissingAsFunction: bool) {
        // Exactly ONE of the two pools is consulted, as the C# ternary did: they are separate walks
        // over the scope stack and running both would be a second observation, not a tidier branch.
        similarNames := new List<string>()
        if reportMissingAsFunction {
            extensionMethodNames := new List<string>()
            for method in extensionMethodsValue {
                extensionMethodNames.Add(method.Name)
            }

            similarNames = scopesValue.SuggestSimilarCallableNames(name, extensionMethodNames)
        } else {
            similarNames = scopesValue.SuggestSimilarVariableNames(name)
        }

        sourceSnippet := diagnosticsValue.SourceSnippet(line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            if reportMissingAsFunction {
                diagnosticsValue.ReportBuilt(ErrorMessageBuilder.UndefinedFunction(currentFilePath, line, column, sourceSnippet, name.Length, name, similarNames))
            } else {
                diagnosticsValue.ReportBuilt(ErrorMessageBuilder.UndefinedVariable(currentFilePath, line, column, sourceSnippet, name.Length, name, similarNames))
            }

            return
        }

        if reportMissingAsFunction {
            diagnosticsValue.Report(ErrorCode.UndefinedFunction, "Function '" + name + "' not found", line, column, null, name.Length)
        } else {
            diagnosticsValue.Report(ErrorCode.UndefinedVariable, "I can't find '" + name + "' — it hasn't been declared in this scope", line, column, null, 0)
        }
    }

    func UnitNamespace(): string? {
        return AnalyzerProjectSourceProvider.UnitNamespace(compilationUnitValue)
    }
}
