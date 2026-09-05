namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the reflection binder's pure interior.
//
// Every member behind these was `private` in Analyzer.cs, so nothing named any of them: the argument
// binding walk was pinned only indirectly, through end-to-end NL402 diagnostics. This is its first
// DIRECT pinning, and it goes at the decisions a reader cannot recover from a single arm:
//
//   * the walk is THREE ORDERED PHASES — place, then default-fill, then score — and a named argument
//     may legally fill a position AFTER one that defaults, which is why filling cannot run first;
//   * the params tail is TWO different bindings, and an EXPANDED tail records the ELEMENT type as
//     each element's open parameter type, which is the only evidence the expansion ever happened;
//   * the direct-versus-expanded choice runs on a TRIAL COPY of the bindings, so a refused direct
//     pass leaves no generic inference behind;
//   * by-ref direction is an EQUALITY, and a params ELEMENT is exempt from it;
//   * the score ladder orders candidates by how much the compiler had to assume, and the
//     broad-delegate lambda scores strictly below a lambda with a known delegate signature;
//   * a method group picks its BEST overload and a tie is a non-binding, never an arbitrary choice;
//   * `Action`/`Func` signatures are read STRUCTURALLY from their type arguments rather than through
//     `Invoke`, because the open form's `Invoke` would lose the N# TypeInfo overrides.
func BinderRuntimeType(canonicalName: string): Type {
    resolved := Type.GetType(canonicalName)
    if resolved == null {
        throw new InvalidOperationException("The runtime does not define '" + canonicalName + "'.")
    }

    return resolved
}

func BinderClosed2(canonicalName: string, first: Type, second: Type): Type {
    definition := BinderRuntimeType(canonicalName)
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return definition.MakeGenericType(arguments)
}

func BinderContext(): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    return context
}

func BinderResolver(
    scopes: AnalyzerScopeStack,
    context: AnalyzerDeclarationContext
): AnalyzerTypeResolver {
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    return new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        new AnalyzerDiagnosticSink(new List<CompilerError>(), provider),
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal),
        new SemanticModel(),
        new BindingMap()
    )
}

// The binder with NO well-known-type bag. Every arm but the delegate ones runs in this state, and
// the delegate ones DELIBERATELY refuse in it: without the bag nothing is a delegate.
func BinderDefault(): AnalyzerReflectionArgumentBinder {
    return BinderFor(null)
}

// The same binder WITH a bag read out of a MetadataLoadContext, which is how the analyzer sees an
// external assembly.
func BinderFor(wellKnown: AnalyzerWellKnownTypes?): AnalyzerReflectionArgumentBinder {
    context := BinderContext()
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    resolver := BinderResolver(scopes, context)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, wellKnown)
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, wellKnown)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(
        context,
        facts,
        structural,
        substitution,
        clrConversion,
        guard
    )
    scoring := new AnalyzerOverloadScoring(
        context,
        clrConversion,
        assignability,
        resolver,
        wellKnown
    )
    return new AnalyzerReflectionArgumentBinder(clrConversion, assignability, facts, scoring, resolver)
}

func BinderWellKnown(loadContext: MetadataLoadContext): AnalyzerWellKnownTypes {
    core := loadContext.LoadFromAssemblyName("System.Runtime")
    return new AnalyzerWellKnownTypes(loadContext, core)
}

// A type read THROUGH the MetadataLoadContext. The delegate arms are only reachable this way: the
// well-known bag's `System.Delegate` is the CONTEXT'S, so a LIVE `Func<int,int>` is not assignable
// to it and the analyzer would not call it a delegate either.
func BinderMlcType(wellKnown: AnalyzerWellKnownTypes, fullName: string): Type {
    coreAssembly := wellKnown.Delegate.get_Assembly()
    resolved := coreAssembly.GetType(fullName)
    if resolved == null {
        throw new InvalidOperationException(
            "The load context does not define '" + fullName + "'."
        )
    }

    return resolved
}

func BinderClosed(definition: Type?, first: Type): Type {
    if definition == null {
        throw new InvalidOperationException("A required open generic definition is missing.")
    }

    arguments := new Type[](1)
    arguments[0] = first
    return definition.MakeGenericType(arguments)
}

func BinderClosedPair(definition: Type?, first: Type, second: Type): Type {
    if definition == null {
        throw new InvalidOperationException("A required open generic definition is missing.")
    }

    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return definition.MakeGenericType(arguments)
}

// ------------------------------------------------------------------ the reflected surface

// `string.Format(string, params object[])` — the params tail every params contract here binds
// against, chosen because it is a REAL declaration carrying a real `ParamArrayAttribute`.
func BinderFormatMethod(): MethodInfo {
    stringType := BinderRuntimeType("System.String, System.Private.CoreLib")
    methods := stringType.GetMethods()
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == "Format" {
            parameters := candidate.GetParameters()
            if parameters.Length == 2 {
                first := parameters[0].get_ParameterType()
                second := parameters[1].get_ParameterType()
                if first == typeof(string) && second == typeof(object[]) {
                    return candidate
                }
            }
        }

        index = index + 1
    }

    throw new InvalidOperationException("string.Format(string, object[]) was not found.")
}

// `string.Substring(int)` and `string.Substring(int, int)` — the fixed-arity pair, and the one whose
// parameter is genuinely NAMED (`startIndex`), which the named-argument contracts address.
func BinderSubstringMethod(argumentCount: int): MethodInfo {
    stringType := BinderRuntimeType("System.String, System.Private.CoreLib")
    methods := stringType.GetMethods()
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == "Substring" && candidate.GetParameters().Length == argumentCount {
            return candidate
        }

        index = index + 1
    }

    throw new InvalidOperationException("string.Substring was not found.")
}

// `int.TryParse(string, out int)` — the by-ref direction contracts' subject.
func BinderTryParseMethod(): MethodInfo {
    intType := BinderRuntimeType("System.Int32, System.Private.CoreLib")
    methods := intType.GetMethods()
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == "TryParse" {
            parameters := candidate.GetParameters()
            if parameters.Length == 2 && parameters[0].get_ParameterType() == typeof(string) && parameters[1].get_ParameterType().get_IsByRef() {
                return candidate
            }
        }

        index = index + 1
    }

    throw new InvalidOperationException("int.TryParse(string, out int) was not found.")
}

// The one BCL method here with a genuinely OPTIONAL parameter, so the default-filling phase binds
// against a real `[opt]` declaration rather than a synthetic one.
func BinderOptionalMethod(): MethodInfo {
    stringType := BinderRuntimeType("System.String, System.Private.CoreLib")
    methods := stringType.GetMethods()
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        parameters := candidate.GetParameters()
        if parameters.Length > 1 && parameters[parameters.Length - 1].get_IsOptional() {
            return candidate
        }

        index = index + 1
    }

    throw new InvalidOperationException("No optional-parameter method was found on System.String.")
}

// ------------------------------------------------------------------ call shapes

func BinderIdentifier(name: string): Expression {
    return new IdentifierExpression(name, 1, 1)
}

func BinderCall(arguments: List<Argument>): CallExpression {
    return new CallExpression(BinderIdentifier("target"), arguments, null, 1, 1)
}

func BinderArguments(): List<Argument> {
    return new List<Argument>()
}

func BinderPositional(name: string): Argument {
    return new Argument(null, BinderIdentifier(name), ArgumentModifier.None)
}

func BinderNamed(parameterName: string, valueName: string): Argument {
    return new Argument(parameterName, BinderIdentifier(valueName), ArgumentModifier.None)
}

func BinderOut(name: string): Argument {
    return new Argument(null, BinderIdentifier(name), ArgumentModifier.Out)
}

func BinderDefaultArgument(): Argument {
    return new Argument(null, new DefaultExpression(1, 1), ArgumentModifier.None)
}

func BinderSpread(name: string): Argument {
    return new Argument(null, new SpreadExpression(BinderIdentifier(name), 1, 1), ArgumentModifier.None)
}

func BinderLambda(parameterCount: int, typeName: string): Argument {
    parameters := new List<Parameter>()
    index := 0
    while index < parameterCount {
        parameterType: TypeReference = new SimpleTypeReference(typeName, 0, 0)
        parameterName := "p" + index.ToString()
        parameter := new Parameter(
            parameterName,
            parameterType,
            null,
            false,
            ParameterModifier.None,
            null,
            1,
            1,
            false,
            null
        )
        parameters.Add(parameter)
        index = index + 1
    }

    lambdaValue: Expression = new LambdaExpression(parameters, BinderIdentifier("p"), null, 1, 1)
    return new Argument(null, lambdaValue, ArgumentModifier.None)
}

