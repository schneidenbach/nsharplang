namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler.Columnar

class GenericConstraintApplicationFixture {
    Owner: TypeBuilder
    TypeParams: Type[]
    Builders: GenericTypeParameterBuilder[]
    TypeParamMap: Dictionary<string, Type>
    Resolution: ColumnarSemanticTypeResolution

    constructor(name: string, parameterCount: int) {
        Owner = TypeOfCreateBuilder(
            name,
            "ColumnarGenericConstraintApplication." + name,
            parameterCount
        )
        TypeParams = Owner.GetGenericArguments()
        if TypeParams.Length != parameterCount {
            throw new InvalidOperationException("The generic-constraint fixture did not define every requested parameter.")
        }

        Builders = new GenericTypeParameterBuilder[](TypeParams.Length)
        TypeParamMap = new Dictionary<string, Type>(StringComparer.Ordinal)
        parameterNames := new string[](TypeParams.Length)
        index := 0
        while index < TypeParams.Length {
            builder := TypeParams[index] as GenericTypeParameterBuilder
            if builder == null {
                throw new InvalidOperationException("The generic-constraint fixture did not expose a GenericTypeParameterBuilder.")
            }
            Builders[index] = builder
            parameterName := TypeParams[index].get_Name()
            parameterNames[index] = parameterName
            TypeParamMap[parameterName] = builder
            index = index + 1
        }
        Resolution = GenericConstraintApplicationResolution(TypeParamMap)
        Resolution.StructuralTypeReferences.RegisterTypeGenericParameters(
            0,
            "GenericConstraintApplication." + name,
            parameterNames,
            Owner
        )
    }
}

func GenericConstraintApplicationResolution(
    typeParams: Dictionary<string, Type>
): ColumnarSemanticTypeResolution {
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "import System\nfunc GenericConstraintApplicationAnchor(): int { return 0 }\n"
    fileNames[0] = "generic-constraint-application/control.nl"
    return SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        typeParams,
        ""
    )
}

class GenericConstraintApplicationOutcome {
    Result: bool
    Error: Exception?
    Specials: int[]?
    BaseConstraints: Type[]?
    InterfaceConstraints: Type[][]?

    constructor(
        specials: int[]?,
        baseConstraints: Type[]?,
        interfaceConstraints: Type[][]?
    ) {
        Result = false
        Error = null
        Specials = specials
        BaseConstraints = baseConstraints
        InterfaceConstraints = interfaceConstraints
    }
}

func GenericConstraintApplicationRun(
    gpBuilders: GenericTypeParameterBuilder[],
    specialRows: int[],
    typeConstraintRows: string[][],
    typeParamMap: Dictionary<string, Type>,
    ownerTypeParams: Type[],
    typeResolution: ColumnarSemanticTypeResolution,
    initialSpecials: int[]?,
    initialBaseConstraints: Type[]?,
    initialInterfaceConstraints: Type[][]?
): GenericConstraintApplicationOutcome {
    outcome := new GenericConstraintApplicationOutcome(
        initialSpecials,
        initialBaseConstraints,
        initialInterfaceConstraints
    )
    specials := initialSpecials
    baseConstraints := initialBaseConstraints
    interfaceConstraints := initialInterfaceConstraints
    try {
        outcome.Result = ColumnarGenericConstraintPlanner.TryApplyGenericParameterConstraints(
            gpBuilders,
            specialRows,
            typeConstraintRows,
            typeParamMap,
            ownerTypeParams,
            typeResolution,
            out specials,
            out baseConstraints,
            out interfaceConstraints
        )
    } catch error: Exception {
        outcome.Error = error
    }
    outcome.Specials = specials
    outcome.BaseConstraints = baseConstraints
    outcome.InterfaceConstraints = interfaceConstraints
    return outcome
}

func GenericConstraintApplicationRequiredSpecials(
    outcome: GenericConstraintApplicationOutcome
): int[] {
    result := outcome.Specials
    if result == null {
        throw new InvalidOperationException("The application outcome did not retain its special rows.")
    }
    return result
}

