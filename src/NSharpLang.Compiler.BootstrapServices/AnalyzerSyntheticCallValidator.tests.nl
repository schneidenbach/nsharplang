namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the SYNTHETIC CALL'S VALIDATOR — the arity, argument-type, generic-constraint,
// no-matching-overload and SoA-intrinsic reports the analyzer makes about a call to an N#-declared
// function, plus the expected-type and return-type questions on either side of them.
//
// All seventeen members behind these were `private` in Analyzer.cs, so nothing in `src/` or `tests/`
// named any of them and the only pinning they ever had was end-to-end diagnostic text. These go at
// the decisions a reader cannot recover from a single arm:
//
//   * REPORT ORDER inside one call is a rule, not an accident: constraints first, then arity (which
//     RETURNS), then placement, then argument types in ARGUMENT order, then the SoA checks;
//   * the rich `ErrorMessageBuilder` shape and the detail-only shape are the SAME report in the SAME
//     position — the choice is made by what the sink can supply, and NL202 additionally needs the
//     parameter's NAME;
//   * the arity report names the REQUIRED count when there are too few and the EXPECTED count when
//     there are too many, and renders a BAND when the two differ;
//   * a params position compares ELEMENT to ELEMENT unless the caller passed the array itself;
//   * a single trailing array literal deliberately has NO expected type;
//   * the `new()` constraint is about the KIND of type, and a record CLASS with primary-constructor
//     parameters is the only shape that loses it;
//   * an unbound type parameter is skipped rather than reported;
//   * the candidate list is capped at eight DISTINCT signatures;
//   * `-0` is not a negative constant, and a cast is transparent to the sign question only when its
//     target is a SIGNED integer type — including through a declared alias.

func ValidatorErrors(): List<CompilerError> {
    return new List<CompilerError>()
}

func ValidatorScopes(): AnalyzerScopeStack {
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    return scopes
}

func ValidatorConstants(scopes: AnalyzerScopeStack): AnalyzerConstantExpressionFacts {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    return new AnalyzerConstantExpressionFacts(scopes, context)
}

func ValidatorOwner(errors: List<CompilerError>): AnalyzerSyntheticCallValidator {
    return ValidatorOwnerWithText(errors, null)
}

// The SAME owner over a sink that has a file path and a line of source text, which is what makes
// the RICH `ErrorMessageBuilder` shape reachable. Both shapes are pinned, because the choice
// between them is made by what the sink can supply and not by the report.
func ValidatorOwnerWithText(
    errors: List<CompilerError>, sourceText: string?): AnalyzerSyntheticCallValidator {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := ValidatorScopes()
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    sink := new AnalyzerDiagnosticSink(errors, provider)
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        sink,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        new SemanticModel(),
        new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    scoring := new AnalyzerOverloadScoring(context, clrConversion, assignability, resolver, null)
    binder := new AnalyzerSyntheticCallBinder(context, scoring, assignability, clrConversion)
    spans := new AnalyzerDiagnosticSpans(sink)
    reporter := new AnalyzerSyntheticCallReporter(sink, spans)
    walk := new AnalyzerSyntheticCallWalk(
        resolver, binder, reporter, scoring, assignability, spans, sink)
    constants := new AnalyzerConstantExpressionFacts(scopes, context)
    if sourceText != null {
        sink.BeginAnalysis("probe.nl", sourceText)
    }

    return new AnalyzerSyntheticCallValidator(
        context, resolver, assignability, scoring, walk, reporter, spans, sink, constants)
}

// ------------------------------------------------------------------ signature and call shapes

func VNames(count: int): List<string> {
    names := new List<string>()
    index := 0
    while index < count {
        ordinal := index + 1
        names.Add("p" + ordinal.ToString())
        index = index + 1
    }

    return names
}

func VModifiers(count: int): List<ParameterModifier> {
    modifiers := new List<ParameterModifier>()
    index := 0
    while index < count {
        modifiers.Add(ParameterModifier.None)
        index = index + 1
    }

    return modifiers
}

func VTypes1(first: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    return types
}

func VTypes2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    types.Add(second)
    return types
}

func VRefs0(): List<TypeReference> {
    return new List<TypeReference>()
}

func VRefs1(first: TypeReference): List<TypeReference> {
    references := VRefs0()
    references.Add(first)
    return references
}

func VRefs2(first: TypeReference, second: TypeReference): List<TypeReference> {
    references := VRefs0()
    references.Add(first)
    references.Add(second)
    return references
}