func BinderAnalyzed(values: List<TypeInfo?>): TypeInfo?[] {
    analyzed := new TypeInfo?[](values.Count)
    index := 0
    while index < values.Count {
        analyzed[index] = values[index]
        index = index + 1
    }

    return analyzed
}

func BinderAnalyzed1(first: TypeInfo?): TypeInfo?[] {
    values := new List<TypeInfo?>()
    values.Add(first)
    return BinderAnalyzed(values)
}

func BinderAnalyzed2(first: TypeInfo?, second: TypeInfo?): TypeInfo?[] {
    values := new List<TypeInfo?>()
    values.Add(first)
    values.Add(second)
    return BinderAnalyzed(values)
}

func BinderAnalyzed3(first: TypeInfo?, second: TypeInfo?, third: TypeInfo?): TypeInfo?[] {
    values := new List<TypeInfo?>()
    values.Add(first)
    values.Add(second)
    values.Add(third)
    return BinderAnalyzed(values)
}

// A DECLARED source function: only a declaration records a source name, and that is the
// method-group-versus-lambda discriminator the delegate arm keys on.
func BinderSourceFunction(name: string, parameter: TypeInfo, returnType: TypeInfo): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SyntheticName = name
    signature.SourceName = name
    signature.SourceContainingType = ""
    signature.SourceLine = 1
    signature.SourceColumn = 1
    signature.SourceParameterCount = 1
    parameterTypes := new List<TypeInfo>()
    parameterTypes.Add(parameter)
    signature.ParameterTypes = parameterTypes
    modifiers := new List<ParameterModifier>()
    modifiers.Add(ParameterModifier.None)
    signature.ParameterModifiers = modifiers
    signature.ReturnType = returnType
    return signature
}

func BinderAnonymousFunction(parameter: TypeInfo, returnType: TypeInfo): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    parameterTypes := new List<TypeInfo>()
    parameterTypes.Add(parameter)
    signature.ParameterTypes = parameterTypes
    modifiers := new List<ParameterModifier>()
    modifiers.Add(ParameterModifier.None)
    signature.ParameterModifiers = modifiers
    signature.ReturnType = returnType
    return signature
}

func BinderTypeName(typeInfo: TypeInfo?): string {
    if typeInfo == null {
        return "<null>"
    }

    typeObject := typeInfo as object
    return typeObject.ToString()
}

// ------------------------------------------------------------------ the walk

test "the binding walk places written arguments before it fills any default" {
    binder := BinderDefault()
    method := BinderOptionalMethod()
    parameters := method.GetParameters()

    // Every position supplied: nothing defaults.
    arguments := BinderArguments()
    index := 0
    while index < parameters.Length {
        arguments.Add(BinderPositional("a" + index.ToString()))
        index = index + 1
    }

    analyzedValues := new List<TypeInfo?>()
    index = 0
    while index < parameters.Length {
        analyzedValues.Add(AnalyzerReflectionTypeConversion.ConvertReflectionType(
            AnalyzerOverloadFacts.GetByRefElementType(parameters[index].get_ParameterType())
        ))
        index = index + 1
    }

    bound := new List<ReflectionBoundArgument>()
    score := 0
    usesParams := false
    defaultsUsed := 0
    assert binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(arguments),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed(analyzedValues),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )
    assert defaultsUsed == 0
    assert bound.Count == parameters.Length

    // The SAME candidate with the optional tail omitted fills it from the declaration.
    shortArguments := BinderArguments()
    index = 0
    while index < parameters.Length - 1 {
        shortArguments.Add(BinderPositional("a" + index.ToString()))
        index = index + 1
    }

    shortAnalyzed := new List<TypeInfo?>()
    index = 0
    while index < parameters.Length - 1 {
        shortAnalyzed.Add(analyzedValues[index])
        index = index + 1
    }

    assert binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(shortArguments),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed(shortAnalyzed),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )
    assert defaultsUsed == 1
    lastBound := bound[bound.Count - 1]
    filled := lastBound as DefaultReflectionBoundArgument
    assert filled != null
    assert filled.Parameter.get_IsOptional()
}

test "a named argument binds by name and a name that does not match fails the candidate" {
    binder := BinderDefault()
    method := BinderSubstringMethod(1)
    parameters := method.GetParameters()
    parameterName := parameters[0].get_Name()
    assert parameterName != null

    named := BinderArguments()
    named.Add(BinderNamed(parameterName, "x"))
    bound := new List<ReflectionBoundArgument>()
    score := 0
    usesParams := false
    defaultsUsed := 0
    assert binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(named),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(BuiltInTypes.Int),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )
    supplied := bound[0] as SuppliedReflectionBoundArgument
    assert supplied != null
    assert supplied.ParameterIndex == 0
    assert supplied.ArgumentIndex == 0

    // An unknown name is not a position at all.
    unknown := BinderArguments()
    unknown.Add(BinderNamed("thisIsNotAParameter", "x"))
    assert !binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(unknown),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(BuiltInTypes.Int),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )

    // A name that lands on a position already taken is a DOUBLE binding, also a refusal.
    duplicated := BinderArguments()
    duplicated.Add(BinderNamed(parameterName, "x"))
    duplicated.Add(BinderNamed(parameterName, "y"))
    assert !binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(duplicated),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed2(BuiltInTypes.Int, BuiltInTypes.Int),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )
}

test "a receiver offset position is never supplied by name and never filled" {
    binder := BinderDefault()
    method := BinderSubstringMethod(2)
    parameters := method.GetParameters()
    firstName := parameters[0].get_Name()
    assert firstName != null

    // With the offset the first position belongs to the RECEIVER, so naming it is not a binding.
    named := BinderArguments()
    named.Add(BinderNamed(firstName, "x"))
    bound := new List<ReflectionBoundArgument>()
    score := 0
    usesParams := false
    defaultsUsed := 0
    assert !binder.TryBindReflectionArguments(
        parameters,
        1,
        BinderCall(named),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(BuiltInTypes.Int),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )

    // One positional argument now fills the SECOND position, and the bound list never carries the
    // receiver's own.
    positional := BinderArguments()
    positional.Add(BinderPositional("x"))
    assert binder.TryBindReflectionArguments(
        parameters,
        1,
        BinderCall(positional),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(BuiltInTypes.Int),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )
    assert bound.Count == 1
    supplied := bound[0] as SuppliedReflectionBoundArgument
    assert supplied != null
    assert supplied.ParameterIndex == 1
}

test "a params tail expands into elements that record the ELEMENT type" {
    binder := BinderDefault()
    method := BinderFormatMethod()
    parameters := method.GetParameters()

    arguments := BinderArguments()
    arguments.Add(BinderPositional("format"))
    arguments.Add(BinderPositional("a"))
    arguments.Add(BinderPositional("b"))
    bound := new List<ReflectionBoundArgument>()
    score := 0
    usesParams := false
    defaultsUsed := 0
    assert binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(arguments),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed3(BuiltInTypes.String, BuiltInTypes.Int, BuiltInTypes.String),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )
    assert usesParams
    assert bound.Count == 2

    expanded := bound[1] as ParamsReflectionBoundArgument
    assert expanded != null
    assert expanded.OpenParameterType == typeof(object[])
    assert expanded.OpenElementType == typeof(object)
    assert expanded.Arguments.Count == 2

    // THE EVIDENCE OF EXPANSION: each element records the ELEMENT type as its own open parameter
    // type, which differs from the declared array — and that is exactly what the expansion question
    // reads. A directly passed array records the ARRAY.
    element := expanded.Arguments[0]
    assert element.OpenParameterType == typeof(object)
    assert element.ParameterIndex == 1
    assert element.ArgumentIndex == 1
    assert AnalyzerOverloadFacts.IsExpandedReflectionParamsArgument(element, parameters[1])

    // The flattening reads those materialized elements rather than re-expanding the tail.
    flattened := binder.EnumerateSuppliedReflectionArguments(bound)
    assert flattened.Count == 3
    firstFlattened := flattened[1] as object
    firstElement := expanded.Arguments[0] as object
    secondFlattened := flattened[2] as object
    secondElement := expanded.Arguments[1] as object
    assert Object.ReferenceEquals(firstFlattened, firstElement)
    assert Object.ReferenceEquals(secondFlattened, secondElement)
}

