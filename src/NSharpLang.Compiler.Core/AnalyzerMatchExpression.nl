namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// THE FIVE STEPS A `match` EXPRESSION TAKES, AND WHY TWO OF THEM ARE WALKS RATHER THAN ONE.
//
// `match` is the expression walk's only arm that opens a SCOPE, and it opens one PER ARM: a pattern's
// bindings are visible to that arm's guard and to that arm's value and to nothing else. Neither the
// scope stack nor the pattern walk is reachable from an owner, so both are driver kinds, and the walk
// suspends across every one of them.
//
//   1  analyse the MATCH VALUE. A PLAIN walk, under a bracket this owner opens and closes itself:
//      `Analyzer.cs` cleared the target-typing slot around it, because the value being matched is not
//      target-typed by whatever the match as a whole is assigned to. That is the slice-51 pattern —
//      the C# bracketed a plain `AnalyzeExpression`, so there is no lambda fork inside the step.
//   2  analyse a TARGET-TYPED expression: an arm's GUARD expecting `bool`, or an arm's VALUE expecting
//      whatever the match itself was expected to produce. This one is NOT owner-holdable and is
//      slice-52's fork: the C# called `AnalyzeExpressionWithExpectedType`, which routes a LAMBDA to
//      `AnalyzeLambda` with the expected type BEFORE any bracket opens, and an owner that merely set
//      the slot would type a lambda arm differently.
//   3  OPEN a block scope at the arm's pattern position.
//   4  ANALYSE the arm's PATTERN against the value's type, which binds its names into the scope
//      step 3 opened. It re-enters the pattern family's own driver, exactly as a nested pattern does.
//   5  CLOSE the scope.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class MatchExpressionRequest {
    Kind: int
    Node: Expression?
    ExpectedType: TypeInfo?
    PatternNode: Pattern?
    CarriedType: TypeInfo
    Line: int
    Column: int

    constructor(kind: int, node: Expression?, expectedType: TypeInfo?, patternNode: Pattern?, carriedType: TypeInfo, line: int, column: int) {
        Kind = kind
        Node = node
        ExpectedType = expectedType
        PatternNode = patternNode
        CarriedType = carriedType
        Line = line
        Column = column
    }
}

// THE WHOLE STATE, SUSPENDED ACROSS FIVE KINDS AND AN UNBOUNDED NUMBER OF ARMS.
//
// `Phase` alternates between READY (even) and OUTSTANDING (odd): 0 nothing asked → 1 the value step
// is outstanding and the cleared-slot bracket is OPEN → 2 ready to open an arm's scope → 3 the scope
// open is outstanding → 4 ready for the pattern → 5 the pattern is outstanding → 6 ready for the
// guard-or-value fork → 7 the guard is outstanding → 8 ready for the arm value → 9 the arm value is
// outstanding → 10 ready to close → 11 the close is outstanding → back to 2 for the next arm → 99
// (finished, exhaustiveness checked). A guard-less arm walks 6 straight to 8 without a step.
//
// `ExpectedResultType` is read ONCE, at `Begin`, and that timing is behaviour: the value walk clears
// the slot, so an owner that read it later would read a null that the arms are then target-typed
// against. `ValueType` is the match value's type AFTER the escape rules have had their say — either
// escape replaces it with `unknown`, which is what stops the exhaustiveness check from reasoning
// about a type the value was refused permission to have.
//
// `ResultType` is null until the FIRST arm answers and is the join so far. `CaseIndex` is the arm
// cursor. `SavedExpectedType` holds the slot's previous value while phase 1's bracket is open.
class MatchExpressionState {
    matchValue: MatchExpression?

    Match: MatchExpression? => matchValue

    Phase: int
    CaseIndex: int
    ExpectedResultType: TypeInfo?
    ValueType: TypeInfo
    ResultType: TypeInfo?
    SavedExpectedType: TypeInfo?