func VSignature(parameterTypes: List<TypeInfo>): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SyntheticName = "f"
    signature.ParameterNames = VNames(parameterTypes.Count)
    signature.ParameterTypes = parameterTypes
    signature.ParameterModifiers = VModifiers(parameterTypes.Count)
    signature.ReturnType = BuiltInTypes.Void
    return signature
}

func VRequire(signature: FunctionTypeInfo, requiredCount: int): FunctionTypeInfo {
    nullableCount: int? = requiredCount
    signature.RequiredParameterCount = nullableCount
    return signature
}

func VIdentifier(name: string): Expression {
    return new IdentifierExpression(name, 1, 1)
}

func VPositional(value: Expression): Argument {
    return new Argument(null, value, ArgumentModifier.None)
}

func VArgs0(): List<Argument> {
    return new List<Argument>()
}

func VArgs1(first: Expression): List<Argument> {
    arguments := VArgs0()
    arguments.Add(VPositional(first))
    return arguments
}

func VArgs2(first: Expression, second: Expression): List<Argument> {
    arguments := VArgs1(first)
    arguments.Add(VPositional(second))
    return arguments
}

// `f(params p1: int[])` — the tail modifier is what makes the position a params tail at all.
func VParamsSignature(): FunctionTypeInfo {
    signature := VSignature(VTypes1(new ArrayTypeInfo(BuiltInTypes.Int)))
    modifiers := new List<ParameterModifier>()
    modifiers.Add(ParameterModifier.Params)
    signature.ParameterModifiers = modifiers
    signature.HasParamsParameter = true
    signature.SourceParameterTypes = VRefs1(
        new ArrayTypeReference(new SimpleTypeReference("int")))
    return signature
}

func VCall(arguments: List<Argument>): CallExpression {
    return new CallExpression(VIdentifier("f"), arguments, null, 1, 1)
}

func VCandidates1(first: FunctionTypeInfo): List<FunctionTypeInfo> {
    candidates := new List<FunctionTypeInfo>()
    candidates.Add(first)
    return candidates
}

func VCandidates2(first: FunctionTypeInfo, second: FunctionTypeInfo): List<FunctionTypeInfo> {
    candidates := VCandidates1(first)
    candidates.Add(second)
    return candidates
}

func VConstraint(
    typeParameter: string,
    constraints: List<TypeReference>,
    special: SpecialConstraintKind): List<GenericConstraint> {
    list := new List<GenericConstraint>()
    list.Add(new GenericConstraint(typeParameter, constraints, special))
    return list
}

func VTypeParameters(name: string): List<TypeParameter> {
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter(name))
    return parameters
}

func VBindings(name: string, bound: TypeInfo): Dictionary<string, TypeInfo> {
    bindings := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    bindings[name] = bound
    return bindings
}

// The generic signature every constraint contract is written against: `f<T>(p1: T)`.
func VGenericSignature(constraints: List<GenericConstraint>): FunctionTypeInfo {
    signature := VSignature(VTypes1(new SimpleTypeInfo("T")))
    signature.SourceParameterTypes = VRefs1(new SimpleTypeReference("T"))
    signature.TypeParameters = VTypeParameters("T")
    signature.GenericConstraints = constraints
    return signature
}

func VCodes(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + ","
        }

        text = text + errors[index].DiagnosticId
        index = index + 1
    }

    return text
}

func VMessages(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + " | "
        }

        text = text + errors[index].Message
        index = index + 1
    }

    return text
}

func VTypeText(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    candidateObject := candidate as object
    rendered := candidateObject.ToString()
    if rendered == null {
        return "<null-text>"
    }

    return rendered
}

// ------------------------------------------------------------------ argument count

test "too FEW arguments names the REQUIRED count and too many names the EXPECTED count" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    VRequire(signature, 1)

    owner.ValidateCall(signature, VCall(VArgs0()), new List<TypeInfo>(), null)
    assert errors.Count == 1
    assert errors[0].DiagnosticId == "NL401"
    // The BAND is rendered because required and expected differ.
    assert errors[0].Message.Contains("1 to 2")

    errors.Clear()
    tooMany := VArgs2(VIdentifier("a"), VIdentifier("b"))
    tooMany.Add(VPositional(VIdentifier("c")))
    tooManyTypes := VTypes2(BuiltInTypes.Int, BuiltInTypes.String)
    tooManyTypes.Add(BuiltInTypes.Int)
    owner.ValidateCall(signature, VCall(tooMany), tooManyTypes, null)
    assert errors.Count == 1
    assert errors[0].DiagnosticId == "NL401"
}

