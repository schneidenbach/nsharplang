namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// THE ONE STEP A COMPILE-TIME CONSTANT CANNOT TAKE FOR ITSELF.
//
// THREE OF THE FOUR FORMS ASK FOR NOTHING AT ALL. `typeof`, `sizeof` and `default` are answered from
// the node, the written type reference and the target-typing slot, and every fact they consult — the
// type resolver, the well-known-type bag, the ambient context and the declared-alias resolver — is
// already reachable without leaving N#. Their walks take ZERO steps: the driver's loop body never
// runs and it returns the answer the entry already had.
//
// THE FOURTH IS `nameof`, AND IT IS THE REASON THIS WALK USES SLICE 49'S PROTOCOL RATHER THAN A
// FUNCTION. Its target is an expression the analyzer must walk, and this walk cannot walk one: that
// door is `AnalyzeExpression`, the very thing this territory is being taken from. So `nameof`
// SUSPENDS once and resumes WITH THE TARGET'S TYPE, because that type is the OPERAND of the
// row-escape report that runs immediately after it. The step count is a pure function of the form
// (exactly one, always); the operand is not.
//
// The kinds:
//   1  analyse an EXPRESSION — the `nameof` target. It ANSWERS a type, and that answer is the
//      row-escape report's second argument. There is no kind 2: nothing else in this family is
//      beyond the walk's own reach. The walk establishes no expected type of its own for the step, so
//      the target inherits whatever the target-typing slot already held — which is why
//      `n: string = nameof(default)` refuses the SHAPE and does not also fail to infer.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class CompileTimeConstantRequest {
    Kind: int
    Node: Expression?
    Line: int
    Column: int

    constructor(kind: int, node: Expression?, line: int, column: int) {
        Kind = kind
        Node = node
        Line = line
        Column = column
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` names which constant this is — 0 `typeof`, 1 `sizeof`, 2 `nameof`, 3 `default`, and -1 for
// a node that is none of them. It is on the state rather than inferred at each suspension because
// three of the four never suspend and the fourth must be told apart from them by the contracts that
// assert the empty walk.
//
// `ResultType` IS THE ANSWER THE DISPATCH GETS BACK, and it is decided at `Begin` for every one of
// the four forms. For `default` that is not a convenience but a requirement: the target-typing slot
// must be read AT THE INSTANT THE DISPATCH REACHED THE NODE, which is what slice 49 pinned for the
// suffixless integer literal and what `Analyzer.cs` did when its arm read `_ambient.CurrentExpectedType`
// before anything else could move it. For `nameof` it is what makes the walk legible: a `nameof` is a
// `string` whatever its target turns out to be, including when the target is refused outright.
//
// `NameofNode` is held only so the phase AFTER the step can find the target again. `TargetType` is that
// step's answer, folded in by `Supply` and consumed by the phase that runs the escape report. It is
// never the walk's own answer.
class CompileTimeConstantState {
    formValue: int
    nameofNodeValue: NameofExpression?

    Form: int => formValue
    NameofNode: NameofExpression? => nameofNodeValue

    Phase: int
    Pending: int
    TargetType: TypeInfo
    ResultType: TypeInfo

    constructor(form: int, nameofNode: NameofExpression?, resultType: TypeInfo) {
        formValue = form
        nameofNodeValue = nameofNode
        Phase = 0
        Pending = 0
        TargetType = BuiltInTypes.Unknown
        ResultType = resultType
    }
}

// WHAT THE COMPILER KNOWS ABOUT A TYPE WITHOUT EVALUATING ANYTHING.
//
// FOUR OPERATORS, ONE QUESTION. `typeof`, `sizeof`, `nameof` and `default` are the expression walk's
// answers that need no run-time value at all: a type token, a width, a name and a zero. They are one
// family rather than four arms because they share the shape that decides the cost — none of them
// evaluates its operand, and the only walking any of them does is the one `nameof` must do to find
// out whether its target is nameable.
//
// IT OWNS WHAT EACH OF THE FOUR IS:
//   * that `typeof` VALIDATES its written type reference and then discards the result — the
//     resolution exists for the diagnostics it raises, not for the answer — and that the answer is a
//     live `System.Type` from the analyzer's own metadata context, or `unknown` when there is no
//     metadata context at all. It is never the operand's type;
//   * that `sizeof` validates its type reference the same way and is always `int`, whatever the
//     operand type's real width is: the analyzer reports the TYPE of the expression, and every
//     `sizeof` in the language is an `int`;
//   * that `nameof` ANALYSES its target — so a broken target still reports — and is a `string` on
//     every path, including the two that refuse it; that a target which escapes an SoA row is
//     refused and STOPS, so a row-view target is told one thing and not two; and that only an
//     identifier or a member access can be named, because those are the only two shapes the IL
//     backend lowers to a string literal;
//   * that `default` is TARGET-TYPED and nothing else — it is the ambient expected type when there is
//     one, and an NL203 with no answer when there is not — and that an SoA table can never be
//     default-initialised, because a defaulted table's backing column arrays would all be null.
//
// IT IS AN OBJECT RATHER THAN A STATIC because five of its facts are ambient: the target-typing slot,
// the declared-alias resolver that slot is read through, the SoA escape reporter, the type resolver
// and the diagnostic sink and span reader the two reports it owns are written to. All six
// collaborators are constructed exactly once by `Analyzer.cs` and none is rebuilt with the metadata
// load context, so holding them is safe. THE WELL-KNOWN-TYPE BAG IS NOT HELD: it is the one thing the
// metadata load context both REBUILDS and NULLS, so it arrives at `Begin` as an argument, read at the
// same instant as the target-typing slot.
class AnalyzerCompileTimeConstants {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    declarationContextValue: AnalyzerDeclarationContext
    typeResolverValue: AnalyzerTypeResolver
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, declarationContext: AnalyzerDeclarationContext, typeResolver: AnalyzerTypeResolver, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape) {
        diagnosticsValue = diagnostics
        spansValue = spans
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        ambientValue = ambient
        soaEscapeValue = soaEscape
    }

    // THE ENTRY, AND IT DECIDES THE ANSWER. Every form's type is settled here; only `nameof` has
    // anything left to do afterwards, and what it has left to do cannot change what it answers. The
    // two type-reference resolutions and `default`'s whole rule — including both of its diagnostics —
    // run HERE, in the order `Analyzer.cs`'s four arms ran them, because none of them needs a step.
    //
    // A node that is not one of the four answers `unknown` and takes no steps — the dispatch never
    // hands one over, and the walk says so rather than guessing.
    func Begin(expression: Expression, wellKnownTypes: AnalyzerWellKnownTypes?): CompileTimeConstantState {
        typeOf := expression as TypeOfExpression
        if typeOf != null {
            typeResolverValue.ResolveType(typeOf.Type)
            return new CompileTimeConstantState(0, null, SystemTypeAnswer(wellKnownTypes))
        }

        sizeOf := expression as SizeOfExpression
        if sizeOf != null {
            typeResolverValue.ResolveType(sizeOf.Type)
            return new CompileTimeConstantState(1, null, BuiltInTypes.Int)
        }

        nameOf := expression as NameofExpression
        if nameOf != null {
            return new CompileTimeConstantState(2, nameOf, BuiltInTypes.String)
        }

        defaultValue := expression as DefaultExpression
        if defaultValue != null {
            return new CompileTimeConstantState(3, null, DefaultValueType(defaultValue))
        }

        return new CompileTimeConstantState(-1, null, BuiltInTypes.Unknown)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished. Three of the four
    // forms answer null on the first call.
    func NextStep(state: CompileTimeConstantState): CompileTimeConstantRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP: the `nameof` target's type, which is the row-escape report's
    // operand. A walk that asked for nothing folds in nothing, and a null answer is `unknown` rather
    // than a missing one — the analyzer's expression walk never answers null, and a walk that saw one
    // would otherwise carry it into a report.
    func Supply(state: CompileTimeConstantState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending != 1 {
            return
        }

        if answer != null {
            state.TargetType = answer
        } else {
            state.TargetType = BuiltInTypes.Unknown
        }
    }

    // WHAT THE WALK ANSWERS, which is what the dispatch hands to its caller. It is defined before the
    // first step and is unchanged by every step there is, which is exactly why a `nameof` whose target
    // fails to analyse is still a `string`.
    func Result(state: CompileTimeConstantState): TypeInfo {
        return state.ResultType
    }

    func Advance(state: CompileTimeConstantState): CompileTimeConstantRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceEntry(state)
        }

        if phase == 1 {
            return AdvanceNameofChecks(state)
        }

        state.Phase = 99
        return null
    }

    // THE FORK, AND THREE OF FOUR FORMS TAKE THE SHORT ARM. Only `nameof` has an operand to walk;
    // every other form is finished the moment it began.
    func AdvanceEntry(state: CompileTimeConstantState): CompileTimeConstantRequest? {
        nameOf := state.NameofNode
        if state.Form != 2 {
            state.Phase = 99
            return null
        }

        if nameOf == null {
            state.Phase = 99
            return null
        }

        state.Pending = 1
        state.Phase = 1
        return new CompileTimeConstantRequest(1, nameOf.Target, nameOf.Target.Line, nameOf.Target.Column)
    }

    // WHAT A `nameof` TARGET MAY BE, ASKED IN THE ONLY ORDER THAT WORKS. The SoA row escape is refused
    // FIRST and STOPS: a row view is not an identifier the backend can lower either, and reporting the
    // shape rule on top of it would tell one mistake twice. Only then is the shape checked, and only
    // an identifier or a member access passes, because those are the only two forms `nameof` lowers to
    // a string literal. Neither report changes the answer.
    func AdvanceNameofChecks(state: CompileTimeConstantState): CompileTimeConstantRequest? {
        state.Phase = 99
        nameOf := state.NameofNode
        if nameOf == null {
            return null
        }

        target := nameOf.Target
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(target, state.TargetType, "used as a nameof target") {
            return null
        }

        identifier := target as IdentifierExpression
        if identifier != null {
            return null
        }

        member := target as MemberAccessExpression
        if member != null {
            return null
        }

        span := spansValue.GetExpressionDiagnosticSpan(target)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "nameof can only name an identifier or member access", span.Line, span.Column, "Use nameof(value) or nameof(value.Member).", span.Length)
        return null
    }

    // WHAT `typeof` ANSWERS. The analyzer reasons about the project's own reference set rather than
    // the compiler's, so `System.Type` comes from the metadata context's bag and never from a
    // `typeof(...)` here. With no metadata context there is no honest answer, and `unknown` is what
    // the walk says rather than reaching for the compiler's own runtime type.
    func SystemTypeAnswer(wellKnownTypes: AnalyzerWellKnownTypes?): TypeInfo {
        if wellKnownTypes == null {
            return BuiltInTypes.Unknown
        }

        reflected: TypeInfo = new ReflectionTypeInfo(wellKnownTypes.SystemType)
        return reflected
    }

    // WHAT `default` IS, WHICH IS WHATEVER THE TARGET SAYS AND NOTHING ELSE. `default` is the only one
    // of the four that reads the target-typing slot, and it reads it ONCE, here, at the instant the
    // dispatch reached the node — the presence test, the SoA refusal's operand and the answer are all
    // the same read, because nothing between them can move the slot: the walk takes no step, and
    // neither report touches the ambient context.
    //
    // With no target there is no answer to give. That is an ERROR rather than an inference, because
    // `default` with nothing to be is not under-constrained — it is meaningless.
    func DefaultValueType(defaultValue: DefaultExpression): TypeInfo {
        expected := ambientValue.CurrentExpectedType
        if expected == null {
            diagnosticsValue.Report(ErrorCode.CannotInferType, "I can't figure out what type 'default' should be here — add a type annotation so I know what you mean (e.g., 'let x: int = default')", defaultValue.Line, defaultValue.Column, null, "default".Length)
            return BuiltInTypes.Unknown
        }

        if ReportSoaDefaultValueIfNeeded(defaultValue, expected) {
            return BuiltInTypes.Unknown
        }

        return expected
    }

    // WHY AN SoA TABLE CANNOT BE DEFAULTED. A defaulted table is a struct of null column arrays and a
    // zero length, which is not an empty table — it is a table every operation on which faults. The
    // two spellings that DO produce a valid table are named, because "cannot be default-initialized"
    // is only half an answer.
    func ReportSoaDefaultValueIfNeeded(defaultValue: DefaultExpression, expectedType: TypeInfo): bool {
        soaRecord := declarationContextValue.ResolveDeclaredAlias(NonNullableType(expectedType)) as SoaRecordTypeInfo
        if soaRecord == null {
            return false
        }

        tableName := soaRecord.Declaration.Name
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA table '" + tableName + "' cannot be default-initialized", defaultValue.Line, defaultValue.Column, "Use new " + tableName + "(capacity) or " + tableName + ".wrap(..., length: count) so every backing column array is valid.", "default".Length)
        return true
    }

    // The nullable unwrap `Analyzer.cs` performs before every structural question. Its C# original has
    // twenty-one other callers and therefore could not move; its two-call body is reproduced rather
    // than reached back for, which is what `AnalyzerSoaEscape`, `AnalyzerFunctionBodies`,
    // `AnalyzerLoopSequence` and `AnalyzerPatternShapes` each already do, so nothing here re-enters C#.
    func NonNullableType(candidate: TypeInfo): TypeInfo {
        nullable := declarationContextValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
    }
}
