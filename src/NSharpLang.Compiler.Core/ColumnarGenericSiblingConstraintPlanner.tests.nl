namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Text
import NSharpLang.Compiler.Columnar


// These controls own the constraint facts used when an emitted generic sibling is closed. Reflection.Emit
// accepts a violating MethodBuilder.MakeGenericMethod call, so this planner must decline before the call
// reaches metadata. The native declaration corpus already proves `where` metadata and constrained dispatch;
// this file pins the unbaked sibling-call decisions that cannot be represented as invalid source declarations.
func SiblingConstraintRegistry(
    definitions: ColumnarStructDef[]
): Dictionary<string, ColumnarStructDef> {
    registry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
    index := 0
    while index < definitions.Length {
        definition := definitions[index]
        registry[definition.DeclaredTypeName] = definition
        index = index + 1
    }
    return registry
}

func SiblingConstraintParameters(name: string, count: int): Type[] {
    owner := TypeOfCreateBuilder(
        name,
        "ColumnarGenericSiblingConstraint." + name,
        count
    )
    parameters := owner.GetGenericArguments()
    if parameters.Length != count {
        throw new InvalidOperationException("The sibling-constraint fixture did not expose every parameter.")
    }
    return parameters
}

func SiblingConstraintOneType(value: Type): Type[] {
    result := new Type[](1)
    result[0] = value
    return result
}

func SiblingConstraintOneInterfaceRow(value: Type): Type[][] {
    result := new Type[][](1)
    result[0] = SiblingConstraintOneType(value)
    return result
}

func SiblingConstraintNoBases(): Type[] {
    return new Type[](0)
}

func SiblingConstraintNoInterfaces(): Type[][] {
    return new Type[][](0)
}

func SiblingConstraintNoSpecials(): int[] {
    return new int[](0)
}

func SiblingConstraintNullableInt(): Type {
    definition := Type.GetType("System.Nullable`1")
    if definition == null {
        throw new InvalidOperationException("System.Nullable`1 was not loadable.")
    }
    arguments := new Type[](1)
    arguments[0] = typeof(int)
    return definition.MakeGenericType(arguments)
}

func SiblingConstraintComparableDefinition(): Type {
    definition := Type.GetType("System.IComparable`1")
    if definition == null {
        throw new InvalidOperationException("System.IComparable`1 was not loadable.")
    }
    return definition
}

class SiblingConstraintAnyOutcome {
    Result: bool
    ErrorMessage: string?

    constructor() {
        Result = false
        ErrorMessage = null
    }
}

// The public helper is directly typed at the production IEnumerable<ColumnarStructDef> boundary. Tests use
// reflection only to feed it the existing wrapped enumerator fixture so they can inspect disposal after the
// early return and an exception during the next traversal step.
class SiblingConstraintAnyInvoker {
    static func Run(
        interfaces: IEnumerable<ColumnarStructDef>,
        target: TypeBuilder,
        outcome: SiblingConstraintAnyOutcome
    ): bool {
        try {
            outcome.Result = ColumnarGenericConstraintPlanner.AnyInterfaceEqualsOrExtends(
                interfaces,
                target
            )
        } catch error: InvalidOperationException {
            outcome.ErrorMessage = error.Message
        }
        return true
    }
}

func SiblingConstraintInvokeAny(
    interfaces: object,
    target: TypeBuilder,
    outcome: SiblingConstraintAnyOutcome
): bool {
    method := typeof(SiblingConstraintAnyInvoker).GetMethod("Run")
    if method == null {
        throw new InvalidOperationException("The sibling-constraint any-interface invoker was not found.")
    }
    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, interfaces)
    ExecutorSetObject(arguments, 1, target)
    ExecutorSetObject(arguments, 2, outcome)
    result := TypeOfRequiredInvocation(method, null, arguments)
    return Convert.ToBoolean(result)
}

class SiblingConstraintSubstitutionOutcome {
    Result: bool
    Substituted: Type?
    Error: Exception?

    constructor(initial: Type?) {
        Result = false
        Substituted = initial
        Error = null
    }
}