test "a signature with no optional parameters renders a single expected count, not a band" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes2(BuiltInTypes.Int, BuiltInTypes.String))

    owner.ValidateCall(signature, VCall(VArgs0()), new List<TypeInfo>(), null)
    assert errors.Count == 1
    assert errors[0].Message.Contains("takes 2 argument(s)")
    assert !errors[0].Message.Contains(" to ")
}

test "the arity report RETURNS — a call that does not fit is not also type-checked" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes2(BuiltInTypes.Int, BuiltInTypes.Int))

    // One argument of the WRONG type against a two-parameter signature: only the arity fires.
    owner.ValidateCall(
        signature, VCall(VArgs1(VIdentifier("a"))), VTypes1(BuiltInTypes.String), null)
    assert VCodes(errors) == "NL401"
}

// ------------------------------------------------------------------ argument types

test "argument types are checked in ARGUMENT order, one report each" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes2(BuiltInTypes.Int, BuiltInTypes.Int))

    owner.ValidateCall(
        signature,
        VCall(VArgs2(VIdentifier("a"), VIdentifier("b"))),
        VTypes2(BuiltInTypes.String, BuiltInTypes.String),
        null)
    assert VCodes(errors) == "NL202,NL202"
    assert errors[0].Message.Contains("p1")
    assert errors[1].Message.Contains("p2")
}

test "an UNKNOWN on either side is skipped rather than reported" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes2(BuiltInTypes.Int, BuiltInTypes.Unknown))

    owner.ValidateCall(
        signature,
        VCall(VArgs2(VIdentifier("a"), VIdentifier("b"))),
        VTypes2(BuiltInTypes.Unknown, BuiltInTypes.String),
        null)
    assert errors.Count == 0
}

test "the detail-only NL202 names the argument by POSITION, or by NAME when the caller wrote one" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(BuiltInTypes.Int))

    owner.ValidateCall(
        signature, VCall(VArgs1(VIdentifier("a"))), VTypes1(BuiltInTypes.String), null)
    assert errors.Count == 1
    assert errors[0].Message.Contains("Argument 1")

    errors.Clear()
    named := VArgs0()
    named.Add(new Argument("p1", VIdentifier("a"), ArgumentModifier.None))
    owner.ValidateCall(signature, VCall(named), VTypes1(BuiltInTypes.String), null)
    assert errors.Count == 1
    assert errors[0].Message.Contains("Argument 'p1'")
}

test "a signature with NO parameter names still reports, through the detail-only shape" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(BuiltInTypes.Int))
    signature.ParameterNames = null

    owner.ValidateCall(
        signature, VCall(VArgs1(VIdentifier("a"))), VTypes1(BuiltInTypes.String), null)
    assert errors.Count == 1
    assert errors[0].DiagnosticId == "NL202"
    assert errors[0].Message.Contains("this parameter expects")
}

// ------------------------------------------------------------------ the params tail

test "a params tail compares ELEMENT to ELEMENT" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VParamsSignature()
    VRequire(signature, 0)

    // A loose STRING argument against `params p1: int[]` is an element mismatch.
    owner.ValidateCall(
        signature, VCall(VArgs1(VIdentifier("a"))), VTypes1(BuiltInTypes.String), null)
    assert VCodes(errors) == "NL202"

    // A loose INT argument is the element type and passes.
    errors.Clear()
    owner.ValidateCall(
        signature, VCall(VArgs1(VIdentifier("a"))), VTypes1(BuiltInTypes.Int), null)
    assert errors.Count == 0

    // The params ARRAY itself passes too — that is the direct-array arm.
    errors.Clear()
    owner.ValidateCall(
        signature,
        VCall(VArgs1(VIdentifier("a"))),
        VTypes1(new ArrayTypeInfo(BuiltInTypes.Int)),
        null)
    assert errors.Count == 0
}

test "the expected type of a params position is its ELEMENT, and NOTHING for a lone array literal" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VParamsSignature()

    plain := VCall(VArgs1(VIdentifier("a")))
    assert VTypeText(owner.GetExpectedArgumentType(signature, plain, 0, 0, null)) == "int"

    // A SINGLE trailing array literal is ambiguous — the params array itself, or one element — so
    // the position deliberately answers nothing and lets validation see the value.
    literal := VCall(VArgs1(new ArrayLiteralExpression(new List<Expression>(), false, 1, 1)))
    assert owner.GetExpectedArgumentType(signature, literal, 0, 0, null) == null
}