test "a single trailing array is passed DIRECTLY and records the array type" {
    binder := BinderDefault()
    method := BinderFormatMethod()
    parameters := method.GetParameters()

    arguments := BinderArguments()
    arguments.Add(BinderPositional("format"))
    arguments.Add(BinderPositional("values"))
    objectArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Object)
    bound := new List<ReflectionBoundArgument>()
    score := 0
    usesParams := false
    defaultsUsed := 0
    assert binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(arguments),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed2(BuiltInTypes.String, objectArray),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )

    direct := bound[1] as SuppliedReflectionBoundArgument
    assert direct != null
    assert direct.OpenParameterType == typeof(object[])
    assert !AnalyzerOverloadFacts.IsExpandedReflectionParamsArgument(direct, parameters[1])

    // A SPREAD of the same array is the expansion, never the direct pass.
    spreadArguments := BinderArguments()
    spreadArguments.Add(BinderPositional("format"))
    spreadArguments.Add(BinderSpread("values"))
    assert binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(spreadArguments),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed2(BuiltInTypes.String, objectArray),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )
    assert bound[1] is ParamsReflectionBoundArgument

    // An EMPTY tail is still a params binding with no elements.
    emptyArguments := BinderArguments()
    emptyArguments.Add(BinderPositional("format"))
    assert binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(emptyArguments),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(BuiltInTypes.String),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )
    emptyTail := bound[1] as ParamsReflectionBoundArgument
    assert emptyTail != null
    assert emptyTail.Arguments.Count == 0
    assert binder.EnumerateSuppliedReflectionArguments(bound).Count == 1
}

test "the direct-params question answers on a TRIAL copy and leaves the bindings alone" {
    binder := BinderDefault()
    genericParameter := BinderRuntimeType("System.Func`2, System.Private.CoreLib").GetGenericArguments()[0]
    openArray := genericParameter.MakeArrayType()

    bindings := new Dictionary<Type, Type>()
    intArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    assert binder.ShouldPassReflectionParamsArgumentDirectly(
        BinderPositional("values"),
        0,
        openArray,
        bindings,
        BinderAnalyzed1(intArray)
    )

    // The match BOUND the open element type — but only inside the trial copy.
    assert bindings.Count == 0

    // A spread is the expansion; an explicit `default` is the null ARRAY, so it always is direct;
    // a lambda has no type until a delegate context exists.
    assert !binder.ShouldPassReflectionParamsArgumentDirectly(
        BinderSpread("values"),
        0,
        typeof(object[]),
        bindings,
        BinderAnalyzed1(intArray)
    )
    assert binder.ShouldPassReflectionParamsArgumentDirectly(
        BinderDefaultArgument(),
        0,
        typeof(object[]),
        bindings,
        BinderAnalyzed1(null)
    )
    assert !binder.ShouldPassReflectionParamsArgumentDirectly(
        BinderLambda(1, "int"),
        0,
        typeof(object[]),
        bindings,
        BinderAnalyzed1(null)
    )

    // An UNKNOWN or untyped argument is not the array either.
    assert !binder.ShouldPassReflectionParamsArgumentDirectly(
        BinderPositional("values"),
        0,
        typeof(object[]),
        bindings,
        BinderAnalyzed1(BuiltInTypes.Unknown)
    )
    assert !binder.ShouldPassReflectionParamsArgumentDirectly(
        BinderPositional("values"),
        0,
        typeof(object[]),
        bindings,
        BinderAnalyzed1(null)
    )

    // A loose element is not the array.
    assert !binder.ShouldPassReflectionParamsArgumentDirectly(
        BinderPositional("value"),
        0,
        typeof(int[]),
        bindings,
        BinderAnalyzed1(BuiltInTypes.Int)
    )
}

test "by-ref direction is an equality and a params element is exempt from it" {
    binder := BinderDefault()
    method := BinderTryParseMethod()
    parameters := method.GetParameters()

    matching := BinderArguments()
    matching.Add(BinderPositional("text"))
    matching.Add(BinderOut("parsed"))
    bound := new List<ReflectionBoundArgument>()
    score := 0
    usesParams := false
    defaultsUsed := 0
    assert binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(matching),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed2(BuiltInTypes.String, BuiltInTypes.Int),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )

    // The by-ref shell is stripped off the recorded open parameter type.
    outBound := bound[1] as SuppliedReflectionBoundArgument
    assert outBound != null
    assert outBound.OpenParameterType == typeof(int)

    // A MISSING modifier is a refusal, not a widening.
    missing := BinderArguments()
    missing.Add(BinderPositional("text"))
    missing.Add(BinderPositional("parsed"))
    assert !binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(missing),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed2(BuiltInTypes.String, BuiltInTypes.Int),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )

    // And so is a modifier the declaration did not ask for.
    extra := BinderArguments()
    extra.Add(BinderOut("text"))
    extra.Add(BinderOut("parsed"))
    assert !binder.TryBindReflectionArguments(
        parameters,
        0,
        BinderCall(extra),
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed2(BuiltInTypes.String, BuiltInTypes.Int),
        out bound,
        out score,
        out usesParams,
        out defaultsUsed
    )

    // A params ELEMENT is exempt: the element of a by-ref params array is not itself by-ref.
    element := new SuppliedReflectionBoundArgument(
        1,
        typeof(int),
        BinderPositional("parsed"),
        1
    )
    elementScore := 0
    assert !binder.TryScoreReflectionSuppliedArgument(
        element,
        parameters[1],
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed2(BuiltInTypes.String, BuiltInTypes.Int),
        false,
        out elementScore
    )
    assert binder.TryScoreReflectionSuppliedArgument(
        element,
        parameters[1],
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed2(BuiltInTypes.String, BuiltInTypes.Int),
        true,
        out elementScore
    )
}

test "the per-argument score ladder orders candidates by how much was assumed" {
    binder := BinderDefault()
    method := BinderSubstringMethod(1)
    parameters := method.GetParameters()

    // An explicit `default` fits any parameter exactly.
    defaulted := new SuppliedReflectionBoundArgument(
        0,
        typeof(int),
        BinderDefaultArgument(),
        0
    )
    score := 0
    assert binder.TryScoreReflectionSuppliedArgument(
        defaulted,
        parameters[0],
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(null),
        false,
        out score
    )
    assert score == 8

    // An identical CLR type scores on the reflection ladder.
    exact := new SuppliedReflectionBoundArgument(0, typeof(int), BinderPositional("x"), 0)
    assert binder.TryScoreReflectionSuppliedArgument(
        exact,
        parameters[0],
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(BuiltInTypes.Int),
        false,
        out score
    )
    assert score == 8

    // A widening scores strictly below it.
    widened := new SuppliedReflectionBoundArgument(0, typeof(long), BinderPositional("x"), 0)
    assert binder.TryScoreReflectionSuppliedArgument(
        widened,
        parameters[0],
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(BuiltInTypes.Int),
        false,
        out score
    )
    assert score == 6

    // An argument the analyzer could not type is never a binding.
    untyped := new SuppliedReflectionBoundArgument(0, typeof(int), BinderPositional("x"), 0)
    assert !binder.TryScoreReflectionSuppliedArgument(
        untyped,
        parameters[0],
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<int, FunctionTypeInfo>(),
        BinderAnalyzed1(null),
        false,
        out score
    )
}

// ------------------------------------------------------------------ the delegate arms

