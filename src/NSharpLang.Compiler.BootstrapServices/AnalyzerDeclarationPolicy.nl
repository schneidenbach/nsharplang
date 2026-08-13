namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// ONE STEP THE PARAMETER WALK CANNOT TAKE FOR ITSELF.
//
// There is exactly ONE kind, and like the import walk's it asks for an EFFECT rather than for an
// answer:
//
//   1  analyse this default-value expression against this expected type.
//
// The analysis is the shell's expression door, and it must be the shell's: it brackets the ambient
// expected type with `try` / `finally` so the ambient is restored even if the analysis THROWS, and a
// guarantee that spans a suspension is one an owner cannot keep. What the walk owns is everything
// around it — WHICH parameters are checked, in which order, and what the two possible outcomes mean.
//
// The step carries no answer back because there is nothing to carry: the shell discards the type too.
// What the walk needs to know is whether the analysis REPORTED anything, and it asks the diagnostic
// sink for its own count on both sides of the suspension rather than being told.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class ParameterWalkRequest {
    Kind: int
    Node: Expression
    ExpectedType: TypeInfo

    constructor(kind: int, node: Expression, expectedType: TypeInfo) {
        Kind = kind
        Node = node
        ExpectedType = expectedType
    }
}

// THE WHOLE STATE OF ONE PARAMETER-LIST WALK, SUSPENDED BETWEEN TWO STEPS.
//
// `foundOptional` is the ordering rule's entire memory: once a parameter with a default has been
// seen, every later parameter without one is an error. It is carried in the state rather than
// recomputed because the walk can suspend in the middle of the list.
//
// `errorsBefore` is the mark taken immediately before a suspension and read immediately after it, and
// it is the only way the walk learns whether the expression it handed out was rejected.
class ParameterWalkState {
    Phase: int
    Pending: int

    Parameters: List<Parameter>
    Index: int
    Line: int
    Column: int

    FoundOptional: bool
    ErrorsBefore: int
    SoaTableName: string
    PendingDefault: Expression?

    constructor(parameters: List<Parameter>, line: int, column: int) {
        Phase = 0
        Pending = 0
        Parameters = parameters
        Index = 0
        Line = line
        Column = column
        FoundOptional = false
        ErrorsBefore = 0
        SoaTableName = ""
        PendingDefault = null
    }
}

// WHAT IT MEANS TO DECLARE SOMETHING — a symbol, a type, a parameter with a default, or a package.
//
// These are four questions with one subject: a name being introduced, and what the compiler owes the
// developer when it is. They share the scope stack, the declaration-name span rule and the binding
// map, and every one of them either rejects the declaration or records it somewhere the IDE reads.
//
// A SYMBOL. `DeclareSymbol` is the only place in the compiler where two declarations of the same name
// can legally coexist, and the rule that permits it is OVERLOADING: a function declared beside an
// existing function of the same name MERGES into a method group when — and only when — both carry a
// SOURCE parameter signature and the new one's signature is distinct from every signature already
// there. Everything else that collides is a duplicate-declaration error. The merge has two shapes,
// depending on whether the existing entry is a lone function or an already-built group, and both
// record a binding declaration for the NEW spelling: an overload the developer can go-to-definition
// on is one they can see.
//
// The non-colliding path does three things in order: it checks SHADOWING, then binds the name and
// its default null state, then records the declaration in both the binding map and the scope.
// `recordBinding` exists because some walks declare a name that has no written spelling to point at.
//
// SHADOWING IS A HARD ERROR (NL316), not a warning, and deliberately so. A local or parameter that
// hides a local or parameter from an enclosing scope is build-blocking; because it is a compiler
// error it suppresses the linter's NL020 for the same file, so the developer sees exactly one
// diagnostic rather than two for one mistake. Note that reporting it does NOT abandon the
// declaration — the name is still bound, which is what stops one shadowing mistake from becoming a
// cascade of "undefined" reports behind it. The deciding walk also stops dead at the first GLOBAL or
// type-level scope, so a local named after a global shadows nothing.
//
// A TYPE. `DeclareType` resolves the name to its CANONICAL type first when the declaration context
// knows one — the same type declared in two files must be one identity, not two — and skips that for
// an alias, whose whole point is to be a second name. Duplicates are rejected; everything else is
// recorded in four places, because four different consumers ask: the scope, the semantic model, the
// type-declaration file map and the binding map. An alias registers as an alias and everything else
// as a canonical type.
//
// A PARAMETER WITH A DEFAULT. Two rules, checked in list order so the reports come out in written
// order. First, a required parameter may not follow an optional one — that is a POSITION rule and the
// squiggle lands on the parameter. Second, a default value must be something the compiler can
// evaluate into metadata: literals, `null`, a matching enum member, and the unary, binary and array
// combinations of those, recursively. `this` parameters and `params` parameters are skipped by both
// rules, because neither can carry a default.
//
// An SoA table is rejected with its own sentence rather than the generic one, because the generic
// sentence would be misleading: the value is not un-evaluatable in principle, it is a runtime
// construction, and the suggestion says what to do instead. That check runs FIRST and, when it
// applies, suppresses the generic report entirely — including when the analysis of the default
// produced its own errors, which are better than either sentence.
//
// A PACKAGE. Every dot-separated segment of a package name must be a valid identifier. The report
// names the SEGMENT that failed rather than the whole name, and one bad segment does not stop the
// remaining segments from being checked.
//
// This owner is NOT rebuilt with the metadata-load-context SCC: everything it holds is constructed
// once. The semantic model and the binding map are the exceptions and arrive at `BeginAnalysis`,
// because the shell `new`s both per `Analyze` and held ones would be the previous file's.
class AnalyzerDeclarationPolicy {
    diagnostics: AnalyzerDiagnosticSink
    spans: AnalyzerDiagnosticSpans
    scopes: AnalyzerScopeStack
    nullFlow: AnalyzerNullFlow
    declarationContext: AnalyzerDeclarationContext
    typeResolver: AnalyzerTypeResolver
    parameterDeclarations: AnalyzerParameterDeclarations
    projectDiscovery: AnalyzerProjectTypeDiscovery