test "an out-of-range parameter index has no expected type" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(BuiltInTypes.Int))
    call := VCall(VArgs1(VIdentifier("a")))

    assert owner.GetExpectedArgumentType(signature, call, 0, -1, null) == null
    assert owner.GetExpectedArgumentType(signature, call, 0, 1, null) == null
    assert VTypeText(owner.GetExpectedArgumentType(signature, call, 0, 0, null)) == "int"
}

test "the expected type is CLOSED over the call's generic bindings" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(new SimpleTypeInfo("T")))
    call := VCall(VArgs1(VIdentifier("a")))

    assert VTypeText(owner.GetExpectedArgumentType(signature, call, 0, 0, null)) == "T"
    assert VTypeText(owner.GetExpectedArgumentType(
        signature, call, 0, 0, VBindings("T", BuiltInTypes.String))) == "string"
}

test "a ref parameter's expected type is by-REF" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(BuiltInTypes.Int))
    modifiers := new List<ParameterModifier>()
    modifiers.Add(ParameterModifier.Ref)
    signature.ParameterModifiers = modifiers

    call := VCall(VArgs1(VIdentifier("a")))
    assert VTypeText(owner.GetExpectedArgumentType(signature, call, 0, 0, null)) == "&int"
}

// ------------------------------------------------------------------ generic constraints

test "the `class` constraint reports a value type and accepts a reference type" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VGenericSignature(VConstraint("T", VRefs0(), SpecialConstraintKind.Class))

    owner.ValidateGenericConstraints(
        signature, VCall(VArgs1(VIdentifier("a"))), VBindings("T", BuiltInTypes.Int))
    assert VCodes(errors) == "NL208"
    assert errors[0].Message.Contains("is a value type")

    errors.Clear()
    owner.ValidateGenericConstraints(
        signature, VCall(VArgs1(VIdentifier("a"))), VBindings("T", BuiltInTypes.String))
    assert errors.Count == 0
}

test "the `struct` constraint rejects a reference type AND a nullable value type" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VGenericSignature(VConstraint("T", VRefs0(), SpecialConstraintKind.Struct))
    call := VCall(VArgs1(VIdentifier("a")))

    owner.ValidateGenericConstraints(signature, call, VBindings("T", BuiltInTypes.String))
    assert VCodes(errors) == "NL208"

    errors.Clear()
    owner.ValidateGenericConstraints(
        signature, call, VBindings("T", new NullableTypeInfo(BuiltInTypes.Int)))
    assert VCodes(errors) == "NL208"
    assert errors[0].Message.Contains("not a non-nullable value type")

    errors.Clear()
    owner.ValidateGenericConstraints(signature, call, VBindings("T", BuiltInTypes.Int))
    assert errors.Count == 0
}

test "a type parameter NOTHING bound is skipped, not reported" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VGenericSignature(VConstraint("T", VRefs0(), SpecialConstraintKind.Class))
    call := VCall(VArgs1(VIdentifier("a")))

    // A binding for a DIFFERENT parameter leaves T open.
    owner.ValidateGenericConstraints(signature, call, VBindings("U", BuiltInTypes.Int))
    assert errors.Count == 0

    // So does an empty binding set, and so does none at all.
    owner.ValidateGenericConstraints(signature, call, new Dictionary<string, TypeInfo>())
    owner.ValidateGenericConstraints(signature, call, null)
    assert errors.Count == 0
}

test "every violated arm of one constraint reports independently, in declaration order" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    combined := Convert.ToInt32(SpecialConstraintKind.Class)
        | Convert.ToInt32(SpecialConstraintKind.New)
    both := (SpecialConstraintKind)combined
    signature := VGenericSignature(VConstraint("T", VRefs0(), both))

    // A record CLASS with primary-constructor parameters is a reference type (class arm passes)
    // with no parameterless constructor (new() arm fires).
    violating := new RecordTypeInfo(
        "Pt",
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](1),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
    violating.PrimaryConstructorParameters[0] = new ParameterDeclarationInfo(
        "x", new SimpleTypeReference("int"), 1, 1)

    owner.ValidateGenericConstraints(
        signature, VCall(VArgs1(VIdentifier("a"))), VBindings("T", violating))
    assert VCodes(errors) == "NL208"
    assert errors[0].Message.Contains("no parameterless constructor")
}

test "a constraint TYPE the bound type does not satisfy reports, and the report is closed" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VGenericSignature(
        VConstraint("T", VRefs1(new SimpleTypeReference("string")), SpecialConstraintKind.None))

    owner.ValidateGenericConstraints(
        signature, VCall(VArgs1(VIdentifier("a"))), VBindings("T", BuiltInTypes.Int))
    assert VCodes(errors) == "NL208"
    assert errors[0].Message.Contains("does not implement `string`")

    errors.Clear()
    owner.ValidateGenericConstraints(
        signature, VCall(VArgs1(VIdentifier("a"))), VBindings("T", BuiltInTypes.String))
    assert errors.Count == 0
}

