namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the source binder's argument filler and its pure inference interior.
//
// Every member behind these was `private` in Analyzer.cs, so nothing named any of them: the source
// world's placement walk was pinned only indirectly, through end-to-end NL402 text. This is its
// first DIRECT pinning, and it goes at the decisions a reader cannot recover from a single arm:
//
//   * the positional cursor SKIPS positions a name already claimed, so `f(1, b: 2, 3)` is not the
//     same as three positional arguments;
//   * a receiver-supplied parameter may not be named, and is not required;
//   * a failed placement CONTINUES the walk — one call reports every placement problem it has;
//   * the map is produced even when the bind failed, because scoring and the renderers keep walking;
//   * the params tail has THREE comparison shapes (direct array, spread, expanded) and a fourth
//     answer — "carries no information" — that is NOT the same as "does not match";
//   * the least upper bound tries the COMMON SUPERTYPE rule before the numeric one, so `int`/`double`
//     answers `double` by assignability rather than by widening;
//   * the collecting inference walk gathers ALL bounds rather than binding at the first sighting.

func SyntheticContext(): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    return context
}

func SyntheticBinder(): AnalyzerSyntheticCallBinder {
    context := SyntheticContext()
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        new AnalyzerDiagnosticSink(new List<CompilerError>(), provider),
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
    return new AnalyzerSyntheticCallBinder(context, scoring, assignability, clrConversion)
}

// ------------------------------------------------------------------ signature shapes

func SyntheticSignature(
    parameterNames: List<string>,
    parameterTypes: List<TypeInfo>,
    modifiers: List<ParameterModifier>): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SyntheticName = "f"
    signature.ParameterNames = parameterNames
    signature.ParameterTypes = parameterTypes
    signature.ParameterModifiers = modifiers
    return signature
}

func SyntheticNames(count: int): List<string> {
    names := new List<string>()
    index := 0
    while index < count {
        ordinal := index + 1
        names.Add("p" + ordinal.ToString())
        index = index + 1
    }

    return names
}

func SyntheticIntTypes(count: int): List<TypeInfo> {
    types := new List<TypeInfo>()
    index := 0
    while index < count {
        types.Add(BuiltInTypes.Int)
        index = index + 1
    }

    return types
}

func SyntheticModifiers(count: int): List<ParameterModifier> {
    modifiers := new List<ParameterModifier>()
    index := 0
    while index < count {
        modifiers.Add(ParameterModifier.None)
        index = index + 1
    }

    return modifiers
}

// `count` plain parameters named p1..pN, all `int`.
func SyntheticPlain(count: int): FunctionTypeInfo {
    return SyntheticSignature(
        SyntheticNames(count), SyntheticIntTypes(count), SyntheticModifiers(count))
}

// `leading` plain `int` parameters followed by a `params int[]` tail.
func SyntheticParams(leading: int): FunctionTypeInfo {
    total := leading + 1
    names := SyntheticNames(total)
    types := SyntheticIntTypes(leading)
    tail: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    types.Add(tail)
    modifiers := SyntheticModifiers(leading)
    modifiers.Add(ParameterModifier.Params)
    signature := SyntheticSignature(names, types, modifiers)
    signature.HasParamsParameter = true
    return signature
}

func SyntheticRequire(signature: FunctionTypeInfo, requiredCount: int): FunctionTypeInfo {
    nullableCount: int? = requiredCount
    signature.RequiredParameterCount = nullableCount
    return signature
}

// ------------------------------------------------------------------ call shapes

func SyntheticIdentifier(name: string): Expression {
    return new IdentifierExpression(name, 1, 1)
}

func SyntheticPositional(name: string): Argument {
    return new Argument(null, SyntheticIdentifier(name), ArgumentModifier.None)
}

func SyntheticNamed(parameterName: string, valueName: string): Argument {
    return new Argument(parameterName, SyntheticIdentifier(valueName), ArgumentModifier.None)
}

func SyntheticSpread(name: string): Argument {
    spreadValue: Expression = new SpreadExpression(SyntheticIdentifier(name), 1, 1)
    return new Argument(null, spreadValue, ArgumentModifier.None)
}

func SyntheticCall(arguments: List<Argument>): CallExpression {
    return new CallExpression(SyntheticIdentifier("f"), arguments, null, 1, 1)
}

