namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// THE TWO KINDS THE CONSTRUCTION FAMILY WALKS UNDER, AND WHY THERE ARE EXACTLY TWO.
//
// `new T(a) { M: v }` and `t with { M: v }` are the same question asked twice — what does an
// initializer entry mean against the member it names — so they are ONE owner with ONE protocol. What
// they do NOT share is the door their value walk goes through:
//
//   1  the ORDINARY walk. Every one of `new`'s seven walk sites is this: a plain expression analysis,
//      bracketed where a type is expected by the ambient slot, which THIS OWNER opens in the instant
//      the step is handed out and closes at the top of the `Supply` that consumes it. That is the
//      slice-51 bracket, and it applies because the C# bracketed a plain `AnalyzeExpression` and
//      never `AnalyzeExpressionWithExpectedType` — a slot-write has no lambda fork inside it.
//   2  the NAMED-EXPECTED-TYPE walk, which `with` and only `with` asks for. It is not kind 1 with an
//      extra argument: it forks to the lambda walk for a lambda value, which `t with { Fn: x => x }`
//      can have, so the owner cannot simulate it by writing the slot around a kind 1. This is
//      slice 52's distinction and these are the same two doors `DriveTargetTypedOperand` has.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class ConstructionRequest {
    Kind: int
    Node: Expression?
    ExpectedType: TypeInfo?

    constructor(kind: int, node: Expression?, expectedType: TypeInfo?) {
        Kind = kind
        Node = node
        ExpectedType = expectedType
    }
}

// THE WHOLE STATE, SUSPENDED ACROSS AS MANY STEPS AS THE CONSTRUCTION HAS OPERANDS.
//
// TWO COUNTERS RATHER THAN ONE, BECAUSE A SUSPENDED WALK MUST ANSWER TWO DIFFERENT QUESTIONS.
// `Stage` says WHERE IN THE FORM the walk is and only ever moves forward; `Phase` says WHICH STEP IS
// OUTSTANDING and returns to 0 the moment it is answered. Folding them into one number is what makes
// a resumable walk re-run a section it already finished, which is exactly the bug a `new int[n]` with
// no initializer would have hit: the length stage would have been re-entered after its own answer
// and reported the argument conflict a second time.
//
// `Stage`, for a `new`: 0 the constructor arguments, 1 the sized-array length, 2 the initializer
// entries, 3 finished. A `with` uses stage 2 alone — its target is its phase-11 step.
//
// `Phase`: 0 nothing outstanding; 1 a CONSTRUCTOR ARGUMENT (bracketed to `int` for a SoA capacity);
// 2 the SIZED-ARRAY LENGTH; 3 an INITIALIZER INDEX; 4 an INITIALIZER VALUE (bracketed when a member
// or element type was resolved for it); 11 the `with` TARGET; 12 a `with` PROPERTY INDEX; 13 a
// `with` PROPERTY VALUE; 99 finished.
//
// `ArgIndex` and `PropIndex` are the two cursors and `PropertyStarted` marks an entry whose
// once-per-entry work — the SoA shape refusal on a `with`, the index step on both — has already run.
// `PendingMemberType` and `PendingElementType` are the per-entry decisions taken BEFORE the value
// step is handed out and consumed by the `Supply` that answers it: they are how the NL202 front door
// survives suspension. `SavedExpectedType` is the ambient slot's previous value and is non-null only
// while a bracketed step is outstanding.
class ConstructionState {
    newValue: NewExpression?
    withValue: WithExpression?

    New: NewExpression? => newValue
    With: WithExpression? => withValue

    Phase: int
    Stage: int
    HeadResolved: bool
    ResultType: TypeInfo
    ConstructedType: TypeInfo
    UnionCaseName: string?
    SoaConstruction: SoaRecordTypeInfo?
    ConstructorArgumentTypes: List<TypeInfo>
    ArgIndex: int
    PropIndex: int
    PropertyStarted: bool
    ShapeUnsupported: bool
    SavedExpectedType: TypeInfo?
    PendingMemberType: TypeInfo?
    PendingElementType: TypeInfo?
    PendingTargetKind: string

    constructor(newExpression: NewExpression?, withExpression: WithExpression?) {
        newValue = newExpression
        withValue = withExpression
        Phase = 0
        Stage = 0
        HeadResolved = false
        ResultType = BuiltInTypes.Unknown
        ConstructedType = BuiltInTypes.Unknown
        UnionCaseName = null
        SoaConstruction = null
        ConstructorArgumentTypes = new List<TypeInfo>()
        ArgIndex = 0
        PropIndex = 0
        PropertyStarted = false
        ShapeUnsupported = false
        SavedExpectedType = null
        PendingMemberType = null
        PendingElementType = null
        PendingTargetKind = "array"
    }
}

