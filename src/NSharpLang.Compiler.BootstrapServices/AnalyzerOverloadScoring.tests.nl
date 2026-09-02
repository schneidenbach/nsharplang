namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the analyzer's overload scoring and applicability kernel.
//
// Every member behind these was `private` in Analyzer.cs, so nothing named any of them: overload
// resolution was pinned only indirectly, through end-to-end NL402 diagnostics. This is their first
// DIRECT pinning, and it goes at the decisions a reader cannot recover from a single arm:
//
//   * the two score LADDERS have the same 8/6/4/2 shape but different identity rules, and the source
//     ladder's CROSS-REPRESENTATION rule is what stops source `int` losing to metadata `System.Int32`;
//   * `TryMatchReflectionParameter` is applicability AND inference at once — the accumulating
//     bindings dictionary is the algorithm, not a cache;
//   * the THREE separate params questions (is it a params parameter, what is its element type, did
//     this call expand it) and why the source form additionally demands a full-length modifier list;
//   * the receiver OFFSET needs BOTH the signature flag and a member-access callee;
//   * a BROAD delegate parameter (`System.Delegate` itself) can only take a fully annotated lambda.

// Generic definitions are resolved by CANONICAL IDENTITY rather than through `typeof`: the columnar
// `typeof` surface does not carry most closed generic collection or delegate types, and the resolved
// instances are the identical runtime ones.
func OverloadRuntimeType(canonicalName: string): Type {
    resolved := Type.GetType(canonicalName)
    if resolved == null {
        throw new InvalidOperationException("The runtime does not define '" + canonicalName + "'.")
    }

    return resolved
}

func OverloadClosed1(canonicalName: string, first: Type): Type {
    definition := OverloadRuntimeType(canonicalName)
    arguments := new Type[](1)
    arguments[0] = first
    return definition.MakeGenericType(arguments)
}

func OverloadClosed2(canonicalName: string, first: Type, second: Type): Type {
    definition := OverloadRuntimeType(canonicalName)
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return definition.MakeGenericType(arguments)
}

func OverloadContext(): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    return context
}

func OverloadResolver(
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

// The scoring owner with NO well-known-type bag — the state the analyzer is in before it has loaded
// a MetadataLoadContext, and the state every contract here but the broad-delegate ones needs.
func OverloadScoringDefault(): AnalyzerOverloadScoring {
    context := OverloadContext()
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    resolver := OverloadResolver(scopes, context)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    return new AnalyzerOverloadScoring(context, clrConversion, assignability, resolver, null)
}

// The same owner WITH a well-known-type bag read out of a MetadataLoadContext, which is how the
// analyzer sees an external assembly.
func OverloadScoringWithWellKnownTypes(loadContext: MetadataLoadContext): AnalyzerOverloadScoring {
    core := loadContext.LoadFromAssemblyName("System.Runtime")
    wellKnown := new AnalyzerWellKnownTypes(loadContext, core)
    context := OverloadContext()
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    resolver := OverloadResolver(scopes, context)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, wellKnown)
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, wellKnown)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    return new AnalyzerOverloadScoring(context, clrConversion, assignability, resolver, wellKnown)
}

// The rendered NAME of a TypeInfo. `BuiltInTypes.Int` and friends are computed properties that
// allocate a FRESH instance on every read, so reference identity cannot be asserted against them.
func OverloadTypeName(typeInfo: TypeInfo?): string {
    if typeInfo == null {
        return "<null>"
    }

    typeObject := typeInfo as object
    return typeObject.ToString()
}

func OverloadSignature(parameterTypes: List<TypeInfo>): FunctionTypeInfo {
    modifiers := new List<ParameterModifier>()
    index := 0
    while index < parameterTypes.Count {
        modifiers.Add(ParameterModifier.None)
        index = index + 1
    }

    signature := new FunctionTypeInfo()
    signature.ParameterTypes = parameterTypes
    signature.ParameterModifiers = modifiers
    return signature
}

func OverloadTypeList(first: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    return types
}

func OverloadTypeList2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    types.Add(second)
    return types
}

// `RequiredParameterCount` is a NULLABLE int: assigning a plain `int` into it is off the columnar
// surface, so it is bound through a nullable local first.
func OverloadWithRequiredCount(signature: FunctionTypeInfo, requiredCount: int): FunctionTypeInfo {
    nullableCount: int? = requiredCount
    signature.RequiredParameterCount = nullableCount
    return signature
}

func OverloadIdentifierCall(): CallExpression {
    callee: Expression = new IdentifierExpression("f", 1, 1)
    return new CallExpression(callee, new List<Argument>(), null, 1, 1)
}

func OverloadMemberAccessCall(): CallExpression {
    receiver: Expression = new IdentifierExpression("receiver", 1, 1)
    callee: Expression = new MemberAccessExpression(receiver, "f", false, 1, 1)
    return new CallExpression(callee, new List<Argument>(), null, 1, 1)
}

// By NAME AND ARITY rather than through `GetMethod(name)`: most of these names are overloaded, and
// the single-argument lookup would throw rather than choose.
func OverloadMethodOfArity(owner: Type, name: string, parameterCount: int): MethodInfo {
    methods := owner.GetMethods()
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == name && candidate.GetParameters().Length == parameterCount {
            return candidate
        }

        index = index + 1
    }

    throw new InvalidOperationException("No '" + name + "' of that arity.")
}

