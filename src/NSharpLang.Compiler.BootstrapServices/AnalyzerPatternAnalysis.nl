namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

// THE SIX STEPS THE PATTERN FAMILY CANNOT TAKE FOR ITSELF, AND EVERYTHING EACH STEP NEEDS.
//
// The walk owns what a pattern MEANS — which of the thirteen arms a pattern node takes, what each
// arm binds and under which name, which union case a dotted name or a case pattern names, what a
// case property resolves to under the scrutinee's substitution, which of the four diagnostics fires
// and where, and in what order all of it happens. It ALSO owns the statement that exists to dispatch
// on patterns: a `switch`, whose per-case scope is there for nothing but the bindings this walk
// declares into it. What it cannot do is run the analyzer's own EXPRESSION walk, declare a symbol
// into the analyzer's scope stack, open or close a scope on that stack, or re-enter the statement
// dispatch for a case body, so it ASKS: one request at a time, each naming a kind
// and carrying every value the step needs. Nothing here is a policy the driver may reinterpret — the
// driver switches on `Kind`, performs exactly the one operation with exactly these operands, and
// hands the answer back.
//
// The kinds:
//   1  analyse an EXPRESSION — a literal pattern's literal, a relational pattern's bound, or a
//      `switch` value. ANSWERS a type, and that type is the operand of the step that follows it.
//   4  declare a binding into the analyzer's scope stack.
//   5  analyse a NESTED pattern against the type this arm resolved for it. A `switch` case's own
//      pattern is this step too — the operation and its operands are identical — so the statement
//      form cost the driver nothing here.
//   6  open a block scope on the analyzer's scope stack at `Line` / `Column`.
//   7  analyse a statement LIST — a `switch` case's body — which re-enters the statement dispatch
//      and applies the unreachable-code rule to its contents.
//   8  close the scope kind 6 opened.
//
// The numbering has GAPS at 2 and 3 rather than closing up, because the kind number is a protocol
// between this walk and one driver, and a renumber would silently re-point every contract that pins
// a step's kind. The gaps say what left: 2 and 3 were the two SoA escape reports, and this walk
// HOLDS `AnalyzerSoaEscape` now — the switch value's two reports needed it held, and once it is
// held, relaying the literal and relational arms' reports through the driver would be asking C# to
// relay one N# call to another.
public class PatternAnalysisRequest {

    public Kind: int
    public Node: Expression?
    public Pattern: Pattern?
    public Statements: List<Statement>?
    public Name: string?
    public CarriedType: TypeInfo
    public Line: int
    public Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Pattern = null
        Statements = null
        Name = null
        CarriedType = carriedType
        Line = 0
        Column = 0
    }
}

// THE WALK'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// ONE state serves BOTH forms, because ONE driver serves them: `Form` 0 is a pattern node and
// `Form` 1 is a `switch` statement, and exactly one of `patternNodeValue` and `switchNodeValue` is
// set.
//
// `Phase` is the walk's program counter, and each form owns a BAND so a phase number never means two
// things: the pattern form runs 0 (the thirteen-way dispatch) with a band per multi-step arm, the
// switch form runs 70..75, and 99 is done for both. `Pending` records what the outstanding
// request asked for, so its answer is folded back into the right place. Everything else is one arm's
// working set, derived at the moment the C# member derived it and never before.
public class PatternAnalysisState {

    formValue: int
    patternNodeValue: Pattern?
    switchNodeValue: SwitchStatement?
    valueTypeValue: TypeInfo

    Form: int => formValue
    PatternNode: Pattern? => patternNodeValue
    SwitchNode: SwitchStatement? => switchNodeValue
    ValueType: TypeInfo => valueTypeValue

    public Phase: int
    public Pending: int
    public Index: int

    // The answer to the outstanding kind-1 analysis. It is an OPERAND of the step after it — the
    // literal arm's escape report, the relational arm's comparability judgement, and the switch
    // form's own escape reports all measure it. `Escaped` is what the relational arm's short-circuit
    // reads; both reports are direct calls now, so it is written here rather than supplied.
    public AnalyzedType: TypeInfo
    public Escaped: bool

