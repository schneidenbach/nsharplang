namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// A NAME A `setup` BLOCK LEAVES BEHIND FOR EVERY TEST IN THE FILE.
//
// It is a class rather than a positional tuple because it outlives the walk that produced it: the
// collection pass runs once over the whole compilation unit and the list is then read by every test
// and by the teardown, each of which declares the name at the position the SETUP wrote it — so a
// hover over an injected name points at the `setup` line, not at the test's.
class SetupSymbol {
    nameValue: string
    typeValue: TypeInfo
    lineValue: int
    columnValue: int

    Name: string => nameValue
    Type: TypeInfo => typeValue
    Line: int => lineValue
    Column: int => columnValue

    constructor(name: string, symbolType: TypeInfo, line: int, column: int) {
        nameValue = name
        typeValue = symbolType
        lineValue = line
        columnValue = column
    }
}

// ONE STEP A DECLARATION WALK CANNOT TAKE FOR ITSELF.
//
// The kinds:
//   1  analyse an EXPRESSION, plainly. It ANSWERS a type. Two callers: a table-driven test case
//      value, which the OWNER brackets with the column's declared type first — the bracket spans the
//      suspension, so it is the owner's and not the driver's — and a constructor's `this(…)` /
//      `base(…)` initializer, which is bracketed by nothing at all. The driver performs the SAME
//      operation for both, which is why there is one kind and not two.
//   2  open a FUNCTION scope on the analyzer's scope stack at `Line` / `Column`. All four forms open
//      a function scope: a test, a `setup`, a `teardown` and a constructor are each a body.
//   3  declare `Name` of `CarriedType` into that scope at `Line` / `Column`.
//   4  record that same name in the semantic model the IDE's hover and completion read.
//   5  analyse a statement LIST — the body's statements, walked as a list rather than as the block
//      itself, so the body does not open a second scope inside the function scope.
//   6  close the scope kind 2 opened.
//   7  validate a parameter LIST for `params` placement and default-value legality.
//   8  analyse a STATEMENT — the constructor's body, which IS handed over as the block. The
//      constructor differs from the other three here deliberately, and it is the shape
//      `Analyzer.cs` wrote: a constructor's block opens its own block scope inside the function
//      scope, and the test/`setup`/`teardown` bodies do not.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class DeclarationWalkRequest {
    Kind: int
    Node: Expression?
    Body: Statement?
    Statements: List<Statement>?
    Parameters: List<Parameter>?
    CarriedType: TypeInfo
    Name: string?
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Body = null
        Statements = null
        Parameters = null
        CarriedType = carriedType
        Name = null
        Line = 0
        Column = 0
    }
}

// THE WHOLE STATE OF ONE DECLARATION WALK, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` names which of the four this is — 0 a test, 1 a `setup`, 2 a `teardown`, 3 a constructor —
// and the four occupy DISJOINT phase ranges (0-19, 20-29, 30-39, 40-59) rather than sharing a
// numbering. That is deliberate and it is the standing rule this arc paid for once already: a phase
// number that means two things in two forms is a fall-through waiting to happen.
//
// `Assignability` is CARRIED rather than held, for the reason the type-declaration and function-body
// walks carry it: `Analyzer.cs` REBUILDS the assignability owner whenever the metadata load context
// opens or closes, and an owner that held one would hold a stale one. Everything else this walk
// reads — the sink, the spans, the type resolver, the ambient context, the definite-assignment
// checker — is constructed once and never rebuilt, which is also why the SETUP SYMBOLS can live on
// the owner itself.
class DeclarationWalkState {
    formValue: int
    testValue: TestDeclaration?
    setupValue: SetupDeclaration?
    teardownValue: TeardownDeclaration?
    constructorValue: ConstructorDeclaration?
    assignabilityValue: AnalyzerAssignability

    Form: int => formValue
    Test: TestDeclaration? => testValue
    Setup: SetupDeclaration? => setupValue
    Teardown: TeardownDeclaration? => teardownValue
    Constructor: ConstructorDeclaration? => constructorValue
    Assignability: AnalyzerAssignability => assignabilityValue

    Phase: int
    Pending: int

