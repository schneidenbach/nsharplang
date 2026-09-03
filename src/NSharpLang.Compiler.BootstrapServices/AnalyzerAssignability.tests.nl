namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the analyzer's assignability decision.
//
// Every member behind these was `private` in Analyzer.cs, so nothing named them: the language's
// central semantic question was pinned only through end-to-end diagnostics. These contracts go at
// the ORDER — which is the specification — and at the two properties a reader cannot infer from any
// single arm: that a bare method reference is NOT assignable to `object`, and that the user-defined
// conversion search is guarded against a cycle rather than merely unlikely to meet one.

// Generic definitions are resolved by CANONICAL IDENTITY rather than through `typeof`: the columnar
// `typeof` surface does not carry most closed generic collection or delegate types, and the
// resolved instances are the identical runtime ones.
func AssignabilityRuntimeType(canonicalName: string): Type {
    resolved := Type.GetType(canonicalName)
    if resolved == null {
        throw new InvalidOperationException("The runtime does not define '" + canonicalName + "'.")
    }

    return resolved
}

func AssignabilityClosed(canonicalName: string, argument: Type): Type {
    definition := AssignabilityRuntimeType(canonicalName)
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

func AssignabilityDefault(): AnalyzerAssignability {
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
    resolver := new AnalyzerTypeResolver(
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
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    return new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
}

func AssignabilityLambda(parameters: List<TypeInfo>, returnType: TypeInfo?): FunctionTypeInfo {
    modifiers := new List<ParameterModifier>()
    index := 0
    while index < parameters.Count {
        modifiers.Add(ParameterModifier.None)
        index = index + 1
    }

    signature := new FunctionTypeInfo()
    signature.ParameterTypes = parameters
    signature.ParameterModifiers = modifiers
    signature.ReturnType = returnType
    return signature
}

func AssignabilityMethodGroup(parameters: List<TypeInfo>, returnType: TypeInfo?): FunctionTypeInfo {
    signature := AssignabilityLambda(parameters, returnType)
    signature.SourceName = "Named"
    signature.SyntheticName = "Named"
    return signature
}

func AssignabilityOne(first: TypeInfo): List<TypeInfo> {
    values := new List<TypeInfo>()
    values.Add(first)
    return values
}

func AssignabilityTwo(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    values := new List<TypeInfo>()
    values.Add(first)
    values.Add(second)
    return values
}

func AssignabilityNone(): List<TypeInfo> {
    return new List<TypeInfo>()
}

test "identity, null, never and the unknown kinds all answer before anything structural" {
    assignability := AssignabilityDefault()
    sameInstance: TypeInfo = new SimpleTypeInfo("Widget")
    assert assignability.IsAssignable(sameInstance, sameInstance)

    nullableIntTarget: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    assert assignability.IsAssignable(nullableIntTarget, BuiltInTypes.Null)
    assert assignability.IsAssignable(BuiltInTypes.String, BuiltInTypes.Null)
    assert !assignability.IsAssignable(BuiltInTypes.Int, BuiltInTypes.Null)

    // `never` is the bottom type: assignable to everything, including a value type.
    assert assignability.IsAssignable(BuiltInTypes.Int, BuiltInTypes.Never)
    assert assignability.IsAssignable(BuiltInTypes.String, BuiltInTypes.Never)

    // All three unknown KINDS suppress, in both directions.
    assert assignability.IsAssignable(BuiltInTypes.Int, BuiltInTypes.Unknown)
    assert assignability.IsAssignable(BuiltInTypes.Unknown, BuiltInTypes.Int)
    assert assignability.IsAssignable(BuiltInTypes.Int, BuiltInTypes.InferenceHole)
    assert assignability.IsAssignable(BuiltInTypes.Int, BuiltInTypes.DeferredExternal)
}

test "by-ref is symmetric and TOTAL — one by-ref side refuses everything else" {
    assignability := AssignabilityDefault()
    intRef: TypeInfo = new ByRefTypeInfo(BuiltInTypes.Int)
    otherIntRef: TypeInfo = new ByRefTypeInfo(BuiltInTypes.Int)
    stringRef: TypeInfo = new ByRefTypeInfo(BuiltInTypes.String)

    assert assignability.IsAssignable(intRef, otherIntRef)
    assert !assignability.IsAssignable(intRef, stringRef)

    // A by-ref on ONE side refuses, and it refuses before the `object` arm below could accept.
    assert !assignability.IsAssignable(intRef, BuiltInTypes.Int)
    assert !assignability.IsAssignable(BuiltInTypes.Int, intRef)
    assert !assignability.IsAssignable(BuiltInTypes.Object, intRef)
}

test "a target union needs ONE arm, a source union needs ALL of them" {
    assignability := AssignabilityDefault()
    intOrString: TypeInfo = new AnonymousUnionTypeInfo(AssignabilityTwo(BuiltInTypes.Int, BuiltInTypes.String))
    intOrBool: TypeInfo = new AnonymousUnionTypeInfo(AssignabilityTwo(BuiltInTypes.Int, BuiltInTypes.Bool))
    onlyInt: TypeInfo = new AnonymousUnionTypeInfo(AssignabilityOne(BuiltInTypes.Int))

    assert assignability.IsAssignable(intOrString, BuiltInTypes.Int)
    assert assignability.IsAssignable(intOrString, BuiltInTypes.String)
    assert !assignability.IsAssignable(intOrString, BuiltInTypes.Bool)

    // Union to union: every source arm must find a home.
    assert assignability.IsAssignable(intOrString, onlyInt)
    assert !assignability.IsAssignable(onlyInt, intOrString)
    assert !assignability.IsAssignable(intOrString, intOrBool)

    // A source union against a NON-union target: every arm must be assignable.
    assert !assignability.IsAssignable(BuiltInTypes.Int, intOrString)
    assert assignability.IsAssignable(BuiltInTypes.Int, onlyInt)
    assert assignability.IsAssignable(BuiltInTypes.Object, intOrString)
}

test "a bare method reference is NOT a value, so it is not assignable even to object" {
    assignability := AssignabilityDefault()
    methodGroup: TypeInfo = AssignabilityMethodGroup(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)
    lambda: TypeInfo = AssignabilityLambda(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)

    // THE EXCEPTION THAT ORDERS THE WHOLE DISPATCH: `object` accepts everything except this.
    assert !assignability.IsAssignable(BuiltInTypes.Object, methodGroup)
    assert assignability.IsAssignable(BuiltInTypes.Object, lambda)
    assert assignability.IsAssignable(BuiltInTypes.Object, BuiltInTypes.Int)
    assert assignability.IsAssignable(BuiltInTypes.Object, BuiltInTypes.String)

    // A callable-reference TARGET refuses an ordinary value.
    assert !assignability.IsAssignable(methodGroup, BuiltInTypes.Int)

    // A method group binds to a matching Func and refuses a mismatched one.
    funcDefinitionType := AssignabilityRuntimeType("System.Func`2, System.Private.CoreLib")
    funcDefinition: TypeInfo = new ReflectionTypeInfo(funcDefinitionType)
    funcArguments := AssignabilityTwo(BuiltInTypes.Int, BuiltInTypes.Int)
    funcIntInt: TypeInfo = new GenericTypeInfo("Func", funcArguments, funcDefinition)
    assert assignability.IsAssignable(funcIntInt, methodGroup)
}

test "nullable widening walks the inner types in both shapes" {
    assignability := AssignabilityDefault()
    nullableInt: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    nullableLong: TypeInfo = new NullableTypeInfo(BuiltInTypes.Long)
    nullableString: TypeInfo = new NullableTypeInfo(BuiltInTypes.String)

    assert assignability.IsAssignable(nullableInt, BuiltInTypes.Int)
    assert assignability.IsAssignable(nullableLong, nullableInt)
    assert !assignability.IsAssignable(nullableInt, nullableLong)
    assert !assignability.IsAssignable(nullableString, nullableInt)

    // Widening is one-directional: a nullable source does not fit a non-nullable target.
    assert !assignability.IsAssignable(BuiltInTypes.Int, nullableInt)
}

test "the known-generic relation is covariant only where the interface is read-only" {
    assignability := AssignabilityDefault()
    listDefinitionType := AssignabilityRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib")
    enumerableDefinitionType := AssignabilityRuntimeType("System.Collections.Generic.IEnumerable`1, System.Private.CoreLib")
    collectionDefinitionType := AssignabilityRuntimeType("System.Collections.Generic.ICollection`1, System.Private.CoreLib")
    listDefinition: TypeInfo = new ReflectionTypeInfo(listDefinitionType)
    enumerableDefinition: TypeInfo = new ReflectionTypeInfo(enumerableDefinitionType)
    collectionDefinition: TypeInfo = new ReflectionTypeInfo(collectionDefinitionType)

    listOfString: TypeInfo = new GenericTypeInfo("List", AssignabilityOne(BuiltInTypes.String), listDefinition)
    enumerableOfString: TypeInfo = new GenericTypeInfo(
        "IEnumerable",
        AssignabilityOne(BuiltInTypes.String),
        enumerableDefinition
    )
    enumerableOfObject: TypeInfo = new GenericTypeInfo(
        "IEnumerable",
        AssignabilityOne(BuiltInTypes.Object),
        enumerableDefinition
    )
    collectionOfObject: TypeInfo = new GenericTypeInfo(
        "ICollection",
        AssignabilityOne(BuiltInTypes.Object),
        collectionDefinition
    )

    assert assignability.IsAssignable(enumerableOfString, listOfString)
    // COVARIANT: IEnumerable<object> accepts IEnumerable<string>.
    assert assignability.IsAssignable(enumerableOfObject, enumerableOfString)
    // INVARIANT: ICollection<object> must NOT accept a string collection — a caller could add.
    assert !assignability.IsAssignable(collectionOfObject, listOfString)

    // The definition is NOMINAL: a same-named instantiation with no runtime definition is not it.
    homemade: TypeInfo = new GenericTypeInfo("List", AssignabilityOne(BuiltInTypes.String))
    assert !assignability.IsAssignable(enumerableOfString, homemade)
}

test "an array widens to a span only for the real span definitions and an identical element" {
    assignability := AssignabilityDefault()
    spanDefinition := AssignabilityRuntimeType("System.Span`1, System.Private.CoreLib")
    spanDefinitionInfo: TypeInfo = new ReflectionTypeInfo(spanDefinition)
    spanIntArguments := AssignabilityOne(BuiltInTypes.Int)
    spanStringArguments := AssignabilityOne(BuiltInTypes.String)
    spanOfInt: TypeInfo = new GenericTypeInfo("Span", spanIntArguments, spanDefinitionInfo)
    spanOfString: TypeInfo = new GenericTypeInfo("Span", spanStringArguments, spanDefinitionInfo)
    intArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    assert assignability.IsAssignable(spanOfInt, intArray)
    // A span is NOT variant.
    assert !assignability.IsAssignable(spanOfString, intArray)
}

test "a collection expression takes the target's element type, and an array is not a collection" {
    assignability := AssignabilityDefault()
    listDefinitionType := AssignabilityRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib")
    listDefinition: TypeInfo = new ReflectionTypeInfo(listDefinitionType)
    listOfLong: TypeInfo = new GenericTypeInfo("List", AssignabilityOne(BuiltInTypes.Long), listDefinition)
    listOfString: TypeInfo = new GenericTypeInfo("List", AssignabilityOne(BuiltInTypes.String), listDefinition)
    intArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    // int[] → List<long> holds because int is assignable to long ELEMENT-WISE.
    assert assignability.IsAssignable(listOfLong, intArray)
    assert !assignability.IsAssignable(listOfString, intArray)
}

test "implicit numeric conversions widen and do not narrow" {
    assignability := AssignabilityDefault()
    assert assignability.IsAssignable(BuiltInTypes.Long, BuiltInTypes.Int)
    assert assignability.IsAssignable(BuiltInTypes.Double, BuiltInTypes.Int)
    assert !assignability.IsAssignable(BuiltInTypes.Int, BuiltInTypes.Long)
    assert !assignability.IsAssignable(BuiltInTypes.Int, BuiltInTypes.Double)
}

test "the delegate signature score ranks exact above convertible above open above unknown" {
    assignability := AssignabilityDefault()
    exact := 0
    assert assignability.TryGetDelegateSignatureConversionScore(BuiltInTypes.Int, BuiltInTypes.Int, out exact)
    assert exact == 8

    unknownScore := 0
    assert assignability.TryGetDelegateSignatureConversionScore(
        BuiltInTypes.Int,
        BuiltInTypes.Unknown,
        out unknownScore
    )
    assert unknownScore == 1

    parameterScore := 0
    listDefinitionType := AssignabilityRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib")
    listParameters := listDefinitionType.GetGenericArguments()
    openParameter: TypeInfo = new ReflectionTypeInfo(listParameters[0])
    assert assignability.TryGetDelegateSignatureConversionScore(
        BuiltInTypes.String,
        openParameter,
        out parameterScore
    )
    assert parameterScore == 2

    referenceScore := 0
    objectTarget: TypeInfo = new ReflectionTypeInfo(typeof(object))
    stringSource: TypeInfo = new ReflectionTypeInfo(typeof(string))
    assert assignability.TryGetDelegateSignatureConversionScore(
        objectTarget,
        stringSource,
        out referenceScore
    )
    assert referenceScore == 4

    // A value type cannot cross a delegate REFERENCE conversion at all.
    refused := 0
    assert !assignability.TryGetDelegateSignatureConversionScore(
        BuiltInTypes.Long,
        BuiltInTypes.Int,
        out refused
    )
    assert refused == 0
}

test "a method-group match needs equal arity and equal ref-ness, and params erases to none" {
    assignability := AssignabilityDefault()
    source := AssignabilityMethodGroup(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)
    target := AssignabilityLambda(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)
    score := 0
    assert assignability.TryGetRuntimeDelegateMethodGroupMatchScore(source, target, out score)
    assert score == 16
    assert assignability.IsFunctionTypeAssignableToRuntimeDelegateMethodGroup(source, target)

    // Arity mismatch.
    wrongArity := AssignabilityLambda(AssignabilityTwo(BuiltInTypes.Int, BuiltInTypes.Int), BuiltInTypes.Int)
    wrongScore := 0
    assert !assignability.TryGetRuntimeDelegateMethodGroupMatchScore(source, wrongArity, out wrongScore)

    // `params` is a call-site convenience and is NOT part of a delegate's signature.
    paramsSource := AssignabilityMethodGroup(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)
    paramsModifiers := new List<ParameterModifier>()
    paramsModifiers.Add(ParameterModifier.Params)
    paramsSource.ParameterModifiers = paramsModifiers
    paramsScore := 0
    assert assignability.TryGetRuntimeDelegateMethodGroupMatchScore(paramsSource, target, out paramsScore)

    // `ref` is load-bearing and is not erased.
    refSource := AssignabilityMethodGroup(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)
    refModifiers := new List<ParameterModifier>()
    refModifiers.Add(ParameterModifier.Ref)
    refSource.ParameterModifiers = refModifiers
    refScore := 0
    assert !assignability.TryGetRuntimeDelegateMethodGroupMatchScore(refSource, target, out refScore)

    // An UNKNOWN source parameter contributes nothing and is not a mismatch.
    inferring := AssignabilityMethodGroup(AssignabilityOne(BuiltInTypes.Unknown), BuiltInTypes.Int)
    inferringScore := 0
    assert assignability.TryGetRuntimeDelegateMethodGroupMatchScore(inferring, target, out inferringScore)
    assert inferringScore == 8
}

test "a source union assignable to object composes with the union arms rather than short-circuiting" {
    assignability := AssignabilityDefault()
    emptyParameters := AssignabilityNone()
    methodGroupArm: TypeInfo = AssignabilityMethodGroup(emptyParameters, BuiltInTypes.Int)
    unionArms := AssignabilityTwo(BuiltInTypes.Int, methodGroupArm)
    intOrMethodGroup: TypeInfo = new AnonymousUnionTypeInfo(unionArms)

    // The union arm walks EVERY arm, and the method-group arm refuses `object`, so the whole union
    // does. This is what proves the union arms run BEFORE the `object` shortcut.
    assert !assignability.IsAssignable(BuiltInTypes.Object, intOrMethodGroup)
}

test "the re-entrancy guard answers a repeated question rather than recursing" {
    guard := new AnalyzerImplicitConversionGuard()
    source: TypeInfo = new SimpleTypeInfo("Money")
    target: TypeInfo = new SimpleTypeInfo("Cents")

    assert guard.TryEnter(source, target)
    // The SAME pair is refused while it is active...
    assert !guard.TryEnter(source, target)
    // ...and so is a STRUCTURALLY equal one, because the scan uses the same virtual equality a set
    // of pairs would.
    equalSource: TypeInfo = new SimpleTypeInfo("Money")
    equalTarget: TypeInfo = new SimpleTypeInfo("Cents")
    assert !guard.TryEnter(equalSource, equalTarget)
    // ...but the reversed pair is a different question.
    assert guard.TryEnter(target, source)

    guard.Exit(source, target)
    assert guard.TryEnter(source, target)

    guard.Clear()
    assert guard.TryEnter(source, target)
    assert guard.TryEnter(target, source)
}

test "a lambda's function type matches a Func by argument order and an Action by count" {
    assignability := AssignabilityDefault()
    funcDefinitionType := AssignabilityRuntimeType("System.Func`2, System.Private.CoreLib")
    actionDefinitionType := AssignabilityRuntimeType("System.Action`1, System.Private.CoreLib")
    funcDefinition: TypeInfo = new ReflectionTypeInfo(funcDefinitionType)
    actionDefinition: TypeInfo = new ReflectionTypeInfo(actionDefinitionType)

    funcIntToInt: TypeInfo = new GenericTypeInfo(
        "Func",
        AssignabilityTwo(BuiltInTypes.Int, BuiltInTypes.Int),
        funcDefinition
    )
    funcIntToString: TypeInfo = new GenericTypeInfo(
        "Func",
        AssignabilityTwo(BuiltInTypes.Int, BuiltInTypes.String),
        funcDefinition
    )
    actionOfInt: TypeInfo = new GenericTypeInfo(
        "Action",
        AssignabilityOne(BuiltInTypes.Int),
        actionDefinition
    )

    lambda: TypeInfo = AssignabilityLambda(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)
    assert assignability.IsAssignable(funcIntToInt, lambda)
    assert !assignability.IsAssignable(funcIntToString, lambda)

    voidLambda: TypeInfo = AssignabilityLambda(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Void)
    assert assignability.IsAssignable(actionOfInt, voidLambda)

    wrongArity: TypeInfo = AssignabilityLambda(
        AssignabilityTwo(BuiltInTypes.Int, BuiltInTypes.Int),
        BuiltInTypes.Int
    )
    assert !assignability.IsAssignable(funcIntToInt, wrongArity)

    // An UNKNOWN lambda parameter is not pre-judged.
    inferring: TypeInfo = AssignabilityLambda(AssignabilityOne(BuiltInTypes.Unknown), BuiltInTypes.Int)
    assert assignability.IsAssignable(funcIntToInt, inferring)
}

test "function-type structural comparison compares parameters and the return, not the display form" {
    assignability := AssignabilityDefault()
    source: TypeInfo = AssignabilityLambda(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)
    same: TypeInfo = AssignabilityLambda(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.Int)
    otherReturn: TypeInfo = AssignabilityLambda(AssignabilityOne(BuiltInTypes.Int), BuiltInTypes.String)
    otherArity: TypeInfo = AssignabilityLambda(AssignabilityNone(), BuiltInTypes.Int)

    assert assignability.IsAssignable(same, source)
    assert !assignability.IsAssignable(otherReturn, source)
    assert !assignability.IsAssignable(otherArity, source)
}

test "nominal subtyping walks reflection hierarchies and refuses identity" {
    assignability := AssignabilityDefault()
    stringType: TypeInfo = new ReflectionTypeInfo(typeof(string))
    objectType: TypeInfo = new ReflectionTypeInfo(typeof(object))

    assert assignability.IsSubtypeOf(stringType, objectType)
    // A type is NOT a strict subtype of itself.
    assert !assignability.IsSubtypeOf(stringType, stringType)
    assert !assignability.IsSubtypeOf(objectType, stringType)

    // A source with no declared bases and no reflection identity answers false rather than throwing.
    // THE CLASS-TARGET CASE STAYS FALSE ON PURPOSE: the interface bridge below deliberately does not
    // widen to class targets, so boxing never enters this predicate.
    assert !assignability.IsSubtypeOf(BuiltInTypes.Int, BuiltInTypes.Object)
}

test "chip: a BUILT-IN spelling reaches its generic INTERFACES, which made every constraint on a primitive a false report" {
    // THE DEFECT. `string` and `int` arrive as `SimpleTypeInfo`, which is neither a class, a struct,
    // a record, an interface nor a reflected type — so `IsSubtypeOf` fell through every arm to
    // `false`, and `where T: IComparable<T>` (published in BOTH `website/docs/functions.md` and
    // `types.md`) answered "`string` does not implement `IComparable<string>`" for every argument.
    //
    // IT WAS NEVER ABOUT SELF-REFERENCE: a constraint that does not mention `T` at all
    // (`where T: IComparable<string>`) failed identically. It was the BOUND TYPE — a user class and
    // `List<int>` both passed all along, because their interface lists are declared where the walk
    // could already see them.
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        assignability := AssignabilityWithWellKnownTypes(context)
        core := context.LoadFromAssemblyName("System.Runtime")

        stringType := core.GetType("System.String")
        charType := core.GetType("System.Char")
        intType := core.GetType("System.Int32")
        comparableDefinition := core.GetType("System.IComparable`1")
        equatableDefinition := core.GetType("System.IEquatable`1")
        enumerableDefinition := core.GetType("System.Collections.Generic.IEnumerable`1")

        comparableOfString: TypeInfo = new ReflectionTypeInfo(AssignabilityCloseOver(comparableDefinition, stringType))
        equatableOfString: TypeInfo = new ReflectionTypeInfo(AssignabilityCloseOver(equatableDefinition, stringType))
        enumerableOfChar: TypeInfo = new ReflectionTypeInfo(AssignabilityCloseOver(enumerableDefinition, charType))
        enumerableOfString: TypeInfo = new ReflectionTypeInfo(AssignabilityCloseOver(enumerableDefinition, stringType))
        comparableOfInt: TypeInfo = new ReflectionTypeInfo(AssignabilityCloseOver(comparableDefinition, intType))

        // The four that were false reports, all of them real CLR facts.
        assert assignability.IsSubtypeOf(BuiltInTypes.String, comparableOfString)
        assert assignability.IsSubtypeOf(BuiltInTypes.String, equatableOfString)
        assert assignability.IsSubtypeOf(BuiltInTypes.String, enumerableOfChar)
        assert assignability.IsSubtypeOf(BuiltInTypes.Int, comparableOfInt)

        // AND THE TRUE NEGATIVE SURVIVES, which is what makes the acceptance mean anything:
        // `string` is `IEnumerable<char>`, NOT `IEnumerable<string>`.
        assert !assignability.IsSubtypeOf(BuiltInTypes.String, enumerableOfString)
    } finally {
        scan.Dispose()
    }
}

test "chip: the interface bridge refuses a CLASS target, so boxing stays out of nominal subtyping" {
    // The bridge is acceptance-only AND interface-only. Both rows below are true of `int` in the
    // CLR and stay false here: widening to class targets would flip the `IsSubtypeOf(int, object)`
    // row pinned above, and would put boxing into a predicate several callers read as nominal.
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        assignability := AssignabilityWithWellKnownTypes(context)
        core := context.LoadFromAssemblyName("System.Runtime")

        objectTarget: TypeInfo = new ReflectionTypeInfo(core.GetType("System.Object"))
        valueTypeTarget: TypeInfo = new ReflectionTypeInfo(core.GetType("System.ValueType"))

        assert !assignability.IsSubtypeOf(BuiltInTypes.Int, objectTarget)
        assert !assignability.IsSubtypeOf(BuiltInTypes.Int, valueTypeTarget)
    } finally {
        scan.Dispose()
    }
}

