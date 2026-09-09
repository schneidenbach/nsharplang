namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the construction family — what `new T(a) { M: v }` and `t with { M: v }` MEAN.
//
// Every member behind these contracts was `private` in `Analyzer.cs`, so nothing named any of them.
// This is their first DIRECT pinning, and it goes at the decisions that are load-bearing rather than
// at the ones that are easy to reach:
//
//   * THE NL202 FRONT DOOR, first and most important. `EmitValueCoercion` silently no-ops for a
//     closed generic over an emitted user type, so this gate is the ONLY thing between
//     `Items: List<Rs>` into a `List<Pt>` field and a type-confused read at run time. It is pinned
//     for BOTH forms and at the closed-generic shape that motivates it.
//   * THE TWO KINDS, and WHICH form asks for which: `new` is one kind however many operands it has,
//     `with` asks for kind 2 exactly when a member type resolved for the entry.
//   * THE BRACKET, observed by recording the ambient slot AT each step — the only way to see a
//     bracket that opens and closes entirely inside the owner — including that a SoA capacity is the
//     one constructor argument that gets one.
//   * THE ORDER of the reports, which is behaviour: a `with` entry's SoA shape refusal is raised
//     BEFORE its member is looked up and GATES that lookup.
//   * THE STAGE/PHASE SPLIT, pinned by the case that motivated it: a sized array reports its
//     argument conflict exactly ONCE.
class ConstructionHarness {
    Arm: AnalyzerConstruction
    Errors: List<CompilerError>
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Context: AnalyzerDeclarationContext
    Sink: AnalyzerDiagnosticSink

    constructor(
        arm: AnalyzerConstruction,
        errors: List<CompilerError>,
        ambient: AnalyzerAmbientContext,
        scopes: AnalyzerScopeStack,
        context: AnalyzerDeclarationContext,
        sink: AnalyzerDiagnosticSink
    ) {
        Arm = arm
        Errors = errors
        Ambient = ambient
        Scopes = scopes
        Context = context
        Sink = sink
    }
}

func ConstructionArm(): ConstructionHarness {
    errors := new List<CompilerError>()
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    sink := new AnalyzerDiagnosticSink(errors, provider)
    spans := new AnalyzerDiagnosticSpans(sink)
    usingAliases := new Dictionary<string, string>(StringComparer.Ordinal)
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal)
    namespaces := new List<string>()
    assemblies := new List<Assembly>()
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, usingAliases)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, usingAliases, importedSymbols, importedDeclarations, model, bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    extensions := new List<FunctionDeclaration>()
    extensionResolution := new AnalyzerExtensionMethodResolution(resolver, assignability, context, functionTypes, clrConversion, extensions, namespaces, assemblies)
    members := new AnalyzerMemberResolution(functionTypes, context, substitution, resolver, clrConversion, extensionResolution, namespaces)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)
    identifierResolution := new AnalyzerIdentifierResolution(sink, scopes, resolver, discovery, probe, functionTypes, ambient, nullFlow, extensions, members, model, bindings)
    memberAccess := new AnalyzerMemberAccess(sink, spans, scopes, context, nullFlow, soaEscape, ambient, provider, discovery, probe, substitution, identifierResolution, extensions, namespaces, usingAliases, importedSymbols, importedDeclarations, assemblies, members, clrConversion, extensionResolution, bindings)
    arrayLiteral := new AnalyzerArrayLiteral(sink, spans, context, ambient, soaEscape, assignability, facts)
    constantFacts := new AnalyzerConstantExpressionFacts(scopes, context)
    exhaustiveness := new AnalyzerMatchExhaustiveness(sink, substitution, assignability, resolver)

    indexAccess := new AnalyzerIndexAccess(sink, spans, context, ambient, nullFlow, soaEscape, memberAccess, constantFacts)
    writeTargets := new AnalyzerWriteTargets(sink, spans, scopes, context, substitution, clrConversion, ambient, soaEscape, memberAccess, indexAccess)
    arm := new AnalyzerConstruction(sink, spans, scopes, context, resolver, substitution, discovery, ambient, soaEscape, memberAccess, arrayLiteral, constantFacts, assignability, members, exhaustiveness, clrConversion, writeTargets)
    return new ConstructionHarness(arm, errors, ambient, scopes, context, sink)
}

func ConstructionCodes(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + ","
        }

        codeValue: int = (int)errors[index].Code
        text = text + codeValue.ToString()
        index = index + 1
    }

    return text
}

func ConstructionTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    if BuiltInTypes.IsUnknown(candidate) {
        return "unknown"
    }

    simple := candidate as SimpleTypeInfo
    if simple != null {
        return "simple:" + simple.Name
    }

    nullable := candidate as NullableTypeInfo
    if nullable != null {
        return "nullable(" + ConstructionTypeName(nullable.InnerType) + ")"
    }

    arrayType := candidate as ArrayTypeInfo
    if arrayType != null {
        return "array(" + ConstructionTypeName(arrayType.ElementType) + ")"
    }

    generic := candidate as GenericTypeInfo
    if generic != null {
        return "generic:" + generic.Name + ConstructionArgumentText(generic)
    }

    classType := candidate as ClassTypeInfo
    if classType != null {
        return "class:" + classType.Name
    }

    structType := candidate as StructTypeInfo
    if structType != null {
        return "struct:" + structType.Name
    }

    unionType := candidate as UnionTypeInfo
    if unionType != null {
        return "union:" + unionType.Declaration.Name
    }

    soaType := candidate as SoaRecordTypeInfo
    if soaType != null {
        return "soa:" + soaType.Declaration.Name
    }

    return "<other>"
}

func ConstructionArgumentText(generic: GenericTypeInfo): string {
    text := "<"
    argIndex := 0
    while argIndex < generic.TypeArguments.Count {
        if argIndex > 0 {
            text = text + ","
        }

        text = text + ConstructionTypeName(generic.TypeArguments[argIndex])
        argIndex = argIndex + 1
    }

    return text + ">"
}

// ---- AST builders --------------------------------------------------------------------------------

func ConstructionIntLiteral(value: string): Expression {
    literal: Expression = new IntLiteralExpression(value, 4, 8)
    return literal
}

func ConstructionStringLiteral(value: string): Expression {
    literal: Expression = new StringLiteralExpression(value, 4, 8)
    return literal
}

func ConstructionNamedEntry(name: string, value: Expression): PropertyInitializer {
    return new PropertyInitializer(name, null, value, 4, 3)
}

func ConstructionElementEntry(value: Expression): PropertyInitializer {
    return new PropertyInitializer(null, null, value, 0, 0)
}

func ConstructionIndexedEntry(index: Expression, value: Expression): PropertyInitializer {
    return new PropertyInitializer(null, index, value, 0, 0)
}