func GenericConstraintApplicationRequiredBases(
    outcome: GenericConstraintApplicationOutcome
): Type[] {
    result := outcome.BaseConstraints
    if result == null {
        throw new InvalidOperationException("The application outcome did not retain its base rows.")
    }
    return result
}

func GenericConstraintApplicationRequiredInterfaces(
    outcome: GenericConstraintApplicationOutcome
): Type[][] {
    result := outcome.InterfaceConstraints
    if result == null {
        throw new InvalidOperationException("The application outcome did not retain its interface rows.")
    }
    return result
}

func GenericConstraintApplicationEmptyTextRows(count: int): string[][] {
    rows := new string[][](count)
    index := 0
    while index < rows.Length {
        rows[index] = new string[](0)
        index = index + 1
    }
    return rows
}

func GenericConstraintApplicationAttributeBits(
    builder: GenericTypeParameterBuilder
): int {
    property := typeof(Type).GetProperty("GenericParameterAttributes")
    if property == null {
        throw new InvalidOperationException("Type.GenericParameterAttributes was not found.")
    }
    return Convert.ToInt32(property.GetValue(builder))
}

func GenericConstraintApplicationBakedParameterConstraints(
    fixture: GenericConstraintApplicationFixture,
    index: int
): Type[] {
    baked := IdentityBake(fixture.Owner)
    parameters := baked.GetGenericArguments()
    if index < 0 || index >= parameters.Length {
        throw new InvalidOperationException("The baked generic-constraint fixture did not retain its requested parameter.")
    }
    return parameters[index].GetGenericParameterConstraints()
}

func GenericConstraintApplicationRequire(
    condition: bool,
    message: string
) {
    if !condition {
        throw new InvalidOperationException(message)
    }
}

func GenericConstraintApplicationMapValue(
    map: IReadOnlyDictionary<Type, Type[]>,
    key: Type
): Type[] {
    value: Type[] = null
    if !map.TryGetValue(key, out value) {
        throw new InvalidOperationException("The generic-interface map did not contain its expected key.")
    }
    return value
}

func GenericConstraintApplicationMapHasKey(
    map: IReadOnlyDictionary<Type, Type[]>,
    key: Type
): bool {
    value: Type[] = null
    return map.TryGetValue(key, out value)
}

func GenericConstraintApplicationMapComparer(
    map: object
): object {
    property := map.GetType().GetProperty("Comparer")
    if property == null {
        throw new InvalidOperationException("Dictionary<Type, Type[]>.Comparer was not found.")
    }
    comparer := property.GetValue(map)
    if comparer == null {
        throw new InvalidOperationException("Dictionary<Type, Type[]>.Comparer returned null.")
    }
    return comparer
}

func GenericConstraintApplicationMapRuntimeType(
    map: object
): Type {
    return map.GetType()
}

func GenericConstraintApplicationMapCount(
    map: object
): int {
    property := map.GetType().GetProperty("Count")
    if property == null {
        throw new InvalidOperationException("Dictionary<Type, Type[]>.Count was not found.")
    }
    return Convert.ToInt32(property.GetValue(map))
}

func GenericConstraintApplicationDefaultTypeComparer(): object {
    property := typeof(EqualityComparer<Type>).GetProperty("Default")
    if property == null {
        throw new InvalidOperationException("EqualityComparer<Type>.Default was not found.")
    }
    comparer := property.GetValue(null)
    if comparer == null {
        throw new InvalidOperationException("EqualityComparer<Type>.Default returned null.")
    }
    return comparer
}

