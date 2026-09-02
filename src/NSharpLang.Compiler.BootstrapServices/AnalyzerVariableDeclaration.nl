namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE FOUR STEPS A LOCAL DECLARATION CANNOT TAKE FOR ITSELF, AND EVERYTHING EACH STEP NEEDS.
//
// The walk owns what N#'s TWO local-declaration statements MEAN — `let x: T = e` and
// `(a, b) := e` — what an annotation resolves to, whether the initializer is assignable to it,
// which of the four type outcomes a declaration has, whether a deconstruction source is a tuple at
// all and whether its element count matches the target list, which of the walk's SEVEN diagnostics
// fires and with which span and wording, which SoA escape report the resulting type selects, and
// what each declared name's null state is the instant it comes into existence. What it cannot do is
// run the analyzer's own EXPRESSION walk, declare a symbol into the analyzer's scope stack, or write
// the semantic model the IDE reads — so it ASKS: one request at a time, each naming a kind and
// carrying every value the step needs. Nothing here is a policy the driver may reinterpret — the
// driver switches on `Kind`, performs exactly the one operation with exactly these operands, and
// hands the answer back.
//
// THE TWO SoA ESCAPE REPORTS ARE NO LONGER STEPS. They were kinds 2 and 3 and are now direct calls
// on `AnalyzerSoaEscape`, which this walk holds. WHICH report the resulting type selects is still
// entirely this walk's decision — that was never the driver's — but performing it no longer costs a
// round trip through C#.
//
// The kinds:
//   1  analyse the INITIALIZER expression under an expected type, SETTING the analyzer's ambient
//      target-typing slot to `ExpectedType` for the duration. ANSWERS a type, and that type is the
//      operand of three of the four steps that follow it.
//   4  declare the name into the analyzer's scope stack, under the declaration kind carried here
//      (null for a deconstruction target, which is not tagged).
//   5  record the name in the semantic model the IDE's hover and completion read.
//   6  analyse the INITIALIZER expression WITHOUT touching the ambient target-typing slot. This is
//      NOT kind 1 with a null expected type: a deconstruction is analysed inside whatever target
//      typing already surrounds it (a lambda body inside an annotated initializer is the reachable
//      case), and overwriting that slot with null would change what `default`, an unbound callable
//      reference, a lambda and a negative integer literal resolve to.
//
// The numbering keeps its GAPS at 2 and 3 rather than closing up: the kind number is a protocol
// between this walk and one driver, and a renumber would silently re-point every contract that pins
// a step's kind.
class VariableDeclarationRequest {
    Kind: int
    Node: Expression?
    Name: string?
    CarriedType: TypeInfo
    ExpectedType: TypeInfo?
    Text: string?
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Name = null
        CarriedType = carriedType
        ExpectedType = null
        Text = null
        Line = 0
        Column = 0
    }
}

// THE LOCAL DECLARATION'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// ONE state serves BOTH local-declaration statements, because ONE driver serves both: exactly one of
// `declarationValue` and `tupleValue` is set, and which one is set selects the phase family. That is
// not a convenience — the two statements replay the SAME operations on the analyzer, so a second
// driver would be a second copy of the same switch.
//
// `Phase` is the walk's program counter. The ANNOTATED family runs 0..5: 0 resolves the annotation
// and asks for the initializer, 1 folds the answer in and settles the type, and 2 through 5 are the
// four replayed operations in the order `Analyzer.cs` performed them. The DECONSTRUCTION family runs
// 10..15: 10 asks for the initializer, 11 chooses and asks for the escape report, 12 settles the
// target list and reports, and 13/14/15 are the per-target declare / record / post-write loop. 99 is
// done for both.
//
// `DeclaredType` is settled at phase 0 and never changes. `InferredType` is the kind-1/kind-6 answer
// and is null until it arrives; it is kept SEPARATELY from `FinalType` because the annotated
// family's null-state rule reads the initializer's OWN type rather than the declaration's, and those
// differ whenever an annotation widens or an initializer is void.
//
// `TargetTypes` is the deconstruction's answer to "what is each name", settled once at phase 12 —
// either the source's element types or ONE shared unknown instance repeated, which is what
// `Analyzer.cs` passed when it fell back.
class VariableDeclarationState {
    declarationValue: VariableDeclarationStatement?
    tupleValue: TupleDeconstructionStatement?