func ConstructionNoEntries(): List<PropertyInitializer> {
    return new List<PropertyInitializer>()
}

func ConstructionOneNamed(name: string): List<PropertyInitializer> {
    entries := ConstructionNoEntries()
    entries.Add(ConstructionNamedEntry(name, ConstructionStringLiteral("x")))
    return entries
}

func ConstructionOneElement(): List<PropertyInitializer> {
    entries := ConstructionNoEntries()
    entries.Add(ConstructionElementEntry(ConstructionStringLiteral("x")))
    return entries
}

func ConstructionEntries(entries: List<PropertyInitializer>): ObjectInitializerExpression {
    return new ObjectInitializerExpression(entries, 4, 1)
}

func ConstructionNoArguments(): List<Argument> {
    return new List<Argument>()
}

func ConstructionArgument(value: Expression): Argument {
    return new Argument(null, value)
}

// A SoA table is built with exactly one int capacity, so every contract about its INITIALIZER passes
// one — otherwise the arity refusal fires first and the contract stops being about the initializer.
func ConstructionCapacity(): List<Argument> {
    args := ConstructionNoArguments()
    args.Add(ConstructionArgument(ConstructionIntLiteral("4")))
    return args
}

func ConstructionNamedArgument(name: string, value: Expression): Argument {
    return new Argument(name, value)
}

func ConstructionNewOf(typeName: string?, args: List<Argument>, initializer: ObjectInitializerExpression?): NewExpression {
    typeReference: TypeReference? = null
    if typeName != null {
        typeReference = new SimpleTypeReference(typeName, 4, 5)
    }

    return new NewExpression(typeReference, args, initializer, 4, 1)
}

func ConstructionSizedArray(typeName: string, length: Expression, args: List<Argument>): NewExpression {
    return new NewExpression(new SimpleTypeReference(typeName, 4, 5), args, null, 4, 1, length)
}

func ConstructionWithOf(entries: List<PropertyInitializer>): WithExpression {
    return new WithExpression(new IdentifierExpression("value", 4, 1), entries, 4, 1)
}

// ---- declared shapes -----------------------------------------------------------------------------

func ConstructionEmptyMembers(): DeclaredMemberInfo[] {
    return new DeclaredMemberInfo[](0)
}

func ConstructionEmptyTypeParameters(): TypeParameter[] {
    return new TypeParameter[](0)
}

func ConstructionEmptyParameters(): ParameterDeclarationInfo[] {
    return new ParameterDeclarationInfo[](0)
}

func ConstructionEmptyTypeReferences(): TypeReference[] {
    return new TypeReference[](0)
}

func ConstructionEmptyNestedTypes(): NestedTypeInfo[] {
    return new NestedTypeInfo[](0)
}

func ConstructionFieldMember(owner: string, name: string, fieldType: TypeReference, isReadonly: bool): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name,
        owner,
        DeclaredMemberKind.Field,
        "field",
        fieldType,
        false,
        isReadonly,
        true,
        true,
        0,
        new string[](0),
        ConstructionEmptyTypeReferences(),
        new ParameterModifier[](0),
        0,
        false,
        false,
        null,
        0,
        ConstructionEmptyTypeParameters(),
        new GenericConstraint[](0),
        0,
        false,
        false,
        false,
        false,
        "",
        false,
        false,
        1,
        1
    )
}

func ConstructionPlainClass(name: string): ClassTypeInfo {
    return new ClassTypeInfo(name, 1, 1, false, null, ConstructionEmptyTypeReferences(), ConstructionEmptyTypeParameters(), ConstructionEmptyParameters(), ConstructionEmptyMembers(), ConstructionEmptyNestedTypes(), true)
}

func ConstructionPlainStruct(name: string): StructTypeInfo {
    return new StructTypeInfo(name, 1, 1, ConstructionEmptyTypeReferences(), ConstructionEmptyTypeParameters(), ConstructionEmptyParameters(), ConstructionEmptyMembers(), ConstructionEmptyNestedTypes())
}

// THE SHAPE THE FRONT DOOR EXISTS FOR. `Box<T>` declares ONE field, `Item: T`, so the member's type
// is only known after the constructed instantiation's substitution is applied — and a closed generic
// over an emitted user type is exactly the shape `EmitValueCoercion` silently no-ops on.
func ConstructionOpenBox(): ClassTypeInfo {
    typeParameters := new TypeParameter[](1)
    typeParameters[0] = new TypeParameter("T")
    membersArray := new DeclaredMemberInfo[](1)
    membersArray[0] = ConstructionFieldMember("Box", "Item", new SimpleTypeReference("T", 1, 1), false)
    return new ClassTypeInfo("Box", 1, 1, false, null, ConstructionEmptyTypeReferences(), typeParameters, ConstructionEmptyParameters(), membersArray, ConstructionEmptyNestedTypes(), true)
}

// The definition is CARRIED by the instantiation, which is how a closed generic answers for its own
// open shape without a lookup.
func ConstructionClosedBox(argument: TypeInfo): TypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(argument)
    closed: TypeInfo = new GenericTypeInfo("Box", arguments, ConstructionOpenBox())
    return closed
}

func ConstructionSoaTable(name: string): SoaRecordTypeInfo {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 1, 1), 1, 1))
    return new SoaRecordTypeInfo(new SoaRecordDeclarationInfo(name, columns, 1, 1))
}

func ConstructionUnion(name: string, caseNames: List<string>, typeParameters: List<TypeParameter>?): UnionTypeInfo {
    cases := new List<UnionCase>()
    index := 0
    while index < caseNames.Count {
        cases.Add(new UnionCase(caseNames[index], null, 1, 1))
        index = index + 1
    }

    return new UnionTypeInfo(new UnionDeclarationInfo(name, typeParameters, cases, 1, 1))
}

func ConstructionQualifiedNew(qualified: string): NewExpression {
    return new NewExpression(new SimpleTypeReference(qualified, 4, 5), ConstructionNoArguments(), null, 4, 1)
}

// ---- the driver ----------------------------------------------------------------------------------

class ConstructionTrace {
    Kinds: string
    ExpectedAtStep: string
    Answer: string
    Reports: int
    Codes: string

    constructor() {
        Kinds = ""
        ExpectedAtStep = ""
        Answer = ""
        Reports = 0
        Codes = ""
    }
}