func SyntheticMemberCall(arguments: List<Argument>): CallExpression {
    receiver: Expression = SyntheticIdentifier("receiver")
    callee: Expression = new MemberAccessExpression(receiver, "f", false, 1, 1)
    return new CallExpression(callee, arguments, null, 1, 1)
}

func SyntheticArgs(): List<Argument> {
    return new List<Argument>()
}

// The placed map rendered as a comma-joined string, which is the whole answer in one assertion.
func SyntheticMap(binding: SyntheticArgumentBinding): string {
    rendered := ""
    index := 0
    while index < binding.ParameterIndexByArgument.Length {
        if index > 0 {
            rendered = rendered + ","
        }

        entry := binding.ParameterIndexByArgument[index]
        rendered = rendered + entry.ToString()
        index = index + 1
    }

    return rendered
}

func SyntheticTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    candidateObject := candidate as object
    return candidateObject.ToString()
}

func SyntheticTypeList(first: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    return types
}

func SyntheticTypeList2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    types.Add(second)
    return types
}

func SyntheticTypeParameters(name: string): List<TypeParameter> {
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter(name))
    return parameters
}

func SyntheticBounds(name: string): Dictionary<string, List<TypeInfo> > {
    bounds := new Dictionary<string, List<TypeInfo> >(StringComparer.Ordinal)
    bounds[name] = new List<TypeInfo>()
    return bounds
}

func SyntheticBoundNames(bounds: List<TypeInfo>): string {
    rendered := ""
    index := 0
    while index < bounds.Count {
        if index > 0 {
            rendered = rendered + ","
        }

        rendered = rendered + SyntheticTypeName(bounds[index])
        index = index + 1
    }

    return rendered
}

// ------------------------------------------------------------------ the placement walk