test "generic constraint application preserves the null pre-output boundary and the zero-owner shortcut" {
    sentinelSpecials := new int[](1)
    sentinelBases := new Type[](1)
    sentinelInterfaces := new Type[][](1)
    failed := GenericConstraintApplicationRun(
        null,
        null,
        null,
        null,
        null,
        null,
        sentinelSpecials,
        sentinelBases,
        sentinelInterfaces
    )
    nullError := failed.Error as NullReferenceException
    assert nullError != null
    assert Object.ReferenceEquals(failed.Specials, sentinelSpecials)
    assert Object.ReferenceEquals(failed.BaseConstraints, sentinelBases)
    assert Object.ReferenceEquals(failed.InterfaceConstraints, sentinelInterfaces)

    emptyBuilders := new GenericTypeParameterBuilder[](0)
    zero := GenericConstraintApplicationRun(
        emptyBuilders,
        null,
        null,
        null,
        null,
        null,
        sentinelSpecials,
        sentinelBases,
        sentinelInterfaces
    )
    assert zero.Result
    assert zero.Error == null
    zeroSpecials := GenericConstraintApplicationRequiredSpecials(zero)
    zeroBases := GenericConstraintApplicationRequiredBases(zero)
    zeroInterfaces := GenericConstraintApplicationRequiredInterfaces(zero)
    assert zeroSpecials.Length == 0
    assert zeroBases.Length == 0
    assert zeroInterfaces.Length == 0
    assert !Object.ReferenceEquals(zeroSpecials, sentinelSpecials)
    assert !Object.ReferenceEquals(zeroBases, sentinelBases)
    assert !Object.ReferenceEquals(zeroInterfaces, sentinelInterfaces)
    assert !Object.ReferenceEquals(zeroSpecials, zeroBases)
    assert !Object.ReferenceEquals(zeroSpecials, zeroInterfaces)
    assert !Object.ReferenceEquals(zeroBases, zeroInterfaces)
}

test "generic constraint application permits an inert null builder when no metadata write is reached" {
    builders := new GenericTypeParameterBuilder[](1)
    rows := GenericConstraintApplicationEmptyTextRows(1)
    outcome := GenericConstraintApplicationRun(
        builders,
        new int[](1),
        rows,
        null,
        null,
        null,
        null,
        null,
        null
    )
    assert outcome.Result
    assert outcome.Error == null
    specials := GenericConstraintApplicationRequiredSpecials(outcome)
    bases := GenericConstraintApplicationRequiredBases(outcome)
    interfaces := GenericConstraintApplicationRequiredInterfaces(outcome)
    assert specials.Length == 1
    assert specials[0] == 0
    assert bases.Length == 1
    assert bases[0] == null
    assert interfaces.Length == 1
    assert interfaces[0].Length == 0
}

test "generic constraint application writes attributes, one base, and two ordered interfaces into its output columns" {
    fixture := new GenericConstraintApplicationFixture("Happy", 3)
    specialRows := new int[](3)
    specialRows[0] = 5
    specialRows[1] = 2
    rows := GenericConstraintApplicationEmptyTextRows(3)
    rows[0] = new string[](2)
    rows[0][0] = "IDisposable"
    rows[0][1] = "IComparable"
    rows[2] = new string[](1)
    rows[2][0] = "object"

    outcome := GenericConstraintApplicationRun(
        fixture.Builders,
        specialRows,
        rows,
        fixture.TypeParamMap,
        fixture.TypeParams,
        fixture.Resolution,
        null,
        null,
        null
    )
    assert outcome.Result
    assert outcome.Error == null
    specials := GenericConstraintApplicationRequiredSpecials(outcome)
    bases := GenericConstraintApplicationRequiredBases(outcome)
    interfaces := GenericConstraintApplicationRequiredInterfaces(outcome)
    assert specials[0] == 5
    assert specials[1] == 2
    assert specials[2] == 0
    assert GenericConstraintApplicationAttributeBits(fixture.Builders[0]) == 20
    assert GenericConstraintApplicationAttributeBits(fixture.Builders[1]) == 24
    assert bases[0] == null
    assert bases[1] == null
    assert bases[2] == typeof(object)
    assert interfaces[0].Length == 2
    assert interfaces[0][0] == typeof(IDisposable)
    assert interfaces[0][1] == typeof(IComparable)
    assert interfaces[1].Length == 0
    assert interfaces[2].Length == 0
}