test "the DECLARATION'S resolved constraint types win over the written references" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VGenericSignature(
        VConstraint("T", VRefs1(new SimpleTypeReference("Missing")), SpecialConstraintKind.None))
    resolved := new Dictionary<string, List<TypeInfo> >(StringComparer.Ordinal)
    resolved["T"] = VTypes1(BuiltInTypes.String)
    signature.ResolvedGenericConstraintTypes = resolved

    // `Missing` never resolves, but the declaration recorded `string`, so THAT is what checks.
    owner.ValidateGenericConstraints(
        signature, VCall(VArgs1(VIdentifier("a"))), VBindings("T", BuiltInTypes.Int))
    assert VCodes(errors) == "NL208"
    assert errors[0].Message.Contains("does not implement `string`")
}

// ------------------------------------------------------------------ the new() constraint

test "every value type satisfies new(), and a record CLASS with primary parameters is the one that does not" {
    structType := new StructTypeInfo(
        "Sz",
        1,
        1,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
    assert AnalyzerSyntheticCallValidator.HasParameterlessConstructor(structType)

    recordStruct := new RecordTypeInfo(
        "PtS",
        1,
        1,
        true,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](1),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
    recordStruct.PrimaryConstructorParameters[0] = new ParameterDeclarationInfo(
        "x", new SimpleTypeReference("int"), 1, 1)
    // A record STRUCT keeps its implicit constructor whatever it declares.
    assert AnalyzerSyntheticCallValidator.HasParameterlessConstructor(recordStruct)

    recordClass := new RecordTypeInfo(
        "Pt",
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](1),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
    recordClass.PrimaryConstructorParameters[0] = new ParameterDeclarationInfo(
        "x", new SimpleTypeReference("int"), 1, 1)
    assert !AnalyzerSyntheticCallValidator.HasParameterlessConstructor(recordClass)

    emptyRecordClass := new RecordTypeInfo(
        "Empty",
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
    assert AnalyzerSyntheticCallValidator.HasParameterlessConstructor(emptyRecordClass)
}

test "a CLASS answers from its own recorded flag, and an unknown type is assumed to satisfy" {
    withCtor := new ClassTypeInfo(
        "Boxy",
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true)
    assert AnalyzerSyntheticCallValidator.HasParameterlessConstructor(withCtor)

    withoutCtor := new ClassTypeInfo(
        "NoCtor",
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        false)
    assert !AnalyzerSyntheticCallValidator.HasParameterlessConstructor(withoutCtor)

    // A type the analyzer could not resolve must not add a constraint report on top of the
    // resolution failure the user already has.
    assert AnalyzerSyntheticCallValidator.HasParameterlessConstructor(BuiltInTypes.Unknown)
    assert AnalyzerSyntheticCallValidator.HasParameterlessConstructor(new SimpleTypeInfo("T"))
}

test "a CLR value type satisfies new() even with no declared constructor; a CLR class must declare one" {
    assert AnalyzerSyntheticCallValidator.HasParameterlessConstructor(
        new ReflectionTypeInfo(typeof(int)))
    assert AnalyzerSyntheticCallValidator.HasParameterlessConstructor(
        new ReflectionTypeInfo(typeof(object)))
    // `string` has no public parameterless constructor.
    assert !AnalyzerSyntheticCallValidator.HasParameterlessConstructor(
        new ReflectionTypeInfo(typeof(string)))
}

// ------------------------------------------------------------------ return type

test "a signature with no declared return type is VOID, not unknown, and inference closes it" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(BuiltInTypes.Int))
    signature.ReturnType = null
    call := VCall(VArgs1(VIdentifier("a")))

    assert VTypeText(owner.ResolveReturnType(signature, call, VTypes1(BuiltInTypes.Int), null)) == "void"

    generic := VSignature(VTypes1(new SimpleTypeInfo("T")))
    generic.ReturnType = new SimpleTypeInfo("T")
    generic.SourceParameterTypes = VRefs1(new SimpleTypeReference("T"))
    generic.TypeParameters = VTypeParameters("T")
    assert VTypeText(owner.ResolveReturnType(generic, call, VTypes1(BuiltInTypes.String), null))
        == "string"
}

// ------------------------------------------------------------------ no matching overload