    // The setup-symbol injection cursor, the parameter cursor, and the table-case row and value
    // cursors. A test uses all four; a `teardown` uses only the first.
    SymbolIndex: int
    ParameterIndex: int
    RowIndex: int
    ValueIndex: int

    // The parameter type resolved by the declare step and carried into the record step, so the type
    // is resolved ONCE per parameter — resolving a type reference RECORDS it, and a second
    // resolution would record it twice.
    ParameterType: TypeInfo

    // The table header's column types, positionally. A row value is checked against the column at
    // its own index, and a row with more values than the header has columns is checked only as far
    // as the header goes.
    ColumnTypes: List<TypeInfo>
    ColumnNames: List<string>

    // The target-typing slot's value from BEFORE the current table case value was entered, and the
    // column that value is being measured against. All three exist only for the table-case walk.
    SavedExpectedType: TypeInfo?
    ExpectedValueType: TypeInfo
    ExpectedValueName: string

    // The outstanding step's answer, folded in by `Supply`.
    AnswerType: TypeInfo

    constructor(form: int, test: TestDeclaration?, setup: SetupDeclaration?, teardown: TeardownDeclaration?, ctor: ConstructorDeclaration?, assignability: AnalyzerAssignability, phase: int) {
        formValue = form
        testValue = test
        setupValue = setup
        teardownValue = teardown
        constructorValue = ctor
        assignabilityValue = assignability
        Phase = phase
        Pending = 0
        SymbolIndex = 0
        ParameterIndex = 0
        RowIndex = 0
        ValueIndex = 0
        ParameterType = BuiltInTypes.Unknown
        ColumnTypes = new List<TypeInfo>()
        ColumnNames = new List<string>()
        SavedExpectedType = null
        ExpectedValueType = BuiltInTypes.Unknown
        ExpectedValueName = ""
        AnswerType = BuiltInTypes.Unknown
    }
}

// WHAT A TEST, A `setup`, A `teardown` AND A CONSTRUCTOR MEAN.
//
// The four live together because they share one vocabulary and one shape: each opens a FUNCTION
// scope, puts some names into it, walks a body and closes the scope. What separates them is which
// names go in and where those names came from — and that is the whole of what this owner decides.
//
// IT OWNS:
//   * that a `setup` block's variable declarations are COLLECTED once for the whole file and then
//     INJECTED into every test and into the `teardown`, at the position the `setup` wrote them, so
//     that a test may reference a setup-declared name it never declared itself;
//   * that a setup symbol's type is its WRITTEN type when it has one, and otherwise is inferred from
//     the initializer's SHAPE alone — a literal, a `new`, an array of them, or one of the three
//     transparent wrappers — falling back to `object` rather than to `unknown`, because an injected
//     name with no usable type must still be a name;
//   * that only ONE `setup` and ONE `teardown` are allowed per file, that the SECOND and every later
//     one is reported, and that the first `setup`'s symbols are the ones collected;
//   * that a table-driven test declares its header parameters as ordinary locals, at each
//     parameter's own position when it has one and at the test's otherwise;
//   * that a table ROW whose value count does not match the header is reported ONCE for the row,
//     against the TEST's position rather than the row's, and that its values are still checked as
//     far as the header goes;
//   * that a table case VALUE must be a compile-time constant — the six literals, a parenthesised
//     one, or a negated numeric literal — that a `typeof` value is measured by the row-type rule
//     FIRST and is not ALSO told it is not constant when that rule already spoke, and that the
//     refusal names the shape the user wrote;
//   * that a row value is then measured against its column's declared type, under that type as the
//     ambient expectation, and that neither an unknown column nor an unknown value is scolded;
//   * that a constructor enters the CONSTRUCTOR ambient boundary before its scope opens and leaves
//     it after that scope closes; that its parameters are validated before any name in it exists;
//     that its `this(…)` / `base(…)` initializer is analysed BEFORE its body; and that
//     definite-assignment of the declaring class's fields is checked only when there is a declaring
//     class AND no initializer — because an initializer hands that duty to the constructor it
//     chains to.
//
// What it cannot do is open or close a scope on the analyzer's scope stack, declare a name into it,
// write the semantic model, run the analyzer's expression or statement walk, or validate a parameter
// list — so it ASKS. Nothing here is a policy the driver may reinterpret.
class AnalyzerDeclarationWalkers {
    diagnostics: AnalyzerDiagnosticSink
    spans: AnalyzerDiagnosticSpans
    typeResolver: AnalyzerTypeResolver
    ambient: AnalyzerAmbientContext
    definiteAssignment: AnalyzerDefiniteAssignment
    setupSymbols: List<SetupSymbol>

