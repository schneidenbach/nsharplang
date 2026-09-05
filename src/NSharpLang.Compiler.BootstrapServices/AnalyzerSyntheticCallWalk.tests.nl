namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the source binder's WALK — overload selection, match scoring, generic
// inference and the constraint report's span.
//
// All four members behind these were `private` in Analyzer.cs, so nothing in `src/` or `tests/`
// named any of them and the only pinning they ever had was end-to-end diagnostic text. These go at
// the decisions a reader cannot recover from a single arm:
//
//   * `NeedsReceiverType` IS the walk's own guard, hoisted so the caller cannot analyse an
//     expression the walk would not have analysed — the five arms are pinned individually;
//   * the receiver POSITION contributes a bound like any other parameter, which is the whole reason
//     the type has to cross the boundary at all;
//   * "does not apply" is -1 and NOT 0, because zero is a real score for an applicable overload
//     every one of whose positions carries no comparable type;
//   * the tie-break order is generic cost, then params-vs-fixed, then parameter count, and ONLY a
//     four-way tie is ambiguous — a later equally specific candidate never displaces an earlier one;
//   * `AnyCandidateNeedsReceiverType` reads the SCORING gate, not just the guard, so a candidate the
//     arity tables reject cannot cause a receiver to be analysed that the walk never touches;
//   * a violated constraint anchors on the ARGUMENT that bound the parameter only when there is
//     exactly one — none and two both fall back to the call.
func WalkErrors(): List<CompilerError> {
    return new List<CompilerError>()
}

func WalkOwner(errors: List<CompilerError>): AnalyzerSyntheticCallWalk {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    sink := new AnalyzerDiagnosticSink(errors, provider)
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        sink,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal),
        new SemanticModel(),
        new BindingMap()
    )
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
    return new AnalyzerSyntheticCallWalk(
        resolver,
        binder,
        reporter,
        scoring,
        assignability,
        spans,
        sink
    )
}

// ------------------------------------------------------------------ signature and call shapes

func WalkNames(count: int): List<string> {
    names := new List<string>()
    index := 0
    while index < count {
        ordinal := index + 1
        names.Add("p" + ordinal.ToString())
        index = index + 1
    }

    return names
}

func WalkModifiers(count: int): List<ParameterModifier> {
    modifiers := new List<ParameterModifier>()
    index := 0
    while index < count {
        modifiers.Add(ParameterModifier.None)
        index = index + 1
    }

    return modifiers
}

func WalkTypes1(first: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    return types
}

func WalkTypes2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    types.Add(second)
    return types
}

func WalkReferences1(first: TypeReference): List<TypeReference> {
    references := new List<TypeReference>()
    references.Add(first)
    return references
}

func WalkReferences2(first: TypeReference, second: TypeReference): List<TypeReference> {
    references := new List<TypeReference>()
    references.Add(first)
    references.Add(second)
    return references
}

func WalkTypeParameters(name: string): List<TypeParameter> {
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter(name))
    return parameters
}

func WalkTypeParameters2(first: string, second: string): List<TypeParameter> {
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter(first))
    parameters.Add(new TypeParameter(second))
    return parameters
}

func WalkSignature(parameterTypes: List<TypeInfo>): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SyntheticName = "f"
    signature.ParameterNames = WalkNames(parameterTypes.Count)
    signature.ParameterTypes = parameterTypes
    signature.ParameterModifiers = WalkModifiers(parameterTypes.Count)
    return signature
}

// `this p1: T` followed by whatever else the caller passes — the shape the whole slice is about.
func WalkReceiverGeneric(parameterTypes: List<TypeInfo>, sources: List<TypeReference>): FunctionTypeInfo {
    signature := WalkSignature(parameterTypes)
    signature.SourceHasReceiverParameter = true
    signature.SourceParameterTypes = sources
    signature.TypeParameters = WalkTypeParameters("T")
    return signature
}

func WalkIdentifier(name: string): Expression {
    return new IdentifierExpression(name, 1, 1)
}

func WalkPositional(name: string): Argument {
    return new Argument(null, WalkIdentifier(name), ArgumentModifier.None)
}

func WalkArgs(): List<Argument> {
    return new List<Argument>()
}

func WalkArgs1(name: string): List<Argument> {
    arguments := WalkArgs()
    arguments.Add(WalkPositional(name))
    return arguments
}

// `receiver.f(...)`, the only callee shape that gives the signature a receiver offset.
func WalkMemberCall(arguments: List<Argument>): CallExpression {
    receiver: Expression = WalkIdentifier("receiver")
    callee: Expression = new MemberAccessExpression(receiver, "f", false, 1, 1)
    return new CallExpression(callee, arguments, null, 1, 1)
}

