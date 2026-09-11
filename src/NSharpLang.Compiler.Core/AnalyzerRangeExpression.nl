namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// THE ONE STEP A RANGE TAKES, HANDED OUT UP TO TWICE.
//
// `a..b`, `a..`, `..b` and `..` have at most TWO operands, both walked by the ordinary expression
// dispatch with the ambient slot untouched. There is no bracket anywhere in this arm — not an
// expected type, not a scope, not a suppression — which makes it the SMALLEST resumable owner in the
// estate and the only one whose driver is a bare `AnalyzeExpression` relay with no operand but the
// node.
//
//   1  analyse an ENDPOINT expression, with nothing bracketed. It is handed out once for `Start` if
//      the syntax has one and once for `End` if the syntax has one, in that order, and NEITHER is
//      handed out when the endpoint is absent — `..` asks for nothing at all and still answers.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class RangeExpressionRequest {
    Kind: int
    Node: Expression?

    constructor(kind: int, node: Expression?) {
        Kind = kind
        Node = node
    }
}

// THE WHOLE STATE, SUSPENDED ACROSS AT MOST TWO STEPS.
//
// `Phase` runs 0 (nothing asked) → 1 (the start step is outstanding) → 2 (start settled, end not yet
// handed out) → 3 (the end step is outstanding) → 99 (finished). Phases 0 and 2 are the DECIDING
// phases and both may skip straight past their step, because an absent endpoint is not walked at all
// rather than walked as a null.
//
// Nothing else is carried. The endpoint types are consumed by the check the instant they arrive and
// never read again, and the RESULT does not depend on either of them: every range expression is a
// `System.Range` whatever its bounds turned out to be, which is why a refused bound still produces a
// usable type and the diagnostics below it are about the bound rather than about the range.
class RangeExpressionState {
    rangeValue: RangeExpression?

    Range: RangeExpression? => rangeValue

    Phase: int

    constructor(range: RangeExpression?) {
        rangeValue = range
        Phase = 0
    }
}

// WHAT A RANGE EXPRESSION MEANS, AND WHAT A RANGE BOUND MAY BE.
//
// TWO RULES, AND THE ORDER BETWEEN THEM IS BEHAVIOUR. For each endpoint the SoA escapes are asked
// first and the endpoint TYPE question second, and a value the analyzer has already refused to let
// leave its record is NOT additionally told it is the wrong type — the developer is owed the escape,
// which is the real defect, not a type complaint about a value that was never going to be allowed
// through. The two escapes SHORT-CIRCUIT against each other, which is `Analyzer.cs`'s own
// `!row && !directColumn`: a bound that is a row view never reaches the direct-column probe.
//
// THE ONE CODE IT OWNS: NL202 once, for a bound that is neither an `int` nor a `System.Index`. It is
// deliberately permissive about `unknown` — a bound whose type could not be worked out is not
// complained about, because the complaint the developer is owed has already been raised somewhere
// below it.
//
// WHAT AN `int` BOUND IS, IS THE ASSIGNABILITY ORACLE'S ANSWER RATHER THAN A TYPE-NAME TEST. The
// endpoint is alias-resolved and then asked whether an `int` may be assigned FROM it, which is what
// admits a `byte` counter, a user alias of `int`, and an enum-free numeric widening while refusing a
// `long`. `System.Index` is tested through the index family's already-published predicate rather than
// reproduced, which is the same routing slice 58 took for `IsRangeLikeType`.
//
// THE TYPE IT ANSWERS is `System.Range` looked up in the scope stack first and fell back to the CLR's
// own only when the project has no name for it — the lookup is what lets a project that has imported
// `System` see its own resolved symbol rather than a reflected stand-in.
class AnalyzerRangeExpression {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    soaEscapeValue: AnalyzerSoaEscape
    assignabilityValue: AnalyzerAssignability

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, soaEscape: AnalyzerSoaEscape, assignability: AnalyzerAssignability) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        soaEscapeValue = soaEscape
        assignabilityValue = assignability
    }

    func Begin(expression: Expression): RangeExpressionState {
        return new RangeExpressionState(expression as RangeExpression)
    }

    // The two deciding phases both fall through to the next when their endpoint is absent, so `..`
    // reaches phase 99 without a single step and the driver's loop body never runs.
    func NextStep(state: RangeExpressionState): RangeExpressionRequest? {
        range := state.Range
        if range == null {
            state.Phase = 99
            return null
        }

        if state.Phase == 0 {
            start := range.Start
            if start != null {
                state.Phase = 1
                return new RangeExpressionRequest(1, start)
            }

            state.Phase = 2
        }

        if state.Phase == 2 {
            rangeEnd := range.End
            if rangeEnd != null {
                state.Phase = 3
                return new RangeExpressionRequest(1, rangeEnd)
            }

            state.Phase = 99
        }

        return null
    }

    func Supply(state: RangeExpressionState, answer: TypeInfo?) {
        range := state.Range
        if range == null {
            state.Phase = 99
            return
        }

        endpointType: TypeInfo = BuiltInTypes.Unknown
        if answer != null {
            endpointType = answer
        }

        if state.Phase == 1 {
            start := range.Start
            if start != null {
                CheckEndpoint(start, endpointType)
            }

            state.Phase = 2
            return
        }

        if state.Phase == 3 {
            rangeEnd := range.End
            if rangeEnd != null {
                CheckEndpoint(rangeEnd, endpointType)
            }
        }

        state.Phase = 99
    }

    // EVERY RANGE IS A `System.Range`, whatever happened to its bounds. The result does not read the
    // state at all, which is why a range whose bounds were both refused still types the expression
    // around it and produces no cascade.
    func Result(state: RangeExpressionState): TypeInfo {
        state.Phase = 99
        return RangeType()
    }

    // THE ESCAPES SHORT-CIRCUIT, AND THAT IS DELIBERATE RATHER THAN INCIDENTAL. `Analyzer.cs` wrote
    // `!row && !directColumn`, so a bound that is a ROW VIEW is told exactly that and the
    // direct-column probe is NEVER RUN on it. This is the opposite of the boolean-condition family,
    // which evaluates both because its C# wrote them out separately — the two shapes look alike and
    // are not, and a bound cannot be both a row view and a direct column anyway.
    func CheckEndpoint(endpoint: Expression, endpointType: TypeInfo) {
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(endpoint, endpointType, "used as a range bound") {
            return
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(endpoint, "used as a range bound") {
            return
        }

        if BuiltInTypes.IsUnknown(endpointType) || IsRangeEndpointType(endpointType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(endpoint)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "Range bounds must be int or System.Index, but this bound has type '" + TypeText(endpointType) + "'", span.Line, span.Column, "Use an int bound, '^n' with an int count, or convert the value before building the range.", span.Length)
    }

    func IsRangeEndpointType(candidate: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        return AnalyzerIndexAccess.IsIndexLikeType(resolved) || assignabilityValue.IsAssignable(BuiltInTypes.Int, resolved)
    }

    // THE PROJECT'S OWN `System.Range` FIRST. The reflected fallback is what a project that never
    // named the type gets, and it is the same instance `Analyzer.cs` produced.
    func RangeType(): TypeInfo {
        declared := scopesValue.LookupType("System.Range")
        if declared != null {
            return declared
        }

        return new ReflectionTypeInfo(typeof(Range))
    }

    static func TypeText(candidate: TypeInfo): string {
        boxed := candidate as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}
