namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// THE ONE STEP A MEMBER ACCESS TAKES AND THE THREE FORMS THAT TAKE NONE.
//
// A member access has exactly ONE operand — its receiver — so its WALK has exactly one kind. There
// is no second walk kind for `a?.b`: the null-conditional flag is read FOUR times and every one of
// them is AFTER the receiver has answered, so the two forms differ in what they conclude and not in
// what they walk.
//
//   1  analyse the RECEIVER expression. It is the full dispatch and not the identifier rule, which
//      matters: an identifier receiver is answered by `AnalyzerIdentifierResolution` and then judged
//      by the dispatch host's common tail — the null state, the flow type, the two semantic-model
//      records, the assignment-target capture and the three value-misuse reports. A member access
//      whose receiver is a method group is refused THERE, not here.
//
// THERE IS NO SECOND KIND ANY MORE. The undefined-member report's RENDERING was one, on the measured
// belief that its did-you-mean list could not be built in N# because it reads `PropertyInfo.Name` and
// `FieldInfo.Name` and neither is in the columnar catalog. The belief was half right and the
// conclusion was wrong: the catalog is the LEGACY whole-subtree planner's surface, consulted only
// when that mode is on, and the ordinary runtime resolver binds any suitable public instance method
// on a receiver type that is already supported — which both of these have been for many slices. What
// slice 55 actually measured declining was `property.Name`, the PROPERTY spelling, which is its own
// standing gotcha and not a catalog gap. The rendering therefore lives here, with the rule that
// decides whether it is owed.
//
// THREE FORMS ANSWER BEFORE THE WALK STEP AND SO NEVER ASK FOR IT: an import ALIAS access
// (`Alias.Symbol`), which is a table lookup and not an expression at all; a QUALIFIED TYPE RECEIVER
// (`System.Text.StringBuilder.Append`), whose receiver is a namespace prefix that would be
// meaningless to analyse; and a QUALIFIED TYPE NAME standing on its own (`System.Console`), which is
// a type-valued expression exactly as the bare `Console` is. All three are decided before the first
// `NextStep` returns, which is why they cost no walk.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class MemberAccessRequest {
    Kind: int
    Node: Expression?

    constructor(kind: int, node: Expression?) {
        Kind = kind
        Node = node
    }
}

// THE WHOLE STATE, SUSPENDED ACROSS AT MOST TWO STEPS.
//
// `Member` is the node. `ResultType` is what the dispatch gets back, and it is NOT decided at
// `Begin`: a member access means nothing until its receiver is known, so every path but the two
// zero-step ones settles it in a phase that runs after a `Supply`.
//
// `Phase` runs 0 (nothing asked yet) → 1 (the receiver step is outstanding) → 99 (finished). A node
// that is not a member access at all lands in 99 at `Begin` with `unknown`, because the dispatch
// never hands one over and a walk that guessed would hide the bug.
//
// THE THREE PENDING SLOTS ARE GONE with the report step they existed for: they held the report's
// operands and the answer the walk was keeping back so the report stayed last. Now that the report is
// rendered where it is decided, the answer is settled in the same statement and nothing is held.
class MemberAccessState {
    memberValue: MemberAccessExpression?

    Member: MemberAccessExpression? => memberValue

    Phase: int
    ResultType: TypeInfo

    constructor(member: MemberAccessExpression?) {
        memberValue = member
        Phase = 0
        ResultType = BuiltInTypes.Unknown
    }
}

// WHAT A MEMBER ACCESS MEANS — the whole of the expression walk's `member` arm, its receiver
// classification, its binding and visibility records, and what a name that is not a member is told.
//
// THE ORDER OF THE SIX GATES IS BEHAVIOUR, AND IT IS THE WHOLE OF `Finish`:
//   1  the NULLABLE fork. `HasValue` and `Value` on a nullable are answered here rather than by
//      member resolution, because `int?` has no such members in metadata — and `Value` on a nullable
//      that flow narrowing did NOT prove non-null is warned about, while the same access inside
//      `if x != null { … }` is silent. That difference is the whole reason the fork reads the
//      ENCLOSING nullable symbol as well as the receiver's own type.
//   2  the null DEREFERENCE report, which belongs to `AnalyzerNullFlow` and is merely asked here.
//   3  the receiver's ALIAS and `ref` unwraps, twice, because a `ref` to an alias is both.
//   4  the three SoA null-conditional refusals — a table, a row view, a direct column — each of
//      which ENDS the walk with `unknown`, because a receiver that cannot be touched that way has no
//      member to resolve.
//   5  the row-view receiver refusal for a name that is not one of its columns.
//   6  the resolution itself, which is `AnalyzerMemberResolution`'s, followed by the undefined-member
//      report when it missed and the SoA column-read registration when it hit a column.
//
// THE FOUR CODES IT OWNS, IN SIX SHAPES: NL303 in THREE — the rich `ErrorMessageBuilder` form with a
// snippet and did-you-mean names, the bare fallback for a diagnostic with no source line, and a
// DISTINCT import-alias form that names the alias rather than a type; NL308 for a member that exists
// but is not exported across a package boundary; NL907 for a `.Value` unwrap that can throw; and
// NL103 twice, for the two SoA null-conditional shapes. WHAT IT DOES NOT OWN: the null-dereference
// report, both SoA row escapes and the column-read registry — those are `AnalyzerNullFlow`'s and
// `AnalyzerSoaEscape`'s, and this arm only asks them.
//
// THREE OF ITS MEMBERS ARE PUBLISHED because other arms ask the same questions: whether a receiver
// names a TYPE rather than a value (the write-target classifiers and the array arm),
// whether a missing member should be REPORTED and the report itself (the object-initializer and
// attribute paths), the dotted-name reader (the expression-tree probe) and the null-conditional
// result wrap (the index arm). They move here rather than staying behind because this is the arm
// that decides what they mean.
//
// CONSTRUCTED ONCE, NEVER REBUILT. Four of its collaborators — member resolution, the CLR type
// conversion funnel, extension-method resolution and the well-known-type bag — are replaced when the
// analyzer opens or closes its metadata load context, so it is TOLD about the replacements rather
// than being rebuilt with them: it also carries per-analysis state (the compilation unit and the
// binding map), and a rebuild between `BeginAnalysis` and the walk would drop both. That is the same
// reason `AnalyzerTypeResolver` and `AnalyzerIdentifierResolution` take theirs through setters.
class AnalyzerMemberAccess {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    nullFlowValue: AnalyzerNullFlow
    soaEscapeValue: AnalyzerSoaEscape
    ambientValue: AnalyzerAmbientContext
    projectSourcesValue: AnalyzerProjectSourceProvider
    projectDiscoveryValue: AnalyzerProjectTypeDiscovery
    externalTypeProbeValue: AnalyzerExternalTypeProbe
    typeSubstitutionValue: AnalyzerTypeSubstitution
    identifierResolutionValue: AnalyzerIdentifierResolution
    extensionMethodsValue: List<FunctionDeclaration>
    usingNamespacesValue: List<string>
    usingAliasesValue: Dictionary<string, string>
    importedSymbolsByAliasValue: Dictionary<string, Dictionary<string, TypeInfo>>
    importedDeclarationsByAliasValue: Dictionary<string, Dictionary<string, SymbolDeclaration>>
    mlcAssembliesValue: List<Assembly>

    memberResolutionValue: AnalyzerMemberResolution
    clrTypeConversionValue: AnalyzerClrTypeConversion
    extensionMethodResolutionValue: AnalyzerExtensionMethodResolution
    wellKnownTypesValue: AnalyzerWellKnownTypes?
    importUsageCreditValue: AnalyzerImportUsageCredit?

    compilationUnitValue: CompilationUnit?
    bindingsValue: BindingMap