    // The switch form's working set: the scrutinee type every case pattern is analysed against —
    // collapsed to `unknown` when the value escaped — and the ambient break-target depth the switch
    // saved on entry and must restore on the way out.
    public SwitchValueType: TypeInfo
    public SavedBreakDepth: int

    // The union-case arm's working set, settled once at dispatch: the owner a case property is
    // resolved against, the substitution the scrutinee's arguments induce, the case's rendered name,
    // the case's own property list and the pattern's.
    public UnionOwner: TypeInfo
    public UnionSubstitution: Dictionary<string, TypeInfo>?
    public UnionCaseName: string
    public CaseProperties: List<UnionCaseProperty>?
    public PatternProperties: List<PropertyPattern>?

    // The list arm's one element type, resolved once for the whole list exactly as the C# member
    // resolved it once above its loop.
    public ElementType: TypeInfo

    // The object arm's nested walk. The property walk is its own owner; this walk drives it and
    // forwards its two requests as its own, so `Analyzer.cs` never sees the composition.
    public PropertyState: PropertyPatternBindingState?

    constructor(
        form: int,
        patternNode: Pattern?,
        switchNode: SwitchStatement?,
        valueType: TypeInfo) {
        formValue = form
        patternNodeValue = patternNode
        switchNodeValue = switchNode
        valueTypeValue = valueType

        Phase = 0
        if form == 1 {
            Phase = 70
        }

        Pending = 0
        Index = 0
        AnalyzedType = BuiltInTypes.Unknown
        Escaped = false
        SwitchValueType = BuiltInTypes.Unknown
        SavedBreakDepth = 0
        UnionOwner = BuiltInTypes.Unknown
        UnionSubstitution = null
        UnionCaseName = ""
        CaseProperties = null
        PatternProperties = null
        ElementType = BuiltInTypes.Unknown
        PropertyState = null
    }
}

// WHAT A PATTERN MEANS — AND WHAT THE STATEMENT THAT DISPATCHES ON ONE MEANS — as a walk that
// suspends at each step it cannot take itself.
//
// This is the pattern family's LAST member and its root: every other owner the family has —
// exhaustiveness selection, the match-coverage decision, the list and relational shape questions,
// reachability, property-pattern binding — sits one layer below it and is called from here. Landing
// it leaves `Analyzer.cs` with no pattern POLICY at all, only a driver.
//
// THE `switch` STATEMENT IS THE SECOND FORM, AND IT IS HERE BECAUSE IT IS THE PATTERN FAMILY'S
// STATEMENT, NOT BECAUSE IT WAS CONVENIENT. A `switch` in N# is non-exhaustive dispatch on patterns
// and nothing else: its value is the scrutinee every case pattern is analysed against, and its
// per-case scope exists for nothing but the bindings THIS walk declares into it with kind 4 — before
// the move, the scope a binding landed in was opened by a caller the walk could not see. A DEDICATED
// owner with a driver of its own was measured first and refused: the driver alone is more C# than
// the arm it would delete, while here the case's pattern step IS kind 5 — the same operation with
// the same operands — so the statement form added THREE kinds and no loop.
//
// WHY A RESUMABLE WALK WITH ANSWERS RATHER THAN THE ANSWER-FREE REQUEST LOOP OF SLICE 28, AND THE
// MEASUREMENT SETTLED IT IN BOTH DIRECTIONS AT ONCE. The deciding question the family has asked
// every time is whether the STEP COUNT — or a step's OPERANDS — depend on an answer the walk does
// not have yet. For the property-pattern walk the answer was no on both counts, and the loop only
// had to yield so its own reports landed in list order. Here it is YES ON BOTH, and the three
// witnesses are different arms:
//   * A LITERAL pattern's two escape reports cannot be made until its ONE step has answered: the
//     row report is passed the literal's analysed type. No schedule computed up front carries that
//     operand.
//   * A RELATIONAL pattern's REPORT CHAIN is not even a fixed length. Its two escape reports are
//     joined by `&&` over their negations, so a row-view bound stops the chain before the
//     direct-column probe runs, and either one stops it before the comparability judgement does.
//   * A `switch`'s STEP COUNT is a function of its cases and its scrutinee type is the answer to its
//     own first step — every case pattern below it is measured against a type the walk does not have
//     until it has already suspended once.
// So this walk suspends and RESUMES WITH THE ANSWER, like slice 24's call walk and unlike slice 28's
// property walk. The distinction is recorded because the mechanism looks identical from the driver's
// side and the reason is not.
//
// THE SELF-RECURSION NEEDS NO STACK, and that is a property of the driver rather than an assumption.
// A nested pattern is delivered as a kind-5 request; the driver calls its own `AnalyzePattern`,
// which begins a FRESH state and runs a fresh loop, so the C# call stack carries the nesting exactly
// as it did before the move. One state is one pattern node, and no arm ever holds two.
//
// THE THIRTEENTH ARM IS THE ONE WITH NO CASE. `Analyzer.cs`'s switch had no `default`, so a pattern
// node of any other kind fell through in silence. That is preserved as an explicit terminal arm here
// rather than left implicit.
public class AnalyzerPatternAnalysis {

    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    typeResolverValue: AnalyzerTypeResolver
    typeSubstitutionValue: AnalyzerTypeSubstitution
    matchExhaustivenessValue: AnalyzerMatchExhaustiveness
    patternShapesValue: AnalyzerPatternShapes
    patternReachabilityValue: AnalyzerPatternReachability
    propertyPatternBindingValue: AnalyzerPropertyPatternBinding
    soaEscapeValue: AnalyzerSoaEscape
    ambientValue: AnalyzerAmbientContext