// One full turn of the protocol. Every step is answered from `answers` in order (the last answer
// repeats once the queue runs out), and the EXPECTED TYPE the ambient slot holds AT each step is
// recorded — the only way to observe a bracket that opens and closes inside the owner.
func ConstructionDrive(harness: ConstructionHarness, state: ConstructionState, answers: List<TypeInfo>): ConstructionTrace {
    trace := new ConstructionTrace()
    before := harness.Errors.Count
    stepIndex := 0
    step := harness.Arm.NextStep(state)
    while step != null {
        trace.Kinds = trace.Kinds + step.Kind.ToString()
        if stepIndex > 0 {
            trace.ExpectedAtStep = trace.ExpectedAtStep + ","
        }

        trace.ExpectedAtStep = trace.ExpectedAtStep + ConstructionTypeName(harness.Ambient.CurrentExpectedType)
        answerIndex := stepIndex
        if answerIndex >= answers.Count {
            answerIndex = answers.Count - 1
        }

        answer: TypeInfo = BuiltInTypes.Unknown
        if answerIndex >= 0 {
            answer = answers[answerIndex]
        }

        harness.Arm.Supply(state, answer)
        stepIndex = stepIndex + 1
        step = harness.Arm.NextStep(state)
    }

    trace.Answer = ConstructionTypeName(harness.Arm.Result(state))
    trace.Reports = harness.Errors.Count - before
    trace.Codes = ConstructionCodes(harness.Errors)
    return trace
}

func ConstructionAnswers(first: TypeInfo): List<TypeInfo> {
    answers := new List<TypeInfo>()
    answers.Add(first)
    return answers
}

func ConstructionAnswerPair(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    answers := new List<TypeInfo>()
    answers.Add(first)
    answers.Add(second)
    return answers
}

// ---- the walk protocol ---------------------------------------------------------------------------

test "a `new` with no operands asks for nothing and answers its resolved type" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Box", ConstructionPlainClass("Box"))
    state := harness.Arm.Begin(ConstructionNewOf("Box", ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Kinds == ""
    assert trace.Answer == "class:Box"
    assert trace.Reports == 0
}

test "a node that is not a construction finishes at Begin and asks for nothing" {
    harness := ConstructionArm()
    state := harness.Arm.Begin(new IdentifierExpression("value", 1, 1))

    assert harness.Arm.NextStep(state) == null
    assert ConstructionTypeName(harness.Arm.Result(state)) == "unknown"
}

test "every `new` operand is ONE kind, however many there are" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Box", ConstructionPlainClass("Box"))
    args := ConstructionNoArguments()
    args.Add(ConstructionArgument(ConstructionIntLiteral("1")))
    args.Add(ConstructionArgument(ConstructionIntLiteral("2")))
    state := harness.Arm.Begin(ConstructionNewOf("Box", args, null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Kinds == "11"
    assert trace.Answer == "class:Box"
}

test "an ordinary constructor argument is walked with the ambient slot exactly as it was found" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Box", ConstructionPlainClass("Box"))
    args := ConstructionNoArguments()
    args.Add(ConstructionArgument(ConstructionIntLiteral("1")))
    state := harness.Arm.Begin(ConstructionNewOf("Box", args, null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.ExpectedAtStep == "<null>"
    assert harness.Ambient.CurrentExpectedType == null
}

// ---- the target-typed form -----------------------------------------------------------------------

test "a target-typed `new` with no expected type is refused as uninferrable" {
    harness := ConstructionArm()
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "203"
    assert trace.Answer == "unknown"
}

test "a target-typed `new` ADOPTS the ambient expected type and says nothing" {
    harness := ConstructionArm()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.String)
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))
    harness.Ambient.ExitExpectedType(saved)

    assert trace.Codes == ""
    assert trace.Answer == "simple:string"
}

test "an ANONYMOUS object needs no target at all — every entry is named and there are no arguments" {
    harness := ConstructionArm()
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(ConstructionOneNamed("Name"))))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))

    assert trace.Codes == ""
    assert trace.Kinds == "1"
}

test "a typeless `new` with an INDEXED entry is not anonymous, so it IS refused" {
    harness := ConstructionArm()
    entries := ConstructionNoEntries()
    entries.Add(ConstructionIndexedEntry(ConstructionIntLiteral("0"), ConstructionStringLiteral("a")))
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(entries)))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))

    assert trace.Codes == "203"
}

// ---- the sized-array form ------------------------------------------------------------------------

test "a sized array walks its LENGTH and says nothing when it is an int" {
    harness := ConstructionArm()
    state := harness.Arm.Begin(ConstructionSizedArray("int", ConstructionIntLiteral("4"), ConstructionNoArguments()))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Kinds == "1"
    assert trace.Codes == ""
}

test "a NON-int length is refused" {
    harness := ConstructionArm()
    state := harness.Arm.Begin(ConstructionSizedArray("int", ConstructionStringLiteral("four"), ConstructionNoArguments()))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))

    assert trace.Codes == "202"
    assert harness.Errors[0].Message == "Array length must be an int, not 'string'"
}

test "a sized array that ALSO passes constructor arguments is refused exactly ONCE" {
    harness := ConstructionArm()
    args := ConstructionNoArguments()
    args.Add(ConstructionArgument(ConstructionIntLiteral("1")))
    state := harness.Arm.Begin(ConstructionSizedArray("int", ConstructionIntLiteral("4"), args))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    // The STAGE counter is what makes this ONE: a phase-only machine re-enters the length stage after
    // its own answer and reports the conflict a second time.
    assert trace.Codes == "321"
    assert trace.Kinds == "11"
}

// ---- the union case form -------------------------------------------------------------------------

test "a qualified `new` that names a real union case answers the UNION, not the case" {
    harness := ConstructionArm()
    caseNames := new List<string>()
    caseNames.Add("Success")
    caseNames.Add("Failure")
    harness.Scopes.DeclareNestedTypeIfAbsent("Result", ConstructionUnion("Result", caseNames, null))
    state := harness.Arm.Begin(ConstructionQualifiedNew("Result.Success"))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Answer == "union:Result"
    assert trace.Codes == ""
}

test "a case the union does NOT declare is refused, with a did-you-mean drawn from the union's cases" {
    harness := ConstructionArm()
    caseNames := new List<string>()
    caseNames.Add("Success")
    caseNames.Add("Failure")
    harness.Scopes.DeclareNestedTypeIfAbsent("Result", ConstructionUnion("Result", caseNames, null))
    state := harness.Arm.Begin(ConstructionQualifiedNew("Result.Sucess"))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "303"
    assert harness.Errors[0].Suggestion == "Did you mean 'Result.Success'?"
    // The type still answers the union, so the initializer entries are not then also accused.
    assert trace.Answer == "union:Result"
}

test "a GENERIC union case with no type arguments and no closed expected type is refused" {
    harness := ConstructionArm()
    caseNames := new List<string>()
    caseNames.Add("Some")
    typeParameters := new List<TypeParameter>()
    typeParameters.Add(new TypeParameter("T"))
    harness.Scopes.DeclareNestedTypeIfAbsent("Option", ConstructionUnion("Option", caseNames, typeParameters))
    state := harness.Arm.Begin(ConstructionQualifiedNew("Option.Some"))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "207"
}

