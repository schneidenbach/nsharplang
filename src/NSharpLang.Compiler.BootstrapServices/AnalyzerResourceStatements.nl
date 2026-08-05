namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// THE SEVEN STEPS THE RESOURCE FAMILY CANNOT TAKE FOR ITSELF.
//
// `try`, `using` and `lock` are one family because they are one SHAPE: each opens a guarded region,
// each names something the region is guarded BY — a set of catch clauses, a disposable resource, a
// monitor object — and each runs a body inside a scope it opened and closes afterwards. What none of
// them can do for itself is run the analyzer's expression walk, push or pop a scope, declare a
// symbol, re-enter the STATEMENT dispatch for a body, or run the local-declaration walk over a
// `using` resource declaration — so it ASKS: one request at a time, each naming a kind and carrying
// every value the step needs. Nothing here is a policy the driver may reinterpret.
//
// The kinds:
//   1  analyse an expression. ANSWERS a type.
//   2  open a block scope on the analyzer's scope stack at `Line` / `Column`.
//   3  declare a symbol named `Name` of type `CarriedType` at `Line` / `Column` — a catch variable.
//   4  record that symbol as a variable in the CURRENT scope, which is what makes the IDE's
//      completion and hover see it.
//   5  analyse ONE STATEMENT — a try block, a catch block, a finally block, a `using` body or a
//      `lock` body. Every one of the five is a `BlockStatement` handed to the statement DISPATCH,
//      which is what pushes the block's own scope and applies the unreachable-code rule to its
//      contents; this is deliberately NOT the statement-LIST walk, because taking the list here
//      would skip that scope and apply the rule twice.
//   6  close a scope kind 2 opened.
//   7  run the LOCAL-DECLARATION walk over a `using` statement's resource declaration. This is the
//      SECOND driver-drives-a-driver step in this estate, after the `for` iterator's, and it is here
//      for the same reason: WHETHER a `using` declares rather than evaluates, and that the
//      declaration runs inside the scope this walk just opened and before the disposability rule, are
//      this walk's decisions. What the driver adds is only the two things N# cannot do for itself —
//      construct that family's state and run its loop.
//
// The numbering is this walk's own protocol with its own driver and starts at 1 with no gaps; the
// other walks' numbers mean different operations, and none of them is a shared vocabulary.
public class ResourceStatementRequest {

    public Kind: int
    public Node: Expression?
    public Body: Statement?
    public Declaration: VariableDeclarationStatement?
    public Name: string?
    public CarriedType: TypeInfo
    public Line: int
    public Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Body = null
        Declaration = null
        Name = null
        CarriedType = carriedType
        Line = 0
        Column = 0
    }
}

// THE RESOURCE STATEMENT'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// ONE state serves all three statements, because ONE driver serves them all. The three AST nodes are
// structurally unrelated — they share no base beyond `Statement` — so exactly one of the three node
// fields is set and `Form` says which walk is running: 0 is `try`, 1 is `using`, 2 is `lock`.
//
// `Phase` is the walk's program counter, and each form owns a BAND of it so a phase number never
// means two things — the discipline the loop family's four walks established. `try` runs 0..7: 0 the
// try block, 1 the catch loop's head, 2 through 5 one catch clause (scope, type and report, declare,
// record, body, close), 6 the finally's entry and 7 its exit. `using` runs 10..15. `lock` runs
// 20..23. 99 is done for all three.
//
// `CatchIndex` is the catch loop's cursor, held on the state rather than in a local because the walk
// SUSPENDS inside the loop — every catch clause costs the driver between three and five round trips.
//
// `ErrorsBefore` is the `using` declaration's guard, captured from the diagnostic sink's own count
// before the nested local-declaration walk runs: a resource whose declaration ALREADY failed must not
// also be told it is not disposable. The sink owns the error list, so the count is its own answer.
//
// THE TWO REBUILT COLLABORATORS AND THE ONE AMBIENT FACT ARE PASSED IN AT `Begin` RATHER THAN HELD.
// `Analyzer.cs` rebuilds the CLR conversion funnel and the assignability oracle when the metadata
// load context opens and again when it is disposed, so an owner constructed once may not keep a
// reference to either; `try` needs the funnel (through the throwability question) and `using` needs
// the oracle (through the nominal `IDisposable` question). The enclosing CLASS declaration is passed
// for the same reason a node is: it is an operand of the moment, and `lock` is the only walk that
// reads it.
public class ResourceStatementState {