func SiblingConstraintSubstitute(
    typeParams: Type[],
    binding: Type[],
    sourceType: Type,
    initial: Type?
): SiblingConstraintSubstitutionOutcome {
    outcome := new SiblingConstraintSubstitutionOutcome(initial)
    substituted := initial
    try {
        outcome.Result = ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(
            typeParams,
            binding,
            sourceType,
            out substituted
        )
    } catch error: Exception {
        outcome.Error = error
    }
    outcome.Substituted = substituted
    return outcome
}

test "generic sibling constraint validation reads its columns before a blank-row bound or registry" {
    // `boundArgs` controls the loop length. A blank row never reads its bound, its inference slot, or the
    // source registry; this is the real short-column behavior from a partially populated generic method.
    blankBound := new Type[](1)
    assert ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        null,
        null,
        null,
        null,
        null,
        new Type[](0),
        null
    )

    assert ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        new Type[](0),
        SiblingConstraintNoSpecials(),
        SiblingConstraintNoBases(),
        SiblingConstraintNoInterfaces(),
        null,
        blankBound,
        null
    )

    // The class and struct bits keep their independent CLR meanings at the closing call site.
    classRow := new int[](1)
    classRow[0] = 1
    // Every row is selected before the bound is inspected. A missing interface column therefore
    // remains a raw null failure instead of returning false for Int32's class-constraint mismatch.
    assert throws NullReferenceException {
        ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
            new Type[](0),
            classRow,
            new Type[](1),
            null,
            null,
            SiblingConstraintOneType(typeof(int)),
            null
        )
    }
    assert !ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        new Type[](0),
        classRow,
        SiblingConstraintNoBases(),
        SiblingConstraintNoInterfaces(),
        null,
        SiblingConstraintOneType(typeof(int)),
        null
    )
    assert ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        new Type[](0),
        classRow,
        SiblingConstraintNoBases(),
        SiblingConstraintNoInterfaces(),
        null,
        SiblingConstraintOneType(typeof(string)),
        null
    )

    structRow := new int[](1)
    structRow[0] = 2
    assert !ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        new Type[](0),
        structRow,
        SiblingConstraintNoBases(),
        SiblingConstraintNoInterfaces(),
        null,
        SiblingConstraintOneType(typeof(string)),
        null
    )
    assert !ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        new Type[](0),
        structRow,
        SiblingConstraintNoBases(),
        SiblingConstraintNoInterfaces(),
        null,
        SiblingConstraintOneType(SiblingConstraintNullableInt()),
        null
    )
    assert ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        new Type[](0),
        structRow,
        SiblingConstraintNoBases(),
        SiblingConstraintNoInterfaces(),
        null,
        SiblingConstraintOneType(typeof(int)),
        null
    )
}

test "generic sibling validation preserves the bound reflection failure phase before constraint or registry work" {
    trace := new List<int>()
    failingBound := GenericConstraintReflectionProbeType(
        "SiblingConstraintBoundFailure",
        typeof(int),
        trace,
        1,
        false,
        3,
        "T",
        0,
        0,
        0,
        new Type[](0),
        0
    )
    classRow := new int[](1)
    classRow[0] = 1
    assert throws InvalidOperationException {
        ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
            new Type[](0),
            classRow,
            SiblingConstraintNoBases(),
            SiblingConstraintNoInterfaces(),
            null,
            SiblingConstraintOneType(failingBound),
            null
        )
    }
    assert GenericConstraintProbeTraceText(trace) == "11"
}