    constructor(
        diagnostics: AnalyzerDiagnosticSink,
        spans: AnalyzerDiagnosticSpans,
        typeResolver: AnalyzerTypeResolver,
        typeSubstitution: AnalyzerTypeSubstitution,
        matchExhaustiveness: AnalyzerMatchExhaustiveness,
        patternShapes: AnalyzerPatternShapes,
        patternReachability: AnalyzerPatternReachability,
        propertyPatternBinding: AnalyzerPropertyPatternBinding,
        soaEscape: AnalyzerSoaEscape,
        ambient: AnalyzerAmbientContext) {
        diagnosticsValue = diagnostics
        spansValue = spans
        typeResolverValue = typeResolver
        typeSubstitutionValue = typeSubstitution
        matchExhaustivenessValue = matchExhaustiveness
        patternShapesValue = patternShapes
        patternReachabilityValue = patternReachability
        propertyPatternBindingValue = propertyPatternBinding
        soaEscapeValue = soaEscape
        ambientValue = ambient
    }

    public func Begin(patternNode: Pattern, valueType: TypeInfo): PatternAnalysisState {
        return new PatternAnalysisState(0, patternNode, null, valueType)
    }

    // A `switch` STATEMENT. The scrutinee type is not known yet — the walk's own first step answers
    // it — so the state opens with `unknown` and the switch form settles `SwitchValueType` at
    // phase 71.
    public func BeginSwitch(switchNode: SwitchStatement): PatternAnalysisState {
        return new PatternAnalysisState(1, null, switchNode, BuiltInTypes.Unknown)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this pattern node is finished. Every phase
    // either decides something and advances, or emits exactly one request; the walk never advances
    // past a point whose answer it has not been given. Reports land here, BETWEEN two steps, which is
    // what keeps this walk's diagnostics in list order with the ones its nested analyses produce.
    public func NextStep(state: PatternAnalysisState): PatternAnalysisRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Kind 1 answers a type that a later step carries. Kinds 4,
    // 5, 6, 7 and 8 answer nothing and nothing is folded in for them, so this fold is now a single
    // question — the escape reports used to answer here and are direct calls on the held reporter.
    public func Supply(state: PatternAnalysisState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 {
            if answer != null {
                state.AnalyzedType = answer
            }
        }
    }

    // Each multi-step arm re-reads its own node off the state here. The cast cannot fail — a phase is
    // only ever entered from the arm that matched that node — and the guard is what lets the phase
    // body read the node as the type it is.
    func Advance(state: PatternAnalysisState): PatternAnalysisRequest? {
        phase := state.Phase
        if state.Form == 1 {
            switchNode := state.SwitchNode
            if switchNode != null {
                return AdvanceSwitch(state, switchNode, phase)
            }

            state.Phase = 99
            return null
        }

        if phase == 0 {
            return Dispatch(state)
        }

        if phase == 10 {
            literalPattern := state.PatternNode as LiteralPattern
            if literalPattern != null {
                return AdvanceLiteral(state, literalPattern)
            }
        } else if phase == 20 {
            relationalPattern := state.PatternNode as RelationalPattern
            if relationalPattern != null {
                return AdvanceRelational(state, relationalPattern)
            }
        } else if phase == 30 {
            return AdvanceUnionProperties(state)
        } else if phase == 40 {
            return AdvanceTwoChildren(state)
        } else if phase == 43 {
            positionalPattern := state.PatternNode as PositionalPattern
            if positionalPattern != null {
                return AdvancePositional(state, positionalPattern)
            }
        } else if phase == 50 {
            return AdvanceObject(state)
        } else if phase == 60 {
            listPattern := state.PatternNode as ListPattern
            if listPattern != null {
                return AdvanceList(state, listPattern)
            }
        }

        state.Phase = 99
        return null
    }

    // THE THIRTEEN-WAY DISPATCH, in the order `Analyzer.cs` tested it. Every pattern class derives
    // directly from `Pattern`, so no node can match two arms and the order is a reading convenience
    // rather than a precedence.
    func Dispatch(state: PatternAnalysisState): PatternAnalysisRequest? {
        patternNode := state.PatternNode
        if patternNode == null {
            state.Phase = 99
            return null
        }

        valueType := state.ValueType

        identifierPattern := patternNode as IdentifierPattern
        if identifierPattern != null {
            return DispatchIdentifier(state, identifierPattern)
        }

        literalPattern := patternNode as LiteralPattern
        if literalPattern != null {
            state.Phase = 10
            state.Pending = 1
            return ExpressionRequest(literalPattern.Literal)
        }

        unionCasePattern := patternNode as UnionCasePattern
        if unionCasePattern != null {
            return DispatchUnionCase(state, unionCasePattern)
        }

        relationalPattern := patternNode as RelationalPattern
        if relationalPattern != null {
            state.Phase = 20
            state.Pending = 1
            return ExpressionRequest(relationalPattern.Value)
        }

        andPattern := patternNode as AndPattern
        if andPattern != null {
            state.Index = 0
            state.Phase = 40
            return null
        }

        orPattern := patternNode as OrPattern
        if orPattern != null {
            state.Index = 0
            state.Phase = 40
            return null
        }

        notPattern := patternNode as NotPattern
        if notPattern != null {
            state.Phase = 99
            return PatternRequest(notPattern.Pattern, valueType)
        }

        positionalPattern := patternNode as PositionalPattern
        if positionalPattern != null {
            state.Index = 0
            state.Phase = 43
            return null
        }

        objectPattern := patternNode as ObjectPattern
        if objectPattern != null {
            state.PropertyState = propertyPatternBindingValue.Begin(
                objectPattern.Properties,
                valueType,
                patternNode.Line,
                patternNode.Column)
            state.Phase = 50
            return null
        }

        listPattern := patternNode as ListPattern
        if listPattern != null {
            state.ElementType = patternShapesValue.ResolveListPatternElementType(listPattern, valueType)
            state.Index = 0
            state.Phase = 60
            return null
        }

        slicePattern := patternNode as SlicePattern
        if slicePattern != null {
            // A slice outside a list pattern is not a shape the parser builds. The arm binds it to an
            // array of the SCRUTINEE rather than of an element type, and that is preserved verbatim.
            state.Phase = 99
            sliceBindingName := slicePattern.BindingName
            if sliceBindingName != null {
                return DeclareRequest(
                    sliceBindingName,
                    new ArrayTypeInfo(valueType),
                    patternNode.Line,
                    patternNode.Column)
            }

            return null
        }

        typePattern := patternNode as TypePattern
        if typePattern != null {
            return DispatchType(state, typePattern)
        }

        state.Phase = 99
        return null
    }

    // THE IDENTIFIER ARM'S THREE-WAY SPLIT, whose two guards are ordered behaviour. A NULLABLE
    // scrutinee narrows an undotted name to the inner type, and `_` is the discard that binds
    // nothing. Otherwise a DOTTED name over a declared union is a case reference: it binds nothing
    // and reports when the union has no such case. Everything else is a plain binding of the
    // scrutinee. The union lookup is reached only by a dotted name, exactly as the `&&` ordered it.
    func DispatchIdentifier(
        state: PatternAnalysisState,
        identifierPattern: IdentifierPattern): PatternAnalysisRequest? {
        state.Phase = 99
        valueType := state.ValueType
        name := identifierPattern.Name
        dotted := name.Contains('.')

        nullableValueType := valueType as NullableTypeInfo
        if nullableValueType != null && !dotted {
            if name != "_" {
                return DeclareRequest(
                    name,
                    nullableValueType.InnerType,
                    identifierPattern.Line,
                    identifierPattern.Column)
            }

            return null
        }

        if dotted {
            ignoredSubstitution: Dictionary<string, TypeInfo>? = null
            unionType := matchExhaustivenessValue.ResolveDeclaredUnionType(valueType, out ignoredSubstitution)
            if unionType != null {
                if AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(unionType, name) == null {
                    span := spansValue.GetPatternNameDiagnosticSpan(identifierPattern)
                    ReportUnknownCase(name, unionType, span)
                }

                // A union case named without properties has nothing to bind.
                return null
            }
        }

        return DeclareRequest(name, valueType, identifierPattern.Line, identifierPattern.Column)
    }

    // THE UNION-CASE ARM'S HEAD. A scrutinee that declares no union makes the whole arm silent —
    // including a case pattern carrying properties, which nothing else checks. Everything the
    // property loop needs is settled here, once, before the first property is looked at.
    func DispatchUnionCase(
        state: PatternAnalysisState,
        unionCasePattern: UnionCasePattern): PatternAnalysisRequest? {
        state.Phase = 99
        substitution: Dictionary<string, TypeInfo>? = null
        unionType := matchExhaustivenessValue.ResolveDeclaredUnionType(state.ValueType, out substitution)
        if unionType == null {
            return null
        }

        caseName := AnalyzerExhaustivenessSelector.GetUnionCaseName(unionCasePattern.CaseName)
        matchingCase := AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(
            unionType,
            unionCasePattern.CaseName)

        if matchingCase == null {
            span := spansValue.GetPatternNameDiagnosticSpan(unionCasePattern)
            ReportUnknownCase(unionCasePattern.CaseName, unionType, span)
            return null
        }

        properties := unionCasePattern.Properties
        if properties == null {
            return null
        }

        // A case that carries nothing cannot be destructured. `Analyzer.cs` tested "no property list"
        // and "an EMPTY property list" in two separate branches that reported the SAME message at the
        // SAME span; they are one branch here and the diagnostic is unchanged.
        caseProperties := matchingCase.Properties
        if caseProperties == null || caseProperties.Count == 0 {
            span := spansValue.GetPatternNameDiagnosticSpan(unionCasePattern)
            diagnosticsValue.Report(
                ErrorCode.InvalidPattern,
                "Union case '" + caseName
                    + "' doesn't carry any data — you can't destructure it with property patterns",
                span.Line,
                span.Column,
                null,
                span.Length)
            return null
        }

        state.UnionOwner = unionType
        state.UnionSubstitution = substitution
        state.UnionCaseName = caseName
        state.CaseProperties = caseProperties
        state.PatternProperties = properties
        state.Index = 0
        state.Phase = 30
        return null
    }

    // The case's property list, in written order, with the same three outcomes the object pattern's
    // property walk has: REPORT a property the case does not carry, ANALYSE a nested pattern against
    // the property's substituted type, or DECLARE the implicit binding. Both lists are settled at
    // dispatch and this phase is unreachable without them.
    func AdvanceUnionProperties(state: PatternAnalysisState): PatternAnalysisRequest? {
        properties := state.PatternProperties
        caseProperties := state.CaseProperties
        patternNode := state.PatternNode
        if properties == null || caseProperties == null || patternNode == null {
            state.Phase = 99
            return null
        }

        while state.Index < properties.Count {
            property := properties[state.Index]
            state.Index = state.Index + 1

            caseProperty := FindCaseProperty(caseProperties, property.Name)
            if caseProperty != null {
                propertyType := typeSubstitutionValue.ResolveTypeForSourceOwner(
                    caseProperty.Type,
                    state.UnionOwner,
                    state.UnionSubstitution)

                nested := property.Pattern
                if nested != null {
                    return PatternRequest(nested, propertyType)
                }

                bindingName: string = property.Name
                explicitBindingName := property.BindingName
                if explicitBindingName != null {
                    bindingName = explicitBindingName
                }

                span := spansValue.GetPropertyPatternNameDiagnosticSpan(
                    property,
                    patternNode.Line,
                    patternNode.Column)
                return DeclareRequest(bindingName, propertyType, span.Line, span.Column)
            }

            ReportUnknownCaseProperty(state, property, patternNode)
        }

        state.Phase = 99
        return null
    }

    func FindCaseProperty(caseProperties: List<UnionCaseProperty>, name: string): UnionCaseProperty? {
        index := 0
        while index < caseProperties.Count {
            candidate := caseProperties[index]
            if candidate.Name == name {
                return candidate
            }

            index = index + 1
        }

        return null
    }

    // A literal pattern's ONE suspension and the two reports after it. Both escape reports run and
    // BOTH answers are discarded — the literal arm never short-circuits — but the row report's TYPE
    // operand is the answer to the analysis before it, which is why the pair cannot be hoisted above
    // the step.
    func AdvanceLiteral(
        state: PatternAnalysisState,
        literalPattern: LiteralPattern): PatternAnalysisRequest? {
        state.Phase = 99
        soaEscapeValue.ReportSoaRowEscapeIfNeeded(
            literalPattern.Literal,
            state.AnalyzedType,
            "used as a pattern value")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
            literalPattern.Literal,
            "used as a pattern value")
        return null
    }

