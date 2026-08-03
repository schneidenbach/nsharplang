namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast

// THE FIVE STEPS A LOCAL DECLARATION CANNOT TAKE FOR ITSELF, AND EVERYTHING EACH STEP NEEDS.
//
// The walk owns what `let x: T = e` MEANS — what the annotation resolves to, whether the initializer
// is assignable to it, which of the four type outcomes the declaration has, which of its five
// diagnostics fires and with which span and wording, which SoA escape report the resulting type
// selects, and what the local's null state is the instant it comes into existence. What it cannot do
// is run the analyzer's own EXPRESSION walk, call the two SoA escape reporters that belong to a
// different family, declare a symbol into the analyzer's scope stack, or write the semantic model
// the IDE reads — so it ASKS: one request at a time, each naming a kind and carrying every value the
// step needs. Nothing here is a policy the driver may reinterpret — the driver switches on `Kind`,
// performs exactly the one operation with exactly these operands, and hands the answer back.
//
// The kinds:
//   1  analyse the INITIALIZER expression under an expected type. ANSWERS a type, and that type is
//      the operand of three of the four steps that follow it.
//   2  the SoA row-view escape report. Answers nothing the walk reads.
//   3  the SoA direct-column escape report. Answers nothing the walk reads.
//   4  declare the local into the analyzer's scope stack, under the declaration kind carried here.
//   5  record the local in the semantic model the IDE's hover and completion read.
public class VariableDeclarationRequest {

    public Kind: int
    public Node: Expression?
    public Name: string?
    public CarriedType: TypeInfo
    public ExpectedType: TypeInfo?
    public Text: string?
    public Line: int
    public Column: int

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
// `Phase` is the walk's program counter: 0 resolves the annotation and asks for the initializer, 1
// folds the answer in and settles the type, and 2 through 5 are the four replayed operations in the
// order `Analyzer.cs` performed them. 99 is done.
//
// `DeclaredType` is settled at phase 0 and never changes. `InferredType` is the kind-1 answer and is
// null until it arrives; it is kept SEPARATELY from `FinalType` because the null-state rule at the
// end reads the initializer's OWN type rather than the declaration's, and those differ whenever an
// annotation widens or an initializer is void.
public class VariableDeclarationState {

    declarationValue: VariableDeclarationStatement

    Declaration: VariableDeclarationStatement => declarationValue

    public Phase: int
    public Pending: int

    public DeclaredType: TypeInfo?
    public InferredType: TypeInfo?
    public FinalType: TypeInfo

    constructor(declaration: VariableDeclarationStatement) {
        declarationValue = declaration
        Phase = 0
        Pending = 0
        DeclaredType = null
        InferredType = null
        FinalType = BuiltInTypes.Unknown
    }
}

// WHAT A LOCAL DECLARATION MEANS, as a walk that suspends at each step it cannot take itself.
//
// This is the FIRST member of the analyzer's expression/statement walker territory to move, and it
// was chosen by measurement rather than by size: of the five bounded statement arms at this tree it
// re-enters the FEWEST members that stay behind — five, every one of them already a driver-replayed
// kind the pattern walk shipped — and it re-enters the statement dispatch ZERO times, so it does not
// drag `AnalyzeStatement` in behind it.
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
// THE EXPECTED TYPE TRAVELS WITH THE REQUEST RATHER THAN BEING AMBIENT. `Analyzer.cs` set
// `_currentExpectedType` to the annotation around the initializer analysis so that a target-typed
// expression (`new()`, a collection literal) could read it. That flag stays in `Analyzer.cs` because
// the expression walker still reads it, but WHAT it is set to is this walk's answer, so the kind-1
// request carries it and the driver performs the same save / set / restore around the same one call.
//
// THE FOUR TYPE OUTCOMES AND THE FIVE DIAGNOSTICS ARE `Analyzer.cs`'s VERBATIM. An annotation with a
// non-assignable initializer reports NL202 in the rich `ErrorMessageBuilder` shape when the file and
// a snippet are both available and in the detail-only shape when either is missing — the SAME report
// in the SAME position, differing only in how much explanation it carries. A `const` with an
// annotation and no initializer reports NL103. A void initializer with no annotation reports NL202
// and the declaration falls back to unknown. A declaration with neither reports NL103. And an
// annotation ALWAYS wins the type, even when the initializer disagreed.
public class AnalyzerVariableDeclaration {

    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    typeResolverValue: AnalyzerTypeResolver
    assignabilityValue: AnalyzerAssignability
    nullFlowValue: AnalyzerNullFlow
    scopesValue: AnalyzerScopeStack

    constructor(
        diagnostics: AnalyzerDiagnosticSink,
        spans: AnalyzerDiagnosticSpans,
        typeResolver: AnalyzerTypeResolver,
        assignability: AnalyzerAssignability,
        nullFlow: AnalyzerNullFlow,
        scopes: AnalyzerScopeStack) {
        diagnosticsValue = diagnostics
        spansValue = spans
        typeResolverValue = typeResolver
        assignabilityValue = assignability
        nullFlowValue = nullFlow
        scopesValue = scopes
    }