// WHAT CONSTRUCTING A VALUE MEANS — the expression walk's `new` and `with` arms whole, the
// object-initializer rule they share, and the eleven refusals they own between them.
//
// THE NL202 FRONT DOOR IS THIS OWNER'S MOST IMPORTANT RESPONSIBILITY AND IT IS NOT A CONVENIENCE.
// `EmitValueCoercion` silently no-ops when it is handed a closed generic over an emitted user type,
// so nothing downstream will catch `Items: List<Rs>` stored into a `List<Pt>` field: the IL backend
// stores it unchecked and every later read is type-confused. The assignability gate on an
// initializer value — here for `new`, and again for `with` — is the ONLY guard, which is why it runs
// on every named entry whose member type resolved and why a member whose type could NOT be resolved
// reliably skips the check rather than guessing at it.
//
// WHAT IT OWNS. **NL203** (a target-typed `new` with nothing to infer from), **NL207** three times (a
// bare generic type constructed without arguments; a union case given the wrong number of type
// arguments; a generic union case given none and with no closed expected type to adopt), **NL303**
// twice in its own voice (a case the union does not declare, a property the case does not declare)
// and twice more through `AnalyzerMemberAccess`'s published rendering (an absent initializer member,
// on the open type and on the constructed one), **NL321** (a sized array that also passes
// constructor arguments), **NL402** twice (a SoA table constructed with the wrong argument count, or
// with a name that is not `capacity`), **NL309** (a readonly field written by an initializer),
// **NL301** twice for SoA table initializer shapes and once for a SoA table member written directly,
// and **NL202** four times — a non-`int` array length, an element that does not fit its array or
// collection target, and the two initializer-value mismatches this owner exists to catch.
//
// WHAT IT DOES NOT OWN: every SoA row escape and direct-column value escape it raises is
// `AnalyzerSoaEscape`'s and is merely asked, which makes this the SIXTH consecutive family whose SoA
// reports belong elsewhere; the undefined-member RENDERING is `AnalyzerMemberAccess`'s, published in
// slice 56 for exactly these three callers.
//
// THE READONLY-FIELD FACT IS ASKED OF THE FAMILY THAT OWNS IT. It was reproduced here while
// `Analyzer.cs` still held the write-target family; that family is now `AnalyzerWriteTargets` and the
// duplicate is gone, which is the end-state the slice that reproduced it named.
class AnalyzerConstruction {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeResolverValue: AnalyzerTypeResolver
    typeSubstitutionValue: AnalyzerTypeSubstitution
    projectDiscoveryValue: AnalyzerProjectTypeDiscovery
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape
    memberAccessValue: AnalyzerMemberAccess
    arrayLiteralValue: AnalyzerArrayLiteral
    constantFactsValue: AnalyzerConstantExpressionFacts
    assignabilityValue: AnalyzerAssignability
    memberResolutionValue: AnalyzerMemberResolution
    matchExhaustivenessValue: AnalyzerMatchExhaustiveness
    clrTypeConversionValue: AnalyzerClrTypeConversion
    writeTargetsValue: AnalyzerWriteTargets

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeResolver: AnalyzerTypeResolver, typeSubstitution: AnalyzerTypeSubstitution, projectDiscovery: AnalyzerProjectTypeDiscovery, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape, memberAccess: AnalyzerMemberAccess, arrayLiteral: AnalyzerArrayLiteral, constantFacts: AnalyzerConstantExpressionFacts, assignability: AnalyzerAssignability, memberResolution: AnalyzerMemberResolution, matchExhaustiveness: AnalyzerMatchExhaustiveness, clrTypeConversion: AnalyzerClrTypeConversion, writeTargets: AnalyzerWriteTargets) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        typeSubstitutionValue = typeSubstitution
        projectDiscoveryValue = projectDiscovery
        ambientValue = ambient
        soaEscapeValue = soaEscape
        memberAccessValue = memberAccess
        arrayLiteralValue = arrayLiteral
        constantFactsValue = constantFacts
        assignabilityValue = assignability
        memberResolutionValue = memberResolution
        matchExhaustivenessValue = matchExhaustiveness
        clrTypeConversionValue = clrTypeConversion
        writeTargetsValue = writeTargets
    }

    // THE `new` DOOR.
    func Begin(expression: Expression): ConstructionState {
        node := expression as NewExpression
        state := new ConstructionState(node, null)
        if node == null {
            state.Phase = 99
        }

        return state
    }

    // THE `with` DOOR. Its first step is the target, and it is handed out immediately: unlike `new`
    // there is nothing to decide before the target has answered.
    func BeginWith(expression: Expression): ConstructionState {
        node := expression as WithExpression
        state := new ConstructionState(null, node)
        if node == null {
            state.Phase = 99
            return state
        }

        state.Phase = 11
        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    //
    // Every bracket opens HERE, in the same instant the step is handed out, and closes at the top of
    // the `Supply` that consumes its answer — an owner that opened it earlier would leave the slot
    // written across a gap the C# never had.
    func NextStep(state: ConstructionState): ConstructionRequest? {
        if state.Phase == 99 {
            return null
        }

        if state.With != null {
            return NextWithStep(state)
        }

        node := state.New
        if node == null {
            state.Phase = 99
            return null
        }

        if !state.HeadResolved {
            state.HeadResolved = true
            ResolveConstructedType(state, node)
        }

        if state.Stage == 0 {
            argumentStep := NextConstructorArgumentStep(state, node)
            if argumentStep != null {
                return argumentStep
            }

            ValidateSoaRecordConstructionIfNeeded(state, node)
            state.Stage = 1
        }

        if state.Stage == 1 {
            state.Stage = 2
            lengthStep := NextArrayLengthStep(state, node)
            if lengthStep != null {
                return lengthStep
            }
        }

        return NextInitializerStep(state, node)
    }

    // THE ANSWER TO THE OUTSTANDING STEP. A null answer is `unknown` rather than a missing one — the
    // analyzer's expression walk never answers null, and a walk that saw one would carry it into a
    // report.
    func Supply(state: ConstructionState, answer: TypeInfo?) {
        answered: TypeInfo = BuiltInTypes.Unknown
        if answer != null {
            answered = answer
        }

        if state.Phase == 1 {
            ConstructorArgumentAnswered(state, answered)
            return
        }

        if state.Phase == 2 {
            ArrayLengthAnswered(state, answered)
            return
        }

        if state.Phase == 3 {
            InitializerIndexAnswered(state, answered)
            return
        }

        if state.Phase == 4 {
            InitializerValueAnswered(state, answered)
            return
        }

        if state.Phase == 11 {
            WithTargetAnswered(state, answered)
            return
        }

        if state.Phase == 12 {
            WithIndexAnswered(state, answered)
            return
        }

        if state.Phase == 13 {
            WithValueAnswered(state, answered)
        }
    }

    func Result(state: ConstructionState): TypeInfo {
        return state.ResultType
    }

    // ------------------------------------------------------------------------------------------
    // THE `new` HEAD: WHAT TYPE IS BEING CONSTRUCTED.
    // ------------------------------------------------------------------------------------------

    // A target-typed `new` adopts the ambient expected type and is refused when there is none —
    // except for an anonymous object, which the backend synthesizes from its initializer and which is
    // therefore intentionally allowed to have no target at all.
    func ResolveConstructedType(state: ConstructionState, node: NewExpression) {
        state.UnionCaseName = null
        if node.Type == null {
            expected := ambientValue.CurrentExpectedType
            if expected == null {
                if !IsAnonymousObjectCreation(node) {
                    ReportCannotInferTargetTypedNew(node)
                }

                state.ConstructedType = BuiltInTypes.Unknown
            } else {
                state.ConstructedType = expected
            }
        } else {
            state.ConstructedType = typeResolverValue.ResolveDeclaredType(node.Type)
            ReportBareGenericConstructionIfNeeded(state, node)
            ReportConstructionConstraintViolationsIfNeeded(state, node)
            ResolveUnionCaseConstruction(state, node)
        }

        state.SoaConstruction = declarationContextValue.ResolveDeclaredAlias(NonNullableType(state.ConstructedType)) as SoaRecordTypeInfo
        state.ResultType = state.ConstructedType
    }

    // A LOCALLY-DECLARED GENERIC TYPE CONSTRUCTED WITHOUT TYPE ARGUMENTS used to emit an open-type
    // token and throw `BadImageFormatException` at run time. N# does not infer a class's type
    // arguments from its constructor arguments — they are written or they are missing.
    func ReportBareGenericConstructionIfNeeded(state: ConstructionState, node: NewExpression) {
        bareTypeReference := node.Type as SimpleTypeReference
        if bareTypeReference == null || bareTypeReference.Name.Contains('.') {
            return
        }

        requiredCount := AnalyzerTypeReferenceFacts.GenericHeadArity(state.ConstructedType)
        if requiredCount <= 0 {
            return
        }

        diagnosticsValue.Report(ErrorCode.InvalidTypeArgument, "Generic type '" + bareTypeReference.Name + "' requires " + requiredCount.ToString() + " type argument(s)", bareTypeReference.Line, bareTypeReference.Column, "Specify them explicitly: 'new " + bareTypeReference.Name + "<...>(...)'", bareTypeReference.Name.Length)
    }

    // `new Box<string>()` UNDER `class Box<T> where T : struct` WAS ACCEPTED IN SILENCE. NL208 was
    // reported at call sites and nowhere else, so a type argument that violated its own declaration's
    // `where` clause reached the emitter unchallenged. The predicates and the sentence are shared with
    // the call-site reporter (`AnalyzerGenericConstraintChecks`); only the suggestion differs, because
    // nothing is being passed here.
    func ReportConstructionConstraintViolationsIfNeeded(state: ConstructionState, node: NewExpression) {
        generic := state.ConstructedType as GenericTypeInfo
        if generic == null {
            return
        }

        definition := generic.GenericDefinition
        if definition == null {
            return
        }

        constraints := AnalyzerGenericConstraintChecks.ConstraintsOf(definition)
        if constraints.Length == 0 {
            return
        }

        substitution := declarationContextValue.CreateGenericSubstitution(definition, generic.TypeArguments)
        // Anchored on the written type reference, the way the bare-generic report above is, so the
        // marker sits under `Box<string>` rather than under the whole `new` expression.
        line := node.Line
        column := node.Column
        genericReference := node.Type as GenericTypeReference
        if genericReference != null {
            line = genericReference.Line
            column = genericReference.Column
        }

        AnalyzerGenericConstraintChecks.ReportTypeArgumentViolations(constraints, substitution, generic.Name, typeResolverValue, assignabilityValue, diagnosticsValue, line, column, MaxSpanLength(generic.Name))
    }

    static func MaxSpanLength(name: string): int {
        if name.Length < 1 {
            return 1
        }

        return name.Length
    }

    // A QUALIFIED NAME MAY BE A UNION CASE (`new Result.Success<int> { ... }`), and the union it names
    // may live in another file with no import — project auto-discovery resolves it exactly as a bare
    // type reference would. Constructing a case the union does not declare used to surface as an
    // internal emit failure; it is reported here the way the pattern path reports it.
    func ResolveUnionCaseConstruction(state: ConstructionState, node: NewExpression) {
        qualifiedCaseName: string? = null
        caseTypeArguments: List<TypeReference>? = null
        simpleCaseRef := node.Type as SimpleTypeReference
        if simpleCaseRef != null && simpleCaseRef.Name.Contains('.') {
            qualifiedCaseName = simpleCaseRef.Name
        } else {
            genericCaseRef := node.Type as GenericTypeReference
            if genericCaseRef != null && genericCaseRef.Name.Contains('.') {
                qualifiedCaseName = genericCaseRef.Name
                caseTypeArguments = genericCaseRef.TypeArguments
            }
        }

        if qualifiedCaseName == null {
            return
        }

        parts := qualifiedCaseName.Split('.')
        if parts.Length != 2 {
            return
        }

        unionBase: UnionTypeInfo? = scopesValue.LookupType(parts[0]) as UnionTypeInfo
        if unionBase == null {
            unionBase = LookupProjectUnion(node, parts[0])
        }

        if unionBase == null {
            return
        }

        if AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(unionBase, qualifiedCaseName) != null {
            state.ConstructedType = ResolveUnionCaseConstructionType(node, unionBase, parts[0], qualifiedCaseName, caseTypeArguments)
            state.UnionCaseName = qualifiedCaseName
            return
        }

        ReportUndeclaredUnionCase(node, unionBase, parts[0], parts[1], qualifiedCaseName)
        state.ConstructedType = unionBase
    }

    // The union may be declared in a file this one never imported. An INACCESSIBLE one is reported
    // once and marked, so the type resolver does not accuse the same name a second time.
    func LookupProjectUnion(node: NewExpression, unionName: string): UnionTypeInfo? {
        candidate: TypeInfo = BuiltInTypes.Unknown
        declaration: SymbolDeclaration? = null
        inaccessibleFile: string? = null
        if projectDiscoveryValue.ResolveVisibleProjectType(unionName, memberAccessValue.UnitNamespace(), node.Line > 0, out candidate, out declaration, out inaccessibleFile) {
            return candidate as UnionTypeInfo
        }

        if inaccessibleFile != null {
            diagnosticsValue.ReportInaccessibleMember(unionName, inaccessibleFile, node.Line, node.Column)
            typeResolverValue.MarkUnresolvedTypeReported(unionName, node.Line, node.Column)
        }

        return null
    }

    // THE WRITTEN TYPE REFERENCE'S SPAN. A target-typed `new` has no type reference at all, so the
    // fallback underlines the `new` keyword — the only thing the developer wrote.
    func TypeReferenceSpan(node: NewExpression): SourceSpan {
        typeReference := node.Type
        if typeReference == null {
            return SourceSpan.FromStartAndLength(node.Line, node.Column, 3)
        }

        return TypeReferenceFacts.GetStartSpan(typeReference)
    }

    // NL303 in this arm's own voice: the receiver is a UNION and the missing name is a CASE, so the
    // did-you-mean list is drawn from the union's cases and the suggestion is written qualified.
    func ReportUndeclaredUnionCase(node: NewExpression, unionBase: UnionTypeInfo, unionName: string, caseName: string, qualifiedCaseName: string) {
        caseNames := new List<string>()
        for unionCase in unionBase.Declaration.Cases {
            caseNames.Add(unionCase.Name)
        }

        suggestion: string? = null
        if caseNames.Count > 0 {
            // The suggester is a LOCAL and the call is a second statement: a call chained straight
            // off a `new` expression is not a shape the columnar front end parses.
            caseSuggester := new SmartSuggester(caseNames)
            similarCases := caseSuggester.SuggestSimilarNames(caseName, 3)
            if similarCases.Count > 0 {
                suggestion = "Did you mean '" + unionName + "." + similarCases[0] + "'?"
            }
        }

        caseSpan := TypeReferenceSpan(node)
        diagnosticsValue.Report(ErrorCode.UndefinedMember, "'" + caseName + "' is not a case of union '" + unionName + "' — check the union definition for available cases", caseSpan.StartLine, caseSpan.StartColumn, suggestion, qualifiedCaseName.Length)
    }

    // THE STATIC TYPE OF A UNION CASE CONSTRUCTION. For a non-generic union that is the union itself;
    // for a generic one the arguments come after the CASE name (`new Result.Success<int> { ... }`) or
    // are adopted from a closed expected type (`return new Option.None` inside `Option<User>`), and
    // the answer is the closed instantiation so it lines up with the annotation.
    func ResolveUnionCaseConstructionType(node: NewExpression, unionType: UnionTypeInfo, unionName: string, qualifiedCaseName: string, typeArguments: List<TypeReference>?): TypeInfo {
        typeParameters := unionType.Declaration.TypeParameters
        arity := 0
        if typeParameters != null {
            arity = typeParameters.Count
        }

        typeRefSpan := TypeReferenceSpan(node)
        if typeArguments != null && typeArguments.Count > 0 {
            resolvedArguments := new List<TypeInfo>()
            for typeArgument in typeArguments {
                resolvedArguments.Add(typeResolverValue.ResolveType(typeArgument))
            }

            if resolvedArguments.Count != arity {
                message := "Generic union '" + unionName + "' takes " + arity.ToString() + " type argument(s), but " + resolvedArguments.Count.ToString() + " were provided"
                suggestion := "Match the declaration's type parameter count for '" + unionName + "'"
                if arity == 0 {
                    message = "Union '" + unionName + "' is not generic, but " + resolvedArguments.Count.ToString() + " type argument(s) were provided"
                    suggestion = "Remove the type arguments: 'new " + qualifiedCaseName + " { ... }'"
                }

                diagnosticsValue.Report(ErrorCode.InvalidTypeArgument, message, typeRefSpan.StartLine, typeRefSpan.StartColumn, suggestion, qualifiedCaseName.Length)
                return unionType
            }

            return new GenericTypeInfo(unionName, resolvedArguments, unionType)
        }

        if arity == 0 {
            return unionType
        }

        expected := ambientValue.CurrentExpectedType as GenericTypeInfo
        if expected != null && expected.Name == unionName && expected.TypeArguments.Count == arity {
            return expected
        }

        diagnosticsValue.Report(ErrorCode.InvalidTypeArgument, "Generic union '" + unionName + "' requires " + arity.ToString() + " type argument(s)", typeRefSpan.StartLine, typeRefSpan.StartColumn, "Specify them after the case name: 'new " + qualifiedCaseName + "<...> { ... }'", qualifiedCaseName.Length)
        return unionType
    }

    // AN ANONYMOUS OBJECT IS A TYPELESS `new` WHOSE ENTRIES ARE ALL NAMED. It is the one shape that
    // needs no target, because the backend synthesizes the concrete shape from the initializer.
    static func IsAnonymousObjectCreation(node: NewExpression): bool {
        if node.Type != null || node.ConstructorArguments.Count != 0 || node.Initializer == null {
            return false
        }

        for property in node.Initializer.Properties {
            if property.Name == null || property.IndexExpression != null {
                return false
            }
        }

        return true
    }

    // NL203. The shape is echoed back with the parentheses the developer actually wrote.
    func ReportCannotInferTargetTypedNew(node: NewExpression) {
        shape := "new(...)"
        if node.ConstructorArguments.Count == 0 {
            shape = "new()"
        }

        diagnosticsValue.Report(ErrorCode.CannotInferType, "I can't figure out what type '" + shape + "' should create here — add a type annotation or write the type after 'new'", node.Line, node.Column, "For example, use `value: Person = new()` when the target type is clear, or `new Person()` when it is not.", 3)
    }

    // ------------------------------------------------------------------------------------------
    // THE `new` OPERANDS: CONSTRUCTOR ARGUMENTS, SIZED-ARRAY LENGTH, INITIALIZER ENTRIES.
    // ------------------------------------------------------------------------------------------

    // A SoA table's SINGLE argument is its capacity and is walked expecting an `int`; every other
    // constructor argument is walked with the slot exactly as it was found.
    func NextConstructorArgumentStep(state: ConstructionState, node: NewExpression): ConstructionRequest? {
        if state.ArgIndex >= node.ConstructorArguments.Count {
            return null
        }

        argument := node.ConstructorArguments[state.ArgIndex]
        expectedArgumentType: TypeInfo? = null
        if state.SoaConstruction != null && node.ConstructorArguments.Count == 1 && state.ArgIndex == 0 {
            expectedArgumentType = BuiltInTypes.Int
        }

        state.Phase = 1
        state.SavedExpectedType = ambientValue.EnterExpectedTypeIfProvided(expectedArgumentType)
        return new ConstructionRequest(1, argument.Value, null)
    }

    func ConstructorArgumentAnswered(state: ConstructionState, argumentType: TypeInfo) {
        ambientValue.ExitExpectedType(state.SavedExpectedType)
        state.SavedExpectedType = null

        node := state.New
        if node == null {
            state.Phase = 99
            return
        }

        argument := node.ConstructorArguments[state.ArgIndex]
        state.ConstructorArgumentTypes.Add(argumentType)
        state.ArgIndex = state.ArgIndex + 1
        state.Phase = 0
        soaEscapeValue.ReportSoaRowEscapeIfNeeded(argument.Value, argumentType, "passed as a constructor argument")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(argument.Value, "passed as a constructor argument")
    }

    // A SIZED ARRAY (`new int[n]`) TAKES NO CONSTRUCTOR ARGUMENTS, and its length is an `int`. A SoA
    // escape on the length is a MORE useful diagnostic than the generic mismatch, so it suppresses it
    // — and the two escape questions short-circuit exactly as the C#'s `||` did.
    func NextArrayLengthStep(state: ConstructionState, node: NewExpression): ConstructionRequest? {
        if node.ArrayLengthExpression == null {
            return null
        }

        if node.ConstructorArguments.Count != 0 {
            diagnosticsValue.Report(ErrorCode.InvalidSizedArrayConstructorArguments, "Sized array allocation cannot also pass constructor arguments", node.Line, node.Column, "Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.", 3)
        }

        state.Phase = 2
        return new ConstructionRequest(1, node.ArrayLengthExpression, null)
    }

    func ArrayLengthAnswered(state: ConstructionState, lengthType: TypeInfo) {
        node := state.New
        if node == null || node.ArrayLengthExpression == null {
            state.Phase = 99
            return
        }

        lengthExpression := node.ArrayLengthExpression
        state.Phase = 0
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(lengthExpression, lengthType, "used as an array length") {
            return
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(lengthExpression, "used as an array length") {
            return
        }

        if BuiltInTypes.IsNot(lengthType, BuiltInTypes.Int) {
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "Array length must be an int, not '" + TypeText(lengthType) + "'", lengthExpression.Line, lengthExpression.Column, null, 0)
        }
    }

    // THE INITIALIZER CURSOR. An indexer entry's index is walked first and separately, then the
    // entry's value goes through the object-initializer rule.
    func NextInitializerStep(state: ConstructionState, node: NewExpression): ConstructionRequest? {
        if node.Initializer == null {
            state.Phase = 99
            return null
        }

        properties := node.Initializer.Properties
        if state.PropIndex >= properties.Count {
            state.Phase = 99
            return null
        }

        property := properties[state.PropIndex]
        if !state.PropertyStarted {
            state.PropertyStarted = true
            if property.IndexExpression != null {
                state.Phase = 3
                return new ConstructionRequest(1, property.IndexExpression, null)
            }
        }

        return BeginInitializerValueStep(state, property)
    }

    func InitializerIndexAnswered(state: ConstructionState, indexType: TypeInfo) {
        node := state.New
        if node == null || node.Initializer == null {
            state.Phase = 99
            return
        }

        state.Phase = 0
        property := node.Initializer.Properties[state.PropIndex]
        indexExpression := property.IndexExpression
        if indexExpression == null {
            return
        }

        soaEscapeValue.ReportSoaRowEscapeIfNeeded(indexExpression, indexType, "used as an initializer index")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(indexExpression, "used as an initializer index")
    }

    // ONE OBJECT-INITIALIZER ENTRY, UP TO THE POINT ITS VALUE MUST BE WALKED. Everything decided here
    // — whether the entry is a named member write at all, whether the member exists, what its
    // declared type is, and therefore whether the NL202 gate applies — is decided BEFORE the value is
    // handed out, because the walk suspends across it.
    func BeginInitializerValueStep(state: ConstructionState, property: PropertyInitializer): ConstructionRequest? {
        state.Phase = 4
        state.PendingMemberType = null
        state.PendingElementType = null
        state.PendingTargetKind = "array"

        constructedType := state.ConstructedType
        if property.Name == null || property.IndexExpression != null {
            ReportUnsupportedSoaTableInitializerShapeIfNeeded(constructedType, property, "object-initializer")
            if property.Name == null && property.IndexExpression == null {
                expectedElement: TypeInfo = BuiltInTypes.Unknown
                resolvedTargetKind := "array"
                if arrayLiteralValue.TryGetExpectedElementType(constructedType, out expectedElement, out resolvedTargetKind) {
                    state.PendingElementType = expectedElement
                    state.PendingTargetKind = resolvedTargetKind
                }
            }

            state.SavedExpectedType = ambientValue.EnterExpectedTypeIfProvided(state.PendingElementType)
            return new ConstructionRequest(1, property.Value, null)
        }

        nameLine := property.Value.Line
        nameColumn := property.Value.Column
        if property.NameLine > 0 {
            nameLine = property.NameLine
            nameColumn = property.NameColumn
        }

        if ReportSoaTableNamedInitializerIfNeeded(constructedType, property.Name, nameLine, nameColumn) {
            return new ConstructionRequest(1, property.Value, null)
        }

        CheckReadonlyObjectInitializerField(constructedType, property.Name, nameLine, nameColumn)

        memberType: TypeInfo = BuiltInTypes.Unknown
        if !TryResolveObjectInitializerMemberType(constructedType, state.UnionCaseName, property.Name, nameLine, nameColumn, out memberType) {
            return new ConstructionRequest(1, property.Value, null)
        }

        // The member's declared type is the expected type for the value — target-typed `new`, integer
        // literal sizing, lambda inference and generic union case inference all read it.
        state.PendingMemberType = memberType
        state.SavedExpectedType = ambientValue.EnterExpectedType(memberType)
        return new ConstructionRequest(1, property.Value, null)
    }

    // THE ENTRY'S VALUE HAS ANSWERED. The bracket closes FIRST, before any report runs, because every
    // one of these reports ran with the slot already restored.
    func InitializerValueAnswered(state: ConstructionState, valueType: TypeInfo) {
        ambientValue.ExitExpectedType(state.SavedExpectedType)
        state.SavedExpectedType = null

        node := state.New
        if node == null || node.Initializer == null {
            state.Phase = 99
            return
        }

        property := node.Initializer.Properties[state.PropIndex]
        state.PropIndex = state.PropIndex + 1
        state.PropertyStarted = false
        state.Phase = 0

        if property.Name == null || property.IndexExpression != null {
            ElementEntryAnswered(state, property, valueType)
            return
        }

        if state.PendingMemberType == null {
            return
        }

        memberType := state.PendingMemberType
        if valueType as SoaRowTypeInfo != null {
            soaEscapeValue.ReportSoaRowEscape(property.Value, "stored in an object initializer")
        } else {
            soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(property.Value, "stored in an object initializer")
        }

        // THE NL202 FRONT DOOR. Nothing downstream repeats this check.
        if assignabilityValue.IsAssignable(memberType, valueType) {
            return
        }

        ReportInitializerMemberMismatch(property, memberType, valueType)
    }

    // AN UNNAMED OR INDEXED ENTRY IS A COLLECTION/ARRAY ELEMENT, not a member write, so it is held to
    // the target's ELEMENT type and scolded with the word that names the target it missed.
    func ElementEntryAnswered(state: ConstructionState, property: PropertyInitializer, valueType: TypeInfo) {
        soaEscapeValue.ReportSoaRowEscapeIfNeeded(property.Value, valueType, "stored in an initializer")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(property.Value, "stored in an initializer")
        if state.PendingElementType == null {
            return
        }

        expectedElementType := state.PendingElementType
        if assignabilityValue.IsAssignable(expectedElementType, valueType) {
            return
        }

        elementLabel := "Array initializer element"
        if state.PendingTargetKind == "collection" {
            elementLabel = "Collection initializer element"
        }

        span := spansValue.GetExpressionDiagnosticSpan(property.Value)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, elementLabel + " is '" + TypeText(valueType) + "', but the target " + state.PendingTargetKind + " expects '" + TypeText(expectedElementType) + "'", span.Line, span.Column, null, span.Length)
    }

    // NL202, IN TWO RENDERINGS, AND THE RICH ONE IS PREFERRED. A diagnostic with a source line to
    // underline gets the full cluster rendering; one without a file or a snippet — a synthesized node,
    // or a unit with no path — carries the same sentence without the snippet. BOTH NAME THE MEMBER,
    // THE MEMBER TYPE AND THE VALUE TYPE: the cluster fields are added to that sentence, never in
    // place of it.
    func ReportInitializerMemberMismatch(property: PropertyInitializer, memberType: TypeInfo, valueType: TypeInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(property.Value)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        message := "'" + property.Name + "' is typed as '" + TypeText(memberType) + "', but the value is '" + TypeText(valueType) + "'"
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.TypeMismatch(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, TypeText(valueType), TypeText(memberType), message))
            return
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, message, span.Line, span.Column, null, span.Length)
    }

    // ------------------------------------------------------------------------------------------
    // THE `with` FORM: THE SAME INITIALIZER RULE OVER AN EXISTING VALUE.
    // ------------------------------------------------------------------------------------------

    func NextWithStep(state: ConstructionState): ConstructionRequest? {
        node := state.With
        if node == null {
            state.Phase = 99
            return null
        }

        if state.Phase == 11 {
            return new ConstructionRequest(1, node.Target, null)
        }

        if state.PropIndex >= node.Properties.Count {
            state.Phase = 99
            return null
        }

        property := node.Properties[state.PropIndex]
        if !state.PropertyStarted {
            state.PropertyStarted = true
            // THE SHAPE REFUSAL IS ASKED BEFORE THE INDEX IS WALKED, which is the order the C# asked
            // it in and therefore the order the developer reads the two diagnostics in.
            state.ShapeUnsupported = ReportUnsupportedSoaTableInitializerShapeIfNeeded(state.ConstructedType, property, "`with`")
            if property.IndexExpression != null {
                state.Phase = 12
                return new ConstructionRequest(1, property.IndexExpression, null)
            }
        }

        return BeginWithValueStep(state, property)
    }

    // THE TARGET HAS ANSWERED. A SoA row view or a direct column cannot be `with`-ed at all, and when
    // either escapes the target type is degraded to `unknown` so no member is then accused of a
    // mismatch it never had a chance at.
    func WithTargetAnswered(state: ConstructionState, targetType: TypeInfo) {
        node := state.With
        if node == null {
            state.Phase = 99
            return
        }

        state.Phase = 0
        targetIsSoaRow := soaEscapeValue.ReportSoaRowEscapeIfNeeded(node.Target, targetType, "used as a with target")
        targetIsSoaDirectColumn := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(node.Target, "used as a with target")
        if targetIsSoaRow || targetIsSoaDirectColumn {
            state.ConstructedType = BuiltInTypes.Unknown
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        state.ConstructedType = targetType
        state.ResultType = targetType
    }

    func WithIndexAnswered(state: ConstructionState, indexType: TypeInfo) {
        node := state.With
        if node == null {
            state.Phase = 99
            return
        }

        state.Phase = 0
        property := node.Properties[state.PropIndex]
        indexExpression := property.IndexExpression
        if indexExpression == null {
            return
        }

        soaEscapeValue.ReportSoaRowEscapeIfNeeded(indexExpression, indexType, "used as a with initializer index")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(indexExpression, "used as a with initializer index")
    }

    // ONE `with` ENTRY. The SoA shape refusal is asked FIRST and its answer GATES the member lookup —
    // a refused shape is not then also accused of naming a member that does not exist. The value goes
    // through kind 2 when a member type resolved, because a `with` value may be a lambda.
    func BeginWithValueStep(state: ConstructionState, property: PropertyInitializer): ConstructionRequest? {
        state.Phase = 13
        state.PendingMemberType = null

        targetType := state.ConstructedType
        if !state.ShapeUnsupported && property.Name != null && property.IndexExpression == null {
            nameLine := property.Value.Line
            nameColumn := property.Value.Column
            if property.NameLine > 0 {
                nameLine = property.NameLine
                nameColumn = property.NameColumn
            }

            if !ReportSoaTableNamedInitializerIfNeeded(targetType, property.Name, nameLine, nameColumn) {
                resolvedMemberType: TypeInfo = BuiltInTypes.Unknown
                if TryResolveObjectInitializerMemberType(targetType, null, property.Name, nameLine, nameColumn, out resolvedMemberType) {
                    state.PendingMemberType = resolvedMemberType
                }
            }
        }

        if state.PendingMemberType == null {
            return new ConstructionRequest(1, property.Value, null)
        }

        return new ConstructionRequest(2, property.Value, state.PendingMemberType)
    }

    // THE `with` VALUE HAS ANSWERED. Unlike the object-initializer form the mismatch is suppressed
    // when the value itself escaped — a SoA escape has already been reported about it and a second
    // report on the same expression helps nobody.
    func WithValueAnswered(state: ConstructionState, valueType: TypeInfo) {
        node := state.With
        if node == null {
            state.Phase = 99
            return
        }

        property := node.Properties[state.PropIndex]
        state.PropIndex = state.PropIndex + 1
        state.PropertyStarted = false
        state.Phase = 0

        valueIsSoaRow := soaEscapeValue.ReportSoaRowEscapeIfNeeded(property.Value, valueType, "stored in a with expression")
        valueIsSoaDirectColumn := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(property.Value, "stored in a with expression")
        if state.PendingMemberType == null || valueIsSoaRow || valueIsSoaDirectColumn {
            return
        }

        memberType := state.PendingMemberType
        // THE NL202 FRONT DOOR, AGAIN. A `with` writes the same fields an initializer does.
        if assignabilityValue.IsAssignable(memberType, valueType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(property.Value)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "'" + property.Name + "' is typed as '" + TypeText(memberType) + "', but the value is '" + TypeText(valueType) + "'", span.Line, span.Column, null, span.Length)
    }

    // ------------------------------------------------------------------------------------------
    // THE RULE BOTH FORMS SHARE: WHAT A NAMED INITIALIZER ENTRY'S MEMBER TYPE IS.
    // ------------------------------------------------------------------------------------------

    // Returns false when the member's type cannot be determined RELIABLY — an unknown or
    // non-member-bearing receiver, a member inherited past an open generic declaration, a method
    // group — so the caller skips the assignability check instead of guessing. When the member is
    // CONCLUSIVELY absent it reports NL303 through the member arm's published rendering; that case
    // used to surface as an internal emit failure.
    func TryResolveObjectInitializerMemberType(constructedType: TypeInfo, unionCaseName: string?, memberName: string, nameLine: int, nameColumn: int, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown

        // A union case construction's members live on the CASE, typed under the closed
        // instantiation's substitution. Checked before the generic branch — a generic union
        // construction is itself a `GenericTypeInfo` over the union's name.
        if unionCaseName != null {
            return TryResolveUnionCaseMemberType(constructedType, unionCaseName, memberName, nameLine, nameColumn, out memberType)
        }

        generic := constructedType as GenericTypeInfo
        if generic != null {
            return TryResolveGenericMemberType(generic, memberName, nameLine, nameColumn, out memberType)
        }

        // Other receiver kinds (enums, tuples, newtypes, ...) have no assignable members, and
        // `ResolveMember`'s fallbacks for them do not model member-assignment semantics.
        if !IsMemberBearingReceiver(constructedType) {
            return false
        }

        resolved := memberResolutionValue.ResolveMember(constructedType, memberName, false, ambientValue.CurrentTypeName)
        if BuiltInTypes.IsUnknown(resolved) {
            if memberAccessValue.ShouldReportUndefinedMember(constructedType, memberName, false) {
                memberAccessValue.ReportUndefinedMemberAt(constructedType, memberName, nameLine, nameColumn, false, null)
            }

            return false
        }

        if IsNonAssignableMemberResult(resolved) {
            return false
        }

        memberType = resolved
        return true
    }

    func TryResolveUnionCaseMemberType(constructedType: TypeInfo, unionCaseName: string, memberName: string, nameLine: int, nameColumn: int, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        unionSubstitution: Dictionary<string, TypeInfo>? = null
        unionType := matchExhaustivenessValue.ResolveDeclaredUnionType(constructedType, out unionSubstitution)
        if unionType == null {
            return false
        }

        unionCase := AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(unionType, unionCaseName)
        if unionCase == null {
            return false
        }

        caseProperty := FindUnionCaseProperty(unionCase, memberName)
        if caseProperty == null {
            ReportUndeclaredUnionCaseProperty(unionCase, unionCaseName, memberName, nameLine, nameColumn)
            return false
        }

        memberType = typeSubstitutionValue.ResolveTypeForSourceOwner(caseProperty.Type, unionType, unionSubstitution)
        return !BuiltInTypes.IsUnknown(memberType)
    }

    static func FindUnionCaseProperty(unionCase: UnionCase, memberName: string): UnionCaseProperty? {
        properties := unionCase.Properties
        if properties == null {
            return null
        }

        for caseProperty in properties {
            if caseProperty.Name == memberName {
                return caseProperty
            }
        }

        return null
    }

    // NL303 in this arm's second voice: the receiver is a union CASE and the missing name is one of
    // its properties.
    func ReportUndeclaredUnionCaseProperty(unionCase: UnionCase, unionCaseName: string, memberName: string, nameLine: int, nameColumn: int) {
        caseDisplayName := AnalyzerExhaustivenessSelector.GetUnionCaseName(unionCaseName)
        casePropertyNames := new List<string>()
        properties := unionCase.Properties
        if properties != null {
            for caseProperty in properties {
                casePropertyNames.Add(caseProperty.Name)
            }
        }

        suggestion: string? = null
        if casePropertyNames.Count > 0 {
            propertySuggester := new SmartSuggester(casePropertyNames)
            similarProperties := propertySuggester.SuggestSimilarNames(memberName, 3)
            if similarProperties.Count > 0 {
                suggestion = "Did you mean '" + similarProperties[0] + "'?"
            }
        }

        diagnosticsValue.Report(ErrorCode.UndefinedMember, "Union case '" + caseDisplayName + "' doesn't have a property named '" + memberName + "' — check the case definition for available properties", nameLine, nameColumn, suggestion, Math.Max(1, memberName.Length))
    }

    // A CLOSED GENERIC INSTANTIATION OF A DECLARED TYPE (`new Box<Pt> { Item: ... }`): the member's
    // declared type reference is resolved under the type-argument substitution, so `Item: T` on
    // `Box<Pt>` expects `Pt`. Only a CONCLUSIVELY absent member reports — same-named functions,
    // generated members and inherited members all resolve on the open type, and a base class would
    // need its own substitution chain, so its presence suppresses the report instead.
    func TryResolveGenericMemberType(generic: GenericTypeInfo, memberName: string, nameLine: int, nameColumn: int, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        openType := typeSubstitutionValue.ResolveGenericDefinition(generic)
        if openType == null {
            return false
        }

        typeParameters := new TypeParameter[](0)
        members := new DeclaredMemberInfo[](0)
        primaryParameters := new ParameterDeclarationInfo[](0)
        if !TryGetDeclaredTypeShape(openType, out typeParameters, out members, out primaryParameters) {
            return false
        }

        substitution: Dictionary<string, TypeInfo>? = null
        if typeParameters.Length > 0 {
            if typeParameters.Length != generic.TypeArguments.Count {
                return false
            }

            built := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
            index := 0
            while index < typeParameters.Length {
                built[typeParameters[index].Name] = generic.TypeArguments[index]
                index = index + 1
            }

            substitution = built
        }

        memberTypeReference := FindDeclaredMemberTypeReference(members, primaryParameters, memberName)
        if memberTypeReference == null {
            ReportAbsentGenericMemberIfNeeded(generic, openType, memberName, nameLine, nameColumn)
            return false
        }

        memberType = typeSubstitutionValue.ResolveTypeForSourceOwner(memberTypeReference, openType, substitution)
        return !BuiltInTypes.IsUnknown(memberType)
    }

    // The report names the type the DEVELOPER WROTE (`Box<Pt>`), not the open definition it was
    // resolved through.
    func ReportAbsentGenericMemberIfNeeded(generic: GenericTypeInfo, openType: TypeInfo, memberName: string, nameLine: int, nameColumn: int) {
        openClassType := openType as ClassTypeInfo
        if openClassType != null && openClassType.BaseClass != null {
            return
        }

        if !BuiltInTypes.IsUnknown(memberResolutionValue.ResolveMember(openType, memberName, false, ambientValue.CurrentTypeName)) {
            return
        }

        if !memberAccessValue.ShouldReportUndefinedMember(openType, memberName, false) {
            return
        }

        memberAccessValue.ReportUndefinedMemberAt(openType, memberName, nameLine, nameColumn, false, NullabilityMetadataReflection.FormatTypeInfo(generic))
    }

    // The declaration shape of a declared class, struct or record: its type parameters, its declared
    // member facts and its primary-constructor parameters.
    static func TryGetDeclaredTypeShape(candidate: TypeInfo, out typeParameters: TypeParameter[], out members: DeclaredMemberInfo[], out primaryConstructorParameters: ParameterDeclarationInfo[]): bool {
        classInfo := candidate as ClassTypeInfo
        if classInfo != null {
            typeParameters = classInfo.TypeParameters
            members = classInfo.DeclaredMembers
            primaryConstructorParameters = classInfo.PrimaryConstructorParameters
            return true
        }

        structInfo := candidate as StructTypeInfo
        if structInfo != null {
            typeParameters = structInfo.TypeParameters
            members = structInfo.DeclaredMembers
            primaryConstructorParameters = structInfo.PrimaryConstructorParameters
            return true
        }

        recordInfo := candidate as RecordTypeInfo
        if recordInfo != null {
            typeParameters = recordInfo.TypeParameters
            members = recordInfo.DeclaredMembers
            primaryConstructorParameters = recordInfo.PrimaryConstructorParameters
            return true
        }

        typeParameters = new TypeParameter[](0)
        members = new DeclaredMemberInfo[](0)
        primaryConstructorParameters = new ParameterDeclarationInfo[](0)
        return false
    }

    // The declared type reference of a field, property or primary-constructor parameter, on the
    // type's OWN members. There is no base walk: a base member of a generic declaration would need
    // its own substitution chain.
    static func FindDeclaredMemberTypeReference(members: DeclaredMemberInfo[], primaryConstructorParameters: ParameterDeclarationInfo[], memberName: string): TypeReference? {
        for member in members {
            if member.Name == memberName && (member.Kind == DeclaredMemberKind.Field || member.Kind == DeclaredMemberKind.Property) {
                return member.Type
            }
        }

        for parameter in primaryConstructorParameters {
            if parameter.Name == memberName {
                return parameter.Type
            }
        }

        return null
    }

    static func IsMemberBearingReceiver(candidate: TypeInfo): bool {
        return candidate as ClassTypeInfo != null || candidate as StructTypeInfo != null || candidate as RecordTypeInfo != null || candidate as ReflectionTypeInfo != null
    }

    // A METHOD GROUP, A REFLECTED METHOD OR EVENT, AND A FUNCTION VALUE WITH SOURCE IDENTITY are all
    // members you cannot assign to, so the gate declines rather than accusing the value.
    static func IsNonAssignableMemberResult(resolved: TypeInfo): bool {
        if resolved as NSharpMethodGroupInfo != null || resolved as ReflectionMethodGroupInfo != null || resolved as ReflectionMethodInfo != null || resolved as ReflectionEventInfo != null {
            return true
        }

        functionType := resolved as FunctionTypeInfo
        if functionType != null {
            return AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(functionType)
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // THE TWO SoA INITIALIZER REFUSALS BOTH FORMS SHARE.
    // ------------------------------------------------------------------------------------------

    // NL301. A SoA table is a column-of-arrays view: an indexer entry and a collection entry are
    // shapes its lowering has no meaning for, whichever syntax asked for them.
    func ReportUnsupportedSoaTableInitializerShapeIfNeeded(targetType: TypeInfo, property: PropertyInitializer, initializerKind: string): bool {
        if declarationContextValue.ResolveDeclaredAlias(NonNullableType(targetType)) as SoaRecordTypeInfo == null {
            return false
        }

        if property.Name != null && property.IndexExpression == null {
            return false
        }

        diagnosticTarget := property.Value
        initializerShape := "collection initializer entries"
        if property.IndexExpression != null {
            diagnosticTarget = property.IndexExpression
            initializerShape = "indexer initializers"
        }

        span := spansValue.GetExpressionDiagnosticSpan(diagnosticTarget)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA tables cannot use " + initializerKind + " " + initializerShape, span.Line, span.Column, "Construct the table with new Table(capacity) or Table.wrap(...), then write individual columns with table[index].column.", span.Length)
        return true
    }

    // A NAMED ENTRY ON A SoA TABLE IS ALWAYS REFUSED, and which of the two refusals it gets depends on
    // whether the name is real: a COLUMN or a bookkeeping field is refused as a direct member write,
    // and anything else is simply not a member of the table at all.
    func ReportSoaTableNamedInitializerIfNeeded(constructedType: TypeInfo, memberName: string, nameLine: int, nameColumn: int): bool {
        soaRecordType := declarationContextValue.ResolveDeclaredAlias(NonNullableType(constructedType)) as SoaRecordTypeInfo
        if soaRecordType == null {
            return false
        }

        isColumn := AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, memberName) != null
        isBookkeepingField := memberName == "length" || memberName == "capacity"
        if isColumn || isBookkeepingField {
            ReportSoaTableMemberInitializer(memberName, nameLine, nameColumn, isColumn)
        } else if memberAccessValue.ShouldReportUndefinedMember(soaRecordType, memberName, false) {
            memberAccessValue.ReportUndefinedMemberAt(soaRecordType, memberName, nameLine, nameColumn, false, null)
        }

        return true
    }

    func ReportSoaTableMemberInitializer(memberName: string, line: int, column: int, isColumn: bool) {
        suggestion := "Use new Table(capacity), add, clear, ensureCapacity, or copyRow so length and capacity stay consistent with the columns."
        if isColumn {
            suggestion = "Write individual rows with table[index].column, or construct/wrap the table with the desired column arrays."
        }

        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA table member '" + memberName + "' cannot be initialized directly", line, column, suggestion, Math.Max(1, memberName.Length))
    }

    // ------------------------------------------------------------------------------------------
    // THE SoA TABLE CONSTRUCTION RULE: `new Table(capacity)` AND NOTHING ELSE.
    // ------------------------------------------------------------------------------------------

    func ValidateSoaRecordConstructionIfNeeded(state: ConstructionState, node: NewExpression) {
        if state.SoaConstruction == null {
            return
        }

        ValidateSoaRecordConstruction(node, state.SoaConstruction, state.ConstructorArgumentTypes)
    }

    // FOUR ORDERED REFUSALS, each of which ENDS the validation: the wrong argument count, a named
    // argument that is not `capacity`, a capacity that is not an `int`, and a capacity that is a
    // negative constant. A row-typed or unknown capacity is left alone — it has already been accused.
    func ValidateSoaRecordConstruction(node: NewExpression, soaRecordType: SoaRecordTypeInfo, constructorArgumentTypes: List<TypeInfo>) {
        expectedShape := "new " + soaRecordType.Declaration.Name + "(capacity)"
        if node.ConstructorArguments.Count != 1 {
            diagnosticsValue.Report(ErrorCode.NoMatchingOverload, "SoA table '" + soaRecordType.Declaration.Name + "' construction expects exactly one int capacity argument, but " + node.ConstructorArguments.Count.ToString() + " were provided", node.Line, node.Column, "Use '" + expectedShape + "' with a non-negative int capacity.", 3)
            return
        }

        capacityArgument := node.ConstructorArguments[0]
        argumentName := capacityArgument.Name
        if argumentName != null && argumentName != "capacity" {
            span := spansValue.GetExpressionDiagnosticSpan(capacityArgument.Value)
            diagnosticsValue.Report(ErrorCode.NoMatchingOverload, "SoA table '" + soaRecordType.Declaration.Name + "' construction has no parameter named '" + argumentName + "'", span.Line, span.Column, "Use '" + expectedShape + "', or rename the argument to 'capacity'.", span.Length)
            return
        }

        capacityType := declarationContextValue.ResolveDeclaredAlias(constructorArgumentTypes[0])
        if capacityType as SoaRowTypeInfo != null || BuiltInTypes.IsUnknown(capacityType) {
            return
        }

        if !assignabilityValue.IsAssignable(BuiltInTypes.Int, capacityType) {
            span := spansValue.GetExpressionDiagnosticSpan(capacityArgument.Value)
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "SoA table capacity must be int, but this argument has type '" + TypeText(capacityType) + "'", span.Line, span.Column, "Use '" + expectedShape + "' with an int capacity.", span.Length)
            return
        }

        if constantFactsValue.IsConstantNegative(capacityArgument.Value) {
            span := spansValue.GetExpressionDiagnosticSpan(capacityArgument.Value)
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "SoA table capacity must not be negative", span.Line, span.Column, "Use zero or a positive capacity; the table can grow later with add or ensureCapacity.", span.Length)
        }
    }

    // ------------------------------------------------------------------------------------------
    // THE READONLY-FIELD REFUSAL, ASKED OF THE FAMILY THAT OWNS THE FACT.
    // ------------------------------------------------------------------------------------------

    // NL309. An object initializer is not a constructor, so a `readonly` field written by one is
    // refused with the same words the assignment arm uses.
    func CheckReadonlyObjectInitializerField(constructedType: TypeInfo, memberName: string, line: int, column: int) {
        resolvedFieldName := ""
        if !writeTargetsValue.TryFindReadonlyInstanceField(NonNullableType(constructedType), memberName, out resolvedFieldName) {
            return
        }

        diagnosticsValue.Report(ErrorCode.ReadonlyAssignment, "Field '" + resolvedFieldName + "' is readonly — it can only be assigned in a constructor", line, column, "Move this assignment into a constructor, or remove `readonly` if the field needs to change later.", Math.Max(1, memberName.Length))
    }

    // ------------------------------------------------------------------------------------------
    // TWO REPRODUCED FACTS.
    // ------------------------------------------------------------------------------------------

    // The nullable unwrap `Analyzer.cs` performs before every structural question. Its C# original has
    // twelve other callers and therefore could not move.
    func NonNullableType(candidate: TypeInfo): TypeInfo {
        nullable := declarationContextValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
    }

    // A type's display text. `TypeInfo.ToString()` is not a modeled instance call; the estate reads it
    // through `object`.
    static func TypeText(candidate: TypeInfo): string {
        boxed := candidate as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}
