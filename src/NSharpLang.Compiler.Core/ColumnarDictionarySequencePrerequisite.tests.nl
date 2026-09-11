namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

func DictionarySequenceClosedTwo(definition: Type, first: Type, second: Type): Type {
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return definition.MakeGenericType(arguments)
}

func DictionarySequencePairType(first: Type, second: Type): Type {
    definition := Type.GetType("System.Collections.Generic.KeyValuePair`2")
    if definition == null {
        throw new InvalidOperationException("System.Collections.Generic.KeyValuePair`2 was not found.")
    }
    return DictionarySequenceClosedTwo(definition, first, second)
}

func DictionarySequenceOneType(argument: Type): Type[] {
    arguments := new Type[](1)
    arguments[0] = argument
    return arguments
}

func DictionarySequenceGenericType(fullName: string, arguments: Type[]): Type {
    definition := Type.GetType(fullName)
    if definition == null {
        throw new InvalidOperationException("Required generic definition was not found: " + fullName)
    }
    return definition.MakeGenericType(arguments)
}

func DictionarySequenceRequiredConstructor(value: ConstructorInfo?): ConstructorInfo {
    if value == null {
        throw new InvalidOperationException("The Dictionary copy constructor was not found.")
    }
    return value
}

// The open IDictionary<K,V> copy constructor, found in the test that wants it: the construction
// planner no longer carries a per-collection finder, because it selects every closed generic
// constructor by ordinary overload resolution.
func DictionarySequenceOpenCopyConstructor(definition: Type): ConstructorInfo? {
    if !definition.get_IsGenericTypeDefinition() {
        return null
    }
    definitionArguments := definition.GetGenericArguments()
    if definitionArguments.Length != 2 {
        return null
    }

    // A namesake built with Reflection.Emit answers nothing before it is created, and asking is a
    // NotSupportedException rather than an empty list.
    constructors := new ConstructorInfo[](0)
    try {
        constructors = definition.GetConstructors()
    } catch ex: NotSupportedException {
        return null
    }
    index := 0
    while index < constructors.Length {
        parameters := constructors[index].GetParameters()
        if parameters.Length == 1 {
            parameterType := parameters[0].get_ParameterType()
            if parameterType.get_IsGenericType() && !parameterType.get_IsGenericTypeDefinition() && parameterType.GetGenericTypeDefinition() == typeof(IDictionary<int, int>).GetGenericTypeDefinition() {
                parameterArguments := parameterType.GetGenericArguments()
                if parameterArguments.Length == 2 && parameterArguments[0] == definitionArguments[0] && parameterArguments[1] == definitionArguments[1] {
                    return constructors[index]
                }
            }
        }
        index += 1
    }
    return null
}

func DictionarySequenceConstructionPlan(argumentType: Type): ColumnarCodePlan {
    tree := ConstructionNewTree(
        "Dictionary<string,string>",
        ConstructionOneText("source"),
        ConstructionOneKind(ColumnarExpressionNodeKind.IdentifierExpression())
    )
    ConstructionStampScope(tree, "")
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "source", 0, argumentType)
    return ConstructionPlan(tree, bindings)
}

