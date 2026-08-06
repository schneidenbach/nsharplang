namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE STEPS A PROPERTY'S OR AN INDEXER'S ACCESSORS CANNOT TAKE FOR THEMSELVES, AND EVERYTHING EACH
// STEP NEEDS.
//
// THIS FAMILY IS A PAIR, NOT A BODY, AND THAT IS WHY IT IS ITS OWN OWNER RATHER THAN A THIRD FORM OF
// `AnalyzerFunctionBodies`. A function has ONE body inside ONE scope; a property and an indexer have
// up to TWO accessors, each opening and closing a FUNCTION scope of its own, each entering and
// leaving the accessor return-type boundary of its own, and — for an indexer — each declaring the
// WHOLE parameter list again inside its own scope. The balance invariant a function's walk states
// absolutely ("exactly one scope opens and one closes") is simply false here: a `{ get set }`
// property opens two and closes two, and relaxing that invariant in the function's walk to admit this
// one would have weakened three contracts to buy nothing.
//
// The walk owns WHAT A PROPERTY DECLARATION MEANS: that its name is checked against the naming
// convention BEFORE its type is resolved, so an unresolvable type does not reorder the convention
// report; that its type is resolved with the DECLARED-type resolver; that its name is declared into
// the ENCLOSING scope under that type — not into either accessor's — so `x` written next to the
// property refers to the property; that it is recorded TWICE in the semantic model the IDE reads,
// once as a member of the containing type (only when there IS one) and once in the top-level property
// table that plain identifier lookup consults, in that order; that an EXPRESSION BODY is walked under
// the property's own type and is refused both SoA escapes exactly as a `return` is; that a mismatched
// expression body is reported at the EXPRESSION with the rich builder and at the DECLARATION without
// it — and that the detail-only shape carries `InvalidSyntax` rather than `TypeMismatch`, which is
// what the three-argument `Error` overload it replaces did; and that the GETTER runs before the
// SETTER, each in a FUNCTION scope of its own.
//
// AND IT OWNS WHAT AN INDEXER DECLARATION MEANS, which is the same accessor pair with a narrower
// entry and a wider accessor: that an indexer has NO name, so nothing is declared for it, no naming
// convention is checked and nothing is recorded for the IDE; that its type is resolved BEFORE its
// parameter list is validated; that the parameter list is validated ONCE, OUTSIDE both accessors —
// unlike a function, whose list is validated inside its scope — so a bad list is reported once rather
// than once per accessor; and that the parameters are then declared and recorded AGAIN inside EACH
// accessor's scope, because each accessor is its own scope and neither can see the other's names.
//
// AND IT OWNS WHAT THE SETTER'S `value` IS: an implicit name of the PROPERTY's or INDEXER's type —
// not of the accessor's return type, which is `void` — declared AFTER the accessor boundary is
// entered and BEFORE the body is walked, and declared WITHOUT a binding declaration, because `value`
// has no position in the source for go-to-definition to land on.
//
// What it cannot do is run the analyzer's own EXPRESSION walk, open or close a scope on the
// analyzer's scope stack, declare a name into that stack, write the semantic model the IDE reads,
// re-enter the STATEMENT dispatch, or run the parameter-list rules whose SoA arm re-enters the
// expression walk — so it ASKS: one request at a time, each naming a kind and carrying every value
// the step needs. Nothing here is a policy the driver may reinterpret — the driver switches on
// `Kind`, performs exactly the one operation with exactly these operands, and hands the answer back.
//
// The kinds:
//   1  analyse an EXPRESSION UNDER AN EXPECTED TYPE — the property's expression body, measured
//      against the property's own type. ANSWERS a type, which is the operand of both escape reports
//      and of the mismatch rule. The expected type is carried on the request rather than installed in
//      the ambient slot, for the reason `AnalyzerFunctionBodies` records: the analyzer's target-typed
//      entry point short-circuits a lambda into the lambda walk with the expected type as an
//      ARGUMENT and leaves the slot alone.
//   2  open a FUNCTION scope on the analyzer's scope stack at `Line` / `Column`. One accessor, one
//      scope; a property with both accessors asks for this twice.
//   3  declare a name into the analyzer's scope stack under `CarriedType` at `Line` / `Column`, with
//      `RecordsBinding` deciding whether a BINDING DECLARATION is recorded for it. That operand
//      exists because of exactly one caller — the setter's implicit `value`, which `Analyzer.cs`
//      declared with `recordBindingDeclaration: false` — and it is an operand here rather than a kind
//      of its own because the operation is the same operation with the same operands otherwise. It is
//      afforded because this protocol is NEW: adding it to the function walk's kind 3 would have
//      changed all six of that walk's call sites to buy one.
//   4  record a name in the semantic model the IDE's hover and completion read, as a VARIABLE.
//   5  close the scope kind 2 opened.
//   6  run the PARAMETER-LIST rules over `Parameters` at `Line` / `Column`. This is the same RELAY
//      `AnalyzerFunctionBodies` records as its kind 7 and for the same reason: the `params` half is
//      N#-owned and called directly by the analyzer, but the DEFAULT-VALUE half re-enters the
//      analyzer's target-typed expression walk whenever an SoA record types a defaulted parameter.
//      The indexer is one of that composite's eight callers.
//   7  analyse ONE STATEMENT, which re-enters the statement dispatch. EVERY accessor body goes
//      through this door — all four of them, verified per site — so each accessor's block opens a
//      BLOCK scope inside its FUNCTION scope, exactly as a top-level `func` declaration's body does
//      and unlike a local function's statement LIST.
//   8  record a TYPE MEMBER in the semantic model, under `ContainingType`. It is asked for only when
//      there IS a containing type, so the driver never decides anything; the name is carried rather
//      than read from the analyzer's own ambient field, so that the step is a value and not a
//      lookup.
//   9  record a PROPERTY in the semantic model's top-level table, which is what makes a bare
//      identifier naming the property resolve. It is a different table through a different member
//      from kind 8's and from kind 4's, which is why it is a kind of its own; and the model itself is
//      REPLACED at the start of every analysis, so no owner here may hold it.
//  10  run the NAMING-CONVENTION rule over `Name` and `CarriedModifiers` at `Line` / `Column`. This
//      is the SECOND RELAY, and it is a relay for the CATALOG reason slice 46 recorded rather than a
//      closure one: the rule's whole closure is already N#-owned, but it asks `char.IsLower` of the
//      name's first character and the columnar backend's `System.Char` catalog does not publish that
//      predicate. It moves with the sibling type-declaration walks, where the rest of its callers
//      live, in the slice that can pay for the toolset repin.
//
// The numbering is this walk's own protocol with its own driver and starts at 1 with no gaps; the
// other walks' numbers mean different operations, and none of them is a shared vocabulary.
class AccessorBodyRequest {
    Kind: int
    Node: Expression?
    ExpectedType: TypeInfo?
    Body: Statement?
    Parameters: List<Parameter>?
    Name: string?
    ContainingType: string?
    CarriedType: TypeInfo
    CarriedModifiers: Modifiers
    RecordsBinding: bool
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        ExpectedType = null
        Body = null
        Parameters = null
        Name = null
        ContainingType = null
        CarriedType = carriedType
        CarriedModifiers = Modifiers.None
        RecordsBinding = true
        Line = 0
        Column = 0
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` is 0 for a PROPERTY and 1 for an INDEXER. They are one walk with two entries because the
// ACCESSOR BAND is genuinely identical: the same scope opens, the same boundary is entered against
// the same member type, the same `value` is declared for the setter, the same dispatch walks the
// body, the same boundary is left and the same scope closes. What differs is entirely in the ENTRY —
// a property has a name, a convention, two IDE records and an expression body; an indexer has a
// parameter list and none of those — plus ONE branch inside the band, which is the indexer's
// per-accessor parameter declarations.
//
// `Phase` is the walk's program counter. The property entry owns 0..5: 0 asks for the naming
// convention; 1 resolves the type and declares the name; 2 records the type member; 3 records the
// property; 4 dispatches on whether there is an expression body; 5 applies the expression body's
// rules. The indexer entry owns 10, which resolves the type and validates the list in that order.
// The SHARED accessor band owns 20..26: 20 selects the next accessor that has a body and opens its
// scope; 21 and 22 are the per-parameter declare/record pair, which a property skips entirely;
// 23 enters the accessor return-type boundary and declares the setter's `value`; 24 records that
// `value`; 25 walks the body through the dispatch; 26 leaves the boundary, closes the scope and
// returns to 20 for the next accessor. 99 is done.
//
// `Accessor` is 0 for the getter and 1 for the setter, and 2 means both have been walked. It is a
// counter rather than two phase bands because the band is one band: the getter and the setter differ
// by which body is walked, which type the boundary takes and whether `value` is declared — three
// questions the band asks of this one number.
//
// `MemberType` is the property's or the indexer's OWN type, resolved once at entry. The walk needs it
// at up to six later suspensions — the getter's boundary, the setter's `value` declaration, the
// setter's IDE record, and the expression-body rule — and `Analyzer.cs` resolved it once too.
//
// `SavedReturnType` is `EnterAccessorReturnType`'s hand-back, and it is a BARE `TypeInfo?` rather
// than an `AmbientContextFrame` because that boundary saves exactly one field. That is the shape
// mismatch that kept this family out of the function walk's state: a frame slot cannot hold it, and a
// second slot on that state would have existed for two forms out of three. Here it is simply the
// state's own field, and its nullability is real — an accessor analysed outside any function
// restores a `null` return type, which is not the same as restoring nothing.
//
// THE ASSIGNABILITY ORACLE AND THE CONTAINING TYPE NAME ARE PASSED AT `Begin` RATHER THAN HELD, for
// the two reasons this estate already records: `Analyzer.cs` REBUILDS the oracle when the metadata
// load context opens and again when it is disposed, so an owner constructed once may not keep a
// reference to it; and the containing type name is ambient analyzer state that changes as the
// analyzer walks in and out of type declarations, so it is read at entry rather than held.
class AccessorBodyState {
    formValue: int
    propertyValue: PropertyDeclaration?
    indexerValue: IndexerDeclaration?
    lineValue: int
    columnValue: int
    containingTypeValue: string?
    assignabilityValue: AnalyzerAssignability

    Form: int => formValue
    Property: PropertyDeclaration? => propertyValue
    Indexer: IndexerDeclaration? => indexerValue
    Line: int => lineValue
    Column: int => columnValue
    ContainingType: string? => containingTypeValue
    Assignability: AnalyzerAssignability => assignabilityValue

    Phase: int
    Pending: int
    Accessor: int
    ParameterIndex: int
    ParameterType: TypeInfo
    MemberType: TypeInfo
    ExpressionBodyType: TypeInfo
    SavedReturnType: TypeInfo?

    constructor(form: int, property: PropertyDeclaration?, indexer: IndexerDeclaration?, line: int, column: int, containingType: string?, assignability: AnalyzerAssignability) {
        formValue = form
        propertyValue = property
        indexerValue = indexer
        lineValue = line
        columnValue = column
        containingTypeValue = containingType
        assignabilityValue = assignability
        Phase = 0
        Pending = 0
        Accessor = 0
        ParameterIndex = 0
        ParameterType = BuiltInTypes.Unknown
        MemberType = BuiltInTypes.Unknown
        ExpressionBodyType = BuiltInTypes.Unknown
        SavedReturnType = null
    }
}

// WHAT A PROPERTY'S AND AN INDEXER'S ACCESSORS MEAN.
//
// THE FAMILY IS NOT A PURE FUNCTION OF ITS DECLARATION, WHICH IS WHY IT IS AN OBJECT RATHER THAN A
// STATIC. The walk consults the TYPE RESOLVER for the member type and every indexer parameter type,
// the AMBIENT CONTEXT for the accessor return-type boundary, the SoA ESCAPE reporter for what an
// expression body may not hand back, and the span reader and the diagnostic sink for the one report
// this family owns. All five are constructed exactly once by `Analyzer.cs` and are never rebuilt with
// the metadata load context, so holding them is safe in a way that holding the assignability oracle
// would not be.
//
// IT DOES NOT HOLD THE SCOPE STACK, and that absence is a fact rather than an oversight: unlike the
// function walk, nothing in this family declares a type parameter or reads a symbol back — every
// scope operation it needs is a step, and every step is the driver's.
class AnalyzerAccessorBodies {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    typeResolverValue: AnalyzerTypeResolver
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, typeResolver: AnalyzerTypeResolver, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape) {
        diagnosticsValue = diagnostics
        spansValue = spans
        typeResolverValue = typeResolver
        ambientValue = ambient
        soaEscapeValue = soaEscape
    }

    // THE PROPERTY DECLARATION'S ENTRY. A property has only its own position, so the same value is
    // what the convention is reported at, what the name is declared at, what both accessor scopes
    // open at, where the setter's `value` lands, and where a mismatched expression body is reported
    // when there is no source text to narrow to.
    func BeginProperty(declaration: PropertyDeclaration, containingType: string?, assignability: AnalyzerAssignability): AccessorBodyState {
        return new AccessorBodyState(0, declaration, null, declaration.Line, declaration.Column, containingType, assignability)
    }

    // THE INDEXER DECLARATION'S ENTRY. The same single position serves the parameter-list rules, both
    // accessor scopes, every parameter without a position of its own, and the setter's `value`.
    func BeginIndexer(declaration: IndexerDeclaration, containingType: string?, assignability: AnalyzerAssignability): AccessorBodyState {
        state := new AccessorBodyState(1, null, declaration, declaration.Line, declaration.Column, containingType, assignability)
        state.Phase = 10
        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    func NextStep(state: AccessorBodyState): AccessorBodyRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything: the expression body's type,
    // which is the operand of both escape reports and of the mismatch rule. The declare, record,
    // scope, statement and parameter-validation steps answer nothing, and nothing is folded in for
    // them.
    func Supply(state: AccessorBodyState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending != 1 {
            return
        }

        if answer != null {
            state.ExpressionBodyType = answer
        } else {
            state.ExpressionBodyType = BuiltInTypes.Unknown
        }
    }

    func Advance(state: AccessorBodyState): AccessorBodyRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvancePropertyConvention(state)
        }

        if phase == 1 {
            return AdvancePropertyName(state)
        }

        if phase == 2 {
            return AdvancePropertyTypeMember(state)
        }

        if phase == 3 {
            return AdvancePropertyRecord(state)
        }

        if phase == 4 {
            return AdvancePropertyBodyShape(state)
        }

        if phase == 5 {
            return AdvancePropertyExpressionBodyRules(state)
        }

        if phase == 10 {
            return AdvanceIndexerEntry(state)
        }

        if phase == 20 {
            return AdvanceSelectAccessor(state)
        }

        if phase == 21 {
            return AdvanceDeclareParameter(state)
        }

        if phase == 22 {
            return AdvanceRecordParameter(state)
        }

        if phase == 23 {
            return AdvanceEnterAccessor(state)
        }

        if phase == 24 {
            return AdvanceRecordValue(state)
        }

        if phase == 25 {
            return AdvanceAccessorBody(state)
        }

        if phase == 26 {
            return AdvanceLeaveAccessor(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — THE NAMING CONVENTION, BEFORE THE TYPE IS RESOLVED. Both halves of that order are
    // behaviour: the convention report is about the NAME and cannot depend on the type, and resolving
    // the type first would let an unresolvable type's own report land ahead of it in the one list
    // whose order is the reported order.
    func AdvancePropertyConvention(state: AccessorBodyState): AccessorBodyRequest? {
        state.Phase = 1
        property := state.Property
        if property == null {
            return null
        }

        request := new AccessorBodyRequest(10, BuiltInTypes.Unknown)
        request.Name = property.Name
        request.CarriedModifiers = property.Modifiers
        request.Line = property.Line
        request.Column = property.Column
        return request
    }

    // PHASE 1 — THE TYPE, THEN THE NAME. The type is resolved with the DECLARED-type resolver, which
    // is what a member declaration uses, and the name is declared into whatever scope encloses the
    // property — the type's own scope for a member, the file's for a top-level one — and NOT into
    // either accessor's, which do not exist yet.
    func AdvancePropertyName(state: AccessorBodyState): AccessorBodyRequest? {
        property := state.Property
        if property == null {
            state.Phase = 20
            return null
        }

        memberType := typeResolverValue.ResolveDeclaredType(property.Type)
        state.MemberType = memberType
        state.Phase = 2
        request := new AccessorBodyRequest(3, memberType)
        request.Name = property.Name
        request.Line = property.Line
        request.Column = property.Column
        return request
    }

    // PHASE 2 — THE COMPLETION RECORD FOR THE CONTAINING TYPE, WHEN THERE IS ONE. A property declared
    // outside every type has no member table to join, and asking for the step anyway would have made
    // the driver decide something.
    func AdvancePropertyTypeMember(state: AccessorBodyState): AccessorBodyRequest? {
        state.Phase = 3
        containingType := state.ContainingType
        if containingType == null {
            return null
        }

        property := state.Property
        if property == null {
            return null
        }

        request := new AccessorBodyRequest(8, state.MemberType)
        request.Name = property.Name
        request.ContainingType = containingType
        return request
    }

    // PHASE 3 — THE TOP-LEVEL PROPERTY RECORD, WHICH IS WHAT MAKES A BARE IDENTIFIER NAMING THE
    // PROPERTY RESOLVE. It is unconditional and it follows the member record, which is the order
    // `Analyzer.cs` wrote.
    func AdvancePropertyRecord(state: AccessorBodyState): AccessorBodyRequest? {
        state.Phase = 4
        property := state.Property
        if property == null {
            return null
        }

        request := new AccessorBodyRequest(9, state.MemberType)
        request.Name = property.Name
        return request
    }

    // PHASE 4 — IS THERE AN EXPRESSION BODY. It is walked under the property's OWN type,
    // unconditionally — there is no generator here to silence it and no `void` property to leave
    // untargeted — and a property that has none goes straight to its accessors.
    func AdvancePropertyBodyShape(state: AccessorBodyState): AccessorBodyRequest? {
        state.Phase = 20
        property := state.Property
        if property == null {
            return null
        }

        expressionBody := property.ExpressionBody
        if expressionBody == null {
            return null
        }

        state.Phase = 5
        state.Pending = 1
        request := new AccessorBodyRequest(1, BuiltInTypes.Unknown)
        request.Node = expressionBody
        request.ExpectedType = state.MemberType
        return request
    }

    // PHASE 5 — AN EXPRESSION BODY'S THREE RULES, IN ORDER. Both SoA escapes are reported first and
    // unconditionally — an expression-bodied property RETURNS its value, so a row view and a direct
    // column read are refused there exactly as they are refused from a `return` — and the type rule
    // follows.
    func AdvancePropertyExpressionBodyRules(state: AccessorBodyState): AccessorBodyRequest? {
        state.Phase = 20
        property := state.Property
        if property == null {
            return null
        }

        expressionBody := property.ExpressionBody
        if expressionBody == null {
            return null
        }

        expressionType := state.ExpressionBodyType
        memberType := state.MemberType
        soaEscapeValue.ReportSoaRowEscapeIfNeeded(expressionBody, expressionType, "returned")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expressionBody, "returned")
        if state.Assignability.IsAssignable(memberType, expressionType) {
            return null
        }

        ReportExpressionBodyTypeMismatch(property, expressionBody, memberType, expressionType)
        return null
    }

    // THE EXPRESSION-BODY MISMATCH, IN BOTH ITS SHAPES, AND THE CODES ARE NOT THE SAME ONE. The rich
    // builder points at the EXPRESSION and reports a TYPE MISMATCH; the detail-only fallback points at
    // the DECLARATION and reports INVALID SYNTAX, because the three-argument `Error` overload it
    // replaces defaulted to that code. The asymmetry is preserved rather than tidied: a file with no
    // readable source text is exactly the case an editor buffer produces, and changing the code there
    // would change which squiggle a developer sees.
    func ReportExpressionBodyTypeMismatch(property: PropertyDeclaration, expressionBody: Expression, memberType: TypeInfo, expressionType: TypeInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(expressionBody)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.TypeMismatch(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, TypeText(expressionType), TypeText(memberType)))
            return
        }

        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Property '" + property.Name + "' is typed as '" + TypeText(memberType) + "', but the expression body returns '" + TypeText(expressionType) + "'", property.Line, property.Column, null, 0)
    }

    // PHASE 10 — AN INDEXER'S WHOLE ENTRY: THE TYPE, THEN THE PARAMETER-LIST RULES. The order is the
    // order `Analyzer.cs` wrote, and the list is validated ONCE and OUTSIDE both accessors — a
    // function validates its list INSIDE its scope, and the difference is visible whenever an indexer
    // has two accessors and a bad list, which is reported once rather than twice.
    func AdvanceIndexerEntry(state: AccessorBodyState): AccessorBodyRequest? {
        state.Phase = 20
        indexer := state.Indexer
        if indexer == null {
            return null
        }

        state.MemberType = typeResolverValue.ResolveDeclaredType(indexer.Type)
        request := new AccessorBodyRequest(6, BuiltInTypes.Unknown)
        request.Parameters = indexer.Parameters
        request.Line = indexer.Line
        request.Column = indexer.Column
        return request
    }

    // PHASE 20 — WHICH ACCESSOR IS NEXT, AND ITS SCOPE. The getter is walked before the setter, and an
    // accessor that was never written is SKIPPED ENTIRELY — it opens no scope, enters no boundary and
    // declares no `value`. The parameter index resets here rather than at entry, because an indexer
    // declares its whole list again inside EACH accessor.
    func AdvanceSelectAccessor(state: AccessorBodyState): AccessorBodyRequest? {
        while state.Accessor < 2 {
            body := AccessorBody(state, state.Accessor)
            if body != null {
                state.Phase = 21
                state.ParameterIndex = 0
                request := new AccessorBodyRequest(2, BuiltInTypes.Unknown)
                request.Line = state.Line
                request.Column = state.Column
                return request
            }

            state.Accessor = state.Accessor + 1
        }

        state.Phase = 99
        return null
    }

    // PHASE 21 — ONE INDEXER PARAMETER'S DECLARATION, INSIDE THIS ACCESSOR'S SCOPE. A parameter with a
    // position of its own is declared there; one without falls back to the INDEXER's position, which
    // is what makes a synthesised parameter squiggle the declaration rather than line zero. A property
    // has no parameters and falls straight through.
    func AdvanceDeclareParameter(state: AccessorBodyState): AccessorBodyRequest? {
        parameters := IndexerParameters(state)
        if parameters == null {
            state.Phase = 23
            return null
        }

        if state.ParameterIndex >= parameters.Count {
            state.Phase = 23
            return null
        }

        parameter := parameters[state.ParameterIndex]
        parameterType := typeResolverValue.ResolveDeclaredType(parameter.Type)
        state.ParameterType = parameterType
        position := AnalyzerBindingFacts.GetParameterDeclarationPosition(parameter.Line, parameter.Column, state.Line, state.Column)
        state.Phase = 22
        request := new AccessorBodyRequest(3, parameterType)
        request.Name = parameter.Name
        request.Line = position.Item1
        request.Column = position.Item2
        return request
    }

    // PHASE 22 — THE SAME PARAMETER, RECORDED FOR THE IDE. It carries the type phase 21 resolved
    // rather than resolving it again, and it is the step that advances the index: the pair is one
    // parameter, and the walk returns to phase 21 for the next.
    func AdvanceRecordParameter(state: AccessorBodyState): AccessorBodyRequest? {
        parameters := IndexerParameters(state)
        if parameters == null {
            state.Phase = 23
            return null
        }

        parameter := parameters[state.ParameterIndex]
        state.ParameterIndex = state.ParameterIndex + 1
        state.Phase = 21
        request := new AccessorBodyRequest(4, state.ParameterType)
        request.Name = parameter.Name
        return request
    }

    // PHASE 23 — THE ACCESSOR RETURN-TYPE BOUNDARY, AND THE SETTER'S IMPLICIT `value`. A GETTER owes
    // the member's type; a SETTER owes NOTHING, so its boundary takes `void` and a bare `return` inside
    // it is legal while `return x` is not. `value` is declared AFTER the boundary is entered — the
    // order `Analyzer.cs` wrote — and under the MEMBER's type rather than under the accessor's, which
    // is the one place in this walk where two different types are live at once.
    func AdvanceEnterAccessor(state: AccessorBodyState): AccessorBodyRequest? {
        memberType := state.MemberType
        accessorReturnType: TypeInfo = memberType
        if state.Accessor == 1 {
            accessorReturnType = BuiltInTypes.Void
        }

        state.SavedReturnType = ambientValue.EnterAccessorReturnType(accessorReturnType)
        if state.Accessor != 1 {
            state.Phase = 25
            return null
        }

        state.Phase = 24
        request := new AccessorBodyRequest(3, memberType)
        request.Name = "value"
        request.RecordsBinding = false
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 24 — `value`, RECORDED FOR THE IDE. It is declared without a binding declaration and
    // recorded WITH a semantic-model entry, and both halves of that are deliberate: there is no source
    // position for go-to-definition to land on, and completion inside a setter must still offer it.
    func AdvanceRecordValue(state: AccessorBodyState): AccessorBodyRequest? {
        state.Phase = 25
        request := new AccessorBodyRequest(4, state.MemberType)
        request.Name = "value"
        return request
    }

    // PHASE 25 — THE ACCESSOR'S BODY, THROUGH THE STATEMENT DISPATCH. Not a statement LIST: the block
    // goes through the dispatch, which advances the analysis cursor and lets the block arm open a
    // BLOCK scope inside the accessor's FUNCTION scope, so an accessor's locals live one scope deeper
    // than its parameters do.
    func AdvanceAccessorBody(state: AccessorBodyState): AccessorBodyRequest? {
        state.Phase = 26
        body := AccessorBody(state, state.Accessor)
        if body == null {
            return null
        }

        request := new AccessorBodyRequest(7, BuiltInTypes.Unknown)
        request.Body = body
        return request
    }

    // PHASE 26 — LEAVING ONE ACCESSOR. The boundary is left BEFORE the scope closes, which is the
    // order `Analyzer.cs` wrote and the order that matters: the scope pop is what makes `value` and
    // the indexer's parameters stop resolving, and the boundary restore is what makes a `return` mean
    // the enclosing function again. Then the walk returns to phase 20 for the other accessor.
    func AdvanceLeaveAccessor(state: AccessorBodyState): AccessorBodyRequest? {
        ambientValue.ExitAccessorReturnType(state.SavedReturnType)
        state.SavedReturnType = null
        state.Accessor = state.Accessor + 1
        state.Phase = 20
        return new AccessorBodyRequest(5, BuiltInTypes.Unknown)
    }

    // WHICH BLOCK THIS ACCESSOR IS, or null when it was never written. 0 is the getter and 1 is the
    // setter in both forms.
    static func AccessorBody(state: AccessorBodyState, accessor: int): BlockStatement? {
        if state.Form == 0 {
            property := state.Property
            if property == null {
                return null
            }

            if accessor == 0 {
                return property.GetBody
            }

            return property.SetBody
        }

        indexer := state.Indexer
        if indexer == null {
            return null
        }

        if accessor == 0 {
            return indexer.GetBody
        }

        return indexer.SetBody
    }

    // THE PARAMETERS EACH ACCESSOR DECLARES, or null for a property — which has none, and whose
    // accessor band therefore skips the pair without asking for a single step.
    static func IndexerParameters(state: AccessorBodyState): List<Parameter>? {
        indexer := state.Indexer
        if indexer == null {
            return null
        }

        return indexer.Parameters
    }

    // A resolved type's own display form, read through an `object`-typed local because `ToString` is
    // declared by the BASE of the TypeInfo hierarchy rather than by the hierarchy itself.
    static func TypeText(typeInfo: TypeInfo): string {
        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}