    // The analyzer's LIVE collections, held by reference and never resnapshotted.
    mlcAssemblies: List<Assembly>
    usingAliases: Dictionary<string, string>
    importedSymbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>
    importedDeclarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>
    typeDeclarationFiles: Dictionary<string, string>

    // Recreated per `Analyze` by the shell, so they arrive at `BeginAnalysis` rather than at
    // construction.
    semanticModel: SemanticModel?
    bindingMap: BindingMap?
    currentFilePath: string?
    declarationContextFilePath: string?
    compilationUnit: CompilationUnit?

    constructor(diagnosticSink: AnalyzerDiagnosticSink, diagnosticSpans: AnalyzerDiagnosticSpans, scopeStack: AnalyzerScopeStack, flow: AnalyzerNullFlow, context: AnalyzerDeclarationContext, resolver: AnalyzerTypeResolver, parameters: AnalyzerParameterDeclarations, discovery: AnalyzerProjectTypeDiscovery, assemblies: List<Assembly>, aliases: Dictionary<string, string>, symbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>, declarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>, declarationFiles: Dictionary<string, string>) {
        diagnostics = diagnosticSink
        spans = diagnosticSpans
        scopes = scopeStack
        nullFlow = flow
        declarationContext = context
        typeResolver = resolver
        parameterDeclarations = parameters
        projectDiscovery = discovery
        mlcAssemblies = assemblies
        usingAliases = aliases
        importedSymbolsByAlias = symbolsByAlias
        importedDeclarationsByAlias = declarationsByAlias
        typeDeclarationFiles = declarationFiles
        semanticModel = null
        bindingMap = null
        currentFilePath = null
        declarationContextFilePath = null
        compilationUnit = null
    }

    // One call per analysis, from the reset block, AFTER the semantic model and the binding map have
    // been recreated. The declaration-context file path is set later, by the shell's context
    // initialisation, so it has its own setter rather than arriving here.
    func BeginAnalysis(model: SemanticModel, bindings: BindingMap, filePath: string?, unit: CompilationUnit?) {
        semanticModel = model
        bindingMap = bindings
        currentFilePath = filePath
        compilationUnit = unit
        declarationContextFilePath = null
    }

    // The declaration context's file path is established after the imports are walked, so it is set
    // separately from `BeginAnalysis`.
    func SetDeclarationContextFilePath(filePath: string?) {
        declarationContextFilePath = filePath
    }

    // ----------------------------------------------------------------------------------------------
    // A SYMBOL
    // ----------------------------------------------------------------------------------------------