func DictionarySequenceConstructionRejected(argumentType: Type) {
    tree := ConstructionNewTree(
        "Dictionary<string,string>",
        ConstructionOneText("source"),
        ConstructionOneKind(ColumnarExpressionNodeKind.IdentifierExpression())
    )
    ConstructionStampScope(tree, "")
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "source", 0, argumentType)
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _plan := ConstructionRejected(tree, bindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "dictionary sequence prerequisite selects only the exact IDictionary copy constructor" {
    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    interfaceDefinition := typeof(IDictionary<int, int>).GetGenericTypeDefinition()
    constructor := DictionarySequenceRequiredConstructor(
        DictionarySequenceOpenCopyConstructor(dictionaryDefinition)
    )
    parameters := constructor.GetParameters()
    assert parameters.Length == 1
    parameterType := parameters[0].get_ParameterType()
    assert parameterType.GetGenericTypeDefinition() == interfaceDefinition
    definitionArguments := dictionaryDefinition.GetGenericArguments()
    parameterArguments := parameterType.GetGenericArguments()
    assert parameterArguments.Length == 2
    assert parameterArguments[0] == definitionArguments[0]
    assert parameterArguments[1] == definitionArguments[1]

    // A namesake with no constructors of its own has no copy constructor to find.
    foreign := TypeOfCreateBuilder(
        "System.Collections.Generic.Dictionary",
        "DictionarySequence.Foreign",
        2
    )
    assert DictionarySequenceOpenCopyConstructor(foreign) == null

    exactInterface := typeof(IDictionary<string, string>)
    exactPlan := DictionarySequenceConstructionPlan(exactInterface)
    assert exactPlan.ResultType == typeof(Dictionary<string, string>)
    assert exactPlan.OperationCount == 2
    assert exactPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert exactPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
    assert exactPlan.ConstructorCount == 1
    assert exactPlan.ConstructorDeclaringTypes[0] == typeof(Dictionary<string, string>)
    assert exactPlan.ConstructorParameterTypes[0].Length == 1
    assert exactPlan.ConstructorParameterTypes[0][0] == exactInterface

    concretePlan := DictionarySequenceConstructionPlan(typeof(Dictionary<string, string>))
    assert concretePlan.ConstructorParameterTypes[0][0] == exactInterface

    comparerPlan := DictionarySequenceConstructionPlan(typeof(IEqualityComparer<string>))
    assert comparerPlan.ConstructorParameterTypes[0][0] == typeof(IEqualityComparer<string>)

    capacityPlan := DictionarySequenceConstructionPlan(typeof(int))
    assert capacityPlan.ConstructorParameterTypes[0][0] == typeof(int)
}

test "dictionary sequence prerequisite retains ambiguity and unrelated copy-source rejections" {
    // A key or value type the target does not name converts to NO dictionary constructor parameter and
    // stays a rejection.
    DictionarySequenceConstructionRejected(typeof(IDictionary<int, string>))
    DictionarySequenceConstructionRejected(typeof(IDictionary<string, int>))

    // Ordinary constructor resolution reaches `Dictionary<K,V>(IEnumerable<KeyValuePair<K,V>>)`, so a
    // read-only dictionary and a bare key/value sequence now construct exactly as they do in C#. The
    // allowlist these rows once pinned could only see the `IDictionary<K,V>` copy constructor.
    stringPair := DictionarySequencePairType(typeof(string), typeof(string))
    enumerableArguments := new Type[](1)
    enumerableArguments[0] = stringPair
    enumerablePair := DictionarySequenceGenericType(
        "System.Collections.Generic.IEnumerable`1",
        enumerableArguments
    )
    sequencePlan := DictionarySequenceConstructionPlan(enumerablePair)
    assert sequencePlan.ConstructorParameterTypes[0].Length == 1
    assert sequencePlan.ConstructorParameterTypes[0][0] == enumerablePair
    readOnlyPlan := DictionarySequenceConstructionPlan(typeof(IReadOnlyDictionary<string, string>))
    assert readOnlyPlan.ConstructorParameterTypes[0].Length == 1
    assert readOnlyPlan.ConstructorParameterTypes[0][0] == enumerablePair

    tree := ConstructionNewTree(
        "Dictionary<string,string>",
        ConstructionOneText("null"),
        ConstructionOneKind(ColumnarExpressionNodeKind.NullLiteralExpression())
    )
    ConstructionStampScope(tree, "")
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _plan := ConstructionRejected(
        tree,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

// THE BODY-LOCAL SEQUENCE IS THE SAME SEQUENCE A SIGNATURE SPELLS. This prerequisite once admitted
// only the exact `IEnumerable<KeyValuePair<string, string>>` shape the Analyzer source needed,
// because the type-parameter walk had no general answer for anything else; it now applies the
// ordinary collection-element policy, so any sequence a signature could name a body local can name
// too. What the policy still refuses is an element this compilation cannot yield.
test "dictionary sequence prerequisite resolves a body-local sequence by the ordinary element policy" {
    resolution := CanonicalResolverBaselineResolution()
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    pair := DictionarySequencePairType(typeof(string), typeof(string))
    enumerableArguments := new Type[](1)
    enumerableArguments[0] = pair
    expected := DictionarySequenceGenericType(
        "System.Collections.Generic.IEnumerable`1",
        enumerableArguments
    )

    resolved := typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
        "IEnumerable<KeyValuePair<string,string>>",
        typeParameters,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    ), "dictionary-sequence body-local assertion 1"
    assert resolved == expected, "dictionary-sequence body-local assertion 2"

    resolved = typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
        "System.Collections.Generic.IEnumerable<System.Collections.Generic.KeyValuePair<string,string>>",
        typeParameters,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    ), "dictionary-sequence body-local assertion 3"
    assert resolved == expected, "dictionary-sequence body-local assertion 4"

    resolved = typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
        "IEnumerable<KeyValuePair<string,int>>",
        typeParameters,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    ), "dictionary-sequence body-local assertion 5"
    assert resolved == DictionarySequenceGenericType(
        "System.Collections.Generic.IEnumerable`1",
        DictionarySequenceOneType(DictionarySequencePairType(typeof(string), typeof(int)))
    ), "dictionary-sequence body-local assertion 6"

    resolved = typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
        "IEnumerable<KeyValuePair<int,string>>",
        typeParameters,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    ), "dictionary-sequence body-local assertion 7"
    assert resolved == DictionarySequenceGenericType(
        "System.Collections.Generic.IEnumerable`1",
        DictionarySequenceOneType(DictionarySequencePairType(typeof(int), typeof(string)))
    ), "dictionary-sequence body-local assertion 8"

    resolved = typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
        "IEnumerable<string>",
        typeParameters,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    ), "dictionary-sequence body-local assertion 9"
    assert resolved == DictionarySequenceGenericType(
        "System.Collections.Generic.IEnumerable`1",
        DictionarySequenceOneType(typeof(string))
    ), "dictionary-sequence body-local assertion 10"

    // AND THE TWO WALKS AGREE, which is the whole point of the change: the body-local answer and the
    // signature answer for one spelling are now the same type, not two different policies.
    ordinaryResolved := typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "IEnumerable<string>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out ordinaryResolved
    ), "the ordinary walk resolves the same sequence spelling"
    assert ordinaryResolved == resolved, "both walks answer one type for one spelling"
}