test "positional arguments fill parameters left to right" {
    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    arguments.Add(SyntheticPositional("b"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(3), "f", SyntheticCall(arguments), 0)

    assert binding.Success == false
    assert SyntheticMap(binding) == "0,1"
    assert binding.Failures.Count == 1
    assert binding.Failures[0].ArgumentIndex == -1
    assert binding.Failures[0].ParameterIndex == 2
    assert binding.Failures[0].Message == "'f' needs an argument for parameter 'p3'"
}

test "a named argument reaches its parameter wherever it is written" {
    arguments := SyntheticArgs()
    arguments.Add(SyntheticNamed("p3", "c"))
    arguments.Add(SyntheticNamed("p1", "a"))
    arguments.Add(SyntheticNamed("p2", "b"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(3), "f", SyntheticCall(arguments), 0)

    assert binding.Success
    assert SyntheticMap(binding) == "2,0,1"
    assert binding.Failures.Count == 0
}

test "THE POSITIONAL CURSOR SKIPS A POSITION A NAME ALREADY CLAIMED" {
    // `f(a, p2: b, c)` — the third argument is positional and must land on p3, NOT on p2, because
    // p2 is already bound. A dense-prefix cursor would double-bind p2 and lose p3.
    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    arguments.Add(SyntheticNamed("p2", "b"))
    arguments.Add(SyntheticPositional("c"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(3), "f", SyntheticCall(arguments), 0)

    assert binding.Success
    assert SyntheticMap(binding) == "0,1,2"
}

test "an unknown parameter name fails the bind, names itself, AND LETS THE WALK CONTINUE" {
    arguments := SyntheticArgs()
    arguments.Add(SyntheticNamed("nope", "a"))
    arguments.Add(SyntheticNamed("alsoNope", "b"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(2), "f", SyntheticCall(arguments), 0)

    assert binding.Success == false
    // Both unknown names reported, then BOTH parameters reported missing — four failures, in
    // walk order, not one.
    assert binding.Failures.Count == 4
    assert binding.Failures[0].ArgumentIndex == 0
    assert binding.Failures[0].Message == "'f' has no parameter named 'nope'"
    assert binding.Failures[1].ArgumentIndex == 1
    assert binding.Failures[1].Message == "'f' has no parameter named 'alsoNope'"
    assert binding.Failures[2].ParameterIndex == 0
    assert binding.Failures[3].ParameterIndex == 1
    // THE MAP IS STILL PRODUCED: a failed placement leaves -1, it does not blank the array.
    assert SyntheticMap(binding) == "-1,-1"
}

test "the same parameter twice is a duplicate rather than a silent overwrite" {
    arguments := SyntheticArgs()
    arguments.Add(SyntheticNamed("p1", "a"))
    arguments.Add(SyntheticNamed("p1", "b"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(1), "f", SyntheticCall(arguments), 0)

    assert binding.Success == false
    assert binding.Failures.Count == 1
    assert binding.Failures[0].ArgumentIndex == 1
    assert binding.Failures[0].Message == "'f' got multiple values for parameter 'p1'"
    assert SyntheticMap(binding) == "0,-1"
}

test "an extra positional argument with no params tail is an overflow failure" {
    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    arguments.Add(SyntheticPositional("b"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(1), "f", SyntheticCall(arguments), 0)

    assert binding.Success == false
    assert binding.Failures.Count == 1
    assert binding.Failures[0].ArgumentIndex == 1
    assert binding.Failures[0].Message
        == "'f' got more positional arguments than its signature accepts"
}

test "every overflow argument falls into the params tail, and the tail counts as bound" {
    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    arguments.Add(SyntheticPositional("b"))
    arguments.Add(SyntheticPositional("c"))
    arguments.Add(SyntheticPositional("d"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticParams(1), "f", SyntheticCall(arguments), 0)

    assert binding.Success
    assert SyntheticMap(binding) == "0,1,1,1"
    assert binding.Failures.Count == 0
}

test "AN EMPTY PARAMS TAIL IS NOT SPECIAL-CASED — THE REQUIRED COUNT IS THE ONLY RULE" {
    // The missing-argument phase asks one question, `RequiredParameterCount`, and a params tail is
    // not exempt from it. A signature that does NOT declare a required count is required in full,
    // so its empty tail is reported; the analyzer's own params signatures declare one, and then the
    // empty tail binds. Special-casing the tail here would have made the two rules disagree.
    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    strict := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticParams(1), "f", SyntheticCall(arguments), 0)
    assert strict.Success == false
    assert strict.Failures.Count == 1
    assert strict.Failures[0].ParameterIndex == 1

    declared := SyntheticRequire(SyntheticParams(1), 1)
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        declared, "f", SyntheticCall(arguments), 0)
    assert binding.Success
    assert SyntheticMap(binding) == "0"
}

test "an optional parameter is not required, and a required one that is missing is named" {
    signature := SyntheticRequire(SyntheticPlain(3), 2)
    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        signature, "f", SyntheticCall(arguments), 0)

    assert binding.Success == false
    // p2 is required and missing; p3 is optional and is NOT reported.
    assert binding.Failures.Count == 1
    assert binding.Failures[0].ParameterIndex == 1
    assert binding.Failures[0].Message == "'f' needs an argument for parameter 'p2'"
}

test "a signature with no recorded names still names the position it wanted" {
    signature := new FunctionTypeInfo()
    signature.SyntheticName = "f"
    signature.ParameterTypes = SyntheticIntTypes(2)
    signature.ParameterModifiers = SyntheticModifiers(2)
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        signature, "f", SyntheticCall(SyntheticArgs()), 0)

    assert binding.Success == false
    assert binding.Failures.Count == 2
    assert binding.Failures[0].Message == "'f' needs an argument for parameter 'arg1'"
    assert binding.Failures[1].Message == "'f' needs an argument for parameter 'arg2'"
}

test "A RECEIVER-SUPPLIED PARAMETER MAY NOT BE NAMED, AND IS NOT REQUIRED" {
    // parameterStartIndex 1: p1 comes from the member-access receiver. Naming it is an unknown
    // name, not a duplicate, and leaving it out is not a missing argument.
    arguments := SyntheticArgs()
    arguments.Add(SyntheticNamed("p1", "a"))
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(2), "f", SyntheticMemberCall(arguments), 1)

    assert binding.Success == false
    assert binding.Failures.Count == 2
    assert binding.Failures[0].Message == "'f' has no parameter named 'p1'"
    assert binding.Failures[1].ParameterIndex == 1

    reachable := SyntheticArgs()
    reachable.Add(SyntheticPositional("b"))
    good := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(2), "f", SyntheticMemberCall(reachable), 1)
    assert good.Success
    assert SyntheticMap(good) == "1"
}

test "a receiver offset past the end of the signature is clamped rather than trusted" {
    binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(
        SyntheticPlain(1), "f", SyntheticCall(SyntheticArgs()), 9)

    assert binding.Success
    assert binding.Failures.Count == 0
}

test "the call target's name is the declaration's, then the written one, then the generic word" {
    named := new FunctionTypeInfo()
    named.SyntheticName = "declared"
    assert AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(
        named, SyntheticCall(SyntheticArgs())) == "declared"

    anonymous := new FunctionTypeInfo()
    assert AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(
        anonymous, SyntheticCall(SyntheticArgs())) == "f"
    assert AnalyzerSyntheticCallFacts.GetCallTargetName(
        SyntheticMemberCall(SyntheticArgs())) == "f"

    indexedCallee: Expression = new IndexAccessExpression(
        SyntheticIdentifier("table"), SyntheticIdentifier("i"), false, 1, 1)
    unnamed := new CallExpression(indexedCallee, SyntheticArgs(), null, 1, 1)
    assert AnalyzerSyntheticCallFacts.GetCallTargetName(unnamed) == null
    assert AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(anonymous, unnamed) == "function"
}

// ------------------------------------------------------------------ the specificity cost

test "the generic cost counts the arguments that landed on a BARE type-parameter position" {
    // `func f<T>(p1: T, p2: int)` called with two positional arguments: one direct match, cost 1.
    signature := SyntheticPlain(2)
    signature.TypeParameters = SyntheticTypeParameters("T")
    sourceTypes := new List<TypeReference>()
    sourceTypes.Add(new SimpleTypeReference("T", 0, 0))
    sourceTypes.Add(new SimpleTypeReference("int", 0, 0))
    signature.SourceParameterTypes = sourceTypes

    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    arguments.Add(SyntheticPositional("b"))
    argTypes := SyntheticTypeList2(BuiltInTypes.String, BuiltInTypes.Int)

    assert AnalyzerSyntheticCallFacts.GetGenericParameterCost(
        signature, SyntheticCall(arguments), argTypes) == 1
}

test "a written type costs nothing, and a signature with no type parameters costs nothing" {
    signature := SyntheticPlain(1)
    sourceTypes := new List<TypeReference>()
    sourceTypes.Add(new SimpleTypeReference("int", 0, 0))
    signature.SourceParameterTypes = sourceTypes

    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    argTypes := SyntheticTypeList(BuiltInTypes.Int)
    // No TypeParameters at all.
    assert AnalyzerSyntheticCallFacts.GetGenericParameterCost(
        signature, SyntheticCall(arguments), argTypes) == 0

    signature.TypeParameters = SyntheticTypeParameters("T")
    assert AnalyzerSyntheticCallFacts.GetGenericParameterCost(
        signature, SyntheticCall(arguments), argTypes) == 0
}

test "THE PARAMS TAIL IS COSTED THROUGH ITS ELEMENT, once per element argument" {
    // `func f<T>(params xs: T[])` called with three arguments costs 3 — the same as three separate
    // `T` parameters would, so a params overload is not made to look artificially specific.
    signature := SyntheticParams(0)
    signature.TypeParameters = SyntheticTypeParameters("T")
    elementRef: TypeReference = new SimpleTypeReference("T", 0, 0)
    sourceTypes := new List<TypeReference>()
    sourceTypes.Add(new ArrayTypeReference(elementRef))
    signature.SourceParameterTypes = sourceTypes

    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    arguments.Add(SyntheticPositional("b"))
    arguments.Add(SyntheticPositional("c"))
    argTypes := new List<TypeInfo>()
    argTypes.Add(BuiltInTypes.Int)
    argTypes.Add(BuiltInTypes.Int)
    argTypes.Add(BuiltInTypes.Int)

    assert AnalyzerSyntheticCallFacts.GetGenericParameterCost(
        signature, SyntheticCall(arguments), argTypes) == 3
}

test "a call whose arguments do not even place has no cost" {
    signature := SyntheticPlain(1)
    signature.TypeParameters = SyntheticTypeParameters("T")
    sourceTypes := new List<TypeReference>()
    sourceTypes.Add(new SimpleTypeReference("T", 0, 0))
    signature.SourceParameterTypes = sourceTypes

    arguments := SyntheticArgs()
    arguments.Add(SyntheticNamed("nope", "a"))
    argTypes := SyntheticTypeList(BuiltInTypes.Int)

    assert AnalyzerSyntheticCallFacts.GetGenericParameterCost(
        signature, SyntheticCall(arguments), argTypes) == 0
}

// ------------------------------------------------------------------ closing a signature

test "a bound type-parameter NAME is substituted at the leaves, in both representations" {
    bindings := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    bindings["T"] = BuiltInTypes.String

    external: TypeInfo = new ExternalTypeInfo("T")
    simple: TypeInfo = new SimpleTypeInfo("T")
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(external, bindings)) == "string"
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(simple, bindings)) == "string"

    // An UNBOUND name is left alone rather than replaced with a hole.
    unbound: TypeInfo = new SimpleTypeInfo("U")
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(unbound, bindings)) == "U"
}