// Close a generic DEFINITION over one argument, both of them already CLR types from the scan's own
// load context — the identity that matters, since a type from a different context would not match.
func AssignabilityCloseOver(definition: Type, argument: Type): Type {
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

// The bridge's own harness, with the well-known-type bag the production analyzer carries: the
// generic-target side of the cross-representation arm converts through the bag, so the bagless
// default cannot exercise it.
func AssignabilityWithWellKnownTypes(loadContext: MetadataLoadContext): AnalyzerAssignability {
    core := loadContext.LoadFromAssemblyName("System.Runtime")
    wellKnown := new AnalyzerWellKnownTypes(loadContext, core)
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
    resolver := new AnalyzerTypeResolver(
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
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, wellKnown)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, wellKnown)
    guard := new AnalyzerImplicitConversionGuard()
    return new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
}

test "the cross-representation bridge takes the CLR's answer when one side is reflected" {
    // Bagless half: a source-spelled array against the reflected Array base — the exact shape the
    // non-generic BCL overloads put in front of the finalise walk.
    assignability := AssignabilityDefault()
    arrayBase: TypeInfo = new ReflectionTypeInfo(AssignabilityRuntimeType("System.Array"))
    stringArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.String)
    assert assignability.IsAssignable(arrayBase, stringArray)

    // The bridge only ACCEPTS — the reverse question still refuses.
    assert !assignability.IsAssignable(stringArray, arrayBase)
}