test "generic constraint application retains earlier mutations and output columns across decline and row failure" {
    unresolved := new GenericConstraintApplicationFixture("Unresolved", 1)
    unresolvedSpecials := new int[](1)
    unresolvedSpecials[0] = 1
    unresolvedRows := new string[][](1)
    unresolvedRows[0] = new string[](2)
    unresolvedRows[0][0] = "Exception"
    unresolvedRows[0][1] = "MissingGenericConstraintApplicationType"
    unresolvedOutcome := GenericConstraintApplicationRun(
        unresolved.Builders,
        unresolvedSpecials,
        unresolvedRows,
        unresolved.TypeParamMap,
        unresolved.TypeParams,
        unresolved.Resolution,
        null,
        null,
        null
    )
    assert !unresolvedOutcome.Result
    assert unresolvedOutcome.Error == null
    unresolvedOutputSpecials := GenericConstraintApplicationRequiredSpecials(unresolvedOutcome)
    unresolvedBases := GenericConstraintApplicationRequiredBases(unresolvedOutcome)
    unresolvedInterfaces := GenericConstraintApplicationRequiredInterfaces(unresolvedOutcome)
    assert unresolvedOutputSpecials[0] == 1
    assert GenericConstraintApplicationAttributeBits(unresolved.Builders[0]) == 4
    assert unresolvedBases[0] == typeof(Exception)
    assert unresolvedInterfaces[0] == null
    unresolvedMetadata := GenericConstraintApplicationBakedParameterConstraints(unresolved, 0)
    assert unresolvedMetadata.Length == 1
    assert unresolvedMetadata[0] == typeof(Exception)

    duplicate := new GenericConstraintApplicationFixture("DuplicateBase", 1)
    duplicateRows := new string[][](1)
    duplicateRows[0] = new string[](2)
    duplicateRows[0][0] = "Exception"
    duplicateRows[0][1] = "string"
    duplicateOutcome := GenericConstraintApplicationRun(
        duplicate.Builders,
        new int[](1),
        duplicateRows,
        duplicate.TypeParamMap,
        duplicate.TypeParams,
        duplicate.Resolution,
        null,
        null,
        null
    )
    assert !duplicateOutcome.Result
    assert duplicateOutcome.Error == null
    duplicateBases := GenericConstraintApplicationRequiredBases(duplicateOutcome)
    duplicateInterfaces := GenericConstraintApplicationRequiredInterfaces(duplicateOutcome)
    assert duplicateBases[0] == typeof(Exception)
    assert duplicateInterfaces[0] == null
    duplicateMetadata := GenericConstraintApplicationBakedParameterConstraints(duplicate, 0)
    assert duplicateMetadata.Length == 1
    assert duplicateMetadata[0] == typeof(Exception)

    nullRow := new GenericConstraintApplicationFixture("NullRow", 1)
    nullSpecials := new int[](1)
    nullSpecials[0] = 1
    nullRows := new string[][](1)
    nullOutcome := GenericConstraintApplicationRun(
        nullRow.Builders,
        nullSpecials,
        nullRows,
        nullRow.TypeParamMap,
        nullRow.TypeParams,
        nullRow.Resolution,
        null,
        null,
        null
    )
    nullRowError := nullOutcome.Error as NullReferenceException
    assert nullRowError != null
    nullOutputSpecials := GenericConstraintApplicationRequiredSpecials(nullOutcome)
    nullBases := GenericConstraintApplicationRequiredBases(nullOutcome)
    nullInterfaces := GenericConstraintApplicationRequiredInterfaces(nullOutcome)
    assert nullOutputSpecials[0] == 1
    assert GenericConstraintApplicationAttributeBits(nullRow.Builders[0]) == 4
    assert nullBases[0] == null
    assert nullInterfaces[0] == null
}

test "generic constraint application detects a cycle only after all base writes and output rows complete" {
    fixture := new GenericConstraintApplicationFixture("Cycle", 2)
    rows := new string[][](2)
    rows[0] = new string[](1)
    rows[0][0] = "T1"
    rows[1] = new string[](1)
    rows[1][0] = "T0"
    outcome := GenericConstraintApplicationRun(
        fixture.Builders,
        new int[](2),
        rows,
        fixture.TypeParamMap,
        fixture.TypeParams,
        fixture.Resolution,
        null,
        null,
        null
    )
    GenericConstraintApplicationRequire(!outcome.Result, "cycle return value")
    if outcome.Error != null {
        throw new InvalidOperationException("cycle application error: " + outcome.Error.Message)
    }
    bases := GenericConstraintApplicationRequiredBases(outcome)
    interfaces := GenericConstraintApplicationRequiredInterfaces(outcome)
    GenericConstraintApplicationRequire(
        Object.ReferenceEquals(bases[0], fixture.TypeParams[1]),
        "first cycle base output"
    )
    GenericConstraintApplicationRequire(
        Object.ReferenceEquals(bases[1], fixture.TypeParams[0]),
        "second cycle base output"
    )
    GenericConstraintApplicationRequire(
        Object.ReferenceEquals(fixture.Builders[0].get_BaseType(), fixture.TypeParams[1]),
        "first cycle pending base metadata"
    )
    GenericConstraintApplicationRequire(
        Object.ReferenceEquals(fixture.Builders[1].get_BaseType(), fixture.TypeParams[0]),
        "second cycle pending base metadata"
    )
    GenericConstraintApplicationRequire(interfaces[0].Length == 0, "first cycle interface output")
    GenericConstraintApplicationRequire(interfaces[1].Length == 0, "second cycle interface output")
}