test "a delegate signature is read structurally for Action and Func and through Invoke otherwise" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        wellKnown := BinderWellKnown(context)
        binder := BinderFor(wellKnown)
        overrides := new Dictionary<Type, TypeInfo>()
        bindings := new Dictionary<Type, Type>()

        funcOfIntInt := BinderClosedPair(wellKnown.Func2, wellKnown.Int32, wellKnown.Int32)
        funcSignature := binder.CreateDelegateSignatureFromOpenType(funcOfIntInt, overrides, bindings)
        assert funcSignature != null
        assert funcSignature.ParameterTypes != null
        assert funcSignature.ParameterTypes.Count == 1
        assert BinderTypeName(funcSignature.ParameterTypes[0]) == "int"
        assert BinderTypeName(funcSignature.ReturnType) == "int"

        actionOfInt := BinderClosed(wellKnown.Action1, wellKnown.Int32)
        actionSignature := binder.CreateDelegateSignatureFromOpenType(actionOfInt, overrides, bindings)
        assert actionSignature != null
        assert actionSignature.ParameterTypes != null
        assert actionSignature.ParameterTypes.Count == 1
        // An Action returns void, and that is read from the FORM rather than from `Invoke`.
        assert BinderTypeName(actionSignature.ReturnType) == "void"

        // A delegate that is neither goes through `Invoke`, whose parameters carry their own
        // nullability metadata.
        comparisonOfInt := BinderClosed(
            BinderMlcType(wellKnown, "System.Comparison`1"),
            wellKnown.Int32
        )
        comparisonSignature := binder.CreateDelegateSignatureFromOpenType(
            comparisonOfInt,
            overrides,
            bindings
        )
        assert comparisonSignature != null
        assert comparisonSignature.ParameterTypes != null
        assert comparisonSignature.ParameterTypes.Count == 2

        // A NON-delegate answers null — "not callable", which the caller distinguishes from a
        // delegate with no signature.
        assert binder.CreateDelegateSignatureFromOpenType(
            wellKnown.Int32,
            overrides,
            bindings
        ) == null
        assert binder.CreateDelegateSignatureFromOpenType(
            wellKnown.String,
            overrides,
            bindings
        ) == null

        // The two abstract ROOTS have no invocation signature and are excluded too.
        assert binder.CreateDelegateSignatureFromOpenType(
            wellKnown.Delegate,
            overrides,
            bindings
        ) == null
    } finally {
        scan.Dispose()
    }
}

test "an N# TypeInfo override survives the structural Action and Func read" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        wellKnown := BinderWellKnown(context)
        binder := BinderFor(wellKnown)

        openFunc := wellKnown.Func2
        assert openFunc != null
        openArguments := openFunc.GetGenericArguments()
        overrides := new Dictionary<Type, TypeInfo>()
        overrides[openArguments[0]] = new SimpleTypeInfo("Point")
        bindings := new Dictionary<Type, Type>()
        bindings[openArguments[0]] = wellKnown.Int32
        bindings[openArguments[1]] = wellKnown.Int32

        // The OPEN form is passed in: the bindings close it enough to be a delegate, and the type
        // ARGUMENTS are then read from the open form so the N# override is not lost to `Invoke`.
        signature := binder.CreateDelegateSignatureFromOpenType(openFunc, overrides, bindings)
        assert signature != null
        assert signature.ParameterTypes != null
        assert signature.ParameterTypes.Count == 1
        assert BinderTypeName(signature.ParameterTypes[0]) == "Point"

        // With NO override the same read answers with the bound CLR type instead.
        plain := binder.CreateDelegateSignatureFromOpenType(
            openFunc,
            new Dictionary<Type, TypeInfo>(),
            bindings
        )
        assert plain != null
        assert plain.ParameterTypes != null
        assert BinderTypeName(plain.ParameterTypes[0]) == "int"
    } finally {
        scan.Dispose()
    }
}

test "a method group picks its best overload and a tie is a non-binding" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        wellKnown := BinderWellKnown(context)
        binder := BinderFor(wellKnown)
        funcOfIntInt := BinderClosedPair(wellKnown.Func2, wellKnown.Int32, wellKnown.Int32)

        // A single SOURCE function binds; the +4 is the method-group conversion itself, so a
        // resolved group always outranks a plain assignable argument.
        selected: FunctionTypeInfo? = null
        score := 0
        single: TypeInfo = BinderSourceFunction("Twice", BuiltInTypes.Int, BuiltInTypes.Int)
        assert binder.TryBindMethodGroupToReflectionDelegate(
            funcOfIntInt,
            single,
            new Dictionary<Type, Type>(),
            out selected,
            out score
        )
        assert score >= 4
        selectedObject := selected as object
        singleObject := single as object
        assert Object.ReferenceEquals(selectedObject, singleObject)

        // A LAMBDA-shaped function type has no source identity and is not a method group.
        anonymous: TypeInfo = BinderAnonymousFunction(BuiltInTypes.Int, BuiltInTypes.Int)
        assert !binder.TryBindMethodGroupToReflectionDelegate(
            funcOfIntInt,
            anonymous,
            new Dictionary<Type, Type>(),
            out selected,
            out score
        )

        // A group picks the overload that matches.
        functions := new List<FunctionTypeInfo>()
        functions.Add(BinderSourceFunction("Twice", BuiltInTypes.String, BuiltInTypes.Int))
        functions.Add(BinderSourceFunction("Twice", BuiltInTypes.Int, BuiltInTypes.Int))
        group: TypeInfo = new NSharpMethodGroupInfo(functions)
        assert binder.TryBindMethodGroupToReflectionDelegate(
            funcOfIntInt,
            group,
            new Dictionary<Type, Type>(),
            out selected,
            out score
        )
        assert selected != null
        assert selected.ParameterTypes != null
        assert BinderTypeName(selected.ParameterTypes[0]) == "int"

        // TWO overloads that score identically are AMBIGUOUS, and ambiguity is a refusal rather than
        // an arbitrary choice.
        tied := new List<FunctionTypeInfo>()
        tied.Add(BinderSourceFunction("Twice", BuiltInTypes.Int, BuiltInTypes.Int))
        tied.Add(BinderSourceFunction("Twice", BuiltInTypes.Int, BuiltInTypes.Int))
        ambiguous: TypeInfo = new NSharpMethodGroupInfo(tied)
        assert !binder.TryBindMethodGroupToReflectionDelegate(
            funcOfIntInt,
            ambiguous,
            new Dictionary<Type, Type>(),
            out selected,
            out score
        )

        // An EMPTY group has nothing to select.
        empty: TypeInfo = new NSharpMethodGroupInfo(new List<FunctionTypeInfo>())
        assert !binder.TryBindMethodGroupToReflectionDelegate(
            funcOfIntInt,
            empty,
            new Dictionary<Type, Type>(),
            out selected,
            out score
        )

        // A NON-delegate parameter never takes a method group.
        assert !binder.TryBindMethodGroupToReflectionDelegate(
            wellKnown.Int32,
            single,
            new Dictionary<Type, Type>(),
            out selected,
            out score
        )
    } finally {
        scan.Dispose()
    }
}

test "without a well-known-type bag nothing is a delegate and every delegate arm refuses" {
    binder := BinderDefault()
    funcOfIntInt := BinderClosed2("System.Func`2, System.Private.CoreLib", typeof(int), typeof(int))
    selected: FunctionTypeInfo? = null
    score := 0
    single: TypeInfo = BinderSourceFunction("Twice", BuiltInTypes.Int, BuiltInTypes.Int)

    assert !binder.TryBindMethodGroupToReflectionDelegate(
        funcOfIntInt,
        single,
        new Dictionary<Type, Type>(),
        out selected,
        out score
    )
    assert binder.CreateDelegateSignatureFromOpenType(
        funcOfIntInt,
        new Dictionary<Type, TypeInfo>(),
        new Dictionary<Type, Type>()
    ) == null
}

test "a selected method group's signature flows back into the reflected type parameters" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        wellKnown := BinderWellKnown(context)
        binder := BinderFor(wellKnown)

        openFunc := wellKnown.Func2
        assert openFunc != null
        openArguments := openFunc.GetGenericArguments()
        bindings := new Dictionary<Type, Type>()
        typeInfoBindings := new Dictionary<Type, TypeInfo>()
        source := BinderSourceFunction("Twice", BuiltInTypes.Int, BuiltInTypes.String)

        assert binder.TryPopulateReflectionBindingsFromMethodGroupDelegate(
            openFunc,
            source,
            bindings,
            typeInfoBindings
        )
        assert bindings.Count == 2
        // The bound CLR types are the CONTEXT'S, not the compiler's own.
        assert bindings[openArguments[0]] == wellKnown.Int32
        assert bindings[openArguments[1]] == wellKnown.String
        assert BinderTypeName(typeInfoBindings[openArguments[0]]) == "int"
        assert BinderTypeName(typeInfoBindings[openArguments[1]]) == "string"

        // An ARITY disagreement is a non-binding.
        twoParameters := new List<TypeInfo>()
        twoParameters.Add(BuiltInTypes.Int)
        twoParameters.Add(BuiltInTypes.Int)
        wide := BinderSourceFunction("Twice", BuiltInTypes.Int, BuiltInTypes.Int)
        wide.ParameterTypes = twoParameters
        assert !binder.TryPopulateReflectionBindingsFromMethodGroupDelegate(
            openFunc,
            wide,
            new Dictionary<Type, Type>(),
            new Dictionary<Type, TypeInfo>()
        )

        // A type with no `Invoke` is not a delegate signature at all.
        assert !binder.TryPopulateReflectionBindingsFromMethodGroupDelegate(
            wellKnown.Int32,
            source,
            new Dictionary<Type, Type>(),
            new Dictionary<Type, TypeInfo>()
        )
    } finally {
        scan.Dispose()
    }
}