test "substitution rebuilds every composite shell above the leaf" {
    bindings := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    bindings["T"] = BuiltInTypes.Int

    leaf: TypeInfo = new SimpleTypeInfo("T")
    arrayOfT: TypeInfo = new ArrayTypeInfo(leaf)
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(arrayOfT, bindings)) == "int[]"

    nullableOfT: TypeInfo = new NullableTypeInfo(leaf)
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(nullableOfT, bindings)) == "int?"

    obliviousOfT: TypeInfo = new ObliviousTypeInfo(leaf)
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(obliviousOfT, bindings)) == "int!"

    genericArguments := new List<TypeInfo>()
    genericArguments.Add(leaf)
    listOfT: TypeInfo = new GenericTypeInfo("List", genericArguments)
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(listOfT, bindings)) == "List<int>"
}

test "no bindings leaves the type exactly as it was" {
    empty := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    candidate: TypeInfo = new SimpleTypeInfo("T")
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(candidate, empty)) == "T"
    assert SyntheticTypeName(
        AnalyzerSyntheticCallFacts.ApplyGenericBindings(candidate, null)) == "T"
}

// ------------------------------------------------------------------ the least upper bound

test "the numeric widening order admits both spellings and refuses a mixed list" {
    assert SyntheticTypeName(AnalyzerSyntheticCallFacts.TryComputeNumericLub(
        SyntheticTypeList2(BuiltInTypes.Byte, BuiltInTypes.Long))) == "long"
    assert SyntheticTypeName(AnalyzerSyntheticCallFacts.TryComputeNumericLub(
        SyntheticTypeList2(BuiltInTypes.Float, BuiltInTypes.Decimal))) == "decimal"
    assert SyntheticTypeName(AnalyzerSyntheticCallFacts.TryComputeNumericLub(
        SyntheticTypeList2(BuiltInTypes.Short, BuiltInTypes.Double))) == "double"

    // The CLR spelling reads the same as the keyword — one bound may be written in source and
    // another read from metadata for the same type parameter.
    clrInt: TypeInfo = new SimpleTypeInfo("System.Int32")
    assert SyntheticTypeName(AnalyzerSyntheticCallFacts.TryComputeNumericLub(
        SyntheticTypeList2(clrInt, BuiltInTypes.Byte))) == "int"

    // ONE non-numeric member answers null for the WHOLE list rather than a partial answer.
    assert AnalyzerSyntheticCallFacts.TryComputeNumericLub(
        SyntheticTypeList2(BuiltInTypes.Int, BuiltInTypes.String)) == null
}