test "generic sibling new constraint uses real source default-constructor state and keeps runtime registry access lazy" {
    // Value and runtime-reference paths do not enumerate a source registry.
    assert ColumnarGenericConstraintPlanner.HasPublicParameterlessConstructorForConstraint(
        typeof(int),
        null
    )
    assert ColumnarGenericConstraintPlanner.HasPublicParameterlessConstructorForConstraint(
        typeof(StringBuilder),
        null
    )
    assert !ColumnarGenericConstraintPlanner.HasPublicParameterlessConstructorForConstraint(
        typeof(string),
        null
    )

    source := SourceCallDefinition("SiblingConstraintDefaultCtor", true)
    source.DefaultCtor = source.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )
    definitions := new ColumnarStructDef[](1)
    definitions[0] = source
    registry := SiblingConstraintRegistry(definitions)
    assert source.DefaultCtor != null
    assert ColumnarGenericConstraintPlanner.HasPublicParameterlessConstructorForConstraint(
        source.Builder,
        registry
    )

    newRow := new int[](1)
    newRow[0] = 4
    assert ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        new Type[](0),
        newRow,
        SiblingConstraintNoBases(),
        SiblingConstraintNoInterfaces(),
        null,
        SiblingConstraintOneType(source.Builder),
        registry
    )

    noConstructor := SourceCallDefinition("SiblingConstraintNoDefaultCtor", true)
    noConstructorDefinitions := new ColumnarStructDef[](1)
    noConstructorDefinitions[0] = noConstructor
    noConstructorRegistry := SiblingConstraintRegistry(noConstructorDefinitions)
    assert noConstructor.DefaultCtor == null
    // A SOURCE argument is answered from its own declaration table and never by reflection. This one
    // declares neither a synthesized default constructor nor a parameterless one of its own, so the
    // `new()` constraint is UNSATISFIED — it does not reach `TypeBuilder.GetConstructor`, which
    // answers an unbaked builder by throwing "The invoked member is not supported before the type is
    // created" and crashed the emission of any program whose `new()` argument was a source type that
    // declared its own constructor.
    assert !ColumnarGenericConstraintPlanner.HasPublicParameterlessConstructorForConstraint(
        noConstructor.Builder,
        noConstructorRegistry
    )

    // A source argument that declares its OWN parameterless constructor satisfies the constraint,
    // which is the shape the reflection fall-through could never answer.
    declaredCtor := SourceCallDefinition("SiblingConstraintDeclaredParameterlessCtor", true)
    declaredCtor.DefineUserConstructor(new Type[](0), new int[](0), new string[](0))
    declaredCtorDefinitions := new ColumnarStructDef[](1)
    declaredCtorDefinitions[0] = declaredCtor
    assert declaredCtor.DefaultCtor == null
    assert ColumnarGenericConstraintPlanner.HasPublicParameterlessConstructorForConstraint(
        declaredCtor.Builder,
        SiblingConstraintRegistry(declaredCtorDefinitions)
    )
}

test "generic sibling base constraints retain runtime, sibling-parameter, and unbaked-bound boundaries" {
    assert ColumnarGenericConstraintPlanner.BoundSatisfiesBaseConstraint(
        new Type[](0),
        SiblingConstraintOneType(typeof(ArgumentException)),
        typeof(ArgumentException),
        typeof(Exception)
    )
    assert !ColumnarGenericConstraintPlanner.BoundSatisfiesBaseConstraint(
        new Type[](0),
        SiblingConstraintOneType(typeof(Exception)),
        typeof(Exception),
        typeof(ArgumentException)
    )

    parameters := SiblingConstraintParameters("BaseSibling", 2)
    boundArgs := new Type[](2)
    boundArgs[0] = typeof(ArgumentException)
    boundArgs[1] = typeof(Exception)
    assert ColumnarGenericConstraintPlanner.BoundSatisfiesBaseConstraint(
        parameters,
        boundArgs,
        boundArgs[0],
        parameters[1]
    )
    boundArgs[0] = typeof(Exception)
    boundArgs[1] = typeof(ArgumentException)
    assert !ColumnarGenericConstraintPlanner.BoundSatisfiesBaseConstraint(
        parameters,
        boundArgs,
        boundArgs[0],
        parameters[1]
    )

    foreign := SiblingConstraintParameters("BaseForeign", 1)[0]
    assert !ColumnarGenericConstraintPlanner.BoundSatisfiesBaseConstraint(
        parameters,
        boundArgs,
        boundArgs[0],
        foreign
    )

    // A source base rejects before reading an otherwise invalid bound. A runtime base sees an unbaked bound
    // as unverifiable rather than accepting it through Object assignability.
    sourceBase := TypeOfCreateBuilder(
        "SiblingConstraintSourceBase",
        "ColumnarGenericSiblingConstraint.SourceBase",
        0
    )
    nullBound: Type = null
    assert !ColumnarGenericConstraintPlanner.BoundSatisfiesBaseConstraint(
        new Type[](0),
        new Type[](0),
        nullBound,
        sourceBase
    )
    assert !ColumnarGenericConstraintPlanner.BoundSatisfiesBaseConstraint(
        new Type[](0),
        new Type[](0),
        sourceBase,
        typeof(object)
    )
}