test "a GENERIC union case ADOPTS a closed expected type of the same name" {
    harness := ConstructionArm()
    caseNames := new List<string>()
    caseNames.Add("Some")
    typeParameters := new List<TypeParameter>()
    typeParameters.Add(new TypeParameter("T"))
    unionType := ConstructionUnion("Option", caseNames, typeParameters)
    harness.Scopes.DeclareNestedTypeIfAbsent("Option", unionType)
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    expected: TypeInfo = new GenericTypeInfo("Option", arguments, unionType)
    saved := harness.Ambient.EnterExpectedType(expected)
    state := harness.Arm.Begin(ConstructionQualifiedNew("Option.Some"))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))
    harness.Ambient.ExitExpectedType(saved)

    assert trace.Codes == ""
    assert trace.Answer == "generic:Option<simple:int>"
}

// ---- THE NL202 FRONT DOOR ------------------------------------------------------------------------

test "THE FRONT DOOR: a closed-generic initializer value that does not fit its member is REFUSED" {
    harness := ConstructionArm()
    saved := harness.Ambient.EnterExpectedType(ConstructionClosedBox(ConstructionPlainStruct("Pt")))
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(ConstructionOneNamed("Item"))))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(ConstructionPlainStruct("Rs")))
    harness.Ambient.ExitExpectedType(saved)

    // Nothing downstream repeats this check: EmitValueCoercion silently no-ops for exactly this shape.
    assert trace.Codes == "202"
    assert trace.Kinds == "1"
}

test "THE FRONT DOOR: the matching closed generic passes without a word" {
    harness := ConstructionArm()
    // The SAME instance on both sides: a source struct's identity is its declaration, so a second
    // `Pt` built from the same name is a DIFFERENT type and would be refused — which is the point.
    pt := ConstructionPlainStruct("Pt")
    saved := harness.Ambient.EnterExpectedType(ConstructionClosedBox(pt))
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(ConstructionOneNamed("Item"))))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(pt))
    harness.Ambient.ExitExpectedType(saved)

    assert trace.Codes == ""
}

test "THE FRONT DOOR brackets the value step with the SUBSTITUTED member type and closes it again" {
    harness := ConstructionArm()
    pt := ConstructionPlainStruct("Pt")
    saved := harness.Ambient.EnterExpectedType(ConstructionClosedBox(pt))
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(ConstructionOneNamed("Item"))))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(pt))
    harness.Ambient.ExitExpectedType(saved)

    // `Item: T` on `Box<Pt>` expects `Pt` — the bracket carries the SUBSTITUTED type, not `T`.
    assert trace.ExpectedAtStep == "struct:Pt"
    assert harness.Ambient.CurrentExpectedType == null
}

test "a member the OPEN generic does not declare is reported against the name the developer WROTE" {
    harness := ConstructionArm()
    saved := harness.Ambient.EnterExpectedType(ConstructionClosedBox(ConstructionPlainStruct("Pt")))
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(ConstructionOneNamed("Missing"))))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(ConstructionPlainStruct("Pt")))
    harness.Ambient.ExitExpectedType(saved)

    assert trace.Codes == "303"
    assert trace.Kinds == "1"
}

test "a member the constructed type does NOT have is reported, and the value is still walked" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Box", ConstructionPlainClass("Box"))
    state := harness.Arm.Begin(ConstructionNewOf("Box", ConstructionNoArguments(), ConstructionEntries(ConstructionOneNamed("Missing"))))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))

    assert trace.Codes == "303"
    assert trace.Kinds == "1"
}

test "an UNRESOLVABLE receiver declines the gate rather than guessing, and the value walks UNBRACKETED" {
    harness := ConstructionArm()
    // A target-typed `new` under an `int` annotation: `int` bears no assignable members, so the rule
    // declines before any report and the ambient slot is left exactly as it was.
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.Int)
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(ConstructionOneNamed("Anything"))))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))
    harness.Ambient.ExitExpectedType(saved)

    assert trace.Codes == ""
    assert trace.ExpectedAtStep == "simple:int"
}

// ---- element entries -----------------------------------------------------------------------------

test "an UNNAMED entry is held to the ARRAY target's element type and scolded with the word `array`" {
    harness := ConstructionArm()
    saved := harness.Ambient.EnterExpectedType(new ArrayTypeInfo(BuiltInTypes.Int))
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(ConstructionOneElement())))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))
    harness.Ambient.ExitExpectedType(saved)

    assert trace.Codes == "202"
    assert harness.Errors[0].Message == "Array initializer element is 'string', but the target array expects 'int'"
}

test "an unnamed entry that FITS the element type says nothing, and the bracket carried it" {
    harness := ConstructionArm()
    saved := harness.Ambient.EnterExpectedType(new ArrayTypeInfo(BuiltInTypes.Int))
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), ConstructionEntries(ConstructionOneElement())))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))
    harness.Ambient.ExitExpectedType(saved)

    assert trace.Codes == ""
    assert trace.ExpectedAtStep == "simple:int"
}

test "an INDEXED entry walks its index FIRST and its value second — two steps, one kind" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Box", ConstructionPlainClass("Box"))
    entries := ConstructionNoEntries()
    entries.Add(ConstructionIndexedEntry(ConstructionIntLiteral("0"), ConstructionStringLiteral("x")))
    state := harness.Arm.Begin(ConstructionNewOf("Box", ConstructionNoArguments(), ConstructionEntries(entries)))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Kinds == "11"
    assert trace.Codes == ""
}

test "EVERY initializer entry is walked, in order" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Box", ConstructionPlainClass("Box"))
    entries := ConstructionNoEntries()
    entries.Add(ConstructionElementEntry(ConstructionStringLiteral("a")))
    entries.Add(ConstructionElementEntry(ConstructionStringLiteral("b")))
    entries.Add(ConstructionElementEntry(ConstructionStringLiteral("c")))
    state := harness.Arm.Begin(ConstructionNewOf("Box", ConstructionNoArguments(), ConstructionEntries(entries)))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))

    assert trace.Kinds == "111"
}

// ---- the `with` form -----------------------------------------------------------------------------

test "a `with` walks its TARGET first and answers the target's type" {
    harness := ConstructionArm()
    state := harness.Arm.BeginWith(ConstructionWithOf(ConstructionNoEntries()))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))

    assert trace.Kinds == "1"
    assert trace.Answer == "simple:string"
}

