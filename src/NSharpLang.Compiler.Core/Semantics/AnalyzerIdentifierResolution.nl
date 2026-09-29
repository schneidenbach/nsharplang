namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
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
// THE SIX CHANNELS, IN ORDER, ARE THE WHOLE OF `TryResolveBindingTarget`. A member/free-function
// collision is diagnosed by simple name only when both candidates serve the written position:
//   1  the SCOPE STACK — locals, parameters and locally declared types, symbols before types. This
//      is also where NARROWING pays off: `AnalyzerFlowNarrowing` writes the narrowed type into the
//      scope's own symbol table, so `text` inside `if text != null { … }` answers `string` here
//      without this rule naming narrowing at all. A local variable, parameter or local function
//      keeps its current shadowing behavior; free-function groups outside the type are compared with
//      a viable member group before the type wins the provisional binding below.
//   2  the ENCLOSING TYPE's members, static ones included. Reads admit value members and method
//      groups; calls admit methods and delegate values, with a non-invocable member yielding to a
//      visible free function. Write targets do not compare with free functions. When both candidates
//      are viable, NL209 is based on the name regardless of call arguments. The resolver RECORDS the
//      binding for a member a source type declares, as
//      channels 1, 4 and 5 do, so a bare inherited member navigates like its `this.` form after the
//      ambiguity diagnostic has been reported.
//   3  the BUILT-IN TYPE KEYWORDS, so `int.Parse`, `string.IsNullOrEmpty` and `int.TryParse` have a
//      receiver.
//   4  project-wide TYPE discovery, which also RECORDS the binding and the semantic-model type.
//   5  project-wide FUNCTION discovery — the function half of auto-discovery.
//   6  the referenced-assembly PROBE, so `Console` resolves. It is deliberately LAST, after the
//      enclosing type's members, so an instance member wins over an imported type of the same name.
// Channel 2 before channel 6 and channel 1 before channel 2 are the two orderings a developer feels
// most directly, and swapping either one silently changes which declaration a name refers to.
//
// THE FIVE CODES IT OWNS: NL301 for a name that is not a variable, NL412 for a called name that
// resolves to nothing, NL413 for a called name that resolves to a VALUE whose type cannot be called
// (a `string` field, an `int` parameter), NL308 for a project declaration that IS visible but is not
// exported, and NL314 for an error-tuple result read before its error was checked. NL301 and NL412
// each have TWO shapes — the RICH `ErrorMessageBuilder` form with a snippet, an underline and
// did-you-mean suggestions, and a bare fallback for a diagnostic that has no source line to point at
// (a synthesised node, or a position the analysed text does not cover).
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
    sourceMemberDeclarationsValue: AnalyzerSourceMemberDeclarations
    wellKnownTypesValue: AnalyzerWellKnownTypes?
    importUsageCreditValue: AnalyzerImportUsageCredit?
    semanticModelValue: SemanticModel
    bindingsValue: BindingMap
    compilationUnitValue: CompilationUnit?
    suppressErrorTupleResultUseValue: bool
    reportedUnverifiedResultsValue: Dictionary<(Line: int, Column: int, Name: string), bool>
    reportedMemberFunctionAmbiguitiesValue: Dictionary<(Line: int, Column: int, Name: string), bool>

    // THE ERROR-TUPLE SUPPRESSION, saved and restored by the assignment arm exactly as
    // `AnalyzerNullFlow.SuppressedFlowTypeNode` is: writing INTO a result name is not a use of it, so a
    // plain `result = …` must not be told the error was never checked. A compound assignment reads
    // the target first, so it is NOT suppressed.
    SuppressErrorTupleResultUse: bool => suppressErrorTupleResultUseValue

    constructor(diagnostics: AnalyzerDiagnosticSink, scopes: AnalyzerScopeStack, typeResolver: AnalyzerTypeResolver, projectDiscovery: AnalyzerProjectTypeDiscovery, externalTypeProbe: AnalyzerExternalTypeProbe, functionTypeFactory: AnalyzerFunctionTypeFactory, ambient: AnalyzerAmbientContext, nullFlow: AnalyzerNullFlow, extensionMethods: List<FunctionDeclaration>, memberResolution: AnalyzerMemberResolution, sourceMemberDeclarations: AnalyzerSourceMemberDeclarations, semanticModel: SemanticModel, bindings: BindingMap) {
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
        sourceMemberDeclarationsValue = sourceMemberDeclarations
        wellKnownTypesValue = null
        importUsageCreditValue = null
        semanticModelValue = semanticModel
        bindingsValue = bindings
        compilationUnitValue = null
        suppressErrorTupleResultUseValue = false
        reportedUnverifiedResultsValue = new Dictionary<(Line: int, Column: int, Name: string), bool>()
        reportedMemberFunctionAmbiguitiesValue = new Dictionary<(Line: int, Column: int, Name: string), bool>()
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
        reportedMemberFunctionAmbiguitiesValue.Clear()
    }

    // Member resolution and the well-known-type bag are both REBUILT when the metadata load context
    // opens and again when it closes. This rule is told about the new pair rather than being rebuilt
    // itself: it holds the unverified-result dedupe set, and rebuilding would drop it mid-analysis.
    func SetMetadataCollaborators(memberResolution: AnalyzerMemberResolution, wellKnownTypes: AnalyzerWellKnownTypes?) {
        memberResolutionValue = memberResolution
        wellKnownTypesValue = wellKnownTypes
    }

    // The import-usage ledger, told about rather than constructed, and optional: a harness that only
    // asks what a name resolves to is not answering NL010.
    func SetImportUsageCredit(credit: AnalyzerImportUsageCredit?) {
        importUsageCreditValue = credit
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
        source := BareNameSource.Other
        return Resolve(name, line, column, reportMissingAsFunction, out source)
    }

    func Resolve(name: string, line: int, column: int, reportMissingAsFunction: bool, out source: BareNameSource): TypeInfo {
        namesType := false
        return ResolveNamingType(name, line, column, reportMissingAsFunction, 0, out source, out namesType)
    }

    // A write target is a storage location, not a value or call target. A free function cannot be a
    // candidate there, so let the existing member/type lookup answer without the NL209 name tie.
    func ResolveWriteTarget(name: string, line: int, column: int): TypeInfo {
        source := BareNameSource.Other
        namesType := false
        return ResolveNamingType(name, line, column, false, 0, out source, out namesType, false)
    }

    func ResolveNamingType(name: string, line: int, column: int, reportMissingAsFunction: bool, typeArgumentCount: int, out namesType: bool): TypeInfo {
        source := BareNameSource.Other
        return ResolveNamingType(name, line, column, reportMissingAsFunction, typeArgumentCount, out source, out namesType)
    }

    func ResolveNamingType(name: string, line: int, column: int, reportMissingAsFunction: bool, typeArgumentCount: int, out source: BareNameSource, out namesType: bool): TypeInfo {
        return ResolveNamingType(name, line, column, reportMissingAsFunction, typeArgumentCount, out source, out namesType, true)
    }

    private func ResolveNamingType(name: string, line: int, column: int, reportMissingAsFunction: bool, typeArgumentCount: int, out source: BareNameSource, out namesType: bool, checkMemberFunctionAmbiguity: bool): TypeInfo {
        source = BareNameSource.Other
        namesType = false
        if name == "<error>" {
            return BuiltInTypes.Unknown
        }

        resolved: TypeInfo = BuiltInTypes.Unknown
        if TryResolveBindingTarget(name, line, column, out resolved, out source, out namesType, reportMissingAsFunction, checkMemberFunctionAmbiguity) {
            ReportUnverifiedErrorTupleResultUseIfNeeded(name, line, column)
            ReportCapturedByRefParameterIfNeeded(name, line, column)
            return resolved
        }

        if typeArgumentCount > 0 {
            genericType := ResolveExternalGenericType(name, typeArgumentCount)
            if genericType != null {
                namesType = true
                return genericType
            }
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

    // NL331: A LOCAL FUNCTION MAY NOT READ AN ENCLOSING FUNCTION'S `ref`, `out`, `in` OR `&T` PARAMETER.
    //
    // A capturing local function's storage outlives the call that created it — the captured bindings
    // live in a closure object on the heap — and a byref parameter is a managed pointer into the
    // CALLER's frame. There is nowhere to put it, which is why C# refuses the same program as CS1628
    // rather than choosing between a stale copy and a dangling pointer.
    //
    // It is reported at the READ, where the fix goes: copy the parameter into an ordinary local and
    // capture that instead, then write the result back after the call.
    private func ReportCapturedByRefParameterIfNeeded(name: string, line: int, column: int) {
        if line <= 0 || !ambientValue.IsCapturedByRefParameter(name) {
            return
        }

        diagnosticsValue.Report(
            ErrorCode.ByRefParameterCapturedByLocalFunction,
            "'" + name + "' is a by-reference parameter ('ref', 'out', 'in' or '&T') of the enclosing function, so a local function cannot use it",
            line,
            column,
            "Copy '" + name + "' into an ordinary local before the local function, use that local inside it, and assign the result back to '" + name + "' afterwards.",
            Math.Max(1, name.Length)
        )
    }

    // THE CALLEE-POSITION FORM of the same rule, and the reason it lives here rather than in the call
    // arm: it is the identifier answer plus the three things every identifier answer needs and the
    // dispatch host does for its own arm — the null state, the flow type that state implies, and the
    // two semantic-model records the IDE's hover reads. The call arm reaches its callee WITHOUT going
    // through the dispatch host, so without this door it would have to repeat all four.
    //
    // A VALUE THAT CANNOT BE CALLED ENDS HERE, as NL413. The IDE's records still carry the value's own
    // type — hovering `Label` in `Label()` should say `string` — but the call arm is handed `unknown`,
    // so nothing downstream reports a second consequence of the same mistake.
    func CallTarget(identifier: IdentifierExpression): TypeInfo {
        namesType := false
        return CallTarget(identifier, 0, out namesType)
    }

    func CallTarget(identifier: IdentifierExpression, typeArgumentCount: int, out namesType: bool): TypeInfo {
        source := BareNameSource.Other
        resolved := ResolveNamingType(identifier.Name, identifier.Line, identifier.Column, true, typeArgumentCount, out source, out namesType)
        nullState := nullFlowValue.GetExpressionNullState(identifier, resolved)
        flowType := nullFlowValue.ApplyNullabilityFlowType(identifier, resolved, nullState)

        semanticModelValue.RecordExpressionType(identifier.Line, identifier.Column, flowType)
        semanticModelValue.RecordExpressionNullState(identifier.Line, identifier.Column, nullState)

        if ReportNotCallableIfNeeded(identifier, resolved, source) {
            return BuiltInTypes.Unknown
        }

        return flowType
    }

    // NL413 FOR A BARE CALLEE: the name answered with a VALUE — a local, a parameter, or a field or
    // property of the enclosing type — and a value can be called only when its type is a delegate.
    // The invocability predicate is the one that decides `this.Label()` in the member-access arm, so
    // the bare spelling and the `this.` spelling of one mistake get one answer. A value whose type
    // did not resolve is left alone: NL201 already reported the type, and the value's callability is
    // exactly what the analyzer cannot know.
    //
    // NL209 ALREADY OWNS A MEMBER/FUNCTION COLLISION. The identifier walk returns `unknown` after
    // reporting that name-level ambiguity, so a field's non-callable type must not add a second
    // NL413 for `Label()` beside both a `string` field `Label` and a `func Label()`.
    func ReportNotCallableIfNeeded(identifier: IdentifierExpression, resolved: TypeInfo, source: BareNameSource): bool {
        ambiguityKey := (Line: identifier.Line, Column: identifier.Column, Name: identifier.Name)
        if reportedMemberFunctionAmbiguitiesValue.ContainsKey(ambiguityKey) {
            return true
        }

        if source == BareNameSource.Other || identifier.Line <= 0 || !AnalyzerCallableReferenceFacts.IsKnownNonInvocableType(resolved) {
            return false
        }

        name := identifier.Name
        kind: string? = null
        owner: string? = null
        currentType := scopesValue.CurrentTypeScope()
        if source == BareNameSource.Member && currentType != null {
            kind = memberResolutionValue.DescribeValueMemberKind(currentType, name)
            if kind == null {
                return false
            }

            owner = NullabilityMetadataReflection.FormatTypeInfo(currentType)
        }

        diagnosticsValue.ReportValueNotCallable(name, kind, NullabilityMetadataReflection.FormatTypeInfo(resolved), owner, false, identifier.Line, identifier.Column)
        return true
    }

    // A BARE NAME HAS NO WRITTEN RECEIVER, so the receiver is the enclosing instance and the
    // `protected` receiver rule is satisfied by construction: what an external base declares
    // `protected` is in scope here exactly as a source base's is.
    private func ResolveEnclosingMember(currentType: TypeInfo, name: string): TypeInfo {
        return memberResolutionValue.ResolveMember(currentType, name, true, ambientValue.CurrentTypeName, false, true)
    }

    // Whether an enclosing member is the provisional binding after `ReportMemberFunctionAmbiguityIfNeeded`
    // has reported any same-name free-function group. Own members sit in the type scope; inherited
    // members are discovered through the member resolver. Planning uses the same provisional choice
    // (`ColumnarProvisionalMemberBinding`) if requested while analysis errors are present.
    private func EnclosingTypeHasMember(name: string): bool {
        currentType := scopesValue.CurrentTypeScope()
        return currentType != null && !BuiltInTypes.IsUnknown(ResolveEnclosingMember(currentType, name))
    }

    // The function half of project auto-discovery, mirroring the type half in
    // `AnalyzerProjectTypeDiscovery`: exported (PascalCase) top-level functions are visible
    // project-wide within visible namespaces without a file import, and a camelCase one is visible to
    // every file of ITS OWN namespace — namespace-private, never file-private. A camelCase function
    // named from another namespace falls through to the inaccessible probe, which reports NL308.
    //
    // PUBLISHED rather than private because the qualified-external-type probe asks the same question
    // of a dotted name's ROOT before it will accept a CLR type of that name — a project function
    // named `Log` must not be shadowed by `Log.Write` resolving to an assembly type.
    //
    // A REFERENCED ASSEMBLY'S FREE FUNCTION answers here too, when the walk settles on one: it is its
    // holder's public static method, so it is typed as that reflected method and the call arm binds
    // it the way it binds any reflected method -- applicability, conversions and the nullability a
    // referenced signature states. It has no source declaration to record.
    func TryResolveVisibleProjectFunction(name: string, out resolvedType: TypeInfo, out declaration: SymbolDeclaration?): bool {
        candidates := new List<ProjectFunctionCandidate>()
        externalFunctions := new List<MethodInfo>()
        if projectDiscoveryValue.TryResolveVisibleSourceFunctionGroup(name, UnitNamespace(), out candidates, out externalFunctions) {
            if candidates.Count > 0 {
                functions := new List<FunctionTypeInfo>()
                firstSymbol: SymbolDeclaration? = null
                for candidate in candidates {
                    candidateDeclaration := candidate.Declaration
                    if candidateDeclaration == null {
                        continue
                    }

                    functions.Add(functionTypeFactoryValue.CreateFromDeclarationInFile(candidateDeclaration, candidate.FilePath))
                    if firstSymbol == null {
                        firstSymbol = projectDiscoveryValue.SymbolForFunction(name, candidate.FilePath, candidateDeclaration)
                    }
                }

                if functions.Count == 1 {
                    resolvedType = functions[0]
                } else if functions.Count > 1 {
                    resolvedType = NSharpMethodGroupInfoFactory.FromFunctions(functions)
                } else {
                    resolvedType = BuiltInTypes.Unknown
                }
                declaration = firstSymbol
                return functions.Count > 0
            }

            if externalFunctions.Count == 1 {
                resolvedType = new ReflectionMethodInfo(externalFunctions[0])
                declaration = null
                return true
            }

            if externalFunctions.Count > 1 {
                resolvedType = new ReflectionMethodGroupInfo(externalFunctions.ToArray(), name + "(...)")
                declaration = null
                return true
            }
        }

        resolvedType = BuiltInTypes.Unknown
        declaration = null
        return false
    }

    // THE QUALIFIED FUNCTION HALF OF MEMBER ACCESS. Unlike bare lookup, the caller has already
    // settled the namespace, so this asks one exact namespace and records its source declaration at
    // the member-name position for navigation, overload selection, and rename.
    func TryResolveQualifiedProjectFunction(name: string, namespaceName: string, line: int, column: int, out resolvedType: TypeInfo, out declaration: SymbolDeclaration?): bool {
        candidates := new List<ProjectFunctionCandidate>()
        externalFunctions := new List<MethodInfo>()
        if !projectDiscoveryValue.TryResolveQualifiedFunctionGroup(name, namespaceName, UnitNamespace(), out candidates, out externalFunctions) {
            resolvedType = BuiltInTypes.Unknown
            declaration = null
            return false
        }

        if candidates.Count > 0 {
            functions := new List<FunctionTypeInfo>()
            for candidate in candidates {
                if candidate.Declaration != null {
                    functions.Add(functionTypeFactoryValue.CreateFromDeclarationInFile(candidate.Declaration, candidate.FilePath))
                }
            }

            if functions.Count == 0 {
                resolvedType = BuiltInTypes.Unknown
                declaration = null
                return false
            }

            if functions.Count == 1 {
                resolvedType = functions[0]
            } else {
                resolvedType = NSharpMethodGroupInfoFactory.FromFunctions(functions)
            }
            first := candidates[0]
            declaration = first.Declaration == null ? null : projectDiscoveryValue.SymbolForFunction(name, first.FilePath, first.Declaration)
            if declaration != null {
                bindingsValue.RecordBinding(diagnosticsValue.CurrentFilePath, line, column, name.Length, declaration)
            }
            semanticModelValue.RecordExpressionType(line, column, resolvedType)
            return true
        }

        if externalFunctions.Count == 1 {
            resolvedType = new ReflectionMethodInfo(externalFunctions[0])
            declaration = null
            semanticModelValue.RecordExpressionType(line, column, resolvedType)
            return true
        }

        if externalFunctions.Count > 1 {
            resolvedType = new ReflectionMethodGroupInfo(externalFunctions.ToArray(), name + "(...)")
            declaration = null
            semanticModelValue.RecordExpressionType(line, column, resolvedType)
            return true
        }

        resolvedType = BuiltInTypes.Unknown
        declaration = null
        return false
    }

    // THE SIX CHANNELS. A miss answers `false` with `unknown`, which is what separates "this name is
    // nothing" from "this name is something whose type we could not work out" — only the first
    // reports.
    func TryResolveBindingTarget(name: string, line: int, column: int, out resolvedType: TypeInfo): bool {
        source := BareNameSource.Other
        namesType := false
        return TryResolveBindingTarget(name, line, column, out resolvedType, out source, out namesType, false)
    }

    // `source` SAYS WHETHER THE ANSWER IS A VALUE, which only the callee door asks: a scope SYMBOL is a
    // local or a parameter, or — when it sits in the type scope itself — one of the type's own
    // members, and channel 2 answers only with members. Every other channel answers with a type or a
    // function, and a call through one of those is judged by the call arm.
    func TryResolveBindingTarget(name: string, line: int, column: int, out resolvedType: TypeInfo, out source: BareNameSource): bool {
        namesType := false
        return TryResolveBindingTarget(name, line, column, out resolvedType, out source, out namesType, false)
    }

    func TryResolveBindingTarget(name: string, line: int, column: int, out resolvedType: TypeInfo, out source: BareNameSource, out namesType: bool): bool {
        return TryResolveBindingTarget(name, line, column, out resolvedType, out source, out namesType, false)
    }

    func TryResolveBindingTarget(name: string, line: int, column: int, out resolvedType: TypeInfo, out source: BareNameSource, out namesType: bool, preferProjectFunctions: bool): bool {
        return TryResolveBindingTarget(name, line, column, out resolvedType, out source, out namesType, preferProjectFunctions, true)
    }

    private func TryResolveBindingTarget(name: string, line: int, column: int, out resolvedType: TypeInfo, out source: BareNameSource, out namesType: bool, preferProjectFunctions: bool, checkMemberFunctionAmbiguity: bool): bool {
        source = BareNameSource.Other
        namesType = false
        // 1. Local symbols first, then local types. A symbol declared OUTSIDE the enclosing type — the
        // file's own free functions live in the global scope — answers only when the type has no
        // member of that name; otherwise channel 2 below answers with the member.
        symbolFloor := 0
        typeScopeIndex := scopesValue.TypeScopeIndex()
        if typeScopeIndex > 0 && scopesValue.DeclaresSymbolBelow(name, typeScopeIndex) && EnclosingTypeHasMember(name) {
            symbolFloor = typeScopeIndex
        }

        symbolScopeIndex := -1
        scopeBinding := scopesValue.ResolveBindingTarget(bindingsValue, diagnosticsValue.CurrentFilePath, name, line, column, symbolFloor, out symbolScopeIndex, out namesType)
        if scopeBinding != null {
            if symbolScopeIndex >= 0 && symbolScopeIndex == typeScopeIndex && preferProjectFunctions && !AnalyzerCallableReferenceFacts.IsInvocableMemberType(scopeBinding) {
                freeFunction: TypeInfo = BuiltInTypes.Unknown
                if TryResolveFreeFunctionForCall(name, line, column, out freeFunction) {
                    resolvedType = freeFunction
                    return true
                }
            }

            resolvedType = AugmentSameNamespaceFreeFunctionOverloads(name, scopeBinding)
            if symbolScopeIndex >= 0 && symbolScopeIndex == typeScopeIndex {
                source = BareNameSource.Member
                if checkMemberFunctionAmbiguity && ReportMemberFunctionAmbiguityIfNeeded(name, line, column, scopesValue.CurrentTypeScope(), resolvedType, preferProjectFunctions) {
                    resolvedType = BuiltInTypes.Unknown
                }
            } else if symbolScopeIndex >= 0 {
                source = BareNameSource.Value
            }

            return true
        }

        // 2. The enclosing type's members, static ones included.
        //
        // The type's OWN members were answered by channel 1 — they live in its type scope — so what
        // reaches this channel is chiefly an INHERITED one, and it RECORDS its binding exactly as
        // `this.Label()` does: from the same source declaration, so definition, references, hover
        // and rename read one answer whichever way the member was written. A member only a reflected
        // base declares has no source position and records nothing.
        currentType := scopesValue.CurrentTypeScope()
        if currentType != null {
            memberType := ResolveEnclosingMember(currentType, name)
            if !BuiltInTypes.IsUnknown(memberType) {
                if preferProjectFunctions && !AnalyzerCallableReferenceFacts.IsInvocableMemberType(memberType) {
                    freeFunction: TypeInfo = BuiltInTypes.Unknown
                    if TryResolveFreeFunctionForCall(name, line, column, out freeFunction) {
                        resolvedType = freeFunction
                        return true
                    }
                }

                memberDeclaration: SymbolDeclaration? = null
                if sourceMemberDeclarationsValue.TryFind(currentType, name, out memberDeclaration) {
                    // TOTAL on this path: the finder materialises the declaration before answering `true`.
                    if memberDeclaration != null {
                        bindingsValue.RecordBinding(diagnosticsValue.CurrentFilePath, line, column, name.Length, memberDeclaration)
                    }
                }

                resolvedType = memberType
                source = BareNameSource.Member
                if checkMemberFunctionAmbiguity && ReportMemberFunctionAmbiguityIfNeeded(name, line, column, currentType, resolvedType, preferProjectFunctions) {
                    resolvedType = BuiltInTypes.Unknown
                }
                return true
            }
        }

        // 3. Built-in type keywords (`int`, `string`, `bool`, …) for static member access.
        builtInClrType := AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(wellKnownTypesValue, name)
        if builtInClrType != null {
            resolvedType = new ReflectionTypeInfo(builtInClrType)
            namesType = true
            return true
        }

        // 3a. THE AMBIGUITY GATE, between the channels that cannot tie and the two that can. Every
        // channel above answers from ONE place — a scope, the enclosing type, the built-in table — so
        // a name that reached here is about to be resolved from an import, and an import is exactly
        // where two declarations can supply one spelling. Reporting before either channel answers is
        // what keeps the error at the reference rather than at whichever candidate happened to win.
        if line > 0 {
            ReportAmbiguousImportedTypeIfNeeded(name, line, column)
        }

        // A call position resolves an available free function before a project-wide type of the same
        // name. Keep this probe after the ambiguity gate so two imported functions still report NL209
        // instead of silently choosing one; a unique function still wins over an unrelated
        // project-discovered type, and a type-only callee reaches NL415.
        if preferProjectFunctions && TryResolveProjectFunctionBinding(name, line, column, out resolvedType) {
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
            namesType = true
            return true
        }

        // A project type that EXISTS but is not exported is reported here and marked, so the type
        // resolver's own NL201 does not report the same position a second time.
        if inaccessibleProjectFile != null {
            diagnosticsValue.ReportInaccessibleMember(name, inaccessibleProjectFile, line, column)
            typeResolverValue.MarkUnresolvedTypeReported(name, line, column)
        }

        // 5. Project-wide function discovery. A call position already probed before channel 4, so
        // this is reached only by an ordinary name read or a callee with no project-wide type answer.
        if !preferProjectFunctions && TryResolveProjectFunctionBinding(name, line, column, out resolvedType) {
            return true
        }

        // 6. An external type (static class access like `Console`). Deliberately after the
        // enclosing-type member lookup so instance members win over imported type names.
        //
        // NL010 AND NL002 ARE BOTH ANSWERED FROM THIS CHANNEL. `Console.WriteLine(...)` writes no
        // type ANNOTATION anywhere, so the type-position walk never sees `Console`; the import that
        // supplies it is used here or nowhere, and a file whose only mention of `System` was a static
        // receiver had its import reported dead until this credit existed.
        externalType := externalTypeProbeValue.ResolveExternalType(name)
        if externalType != null {
            resolvedType = externalType
            credit := importUsageCreditValue
            if credit != null {
                credit.CreditResolvedType(name, externalType)
            }

            namesType = true
            return true
        }

        resolvedType = BuiltInTypes.Unknown
        return false
    }

    // Resolve and record the project-wide function answer once, whether it precedes or follows
    // project-type discovery for the current expression position.
    private func TryResolveProjectFunctionBinding(name: string, line: int, column: int, out resolvedType: TypeInfo): bool {
        declaration: SymbolDeclaration? = null
        if TryResolveVisibleProjectFunction(name, out resolvedType, out declaration) {
            if declaration != null {
                bindingsValue.RecordBinding(diagnosticsValue.CurrentFilePath, line, column, name.Length, declaration)
            }

            return true
        }

        resolvedType = BuiltInTypes.Unknown
        return false
    }

    // A call can choose the free-function group when the enclosing member is not invocable. This is
    // still a name lookup, and it uses the same project visibility probe as the ordinary free-call
    // channel plus the current-file global symbol fallback used by analyzer harnesses.
    private func TryResolveFreeFunctionForCall(name: string, line: int, column: int, out resolvedType: TypeInfo): bool {
        if TryResolveProjectFunctionBinding(name, line, column, out resolvedType) {
            return true
        }

        globalSymbol: TypeInfo = BuiltInTypes.Unknown
        if scopesValue.GlobalScope().Symbols.TryGetValue(name, out globalSymbol) && (globalSymbol is FunctionTypeInfo || globalSymbol is NSharpMethodGroupInfo || globalSymbol is ReflectionMethodInfo || globalSymbol is ReflectionMethodGroupInfo) {
            resolvedType = globalSymbol
            return true
        }

        resolvedType = BuiltInTypes.Unknown
        return false
    }

    // A referenced generic type by its written name and arity, found the way the type resolver finds
    // the head of `List<int>` in a type position: compiler-known open generics first, then the
    // arity-qualified metadata name. Credit the import that supplies it, just as channel 6 does for
    // a bare `Console`.
    private func ResolveExternalGenericType(name: string, arity: int): TypeInfo? {
        resolved: TypeInfo? = null
        knownType := AnalyzerWellKnownTypeFacts.KnownOpenGenericType(wellKnownTypesValue, name, arity)
        if knownType != null {
            resolved = new ReflectionTypeInfo(knownType)
        } else {
            resolved = externalTypeProbeValue.ResolveExternalType(name + "`" + arity.ToString())
        }

        credit := importUsageCreditValue
        if resolved != null && credit != null {
            credit.CreditResolvedType(name, resolved)
        }

        return resolved
    }

    // A top-level declaration in this file already won the local scope lookup. Complete its group
    // with same-namespace declarations from the other project files before BindNSharpCall sees the
    // candidates. This is the analyzer's existing group representation and binder, not an emitter
    // overload ranking rule.
    private func AugmentSameNamespaceFreeFunctionOverloads(name: string, resolved: TypeInfo): TypeInfo {
        if !projectDiscoveryValue.CompilesAsOneProgram() {
            return resolved
        }

        currentPath := diagnosticsValue.CurrentFilePath
        if currentPath == null {
            return resolved
        }

        currentFullPath := System.IO.Path.GetFullPath(currentPath)
        functions := new List<FunctionTypeInfo>()
        hasCurrentFileFunction := false
        single := resolved as FunctionTypeInfo
        if single != null && single.SourceContainingType == null && single.SourceName == name && single.SourceFilePath != null && string.Equals(System.IO.Path.GetFullPath(single.SourceFilePath), currentFullPath, StringComparison.OrdinalIgnoreCase) {
            functions.Add(single)
            hasCurrentFileFunction = true
        }

        group := resolved as NSharpMethodGroupInfo
        if group != null {
            for function in NSharpMethodGroupInfoFactory.GetFunctions(group) {
                if function.SourceContainingType == null && function.SourceName == name && function.SourceFilePath != null && string.Equals(System.IO.Path.GetFullPath(function.SourceFilePath), currentFullPath, StringComparison.OrdinalIgnoreCase) {
                    functions.Add(function)
                    hasCurrentFileFunction = true
                }
            }
        }

        if !hasCurrentFileFunction {
            return resolved
        }

        candidates := projectDiscoveryValue.SameNamespaceFunctionCandidates(currentPath, UnitNamespace())
        for candidate in candidates {
            declaration := candidate.Declaration
            if declaration != null && declaration.Name == name {
                functions.Add(functionTypeFactoryValue.CreateFromDeclarationInFile(declaration, candidate.FilePath))
            }
        }

        if functions.Count == 1 {
            return functions[0]
        }

        return NSharpMethodGroupInfoFactory.FromFunctions(functions)
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

    // NL209's report site for a bare name in EXPRESSION position. It shares the type resolver's
    // unresolved-reference dedupe set, which is what stops the same position being told twice — once
    // here and once by the type resolver's own gate — and also stops an ambiguous name being
    // reported a second time as unresolved.
    func ReportAmbiguousImportedTypeIfNeeded(name: string, line: int, column: int) {
        firstCandidate := ""
        secondCandidate := ""
        if projectDiscoveryValue.TryFindAmbiguousImportedType(name, UnitNamespace(), out firstCandidate, out secondCandidate) {
            if typeResolverValue.MarkUnresolvedTypeReported(name, line, column) {
                diagnosticsValue.ReportAmbiguousTypeReference(name, firstCandidate, secondCandidate, line, column)
            }
            return
        }

        // THE FUNCTION CHANNEL TIES THE SAME WAY. A free function is not auto-discovered across
        // namespaces, so an import is the ONLY way one reaches this file from a sibling namespace —
        // which makes two imports supplying one spelling exactly the NL209 tie, and makes reporting
        // it the difference between a named ambiguity and a call that silently reaches whichever
        // import was written first.
        firstFunctionCandidate := ""
        secondFunctionCandidate := ""
        if !projectDiscoveryValue.TryFindAmbiguousImportedFunction(name, UnitNamespace(), out firstFunctionCandidate, out secondFunctionCandidate) {
            return
        }

        if typeResolverValue.MarkUnresolvedTypeReported(name, line, column) {
            diagnosticsValue.ReportAmbiguousFunctionReference(name, firstFunctionCandidate, secondFunctionCandidate, line, column)
        }
    }

    func UnitNamespace(): string? {
        return AnalyzerProjectSourceProvider.UnitNamespace(compilationUnitValue)
    }

    // The strict-language tie is decided by SIMPLE NAME when both sides can serve the written
    // position. Reads admit fields, properties and methods; calls admit methods and delegate values.
    // Locals and local functions never reach this arm; they remain source Value and keep shadowing.
    private func ReportMemberFunctionAmbiguityIfNeeded(name: string, line: int, column: int, currentType: TypeInfo?, memberType: TypeInfo, callPosition: bool): bool {
        if currentType == null || line <= 0 {
            return false
        }

        key := (Line: line, Column: column, Name: name)
        if reportedMemberFunctionAmbiguitiesValue.ContainsKey(key) {
            return true
        }

        if callPosition && !AnalyzerCallableReferenceFacts.IsInvocableMemberType(memberType) {
            return false
        }

        functionGroup: TypeInfo = BuiltInTypes.Unknown
        functionDeclaration: SymbolDeclaration? = null
        foundFunction := TryResolveVisibleProjectFunction(name, out functionGroup, out functionDeclaration)
        if !foundFunction {
            // Unit harnesses and declaration-time probes can have a current-file top-level function
            // in the global scope before project discovery has a source snapshot to consult.
            globalSymbol: TypeInfo = BuiltInTypes.Unknown
            if scopesValue.GlobalScope().Symbols.TryGetValue(name, out globalSymbol) && (globalSymbol is FunctionTypeInfo || globalSymbol is NSharpMethodGroupInfo || globalSymbol is ReflectionMethodInfo || globalSymbol is ReflectionMethodGroupInfo) {
                functionGroup = globalSymbol
                foundFunction = true
            }
        }
        if !foundFunction {
            return false
        }

        functionSpelling := name
        functionNamespace: string? = null
        if !TryGetFreeFunctionQualification(functionGroup, name, out functionNamespace, out functionSpelling) {
            return false
        }

        if functionNamespace == null {
            functionNamespace = UnitNamespace()
            if functionNamespace != null && functionNamespace.Length > 0 {
                functionSpelling = functionNamespace + "." + name
            }
        }

        memberOwner := memberResolutionValue.MemberDeclarationOwnerName(currentType, name)
        if string.IsNullOrWhiteSpace(memberOwner) {
            memberOwner = currentType.ToString() ?? ""
        }
        memberCandidate := memberOwner + "." + name
        memberDescription := "member '" + memberCandidate + "' (declared by '" + memberOwner + "')"
        namespaceDescription := functionNamespace == null || functionNamespace.Length == 0 ? "the global namespace" : "namespace '" + functionNamespace + "'"
        functionCandidate := functionNamespace == null || functionNamespace.Length == 0 ? name : functionNamespace + "." + name
        functionDescription := "free function '" + functionCandidate + "' (declared in " + namespaceDescription + ")"
        memberSpelling := memberResolutionValue.MemberIsStatic(currentType, name) ? memberOwner + "." + name : "this." + name
        suggestion := callPosition ? "Call the member with `" + memberSpelling + "(...)` or call the free function with `" + functionSpelling + "(...)`." : "Use the member `" + memberSpelling + "` or the free-function group `" + functionSpelling + "`."
        reportedMemberFunctionAmbiguitiesValue[key] = true
        diagnosticsValue.ReportAmbiguousBareName(name, memberDescription, functionDescription, suggestion, line, column)
        return true
    }

    private func TryGetFreeFunctionQualification(functionGroup: TypeInfo, name: string, out namespaceName: string?, out qualifiedName: string): bool {
        namespaceName = null
        qualifiedName = ""
        function := functionGroup as FunctionTypeInfo
        if function != null && function.SourceFilePath != null {
            namespaceName = projectDiscoveryValue.NamespaceForFile(function.SourceFilePath)
        } else {
            sourceGroup := functionGroup as NSharpMethodGroupInfo
            if sourceGroup != null && sourceGroup.Functions.Count > 0 && sourceGroup.Functions[0].SourceFilePath != null {
                namespaceName = projectDiscoveryValue.NamespaceForFile(sourceGroup.Functions[0].SourceFilePath)
            } else {
                reflected := functionGroup as ReflectionMethodInfo
                reflectedGroup := functionGroup as ReflectionMethodGroupInfo
                method: MethodInfo? = null
                if reflected != null {
                    method = reflected.Method
                } else if reflectedGroup != null && reflectedGroup.Methods.Length > 0 {
                    method = reflectedGroup.Methods[0]
                }
                if method != null && method.DeclaringType != null {
                    namespaceName = method.DeclaringType.Namespace
                    declaringTypeName := method.DeclaringType.FullName
                    if declaringTypeName != null && declaringTypeName.Length > 0 {
                        // Referenced free functions are methods on the emitted namespace holder.
                        // Unlike source functions, an external one is qualified through that real
                        // CLR type (`Reporting.Program.Helper`) so the suggested spelling binds.
                        qualifiedName = declaringTypeName.Replace('+', '.') + "." + name
                    }
                }
            }
        }

        if qualifiedName.Length > 0 {
            return true
        }

        if namespaceName == null || namespaceName.Length == 0 {
            // The global holder is a source-level type in N# and provides the unambiguous qualified
            // spelling for global free functions.
            qualifiedName = "Program." + name
        } else {
            qualifiedName = namespaceName + "." + name
        }
        return true
    }
}

// WHERE A BARE NAME'S ANSWER CAME FROM, as far as a CALL cares. A `Value` or a `Member` is something
// read, and reading one before a parenthesis is a call only when its type is a delegate; `Other` is
// a type or a function, whose call the call arm judges for itself.
enum BareNameSource {
    Other,
    Value,
    Member
}
