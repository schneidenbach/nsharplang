namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the analyzer's `FunctionTypeInfo` factory.
//
// All four sources were `private` in Analyzer.cs. These contracts go at the decisions that are
// behaviour rather than plumbing:
//
//   * the `Func`/`Action` ARITY TABLES answer without consulting nullability metadata, and `Func`
//     takes its LAST type argument as the return type while `Action` takes them all as parameters;
//   * a delegate outside those tables is read through `Invoke`, WITH annotations;
//   * an `Expression<TDelegate>` unwraps to its delegate, including through a by-ref shell;
//   * the ASYNC call-return rule: only an async non-generator is wrapped, `main` gets the `Task`
//     family and everything else `ValueTask`, and an already task-like declared type is left alone;
//   * a function's OWN type parameters shadow, so `func F<T>(x: T)` names `T` rather than resolving
//     it.

// Generic definitions are resolved by CANONICAL IDENTITY rather than through `typeof`: the columnar
// `typeof` surface does not carry closed generic delegate or collection types, and the resolved
// instances are the identical runtime ones.
func FactoryRuntimeType(canonicalName: string): Type {
    resolved := Type.GetType(canonicalName)
    if resolved == null {
        throw new InvalidOperationException("The runtime does not define '" + canonicalName + "'.")
    }

    return resolved
}

func FactoryClosed1(canonicalName: string, first: Type): Type {
    definition := FactoryRuntimeType(canonicalName)
    arguments := new Type[](1)
    arguments[0] = first
    return definition.MakeGenericType(arguments)
}

func FactoryClosed2(canonicalName: string, first: Type, second: Type): Type {
    definition := FactoryRuntimeType(canonicalName)
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return definition.MakeGenericType(arguments)
}

func FactoryClosed3(canonicalName: string, first: Type, second: Type, third: Type): Type {
    definition := FactoryRuntimeType(canonicalName)
    arguments := new Type[](3)
    arguments[0] = first
    arguments[1] = second
    arguments[2] = third
    return definition.MakeGenericType(arguments)
}

func FactoryContext(): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    return context
}

func FactoryScopes(): AnalyzerScopeStack {
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    return scopes
}