test "a `with` entry whose member RESOLVED goes through kind 2 — the named-expected-type door" {
    harness := ConstructionArm()
    pt := ConstructionPlainStruct("Pt")
    state := harness.Arm.BeginWith(ConstructionWithOf(ConstructionOneNamed("Item")))
    answers := ConstructionAnswerPair(ConstructionClosedBox(pt), pt)
    trace := ConstructionDrive(harness, state, answers)

    // A `with` value can be a lambda, which the owner cannot simulate by writing the ambient slot.
    assert trace.Kinds == "12"
    assert trace.Codes == ""
}

test "THE FRONT DOOR, AGAIN: a `with` value that does not fit its member is REFUSED" {
    harness := ConstructionArm()
    state := harness.Arm.BeginWith(ConstructionWithOf(ConstructionOneNamed("Item")))
    answers := ConstructionAnswerPair(ConstructionClosedBox(ConstructionPlainStruct("Pt")), ConstructionPlainStruct("Rs"))
    trace := ConstructionDrive(harness, state, answers)

    assert trace.Codes == "202"
    assert harness.Errors[0].Message == "'Item' is typed as 'Pt', but the value is 'Rs'"
}

test "a `with` entry whose member did NOT resolve goes through kind 1 and is not accused" {
    harness := ConstructionArm()
    state := harness.Arm.BeginWith(ConstructionWithOf(ConstructionOneNamed("Items")))
    trace := ConstructionDrive(harness, state, ConstructionAnswerPair(BuiltInTypes.Unknown, BuiltInTypes.String))

    assert trace.Kinds == "11"
    assert trace.Codes == ""
}

test "a `with` walks EVERY entry, in order" {
    harness := ConstructionArm()
    entries := ConstructionNoEntries()
    entries.Add(ConstructionNamedEntry("A", ConstructionStringLiteral("x")))
    entries.Add(ConstructionNamedEntry("B", ConstructionStringLiteral("y")))
    entries.Add(ConstructionNamedEntry("C", ConstructionStringLiteral("z")))
    state := harness.Arm.BeginWith(ConstructionWithOf(entries))
    trace := ConstructionDrive(harness, state, ConstructionAnswerPair(BuiltInTypes.Unknown, BuiltInTypes.String))

    assert trace.Kinds == "1111"
}

test "a node that is not a `with` finishes at BeginWith" {
    harness := ConstructionArm()
    state := harness.Arm.BeginWith(new IdentifierExpression("value", 1, 1))

    assert harness.Arm.NextStep(state) == null
    assert ConstructionTypeName(harness.Arm.Result(state)) == "unknown"
}

// ---- the SoA table rules -------------------------------------------------------------------------

test "a SoA table's ONE constructor argument is bracketed to `int`" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    args := ConstructionNoArguments()
    args.Add(ConstructionArgument(ConstructionIntLiteral("4")))
    state := harness.Arm.Begin(ConstructionNewOf("Table", args, null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.ExpectedAtStep == "simple:int"
    assert trace.Codes == ""
}

test "a SoA table constructed with the WRONG argument count is refused, and NEITHER argument is bracketed" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    args := ConstructionNoArguments()
    args.Add(ConstructionArgument(ConstructionIntLiteral("4")))
    args.Add(ConstructionArgument(ConstructionIntLiteral("5")))
    state := harness.Arm.Begin(ConstructionNewOf("Table", args, null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "402"
    assert trace.ExpectedAtStep == "<null>,<null>"
}

test "a SoA table argument named something other than `capacity` is refused" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    args := ConstructionNoArguments()
    args.Add(ConstructionNamedArgument("size", ConstructionIntLiteral("4")))
    state := harness.Arm.Begin(ConstructionNewOf("Table", args, null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "402"
}

test "a SoA table argument named `capacity` is accepted" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    args := ConstructionNoArguments()
    args.Add(ConstructionNamedArgument("capacity", ConstructionIntLiteral("4")))
    state := harness.Arm.Begin(ConstructionNewOf("Table", args, null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == ""
}

test "a SoA table capacity that is not an int is refused" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    args := ConstructionNoArguments()
    args.Add(ConstructionArgument(ConstructionStringLiteral("four")))
    state := harness.Arm.Begin(ConstructionNewOf("Table", args, null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.String))

    assert trace.Codes == "202"
}

test "an UNKNOWN capacity is left alone — it has already been accused elsewhere" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    args := ConstructionNoArguments()
    args.Add(ConstructionArgument(ConstructionStringLiteral("four")))
    state := harness.Arm.Begin(ConstructionNewOf("Table", args, null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Unknown))

    assert trace.Codes == ""
}

test "a SoA table's COLUMN cannot be written by a named initializer entry, and the value still walks" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    entries := ConstructionNoEntries()
    entries.Add(ConstructionNamedEntry("x", ConstructionIntLiteral("1")))
    state := harness.Arm.Begin(ConstructionNewOf("Table", ConstructionCapacity(), ConstructionEntries(entries)))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "103"
    // The capacity and the refused value are BOTH walked: the developer's expression deserves its
    // own analysis even when the entry it belongs to is refused.
    assert trace.Kinds == "11"
}

test "a SoA table's BOOKKEEPING field is refused with the same code and a different suggestion" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    entries := ConstructionNoEntries()
    entries.Add(ConstructionNamedEntry("length", ConstructionIntLiteral("1")))
    state := harness.Arm.Begin(ConstructionNewOf("Table", ConstructionCapacity(), ConstructionEntries(entries)))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "103"
    assert harness.Errors[0].Suggestion == "Use new Table(capacity), add, clear, ensureCapacity, or copyRow so length and capacity stay consistent with the columns."
}

test "a SoA table refuses a COLLECTION initializer entry by shape" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    state := harness.Arm.Begin(ConstructionNewOf("Table", ConstructionCapacity(), ConstructionEntries(ConstructionOneElement())))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "103"
    assert harness.Errors[0].Message == "SoA tables cannot use object-initializer collection initializer entries"
}

test "the SAME shape refusal under `with` names `with` rather than the object initializer" {
    harness := ConstructionArm()
    state := harness.Arm.BeginWith(ConstructionWithOf(ConstructionOneElement()))
    trace := ConstructionDrive(harness, state, ConstructionAnswerPair(ConstructionSoaTable("Table"), BuiltInTypes.Int))

    assert harness.Errors[0].Message == "SoA tables cannot use `with` collection initializer entries"
}

// ---- the uninstantiable forms (NL803) --------------------------------------------------------------
//
// `new Shape()` ON AN `abstract class Shape` WAS ACCEPTED IN SILENCE, AND HAD BEEN SINCE THE CODE WAS
// WRITTEN. The catalog published NL803 and nothing reported it: `nlc check` answered `ok: true` on a
// project that constructs a type with no direct instances. These contracts pin the rule's whole
// surface — the three shapes that have no instance, the shapes that DO, and the two ways the rule
// must not fire.