test "the least upper bound is object, the single bound, then a common supertype" {
    binder := SyntheticBinder()

    assert SyntheticTypeName(binder.ComputeLeastUpperBound(new List<TypeInfo>())) == "object"
    assert SyntheticTypeName(
        binder.ComputeLeastUpperBound(SyntheticTypeList(BuiltInTypes.String))) == "string"
    assert SyntheticTypeName(binder.ComputeLeastUpperBound(
        SyntheticTypeList2(BuiltInTypes.Int, BuiltInTypes.Int))) == "int"

    // THE COMMON-SUPERTYPE RULE RUNS BEFORE THE NUMERIC ONE: `int`/`double` answers `double`
    // because `int` converts to it, not because the widening table says so.
    assert SyntheticTypeName(binder.ComputeLeastUpperBound(
        SyntheticTypeList2(BuiltInTypes.Int, BuiltInTypes.Double))) == "double"

    // Nothing in common is `object` — the conservative answer, deliberately not a failure.
    assert SyntheticTypeName(binder.ComputeLeastUpperBound(
        SyntheticTypeList2(BuiltInTypes.String, BuiltInTypes.Bool))) == "object"
}

// ------------------------------------------------------------------ the argument comparison

test "an ordinary position compares the parameter's type against the argument's" {
    binder := SyntheticBinder()
    argTypes := SyntheticTypeList2(BuiltInTypes.Int, BuiltInTypes.String)
    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    arguments.Add(SyntheticPositional("b"))

    comparison := binder.GetArgumentComparisonTypes(
        SyntheticPlain(2), SyntheticCall(arguments), argTypes, 1, 1, -1, 0, null)

    assert comparison.Matched
    assert SyntheticTypeName(comparison.ExpectedType) == "int"
    assert SyntheticTypeName(comparison.ArgumentType) == "string"
}