func OverloadEnumerableMethod(name: string, parameterCount: int): MethodInfo {
    enumerableType := OverloadRuntimeType("System.Linq.Enumerable, System.Linq")
    methods := enumerableType.GetMethods()
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == name && candidate.GetParameters().Length == parameterCount {
            return candidate
        }

        index = index + 1
    }

    throw new InvalidOperationException("Enumerable has no '" + name + "' of that arity.")
}

// ---------------------------------------------------------------- the reflection ladder

test "the reflection ladder ranks identity 8, implicit numeric 6, assignable 4 and anything else 2" {
    assert AnalyzerOverloadFacts.GetReflectionMatchScore(typeof(int), typeof(int)) == 8
    assert AnalyzerOverloadFacts.GetReflectionMatchScore(typeof(long), typeof(int)) == 6
    assert AnalyzerOverloadFacts.GetReflectionMatchScore(typeof(object), typeof(string)) == 4
    assert AnalyzerOverloadFacts.GetReflectionMatchScore(typeof(string), typeof(int)) == 2
}

// The ladder ORDERS survivors; it never refuses. An unrelated pair still scores, because
// applicability was already decided by the matcher.
test "the reflection ladder never refuses an unrelated pair" {
    dateTime := OverloadRuntimeType("System.DateTime, System.Private.CoreLib")
    guid := OverloadRuntimeType("System.Guid, System.Private.CoreLib")
    assert AnalyzerOverloadFacts.GetReflectionMatchScore(dateTime, guid) == 2
}

// ---------------------------------------------------------------- matching and inference

test "an unbound reflection type parameter binds, and a later position must agree with the binding" {
    identity := OverloadEnumerableMethod("Count", 1)
    sequenceParameter := identity.GetParameters()[0].get_ParameterType()
    elementParameter := sequenceParameter.GetGenericArguments()[0]

    bindings := new Dictionary<Type, Type>()
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(elementParameter, typeof(int), bindings)
    bound: Type = typeof(object)
    assert bindings.TryGetValue(elementParameter, out bound)
    assert bound == typeof(int)

    // The SAME parameter, a second time: a disagreeing argument is refused, an assignable one and an
    // implicit numeric widening are accepted.
    assert !AnalyzerOverloadFacts.TryMatchReflectionParameter(elementParameter, typeof(string), bindings)
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(elementParameter, typeof(int), bindings)
}

test "a bound reflection type parameter accepts an assignable argument and a numeric widening" {
    identity := OverloadEnumerableMethod("Count", 1)
    elementParameter := identity.GetParameters()[0].get_ParameterType().GetGenericArguments()[0]

    objectBindings := new Dictionary<Type, Type>()
    objectBindings[elementParameter] = typeof(object)
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(elementParameter, typeof(string), objectBindings)

    longBindings := new Dictionary<Type, Type>()
    longBindings[elementParameter] = typeof(long)
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(elementParameter, typeof(int), longBindings)
    assert !AnalyzerOverloadFacts.TryMatchReflectionParameter(elementParameter, typeof(string), longBindings)
}

test "a closed reflection parameter is a plain assignability question" {
    bindings := new Dictionary<Type, Type>()
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(typeof(object), typeof(string), bindings)
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(typeof(long), typeof(int), bindings)
    assert !AnalyzerOverloadFacts.TryMatchReflectionParameter(typeof(string), typeof(int), bindings)
    assert bindings.Count == 0
}

test "a by-ref reflection parameter matches through its element type" {
    byRefInt := typeof(int).MakeByRefType()
    bindings := new Dictionary<Type, Type>()
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(byRefInt, typeof(int), bindings)
    assert !AnalyzerOverloadFacts.TryMatchReflectionParameter(byRefInt, typeof(string), bindings)
}

test "an open array parameter descends into its element and refuses a non-array argument" {
    identity := OverloadEnumerableMethod("Count", 1)
    elementParameter := identity.GetParameters()[0].get_ParameterType().GetGenericArguments()[0]
    openArray := elementParameter.MakeArrayType()

    arrayBindings := new Dictionary<Type, Type>()
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(openArray, typeof(int[]), arrayBindings)
    bound: Type = typeof(object)
    assert arrayBindings.TryGetValue(elementParameter, out bound)
    assert bound == typeof(int)

    scalarBindings := new Dictionary<Type, Type>()
    assert !AnalyzerOverloadFacts.TryMatchReflectionParameter(openArray, typeof(int), scalarBindings)
}

// The case the argument walk exists for: a `List<int>` argument against an `IEnumerable<T>`
// parameter binds `T` to `int` through the argument's INTERFACE, not its own definition.
test "an open generic parameter matches through the argument's interface" {
    identity := OverloadEnumerableMethod("Count", 1)
    sequenceParameter := identity.GetParameters()[0].get_ParameterType()
    elementParameter := sequenceParameter.GetGenericArguments()[0]

    bindings := new Dictionary<Type, Type>()
    listOfInt := OverloadClosed1("System.Collections.Generic.List`1, System.Private.CoreLib", typeof(int))
    assert AnalyzerOverloadFacts.TryMatchReflectionParameter(sequenceParameter, listOfInt, bindings)
    bound: Type = typeof(object)
    assert bindings.TryGetValue(elementParameter, out bound)
    assert bound == typeof(int)
}