func ConstructionAbstractClass(name: string): ClassTypeInfo {
    return new ClassTypeInfo(name, 1, 1, false, null, ConstructionEmptyTypeReferences(), ConstructionEmptyTypeParameters(), ConstructionEmptyParameters(), ConstructionEmptyMembers(), ConstructionEmptyNestedTypes(), true, null, true)
}

func ConstructionInterface(name: string): InterfaceTypeInfo {
    return new InterfaceTypeInfo(name, 1, 1, false, ConstructionEmptyTypeReferences(), ConstructionEmptyTypeParameters(), ConstructionEmptyMembers(), ConstructionEmptyNestedTypes())
}

// `typeof` of a STATIC class does not emit in this toolset — it is the `abstract sealed` SHAPE, not
// the assembly — so the CLR type arrives through `Type.GetType`, which is the estate's door. The
// names must be CORE-LIBRARY names: `System.Console` lives in its own assembly and `Type.GetType`
// answers null for it without an assembly qualifier, so `System.Math` is the static class used here.
func ConstructionClrType(metadataName: string): ReflectionTypeInfo {
    resolved := Type.GetType(metadataName)
    if resolved == null {
        throw new InvalidOperationException("Could not resolve '" + metadataName + "'.")
    }

    return new ReflectionTypeInfo(resolved)
}

func ConstructionAbstractOpenHolder(): ClassTypeInfo {
    typeParameters := new TypeParameter[](1)
    typeParameters[0] = new TypeParameter("T")
    return new ClassTypeInfo("Holder", 1, 1, false, null, ConstructionEmptyTypeReferences(), typeParameters, ConstructionEmptyParameters(), ConstructionEmptyMembers(), ConstructionEmptyNestedTypes(), true, null, true)
}

test "`new` on an ABSTRACT CLASS is refused, anchored on the written type name" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Shape", ConstructionAbstractClass("Shape"))
    state := harness.Arm.Begin(ConstructionNewOf("Shape", ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "803"
    assert harness.Errors[0].Message == "Cannot create an instance of abstract class 'Shape'"
    // The squiggle sits under `Shape`, not under the whole `new` expression: the type reference is at
    // (4,5) and the `new` keyword at (4,1).
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 5
}

test "the abstract-class way out is a CONCRETE SUBCLASS, spelled so the reader can paste it" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Shape", ConstructionAbstractClass("Shape"))
    state := harness.Arm.Begin(ConstructionNewOf("Shape", ConstructionNoArguments(), null))
    ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert harness.Errors[0].Suggestion == "Construct a concrete subclass — `class ConcreteShape : Shape { ... }` — and write `new ConcreteShape()` here, or remove `abstract` from `Shape` if it is meant to be constructed directly."
}

test "`new` on an INTERFACE is refused and named as an interface" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Greeter", ConstructionInterface("Greeter"))
    state := harness.Arm.Begin(ConstructionNewOf("Greeter", ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "803"
    assert harness.Errors[0].Message == "Cannot create an instance of interface 'Greeter'"
    assert harness.Errors[0].Suggestion == "Construct a class that implements it — `class MyGreeter : Greeter { ... }` — and write `new MyGreeter()` here."
}

test "`new` on an EXTERNAL abstract class is refused with the same sentence" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Stream", ConstructionClrType("System.IO.Stream"))
    state := harness.Arm.Begin(ConstructionNewOf("Stream", ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "803"
    assert harness.Errors[0].Message == "Cannot create an instance of abstract class 'Stream'"
}

// A STATIC CLASS IS `abstract sealed` IN METADATA AND THE READER NEVER WROTE EITHER WORD. Telling
// them `Console` is abstract would be true of the metadata and useless to them, so the arm is split
// and the suggestion is the member call they meant.
test "`new` on an EXTERNAL STATIC class is refused as a static class, not as an abstract one" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Math", ConstructionClrType("System.Math"))
    state := harness.Arm.Begin(ConstructionNewOf("Math", ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "803"
    assert harness.Errors[0].Message == "Cannot create an instance of static class 'Math'"
    assert harness.Errors[0].Suggestion == "`Math` is a static class and has no instances. Call its members directly, as `Math.Member(...)`."
}

test "`new` on an EXTERNAL INTERFACE is refused as an interface" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("IDisposable", ConstructionClrType("System.IDisposable"))
    state := harness.Arm.Begin(ConstructionNewOf("IDisposable", ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "803"
    assert harness.Errors[0].Message == "Cannot create an instance of interface 'IDisposable'"
}

// A CLOSED GENERIC IS OPENED FIRST: `Holder<string>` is instantiable exactly when `Holder<T>` is, and
// the name the reader wrote is the one the report names.
test "a CLOSED GENERIC over an abstract definition is refused, naming what was written" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Holder", ConstructionAbstractOpenHolder())
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("string", 4, 12))
    generic: TypeReference = new GenericTypeReference("Holder", arguments, 4, 5)
    state := harness.Arm.Begin(new NewExpression(generic, ConstructionNoArguments(), null, 4, 1))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "803"
    assert harness.Errors[0].Message == "Cannot create an instance of abstract class 'Holder'"
    assert harness.Errors[0].Column == 5
}

// ---- and the shapes the rule must leave alone ------------------------------------------------------

test "a CONCRETE class is silent" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Circle", ConstructionPlainClass("Circle"))
    state := harness.Arm.Begin(ConstructionNewOf("Circle", ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == ""
    assert trace.Answer == "class:Circle"
}

// AN ARRAY IS NOT AN INSTANCE OF ITS ELEMENT TYPE. `new Shape[](4)` makes four empty slots, which is
// legal over any element type at all, so the written length ends the question before it is asked.
test "a SIZED ARRAY over an abstract element type is silent" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Shape", ConstructionAbstractClass("Shape"))
    state := harness.Arm.Begin(ConstructionSizedArray("Shape", ConstructionIntLiteral("4"), ConstructionNoArguments()))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == ""
}

test "an EXTERNAL CONCRETE class is silent" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("MemoryStream", ConstructionClrType("System.IO.MemoryStream"))
    state := harness.Arm.Begin(ConstructionNewOf("MemoryStream", ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == ""
}

// A TARGET-TYPED `new` HAS NO WRITTEN TYPE REFERENCE AND IS NOT THIS RULE'S BUSINESS: the type it
// adopts came from a slot that some other declaration already vouched for.
test "a TARGET-TYPED `new` is not put through this rule" {
    harness := ConstructionArm()
    saved := harness.Ambient.EnterExpectedType(ConstructionAbstractClass("Shape"))
    state := harness.Arm.Begin(ConstructionNewOf(null, ConstructionNoArguments(), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))
    harness.Ambient.ExitExpectedType(saved)

    assert trace.Codes == ""
}

// ---- the constructor arity rule (NL806) ------------------------------------------------------------
//
// `new Point(1, 2)` OVER `class Point { constructor(x: int) }` REACHED THE EMITTER AND DIED THERE as
// an `NL103` decline naming a `return expression`. The plainest constructor mistake there is — the
// wrong number of arguments — was answered by a sentence about the columnar backend, and NL806 had
// been in the catalog the whole time with nothing reporting it.

func ConstructionConstructorMember(owner: string, parameterNames: string[], parameterTypes: TypeReference[], requiredParameterCount: int, hasParamsParameter: bool): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        ".ctor",
        owner,
        DeclaredMemberKind.Constructor,
        "constructor",
        null,
        false,
        false,
        false,
        true,
        parameterNames.Length,
        parameterNames,
        parameterTypes,
        new ParameterModifier[](0),
        requiredParameterCount,
        hasParamsParameter,
        false,
        null,
        0,
        ConstructionEmptyTypeParameters(),
        new GenericConstraint[](0),
        0,
        false,
        false,
        false,
        false,
        "",
        false,
        false,
        1,
        1
    )
}

func ConstructionParameterNames(first: string): string[] {
    names := new string[](1)
    names[0] = first
    return names
}

func ConstructionParameterNames2(first: string, second: string): string[] {
    names := new string[](2)
    names[0] = first
    names[1] = second
    return names
}

// A DERIVED VALUE DOES NOT WIDEN INTO A BASE-TYPED SLOT: a `SimpleTypeReference` written straight
// into a `TypeReference[]` element declines at `emit.statement.block-child`. Each one is bound to a
// `TypeReference`-typed local first, which is the estate's established idiom.
func ConstructionParameterTypes(first: string): TypeReference[] {
    types := new TypeReference[](1)
    firstType: TypeReference = new SimpleTypeReference(first, 1, 1)
    types[0] = firstType
    return types
}

func ConstructionParameterTypes2(first: string, second: string): TypeReference[] {
    types := new TypeReference[](2)
    firstType: TypeReference = new SimpleTypeReference(first, 1, 1)
    secondType: TypeReference = new SimpleTypeReference(second, 1, 1)
    types[0] = firstType
    types[1] = secondType
    return types
}

func ConstructionClassWithConstructors(name: string, constructors: List<DeclaredMemberInfo>): ClassTypeInfo {
    members := new DeclaredMemberInfo[](constructors.Count)
    index := 0
    while index < constructors.Count {
        members[index] = constructors[index]
        index = index + 1
    }

    return new ClassTypeInfo(name, 1, 1, false, null, ConstructionEmptyTypeReferences(), ConstructionEmptyTypeParameters(), ConstructionEmptyParameters(), members, ConstructionEmptyNestedTypes(), constructors.Count == 0)
}

func ConstructionOneConstructor(member: DeclaredMemberInfo): List<DeclaredMemberInfo> {
    members := new List<DeclaredMemberInfo>()
    members.Add(member)
    return members
}

func ConstructionArgumentsOf(count: int): List<Argument> {
    args := ConstructionNoArguments()
    index := 0
    while index < count {
        args.Add(ConstructionArgument(ConstructionIntLiteral("1")))
        index = index + 1
    }

    return args
}

test "a call that fits NO declared constructor is refused, naming the one that exists" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Point", ConstructionClassWithConstructors("Point", ConstructionOneConstructor(ConstructionConstructorMember("Point", ConstructionParameterNames("x"), ConstructionParameterTypes("int"), 1, false))))
    state := harness.Arm.Begin(ConstructionNewOf("Point", ConstructionArgumentsOf(2), null))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == "806"
    assert harness.Errors[0].Message == "'Point' has no constructor taking 2 arguments"
    assert harness.Errors[0].Suggestion == "'Point' declares one constructor: `constructor(x: int)`. Match it, or add a constructor taking 2 arguments."
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 5
}