// ------------------------------------------------------------------ inference

test "the N# half of inference binds the leftmost occurrence and never overwrites it" {
    binder := BinderDefault()
    openFunc := BinderRuntimeType("System.Func`2, System.Private.CoreLib")
    openArguments := openFunc.GetGenericArguments()

    typeInfoBindings := new Dictionary<Type, TypeInfo>()
    binder.PopulateTypeInfoBindingsFromType(openArguments[0], BuiltInTypes.Int, typeInfoBindings)
    assert BinderTypeName(typeInfoBindings[openArguments[0]]) == "int"

    // FIRST BINDING WINS, so a repeated type parameter is decided by its leftmost occurrence.
    binder.PopulateTypeInfoBindingsFromType(openArguments[0], BuiltInTypes.String, typeInfoBindings)
    assert BinderTypeName(typeInfoBindings[openArguments[0]]) == "int"

    // A non-generic parameter contributes nothing.
    plain := new Dictionary<Type, TypeInfo>()
    binder.PopulateTypeInfoBindingsFromType(typeof(int), BuiltInTypes.String, plain)
    assert plain.Count == 0
}

test "an array argument contributes its ELEMENT type to every read-only sequence parameter" {
    binder := BinderDefault()
    openFunc := BinderRuntimeType("System.Func`2, System.Private.CoreLib")
    openParameter := openFunc.GetGenericArguments()[0]
    intArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    sequenceNames := new List<string>()
    sequenceNames.Add("System.Collections.Generic.IEnumerable`1, System.Private.CoreLib")
    sequenceNames.Add("System.Collections.Generic.IReadOnlyList`1, System.Private.CoreLib")
    sequenceNames.Add("System.Collections.Generic.IReadOnlyCollection`1, System.Private.CoreLib")
    sequenceNames.Add("System.Collections.Generic.ICollection`1, System.Private.CoreLib")
    sequenceNames.Add("System.Collections.Generic.IList`1, System.Private.CoreLib")

    index := 0
    while index < sequenceNames.Count {
        definition := BinderRuntimeType(sequenceNames[index])
        arguments := new Type[](1)
        arguments[0] = openParameter
        closed := definition.MakeGenericType(arguments)
        bindings := new Dictionary<Type, TypeInfo>()
        binder.PopulateTypeInfoBindingsFromType(closed, intArray, bindings)
        assert BinderTypeName(bindings[openParameter]) == "int"
        index = index + 1
    }

    // An open ARRAY parameter takes the element type too.
    arrayBindings := new Dictionary<Type, TypeInfo>()
    binder.PopulateTypeInfoBindingsFromType(
        openParameter.MakeArrayType(),
        intArray,
        arrayBindings
    )
    assert BinderTypeName(arrayBindings[openParameter]) == "int"

    // A parameter that is NOT a read-only sequence takes nothing from an array argument: the set is
    // deliberately closed.
    dictionaryDefinition := BinderRuntimeType(
        "System.Collections.Generic.Dictionary`2, System.Private.CoreLib"
    )
    dictionaryArguments := new Type[](2)
    dictionaryArguments[0] = openParameter
    dictionaryArguments[1] = openParameter
    dictionaryBindings := new Dictionary<Type, TypeInfo>()
    binder.PopulateTypeInfoBindingsFromType(
        dictionaryDefinition.MakeGenericType(dictionaryArguments),
        intArray,
        dictionaryBindings
    )
    assert dictionaryBindings.Count == 0
}

test "a generic argument that does not match the parameter's definition is traced through the hierarchy" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        wellKnown := BinderWellKnown(context)
        binder := BinderFor(wellKnown)

        openFunc := wellKnown.Func2
        assert openFunc != null
        openParameter := openFunc.GetGenericArguments()[0]
        openEnumerable := BinderClosed(wellKnown.IEnumerableOpen, openParameter)

        // DIRECT: the argument's own definition matches the parameter's, so the positions line up.
        directArgument: TypeInfo = new GenericTypeInfo(
            "IEnumerable",
            BinderTypeArguments(BuiltInTypes.String)
        )
        directBindings := new Dictionary<Type, TypeInfo>()
        binder.PopulateTypeInfoBindingsFromType(openEnumerable, directArgument, directBindings)
        assert BinderTypeName(directBindings[openParameter]) == "string"

        // TRACED: `List<int>` is not an `IEnumerable<T>` by name, so the interface's own type
        // arguments are mapped back to the argument definition's to find which position carries
        // `T`. This arm needs the well-known bag: the argument has to be given a CLR form first.
        listArgument: TypeInfo = new GenericTypeInfo("List", BinderTypeArguments(BuiltInTypes.Int))
        tracedBindings := new Dictionary<Type, TypeInfo>()
        binder.PopulateTypeInfoBindingsFromType(openEnumerable, listArgument, tracedBindings)
        assert BinderTypeName(tracedBindings[openParameter]) == "int"

        // WITHOUT the bag the same trace finds no CLR form and binds nothing, which is why the two
        // are different answers rather than one.
        bagless := BinderDefault()
        baglessBindings := new Dictionary<Type, TypeInfo>()
        bagless.PopulateTypeInfoBindingsFromType(openEnumerable, listArgument, baglessBindings)
        assert baglessBindings.Count == 0
    } finally {
        scan.Dispose()
    }
}

func BinderTypeArguments(first: TypeInfo): List<TypeInfo> {
    arguments := new List<TypeInfo>()
    arguments.Add(first)
    return arguments
}

test "both halves of inference run together and the by-ref shell is stripped first" {
    binder := BinderDefault()
    openFunc := BinderRuntimeType("System.Func`2, System.Private.CoreLib")
    openParameter := openFunc.GetGenericArguments()[0]

    bindings := new Dictionary<Type, Type>()
    typeInfoBindings := new Dictionary<Type, TypeInfo>()
    binder.PopulateReflectionBindingsFromTypeInfo(
        openParameter.MakeByRefType(),
        BuiltInTypes.Int,
        bindings,
        typeInfoBindings
    )
    assert bindings[openParameter] == typeof(int)
    assert BinderTypeName(typeInfoBindings[openParameter]) == "int"

    // FIRST BINDING WINS on BOTH sides.
    binder.PopulateReflectionBindingsFromTypeInfo(
        openParameter,
        BuiltInTypes.String,
        bindings,
        typeInfoBindings
    )
    assert bindings[openParameter] == typeof(int)
    assert BinderTypeName(typeInfoBindings[openParameter]) == "int"

    // An open ARRAY recurses into its element.
    arrayBindings := new Dictionary<Type, Type>()
    arrayTypeInfos := new Dictionary<Type, TypeInfo>()
    intArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.String)
    binder.PopulateReflectionBindingsFromTypeInfo(
        openParameter.MakeArrayType(),
        intArray,
        arrayBindings,
        arrayTypeInfos
    )
    assert arrayBindings[openParameter] == typeof(string)

    // A SOURCE type has no CLR form, so only the TypeInfo half binds — which is exactly why the two
    // halves are not one dictionary.
    sourceBindings := new Dictionary<Type, Type>()
    sourceTypeInfos := new Dictionary<Type, TypeInfo>()
    sourceType: TypeInfo = new SimpleTypeInfo("Point")
    binder.PopulateReflectionBindingsFromTypeInfo(
        openParameter,
        sourceType,
        sourceBindings,
        sourceTypeInfos
    )
    assert sourceBindings.Count == 0
    assert BinderTypeName(sourceTypeInfos[openParameter]) == "Point"
}