test "an open generic parameter refuses an argument that cannot be re-expressed over its definition" {
    identity := OverloadEnumerableMethod("Count", 1)
    sequenceParameter := identity.GetParameters()[0].get_ParameterType()
    bindings := new Dictionary<Type, Type>()
    assert !AnalyzerOverloadFacts.TryMatchReflectionParameter(sequenceParameter, typeof(int), bindings)
}

test "a compatible generic type is searched for on the type itself, its interfaces and its base chain" {
    listDefinition := OverloadRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib")
    listOfInt := OverloadClosed1("System.Collections.Generic.List`1, System.Private.CoreLib", typeof(int))

    // The type ITSELF.
    selfMatch: Type? = null
    assert AnalyzerOverloadFacts.TryFindCompatibleGenericType(listOfInt, listOfInt, out selfMatch)
    assert selfMatch == listOfInt

    // An INTERFACE the argument implements.
    enumerableOfInt := OverloadClosed1(
        "System.Collections.Generic.IEnumerable`1, System.Private.CoreLib",
        typeof(int)
    )
    interfaceMatch: Type? = null
    assert AnalyzerOverloadFacts.TryFindCompatibleGenericType(enumerableOfInt, listOfInt, out interfaceMatch)
    assert interfaceMatch == enumerableOfInt

    // Nothing at all.
    missing: Type? = null
    assert !AnalyzerOverloadFacts.TryFindCompatibleGenericType(listDefinition, typeof(int), out missing)
    assert missing == null

    // A NON-generic parameter never has a compatible instantiation.
    nonGeneric: Type? = null
    assert !AnalyzerOverloadFacts.TryFindCompatibleGenericType(typeof(int), listOfInt, out nonGeneric)
}

// ---------------------------------------------------------------- extensions

test "an extension receiver is compatible closed by assignability and open by re-expression" {
    // Closed: `IEnumerable<int>` accepts a `List<int>` receiver but not an `int`.
    enumerableOfInt := OverloadClosed1(
        "System.Collections.Generic.IEnumerable`1, System.Private.CoreLib",
        typeof(int)
    )
    listOfInt := OverloadClosed1("System.Collections.Generic.List`1, System.Private.CoreLib", typeof(int))
    assert AnalyzerOverloadFacts.IsExtensionParameterCompatible(enumerableOfInt, listOfInt)
    assert !AnalyzerOverloadFacts.IsExtensionParameterCompatible(enumerableOfInt, typeof(int))

    // Open: the OPEN `IEnumerable<TSource>` receiver of `Enumerable.Count` accepts the same list,
    // because the type argument is inferred later.
    openReceiver := OverloadEnumerableMethod("Count", 1).GetParameters()[0].get_ParameterType()
    assert AnalyzerOverloadFacts.IsExtensionParameterCompatible(openReceiver, listOfInt)
    assert !AnalyzerOverloadFacts.IsExtensionParameterCompatible(openReceiver, typeof(int))
}

// Read by FULL NAME, not by type identity: through a MetadataLoadContext the attribute is a
// different type object from the compiler's own.
test "the extension and params attributes are read by full name" {
    assert AnalyzerOverloadFacts.HasExtensionAttribute(OverloadEnumerableMethod("Count", 1))
    assert !AnalyzerOverloadFacts.HasExtensionAttribute(OverloadMethodOfArity(typeof(object), "GetType", 0))

    formatParameters := OverloadFormatMethod().GetParameters()
    paramsParameter := formatParameters[1]
    fixedParameter := formatParameters[0]
    assert AnalyzerOverloadFacts.IsParamsParameter(paramsParameter)
    assert !AnalyzerOverloadFacts.IsParamsParameter(fixedParameter)
}

// `string.Format(string, params object[])` — the canonical params signature.
func OverloadFormatMethod(): MethodInfo {
    stringType := OverloadRuntimeType("System.String, System.Private.CoreLib")
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

    throw new InvalidOperationException("string.Format(string, params object[]) was not found.")
}

// A receiver-style call against an extension method; the bare form asks only the syntactic question,
// the receiver form also checks the receiver.
test "an extension method call needs a member-access callee, and the receiver form checks the receiver" {
    countMethod := OverloadEnumerableMethod("Count", 1)
    listOfInt := OverloadClosed1("System.Collections.Generic.List`1, System.Private.CoreLib", typeof(int))

    assert AnalyzerOverloadFacts.IsExtensionMethodCall(countMethod, OverloadMemberAccessCall())
    assert !AnalyzerOverloadFacts.IsExtensionMethodCall(countMethod, OverloadIdentifierCall())

    assert AnalyzerOverloadFacts.IsExtensionMethodCallOnReceiver(
        countMethod,
        OverloadMemberAccessCall(),
        listOfInt
    )
    assert !AnalyzerOverloadFacts.IsExtensionMethodCallOnReceiver(
        countMethod,
        OverloadMemberAccessCall(),
        typeof(int)
    )
    assert !AnalyzerOverloadFacts.IsExtensionMethodCallOnReceiver(
        countMethod,
        OverloadMemberAccessCall(),
        null
    )
}

// ---------------------------------------------------------------- arity and params