    func DeclareSymbol(name: string, symbolType: TypeInfo, line: int, column: int, declarationKind: string?, recordBinding: bool) {
        currentScope := scopes.Peek()
        nameColumn := spans.GetDeclarationNameColumn(name, line, column)

        existing: TypeInfo = BuiltInTypes.Unknown
        if currentScope.Symbols.TryGetValue(name, out existing) {
            if TryMergeOverload(currentScope, name, symbolType, existing, line, nameColumn, declarationKind, recordBinding) {
                return
            }

            diagnostics.Report(ErrorCode.DuplicateDeclaration, "'" + name + "' is already declared in this scope — each name must be unique within the same scope", line, nameColumn, null, NameLength(name))
            return
        }

        CheckShadowedDeclaration(name, symbolType, line, nameColumn)

        currentScope.Symbols[name] = symbolType
        currentScope.NullStates[name] = nullFlow.GetDefaultNullState(symbolType)

        kind := DeclarationKind(declarationKind, symbolType)
        if recordBinding {
            RecordDeclaration(name, line, nameColumn, kind)
            currentScope.RecordDeclarationLocation(name, currentFilePath, line, nameColumn, kind)
        }
    }

    // THE OVERLOAD MERGE, IN ITS TWO SHAPES. Answers whether the collision was absorbed; a `false`
    // means the caller reports a duplicate. Both shapes require the NEW declaration to be a function
    // with a source parameter signature — a reflection-derived signature is not something the source
    // may overload against.
    func TryMergeOverload(currentScope: Scope, name: string, symbolType: TypeInfo, existing: TypeInfo, line: int, nameColumn: int, declarationKind: string?, recordBinding: bool): bool {
        newFunction := symbolType as FunctionTypeInfo
        if newFunction == null || !AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(newFunction) {
            return false
        }

        // SHAPE ONE: a lone function already holds the name. The two become a group.
        //
        // The distinctness question is asked against the EXISTING function ALONE. A list that also
        // held the new function would compare it with itself, match, and answer "not distinct" for
        // every overload ever written.
        existingFunction := existing as FunctionTypeInfo
        if existingFunction != null && AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(existingFunction) {
            existingOnly := new List<FunctionTypeInfo>()
            existingOnly.Add(existingFunction)
            if AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(newFunction, existingOnly) {
                pair := new List<FunctionTypeInfo>()
                pair.Add(existingFunction)
                pair.Add(newFunction)
                currentScope.Symbols[name] = NSharpMethodGroupInfoFactory.FromFunctions(pair)
                RecordOverloadDeclaration(name, symbolType, line, nameColumn, declarationKind, recordBinding)
                return true
            }
        }

        // SHAPE TWO: a group already holds the name. The new function joins it, but only if EVERY
        // member of the group is a source function — a group that already contains a reflection
        // overload is not one the source may extend.
        group := existing as NSharpMethodGroupInfo
        if group != null {
            functions := NSharpMethodGroupInfoFactory.GetFunctions(group)
            if AllHaveSourceParameterSignature(functions) && AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(newFunction, functions) {
                NSharpMethodGroupInfoFactory.AddFunction(group, newFunction)
                RecordOverloadDeclaration(name, symbolType, line, nameColumn, declarationKind, recordBinding)
                return true
            }
        }

        return false
    }