func WalkMemberCallWithTypeArguments(
    arguments: List<Argument>,
    typeArguments: List<TypeReference>
): CallExpression {
    receiver: Expression = WalkIdentifier("receiver")
    callee: Expression = new MemberAccessExpression(receiver, "f", false, 1, 1)
    return new CallExpression(callee, arguments, typeArguments, 1, 1)
}

func WalkBareCall(arguments: List<Argument>): CallExpression {
    return new CallExpression(WalkIdentifier("f"), arguments, null, 1, 1)
}

func WalkCandidates(first: FunctionTypeInfo): List<FunctionTypeInfo> {
    candidates := new List<FunctionTypeInfo>()
    candidates.Add(first)
    return candidates
}

func WalkCandidates2(first: FunctionTypeInfo, second: FunctionTypeInfo): List<FunctionTypeInfo> {
    candidates := new List<FunctionTypeInfo>()
    candidates.Add(first)
    candidates.Add(second)
    return candidates
}

func WalkBindingText(bindings: Dictionary<string, TypeInfo>?, name: string): string {
    if bindings != null {
        bound: TypeInfo = BuiltInTypes.Unknown
        if bindings.TryGetValue(name, out bound) {
            boundObject := bound as object
            return boundObject.ToString()
        }

        return "<unbound>"
    }

    return "<null>"
}

// ------------------------------------------------------------------ the guard

// Every arm of the guard is an early exit of the inference walk, and the caller reads the SAME
// answer, so a receiver can never be analysed that the walk would not have analysed.
test "the receiver type is needed only for a generic receiver-style call with room to infer" {
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("string"))
    )

    assert AnalyzerSyntheticCallWalk.NeedsReceiverType(generic, WalkMemberCall(WalkArgs1("a")))

    // A bare call to the same declaration supplies every parameter positionally.
    assert !AnalyzerSyntheticCallWalk.NeedsReceiverType(generic, WalkBareCall(WalkArgs1("a")))
}

test "a non-generic signature never reads the receiver type" {
    plain := WalkSignature(WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    plain.SourceHasReceiverParameter = true
    plain.SourceParameterTypes = WalkReferences2(
        new SimpleTypeReference("int"),
        new SimpleTypeReference("string")
    )

    assert !AnalyzerSyntheticCallWalk.NeedsReceiverType(plain, WalkMemberCall(WalkArgs1("a")))
}

test "a call that wrote all of its type arguments is already closed" {
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("string"))
    )
    closed := WalkMemberCallWithTypeArguments(
        WalkArgs1("a"),
        WalkReferences1(new SimpleTypeReference("int"))
    )

    assert !AnalyzerSyntheticCallWalk.NeedsReceiverType(generic, closed)

    // More type arguments than parameters is a dead call, not a call to infer.
    tooMany := WalkMemberCallWithTypeArguments(
        WalkArgs1("a"),
        WalkReferences2(new SimpleTypeReference("int"), new SimpleTypeReference("string"))
    )
    assert !AnalyzerSyntheticCallWalk.NeedsReceiverType(generic, tooMany)
}

test "a PARTIALLY closed generic call still reads the receiver" {
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("U"))
    )
    generic.TypeParameters = WalkTypeParameters2("T", "U")
    partiallyClosed := WalkMemberCallWithTypeArguments(
        WalkArgs1("a"),
        WalkReferences1(new SimpleTypeReference("int"))
    )

    assert AnalyzerSyntheticCallWalk.NeedsReceiverType(generic, partiallyClosed)
}

test "a signature with no SOURCE parameter types has nothing to match the receiver against" {
    generic := WalkSignature(WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    generic.SourceHasReceiverParameter = true
    generic.TypeParameters = WalkTypeParameters("T")

    assert !AnalyzerSyntheticCallWalk.NeedsReceiverType(generic, WalkMemberCall(WalkArgs1("a")))
}

// The group question reads the SCORING gate too: a candidate the arity tables reject never reaches
// the inference walk, so it must not cause a receiver analysis either.
test "the group question ignores candidates the arity tables already rejected" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("string"))
    )

    oneArgument := new List<TypeInfo>()
    oneArgument.Add(BuiltInTypes.String)
    assert owner.AnyCandidateNeedsReceiverType(
        WalkCandidates(generic),
        WalkMemberCall(WalkArgs1("a")),
        oneArgument
    )

    // The same candidate called with two arguments does not survive the gate.
    twoArguments := WalkTypes2(BuiltInTypes.String, BuiltInTypes.String)
    arguments := WalkArgs1("a")
    arguments.Add(WalkPositional("b"))
    assert !owner.AnyCandidateNeedsReceiverType(
        WalkCandidates(generic),
        WalkMemberCall(arguments),
        twoArguments
    )
    assert errors.Count == 0
}