    formValue: int
    tryNodeValue: TryStatement?
    usingNodeValue: UsingStatement?
    lockNodeValue: LockStatement?
    clrTypeConversionValue: AnalyzerClrTypeConversion?
    assignabilityValue: AnalyzerAssignability?
    currentClassValue: ClassDeclaration?

    Form: int => formValue
    TryNode: TryStatement? => tryNodeValue
    UsingNode: UsingStatement? => usingNodeValue
    LockNode: LockStatement? => lockNodeValue
    ClrTypeConversion: AnalyzerClrTypeConversion? => clrTypeConversionValue
    Assignability: AnalyzerAssignability? => assignabilityValue
    CurrentClass: ClassDeclaration? => currentClassValue

    public Phase: int
    public Pending: int
    public AnsweredType: TypeInfo
    public CatchIndex: int
    public CatchType: TypeInfo
    public ErrorsBefore: int

    constructor(
        form: int,
        tryNode: TryStatement?,
        usingNode: UsingStatement?,
        lockNode: LockStatement?,
        clrTypeConversion: AnalyzerClrTypeConversion?,
        assignability: AnalyzerAssignability?,
        currentClass: ClassDeclaration?) {
        formValue = form
        tryNodeValue = tryNode
        usingNodeValue = usingNode
        lockNodeValue = lockNode
        clrTypeConversionValue = clrTypeConversion
        assignabilityValue = assignability
        currentClassValue = currentClass

        Phase = 0
        if form == 1 {
            Phase = 10
        }

        if form == 2 {
            Phase = 20
        }

        Pending = 0
        AnsweredType = BuiltInTypes.Unknown
        CatchIndex = 0
        CatchType = BuiltInTypes.Unknown
        ErrorsBefore = 0
    }
}

// WHAT A GUARDED REGION IS IN N#, as three walks over one protocol.
//
// This family owns everything `try`, `using` and `lock` decide: which of the three reports fires and
// with which span and suggestion, what a catch clause's exception type resolves to when none is
// written, that a catch variable is declared in a scope opened at the TRY keyword rather than at the
// clause, that a `finally` body raises the ambient finally depth for exactly its own extent (which is
// what makes NL319 fire on a `return` inside one), that a `using` resource is measured for
// disposability only when its own declaration produced no error, that a value refused as a
// struct-of-arrays escape is not ALSO told it is not disposable, and that a monitor lock on a value
// type is refused while a lock on a type the analyzer cannot classify stays silent.
//
// THE THREE QUESTIONS IT ANSWERS ABOUT A TYPE ARE NOT ONE QUESTION. Throwability lives in
// `AnalyzerThrowability`, because a `throw` and an `assert throws` ask it too and neither is a
// resource statement. Disposability and value-type lockee-ness are asked by exactly one statement
// each and live here.
//
// DISPOSABILITY IS STRUCTURAL BEFORE IT IS NOMINAL, and the order is behaviour: a parameterless
// `Dispose` returning `void` — declared or reflected, and PUBLIC OR NOT — satisfies `using` even on a
// type that never names `IDisposable`, and only then does the nominal test run. A member whose return
// type is missing satisfies it too, which is what keeps a half-written `Dispose` from producing two
// errors at once.
//
// THE VALUE-TYPE LOCKEE TEST IS DELIBERATELY CONSERVATIVE and is NOT the inverse of
// `AnalyzerConversionFacts.IsReferenceType`: that predicate answers "can this be assigned null" and
// says no for `unknown`, external and generic types, every one of which must stay SILENT here —
// refusing a type the analyzer cannot classify would break locks on external .NET reference types.
//
// WHAT IT HOLDS AND WHAT IT IS HANDED. Every collaborator below is constructed exactly once by
// `Analyzer.cs` and never rebuilt with the metadata load context: the diagnostic sink, the span
// reader, the scope stack, the declaration context, the type resolver, the type substitution engine,
// the ambient context, the SoA escape owner and the throwability owner. The two that ARE rebuilt are
// handed in at `Begin`.
public class AnalyzerResourceStatements {

    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeResolverValue: AnalyzerTypeResolver
    typeSubstitutionValue: AnalyzerTypeSubstitution
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape
    throwabilityValue: AnalyzerThrowability