    // A relational pattern's bound, and the three questions after it whose LENGTH depends on the
    // first answers. A bound that escapes a row view — or that is a direct column value — is reported
    // as that, and the comparability judgement is not asked at all, exactly as the `!a && !b` guard
    // ordered it.
    func AdvanceRelational(
        state: PatternAnalysisState,
        relationalPattern: RelationalPattern): PatternAnalysisRequest? {
        state.Phase = 99
        state.Escaped = soaEscapeValue.ReportSoaRowEscapeIfNeeded(
            relationalPattern.Value,
            state.AnalyzedType,
            "used as a relational pattern value")
        if state.Escaped {
            return null
        }

        state.Escaped = soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
            relationalPattern.Value,
            "used as a relational pattern value")
        if state.Escaped {
            return null
        }

        patternShapesValue.ValidateRelationalPattern(
            relationalPattern,
            state.ValueType,
            state.AnalyzedType)
        return null
    }

    // `and` and `or` alike: both sides are analysed against the SAME scrutinee type, left first.
    func AdvanceTwoChildren(state: PatternAnalysisState): PatternAnalysisRequest? {
        andPattern := state.PatternNode as AndPattern
        if andPattern != null {
            if state.Index == 0 {
                state.Index = 1
                return PatternRequest(andPattern.Left, state.ValueType)
            }

            if state.Index == 1 {
                state.Index = 2
                return PatternRequest(andPattern.Right, state.ValueType)
            }
        }

        orPattern := state.PatternNode as OrPattern
        if orPattern != null {
            if state.Index == 0 {
                state.Index = 1
                return PatternRequest(orPattern.Left, state.ValueType)
            }

            if state.Index == 1 {
                state.Index = 2
                return PatternRequest(orPattern.Right, state.ValueType)
            }
        }

        state.Phase = 99
        return null
    }

    // A positional pattern's elements are analysed against the scrutinee ITSELF, not against a
    // per-position element type. That is what `Analyzer.cs` did — its own comment said so — and it is
    // preserved verbatim; an ownership slice does not improve behaviour.
    func AdvancePositional(
        state: PatternAnalysisState,
        positionalPattern: PositionalPattern): PatternAnalysisRequest? {
        if state.Index < positionalPattern.Patterns.Count {
            child := positionalPattern.Patterns[state.Index]
            state.Index = state.Index + 1
            return PatternRequest(child, state.ValueType)
        }

        state.Phase = 99
        return null
    }

    // The object arm drives the PROPERTY walk and forwards its two requests as its own, so the
    // composition of the family's two binding walks lives here rather than in `Analyzer.cs`. The
    // walk is begun at dispatch and this phase is unreachable without it.
    func AdvanceObject(state: PatternAnalysisState): PatternAnalysisRequest? {
        propertyState := state.PropertyState
        if propertyState == null {
            state.Phase = 99
            return null
        }

        step := propertyPatternBindingValue.NextStep(propertyState)
        if step == null {
            state.Phase = 99
            return null
        }

        if step.Kind == 1 {
            nestedRequest := new PatternAnalysisRequest(5, step.CarriedType)
            nestedRequest.Pattern = step.Pattern
            return nestedRequest
        }

        declareRequest := new PatternAnalysisRequest(4, step.CarriedType)
        declareRequest.Name = step.Name
        declareRequest.Line = step.Line
        declareRequest.Column = step.Column
        return declareRequest
    }

    // A list pattern's elements, against the one element type resolved for the whole list. A SLICE
    // element binds an ARRAY of that element type — anchored on the enclosing LIST pattern's
    // position, not the slice's — and a slice with no binding name is passed over in silence.
    func AdvanceList(
        state: PatternAnalysisState,
        listPattern: ListPattern): PatternAnalysisRequest? {
        while state.Index < listPattern.Elements.Count {
            element := listPattern.Elements[state.Index]
            state.Index = state.Index + 1

            slicePattern := element as SlicePattern
            if slicePattern == null {
                return PatternRequest(element, state.ElementType)
            }

            bindingName := slicePattern.BindingName
            if bindingName != null {
                sliceType := new ArrayTypeInfo(state.ElementType)
                return DeclareRequest(
                    bindingName,
                    sliceType,
                    listPattern.Line,
                    listPattern.Column)
            }
        }

        state.Phase = 99
        return null
    }

    // A type pattern resolves its target, asks whether the test can ever succeed, and binds. The
    // reachability judgement runs BEFORE the binding and reports for itself.
    func DispatchType(
        state: PatternAnalysisState,
        typePattern: TypePattern): PatternAnalysisRequest? {
        state.Phase = 99
        targetType := typeResolverValue.ResolveType(typePattern.Type)
        patternReachabilityValue.CheckTypePattern(typePattern, state.ValueType, targetType)

        bindingName := typePattern.BindingName
        if bindingName != null {
            return DeclareRequest(bindingName, targetType, typePattern.Line, typePattern.Column)
        }

        return null
    }

    // The one message shape both the identifier arm and the union-case arm produce. The union renders
    // itself, so what a reader sees is the name they wrote.
    func ReportUnknownCase(name: string, unionType: UnionTypeInfo, span: DiagnosticSpan) {
        unionObject := unionType as object
        diagnosticsValue.Report(
            ErrorCode.InvalidPattern,
            "'" + name + "' is not a case of union '" + unionObject.ToString()
                + "' — check the union definition for available cases",
            span.Line,
            span.Column,
            null,
            span.Length)
    }

    // The near-duplicate of the object pattern's NL503, and deliberately NOT the same diagnostic: a
    // case property is named on a UNION CASE, so the message names the case and points at its
    // definition. Slice 28 left it behind for exactly this reason.
    func ReportUnknownCaseProperty(
        state: PatternAnalysisState,
        property: PropertyPattern,
        patternNode: Pattern) {
        span := spansValue.GetPropertyPatternNameDiagnosticSpan(
            property,
            patternNode.Line,
            patternNode.Column)
        diagnosticsValue.Report(
            ErrorCode.InvalidPattern,
            "Union case '" + state.UnionCaseName + "' doesn't have a property named '" + property.Name
                + "' — check the case definition for available properties",
            span.Line,
            span.Column,
            null,
            span.Length)
    }

    // ── THE `switch` WALK ──────────────────────────────────────────────────────────────────────
    //
    // SIX PHASES, AND EVERY ONE OF THE STATEMENT'S DECISIONS IS HERE. Phase 70 asks for the value.
    // Phase 71 folds the answer, runs the two escape reports — the row report SHORT-CIRCUITS the
    // column probe, so a value already refused as a row view is not also called a direct column read
    // — collapses an escaped value to `unknown` for every case pattern below it, and enters the
    // switch's ambient frame. Phases 72..75 are the per-case loop: open the case scope, analyse the
    // case's pattern when it has one, analyse the case's statements, close the scope. The loop exits
    // through 72, which is also where the ambient frame is restored, so the frame is balanced on the
    // ONE path out.
    //
    // TWO THINGS ABOUT THE CASE SCOPE ARE `Analyzer.cs`'s AND ARE PRESERVED RATHER THAN TIDIED. It is
    // positioned at the SWITCH statement's own line and column — not at the case's, and not at the
    // pattern's, which is what `AnalyzeMatchExpression` uses for its arms — and it is opened for
    // EVERY case including the `default` one that has no pattern to bind.
    //
    // THE AMBIENT FRAME IS A `break` TARGET AND NOTHING ELSE. `EnterSwitch` moves only the
    // break-target finally depth, which is what NL319 reads; `continue` still targets the enclosing
    // loop, and a switch does not make `continue` legal where it was not. That asymmetry lives in
    // `AnalyzerAmbientContext` and this walk asks for it by name.
    func AdvanceSwitch(
        state: PatternAnalysisState,
        switchNode: SwitchStatement,
        phase: int): PatternAnalysisRequest? {
        if phase == 70 {
            state.Phase = 71
            state.Pending = 1
            return ExpressionRequest(switchNode.Value)
        }

        if phase == 71 {
            valueType := state.AnalyzedType
            escaped := soaEscapeValue.ReportSoaRowEscapeIfNeeded(
                switchNode.Value,
                valueType,
                "used as a switch value")
            if !escaped {
                escaped = soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
                    switchNode.Value,
                    "used as a switch value")
            }

            state.Escaped = escaped
            state.SwitchValueType = valueType
            if escaped {
                state.SwitchValueType = BuiltInTypes.Unknown
            }

            state.SavedBreakDepth = ambientValue.EnterSwitch()
            state.Index = 0
            state.Phase = 72
            return null
        }

        if phase == 72 {
            if state.Index >= switchNode.Cases.Count {
                state.Phase = 99
                ambientValue.ExitSwitch(state.SavedBreakDepth)
                return null
            }

            state.Phase = 73
            return ScopeOpenRequest(switchNode.Line, switchNode.Column)
        }

        if phase == 73 {
            state.Phase = 74
            casePattern := switchNode.Cases[state.Index].Pattern
            if casePattern != null {
                return PatternRequest(casePattern, state.SwitchValueType)
            }

            return null
        }

        if phase == 74 {
            state.Phase = 75
            return StatementsRequest(switchNode.Cases[state.Index].Statements)
        }

        if phase == 75 {
            state.Index = state.Index + 1
            state.Phase = 72
            return ScopeCloseRequest()
        }

        state.Phase = 99
        return null
    }

    func ExpressionRequest(node: Expression): PatternAnalysisRequest {
        request := new PatternAnalysisRequest(1, BuiltInTypes.Unknown)
        request.Node = node
        return request
    }

    func ScopeOpenRequest(line: int, column: int): PatternAnalysisRequest {
        request := new PatternAnalysisRequest(6, BuiltInTypes.Unknown)
        request.Line = line
        request.Column = column
        return request
    }

    func StatementsRequest(statements: List<Statement>): PatternAnalysisRequest {
        request := new PatternAnalysisRequest(7, BuiltInTypes.Unknown)
        request.Statements = statements
        return request
    }

    func ScopeCloseRequest(): PatternAnalysisRequest {
        return new PatternAnalysisRequest(8, BuiltInTypes.Unknown)
    }

    func DeclareRequest(name: string, carriedType: TypeInfo, line: int, column: int): PatternAnalysisRequest {
        request := new PatternAnalysisRequest(4, carriedType)
        request.Name = name
        request.Line = line
        request.Column = column
        return request
    }

    func PatternRequest(nested: Pattern, carriedType: TypeInfo): PatternAnalysisRequest {
        request := new PatternAnalysisRequest(5, carriedType)
        request.Pattern = nested
        return request
    }
}