    constructor(diagnosticSink: AnalyzerDiagnosticSink, spansOwner: AnalyzerDiagnosticSpans, resolver: AnalyzerTypeResolver, ambientContext: AnalyzerAmbientContext, definiteAssignmentOwner: AnalyzerDefiniteAssignment) {
        diagnostics = diagnosticSink
        spans = spansOwner
        typeResolver = resolver
        ambient = ambientContext
        definiteAssignment = definiteAssignmentOwner
        setupSymbols = new List<SetupSymbol>()
    }

    // THE FILE'S TEST SCAFFOLDING, DECIDED ONCE BEFORE ANY DECLARATION IS WALKED.
    //
    // Two rules and one collection, in ONE pass in declaration order: at most one `setup`, at most
    // one `teardown`, and the FIRST `setup`'s variable declarations become the file's injected
    // symbols. The two rules are written differently on purpose and the difference is `Analyzer.cs`'s
    // own: a duplicate `setup` does not collect, while a duplicate `teardown` has nothing to collect,
    // so its flag is set unconditionally.
    //
    // The symbol list is REPLACED rather than cleared, because a test that captured the previous
    // analysis's list must not see this one's.
    func CollectTestScaffolding(declarations: List<Declaration>) {
        setupSymbols = new List<SetupSymbol>()
        foundSetup := false
        foundTeardown := false
        index := 0
        while index < declarations.Count {
            declaration := declarations[index]
            setup := declaration as SetupDeclaration
            if setup != null {
                if foundSetup {
                    diagnostics.Report(ErrorCode.DuplicateDeclaration, "Only one setup block is allowed per test file", setup.Line, setup.Column, null, 5)
                } else {
                    foundSetup = true
                    CollectSetupSymbols(setup)
                }
            } else {
                teardown := declaration as TeardownDeclaration
                if teardown != null {
                    if foundTeardown {
                        diagnostics.Report(ErrorCode.DuplicateDeclaration, "Only one teardown block is allowed per test file", teardown.Line, teardown.Column, null, 8)
                    }

                    foundTeardown = true
                }
            }

            index = index + 1
        }
    }

    // THE NAMES A `setup` BLOCK LEAVES BEHIND: its top-level variable declarations, in written order.
    // Only the block's OWN statements are read — a variable declared inside an `if` inside the setup
    // is scoped to that `if` and is not the file's.
    func CollectSetupSymbols(setup: SetupDeclaration) {
        index := 0
        while index < setup.Body.Statements.Count {
            variableDeclaration := setup.Body.Statements[index] as VariableDeclarationStatement
            if variableDeclaration != null {
                symbolType := ResolveSetupSymbolType(variableDeclaration)
                setupSymbols.Add(new SetupSymbol(variableDeclaration.Name, symbolType, variableDeclaration.Line, variableDeclaration.Column))
            }

            index = index + 1
        }
    }

    // WHAT AN INJECTED NAME'S TYPE IS. The written type wins; otherwise the initializer's SHAPE is
    // read; otherwise `object`. It is `object` and not `unknown` deliberately: the name exists in
    // every test in the file whatever its type turned out to be, and `unknown` would make every use
    // of it a second complaint about the same unwritten type.
    func ResolveSetupSymbolType(variableDeclaration: VariableDeclarationStatement): TypeInfo {
        writtenType := variableDeclaration.Type
        if writtenType != null {
            return typeResolver.ResolveType(writtenType)
        }

        initializer := variableDeclaration.Initializer
        if initializer != null {
            inferred := InferSetupInitializerType(initializer)
            if inferred != null {
                return inferred
            }
        }

        return BuiltInTypes.Object
    }

