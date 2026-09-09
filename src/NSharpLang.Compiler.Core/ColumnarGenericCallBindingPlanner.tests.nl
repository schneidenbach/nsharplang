namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler.Columnar


// Generic sibling inference mutates its caller-owned slots as it walks the declared shape. These
// controls use actual Reflection.Emit parameters because their identity and builder-bound behavior
// differs from ordinary runtime generic parameters.
func GenericCallBindingParameters(name: string, count: int): Type[] {
    owner := TypeOfCreateBuilder(
        name,
        "ColumnarGenericCallBinding." + name,
        count
    )
    parameters := owner.GetGenericArguments()
    if parameters.Length != count {
        throw new InvalidOperationException("The generic-call binding fixture did not expose every parameter.")
    }
    return parameters
}

func GenericCallBindingClose1(definition: Type, first: Type): Type {
    arguments := new Type[](1)
    arguments[0] = first
    return definition.MakeGenericType(arguments)
}

func GenericCallBindingClose2(definition: Type, first: Type, second: Type): Type {
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return definition.MakeGenericType(arguments)
}

class GenericCallBindingReturnOutcome {
    Result: bool
    Substituted: Type?
    Error: Exception?

    constructor(initial: Type?) {
        Result = false
        Substituted = initial
        Error = null
    }
}

func GenericCallBindingSubstituteReturn(
    typeParams: Type[],
    binding: Type[],
    declaredReturn: Type,
    initial: Type?
): GenericCallBindingReturnOutcome {
    outcome := new GenericCallBindingReturnOutcome(initial)
    substituted := initial
    try {
        outcome.Result = ColumnarGenericCallBindingPlanner.TrySubstituteReturnType(
            typeParams,
            binding,
            declaredReturn,
            out substituted
        )
    } catch error: Exception {
        outcome.Error = error
    }
    outcome.Substituted = substituted
    return outcome
}

test "generic call binding identifies declared parameters by identity and accepts equal repeated actual types" {
    parameters := GenericCallBindingParameters("Identity", 1)
    declaredAlias: Type = new TypeDelegator(parameters[0])
    assert !Object.ReferenceEquals(declaredAlias, parameters[0])
    assert declaredAlias == parameters[0]

    foreignBinding := new Type[](1)
    assert !ColumnarGenericCallBindingPlanner.TryUnifyTypeParam(
        parameters,
        foreignBinding,
        declaredAlias,
        typeof(int)
    )
    assert foreignBinding[0] == null

    firstActual: Type = new TypeDelegator(typeof(int))
    repeatedActual: Type = new TypeDelegator(typeof(int))
    assert !Object.ReferenceEquals(firstActual, repeatedActual)
    assert firstActual == repeatedActual

    binding := new Type[](1)
    assert ColumnarGenericCallBindingPlanner.TryUnifyTypeParam(
        parameters,
        binding,
        parameters[0],
        firstActual
    )
    assert Object.ReferenceEquals(binding[0], firstActual)
    assert ColumnarGenericCallBindingPlanner.TryUnifyTypeParam(
        parameters,
        binding,
        parameters[0],
        repeatedActual
    )
    assert Object.ReferenceEquals(binding[0], firstActual)
}

test "generic call binding retains earlier inference across array and recursive container failures" {
    parameters := GenericCallBindingParameters("Recursive", 1)
    arrayBinding := new Type[](1)
    declaredArray := parameters[0].MakeArrayType()
    assert ColumnarGenericCallBindingPlanner.TryUnifyGenericCallArgument(
        parameters,
        arrayBinding,
        declaredArray,
        typeof(int[])
    )
    assert arrayBinding[0] == typeof(int)

    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    declaredNested := GenericCallBindingClose2(
        dictionaryDefinition,
        typeof(string),
        GenericCallBindingClose1(listDefinition, parameters[0])
    )
    actualNested := GenericCallBindingClose2(
        dictionaryDefinition,
        typeof(string),
        typeof(List<int>)
    )
    nestedBinding := new Type[](1)
    assert ColumnarGenericCallBindingPlanner.TryUnifyGenericContainer(
        parameters,
        nestedBinding,
        declaredNested,
        actualNested
    )
    assert nestedBinding[0] == typeof(int)

    declaredRepeated := GenericCallBindingClose2(
        dictionaryDefinition,
        parameters[0],
        parameters[0]
    )
    actualConflict := typeof(Dictionary<int, string>)
    retainedBinding := new Type[](1)
    assert !ColumnarGenericCallBindingPlanner.TryUnifyGenericContainer(
        parameters,
        retainedBinding,
        declaredRepeated,
        actualConflict
    )
    assert retainedBinding[0] == typeof(int)
}