func FactoryResolver(
    scopes: AnalyzerScopeStack,
    context: AnalyzerDeclarationContext): AnalyzerTypeResolver {
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    return new AnalyzerTypeResolver(
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
}

func FactoryUnderTest(): AnalyzerFunctionTypeFactory {
    context := FactoryContext()
    scopes := FactoryScopes()
    resolver := FactoryResolver(scopes, context)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    return new AnalyzerFunctionTypeFactory(context, substitution)
}

func FactoryParameter(name: string, typeName: string): Parameter {
    reference: TypeReference = new SimpleTypeReference(typeName)
    return new Parameter(name, reference, null, false, ParameterModifier.None, null, 1, 1, false, null)
}

func FactoryDeclaration(
    name: string,
    parameters: List<Parameter>,
    returnTypeName: string?,
    modifiers: Modifiers): FunctionDeclaration {
    returnType: TypeReference? = null
    if returnTypeName != null {
        returnType = new SimpleTypeReference(returnTypeName)
    }

    return new FunctionDeclaration(
        name, parameters, returnType, null, null, null, null, modifiers,
        new List<AttributeNode>(), false, null, false, false, 1, 1)
}

// `RequiredParameterCount` is a NULLABLE int; comparing one against a literal is off the columnar
// surface, so these contracts read it through its boxed rendering.
func FactoryRequiredCount(signature: FunctionTypeInfo): string {
    boxed: object? = signature.RequiredParameterCount
    if boxed == null {
        return "<null>"
    }

    return boxed.ToString()
}

func FactoryTypeName(typeInfo: TypeInfo?): string {
    if typeInfo == null {
        return "<null>"
    }

    simple := typeInfo as SimpleTypeInfo
    if simple != null {
        return simple.Name
    }

    generic := typeInfo as GenericTypeInfo
    if generic != null {
        return generic.Name + "<" + FactoryTypeName(generic.TypeArguments[0]) + ">"
    }

    reflection := typeInfo as ReflectionTypeInfo
    if reflection != null {
        reflected := reflection.Type
        name := reflected.get_FullName()
        if name == null {
            return "<unnamed>"
        }

        return name
    }

    unknown := typeInfo as UnknownTypeInfo
    if unknown != null {
        return "<unknown>"
    }

    return "<other>"
}

test "the Func arity table takes the last argument as the return type" {
    funcType := FactoryClosed3("System.Func`3, System.Private.CoreLib", typeof(int), typeof(string), typeof(bool))
    signature := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(funcType)
    parameterTypes := signature.ParameterTypes
    assert parameterTypes != null
    assert parameterTypes.Count == 2
    assert FactoryTypeName(parameterTypes[0]) == "int"
    assert FactoryTypeName(parameterTypes[1]) == "string"
    assert FactoryTypeName(signature.ReturnType) == "bool"

    modifiers := signature.ParameterModifiers
    assert modifiers != null
    assert modifiers.Count == 2
    assert modifiers[0] == ParameterModifier.None

    // `Func<T>` is the degenerate case: no parameters, the single argument IS the return.
    nullaryType := FactoryClosed1("System.Func`1, System.Private.CoreLib", typeof(int))
    nullary := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(nullaryType)
    nullaryParameters := nullary.ParameterTypes
    assert nullaryParameters != null
    assert nullaryParameters.Count == 0
    assert FactoryTypeName(nullary.ReturnType) == "int"
}

test "the Action arity table takes every argument as a parameter and returns void" {
    actionType := FactoryClosed2("System.Action`2, System.Private.CoreLib", typeof(int), typeof(string))
    signature := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(actionType)
    parameterTypes := signature.ParameterTypes
    assert parameterTypes != null
    assert parameterTypes.Count == 2
    assert FactoryTypeName(parameterTypes[0]) == "int"
    assert FactoryTypeName(signature.ReturnType) == "void"
}

test "a delegate outside the arity tables is read through Invoke" {
    // `Action` (non-generic) is NOT in the table — the table starts at `Action\`1` — so it goes
    // through `Invoke`, which has no parameters and returns void.
    actionType := FactoryRuntimeType("System.Action, System.Private.CoreLib")
    signature := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(actionType)
    parameterTypes := signature.ParameterTypes
    assert parameterTypes != null
    assert parameterTypes.Count == 0
    assert FactoryTypeName(signature.ReturnType) == "void"

    // A type with no `Invoke` at all answers the unknown signature rather than throwing.
    notADelegateType := FactoryRuntimeType("System.Uri, System.Private.Uri")
    notADelegate := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(notADelegateType)
    assert BuiltInTypes.IsUnknown(notADelegate.ReturnType)
}

test "an expression tree unwraps to its delegate, including through a by-ref shell" {
    funcIntInt := FactoryClosed2("System.Func`2, System.Private.CoreLib", typeof(int), typeof(int))
    expressionType := FactoryClosed1(
        "System.Linq.Expressions.Expression`1, System.Linq.Expressions", funcIntInt)
    unwrapped: Type = typeof(object)
    assert AnalyzerFunctionTypeFactory.TryGetExpressionTreeDelegateType(expressionType, out unwrapped)
    assert Object.Equals(unwrapped, funcIntInt)

    byRefExpression := expressionType.MakeByRefType()
    byRefUnwrapped: Type = typeof(object)
    assert AnalyzerFunctionTypeFactory.TryGetExpressionTreeDelegateType(byRefExpression, out byRefUnwrapped)
    assert Object.Equals(byRefUnwrapped, funcIntInt)

    // And the signature it produces is the DELEGATE's, not the expression's.
    signature := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(expressionType)
    parameterTypes := signature.ParameterTypes
    assert parameterTypes != null
    assert parameterTypes.Count == 1
    assert FactoryTypeName(signature.ReturnType) == "int"

    // A generic type that is not an expression tree answers false.
    notExpression: Type = typeof(object)
    listOfInt := FactoryClosed1("System.Collections.Generic.List`1, System.Private.CoreLib", typeof(int))
    assert !AnalyzerFunctionTypeFactory.TryGetExpressionTreeDelegateType(listOfInt, out notExpression)
    assert !AnalyzerFunctionTypeFactory.TryGetExpressionTreeDelegateType(typeof(int), out notExpression)
}

test "a reflection parameter's modifier is read off its by-ref direction" {
    tryParseTypes := new Type[](2)
    tryParseTypes[0] = typeof(string)
    tryParseTypes[1] = typeof(int).MakeByRefType()
    tryParse := typeof(int).GetMethod("TryParse", tryParseTypes)
    assert tryParse != null

    parameters := tryParse.GetParameters()
    assert AnalyzerFunctionTypeFactory.GetReflectionParameterModifier(parameters[0]) == ParameterModifier.None
    assert AnalyzerFunctionTypeFactory.GetReflectionParameterModifier(parameters[1]) == ParameterModifier.Out
}

test "only an async NON-generator is wrapped in the task family" {
    plain := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("f", false, false, BuiltInTypes.Int)
    assert FactoryTypeName(plain) == "int"

    generator := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("f", true, true, BuiltInTypes.Int)
    assert FactoryTypeName(generator) == "int"

    wrapped := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("f", true, false, BuiltInTypes.Int)
    assert FactoryTypeName(wrapped) == "ValueTask<int>"
}

test "main gets the Task family and everything else ValueTask, case-insensitively" {
    mainValue := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("main", true, false, BuiltInTypes.Int)
    assert FactoryTypeName(mainValue) == "Task<int>"

    upperMain := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("MAIN", true, false, BuiltInTypes.Int)
    assert FactoryTypeName(upperMain) == "Task<int>"

    other := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("other", true, false, BuiltInTypes.Int)
    assert FactoryTypeName(other) == "ValueTask<int>"

    // A void async is the UNIT task, not a wrapped void.
    mainVoid := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("main", true, false, BuiltInTypes.Void)
    assert FactoryTypeName(mainVoid) == "System.Threading.Tasks.Task"

    otherVoid := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("other", true, false, BuiltInTypes.Void)
    assert FactoryTypeName(otherVoid) == "System.Threading.Tasks.ValueTask"
}

test "an already task-like declared return type is left exactly as written" {
    unitTaskType := FactoryRuntimeType("System.Threading.Tasks.Task, System.Private.CoreLib")
    unitTask: TypeInfo = new ReflectionTypeInfo(unitTaskType)
    assert AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(unitTask)
    resolved := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("f", true, false, unitTask)
    assert Object.ReferenceEquals(resolved, unitTask)

    unitValueTaskType := FactoryRuntimeType("System.Threading.Tasks.ValueTask, System.Private.CoreLib")
    unitValueTask: TypeInfo = new ReflectionTypeInfo(unitValueTaskType)
    assert AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(unitValueTask)

    genericTaskType := FactoryClosed1("System.Threading.Tasks.Task`1, System.Private.CoreLib", typeof(int))
    genericTask: TypeInfo = new ReflectionTypeInfo(genericTaskType)
    result: TypeInfo = BuiltInTypes.Unknown
    assert AnalyzerFunctionTypeFactory.TryGetTaskLikeResultTypeInfo(genericTask, out result)
    assert FactoryTypeName(result) == "int"
    resolvedGeneric := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType("f", true, false, genericTask)
    assert Object.ReferenceEquals(resolvedGeneric, genericTask)

    // A plain type is neither.
    assert !AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(BuiltInTypes.Int)
    plainResult: TypeInfo = BuiltInTypes.Unknown
    assert !AnalyzerFunctionTypeFactory.TryGetTaskLikeResultTypeInfo(BuiltInTypes.Int, out plainResult)
    assert BuiltInTypes.IsUnknown(plainResult)
}

test "a declaration's signature carries its source identity and its resolved parameters" {
    factory := FactoryUnderTest()
    parameters := new List<Parameter>()
    parameters.Add(FactoryParameter("first", "int"))
    parameters.Add(FactoryParameter("second", "string"))
    declaration := FactoryDeclaration("Compute", parameters, "bool", Modifiers.None)

    signature := factory.CreateFromDeclaration(declaration, "Owner")
    assert signature.SourceName == "Compute"
    assert signature.SyntheticName == "Compute"
    assert signature.SourceContainingType == "Owner"
    assert signature.SourceParameterCount == 2
    assert !signature.SourceHasReceiverParameter
    assert !signature.HasParamsParameter
    assert FactoryRequiredCount(signature) == "2"

    names := signature.ParameterNames
    assert names != null
    assert names[0] == "first"
    assert names[1] == "second"

    types := signature.ParameterTypes
    assert types != null
    assert FactoryTypeName(types[0]) == "int"
    assert FactoryTypeName(types[1]) == "string"
    assert FactoryTypeName(signature.ReturnType) == "bool"

    // A null containing type is carried through as null rather than invented.
    free := factory.CreateFromDeclaration(declaration, null)
    assert free.SourceContainingType == null
}

test "a defaulted parameter lowers the required count and a params parameter is flagged" {
    factory := FactoryUnderTest()
    parameters := new List<Parameter>()
    parameters.Add(FactoryParameter("first", "int"))
    defaultedType: TypeReference = new SimpleTypeReference("string")
    defaultValue: Expression = new StringLiteralExpression("x", 1, 1)
    parameters.Add(
        new Parameter("second", defaultedType, defaultValue, false, ParameterModifier.None, null, 1, 1, false, null))
    declaration := FactoryDeclaration("Defaulted", parameters, "bool", Modifiers.None)
    signature := factory.CreateFromDeclaration(declaration, null)
    assert FactoryRequiredCount(signature) == "1"
    assert !signature.HasParamsParameter

    paramsElement: TypeReference = new SimpleTypeReference("string")
    paramsType: TypeReference = new ArrayTypeReference(paramsElement)
    spreadParameters := new List<Parameter>()
    spreadParameters.Add(FactoryParameter("first", "int"))
    spreadParameters.Add(
        new Parameter("rest", paramsType, null, false, ParameterModifier.Params, null, 1, 1, false, null))
    spread := FactoryDeclaration("Spread", spreadParameters, "bool", Modifiers.None)
    spreadSignature := factory.CreateFromDeclaration(spread, null)
    assert spreadSignature.HasParamsParameter
    assert FactoryRequiredCount(spreadSignature) == "1"
}

test "a function's own type parameters shadow the names its references use" {
    factory := FactoryUnderTest()
    parameters := new List<Parameter>()
    parameters.Add(FactoryParameter("value", "T"))
    typeParameters := new List<TypeParameter>()
    typeParameters.Add(new TypeParameter("T"))
    declaration := new FunctionDeclaration(
        "Identity", parameters, new SimpleTypeReference("T"), null, null, typeParameters, null,
        Modifiers.None, new List<AttributeNode>(), false, null, false, false, 1, 1)

    signature := factory.CreateFromDeclaration(declaration, null)
    types := signature.ParameterTypes
    assert types != null
    assert FactoryTypeName(types[0]) == "T"
    assert FactoryTypeName(signature.ReturnType) == "T"

    carried := signature.TypeParameters
    assert carried != null
    assert carried.Count == 1
    assert carried[0].Name == "T"
}

test "an omitted return type reads as void, and the source reference is carried unresolved" {
    factory := FactoryUnderTest()
    parameters := new List<Parameter>()
    declaration := FactoryDeclaration("NoReturn", parameters, null, Modifiers.None)
    signature := factory.CreateFromDeclaration(declaration, null)
    assert FactoryTypeName(signature.ReturnType) == "void"
    assert signature.SourceReturnType == null

    typed := FactoryDeclaration("Typed", parameters, "int", Modifiers.None)
    typedSignature := factory.CreateFromDeclaration(typed, null)
    assert typedSignature.SourceReturnType != null
}

test "an async declaration's SIGNATURE return type is the wrapped one" {
    factory := FactoryUnderTest()
    parameters := new List<Parameter>()
    declaration := FactoryDeclaration("Wait", parameters, "int", Modifiers.Async)
    signature := factory.CreateFromDeclaration(declaration, null)
    assert FactoryTypeName(signature.ReturnType) == "ValueTask<int>"

    mainDeclaration := FactoryDeclaration("main", parameters, "int", Modifiers.Async)
    mainSignature := factory.CreateFromDeclaration(mainDeclaration, null)
    assert FactoryTypeName(mainSignature.ReturnType) == "Task<int>"
}

test "a declared member's signature reads its arrays and its required count off the member" {
    factory := FactoryUnderTest()
    parameterNames := new string[](2)
    parameterNames[0] = "left"
    parameterNames[1] = "right"
    parameterTypes := new TypeReference[](2)
    intReference: TypeReference = new SimpleTypeReference("int")
    stringReference: TypeReference = new SimpleTypeReference("string")
    parameterTypes[0] = intReference
    parameterTypes[1] = stringReference
    parameterModifiers := new ParameterModifier[](2)
    parameterModifiers[0] = ParameterModifier.None
    parameterModifiers[1] = ParameterModifier.None

    boolReference: TypeReference = new SimpleTypeReference("bool")
    noTypeParameters := new TypeParameter[](0)
    noConstraints := new GenericConstraint[](0)
    member := new DeclaredMemberInfo(
        "Combine", "Owner", DeclaredMemberKind.Function, "function", null, false, false, false, true,
        2, parameterNames, parameterTypes, parameterModifiers, 2, false, false,
        boolReference, 0, noTypeParameters, noConstraints,
        0, false, false, false, false, "", false, false, 7, 3)

    signature := factory.CreateFromDeclaredMember(member, null, null)
    assert signature.SourceName == "Combine"
    assert signature.SourceContainingType == "Owner"
    assert signature.SourceLine == 7
    assert signature.SourceColumn == 3
    assert FactoryRequiredCount(signature) == "2"
    types := signature.ParameterTypes
    assert types != null
    assert FactoryTypeName(types[0]) == "int"
    assert FactoryTypeName(types[1]) == "string"
    assert FactoryTypeName(signature.ReturnType) == "bool"

    // A supplied substitution binds a name the member's references use.
    substitution := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    substitution["int"] = BuiltInTypes.Double
    substituted := factory.CreateFromDeclaredMember(member, substitution, null)
    substitutedTypes := substituted.ParameterTypes
    assert substitutedTypes != null
    assert FactoryTypeName(substitutedTypes[0]) == "double"
}