test "the reflection arity filter counts only non-optional non-params parameters as required" {
    // `string.Format(string, params object[])`: one required parameter, no upper bound.
    formatParameters := OverloadFormatMethod().GetParameters()
    assert !AnalyzerOverloadFacts.HasCompatibleReflectionArity(formatParameters, 0, 0)
    assert AnalyzerOverloadFacts.HasCompatibleReflectionArity(formatParameters, 0, 1)
    assert AnalyzerOverloadFacts.HasCompatibleReflectionArity(formatParameters, 0, 9)

    // The OFFSET skips an extension receiver, so the same list admits one fewer argument.
    assert AnalyzerOverloadFacts.HasCompatibleReflectionArity(formatParameters, 1, 0)

    // A fixed signature DOES have an upper bound.
    substringParameters := OverloadMethodOfArity(typeof(string), "Substring", 1).GetParameters()
    assert AnalyzerOverloadFacts.HasCompatibleReflectionArity(substringParameters, 0, 1)
    assert !AnalyzerOverloadFacts.HasCompatibleReflectionArity(substringParameters, 0, 2)
}

test "a params parameter's element type covers arrays, the span family and read-only sequences" {
    arrayElement: Type = typeof(object)
    assert AnalyzerOverloadFacts.TryGetReflectionParamsElementType(typeof(int[]), out arrayElement)
    assert arrayElement == typeof(int)

    readOnlySpanOfInt := OverloadClosed1("System.ReadOnlySpan`1, System.Private.CoreLib", typeof(int))
    spanElement: Type = typeof(object)
    assert AnalyzerOverloadFacts.TryGetReflectionParamsElementType(readOnlySpanOfInt, out spanElement)
    assert spanElement == typeof(int)

    readOnlyListOfString := OverloadClosed1(
        "System.Collections.Generic.IReadOnlyList`1, System.Private.CoreLib",
        typeof(string)
    )
    listElement: Type = typeof(object)
    assert AnalyzerOverloadFacts.TryGetReflectionParamsElementType(readOnlyListOfString, out listElement)
    assert listElement == typeof(string)

    // Anything else answers false AND `object`, because the caller uses the element type either way.
    dictionaryOfIntString := OverloadClosed2(
        "System.Collections.Generic.Dictionary`2, System.Private.CoreLib",
        typeof(int),
        typeof(string)
    )
    otherElement: Type = typeof(string)
    assert !AnalyzerOverloadFacts.TryGetReflectionParamsElementType(dictionaryOfIntString, out otherElement)
    assert otherElement == typeof(object)
}

// The third params question: a bound argument whose OPEN parameter type is the element type came
// from an expanded tail; one whose open type is the declared array type was passed directly.
test "an expanded params argument is distinguished from a directly passed array" {
    formatParameters := OverloadFormatMethod().GetParameters()
    paramsParameter := formatParameters[1]
    fixedParameter := formatParameters[0]

    expandedElement := OverloadBoundArgument(1, typeof(object))
    directArray := OverloadBoundArgument(1, typeof(object[]))
    assert AnalyzerOverloadFacts.IsExpandedReflectionParamsArgument(
        expandedElement,
        paramsParameter
    )
    assert !AnalyzerOverloadFacts.IsExpandedReflectionParamsArgument(
        directArray,
        paramsParameter
    )

    // A parameter that is not a params tail is never expanded.
    fixedArgument := OverloadBoundArgument(0, typeof(string))
    assert !AnalyzerOverloadFacts.IsExpandedReflectionParamsArgument(
        fixedArgument,
        fixedParameter
    )
}

// A bound argument for the expansion question. Only the position and the OPEN parameter type
// participate; the argument node is a placeholder.
func OverloadBoundArgument(
    parameterIndex: int,
    openParameterType: Type
): SuppliedReflectionBoundArgument {
    placeholder := new Argument(
        null,
        new IdentifierExpression("x", 1, 1),
        ArgumentModifier.None
    )
    return new SuppliedReflectionBoundArgument(
        parameterIndex,
        openParameterType,
        placeholder,
        parameterIndex
    )
}

test "a by-ref element type is taken off, and a non-by-ref type is itself" {
    assert AnalyzerOverloadFacts.GetByRefElementType(typeof(int).MakeByRefType()) == typeof(int)
    assert AnalyzerOverloadFacts.GetByRefElementType(typeof(int)) == typeof(int)
}

// ---------------------------------------------------------------- lambda targets

test "a lambda's delegate target strips the by-ref shell and unwraps an expression tree" {
    funcOfIntInt := OverloadClosed2("System.Func`2, System.Private.CoreLib", typeof(int), typeof(int))
    expressionOfFunc := OverloadClosed1(
        "System.Linq.Expressions.Expression`1, System.Linq.Expressions",
        funcOfIntInt
    )

    assert AnalyzerOverloadFacts.GetDelegateParameterTypeForLambdaTarget(funcOfIntInt) == funcOfIntInt
    assert AnalyzerOverloadFacts.GetDelegateParameterTypeForLambdaTarget(expressionOfFunc) == funcOfIntInt
    assert AnalyzerOverloadFacts.GetDelegateParameterTypeForLambdaTarget(
        expressionOfFunc.MakeByRefType()
    ) == funcOfIntInt
}

