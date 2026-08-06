namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE TEN STEPS A DECLARED FUNCTION'S BODY CANNOT TAKE FOR ITSELF, AND EVERYTHING EACH STEP NEEDS.
//
// The walk owns what a LOCAL FUNCTION MEANS — `func f(a: int): int { … }` written inside another
// body: that the function's own name is declared into the ENCLOSING scope BEFORE its own scope opens,
// which is what makes a RECURSIVE call inside its body resolve — and what makes a call written ABOVE
// the declaration NOT resolve, because the name lands when the STATEMENT is walked, not when the
// enclosing body is entered; that its body then runs inside a FUNCTION scope rather than a
// block scope; that its type parameters are declared into both namespaces before its parameters are
// resolved, so a parameter may be typed by one; that its parameter list is validated BEFORE any
// parameter is declared; that each parameter is declared at ITS OWN position when it has one and at
// the statement's otherwise; that its return type is resolved with `ResolveType` rather than with the
// declared-type resolver a top-level declaration uses; that entering it ZEROES the ambient loop and
// `finally` state, so a `break` inside it cannot reach a loop outside it; that a BLOCK body is walked
// as a STATEMENT LIST and therefore gets the unreachable-code rule while opening no second scope; and
// that an EXPRESSION body is walked UNDER THE DECLARED RETURN TYPE unless the function is a generator
// or returns nothing.
//
// AND IT OWNS WHAT A TOP-LEVEL `func` DECLARATION MEANS, which is the same walk with a wider entry:
// that an operator overload is checked for its `static` modifier, its symbol and its arity BEFORE
// anything else happens; that the name is declared only when the enclosing scope does not already
// hold it as a method group or as an identically-signed function, because a class's first pass may
// already have registered it; that a first parameter marked `this` makes the whole declaration an
// extension method; that the naming convention is checked for everything EXCEPT an operator overload,
// which has no choice about its name; that its type parameters' constraints are resolved and checked
// for circularity; that its return type is resolved with the DECLARED-type resolver rather than the
// plain one; that it enters the FUNCTION-DECLARATION ambient boundary, whose exit deliberately leaves
// no return type behind at all; that it is recorded in the semantic model the IDE reads as a
// FUNCTION rather than as a variable; that its block body is handed to the STATEMENT DISPATCH — a
// block, which therefore opens a block scope inside the function scope, unlike a local function's
// list; and that a non-void function whose body does not always return is told so.
//
// What it cannot do is run the analyzer's own EXPRESSION walk, open or close a scope on the
// analyzer's scope stack, declare a name into that stack, write the semantic model the IDE reads,
// re-enter the STATEMENT dispatch, or run the parameter-list rules whose SoA arm re-enters the
// expression walk — so it ASKS: one request at a time, each naming a kind and carrying every value
// the step needs. Nothing here is a policy the driver may reinterpret — the driver switches on
// `Kind`, performs exactly the one operation with exactly these operands, and hands the answer back.
//
// The kinds:
//   1  analyse an EXPRESSION UNDER AN EXPECTED TYPE. THIS IS THE ESTATE'S FIRST TARGET-TYPED WALK
//      KIND, and it is a kind of its own rather than a widening of any existing kind 1: every other
//      driver's kind 1 deliberately leaves the ambient target-typing slot ALONE, and that discipline
//      is preserved for all of them by giving this one its own number. It cannot be replaced by
//      setting the slot here and asking for a bare walk, because the analyzer's target-typed entry
//      point SHORT-CIRCUITS a lambda straight into the lambda walk with the expected type as an
//      ARGUMENT, leaving the ambient slot untouched for the lambda's own body — a difference that is
//      observable whenever the expected type is absent and a slot is already open. ANSWERS a type,
//      which is the operand of both escape reports and of the return-type rule.
//   2  open a FUNCTION scope on the analyzer's scope stack at `Line` / `Column`. A function scope,
//      not a block scope: it is what makes the body a body rather than a nested block.
//   3  declare a name into the analyzer's scope stack under `CarriedType` at `Line` / `Column` —
//      the function's own name into the enclosing scope, then each parameter into the new one.
//   4  record a parameter in the semantic model the IDE's hover and completion read.
//   5  analyse a STATEMENT LIST, which re-enters the statement dispatch AND applies the
//      unreachable-code rule. This is a LIST rather than `LoopStatementRequest`'s single statement
//      because a local function's block body is walked as its STATEMENTS: handing the block itself
//      to the dispatch would open a second scope inside the function scope, which is not what a
//      function body is.
//   6  close the scope kind 2 opened.
//   7  run the PARAMETER-LIST rules over `Parameters` at `Line` / `Column`. This is a RELAY and is
//      recorded as one: the `params` half of those rules is N#-owned and is called directly by the
//      analyzer, but the DEFAULT-VALUE half re-enters the analyzer's target-typed expression walk
//      whenever an SoA record types a defaulted parameter, and that walk is not N#'s to run. The
//      composite has eight callers, seven of them outside this family and none of them driven, so
//      turning it into a suspendable walk is a slice of its own rather than a step of this one.
//   8  record a FUNCTION in the semantic model the IDE's hover, completion and signature help read.
//      It is a separate kind from 4 rather than an operand on it because it writes a DIFFERENT table
//      through a different member, and because the semantic model itself is REBUILT at the start of
//      every analysis, so no owner here may hold it — the same reason kind 4 exists at all.
//   9  analyse ONE STATEMENT, which re-enters the statement dispatch. A top-level declaration's
//      block body goes through this door rather than through kind 5's statement LIST, and the
//      difference is behaviour rather than taste: the dispatch advances the analysis cursor to the
//      block's own line before the block arm opens the block's scope, so an EMPTY body records its
//      scope as ending on the brace's line instead of on whatever line was last analysed. Sending the
//      block through the dispatch also keeps ONE owner for what a `{ … }` block means; opening the
//      scope here instead would have copied that rule into this walk.
//  10  run the NAMING-CONVENTION rule over `Name` and `CarriedModifiers` at `Line` / `Column`. This is the
//      SECOND RELAY and, unlike kind 7, it is a relay for a CATALOG reason rather than a closure one:
//      the rule's whole closure is already N#-owned, but it asks `char.IsLower` of the name's first
//      character and the columnar backend's `System.Char` catalog does not publish that predicate —
//      `IsUpper`, `IsLetter`, `IsDigit`, `IsLetterOrDigit`, `IsWhiteSpace` and both invariant case
//      transforms are all there and `IsLower` is not. No published predicate separates a lowercase
//      letter from a title-case, modifier or other-category one, so there is no rewrite that keeps the
//      behaviour, and approximating it would silently change which identifiers are reported. The rule
//      moves when the catalog admits the predicate; eight of its nine callers are the sibling
//      declaration walks, which is where that slice will be.
//
// The numbering is this walk's own protocol with its own driver and starts at 1 with no gaps; the
// other walks' numbers mean different operations, and none of them is a shared vocabulary.
class FunctionBodyRequest {
    Kind: int
    Node: Expression?
    ExpectedType: TypeInfo?
    Statements: List<Statement>?
    Body: Statement?
    Parameters: List<Parameter>?
    Name: string?
    CarriedType: TypeInfo
    CarriedModifiers: Modifiers
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        ExpectedType = null
        Statements = null
        Body = null
        Parameters = null
        Name = null
        CarriedType = carriedType
        CarriedModifiers = Modifiers.None
        Line = 0
        Column = 0
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` is 0 for a LOCAL FUNCTION and 1 for a TOP-LEVEL `func` DECLARATION. They are one walk with
// two entries rather than two walks, because everything between the parameter list and the body is
// identical: the same function-type factory answers the symbol, the same scope stack takes the type
// parameters, the same per-parameter declare/record pair runs, the same generator return-type report
// fires, and the same expected-type rule decides what an expression body is measured against. What
// differs is written down and is form-branched in exactly the four places it is real: the wider entry
// (an operator check, an overload-aware declaration decision, extension-method tracking, the naming
// convention, and generic-constraint resolution and circularity), the return-type resolver, the
// ambient boundary, and the body — a block handed to the DISPATCH plus a missing-return rule, against
// a statement LIST with no such rule.
//
// `Phase` is the walk's program counter. The local-function form owns 0..8: 0 declares the function's
// own name; 1 opens the function scope; 2 declares the type parameters and validates the parameter
// list; 3 and 4 are the per-parameter pair, which the walk re-enters once per parameter because the
// DECLARE and the RECORD are two separate operations on the analyzer; 5 resolves the return type,
// enters the ambient body and dispatches on which body shape there is; 6 finishes a block body;
// 7 finishes an expression body; 8 leaves. The declaration form owns 10..19 and SHARES 3 and 4 —
// the per-parameter pair is the same operation on the same operands in both forms, so it is written
// once and phase 3's exhaustion is the one place it asks which form it is running: 10 checks the
// operator and decides whether the name is declared at all; 11 tracks the extension method and asks
// for the naming-convention rule; 12 opens the function scope; 13 declares the type parameters,
// resolves and checks the constraints and validates the parameter list; 15 resolves the return type, enters the
// declaration boundary, reports a bad generator return type and records the function for the IDE;
// 16 dispatches on which body shape there is; 17 finishes a block body and applies the missing-return
// rule; 18 finishes an expression body; 19 leaves. 99 is done in both.
//
// `ParameterType` is held because the declare step and the record step are two suspensions apart and
// both take the SAME resolved type — resolving it twice would be a second pass over the type
// resolver, which is not what `Analyzer.cs` did.
//
// `SymbolType` is the function's OWN type, computed once at entry. The declaration form needs it
// twice, six suspensions apart — once to declare the name and again to record the function in the
// semantic model — and `Analyzer.cs` computed it once too.
//
// `FunctionFrame` is the ambient snapshot the boundary hands back — `EnterNestedBody`'s for a local
// function and `EnterFunctionDeclaration`'s for a declaration. It lives on the state rather than in a
// local because the walk SUSPENDS between entering the body and leaving it — the body runs in the
// driver — and it is nullable only because a state exists before the body has been entered.
//
// THE ASSIGNABILITY ORACLE AND THE CONTAINING TYPE NAME ARE PASSED AT `Begin` RATHER THAN HELD, for
// the two different reasons this estate already records: `Analyzer.cs` REBUILDS the oracle when the
// metadata load context opens and again when it is disposed, so an owner constructed once may not
// keep a reference to it; and the containing type name is ambient analyzer state that changes as the
// analyzer walks in and out of type declarations, so it is read at entry rather than held.
class FunctionBodyState {
    formValue: int
    declarationValue: FunctionDeclaration
    lineValue: int
    columnValue: int
    containingTypeValue: string?
    assignabilityValue: AnalyzerAssignability

    Form: int => formValue
    Declaration: FunctionDeclaration => declarationValue
    Line: int => lineValue
    Column: int => columnValue
    ContainingType: string? => containingTypeValue
    Assignability: AnalyzerAssignability => assignabilityValue

    Phase: int
    Pending: int
    ParameterIndex: int
    ParameterType: TypeInfo
    SymbolType: TypeInfo
    ReturnType: TypeInfo
    ExpressionBodyType: TypeInfo
    FunctionFrame: AmbientContextFrame?

    constructor(form: int, declaration: FunctionDeclaration, line: int, column: int, containingType: string?, assignability: AnalyzerAssignability) {
        formValue = form
        declarationValue = declaration
        lineValue = line
        columnValue = column
        containingTypeValue = containingType
        assignabilityValue = assignability
        Phase = 0
        Pending = 0
        ParameterIndex = 0
        ParameterType = BuiltInTypes.Unknown
        SymbolType = BuiltInTypes.Unknown
        ReturnType = BuiltInTypes.Void
        ExpressionBodyType = BuiltInTypes.Unknown
        FunctionFrame = null
    }
}

// WHAT A DECLARED FUNCTION'S BODY MEANS, AND THE TWO GENERATOR REPORTS EVERY DECLARED FUNCTION SHARES.
//
// THE FAMILY IS NOT A PURE FUNCTION OF ITS DECLARATION, WHICH IS WHY IT IS AN OBJECT RATHER THAN A
// STATIC. The walk consults the FUNCTION-TYPE FACTORY for the symbol the name is declared under, the
// SCOPE STACK for type-parameter declaration, the TYPE RESOLVER for the return type and every
// parameter type, the AMBIENT CONTEXT for the nested-body boundary, the SoA ESCAPE reporter for what
// an expression body may not hand back, DEFINITE ASSIGNMENT for a block body's local reads, and the
// span reader and the diagnostic sink for the return-type mismatch. Every one of those seven
// collaborators is constructed exactly once by `Analyzer.cs` and is never rebuilt with the metadata
// load context, so holding them is safe in a way that holding the assignability oracle would not be.
//
// THE TWO GENERATOR REPORTS LIVE HERE RATHER THAN IN THE WALK BECAUSE THEY ARE SHARED. Both are asked
// by both forms, and neither is a step: each is a pure decision over a declaration plus, for the
// return-type one, its already-resolved return type. Publishing them here and routing every caller is
// what a shared member whose closure is N#-complete costs — a relay would have bought nothing,
// because there is no analyzer operation inside either.
//
// THE EXTENSION-METHOD LIST IS HELD RATHER THAN ASKED FOR, AND THE REASON IS THE OPPOSITE OF THE
// ASSIGNABILITY ORACLE'S. `Analyzer.cs` declares it `readonly` and mutates it in place — it is
// CLEARED at the start of each analysis and never replaced — and it is already held live by
// `AnalyzerExtensionMethodResolution`, which reads back exactly what this walk writes. There is
// nothing for a driver to reinterpret in `list.Add(declaration)`, and the decision that produces it
// (a first parameter marked `this`) is this walk's, so a kind would have bought a round trip and
// nothing else.
class AnalyzerFunctionBodies {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeResolverValue: AnalyzerTypeResolver
    functionTypeFactoryValue: AnalyzerFunctionTypeFactory
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape
    definiteAssignmentValue: AnalyzerDefiniteAssignment
    extensionMethodsValue: List<FunctionDeclaration>

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeResolver: AnalyzerTypeResolver, functionTypeFactory: AnalyzerFunctionTypeFactory, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape, definiteAssignment: AnalyzerDefiniteAssignment, extensionMethods: List<FunctionDeclaration>) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        functionTypeFactoryValue = functionTypeFactory
        ambientValue = ambient
        soaEscapeValue = soaEscape
        definiteAssignmentValue = definiteAssignment
        extensionMethodsValue = extensionMethods
    }

    // THE LOCAL FUNCTION STATEMENT'S ENTRY. The statement's OWN position — not the inner
    // declaration's — is what the name is declared at, what the function scope opens at, and what
    // every parameter without a position of its own falls back to; `Analyzer.cs` passed
    // `localFunc.Line` / `localFunc.Column` to all three, and the inner `FunctionDeclaration` carries
    // a position of its own that is deliberately NOT used.
    func BeginLocalFunction(statement: LocalFunctionStatement, containingType: string?, assignability: AnalyzerAssignability): FunctionBodyState {
        return new FunctionBodyState(0, statement.Function, statement.Line, statement.Column, containingType, assignability)
    }

    // THE TOP-LEVEL `func` DECLARATION'S ENTRY. A declaration has only its own position, so the same
    // value is what the name is declared at, what the function scope opens at, what the parameter
    // list is validated against, what every parameter without a position of its own falls back to,
    // and where a missing return is reported.
    func BeginFunctionDeclaration(declaration: FunctionDeclaration, containingType: string?, assignability: AnalyzerAssignability): FunctionBodyState {
        state := new FunctionBodyState(1, declaration, declaration.Line, declaration.Column, containingType, assignability)
        state.Phase = 10
        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    func NextStep(state: FunctionBodyState): FunctionBodyRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything: the expression body's type,
    // which is the operand of both escape reports and of the return-type rule. The declare, record,
    // scope, statement-list and parameter-validation steps answer nothing, and nothing is folded in
    // for them.
    func Supply(state: FunctionBodyState, answer: TypeInfo?) {
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

    func Advance(state: FunctionBodyState): FunctionBodyRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceDeclareFunction(state)
        }

        if phase == 1 {
            return AdvanceOpenFunctionScope(state)
        }

        if phase == 2 {
            return AdvanceTypeParametersAndValidation(state)
        }

        if phase == 3 {
            return AdvanceDeclareParameter(state)
        }

        if phase == 4 {
            return AdvanceRecordParameter(state)
        }

        if phase == 5 {
            return AdvanceEnterBody(state)
        }

        if phase == 6 {
            return AdvanceBlockBodyRules(state)
        }

        if phase == 7 {
            return AdvanceExpressionBodyRules(state)
        }

        if phase == 8 {
            return AdvanceLeaveBody(state)
        }

        if phase == 10 {
            return AdvanceDeclarationName(state)
        }

        if phase == 11 {
            return AdvanceDeclarationEntry(state)
        }

        if phase == 12 {
            return AdvanceDeclarationScope(state)
        }

        if phase == 13 {
            return AdvanceDeclarationConstraints(state)
        }

        if phase == 15 {
            return AdvanceDeclarationEnterBody(state)
        }

        if phase == 16 {
            return AdvanceDeclarationBodyShape(state)
        }

        if phase == 17 {
            return AdvanceDeclarationBlockBodyRules(state)
        }

        if phase == 18 {
            return AdvanceDeclarationExpressionBodyRules(state)
        }

        if phase == 19 {
            return AdvanceDeclarationLeaveBody(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — THE NAME, DECLARED INTO THE SCOPE THAT ENCLOSES THE FUNCTION AND BEFORE THE FUNCTION
    // SCOPE OPENS. Both halves of that order are behaviour. ENCLOSING scope, so the name outlives the
    // body and a sibling statement below can call it; BEFORE the scope opens, so the body's own scope
    // chain already contains the name and a RECURSIVE call resolves. It is NOT a hoist: the name lands
    // when this STATEMENT is walked, so a call written ABOVE the declaration does not resolve.
    func AdvanceDeclareFunction(state: FunctionBodyState): FunctionBodyRequest? {
        declaration := state.Declaration
        functionType := functionTypeFactoryValue.CreateFromDeclaration(declaration, state.ContainingType)
        state.Phase = 1
        request := new FunctionBodyRequest(3, functionType)
        request.Name = declaration.Name
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 1 — the body's own scope, which is a FUNCTION scope and opens at the STATEMENT's position.
    func AdvanceOpenFunctionScope(state: FunctionBodyState): FunctionBodyRequest? {
        state.Phase = 2
        request := new FunctionBodyRequest(2, BuiltInTypes.Unknown)
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 2 — THE TYPE PARAMETERS, THEN THE PARAMETER-LIST RULES, IN THAT ORDER. The type
    // parameters go into the scope stack directly — declaring one is N#-owned — and they go in
    // BEFORE the parameter list is validated and before any parameter type is resolved, because a
    // parameter may be typed by one. The parameter-list relay follows and precedes every parameter
    // declaration, so a list that is invalid is reported once, against the list, before any name in
    // it exists.
    func AdvanceTypeParametersAndValidation(state: FunctionBodyState): FunctionBodyRequest? {
        declaration := state.Declaration
        typeParameters := declaration.TypeParameters
        if typeParameters != null {
            index := 0
            while index < typeParameters.Count {
                typeParameter := typeParameters[index]
                scopesValue.DeclareTypeParameter(typeParameter.Name)
                index = index + 1
            }
        }

        state.Phase = 3
        state.ParameterIndex = 0
        request := new FunctionBodyRequest(7, BuiltInTypes.Unknown)
        request.Parameters = declaration.Parameters
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 3 — ONE PARAMETER'S DECLARATION, AND IT IS SHARED BY BOTH FORMS. A parameter with a
    // position of its own is declared there; one without falls back to the DECLARATION's position,
    // which is what makes a synthesised parameter squiggle the function rather than line zero.
    // Exhausting the list is the ONE place the shared pair asks which form it is running, because
    // that is the only thing that differs: where the walk goes next.
    func AdvanceDeclareParameter(state: FunctionBodyState): FunctionBodyRequest? {
        parameters := state.Declaration.Parameters
        if state.ParameterIndex >= parameters.Count {
            if state.Form == 1 {
                state.Phase = 15
            } else {
                state.Phase = 5
            }

            return null
        }

        parameter := parameters[state.ParameterIndex]
        parameterType := typeResolverValue.ResolveDeclaredType(parameter.Type)
        state.ParameterType = parameterType
        position := AnalyzerBindingFacts.GetParameterDeclarationPosition(parameter.Line, parameter.Column, state.Line, state.Column)
        state.Phase = 4
        request := new FunctionBodyRequest(3, parameterType)
        request.Name = parameter.Name
        request.Line = position.Item1
        request.Column = position.Item2
        return request
    }

    // PHASE 4 — THE SAME PARAMETER, RECORDED FOR THE IDE. It carries the type phase 3 resolved
    // rather than resolving it again, and it is the step that advances the index: the pair is one
    // parameter, and the walk returns to phase 3 for the next.
    func AdvanceRecordParameter(state: FunctionBodyState): FunctionBodyRequest? {
        parameters := state.Declaration.Parameters
        parameter := parameters[state.ParameterIndex]
        state.ParameterIndex = state.ParameterIndex + 1
        state.Phase = 3
        request := new FunctionBodyRequest(4, state.ParameterType)
        request.Name = parameter.Name
        return request
    }

    // PHASE 5 — THE RETURN TYPE, THE AMBIENT BOUNDARY, THE GENERATOR RETURN-TYPE REPORT, AND WHICH
    // BODY SHAPE THERE IS. The return type is resolved with `ResolveType`, NOT with the declared-type
    // resolver a top-level `func` uses — the two differ on how a bare name is treated, and the
    // difference is preserved rather than unified. An absent annotation means `void`. The ambient
    // boundary is entered BEFORE the generator report, because the report is about the declaration
    // and not about anything the boundary changes, and that is the order `Analyzer.cs` wrote.
    func AdvanceEnterBody(state: FunctionBodyState): FunctionBodyRequest? {
        declaration := state.Declaration
        returnTypeReference := declaration.ReturnType
        returnType: TypeInfo = BuiltInTypes.Void
        if returnTypeReference != null {
            returnType = typeResolverValue.ResolveType(returnTypeReference)
        }

        state.ReturnType = returnType
        state.FunctionFrame = ambientValue.EnterNestedBody(declaration, returnType)
        ReportGeneratorReturnTypeIfNeeded(declaration, returnType)

        body := declaration.Body
        if body != null {
            state.Phase = 6
            request := new FunctionBodyRequest(5, BuiltInTypes.Unknown)
            request.Statements = body.Statements
            return request
        }

        expressionBody := declaration.ExpressionBody
        if expressionBody != null {
            state.Phase = 7
            state.Pending = 1
            request := new FunctionBodyRequest(1, BuiltInTypes.Unknown)
            request.Node = expressionBody
            request.ExpectedType = ExpressionBodyExpectedType(declaration, returnType)
            return request
        }

        state.Phase = 8
        return null
    }

    // WHAT AN EXPRESSION BODY IS WALKED UNDER. A generator's expression body is walked under NOTHING
    // — it is about to be refused for being an expression body at all — and so is a body whose
    // function returns nothing. Everything else is walked under the declared return type, which is
    // what lets `=> default`, `=> new()`, `=> null` and an untyped lambda resolve.
    static func ExpressionBodyExpectedType(declaration: FunctionDeclaration, returnType: TypeInfo): TypeInfo? {
        if AnalyzerAmbientContext.HasModifier(declaration, Modifiers.Generator) {
            return null
        }

        if BuiltInTypes.Is(returnType, BuiltInTypes.Void) {
            return null
        }

        return returnType
    }

    // PHASE 6 — A BLOCK BODY'S ONE REMAINING RULE. Definite assignment runs AFTER the statements have
    // been walked, because it reads what the walk recorded. A local function has no missing-return
    // rule of its own: that rule belongs to the top-level declaration, and `Analyzer.cs` never
    // applied it here.
    func AdvanceBlockBodyRules(state: FunctionBodyState): FunctionBodyRequest? {
        body := state.Declaration.Body
        if body != null {
            definiteAssignmentValue.CheckLocals(body)
        }

        state.Phase = 8
        return null
    }

    // PHASE 7 — AN EXPRESSION BODY'S THREE RULES, IN ORDER. Both SoA escapes are reported first and
    // unconditionally — an expression body RETURNS its value, so a row view and a direct column read
    // are refused there exactly as they are refused from a `return`. The generator report follows,
    // and it SILENCES the type rule when it fires: a generator that used an expression body has
    // already been told the shape is wrong, and measuring its expression against the sequence type it
    // was also told is wrong would be a second complaint about one mistake.
    func AdvanceExpressionBodyRules(state: FunctionBodyState): FunctionBodyRequest? {
        state.Phase = 8
        declaration := state.Declaration
        expressionBody := declaration.ExpressionBody
        if expressionBody == null {
            return null
        }

        expressionType := state.ExpressionBodyType
        soaEscapeValue.ReportSoaRowEscapeIfNeeded(expressionBody, expressionType, "returned")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expressionBody, "returned")
        if ReportGeneratorExpressionBodyIfNeeded(declaration) {
            return null
        }

        returnType := state.ReturnType
        if BuiltInTypes.Is(returnType, BuiltInTypes.Void) {
            return null
        }

        if state.Assignability.IsAssignable(returnType, expressionType) {
            return null
        }

        span := spansValue.GetExpressionDiagnosticSpan(expressionBody)
        message := "Function '" + declaration.Name + "' should return '" + TypeText(returnType) + "' but the expression body gives '" + TypeText(expressionType) + "'"
        diagnosticsValue.Report(ErrorCode.TypeMismatch, message, span.Line, span.Column, null, span.Length)
        return null
    }

    // PHASE 8 — LEAVING. The ambient body closes BEFORE the scope does, which is the order
    // `Analyzer.cs` wrote and the order that matters: the scope pop is what makes the parameters stop
    // resolving, and the ambient restore is what makes a `return` mean the enclosing function again.
    func AdvanceLeaveBody(state: FunctionBodyState): FunctionBodyRequest? {
        frame := state.FunctionFrame
        if frame != null {
            ambientValue.ExitNestedBody(frame)
            state.FunctionFrame = null
        }

        state.Phase = 99
        return new FunctionBodyRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 10 — THE OPERATOR RULES, AND WHETHER THE NAME IS DECLARED AT ALL. The operator check runs
    // FIRST because it is about the declaration's shape and holds whatever the name later does; the
    // name follows. UNLIKE A LOCAL FUNCTION, THE DECLARATION MAY ALREADY BE IN SCOPE: a class's first
    // pass registers its methods before their bodies are walked, so declaring again would either
    // duplicate a symbol or re-merge a method group. The symbol's type is computed here once and kept,
    // because the semantic-model record six suspensions later takes the same value.
    func AdvanceDeclarationName(state: FunctionBodyState): FunctionBodyRequest? {
        declaration := state.Declaration
        if declaration.IsOperatorOverload {
            ValidateOperatorOverload(declaration)
        }

        functionType := functionTypeFactoryValue.CreateFromDeclaration(declaration, state.ContainingType)
        state.SymbolType = functionType
        state.Phase = 11
        if !DeclaresFunctionSymbol(declaration.Name, functionType) {
            return null
        }

        request := new FunctionBodyRequest(3, functionType)
        request.Name = declaration.Name
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // WHETHER THIS DECLARATION STILL OWES THE SCOPE ITS NAME. Nothing in the innermost scope means
    // yes. A METHOD GROUP means no — a first pass already merged every overload of this name, and
    // declaring into it again is what `DeclareSymbol`'s own merge would have to undo. A function with
    // the SAME parameter signature means no for the same reason: it is this declaration, already
    // registered. Anything else — a field, a property, a differently-signed function — means yes, and
    // the duplicate or the merge is `DeclareSymbol`'s decision rather than this one's.
    func DeclaresFunctionSymbol(name: string, functionType: FunctionTypeInfo): bool {
        existing := scopesValue.CurrentScopeSymbol(name)
        if existing == null {
            return true
        }

        methodGroup := existing as NSharpMethodGroupInfo
        if methodGroup != null {
            return false
        }

        existingFunction := existing as FunctionTypeInfo
        if existingFunction == null {
            return true
        }

        return !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(existingFunction, functionType)
    }

    // PHASE 11 — THE EXTENSION-METHOD REGISTRATION AND THE NAMING CONVENTION. A first parameter marked
    // `this` is what makes a plain `func` an extension method, and it is registered whether or not the
    // name was declared this pass, because a class's first pass registers symbols and not extensions.
    // The naming convention is asked for everything EXCEPT an operator overload, which has no name of
    // its own to get right; an operator therefore takes no step here at all. Both happen AFTER the
    // name is declared and BEFORE the scope opens, which is the order the reports appear in.
    func AdvanceDeclarationEntry(state: FunctionBodyState): FunctionBodyRequest? {
        declaration := state.Declaration
        parameters := declaration.Parameters
        if parameters.Count > 0 {
            firstParameter := parameters[0]
            if firstParameter.IsThis {
                extensionMethodsValue.Add(declaration)
            }
        }

        state.Phase = 12
        if declaration.IsOperatorOverload {
            return null
        }

        request := new FunctionBodyRequest(10, BuiltInTypes.Unknown)
        request.Name = declaration.Name
        request.CarriedModifiers = declaration.Modifiers
        request.Line = declaration.Line
        request.Column = declaration.Column
        return request
    }

    // PHASE 12 — the body's own scope, which is a FUNCTION scope and opens at the declaration's
    // position. It is the same step the nested form's phase 1 takes, with the same kind and the same
    // operands, and the two phases are separate only because the entries that precede them differ.
    func AdvanceDeclarationScope(state: FunctionBodyState): FunctionBodyRequest? {
        state.Phase = 13
        request := new FunctionBodyRequest(2, BuiltInTypes.Unknown)
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 13 — THE TYPE PARAMETERS, THEIR CONSTRAINTS, AND THEN THE PARAMETER-LIST RULES. This is
    // the local-function form's phase 2 with the two generic-constraint rules a top-level declaration
    // adds: the constraint TYPES are resolved — which is what makes `where T: Comparable` report an
    // unknown `Comparable` — and the constraint GRAPH is checked for cycles. Both run inside the
    // function scope and after the type parameters are declared, because a constraint names them.
    func AdvanceDeclarationConstraints(state: FunctionBodyState): FunctionBodyRequest? {
        declaration := state.Declaration
        typeParameters := declaration.TypeParameters
        if typeParameters != null {
            index := 0
            while index < typeParameters.Count {
                typeParameter := typeParameters[index]
                scopesValue.DeclareTypeParameter(typeParameter.Name)
                index = index + 1
            }
        }

        constraints := declaration.Constraints
        typeResolverValue.ResolveGenericConstraintTypes(constraints)
        CheckCircularGenericConstraints(typeParameters, constraints, declaration.Name, state.Line, state.Column)

        state.Phase = 3
        state.ParameterIndex = 0
        request := new FunctionBodyRequest(7, BuiltInTypes.Unknown)
        request.Parameters = declaration.Parameters
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 15 — THE RETURN TYPE, THE DECLARATION BOUNDARY, THE GENERATOR REPORT, AND THE IDE RECORD.
    // The return type is resolved with the DECLARED-type resolver, not the plain one a local function
    // uses; the two differ on how a bare name is treated and the difference is preserved rather than
    // unified. The boundary is `EnterFunctionDeclaration` rather than `EnterNestedBody`: a declaration
    // is never analysed from inside a loop or a `finally`, so the control-flow family is left alone
    // instead of being zeroed. The IDE record comes LAST of the four and carries the type computed at
    // phase 10, because that is the type the completion list must show.
    func AdvanceDeclarationEnterBody(state: FunctionBodyState): FunctionBodyRequest? {
        declaration := state.Declaration
        returnTypeReference := declaration.ReturnType
        returnType: TypeInfo = BuiltInTypes.Void
        if returnTypeReference != null {
            returnType = typeResolverValue.ResolveDeclaredType(returnTypeReference)
        }

        state.ReturnType = returnType
        state.FunctionFrame = ambientValue.EnterFunctionDeclaration(declaration, returnType)
        ReportGeneratorReturnTypeIfNeeded(declaration, returnType)

        state.Phase = 16
        request := new FunctionBodyRequest(8, state.SymbolType)
        request.Name = declaration.Name
        return request
    }

    // PHASE 16 — WHICH BODY SHAPE THERE IS. A BLOCK BODY GOES THROUGH THE STATEMENT DISPATCH, not
    // through the statement-LIST step a local function uses, and the difference is real: the dispatch
    // advances the analysis cursor and the block arm opens a BLOCK scope inside the function scope, so
    // a top-level function's locals live one scope deeper than a local function's do. A declaration
    // with neither body — an interface member, an abstract method — reaches phase 19 having opened a
    // scope and entered a boundary, and closes both.
    func AdvanceDeclarationBodyShape(state: FunctionBodyState): FunctionBodyRequest? {
        declaration := state.Declaration
        body := declaration.Body
        if body != null {
            state.Phase = 17
            request := new FunctionBodyRequest(9, BuiltInTypes.Unknown)
            request.Body = body
            return request
        }

        expressionBody := declaration.ExpressionBody
        if expressionBody != null {
            state.Phase = 18
            state.Pending = 1
            request := new FunctionBodyRequest(1, BuiltInTypes.Unknown)
            request.Node = expressionBody
            request.ExpectedType = ExpressionBodyExpectedType(declaration, state.ReturnType)
            return request
        }

        state.Phase = 19
        return null
    }

    // PHASE 17 — A BLOCK BODY'S TWO RULES. Definite assignment runs first and reads what the walk
    // recorded. THE MISSING-RETURN RULE IS THIS FORM'S ALONE: a local function never had it. It is
    // silent for a function that returns nothing, silent for a GENERATOR — which produces its values
    // with `yield` and never returns one — silent for an `async` function whose declared type is a
    // unit task, asked BOTH of the resolved type and of the written reference so an unresolvable
    // `Task` still counts, and silent when every path already returns.
    func AdvanceDeclarationBlockBodyRules(state: FunctionBodyState): FunctionBodyRequest? {
        state.Phase = 19
        declaration := state.Declaration
        body := declaration.Body
        if body == null {
            return null
        }

        definiteAssignmentValue.CheckLocals(body)
        returnType := state.ReturnType
        if BuiltInTypes.Is(returnType, BuiltInTypes.Void) {
            return null
        }

        if AnalyzerAmbientContext.HasModifier(declaration, Modifiers.Generator) {
            return null
        }

        if IsAsyncUnitTaskDeclaration(declaration, returnType) {
            return null
        }

        if AnalyzerStatementTermination.AlwaysReturns(body) {
            return null
        }

        ReportMissingReturn(declaration, returnType)
        return null
    }

    // AN `async` FUNCTION THAT OWES NO VALUE. `async func f(): Task` returns a task carrying nothing,
    // so a body with no `return` is complete. The question is asked of the RESOLVED type first and of
    // the WRITTEN reference second, because a `Task` the analyzer could not resolve still reads as one
    // in the source and must not produce a second complaint.
    static func IsAsyncUnitTaskDeclaration(declaration: FunctionDeclaration, returnType: TypeInfo): bool {
        if !AnalyzerAmbientContext.HasModifier(declaration, Modifiers.Async) {
            return false
        }

        if AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(returnType) {
            return true
        }

        return TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(declaration.ReturnType)
    }

    // THE MISSING-RETURN REPORT, IN BOTH ITS SHAPES. The rich builder underlines `func ` plus the
    // name — five characters plus the identifier — on the declaration's own line, and the detail-only
    // shape is what a file with no readable source text gets. They are one report through one door.
    func ReportMissingReturn(declaration: FunctionDeclaration, returnType: TypeInfo) {
        returnTypeName := TypeText(returnType)
        sourceSnippet := diagnosticsValue.SourceSnippet(declaration.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.MissingReturn(currentFilePath, declaration.Line, declaration.Column, sourceSnippet, declaration.Name.Length + 5, returnTypeName))
            return
        }

        diagnosticsValue.Report(ErrorCode.MissingReturn, "This function should return '" + returnTypeName + "', but not all code paths return a value — make sure every branch ends with a 'return'", declaration.Line, declaration.Column, null, 0)
    }

    // PHASE 18 — AN EXPRESSION BODY'S RULES. The two SoA escapes and the generator refusal are shared
    // with the local-function form and in the same order. WHAT DIFFERS IS THE VOID CASE: a top-level
    // `func` that declares no return type and hands back a value is TOLD SO, through the ambient
    // context's own report, whereas a local function is silent. And the mismatch report is the RICH
    // one, naming the function and both types on the expression's own span.
    func AdvanceDeclarationExpressionBodyRules(state: FunctionBodyState): FunctionBodyRequest? {
        state.Phase = 19
        declaration := state.Declaration
        expressionBody := declaration.ExpressionBody
        if expressionBody == null {
            return null
        }

        expressionType := state.ExpressionBodyType
        soaEscapeValue.ReportSoaRowEscapeIfNeeded(expressionBody, expressionType, "returned")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expressionBody, "returned")
        if ReportGeneratorExpressionBodyIfNeeded(declaration) {
            return null
        }

        returnType := state.ReturnType
        if BuiltInTypes.Is(returnType, BuiltInTypes.Void) {
            if BuiltInTypes.IsNot(expressionType, BuiltInTypes.Void) {
                ambientValue.ReportExpressionBodyReturn(declaration, expressionType)
            }

            return null
        }

        if state.Assignability.IsAssignable(returnType, expressionType) {
            return null
        }

        ReportExpressionBodyTypeMismatch(declaration, expressionBody, returnType, expressionType)
        return null
    }

    // THE EXPRESSION-BODY MISMATCH, IN BOTH ITS SHAPES. The rich builder points at the EXPRESSION and
    // names the function; the detail-only fallback points at the DECLARATION, because without source
    // text there is no span worth narrowing to.
    func ReportExpressionBodyTypeMismatch(declaration: FunctionDeclaration, expressionBody: Expression, returnType: TypeInfo, expressionType: TypeInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(expressionBody)
        returnTypeName := TypeText(returnType)
        expressionTypeName := TypeText(expressionType)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.ReturnTypeMismatch(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, declaration.Name, expressionTypeName, returnTypeName))
            return
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, "This function should return '" + returnTypeName + "', but the expression body gives '" + expressionTypeName + "'", declaration.Line, declaration.Column, null, 0)
    }

    // PHASE 19 — LEAVING A TOP-LEVEL DECLARATION. The ambient exit is `ExitFunctionDeclaration`, and
    // its ASYMMETRY is the whole reason this form does not share phase 8: it restores the enclosing
    // function, the omitted flag and the async flag but sets the return type to NULL rather than to
    // the saved one, so a stray `return` written between two declarations is reported as having no
    // function to return from. The scope closes after it, exactly as the nested form does.
    func AdvanceDeclarationLeaveBody(state: FunctionBodyState): FunctionBodyRequest? {
        frame := state.FunctionFrame
        if frame != null {
            ambientValue.ExitFunctionDeclaration(frame)
            state.FunctionFrame = null
        }

        state.Phase = 99
        return new FunctionBodyRequest(6, BuiltInTypes.Unknown)
    }

    // WHAT AN OPERATOR OVERLOAD MUST LOOK LIKE. Three independent faults, each reported on its own
    // span: an operator that is not `static` underlines the `operator` KEYWORD, and both arity faults
    // underline the SYMBOL. An unsupported symbol RETURNS — there is no arity to check for an operator
    // the language does not have, and telling an author their `**` takes the wrong number of arguments
    // would be a second complaint about a first mistake. `+` and `-` are the only two that may be
    // either unary or binary.
    func ValidateOperatorOverload(declaration: FunctionDeclaration) {
        keywordSpan := AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(declaration.OperatorKeywordSpan, declaration.Line, declaration.Column, 8)
        symbol := declaration.OperatorSymbol
        symbolLength := 1
        if symbol != null {
            symbolLength = symbol.Length
        }

        symbolSpan := AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(declaration.OperatorSymbolSpan, declaration.Line, declaration.Column, symbolLength)
        if !AnalyzerAmbientContext.HasModifier(declaration, Modifiers.Static) {
            diagnosticsValue.Report(ErrorCode.InvalidOperatorOverload, "Operator overloads must be declared 'static' — they don't belong to a specific instance", keywordSpan.Line, keywordSpan.Column, null, keywordSpan.Length)
        }

        symbolText := OperatorSymbolText(symbol)
        expectedParameters := OperatorParameterArity(symbol)
        if expectedParameters < 0 {
            diagnosticsValue.Report(ErrorCode.InvalidOperatorOverload, "The operator '" + symbolText + "' cannot be overloaded — only arithmetic, comparison, bitwise, and logical operators are supported", symbolSpan.Line, symbolSpan.Column, null, symbolSpan.Length)
            return
        }

        declaredCount := declaration.Parameters.Count
        if symbol == "+" || symbol == "-" {
            if declaredCount != 1 && declaredCount != 2 {
                diagnosticsValue.Report(ErrorCode.OperatorParameterCount, "Operator '" + symbolText + "' can be unary (1 parameter) or binary (2 parameters), but you declared " + declaredCount.ToString(), symbolSpan.Line, symbolSpan.Column, null, symbolSpan.Length)
            }

            return
        }

        if declaredCount != expectedParameters {
            diagnosticsValue.Report(ErrorCode.OperatorParameterCount, "Operator '" + symbolText + "' requires exactly " + expectedParameters.ToString() + " parameter(s), but you declared " + declaredCount.ToString(), symbolSpan.Line, symbolSpan.Column, null, symbolSpan.Length)
        }
    }

    // HOW MANY OPERANDS EACH OVERLOADABLE OPERATOR TAKES, or −1 for one the language does not
    // overload. A declaration that parsed without a symbol at all answers −1 too, which is the same
    // answer the C# switch gave a null.
    static func OperatorParameterArity(symbol: string?): int {
        if symbol == null {
            return -1
        }

        if symbol == "!" || symbol == "~" || symbol == "++" || symbol == "--" || symbol == "true" || symbol == "false" {
            return 1
        }

        if symbol == "+" || symbol == "-" || symbol == "*" || symbol == "/" || symbol == "%" {
            return 2
        }

        if symbol == "==" || symbol == "!=" || symbol == "<" || symbol == ">" || symbol == "<=" || symbol == ">=" {
            return 2
        }

        if symbol == "&" || symbol == "|" || symbol == "^" || symbol == "<<" || symbol == ">>" {
            return 2
        }

        return -1
    }

    // A missing operator symbol renders as nothing, which is what interpolating a null string did.
    static func OperatorSymbolText(symbol: string?): string {
        if symbol == null {
            return ""
        }

        return symbol
    }

    // A TYPE PARAMETER CONSTRAINED TO ITSELF, DIRECTLY OR THROUGH ITS SIBLINGS. Only constraints
    // naming ANOTHER TYPE PARAMETER of this same declaration are edges: `where T: IComparable` names a
    // type and cannot close a cycle, and a constraint on a parameter this declaration does not have is
    // not this rule's business. AT MOST ONE report is raised no matter how many cycles there are,
    // because they are one mistake in one `where` clause set.
    func CheckCircularGenericConstraints(typeParameters: List<TypeParameter>?, constraints: List<GenericConstraint>?, declarationName: string, line: int, column: int) {
        if typeParameters == null || constraints == null {
            return
        }

        if typeParameters.Count == 0 || constraints.Count == 0 {
            return
        }

        names := new List<string>()
        successors := new List<List<int>>()
        index := 0
        while index < typeParameters.Count {
            typeParameter := typeParameters[index]
            names.Add(typeParameter.Name)
            successors.Add(new List<int>())
            index = index + 1
        }

        CollectConstraintEdges(names, successors, constraints)

        start := 0
        while start < names.Count {
            if HasConstraintCycle(successors, start, names.Count) {
                diagnosticsValue.Report(ErrorCode.GenericConstraintViolation, "Type parameter `" + names[start] + "` of `" + declarationName + "` has a circular constraint dependency", line, column, "Remove the cycle in the `where` clauses of `" + declarationName + "` — a type parameter cannot be constrained to itself, directly or through other type parameters.", 0)
                return
            }

            start = start + 1
        }
    }

    // THE EDGE SET: which type parameters each one is DIRECTLY constrained to. Bare names only — a
    // generic constraint like `List<T>` is not an edge, because constraining `T` to a type that merely
    // MENTIONS `U` does not make `T` depend on `U` the way `where T: U` does.
    static func CollectConstraintEdges(names: List<string>, successors: List<List<int>>, constraints: List<GenericConstraint>) {
        constraintIndex := 0
        while constraintIndex < constraints.Count {
            constraint := constraints[constraintIndex]
            constraintIndex = constraintIndex + 1
            from := names.IndexOf(constraint.TypeParameter)
            if from < 0 {
                continue
            }

            bucket := successors[from]
            constraintTypes := constraint.Constraints
            typeIndex := 0
            while typeIndex < constraintTypes.Count {
                constraintType := constraintTypes[typeIndex]
                typeIndex = typeIndex + 1
                simple := constraintType as SimpleTypeReference
                if simple == null {
                    continue
                }

                to := names.IndexOf(simple.Name)
                if to >= 0 {
                    bucket.Add(to)
                }
            }
        }
    }

    // CAN THIS PARAMETER REACH ITSELF. A successor chain longer than the parameter count must revisit
    // a node, so the walk is bounded at that depth rather than tracking visited nodes: walking every
    // simple path is exponential in pathological cases, and a bounded depth-first walk answers the
    // same question. The two parallel lists ARE the stack of `(node, depth)` pairs the C# pushed.
    static func HasConstraintCycle(successors: List<List<int>>, start: int, limit: int): bool {
        nodeStack := new List<int>()
        depthStack := new List<int>()
        nodeStack.Add(start)
        depthStack.Add(0)
        while nodeStack.Count > 0 {
            top := nodeStack.Count - 1
            node := nodeStack[top]
            depth := depthStack[top]
            nodeStack.RemoveAt(top)
            depthStack.RemoveAt(top)
            if depth >= limit {
                continue
            }

            next := successors[node]
            index := 0
            while index < next.Count {
                to := next[index]
                index = index + 1
                if to == start {
                    return true
                }

                nodeStack.Add(to)
                depthStack.Add(depth + 1)
            }
        }

        return false
    }

    // A GENERATOR THAT USED AN EXPRESSION BODY. Generators produce their values with `yield`, which
    // is a statement, so there is no expression body that could ever be right; the report ANSWERS
    // whether it fired, because a declaration that has been told this must not also be told its
    // expression does not fit a return type it was told is wrong.
    func ReportGeneratorExpressionBodyIfNeeded(declaration: FunctionDeclaration): bool {
        if !AnalyzerAmbientContext.HasModifier(declaration, Modifiers.Generator) {
            return false
        }

        expressionBody := declaration.ExpressionBody
        if expressionBody == null {
            return false
        }

        span := spansValue.GetExpressionDiagnosticSpan(expressionBody)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Generator functions must use a block body", span.Line, span.Column, "Use `{ yield value }` to produce sequence values from a generator.", span.Length)
        return true
    }

    // A GENERATOR WHOSE RETURN TYPE IS NOT A SEQUENCE. Silent for a non-generator, silent for a return
    // type nothing could resolve — a second complaint about a type the analyzer has already refused is
    // noise — and silent for every shape that IS a sequence. `async func*` owes an async sequence and
    // `func*` owes a synchronous one, and the two are never interchangeable. The squiggle lands on the
    // written return type when there is one and on the function's NAME when the annotation was
    // omitted, because there is nothing else to underline.
    func ReportGeneratorReturnTypeIfNeeded(declaration: FunctionDeclaration, returnType: TypeInfo): bool {
        if !AnalyzerAmbientContext.HasModifier(declaration, Modifiers.Generator) {
            return false
        }

        resolvedReturnType := declarationContextValue.ResolveDeclaredAlias(NonNullableType(returnType))
        isAsyncGenerator := AnalyzerAmbientContext.HasModifier(declaration, Modifiers.Async)
        if BuiltInTypes.IsUnknown(resolvedReturnType) {
            return false
        }

        if IsGeneratorSequenceReturnType(resolvedReturnType, isAsyncGenerator) {
            return false
        }

        sequenceKind := GeneratorSequenceTypeFacts.ExpectedSequenceKind(isAsyncGenerator)
        suggestion := GeneratorSequenceTypeFacts.ReturnTypeSuggestion(isAsyncGenerator)
        returnTypeName := TypeText(returnType)
        span := GeneratorReturnTypeSpan(declaration, returnTypeName)
        message := "Generator function '" + declaration.Name + "' must return " + sequenceKind + ", but it returns '" + returnTypeName + "'"
        diagnosticsValue.Report(ErrorCode.TypeMismatch, message, span.Line, span.Column, suggestion, span.Length)
        return true
    }

    func GeneratorReturnTypeSpan(declaration: FunctionDeclaration, returnTypeName: string): DiagnosticSpan {
        returnTypeReference := declaration.ReturnType
        if returnTypeReference == null {
            return spansValue.GetFunctionNameDiagnosticSpan(declaration)
        }

        return AnalyzerDiagnosticSpanFacts.GetSourceSpanDiagnosticSpan(TypeReferenceFacts.GetStartSpan(returnTypeReference), declaration.Line, declaration.Column, Math.Max(1, returnTypeName.Length))
    }

    // IS THIS TYPE A SEQUENCE A GENERATOR MAY RETURN. A DECLARED generic answers by name, so a
    // user-written `List` behaves like the BCL one; a REFLECTED type answers by generic-definition
    // IDENTITY, which is a reference comparison against runtime types and is deliberate — a type
    // loaded into the analyzer's MetadataLoadContext is a different object from its runtime twin, so
    // an MLC type answers NO here and falls through to the declared path exactly as it did in
    // `Analyzer.cs`.
    static func IsGeneratorSequenceReturnType(typeInfo: TypeInfo, isAsyncGenerator: bool): bool {
        if GeneratorSequenceTypeFacts.IsSequenceReturnType(typeInfo, isAsyncGenerator) {
            return true
        }

        reflection := typeInfo as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        return IsGeneratorSequenceReflectionType(reflection.Type, isAsyncGenerator)
    }

    // THE REFLECTED ARM. An array is refused before anything else — `int[]` is enumerable but is not
    // a sequence a generator may declare — and so is a non-generic type, because every sequence in
    // the set has exactly one type argument.
    static func IsGeneratorSequenceReflectionType(clrType: Type, isAsyncGenerator: bool): bool {
        if clrType.get_IsArray() {
            return false
        }

        if !clrType.get_IsGenericType() {
            return false
        }

        definition := clrType.GetGenericTypeDefinition()
        if isAsyncGenerator {
            asyncDefinition := SequenceDefinition("System.Collections.Generic.IAsyncEnumerable`1")
            return definition == asyncDefinition
        }

        return IsSynchronousSequenceDefinition(definition)
    }

    // THE SIX SYNCHRONOUS SEQUENCE DEFINITIONS, COMPARED ONE AT A TIME BY IDENTITY. The set is
    // `Analyzer.cs`'s exactly and in its order; nothing is inferred from a name here, because a name
    // match would also accept a type loaded into the analyzer's MetadataLoadContext, which is a
    // DIFFERENT object from its runtime twin and which the C# deliberately refused.
    static func IsSynchronousSequenceDefinition(definition: Type): bool {
        listDefinition := SequenceDefinition("System.Collections.Generic.List`1")
        if definition == listDefinition {
            return true
        }

        enumerableDefinition := SequenceDefinition("System.Collections.Generic.IEnumerable`1")
        if definition == enumerableDefinition {
            return true
        }

        collectionDefinition := SequenceDefinition("System.Collections.Generic.ICollection`1")
        if definition == collectionDefinition {
            return true
        }

        listInterfaceDefinition := SequenceDefinition("System.Collections.Generic.IList`1")
        if definition == listInterfaceDefinition {
            return true
        }

        readOnlyCollectionDefinition := SequenceDefinition("System.Collections.Generic.IReadOnlyCollection`1")
        if definition == readOnlyCollectionDefinition {
            return true
        }

        readOnlyListDefinition := SequenceDefinition("System.Collections.Generic.IReadOnlyList`1")
        return definition == readOnlyListDefinition
    }

    // A SEQUENCE TYPE'S RUNTIME IDENTITY BY NAME. The spelling is forced rather than chosen, exactly
    // as `AnalyzerLoopSequence` records: the pinned toolset DECLINES `typeof` on several of these in
    // every spelling tried, so all of them are named through `Type.GetType` — one door for the whole
    // set rather than two — and each resolves to the same `System.Private.CoreLib` identity `typeof`
    // would have given.
    static func SequenceDefinition(fullName: string): Type {
        definition := Type.GetType(fullName)
        if definition == null {
            throw new InvalidOperationException("Required sequence type " + fullName + " was not found.")
        }

        return definition
    }

    // A NULL-CHECK NARROWING'S TYPE SLOT IS NOT THE ONLY PLACE A NULLABLE MUST BE UNWRAPPED. The
    // generator rule asks its question of the UNDERLYING type, so `IEnumerable<int>?` is still a
    // sequence.
    func NonNullableType(candidate: TypeInfo): TypeInfo {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
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