test "a position outside the signature does not match at all" {
    binder := SyntheticBinder()
    argTypes := SyntheticTypeList(BuiltInTypes.Int)
    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))

    comparison := binder.GetArgumentComparisonTypes(
        SyntheticPlain(1), SyntheticCall(arguments), argTypes, 0, 7, -1, 0, null)

    assert comparison.Matched == false
}

test "A DIRECT PARAMS ARRAY IS COMPARED WHOLE, AN EXPANDED TAIL ELEMENT BY ELEMENT" {
    binder := SyntheticBinder()
    signature := SyntheticParams(0)

    // `f(xs)` where `xs: int[]` — passed straight through, so the ARRAY is compared.
    directArguments := SyntheticArgs()
    directArguments.Add(SyntheticPositional("xs"))
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    directTypes := SyntheticTypeList(arrayType)
    direct := binder.GetArgumentComparisonTypes(
        signature, SyntheticCall(directArguments), directTypes, 0, 0, 0, 0, null)
    assert direct.Matched
    assert SyntheticTypeName(direct.ExpectedType) == "int[]"
    assert SyntheticTypeName(direct.ArgumentType) == "int[]"

    // `f(a, b)` — an expanded tail: the parameter contributes its ELEMENT, the argument stays whole.
    expandedArguments := SyntheticArgs()
    expandedArguments.Add(SyntheticPositional("a"))
    expandedArguments.Add(SyntheticPositional("b"))
    expandedTypes := SyntheticTypeList2(BuiltInTypes.Int, BuiltInTypes.Int)
    expanded := binder.GetArgumentComparisonTypes(
        signature, SyntheticCall(expandedArguments), expandedTypes, 0, 0, 0, 0, null)
    assert expanded.Matched
    assert SyntheticTypeName(expanded.ExpectedType) == "int"
    assert SyntheticTypeName(expanded.ArgumentType) == "int"
}

test "a spread compares element to element, and an unknown spread carries no information" {
    binder := SyntheticBinder()
    signature := SyntheticParams(0)

    spreadArguments := SyntheticArgs()
    spreadArguments.Add(SyntheticSpread("xs"))
    longArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Long)
    spread := binder.GetArgumentComparisonTypes(
        signature, SyntheticCall(spreadArguments), SyntheticTypeList(longArray), 0, 0, 0, 0, null)
    assert spread.Matched
    assert SyntheticTypeName(spread.ExpectedType) == "int"
    assert SyntheticTypeName(spread.ArgumentType) == "long"

    // An unknown spread MATCHES with no types — a different answer from "does not match", so the
    // candidate survives instead of being eliminated by an error-recovery type.
    unknownType: TypeInfo = BuiltInTypes.Unknown
    unknown := binder.GetArgumentComparisonTypes(
        signature, SyntheticCall(spreadArguments), SyntheticTypeList(unknownType), 0, 0, 0, 0, null)
    assert unknown.Matched
    assert unknown.ExpectedType == null
    assert unknown.ArgumentType == null
}

test "a params parameter that is not an array describes nothing and is SKIPPED, not failed" {
    binder := SyntheticBinder()
    // A malformed signature: the params position's type is a scalar.
    names := SyntheticNames(1)
    types := SyntheticIntTypes(1)
    modifiers := new List<ParameterModifier>()
    modifiers.Add(ParameterModifier.Params)
    signature := SyntheticSignature(names, types, modifiers)
    signature.HasParamsParameter = true

    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    comparison := binder.GetArgumentComparisonTypes(
        signature, SyntheticCall(arguments), SyntheticTypeList(BuiltInTypes.Int), 0, 0, 0, 0, null)

    assert comparison.Matched
    assert comparison.ExpectedType == null
    assert comparison.ArgumentType == null
}