test "a receiver contributes bindings only when its declaring type mentions a type parameter" {
    binder := BinderDefault()
    listDefinition := BinderRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib")
    listArguments := new Type[](1)
    listArguments[0] = typeof(int)
    closedList := listDefinition.MakeGenericType(listArguments)
    listTypeInfo: TypeInfo = new GenericTypeInfo("List", BinderTypeArguments(BuiltInTypes.Int))

    bindings := new Dictionary<Type, Type>()
    typeInfoBindings := new Dictionary<Type, TypeInfo>()
    assert binder.TryPopulateReceiverGenericTypeBindings(
        listDefinition,
        closedList,
        listTypeInfo,
        bindings,
        typeInfoBindings
    )
    assert bindings[listDefinition.GetGenericArguments()[0]] == typeof(int)

    // A declaring type with NO type parameter contributes nothing and is NOT a failure — the two
    // outcomes are different answers, and collapsing them would fail every call on a plain type.
    plainBindings := new Dictionary<Type, Type>()
    plainTypeInfos := new Dictionary<Type, TypeInfo>()
    assert binder.TryPopulateReceiverGenericTypeBindings(
        typeof(string),
        typeof(string),
        BuiltInTypes.String,
        plainBindings,
        plainTypeInfos
    )
    assert plainBindings.Count == 0

    // So does a null declaring type.
    assert binder.TryPopulateReceiverGenericTypeBindings(
        null,
        typeof(string),
        BuiltInTypes.String,
        plainBindings,
        plainTypeInfos
    )

    // A receiver that does not match the declaring type IS a failure.
    mismatchBindings := new Dictionary<Type, Type>()
    mismatchTypeInfos := new Dictionary<Type, TypeInfo>()
    assert !binder.TryPopulateReceiverGenericTypeBindings(
        listDefinition,
        typeof(string),
        BuiltInTypes.String,
        mismatchBindings,
        mismatchTypeInfos
    )
}

// The generic type DEFINITION whose members the mask re-finds. A test body cannot narrow a
// maybe-null local (`assert x != null` does not narrow — NL905), so every lookup that can fail is
// resolved here and answers a non-null value or throws.
func maskProbeListDefinition(): Type {
    definition := Type.GetType("System.Collections.Generic.List`1, System.Private.CoreLib")
    if definition == null {
        throw new InvalidOperationException("List`1 was unavailable.")
    }
    return definition
}

func maskProbeClosedAdd(): MethodInfo {
    closedName := "System.Collections.Generic.List`1[[System.Int32, System.Private.CoreLib]], System.Private.CoreLib"
    closedType := Type.GetType(closedName)
    if closedType == null {
        throw new InvalidOperationException("List<int> was unavailable.")
    }
    closed := closedType.GetMethod("Add")
    if closed == null {
        throw new InvalidOperationException("List<int>.Add was unavailable.")
    }
    return closed
}

// GetOpenReflectionSignatureMethod's body, which is the whole reason for the rows.
func maskProbeOpenAdd(): MethodInfo {
    closed := maskProbeClosedAdd()
    declaring := closed.get_DeclaringType()
    if declaring == null {
        throw new InvalidOperationException("List<int>.Add had no declaring type.")
    }
    definition := declaring.GetGenericTypeDefinition()
    candidates := definition.GetMethods(
        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static
    )
    i := 0
    while i < candidates.Length {
        candidate := candidates[i]
        if candidate.get_MetadataToken() == closed.get_MetadataToken() {
            return candidate
        }
        i = i + 1
    }
    throw new InvalidOperationException("The open signature was not re-found.")
}

test "the binding mask combines and selects the filtered enumeration" {
    definition := maskProbeListDefinition()

    publicInstance := definition.GetMethods(BindingFlags.Public | BindingFlags.Instance)
    declared := definition.GetMethods(
        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static
    )

    // The mask is not decoration: the wider request answers strictly more members.
    assert publicInstance.Length > 0
    assert declared.Length > publicInstance.Length

    // The unfiltered arity-0 arm is still its own overload and still binds.
    assert definition.GetMethods().Length == publicInstance.Length
}

test "a single mask member and a hoisted mask both bind" {
    definition := maskProbeListDefinition()

    // The two shapes the ordinary runtime resolver already covered once the mask row admits the
    // enum. They must keep working: a regression here means the mask row stopped admitting it.
    // A lone visibility flag is a legal mask that selects NOTHING — the CLR requires a staticness
    // flag too — so the empty answer is the proof that the call bound and ran, not that it failed.
    single := definition.GetMethods(BindingFlags.Public)
    assert single.Length == 0

    hoisted: BindingFlags = BindingFlags.Public | BindingFlags.Instance
    assert definition.GetMethods(hoisted).Length == definition.GetMethods(BindingFlags.Public | BindingFlags.Instance).Length
    assert definition.GetMethods(hoisted).Length > 0
}

test "an open signature is re-found on the generic definition by metadata token" {
    openAdd := maskProbeOpenAdd()
    assert openAdd.get_Name() == "Add"
    assert openAdd.GetParameters().Length == 1
    assert openAdd.get_MetadataToken() == maskProbeClosedAdd().get_MetadataToken()
}

// THE PRE-BINDER (task 017 slice 20 phase B). The first pass over one candidate. These pin the
// decisions a reader cannot recover from any single arm: which method the signature is READ from,
// the order of the four gates, and the three tie-break fields that order the candidates.

test "the open signature reduces a generic method to its own definition" {
    // A closed generic method is not the signature: its parameters are already substituted, so the
    // type parameters inference must bind are gone.
    listType := BinderClosed(
        BinderRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib"),
        typeof(int)
    )
    convertAll := listType.GetMethod("ConvertAll")
    assert convertAll != null
    assert convertAll.get_IsGenericMethodDefinition()

    reduced := AnalyzerReflectionArgumentBinder.GetOpenReflectionSignatureMethod(convertAll)
    assert reduced.get_IsGenericMethodDefinition()
    assert reduced.get_Name() == "ConvertAll"
}

test "the open signature is re-found on the declaring type's definition" {
    // THE ROW'S WHOLE REASON. `List<int>.Add` declares `void Add(int)`; the OPEN form declares
    // `void Add(T)`, and only the definition's own member table has it.
    closedListType := BinderClosed(
        BinderRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib"),
        typeof(int)
    )
    closed := closedListType.GetMethod("Add")
    assert closed != null
    closedParameters := closed.GetParameters()
    assert closedParameters[0].get_ParameterType() == typeof(int)

    open := AnalyzerReflectionArgumentBinder.GetOpenReflectionSignatureMethod(closed)
    assert open.get_MetadataToken() == closed.get_MetadataToken()
    openParameters := open.GetParameters()
    openFirstType := openParameters[0].get_ParameterType()
    assert openFirstType.get_IsGenericParameter()
    openOwner := open.get_DeclaringType()
    assert openOwner != null
    assert openOwner.get_IsGenericTypeDefinition()

    // The METADATA TOKEN is what identifies it, not the name: `Insert` and `Add` are both on the
    // same definition and must not be confused, and a name-keyed re-find would have to pick
    // between overloads it cannot tell apart.
    closedInsert := closedListType.GetMethod("Insert")
    assert closedInsert != null
    openInsert := AnalyzerReflectionArgumentBinder.GetOpenReflectionSignatureMethod(closedInsert)
    assert openInsert.get_MetadataToken() == closedInsert.get_MetadataToken()
    assert openInsert.get_MetadataToken() != open.get_MetadataToken()
    assert openInsert.GetParameters().Length == 2
}

test "the open signature leaves an already-open or non-generic method alone" {
    // A method on a NON-generic type is already open.
    stringType := typeof(string)
    substring := stringType.GetMethod("Substring", PreBindTypeArray(typeof(int)))
    assert substring != null
    reducedSubstring := AnalyzerReflectionArgumentBinder.GetOpenReflectionSignatureMethod(substring)
    assert reducedSubstring.get_MetadataToken() == substring.get_MetadataToken()
    substringParameters := reducedSubstring.GetParameters()
    assert substringParameters[0].get_ParameterType() == typeof(int)

    // A method declared on the DEFINITION is already open too, and comes back unchanged.
    listDefinition := BinderRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib")
    openAdd := listDefinition.GetMethod("Add")
    assert openAdd != null
    reduced := AnalyzerReflectionArgumentBinder.GetOpenReflectionSignatureMethod(openAdd)
    assert reduced.get_MetadataToken() == openAdd.get_MetadataToken()
    reducedOwner := reduced.get_DeclaringType()
    assert reducedOwner != null
    assert reducedOwner.get_IsGenericTypeDefinition()
}