    constructor(matchExpression: MatchExpression?, expectedResultType: TypeInfo?) {
        matchValue = matchExpression
        Phase = 0
        CaseIndex = 0
        ExpectedResultType = expectedResultType
        ValueType = BuiltInTypes.Unknown
        ResultType = null
        SavedExpectedType = null
    }
}

// WHAT A `match` EXPRESSION MEANS: what its arms may be, what type it produces, and who is told what
// when they disagree.
//
// THE ARM JOIN IS NOT A COMMON-TYPE COMPUTATION, AND THAT IS THE ARM'S MOST IMPORTANT — AND MOST
// UNDER-SPECIFIED — RULE. The first arm's type becomes the result. Every later arm is asked only
// whether it is assignable to the result OR the result to it, and if EITHER holds the result is left
// EXACTLY AS IT WAS. It is not widened to the more general of the two and it is not re-joined; a
// `match` whose first arm is a `Dog` and whose second is an `Animal` types as `Dog`. Only when
// NEITHER direction is assignable is a common type looked for at all, and only then can the result
// change. This is `Analyzer.cs`'s behaviour to the branch and it is preserved rather than improved,
// because improving it is a language decision and not a port's.
//
// EVERY ARM IS TARGET-TYPED AGAINST THE MATCH'S OWN EXPECTED TYPE, never against the arm before it.
// A `match` assigned to an `IShape?` offers every arm `IShape?`, so a `null` arm and a `new Circle()`
// arm both bind against the declared target rather than against each other.
//
// THE COMMON-TYPE SEARCH IS REFLECTED-ONLY AND ORDERED. It applies when BOTH sides are reflected CLR
// types, and it prefers a SHARED INTERFACE — walked in the FIRST type's own interface order, which is
// the CLR's declaration order and is therefore stable — over a shared BASE CLASS, which is walked
// upward from the first type and stops before `object`. Anything else, including two source types
// that share a declared base, answers "no common type" and the arms are told they disagree. That
// asymmetry is deliberate: this rule exists for the reflected hierarchies (an `IActionResult`
// returned as two different concrete results) that the assignability oracle cannot join.
//
// THE ONE CODE IT OWNS: NL202 once, underlined at the DISAGREEING ARM rather than at the match, and
// worded to name both the first arm's type and this one's — so a developer reads which two arms are
// in conflict rather than that "the types do not match".
//
// WHAT IT DOES NOT OWN: both SoA escapes (asked of `AnalyzerSoaEscape`, on the value and on every
// arm), the guard's boolean rule (asked of `AnalyzerBooleanConditions`, which owns NL313 and both of
// its own escapes) and EXHAUSTIVENESS (asked of `AnalyzerMatchExhaustiveness`, which owns the four
// scrutinee families and their reports). This arm decides WHEN each is asked and about WHAT, and
// nothing about what any of them answers.
//
// THE EXHAUSTIVENESS CHECK RUNS LAST, AFTER EVERY ARM, AND ON THE POST-ESCAPE VALUE TYPE. Running it
// last is what lets an arm's own analysis report first; running it on the post-escape type is what
// keeps it silent about a value that was already refused.
class AnalyzerMatchExpression {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape
    conditionsValue: AnalyzerBooleanConditions
    assignabilityValue: AnalyzerAssignability
    matchExhaustivenessValue: AnalyzerMatchExhaustiveness

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape, conditions: AnalyzerBooleanConditions, assignability: AnalyzerAssignability, matchExhaustiveness: AnalyzerMatchExhaustiveness) {
        diagnosticsValue = diagnostics
        spansValue = spans
        ambientValue = ambient
        soaEscapeValue = soaEscape
        conditionsValue = conditions
        assignabilityValue = assignability
        matchExhaustivenessValue = matchExhaustiveness
    }

    // THE EXPECTED TYPE IS CAPTURED HERE AND NOWHERE ELSE. The very next thing that happens is that
    // the slot is cleared for the value walk, so reading it later would read the clear.
    func Begin(expression: Expression): MatchExpressionState {
        return new MatchExpressionState(expression as MatchExpression, ambientValue.CurrentExpectedType)
    }

    // THE PHASE NUMBERS ARE OUTSTANDING-STEP MARKERS, NOT A COUNT. An ODD phase means a step is
    // outstanding and `Supply` is what advances it; an EVEN phase means the walk is ready to hand the
    // next one out. 0 nothing asked; 1 the value walk; 2 ready to open an arm's scope; 3 the scope
    // open; 4 ready for the pattern; 5 the pattern; 6 ready for the guard-or-value fork; 7 the guard;
    // 8 ready for the arm value; 9 the arm value; 10 ready to close; 11 the close; 99 finished.
    func NextStep(state: MatchExpressionState): MatchExpressionRequest? {
        matchExpression := state.Match
        if matchExpression == null {
            state.Phase = 99
            return null
        }

        if state.Phase == 0 {
            // The bracket opens in the same instant the step is handed out, and closes in `Supply`.
            state.SavedExpectedType = ambientValue.EnterExpectedType(null)
            state.Phase = 1
            return new MatchExpressionRequest(1, matchExpression.Value, null, null, BuiltInTypes.Unknown, 0, 0)
        }

        cases := matchExpression.Cases
        if state.Phase == 2 {
            if state.CaseIndex >= cases.Count {
                // EXHAUSTIVENESS IS THE LAST THING THAT HAPPENS, after every arm and on the
                // post-escape value type.
                state.Phase = 99
                matchExhaustivenessValue.Check(matchExpression, state.ValueType)
                return null
            }

            openingCase := cases[state.CaseIndex]
            state.Phase = 3
            return new MatchExpressionRequest(3, null, null, null, BuiltInTypes.Unknown, openingCase.Pattern.Line, openingCase.Pattern.Column)
        }

        if state.Phase >= 99 || state.CaseIndex >= cases.Count {
            return null
        }

        matchCase := cases[state.CaseIndex]
        if state.Phase == 4 {
            state.Phase = 5
            return new MatchExpressionRequest(4, null, null, matchCase.Pattern, state.ValueType, 0, 0)
        }

        if state.Phase == 6 {
            guard := matchCase.Guard
            if guard != null {
                state.Phase = 7
                return new MatchExpressionRequest(2, guard, BuiltInTypes.Bool, null, BuiltInTypes.Unknown, 0, 0)
            }

            state.Phase = 8
        }

        if state.Phase == 8 {
            state.Phase = 9
            return new MatchExpressionRequest(2, matchCase.Expression, state.ExpectedResultType, null, BuiltInTypes.Unknown, 0, 0)
        }

        if state.Phase == 10 {
            state.Phase = 11
            return new MatchExpressionRequest(5, null, null, null, BuiltInTypes.Unknown, 0, 0)
        }

        return null
    }

    func Supply(state: MatchExpressionState, answer: TypeInfo?) {
        matchExpression := state.Match
        if matchExpression == null {
            state.Phase = 99
            return
        }

        answered: TypeInfo = BuiltInTypes.Unknown
        if answer != null {
            answered = answer
        }

        if state.Phase == 1 {
            // The bracket closes HERE rather than in the phase handler, because the handler runs on
            // the NEXT `NextStep` — one call later than the C#'s `finally` around the walk.
            ambientValue.ExitExpectedType(state.SavedExpectedType)
            state.SavedExpectedType = null
            state.ValueType = ValueTypeAfterEscapes(matchExpression.Value, answered)
            state.Phase = 2
            return
        }

        if state.Phase == 3 {
            state.Phase = 4
            return
        }

        if state.Phase == 5 {
            state.Phase = 6
            return
        }

        if state.Phase == 11 {
            state.CaseIndex = state.CaseIndex + 1
            state.Phase = 2
            return
        }

        cases := matchExpression.Cases
        if state.CaseIndex >= cases.Count {
            state.Phase = 99
            return
        }

        matchCase := cases[state.CaseIndex]
        if state.Phase == 7 {
            guard := matchCase.Guard
            if guard != null {
                conditionsValue.ReportMatchGuardTypeMismatchIfNeeded(guard, answered, assignabilityValue)
            }

            state.Phase = 8
            return
        }

        if state.Phase == 9 {
            JoinArm(state, matchCase.Expression, answered)
            state.Phase = 10
        }
    }

    // AN UNMATCHED `match` IS `unknown`, NOT AN ERROR. A `match` with no arms at all produces the
    // same `unknown` a refused arm would, and the exhaustiveness family is what has already said
    // whatever there was to say about it.
    func Result(state: MatchExpressionState): TypeInfo {
        state.Phase = 99
        resultType := state.ResultType
        if resultType != null {
            return resultType
        }

        return BuiltInTypes.Unknown
    }

    // EITHER ESCAPE REPLACES THE VALUE'S TYPE WITH `unknown`, AND THE SECOND IS NOT ASKED WHEN THE
    // FIRST FIRED — `Analyzer.cs`'s `if / else if`, preserved as written.
    func ValueTypeAfterEscapes(value: Expression, valueType: TypeInfo): TypeInfo {
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(value, valueType, "used as a match value") {
            return BuiltInTypes.Unknown
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(value, "used as a match value") {
            return BuiltInTypes.Unknown
        }

        return valueType
    }

    // THE JOIN, AND ITS ONE REPORT. The escapes run first and on the ARM's expression with the ARM's
    // wording, and a refused arm still participates in the join — as `unknown`, which is assignable
    // both ways and therefore never disagrees with anything.
    func JoinArm(state: MatchExpressionState, armExpression: Expression, armType: TypeInfo) {
        caseType := armType
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(armExpression, caseType, "used as a match result") {
            caseType = BuiltInTypes.Unknown
        } else if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(armExpression, "used as a match result") {
            caseType = BuiltInTypes.Unknown
        }

        resultType := state.ResultType
        if resultType == null {
            state.ResultType = caseType
            return
        }

        if assignabilityValue.IsAssignable(resultType, caseType) || assignabilityValue.IsAssignable(caseType, resultType) {
            return
        }

        commonType := FindCommonBaseType(resultType, caseType)
        if commonType != null {
            state.ResultType = commonType
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(armExpression)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "All match arms must return the same type — the first arm returns '" + TypeText(resultType) + "', but this arm returns '" + TypeText(caseType) + "'", span.Line, span.Column, null, span.Length)
    }

    // A SHARED INTERFACE BEATS A SHARED BASE, AND BOTH ARE WALKED FROM THE FIRST TYPE. `object` is
    // deliberately not an answer: joining two unrelated reflected types at `object` would silence a
    // disagreement the developer needs to see.
    static func FindCommonBaseType(first: TypeInfo, second: TypeInfo): TypeInfo? {
        reflectedFirst := first as ReflectionTypeInfo
        reflectedSecond := second as ReflectionTypeInfo
        if reflectedFirst == null || reflectedSecond == null {
            return null
        }

        firstClrType := reflectedFirst.Type
        secondClrType := reflectedSecond.Type
        interfacesFirst := firstClrType.GetInterfaces()
        interfacesSecond := secondClrType.GetInterfaces()
        for candidate in interfacesFirst {
            for other in interfacesSecond {
                if candidate == other {
                    return new ReflectionTypeInfo(candidate)
                }
            }
        }

        objectType := typeof(object)
        current := firstClrType.get_BaseType()
        while current != null && current != objectType {
            declaredBase := current
            if declaredBase.IsAssignableFrom(secondClrType) {
                return new ReflectionTypeInfo(declaredBase)
            }

            current = declaredBase.get_BaseType()
        }

        return null
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