test "generic sibling substitution closes recursive arrays byrefs and generic arguments while preserving failure slots" {
    parameters := SiblingConstraintParameters("Substitution", 2)
    binding := new Type[](2)
    binding[0] = typeof(int)
    binding[1] = typeof(string)

    direct := SiblingConstraintSubstitute(parameters, binding, parameters[0], typeof(object))
    assert direct.Result
    assert direct.Error == null
    assert direct.Substituted == typeof(int)

    array := SiblingConstraintSubstitute(
        parameters,
        binding,
        parameters[0].MakeArrayType(),
        typeof(object)
    )
    assert array.Result
    assert array.Error == null
    assert array.Substituted == typeof(int[])

    builderByRef := parameters[1].MakeByRefType()
    // Reflection.Emit's SymbolType reports both answers. The historical source checks IsSZArray first,
    // so this builder-derived byref deliberately closes as an SZ array.
    assert builderByRef.get_IsSZArray()
    assert builderByRef.get_IsByRef()
    byRef := SiblingConstraintSubstitute(
        parameters,
        binding,
        builderByRef,
        typeof(object)
    )
    assert byRef.Result
    assert byRef.Error == null
    assert byRef.Substituted == typeof(string[])

    // A runtime managed reference is not that SymbolType shape, so it reaches the actual by-ref arm.
    runtimeByRef := SiblingConstraintSubstitute(
        parameters,
        binding,
        typeof(string).MakeByRefType(),
        typeof(object)
    )
    assert runtimeByRef.Result
    assert runtimeByRef.Error == null
    assert runtimeByRef.Substituted == typeof(string).MakeByRefType()

    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    listArguments := new Type[](1)
    listArguments[0] = parameters[0].MakeArrayType()
    nestedList := listDefinition.MakeGenericType(listArguments)
    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    dictionaryArguments := new Type[](2)
    dictionaryArguments[0] = parameters[1]
    dictionaryArguments[1] = nestedList
    nested := dictionaryDefinition.MakeGenericType(dictionaryArguments)
    recursive := SiblingConstraintSubstitute(parameters, binding, nested, typeof(object))
    assert recursive.Result
    assert recursive.Error == null
    assert recursive.Substituted != null
    assert recursive.Substituted.GetGenericTypeDefinition() == dictionaryDefinition
    recursiveArguments := recursive.Substituted.GetGenericArguments()
    assert recursiveArguments[0] == typeof(string)
    assert recursiveArguments[1].GetGenericTypeDefinition() == listDefinition
    assert recursiveArguments[1].GetGenericArguments()[0] == typeof(int[])

    unbound := new Type[](2)
    failed := SiblingConstraintSubstitute(parameters, unbound, parameters[0], typeof(object))
    assert !failed.Result
    assert failed.Error == null
    assert failed.Substituted == null

    foreign := SiblingConstraintParameters("SubstitutionForeign", 1)[0]
    foreignFailed := SiblingConstraintSubstitute(parameters, binding, foreign, typeof(object))
    assert !foreignFailed.Result
    assert foreignFailed.Error == null
    assert foreignFailed.Substituted == null

    openDefinition := typeof(List<int>).GetGenericTypeDefinition()
    openFailed := SiblingConstraintSubstitute(parameters, binding, openDefinition, typeof(object))
    assert !openFailed.Result
    assert openFailed.Error == null
    assert openFailed.Substituted == null
}

test "generic sibling validation closes an inferred interface and declines before source lookup when inference is absent" {
    parameters := SiblingConstraintParameters("ClosedInterface", 1)
    comparableDefinition := SiblingConstraintComparableDefinition()
    interfaceArguments := new Type[](1)
    interfaceArguments[0] = parameters[0]
    inferredInterface := comparableDefinition.MakeGenericType(interfaceArguments)
    binding := new Type[](1)
    binding[0] = typeof(int)
    assert ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        parameters,
        new int[](1),
        new Type[](1),
        SiblingConstraintOneInterfaceRow(inferredInterface),
        binding,
        SiblingConstraintOneType(typeof(int)),
        null
    )

    wrongBinding := new Type[](1)
    wrongBinding[0] = typeof(string)
    assert !ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        parameters,
        new int[](1),
        new Type[](1),
        SiblingConstraintOneInterfaceRow(inferredInterface),
        wrongBinding,
        SiblingConstraintOneType(typeof(int)),
        null
    )

    missingBinding := new Type[](1)
    assert !ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        parameters,
        new int[](1),
        new Type[](1),
        SiblingConstraintOneInterfaceRow(inferredInterface),
        missingBinding,
        SiblingConstraintOneType(typeof(int)),
        null
    )
}