test "an EMPTY candidate list reports nothing" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)

    owner.ReportNoMatchingOverload(
        new List<FunctionTypeInfo>(), VCall(VArgs1(VIdentifier("a"))), VTypes1(BuiltInTypes.Int))
    assert errors.Count == 0
}

test "the candidate list is DISTINCT and capped at eight signatures" {
    errors := ValidatorErrors()
    owner := ValidatorOwnerWithText(errors, "f()\n")
    candidates := new List<FunctionTypeInfo>()
    index := 0
    while index < 12 {
        candidates.Add(VSignature(VTypes1(BuiltInTypes.Int)))
        index = index + 1
    }

    owner.ReportNoMatchingOverload(candidates, VCall(VArgs0()), new List<TypeInfo>())
    assert VCodes(errors) == "NL402"
    // Twelve identical signatures collapse to ONE line, because distinctness comes first.
    hint := errors[0].ContextualHint
    assert hint != null
    assert hint.Contains("f(p1: int)")
}

test "the report names the CALL's target, falling back to the first candidate's own name" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(BuiltInTypes.Int))
    signature.SyntheticName = "declared"

    owner.ReportNoMatchingOverload(
        VCandidates1(signature), VCall(VArgs0()), new List<TypeInfo>())
    assert errors.Count == 1
    // The call is written `f(...)`, so `f` wins over the declaration's own name.
    assert errors[0].Message.Contains("'f'")

    errors.Clear()
    anonymous := new CallExpression(
        new IntLiteralExpression("1", 1, 1), VArgs0(), null, 1, 1)
    owner.ReportNoMatchingOverload(VCandidates1(signature), anonymous, new List<TypeInfo>())
    assert errors.Count == 1
    assert errors[0].Message.Contains("'declared'")
}

test "two DIFFERENT signatures both render" {
    errors := ValidatorErrors()
    owner := ValidatorOwnerWithText(errors, "f()\n")
    first := VSignature(VTypes1(BuiltInTypes.Int))
    second := VSignature(VTypes2(BuiltInTypes.String, BuiltInTypes.String))

    owner.ReportNoMatchingOverload(
        VCandidates2(first, second), VCall(VArgs0()), new List<TypeInfo>())
    assert errors.Count == 1
    hint := errors[0].ContextualHint
    assert hint != null
    assert hint.Contains("f(p1: int)")
    assert hint.Contains("f(p1: string, p2: string)")
}

// ------------------------------------------------------------------ the SoA intrinsics

test "a wrap column written as null or default reports; a real array does not" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(new ArrayTypeInfo(BuiltInTypes.Int)))
    signature.SyntheticName = "wrap"
    placement: int[] = new int[1]
    placement[0] = 0

    owner.ValidateSoaCall(
        signature,
        "wrap",
        VCall(VArgs1(new NullLiteralExpression(1, 1))),
        VTypes1(new ArrayTypeInfo(BuiltInTypes.Int)),
        placement)
    assert VCodes(errors) == "NL202"
    assert errors[0].Message.Contains("cannot be null")

    errors.Clear()
    owner.ValidateSoaCall(
        signature,
        "wrap",
        VCall(VArgs1(new DefaultExpression(1, 1))),
        VTypes1(new ArrayTypeInfo(BuiltInTypes.Int)),
        placement)
    assert VCodes(errors) == "NL202"

    errors.Clear()
    owner.ValidateSoaCall(
        signature,
        "wrap",
        VCall(VArgs1(VIdentifier("columns"))),
        VTypes1(new ArrayTypeInfo(BuiltInTypes.Int)),
        placement)
    assert errors.Count == 0
}

test "a negative capacity, source row and target row each report, and -0 does not" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    capacity := VSignature(VTypes1(BuiltInTypes.Int))
    capacity.SyntheticName = "ensureCapacity"
    placement1: int[] = new int[1]
    placement1[0] = 0

    negative: Expression = new UnaryExpression(
        UnaryOperator.Negate, new IntLiteralExpression("5", 1, 1), 1, 1)
    owner.ValidateSoaCall(
        capacity, "ensureCapacity", VCall(VArgs1(negative)), VTypes1(BuiltInTypes.Int), placement1)
    assert VCodes(errors) == "NL202"
    assert errors[0].Message.Contains("capacity must not be negative")

    // Negative ZERO is not negative.
    errors.Clear()
    negativeZero: Expression = new UnaryExpression(
        UnaryOperator.Negate, new IntLiteralExpression("0", 1, 1), 1, 1)
    owner.ValidateSoaCall(
        capacity,
        "ensureCapacity",
        VCall(VArgs1(negativeZero)),
        VTypes1(BuiltInTypes.Int),
        placement1)
    assert errors.Count == 0

    errors.Clear()
    copyRow := VSignature(VTypes2(BuiltInTypes.Int, BuiltInTypes.Int))
    copyRow.SyntheticName = "copyRow"
    placement2: int[] = new int[2]
    placement2[0] = 0
    placement2[1] = 1
    other: Expression = new UnaryExpression(
        UnaryOperator.Negate, new IntLiteralExpression("2", 1, 1), 1, 1)
    owner.ValidateSoaCall(
        copyRow,
        "copyRow",
        VCall(VArgs2(negative, other)),
        VTypes2(BuiltInTypes.Int, BuiltInTypes.Int),
        placement2)
    assert VCodes(errors) == "NL202,NL202"
    assert errors[0].Message.Contains("source row id")
    assert errors[1].Message.Contains("target row id")
}