test "generic constraint application observes a directly assigned pending CLR base constraint" {
    fixture := new GenericConstraintApplicationFixture("DirectPendingBase", 1)
    fixture.Builders[0].SetBaseTypeConstraint(typeof(Exception))
    GenericConstraintApplicationRequire(
        Object.ReferenceEquals(fixture.Builders[0].get_BaseType(), typeof(Exception)),
        "direct pending BaseType"
    )
}

test "declared-type constraint application retains its null shortcut and builder-map cast boundary" {
    assert ColumnarGenericConstraintPlanner.TryApplyDeclaredTypeConstraints(
        null,
        null,
        null,
        null,
        null
    )

    names := new string[](1)
    names[0] = "T0"
    castBoundaryFixture := new GenericConstraintApplicationFixture("CastBoundary", 1)
    castNames := new string[](2)
    castNames[0] = "T0"
    castNames[1] = "T1"
    wrongMap := new Dictionary<string, Type>(StringComparer.Ordinal)
    wrongMap["T0"] = castBoundaryFixture.Builders[0]
    wrongMap["T1"] = typeof(int)
    castSpecials := new int[](2)
    castSpecials[0] = 1
    assert throws InvalidCastException {
        ColumnarGenericConstraintPlanner.TryApplyDeclaredTypeConstraints(
            castNames,
            wrongMap,
            castSpecials,
            null,
            null
        )
    }
    assert GenericConstraintApplicationAttributeBits(castBoundaryFixture.Builders[0]) == 0

    fixture := new GenericConstraintApplicationFixture("Declared", 1)
    specials := new int[](1)
    specials[0] = 1
    rows := new string[][](1)
    rows[0] = new string[](1)
    rows[0][0] = "IDisposable"
    assert ColumnarGenericConstraintPlanner.TryApplyDeclaredTypeConstraints(
        names,
        fixture.TypeParamMap,
        specials,
        rows,
        fixture.Resolution
    )
    assert GenericConstraintApplicationAttributeBits(fixture.Builders[0]) == 4
}

test "generic-interface map preserves its caller empty instance and its short-circuit null boundary" {
    sharedEmpty := new Dictionary<Type, Type[]>()
    noTypeParams := new Type[](0)
    assert Object.ReferenceEquals(
        ColumnarGenericConstraintPlanner.BuildGenericInterfaceConstraintMap(
            noTypeParams,
            null,
            sharedEmpty
        ),
        sharedEmpty
    )

    nonemptyTypeParams := new Type[](1)
    nonemptyTypeParams[0] = typeof(int)
    assert throws NullReferenceException {
        ColumnarGenericConstraintPlanner.BuildGenericInterfaceConstraintMap(
            nonemptyTypeParams,
            null,
            sharedEmpty
        )
    }

    emptyRows := new Type[][](1)
    emptyRows[0] = new Type[](0)
    assert Object.ReferenceEquals(
        ColumnarGenericConstraintPlanner.BuildGenericInterfaceConstraintMap(
            nonemptyTypeParams,
            emptyRows,
            sharedEmpty
        ),
        sharedEmpty
    )
}