test "generic call binding admits direct source shapes but declines a composed builder-bound argument" {
    parameters := GenericCallBindingParameters("SourceBoundary", 1)
    sourceDefinition := TypeOfCreateBuilder(
        "GenericCallBindingSource",
        "ColumnarGenericCallBinding.SourceBoundary",
        1
    )
    directBinding := new Type[](1)
    assert ColumnarGenericCallBindingPlanner.TryUnifyTypeParam(
        parameters,
        directBinding,
        parameters[0],
        sourceDefinition
    )
    assert Object.ReferenceEquals(directBinding[0], sourceDefinition)

    sourceParameter := sourceDefinition.GetGenericArguments()[0]
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    composed := GenericCallBindingClose1(listDefinition, sourceParameter)
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(composed)
    composedBinding := new Type[](1)
    assert !ColumnarGenericCallBindingPlanner.TryUnifyTypeParam(
        parameters,
        composedBinding,
        parameters[0],
        composed
    )
    assert composedBinding[0] == null
}

test "generic call binding dictionary classifiers accept only their exact generic definitions" {
    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    sortedDictionaryDefinition := typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
    readOnlyDictionaryDefinition := typeof(IReadOnlyDictionary<int, int>).GetGenericTypeDefinition()
    mutableInterfaceDefinition := typeof(IDictionary<int, int>).GetGenericTypeDefinition()
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()

    assert ColumnarGenericCallBindingPlanner.IsDictionaryLikeCollectionDefinition(dictionaryDefinition)
    assert ColumnarGenericCallBindingPlanner.IsDictionaryLikeCollectionDefinition(sortedDictionaryDefinition)
    assert !ColumnarGenericCallBindingPlanner.IsDictionaryLikeCollectionDefinition(readOnlyDictionaryDefinition)
    assert !ColumnarGenericCallBindingPlanner.IsDictionaryLikeCollectionDefinition(mutableInterfaceDefinition)
    assert !ColumnarGenericCallBindingPlanner.IsDictionaryLikeCollectionDefinition(typeof(Dictionary<int, string>))

    assert ColumnarGenericCallBindingPlanner.IsReadOnlyDictionaryCollectionDefinition(readOnlyDictionaryDefinition)
    assert !ColumnarGenericCallBindingPlanner.IsReadOnlyDictionaryCollectionDefinition(dictionaryDefinition)
    assert !ColumnarGenericCallBindingPlanner.IsReadOnlyDictionaryCollectionDefinition(sortedDictionaryDefinition)
    assert !ColumnarGenericCallBindingPlanner.IsReadOnlyDictionaryCollectionDefinition(mutableInterfaceDefinition)

    assert ColumnarGenericCallBindingPlanner.IsAnyDictionaryCollectionDefinition(dictionaryDefinition)
    assert ColumnarGenericCallBindingPlanner.IsAnyDictionaryCollectionDefinition(sortedDictionaryDefinition)
    assert ColumnarGenericCallBindingPlanner.IsAnyDictionaryCollectionDefinition(readOnlyDictionaryDefinition)
    assert !ColumnarGenericCallBindingPlanner.IsAnyDictionaryCollectionDefinition(mutableInterfaceDefinition)
    assert !ColumnarGenericCallBindingPlanner.IsAnyDictionaryCollectionDefinition(listDefinition)
}

test "generic sibling return substitution keeps direct null slots and raw reflection failures distinct" {
    parameters := GenericCallBindingParameters("ReturnSlots", 1)
    binding := new Type[](1)
    binding[0] = typeof(int)

    direct := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        parameters[0],
        typeof(object)
    )
    assert direct.Result
    assert direct.Error == null
    assert direct.Substituted == typeof(int)

    array := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        parameters[0].MakeArrayType(),
        typeof(object)
    )
    assert array.Result
    assert array.Error == null
    assert array.Substituted == typeof(int[])

    unbound := new Type[](1)
    nullDirect := GenericCallBindingSubstituteReturn(
        parameters,
        unbound,
        parameters[0],
        typeof(object)
    )
    assert nullDirect.Result
    assert nullDirect.Error == null
    assert nullDirect.Substituted == null

    nullArray := GenericCallBindingSubstituteReturn(
        parameters,
        unbound,
        parameters[0].MakeArrayType(),
        typeof(object)
    )
    assert !nullArray.Result
    assert EntryPointRealizationControlsRequiredErrorType(nullArray.Error) == typeof(NullReferenceException)
    assert nullArray.Substituted == null

    trace := new List<int>()
    noConstraints := new Type[](0)
    throwingReturn := GenericConstraintReflectionProbeType(
        "GenericCallBindingReturnFailure",
        typeof(int),
        trace,
        1,
        false,
        1,
        "T",
        0,
        0,
        0,
        noConstraints,
        0
    )
    rawFailure := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        throwingReturn,
        typeof(object)
    )
    assert !rawFailure.Result
    assert EntryPointRealizationControlsRequiredErrorType(rawFailure.Error) == typeof(NotSupportedException)
    assert rawFailure.Substituted == null
    assert GenericConstraintProbeTraceText(trace) == "11"
}