test "dictionary sequence prerequisite selects exact acquisition movement current and disposal handles" {
    pair := DictionarySequencePairType(typeof(string), typeof(string))
    sequenceArguments := new Type[](1)
    sequenceArguments[0] = pair
    sequence := DictionarySequenceGenericType(
        "System.Collections.Generic.IEnumerable`1",
        sequenceArguments
    )
    enumerator := DictionarySequenceGenericType(
        "System.Collections.Generic.IEnumerator`1",
        sequenceArguments
    )
    noArguments := new Type[](0)

    acquisition := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        sequence,
        "GetEnumerator",
        noArguments,
        false
    )
    assert acquisition.IsSelected
    assert acquisition.LookupType == sequence
    assert acquisition.DeclaringType == sequence
    assert acquisition.ReturnType == enumerator
    assert acquisition.UsesCallVirtual

    movement := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        enumerator,
        "MoveNext",
        noArguments,
        false
    )
    assert movement.IsSelected
    assert movement.LookupType == enumerator
    assert movement.DeclaringType.FullName == "System.Collections.IEnumerator"
    assert movement.ReturnType == typeof(bool)
    assert movement.UsesCallVirtual

    current := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        enumerator,
        "get_Current",
        noArguments,
        false
    )
    assert current.IsSelected
    assert current.DeclaringType == enumerator
    assert current.ReturnType == pair
    assert current.UsesCallVirtual

    disposal := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        typeof(IDisposable),
        "Dispose",
        noArguments,
        false
    )
    assert disposal.IsSelected
    assert disposal.DeclaringType == typeof(IDisposable)
    assert disposal.ReturnType == ColumnarTypeOfPlanner.RequiredVoidType()
    assert disposal.UsesCallVirtual

    readOnlyDictionary := typeof(IReadOnlyDictionary<string, string>)
    assert ColumnarReferenceConversionFacts.TryEmitReferenceConversion(
        readOnlyDictionary,
        sequence
    )

    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        enumerator,
        "Reset",
        noArguments,
        false
    ).IsNotFound

    intPair := DictionarySequencePairType(typeof(string), typeof(int))
    intSequenceArguments := new Type[](1)
    intSequenceArguments[0] = intPair
    intEnumerator := DictionarySequenceGenericType(
        "System.Collections.Generic.IEnumerator`1",
        intSequenceArguments
    )
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        intEnumerator,
        "MoveNext",
        noArguments,
        false
    ).IsNotFound
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        enumerator,
        "MoveNext",
        noArguments,
        true
    ).IsNotFound
}