    constructor(
        diagnostics: AnalyzerDiagnosticSink,
        spans: AnalyzerDiagnosticSpans,
        scopes: AnalyzerScopeStack,
        declarationContext: AnalyzerDeclarationContext,
        typeResolver: AnalyzerTypeResolver,
        typeSubstitution: AnalyzerTypeSubstitution,
        ambient: AnalyzerAmbientContext,
        soaEscape: AnalyzerSoaEscape,
        throwability: AnalyzerThrowability) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        typeSubstitutionValue = typeSubstitution
        ambientValue = ambient
        soaEscapeValue = soaEscape
        throwabilityValue = throwability
    }

    // A `try` STATEMENT. The CLR conversion funnel is read from the caller's field HERE, for the
    // reason `ResourceStatementState` records.
    public func BeginTry(
        statement: TryStatement,
        clrTypeConversion: AnalyzerClrTypeConversion): ResourceStatementState {
        return new ResourceStatementState(0, statement, null, null, clrTypeConversion, null, null)
    }

    // A `using` STATEMENT. The assignability oracle is read from the caller's field HERE, for the
    // same reason.
    public func BeginUsing(
        statement: UsingStatement,
        assignability: AnalyzerAssignability): ResourceStatementState {
        return new ResourceStatementState(1, null, statement, null, null, assignability, null)
    }

    // A `lock` STATEMENT. The enclosing class declaration is an operand: a bare name lockee may be
    // one of ITS type parameters rather than the enclosing function's.
    public func BeginLock(
        statement: LockStatement,
        currentClass: ClassDeclaration?): ResourceStatementState {
        return new ResourceStatementState(2, null, null, statement, null, null, currentClass)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this statement is finished. Every phase
    // either decides something and advances, or emits exactly one request; the walk never advances
    // past a point whose answer it has not been given.
    public func NextResourceStep(state: ResourceStatementState): ResourceStatementRequest? {
        while state.Phase != 99 {
            request := AdvanceResource(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything — the `using` resource
    // expression's type and the `lock` object's type. The other six are operations.
    public func SupplyResource(state: ResourceStatementState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0
        if pending != 1 {
            return
        }

        if answer != null {
            state.AnsweredType = answer
        } else {
            state.AnsweredType = BuiltInTypes.Unknown
        }
    }

    func AdvanceResource(state: ResourceStatementState): ResourceStatementRequest? {
        tryNode := state.TryNode
        if tryNode != null {
            return AdvanceTry(state, tryNode)
        }

        usingNode := state.UsingNode
        if usingNode != null {
            return AdvanceUsing(state, usingNode)
        }

        lockNode := state.LockNode
        if lockNode != null {
            return AdvanceLock(state, lockNode)
        }

        state.Phase = 99
        return null
    }

    // ── THE `try` WALK ─────────────────────────────────────────────────────────────────────────
    //
    // Eight phases, of which five are the catch loop. The loop is a SUSPENDED loop: phase 1 is its
    // head, phase 5 its tail, and between them the driver has run a scope open, a symbol declaration,
    // a variable record and a whole nested statement dispatch. The scope a catch clause opens is
    // positioned at the TRY statement's own line and column rather than at the clause's, and the catch
    // variable is declared there too — preserved exactly, because those positions are what the IDE
    // reports a redeclaration against.
    func AdvanceTry(state: ResourceStatementState, statement: TryStatement): ResourceStatementRequest? {
        phase := state.Phase
        if phase == 0 {
            state.Phase = 1
            return NewStatementRequest(statement.TryBlock)
        }

        if phase == 1 {
            clauses := statement.CatchClauses
            if state.CatchIndex >= clauses.Count {
                state.Phase = 6
                return null
            }

            state.Phase = 2
            return NewScopeRequest(statement.Line, statement.Column)
        }

        if phase == 2 {
            clause := CatchAt(statement, state.CatchIndex)
            declaredType := clause.ExceptionType
            if declaredType != null {
                state.CatchType = typeResolverValue.ResolveDeclaredType(declaredType)
                ReportNonThrowableCatchTypeIfNeeded(declaredType, state)
            } else {
                state.CatchType = new SimpleTypeInfo("Exception")
            }

            variableName := clause.VariableName
            if variableName == null {
                state.Phase = 4
                return null
            }

            state.Phase = 3
            request := new ResourceStatementRequest(3, state.CatchType)
            request.Name = variableName
            request.Line = statement.Line
            request.Column = statement.Column
            return request
        }

        if phase == 3 {
            clause := CatchAt(statement, state.CatchIndex)
            state.Phase = 4
            request := new ResourceStatementRequest(4, state.CatchType)
            request.Name = clause.VariableName
            return request
        }

        if phase == 4 {
            clause := CatchAt(statement, state.CatchIndex)
            state.Phase = 5
            return NewStatementRequest(clause.Block)
        }

        if phase == 5 {
            state.CatchIndex = state.CatchIndex + 1
            state.Phase = 1
            return new ResourceStatementRequest(6, BuiltInTypes.Unknown)
        }

        // THE FINALLY DEPTH IS RAISED FOR EXACTLY THIS BODY. It is what NL319 reads: a `return` — or
        // a `break`/`continue` targeting a construct entered at a shallower depth — inside a finally
        // handler would leave it, which is illegal IL.
        if phase == 6 {
            finallyBlock := statement.FinallyBlock
            if finallyBlock == null {
                state.Phase = 99
                return null
            }

            ambientValue.EnterFinally()
            state.Phase = 7
            return NewStatementRequest(finallyBlock)
        }

        if phase == 7 {
            ambientValue.ExitFinally()
            state.Phase = 99
            return null
        }

        state.Phase = 99
        return null
    }

    func CatchAt(statement: TryStatement, index: int): CatchClause {
        clauses := statement.CatchClauses
        return clauses[index]
    }

    // NL202 ON A CATCH TYPE. The span is the type reference's own start, so the underline lands on
    // the written type rather than on the `catch` keyword. A clause with no written type cannot reach
    // this: a bare `catch` means `Exception`, which is throwable by definition.
    func ReportNonThrowableCatchTypeIfNeeded(typeReference: TypeReference, state: ResourceStatementState) {
        clrTypeConversion := state.ClrTypeConversion
        if clrTypeConversion == null {
            return
        }

        if throwabilityValue.IsThrowable(state.CatchType, clrTypeConversion) {
            return
        }

        span := TypeReferenceFacts.GetStartSpan(typeReference)
        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            "Catch type must be assignable to System.Exception, but this type is '"
                + TypeText(state.CatchType) + "'",
            span.StartLine,
            span.StartColumn,
            "Catch Exception or an Exception-derived type, or use a bare catch for all exceptions.",
            span.Length)
    }

    // ── THE `using` WALK ───────────────────────────────────────────────────────────────────────
    //
    // Six phases and TWO resource forms that share a scope, a body and a report but nothing else. A
    // DECLARATION runs the local-declaration walk and is then looked up by NAME — the declared type is
    // whatever that walk settled, which is why it is read from the scope stack rather than carried —
    // and it is measured only if the declaration itself reported nothing. An EXPRESSION is analysed
    // and measured directly, behind both SoA escape reports, and there the FIRST escape short-circuits
    // the second: unlike `print`, a `using` resource that is a row view is not also told it is a
    // direct column read.
    func AdvanceUsing(state: ResourceStatementState, statement: UsingStatement): ResourceStatementRequest? {
        phase := state.Phase
        if phase == 10 {
            state.Phase = 11
            return NewScopeRequest(statement.Line, statement.Column)
        }

        if phase == 11 {
            declaration := statement.Declaration
            if declaration != null {
                state.ErrorsBefore = diagnosticsValue.ErrorCount
                state.Phase = 12
                request := new ResourceStatementRequest(7, BuiltInTypes.Unknown)
                request.Declaration = declaration
                return request
            }

            resourceExpression := statement.Expression
            if resourceExpression != null {
                state.Phase = 13
                state.Pending = 1
                request := new ResourceStatementRequest(1, BuiltInTypes.Unknown)
                request.Node = resourceExpression
                return request
            }

            state.Phase = 14
            return null
        }

        if phase == 12 {
            state.Phase = 14
            declaration := statement.Declaration
            if declaration == null || diagnosticsValue.ErrorCount != state.ErrorsBefore {
                return null
            }

            resourceType := scopesValue.LookupSymbol(declaration.Name)
            if resourceType == null {
                return null
            }

            if IsDisposableResourceType(resourceType, state) {
                return null
            }

            span := AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(declaration)
            ReportNonDisposableUsingResource(resourceType, span.Line, span.Column, span.Length)
            return null
        }

        if phase == 13 {
            state.Phase = 14
            resourceExpression := statement.Expression
            if resourceExpression == null {
                return null
            }

            if soaEscapeValue.ReportSoaRowEscapeIfNeeded(
                    resourceExpression,
                    state.AnsweredType,
                    "used as a using resource") {
                return null
            }

            if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
                    resourceExpression,
                    "used as a using resource") {
                return null
            }

            if IsDisposableResourceType(state.AnsweredType, state) {
                return null
            }

            span := spansValue.GetExpressionDiagnosticSpan(resourceExpression)
            ReportNonDisposableUsingResource(state.AnsweredType, span.Line, span.Column, span.Length)
            return null
        }

        if phase == 14 {
            body := statement.Body
            state.Phase = 15
            if body == null {
                return null
            }

            return NewStatementRequest(body)
        }

        if phase == 15 {
            state.Phase = 99
            return new ResourceStatementRequest(6, BuiltInTypes.Unknown)
        }

        state.Phase = 99
        return null
    }

    // NL103 ON A `using` RESOURCE. One wording and one suggestion for both resource forms; only the
    // span differs, and each caller takes its own.
    func ReportNonDisposableUsingResource(resourceType: TypeInfo, line: int, column: int, length: int) {
        diagnosticsValue.Report(
            ErrorCode.InvalidSyntax,
            "Using resource of type '" + TypeText(resourceType)
                + "' must implement IDisposable or provide Dispose(): void",
            line,
            column,
            "Use a resource type with a parameterless void Dispose method, or remove the using statement.",
            length)
    }

    // ── THE `lock` WALK ────────────────────────────────────────────────────────────────────────
    //
    // Four phases. The gate runs BETWEEN the lockee's analysis and the body's scope, which is the
    // order `Analyzer.cs` had and is visible: a diagnostic about the lockee is reported before
    // anything inside the body is.
    func AdvanceLock(state: ResourceStatementState, statement: LockStatement): ResourceStatementRequest? {
        phase := state.Phase
        if phase == 20 {
            state.Phase = 21
            state.Pending = 1
            request := new ResourceStatementRequest(1, BuiltInTypes.Unknown)
            request.Node = statement.LockObject
            return request
        }

        if phase == 21 {
            state.Phase = 22
            ReportLockeeIfNeeded(statement.LockObject, state)
            return NewScopeRequest(statement.Line, statement.Column)
        }

        if phase == 22 {
            state.Phase = 23
            return NewStatementRequest(statement.Body)
        }

        if phase == 23 {
            state.Phase = 99
            return new ResourceStatementRequest(6, BuiltInTypes.Unknown)
        }

        state.Phase = 99
        return null
    }

    // NL320'S WHOLE GATE, AND THE THREE ARMS ARE AN else-if CHAIN RATHER THAN THREE TESTS.
    // A row view is reported and nothing else runs. Otherwise the direct-column probe ALWAYS runs —
    // it is the first operand of the second arm — and if it fires, the type-parameter arm is skipped
    // but the value-type arm is STILL reached: a column read that is also a value type gets both
    // squiggles, which is what the chain says and is preserved rather than tidied. A bare name that
    // IS an enclosing type parameter ends the chain whether or not it reports, so a `where T: class`
    // lockee never reaches the value-type test.
    func ReportLockeeIfNeeded(lockee: Expression, state: ResourceStatementState) {
        lockeeType := declarationContextValue.ResolveDeclaredAlias(state.AnsweredType)
        rowView := lockeeType as SoaRowTypeInfo
        if rowView != null {
            soaEscapeValue.ReportSoaRowEscape(lockee, "locked")
            return
        }

        columnEscaped := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(lockee, "locked")
        if !columnEscaped {
            named := lockeeType as SimpleTypeInfo
            if named != null {
                constraintKind := EnclosingTypeParameterKind(named.Name, state.CurrentClass)
                if constraintKind != 0 {
                    // Stricter by design: an unconstrained `T` would require boxing and could never
                    // provide mutual exclusion, so N# requires the parameter to be PROVABLY a
                    // reference.
                    if constraintKind == 1 {
                        ReportLockRequiresReferenceType(lockee, named.Name, true)
                    }

                    return
                }
            }
        }

        if IsKnownValueTypeLockee(lockeeType) {
            ReportLockRequiresReferenceType(lockee, TypeText(lockeeType), false)
        }
    }

    // NL320, RICH WHEN THE FILE CAN ANCHOR IT. The rich shape carries the source line, the underline
    // and a constraint-aware hint; the plain fallback is the analyzer's in-memory and generated-source
    // path, and its suggestion has the SAME two shapes.
    func ReportLockRequiresReferenceType(lockee: Expression, typeName: string, isTypeParameter: bool) {
        span := spansValue.GetExpressionDiagnosticSpan(lockee)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.LockRequiresReferenceType(
                currentFilePath,
                span.Line,
                span.Column,
                sourceSnippet,
                span.Length,
                typeName,
                isTypeParameter))
            return
        }

        suggestion := "Lock on a dedicated `object` field instead: `sync: object = new object()`"
        if isTypeParameter {
            suggestion = "Constrain `" + typeName + "` to a reference type (`where " + typeName
                + ": class`), or lock on a dedicated `object` field instead: `sync: object = new object()`"
        }

        diagnosticsValue.Report(
            ErrorCode.LockRequiresReferenceType,
            "'" + typeName + "' is not a reference type as required by the lock statement",
            span.Line,
            span.Column,
            suggestion,
            span.Length)
    }

    // ── WHETHER A NAME IS AN ENCLOSING TYPE PARAMETER, AND WHETHER IT IS PROVABLY A REFERENCE ───
    //
    // 0 is "not a type parameter of the enclosing function or type"; 1 is "a type parameter whose
    // constraints do not prove it is a reference"; 2 is "provably a reference". Only the FUNCTION's
    // constraints are consulted, exactly as `Analyzer.cs` did — a class-level constraint list is not
    // reached from here — and an INTERFACE constraint proves nothing, because a struct may implement
    // one.
    func EnclosingTypeParameterKind(name: string, currentClass: ClassDeclaration?): int {
        currentFunction := ambientValue.CurrentFunction
        declaredOnFunction := DeclaresTypeParameter(FunctionTypeParameters(currentFunction), name)
        declaredOnType := DeclaresTypeParameter(ClassTypeParameters(currentClass), name)
        if !declaredOnFunction && !declaredOnType {
            return 0
        }

        if !declaredOnFunction || currentFunction == null {
            return 1
        }

        constraint := FindConstraint(currentFunction, name)
        if constraint == null {
            return 1
        }

        specialBits := Convert.ToInt32(constraint.SpecialConstraints)
        classBit := Convert.ToInt32(SpecialConstraintKind.Class)
        if (specialBits & classBit) == classBit {
            return 2
        }

        constraintReferences := constraint.Constraints
        index := 0
        while index < constraintReferences.Count {
            constraintReference := constraintReferences[index]
            constraintType := declarationContextValue.ResolveDeclaredAlias(
                typeResolverValue.ResolveType(constraintReference))
            if IsReferenceConstraintType(constraintType) {
                return 2
            }

            index = index + 1
        }

        return 1
    }

    static func FunctionTypeParameters(declaration: FunctionDeclaration?): List<TypeParameter>? {
        if declaration == null {
            return null
        }

        return declaration.TypeParameters
    }

    static func ClassTypeParameters(declaration: ClassDeclaration?): List<TypeParameter>? {
        if declaration == null {
            return null
        }

        return declaration.TypeParameters
    }

    static func DeclaresTypeParameter(typeParameters: List<TypeParameter>?, name: string): bool {
        if typeParameters == null {
            return false
        }

        index := 0
        while index < typeParameters.Count {
            candidate := typeParameters[index]
            if candidate.Name == name {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func FindConstraint(declaration: FunctionDeclaration, name: string): GenericConstraint? {
        constraints := declaration.Constraints
        if constraints == null {
            return null
        }

        index := 0
        while index < constraints.Count {
            candidate := constraints[index]
            if candidate.TypeParameter == name {
                return candidate
            }

            index = index + 1
        }

        return null
    }

    // A BASE-CLASS CONSTRAINT PROVES A REFERENCE; AN INTERFACE ONE DOES NOT. A record answers by
    // whether it is a struct record, and a reflected constraint by the CLR's own answer.
    static func IsReferenceConstraintType(constraintType: TypeInfo): bool {
        classConstraint := constraintType as ClassTypeInfo
        if classConstraint != null {
            return true
        }

        recordConstraint := constraintType as RecordTypeInfo
        if recordConstraint != null {
            return !recordConstraint.IsStruct
        }

        reflectedConstraint := constraintType as ReflectionTypeInfo
        if reflectedConstraint != null {
            clrType := reflectedConstraint.Type
            return clrType.get_IsClass()
        }

        return false
    }

    // ── WHETHER A TYPE IS A KNOWN VALUE TYPE FOR THE LOCK RULE ─────────────────────────────────
    //
    // Deliberately conservative: everything it cannot classify — `unknown`, external, generic and
    // every class-like shape — answers NO and stays silent.
    func IsKnownValueTypeLockee(candidate: TypeInfo): bool {
        simple := candidate as SimpleTypeInfo
        if simple != null {
            if IsPrimitiveValueTypeName(simple.Name) {
                return true
            }

            // A bare name can reach here for a user struct or enum the expression analysis did not
            // materialize into its declaration-backed `TypeInfo` — resolve it and re-classify.
            resolved := scopesValue.LookupType(simple.Name)
            if resolved == null {
                return false
            }

            resolvedSimple := resolved as SimpleTypeInfo
            if resolvedSimple != null {
                return false
            }

            return IsKnownValueTypeLockee(resolved)
        }

        structType := candidate as StructTypeInfo
        if structType != null {
            return true
        }

        enumType := candidate as EnumTypeInfo
        if enumType != null {
            return true
        }

        tupleType := candidate as TupleTypeInfo
        if tupleType != null {
            return true
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return recordType.IsStruct
        }

        // `T?` over a value type is `Nullable<T>` — itself a struct. Over a reference type it is only
        // a nullability annotation.
        nullable := candidate as NullableTypeInfo
        if nullable != null {
            return IsKnownValueTypeLockee(nullable.InnerType)
        }

        oblivious := candidate as ObliviousTypeInfo
        if oblivious != null {
            return IsKnownValueTypeLockee(oblivious.InnerType)
        }

        // A byref loads the referenced value when it is used as an expression.
        byRef := candidate as ByRefTypeInfo
        if byRef != null {
            return IsKnownValueTypeLockee(byRef.InnerType)
        }

        reflected := candidate as ReflectionTypeInfo
        if reflected != null {
            clrType := reflected.Type
            return clrType.get_IsValueType()
        }

        return false
    }

    static func IsPrimitiveValueTypeName(name: string): bool {
        return name == "int" || name == "long" || name == "float" || name == "double"
            || name == "decimal" || name == "byte" || name == "sbyte" || name == "short"
            || name == "ushort" || name == "uint" || name == "ulong" || name == "char"
            || name == "bool" || name == "void"
    }

    // ── WHETHER A TYPE MAY BE A `using` RESOURCE ───────────────────────────────────────────────
    //
    // `unknown` passes, because a resource whose type failed to resolve already carries that error.
    // The wrappers unwrap; a NULLABLE additionally requires the thing it wraps to be a REFERENCE, so
    // a `Nullable<SomeDisposableStruct>` is refused. A simple name and a closed generic redirect to
    // what they declare, and a redirect that goes nowhere falls through to the structural and nominal
    // tests rather than answering no.
    func IsDisposableResourceType(candidate: TypeInfo, state: ResourceStatementState): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        if BuiltInTypes.IsUnknown(resolved) {
            return true
        }

        oblivious := resolved as ObliviousTypeInfo
        if oblivious != null {
            return IsDisposableResourceType(oblivious.InnerType, state)
        }

        byRef := resolved as ByRefTypeInfo
        if byRef != null {
            return IsDisposableResourceType(byRef.InnerType, state)
        }

        nullable := resolved as NullableTypeInfo
        if nullable != null {
            innerType := declarationContextValue.ResolveDeclaredAlias(nullable.InnerType)
            if !AnalyzerConversionFacts.IsReferenceType(innerType) {
                return false
            }

            return IsDisposableResourceType(innerType, state)
        }

        simple := resolved as SimpleTypeInfo
        if simple != null {
            namedType := scopesValue.LookupType(simple.Name)
            if namedType != null && !Object.ReferenceEquals(namedType, resolved) {
                return IsDisposableResourceType(namedType, state)
            }
        }

        generic := resolved as GenericTypeInfo
        if generic != null {
            genericDefinition := typeSubstitutionValue.ResolveGenericDefinition(generic)
            if genericDefinition != null {
                return IsDisposableResourceType(genericDefinition, state)
            }
        }

        if HasDisposePattern(resolved) {
            return true
        }

        return IsNominallyDisposable(resolved, state)
    }

    // THE STRUCTURAL TEST: a parameterless `Dispose` returning `void`, declared or reflected.
    func HasDisposePattern(candidate: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        classType := resolved as ClassTypeInfo
        if classType != null {
            return HasDeclaredDisposeMember(classType.DeclaredMembers)
        }

        structType := resolved as StructTypeInfo
        if structType != null {
            return HasDeclaredDisposeMember(structType.DeclaredMembers)
        }

        recordType := resolved as RecordTypeInfo
        if recordType != null {
            return HasDeclaredDisposeMember(recordType.DeclaredMembers)
        }

        interfaceType := resolved as InterfaceTypeInfo
        if interfaceType != null {
            return HasDeclaredDisposeMember(interfaceType.DeclaredMembers)
        }

        reflected := resolved as ReflectionTypeInfo
        if reflected != null {
            return HasReflectedDisposeMember(reflected.Type)
        }

        return false
    }

    // A DECLARED `Dispose`. A member with NO written return type satisfies it, which keeps a
    // half-written `Dispose` from producing a second error here.
    func HasDeclaredDisposeMember(members: DeclaredMemberInfo[]): bool {
        index := 0
        while index < members.Length {
            member := members[index]
            index = index + 1
            if member.Kind != DeclaredMemberKind.Function {
                continue
            }

            if member.Name != "Dispose" || member.IsStatic || member.ParameterCount != 0 {
                continue
            }

            returnType := member.ReturnType
            if returnType == null {
                return true
            }

            if BuiltInTypes.Is(typeResolverValue.ResolveType(returnType), BuiltInTypes.Void) {
                return true
            }
        }

        return false
    }

    // A REFLECTED `Dispose`. Visibility is deliberately wide — a non-public member satisfies the
    // pattern here, as it did in `Analyzer.cs`.
    static func HasReflectedDisposeMember(clrType: Type): bool {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        noParameters := new Type[](0)
        dispose := clrType.GetMethod("Dispose", flags, null, noParameters, null)
        if dispose == null {
            return false
        }

        if dispose.get_IsStatic() {
            return false
        }

        return dispose.get_ReturnType() == VoidRuntimeType()
    }

    // THE NOMINAL TEST. A reflected type answers by real CLR assignability; a declared class, struct,
    // record or interface answers through the assignability oracle against the reflected
    // `System.IDisposable`, and everything else answers no.
    func IsNominallyDisposable(candidate: TypeInfo, state: ResourceStatementState): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        reflected := resolved as ReflectionTypeInfo
        if reflected != null {
            return AnalyzerConversionFacts.IsReflectionAssignableFrom(DisposableRoot(), reflected.Type)
        }

        if !IsDeclaredNominalShape(resolved) {
            return false
        }

        assignability := state.Assignability
        if assignability == null {
            return false
        }

        return assignability.IsSubtypeOf(resolved, new ReflectionTypeInfo(DisposableRoot()))
    }

    static func IsDeclaredNominalShape(resolved: TypeInfo): bool {
        classType := resolved as ClassTypeInfo
        if classType != null {
            return true
        }

        structType := resolved as StructTypeInfo
        if structType != null {
            return true
        }

        recordType := resolved as RecordTypeInfo
        if recordType != null {
            return true
        }

        interfaceType := resolved as InterfaceTypeInfo
        if interfaceType != null {
            return true
        }

        return false
    }

    // ── THE TWO RUNTIME IDENTITIES THIS FAMILY COMPARES AGAINST ────────────────────────────────
    //
    // Both are named through `Type.GetType` rather than `typeof`, the door `AnalyzerLoopSequence`
    // already opens for the non-generic sequence interfaces: the pinned toolset's `typeof` surface
    // does not carry `void`, and naming both roots the same way keeps the two lookups on one
    // mechanism. Both resolve to `System.Private.CoreLib`, so the identity is the one `typeof` would
    // have given.
    static func DisposableRoot(): Type {
        disposable := Type.GetType("System.IDisposable")
        if disposable == null {
            throw new InvalidOperationException("Required interface System.IDisposable was not found.")
        }

        return disposable
    }

    static func VoidRuntimeType(): Type {
        voidType := Type.GetType("System.Void")
        if voidType == null {
            throw new InvalidOperationException("Required type System.Void was not found.")
        }

        return voidType
    }

    // ── SHARED REQUEST SHAPES ──────────────────────────────────────────────────────────────────

    static func NewStatementRequest(body: Statement): ResourceStatementRequest {
        request := new ResourceStatementRequest(5, BuiltInTypes.Unknown)
        request.Body = body
        return request
    }

    static func NewScopeRequest(line: int, column: int): ResourceStatementRequest {
        request := new ResourceStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = line
        request.Column = column
        return request
    }

    static func TypeText(typeInfo: TypeInfo): string {
        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}