    // THE BUILT-IN MEMBER NAME TABLES. They exist because the analyzer must answer "does `string`
    // have a `Lenght`?" even when no metadata load context is open — with no reflection to ask, a
    // built-in receiver would otherwise report EVERY member as missing. They are deliberately small:
    // they only have to cover the names a developer types often enough that a false "not found"
    // would be worse than a missed one.
    builtInObjectMembersValue: HashSet<string>
    builtInStringInstanceMembersValue: HashSet<string>
    builtInStringStaticMembersValue: HashSet<string>
    builtInNumericStaticMembersValue: HashSet<string>
    builtInNumericInstanceMembersValue: HashSet<string>
    builtInBooleanStaticMembersValue: HashSet<string>
    builtInBooleanInstanceMembersValue: HashSet<string>
    builtInArrayMembersValue: HashSet<string>

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, nullFlow: AnalyzerNullFlow, soaEscape: AnalyzerSoaEscape, ambient: AnalyzerAmbientContext, projectSources: AnalyzerProjectSourceProvider, projectDiscovery: AnalyzerProjectTypeDiscovery, externalTypeProbe: AnalyzerExternalTypeProbe, typeSubstitution: AnalyzerTypeSubstitution, identifierResolution: AnalyzerIdentifierResolution, extensionMethods: List<FunctionDeclaration>, usingNamespaces: List<string>, usingAliases: Dictionary<string, string>, importedSymbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>, importedDeclarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>, mlcAssemblies: List<Assembly>, memberResolution: AnalyzerMemberResolution, clrTypeConversion: AnalyzerClrTypeConversion, extensionMethodResolution: AnalyzerExtensionMethodResolution, bindings: BindingMap) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        nullFlowValue = nullFlow
        soaEscapeValue = soaEscape
        ambientValue = ambient
        projectSourcesValue = projectSources
        projectDiscoveryValue = projectDiscovery
        externalTypeProbeValue = externalTypeProbe
        typeSubstitutionValue = typeSubstitution
        identifierResolutionValue = identifierResolution
        extensionMethodsValue = extensionMethods
        usingNamespacesValue = usingNamespaces
        usingAliasesValue = usingAliases
        importedSymbolsByAliasValue = importedSymbolsByAlias
        importedDeclarationsByAliasValue = importedDeclarationsByAlias
        mlcAssembliesValue = mlcAssemblies
        memberResolutionValue = memberResolution
        clrTypeConversionValue = clrTypeConversion
        extensionMethodResolutionValue = extensionMethodResolution
        wellKnownTypesValue = null
        importUsageCreditValue = null
        compilationUnitValue = null
        bindingsValue = bindings

        builtInObjectMembersValue = NameSet(["ToString", "Equals", "GetHashCode", "GetType"])
        builtInStringInstanceMembersValue = NameSet(["Length", "Chars", "CompareTo", "Contains", "EndsWith", "Equals", "IndexOf", "LastIndexOf", "Replace", "Split", "StartsWith", "Substring", "ToCharArray", "ToLower", "ToLowerInvariant", "ToUpper", "ToUpperInvariant", "Trim", "TrimEnd", "TrimStart"])
        builtInStringStaticMembersValue = NameSet(["Compare", "Concat", "Copy", "Equals", "Format", "IsNullOrEmpty", "IsNullOrWhiteSpace", "Join"])
        builtInNumericStaticMembersValue = NameSet(["MaxValue", "MinValue", "Parse", "TryParse"])
        builtInNumericInstanceMembersValue = NameSet(["CompareTo", "Equals", "ToString"])
        builtInBooleanStaticMembersValue = NameSet(["FalseString", "Parse", "TrueString", "TryParse"])
        builtInBooleanInstanceMembersValue = NameSet(["CompareTo", "Equals", "GetHashCode", "ToString"])
        builtInArrayMembersValue = NameSet(["Length", "LongLength", "Rank", "GetLength", "GetLowerBound", "GetUpperBound", "GetValue", "SetValue", "Clone", "CopyTo"])
    }

    static func NameSet(names: string[]): HashSet<string> {
        result := new HashSet<string>(StringComparer.Ordinal)
        for name in names {
            result.Add(name)
        }

        return result
    }

    // One call per analysis, from the analyzer's own reset block. The compilation unit names the
    // namespace two of its questions are asked in, and the binding map is REPLACED per analysis
    // rather than cleared, so both arrive here instead of being held from construction.
    func BeginAnalysis(unit: CompilationUnit?, bindings: BindingMap) {
        compilationUnitValue = unit
        bindingsValue = bindings
    }

    // The four collaborators the metadata load context REBUILDS, told rather than reconstructed:
    // this owner carries per-analysis state and a rebuild would drop it.
    func SetMetadataCollaborators(memberResolution: AnalyzerMemberResolution, clrTypeConversion: AnalyzerClrTypeConversion, extensionMethodResolution: AnalyzerExtensionMethodResolution, wellKnownTypes: AnalyzerWellKnownTypes?) {
        memberResolutionValue = memberResolution
        clrTypeConversionValue = clrTypeConversion
        extensionMethodResolutionValue = extensionMethodResolution
        wellKnownTypesValue = wellKnownTypes
    }

    // The import-usage ledger, told about rather than constructed, and optional: a harness that only
    // asks what a name resolves to is not answering NL010.
    func SetImportUsageCredit(credit: AnalyzerImportUsageCredit?) {
        importUsageCreditValue = credit
    }

    // THE ENTRY, AND IT DECIDES NOTHING. Every gate this arm owns needs the receiver's answer, so
    // `Begin` names the node and stops. A node that is not a member access finishes immediately.
    func Begin(expression: Expression): MemberAccessState {
        member := expression as MemberAccessExpression
        state := new MemberAccessState(member)
        if member == null {
            state.Phase = 99
        }

        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    //
    // The two zero-step forms are decided HERE rather than at `Begin`, so that the alias table and
    // the qualified-external-type probe are read at the instant the dispatch reached the node.
    func NextStep(state: MemberAccessState): MemberAccessRequest? {
        member := state.Member
        if member == null {
            state.Phase = 99
            return null
        }

        if state.Phase != 0 {
            return null
        }

        aliasMemberType: TypeInfo = BuiltInTypes.Unknown
        if TryResolveImportAliasMember(member, out aliasMemberType) {
            state.ResultType = aliasMemberType
            state.Phase = 99
            return null
        }

        typeReceiver: TypeInfo = BuiltInTypes.Unknown
        if TryResolveQualifiedTypeName(member.Object, out typeReceiver) {
            state.Phase = 99
            Finish(state, typeReceiver)
            return null
        }

        // THE DOTTED NAME THAT IS ITSELF A TYPE, which is the same answer a bare name that names a
        // type gives: `AnalyzerIdentifierResolution`'s type channels hand the TypeInfo back as the
        // expression's own value, so `System.Console` and `Console` mean one thing. Without this
        // channel the walk would analyse `System` as a value and report NL301 on it — which is
        // exactly what a static call spelled `System.Console.WriteLine(…)` used to do, because the
        // reflected bind analyses the callee's receiver a second time as an expression.
        qualifiedType: TypeInfo = BuiltInTypes.Unknown
        if TryResolveQualifiedTypeName(member, out qualifiedType) {
            state.ResultType = qualifiedType
            state.Phase = 99
            return null
        }

        state.Phase = 1
        return new MemberAccessRequest(1, member.Object)
    }

    // THE ANSWER TO THE OUTSTANDING STEP. The one kind answers the receiver's type; a null answer is
    // `unknown` rather than a missing one — the analyzer's expression walk never answers null, and a
    // walk that saw one would otherwise carry it into a report.
    func Supply(state: MemberAccessState, answer: TypeInfo?) {
        if state.Phase != 1 {
            return
        }

        state.Phase = 99
        if answer != null {
            Finish(state, answer)
        } else {
            Finish(state, BuiltInTypes.Unknown)
        }
    }

    func Result(state: MemberAccessState): TypeInfo {
        return state.ResultType
    }

    // THE IMPORT-ALIAS FORM, which is not an expression walk at all: `Alias.Symbol` is two table
    // lookups over what the file's aliased import brought in. A miss inside a KNOWN alias is its own
    // NL303 shape — it names the alias, and its did-you-mean names come from that alias's symbols
    // rather than from any type's members — and it ends the walk, because there is no receiver type
    // to resolve against. A name that is not an alias at all falls through to the ordinary walk.
    func TryResolveImportAliasMember(member: MemberAccessExpression, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        identifier := member.Object as IdentifierExpression
        if identifier == null {
            return false
        }

        aliasName := identifier.Name
        symbols: Dictionary<string, TypeInfo>? = null
        if !importedSymbolsByAliasValue.TryGetValue(aliasName, out symbols) {
            return false
        }

        symbolType: TypeInfo? = null
        if symbols != null && symbols.TryGetValue(member.MemberName, out symbolType) {
            declarations: Dictionary<string, SymbolDeclaration>? = null
            if importedDeclarationsByAliasValue.TryGetValue(aliasName, out declarations) && declarations != null {
                declaration: SymbolDeclaration? = null
                if declarations.TryGetValue(member.MemberName, out declaration) && declaration != null {
                    RecordMemberBinding(member, declaration)
                }
            }

            if symbolType != null {
                memberType = symbolType
            }

            return true
        }

        memberColumn := spansValue.GetMemberNameColumn(member)
        similarSymbols := new List<string>()
        if symbols != null && symbols.Count != 0 {
            candidates := new List<string>()
            for entry in symbols {
                candidates.Add(entry.Key)
            }

            suggester := new SmartSuggester(candidates)
            similarSymbols = suggester.SuggestSimilarNames(member.MemberName, 3)
        }

        suggestion: string? = null
        if similarSymbols.Count > 0 {
            suggestion = "Did you mean '" + similarSymbols[0] + "'?"
        }

        diagnosticsValue.Report(ErrorCode.UndefinedMember, "'" + member.MemberName + "' doesn't exist in import alias '" + aliasName + "' — check the import for available symbols", member.Line, memberColumn, suggestion, Math.Max(1, member.MemberName.Length))
        memberType = BuiltInTypes.Unknown
        return true
    }

    // EVERYTHING THE ARM DOES ONCE THE RECEIVER IS KNOWN, in the one order that is behaviour. Both
    // zero-step forms and the walked form converge here, which is why the qualified-external-type
    // receiver is judged by exactly the same six gates a walked receiver is.
    func Finish(state: MemberAccessState, objectType: TypeInfo) {
        member := state.Member
        if member == null {
            return
        }

        nullableMemberType: TypeInfo = BuiltInTypes.Unknown
        if TryResolveNullableMemberAccess(member, objectType, out nullableMemberType) {
            state.ResultType = nullableMemberType
            return
        }

        nullableOwnMemberType: TypeInfo = BuiltInTypes.Unknown
        if TryResolveNullableValueTypeOwnMember(member, objectType, out nullableOwnMemberType) {
            state.ResultType = nullableOwnMemberType
            return
        }

        // A CONTINUATION LINK IS PART OF THE CHAIN, NOT A DEREFERENCE OF ITS RESULT. `.Count` in
        // `snapshot?.Units.Count` runs only when the `?` already proved `snapshot`, so NL905 stays
        // silent on it and the result is lifted exactly as the guard's own link is — the chain
        // produces `int?`, and every later link strips the lift again before resolving on it.
        isChainContinuation := AnalyzerNullConditionalChainFacts.IsMemberContinuation(member)
        nullFlowValue.ReportPossibleNullAccess(member.Object, objectType, member.Line, member.Column, "dereference", member.IsNullConditional || isChainContinuation)
        receiverType := declarationContextValue.ResolveDeclaredAlias(NonNullableType(objectType))
        byRefReceiver := receiverType as ByRefTypeInfo
        if byRefReceiver != null {
            receiverType = declarationContextValue.ResolveDeclaredAlias(NonNullableType(byRefReceiver.InnerType))
        }

        if receiverType as SoaRecordTypeInfo != null && member.IsNullConditional {
            ReportSoaTableNullConditionalAccess(member)
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if receiverType as SoaRowTypeInfo != null && member.IsNullConditional {
            soaEscapeValue.ReportSoaRowEscape(member.Object, "used with null-conditional member access")
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if member.IsNullConditional && soaEscapeValue.ReportDirectColumnNullConditionalAccessIfNeeded(member, member.Object, "member access") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        soaRowType := receiverType as SoaRowTypeInfo
        if soaRowType != null && AnalyzerMemberResolution.TryGetSoaColumn(soaRowType.Declaration, member.MemberName) == null {
            soaEscapeValue.ReportSoaRowEscape(member.Object, "used as a member receiver")
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        ValidateDeclaredMemberVisibility(receiverType, member)
        TryRecordMemberBinding(receiverType, member)

        includeStaticMembers := IsStaticMemberAccessTarget(member.Object)
        invocationPosition := IsCallCalleePosition(member)
        memberType := memberResolutionValue.ResolveMember(scopesValue.ConstrainedReceiverType(receiverType), member.MemberName, includeStaticMembers, ambientValue.CurrentTypeName, invocationPosition, InheritsProtectedThrough(receiverType, member.Object))
        if invocationPosition && BuiltInTypes.IsUnknown(memberType) && ReportMemberNotCallableIfNeeded(receiverType, member, includeStaticMembers) {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        // NL308 BEFORE NL303, AND BEFORE THE LENIENCY. A name that is really declared on the
        // receiver's metadata and is out of reach for ONE reason — the declaring assembly did not
        // name this compilation a friend — is a visibility refusal, not a missing member. It is
        // asked here rather than in `ValidateDeclaredMemberVisibility` above because it is only
        // worth asking once resolution has MISSED: a member this compilation may see has already
        // answered, so the reflection sweep never runs on the resolving path.
        if BuiltInTypes.IsUnknown(memberType) && ReportFriendBarredMemberIfNeeded(receiverType, member, includeStaticMembers) {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if BuiltInTypes.IsUnknown(memberType) && ShouldReportUndefinedMember(receiverType, member.MemberName, includeStaticMembers) {
            // The report is RENDERED HERE. It used to be a step the driver performed, because building
            // the did-you-mean list reads `PropertyInfo.Name` and `FieldInfo.Name` off the receiver's
            // reflected members — which slice 55 measured as absent from the columnar catalog and
            // priced at two rows. The re-measurement overturned that: the catalog is the LEGACY
            // whole-subtree planner's surface, and the ordinary runtime resolver binds both names on
            // receivers that have been supported all along. Returning here is what preserves the C#'s
            // `else if`: the SoA column registration must not run when the report did.
            ReportUndefinedMember(receiverType, member, includeStaticMembers)
            if member.IsNullConditional {
                state.ResultType = MakeNullableResult(memberType)
            } else {
                state.ResultType = memberType
            }

            return
        }

        soaRecordType := receiverType as SoaRecordTypeInfo
        if soaRecordType != null && AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, member.MemberName) != null {
            soaEscapeValue.RecordColumnMemberAccess(member)
        }

        // A MEMBER RESOLVED THROUGH REFLECTION HAS NO ELEMENT NAMES IN IT, because a named tuple has
        // none in the CLR. The receiver's WRITTEN type is the position that named them, so the member's
        // type takes them back from it -- see `AnalyzerTupleElementNames.GraftFromReceiver`.
        memberType = AnalyzerTupleElementNames.GraftFromReceiver(memberType, receiverType)

        // THE LIFT SKIPS A CALLEE — every callee, including the `?.` link itself. `s?.Trim()` resolves
        // `.Trim` to a method group, and a method group has no nullable form; the INVOCATION is the
        // chain's result and lifts there. Lifting the guard link too wrapped the method group in a
        // `NullableTypeInfo`, which the call's own dispatch matches NOTHING against — so every
        // `x?.M(...)` silently answered `unknown`: no overload resolution, no argument diagnostics,
        // and no postconditions, which is why `map?.TryGetValue(k, out v) == true` proved nothing
        // about `v` and `h?.M("a", "b", "c")` reported no arity error at all.
        if (member.IsNullConditional || isChainContinuation) && !invocationPosition {
            state.ResultType = MakeNullableResult(memberType)
        } else {
            state.ResultType = memberType
        }
    }

    // `HasValue` AND `Value` ON A NULLABLE, and nothing else — a third name falls through so member
    // resolution can answer it against the INNER type.
    //
    // The second way in is the one that carries the rule: a receiver whose SYMBOL was declared
    // nullable and has been NARROWED, so the type reaching here is the inner one. `x.Value` inside
    // `if x != null { … }` reaches here with `int`, not `int?`, and it must still mean the unwrap —
    // and it must NOT be warned about, because the narrowing already proved it safe. That is the
    // whole of `isNarrowedNullableOrigin`.
    //
    // WHICH RECEIVERS COUNT AS NARROWED IS `AnalyzerNullFlow.NarrowedNullableOrigin`'S RULE — a
    // narrowed local found by walking out of the scopes, and a narrowed member PATH read back from
    // the collapse that produced the inner type. The arm below asks it identically.
    func TryResolveNullableMemberAccess(member: MemberAccessExpression, objectType: TypeInfo, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown

        nullableType := objectType as NullableTypeInfo
        isNarrowedNullableOrigin := false
        if nullableType == null {
            origin := nullFlowValue.NarrowedNullableOrigin(member.Object, objectType)
            if origin != null {
                nullableType = origin
                isNarrowedNullableOrigin = true
            }
        }

        if nullableType == null {
            return false
        }

        // `Nullable<T>` IS A VALUE-TYPE CONSTRUCT, AND A REFERENCE `T?` IS NOT ONE. The `?` on a class
        // is an ANNOTATION on the same CLR type — `MarkupContent?` IS `MarkupContent` — so `.Value`
        // and `.HasValue` there are whatever the class itself declares, and a class that declares
        // neither has no such member at all. Answering them from here read
        // `documentation.MarkupContent?.Value` as the unwrap and typed it `MarkupContent`, when the
        // class's own `Value: string` is what the reader wrote.
        //
        // A `struct`-CONSTRAINED TYPE PARAMETER IS THE ONE BARE NAME THAT IS NOT A REFERENCE. `T` is a
        // `SimpleTypeInfo` carrying nothing but its spelling, so the reference question answers YES of
        // it — and the `T?` of `func F<T>(a: T?) where T : struct` is a real `Nullable<T>`, whose
        // `.HasValue` inside the declaration was therefore read as a class member that does not exist.
        if AnalyzerConversionFacts.IsReferenceType(nullableType.InnerType) && !IsStructConstrainedTypeParameter(nullableType.InnerType) {
            return false
        }

        if member.MemberName == "HasValue" {
            memberType = BuiltInTypes.Bool
            return true
        }

        if member.MemberName == "Value" {
            if !isNarrowedNullableOrigin {
                diagnosticsValue.Warn(ErrorCode.NullabilityWarning, "This '.Value' access can throw when the nullable value is absent", member.Line, spansValue.GetMemberNameColumn(member), "Prefer 'must value' for an explicit unwrap, or use 'match value { null => ..., inner => ... }' to handle both cases.", Math.Max(1, member.MemberName.Length))
            }

            memberType = nullableType.InnerType
            return true
        }

        return false
    }

    // `Nullable<T>`'S OWN SURFACE — every member the DEFINITION declares, and nothing else.
    //
    // THE SPLIT IS DECIDED BY WHAT `Nullable<T>` DECLARES, NOT BY WHAT `T` CANNOT ANSWER. Both are
    // metadata questions and neither is a name list, but they give different answers for the three
    // names both types have — `ToString`, `Equals` and `GetHashCode` — and C# gives `Nullable<T>`'s.
    // `v.ToString()` on an `int?` is `Nullable<int>.ToString()`: null-safe, "" when the value is
    // absent, and no warning. Asking `T` first bound `int.ToString` and read the receiver as a
    // DEREFERENCE, so the same expression reported NL905 for a call that cannot throw.
    //
    // A NAME `Nullable<T>` DOES NOT DECLARE STAYS `T`-FIRST, which is the other half of the same
    // rule and is what keeps `v.CompareTo(3)` on `int`'s own overloads. `GetType` is the sharp case:
    // `Nullable<T>` does not override it, so it is `object`'s, it BOXES the receiver, and boxing an
    // absent nullable yields a null reference — the NL905 a `T`-first read produces is the correct
    // answer there, and C# throws at run time for the same program.
    //
    // AND IT IS ASKED BEFORE NL905, because nothing on this surface dereferences anything.
    // `Nullable<T>` is a struct; `v.GetValueOrDefault()` on an absent value returns `default` and
    // `v.HasValue` returns false. C# warns about neither, and neither does this.
    func TryResolveNullableValueTypeOwnMember(member: MemberAccessExpression, objectType: TypeInfo, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        if IsStaticMemberAccessTarget(member.Object) {
            return false
        }

        nullableType := declarationContextValue.ResolveDeclaredAlias(objectType) as NullableTypeInfo
        if nullableType == null {
            origin := nullFlowValue.NarrowedNullableOrigin(member.Object, objectType)
            if origin == null {
                return false
            }

            nullableType = origin
        }

        // `T?` over a REFERENCE type is the same CLR type as `T` and has no surface of its own.
        if !IsLiftedValueReceiver(nullableType.InnerType) {
            return false
        }

        if !NullableDefinitionDeclares(member.MemberName) {
            return false
        }

        clrNullableType := clrTypeConversionValue.TryConvertTypeInfoToClrType(nullableType)
        if clrNullableType != null {
            resolved := memberResolutionValue.ResolveMember(new ReflectionTypeInfo(clrNullableType), member.MemberName, false, ambientValue.CurrentTypeName)
            if BuiltInTypes.IsUnknown(resolved) {
                return false
            }

            memberType = resolved
            return true
        }

        return TryResolveOpenNullableDefinitionMember(nullableType.InnerType, member.MemberName, out memberType)
    }

    // A BARE NAME THAT A `where` CLAUSE CONSTRAINED TO `struct`. The clause is recorded on the scope
    // that declared the parameter — the same fact `NullabilityGenericSubstitution`'s
    // `LiftedTypeParameterNames` reads off a signature — because a type parameter is a
    // `SimpleTypeInfo` and carries nothing else.
    func IsStructConstrainedTypeParameter(candidate: TypeInfo): bool {
        typeParameter := declarationContextValue.ResolveDeclaredAlias(candidate) as SimpleTypeInfo
        return typeParameter != null && scopesValue.IsStructConstrainedTypeParameter(typeParameter.Name)
    }

    // IS `T` IN THIS `T?` A VALUE TYPE? That is what decides whether `Nullable<T>` exists at all here.
    //
    // The CLR answers for every type it has a handle for, and it is asked of the INNER type rather
    // than of the constructed one because `Nullable.GetUnderlyingType` compares against the RUNTIME
    // `Nullable<>` and answers null for every type the metadata load context produced. A type THIS
    // COMPILATION declares has no handle yet, so its DECLARATION answers — a struct, an enum, a
    // struct record and a tuple are values, and nothing else is. `unknown` is not a value type and
    // must not be read as one.
    func IsLiftedValueReceiver(innerType: TypeInfo): bool {
        clrInnerType := clrTypeConversionValue.TryConvertTypeInfoToClrType(innerType)
        if clrInnerType != null {
            return clrInnerType.get_IsValueType()
        }

        // A TYPE PARAMETER IS A VALUE WHEN ITS OWN `where` CLAUSE SAYS SO, and it has no CLR handle to
        // ask instead: `a.GetValueOrDefault()` inside `func F<T>(a: T?) where T : struct` reported
        // NL303 for a member `T` certainly does not declare, while `if a == null` and the narrowed
        // `a.Value` beside it were fine.
        if IsStructConstrainedTypeParameter(innerType) {
            return true
        }

        resolved := declarationContextValue.ResolveDeclaredAlias(innerType)
        if resolved as StructTypeInfo != null || resolved as EnumTypeInfo != null || resolved as TupleTypeInfo != null {
            return true
        }

        recordType := resolved as RecordTypeInfo
        return recordType != null && recordType.IsStruct
    }

    // WHETHER `Nullable<T>` ITSELF DECLARES A NAME, asked of the DEFINITION'S OWN metadata.
    //
    // `DeclaredOnly` is what makes this a question about `Nullable<T>` rather than about every type:
    // `ToString`, `Equals` and `GetHashCode` are overrides `Nullable<T>` declares, and `GetType`,
    // which it inherits from `object` unchanged, is not on this surface and stays `T`-first. No name
    // is written down here — the definition is read, and whatever it declares is what a `T?`
    // receiver answers first.
    func NullableDefinitionDeclares(memberName: string): bool {
        return NullableDefinitionNames(true).Contains(memberName)
    }

    // The names a `T?` receiver offers a READER — the same surface with the accessor methods left
    // out, because `HasValue` is what a developer writes and `get_HasValue` is what the binder also
    // has to accept.
    func NullableDefinitionMemberNames(): List<string> {
        return NullableDefinitionNames(false)
    }

    // The definition's declared names, in declaration order.
    func NullableDefinitionNames(includeAccessors: bool): List<string> {
        names := new List<string>()
        definition: Type = typeof(object)
        if !TryGetNullableDefinition(out definition) {
            return names
        }

        declaredFlags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly
        properties := definition.GetProperties(declaredFlags)
        for property in properties {
            names.Add(property.get_Name())
        }

        methods := definition.GetMethods(declaredFlags)
        for method in methods {
            if includeAccessors || !method.get_IsSpecialName() {
                names.Add(method.get_Name())
            }
        }

        return names
    }

    // ONE SURFACE FOR EVERY `Nullable<T>`, WHATEVER `T` IS — read off the DEFINITION, with the
    // element substituted.
    //
    // The arm above answers from the CLOSED construction, which is the exact reading whenever the
    // CLR has one. It does NOT have one while `T` is a struct or an enum this compilation is
    // emitting, and the whole surface vanished there: `money.GetValueOrDefault()` on a `Money?`
    // reported NL303 "Member 'GetValueOrDefault' not found on type 'Money'" — the name resolved
    // against the UNWRAPPED receiver, which is the one type that certainly does not declare it —
    // while the identical spelling over an `int?` bound.
    //
    // `Nullable<T>` is one declaration, so its members are one list, and the only thing an element
    // changes is what `T` means in them. That is exactly the substitution
    // `AnalyzerReflectionTypeOverride.ForGenericArguments` performs for every other external generic
    // closed over a source type, so the members are read off the definition under it rather than
    // enumerated by name here. No name list, no per-element table: whatever `Nullable<T>` declares
    // is what a `T?` receiver has.
    func TryResolveOpenNullableDefinitionMember(innerType: TypeInfo, memberName: string, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        definition: Type = typeof(object)
        if !TryGetNullableDefinition(out definition) {
            return false
        }

        parameters := definition.GetGenericArguments()
        if parameters.Length != 1 {
            return false
        }

        overrides := new Dictionary<Type, TypeInfo>()
        overrides[parameters[0]] = innerType
        answering := AnalyzerReflectionTypeOverride.Direct(overrides, null)
        memberFlags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly

        property := definition.GetProperty(memberName, memberFlags)
        if property != null {
            memberType = NullabilityMetadataReflection.ConvertPropertyWithOverride(property, answering)
            return true
        }

        methods := definition.GetMethods(memberFlags)
        functions := new List<FunctionTypeInfo>()
        for method in methods {
            if method.get_Name() == memberName {
                functions.Add(CreateSubstitutedNullableSignature(method, answering))
            }
        }

        if functions.Count == 0 {
            return false
        }

        memberType = new NSharpMethodGroupInfo(functions)
        return true
    }

    // THE `Nullable<>` DEFINITION IN THE ANALYZER'S OWN UNIVERSE, reached through the conversion
    // funnel that already builds an `int?` rather than through `typeof(Nullable<>)`: under a
    // MetadataLoadContext the projected definition is a different object from this process's, and a
    // member read off the wrong one belongs to the wrong universe.
    func TryGetNullableDefinition(out definition: Type): bool {
        definition = typeof(object)
        probe: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
        closed := clrTypeConversionValue.TryConvertTypeInfoToClrType(probe)
        if closed == null || !closed.get_IsGenericType() || closed.get_IsGenericTypeDefinition() {
            return false
        }

        definition = closed.GetGenericTypeDefinition()
        return true
    }

    // One of the definition's methods as a signature the source call binder can resolve, with every
    // position converted under the element substitution.
    static func CreateSubstitutedNullableSignature(method: MethodInfo, answering: AnalyzerReflectionTypeOverride): FunctionTypeInfo {
        signature := new FunctionTypeInfo()
        signature.SyntheticName = method.get_Name()
        parameterNames := new List<string>()
        parameterTypes := new List<TypeInfo>()
        parameters := method.GetParameters()
        for parameter in parameters {
            parameterNames.Add(parameter.get_Name() ?? "")
            parameterTypes.Add(NullabilityMetadataReflection.ConvertParameterWithOverride(parameter, answering))
        }

        signature.ParameterNames = parameterNames
        signature.ParameterTypes = parameterTypes
        signature.ReturnType = NullabilityMetadataReflection.ConvertReturnWithOverride(method, answering)
        return signature
    }

    // WHETHER THE RECEIVER NAMES A TYPE RATHER THAN A VALUE, which is what decides whether STATIC
    // members are in scope for the name after the dot.
    //
    // PUBLISHED because the four write-target classifiers ask exactly the same question about
    // exactly the same node — a `readonly` field's owner, a read-only property's receiver, and the
    // static and instance readonly-field targets all fork on it.
    //
    // A bare identifier is a TYPE precisely when no SYMBOL of that name is in scope: a local named
    // `Console` shadows the class, which is the shadowing rule the identifier arm applies one level
    // down.
    func IsStaticMemberAccessTarget(target: Expression): bool {
        parenthesized := target as ParenthesizedExpression
        if parenthesized != null {
            return IsStaticMemberAccessTarget(parenthesized.Inner)
        }

        identifier := target as IdentifierExpression
        if identifier != null {
            return scopesValue.LookupSymbol(identifier.Name) == null
        }

        // A CONSTRUCTED GENERIC TYPE RECEIVER IS ALWAYS A TYPE. `Vector<int>` cannot be a value —
        // the parser builds this node only for `Name<Args>.`, and no symbol can shadow it — so it
        // answers here without a scope probe, the same shortcut the identifier arm above takes in
        // the other direction.
        if target as GenericTypeExpression != null {
            return true
        }

        discardedType: TypeInfo = BuiltInTypes.Unknown
        return TryResolveTypeValuedMemberAccess(target, out discardedType)
    }

    // THE TYPE A RECEIVER NAMES, or nothing. Four channels in order — a local type, a built-in
    // keyword, an external type, and a nested type reached through a dotted owner — with a
    // SYMBOL of that name vetoing all four, because a value shadows a type name.
    //
    // PUBLISHED because the array arm asks it of `Array`, `System.Array` and any dotted expression
    // that might name one.
    func TryResolveTypeValuedMemberAccess(expression: Expression, out resolvedType: TypeInfo): bool {
        resolvedType = BuiltInTypes.Unknown

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return TryResolveTypeValuedMemberAccess(parenthesized.Inner, out resolvedType)
        }

        identifier := expression as IdentifierExpression
        if identifier != null {
            if scopesValue.LookupSymbol(identifier.Name) != null {
                return false
            }

            localType := scopesValue.LookupType(identifier.Name)
            if localType != null {
                resolvedType = declarationContextValue.ResolveDeclaredAlias(localType)
            } else {
                resolvedType = declarationContextValue.ResolveDeclaredAlias(BuiltInTypes.Unknown)
            }

            if !BuiltInTypes.IsUnknown(resolvedType) {
                return true
            }

            builtInType := AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(wellKnownTypesValue, identifier.Name)
            if builtInType != null {
                resolvedType = new ReflectionTypeInfo(builtInType)
                return true
            }

            externalType := externalTypeProbeValue.ResolveExternalType(identifier.Name)
            if externalType != null {
                resolvedType = externalType
                // The import that supplied a TYPE-VALUED receiver is used by this file, and this is
                // the only channel that sees it: `Encoding.UTF8` writes no annotation.
                credit := importUsageCreditValue
                if credit != null {
                    credit.CreditResolvedType(identifier.Name, externalType)
                }
            } else {
                resolvedType = BuiltInTypes.Unknown
            }

            return !BuiltInTypes.IsUnknown(resolvedType)
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            if TryResolveQualifiedTypeName(memberAccess, out resolvedType) {
                return true
            }

            ownerType: TypeInfo = BuiltInTypes.Unknown
            if !TryResolveTypeValuedMemberAccess(memberAccess.Object, out ownerType) {
                return false
            }

            return declarationContextValue.TryResolveNestedType(ownerType, memberAccess.MemberName, false, out resolvedType)
        }

        return false
    }

    // A DOTTED NAME THAT NAMES A TYPE — `System.Text.StringBuilder`, `MyApp.Models.Person`, or the
    // same two reached through a namespace alias — and the SIX vetoes that must all miss before the
    // name is read as a qualification at all. Their ORDER is the whole rule: every one of them names
    // something the developer wrote that would OUTRANK a namespace of the same root, so a local, a
    // local type, a file-import alias, a project type of that root name, an enclosing-type member and
    // a project function each stop the probe before it looks at a namespace. Without them a project
    // function named `Log` would be shadowed by an assembly's `Log.Write`.
    //
    // The CHEAP vetoes run first and the four that cost a scan run after them, which is what keeps
    // this affordable now that it is asked of a member access TWICE — once about its receiver and
    // once about the node itself. Reordering vetoes is safe because every one of them answers "not a
    // qualified name"; only the alias arm below both vetoes and answers, so it keeps its place.
    //
    // A USING ALIAS IS NOT A VETO ANY MORE, it is a channel: `import NSharpLang.Runtime as Rt` makes
    // `Rt.SimdReductions` mean the aliased namespace's type, which is what the same alias already
    // meant at a declared-type position (`AnalyzerDeclarationPolicy.ResolveThroughNamespaceAlias`).
    //
    // WHAT IT RESOLVES TO, in the documented order — a PROJECT type in the named namespace first,
    // because project types outrank CLR types, then a CLR type from the referenced assemblies.
    func TryResolveQualifiedTypeName(expression: Expression, out resolvedType: TypeInfo): bool {
        resolvedType = BuiltInTypes.Unknown
        if expression as MemberAccessExpression == null {
            return false
        }

        qualifiedName := ""
        if !TryGetQualifiedExpressionTreeName(expression, out qualifiedName) {
            return false
        }

        rootName := ExternalQualifiedTypeResolver.RootName(qualifiedName)
        if scopesValue.LookupSymbol(rootName) != null || scopesValue.LookupType(rootName) != null || importedSymbolsByAliasValue.ContainsKey(rootName) {
            return false
        }

        aliasedNamespace := ""
        if usingAliasesValue.TryGetValue(rootName, out aliasedNamespace) {
            return TryResolveTypeInNamespaceOrAssemblies(aliasedNamespace + qualifiedName.Substring(rootName.Length), out resolvedType)
        }

        currentUnitNamespace := UnitNamespace()
        visibleNamespaces := AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(currentUnitNamespace, usingNamespacesValue)
        for visibleNamespace in visibleNamespaces {
            namespaceType: TypeInfo = BuiltInTypes.Unknown
            namespaceDeclaration: SymbolDeclaration? = null
            if projectDiscoveryValue.TryResolveProjectTypeInNamespace(rootName, visibleNamespace, currentUnitNamespace, out namespaceType, out namespaceDeclaration) {
                return false
            }
        }

        currentType := scopesValue.CurrentTypeScope()
        if currentType != null && !BuiltInTypes.IsUnknown(memberResolutionValue.ResolveMember(currentType, rootName, true, ambientValue.CurrentTypeName)) {
            return false
        }

        projectFunctionType: TypeInfo = BuiltInTypes.Unknown
        projectFunctionDeclaration: SymbolDeclaration? = null
        if identifierResolutionValue.TryResolveVisibleProjectFunction(rootName, out projectFunctionType, out projectFunctionDeclaration) {
            return false
        }

        return TryResolveTypeInNamespaceOrAssemblies(qualifiedName, out resolvedType)
    }

    // THE TWO PLACES A QUALIFIED NAME'S TYPE CAN LIVE, in the documented order: the project's own
    // sources, split at the LAST dot into a namespace and a type name, and then the referenced
    // assemblies. A project type is required to be EXPORTED unless the reader is in its own
    // namespace, which is `TryResolveProjectTypeInNamespace`'s rule and not a second one here.
    //
    // The namespace half is read through the file's LEXICAL chain (`SimpleNamePrecedence`), the same
    // owner the declared-type resolver uses, so `Ast.Node` written inside `App` finds `App.Ast.Node`
    // in expression position exactly as it does at a type position.
    func TryResolveTypeInNamespaceOrAssemblies(qualifiedName: string, out resolvedType: TypeInfo): bool {
        resolvedType = BuiltInTypes.Unknown
        separator := qualifiedName.LastIndexOf(".")
        if separator > 0 {
            currentNamespace := UnitNamespace()
            leafName := qualifiedName.Substring(separator + 1)
            qualifiers := SimpleNamePrecedence.QualifierNamespaces(currentNamespace, qualifiedName.Substring(0, separator))
            qualifierIndex := 0
            while qualifierIndex < qualifiers.Count {
                projectType: TypeInfo = BuiltInTypes.Unknown
                projectDeclaration: SymbolDeclaration? = null
                if projectDiscoveryValue.TryResolveProjectTypeInNamespace(leafName, qualifiers[qualifierIndex], currentNamespace, out projectType, out projectDeclaration) {
                    resolvedType = declarationContextValue.ResolveDeclaredAlias(projectType)
                    return !BuiltInTypes.IsUnknown(resolvedType)
                }
                qualifierIndex = qualifierIndex + 1
            }
        }

        runtimeType: Type = typeof(object)
        if !ExternalQualifiedTypeResolver.TryResolve(mlcAssembliesValue, qualifiedName, externalTypeProbeValue.Grants, out runtimeType) {
            return false
        }

        resolvedType = new ReflectionTypeInfo(runtimeType)
        return true
    }

    // THE DOTTED NAME AN EXPRESSION TREE SPELLS, or nothing. A null-conditional link BREAKS the name:
    // `a?.B.C` is not a type reference, because a type reference cannot be conditional.
    //
    // PUBLISHED because the expression-tree static-call receiver probe reads the same name.
    static func TryGetQualifiedExpressionTreeName(expression: Expression, out name: string): bool {
        identifier := expression as IdentifierExpression
        if identifier != null {
            name = identifier.Name
            return true
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null && !memberAccess.IsNullConditional {
            parentName := ""
            if TryGetQualifiedExpressionTreeName(memberAccess.Object, out parentName) {
                name = parentName + "." + memberAccess.MemberName
                return true
            }
        }

        name = ""
        return false
    }

    // THE BINDING GO-TO-DEFINITION READS. Recorded for every member access whose declaration can be
    // found, including one found only as an extension method — the extension case is why this cannot
    // just read what member resolution returned.
    func TryRecordMemberBinding(objectType: TypeInfo, member: MemberAccessExpression) {
        declaration: SymbolDeclaration? = null
        if TryFindMemberDeclaration(objectType, member.MemberName, out declaration) {
            // TOTAL on this path: the finder materialises the declaration before answering `true`.
            if declaration != null {
                RecordMemberBinding(member, declaration)
            }
        }
    }

    // NL308. A member that EXISTS and is reachable but is not exported, read from a file in another
    // package. The check runs before resolution rather than after, because a non-exported member
    // still RESOLVES — the objection is visibility, not existence, and the developer must be told
    // which of the two it is.
    func ValidateDeclaredMemberVisibility(objectType: TypeInfo, member: MemberAccessExpression) {
        selection := new AnalyzerMemberSelection()
        if !declarationContextValue.TryFindMember(declarationContextValue.ResolveDeclaredAlias(objectType), member.MemberName, out selection) {
            return
        }

        if IsCrossPackageFile(selection.FilePath) && !selection.IsExported {
            diagnosticsValue.ReportInaccessibleMember(member.MemberName, selection.FilePath, member.Line, spansValue.GetMemberNameColumn(member))
            return
        }

        ValidateDeclaredMemberAccessibility(objectType, member, selection)
    }

    // THE DECLARED-ACCESSIBILITY HALF OF NL308, for a member reached through a written receiver.
    //
    // The package rule above and this one are both NL308 and they are genuinely one question — "may
    // this file read this member" — asked of two independent systems, so only one of them reports:
    // a camelCase `private` field read from another package has one thing wrong with it that the
    // developer will fix once, and two underlines saying so would be noise.
    //
    // `base.M()` IS ITS OWN ARM and not a receiver judgement. The receiver half of the `protected`
    // rule asks whether the receiver's type derives from the accessing type, and `base` is typed as
    // the BASE — the one receiver that never does. C# spells this out separately (§7.6.8) and so
    // does this: inside a derived type, `base.` reaches exactly what the base declares protected.
    func ValidateDeclaredMemberAccessibility(objectType: TypeInfo, member: MemberAccessExpression, selection: AnalyzerMemberSelection) {
        declaredMember := selection.Member
        if declaredMember == null {
            return
        }

        level := MemberAccessibility.LevelOfDeclaredModifiers(declaredMember.DeclaredModifiers)
        if level == MemberAccessibility.Public {
            return
        }

        accessingType := TryGetAccessingType(objectType)
        declaringOwner := selection.Owner

        // THE AMBIENT NAME IS THE LAST WORD ON "am I inside the declaring type". It is what every
        // member declaration in this walk was recorded under, so it answers even where the registry
        // hands back a different instance of the same declaration.
        isDeclaringType := IsSameDeclaredType(accessingType, declaringOwner) || AmbientTypeNameMatches(declaringOwner)
        derives := IsSameOrDerivedFrom(accessingType, declaringOwner)
        receiverCompatible := member.Object as BaseExpression != null || IsStaticMemberAccessTarget(member.Object) || IsSameOrDerivedFrom(objectType, accessingType)

        // Source members are compiled into the assembly being produced, so `internal` and the
        // assembly half of `protected internal` are always satisfied here.
        if MemberAccessibility.IsAccessible(level, isDeclaringType, derives, receiverCompatible, true) {
            return
        }

        diagnosticsValue.ReportInaccessibleDeclaredMember(member.MemberName, DeclaredTypeDisplayName(declaringOwner), level, AccessingTypeDisplayName(), member.Line, spansValue.GetMemberNameColumn(member), member.MemberName.Length)
    }

    // WHETHER THIS ACCESS MAY SEE THE `protected` SURFACE OF THE RECEIVER'S BASES.
    //
    // The same receiver rule the declared relation enforces for SOURCE members (C# §7.5.4), asked of
    // a receiver whose bases are EXTERNAL: the access must be written inside a type that is, or
    // derives from, the receiver's type — and `base.`, whose receiver is by construction the base,
    // is its own case, as is a bare name, which has no written receiver because the receiver is
    // `this`.
    func InheritsProtectedThrough(receiverType: TypeInfo, receiver: Expression?): bool {
        accessingType := TryGetAccessingType()
        if accessingType == null {
            return false
        }

        if receiver as BaseExpression != null || receiver as ThisExpression != null {
            return true
        }

        return IsSameOrDerivedFrom(receiverType, accessingType)
    }

    // The type the walk is written inside, resolved from the ambient name against the file being
    // analysed. A free function, a top-level statement and a lambda outside every type all answer
    // nothing, which the relation reads as "not the declaring type and not derived from it".
    func TryGetAccessingType(): TypeInfo? {
        return TryGetAccessingType(null)
    }

    // The RECEIVER'S OWN CHAIN IS THE SECOND PLACE TO LOOK, and for a generic type it is the only one
    // that answers: the declaration registry is keyed by written name and a generic declaration does
    // not always come back out of it as the same shape the walk is standing inside. When the access is
    // written in a type that IS on the receiver's chain — which is every `this.`/derived access, the
    // only shape the protected rule can admit — the chain names it exactly.
    func TryGetAccessingType(receiverType: TypeInfo?): TypeInfo? {
        typeName := ambientValue.CurrentTypeName
        if typeName == null || typeName.Length == 0 {
            return null
        }

        currentFile := diagnosticsValue.CurrentFilePath
        if currentFile != null && currentFile.Length > 0 {
            resolved := BuiltInTypes.Unknown as TypeInfo
            if declarationContextValue.TryGetCanonicalType(currentFile, typeName, out resolved) && !BuiltInTypes.IsUnknown(resolved) {
                return resolved
            }
        }

        return TryFindNamedTypeInChain(receiverType, typeName)
    }

    func TryFindNamedTypeInChain(start: TypeInfo?, typeName: string): TypeInfo? {
        visited := new HashSet<object>()
        current: TypeInfo? = start
        while current != null {
            declaration := DeclarationOf(current)
            if DeclaredSimpleName(declaration) == typeName {
                return declaration
            }

            if !visited.Add(declaration) {
                return null
            }

            shape := new AnalyzerSourceMemberShape()
            if !declarationContextValue.TryGetSourceMemberShape(declaration, null, out shape) {
                return null
            }

            current = shape.BaseType
        }

        return null
    }

    func AmbientTypeNameMatches(owner: TypeInfo?): bool {
        ownerName := DeclaredSimpleName(owner)
        currentName := ambientValue.CurrentTypeName
        return ownerName != null && currentName != null && ownerName == currentName
    }

    func AccessingTypeDisplayName(): string? {
        return ambientValue.CurrentTypeName
    }

    // THE NAME A REFUSAL QUOTES for the declaring type. `FormatTypeInfo` is what the undefined-member
    // report in this file renders a type with, so a generic owner reads the same way here as it does
    // everywhere else the developer has already seen it.
    func DeclaredTypeDisplayName(owner: TypeInfo?): string {
        if owner == null {
            return "the declaring type"
        }

        return NullabilityMetadataReflection.FormatTypeInfo(owner)
    }

    // WHETHER TWO TYPE SHAPES ARE THE SAME SOURCE DECLARATION. A closed generic is the same
    // declaration as its own definition — `Box<int>` and `Box<T>` share every member declaration —
    // so both sides are reduced to their definition before being compared.
    //
    // THE NAME IS A SECOND CHANCE AND NOT A SHORTCUT. A generic type's `this` receiver and the same
    // type read back out of the declaration registry are not always the same INSTANCE, and a refusal
    // built on that difference would report `this.privateField` inside `Box<T>`'s own constructor —
    // which is what it did. A name match can only ever ADMIT an access, never refuse one, so the
    // worst a collision costs is a diagnostic this rule declines to raise.
    func IsSameDeclaredType(candidate: TypeInfo?, other: TypeInfo?): bool {
        if candidate == null || other == null {
            return false
        }

        left := DeclarationOf(candidate)
        right := DeclarationOf(other)
        if left == right {
            return true
        }

        leftName := DeclaredSimpleName(left)
        rightName := DeclaredSimpleName(right)
        return leftName != null && rightName != null && leftName == rightName
    }

    // The written name of a source type declaration, or nothing for a shape that is not one.
    func DeclaredSimpleName(typeInfo: TypeInfo?): string? {
        if typeInfo == null {
            return null
        }

        classType := typeInfo as ClassTypeInfo
        if classType != null {
            return classType.Name
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            return structType.Name
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return recordType.Name
        }

        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            return generic.Name
        }

        return null
    }

    func DeclarationOf(typeInfo: TypeInfo): TypeInfo {
        resolved := declarationContextValue.ResolveDeclaredAlias(typeInfo)
        generic := resolved as GenericTypeInfo
        if generic != null && generic.GenericDefinition != null {
            return generic.GenericDefinition
        }

        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return DeclarationOf(nullable.InnerType)
        }

        oblivious := resolved as ObliviousTypeInfo
        if oblivious != null {
            return DeclarationOf(oblivious.InnerType)
        }

        return resolved
    }

    // Whether `candidate` IS `ancestor` or declares it somewhere up its source base chain. The walk
    // is bounded by a visited set rather than a depth count because a malformed cyclic base clause is
    // reported elsewhere and must not hang this one.
    func IsSameOrDerivedFrom(candidate: TypeInfo?, ancestor: TypeInfo?): bool {
        if candidate == null || ancestor == null {
            return false
        }

        target := DeclarationOf(ancestor)
        visited := new HashSet<object>()
        current: TypeInfo? = candidate
        while current != null {
            declaration := DeclarationOf(current)
            if IsSameDeclaredType(declaration, target) {
                return true
            }

            if !visited.Add(declaration) {
                return false
            }

            shape := new AnalyzerSourceMemberShape()
            if !declarationContextValue.TryGetSourceMemberShape(declaration, null, out shape) {
                return false
            }

            current = shape.BaseType
        }

        return false
    }

    func RecordMemberBinding(member: MemberAccessExpression, declaration: SymbolDeclaration) {
        memberColumn := spansValue.GetMemberNameColumn(member)
        bindingsValue.RecordBinding(diagnosticsValue.CurrentFilePath, member.Line, memberColumn, member.MemberName.Length, declaration)
    }

    // WHERE A MEMBER IS DECLARED: the owner's own members first, then the extension methods. The
    // extension fallback is what makes go-to-definition work on `value.MyExtension()`, and its
    // declaration is attributed to the CURRENT file because an extension `func` is only visible from
    // one that imported it.
    func TryFindMemberDeclaration(objectType: TypeInfo, memberName: string, out declaration: SymbolDeclaration?): bool {
        resolvedOwner := declarationContextValue.ResolveDeclaredAlias(objectType)
        selection := new AnalyzerMemberSelection()
        if declarationContextValue.TryFindMember(resolvedOwner, memberName, out selection) {
            if selection.Member != null {
                declaration = CreateSymbolDeclaration(selection.Member, selection.FilePath, selection.KindName)
            } else {
                declaration = new SymbolDeclaration(memberName, selection.FilePath, selection.Line, selection.Column, selection.KindName)
            }

            return true
        }

        index := 0
        while index < extensionMethodsValue.Count {
            candidate := extensionMethodsValue[index]
            if candidate.Name == memberName && extensionMethodResolutionValue.IsExtensionReceiverApplicable(candidate, resolvedOwner) {
                declaration = new SymbolDeclaration(candidate.Name, diagnosticsValue.CurrentFilePath, candidate.Line, candidate.Column, "function")
                return true
            }

            index = index + 1
        }

        declaration = null
        return false
    }

    // The declaration's own column is re-derived from the declaring file's TEXT rather than trusted
    // from the parsed node, so go-to-definition lands on the NAME and not on the modifier that
    // precedes it.
    // The KIND WORD comes from the selection rather than off the member, because the word depends on
    // the OWNER the member was found on: an interface's instance value member is a property, and only
    // the lookup that walked the owner knows that.
    func CreateSymbolDeclaration(member: DeclaredMemberInfo, filePath: string?, kindName: string): SymbolDeclaration {
        sourceText := projectSourcesValue.TryGetProjectSourceText(filePath)
        return new SymbolDeclaration(member.Name, filePath, member.Line, AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(sourceText, member.Name, member.Line, member.Column), kindName)
    }

    // WHETHER A MISS IS WORTH REPORTING, which is a question about the RECEIVER and not about the
    // name. The rule is confidence: report only when the analyzer can enumerate the receiver's
    // members well enough to be sure the name is absent.
    //   * `object` never reports — every name might be there through a cast.
    //   * a built-in primitive reports when its CLR type is reachable, and otherwise only for a name
    //     the built-in tables say it does NOT have.
    //   * a generic reports when it has a SOURCE definition or a reachable CLR type, and otherwise
    //     when its REFLECTED definition has a reliable member set that does not contain the name —
    //     which is the case a BCL generic closed over a source type (`List<PriceArgs>`) or over an
    //     enclosing type parameter (`List<T>`) is in: its closed CLR type cannot be constructed, and
    //     a type argument never adds a member to the definition.
    //   * a reflected type reports only from assemblies whose member set is reliable.
    //   * every SOURCE-declared shape reports, because its member list is complete by construction.
    //   * a nullable and an oblivious ask about their inner type.
    //
    // PUBLISHED because the object-initializer and SoA-table-initializer paths ask the same question
    // about a name they could not resolve either.
    // Whether THIS member access is the exact node the enclosing call names. The ambient position
    // flag is true for the whole callee subtree, so identity against the recorded node is what
    // separates `a.b.Count(x)`'s outermost link from the `a.b` beneath it.
    func IsCallCalleePosition(member: MemberAccessExpression): bool {
        calleeNode := ambientValue.CallCalleeNode
        if calleeNode == null {
            return false
        }

        return Object.ReferenceEquals(calleeNode, member)
    }

    // THE MEMBER IS THERE, BUT A CALL CANNOT NAME IT.
    //
    // Invocation-position resolution has just answered `unknown`, which has two causes that read
    // identically from here: there is no such member at all, or there is one and its value cannot be
    // called. Only the second one is worth a sentence of its own, so the same name is resolved AGAIN
    // as a value and the report is made only when that answers. Silence otherwise — the
    // undefined-member report is the right one and it follows.
    func ReportMemberNotCallableIfNeeded(receiverType: TypeInfo, member: MemberAccessExpression, includeStaticMembers: bool): bool {
        valueMemberType := memberResolutionValue.ResolveMember(receiverType, member.MemberName, includeStaticMembers, ambientValue.CurrentTypeName, false)
        if BuiltInTypes.IsUnknown(valueMemberType) {
            return false
        }

        diagnosticsValue.Report(ErrorCode.MemberNotCallable, "`" + member.MemberName + "` is a value of type `" + NullabilityMetadataReflection.FormatTypeInfo(valueMemberType) + "`, not something you can call", member.Line, spansValue.GetMemberNameColumn(member), "Drop the parentheses to read `" + member.MemberName + "`, or call a method or extension of that name — only a delegate value can be called.", Math.Max(1, member.MemberName.Length))
        return true
    }

    func ShouldReportUndefinedMember(receiverType: TypeInfo, memberName: string, includeStaticMembers: bool): bool {
        if string.IsNullOrWhiteSpace(memberName) || memberName == "<error>" {
            return false
        }

        resolved := ResolveAliasAndMetadata(receiverType)

        simple := resolved as SimpleTypeInfo
        if simple != null {
            if BuiltInTypes.Is(simple, BuiltInTypes.Object) {
                return false
            }

            if clrTypeConversionValue.TryConvertTypeInfoToClrType(simple) != null {
                return true
            }

            return IsKnownBuiltInReceiverWithoutReflection(simple) && !IsKnownBuiltInMemberWithoutReflection(simple, memberName, includeStaticMembers)
        }

        if resolved as ArrayTypeInfo != null {
            if clrTypeConversionValue.TryConvertTypeInfoToClrType(resolved) != null {
                return true
            }

            return !IsKnownBuiltInMemberWithoutReflection(resolved, memberName, includeStaticMembers)
        }

        generic := resolved as GenericTypeInfo
        if generic != null {
            genericDefinition := typeSubstitutionValue.ResolveGenericDefinition(generic)
            if genericDefinition != null && genericDefinition as ReflectionTypeInfo == null {
                return true
            }

            if clrTypeConversionValue.TryConvertTypeInfoToClrType(resolved) != null {
                return true
            }

            // A REFLECTED DEFINITION CLOSED OVER A TYPE THAT HAS NO CLR HANDLE — `List<PriceArgs>`,
            // where `PriceArgs` is declared in this program and is not emitted yet, or `List<T>` inside
            // a generic function. The CLOSED type cannot be constructed, so the question above answers
            // nothing, and the miss used to surface only as an emitter decline naming a backend rather
            // than the typo.
            //
            // THE DEFINITION IS ASKED INSTEAD, AND IT IS ASKED ABOUT THE NAME. A type argument never
            // adds a member, so a name the DEFINITION does not have is absent from every instantiation
            // of it and the report is certain. A name the definition DOES have is the other case
            // entirely — the member is real and the resolution failed for want of a closed type — and
            // reporting there would accuse the reader of the analyzer's own gap.
            reflectedDefinition := genericDefinition as ReflectionTypeInfo
            if reflectedDefinition != null {
                if !HasReliableReflectionMemberSet(reflectedDefinition.Type) {
                    return false
                }

                return !GetReflectionMemberNames(reflectedDefinition.Type, includeStaticMembers).Contains(memberName)
            }

            return false
        }

        reflection := resolved as ReflectionTypeInfo
        if reflection != null {
            if IsSystemObjectType(reflection.Type) {
                return false
            }

            return HasReliableReflectionMemberSet(reflection.Type)
        }

        if resolved as ClassTypeInfo != null || resolved as StructTypeInfo != null || resolved as RecordTypeInfo != null || resolved as SoaRecordTypeInfo != null || resolved as SoaRowTypeInfo != null || resolved as InterfaceTypeInfo != null || resolved as EnumTypeInfo != null || resolved as UnionTypeInfo != null || resolved as NewtypeInfo != null || resolved as TupleTypeInfo != null {
            return true
        }

        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return ShouldReportUndefinedMember(nullable.InnerType, memberName, includeStaticMembers)
        }

        oblivious := resolved as ObliviousTypeInfo
        if oblivious != null {
            return ShouldReportUndefinedMember(oblivious.InnerType, memberName, includeStaticMembers)
        }

        return false
    }

    func IsKnownBuiltInMemberWithoutReflection(receiverType: TypeInfo, memberName: string, includeStaticMembers: bool): bool {
        if builtInObjectMembersValue.Contains(memberName) {
            return true
        }

        simple := receiverType as SimpleTypeInfo
        if simple != null {
            if BuiltInTypes.Is(simple, BuiltInTypes.String) {
                return builtInStringInstanceMembersValue.Contains(memberName) || (includeStaticMembers && builtInStringStaticMembersValue.Contains(memberName))
            }

            if BuiltInTypes.Is(simple, BuiltInTypes.Bool) {
                return builtInBooleanInstanceMembersValue.Contains(memberName) || (includeStaticMembers && builtInBooleanStaticMembersValue.Contains(memberName))
            }

            if IsBuiltInNumericType(simple) {
                return builtInNumericInstanceMembersValue.Contains(memberName) || (includeStaticMembers && builtInNumericStaticMembersValue.Contains(memberName))
            }

            if BuiltInTypes.Is(simple, BuiltInTypes.Char) {
                return builtInNumericInstanceMembersValue.Contains(memberName) || (includeStaticMembers && builtInNumericStaticMembersValue.Contains(memberName))
            }

            return false
        }

        if receiverType as ArrayTypeInfo != null {
            return builtInArrayMembersValue.Contains(memberName)
        }

        return false
    }

    static func IsKnownBuiltInReceiverWithoutReflection(candidate: SimpleTypeInfo): bool {
        return BuiltInTypes.Is(candidate, BuiltInTypes.String) || BuiltInTypes.Is(candidate, BuiltInTypes.Bool) || BuiltInTypes.Is(candidate, BuiltInTypes.Char) || IsBuiltInNumericType(candidate)
    }

    static func IsBuiltInNumericType(candidate: SimpleTypeInfo): bool {
        return BuiltInTypes.Is(candidate, BuiltInTypes.Int) || BuiltInTypes.Is(candidate, BuiltInTypes.Long) || BuiltInTypes.Is(candidate, BuiltInTypes.Float) || BuiltInTypes.Is(candidate, BuiltInTypes.Double) || BuiltInTypes.Is(candidate, BuiltInTypes.Decimal) || BuiltInTypes.Is(candidate, BuiltInTypes.Byte) || BuiltInTypes.Is(candidate, BuiltInTypes.SByte) || BuiltInTypes.Is(candidate, BuiltInTypes.Short) || BuiltInTypes.Is(candidate, BuiltInTypes.UShort) || BuiltInTypes.Is(candidate, BuiltInTypes.UInt) || BuiltInTypes.Is(candidate, BuiltInTypes.ULong)
    }

    // WHOSE REFLECTED MEMBER SET CAN BE TRUSTED TO BE COMPLETE: the core library, the console
    // library, LINQ, and any non-interface `System.*` type. An interface is excluded because its
    // members may be spread across the interfaces it inherits, which this probe does not walk.
    static func HasReliableReflectionMemberSet(reflected: Type): bool {
        // `Object.ReferenceEquals` rather than `==`: `Assembly` declares no equality operator, so C#'s
        // `==` on two of them IS reference identity — and that identity is load-bearing. A type read
        // through the metadata load context is never reference-equal to a runtime assembly, so an
        // MLC-loaded `System.String` deliberately falls through these three to the namespace rule.
        // Comparing assembly NAMES instead would silently collapse that distinction.
        //
        // `Console` and `Enumerable` are read by ASSEMBLY-QUALIFIED NAME rather than written
        // `typeof(...)`, because the columnar front end's `typeof` surface carries neither and
        // extending it is a compiler-capability change needing a two-stage bootstrap. This is the
        // compiler's own established spelling — `ColumnarExternalBindingPlans` resolves
        // `System.Console` by exactly this qualified name — and it yields the IDENTICAL runtime
        // `Assembly` instances, so the identity test above is preserved rather than approximated.
        assembly: object = reflected.get_Assembly()
        coreAssembly: object = typeof(object).get_Assembly()
        if Object.ReferenceEquals(assembly, coreAssembly) {
            return true
        }

        consoleType := Type.GetType("System.Console, System.Console")
        if consoleType != null {
            consoleAssembly: object = consoleType.get_Assembly()
            if Object.ReferenceEquals(assembly, consoleAssembly) {
                return true
            }
        }

        linqType := Type.GetType("System.Linq.Enumerable, System.Linq")
        if linqType != null {
            linqAssembly: object = linqType.get_Assembly()
            if Object.ReferenceEquals(assembly, linqAssembly) {
                return true
            }
        }

        reflectedNamespace := reflected.get_Namespace()
        return reflectedNamespace != null && reflectedNamespace.StartsWith("System.", StringComparison.Ordinal) && !reflected.get_IsInterface()
    }

    static func IsSystemObjectType(reflected: Type): bool {
        return reflected == typeof(object) || string.Equals(reflected.FullName, "System.Object", StringComparison.Ordinal)
    }

    func ResolveAliasAndMetadata(candidate: TypeInfo): TypeInfo {
        alias := candidate as AliasTypeInfo
        if alias != null {
            return ResolveAliasAndMetadata(declarationContextValue.ResolveDeclaredAlias(alias))
        }

        oblivious := candidate as ObliviousTypeInfo
        if oblivious != null {
            return ResolveAliasAndMetadata(oblivious.InnerType)
        }

        return candidate
    }

    // NL308 FOR A MEMBER OF A REFERENCED ASSEMBLY THAT ONLY A FRIEND MAY READ.
    //
    // The report is the SAME one a source `internal` member gets — same code, same sentence shape,
    // same three facts (the word, the declaring type, where the access was written from) — because
    // it is the same question. Only the system that answers it differs: a source member's level is
    // its written modifiers, a referenced one's is its metadata, and the grant is what makes the
    // assembly half of both reachable.
    //
    // UNTIL THIS, `nlc check` told a non-friend author the wrong thing at the wrong stage: the
    // analysis pass was clean and the refusal arrived from the columnar backend as
    // `NL103 … 'Handler.matchesQuery' … is not modeled`. THE EMIT-TIME REFUSAL IS UNCHANGED AND IS
    // STILL THE BACKSTOP — the SDK's emit-only path runs no analysis at all, so it is the only
    // refusal there, and a shape this probe cannot see still reaches it.
    func ReportFriendBarredMemberIfNeeded(receiverType: TypeInfo, member: MemberAccessExpression, includeStaticMembers: bool): bool {
        reflection := ResolveAliasAndMetadata(receiverType) as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        level := MemberAccessibility.Public
        if !AnalyzerMemberResolution.TryFindFriendBarredReflectedMemberLevel(reflection.Type, member.MemberName, includeStaticMembers, externalTypeProbeValue.Grants, out level) {
            return false
        }

        return diagnosticsValue.ReportInaccessibleDeclaredMember(
            member.MemberName,
            NullabilityMetadataReflection.FormatTypeInfo(receiverType),
            level,
            AccessingTypeDisplayName(),
            member.Line,
            spansValue.GetMemberNameColumn(member),
            Math.Max(1, member.MemberName.Length)
        )
    }

    // NL303, THE RENDERING, IN BOTH SHAPES. The report lands at the MEMBER NAME's column rather than
    // the node's, because underlining the receiver of `w.Sze` tells the developer the wrong thing.
    func ReportUndefinedMember(receiverType: TypeInfo, member: MemberAccessExpression, includeStaticMembers: bool) {
        ReportUndefinedMemberAt(receiverType, member.MemberName, member.Line, spansValue.GetMemberNameColumn(member), includeStaticMembers, null)
    }

    // PUBLISHED under its own name because three other paths — the object-initializer walk, the
    // attribute static-member walk and the SoA table named-initializer walk — report the same thing
    // about a position they computed themselves. `typeNameOverride` exists for exactly those: an open
    // generic reports the name the developer WROTE, not the substituted one.
    //
    // THE RICH SHAPE IS PREFERRED AND THE BARE ONE IS NOT A FALLBACK FOR FAILURE: a diagnostic with no
    // source line to underline (a synthesized node, or a unit with no file) still has a name and a
    // suggestion, and gets them.
    func ReportUndefinedMemberAt(receiverType: TypeInfo, memberName: string, line: int, column: int, includeStaticMembers: bool, typeNameOverride: string?) {
        length := Math.Max(1, memberName.Length)
        // The override is preferred and the formatter is NOT run when there is one — the C#'s `??`
        // was lazy, and an open generic's report must name what the developer wrote.
        typeName := ""
        if typeNameOverride != null {
            typeName = typeNameOverride
        } else {
            typeName = NullabilityMetadataReflection.FormatTypeInfo(receiverType)
        }

        similarMembers := FindSimilarMemberNames(receiverType, memberName, includeStaticMembers)
        sourceSnippet := diagnosticsValue.SourceSnippet(line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.UndefinedMember(currentFilePath, line, column, sourceSnippet, length, memberName, typeName, similarMembers))
            return
        }

        suggestion: string? = null
        if similarMembers.Count > 0 {
            suggestion = "Did you mean '" + similarMembers[0] + "'?"
        }

        diagnosticsValue.Report(ErrorCode.UndefinedMember, "Member '" + memberName + "' not found on type '" + typeName + "'", line, column, suggestion, length)
    }

    // THE DID-YOU-MEAN LIST, DRAWN FROM THE RECEIVER'S OWN MEMBERS. A receiver that offers NOTHING
    // gets no suggester at all rather than an empty one, which is the C#'s guard and matters because
    // the suggester's threshold is relative to the candidate pool.
    func FindSimilarMemberNames(receiverType: TypeInfo, memberName: string, includeStaticMembers: bool): List<string> {
        candidates := GetAvailableMemberNames(receiverType, includeStaticMembers)
        distinct := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)
        for candidate in candidates {
            if seen.Add(candidate) {
                distinct.Add(candidate)
            }
        }

        if distinct.Count == 0 {
            return new List<string>()
        }

        suggester := new SmartSuggester(distinct)
        return suggester.SuggestSimilarNames(memberName, 3)
    }

    // WHICH NAMES A RECEIVER OFFERS. A NULLABLE offers `Nullable<T>`'S OWN DECLARED NAMES ahead of
    // its inner type's, which is what makes `count.Vaule` suggest `Value` rather than an `int`
    // member — and it is the same order, read off the same metadata, that decides which of the two
    // types a name actually BINDS on, so the suggestion and the binding cannot disagree. A
    // built-in, generic or array receiver is converted to a CLR type and reflected; a reflected
    // receiver is reflected directly; and a SOURCE receiver answers from the declaration context —
    // plus `object`'s four members when the receiver is one that inherits them.
    func GetAvailableMemberNames(receiver: TypeInfo, includeStaticMembers: bool): List<string> {
        receiverType := ResolveAliasAndMetadata(receiver)
        nullableType := receiverType as NullableTypeInfo
        if nullableType != null {
            nullableMembers := NullableDefinitionMemberNames()
            innerMembers := GetAvailableMemberNames(nullableType.InnerType, includeStaticMembers)
            for innerMember in innerMembers {
                nullableMembers.Add(innerMember)
            }

            return nullableMembers
        }

        if receiverType as SimpleTypeInfo != null || receiverType as GenericTypeInfo != null || receiverType as ArrayTypeInfo != null {
            clrType := clrTypeConversionValue.TryConvertTypeInfoToClrType(receiverType)
            if clrType != null {
                return GetReflectionMemberNames(clrType, includeStaticMembers)
            }
        }

        reflectionType := receiverType as ReflectionTypeInfo
        if reflectionType != null {
            return GetReflectionMemberNames(reflectionType.Type, includeStaticMembers)
        }

        members := declarationContextValue.GetAvailableSourceMemberNames(receiverType, includeStaticMembers)
        if !includeStaticMembers && declarationContextValue.SourceObjectMembersApply(receiverType) {
            objectMembers := GetReflectionMemberNames(typeof(object), false)
            for objectMember in objectMembers {
                members.Add(objectMember)
            }
        }

        return members
    }

    // EVERY PUBLIC NAME A REFLECTED TYPE OFFERS, properties then fields then methods, de-duplicated in
    // first-occurrence order. SPECIAL-NAME methods are excluded: a developer who mistyped `Length`
    // should be offered `Length`, not `get_Length`.
    static func GetReflectionMemberNames(reflected: Type, includeStaticMembers: bool): List<string> {
        flags := BindingFlags.Public | BindingFlags.Instance
        if includeStaticMembers {
            flags = flags | BindingFlags.Static
        }

        // EVERY REFLECTED RECEIVER IS A LOCAL, NEVER AN INDEX EXPRESSION. `properties[i].get_Name()`
        // declines as an unmodeled instance call while `property.get_Name()` on the loop's own binding
        // does not — the receiver's SHAPE decides, not the member.
        names := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)
        properties := reflected.GetProperties(flags)
        for property in properties {
            AddDistinctName(names, seen, property.get_Name())
        }

        fields := reflected.GetFields(flags)
        for field in fields {
            AddDistinctName(names, seen, field.get_Name())
        }

        methods := reflected.GetMethods(flags)
        for method in methods {
            if !method.get_IsSpecialName() {
                AddDistinctName(names, seen, method.get_Name())
            }
        }

        return names
    }

    static func AddDistinctName(names: List<string>, seen: HashSet<string>, name: string) {
        if seen.Add(name) {
            names.Add(name)
        }
    }

    // NL103. A SoA table wrapper is a value view, so `table?.column` is not a safer `table.column` —
    // it is a shape the lowering has no meaning for.
    func ReportSoaTableNullConditionalAccess(member: MemberAccessExpression) {
        span := spansValue.GetExpressionDiagnosticSpan(member)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA tables cannot use null-conditional member access", span.Line, span.Column, "SoA table wrappers are value views; use direct table.member access.", span.Length)
    }

    // WHETHER THE DECLARING FILE IS IN ANOTHER PACKAGE, which is what turns a non-exported member
    // into NL308 rather than into nothing. Same file is never cross-package; two files are, exactly
    // when they declare different namespaces.
    func IsCrossPackageFile(declarationFile: string?): bool {
        currentFilePath := diagnosticsValue.CurrentFilePath
        if string.IsNullOrWhiteSpace(declarationFile) || string.IsNullOrWhiteSpace(currentFilePath) {
            return false
        }

        currentPath := Path.GetFullPath(currentFilePath)
        declarationPath := Path.GetFullPath(declarationFile)
        if string.Equals(currentPath, declarationPath, StringComparison.OrdinalIgnoreCase) {
            return false
        }

        currentNamespace := UnitNamespace()
        if currentNamespace == null {
            currentNamespace = projectSourcesValue.GetNamespaceForFile(currentPath)
        }

        declarationNamespace := projectSourcesValue.GetNamespaceForFile(declarationPath)
        return !string.Equals(currentNamespace, declarationNamespace, StringComparison.Ordinal)
    }

    // WHAT `a?.b` IS WORTH: one layer of nullability over what `a.b` would be — except that `void`,
    // `never`, `unknown` and an already-nullable type are left alone, because none of the four has a
    // nullable form that means anything.
    //
    // PUBLISHED because the index arm applies the identical rule to `a?[i]`.
    func MakeNullableResult(candidate: TypeInfo): TypeInfo {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        if BuiltInTypes.Is(resolved, BuiltInTypes.Void) || BuiltInTypes.Is(resolved, BuiltInTypes.Never) || resolved as UnknownTypeInfo != null || resolved as NullableTypeInfo != null {
            return candidate
        }

        return new NullableTypeInfo(candidate)
    }

    // The nullable unwrap `Analyzer.cs` performs before every structural question. Its C# original
    // has fourteen other callers and therefore could not move; its two-call body is reproduced rather
    // than reached back for, so nothing here re-enters C#.
    func NonNullableType(candidate: TypeInfo): TypeInfo {
        nullable := declarationContextValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
    }

    func UnitNamespace(): string? {
        return AnalyzerProjectSourceProvider.UnitNamespace(compilationUnitValue)
    }
}