// Without a well-known-type bag there are no metadata facts at all, so the answer is false rather
// than a guess. With one, only the delegate ROOTS answer true.
test "a broad delegate parameter is only System.Delegate itself, and needs a well-known-type bag" {
    funcOfIntInt := OverloadClosed2("System.Func`2, System.Private.CoreLib", typeof(int), typeof(int))
    delegateRoot := OverloadRuntimeType("System.Delegate, System.Private.CoreLib")
    multicastRoot := OverloadRuntimeType("System.MulticastDelegate, System.Private.CoreLib")
    bagless := OverloadScoringDefault()
    assert !bagless.IsBroadDelegateType(delegateRoot)

    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        scoring := OverloadScoringWithWellKnownTypes(context)
        assert scoring.IsBroadDelegateType(delegateRoot)
        assert scoring.IsBroadDelegateType(multicastRoot)
        assert !scoring.IsBroadDelegateType(funcOfIntInt)
    } finally {
        scan.Dispose()
    }
}

test "a lambda may only take a broad delegate parameter when every parameter is annotated" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        scoring := OverloadScoringWithWellKnownTypes(context)
        bindings := new Dictionary<Type, Type>()
        delegateRoot := OverloadRuntimeType("System.Delegate, System.Private.CoreLib")

        annotated := OverloadLambda("x", "int")
        assert scoring.CanInferBroadDelegateLambda(delegateRoot, bindings, annotated)

        // `var` is the parser's stand-in for an UNANNOTATED lambda parameter: there is no delegate
        // shape to infer it from, so the lambda cannot take a broad parameter.
        inferred := OverloadLambda("x", "var")
        assert !scoring.CanInferBroadDelegateLambda(delegateRoot, bindings, inferred)

        // And a CONCRETE delegate parameter is not broad at all.
        funcOfIntInt := OverloadClosed2("System.Func`2, System.Private.CoreLib", typeof(int), typeof(int))
        assert !scoring.CanInferBroadDelegateLambda(funcOfIntInt, bindings, annotated)
    } finally {
        scan.Dispose()
    }
}

func OverloadLambda(parameterName: string, typeName: string): LambdaExpression {
    parameterType: TypeReference = new SimpleTypeReference(typeName)
    parameters := new List<Parameter>()
    parameters.Add(new Parameter(parameterName, parameterType, null, false, ParameterModifier.None, null, 1, 1, false, null))
    return new LambdaExpression(parameters, null, null, 1, 1)
}

test "a broad delegate lambda contributes its annotated parameters with no modifiers and no return type" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        scoring := OverloadScoringWithWellKnownTypes(context)
        bindings := new Dictionary<Type, Type>()
        delegateRoot := OverloadRuntimeType("System.Delegate, System.Private.CoreLib")

        signature := scoring.CreateBroadDelegateSignatureForLambda(
            delegateRoot,
            bindings,
            OverloadLambda("x", "int")
        )
        assert signature != null
        parameterTypes := signature.ParameterTypes
        assert parameterTypes != null
        assert parameterTypes.Count == 1
        modifiers := signature.ParameterModifiers
        assert modifiers != null
        assert modifiers[0] == ParameterModifier.None
        assert signature.ReturnType == null

        // An un-annotated lambda produces NO signature rather than a partial one.
        assert scoring.CreateBroadDelegateSignatureForLambda(
            delegateRoot,
            bindings,
            OverloadLambda("x", "var")
        ) == null
    } finally {
        scan.Dispose()
    }
}

// ---------------------------------------------------------------- operator applicability

// A NULL operand type is INCOMPATIBLE, deliberately: the IL backend would not bind the operator
// either, and answering true would let an unrelated operand swallow a real type mismatch.
test "an operator parameter refuses an unknown operand and accepts assignable, identical and by-ref" {
    assert !AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(typeof(int), null)
    assert AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(typeof(int), typeof(int))
    assert AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(typeof(object), typeof(string))
    assert AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(
        typeof(int).MakeByRefType(),
        typeof(int)
    )
    assert !AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(typeof(int), typeof(string))
}

// ---------------------------------------------------------------- the source arity tables

// THREE conditions, and the middle one is the guard: a signature whose modifier list disagrees with
// its parameter list is treated as having no params tail rather than being indexed into.
test "a source params index needs the flag, a full-length modifier list and the modifier last" {
    types := OverloadTypeList2(BuiltInTypes.Int, new ArrayTypeInfo(BuiltInTypes.Int))

    withoutFlag := OverloadSignature(types)
    assert AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(withoutFlag, 2) == -1

    modifiers := new List<ParameterModifier>()
    modifiers.Add(ParameterModifier.None)
    modifiers.Add(ParameterModifier.Params)
    withParams := OverloadSignature(types)
    withParams.HasParamsParameter = true
    withParams.ParameterModifiers = modifiers
    assert AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(withParams, 2) == 1

    // A modifier list of the wrong length is not trusted.
    assert AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(withParams, 1) == -1

    // Nor is a modifier in the wrong position.
    misplaced := new List<ParameterModifier>()
    misplaced.Add(ParameterModifier.Params)
    misplaced.Add(ParameterModifier.None)
    withMisplaced := OverloadSignature(types)
    withMisplaced.HasParamsParameter = true
    withMisplaced.ParameterModifiers = misplaced
    assert AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(withMisplaced, 2) == -1

    // An empty signature has no tail at all.
    assert AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(withParams, 0) == -1
}