test "generic sibling interface constraints use source direct metadata and inherited source interfaces" {
    target := SourceCallInterfaceDefinition("SiblingConstraintTarget")
    derived := SourceCallInterfaceDefinition("SiblingConstraintDerived")
    derived.InterfaceBases.Add(target)
    implementer := SourceCallDefinition("SiblingConstraintImplementer", true)
    implementer.ImplementedInterfaceTypes.Add(typeof(IDisposable))
    implementer.ImplementedInterfaces.Add(derived)
    definitions := new ColumnarStructDef[](3)
    definitions[0] = target
    definitions[1] = derived
    definitions[2] = implementer
    registry := SiblingConstraintRegistry(definitions)

    assert ColumnarGenericConstraintPlanner.BoundSatisfiesInterfaceConstraint(
        typeof(int),
        typeof(IComparable),
        null
    )
    assert !ColumnarGenericConstraintPlanner.BoundSatisfiesInterfaceConstraint(
        typeof(int),
        typeof(IDisposable),
        null
    )
    assert !ColumnarGenericConstraintPlanner.BoundSatisfiesInterfaceConstraint(
        typeof(int),
        typeof(object),
        null
    )
    assert ColumnarGenericConstraintPlanner.BoundSatisfiesInterfaceConstraint(
        implementer.Builder,
        typeof(IDisposable),
        registry
    )
    assert ColumnarGenericConstraintPlanner.BoundSatisfiesInterfaceConstraint(
        implementer.Builder,
        target.Builder,
        registry
    )

    assert ColumnarGenericConstraintPlanner.InterfaceEqualsOrExtends(
        derived,
        target.Builder
    )
    unrelated := SourceCallInterfaceDefinition("SiblingConstraintUnrelated")
    assert !ColumnarGenericConstraintPlanner.InterfaceEqualsOrExtends(
        derived,
        unrelated.Builder
    )

    row := SiblingConstraintOneInterfaceRow(target.Builder)
    assert ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(
        new Type[](0),
        new int[](1),
        new Type[](1),
        row,
        new Type[](0),
        SiblingConstraintOneType(implementer.Builder),
        registry
    )
}

test "generic sibling interface closure disposes its live enumeration on early success and on later traversal failure" {
    target := SourceCallInterfaceDefinition("SiblingConstraintTraversalTarget")
    matching := SourceCallInterfaceDefinition("SiblingConstraintTraversalMatching")
    matching.InterfaceBases.Add(target)
    later := SourceCallInterfaceDefinition("SiblingConstraintTraversalLater")

    hitSequence := SourceDiscoveryTimingRows(matching, later)
    hitEnumerator := hitSequence.GetEnumerator()
    hitRows := SourceDiscoveryTimingWrapRows(hitEnumerator, "SiblingConstraintTraversalHit")
    hitOutcome := new SiblingConstraintAnyOutcome()
    assert SiblingConstraintInvokeAny(hitRows, target.Builder, hitOutcome)
    assert hitOutcome.Result
    assert hitOutcome.ErrorMessage == null
    hitEnumeratorObject: object = hitEnumerator
    assert SourceDiscoveryTimingIteratorState(hitEnumeratorObject) == -2

    absent := SourceCallInterfaceDefinition("SiblingConstraintTraversalAbsent")
    throwingSequence := SourceDiscoveryTimingThrowAfter(matching)
    throwingEnumerator := throwingSequence.GetEnumerator()
    throwingRows := SourceDiscoveryTimingWrapRows(
        throwingEnumerator,
        "SiblingConstraintTraversalThrow"
    )
    throwingOutcome := new SiblingConstraintAnyOutcome()
    assert SiblingConstraintInvokeAny(throwingRows, absent.Builder, throwingOutcome)
    assert !throwingOutcome.Result
    assert throwingOutcome.ErrorMessage == "source definition enumeration failed"
    throwingEnumeratorObject: object = throwingEnumerator
    assert SourceDiscoveryTimingIteratorState(throwingEnumeratorObject) == -2
}