    func AllHaveSourceParameterSignature(functions: List<FunctionTypeInfo>): bool {
        index := 0
        while index < functions.Count {
            if !AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(functions[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // A merged overload records its declaration but does NOT touch the scope's declaration-location
    // table: the name's location there is the FIRST declaration's, which is what go-to-definition on
    // the name itself should reach.
    func RecordOverloadDeclaration(name: string, symbolType: TypeInfo, line: int, nameColumn: int, declarationKind: string?, recordBinding: bool) {
        if !recordBinding {
            return
        }

        RecordDeclaration(name, line, nameColumn, DeclarationKind(declarationKind, symbolType))
    }

    func RecordDeclaration(name: string, line: int, nameColumn: int, kind: string) {
        bindings := bindingMap
        if bindings == null {
            return
        }

        declaration := new SymbolDeclaration(name, currentFilePath, line, nameColumn, kind)
        bindings.RecordDeclaration(declaration)
    }

    func DeclarationKind(declarationKind: string?, symbolType: TypeInfo): string {
        if declarationKind != null {
            return declarationKind
        }

        return AnalyzerBindingFacts.TypeInfoToDeclarationKind(symbolType)
    }

    // A zero-length squiggle is invisible, so an empty name still underlines one column.
    func NameLength(name: string): int {
        if name.Length > 1 {
            return name.Length
        }

        return 1
    }

    // NL316. Build-blocking rather than advisory: shadowing hides the outer binding and invites bugs
    // whose cause is invisible at the point of failure.
    func CheckShadowedDeclaration(name: string, symbolType: TypeInfo, line: int, nameColumn: int) {
        if !scopes.ShadowsEnclosingValueBinding(name, symbolType) {
            return
        }

        // Every defaulted parameter is passed explicitly: omitting one is the recorded columnar
        // decline shape.
        suggestion := ErrorSuggestions.GetSuggestion(ErrorCode.ShadowedDeclaration, name, null)
        diagnostics.Report(ErrorCode.ShadowedDeclaration, "'" + name + "' shadows an existing '" + name + "' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs", line, nameColumn, suggestion, NameLength(name))
    }

    // ----------------------------------------------------------------------------------------------
    // A TYPE
    // ----------------------------------------------------------------------------------------------

    func DeclareType(name: string, declaredType: TypeInfo, line: int, column: int) {
        resolvedType := CanonicalTypeFor(name, declaredType)

        currentScope := scopes.Peek()
        nameColumn := spans.GetDeclarationNameColumn(name, line, column)
        if currentScope.Types.ContainsKey(name) {
            diagnostics.Report(ErrorCode.DuplicateDeclaration, "A type named '" + name + "' already exists — each type name must be unique", line, nameColumn, null, NameLength(name))
            return
        }

        currentScope.Types[name] = resolvedType

        model := semanticModel
        if model != null {
            model.RecordType(name, resolvedType)
        }

        filePath := currentFilePath
        if filePath != null && filePath.Length > 0 {
            typeDeclarationFiles[name] = filePath
        }

        RegisterInDeclarationContext(name, resolvedType)

        kind := AnalyzerBindingFacts.TypeInfoToDeclarationKind(resolvedType)
        RecordDeclaration(name, line, nameColumn, kind)
        currentScope.RecordDeclarationLocation(name, currentFilePath, line, nameColumn, kind)
    }

    // THE SAME TYPE DECLARED IN TWO FILES MUST BE ONE IDENTITY. An alias is exempt: being a second
    // name for something is what it is for, and canonicalising it would erase it.
    func CanonicalTypeFor(name: string, declaredType: TypeInfo): TypeInfo {
        contextPath := declarationContextFilePath
        if contextPath == null {
            return declaredType
        }

        alias := declaredType as AliasTypeInfo
        if alias != null {
            return declaredType
        }

        canonicalType: TypeInfo = BuiltInTypes.Unknown
        if declarationContext.TryGetCanonicalType(contextPath, name, out canonicalType) && !BuiltInTypes.IsUnknown(canonicalType) {
            return canonicalType
        }

        return declaredType
    }

    func RegisterInDeclarationContext(name: string, resolvedType: TypeInfo) {
        contextPath := declarationContextFilePath
        if contextPath == null {
            return
        }

        declaredAlias := resolvedType as AliasTypeInfo
        if declaredAlias != null {
            declarationContext.RegisterDeclaredAlias(contextPath, declaredAlias)
            return
        }

        declarationContext.RegisterCanonicalType(contextPath, name, resolvedType)
    }

    // ----------------------------------------------------------------------------------------------
    // A PACKAGE
    // ----------------------------------------------------------------------------------------------

    // One report per bad SEGMENT: a name with two bad segments is two mistakes, and stopping at the
    // first would hide the second until the first was fixed.
    //
    // The parser's recovery preserves each segment AS WRITTEN, with its span
    // (ColumnarParserRecovery.ParsePackageSegment), so the report can name `'9bad'` and underline
    // it. A segment whose text is the `<error>` placeholder had no written text to carry (end of
    // file, reserved keyword, detached offender) and the parser has already reported precisely at
    // that site — a second report naming the placeholder would be noise, so it is skipped. The
    // Name-splitting fallback serves hand-constructed declarations with no parser segments; its
    // reports anchor on the declaration, exactly as before segments existed.
    func ValidatePackageName(declaration: PackageDeclaration) {
        segments := declaration.Segments
        if segments != null {
            segmentIndex := 0
            while segmentIndex < segments.Count {
                segment := segments[segmentIndex]
                if segment.Text != "<error>" && !IsValidIdentifier(segment.Text) {
                    diagnostics.Report(ErrorCode.InvalidSyntax, PackageNameReport(segment.Text), segment.Line, segment.Column, null, segment.Length)
                }

                segmentIndex = segmentIndex + 1
            }

            return
        }

        parts := declaration.Name.Split('.')
        index := 0
        while index < parts.Length {
            if !IsValidIdentifier(parts[index]) {
                diagnostics.Report(ErrorCode.InvalidSyntax, PackageNameReport(parts[index]), declaration.Line, declaration.Column, null, 0)
            }

            index = index + 1
        }
    }

    static func PackageNameReport(segment: string): string {
        return "Package name '" + segment + "' is not a valid identifier — package names must start with a letter and contain only letters, digits, and underscores"
    }

    // A letter or an underscore, then letters, digits and underscores. An empty segment — which is
    // what a leading, trailing or doubled dot produces — is not valid.
    static func IsValidIdentifier(name: string): bool {
        if name == null {
            return false
        }

        if name.Length == 0 {
            return false
        }

        first := name[0]
        if !char.IsLetter(first) && first != '_' {
            return false
        }

        index := 1
        while index < name.Length {
            current := name[index]
            if !char.IsLetterOrDigit(current) && current != '_' {
                return false
            }

            index = index + 1
        }

        return true
    }

    // ----------------------------------------------------------------------------------------------
    // A PARAMETER WITH A DEFAULT — THE PROTOCOL
    // ----------------------------------------------------------------------------------------------

    // The `params` rule is checked FIRST, whole, before the walk begins, because its reports belong
    // ahead of the default-value reports in the one ordered list and it never suspends.
    func BeginParameterDeclarations(parameters: List<Parameter>, line: int, column: int): ParameterWalkState {
        return new ParameterWalkState(parameters, line, column)
    }

    func NextStep(state: ParameterWalkState): ParameterWalkRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // The one kind answers NOTHING — what it produced is diagnostics, which this owner counts for
    // itself — so the walk records only that the step is done.
    func Supply(state: ParameterWalkState) {
        state.Pending = 0
    }

    func Advance(state: ParameterWalkState): ParameterWalkRequest? {
        if state.Phase == 0 {
            parameterDeclarations.ValidateParamsParameters(state.Parameters, state.Line, state.Column)
            state.Phase = 1
            return null
        }

        if state.Phase == 2 {
            ResumeSoaDefault(state)
            return null
        }

        if state.Index >= state.Parameters.Count {
            state.Phase = 99
            return null
        }

        parameter := state.Parameters[state.Index]

        // Neither a `this` receiver nor a `params` tail can carry a default, so neither rule applies.
        if parameter.IsThis || parameter.Modifier == ParameterModifier.Params {
            state.Index = state.Index + 1
            return null
        }

        defaultValue := parameter.DefaultValue
        if defaultValue == null {
            // THE POSITION RULE. A required parameter after an optional one.
            if state.FoundOptional {
                span := AnalyzerDiagnosticSpanFacts.GetParameterDiagnosticSpan(parameter, state.Line, state.Column)
                diagnostics.Report(ErrorCode.RequiredParameterAfterOptional, "Required parameter '" + parameter.Name + "' can't come after optional parameters — move it before the optional ones, or give it a default value too", span.Line, span.Column, null, span.Length)
            }

            state.Index = state.Index + 1
            return null
        }

        state.FoundOptional = true

        // THE SoA RULE, WHICH MAY SUSPEND. When it applies it takes over the parameter entirely.
        soaRequest := BeginSoaDefaultCheck(state, parameter, defaultValue)
        if soaRequest != null {
            return soaRequest
        }

        // THE VALUE RULE. Everything the compiler cannot evaluate into metadata.
        if !IsValidDefaultValue(defaultValue, parameter.Type) {
            span := spans.GetExpressionDiagnosticSpan(defaultValue)
            diagnostics.Report(ErrorCode.InvalidDefaultParameterValue, "The default value for '" + parameter.Name + "' must be something the compiler can evaluate — use a literal, null, or a simple constant", span.Line, span.Column, null, span.Length)
        }

        state.Index = state.Index + 1
        return null
    }

    // Answers a request when the parameter's declared type is an SoA table, and null when the SoA rule
    // does not apply and the generic value rule should run instead.
    func BeginSoaDefaultCheck(state: ParameterWalkState, parameter: Parameter, defaultValue: Expression): ParameterWalkRequest? {
        if !SoaFeature.IsEnabled {
            return null
        }

        parameterType := typeResolver.ResolveDeclaredType(parameter.Type)
        resolved := declarationContext.ResolveDeclaredAlias(GetNonNullableType(parameterType))
        soaRecordType := resolved as SoaRecordTypeInfo
        if soaRecordType == null {
            return null
        }

        state.ErrorsBefore = diagnostics.ErrorCount
        state.SoaTableName = soaRecordType.Declaration.Name
        state.PendingDefault = defaultValue
        state.Phase = 2
        state.Pending = 1
        return new ParameterWalkRequest(1, defaultValue, parameterType)
    }

    // AFTER THE ANALYSIS. If analysing the default produced its own errors those are the better
    // report and this rule stays quiet; otherwise the value analysed cleanly and is still not a
    // metadata constant, which is exactly the case the SoA sentence exists for. Either way the
    // parameter is finished — the generic value rule never runs for it.
    func ResumeSoaDefault(state: ParameterWalkState) {
        state.Phase = 1
        pendingDefault := state.PendingDefault
        state.PendingDefault = null
        state.Index = state.Index + 1

        if diagnostics.ErrorCount > state.ErrorsBefore {
            return
        }

        if pendingDefault == null {
            return
        }

        tableName := state.SoaTableName
        span := spans.GetExpressionDiagnosticSpan(pendingDefault)
        diagnostics.Report(ErrorCode.InvalidDefaultParameterValue, "SoA table '" + tableName + "' cannot be used as a default parameter value — optional parameter defaults are metadata constants, but SoA tables must be constructed or wrapped at runtime", span.Line, span.Column, "Use an overload that creates the table with 'new " + tableName + "(capacity)' or accepts a '" + tableName + ".wrap(...)' value from the caller.", span.Length)
    }

    // ----------------------------------------------------------------------------------------------
    // WHAT THE COMPILER CAN EVALUATE INTO METADATA
    // ----------------------------------------------------------------------------------------------

    // The six literal forms, a matching enum member, and the unary, binary and array combinations of
    // those. The recursion carries the SAME expected type down, which is what makes an enum member
    // valid inside a `|` combination of flags but not inside one against a different enum.
    func IsValidDefaultValue(expr: Expression, expectedType: TypeReference): bool {
        if expr is IntLiteralExpression || expr is FloatLiteralExpression || expr is CharLiteralExpression || expr is BoolLiteralExpression || expr is StringLiteralExpression || expr is NullLiteralExpression {
            return true
        }

        memberAccess := expr as MemberAccessExpression
        if memberAccess != null {
            return IsMatchingEnumMemberDefault(memberAccess, expectedType)
        }

        unary := expr as UnaryExpression
        if unary != null {
            return IsValidDefaultValue(unary.Operand, expectedType)
        }

        binary := expr as BinaryExpression
        if binary != null {
            if !IsValidDefaultValue(binary.Left, expectedType) {
                return false
            }

            return IsValidDefaultValue(binary.Right, expectedType)
        }

        arrayLiteral := expr as ArrayLiteralExpression
        if arrayLiteral != null {
            return AllElementsAreValidDefaults(arrayLiteral, expectedType)
        }

        return false
    }

    func AllElementsAreValidDefaults(arrayLiteral: ArrayLiteralExpression, expectedType: TypeReference): bool {
        elements := arrayLiteral.Elements
        index := 0
        while index < elements.Count {
            if !IsValidDefaultValue(elements[index], expectedType) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // AN ENUM MEMBER IS A VALID DEFAULT ONLY FOR ITS OWN ENUM. The owner named on the left of the dot
    // must resolve to the SAME type the parameter is declared as — not merely to an enum — and the
    // member must actually exist on it. A null-conditional access is never a constant.
    //
    // Both source enums and runtime enums answer, and the runtime side is restricted to Int32-backed
    // enums because that is what the metadata constant can hold.
    func IsMatchingEnumMemberDefault(memberAccess: MemberAccessExpression, expectedType: TypeReference): bool {
        if memberAccess.IsNullConditional {
            return false
        }

        ownerName := ""
        if !AnalyzerAttributeValidator.TryGetQualifiedName(memberAccess.Object, out ownerName) {
            return false
        }

        ownerType := declarationContext.ResolveDeclaredAlias(ResolveDefaultEnumTypeName(ownerName))
        resolvedExpectedType := declarationContext.ResolveDeclaredAlias(ExpectedTypeFor(expectedType))
        if !TypeInfoIdentityFacts.AreEqual(ownerType, resolvedExpectedType) {
            return false
        }

        sourceEnum := ownerType as EnumTypeInfo
        if sourceEnum != null {
            return TypeInfoIdentityFacts.HasSourceEnumMember(sourceEnum, memberAccess.MemberName)
        }

        reflectionType := ownerType as ReflectionTypeInfo
        if reflectionType != null {
            runtimeEnum := reflectionType.Type
            if TypeInfoIdentityFacts.IsInt32BackedRuntimeEnum(runtimeEnum) {
                return TypeInfoIdentityFacts.HasRuntimeEnumMember(runtimeEnum, memberAccess.MemberName)
            }
        }

        return false
    }

    // A SIMPLE type reference goes through the same name resolution the owner side uses, so that
    // `Color.Red` on a parameter declared `Color` compares two identities resolved the same way.
    // Anything else is resolved as a declared type.
    func ExpectedTypeFor(expectedType: TypeReference): TypeInfo {
        simple := expectedType as SimpleTypeReference
        if simple != null {
            return ResolveDefaultEnumTypeName(simple.Name)
        }

        return typeResolver.ResolveDeclaredType(expectedType)
    }

    // RESOLVING THE NAME ON THE LEFT OF THE DOT, in four ways, in this order: an unqualified name goes
    // straight to the type resolver; a file-import alias claims the name whether or not it resolves
    // (a claimed-but-unresolved alias answers Unknown rather than falling through to something else
    // that happens to share the spelling); a namespace alias expands and is looked for in the project
    // first and the loaded assemblies second; and a fully-qualified name is looked for in the loaded
    // assemblies before being handed to the resolver.
    func ResolveDefaultEnumTypeName(name: string): TypeInfo {
        separator := name.IndexOf('.')
        if separator <= 0 || separator >= name.Length - 1 {
            return typeResolver.ResolveSimpleType(name, 0, 0)
        }

        root := name.Substring(0, separator)
        remainder := name.Substring(separator + 1)

        importedType: TypeInfo = BuiltInTypes.Unknown
        importedDeclaration: SymbolDeclaration? = null
        fileAliasClaimed := false
        if declarationContext.TryResolveFileImportAliasType(name, currentFilePath, importedSymbolsByAlias, importedDeclarationsByAlias, out importedType, out importedDeclaration, out fileAliasClaimed) {
            return declarationContext.ResolveDeclaredAlias(importedType)
        }

        if fileAliasClaimed {
            return BuiltInTypes.Unknown
        }

        namespaceName := ""
        if usingAliases.TryGetValue(root, out namespaceName) {
            return ResolveThroughNamespaceAlias(namespaceName, remainder)
        }

        runtimeType: Type = null
        if ExternalQualifiedTypeResolver.TryResolve(mlcAssemblies, name, out runtimeType) {
            return new ReflectionTypeInfo(runtimeType)
        }

        return typeResolver.ResolveSimpleType(name, 0, 0)
    }

    func ResolveThroughNamespaceAlias(namespaceName: string, remainder: string): TypeInfo {
        projectType: TypeInfo = BuiltInTypes.Unknown
        projectDeclaration: SymbolDeclaration? = null
        currentNamespace := AnalyzerProjectSourceProvider.UnitNamespace(compilationUnit)
        if projectDiscovery.TryResolveProjectTypeInNamespace(remainder, namespaceName, currentNamespace, out projectType, out projectDeclaration) {
            return projectType
        }

        expandedName := namespaceName + "." + remainder
        aliasedRuntimeType: Type = null
        if ExternalQualifiedTypeResolver.TryResolve(mlcAssemblies, expandedName, out aliasedRuntimeType) {
            return new ReflectionTypeInfo(aliasedRuntimeType)
        }

        return typeResolver.ResolveSimpleType(expandedName, 0, 0)
    }

    // The nullable wrapper is transparent to the SoA question: a `Points?` parameter is still a table.
    func GetNonNullableType(candidate: TypeInfo): TypeInfo {
        resolved := declarationContext.ResolveDeclaredAlias(candidate)
        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
    }
}