test "a synthetic name that is not an SoA intrinsic checks nothing" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    signature := VSignature(VTypes1(BuiltInTypes.Int))
    placement: int[] = new int[1]
    placement[0] = 0
    negative: Expression = new UnaryExpression(
        UnaryOperator.Negate, new IntLiteralExpression("5", 1, 1), 1, 1)

    owner.ValidateSoaCall(
        signature, "f", VCall(VArgs1(negative)), VTypes1(BuiltInTypes.Int), placement)
    assert errors.Count == 0
}

// ------------------------------------------------------------------ literal and constant shape

test "a written negative is a NEGATION of a non-zero magnitude, through wrappers and signed casts" {
    scopes := ValidatorScopes()
    constants := ValidatorConstants(scopes)

    negative: Expression = new UnaryExpression(
        UnaryOperator.Negate, new IntLiteralExpression("7", 1, 1), 1, 1)
    assert constants.IsConstantNegative(negative)

    zero: Expression = new UnaryExpression(
        UnaryOperator.Negate, new IntLiteralExpression("0", 1, 1), 1, 1)
    assert !constants.IsConstantNegative(zero)

    // Parentheses, `checked` and `unchecked` change nothing.
    assert constants.IsConstantNegative(new ParenthesizedExpression(negative, 1, 1))
    assert constants.IsConstantNegative(new CheckedExpression(negative, 1, 1))
    assert constants.IsConstantNegative(new UncheckedExpression(negative, 1, 1))

    // A cast to a SIGNED integer type is transparent; a cast to an unsigned one is not.
    signed: Expression = new CastExpression(
        negative, new SimpleTypeReference("int"), CastKind.Hard, 1, 1)
    assert constants.IsConstantNegative(signed)
    unsigned: Expression = new CastExpression(
        negative, new SimpleTypeReference("uint"), CastKind.Hard, 1, 1)
    assert !constants.IsConstantNegative(unsigned)

    // A negated IDENTIFIER is not a written constant at all.
    identifier: Expression = new UnaryExpression(
        UnaryOperator.Negate, new IdentifierExpression("k", 1, 1), 1, 1)
    assert !constants.IsConstantNegative(identifier)
}

test "a DECLARED ALIAS of a signed integer type is transparent to the sign question" {
    scopes := ValidatorScopes()
    scopes.DeclareNestedTypeIfAbsent("MyInt", BuiltInTypes.Int)
    scopes.DeclareNestedTypeIfAbsent("MyStr", BuiltInTypes.String)
    constants := ValidatorConstants(scopes)

    negative: Expression = new UnaryExpression(
        UnaryOperator.Negate, new IntLiteralExpression("7", 1, 1), 1, 1)

    aliased: Expression = new CastExpression(
        negative, new SimpleTypeReference("MyInt"), CastKind.Hard, 1, 1)
    assert constants.IsConstantNegative(aliased)

    // An alias of a NON-integer type is opaque, and so is a name that resolves to nothing.
    stringAlias: Expression = new CastExpression(
        negative, new SimpleTypeReference("MyStr"), CastKind.Hard, 1, 1)
    assert !constants.IsConstantNegative(stringAlias)
    missing: Expression = new CastExpression(
        negative, new SimpleTypeReference("Nope"), CastKind.Hard, 1, 1)
    assert !constants.IsConstantNegative(missing)
}

