namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// THE ONE STEP A MEMBER ACCESS TAKES, THE TWO FORMS THAT TAKE NONE, AND THE ONE REPORT IT CANNOT
// RENDER ITSELF.
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
//   2  RENDER the undefined-member report for a receiver, a name and a position this owner has
//      ALREADY decided is worth reporting. WHETHER to report is this owner's — `ShouldReport` is the
//      rule and it lives here — and only the RENDERING is asked for, because the did-you-mean list
//      is built by enumerating the receiver's reflected properties and fields and reading their
//      names, and `PropertyInfo.Name` and `FieldInfo.Name` are not in the columnar catalog
//      (`MethodInfo.Name` and `EventInfo.Name` are, by explicit rows, because all four are inherited
//      from `MemberInfo` and only the named ones were published). Two catalog rows retire this kind;
//      until then it is a step and not a callback, exactly as slice 53's write-target reports are.
//
// TWO FORMS ANSWER BEFORE THE WALK STEP AND SO NEVER ASK FOR IT: an import ALIAS access
// (`Alias.Symbol`), which is a table lookup and not an expression at all, and a QUALIFIED EXTERNAL
// TYPE (`System.Text.StringBuilder`), whose receiver is a namespace prefix that would be meaningless
// to analyse. Both are decided before the first `NextStep` returns, which is why they cost no walk.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class MemberAccessRequest {
    Kind: int
    Node: Expression?
    ReceiverType: TypeInfo
    IncludeStaticMembers: bool

    constructor(kind: int, node: Expression?, receiverType: TypeInfo, includeStaticMembers: bool) {
        Kind = kind
        Node = node
        ReceiverType = receiverType
        IncludeStaticMembers = includeStaticMembers
    }
}

// THE WHOLE STATE, SUSPENDED ACROSS AT MOST TWO STEPS.
//
// `Member` is the node. `ResultType` is what the dispatch gets back, and it is NOT decided at
// `Begin`: a member access means nothing until its receiver is known, so every path but the two
// zero-step ones settles it in a phase that runs after a `Supply`.
//
// `Phase` runs 0 (nothing asked yet) → 1 (the receiver step is outstanding) → 2 (a report is owed)
// → 3 (the report step is outstanding) → 99 (finished). Phases 2 and 3 are reached only on the miss
// path, which slice 54's census measured at well under one resolution in a thousand. A node that is
// not a member access at all lands in 99 at `Begin` with `unknown`, because the dispatch never hands
// one over and a walk that guessed would hide the bug.
//
// `PendingReceiverType`, `PendingIncludeStatic` and `PendingMemberType` are the report's operands and
// the answer the walk is still holding while the report is outstanding. The answer must not be
// settled before the report runs: the report is the LAST observable effect of this arm, and settling
// first would move an alias resolution ahead of it.
class MemberAccessState {
    memberValue: MemberAccessExpression?

    Member: MemberAccessExpression? => memberValue

    Phase: int
    ResultType: TypeInfo
    PendingReceiverType: TypeInfo
    PendingIncludeStatic: bool
    PendingMemberType: TypeInfo