test "a declared required count outside the signature is ignored rather than trusted" {
    types := OverloadTypeList2(BuiltInTypes.Int, BuiltInTypes.String)

    unstated := OverloadSignature(types)
    assert AnalyzerOverloadFacts.GetSyntheticRequiredParameterCount(unstated, 2) == 2

    stated := OverloadWithRequiredCount(OverloadSignature(types), 1)
    assert AnalyzerOverloadFacts.GetSyntheticRequiredParameterCount(stated, 2) == 1

    tooLarge := OverloadWithRequiredCount(OverloadSignature(types), 5)
    assert AnalyzerOverloadFacts.GetSyntheticRequiredParameterCount(tooLarge, 2) == 2

    negative := OverloadWithRequiredCount(OverloadSignature(types), -1)
    assert AnalyzerOverloadFacts.GetSyntheticRequiredParameterCount(negative, 2) == 2
}

test "the required ARGUMENT count subtracts the clamped receiver offset and floors at zero" {
    types := OverloadTypeList2(BuiltInTypes.Int, BuiltInTypes.String)
    signature := OverloadSignature(types)

    assert AnalyzerOverloadFacts.GetSyntheticRequiredArgumentCount(signature, 2, 0) == 2
    assert AnalyzerOverloadFacts.GetSyntheticRequiredArgumentCount(signature, 2, 1) == 1

    // A nonsense offset is clamped rather than producing a negative count.
    assert AnalyzerOverloadFacts.GetSyntheticRequiredArgumentCount(signature, 2, 9) == 0
    assert AnalyzerOverloadFacts.GetSyntheticRequiredArgumentCount(signature, 2, -3) == 2

    withDefault := OverloadWithRequiredCount(OverloadSignature(types), 1)
    assert AnalyzerOverloadFacts.GetSyntheticRequiredArgumentCount(withDefault, 2, 1) == 0
}

// BOTH halves are required. A receiver-style signature invoked WITHOUT a member access — a bare call
// to an extension by its declared name — supplies every parameter positionally.
test "the receiver offset needs both the signature flag and a member-access callee" {
    plain := OverloadSignature(OverloadTypeList(BuiltInTypes.Int))
    assert AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(plain, OverloadMemberAccessCall()) == 0

    receiverStyle := OverloadSignature(OverloadTypeList(BuiltInTypes.Int))
    receiverStyle.SourceHasReceiverParameter = true
    assert AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(
        receiverStyle,
        OverloadMemberAccessCall()
    ) == 1
    assert AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(
        receiverStyle,
        OverloadIdentifierCall()
    ) == 0
}

test "only a bare type-parameter name counts as a direct type-parameter reference" {
    typeParameters := new List<TypeParameter>()
    typeParameters.Add(new TypeParameter("T"))

    bare: TypeReference = new SimpleTypeReference("T")
    assert AnalyzerOverloadFacts.IsDirectFunctionTypeParameterReference(bare, typeParameters)

    other: TypeReference = new SimpleTypeReference("int")
    assert !AnalyzerOverloadFacts.IsDirectFunctionTypeParameterReference(other, typeParameters)

    // An F-bounded shape mentions `T` but is not a bare reference to it.
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("T"))
    wrapped: TypeReference = new GenericTypeReference("List", arguments, 1, 1)
    assert !AnalyzerOverloadFacts.IsDirectFunctionTypeParameterReference(wrapped, typeParameters)
}

test "params inference reads a params reference's element rather than the sequence" {
    element: TypeReference = new SimpleTypeReference("T")
    arrayReference: TypeReference = new ArrayTypeReference(element)
    assert AnalyzerOverloadFacts.GetParamsInferenceTypeReference(arrayReference) == element

    genericArguments := new List<TypeReference>()
    genericArguments.Add(element)
    genericReference: TypeReference = new GenericTypeReference("ReadOnlySpan", genericArguments, 1, 1)
    assert AnalyzerOverloadFacts.GetParamsInferenceTypeReference(genericReference) == element

    // A two-argument generic is not a sequence shape, so it reads as itself.
    twoArguments := new List<TypeReference>()
    twoArguments.Add(element)
    twoArguments.Add(new SimpleTypeReference("int"))
    pairReference: TypeReference = new GenericTypeReference("Dictionary", twoArguments, 1, 1)
    assert AnalyzerOverloadFacts.GetParamsInferenceTypeReference(pairReference) == pairReference

    plain: TypeReference = new SimpleTypeReference("int")
    assert AnalyzerOverloadFacts.GetParamsInferenceTypeReference(plain) == plain
}

test "a ref or out source parameter carries a by-ref type, idempotently" {
    modifiers := new List<ParameterModifier>()
    modifiers.Add(ParameterModifier.Ref)
    modifiers.Add(ParameterModifier.Out)
    modifiers.Add(ParameterModifier.None)
    signature := OverloadSignature(OverloadTypeList(BuiltInTypes.Int))
    signature.ParameterModifiers = modifiers

    intType: TypeInfo = BuiltInTypes.Int

    wrappedRef := AnalyzerOverloadFacts.ApplySyntheticParameterModifier(signature, 0, intType)
    refShell := wrappedRef as ByRefTypeInfo
    assert refShell != null

    wrappedOut := AnalyzerOverloadFacts.ApplySyntheticParameterModifier(signature, 1, intType)
    outShell := wrappedOut as ByRefTypeInfo
    assert outShell != null

    unwrapped := AnalyzerOverloadFacts.ApplySyntheticParameterModifier(signature, 2, intType)
    assert Object.ReferenceEquals(unwrapped, intType)

    // Already by-ref: the shell is not doubled.
    existing: TypeInfo = new ByRefTypeInfo(intType)
    doubled := AnalyzerOverloadFacts.ApplySyntheticParameterModifier(signature, 0, existing)
    assert Object.ReferenceEquals(doubled, existing)

    // An index outside the modifier list is left alone.
    outside := AnalyzerOverloadFacts.ApplySyntheticParameterModifier(signature, 9, intType)
    assert Object.ReferenceEquals(outside, intType)
}