test "a class that declares NO constructor has exactly one, taking nothing" {
    refused := ConstructionArm()
    refused.Scopes.DeclareNestedTypeIfAbsent("Empty", ConstructionPlainClass("Empty"))
    refusedState := refused.Arm.Begin(ConstructionNewOf("Empty", ConstructionArgumentsOf(1), null))
    refusedTrace := ConstructionDrive(refused, refusedState, ConstructionAnswers(BuiltInTypes.Int))

    assert refusedTrace.Codes == "806"
    assert refused.Errors[0].Message == "'Empty' declares no constructor, so it takes no arguments — 1 argument passed"
    assert refused.Errors[0].Suggestion == "Write `new Empty()`, or declare `constructor(...)` on 'Empty' if it is meant to take arguments."

    // And the parameterless call it DOES have is silent.
    accepted := ConstructionArm()
    accepted.Scopes.DeclareNestedTypeIfAbsent("Empty", ConstructionPlainClass("Empty"))
    acceptedState := accepted.Arm.Begin(ConstructionNewOf("Empty", ConstructionNoArguments(), null))
    assert ConstructionDrive(accepted, acceptedState, ConstructionAnswers(BuiltInTypes.Int)).Codes == ""
}

test "OVERLOADS are checked as a set: a call fits if it fits ANY of them" {
    constructors := new List<DeclaredMemberInfo>()
    constructors.Add(ConstructionConstructorMember("Point", new string[](0), ConstructionEmptyTypeReferences(), 0, false))
    constructors.Add(ConstructionConstructorMember("Point", ConstructionParameterNames2("x", "y"), ConstructionParameterTypes2("int", "int"), 2, false))

    zero := ConstructionArm()
    zero.Scopes.DeclareNestedTypeIfAbsent("Point", ConstructionClassWithConstructors("Point", constructors))
    assert ConstructionDrive(zero, zero.Arm.Begin(ConstructionNewOf("Point", ConstructionNoArguments(), null)), ConstructionAnswers(BuiltInTypes.Int)).Codes == ""

    two := ConstructionArm()
    two.Scopes.DeclareNestedTypeIfAbsent("Point", ConstructionClassWithConstructors("Point", constructors))
    assert ConstructionDrive(two, two.Arm.Begin(ConstructionNewOf("Point", ConstructionArgumentsOf(2), null)), ConstructionAnswers(BuiltInTypes.Int)).Codes == ""

    // ONE argument fits neither, and the suggestion lists BOTH so the reader compares rather than hunts.
    one := ConstructionArm()
    one.Scopes.DeclareNestedTypeIfAbsent("Point", ConstructionClassWithConstructors("Point", constructors))
    oneTrace := ConstructionDrive(one, one.Arm.Begin(ConstructionNewOf("Point", ConstructionArgumentsOf(1), null)), ConstructionAnswers(BuiltInTypes.Int))
    assert oneTrace.Codes == "806"
    assert one.Errors[0].Message == "'Point' has no constructor taking 1 argument"
    assert one.Errors[0].Suggestion == "'Point' declares 2 constructors: `constructor()`, `constructor(x: int, y: int)`. Match one of them, or add a constructor taking 1 argument."
}