    Declaration: VariableDeclarationStatement? => declarationValue
    Tuple: TupleDeconstructionStatement? => tupleValue

    Phase: int
    Pending: int

    DeclaredType: TypeInfo?
    InferredType: TypeInfo?
    FinalType: TypeInfo

    ErrorForm: bool
    EscapeFired: bool
    TargetTypes: List<TypeInfo>
    TargetIndex: int
    PendingName: string?
    PendingType: TypeInfo

    constructor(declaration: VariableDeclarationStatement?, tuple: TupleDeconstructionStatement?) {
        declarationValue = declaration
        tupleValue = tuple
        Phase = 0
        if tuple != null {
            Phase = 10
        }

        Pending = 0
        DeclaredType = null
        InferredType = null
        FinalType = BuiltInTypes.Unknown
        ErrorForm = false
        EscapeFired = false
        TargetTypes = new List<TypeInfo>()
        TargetIndex = 0
        PendingName = null
        PendingType = BuiltInTypes.Unknown
    }
}

// WHAT A LOCAL DECLARATION MEANS, as a walk that suspends at each step it cannot take itself.
//
// This is the analyzer's expression/statement walker territory, and it owns BOTH of N#'s
// local-declaration statements: the annotated form `let x: T = e` and the deconstruction form
// `(a, b) := e`. They moved in two slices and they share ONE driver, because a caller-closure scan
// of the deconstruction arm resolved its re-entries to EXACTLY the annotated arm's — once five
// (`AnalyzeExpression`, the two SoA escape reporters, `DeclareSymbol` and
// `RecordVariableInCurrentScope`), now THREE, since the escape reports became N#-owned and are called
// directly. No new kind but the ambient-slot distinction kind 6 records.
// Neither arm re-enters the statement dispatch, so neither drags `AnalyzeStatement` in behind it.
//
// THE DECONSTRUCTION ARM ARRIVED WITH ITS WHOLE PRIVATE CLOSURE. `Analyzer.cs` kept four helpers
// that nothing else in 13,875 lines called — the two target declarers, the element extractor and the
// reflected-`ValueTuple` reader — so they are here rather than left behind as callbacks.
//
// WHY A RESUMABLE WALK WITH ANSWERS RATHER THAN A SCHEDULE COMPUTED UP FRONT. The deciding question
// the arc asks every family is whether the step COUNT — or a step's OPERANDS — depend on an answer
// the walk does not have yet. Here the COUNT is knowable (`Initializer != null` decides the kind-1
// and the SoA step, and the last two always happen), but THREE of the five steps take `FinalType` as
// an operand and in the inference form — `x := expr`, no annotation, which is the ordinary way to
// declare a local in N# — `FinalType` IS the kind-1 answer:
//   * WHICH SoA report fires is chosen by `FinalType is SoaRowTypeInfo`;
//   * the kind-4 declaration is PASSED `FinalType`, and so is the kind-5 semantic-model record.
// So no schedule computed before the first step can carry the later steps' operands, and the walk
// suspends and RESUMES WITH THE ANSWER, like slice 24's call walk and slice 29's pattern walk.
//
// THE DECONSTRUCTION FORM IS RESUMABLE ON THE STRONGER COUNT: its step COUNT is not knowable either.
// How many names are declared is `Names.Count` minus the discards, but WHICH steps run is decided by
// the source's answered type — an escaped or non-tuple source declares every name as `unknown`, a
// count mismatch does the same and reports, and only a matching tuple hands out element types — and
// the arity report's own MESSAGE interpolates a count derived from that answer. A schedule computed
// before the initializer is analysed cannot name a single one of those operands.
//
// THE EXPECTED TYPE TRAVELS WITH THE REQUEST RATHER THAN BEING AMBIENT. `Analyzer.cs` set
// `_currentExpectedType` to the annotation around the initializer analysis so that a target-typed
// expression (`new()`, a collection literal) could read it. That flag stays in `Analyzer.cs` because
// the expression walker still reads it, but WHAT it is set to is this walk's answer, so the kind-1
// request carries it and the driver performs the same save / set / restore around the same one call.
//
// THE FOUR TYPE OUTCOMES AND ALL SEVEN DIAGNOSTICS ARE `Analyzer.cs`'s VERBATIM. An annotation with
// a non-assignable initializer reports NL202 in the rich `ErrorMessageBuilder` shape when the file
// and a snippet are both available and in the detail-only shape when either is missing — the SAME
// report in the SAME position, differing only in how much explanation it carries. A `const` with an
// annotation and no initializer reports NL103. A void initializer with no annotation reports NL202
// and the declaration falls back to unknown. A declaration with neither reports NL103. And an
// annotation ALWAYS wins the type, even when the initializer disagreed. A deconstruction adds two
// more, both NL103 and both underlining the INITIALIZER: a source that is not a tuple, and a tuple
// whose element count disagrees with the target count. Both then give every target `unknown` rather
// than abandoning the statement, so the names still exist for the rest of the scope.
class AnalyzerVariableDeclaration {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    typeResolverValue: AnalyzerTypeResolver
    assignabilityValue: AnalyzerAssignability
    nullFlowValue: AnalyzerNullFlow
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    soaEscapeValue: AnalyzerSoaEscape

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, typeResolver: AnalyzerTypeResolver, assignability: AnalyzerAssignability, nullFlow: AnalyzerNullFlow, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, soaEscape: AnalyzerSoaEscape) {
        diagnosticsValue = diagnostics
        spansValue = spans
        typeResolverValue = typeResolver
        assignabilityValue = assignability
        nullFlowValue = nullFlow
        scopesValue = scopes
        declarationContextValue = declarationContext
        soaEscapeValue = soaEscape
    }

    // ── THE ERROR-CAPTURE CONVENTION, NAMED ────────────────────────────────────────────────────
    //
    // `result, err := f()` is the Go-style error capture, and this predicate is the whole rule:
    // EXACTLY TWO names whose SECOND is literally `err`. It is a language convention rather than a
    // type rule — nothing about the initializer decides it, the spelling of the second name does —
    // and it decides real behaviour in three places: the analyzer gives that name the type
    // `Exception?` regardless of what the source says (phase 10 below), the columnar emitter lowers
    // the call into a try/catch and binds `err` to the caught exception, and the editor paints the
    // name with the `catchResult` semantic-token modifier.
    //
    // IT IS `== 2`, NOT `>= 2`, AND THE DIFFERENCE IS OBSERVABLE. A three-name deconstruction whose
    // last name happens to be `err` — `(a, b, err) := f()` — is an ORDINARY tuple deconstruction:
    // the analyzer counts its elements and types `err` from the source, and the emitter does not
    // wrap anything in a catch. Any consumer that admits it is describing a form the language does
    // not have.
    static func IsErrorCaptureForm(nameCount: int, lastName: string): bool {
        return nameCount == 2 && lastName == "err"
    }

    func Begin(declaration: VariableDeclarationStatement): VariableDeclarationState {
        return new VariableDeclarationState(declaration, null)
    }

    // THE DECONSTRUCTION FORM'S ENTRY. Same state, same `NextStep`, same `Supply`, same driver — only
    // the phase family differs.
    func BeginTuple(tuple: TupleDeconstructionStatement): VariableDeclarationState {
        return new VariableDeclarationState(null, tuple)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this declaration is finished. Every phase
    // either decides something and advances, or emits exactly one request; the walk never advances
    // past a point whose answer it has not been given. The type diagnostics land HERE, between the
    // kind-1 step and the SoA step, which is exactly where `Analyzer.cs` reported them.
    func NextStep(state: VariableDeclarationState): VariableDeclarationRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kinds 1 and 6 answer anything the walk reads — the
    // initializer's type, which settles the declaration's type and three later operands. The two
    // declaration steps answer nothing, and nothing is folded in for them. The escape answer used to
    // arrive here as a second parameter; the reports are direct calls now, so the flag is gone.
    func Supply(state: VariableDeclarationState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 || pending == 6 {
            state.InferredType = answer
        }
    }

    func Advance(state: VariableDeclarationState): VariableDeclarationRequest? {
        tuple := state.Tuple
        if tuple != null {
            return AdvanceTuple(state, tuple)
        }

        declaration := state.Declaration
        if declaration != null {
            return AdvanceAnnotated(state, declaration)
        }

        state.Phase = 99
        return null
    }

    func AdvanceAnnotated(state: VariableDeclarationState, declaration: VariableDeclarationStatement): VariableDeclarationRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceAnnotation(state, declaration)
        }

        if phase == 1 {
            return AdvanceType(state, declaration)
        }

        if phase == 2 {
            return AdvanceEscape(state, declaration)
        }

        if phase == 3 {
            return AdvanceDeclare(state, declaration)
        }

        if phase == 4 {
            return AdvanceRecord(state, declaration)
        }

        if phase == 5 {
            return AdvanceNullState(state, declaration)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — the annotation, and the one step whose answer everything else depends on. A
    // declaration with no initializer skips straight to the type decision with no answer to wait for.
    func AdvanceAnnotation(state: VariableDeclarationState, declaration: VariableDeclarationStatement): VariableDeclarationRequest? {
        typeReference := declaration.Type
        if typeReference != null {
            state.DeclaredType = typeResolverValue.ResolveDeclaredType(typeReference)
        }

        state.Phase = 1
        initializer := declaration.Initializer
        if initializer == null {
            return null
        }

        state.Pending = 1
        request := new VariableDeclarationRequest(1, BuiltInTypes.Unknown)
        request.Node = initializer
        request.ExpectedType = state.DeclaredType
        return request
    }

    // PHASE 1 — THE FOUR TYPE OUTCOMES, in the order `Analyzer.cs` tested them. Exactly one arm runs
    // and at most one diagnostic is reported.
    func AdvanceType(state: VariableDeclarationState, declaration: VariableDeclarationStatement): VariableDeclarationRequest? {
        declaredType := state.DeclaredType
        inferredType := state.InferredType
        initializer := declaration.Initializer

        state.Phase = 2

        if declaredType != null && inferredType != null && initializer != null {
            ReportIfNotAssignable(declaration, declaredType, inferredType, initializer)
            state.FinalType = declaredType
            return null
        }

        if declaredType != null {
            if declaration.Kind == VariableKind.Const {
                ReportConstWithoutInitializer(declaration, declaredType)
            }

            state.FinalType = declaredType
            return null
        }

        if inferredType != null {
            if BuiltInTypes.Is(inferredType, BuiltInTypes.Void) {
                ReportVoidInitializer(declaration, initializer)
                state.FinalType = BuiltInTypes.Unknown
                return null
            }

            state.FinalType = inferredType
            return null
        }

        ReportUndeterminedType(declaration)
        state.FinalType = BuiltInTypes.Unknown
        return null
    }

    // PHASE 2 — THE SoA ESCAPE REPORT THE RESULTING TYPE SELECTS. A row view stored in a variable is
    // always an escape; anything else has to be asked. A declaration with no initializer has no
    // expression to report on and asks for neither.
    func AdvanceEscape(state: VariableDeclarationState, declaration: VariableDeclarationStatement): VariableDeclarationRequest? {
        initializer := declaration.Initializer
        state.Phase = 3
        if initializer == null {
            return null
        }

        soaRow := state.FinalType as SoaRowTypeInfo
        if soaRow != null {
            soaEscapeValue.ReportSoaRowEscape(initializer, "stored in a variable")
            return null
        }

        state.EscapeFired = soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(initializer, "stored in a variable")
        return null
    }

    // PHASE 3 — the local enters the analyzer's scope stack under the declaration kind `local`, which
    // is what makes it a local rather than a parameter or a field to everything that reads the scope.
    func AdvanceDeclare(state: VariableDeclarationState, declaration: VariableDeclarationStatement): VariableDeclarationRequest? {
        state.Phase = 4
        state.Pending = 4
        request := new VariableDeclarationRequest(4, state.FinalType)
        request.Name = declaration.Name
        request.Text = "local"
        request.Line = declaration.Line
        request.Column = declaration.Column
        return request
    }

    // PHASE 4 — the semantic model the IDE's hover and completion read. This is a SEPARATE step from
    // the scope declaration because it writes a different store and, unlike the scope, it is scoped
    // by the semantic scope id rather than by the analyzer's own stack.
    func AdvanceRecord(state: VariableDeclarationState, declaration: VariableDeclarationStatement): VariableDeclarationRequest? {
        state.Phase = 5
        state.Pending = 5
        request := new VariableDeclarationRequest(5, state.FinalType)
        request.Name = declaration.Name
        return request
    }

    // PHASE 5 — WHAT THE ANALYZER BELIEVES ABOUT THIS LOCAL'S NULLNESS THE INSTANT IT EXISTS, and the
    // walk's only write that is not a replayed operation, because the scope stack is already N#.
    //
    // It runs AFTER the declaration step rather than before it, exactly as `Analyzer.cs` ordered it:
    // the null state is set on a name the scope already knows. A declared-nullable local takes its
    // state from the SYNTAX of the initializer (a literal `null` is null, anything else is
    // maybe-null); everything else asks the null-state owner, about the INITIALIZER'S type when there
    // is an initializer and about the declaration's own type when there is not.
    func AdvanceNullState(state: VariableDeclarationState, declaration: VariableDeclarationStatement): VariableDeclarationRequest? {
        initializer := declaration.Initializer
        finalType := state.FinalType
        state.Phase = 99

        nullable := finalType as NullableTypeInfo
        if nullable != null {
            nullLiteral := initializer as NullLiteralExpression
            if nullLiteral != null {
                scopesValue.SetNullStateInCurrentScope(declaration.Name, NullState.Null)
            } else {
                scopesValue.SetNullStateInCurrentScope(declaration.Name, NullState.MaybeNull)
            }

            return null
        }

        if initializer != null {
            // `inferredType ?? finalType` in `Analyzer.cs`, written as a POSITIVE guard: N# does not
            // carry a narrowing across an assignment that repairs the null, so the `== null` shape
            // reports NL202 on the call below rather than narrowing it.
            inferredType := state.InferredType
            if inferredType != null {
                scopesValue.SetNullStateInCurrentScope(declaration.Name, nullFlowValue.GetExpressionNullState(initializer, inferredType))
                return null
            }

            scopesValue.SetNullStateInCurrentScope(declaration.Name, nullFlowValue.GetExpressionNullState(initializer, finalType))
            return null
        }

        scopesValue.SetNullStateInCurrentScope(declaration.Name, nullFlowValue.GetDefaultNullState(finalType))
        return null
    }

    // ─── THE DECONSTRUCTION FORM: `(a, b) := e` ──────────────────────────────────────────────────
    //
    // Six phases, and the only structural difference from the annotated form is that the last three
    // are a LOOP: a deconstruction declares N names, and each one replays the same declare / record
    // pair before the walk writes its null state itself.
    func AdvanceTuple(state: VariableDeclarationState, tuple: TupleDeconstructionStatement): VariableDeclarationRequest? {
        phase := state.Phase
        if phase == 10 {
            return AdvanceTupleInitializer(state, tuple)
        }

        if phase == 11 {
            return AdvanceTupleEscape(state, tuple)
        }

        if phase == 12 {
            return AdvanceTupleTargets(state, tuple)
        }

        if phase == 13 {
            return AdvanceTupleDeclare(state, tuple)
        }

        if phase == 14 {
            return AdvanceTupleRecord(state)
        }

        if phase == 15 {
            return AdvanceTupleAfterTarget(state, tuple)
        }

        state.Phase = 99
        return null
    }

    // PHASE 10 — WHICH DECONSTRUCTION THIS IS, and the one step whose answer everything else depends
    // on. The ERROR form is `(result, err := f())` — exactly two names whose second is literally
    // `err` — and it is a different statement in every respect below: it never counts elements, it
    // never reports, and it gives its second name the type `Exception?` regardless of the source.
    // The initializer is analysed with kind 6, NOT kind 1: a deconstruction has no annotation to
    // target-type with, and it must not overwrite whatever target typing already surrounds it.
    func AdvanceTupleInitializer(state: VariableDeclarationState, tuple: TupleDeconstructionStatement): VariableDeclarationRequest? {
        names := tuple.Names
        if names.Count > 0 {
            state.ErrorForm = IsErrorCaptureForm(names.Count, names[names.Count - 1])
        }

        state.Phase = 11
        state.Pending = 6
        request := new VariableDeclarationRequest(6, BuiltInTypes.Unknown)
        request.Node = tuple.Initializer
        return request
    }

    // PHASE 11 — THE SoA ESCAPE REPORT THE SOURCE'S TYPE SELECTS, and the ONE place the two forms
    // agree completely. A row view is always an escape and the direct-column probe is then NOT run
    // at all — `Analyzer.cs` joined the two with `||`, so the row report short-circuits it — and
    // EITHER firing makes the source `unknown`, which is folded in at phase 12.
    func AdvanceTupleEscape(state: VariableDeclarationState, tuple: TupleDeconstructionStatement): VariableDeclarationRequest? {
        answered := state.InferredType
        if answered != null {
            state.FinalType = answered
        }

        state.Phase = 12
        soaRow := state.FinalType as SoaRowTypeInfo
        if soaRow != null {
            state.EscapeFired = true
            soaEscapeValue.ReportSoaRowEscape(tuple.Initializer, "deconstructed")
            return null
        }

        state.EscapeFired = soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(tuple.Initializer, "deconstructed")
        return null
    }

    // PHASE 12 — WHAT EACH NAME IS, and both of this arm's diagnostics. In the order `Analyzer.cs`
    // tested it: an escaped or unknown source gives every target the SAME unknown instance and
    // reports nothing; a source that is not a tuple at all reports NL103 and does the same; a tuple
    // whose element count disagrees with the target count reports NL103 and does the same; and only
    // a matching tuple hands each name its own element type. The error form skips all of it — its
    // two names' types are decided per-target at phase 13.
    func AdvanceTupleTargets(state: VariableDeclarationState, tuple: TupleDeconstructionStatement): VariableDeclarationRequest? {
        state.Phase = 13
        state.TargetIndex = 0
        if state.EscapeFired {
            state.FinalType = BuiltInTypes.Unknown
        }

        if state.ErrorForm {
            return null
        }

        names := tuple.Names
        targetCount := names.Count
        if BuiltInTypes.IsUnknown(state.FinalType) {
            FillUnknownTargets(state, targetCount)
            return null
        }

        elements := TryGetTupleElements(state.FinalType)
        if elements != null {
            if elements.Count == targetCount {
                state.TargetTypes = elements
                return null
            }

            ReportTupleArityMismatch(tuple, targetCount, elements.Count)
            FillUnknownTargets(state, targetCount)
            return null
        }

        ReportNotATuple(tuple, state.FinalType)
        FillUnknownTargets(state, targetCount)
        return null
    }

    // PHASE 13 — the next name that actually becomes a symbol. `_` is a discard: `Analyzer.cs`
    // neither declared it, nor recorded it, nor gave it a null state, so the loop skips it whole
    // rather than declaring it under its own name.
    func AdvanceTupleDeclare(state: VariableDeclarationState, tuple: TupleDeconstructionStatement): VariableDeclarationRequest? {
        names := tuple.Names
        targetCount := names.Count
        index := state.TargetIndex
        while index < targetCount {
            name := names[index]
            if name != "_" {
                state.TargetIndex = index
                state.PendingName = name
                state.PendingType = TargetType(state, index)
                state.Phase = 14
                state.Pending = 4
                request := new VariableDeclarationRequest(4, state.PendingType)
                request.Name = name
                request.Line = tuple.Line
                request.Column = tuple.Column
                return request
            }

            index = index + 1
        }

        state.Phase = 99
        return null
    }

    // PHASE 14 — the semantic model the IDE's hover and completion read, for the SAME name and the
    // SAME type instance phase 13 just declared.
    func AdvanceTupleRecord(state: VariableDeclarationState): VariableDeclarationRequest? {
        state.Phase = 15
        state.Pending = 5
        request := new VariableDeclarationRequest(5, state.PendingType)
        request.Name = state.PendingName
        return request
    }

    // PHASE 15 — THE WRITE THE WALK MAKES ITSELF, because the scope stack is already N#. Which write
    // it is depends on the form and the position: the error form's FIRST name is registered as an
    // error-tuple result — the pairing that lets a later `err` check narrow it, and the only caller
    // of that registration in the whole analyzer — its SECOND name is maybe-null because an
    // `Exception?` that has not been checked may be anything, and every ordinary target takes the
    // default state its own type implies.
    func AdvanceTupleAfterTarget(state: VariableDeclarationState, tuple: TupleDeconstructionStatement): VariableDeclarationRequest? {
        name := state.PendingName
        if name != null {
            if state.ErrorForm {
                if state.TargetIndex == 0 {
                    names := tuple.Names
                    errorName := names[1]
                    scopesValue.RegisterErrorTupleResult(name, errorName, tuple.Line, tuple.Column)
                } else {
                    scopesValue.SetNullStateInCurrentScope(name, NullState.MaybeNull)
                }
            } else {
                scopesValue.SetNullStateInCurrentScope(name, nullFlowValue.GetDefaultNullState(state.PendingType))
            }
        }

        state.TargetIndex = state.TargetIndex + 1
        state.Phase = 13
        return null
    }

    // THE TYPE A TARGET GETS. The error form decides per position and never consults the target
    // list: its first name takes the SOURCE's type whole (it is not deconstructed at all) and its
    // second is always `Exception?`. Every other deconstruction reads the list phase 12 settled.
    func TargetType(state: VariableDeclarationState, index: int): TypeInfo {
        if state.ErrorForm {
            if index == 0 {
                return state.FinalType
            }

            exceptionType: TypeInfo = new ExternalTypeInfo("Exception?")
            return exceptionType
        }

        return state.TargetTypes[index]
    }

    // EVERY TARGET UNKNOWN — and every target the SAME unknown, because `Analyzer.cs` evaluated
    // `BuiltInTypes.Unknown` ONCE at the call and handed that one instance to each name. The
    // property builds a new instance on every read, so reading it per target would put distinct
    // instances into the scope and the semantic model.
    func FillUnknownTargets(state: VariableDeclarationState, count: int) {
        unknown: TypeInfo = BuiltInTypes.Unknown
        targets := new List<TypeInfo>()
        index := 0
        while index < count {
            targets.Add(unknown)
            index = index + 1
        }

        state.TargetTypes = targets
    }

    // WHAT A DECONSTRUCTION SOURCE'S ELEMENTS ARE, or null when the source is not a tuple. Three
    // shapes answer, in `Analyzer.cs`'s order and after the SAME alias resolution: a declared tuple
    // type, a constructed generic named `ValueTuple`, and a reflected CLR `System.ValueTuple`N`.
    // There is NO `Deconstruct`-method resolution — a type with a `Deconstruct` method is not
    // deconstructable in N#, and that is the language's answer rather than an omission here.
    func TryGetTupleElements(sourceType: TypeInfo): List<TypeInfo>? {
        resolved := declarationContextValue.ResolveDeclaredAlias(sourceType)

        tupleType := resolved as TupleTypeInfo
        if tupleType != null {
            declared := tupleType.Elements
            elements := new List<TypeInfo>()
            index := 0
            while index < declared.Count {
                element := declared[index]
                elements.Add(element.Type)
                index = index + 1
            }

            return elements
        }

        generic := resolved as GenericTypeInfo
        if generic != null && generic.Name == "ValueTuple" {
            arguments := generic.TypeArguments
            elements := new List<TypeInfo>()
            index := 0
            while index < arguments.Count {
                elements.Add(arguments[index])
                index = index + 1
            }

            return elements
        }

        reflected := resolved as ReflectionTypeInfo
        if reflected != null {
            return TryGetReflectionValueTupleElements(reflected.Type)
        }

        return null
    }

    // A REFLECTED `System.ValueTuple`N`'S ELEMENTS, read off the type's own `ItemN` fields rather
    // than its generic arguments. The distinction is REAL at arity 8 and above: `ValueTuple`8` has
    // eight generic arguments but only seven `ItemN` fields, the eighth being the nested `Rest`, so
    // reading fields answers seven and reading arguments would answer eight and silently mis-pair
    // every target. The guard is on the GENERIC DEFINITION's full name, so a user type merely
    // spelled `ValueTuple` does not qualify.
    func TryGetReflectionValueTupleElements(clrType: Type): List<TypeInfo>? {
        valueTupleType := clrType
        underlying := Nullable.GetUnderlyingType(clrType)
        if underlying != null {
            valueTupleType = underlying
        }

        if !valueTupleType.get_IsValueType() {
            return null
        }

        if !valueTupleType.get_IsGenericType() {
            return null
        }

        definition := valueTupleType.GetGenericTypeDefinition()
        definitionName := definition.get_FullName()
        if definitionName == null {
            return null
        }

        if !definitionName.StartsWith("System.ValueTuple`", StringComparison.Ordinal) {
            return null
        }

        elements := new List<TypeInfo>()
        index := 1
        searching := true
        while searching {
            field := valueTupleType.GetField("Item" + index.ToString())
            if field != null {
                elements.Add(AnalyzerReflectionTypeConversion.ConvertReflectionType(field.get_FieldType()))
                index = index + 1
            } else {
                searching = false
            }
        }

        if elements.Count == 0 {
            return null
        }

        return elements
    }

    // NL103 — THE SOURCE IS NOT A TUPLE. The report underlines the initializer, not the target list,
    // because the initializer is what has to change.
    func ReportNotATuple(tuple: TupleDeconstructionStatement, sourceType: TypeInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(tuple.Initializer)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Tuple deconstruction needs a tuple value, but this initializer is '" + TypeText(sourceType) + "'", span.Line, span.Column, "Return or construct a tuple with the same number of elements as the deconstruction targets.", span.Length)
    }

    // NL103 — THE COUNTS DISAGREE. Both counts are named, because which side is wrong is the
    // author's call.
    func ReportTupleArityMismatch(tuple: TupleDeconstructionStatement, targetCount: int, elementCount: int) {
        span := spansValue.GetExpressionDiagnosticSpan(tuple.Initializer)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Tuple deconstruction has " + targetCount.ToString() + " target(s), but the initializer has " + elementCount.ToString() + " element(s)", span.Line, span.Column, "Match the number of target names to the tuple element count.", span.Length)
    }

    // A TYPE'S RENDERED TEXT, TAKEN THROUGH `object`. `Analyzer.cs` wrote `$"{type}"` and
    // `type.ToString()`; the columnar backend declines a virtual `ToString` called directly on a
    // `TypeInfo`, and the estate's established spelling is to box first. The empty fallback is
    // unreachable — every `TypeInfo` override returns a string — and exists so the local is a
    // non-null `string`.
    func TypeText(typeInfo: TypeInfo): string {
        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }

    // NL202 — THE ANNOTATION AND THE VALUE DISAGREE. The rich shape needs BOTH a file path and a
    // snippet for that line; a diagnostic with either missing falls back to the detail-only shape,
    // which anchors the declaration rather than underlining the expression. THE SENTENCE IS THE SAME
    // ON BOTH ROUTES: it is computed once, above the branch, so the route production actually calls
    // cannot be the one that says less. Both are the same report in the same position.
    func ReportIfNotAssignable(declaration: VariableDeclarationStatement, declaredType: TypeInfo, inferredType: TypeInfo, initializer: Expression) {
        if assignabilityValue.IsAssignable(declaredType, inferredType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(initializer)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        declaredText := TypeText(declaredType)
        inferredText := TypeText(inferredType)
        message := "Variable '" + declaration.Name + "' is typed as '" + declaredText + "', but the value is '" + inferredText + "'"
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.TypeMismatch(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, inferredText, declaredText, message))
            return
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, message, declaration.Line, declaration.Column, null, 0)
    }

    // NL103 — a `const` is a compile-time value, so a `const` without one has nothing to be.
    func ReportConstWithoutInitializer(declaration: VariableDeclarationStatement, declaredType: TypeInfo) {
        span := AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(declaration)
        declaredText := TypeText(declaredType)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "A 'const' must have an initial value — the compiler needs to know its value at compile time", span.Line, span.Column, "Add an initializer, for example `const " + declaration.Name + ": " + declaredText + " = 42`.", span.Length)
    }

    // NL202 — a void call produces nothing, so there is nothing to store. The report underlines the
    // initializer when there is one; the fallback anchor is the declaration's own name, which is
    // unreachable from source (this arm is only entered with an inferred type) and is preserved
    // rather than dropped.
    func ReportVoidInitializer(declaration: VariableDeclarationStatement, initializer: Expression?) {
        span := new DiagnosticSpan(declaration.Line, declaration.Column, Math.Max(1, declaration.Name.Length))
        if initializer != null {
            span = spansValue.GetExpressionDiagnosticSpan(initializer)
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, "This expression doesn't return a value (it's void) — you can't assign it to a variable", span.Line, span.Column, null, span.Length)
    }

    // NL103 — no annotation and no initializer leaves nothing to infer from.
    func ReportUndeterminedType(declaration: VariableDeclarationStatement) {
        span := AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(declaration)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "I can't determine the type of this variable — give it a type annotation or an initial value", span.Line, span.Column, "Add a type annotation like `let " + declaration.Name + ": int`, or add an initializer like `let " + declaration.Name + " := 0`.", span.Length)
    }
}