test "generic names match across qualification in either direction" {
    assert AnalyzerOverloadFacts.GenericNamesMatch("List", "List")
    assert AnalyzerOverloadFacts.GenericNamesMatch("List", "System.Collections.Generic.List")
    assert AnalyzerOverloadFacts.GenericNamesMatch("System.Collections.Generic.List", "List")
    assert !AnalyzerOverloadFacts.GenericNamesMatch("List", "Dictionary")
    assert !AnalyzerOverloadFacts.GenericNamesMatch("List", "System.Collections.Generic.LinkedList")
}

// ---------------------------------------------------------------- the source ladder

test "the source ladder ranks identity 8, implicit numeric 6, assignable 4 and anything else 2" {
    scoring := OverloadScoringDefault()
    assert scoring.GetNSharpMatchScore(BuiltInTypes.Int, BuiltInTypes.Int) == 8
    assert scoring.GetNSharpMatchScore(BuiltInTypes.Long, BuiltInTypes.Int) == 6
    assert scoring.GetNSharpMatchScore(BuiltInTypes.Object, BuiltInTypes.String) == 4
    assert scoring.GetNSharpMatchScore(BuiltInTypes.String, BuiltInTypes.Int) == 2
}

// The CROSS-REPRESENTATION rule: a `SimpleTypeInfo` from source and a `ReflectionTypeInfo` from
// metadata that denote the same CLR type are IDENTICAL, which is what stops source `int` from losing
// to metadata `System.Int32`.
test "the source ladder scores a source type and its metadata representation as identical" {
    scoring := OverloadScoringDefault()
    reflectedInt: TypeInfo = new ReflectionTypeInfo(typeof(int))
    assert scoring.GetNSharpMatchScore(BuiltInTypes.Int, reflectedInt) == 8
    assert scoring.GetNSharpMatchScore(reflectedInt, BuiltInTypes.Int) == 8
}

// The one relaxation over plain assignability, and its exact boundary: a nullable REFERENCE type
// unwraps because the annotation is not a conversion; a nullable VALUE type does not.
test "a reflection argument may unwrap a nullable REFERENCE type but not a nullable value type" {
    scoring := OverloadScoringDefault()

    nullableString: TypeInfo = new NullableTypeInfo(BuiltInTypes.String)
    assert scoring.IsAssignableReflectionArgument(BuiltInTypes.String, nullableString)

    nullableInt: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    assert !scoring.IsAssignableReflectionArgument(BuiltInTypes.Int, nullableInt)

    // A plain assignable pair still answers through the first arm.
    assert scoring.IsAssignableReflectionArgument(BuiltInTypes.Object, BuiltInTypes.String)
    assert !scoring.IsAssignableReflectionArgument(BuiltInTypes.Int, BuiltInTypes.String)
}

test "a source params element type covers arrays and single-argument generics, and is null otherwise" {
    scoring := OverloadScoringDefault()

    arrayElement := scoring.GetNSharpParamsElementType(new ArrayTypeInfo(BuiltInTypes.Int))
    assert OverloadTypeName(arrayElement) == "int"

    genericElement := scoring.GetNSharpParamsElementType(
        new GenericTypeInfo("ReadOnlySpan", OverloadTypeList(BuiltInTypes.Int))
    )
    assert OverloadTypeName(genericElement) == "int"

    assert scoring.GetNSharpParamsElementType(
        new GenericTypeInfo("Dictionary", OverloadTypeList2(BuiltInTypes.Int, BuiltInTypes.String))
    ) == null
    assert scoring.GetNSharpParamsElementType(BuiltInTypes.Int) == null
}

test "a directly passed params array is exactly one trailing non-spread assignable argument" {
    scoring := OverloadScoringDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    direct := new List<Argument>()
    direct.Add(new Argument(null, new IdentifierExpression("xs", 1, 1), ArgumentModifier.None))
    directTypes := OverloadTypeList(arrayType)
    assert scoring.IsSingleDirectNSharpParamsArrayArgument(0, direct, directTypes, arrayType)

    // A SPREAD is an expansion, not a direct array.
    spread := new List<Argument>()
    spreadValue: Expression = new SpreadExpression(new IdentifierExpression("xs", 1, 1), 1, 1)
    spread.Add(new Argument(null, spreadValue, ArgumentModifier.None))
    assert !scoring.IsSingleDirectNSharpParamsArrayArgument(0, spread, directTypes, arrayType)

    // A non-assignable single argument is a loose element, not the array.
    scalarTypes := OverloadTypeList(BuiltInTypes.Int)
    assert !scoring.IsSingleDirectNSharpParamsArrayArgument(0, direct, scalarTypes, arrayType)

    // Two arguments cannot be one array.
    twoArguments := new List<Argument>()
    twoArguments.Add(new Argument(null, new IdentifierExpression("a", 1, 1), ArgumentModifier.None))
    twoArguments.Add(new Argument(null, new IdentifierExpression("b", 1, 1), ArgumentModifier.None))
    twoTypes := OverloadTypeList2(arrayType, arrayType)
    assert !scoring.IsSingleDirectNSharpParamsArrayArgument(0, twoArguments, twoTypes, arrayType)
}