// ------------------------------------------------------------------ inference

test "a non-generic signature infers nothing at all" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    plain := WalkSignature(WalkTypes1(BuiltInTypes.Int))

    assert owner.InferGenericBindings(
        plain,
        WalkBareCall(WalkArgs1("a")),
        WalkTypes1(BuiltInTypes.Int),
        null
    ) == null
}

// THE RECEIVER POSITION IS A BOUND LIKE ANY OTHER — this is why the type has to cross the boundary.
test "the receiver type binds the type parameter its source position names" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("string"))
    )
    call := WalkMemberCall(WalkArgs1("a"))
    argTypes := WalkTypes1(BuiltInTypes.String)

    withReceiver := owner.InferGenericBindings(generic, call, argTypes, BuiltInTypes.Double)
    assert WalkBindingText(withReceiver, "T") == "double"

    // WITHOUT the receiver type nothing constrains `T`, and an unconstrained parameter is left
    // unbound rather than guessed.
    withoutReceiver := owner.InferGenericBindings(generic, call, argTypes, null)
    assert WalkBindingText(withoutReceiver, "T") == "<unbound>"
    assert errors.Count == 0
}

test "explicit type arguments win outright and close the signature" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("string"))
    )
    closed := WalkMemberCallWithTypeArguments(
        WalkArgs1("a"),
        WalkReferences1(new SimpleTypeReference("int"))
    )

    // The receiver is `double`, but the call WROTE `int`, so `int` it is.
    bindings := owner.InferGenericBindings(
        generic,
        closed,
        WalkTypes1(BuiltInTypes.String),
        BuiltInTypes.Double
    )
    assert WalkBindingText(bindings, "T") == "int"
}

test "more type arguments than the signature declares infers nothing" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("string"))
    )
    tooMany := WalkMemberCallWithTypeArguments(
        WalkArgs1("a"),
        WalkReferences2(new SimpleTypeReference("int"), new SimpleTypeReference("string"))
    )

    assert owner.InferGenericBindings(
        generic,
        tooMany,
        WalkTypes1(BuiltInTypes.String),
        BuiltInTypes.Double
    ) == null
}

// The receiver and an ARGUMENT can constrain the same parameter, and the answer is their least
// upper bound rather than whichever was seen first.
test "several bounds on one type parameter resolve to their least upper bound" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.Int),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("T"))
    )
    call := WalkMemberCall(WalkArgs1("a"))

    bindings := owner.InferGenericBindings(
        generic,
        call,
        WalkTypes1(BuiltInTypes.Double),
        BuiltInTypes.Int
    )
    assert WalkBindingText(bindings, "T") == "double"
}

// ------------------------------------------------------------------ scoring

// ZERO IS A REAL SCORE. An applicable overload every one of whose positions carries no comparable
// type scores zero, so "does not apply" has to live outside the score's range.
test "an inapplicable candidate scores -1 and an applicable one may still score zero" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("string"))
    )

    // Two arguments for a one-argument signature: out on arity.
    twoArguments := WalkTypes2(BuiltInTypes.String, BuiltInTypes.String)
    arguments := WalkArgs1("a")
    arguments.Add(WalkPositional("b"))
    assert owner.GetCallMatchScore(
        generic,
        WalkMemberCall(arguments),
        twoArguments,
        BuiltInTypes.Int
    ) == -1

    // An UNKNOWN argument is skipped rather than rejected, so the candidate applies at score zero.
    unknownOnly := WalkTypes1(BuiltInTypes.Unknown)
    assert owner.GetCallMatchScore(
        generic,
        WalkMemberCall(WalkArgs1("a")),
        unknownOnly,
        BuiltInTypes.Int
    ) == 0
    assert errors.Count == 0
}

test "a position that is not assignable takes the candidate out" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    generic := WalkReceiverGeneric(
        WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String),
        WalkReferences2(new SimpleTypeReference("T"), new SimpleTypeReference("string"))
    )

    matching := owner.GetCallMatchScore(
        generic,
        WalkMemberCall(WalkArgs1("a")),
        WalkTypes1(BuiltInTypes.String),
        BuiltInTypes.Int
    )
    assert matching > 0

    mismatched := owner.GetCallMatchScore(
        generic,
        WalkMemberCall(WalkArgs1("a")),
        WalkTypes1(BuiltInTypes.Bool),
        BuiltInTypes.Int
    )
    assert mismatched == -1
}

// ------------------------------------------------------------------ overload selection