    // THE INITIALIZER'S SHAPE, AND NOTHING ELSE. This is deliberately NOT the expression walk: the
    // collection pass runs BEFORE the global scope holds anything, so nothing here may resolve a
    // name. A literal answers its own type, a `new` answers its written type when that type
    // resolves, an array answers an array of its FIRST element's shape, and the three transparent
    // wrappers hand the question through. Anything else answers null, which the caller reads as
    // `object`.
    func InferSetupInitializerType(expression: Expression): TypeInfo? {
        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            return BuiltInTypes.Int
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return BuiltInTypes.Double
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            return BuiltInTypes.Char
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            return BuiltInTypes.String
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            return BuiltInTypes.String
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            return BuiltInTypes.Bool
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            return BuiltInTypes.Null
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            writtenType := newExpression.Type
            if writtenType == null {
                return null
            }

            resolved := typeResolver.ResolveType(writtenType)
            if BuiltInTypes.IsUnknown(resolved) {
                return null
            }

            return resolved
        }

        arrayLiteral := expression as ArrayLiteralExpression
        if arrayLiteral != null {
            if arrayLiteral.Elements.Count == 0 {
                return null
            }

            elementType := InferSetupInitializerType(arrayLiteral.Elements[0])
            if elementType == null {
                return null
            }

            return new ArrayTypeInfo(elementType)
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return InferSetupInitializerType(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return InferSetupInitializerType(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return InferSetupInitializerType(uncheckedExpression.Expression)
        }

        return null
    }

    func BeginTest(test: TestDeclaration, assignability: AnalyzerAssignability): DeclarationWalkState {
        return new DeclarationWalkState(0, test, null, null, null, assignability, 0)
    }

    func BeginSetup(setup: SetupDeclaration, assignability: AnalyzerAssignability): DeclarationWalkState {
        return new DeclarationWalkState(1, null, setup, null, null, assignability, 20)
    }

    func BeginTeardown(teardown: TeardownDeclaration, assignability: AnalyzerAssignability): DeclarationWalkState {
        return new DeclarationWalkState(2, null, null, teardown, null, assignability, 30)
    }

    func BeginConstructor(ctor: ConstructorDeclaration, assignability: AnalyzerAssignability): DeclarationWalkState {
        return new DeclarationWalkState(3, null, null, null, ctor, assignability, 40)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this declaration is walked.
    func NextStep(state: DeclarationWalkState): DeclarationWalkRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything the walk reads: the expression
    // it asked for. The scope, declare, record, statement, parameter-list and body steps answer
    // nothing.
    func Supply(state: DeclarationWalkState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending != 1 {
            return
        }

        if answer != null {
            state.AnswerType = answer
        } else {
            state.AnswerType = BuiltInTypes.Unknown
        }
    }

    func Advance(state: DeclarationWalkState): DeclarationWalkRequest? {
        phase := state.Phase
        if phase < 20 {
            return AdvanceTest(state)
        }

        if phase < 30 {
            return AdvanceSetup(state)
        }

        if phase < 40 {
            return AdvanceTeardown(state)
        }

        return AdvanceConstructor(state)
    }

    // ------------------------------------------------------------------------------------------
    // THE TEST WALK — phases 0 through 11.
    // ------------------------------------------------------------------------------------------
    func AdvanceTest(state: DeclarationWalkState): DeclarationWalkRequest? {
        test := state.Test
        if test == null {
            state.Phase = 99
            return null
        }

        phase := state.Phase
        if phase == 0 {
            ReportUnsupportedSkipClause(test)
            state.Phase = 1
            return OpenScope(test.Line, test.Column)
        }

        if phase == 1 {
            return DeclareInjectedSymbol(state, 2, 3)
        }

        if phase == 2 {
            return RecordInjectedSymbol(state, 1)
        }

        if phase == 3 {
            parameters := test.TableParameters
            if parameters == null {
                state.Phase = 10
                return null
            }

            state.Phase = 4
            return ValidateParameters(parameters, test.Line, test.Column)
        }

        if phase == 4 {
            return DeclareTableParameter(state, test)
        }

        if phase == 5 {
            return RecordTableParameter(state, test)
        }

        if phase == 6 {
            state.ParameterIndex = state.ParameterIndex + 1
            state.Phase = 4
            return null
        }

        if phase == 7 {
            return EnterTableRow(state, test)
        }

        if phase == 8 {
            return AdvanceTableValue(state, test)
        }

        if phase == 9 {
            return CompleteTableValue(state, test)
        }

        if phase == 10 {
            state.Phase = 11
            return WalkStatements(test.Body.Statements)
        }

        state.Phase = 99
        return CloseScope()
    }

    // PHASE 0 ALSO — THE `skip "reason"` CLAUSE, REFUSED WHERE THE DEVELOPER WROTE IT.
    //
    // `skip` is written by the docs, parsed by the recovery parser into `TestDeclaration.SkipReason`,
    // rendered by the formatter and listed by the LSP — and emitted by NOTHING. The runner capability
    // was MEASURED and declined (020 slice 2: zero consumers across 2,818 attributed test methods, and
    // a STATIC modifier cannot express the runtime preconditions the only candidates wanted), so a
    // file that spells `skip` cannot be built and will not become buildable.
    //
    // Before this report the refusal reached the developer as the WHOLE FILE declining at
    // `parse.declaration-scan` — no code, no line, no column, no reason, and every passing test in the
    // same file taken down with it. Reporting here is what turns that into one `NL323` at a position,
    // with a suggestion, everywhere the analyzer runs. It is a REFUSAL, not a step toward the
    // capability: nothing here emits, skips or reports a skipped test.
    //
    // THE SPAN IS THE DECLARATION HEAD, NOT THE `skip` TOKEN. `TestDeclaration` carries the reason but
    // not the clause's own position, and giving it one reshapes the AST and its columnar
    // materialization for four characters of squiggle; the message names the clause instead.
    func ReportUnsupportedSkipClause(test: TestDeclaration) {
        if test.SkipReason == null {
            return
        }

        diagnostics.Report(ErrorCode.FeatureNotImplemented, "test '" + test.Description + "' declares 'skip', which is parsed for forward compatibility but is not compiled by 'nlc test'", test.Line, test.Column, "Delete the skip clause and its reason, or comment out the whole test declaration — nlc test cannot report a skipped test.", 4)
    }

    // PHASES 1 AND 2 — THE `setup` BLOCK'S NAMES, INJECTED. Each is declared and then recorded, at
    // the position the SETUP wrote it. `doneNext` is the phase to move to when the list is spent,
    // which is the ONLY thing that differs between the test's injection and the `teardown`'s.
    func DeclareInjectedSymbol(state: DeclarationWalkState, recordPhase: int, donePhase: int): DeclarationWalkRequest? {
        if state.SymbolIndex >= setupSymbols.Count {
            state.Phase = donePhase
            return null
        }

        symbol := setupSymbols[state.SymbolIndex]
        state.Phase = recordPhase
        request := new DeclarationWalkRequest(3, symbol.Type)
        request.Name = symbol.Name
        request.Line = symbol.Line
        request.Column = symbol.Column
        return request
    }

    func RecordInjectedSymbol(state: DeclarationWalkState, declarePhase: int): DeclarationWalkRequest? {
        symbol := setupSymbols[state.SymbolIndex]
        state.SymbolIndex = state.SymbolIndex + 1
        state.Phase = declarePhase
        request := new DeclarationWalkRequest(4, symbol.Type)
        request.Name = symbol.Name
        return request
    }

    // PHASE 4 — A TABLE HEADER COLUMN, DECLARED. Its type is resolved ONCE here and carried into the
    // record step, and it is also remembered positionally: the row values are measured against it.
    func DeclareTableParameter(state: DeclarationWalkState, test: TestDeclaration): DeclarationWalkRequest? {
        parameters := test.TableParameters
        if parameters == null || state.ParameterIndex >= parameters.Count {
            state.RowIndex = 0
            state.Phase = 7
            return null
        }

        parameter := parameters[state.ParameterIndex]
        parameterType := typeResolver.ResolveDeclaredType(parameter.Type)
        state.ParameterType = parameterType
        state.ColumnTypes.Add(parameterType)
        state.ColumnNames.Add(parameter.Name)
        position := AnalyzerBindingFacts.GetParameterDeclarationPosition(parameter.Line, parameter.Column, test.Line, test.Column)
        state.Phase = 5
        request := new DeclarationWalkRequest(3, parameterType)
        request.Name = parameter.Name
        request.Line = position.Item1
        request.Column = position.Item2
        return request
    }

    func RecordTableParameter(state: DeclarationWalkState, test: TestDeclaration): DeclarationWalkRequest? {
        parameters := test.TableParameters
        state.Phase = 6
        request := new DeclarationWalkRequest(4, state.ParameterType)
        if parameters != null {
            request.Name = parameters[state.ParameterIndex].Name
        }

        return request
    }

    // PHASE 7 — ONE TABLE ROW. The arity report fires ONCE per row and anchors on the TEST rather
    // than on the row, which is `Analyzer.cs`'s own choice and is what a reader of a wide table
    // needs: the row has no position of its own worth pointing at.
    func EnterTableRow(state: DeclarationWalkState, test: TestDeclaration): DeclarationWalkRequest? {
        cases := test.TableCases
        parameters := test.TableParameters
        if cases == null || parameters == null || state.RowIndex >= cases.Count {
            state.Phase = 10
            return null
        }

        row := cases[state.RowIndex]
        if row.Count != parameters.Count {
            diagnostics.Report(ErrorCode.TypeMismatch, "This test case has " + row.Count.ToString() + " values but the table header declares " + parameters.Count.ToString() + " parameters — each row must have exactly one value per parameter", test.Line, test.Column, null, 0)
        }

        state.ValueIndex = 0
        state.Phase = 8
        return null
    }

    // PHASE 8 — ONE VALUE IN THAT ROW. The constant check ALWAYS runs, for its reports; only then is
    // the surplus-value case skipped. A value that is not constant is not ALSO measured against a
    // column type, and a value beyond the header's width has no column to be measured against.
    func AdvanceTableValue(state: DeclarationWalkState, test: TestDeclaration): DeclarationWalkRequest? {
        cases := test.TableCases
        if cases == null {
            state.Phase = 10
            return null
        }

        row := cases[state.RowIndex]
        if state.ValueIndex >= row.Count {
            state.RowIndex = state.RowIndex + 1
            state.Phase = 7
            return null
        }

        value := row[state.ValueIndex]
        valuesToValidate := Math.Min(row.Count, state.ColumnTypes.Count)
        if !ValidateTableCaseValue(value) || state.ValueIndex >= valuesToValidate {
            state.ValueIndex = state.ValueIndex + 1
            return null
        }

        state.ExpectedValueType = state.ColumnTypes[state.ValueIndex]
        state.ExpectedValueName = state.ColumnNames[state.ValueIndex]
        state.SavedExpectedType = ambient.EnterExpectedType(state.ExpectedValueType)
        state.Phase = 9
        state.Pending = 1
        request := new DeclarationWalkRequest(1, BuiltInTypes.Unknown)
        request.Node = value
        return request
    }

    // PHASE 9 — WHAT THAT VALUE TURNED OUT TO BE, MEASURED AGAINST ITS COLUMN. The ambient
    // expectation is left BEFORE the comparison, because the comparison is not part of the value's
    // analysis. Neither an unknown column nor an unknown value is scolded: an unknown here is
    // somebody else's report, already made.
    func CompleteTableValue(state: DeclarationWalkState, test: TestDeclaration): DeclarationWalkRequest? {
        ambient.ExitExpectedType(state.SavedExpectedType)
        state.SavedExpectedType = null
        cases := test.TableCases
        if cases == null {
            state.Phase = 10
            return null
        }

        row := cases[state.RowIndex]
        value := row[state.ValueIndex]
        expectedType := state.ExpectedValueType
        actualType := state.AnswerType
        state.ValueIndex = state.ValueIndex + 1
        state.Phase = 8
        if BuiltInTypes.IsUnknown(expectedType) || BuiltInTypes.IsUnknown(actualType) || state.Assignability.IsAssignable(expectedType, actualType) {
            return null
        }

        span := spans.GetExpressionDiagnosticSpan(value)
        diagnostics.Report(ErrorCode.TypeMismatch, "Table-driven test case value for '" + state.ExpectedValueName + "' is '" + AnalyzerExpressionStatements.TypeText(actualType) + "', but the table header declares '" + AnalyzerExpressionStatements.TypeText(expectedType) + "'", span.Line, span.Column, "Change the literal or the '" + state.ExpectedValueName + "' parameter type so the row value matches.", span.Length)
        return null
    }

    // IS THIS ROW VALUE A COMPILE-TIME CONSTANT? ANSWERS whether it may go on to be type-checked.
    //
    // A `typeof` value gets the SoA row-type rule first, and if that rule spoke the value is refused
    // SILENTLY — one sentence about a row view is the report the reader needs, and "not a constant"
    // on top of it would be a second sentence about the same token.
    func ValidateTableCaseValue(expression: Expression): bool {
        if IsSupportedTableCaseValue(expression) {
            return true
        }

        errorsBefore := diagnostics.ErrorCount
        typeOfExpression := expression as TypeOfExpression
        if typeOfExpression != null {
            typeResolver.ReportSoaRowTypeReferencesIn(typeOfExpression.Type)
        }

        if diagnostics.ErrorCount != errorsBefore {
            return false
        }

        span := spans.GetExpressionDiagnosticSpan(expression)
        diagnostics.Report(ErrorCode.ConstantRequired, "Table-driven test case values must be compile-time constants; " + DescribeTableCaseValue(expression) + " is not supported here", span.Line, span.Column, "Use literal int, float, char, string, bool, or null values in table rows.", span.Length)
        return false
    }

    // THE CLOSED SET A TABLE ROW MAY HOLD: the six literals, a parenthesised one, and a NEGATED
    // numeric literal — because `-1` is a unary operator over a literal in the AST and a table of
    // negative numbers is the ordinary case, not an exotic one.
    static func IsSupportedTableCaseValue(expression: Expression): bool {
        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            return true
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return true
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            return true
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            return true
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            return true
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            return true
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return IsSupportedTableCaseValue(parenthesized.Inner)
        }

        unary := expression as UnaryExpression
        if unary != null && unary.Operator == UnaryOperator.Negate {
            negatedInt := unary.Operand as IntLiteralExpression
            if negatedInt != null {
                return true
            }

            negatedFloat := unary.Operand as FloatLiteralExpression
            if negatedFloat != null {
                return true
            }
        }

        return false
    }

    // WHAT TO CALL A ROW VALUE THAT IS NOT CONSTANT. A call and a `typeof` are named outright; a
    // description that already reads as a phrase is used as written; anything else is lower-cased
    // and suffixed, so `Binary` reads `binary expression` in the sentence.
    static func DescribeTableCaseValue(expression: Expression): string {
        description := AnalyzerExpressionStatements.DescribeExpression(expression)
        call := expression as CallExpression
        if call != null {
            return "call"
        }

        typeOfExpression := expression as TypeOfExpression
        if typeOfExpression != null {
            return "typeof expression"
        }

        if description.Contains(' ') {
            return description
        }

        return char.ToLowerInvariant(description[0]).ToString() + description.Substring(1) + " expression"
    }

    // ------------------------------------------------------------------------------------------
    // THE `setup` WALK — phases 20 through 22. Its body is ANALYSED even though its symbols were
    // already collected: the collection pass read shapes, and the body still has to be checked.
    // ------------------------------------------------------------------------------------------
    func AdvanceSetup(state: DeclarationWalkState): DeclarationWalkRequest? {
        setup := state.Setup
        if setup == null {
            state.Phase = 99
            return null
        }

        phase := state.Phase
        if phase == 20 {
            state.Phase = 21
            return OpenScope(setup.Line, setup.Column)
        }

        if phase == 21 {
            state.Phase = 22
            return WalkStatements(setup.Body.Statements)
        }

        state.Phase = 99
        return CloseScope()
    }

    // ------------------------------------------------------------------------------------------
    // THE `teardown` WALK — phases 30 through 34. It gets the injected names for the same reason a
    // test does: cleanup code refers to what the setup created.
    // ------------------------------------------------------------------------------------------
    func AdvanceTeardown(state: DeclarationWalkState): DeclarationWalkRequest? {
        teardown := state.Teardown
        if teardown == null {
            state.Phase = 99
            return null
        }

        phase := state.Phase
        if phase == 30 {
            state.Phase = 31
            return OpenScope(teardown.Line, teardown.Column)
        }

        if phase == 31 {
            return DeclareInjectedSymbol(state, 32, 33)
        }

        if phase == 32 {
            return RecordInjectedSymbol(state, 31)
        }

        if phase == 33 {
            state.Phase = 34
            return WalkStatements(teardown.Body.Statements)
        }

        state.Phase = 99
        return CloseScope()
    }

    // ------------------------------------------------------------------------------------------
    // THE CONSTRUCTOR WALK — phases 40 through 49.
    // ------------------------------------------------------------------------------------------
    func AdvanceConstructor(state: DeclarationWalkState): DeclarationWalkRequest? {
        ctor := state.Constructor
        if ctor == null {
            state.Phase = 99
            return null
        }

        phase := state.Phase
        if phase == 40 {
            // The ambient boundary opens BEFORE the scope and closes AFTER it, so it is held by this
            // owner across every suspension in between rather than by the driver.
            ambient.EnterConstructor()
            state.Phase = 41
            return OpenScope(ctor.Line, ctor.Column)
        }

        if phase == 41 {
            state.Phase = 42
            return ValidateParameters(ctor.Parameters, ctor.Line, ctor.Column)
        }

        if phase == 42 {
            return DeclareConstructorParameter(state, ctor)
        }

        if phase == 43 {
            return RecordConstructorParameter(state, ctor)
        }

        if phase == 44 {
            state.ParameterIndex = state.ParameterIndex + 1
            state.Phase = 42
            return null
        }

        if phase == 45 {
            initializer := ctor.Initializer
            state.Phase = 46
            if initializer == null {
                return null
            }

            state.Pending = 1
            request := new DeclarationWalkRequest(1, BuiltInTypes.Unknown)
            request.Node = initializer
            return request
        }

        if phase == 46 {
            state.Phase = 47
            request := new DeclarationWalkRequest(8, BuiltInTypes.Unknown)
            request.Body = ctor.Body
            return request
        }

        if phase == 47 {
            // Definite assignment is the DECLARING CLASS's question, and a constructor that chains
            // to another one has handed the duty over: the fields it does not set are the other
            // constructor's to set.
            currentClass := ambient.CurrentClass
            if currentClass != null && ctor.Initializer == null {
                definiteAssignment.CheckConstructorFields(ctor, currentClass)
            }

            state.Phase = 48
            return null
        }

        if phase == 48 {
            state.Phase = 49
            return CloseScope()
        }

        ambient.ExitConstructor()
        state.Phase = 99
        return null
    }

    func DeclareConstructorParameter(state: DeclarationWalkState, ctor: ConstructorDeclaration): DeclarationWalkRequest? {
        if state.ParameterIndex >= ctor.Parameters.Count {
            state.Phase = 45
            return null
        }

        parameter := ctor.Parameters[state.ParameterIndex]
        parameterType := typeResolver.ResolveDeclaredType(parameter.Type)
        state.ParameterType = parameterType
        position := AnalyzerBindingFacts.GetParameterDeclarationPosition(parameter.Line, parameter.Column, ctor.Line, ctor.Column)
        state.Phase = 43
        request := new DeclarationWalkRequest(3, parameterType)
        request.Name = parameter.Name
        request.Line = position.Item1
        request.Column = position.Item2
        return request
    }

    func RecordConstructorParameter(state: DeclarationWalkState, ctor: ConstructorDeclaration): DeclarationWalkRequest? {
        parameter := ctor.Parameters[state.ParameterIndex]
        state.Phase = 44
        request := new DeclarationWalkRequest(4, state.ParameterType)
        request.Name = parameter.Name
        return request
    }

    // ------------------------------------------------------------------------------------------
    // THE FOUR REQUESTS ALL FOUR FORMS SHARE.
    // ------------------------------------------------------------------------------------------
    func OpenScope(line: int, column: int): DeclarationWalkRequest {
        request := new DeclarationWalkRequest(2, BuiltInTypes.Unknown)
        request.Line = line
        request.Column = column
        return request
    }

    func CloseScope(): DeclarationWalkRequest {
        return new DeclarationWalkRequest(6, BuiltInTypes.Unknown)
    }

    func WalkStatements(statements: List<Statement>): DeclarationWalkRequest {
        request := new DeclarationWalkRequest(5, BuiltInTypes.Unknown)
        request.Statements = statements
        return request
    }

    func ValidateParameters(parameters: List<Parameter>, line: int, column: int): DeclarationWalkRequest {
        request := new DeclarationWalkRequest(7, BuiltInTypes.Unknown)
        request.Parameters = parameters
        request.Line = line
        request.Column = column
        return request
    }
}