test "generic-interface map truncates only at the shorter outer array and skips empty rows before their keys" {
    sharedEmpty := new Dictionary<Type, Type[]>()
    typeParams := new Type[](3)
    typeParams[0] = typeof(string)
    typeParams[1] = typeof(int)
    typeParams[2] = typeof(DateTime)
    firstRow := new Type[](1)
    firstRow[0] = typeof(IDisposable)
    shortRows := new Type[][](1)
    shortRows[0] = firstRow
    truncated := ColumnarGenericConstraintPlanner.BuildGenericInterfaceConstraintMap(
        typeParams,
        shortRows,
        sharedEmpty
    )
    assert GenericConstraintApplicationMapRuntimeType(truncated) == typeof(Dictionary<Type, Type[]>)
    assert GenericConstraintApplicationMapCount(truncated) == 1
    assert Object.ReferenceEquals(
        GenericConstraintApplicationMapValue(truncated, typeParams[0]),
        firstRow
    )
    assert !GenericConstraintApplicationMapHasKey(truncated, typeParams[1])
    assert !GenericConstraintApplicationMapHasKey(truncated, typeParams[2])

    emptyThenValueParams := new Type[](2)
    emptyThenValueParams[0] = null
    emptyThenValueParams[1] = typeof(int)
    emptyThenValueRows := new Type[][](2)
    emptyThenValueRows[0] = new Type[](0)
    laterRow := new Type[](1)
    laterRow[0] = typeof(IComparable)
    emptyThenValueRows[1] = laterRow
    skipped := ColumnarGenericConstraintPlanner.BuildGenericInterfaceConstraintMap(
        emptyThenValueParams,
        emptyThenValueRows,
        sharedEmpty
    )
    assert GenericConstraintApplicationMapRuntimeType(skipped) == typeof(Dictionary<Type, Type[]>)
    assert GenericConstraintApplicationMapCount(skipped) == 1
    assert Object.ReferenceEquals(
        GenericConstraintApplicationMapValue(skipped, typeof(int)),
        laterRow
    )

    nullRowParams := new Type[](1)
    nullRowParams[0] = typeof(int)
    nullRows := new Type[][](1)
    assert throws NullReferenceException {
        ColumnarGenericConstraintPlanner.BuildGenericInterfaceConstraintMap(
            nullRowParams,
            nullRows,
            sharedEmpty
        )
    }
}

test "generic-interface map uses the default comparer, preserves rows, overwrites duplicates, and feeds both lookup routes" {
    sharedEmpty := new Dictionary<Type, Type[]>()
    first := new GenericConstraintApplicationFixture("MapFirst", 1)
    weakRequested := new GenericConstraintApplicationFixture("MapWeakRequested", 1)
    otherKey := typeof(DateTime)
    firstValue := new Type[](1)
    firstValue[0] = typeof(IDisposable)
    otherValue := new Type[](1)
    otherValue[0] = typeof(IComparable)
    overwritten := new Type[](1)
    overwritten[0] = typeof(ICloneable)
    typeParams := new Type[](3)
    typeParams[0] = first.TypeParams[0]
    typeParams[1] = otherKey
    typeParams[2] = first.TypeParams[0]
    rows := new Type[][](3)
    rows[0] = firstValue
    rows[1] = otherValue
    rows[2] = overwritten

    built := ColumnarGenericConstraintPlanner.BuildGenericInterfaceConstraintMap(
        typeParams,
        rows,
        sharedEmpty
    )
    assert GenericConstraintApplicationMapRuntimeType(built) == typeof(Dictionary<Type, Type[]>)
    assert GenericConstraintApplicationMapCount(built) == 2
    assert Object.ReferenceEquals(
        GenericConstraintApplicationMapComparer(built),
        GenericConstraintApplicationDefaultTypeComparer()
    )
    assert Object.ReferenceEquals(
        GenericConstraintApplicationMapValue(built, first.TypeParams[0]),
        overwritten
    )
    assert Object.ReferenceEquals(
        GenericConstraintApplicationMapValue(built, otherKey),
        otherValue
    )
    assert Object.ReferenceEquals(
        ColumnarGenericConstraintPlanner.ResolveCallConstraints(built, first.TypeParams[0]),
        overwritten
    )
    assert Object.ReferenceEquals(
        ColumnarGenericConstraintPlanner.ResolveCallConstraints(built, weakRequested.TypeParams[0]),
        overwritten
    )
}