test "generic sibling return substitution recloses source and admitted BCL collection shapes" {
    parameters := GenericCallBindingParameters("ReturnRecursion", 1)
    binding := new Type[](1)
    binding[0] = typeof(int)

    sourceDefinition := TypeOfCreateBuilder(
        "GenericCallBindingReturnSource",
        "ColumnarGenericCallBinding.ReturnRecursion",
        1
    )
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    declaredSource := GenericCallBindingClose1(
        sourceDefinition,
        GenericCallBindingClose1(listDefinition, parameters[0])
    )
    sourceOutcome := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        declaredSource,
        typeof(object)
    )
    assert sourceOutcome.Result
    assert sourceOutcome.Error == null
    assert sourceOutcome.Substituted != null
    sourceSubstituted: Type = sourceOutcome.Substituted
    sourceResultDefinition := sourceSubstituted.GetGenericTypeDefinition()
    assert Object.ReferenceEquals(sourceResultDefinition, sourceDefinition)
    sourceArguments := sourceSubstituted.GetGenericArguments()
    assert sourceArguments.Length == 1
    sourceList: Type = sourceArguments[0]
    sourceListDefinition := sourceList.GetGenericTypeDefinition()
    assert Object.ReferenceEquals(sourceListDefinition, listDefinition)
    sourceListArguments := sourceList.GetGenericArguments()
    assert sourceListArguments.Length == 1
    assert sourceListArguments[0] == typeof(int)

    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    sortedDictionaryDefinition := typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
    readOnlyDictionaryDefinition := typeof(IReadOnlyDictionary<int, int>).GetGenericTypeDefinition()
    hashSetDefinition := typeof(HashSet<int>).GetGenericTypeDefinition()
    enumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()

    listOutcome := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        GenericCallBindingClose1(listDefinition, parameters[0]),
        typeof(object)
    )
    assert listOutcome.Result
    assert listOutcome.Error == null
    assert listOutcome.Substituted == typeof(List<int>)

    dictionaryOutcome := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        GenericCallBindingClose2(dictionaryDefinition, typeof(string), parameters[0]),
        typeof(object)
    )
    assert dictionaryOutcome.Result
    assert dictionaryOutcome.Error == null
    assert dictionaryOutcome.Substituted == typeof(Dictionary<string, int>)

    sortedDictionaryOutcome := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        GenericCallBindingClose2(sortedDictionaryDefinition, typeof(string), parameters[0]),
        typeof(object)
    )
    assert sortedDictionaryOutcome.Result
    assert sortedDictionaryOutcome.Error == null
    assert sortedDictionaryOutcome.Substituted == typeof(SortedDictionary<string, int>)

    readOnlyDictionaryOutcome := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        GenericCallBindingClose2(readOnlyDictionaryDefinition, typeof(string), parameters[0]),
        typeof(object)
    )
    assert readOnlyDictionaryOutcome.Result
    assert readOnlyDictionaryOutcome.Error == null
    assert readOnlyDictionaryOutcome.Substituted == typeof(IReadOnlyDictionary<string, int>)

    hashSetOutcome := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        GenericCallBindingClose1(hashSetDefinition, parameters[0]),
        typeof(object)
    )
    assert hashSetOutcome.Result
    assert hashSetOutcome.Error == null
    assert hashSetOutcome.Substituted == typeof(HashSet<int>)

    enumerableOutcome := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        GenericCallBindingClose1(enumerableDefinition, parameters[0]),
        typeof(object)
    )
    assert enumerableOutcome.Result
    assert enumerableOutcome.Error == null
    assert enumerableOutcome.Substituted == typeof(IEnumerable<int>)

    queueDefinition := typeof(Queue<int>).GetGenericTypeDefinition()
    declaredQueue := GenericCallBindingClose1(queueDefinition, parameters[0])
    generalSubstitution: Type = null
    assert ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(
        parameters,
        binding,
        declaredQueue,
        out generalSubstitution
    )
    assert generalSubstitution == typeof(Queue<int>)

    queueOutcome := GenericCallBindingSubstituteReturn(
        parameters,
        binding,
        declaredQueue,
        typeof(object)
    )
    assert !queueOutcome.Result
    assert queueOutcome.Error == null
    assert queueOutcome.Substituted == null
}