test "null and default are the literal shape, through any wrapper and any cast" {
    nullLiteral: Expression = new NullLiteralExpression(1, 1)
    assert AnalyzerConstantExpressionFacts.IsNullOrDefaultLiteral(nullLiteral)
    assert AnalyzerConstantExpressionFacts.IsNullOrDefaultLiteral(new DefaultExpression(1, 1))

    // Unlike the sign question, the cast here is peeled whatever its target is.
    unsignedCast: Expression = new CastExpression(
        nullLiteral, new SimpleTypeReference("uint"), CastKind.Hard, 1, 1)
    assert AnalyzerConstantExpressionFacts.IsNullOrDefaultLiteral(unsignedCast)

    wrapped: Expression = new ParenthesizedExpression(
        new CheckedExpression(nullLiteral, 1, 1), 1, 1)
    assert AnalyzerConstantExpressionFacts.IsNullOrDefaultLiteral(wrapped)

    assert !AnalyzerConstantExpressionFacts.IsNullOrDefaultLiteral(new IdentifierExpression("k", 1, 1))
}

test "the transparent wrappers peel in any order and any depth, and nothing else does" {
    inner: Expression = new IdentifierExpression("k", 1, 1)
    nested: Expression = new ParenthesizedExpression(
        new UncheckedExpression(new CheckedExpression(
            new ParenthesizedExpression(inner, 1, 1), 1, 1), 1, 1), 1, 1)
    assert AnalyzerConstantExpressionFacts.UnwrapTransparentWrappers(nested) == inner

    // A CAST is not transparent here — that is the sign question's own rule, not this one's.
    cast: Expression = new CastExpression(
        inner, new SimpleTypeReference("int"), CastKind.Hard, 1, 1)
    assert AnalyzerConstantExpressionFacts.UnwrapTransparentWrappers(cast) == cast
}

// ------------------------------------------------------------------ callable-reference naming

test "what the user WROTE names a callable reference, and the TYPE answers only when nothing was" {
    identifier: Expression = new IdentifierExpression("mg", 1, 1)
    assert AnalyzerCallableReferenceFacts.GetCallableReferenceName(identifier, BuiltInTypes.Unknown)
        == "mg"

    member: Expression = new MemberAccessExpression(
        new IdentifierExpression("a", 1, 1), "Tag", false, 1, 1)
    assert AnalyzerCallableReferenceFacts.GetCallableReferenceName(member, BuiltInTypes.Unknown)
        == "Tag"

    // Wrappers do not change what was written.
    wrapped: Expression = new ParenthesizedExpression(identifier, 1, 1)
    assert AnalyzerCallableReferenceFacts.GetCallableReferenceName(wrapped, BuiltInTypes.Unknown)
        == "mg"
}

test "an unwritten reference falls to the TYPE, and an empty name falls through to `method`" {
    anonymous: Expression = new CallExpression(
        new IdentifierExpression("f", 1, 1), new List<Argument>(), null, 1, 1)

    named := VSignature(VTypes1(BuiltInTypes.Int))
    named.SyntheticName = "declared"
    assert AnalyzerCallableReferenceFacts.GetCallableReferenceName(anonymous, named) == "declared"

    // An EMPTY synthetic name is not a name.
    empty := VSignature(VTypes1(BuiltInTypes.Int))
    empty.SyntheticName = ""
    assert AnalyzerCallableReferenceFacts.GetCallableReferenceName(anonymous, empty) == "method"

    group := new NSharpMethodGroupInfo(VCandidates1(named))
    assert AnalyzerCallableReferenceFacts.GetCallableReferenceName(anonymous, group) == "declared"

    // An EMPTY group has no first candidate to name.
    emptyGroup := new NSharpMethodGroupInfo(new List<FunctionTypeInfo>())
    assert AnalyzerCallableReferenceFacts.GetCallableReferenceName(anonymous, emptyGroup) == "method"

    assert AnalyzerCallableReferenceFacts.GetCallableReferenceName(anonymous, BuiltInTypes.Int)
        == "method"
}

test "a method group in argument position is NAMED rather than typed, and the phrase is not double-quoted" {
    errors := ValidatorErrors()
    owner := ValidatorOwner(errors)
    argument := new Argument(null, new IdentifierExpression("mg", 1, 1), ArgumentModifier.None)

    group := VSignature(VTypes1(BuiltInTypes.Int))
    group.SourceName = "mg"
    assert owner.GetArgumentTypeDiagnosticName(argument, group) == "method group 'mg'"
    assert owner.FormatArgumentTypeDiagnosticPhrase(argument, group) == "method group 'mg'"

    // An ordinary type renders its own name, and the phrase quotes it.
    assert owner.GetArgumentTypeDiagnosticName(argument, BuiltInTypes.Int) == "int"
    assert owner.FormatArgumentTypeDiagnosticPhrase(argument, BuiltInTypes.Int) == "'int'"
}