test "a spread argument contributes its ELEMENT type to generic inference" {
    scoring := OverloadScoringDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    spreadValue: Expression = new SpreadExpression(new IdentifierExpression("xs", 1, 1), 1, 1)
    spreadArgument := new Argument(null, spreadValue, ArgumentModifier.None)
    spreadElement := scoring.GetParamsInferenceArgumentType(spreadArgument, arrayType)
    assert OverloadTypeName(spreadElement) == "int"

    // A plain argument contributes itself, spread or not.
    plainArgument := new Argument(null, new IdentifierExpression("xs", 1, 1), ArgumentModifier.None)
    plainResult := scoring.GetParamsInferenceArgumentType(plainArgument, arrayType)
    assert Object.ReferenceEquals(plainResult, arrayType)

    // A spread of a NON-array contributes itself too.
    scalarType: TypeInfo = BuiltInTypes.Int
    scalarResult := scoring.GetParamsInferenceArgumentType(spreadArgument, scalarType)
    assert Object.ReferenceEquals(scalarResult, scalarType)
}

// ---------------------------------------------------------------- the NL402 renderers

test "a reflected candidate's signature drops the receiver for a receiver-style extension call" {
    countMethod := OverloadEnumerableMethod("Count", 1)
    withReceiver := AnalyzerOverloadFacts.FormatReflectionMethodSignature(
        countMethod,
        OverloadMemberAccessCall()
    )
    withoutReceiver := AnalyzerOverloadFacts.FormatReflectionMethodSignature(
        countMethod,
        OverloadIdentifierCall()
    )

    assert withReceiver.StartsWith("Count(")
    assert withReceiver.Contains("()")
    assert withoutReceiver.StartsWith("Count(")
    assert !withoutReceiver.Contains("()")
    assert withReceiver.Contains("): ")
}

test "a source candidate's signature renders type parameters, the clamped offset and the return type" {
    types := OverloadTypeList2(BuiltInTypes.Int, BuiltInTypes.String)
    signature := OverloadSignature(types)
    signature.ReturnType = BuiltInTypes.Bool
    names := new List<string>()
    names.Add("a")
    names.Add("b")
    signature.ParameterNames = names
    typeParameters := new List<TypeParameter>()
    typeParameters.Add(new TypeParameter("T"))
    signature.TypeParameters = typeParameters

    assert AnalyzerOverloadFacts.FormatSyntheticFunctionSignature(signature, "f", 0) == "f<T>(a: int, b: string): bool"

    // The receiver offset drops the first parameter.
    assert AnalyzerOverloadFacts.FormatSyntheticFunctionSignature(signature, "f", 1) == "f<T>(b: string): bool"

    // A nonsense offset is clamped to an empty list rather than indexing out of the signature.
    assert AnalyzerOverloadFacts.FormatSyntheticFunctionSignature(signature, "f", 9) == "f<T>(): bool"
    assert AnalyzerOverloadFacts.FormatSyntheticFunctionSignature(signature, "f", -3) == "f<T>(a: int, b: string): bool"
}

test "a source parameter renders its modifier, its source type name and its default marker" {
    sourceTypes := new List<TypeReference>()
    sourceTypes.Add(new SimpleTypeReference("int"))
    sourceTypes.Add(new SimpleTypeReference("string"))
    sourceTypes.Add(new ArrayTypeReference(new SimpleTypeReference("int")))
    modifiers := new List<ParameterModifier>()
    modifiers.Add(ParameterModifier.Ref)
    modifiers.Add(ParameterModifier.None)
    modifiers.Add(ParameterModifier.Params)
    names := new List<string>()
    names.Add("a")
    names.Add("b")
    names.Add("rest")

    types := new List<TypeInfo>()
    types.Add(BuiltInTypes.Int)
    types.Add(BuiltInTypes.String)
    types.Add(new ArrayTypeInfo(BuiltInTypes.Int))
    signature := OverloadWithRequiredCount(OverloadSignature(types), 1)
    signature.SourceParameterTypes = sourceTypes
    signature.ParameterModifiers = modifiers
    signature.ParameterNames = names

    // The SOURCE reference is preferred, so the hint echoes what the user wrote.
    assert AnalyzerOverloadFacts.FormatSyntheticParameterSignature(signature, 0) == "ref a: int"

    // Past the required count: a default marker.
    assert AnalyzerOverloadFacts.FormatSyntheticParameterSignature(signature, 1) == "b: string = ..."

    // Except for the params tail, which has no default.
    assert AnalyzerOverloadFacts.FormatSyntheticParameterSignature(signature, 2) == "params rest: int[]"
}

test "a source parameter with no name or source type falls back to a positional name and the resolved type" {
    types := OverloadTypeList(BuiltInTypes.Int)
    signature := OverloadSignature(types)
    assert AnalyzerOverloadFacts.FormatSyntheticParameterSignature(signature, 0) == "arg1: int"
}