test "the comparison closes the parameter type with the inferred bindings first" {
    binder := SyntheticBinder()
    openParameter: TypeInfo = new SimpleTypeInfo("T")
    types := new List<TypeInfo>()
    types.Add(openParameter)
    signature := SyntheticSignature(
        SyntheticNames(1), types, SyntheticModifiers(1))

    bindings := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    bindings["T"] = BuiltInTypes.String

    arguments := SyntheticArgs()
    arguments.Add(SyntheticPositional("a"))
    comparison := binder.GetArgumentComparisonTypes(
        signature, SyntheticCall(arguments), SyntheticTypeList(BuiltInTypes.String), 0, 0, -1, 0, bindings)

    assert comparison.Matched
    assert SyntheticTypeName(comparison.ExpectedType) == "string"
}

// ------------------------------------------------------------------ the collecting walk

test "a bare type-parameter name binds, and EVERY sighting contributes a bound" {
    binder := SyntheticBinder()
    typeParameters := SyntheticTypeParameters("T")
    bounds := SyntheticBounds("T")
    reference: TypeReference = new SimpleTypeReference("T", 0, 0)

    binder.CollectTypeParameterBounds(reference, BuiltInTypes.Int, typeParameters, bounds)
    binder.CollectTypeParameterBounds(reference, BuiltInTypes.Double, typeParameters, bounds)

    // TWO bounds, not one — the LUB is computed later, rather than the first sighting winning.
    assert bounds["T"].Count == 2
    assert SyntheticBoundNames(bounds["T"]) == "int,double"
}

test "unknown and null argument types carry no information and are dropped" {
    binder := SyntheticBinder()
    typeParameters := SyntheticTypeParameters("T")
    bounds := SyntheticBounds("T")
    reference: TypeReference = new SimpleTypeReference("T", 0, 0)

    unknownType: TypeInfo = BuiltInTypes.Unknown
    nullType: TypeInfo = BuiltInTypes.Null
    binder.CollectTypeParameterBounds(reference, unknownType, typeParameters, bounds)
    binder.CollectTypeParameterBounds(reference, nullType, typeParameters, bounds)

    assert bounds["T"].Count == 0
}

test "a name that is not a type parameter binds nothing" {
    binder := SyntheticBinder()
    typeParameters := SyntheticTypeParameters("T")
    bounds := SyntheticBounds("T")
    reference: TypeReference = new SimpleTypeReference("int", 0, 0)

    binder.CollectTypeParameterBounds(reference, BuiltInTypes.Int, typeParameters, bounds)
    assert bounds["T"].Count == 0
}

test "the walk descends through generic, array, nullable and by-ref shapes" {
    binder := SyntheticBinder()
    typeParameters := SyntheticTypeParameters("T")
    elementReference: TypeReference = new SimpleTypeReference("T", 0, 0)

    genericArguments := new List<TypeReference>()
    genericArguments.Add(elementReference)
    listOfT: TypeReference = new GenericTypeReference("List", genericArguments, 0, 0)
    listArguments := new List<TypeInfo>()
    listArguments.Add(BuiltInTypes.Int)
    listOfInt: TypeInfo = new GenericTypeInfo("List", listArguments)
    genericBounds := SyntheticBounds("T")
    binder.CollectTypeParameterBounds(listOfT, listOfInt, typeParameters, genericBounds)
    assert SyntheticBoundNames(genericBounds["T"]) == "int"

    arrayOfT: TypeReference = new ArrayTypeReference(elementReference)
    arrayOfString: TypeInfo = new ArrayTypeInfo(BuiltInTypes.String)
    arrayBounds := SyntheticBounds("T")
    binder.CollectTypeParameterBounds(arrayOfT, arrayOfString, typeParameters, arrayBounds)
    assert SyntheticBoundNames(arrayBounds["T"]) == "string"

    byRefOfT: TypeReference = new ByRefTypeReference(elementReference)
    byRefOfLong: TypeInfo = new ByRefTypeInfo(BuiltInTypes.Long)
    byRefBounds := SyntheticBounds("T")
    binder.CollectTypeParameterBounds(byRefOfT, byRefOfLong, typeParameters, byRefBounds)
    assert SyntheticBoundNames(byRefBounds["T"]) == "long"
}

