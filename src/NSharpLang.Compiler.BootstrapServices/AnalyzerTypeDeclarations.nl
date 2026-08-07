namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE STEPS A TYPE DECLARATION CANNOT TAKE FOR ITSELF, AND EVERYTHING EACH STEP NEEDS.
//
// EIGHT FORMS, ONE WALK, because they are one family and not eight slices: every one of them is
// reached through the SAME arm of the declaration dispatch, every one of them decides the same first
// question (what this declaration's NAME says about its visibility), and six of them share the scope
// band, the declare/record pair and the member walk outright. Splitting them would have cost three
// request types, three state types and three driver loops to express one vocabulary three times.
//
// The kinds:
//   1  analyse an EXPRESSION. ANSWERS a type. Three sites ask: an enum member's initializer, a field
//      declaration's initializer when the field has NO written type (the inference arm), and the same
//      initializer when it DOES (the checked arm). The third differs from the second only in that the
//      TARGET-TYPING SLOT is open around it — and this walk opens that slot ITSELF, because it holds
//      the ambient context, so the driver's step is the same plain expression walk in all three cases.
//   2  open a SCOPE of the carried KIND at `Line` / `Column`. The kind is an operand rather than five
//      kinds because the operation is one operation: a class opens a CLASS scope, a struct a STRUCT
//      scope, a record a RECORD scope, an interface an INTERFACE scope and a union a BLOCK scope, and
//      nothing else about the step changes with it.
//   3  declare a NAME into the analyzer's scope stack under `CarriedType` at `Line` / `Column`, with
//      `RecordsBinding` deciding whether a binding declaration is recorded. Four sites ask: the
//      implicit `this` (with `RecordsBinding` FALSE, because `this` has no position to go to), each
//      primary-constructor parameter, each member FUNCTION in the class's forward-reference pass, and
//      a field's own name.
//   4  record a name in the semantic model the IDE reads, as a VARIABLE. Only the primary-constructor
//      parameters ask.
//   5  close the scope kind 2 opened.
//   6  run the PARAMETER-LIST rules over `Parameters`. This is the RELAY the function and accessor
//      walks already record as theirs: the `params` half is N#-owned, but the default-value half
//      re-enters the analyzer's target-typed expression walk whenever an SoA record types a defaulted
//      parameter. The three primary constructors are three of that composite's callers.
//   7  analyse one MEMBER DECLARATION, which RE-ENTERS the declaration dispatch this walk is itself
//      reached through. It is the arc's first re-entrant step and it is safe for a measured reason:
//      the operation ANSWERS NOTHING (the dispatch returns void, so no phase here folds anything in),
//      and every datum the walk holds lives on the STATE, which is created per `Begin`. A class
//      nested in a class is therefore two states and two driver frames, never one walk observing
//      another's phase.
//   8  record a TYPE MEMBER in the semantic model under `ContainingType`, which is what member
//      completion inside the type reads. Only a field asks, and only when there IS a containing type.
//   9  record a FIELD in the semantic model's top-level table, which is what a bare identifier naming
//      the field resolves through. Only a field asks, and it asks unconditionally.
//
// The numbering is this walk's own protocol with its own driver and starts at 1 with no gaps. The
// other walks' numbers mean different operations; none of them is a shared vocabulary.
class TypeDeclarationRequest {
    Kind: int
    Node: Expression?
    Member: Declaration?
    Parameters: List<Parameter>?
    Name: string?
    ContainingType: string?
    CarriedType: TypeInfo
    CarriedScopeKind: ScopeKind
    RecordsBinding: bool
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Member = null
        Parameters = null
        Name = null
        ContainingType = null
        CarriedType = carriedType
        CarriedScopeKind = ScopeKind.Block
        RecordsBinding = true
        Line = 0
        Column = 0
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` names which declaration is being walked: 0 CLASS, 1 STRUCT, 2 RECORD, 3 INTERFACE, 4 UNION,
// 5 ENUM, 6 SOA RECORD, 7 FIELD. The first four share one phase band because they are the same walk
// with pieces removed; the last four have bands of their own because they share no scope and no
// members.
//
// `Phase` is the walk's program counter, in five bands:
//   0..8   THE TYPE BAND (forms 0..3). 0 enters the ambient context, checks the convention, looks the
//          declared type up and opens the scope; 1 declares the type parameters, applies the
//          generic-static rule, resolves the bases and the nested types and declares `this`; 2
//          validates the primary-constructor list; 3 and 4 are the per-parameter declare/record pair;
//          5 is the CLASS's forward-reference pass over its member functions; 6 walks the members; 7
//          closes the scope; 8 leaves the ambient context.
//   10..11 THE UNION BAND. 10 checks the convention and opens a BLOCK scope; 11 declares the type
//          parameters, applies the case rules and closes the scope.
//   20..22 THE ENUM BAND. 20 checks the convention; 21 selects the next member, applies the
//          duplicate rule and asks for an initializer's type when there is one; 22 applies the
//          backing-type rule to the answer.
//   30     THE SOA BAND, which asks for NOTHING: every rule a `soa record` has is a pure function of
//          its columns and the ambient type name, so the whole walk is one phase and no step.
//   40..45 THE FIELD BAND. 40 checks the convention and takes one of the three initializer shapes;
//          41 applies the inference arm's rules; 42 closes the target type and applies the checked
//          arm's rules; 43 declares the name; 44 records the type member; 45 records the field.
//   99     done.
//
// `SavedClass` and `SavedTypeName` are the ambient context's hand-backs, held HERE because the
// boundary opens in phase 0 and closes in phase 8 with the whole member walk in between. They are two
// slots rather than one frame because the four type forms do not move them together: only a CLASS
// moves the declaration, while all four move the name.
//
// `SavedExpectedType` is the target-typing slot's hand-back for the field band's checked arm, held
// for exactly one step.
//
// THE ASSIGNABILITY ORACLE IS PASSED AT `Begin` RATHER THAN HELD, for the reason this estate records
// at every walk: `Analyzer.cs` REBUILDS it when the metadata load context opens and again when it is
// disposed, so an owner constructed once may not keep a reference to it.
class TypeDeclarationState {
    formValue: int
    declarationValue: Declaration
    assignabilityValue: AnalyzerAssignability

    Form: int => formValue
    Declaration: Declaration => declarationValue
    Assignability: AnalyzerAssignability => assignabilityValue

    Phase: int
    Pending: int
    MemberIndex: int
    ParameterIndex: int
    AnswerType: TypeInfo
    DeclaredType: TypeInfo?
    OwnerType: TypeInfo
    ParameterType: TypeInfo
    FieldType: TypeInfo
    SavedClass: ClassDeclaration?
    SavedTypeName: string?
    SavedExpectedType: TypeInfo?
    SeenNames: HashSet<string>

    constructor(form: int, declaration: Declaration, assignability: AnalyzerAssignability) {
        formValue = form
        declarationValue = declaration
        assignabilityValue = assignability
        Phase = 0
        Pending = 0
        MemberIndex = 0
        ParameterIndex = 0
        AnswerType = BuiltInTypes.Unknown
        DeclaredType = null
        OwnerType = BuiltInTypes.Unknown
        ParameterType = BuiltInTypes.Unknown
        FieldType = BuiltInTypes.Unknown
        SavedClass = null
        SavedTypeName = null
        SavedExpectedType = null
        SeenNames = new HashSet<string>(StringComparer.Ordinal)
    }
}

// WHAT A TYPE DECLARATION MEANS.
//
// The walk owns the whole of what a `class`, `struct`, `record`, `interface`, `union`, `enum`,
// `soa record` and field declaration DECIDE:
//
// * that the ambient type context is entered BEFORE anything is reported, and that a CLASS enters
//   both slots while a struct, record and interface enter only the name — so a struct nested in a
//   class is still analysed with that class current;
// * that the naming convention is checked FIRST, before the declared type is looked up, so an
//   unresolvable name cannot reorder the convention report;
// * which SCOPE KIND each form opens, and that a union opens a BLOCK while an enum and a `soa record`
//   open nothing at all;
// * that type parameters are declared into that scope before any base type is resolved;
// * that a generic type may not carry a static field, property or method, and that the report names
//   the type with its parameters;
// * that a class resolves its base class and then its interfaces, a struct and a record their
//   interfaces, and an interface its base interfaces;
// * that the nested types of the declared type — or of a freshly built nominal type when the
//   declaration is not in the scope stack — are declared before `this` is;
// * that `this` is declared WITHOUT a binding declaration, and that an interface never declares it;
// * that a primary constructor's list is validated ONCE and then declared and recorded parameter by
//   parameter, each at its own position or at the declaration's when it has none;
// * that a CLASS — and ONLY a class — pre-declares every member FUNCTION before walking any member,
//   which is what makes a forward reference between two methods resolve;
// * that every member is then walked through the declaration dispatch, in source order;
// * that a union's cases must be uniquely named and that every case property's type is resolved;
// * that an enum's members must be uniquely named and that an `int` enum takes numeric initializers
//   while a `string` enum takes string ones;
// * that a `soa record` is refused outside the experimental gate, refused when nested, and held to
//   its supported column types and its reserved member names;
// * and what a FIELD is: a type that is either written or inferred, an initializer that is checked
//   against it and refused both SoA escapes, a name declared into the enclosing scope, and two
//   semantic-model records — one under the containing type when there is one, and one in the
//   top-level field table always.
//
// What it cannot do is run the analyzer's own EXPRESSION walk, open or close a scope, declare a name
// into the scope stack, write the semantic model, re-enter the declaration dispatch, or run the
// parameter-list rules whose default-value half re-enters the expression walk — so it ASKS: one
// request at a time, each naming a kind and carrying every value the step needs.
//
// IT HOLDS THE SCOPE STACK, unlike the accessor walk and like the function walk, because three of its
// operations READ that stack rather than write it: the declared type is looked UP in it, type
// parameters are declared into it directly, and nested types are declared into it directly. None of
// those needs the semantic model, which is the one thing that makes an operation a step.
class AnalyzerTypeDeclarations {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeResolverValue: AnalyzerTypeResolver
    functionTypeFactoryValue: AnalyzerFunctionTypeFactory
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeResolver: AnalyzerTypeResolver, functionTypeFactory: AnalyzerFunctionTypeFactory, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        functionTypeFactoryValue = functionTypeFactory
        ambientValue = ambient
        soaEscapeValue = soaEscape
    }

    // THE EIGHT ENTRIES. Each one records only which form is running; every value the walk needs is
    // read off the declaration as the phase that needs it runs, which is what lets one state shape
    // serve eight declarations.
    func BeginClass(declaration: ClassDeclaration, assignability: AnalyzerAssignability): TypeDeclarationState {
        return new TypeDeclarationState(0, declaration, assignability)
    }

    func BeginStruct(declaration: StructDeclaration, assignability: AnalyzerAssignability): TypeDeclarationState {
        return new TypeDeclarationState(1, declaration, assignability)
    }

    func BeginRecord(declaration: RecordDeclaration, assignability: AnalyzerAssignability): TypeDeclarationState {
        return new TypeDeclarationState(2, declaration, assignability)
    }

    func BeginInterface(declaration: InterfaceDeclaration, assignability: AnalyzerAssignability): TypeDeclarationState {
        return new TypeDeclarationState(3, declaration, assignability)
    }

    func BeginUnion(declaration: UnionDeclaration, assignability: AnalyzerAssignability): TypeDeclarationState {
        state := new TypeDeclarationState(4, declaration, assignability)
        state.Phase = 10
        return state
    }

    func BeginEnum(declaration: EnumDeclaration, assignability: AnalyzerAssignability): TypeDeclarationState {
        state := new TypeDeclarationState(5, declaration, assignability)
        state.Phase = 20
        return state
    }

    func BeginSoaRecord(declaration: SoaRecordDeclaration, assignability: AnalyzerAssignability): TypeDeclarationState {
        state := new TypeDeclarationState(6, declaration, assignability)
        state.Phase = 30
        return state
    }

    func BeginField(declaration: FieldDeclaration, assignability: AnalyzerAssignability): TypeDeclarationState {
        state := new TypeDeclarationState(7, declaration, assignability)
        state.Phase = 40
        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    func NextStep(state: TypeDeclarationState): TypeDeclarationRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything, and only three phases ask for
    // it; every other step performs an operation whose result the walk does not read.
    func Supply(state: TypeDeclarationState, answer: TypeInfo?) {
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

    func Advance(state: TypeDeclarationState): TypeDeclarationRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceTypeEntry(state)
        }

        if phase == 1 {
            return AdvanceTypeHeader(state)
        }

        if phase == 2 {
            return AdvancePrimaryConstructorList(state)
        }

        if phase == 3 {
            return AdvanceDeclareParameter(state)
        }

        if phase == 4 {
            return AdvanceRecordParameter(state)
        }

        if phase == 5 {
            return AdvanceForwardReferencePass(state)
        }

        if phase == 6 {
            return AdvanceMemberPass(state)
        }

        if phase == 7 {
            return AdvanceCloseTypeScope(state)
        }

        if phase == 8 {
            return AdvanceLeaveTypeContext(state)
        }

        if phase == 10 {
            return AdvanceUnionEntry(state)
        }

        if phase == 11 {
            return AdvanceUnionCases(state)
        }

        if phase == 20 {
            return AdvanceEnumEntry(state)
        }

        if phase == 21 {
            return AdvanceEnumMember(state)
        }

        if phase == 22 {
            return AdvanceEnumMemberValue(state)
        }

        if phase == 30 {
            return AdvanceSoaRecord(state)
        }

        if phase == 40 {
            return AdvanceFieldEntry(state)
        }

        if phase == 41 {
            return AdvanceInferredFieldRules(state)
        }

        if phase == 42 {
            return AdvanceCheckedFieldRules(state)
        }

        if phase == 43 {
            return AdvanceDeclareField(state)
        }

        if phase == 44 {
            return AdvanceRecordFieldMember(state)
        }

        if phase == 45 {
            return AdvanceRecordField(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — THE AMBIENT CONTEXT, THE CONVENTION, THE DECLARED TYPE AND THE SCOPE, IN THAT ORDER.
    // The ambient context moves FIRST, before a single report, because every report made from here
    // down is made from inside this type. A CLASS moves both slots and everything else moves only the
    // name — the difference a struct nested in a class depends on. The declared type is looked up
    // BEFORE the scope opens, so the lookup sees the ENCLOSING scope, which is where a type
    // declaration's own name lives.
    func AdvanceTypeEntry(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 1
        name := TypeName(state)
        if state.Form == 0 {
            classDeclaration := state.Declaration as ClassDeclaration
            state.SavedClass = ambientValue.EnterClassDeclaration(classDeclaration)
        }

        state.SavedTypeName = ambientValue.EnterTypeName(name)
        AnalyzerDeclarationConventions.CheckVisibilityConvention(diagnosticsValue, name, TypeModifiers(state), state.Declaration.Line, state.Declaration.Column)
        state.DeclaredType = scopesValue.LookupType(name)
        request := new TypeDeclarationRequest(2, BuiltInTypes.Unknown)
        request.CarriedScopeKind = TypeScopeKind(state)
        request.Line = state.Declaration.Line
        request.Column = state.Declaration.Column
        return request
    }

    // PHASE 1 — EVERYTHING THAT HAPPENS INSIDE THE OPEN SCOPE BEFORE THE MEMBERS DO. The type
    // parameters go in first, so a base type written in terms of one resolves; the generic-static rule
    // runs next, because it is about the declaration rather than about anything resolved; the bases
    // are resolved in the order each form writes them; the nested types are declared from the DECLARED
    // type when the scope stack knows it and from a freshly built nominal type when it does not; and
    // `this` is declared last, which an INTERFACE never does — it has no instance to name.
    func AdvanceTypeHeader(state: TypeDeclarationState): TypeDeclarationRequest? {
        DeclareTypeParameters(state)
        ValidateNoStaticMembersOnGenericType(state)
        ResolveDeclaredBases(state)
        state.OwnerType = OwnerTypeFor(state)
        DeclareNestedTypesInCurrentScope(state.OwnerType)
        if state.Form == 3 {
            state.Phase = 6
            return null
        }

        state.Phase = 2
        request := new TypeDeclarationRequest(3, state.OwnerType)
        request.Name = "this"
        request.RecordsBinding = false
        request.Line = state.Declaration.Line
        request.Column = state.Declaration.Column
        return request
    }

    // PHASE 2 — THE PRIMARY-CONSTRUCTOR LIST, VALIDATED ONCE AND BEFORE ANY NAME IN IT EXISTS. A
    // declaration without a primary constructor skips straight to the members.
    func AdvancePrimaryConstructorList(state: TypeDeclarationState): TypeDeclarationRequest? {
        parameters := PrimaryConstructorParameters(state)
        if parameters == null {
            state.Phase = 5
            return null
        }

        state.Phase = 3
        state.ParameterIndex = 0
        request := new TypeDeclarationRequest(6, BuiltInTypes.Unknown)
        request.Parameters = parameters
        request.Line = state.Declaration.Line
        request.Column = state.Declaration.Column
        return request
    }

    // PHASE 3 — ONE PRIMARY-CONSTRUCTOR PARAMETER'S DECLARATION. A parameter with a position of its
    // own is declared there; one without falls back to the DECLARATION's position, which is what keeps
    // a synthesised parameter's squiggle on the type rather than at line zero.
    func AdvanceDeclareParameter(state: TypeDeclarationState): TypeDeclarationRequest? {
        parameters := PrimaryConstructorParameters(state)
        if parameters == null || state.ParameterIndex >= parameters.Count {
            state.Phase = 5
            return null
        }

        parameter := parameters[state.ParameterIndex]
        parameterType := typeResolverValue.ResolveDeclaredType(parameter.Type)
        state.ParameterType = parameterType
        position := AnalyzerBindingFacts.GetParameterDeclarationPosition(parameter.Line, parameter.Column, state.Declaration.Line, state.Declaration.Column)
        state.Phase = 4
        request := new TypeDeclarationRequest(3, parameterType)
        request.Name = parameter.Name
        request.Line = position.Item1
        request.Column = position.Item2
        return request
    }

    // PHASE 4 — THE SAME PARAMETER'S IDE RECORD, which is a different table through a different
    // member from the declaration and is therefore its own step. The pair then repeats.
    func AdvanceRecordParameter(state: TypeDeclarationState): TypeDeclarationRequest? {
        parameters := PrimaryConstructorParameters(state)
        if parameters == null || state.ParameterIndex >= parameters.Count {
            state.Phase = 5
            return null
        }

        parameter := parameters[state.ParameterIndex]
        state.ParameterIndex = state.ParameterIndex + 1
        state.Phase = 3
        request := new TypeDeclarationRequest(4, state.ParameterType)
        request.Name = parameter.Name
        return request
    }

    // PHASE 5 — THE FORWARD-REFERENCE PASS, AND IT IS A CLASS'S ALONE. Only `AnalyzeClassDeclaration`
    // pre-declared its member functions; the struct, record and interface walks went straight to their
    // members, so a method written above another in a STRUCT resolves through a different route
    // entirely. That asymmetry is shipped behaviour and is preserved rather than levelled.
    func AdvanceForwardReferencePass(state: TypeDeclarationState): TypeDeclarationRequest? {
        if state.Form != 0 {
            state.Phase = 6
            state.MemberIndex = 0
            return null
        }

        members := TypeMembers(state)
        if members == null {
            state.Phase = 6
            state.MemberIndex = 0
            return null
        }

        while state.MemberIndex < members.Count {
            member := members[state.MemberIndex]
            state.MemberIndex = state.MemberIndex + 1
            functionDeclaration := member as FunctionDeclaration
            if functionDeclaration != null {
                functionType := functionTypeFactoryValue.CreateFromDeclaration(functionDeclaration, TypeName(state))
                request := new TypeDeclarationRequest(3, functionType)
                request.Name = functionDeclaration.Name
                request.Line = functionDeclaration.Line
                request.Column = functionDeclaration.Column
                return request
            }
        }

        state.Phase = 6
        state.MemberIndex = 0
        return null
    }

    // PHASE 6 — THE MEMBERS, IN SOURCE ORDER, THROUGH THE DECLARATION DISPATCH. This is the re-entrant
    // step: a nested type declaration reaches this same walk again with a state of its own, and
    // nothing here reads an answer, because the dispatch produces none.
    func AdvanceMemberPass(state: TypeDeclarationState): TypeDeclarationRequest? {
        members := TypeMembers(state)
        if members == null || state.MemberIndex >= members.Count {
            state.Phase = 7
            return null
        }

        member := members[state.MemberIndex]
        state.MemberIndex = state.MemberIndex + 1
        request := new TypeDeclarationRequest(7, BuiltInTypes.Unknown)
        request.Member = member
        request.Line = member.Line
        request.Column = member.Column
        return request
    }

    // PHASE 7 — THE SCOPE CLOSES, and it closes BEFORE the ambient context is left, which is the order
    // every one of the four C# walks wrote.
    func AdvanceCloseTypeScope(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 8
        request := new TypeDeclarationRequest(5, BuiltInTypes.Unknown)
        request.Line = state.Declaration.Line
        request.Column = state.Declaration.Column
        return request
    }

    // PHASE 8 — THE AMBIENT CONTEXT IS LEFT, class slot first and name second, which is the order the
    // class walk restored its two locals in. A throw anywhere inside the walk never reaches here, and
    // that is the C# behaviour preserved exactly: not one of these four restores sat in a `finally`.
    func AdvanceLeaveTypeContext(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 99
        if state.Form == 0 {
            ambientValue.ExitClassDeclaration(state.SavedClass)
        }

        ambientValue.ExitTypeName(state.SavedTypeName)
        return null
    }

    // PHASE 10 — A UNION'S ENTRY. It checks the same convention and opens a BLOCK scope rather than a
    // scope named for the declaration, and it does NOT enter the ambient type context at all: a
    // union's cases are not members of a containing type in the sense the rest of the analyzer means.
    func AdvanceUnionEntry(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 11
        AnalyzerDeclarationConventions.CheckVisibilityConvention(diagnosticsValue, TypeName(state), TypeModifiers(state), state.Declaration.Line, state.Declaration.Column)
        request := new TypeDeclarationRequest(2, BuiltInTypes.Unknown)
        request.CarriedScopeKind = ScopeKind.Block
        request.Line = state.Declaration.Line
        request.Column = state.Declaration.Column
        return request
    }

    // PHASE 11 — THE TYPE PARAMETERS, THE CASE RULES AND THE CLOSE. Every case must be uniquely named
    // and every case property's type is resolved whether the case is a duplicate or not, so a
    // misspelled type inside a duplicated case is still reported.
    func AdvanceUnionCases(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 99
        DeclareTypeParameters(state)
        unionDeclaration := state.Declaration as UnionDeclaration
        if unionDeclaration != null {
            for unionCase in unionDeclaration.Cases {
                ReportDuplicateUnionCaseIfNeeded(state, unionDeclaration, unionCase)
                properties := unionCase.Properties
                if properties != null {
                    for caseProperty in properties {
                        typeResolverValue.ResolveDeclaredType(caseProperty.Type)
                    }
                }
            }
        }

        request := new TypeDeclarationRequest(5, BuiltInTypes.Unknown)
        request.Line = state.Declaration.Line
        request.Column = state.Declaration.Column
        return request
    }

    // A DUPLICATED UNION CASE, IN BOTH ITS SHAPES. The rich builder needs a readable source line and a
    // file; without either, the detail-only shape carries the same code and a wording of its own. A
    // case with no position of its own is reported at the UNION's.
    func ReportDuplicateUnionCaseIfNeeded(state: TypeDeclarationState, unionDeclaration: UnionDeclaration, unionCase: UnionCase) {
        if state.SeenNames.Add(unionCase.Name) {
            return
        }

        caseLine := unionDeclaration.Line
        if unionCase.Line > 0 {
            caseLine = unionCase.Line
        }

        caseColumn := unionDeclaration.Column
        if unionCase.Column > 0 {
            caseColumn = unionCase.Column
        }

        sourceSnippet := diagnosticsValue.SourceSnippet(caseLine)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.DuplicateDeclaration(currentFilePath, caseLine, caseColumn, sourceSnippet, unionCase.Name.Length, unionCase.Name, "union case"))
            return
        }

        diagnosticsValue.Report(ErrorCode.DuplicateDeclaration, "Union case '" + unionCase.Name + "' is already defined — each case in a union must have a unique name", caseLine, caseColumn, null, Math.Max(1, unionCase.Name.Length))
    }

    // PHASE 20 — AN ENUM'S ENTRY, WHICH IS THE CONVENTION AND NOTHING ELSE. An enum opens no scope: its
    // members are not names in the enclosing scope, and its initializers are analysed where the
    // declaration sits.
    func AdvanceEnumEntry(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 21
        AnalyzerDeclarationConventions.CheckVisibilityConvention(diagnosticsValue, TypeName(state), TypeModifiers(state), state.Declaration.Line, state.Declaration.Column)
        return null
    }

    // PHASE 21 — THE NEXT ENUM MEMBER: ITS DUPLICATE RULE FIRST, THEN ITS INITIALIZER IF IT HAS ONE.
    // The duplicate rule runs for EVERY member including one whose value is then analysed, and a member
    // with no initializer produces no step at all.
    func AdvanceEnumMember(state: TypeDeclarationState): TypeDeclarationRequest? {
        enumDeclaration := state.Declaration as EnumDeclaration
        if enumDeclaration == null {
            state.Phase = 99
            return null
        }

        while state.MemberIndex < enumDeclaration.Members.Count {
            member := enumDeclaration.Members[state.MemberIndex]
            ReportDuplicateEnumMemberIfNeeded(state, enumDeclaration, member)
            value := member.Value
            if value != null {
                state.Phase = 22
                state.Pending = 1
                request := new TypeDeclarationRequest(1, BuiltInTypes.Unknown)
                request.Node = value
                request.Line = member.Line
                request.Column = member.Column
                return request
            }

            state.MemberIndex = state.MemberIndex + 1
        }

        state.Phase = 99
        return null
    }

    // PHASE 22 — THE BACKING-TYPE RULE OVER THE ANSWER. An `int` enum takes any numeric value and a
    // `string` enum takes a string one; both reports point at the EXPRESSION rather than at the member,
    // and both name the other backing type as the alternative fix.
    func AdvanceEnumMemberValue(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 21
        enumDeclaration := state.Declaration as EnumDeclaration
        if enumDeclaration == null {
            state.Phase = 99
            return null
        }

        member := enumDeclaration.Members[state.MemberIndex]
        state.MemberIndex = state.MemberIndex + 1
        value := member.Value
        if value == null {
            return null
        }

        valueType := state.AnswerType
        if enumDeclaration.Type == EnumType.Int && !IsNumericValueType(valueType) {
            span := spansValue.GetExpressionDiagnosticSpan(value)
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "Enum member '" + member.Name + "' must have a numeric value — this enum uses int values", span.Line, span.Column, "Use a numeric value for '" + member.Name + "', or change the enum backing type to 'string'", span.Length)
            return null
        }

        if enumDeclaration.Type == EnumType.String && !BuiltInTypes.Is(valueType, BuiltInTypes.String) {
            span := spansValue.GetExpressionDiagnosticSpan(value)
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "Enum member '" + member.Name + "' must have a string value — this enum uses string values", span.Line, span.Column, "Use a string value for '" + member.Name + "', or change the enum backing type to 'int'", span.Length)
        }

        return null
    }

    // A DUPLICATED ENUM MEMBER, IN BOTH ITS SHAPES — the same pair of shapes the union case uses, with
    // its own noun and its own wording.
    func ReportDuplicateEnumMemberIfNeeded(state: TypeDeclarationState, enumDeclaration: EnumDeclaration, member: EnumMember) {
        if state.SeenNames.Add(member.Name) {
            return
        }

        memberLine := enumDeclaration.Line
        if member.Line > 0 {
            memberLine = member.Line
        }

        memberColumn := enumDeclaration.Column
        if member.Column > 0 {
            memberColumn = member.Column
        }

        sourceSnippet := diagnosticsValue.SourceSnippet(memberLine)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.DuplicateDeclaration(currentFilePath, memberLine, memberColumn, sourceSnippet, member.Name.Length, member.Name, "enum member"))
            return
        }

        diagnosticsValue.Report(ErrorCode.DuplicateDeclaration, "Enum member '" + member.Name + "' is already defined — each member in an enum must have a unique name", memberLine, memberColumn, null, Math.Max(1, member.Name.Length))
    }

    // PHASE 30 — A `soa record`, WHOLE, IN ONE PHASE AND NO STEPS. Two gates come first and both
    // RETURN: the experimental feature gate, and the nesting gate, which reads the ambient type name
    // this walk's own type forms set. Only past both are the columns resolved, and every column's type
    // is resolved BEFORE any of them is judged, so a later column's unresolvable type is reported in
    // resolution order rather than interleaved with the support rule.
    func AdvanceSoaRecord(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 99
        soaRecord := state.Declaration as SoaRecordDeclaration
        if soaRecord == null {
            return null
        }

        if !SoaFeature.IsEnabled {
            diagnosticsValue.Report(ErrorCode.FeatureNotImplemented, "soa record '" + soaRecord.Name + "' is parsed but not available in production builds yet", soaRecord.Line, soaRecord.Column, "Set NSHARP_EXPERIMENTAL_SOA=1 only for the compiler table migration gate; otherwise keep using regular records", 3)
            return null
        }

        if ambientValue.CurrentTypeName != null {
            diagnosticsValue.Report(ErrorCode.FeatureNotImplemented, "nested soa record '" + soaRecord.Name + "' is not part of the experimental lowering slice yet", soaRecord.Line, soaRecord.Column, "Move the soa record to top level while the wrapper ABI is being proven", 3)
            return null
        }

        columnTypes := new List<TypeInfo>()
        for column in soaRecord.Columns {
            columnTypes.Add(typeResolverValue.ResolveDeclaredType(column.Type))
        }

        ValidateSoaColumnNames(state, soaRecord)

        index := 0
        while index < soaRecord.Columns.Count {
            column := soaRecord.Columns[index]
            resolvedColumnType := declarationContextValue.ResolveDeclaredAlias(columnTypes[index])
            index = index + 1
            if IsSupportedSoaColumnType(resolvedColumnType) {
                continue
            }

            span := AnalyzerDiagnosticSpanFacts.GetSoaColumnTypeDiagnosticSpan(column)
            diagnosticsValue.Report(ErrorCode.FeatureNotImplemented, "SoA column type '" + TypeText(resolvedColumnType) + "' is not supported in this lowering", span.Line, span.Column, "Use int, uint, long, bool, char, string, string?, or int-backed enum columns until this table migration verifies another element shape", span.Length)
        }

        return null
    }

    // EVERY COLUMN NAME IS TWO RULES, IN THIS ORDER: it must be unique among the columns, and it must
    // not collide with a member the generated table already has. A name that breaks both is reported
    // TWICE, which is what the C# did.
    func ValidateSoaColumnNames(state: TypeDeclarationState, soaRecord: SoaRecordDeclaration) {
        for column in soaRecord.Columns {
            span := AnalyzerDiagnosticSpanFacts.GetSoaColumnNameDiagnosticSpan(column, soaRecord)
            if !state.SeenNames.Add(column.Name) {
                diagnosticsValue.Report(ErrorCode.DuplicateDeclaration, "SoA column '" + column.Name + "' is already defined — each column in a soa record must have a unique name", span.Line, span.Column, "Rename one of the columns so every table member has one storage slot.", span.Length)
            }

            if IsReservedSoaTableMemberName(column.Name) {
                diagnosticsValue.Report(ErrorCode.DuplicateDeclaration, "SoA column '" + column.Name + "' conflicts with a generated table member", span.Line, span.Column, "Rename the column; SoA tables reserve length, capacity, add, clear, ensureCapacity, copyRow, and wrap.", span.Length)
            }
        }
    }

    static func IsReservedSoaTableMemberName(name: string): bool {
        return name == "length" || name == "capacity" || name == "add" || name == "clear" || name == "ensureCapacity" || name == "copyRow" || name == "wrap"
    }

    // WHICH COLUMN TYPES THE TABLE LOWERING CAN ACTUALLY BUILD. An UNKNOWN type is accepted, because
    // whatever made it unknown has already been reported and a second report about the same column
    // would be noise; a nullable is accepted only for `string`; an enum is accepted only when it is
    // int-backed, whether it is declared here or reflected from metadata.
    func IsSupportedSoaColumnType(candidate: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        if BuiltInTypes.IsUnknown(resolved) {
            return true
        }

        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return BuiltInTypes.Is(declarationContextValue.ResolveDeclaredAlias(nullable.InnerType), BuiltInTypes.String)
        }

        enumType := resolved as EnumTypeInfo
        if enumType != null {
            return enumType.Declaration.Type == EnumType.Int
        }

        reflectionType := resolved as ReflectionTypeInfo
        if reflectionType != null && TypeInfoIdentityFacts.IsInt32BackedRuntimeEnum(reflectionType.Type) {
            return true
        }

        return BuiltInTypes.Is(resolved, BuiltInTypes.Int) || BuiltInTypes.Is(resolved, BuiltInTypes.UInt) || BuiltInTypes.Is(resolved, BuiltInTypes.Long) || BuiltInTypes.Is(resolved, BuiltInTypes.Bool) || BuiltInTypes.Is(resolved, BuiltInTypes.Char) || BuiltInTypes.Is(resolved, BuiltInTypes.String)
    }

    // PHASE 40 — A FIELD'S ENTRY, AND THE THREE SHAPES ITS TYPE CAN TAKE. A field with NEITHER a type
    // nor an initializer cannot be typed at all and is told so; one with only an initializer is walked
    // UNTARGETED, because there is nothing to target it with; one with a written type resolves it
    // first and walks the initializer with the target-typing slot HELD OPEN, which is what makes a
    // collection literal, a `default` or an untyped `new()` take the field's type.
    func AdvanceFieldEntry(state: TypeDeclarationState): TypeDeclarationRequest? {
        field := state.Declaration as FieldDeclaration
        if field == null {
            state.Phase = 99
            return null
        }

        AnalyzerDeclarationConventions.CheckVisibilityConvention(diagnosticsValue, field.Name, field.Modifiers, field.Line, field.Column)
        initializer := field.Initializer
        if field.Type == null {
            if initializer == null {
                state.Phase = 43
                state.FieldType = BuiltInTypes.Unknown
                diagnosticsValue.Report(ErrorCode.InvalidSyntax, "I can't determine the type of '" + field.Name + "' — give it a type annotation or an initial value so I know what it is", field.Line, field.Column, null, 0)
                return null
            }

            state.Phase = 41
            state.Pending = 1
            request := new TypeDeclarationRequest(1, BuiltInTypes.Unknown)
            request.Node = initializer
            request.Line = field.Line
            request.Column = field.Column
            return request
        }

        state.FieldType = typeResolverValue.ResolveDeclaredType(field.Type)
        if initializer == null {
            state.Phase = 43
            return null
        }

        state.SavedExpectedType = ambientValue.EnterExpectedType(state.FieldType)
        state.Phase = 42
        state.Pending = 1
        request := new TypeDeclarationRequest(1, BuiltInTypes.Unknown)
        request.Node = initializer
        request.Line = field.Line
        request.Column = field.Column
        return request
    }

    // PHASE 41 — THE INFERENCE ARM'S RULES, AND THEY ARE A CHAIN RATHER THAN A LIST. A row view is
    // refused first; only if it was NOT one is a direct column read refused; and only if it was neither
    // is an unknown inferred type reported. Each refusal replaces the inferred type with UNKNOWN, so
    // the field still gets declared and one report is made rather than two.
    func AdvanceInferredFieldRules(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 43
        field := state.Declaration as FieldDeclaration
        if field == null {
            return null
        }

        initializer := field.Initializer
        if initializer == null {
            return null
        }

        fieldType := state.AnswerType
        state.FieldType = fieldType
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(initializer, fieldType, "stored in a field") {
            state.FieldType = BuiltInTypes.Unknown
            return null
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(initializer, "stored in a field") {
            state.FieldType = BuiltInTypes.Unknown
            return null
        }

        if BuiltInTypes.IsUnknown(fieldType) {
            diagnosticsValue.Report(ErrorCode.InvalidSyntax, "I can't figure out the type of '" + field.Name + "' from its initializer — try adding an explicit type annotation", field.Line, field.Column, null, 0)
        }

        return null
    }

    // PHASE 42 — THE CHECKED ARM. The target type closes FIRST and unconditionally, before a single
    // rule runs, because the C# restored it the instant the expression walk returned. Then BOTH escape
    // reports run — both of them, unlike the inference arm's chain — and only a value that is neither
    // escape is measured against the field's declared type. The field keeps its DECLARED type either
    // way: a mismatched initializer does not retype the field.
    func AdvanceCheckedFieldRules(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 43
        ambientValue.ExitExpectedType(state.SavedExpectedType)
        state.SavedExpectedType = null
        field := state.Declaration as FieldDeclaration
        if field == null {
            return null
        }

        initializer := field.Initializer
        if initializer == null {
            return null
        }

        initializerType := state.AnswerType
        isSoaRowInitializer := soaEscapeValue.ReportSoaRowEscapeIfNeeded(initializer, initializerType, "stored in a field")
        isSoaDirectColumnInitializer := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(initializer, "stored in a field")
        if isSoaRowInitializer || isSoaDirectColumnInitializer {
            return null
        }

        if state.Assignability.IsAssignable(state.FieldType, initializerType) {
            return null
        }

        ReportFieldTypeMismatch(state, field, initializer, initializerType)
        return null
    }

    // THE FIELD'S INITIALIZER MISMATCH, IN BOTH ITS SHAPES, AND THE CODES ARE NOT THE SAME ONE. The
    // rich builder points at the INITIALIZER and reports a type mismatch; the detail-only fallback
    // points at the DECLARATION and carries INVALID SYNTAX, because the three-argument `Error` overload
    // it replaces defaulted to that code. The asymmetry is the shipped behaviour — the detail-only
    // shape is exactly what an unsaved editor buffer produces — and is preserved rather than tidied.
    func ReportFieldTypeMismatch(state: TypeDeclarationState, field: FieldDeclaration, initializer: Expression, initializerType: TypeInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(initializer)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.TypeMismatch(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, TypeText(initializerType), TypeText(state.FieldType)))
            return
        }

        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Field '" + field.Name + "' is typed as '" + TypeText(state.FieldType) + "', but the initializer gives '" + TypeText(initializerType) + "'", field.Line, field.Column, null, 0)
    }

    // PHASE 43 — THE FIELD'S NAME, DECLARED INTO WHATEVER SCOPE ENCLOSES IT: the type's own scope for
    // a member, the file's for a top-level field. It is declared AFTER every rule above, so a field
    // whose initializer was refused is still a name the rest of the file can resolve.
    func AdvanceDeclareField(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 44
        field := state.Declaration as FieldDeclaration
        if field == null {
            return null
        }

        request := new TypeDeclarationRequest(3, state.FieldType)
        request.Name = field.Name
        request.Line = field.Line
        request.Column = field.Column
        return request
    }

    // PHASE 44 — THE COMPLETION RECORD FOR THE CONTAINING TYPE, WHEN THERE IS ONE. A field declared
    // outside every type has no member table to join, and asking for the step anyway would have made
    // the driver decide something.
    func AdvanceRecordFieldMember(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 45
        field := state.Declaration as FieldDeclaration
        if field == null {
            return null
        }

        containingType := ambientValue.CurrentTypeName
        if containingType == null {
            return null
        }

        request := new TypeDeclarationRequest(8, state.FieldType)
        request.Name = field.Name
        request.ContainingType = containingType
        return request
    }

    // PHASE 45 — THE TOP-LEVEL FIELD RECORD, which is unconditional and is what makes a bare identifier
    // naming the field resolve through the semantic model.
    func AdvanceRecordField(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 99
        field := state.Declaration as FieldDeclaration
        if field == null {
            return null
        }

        request := new TypeDeclarationRequest(9, state.FieldType)
        request.Name = field.Name
        return request
    }

    // A GENERIC TYPE MAY NOT CARRY A STATIC MEMBER, and the rule is about the DECLARATION rather than
    // about anything resolved, which is why it runs before the bases are. Three member shapes can
    // break it — a field, a property and a method — and each is named by its own noun in the report.
    // A non-generic type is not asked at all.
    func ValidateNoStaticMembersOnGenericType(state: TypeDeclarationState) {
        if state.Form == 3 {
            return
        }

        typeParameters := TypeParameters(state)
        if typeParameters == null || typeParameters.Count == 0 {
            return
        }

        members := TypeMembers(state)
        if members == null {
            return
        }

        for member in members {
            field := member as FieldDeclaration
            if field != null && HasStaticModifier(field.Modifiers) {
                ReportUnsupportedGenericStaticMember(state, typeParameters, "field", field.Name, field.Line, field.Column)
                continue
            }

            property := member as PropertyDeclaration
            if property != null && HasStaticModifier(property.Modifiers) {
                ReportUnsupportedGenericStaticMember(state, typeParameters, "property", property.Name, property.Line, property.Column)
                continue
            }

            function := member as FunctionDeclaration
            if function != null && HasStaticModifier(function.Modifiers) {
                ReportUnsupportedGenericStaticMember(state, typeParameters, "method", function.Name, function.Line, function.Column)
            }
        }
    }

    func ReportUnsupportedGenericStaticMember(state: TypeDeclarationState, typeParameters: List<TypeParameter>, memberKind: string, memberName: string, line: int, column: int) {
        typeDisplay := TypeName(state) + "<" + TypeParameterList(typeParameters) + ">"
        diagnosticsValue.Report(ErrorCode.FeatureNotImplemented, "Static " + memberKind + " '" + memberName + "' is not supported on generic type '" + typeDisplay + "' yet", line, column, "Move the static member to a non-generic helper type, or make it an instance member.", Math.Max(1, memberName.Length))
    }

    static func TypeParameterList(typeParameters: List<TypeParameter>): string {
        rendered := ""
        index := 0
        while index < typeParameters.Count {
            if index > 0 {
                rendered = rendered + ", "
            }

            rendered = rendered + typeParameters[index].Name
            index = index + 1
        }

        return rendered
    }

    // THE NESTED TYPES OF THIS DECLARATION, DECLARED INTO THE SCOPE THAT IS NOW OPEN. A declaration
    // whose shape the context cannot read declares none, which is not an error: it means the type has
    // no source shape to walk.
    func DeclareNestedTypesInCurrentScope(owner: TypeInfo) {
        shape := new AnalyzerSourceMemberShape()
        if !declarationContextValue.TryGetSourceMemberShape(owner, null, out shape) {
            return
        }

        for nested in shape.NestedTypes {
            scopesValue.DeclareNestedTypeIfAbsent(nested.Name, nested.Type)
        }
    }

    func DeclareTypeParameters(state: TypeDeclarationState) {
        typeParameters := TypeParameters(state)
        if typeParameters == null {
            return
        }

        for typeParameter in typeParameters {
            scopesValue.DeclareTypeParameter(typeParameter.Name)
        }
    }

    // THE BASES, IN THE ORDER EACH FORM WRITES THEM. A class resolves its base class and THEN its
    // interfaces; a struct and a record have no base to resolve; an interface resolves its base
    // interfaces. The order is visible whenever both are unresolvable, because the two reports land in
    // it.
    func ResolveDeclaredBases(state: TypeDeclarationState) {
        if state.Form == 0 {
            classDeclaration := state.Declaration as ClassDeclaration
            if classDeclaration != null {
                typeResolverValue.ResolveTypeIfPresent(classDeclaration.BaseClass)
                typeResolverValue.ResolveTypeReferences(classDeclaration.Interfaces)
            }

            return
        }

        if state.Form == 1 {
            structDeclaration := state.Declaration as StructDeclaration
            if structDeclaration != null {
                typeResolverValue.ResolveTypeReferences(structDeclaration.Interfaces)
            }

            return
        }

        if state.Form == 2 {
            recordDeclaration := state.Declaration as RecordDeclaration
            if recordDeclaration != null {
                typeResolverValue.ResolveTypeReferences(recordDeclaration.Interfaces)
            }

            return
        }

        interfaceDeclaration := state.Declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            typeResolverValue.ResolveTypeReferences(interfaceDeclaration.BaseInterfaces)
        }
    }

    // THE TYPE `this` IS DECLARED UNDER AND THE OWNER WHOSE NESTED TYPES ARE DECLARED. It is the type
    // the SCOPE STACK already knows when the declaration has been discovered, and a freshly built
    // nominal type when it has not — which is the case for a type declared inside a member body.
    func OwnerTypeFor(state: TypeDeclarationState): TypeInfo {
        declared := state.DeclaredType
        if declared != null {
            return declared
        }

        if state.Form == 0 {
            return NominalTypeInfoFactory.FromClassDeclaration(state.Declaration)
        }

        if state.Form == 1 {
            return NominalTypeInfoFactory.FromStructDeclaration(state.Declaration)
        }

        if state.Form == 2 {
            return NominalTypeInfoFactory.FromRecordDeclaration(state.Declaration)
        }

        return NominalTypeInfoFactory.FromInterfaceDeclaration(state.Declaration)
    }

    func TypeScopeKind(state: TypeDeclarationState): ScopeKind {
        if state.Form == 0 {
            return ScopeKind.Class
        }

        if state.Form == 1 {
            return ScopeKind.Struct
        }

        if state.Form == 2 {
            return ScopeKind.Record
        }

        return ScopeKind.Interface
    }

    func TypeName(state: TypeDeclarationState): string {
        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration != null {
            return classDeclaration.Name
        }

        structDeclaration := state.Declaration as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.Name
        }

        recordDeclaration := state.Declaration as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.Name
        }

        interfaceDeclaration := state.Declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return interfaceDeclaration.Name
        }

        unionDeclaration := state.Declaration as UnionDeclaration
        if unionDeclaration != null {
            return unionDeclaration.Name
        }

        enumDeclaration := state.Declaration as EnumDeclaration
        if enumDeclaration != null {
            return enumDeclaration.Name
        }

        return ""
    }

    func TypeModifiers(state: TypeDeclarationState): Modifiers {
        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration != null {
            return classDeclaration.Modifiers
        }

        structDeclaration := state.Declaration as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.Modifiers
        }

        recordDeclaration := state.Declaration as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.Modifiers
        }

        interfaceDeclaration := state.Declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return interfaceDeclaration.Modifiers
        }

        unionDeclaration := state.Declaration as UnionDeclaration
        if unionDeclaration != null {
            return unionDeclaration.Modifiers
        }

        enumDeclaration := state.Declaration as EnumDeclaration
        if enumDeclaration != null {
            return enumDeclaration.Modifiers
        }

        return Modifiers.None
    }

    func TypeParameters(state: TypeDeclarationState): List<TypeParameter>? {
        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration != null {
            return classDeclaration.TypeParameters
        }

        structDeclaration := state.Declaration as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.TypeParameters
        }

        recordDeclaration := state.Declaration as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.TypeParameters
        }

        interfaceDeclaration := state.Declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return interfaceDeclaration.TypeParameters
        }

        unionDeclaration := state.Declaration as UnionDeclaration
        if unionDeclaration != null {
            return unionDeclaration.TypeParameters
        }

        return null
    }

    func TypeMembers(state: TypeDeclarationState): List<Declaration>? {
        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration != null {
            return classDeclaration.Members
        }

        structDeclaration := state.Declaration as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.Members
        }

        recordDeclaration := state.Declaration as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.Members
        }

        interfaceDeclaration := state.Declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return interfaceDeclaration.Members
        }

        return null
    }

    func PrimaryConstructorParameters(state: TypeDeclarationState): List<Parameter>? {
        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration != null {
            return classDeclaration.PrimaryConstructorParameters
        }

        structDeclaration := state.Declaration as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.PrimaryConstructorParameters
        }

        recordDeclaration := state.Declaration as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.PrimaryConstructorParameters
        }

        return null
    }

    // THE SAME TWELVE BUILT-IN TYPES `Analyzer.cs`'s numeric predicate lists, `char` INCLUDED — which
    // is why `E: int { A = 'x' }` is accepted. That predicate stays in the shell for its many other
    // callers; this is the enum rule's own copy of the question, and the twelve are pinned by a
    // contract so the two cannot drift silently.
    static func IsNumericValueType(candidate: TypeInfo): bool {
        return BuiltInTypes.Is(candidate, BuiltInTypes.Int) || BuiltInTypes.Is(candidate, BuiltInTypes.Long) || BuiltInTypes.Is(candidate, BuiltInTypes.Float) || BuiltInTypes.Is(candidate, BuiltInTypes.Double) || BuiltInTypes.Is(candidate, BuiltInTypes.Decimal) || BuiltInTypes.Is(candidate, BuiltInTypes.Byte) || BuiltInTypes.Is(candidate, BuiltInTypes.SByte) || BuiltInTypes.Is(candidate, BuiltInTypes.Short) || BuiltInTypes.Is(candidate, BuiltInTypes.UShort) || BuiltInTypes.Is(candidate, BuiltInTypes.UInt) || BuiltInTypes.Is(candidate, BuiltInTypes.ULong) || BuiltInTypes.Is(candidate, BuiltInTypes.Char)
    }

    static func HasStaticModifier(modifiers: Modifiers): bool {
        return (Convert.ToInt32(modifiers) & Convert.ToInt32(Modifiers.Static)) != 0
    }

    // A TYPE'S DISPLAY TEXT, THROUGH `object`. A `ToString()` on the TYPED receiver declines columnar
    // emission; boxing first is the estate's established idiom for the same question.
    static func TypeText(candidate: TypeInfo): string {
        boxed := candidate as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}