test "the bridge answers a reflected comparer against the source-spelled interface it implements" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        assignability := AssignabilityWithWellKnownTypes(context)
        core := context.LoadFromAssemblyName("System.Runtime")

        comparerDefinitionType := core.GetType("System.Collections.Generic.IComparer`1")
        assert comparerDefinitionType != null
        stringComparerType := core.GetType("System.StringComparer")
        assert stringComparerType != null

        comparerDefinition: TypeInfo = new ReflectionTypeInfo(comparerDefinitionType)
        comparerOfString: TypeInfo = new GenericTypeInfo(
            "IComparer",
            AssignabilityOne(BuiltInTypes.String),
            comparerDefinition
        )
        stringComparer: TypeInfo = new ReflectionTypeInfo(stringComparerType)

        // StringComparer implements IComparer<string>: the NL402/NL202 shape this bridge exists for.
        assert assignability.IsAssignable(comparerOfString, stringComparer)

        // The instantiation is exact: the same comparer does NOT satisfy IComparer<int>.
        comparerOfInt: TypeInfo = new GenericTypeInfo(
            "IComparer",
            AssignabilityOne(BuiltInTypes.Int),
            comparerDefinition
        )
        assert !assignability.IsAssignable(comparerOfInt, stringComparer)
    } finally {
        scan.Dispose()
    }
}