test "A NULLABLE REFERENCE INFERS FROM A NON-NULLABLE ARGUMENT TOO" {
    binder := SyntheticBinder()
    typeParameters := SyntheticTypeParameters("T")
    elementReference: TypeReference = new SimpleTypeReference("T", 0, 0)
    nullableOfT: TypeReference = new NullableTypeReference(elementReference)

    nullableBounds := SyntheticBounds("T")
    nullableOfInt: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    binder.CollectTypeParameterBounds(nullableOfT, nullableOfInt, typeParameters, nullableBounds)
    assert SyntheticBoundNames(nullableBounds["T"]) == "int"

    // `T?` matched against a plain `T` still tells you what `T` is.
    plainBounds := SyntheticBounds("T")
    binder.CollectTypeParameterBounds(nullableOfT, BuiltInTypes.String, typeParameters, plainBounds)
    assert SyntheticBoundNames(plainBounds["T"]) == "string"
}

test "a generic head whose arity or name disagrees contributes nothing" {
    binder := SyntheticBinder()
    typeParameters := SyntheticTypeParameters("T")
    elementReference: TypeReference = new SimpleTypeReference("T", 0, 0)
    genericArguments := new List<TypeReference>()
    genericArguments.Add(elementReference)
    listOfT: TypeReference = new GenericTypeReference("List", genericArguments, 0, 0)

    otherArguments := new List<TypeInfo>()
    otherArguments.Add(BuiltInTypes.Int)
    setOfInt: TypeInfo = new GenericTypeInfo("HashSet", otherArguments)
    bounds := SyntheticBounds("T")
    binder.CollectTypeParameterBounds(listOfT, setOfInt, typeParameters, bounds)
    assert bounds["T"].Count == 0

    // The head name is namespace-tolerant, so the QUALIFIED spelling still matches.
    qualifiedArguments := new List<TypeInfo>()
    qualifiedArguments.Add(BuiltInTypes.Int)
    qualified: TypeInfo = new GenericTypeInfo("System.Collections.Generic.List", qualifiedArguments)
    qualifiedBounds := SyntheticBounds("T")
    binder.CollectTypeParameterBounds(listOfT, qualified, typeParameters, qualifiedBounds)
    assert SyntheticBoundNames(qualifiedBounds["T"]) == "int"
}

test "a generic reference descends into a ReflectionTypeInfo read from metadata" {
    binder := SyntheticBinder()
    typeParameters := SyntheticTypeParameters("T")
    elementReference: TypeReference = new SimpleTypeReference("T", 0, 0)
    genericArguments := new List<TypeReference>()
    genericArguments.Add(elementReference)
    listOfT: TypeReference = new GenericTypeReference("List", genericArguments, 0, 0)

    definition := Type.GetType("System.Collections.Generic.List`1")
    assert definition != null
    closedArguments := new Type[](1)
    closedArguments[0] = typeof(string)
    closed := definition.MakeGenericType(closedArguments)
    reflected: TypeInfo = new ReflectionTypeInfo(closed)

    bounds := SyntheticBounds("T")
    binder.CollectTypeParameterBounds(listOfT, reflected, typeParameters, bounds)
    // The arity suffix comes off the CLR name before the heads are compared.
    assert bounds["T"].Count == 1
}

test "a function reference descends into every parameter it shares and the return" {
    binder := SyntheticBinder()
    typeParameters := SyntheticTypeParameters("T")
    elementReference: TypeReference = new SimpleTypeReference("T", 0, 0)
    referenceParameters := new List<TypeReference>()
    referenceParameters.Add(elementReference)
    funcOfT: TypeReference = new FunctionTypeReference(referenceParameters, elementReference)

    lambdaSignature := new FunctionTypeInfo()
    lambdaParameters := new List<TypeInfo>()
    lambdaParameters.Add(BuiltInTypes.Int)
    lambdaSignature.ParameterTypes = lambdaParameters
    lambdaSignature.ReturnType = BuiltInTypes.String

    bounds := SyntheticBounds("T")
    lambdaType: TypeInfo = lambdaSignature
    binder.CollectTypeParameterBounds(funcOfT, lambdaType, typeParameters, bounds)
    assert SyntheticBoundNames(bounds["T"]) == "int,string"

    // A non-function argument against a function reference contributes nothing.
    emptyBounds := SyntheticBounds("T")
    binder.CollectTypeParameterBounds(funcOfT, BuiltInTypes.Int, typeParameters, emptyBounds)
    assert emptyBounds["T"].Count == 0
}