test "the pre-binder answers a candidate with its score and both tie-breaks" {
    binder := BinderDefault()
    substring := typeof(string).GetMethod("Substring", PreBindTypeArray(typeof(int)))
    assert substring != null

    bound := binder.PreBindReflectionMethod(
        substring,
        PreBindCall(1),
        typeof(string),
        new ReflectionTypeInfo(typeof(string)),
        BinderAnalyzed1(BuiltInTypes.Int)
    )
    assert bound != null
    assert bound.RuntimeMethod.get_MetadataToken() == substring.get_MetadataToken()
    assert bound.SignatureMethod.get_MetadataToken() == substring.get_MetadataToken()
    assert bound.BoundArguments.Count == 1
    // An exact single-argument match neither expands a tail nor consumes a default.
    assert !bound.UsesParams
    assert bound.DefaultsUsed == 0

    // ARITY IS EXACT: the same candidate refuses a call it cannot fill.
    assert binder.PreBindReflectionMethod(
        substring,
        PreBindCall(3),
        typeof(string),
        new ReflectionTypeInfo(typeof(string)),
        BinderAnalyzed3(BuiltInTypes.Int, BuiltInTypes.Int, BuiltInTypes.Int)
    ) == null
    assert binder.PreBindReflectionMethod(
        substring,
        PreBindCall(0),
        typeof(string),
        new ReflectionTypeInfo(typeof(string)),
        BinderAnalyzed(new List<TypeInfo?>())
    ) == null
}

test "the pre-binder refuses written type arguments a candidate cannot take" {
    binder := BinderDefault()
    substring := typeof(string).GetMethod("Substring", PreBindTypeArray(typeof(int)))
    assert substring != null

    // WRITTEN TYPE ARGUMENTS ARE ABSOLUTE. A non-generic candidate cannot take one at all, and a
    // wrong COUNT is a non-binding rather than a partial inference.
    typed := PreBindCallWithTypeArguments(1, 1)
    assert binder.PreBindReflectionMethod(
        substring,
        typed,
        typeof(string),
        new ReflectionTypeInfo(typeof(string)),
        BinderAnalyzed1(BuiltInTypes.Int)
    ) == null

    // The same call WITHOUT the type argument binds, so the refusal is the type argument's doing.
    assert binder.PreBindReflectionMethod(
        substring,
        PreBindCall(1),
        typeof(string),
        new ReflectionTypeInfo(typeof(string)),
        BinderAnalyzed1(BuiltInTypes.Int)
    ) != null
}

// A call on a MEMBER-ACCESS callee, which is the shape a reflected instance call always has, with
// `arity` positional arguments and an optional written type argument.
func PreBindCall(arity: int): CallExpression {
    return PreBindCallWithTypeArguments(arity, 0)
}

func PreBindCallWithTypeArguments(arity: int, typeArgumentCount: int): CallExpression {
    arguments := BinderArguments()
    i := 0
    while i < arity {
        arguments.Add(BinderPositional("a"))
        i = i + 1
    }

    typeArguments: List<TypeReference>? = null
    if typeArgumentCount > 0 {
        written := new List<TypeReference>()
        t := 0
        while t < typeArgumentCount {
            written.Add(new SimpleTypeReference("int", 1, 1))
            t = t + 1
        }
        typeArguments = written
    }

    receiver: Expression = new MemberAccessExpression(BinderIdentifier("receiver"), "m", false, 1, 1)
    return new CallExpression(receiver, arguments, typeArguments, 1, 1)
}

// Named for assembly-wide uniqueness: a bare `One` collides with the catalog's own static helper
// and makes an UNRELATED file decline (slice 16's gotcha, and it applies to free functions too).
func PreBindTypeArray(first: Type): Type[] {
    values := new Type[](1)
    values[0] = first
    return values
}

// ------------------------------------------------------------------ the finalising walk
//
// The walk is the candidate's SECOND pass and the only part of the reflected-call arc that cannot be
// stated as a function: it suspends at each expression it needs analysed. These contracts pin the
// suspension protocol itself, because it is the part a reader cannot recover from any single arm:
// WHEN a request is issued, what expected type rides on it, what each answer is folded into, and
// when the walk stops asking.

// `Array.ConvertAll<TInput, TOutput>(TInput[], Converter<TInput, TOutput>)` — the CoreLib generic
// with a DELEGATE parameter whose return type is a type parameter nothing else can bind. It is the
// only shape that exercises the pre-pass's inference rule on a real declaration.
func FinalizeConvertAllMethod(wellKnown: AnalyzerWellKnownTypes): MethodInfo {
    arrayType := BinderMlcType(wellKnown, "System.Array")
    methods := arrayType.GetMethods()
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == "ConvertAll" && candidate.GetParameters().Length == 2 {
            return candidate
        }

        index = index + 1
    }

    throw new InvalidOperationException("Array.ConvertAll was not found in the load context.")
}

// A call with `arity` positional arguments where the position at `lambdaIndex` is a one-parameter
// lambda. A negative index means no lambda at all.
func FinalizeCall(arity: int, lambdaIndex: int): CallExpression {
    arguments := BinderArguments()
    index := 0
    while index < arity {
        if index == lambdaIndex {
            arguments.Add(BinderLambda(1, "int"))
        } else {
            arguments.Add(BinderPositional("a" + index.ToString()))
        }

        index = index + 1
    }

    receiver: Expression = new MemberAccessExpression(BinderIdentifier("receiver"), "m", false, 1, 1)
    return new CallExpression(receiver, arguments, null, 1, 1)
}

// An analysed lambda's answer: the shape `AnalyzeLambda` hands back.
func FinalizeLambdaAnswer(parameter: TypeInfo, returnType: TypeInfo): FunctionTypeInfo {
    return BinderAnonymousFunction(parameter, returnType)
}

func FinalizeSignatureText(request: ReflectionAnalysisRequest?): string {
    if request == null {
        return "<none>"
    }

    signature := request.ExpectedType as FunctionTypeInfo
    if signature == null {
        return BinderTypeName(request.ExpectedType)
    }

    text := "("
    parameterTypes := signature.ParameterTypes
    if parameterTypes != null {
        index := 0
        while index < parameterTypes.Count {
            if index > 0 {
                text = text + ","
            }

            text = text + BinderTypeName(parameterTypes[index])
            index = index + 1
        }
    }

    return text + ")->" + BinderTypeName(signature.ReturnType)
}

test "the finalising walk asks once per supplied argument and answers the call's type" {
    binder := BinderDefault()
    substring := typeof(string).GetMethod("Substring", PreBindTypeArray(typeof(int)))
    assert substring != null

    candidate := binder.PreBindReflectionMethod(
        substring,
        PreBindCall(1),
        typeof(string),
        new ReflectionTypeInfo(typeof(string)),
        BinderAnalyzed1(BuiltInTypes.Int)
    )
    assert candidate != null

    state := binder.BeginFinalizeReflectionCall(candidate)
    first := binder.NextReflectionAnalysis(state)
    assert first != null
    // A non-lambda position rides the ordinary expected-type entry point, and the expected type is
    // the parameter's, not the argument's.
    assert first.Lambda == null
    assert !first.IsExpressionTreeTarget
    assert BinderTypeName(first.ExpectedType) == "int"
    // The walk is SUSPENDED: no answer, no result.
    assert state.Result == null

    binder.SupplyReflectionAnalysis(state, BuiltInTypes.Int)
    assert binder.NextReflectionAnalysis(state) == null
    assert state.Result != null
    assert state.Result.ParameterTypes != null
    assert state.Result.ParameterTypes.Count == 1
    assert BinderTypeName(state.Result.ReturnType) == "string"
}

