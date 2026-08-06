namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE SEVEN STEPS A DECLARED FUNCTION'S BODY CANNOT TAKE FOR ITSELF, AND EVERYTHING EACH STEP NEEDS.
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
//
// The numbering is this walk's own protocol with its own driver and starts at 1 with no gaps; the
// other walks' numbers mean different operations, and none of them is a shared vocabulary.
class FunctionBodyRequest {
    Kind: int
    Node: Expression?
    ExpectedType: TypeInfo?
    Statements: List<Statement>?
    Parameters: List<Parameter>?
    Name: string?
    CarriedType: TypeInfo
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        ExpectedType = null
        Statements = null
        Parameters = null
        Name = null
        CarriedType = carriedType
        Line = 0
        Column = 0
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` is 0 for a local function, and it is written as a form rather than assumed because a
// top-level `func` declaration is the SAME walk with a wider entry — it declares into a method group
// instead of a plain symbol, resolves its return type with the declared-type resolver, enters the
// FUNCTION-DECLARATION ambient boundary rather than the nested-body one, hands its block body to the
// dispatch instead of walking the list, and owns a missing-return rule this form has no equivalent
// of. Nothing here is written for that form yet; the slot exists so joining it costs no new kind.
//
// `Phase` is the walk's program counter and the local-function form owns 0..8. 0 declares the
// function's own name; 1 opens the function scope; 2 declares the type parameters and validates the
// parameter list; 3 and 4 are the per-parameter pair, which the walk re-enters once per parameter
// because the DECLARE and the RECORD are two separate operations on the analyzer; 5 resolves the
// return type, enters the ambient body and dispatches on which body shape there is; 6 finishes a
// block body; 7 finishes an expression body; 8 leaves. 99 is done.
//
// `ParameterType` is held because the declare step and the record step are two suspensions apart and
// both take the SAME resolved type — resolving it twice would be a second pass over the type
// resolver, which is not what `Analyzer.cs` did.
//
// `FunctionFrame` is the ambient snapshot `EnterNestedBody` hands back. It lives on the state rather
// than in a local because the walk SUSPENDS between entering the body and leaving it — the body runs
// in the driver — and it is nullable only because a state exists before the body has been entered.
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
// by this walk and by `Analyzer.cs`'s top-level function declaration, and neither is a step: each is
// a pure decision over a declaration plus, for the return-type one, its already-resolved return type.
// Publishing them here and routing BOTH callers is what a shared member whose closure is N#-complete
// costs — a relay would have bought nothing, because there is no analyzer operation inside either.
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

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeResolver: AnalyzerTypeResolver, functionTypeFactory: AnalyzerFunctionTypeFactory, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape, definiteAssignment: AnalyzerDefiniteAssignment) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        functionTypeFactoryValue = functionTypeFactory
        ambientValue = ambient
        soaEscapeValue = soaEscape
        definiteAssignmentValue = definiteAssignment
    }

    // THE LOCAL FUNCTION STATEMENT'S ENTRY. The statement's OWN position — not the inner
    // declaration's — is what the name is declared at, what the function scope opens at, and what
    // every parameter without a position of its own falls back to; `Analyzer.cs` passed
    // `localFunc.Line` / `localFunc.Column` to all three, and the inner `FunctionDeclaration` carries
    // a position of its own that is deliberately NOT used.
    func BeginLocalFunction(statement: LocalFunctionStatement, containingType: string?, assignability: AnalyzerAssignability): FunctionBodyState {
        return new FunctionBodyState(0, statement.Function, statement.Line, statement.Column, containingType, assignability)
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

    // PHASE 3 — ONE PARAMETER'S DECLARATION. A parameter with a position of its own is declared
    // there; one without falls back to the STATEMENT's position, which is what makes a synthesised
    // parameter squiggle the function rather than line zero.
    func AdvanceDeclareParameter(state: FunctionBodyState): FunctionBodyRequest? {
        parameters := state.Declaration.Parameters
        if state.ParameterIndex >= parameters.Count {
            state.Phase = 5
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