// A DEFAULTED PARAMETER IS A RANGE, NOT A COUNT, and `params` has no upper bound at all. Both are
// read off the model the declaration factory already fills, so neither needs a second walk.
test "the accepted range runs from REQUIRED to WRITTEN, and `params` removes the ceiling" {
    defaulted := ConstructionOneConstructor(ConstructionConstructorMember("Greeting", ConstructionParameterNames("text"), ConstructionParameterTypes("string"), 0, false))
    assert AnalyzerConstruction.AcceptsConstructorArity(defaulted, 0)
    assert AnalyzerConstruction.AcceptsConstructorArity(defaulted, 1)
    assert !AnalyzerConstruction.AcceptsConstructorArity(defaulted, 2)

    variadic := ConstructionOneConstructor(ConstructionConstructorMember("Log", ConstructionParameterNames("parts"), ConstructionParameterTypes("string[]"), 1, true))
    assert !AnalyzerConstruction.AcceptsConstructorArity(variadic, 0)
    assert AnalyzerConstruction.AcceptsConstructorArity(variadic, 1)
    assert AnalyzerConstruction.AcceptsConstructorArity(variadic, 9)

    // An EMPTY set is the implicit parameterless constructor, not "anything goes".
    empty := new List<DeclaredMemberInfo>()
    assert AnalyzerConstruction.AcceptsConstructorArity(empty, 0)
    assert !AnalyzerConstruction.AcceptsConstructorArity(empty, 1)

    // The singular is not a truncated plural.
    assert AnalyzerConstruction.ArgumentWord(0) == "0 arguments"
    assert AnalyzerConstruction.ArgumentWord(1) == "1 argument"
    assert AnalyzerConstruction.ArgumentWord(2) == "2 arguments"
}

// ---- and the five shapes the arity rule is not asked about -----------------------------------------

test "a CLOSED GENERIC is opened, so its definition's constructors are the ones checked" {
    open := ConstructionOpenBox()
    closed := ConstructionClosedBox(BuiltInTypes.String)

    // `Box<T>` as built by the harness declares one field and NO constructor, so exactly the
    // parameterless call fits — through the wrapper, not around it.
    refused := ConstructionArm()
    refused.Scopes.DeclareNestedTypeIfAbsent("Box", open)
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("string", 4, 12))
    generic: TypeReference = new GenericTypeReference("Box", arguments, 4, 5)
    refusedTrace := ConstructionDrive(refused, refused.Arm.Begin(new NewExpression(generic, ConstructionArgumentsOf(1), null, 4, 1)), ConstructionAnswers(BuiltInTypes.Int))
    assert refusedTrace.Codes == "806"
    assert refused.Errors[0].Message == "'Box' declares no constructor, so it takes no arguments — 1 argument passed"

    // A wrapper with NO definition answers "cannot tell" and is left alone by construction.
    assert ConstructionTypeName(closed) == "generic:Box<simple:string>"
}

test "a SIZED ARRAY calls no constructor and is not asked" {
    harness := ConstructionArm()
    harness.Scopes.DeclareNestedTypeIfAbsent("Point", ConstructionClassWithConstructors("Point", ConstructionOneConstructor(ConstructionConstructorMember("Point", ConstructionParameterNames("x"), ConstructionParameterTypes("int"), 1, false))))
    state := harness.Arm.Begin(ConstructionSizedArray("Point", ConstructionIntLiteral("4"), ConstructionNoArguments()))
    trace := ConstructionDrive(harness, state, ConstructionAnswers(BuiltInTypes.Int))

    assert trace.Codes == ""
}

test "a UNION CASE owns its own arity and a SoA TABLE owns its capacity" {
    unionHarness := ConstructionArm()
    caseNames := new List<string>()
    caseNames.Add("Success")
    unionHarness.Scopes.DeclareNestedTypeIfAbsent("Result", ConstructionUnion("Result", caseNames, null))
    unionTrace := ConstructionDrive(unionHarness, unionHarness.Arm.Begin(ConstructionQualifiedNew("Result.Success")), ConstructionAnswers(BuiltInTypes.Int))
    assert unionTrace.Codes == ""

    // The SoA table's ONE capacity argument is `NL321`'s, and adding this rule must not double it.
    soaHarness := ConstructionArm()
    soaHarness.Scopes.DeclareNestedTypeIfAbsent("Table", ConstructionSoaTable("Table"))
    soaTrace := ConstructionDrive(soaHarness, soaHarness.Arm.Begin(ConstructionNewOf("Table", ConstructionCapacity(), null)), ConstructionAnswers(BuiltInTypes.Int))
    assert soaTrace.Codes == ""
}

// AN EXTERNAL TYPE'S CONSTRUCTOR SET IS THE OVERLOAD RESOLVER'S, NOT THIS WALK'S, and a class with a
// PRIMARY CONSTRUCTOR is silent on purpose: `ParameterDeclarationInfo` does not carry parameter
// DEFAULTS, so its legal arity is a range this walk cannot compute, and reporting from half the model
// would accuse correct programs.
test "an EXTERNAL type and a PRIMARY-CONSTRUCTOR class are both left alone" {
    externalHarness := ConstructionArm()
    externalHarness.Scopes.DeclareNestedTypeIfAbsent("MemoryStream", ConstructionClrType("System.IO.MemoryStream"))
    assert ConstructionDrive(externalHarness, externalHarness.Arm.Begin(ConstructionNewOf("MemoryStream", ConstructionArgumentsOf(3), null)), ConstructionAnswers(BuiltInTypes.Int)).Codes == ""

    primaryParameters := new ParameterDeclarationInfo[](1)
    primaryType: TypeReference = new SimpleTypeReference("int", 1, 1)
    primaryParameters[0] = new ParameterDeclarationInfo("x", primaryType, 1, 1)
    primaryHarness := ConstructionArm()
    primaryHarness.Scopes.DeclareNestedTypeIfAbsent("Point", new ClassTypeInfo("Point", 1, 1, false, null, ConstructionEmptyTypeReferences(), ConstructionEmptyTypeParameters(), primaryParameters, ConstructionEmptyMembers(), ConstructionEmptyNestedTypes(), false))
    assert ConstructionDrive(primaryHarness, primaryHarness.Arm.Begin(ConstructionNewOf("Point", ConstructionArgumentsOf(4), null)), ConstructionAnswers(BuiltInTypes.Int)).Codes == ""
}
