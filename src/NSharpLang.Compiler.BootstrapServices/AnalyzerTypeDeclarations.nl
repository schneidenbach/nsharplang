namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
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
// `SavedClass`, `SavedTypeMembers` and `SavedTypeName` are the ambient context's hand-backs, held
// HERE because the boundary opens in phase 0 and closes in phase 8 with the whole member walk in
// between. They are three slots rather than one frame because the four type forms do not move them
// together: only a CLASS moves the declaration, while all four move the name and the member list.
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
    SavedTypeMembers: List<Declaration>?
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
        SavedTypeMembers = null
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
    // down is made from inside this type. A CLASS moves the DECLARATION slot and everything else
    // leaves it alone — the difference a struct nested in a class depends on — while all four forms
    // move the NAME and the MEMBER LIST together, so those two always describe the same declaration.
    // The declared type is looked up BEFORE the scope opens, so the lookup sees the ENCLOSING scope,
    // which is where a type declaration's own name lives.
    //
    // THE MEMBER LIST IS WHAT THE READONLY-WRITE RULE READS, and it is a separate slot precisely
    // because the declaration slot cannot carry a struct or a record: `CurrentClass` is typed
    // `ClassDeclaration`, so NL309's bare-name channel saw NOTHING inside a struct or a record and
    // silently allowed writes Roslyn refuses with `CS0191`.
    func AdvanceTypeEntry(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 1
        name := TypeName(state)
        if state.Form == 0 {
            classDeclaration := state.Declaration as ClassDeclaration
            state.SavedClass = ambientValue.EnterClassDeclaration(classDeclaration)
        }

        state.SavedTypeMembers = ambientValue.EnterTypeMembers(TypeMembers(state))
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
        ValidateBaseClassEligibility(state)
        ValidateOverrideTargets(state)
        ValidateAbstractMemberImplementations(state)
        ValidateInterfaceImplementations(state)
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

    // PHASE 8 — THE AMBIENT CONTEXT IS LEFT, class slot first and name last, which is the order the
    // class walk restored its locals in, with the member list restored alongside the name it is
    // paired with. A throw anywhere inside the walk never reaches here, and that is the C# behaviour
    // preserved exactly: not one of these restores sat in a `finally`.
    func AdvanceLeaveTypeContext(state: TypeDeclarationState): TypeDeclarationRequest? {
        state.Phase = 99
        if state.Form == 0 {
            ambientValue.ExitClassDeclaration(state.SavedClass)
        }

        ambientValue.ExitTypeMembers(state.SavedTypeMembers)
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
    // THE MESSAGE IS NOT PART OF THAT ASYMMETRY: both shapes name the field, its type and what the
    // initializer gave, because a reader with a snippet needs the sentence just as much as one without.
    func ReportFieldTypeMismatch(state: TypeDeclarationState, field: FieldDeclaration, initializer: Expression, initializerType: TypeInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(initializer)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        message := "Field '" + field.Name + "' is typed as '" + TypeText(state.FieldType) + "', but the initializer gives '" + TypeText(initializerType) + "'"
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.TypeMismatch(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, TypeText(initializerType), TypeText(state.FieldType), message))
            return
        }

        diagnosticsValue.Report(ErrorCode.InvalidSyntax, message, field.Line, field.Column, null, 0)
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

    // AN `override` MUST HAVE A SLOT TO TAKE, AND THE SLOT MUST BE OPEN.
    //
    // `override` is a promise about a BASE member: that one exists with this name, and that it was
    // declared `virtual`, `abstract` or `override` so a derived type may replace it. Neither half was
    // checked before, so `override func Speak()` over a plain base method reported nothing at all and
    // the mistake surfaced — if at all — as an emission decline with no sentence naming the cause.
    //
    // THE WALK IS DELIBERATELY CONSERVATIVE, and silence is its default. It reports only when it can
    // NAME the base surface it searched: a source shape it can read, a CLR type it can reflect over,
    // or the implicit `object` at the end of a source chain. A base that resolves to nothing, to a
    // bare external NAME, or to a generic instantiation whose shape this owner cannot open answers
    // "cannot tell", and a check that cannot tell says nothing — a false `override` error would be
    // far worse than the missing one it replaces.
    //
    // The two faults get two sentences because they are two different mistakes: a member that is not
    // there at all is usually a typo or a signature drift, and a member that is there but sealed shut
    // is a missing `virtual` on the BASE. Both are `NL311` — the fault is in the modifier, not in the
    // name, which is why this is not an undefined-member report.
    func ValidateOverrideTargets(state: TypeDeclarationState) {
        members := TypeMembers(state)
        if members == null {
            return
        }

        declaredBase := DeclaredBaseTypeFor(state)
        for member in members {
            function := member as FunctionDeclaration
            if function != null {
                if HasOverrideModifier(function.Modifiers) {
                    verdict := ClassifyOverrideTarget(declaredBase, function.Name, 0)
                    if verdict == 2 {
                        ReportOverrideTargetFault(function, "is not marked 'virtual', 'abstract' or 'override'", "Mark the base member 'virtual', or drop 'override' from this declaration.")
                    }

                    if verdict == 3 {
                        ReportOverrideTargetFault(function, "has no base member of that name", "Check the spelling against the base type, or drop 'override' to declare a new member.")
                    }
                }

                continue
            }

            property := member as PropertyDeclaration
            if property != null {
                if HasOverrideModifier(property.Modifiers) {
                    propertyVerdict := ClassifyOverridePropertyTarget(declaredBase, property.Name, 0)
                    if propertyVerdict == 2 {
                        ReportOverridePropertyTargetFault(property, "is not marked 'virtual', 'abstract' or 'override'", "Mark the base property 'virtual', or drop 'override' from this declaration.")
                    }

                    if propertyVerdict == 3 {
                        ReportOverridePropertyTargetFault(property, "has no base member of that name", "Check the spelling against the base type, or drop 'override' to declare a new property.")
                    }
                }

                continue
            }

            field := member as FieldDeclaration
            if field != null {
                ValidateFieldInheritanceModifiers(field)
            }
        }
    }

    // A FIELD CANNOT TAKE PART IN INHERITANCE AT ALL, AND N# LETS ONE BE WRITTEN AS IF IT COULD.
    //
    // MEASURED, because the answer decides the rule: the parser chooses field or property from what
    // FOLLOWS the type and never from the modifiers, so `virtual Label: string`, `abstract Label:
    // string` and `override Label: string` all build a `FieldDeclaration`, while `Label: string => …`
    // and `Label: string { get … }` build a `PropertyDeclaration`. The emitted metadata agrees: a bare
    // `Auto: string` is a CLR FIELD and only the accessor forms are properties. A CLR field is never
    // virtual, never abstract and can never be overridden, so all three words are meaningless there —
    // and they were accepted in silence, which reads as a promise the runtime does not keep.
    //
    // The report is `NL311` for the same reason the override family is: the fault is the MODIFIER, not
    // the name. The suggestion names the two ways out, because both are real: give the member an
    // accessor and it becomes a property that CAN carry the word, or drop the word.
    func ValidateFieldInheritanceModifiers(field: FieldDeclaration) {
        modifierBits := Convert.ToInt32(field.Modifiers)
        if (modifierBits & Convert.ToInt32(Modifiers.Override)) != 0 {
            ReportFieldInheritanceModifierFault(field, "override")
            return
        }

        if (modifierBits & Convert.ToInt32(Modifiers.Abstract)) != 0 {
            ReportFieldInheritanceModifierFault(field, "abstract")
            return
        }

        if (modifierBits & Convert.ToInt32(Modifiers.Virtual)) != 0 {
            ReportFieldInheritanceModifierFault(field, "virtual")
        }
    }

    func ReportFieldInheritanceModifierFault(field: FieldDeclaration, modifierName: string) {
        span := spansValue.GetFieldNameDiagnosticSpan(field)
        diagnosticsValue.Report(ErrorCode.InvalidModifier, "'" + field.Name + "' is declared '" + modifierName + "', but a field cannot be virtual, abstract or overridden", span.Line, span.Column, "Give it an accessor — '" + field.Name + ": <type> => <expression>' or a 'get'/'set' block — so it becomes a property, or drop '" + modifierName + "'.", span.Length)
    }

    // THE SQUIGGLE GOES ON THE MEMBER NAME, not on the `override` keyword and not on `func`. The name
    // is the thing the developer either misspelled or must stop calling an override, and it is the
    // span every other declaration-name report in the analyzer already uses.
    func ReportOverrideTargetFault(function: FunctionDeclaration, reason: string, suggestion: string) {
        span := spansValue.GetFunctionNameDiagnosticSpan(function)
        diagnosticsValue.Report(ErrorCode.InvalidModifier, "'" + function.Name + "' is declared 'override', but it " + reason, span.Line, span.Column, suggestion, span.Length)
    }

    // The property sibling, on the same span rule and carrying the same two sentences — the fault a
    // developer made is the same one whether the member is spelled with `func` or with an accessor.
    func ReportOverridePropertyTargetFault(property: PropertyDeclaration, reason: string, suggestion: string) {
        span := spansValue.GetPropertyNameDiagnosticSpan(property)
        diagnosticsValue.Report(ErrorCode.InvalidModifier, "'" + property.Name + "' is declared 'override', but it " + reason, span.Line, span.Column, suggestion, span.Length)
    }

    // `class Derived : Base` WHERE `Base` IS `sealed` WAS ACCEPTED IN SILENCE AND THE WHOLE PROJECT
    // CHECKED CLEAN. NL802 has been in the catalog since the codes were written and nothing reported
    // it: `sealed` is a promise the declaration makes to every reader — "nothing extends this" — and
    // the compiler was not keeping it. The CLR refuses the derivation outright, so what shipped was a
    // program that could not load.
    //
    // THE REPORT IS ANCHORED ON THE BASE NAME, not on the deriving class's header: the base name is
    // the word that has to change, and pointing at `Derived` would send the reader to the wrong line
    // in a file where several classes share one base.
    //
    // IT RUNS BEFORE `ValidateOverrideTargets`, deliberately. A sealed base explains every override
    // fault beneath it, so it must be the first thing said about the declaration.
    func ValidateBaseClassEligibility(state: TypeDeclarationState) {
        if state.Form != 0 {
            return
        }

        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration == null {
            return
        }

        declaredBase := classDeclaration.BaseClass
        if declaredBase == null {
            return
        }

        resolved := DeclaredBaseTypeFor(state)
        if resolved == null || BuiltInTypes.IsUnknown(resolved) {
            return
        }

        // THE BASE-CLASS SLOT IS A SYNTACTIC ACCIDENT AND MAY HOLD AN INTERFACE. The parser splits
        // `: A, B, C` by position, so `class R : IDisposable` arrives with an interface here — and an
        // interface is exactly what a class is allowed to write. The interface rules own it.
        if IsInterfaceType(resolved) {
            return
        }

        kind := UnextendableBaseKind(resolved)
        if kind.Length == 0 {
            return
        }

        baseName := BaseReferenceName(declaredBase)
        span := BaseReferenceSpan(declaredBase, baseName, classDeclaration)
        message := "Cannot inherit from '" + baseName + "' because it is a " + kind
        diagnosticsValue.Report(ErrorCode.SealedInheritance, message, span.Line, span.Column, UnextendableBaseSuggestion(kind, baseName, classDeclaration.Name), span.Length)
    }

    // WHICH SHUT SHAPE THIS BASE IS, or "" for every type a class may extend. A closed generic is
    // opened first: `Box<int>` is extendable exactly when `Box<T>` is.
    static func UnextendableBaseKind(candidate: TypeInfo): string {
        opened := OpenGenericInstantiation(candidate)
        if opened == null {
            return ""
        }

        classType := opened as ClassTypeInfo
        if classType != null {
            if classType.IsSealed {
                return "sealed class"
            }

            return ""
        }

        reflectionType := opened as ReflectionTypeInfo
        if reflectionType == null {
            return ""
        }

        clrType := reflectionType.Type
        // A struct, an enum or a delegate in the base slot is a different fault with a different
        // sentence; every one of them is sealed in metadata, and calling them "a sealed class" would
        // name the wrong thing. Only reference types answer here.
        if clrType.get_IsInterface() || clrType.get_IsValueType() || !clrType.get_IsSealed() {
            return ""
        }

        if clrType.get_IsAbstract() {
            return "static class"
        }

        return "sealed class"
    }

    // THE WAY OUT, AND IT MUST COMPILE. A sealed base becomes a FIELD — composition is the answer the
    // reader wants and the one the CLR allows — and a static base is not a base at all.
    static func UnextendableBaseSuggestion(kind: string, baseName: string, derivedName: string): string {
        if kind == "static class" {
            return "A static class has no instances and cannot be a base. Call its members directly, as `" + baseName + ".Member(...)`."
        }

        return "Remove `sealed` from `" + baseName + "` if it is meant to be extended, or hold one instead of inheriting one — give `" + derivedName + "` a field `inner: " + baseName + "`."
    }

    // The written name of a base reference, in the two spellings a base clause can take.
    static func BaseReferenceName(declaredBase: TypeReference): string {
        simpleReference := declaredBase as SimpleTypeReference
        if simpleReference != null {
            return simpleReference.Name
        }

        genericReference := declaredBase as GenericTypeReference
        if genericReference != null {
            return genericReference.Name
        }

        return TypeReferenceFacts.GetDisplayName(declaredBase)
    }

    // Where the squiggle goes. A base reference the parser gave no position — every shape but the two
    // named ones — falls back to the declaring class's own header rather than to line 0, so the
    // diagnostic is always somewhere a reader can open.
    static func BaseReferenceSpan(declaredBase: TypeReference, baseName: string, classDeclaration: ClassDeclaration): DiagnosticSpan {
        simpleReference := declaredBase as SimpleTypeReference
        if simpleReference != null && simpleReference.Line > 0 {
            return new DiagnosticSpan(simpleReference.Line, simpleReference.Column, Math.Max(1, baseName.Length))
        }

        genericReference := declaredBase as GenericTypeReference
        if genericReference != null && genericReference.Line > 0 {
            return new DiagnosticSpan(genericReference.Line, genericReference.Column, Math.Max(1, baseName.Length))
        }

        return new DiagnosticSpan(classDeclaration.Line, classDeclaration.Column, Math.Max(1, classDeclaration.Name.Length))
    }

    // THE BASE THIS DECLARATION WRITES, or `null` for every form that writes none. A class with no
    // `:` clause, a struct and a record all still INHERIT — from `object` or `ValueType` — and `null`
    // here means exactly that: walk to the implicit root rather than give up.
    func DeclaredBaseTypeFor(state: TypeDeclarationState): TypeInfo? {
        if state.Form != 0 {
            return null
        }

        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration == null {
            return null
        }

        declaredBase := classDeclaration.BaseClass
        if declaredBase == null {
            return null
        }

        return typeResolverValue.ResolveType(declaredBase)
    }

    // 0 cannot tell · 1 an overridable base member · 2 a base member that is sealed shut · 3 no base
    // member of that name. The depth guard is the cycle brake: a base chain that closes on itself is
    // a separate diagnostic's problem, and this walk must not hang on it.
    func ClassifyOverrideTarget(candidate: TypeInfo?, name: string, depth: int): int {
        if depth > 24 {
            return 0
        }

        if candidate == null {
            return ClassifyObjectOverrideTarget(name)
        }

        if BuiltInTypes.IsUnknown(candidate) {
            return 0
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            return ClassifyReflectionOverrideTarget(reflectionType.Type, name)
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContextValue.TryGetSourceMemberShape(candidate, null, out shape) {
            return 0
        }

        declaredVerdict := ClassifyDeclaredOverrideTarget(shape.DeclaredMembers, name)
        if declaredVerdict != 0 {
            return declaredVerdict
        }

        // A SHAPE THAT WROTE A BASE THE CONTEXT COULD NOT RESOLVE IS NOT A SHAPE THAT ENDS AT
        // `object`. Walking on to the implicit root would search a surface this class does not
        // actually inherit and report a member that is virtual one link further up, so an unresolved
        // `:` clause answers "cannot tell" instead.
        if shape.BaseType == null && WritesUnresolvedBase(candidate) {
            return 0
        }

        return ClassifyOverrideTarget(shape.BaseType, name, depth + 1)
    }

    // WHETHER A DECLARED SHAPE NAMES A BASE THAT WAS NOT RESOLVED. Only a class can write one, and
    // the shape reports the RESOLVED base — so a written-but-null pair is exactly a resolution
    // failure rather than an absent clause.
    static func WritesUnresolvedBase(candidate: TypeInfo): bool {
        classType := candidate as ClassTypeInfo
        if classType == null {
            return false
        }

        return classType.BaseClass != null
    }

    // A SOURCE SHAPE'S OWN FUNCTION MEMBERS. Only functions answer: a field or a property of the same
    // name is not a method slot, and letting one answer would turn a real fault into silence. The
    // FIRST function of the name decides, because overloads of one name share one virtual-ness in
    // every shape this walk can read.
    static func ClassifyDeclaredOverrideTarget(declaredMembers: DeclaredMemberInfo[], name: string): int {
        index := 0
        while index < declaredMembers.Length {
            declared := declaredMembers[index]
            if declared.Kind == DeclaredMemberKind.Function && declared.Name == name {
                if declared.IsOverridable {
                    return 1
                }

                return 2
            }

            index = index + 1
        }

        return 0
    }

    // METADATA'S ANSWER. `GetMethods` already walks the CLR chain, so one call settles the whole
    // remaining base surface. `NonPublic` is in the flags because `protected virtual` is the shape
    // most worth catching; a method that is virtual but FINAL (a sealed override) is closed, not open.
    static func ClassifyReflectionOverrideTarget(clrType: Type, name: string): int {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        methods := clrType.GetMethods(flags)
        found := false
        index := 0
        while index < methods.Length {
            method := methods[index]
            if method.get_Name() == name && !method.get_IsSpecialName() {
                found = true
                if method.get_IsVirtual() && !method.get_IsFinal() {
                    return 1
                }
            }

            index = index + 1
        }

        if found {
            return 2
        }

        return 3
    }

    // THE IMPLICIT ROOT. A source chain that names no further base ends at `object`, whose only open
    // slots are `ToString`, `Equals` and `GetHashCode` — `GetType` is not virtual, which is why
    // `override func GetType()` is a real fault rather than a tolerated one.
    static func ClassifyObjectOverrideTarget(name: string): int {
        return ClassifyReflectionOverrideTarget(typeof(object), name)
    }

    // ---- a declared interface that the type does not implement ------------------------------------
    //
    // NOTHING EVER CHECKED THIS. `interface Greeter { func Greet(): string }` with
    // `class English : Greeter { }` beneath it reported nothing at all, and neither did
    // `class Resource : IDisposable { }` or `struct Point : Greeter { }`. A declared interface is a
    // promise to callers; an unkept one is a type that cannot satisfy the calls its own declaration
    // invites.
    //
    // WHERE THE INTERFACES ARE IS A SYNTACTIC ACCIDENT AND THIS RULE UNDOES IT. The parser splits a
    // class's `: A, B, C` by POSITION — `[0]` to `BaseClass`, the rest to `Interfaces` — so a class
    // whose only base entry is an interface carries it in the base-CLASS slot. Both slots are read
    // here and each is kept only if it RESOLVES to an interface, which is the semantic question the
    // parser could not answer. A struct and a record have no base-class slot at all, so for them the
    // list is already pure.
    //
    // N# HAS ONLY IMPLICIT IMPLEMENTATION. There is no explicit-interface-implementation syntax in the
    // grammar, in the parser or in the documentation, so a member satisfies an interface by NAME —
    // there is no second, differently-spelled way to satisfy one that this walk could miss.
    func ValidateInterfaceImplementations(state: TypeDeclarationState) {
        if state.Form == 3 {
            return
        }

        if IsAbstractDeclaration(state) {
            return
        }

        declaredInterfaces := DeclaredInterfacesFor(state)
        if declaredInterfaces.Count == 0 {
            return
        }

        // WHAT THE TYPE SUPPLIES INCLUDES WHAT IT INHERITS. A base class that already implements the
        // member discharges the obligation, so the supply set is this type's own members plus every
        // member of its base-class chain — collected with the same tolerance for an unreadable link
        // that the abstract walk uses, except that here an unreadable base means "cannot tell" for the
        // whole type rather than a partial answer.
        suppliedFunctions := new HashSet<string>(StringComparer.Ordinal)
        suppliedValues := new HashSet<string>(StringComparer.Ordinal)
        CollectSuppliedMemberNames(state, suppliedFunctions, suppliedValues)

        baseType := DeclaredBaseTypeFor(state)
        if baseType != null && !IsInterfaceType(baseType) {
            if !CollectInheritedMemberNames(baseType, suppliedFunctions, suppliedValues, 0) {
                return
            }
        }

        missing := new List<string>()
        index := 0
        while index < declaredInterfaces.Count {
            if !CollectUnimplementedInterfaceMembers(declaredInterfaces[index], suppliedFunctions, suppliedValues, missing, 0) {
                return
            }

            index = index + 1
        }

        if missing.Count == 0 {
            return
        }

        ReportUnimplementedInterfaceMembers(state, missing)
    }

    // THE DECLARED INTERFACES, RESOLVED AND FILTERED BY KIND. An entry that does not resolve, or that
    // resolves to something that is not an interface, is dropped rather than guessed at — an
    // unresolved name is `NL201`'s business and a base CLASS is the abstract walk's.
    func DeclaredInterfacesFor(state: TypeDeclarationState): List<TypeInfo> {
        resolved := new List<TypeInfo>()
        written := WrittenInterfaceReferences(state)
        if written == null {
            return resolved
        }

        for reference in written {
            candidate := typeResolverValue.ResolveType(reference)
            if candidate != null && IsInterfaceType(candidate) {
                resolved.Add(candidate)
            }
        }

        return resolved
    }

    // The written list, including a class's base-CLASS slot — see the banner: the split is positional,
    // so the slot may hold an interface and the filter above is what decides.
    func WrittenInterfaceReferences(state: TypeDeclarationState): List<TypeReference>? {
        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration != null {
            written := new List<TypeReference>()
            declaredBase := classDeclaration.BaseClass
            if declaredBase != null {
                written.Add(declaredBase)
            }

            for reference in classDeclaration.Interfaces {
                written.Add(reference)
            }

            return written
        }

        structDeclaration := state.Declaration as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.Interfaces
        }

        recordDeclaration := state.Declaration as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.Interfaces
        }

        return null
    }

    static func IsInterfaceType(candidate: TypeInfo): bool {
        opened := OpenGenericInstantiation(candidate)
        if opened == null {
            return false
        }

        if (opened as InterfaceTypeInfo) != null {
            return true
        }

        reflectionType := opened as ReflectionTypeInfo
        if reflectionType != null {
            return reflectionType.Type.get_IsInterface()
        }

        return false
    }

    // A CLOSED GENERIC IS A WRAPPER, AND THE MEMBER NAMES ARE ON THE DEFINITION. `IComparable<Version2>`
    // resolves to a `GenericTypeInfo` whose `GenericDefinition` is the interface itself, and every
    // question this family asks — is it an interface, what does it require — is answered by NAME, which
    // no type argument can change. So the wrapper is opened once, here, and both callers work on what
    // comes out. A wrapper with no definition is not opened and answers "cannot tell", which is why
    // this returns null rather than the wrapper.
    static func OpenGenericInstantiation(candidate: TypeInfo): TypeInfo? {
        generic := candidate as GenericTypeInfo
        if generic == null {
            return candidate
        }

        return generic.GenericDefinition
    }

    // Whether the DECLARATION carries `abstract`. An abstract class may leave an interface member to
    // its subclasses, exactly as it may leave an abstract member — and a struct or record can never be
    // abstract, so the question only has a class answer.
    func IsAbstractDeclaration(state: TypeDeclarationState): bool {
        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration == null {
            return false
        }

        return (Convert.ToInt32(classDeclaration.Modifiers) & Convert.ToInt32(Modifiers.Abstract)) != 0
    }

    // WHAT THIS TYPE ITSELF SUPPLIES. Functions go in one set and VALUE members — fields and properties
    // together — in the other, because N# does not make the caller choose: an interface's value member
    // is written bare (`Id: int`, which the AST calls a field) and an implementer may spell it bare or
    // with an accessor. Splitting those two into different slots would report correct programs.
    func CollectSuppliedMemberNames(state: TypeDeclarationState, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>) {
        members := TypeMembers(state)
        if members != null {
            AddDeclaredMemberNames(members, suppliedFunctions, suppliedValues)
        }

        primaryParameters := PrimaryConstructorParameters(state)
        if primaryParameters != null {
            for parameter in primaryParameters {
                suppliedValues.Add(parameter.Name)
            }
        }
    }

    // A record's positional parameters ARE its members, which is why they are counted above.
    static func AddDeclaredMemberNames(members: List<Declaration>, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>) {
        for member in members {
            function := member as FunctionDeclaration
            if function != null {
                suppliedFunctions.Add(function.Name)
                continue
            }

            property := member as PropertyDeclaration
            if property != null {
                suppliedValues.Add(property.Name)
                continue
            }

            field := member as FieldDeclaration
            if field != null {
                suppliedValues.Add(field.Name)
            }
        }
    }

    // THE BASE-CLASS CHAIN'S CONTRIBUTION. Returns false for "cannot tell", which abandons the whole
    // report — a supply set missing a link would accuse a type of not implementing what its base does.
    func CollectInheritedMemberNames(candidate: TypeInfo?, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>, depth: int): bool {
        if depth > 24 {
            return false
        }

        if candidate == null {
            return true
        }

        if BuiltInTypes.IsUnknown(candidate) {
            return false
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            CollectReflectedMemberNames(reflectionType.Type, suppliedFunctions, suppliedValues)
            return true
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContextValue.TryGetSourceMemberShape(candidate, null, out shape) {
            return false
        }

        declaredMembers := shape.DeclaredMembers
        index := 0
        while index < declaredMembers.Length {
            declared := declaredMembers[index]
            if declared.Kind == DeclaredMemberKind.Function {
                suppliedFunctions.Add(declared.Name)
            } else {
                if declared.Kind == DeclaredMemberKind.Property || declared.Kind == DeclaredMemberKind.Field {
                    suppliedValues.Add(declared.Name)
                }
            }

            index = index + 1
        }

        if shape.BaseType == null && WritesUnresolvedBase(candidate) {
            return false
        }

        return CollectInheritedMemberNames(shape.BaseType, suppliedFunctions, suppliedValues, depth + 1)
    }

    // One `GetMethods`/`GetProperties` pair settles a CLR base chain, the same way it does for the
    // abstract walk. An abstract member of a CLR base supplies nothing — it is a slot, not a body — so
    // it is excluded here or a `class X : Stream, IDisposable` would look as if `Stream` had implemented
    // whatever names happened to match.
    //
    // MATCHING IS BY NAME, AND OVERLOADS ARE THE MEASURED LIMIT OF THAT. `Stream.Read` has two
    // declarations — `Read(byte[], int, int)` is abstract, `Read(Span<byte>)` is concrete — so the name
    // counts as SUPPLIED here even though one overload is a slot. That is the UNDER-reporting direction,
    // deliberately: this family's worst failure is the correct program it rejects, not the fault it
    // misses. It is also unreachable from N# source, which cannot spell overloads in a class body at
    // all (a class with overloaded methods does not parse).
    static func CollectReflectedMemberNames(clrType: Type, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>) {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        methods := clrType.GetMethods(flags)
        index := 0
        while index < methods.Length {
            method := methods[index]
            if !method.get_IsSpecialName() && !method.get_IsAbstract() {
                suppliedFunctions.Add(method.get_Name())
            }

            index = index + 1
        }

        properties := clrType.GetProperties(flags)
        propertyIndex := 0
        while propertyIndex < properties.Length {
            property := properties[propertyIndex]
            if !IsAbstractPropertyAccessor(property.GetGetMethod(true)) && !IsAbstractPropertyAccessor(property.GetSetMethod(true)) {
                suppliedValues.Add(property.get_Name())
            }

            propertyIndex = propertyIndex + 1
        }
    }

    // AN INTERFACE'S REQUIREMENTS, INCLUDING THE ONES IT INHERITS. `IEnumerable<T>` requires
    // `IEnumerable`'s member too, so the base-interface list is walked as well; a name already supplied
    // is recorded so two interfaces demanding the same member report it once.
    func CollectUnimplementedInterfaceMembers(candidate: TypeInfo?, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>, missing: List<string>, depth: int): bool {
        if depth > 24 {
            return false
        }

        if candidate == null {
            return true
        }

        if BuiltInTypes.IsUnknown(candidate) {
            return false
        }

        opened := OpenGenericInstantiation(candidate)
        if opened == null {
            return false
        }

        reflectionType := opened as ReflectionTypeInfo
        if reflectionType != null {
            CollectReflectedInterfaceRequirements(reflectionType.Type, suppliedFunctions, suppliedValues, missing)
            return true
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContextValue.TryGetSourceMemberShape(opened, null, out shape) {
            return false
        }

        declaredMembers := shape.DeclaredMembers
        index := 0
        while index < declaredMembers.Length {
            RequireInterfaceMember(declaredMembers[index], suppliedFunctions, suppliedValues, missing)
            index = index + 1
        }

        return CollectSourceBaseInterfaceRequirements(opened, suppliedFunctions, suppliedValues, missing, depth)
    }

    // A source interface's own `: A, B` list. Each is resolved and walked; one that does not resolve to
    // an interface answers "cannot tell" for the whole report rather than being skipped, because a
    // requirement that was not read is not a requirement that was met.
    func CollectSourceBaseInterfaceRequirements(candidate: TypeInfo, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>, missing: List<string>, depth: int): bool {
        interfaceType := candidate as InterfaceTypeInfo
        if interfaceType == null {
            return true
        }

        baseInterfaces := interfaceType.BaseInterfaces
        index := 0
        while index < baseInterfaces.Length {
            resolved := typeResolverValue.ResolveType(baseInterfaces[index])
            if resolved == null {
                return false
            }

            if !CollectUnimplementedInterfaceMembers(resolved, suppliedFunctions, suppliedValues, missing, depth + 1) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // A MEMBER WITH A BODY IS A DEFAULT IMPLEMENTATION AND REQUIRES NOTHING. Everything else is a slot
    // the implementer must fill.
    //
    // THIS ONE LINE IS WHAT THE FIRST CENSUS FOUND. `examples/06-classes-and-records/RecordsAndInterfaces.nl`
    // writes `interface IShape { func GetArea(): double; func Describe(): string { … } }` and a `Circle`
    // that implements only `GetArea` — CORRECT N#, because `Describe` comes with its body. Without the
    // body test the rule accused it, which is exactly the failure mode this family fears most: the
    // correct program it rejects, not the fault it misses. The example is right and stays as written.
    static func RequireInterfaceMember(declared: DeclaredMemberInfo, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>, missing: List<string>) {
        if declared.HasBody {
            if declared.Kind == DeclaredMemberKind.Function {
                suppliedFunctions.Add(declared.Name)
            } else {
                suppliedValues.Add(declared.Name)
            }

            return
        }

        if declared.Kind == DeclaredMemberKind.Function {
            if suppliedFunctions.Add(declared.Name) {
                missing.Add(declared.Name)
            }

            return
        }

        if declared.Kind == DeclaredMemberKind.Property || declared.Kind == DeclaredMemberKind.Field {
            if suppliedValues.Add(declared.Name) {
                missing.Add(declared.Name)
            }
        }
    }

    // A CLR INTERFACE'S REQUIREMENTS. `GetMethods` on an interface returns its own members only, so the
    // inherited ones come from `GetInterfaces`, which flattens the whole set — one call, no walk.
    // Property accessors are `IsSpecialName` and are excluded from the method half so a property is
    // demanded once, under its own name, rather than twice as `get_X`/`set_X`.
    static func CollectReflectedInterfaceRequirements(clrType: Type, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>, missing: List<string>) {
        AddReflectedInterfaceMembers(clrType, suppliedFunctions, suppliedValues, missing)
        inherited := clrType.GetInterfaces()
        index := 0
        while index < inherited.Length {
            AddReflectedInterfaceMembers(inherited[index], suppliedFunctions, suppliedValues, missing)
            index = index + 1
        }
    }

    static func AddReflectedInterfaceMembers(clrType: Type, suppliedFunctions: HashSet<string>, suppliedValues: HashSet<string>, missing: List<string>) {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        methods := clrType.GetMethods(flags)
        index := 0
        while index < methods.Length {
            method := methods[index]
            if !method.get_IsSpecialName() && method.get_IsAbstract() {
                if suppliedFunctions.Add(method.get_Name()) {
                    missing.Add(method.get_Name())
                }
            }

            index = index + 1
        }

        properties := clrType.GetProperties(flags)
        propertyIndex := 0
        while propertyIndex < properties.Length {
            property := properties[propertyIndex]
            if IsAbstractPropertyAccessor(property.GetGetMethod(true)) || IsAbstractPropertyAccessor(property.GetSetMethod(true)) {
                if suppliedValues.Add(property.get_Name()) {
                    missing.Add(property.get_Name())
                }
            }

            propertyIndex = propertyIndex + 1
        }
    }

    // The same one-diagnostic-with-a-list rule the abstract report uses, in the interface's words. The
    // squiggle goes on the TYPE NAME for the same reason: the type is what is incomplete.
    func ReportUnimplementedInterfaceMembers(state: TypeDeclarationState, missing: List<string>) {
        typeName := DeclaredTypeNameFor(state)
        names := ""
        index := 0
        while index < missing.Count {
            if index > 0 {
                names = names + ", "
            }

            names = names + "'" + missing[index] + "'"
            index = index + 1
        }

        message := "'" + typeName + "' declares an interface but does not implement its member " + names
        suggestion := "Implement it in '" + typeName + "', inherit it from a base class, or drop the interface from the declaration."
        if missing.Count > 1 {
            message = "'" + typeName + "' declares an interface but does not implement " + missing.Count.ToString() + " of its members: " + names
            suggestion = "Implement all " + missing.Count.ToString() + " in '" + typeName + "', inherit them from a base class, or drop the interface from the declaration."
        }

        span := spansValue.GetTypeNameDiagnosticSpan(typeName, state.Declaration.Line, state.Declaration.Column)
        diagnosticsValue.Report(ErrorCode.InterfaceMemberNotImplemented, message, span.Line, span.Column, suggestion, span.Length)
    }

    func DeclaredTypeNameFor(state: TypeDeclarationState): string {
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

        return "<unknown>"
    }

    // ---- an inherited abstract member that nobody implemented -------------------------------------
    //
    // A CONCRETE CLASS MUST CARRY EVERY ABSTRACT MEMBER IT INHERITS, AND N# LET ONE OUT THE DOOR.
    // `abstract class Shape { abstract Area: double => … }` with `class Circle : Shape { }` beneath it
    // reported nothing at all and EMITTED — a concrete type with an unimplemented abstract slot, which
    // is the CS0534 family and a language-correctness hole rather than a style rule. The method
    // spelling was equally silent.
    //
    // THE REPORT IS ONE DIAGNOSTIC NAMING EVERY MISSING MEMBER, not one per member. A half-written
    // subclass is a single mistake with a list attached, and three separate squiggles on the same class
    // header would read as three unrelated problems.
    //
    // SILENCE REMAINS THE DEFAULT, and here it is stricter than in the override rule: if ANY link in
    // the base chain cannot be opened, the whole check abandons rather than reporting the members it
    // did manage to see — a missing set computed from half a chain is not a missing set. Four shapes
    // are exempt outright: a type with no written base (it inherits `object`, which is concrete), an
    // ABSTRACT derived class (it may pass the obligation down), any non-class form, and a base clause
    // that did not resolve.
    //
    // MATCHING IS BY NAME AND KIND. A function answers a function and a property answers a property,
    // because a field named `Area` does not implement `abstract func Area()` and silencing on it would
    // be worse than the report. Overloads are not distinguished — a class with overloaded methods does
    // not parse in N# today, so a name is a slot for every source shape this walk can read.
    func ValidateAbstractMemberImplementations(state: TypeDeclarationState) {
        if state.Form != 0 {
            return
        }

        classDeclaration := state.Declaration as ClassDeclaration
        if classDeclaration == null {
            return
        }

        if (Convert.ToInt32(classDeclaration.Modifiers) & Convert.ToInt32(Modifiers.Abstract)) != 0 {
            return
        }

        declaredBase := DeclaredBaseTypeFor(state)
        if declaredBase == null {
            return
        }

        // A CLASS'S FIRST BASE-LIST ENTRY IS NOT NECESSARILY A CLASS. The parser splits `: A, B, C`
        // syntactically — `[0]` becomes `BaseClass` and the rest `Interfaces` — so `class R : IDisposable`
        // arrives here with an INTERFACE in the base-class slot. Reporting it as an unimplemented
        // ABSTRACT MEMBER would be the wrong sentence for the right fault; the interface rule below owns
        // it, and this walk steps aside. (Measured: before this guard, `class Resource : IDisposable {}`
        // answered NL324 "does not implement inherited abstract member 'Dispose'".)
        if IsInterfaceType(declaredBase) {
            return
        }

        seenFunctions := new HashSet<string>(StringComparer.Ordinal)
        seenProperties := new HashSet<string>(StringComparer.Ordinal)
        CollectDeclaredMemberNames(state, seenFunctions, seenProperties)

        missing := new List<string>()
        if !CollectUnimplementedAbstractMembers(declaredBase, seenFunctions, seenProperties, missing, 0) {
            return
        }

        if missing.Count == 0 {
            return
        }

        ReportUnimplementedAbstractMembers(classDeclaration, missing)
    }

    // WHAT THIS TYPE ITSELF BRINGS. Every function and property it declares counts, with or without
    // `override`: a member that fills the slot fills it, and a missing `override` is the override
    // rule's business rather than this one's.
    func CollectDeclaredMemberNames(state: TypeDeclarationState, seenFunctions: HashSet<string>, seenProperties: HashSet<string>) {
        members := TypeMembers(state)
        if members == null {
            return
        }

        for member in members {
            function := member as FunctionDeclaration
            if function != null {
                seenFunctions.Add(function.Name)
                continue
            }

            property := member as PropertyDeclaration
            if property != null {
                seenProperties.Add(property.Name)
            }
        }
    }

    // THE BASE CHAIN, NEAREST FIRST, SO A NEARER CONCRETE OVERRIDE CLOSES THE SLOT. A member name is
    // recorded the first time the walk meets it, and only an ABSTRACT first sighting is a missing
    // implementation — an intermediate class that already overrode it has discharged the obligation.
    // Returns false for "cannot tell", which abandons the whole report.
    func CollectUnimplementedAbstractMembers(candidate: TypeInfo?, seenFunctions: HashSet<string>, seenProperties: HashSet<string>, missing: List<string>, depth: int): bool {
        if depth > 24 {
            return false
        }

        if candidate == null {
            return true
        }

        if BuiltInTypes.IsUnknown(candidate) {
            return false
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            CollectReflectedAbstractMembers(reflectionType.Type, seenFunctions, seenProperties, missing)
            return true
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContextValue.TryGetSourceMemberShape(candidate, null, out shape) {
            return false
        }

        declaredMembers := shape.DeclaredMembers
        index := 0
        while index < declaredMembers.Length {
            declared := declaredMembers[index]
            RecordAbstractCandidate(declared, seenFunctions, seenProperties, missing)
            index = index + 1
        }

        if shape.BaseType == null && WritesUnresolvedBase(candidate) {
            return false
        }

        return CollectUnimplementedAbstractMembers(shape.BaseType, seenFunctions, seenProperties, missing, depth + 1)
    }

    static func RecordAbstractCandidate(declared: DeclaredMemberInfo, seenFunctions: HashSet<string>, seenProperties: HashSet<string>, missing: List<string>) {
        isAbstract := (declared.DeclaredModifiers & Convert.ToInt32(Modifiers.Abstract)) != 0
        if declared.Kind == DeclaredMemberKind.Function {
            if seenFunctions.Add(declared.Name) && isAbstract {
                missing.Add(declared.Name)
            }

            return
        }

        if declared.Kind == DeclaredMemberKind.Property {
            if seenProperties.Add(declared.Name) && isAbstract {
                missing.Add(declared.Name)
            }
        }
    }

    // METADATA'S HALF, AND ONE CALL SETTLES THE WHOLE REMAINING CHAIN. `GetMethods` and `GetProperties`
    // already walk the CLR bases and already return the MOST DERIVED implementation of each virtual
    // slot, so a member that some intermediate CLR class overrode comes back non-abstract and is
    // correctly not required — the same property that lets the override rule ask them once.
    static func CollectReflectedAbstractMembers(clrType: Type, seenFunctions: HashSet<string>, seenProperties: HashSet<string>, missing: List<string>) {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        methods := clrType.GetMethods(flags)
        index := 0
        while index < methods.Length {
            method := methods[index]
            if !method.get_IsSpecialName() && method.get_IsAbstract() {
                if seenFunctions.Add(method.get_Name()) {
                    missing.Add(method.get_Name())
                }
            }

            index = index + 1
        }

        properties := clrType.GetProperties(flags)
        propertyIndex := 0
        while propertyIndex < properties.Length {
            property := properties[propertyIndex]
            if IsAbstractPropertyAccessor(property.GetGetMethod(true)) || IsAbstractPropertyAccessor(property.GetSetMethod(true)) {
                if seenProperties.Add(property.get_Name()) {
                    missing.Add(property.get_Name())
                }
            }

            propertyIndex = propertyIndex + 1
        }
    }

    static func IsAbstractPropertyAccessor(accessor: MethodInfo?): bool {
        if accessor == null {
            return false
        }

        return accessor.get_IsAbstract()
    }

    // THE SENTENCE COUNTS, because "does not implement 3 inherited abstract members" followed by the
    // list is what a reader can act on, and the singular form must not read like a truncated plural.
    // The squiggle goes on the CLASS NAME — the class is what is incomplete, and no one member is more
    // to blame than the others.
    func ReportUnimplementedAbstractMembers(classDeclaration: ClassDeclaration, missing: List<string>) {
        names := ""
        index := 0
        while index < missing.Count {
            if index > 0 {
                names = names + ", "
            }

            names = names + "'" + missing[index] + "'"
            index = index + 1
        }

        message := "'" + classDeclaration.Name + "' does not implement inherited abstract member " + names
        suggestion := "Implement it in '" + classDeclaration.Name + "', or declare '" + classDeclaration.Name + "' abstract so a subclass must."
        if missing.Count > 1 {
            message = "'" + classDeclaration.Name + "' does not implement " + missing.Count.ToString() + " inherited abstract members: " + names
            suggestion = "Implement all " + missing.Count.ToString() + " in '" + classDeclaration.Name + "', or declare '" + classDeclaration.Name + "' abstract so a subclass must."
        }

        span := spansValue.GetTypeNameDiagnosticSpan(classDeclaration.Name, classDeclaration.Line, classDeclaration.Column)
        diagnosticsValue.Report(ErrorCode.AbstractMemberNotImplemented, message, span.Line, span.Column, suggestion, span.Length)
    }

    // ---- the property half of the same question -------------------------------------------------
    //
    // A PROPERTY OVERRIDE ASKS THE SAME QUESTION ABOUT A DIFFERENT SLOT, AND IT COULD NOT BORROW THE
    // FUNCTION WALK FOR EITHER ANSWER. On the source side `ClassifyDeclaredOverrideTarget` matches
    // `DeclaredMemberKind.Function` and its own comment refuses a property deliberately — a method slot
    // is not a property slot. On the metadata side the refusal is subtler and would have been silent:
    // `ClassifyReflectionOverrideTarget` walks `GetMethods` and skips every `IsSpecialName`, which is
    // EXACTLY what a property accessor is, so a property override against a CLR base would have
    // searched a surface that structurally cannot contain it and answered "no base member" for every
    // correct program. Hence a separate pair, built to the same shape and the same verdict codes:
    // 0 cannot tell · 1 an overridable base property · 2 one that is sealed shut · 3 none of that name.
    //
    // The conservatism is inherited unchanged: an unresolved base, an unopenable shape and a depth
    // blow-out all answer "cannot tell", because a false `override` error on a correct program is worse
    // than the missing one it replaces.
    func ClassifyOverridePropertyTarget(candidate: TypeInfo?, name: string, depth: int): int {
        if depth > 24 {
            return 0
        }

        if candidate == null {
            return ClassifyObjectOverridePropertyTarget(name)
        }

        if BuiltInTypes.IsUnknown(candidate) {
            return 0
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            return ClassifyReflectionOverridePropertyTarget(reflectionType.Type, name)
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContextValue.TryGetSourceMemberShape(candidate, null, out shape) {
            return 0
        }

        declaredVerdict := ClassifyDeclaredOverridePropertyTarget(shape.DeclaredMembers, name)
        if declaredVerdict != 0 {
            return declaredVerdict
        }

        if shape.BaseType == null && WritesUnresolvedBase(candidate) {
            return 0
        }

        return ClassifyOverridePropertyTarget(shape.BaseType, name, depth + 1)
    }

    // A SOURCE SHAPE'S OWN PROPERTY MEMBERS. Only properties answer, for the mirror of the reason only
    // functions answer above: a base FIELD of the same name is not a property slot either, and a bare
    // `Name: Type` member is a field in this model and in the emitted metadata both.
    static func ClassifyDeclaredOverridePropertyTarget(declaredMembers: DeclaredMemberInfo[], name: string): int {
        index := 0
        while index < declaredMembers.Length {
            declared := declaredMembers[index]
            if declared.Kind == DeclaredMemberKind.Property && declared.Name == name {
                if declared.IsOverridable {
                    return 1
                }

                return 2
            }

            index = index + 1
        }

        return 0
    }

    // METADATA'S ANSWER FOR A PROPERTY. `GetProperties` walks the CLR chain the way `GetMethods` does,
    // and virtual-ness lives on the ACCESSORS rather than on the property: a property is overridable
    // exactly when one of its accessors is virtual and not final. `GetGetMethod(true)`/`GetSetMethod(true)`
    // take the non-public ones, because `protected virtual` is the shape most worth catching — the same
    // reason `NonPublic` is in the method walk's flags.
    static func ClassifyReflectionOverridePropertyTarget(clrType: Type, name: string): int {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        properties := clrType.GetProperties(flags)
        found := false
        index := 0
        while index < properties.Length {
            property := properties[index]
            if property.get_Name() == name {
                found = true
                if IsOverridablePropertyAccessor(property.GetGetMethod(true)) {
                    return 1
                }

                if IsOverridablePropertyAccessor(property.GetSetMethod(true)) {
                    return 1
                }
            }

            index = index + 1
        }

        if found {
            return 2
        }

        return 3
    }

    // An accessor opens the slot when it is virtual and NOT final — a sealed override is closed, which
    // is the same test the method walk makes and the reason `sealed override` cannot be overridden again.
    static func IsOverridablePropertyAccessor(accessor: MethodInfo?): bool {
        if accessor == null {
            return false
        }

        return accessor.get_IsVirtual() && !accessor.get_IsFinal()
    }

    // THE IMPLICIT ROOT, FOR PROPERTIES. `object` declares no properties at all, so a source chain that
    // names no further base has nothing a property can override — the answer is always 3, and it is
    // asked through the same reflection walk rather than hard-coded so the two stay in step.
    static func ClassifyObjectOverridePropertyTarget(name: string): int {
        return ClassifyReflectionOverridePropertyTarget(typeof(object), name)
    }

    static func HasOverrideModifier(modifiers: Modifiers): bool {
        return (Convert.ToInt32(modifiers) & Convert.ToInt32(Modifiers.Override)) != 0
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