    public func Begin(declaration: VariableDeclarationStatement): VariableDeclarationState {
        return new VariableDeclarationState(declaration)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this declaration is finished. Every phase
    // either decides something and advances, or emits exactly one request; the walk never advances
    // past a point whose answer it has not been given. The type diagnostics land HERE, between the
    // kind-1 step and the SoA step, which is exactly where `Analyzer.cs` reported them.
    public func NextStep(state: VariableDeclarationState): VariableDeclarationRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything this walk reads: the
    // initializer's type, which settles the declaration's type and three later operands. The two
    // escape reports and the two declaration steps answer nothing, and nothing is folded in for them.
    public func Supply(state: VariableDeclarationState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 {
            state.InferredType = answer
        }
    }

    func Advance(state: VariableDeclarationState): VariableDeclarationRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceAnnotation(state)
        }

        if phase == 1 {
            return AdvanceType(state)
        }

        if phase == 2 {
            return AdvanceEscape(state)
        }

        if phase == 3 {
            return AdvanceDeclare(state)
        }

        if phase == 4 {
            return AdvanceRecord(state)
        }

        if phase == 5 {
            return AdvanceNullState(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — the annotation, and the one step whose answer everything else depends on. A
    // declaration with no initializer skips straight to the type decision with no answer to wait for.
    func AdvanceAnnotation(state: VariableDeclarationState): VariableDeclarationRequest? {
        declaration := state.Declaration
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
    func AdvanceType(state: VariableDeclarationState): VariableDeclarationRequest? {
        declaration := state.Declaration
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
    func AdvanceEscape(state: VariableDeclarationState): VariableDeclarationRequest? {
        declaration := state.Declaration
        initializer := declaration.Initializer
        state.Phase = 3
        if initializer == null {
            return null
        }

        soaRow := state.FinalType as SoaRowTypeInfo
        kind := 3
        if soaRow != null {
            kind = 2
        }

        state.Pending = kind
        request := new VariableDeclarationRequest(kind, state.FinalType)
        request.Node = initializer
        request.Text = "stored in a variable"
        return request
    }

    // PHASE 3 — the local enters the analyzer's scope stack under the declaration kind `local`, which
    // is what makes it a local rather than a parameter or a field to everything that reads the scope.
    func AdvanceDeclare(state: VariableDeclarationState): VariableDeclarationRequest? {
        declaration := state.Declaration
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
    func AdvanceRecord(state: VariableDeclarationState): VariableDeclarationRequest? {
        declaration := state.Declaration
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
    func AdvanceNullState(state: VariableDeclarationState): VariableDeclarationRequest? {
        declaration := state.Declaration
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
                scopesValue.SetNullStateInCurrentScope(
                    declaration.Name,
                    nullFlowValue.GetExpressionNullState(initializer, inferredType))
                return null
            }

            scopesValue.SetNullStateInCurrentScope(
                declaration.Name,
                nullFlowValue.GetExpressionNullState(initializer, finalType))
            return null
        }

        scopesValue.SetNullStateInCurrentScope(
            declaration.Name,
            nullFlowValue.GetDefaultNullState(finalType))
        return null
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
    // which names the variable rather than underlining the expression. Both are the same report in
    // the same position.
    func ReportIfNotAssignable(
        declaration: VariableDeclarationStatement,
        declaredType: TypeInfo,
        inferredType: TypeInfo,
        initializer: Expression) {
        if assignabilityValue.IsAssignable(declaredType, inferredType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(initializer)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        declaredText := TypeText(declaredType)
        inferredText := TypeText(inferredType)
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.TypeMismatch(
                currentFilePath,
                span.Line,
                span.Column,
                sourceSnippet,
                span.Length,
                inferredText,
                declaredText))
            return
        }

        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            "Variable '" + declaration.Name + "' is typed as '" + declaredText
                + "', but the value is '" + inferredText + "'",
            declaration.Line,
            declaration.Column,
            null,
            0)
    }

    // NL103 — a `const` is a compile-time value, so a `const` without one has nothing to be.
    func ReportConstWithoutInitializer(
        declaration: VariableDeclarationStatement,
        declaredType: TypeInfo) {
        span := AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(declaration)
        declaredText := TypeText(declaredType)
        diagnosticsValue.Report(
            ErrorCode.InvalidSyntax,
            "A 'const' must have an initial value — the compiler needs to know its value at compile time",
            span.Line,
            span.Column,
            "Add an initializer, for example `const " + declaration.Name + ": " + declaredText + " = 42`.",
            span.Length)
    }

    // NL202 — a void call produces nothing, so there is nothing to store. The report underlines the
    // initializer when there is one; the fallback anchor is the declaration's own name, which is
    // unreachable from source (this arm is only entered with an inferred type) and is preserved
    // rather than dropped.
    func ReportVoidInitializer(
        declaration: VariableDeclarationStatement,
        initializer: Expression?) {
        span := new DiagnosticSpan(
            declaration.Line,
            declaration.Column,
            Math.Max(1, declaration.Name.Length))
        if initializer != null {
            span = spansValue.GetExpressionDiagnosticSpan(initializer)
        }

        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            "This expression doesn't return a value (it's void) — you can't assign it to a variable",
            span.Line,
            span.Column,
            null,
            span.Length)
    }

    // NL103 — no annotation and no initializer leaves nothing to infer from.
    func ReportUndeterminedType(declaration: VariableDeclarationStatement) {
        span := AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(declaration)
        diagnosticsValue.Report(
            ErrorCode.InvalidSyntax,
            "I can't determine the type of this variable — give it a type annotation or an initial value",
            span.Line,
            span.Column,
            "Add a type annotation like `let " + declaration.Name + ": int`, or add an initializer like `let "
                + declaration.Name + " := 0`.",
            span.Length)
    }
}