test "the higher score wins and no ambiguity is reported" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    exact := WalkSignature(WalkTypes1(BuiltInTypes.String))
    exact.SourceParameterTypes = WalkReferences1(new SimpleTypeReference("string"))
    widening := WalkSignature(WalkTypes1(BuiltInTypes.Object))
    widening.SourceParameterTypes = WalkReferences1(new SimpleTypeReference("object"))

    chosen := owner.BindNSharpCall(
        WalkCandidates2(widening, exact),
        WalkBareCall(WalkArgs1("a")),
        WalkTypes1(BuiltInTypes.String),
        null
    )
    assert chosen == exact
    assert errors.Count == 0
}

// A FOUR-WAY TIE is what ambiguity means: same score, same generic cost, same params shape and the
// same parameter count.
test "an unbreakable tie is reported as an ambiguous call" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    first := WalkSignature(WalkTypes1(BuiltInTypes.String))
    first.SourceParameterTypes = WalkReferences1(new SimpleTypeReference("string"))
    second := WalkSignature(WalkTypes1(BuiltInTypes.String))
    second.SourceParameterTypes = WalkReferences1(new SimpleTypeReference("string"))

    chosen := owner.BindNSharpCall(
        WalkCandidates2(first, second),
        WalkBareCall(WalkArgs1("a")),
        WalkTypes1(BuiltInTypes.String),
        null
    )

    // The FIRST candidate is kept — a later equally specific overload never displaces it.
    assert chosen == first
    assert errors.Count == 1
    assert errors[0].Message == "Ambiguous call to 'f': multiple overloads match with equal specificity"
}

// A candidate that matched by BINDING a type parameter is less specific than one that matched a
// written type, and that rule is read before the params and parameter-count rules.
test "fewer inferred type parameters beats more at an equal score" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    written := WalkSignature(WalkTypes1(BuiltInTypes.String))
    written.SourceParameterTypes = WalkReferences1(new SimpleTypeReference("string"))
    inferred := WalkSignature(WalkTypes1(BuiltInTypes.String))
    inferred.SourceParameterTypes = WalkReferences1(new SimpleTypeReference("T"))
    inferred.TypeParameters = WalkTypeParameters("T")

    chosen := owner.BindNSharpCall(
        WalkCandidates2(inferred, written),
        WalkBareCall(WalkArgs1("a")),
        WalkTypes1(BuiltInTypes.String),
        null
    )
    assert chosen == written
    assert errors.Count == 0
}

// ------------------------------------------------------------------ the constraint span

// The span is the ARGUMENT that bound the offending parameter — but only when there is EXACTLY one.
test "a violated constraint anchors on the single argument that bound the parameter" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    signature := WalkSignature(WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    signature.SourceParameterTypes = WalkReferences2(
        new SimpleTypeReference("int"),
        new SimpleTypeReference("T")
    )
    arguments := WalkArgs()
    arguments.Add(new Argument(null, new IdentifierExpression("first", 3, 5), ArgumentModifier.None))
    arguments.Add(new Argument(null, new IdentifierExpression("second", 3, 12), ArgumentModifier.None))
    call := new CallExpression(WalkIdentifier("f"), arguments, null, 3, 1)

    span := owner.GetGenericConstraintDiagnosticSpan(signature, call, "T", "f")
    assert span.Line == 3
    assert span.Column == 12
    assert span.Length == 6
}

test "no offending argument and two offending arguments both fall back to the call" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    none := WalkSignature(WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    none.SourceParameterTypes = WalkReferences2(
        new SimpleTypeReference("int"),
        new SimpleTypeReference("string")
    )
    arguments := WalkArgs()
    arguments.Add(new Argument(null, new IdentifierExpression("first", 3, 5), ArgumentModifier.None))
    arguments.Add(new Argument(null, new IdentifierExpression("second", 3, 12), ArgumentModifier.None))
    call := new CallExpression(WalkIdentifier("f"), arguments, null, 3, 1)

    absent := owner.GetGenericConstraintDiagnosticSpan(none, call, "T", "f")
    assert absent.Column == 1

    both := WalkSignature(WalkTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    both.SourceParameterTypes = WalkReferences2(
        new SimpleTypeReference("T"),
        new SimpleTypeReference("T")
    )
    twoOffenders := owner.GetGenericConstraintDiagnosticSpan(both, call, "T", "f")
    assert twoOffenders.Column == 1
}

// With no source parameter types there is nothing to search, so the report lands on the callee's
// own name — its line, its column and its written length.
test "a signature with no source parameter types anchors the constraint on the call" {
    errors := WalkErrors()
    owner := WalkOwner(errors)
    signature := WalkSignature(WalkTypes1(BuiltInTypes.Int))
    callee: Expression = new IdentifierExpression("f", 7, 2)
    call := new CallExpression(callee, WalkArgs1("a"), null, 7, 2)

    span := owner.GetGenericConstraintDiagnosticSpan(signature, call, "T", "f")
    assert span.Line == 7
    assert span.Column == 2
    assert span.Length == 1
}