    constructor(member: MemberAccessExpression?) {
        memberValue = member
        Phase = 0
        ResultType = BuiltInTypes.Unknown
        PendingReceiverType = BuiltInTypes.Unknown
        PendingIncludeStatic = false
        PendingMemberType = BuiltInTypes.Unknown
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
        index := 0
        while index < names.Length {
            result.Add(names[index])
            index = index + 1
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

        if state.Phase == 2 {
            state.Phase = 3
            return new MemberAccessRequest(2, member, state.PendingReceiverType, state.PendingIncludeStatic)
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
        if TryResolveQualifiedExternalType(member.Object, out typeReceiver) {
            state.Phase = 99
            Finish(state, typeReceiver)
            if state.Phase == 2 {
                state.Phase = 3
                return new MemberAccessRequest(2, member, state.PendingReceiverType, state.PendingIncludeStatic)
            }

            return null
        }

        state.Phase = 1
        return new MemberAccessRequest(1, member.Object, BuiltInTypes.Unknown, false)
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Kind 1 answers the receiver's type; a null answer is
    // `unknown` rather than a missing one — the analyzer's expression walk never answers null, and a
    // walk that saw one would otherwise carry it into a report. Kind 2 answers nothing, and the only
    // work left after it is the answer this walk was holding back so the report stayed last.
    func Supply(state: MemberAccessState, answer: TypeInfo?) {
        if state.Phase == 3 {
            state.Phase = 99
            CompleteAfterReport(state)
            return
        }

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

    func CompleteAfterReport(state: MemberAccessState) {
        member := state.Member
        if member != null && member.IsNullConditional {
            state.ResultType = MakeNullableResult(state.PendingMemberType)
        } else {
            state.ResultType = state.PendingMemberType
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

        nullFlowValue.ReportPossibleNullAccess(member.Object, objectType, member.Line, member.Column, "dereference", member.IsNullConditional)
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
        memberType := memberResolutionValue.ResolveMember(receiverType, member.MemberName, includeStaticMembers, ambientValue.CurrentTypeName)
        if BuiltInTypes.IsUnknown(memberType) && ShouldReportUndefinedMember(receiverType, member.MemberName, includeStaticMembers) {
            // The report is OWED, not skipped: its rendering is kind 2, and the answer below is held
            // until the driver has performed it. Returning here is what preserves the C#'s `else if`:
            // the SoA column registration must not run when the report did.
            state.PendingReceiverType = receiverType
            state.PendingIncludeStatic = includeStaticMembers
            state.PendingMemberType = memberType
            state.Phase = 2
            return
        }

        soaRecordType := receiverType as SoaRecordTypeInfo
        if soaRecordType != null && AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, member.MemberName) != null {
            soaEscapeValue.RecordColumnMemberAccess(member)
        }

        if member.IsNullConditional {
            state.ResultType = MakeNullableResult(memberType)
        } else {
            state.ResultType = memberType
        }
    }

    // `HasValue` AND `Value` ON A NULLABLE, and nothing else — a third name falls through so member
    // resolution can answer it against the INNER type.
    //
    // The second way in is the one that carries the rule: a receiver whose type is a plain primitive
    // but whose SYMBOL was declared nullable and has been narrowed. `x!.Value` inside
    // `if x != null { … }` reaches here with `int`, not `int?`, and it must still mean the unwrap —
    // and it must NOT be warned about, because the narrowing already proved it safe. That is the
    // whole of `isNarrowedNullableOrigin`.
    func TryResolveNullableMemberAccess(member: MemberAccessExpression, objectType: TypeInfo, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown

        nullableType := objectType as NullableTypeInfo
        isNarrowedNullableOrigin := false
        if nullableType == null {
            identifier := member.Object as IdentifierExpression
            if identifier != null && IsPrimitiveLikeType(objectType) {
                origin := scopesValue.FindEnclosingNullableSymbol(identifier.Name)
                if origin != null {
                    nullableType = origin
                    isNarrowedNullableOrigin = true
                }
            }
        }

        if nullableType == null {
            return false
        }

        if member.MemberName == "HasValue" {
            memberType = BuiltInTypes.Bool
            return true
        }

        if member.MemberName == "Value" {
            if !isNarrowedNullableOrigin {
                diagnosticsValue.Report(ErrorCode.NullabilityWarning, "This '.Value' access can throw when the nullable value is absent", member.Line, spansValue.GetMemberNameColumn(member), "Prefer 'must value' for an explicit unwrap, or use 'match value { null => ..., inner => ... }' to handle both cases.", Math.Max(1, member.MemberName.Length))
            }

            memberType = nullableType.InnerType
            return true
        }

        return false
    }

    static func IsPrimitiveLikeType(candidate: TypeInfo): bool {
        return candidate as SimpleTypeInfo != null || candidate as ReflectionTypeInfo != null
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
            } else {
                resolvedType = BuiltInTypes.Unknown
            }

            return !BuiltInTypes.IsUnknown(resolvedType)
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            if TryResolveQualifiedExternalType(memberAccess, out resolvedType) {
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

    // A DOTTED NAME THAT IS A CLR TYPE — `System.Text.StringBuilder` — and the SEVEN vetoes that must
    // all miss before it is accepted. Their ORDER is the whole rule: every one of them names
    // something the developer wrote that would OUTRANK an assembly type of the same root, so a
    // project type, a local, a local type, a using alias, an import alias, an enclosing-type member
    // and a project function each stop the probe before it ever looks at metadata. Without them a
    // project function named `Log` would be shadowed by an assembly's `Log.Write`.
    //
    // The disjunction is written as sequential returns rather than a chain of `||` so the
    // short-circuit ORDER is visible: four of these seven vetoes ask a collaborator a question that
    // costs a scan, and the C# original's operator precedence is the only thing that kept them from
    // all running.
    func TryResolveQualifiedExternalType(expression: Expression, out resolvedType: TypeInfo): bool {
        resolvedType = BuiltInTypes.Unknown
        if expression as MemberAccessExpression == null {
            return false
        }

        qualifiedName := ""
        if !TryGetQualifiedExpressionTreeName(expression, out qualifiedName) {
            return false
        }

        rootName := ExternalQualifiedTypeResolver.RootName(qualifiedName)
        currentType := scopesValue.CurrentTypeScope()
        separator := qualifiedName.LastIndexOf(".")
        currentUnitNamespace := UnitNamespace()

        visibleNamespaces := AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(currentUnitNamespace, usingNamespacesValue)
        for visibleNamespace in visibleNamespaces {
            namespaceType: TypeInfo = BuiltInTypes.Unknown
            namespaceDeclaration: SymbolDeclaration? = null
            if projectDiscoveryValue.TryResolveProjectTypeInNamespace(rootName, visibleNamespace, currentUnitNamespace, out namespaceType, out namespaceDeclaration) {
                return false
            }
        }

        if scopesValue.LookupSymbol(rootName) != null || scopesValue.LookupType(rootName) != null || usingAliasesValue.ContainsKey(rootName) || importedSymbolsByAliasValue.ContainsKey(rootName) {
            return false
        }

        if currentType != null && !BuiltInTypes.IsUnknown(memberResolutionValue.ResolveMember(currentType, rootName, true, ambientValue.CurrentTypeName)) {
            return false
        }

        projectFunctionType: TypeInfo = BuiltInTypes.Unknown
        projectFunctionDeclaration: SymbolDeclaration? = null
        if identifierResolutionValue.TryResolveVisibleProjectFunction(rootName, out projectFunctionType, out projectFunctionDeclaration) {
            return false
        }

        if separator > 0 {
            qualifiedType: TypeInfo = BuiltInTypes.Unknown
            qualifiedDeclaration: SymbolDeclaration? = null
            if projectDiscoveryValue.TryResolveProjectTypeInNamespace(qualifiedName.Substring(separator + 1), qualifiedName.Substring(0, separator), currentUnitNamespace, out qualifiedType, out qualifiedDeclaration) {
                return false
            }
        }

        runtimeType: Type = typeof(object)
        if !ExternalQualifiedTypeResolver.TryResolve(mlcAssembliesValue, qualifiedName, out runtimeType) {
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
        isExported := false
        filePath: string? = null
        if TryFindMemberExportVisibility(objectType, member.MemberName, out isExported, out filePath) && IsCrossPackageFile(filePath) && !isExported {
            diagnosticsValue.ReportInaccessibleMember(member.MemberName, filePath, member.Line, spansValue.GetMemberNameColumn(member))
        }
    }

    func TryFindMemberExportVisibility(objectType: TypeInfo, memberName: string, out isExported: bool, out filePath: string?): bool {
        resolvedOwner := declarationContextValue.ResolveDeclaredAlias(objectType)
        selection := new AnalyzerMemberSelection()
        if declarationContextValue.TryFindMember(resolvedOwner, memberName, out selection) {
            isExported = selection.IsExported
            filePath = selection.FilePath
            return true
        }

        isExported = false
        filePath = null
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
                declaration = CreateSymbolDeclaration(selection.Member, selection.FilePath)
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
    func CreateSymbolDeclaration(member: DeclaredMemberInfo, filePath: string?): SymbolDeclaration {
        sourceText := projectSourcesValue.TryGetProjectSourceText(filePath)
        return new SymbolDeclaration(member.Name, filePath, member.Line, AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(sourceText, member.Name, member.Line, member.Column), member.KindName)
    }

    // WHETHER A MISS IS WORTH REPORTING, which is a question about the RECEIVER and not about the
    // name. The rule is confidence: report only when the analyzer can enumerate the receiver's
    // members well enough to be sure the name is absent.
    //   * `object` never reports — every name might be there through a cast.
    //   * a built-in primitive reports when its CLR type is reachable, and otherwise only for a name
    //     the built-in tables say it does NOT have.
    //   * a generic reports when it has a SOURCE definition or a reachable CLR type.
    //   * a reflected type reports only from assemblies whose member set is reliable.
    //   * every SOURCE-declared shape reports, because its member list is complete by construction.
    //   * a nullable and an oblivious ask about their inner type.
    //
    // PUBLISHED because the object-initializer and SoA-table-initializer paths ask the same question
    // about a name they could not resolve either.
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

            return clrTypeConversionValue.TryConvertTypeInfoToClrType(resolved) != null
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