test "an argument that does not assign ends the walk and no later argument is asked for" {
    binder := BinderDefault()
    substring := typeof(string).GetMethod(
        "Substring",
        PreBindTypeArray2(typeof(int), typeof(int))
    )
    assert substring != null

    candidate := binder.PreBindReflectionMethod(
        substring,
        PreBindCall(2),
        typeof(string),
        new ReflectionTypeInfo(typeof(string)),
        BinderAnalyzed2(BuiltInTypes.Int, BuiltInTypes.Int)
    )
    assert candidate != null

    // Both positions are asked for when both answers assign.
    accepted := binder.BeginFinalizeReflectionCall(candidate)
    assert binder.NextReflectionAnalysis(accepted) != null
    binder.SupplyReflectionAnalysis(accepted, BuiltInTypes.Int)
    assert binder.NextReflectionAnalysis(accepted) != null
    binder.SupplyReflectionAnalysis(accepted, BuiltInTypes.Int)
    assert binder.NextReflectionAnalysis(accepted) == null
    assert accepted.Result != null

    // A refused FIRST answer stops the walk where it stands: the second position is never asked
    // for, so the analyzer never analyses it and never reports from inside it.
    refused := binder.BeginFinalizeReflectionCall(candidate)
    assert binder.NextReflectionAnalysis(refused) != null
    binder.SupplyReflectionAnalysis(refused, BuiltInTypes.String)
    assert binder.NextReflectionAnalysis(refused) == null
    assert refused.Result == null
}

test "a defaulted position contributes a parameter type without asking for an analysis" {
    binder := BinderDefault()
    method := BinderOptionalMethod()
    parameters := method.GetParameters()
    firstType := AnalyzerReflectionTypeConversion.ConvertReflectionType(
        AnalyzerOverloadFacts.GetByRefElementType(parameters[0].get_ParameterType())
    )
    candidate := binder.PreBindReflectionMethod(
        method,
        PreBindCall(1),
        null,
        null,
        BinderAnalyzed1(firstType)
    )
    assert candidate != null

    state := binder.BeginFinalizeReflectionCall(candidate)
    requests := 0
    request := binder.NextReflectionAnalysis(state)
    while request != null {
        requests = requests + 1
        binder.SupplyReflectionAnalysis(state, request.ExpectedType)
        request = binder.NextReflectionAnalysis(state)
    }

    assert state.Result != null
    assert state.Result.ParameterTypes != null
    // One written argument, one analysis; the defaulted positions are typed without one.
    assert requests == 1
    assert state.Result.ParameterTypes.Count > requests
}

test "an expanded params tail asks once per element" {
    binder := BinderDefault()
    format := BinderFormatMethod()
    candidate := binder.PreBindReflectionMethod(
        format,
        PreBindCall(4),
        null,
        null,
        BinderAnalyzed(FinalizeStringValues(4))
    )
    assert candidate != null

    state := binder.BeginFinalizeReflectionCall(candidate)
    requests := 0
    request := binder.NextReflectionAnalysis(state)
    while request != null {
        requests = requests + 1
        binder.SupplyReflectionAnalysis(state, request.ExpectedType)
        request = binder.NextReflectionAnalysis(state)
    }

    // The format string plus THREE expanded elements: the tail is one bound argument and three
    // analyses, not one.
    assert requests == 4
    assert state.Result != null
}

test "a phase-one lambda answer binds the method's one remaining type parameter" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        wellKnown := BinderWellKnown(context)
        binder := BinderFor(wellKnown)
        convertAll := FinalizeConvertAllMethod(wellKnown)

        intArray := wellKnown.Int32.MakeArrayType()
        candidate := binder.PreBindReflectionMethod(
            convertAll,
            FinalizeCall(2, 1),
            null,
            null,
            BinderAnalyzed2(new ReflectionTypeInfo(intArray), null)
        )
        assert candidate != null

        state := binder.BeginFinalizeReflectionCall(candidate)

        // PHASE ONE. The lambda is asked for FIRST, ahead of every conversion, and its expected
        // return type is still the OPEN type parameter — nothing has bound it yet.
        first := binder.NextReflectionAnalysis(state)
        assert first != null
        assert first.Lambda != null
        assert FinalizeSignatureText(first) == "(int)->TOutput"

        // The answer INFERS: with exactly one type parameter still unbound, the lambda's return
        // type takes it.
        binder.SupplyReflectionAnalysis(
            state,
            FinalizeLambdaAnswer(BuiltInTypes.Int, BuiltInTypes.String)
        )

        // PHASE TWO. The array position, then the SAME lambda again — and its signature is now the
        // bound one, which is why the second analysis is not a repeat of the first.
        second := binder.NextReflectionAnalysis(state)
        assert second != null
        assert second.Lambda == null
        binder.SupplyReflectionAnalysis(state, second.ExpectedType)

        third := binder.NextReflectionAnalysis(state)
        assert third != null
        assert third.Lambda != null
        // The lambda's own answer closed `TOutput`; the nullability spelling rides along from the
        // reflected delegate's metadata, which is why the second signature is not merely "(int)->string".
        assert FinalizeSignatureText(third) == "(int)->string?"
        binder.SupplyReflectionAnalysis(
            state,
            FinalizeLambdaAnswer(BuiltInTypes.Int, BuiltInTypes.String)
        )

        assert binder.NextReflectionAnalysis(state) == null
        assert state.Result != null
        // The inferred type parameter reaches the call's own type.
        assert BinderTypeName(state.Result.ReturnType) == "string[]"
    } finally {
        scan.Dispose()
    }
}

test "a type parameter the pre-pass never binds is a non-finalisation rather than a throw" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        wellKnown := BinderWellKnown(context)
        binder := BinderFor(wellKnown)
        convertAll := FinalizeConvertAllMethod(wellKnown)

        intArray := wellKnown.Int32.MakeArrayType()
        candidate := binder.PreBindReflectionMethod(
            convertAll,
            FinalizeCall(2, 1),
            null,
            null,
            BinderAnalyzed2(new ReflectionTypeInfo(intArray), null)
        )
        assert candidate != null

        state := binder.BeginFinalizeReflectionCall(candidate)
        first := binder.NextReflectionAnalysis(state)
        assert first != null

        // A lambda whose return type is UNKNOWN converts to no CLR type, so `TOutput` stays open.
        // The walk answers nothing at all rather than closing the method on a guess.
        binder.SupplyReflectionAnalysis(
            state,
            FinalizeLambdaAnswer(BuiltInTypes.Int, BuiltInTypes.Unknown)
        )
        assert binder.NextReflectionAnalysis(state) == null
        assert state.Result == null
        assert state.Failed
    } finally {
        scan.Dispose()
    }
}

test "the finalisation leaves the candidate's own recorded inference untouched" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        wellKnown := BinderWellKnown(context)
        binder := BinderFor(wellKnown)
        convertAll := FinalizeConvertAllMethod(wellKnown)

        intArray := wellKnown.Int32.MakeArrayType()
        candidate := binder.PreBindReflectionMethod(
            convertAll,
            FinalizeCall(2, 1),
            null,
            null,
            BinderAnalyzed2(new ReflectionTypeInfo(intArray), null)
        )
        assert candidate != null

        bindingsBefore := candidate.Bindings.Count
        typeInfoBindingsBefore := candidate.TypeInfoBindings.Count

        state := binder.BeginFinalizeReflectionCall(candidate)
        request := binder.NextReflectionAnalysis(state)
        while request != null {
            if request.Lambda != null {
                binder.SupplyReflectionAnalysis(
                    state,
                    FinalizeLambdaAnswer(BuiltInTypes.Int, BuiltInTypes.String)
                )
            } else {
                binder.SupplyReflectionAnalysis(state, request.ExpectedType)
            }

            request = binder.NextReflectionAnalysis(state)
        }

        // The pre-pass's inference lands on the WALK's copies. A finalisation that failed would
        // otherwise poison the next candidate the caller tries.
        assert candidate.Bindings.Count == bindingsBefore
        assert candidate.TypeInfoBindings.Count == typeInfoBindingsBefore
        assert state.WorkingBindings.Count > bindingsBefore
    } finally {
        scan.Dispose()
    }
}

func FinalizeStringValues(count: int): List<TypeInfo?> {
    values := new List<TypeInfo?>()
    index := 0
    while index < count {
        values.Add(BuiltInTypes.String)
        index = index + 1
    }

    return values
}

func PreBindTypeArray2(first: Type, second: Type): Type[] {
    values := new Type[](2)
    values[0] = first
    values[1] = second
    return values
}
